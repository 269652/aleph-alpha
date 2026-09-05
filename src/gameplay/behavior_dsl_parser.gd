extends RefCounted

## Parser for the behavior DSL (docs/concept/behavior_dsl.md): turns an
## authored behavior script into the canonical AST -- plain Godot
## Dictionaries/Arrays -- that behavior_atom_catalog.gd and
## behavior_tree_executor.gd consume. Pure, no side effects, parsing only.
##
## Purely structural, exactly spell_parser.gd's own pillar: this knows the
## grammar, not the atoms. An unknown atom name, or an atom used as a
## condition when it is really an action, parses fine -- that is the
## executor/catalog's job to reject, one layer up. Named args only
## (`on: predator`), never positional, so unlike npc_instruction_parser.gd
## this needs no per-atom signature table converting one shape into the
## other: the surface syntax already matches the AST it produces.
##
## Surface syntax:
##   behavior "mammal" {
##       priority {
##           flee(on: predator, on: player)
##           gate(above(need: hunger, threshold: 0.5)) {
##               seek(on: forage)
##           }
##           wander()
##       }
##   }
##
## A file is zero or more `behavior "name" { <node> }` blocks. A node is
## priority/sequence/parallel (a block of child nodes), gate (a condition
## call plus exactly one child node), or a leaf (an atom call). Repeated
## `key: value` pairs on one call accumulate into a list, in written order;
## a single occurrence stays a scalar (docs/concept/behavior_dsl.md §1) --
## what lets flee/seek take one or several channels with no separate
## list-literal syntax.
##
## parse(source) returns {"ok": bool, "behaviors": {name: <node>},
## "errors": Array[String]}. Fail-closed: an unknown top-level keyword, an
## unclosed brace/string, a malformed gate, or a bare identifier where a
## call belongs all fail with "line N: ..." -- never a crash, never a
## silent partial parse (a failed parse reports zero behaviors, not
## whatever happened to parse before the error).

## The four reserved composition keywords. Anything else starting a node
## is read as a leaf atom call -- the parser does not know atom names (see
## the class doc comment), only these four structural words.
const _COMPOSITION_KEYWORDS := ["priority", "sequence", "parallel"]
const _GATE_KEYWORD := "gate"

var _tokens: Array = []
var _pos: int = 0
var _errors: Array = []
var _failed: bool = false


func parse(source: String) -> Dictionary:
	_errors = []
	_failed = false
	_pos = 0
	_tokens = _tokenize(source)
	if _errors.size() > 0:
		return {"ok": false, "behaviors": {}, "errors": _errors}
	var behaviors := _parse_file()
	if _failed or _errors.size() > 0:
		return {"ok": false, "behaviors": {}, "errors": _errors}
	return {"ok": true, "behaviors": behaviors, "errors": _errors}


# --- lexer --------------------------------------------------------------------

func _tokenize(source: String) -> Array:
	var tokens: Array = []
	var i := 0
	var line := 1
	var n := source.length()
	while i < n:
		var c := source[i]
		if c == "\n":
			line += 1
			i += 1
		elif c == " " or c == "\t" or c == "\r":
			i += 1
		elif c == "#":
			while i < n and source[i] != "\n":
				i += 1
		elif c == "\"":
			var start_line := line
			i += 1
			var text := ""
			var closed := false
			while i < n:
				if source[i] == "\"":
					closed = true
					i += 1
					break
				if source[i] == "\n":
					line += 1
				text += source[i]
				i += 1
			if not closed:
				_errors.append("line %d: unterminated string" % start_line)
			tokens.append({"type": "string", "value": text, "line": start_line})
		elif _is_digit(c):
			var start := i
			var has_dot := false
			while i < n and (_is_digit(source[i]) or source[i] == "."):
				if source[i] == ".":
					if has_dot:
						break
					has_dot = true
				i += 1
			var num_text := source.substr(start, i - start)
			var num_value: Variant = float(num_text) if has_dot else int(num_text)
			tokens.append({"type": "number", "value": num_value, "line": line})
		elif _is_alpha(c):
			var start := i
			while i < n and _is_alnum(source[i]):
				i += 1
			tokens.append({"type": "ident", "value": source.substr(start, i - start), "line": line})
		elif c == "{" or c == "}" or c == "(" or c == ")" or c == ":" or c == ",":
			tokens.append({"type": "punct", "value": c, "line": line})
			i += 1
		else:
			_errors.append("line %d: unexpected character '%s'" % [line, c])
			i += 1
	tokens.append({"type": "eof", "value": "", "line": line})
	return tokens


func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


func _is_alpha(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


func _is_alnum(c: String) -> bool:
	return _is_digit(c) or _is_alpha(c)


# --- token cursor ---------------------------------------------------------------

func _peek() -> Dictionary:
	return _tokens[mini(_pos, _tokens.size() - 1)]


func _advance() -> Dictionary:
	var token := _peek()
	if _pos < _tokens.size():
		_pos += 1
	return token


func _check(type: String, value: Variant = null) -> bool:
	var token := _peek()
	if token["type"] != type:
		return false
	return value == null or token["value"] == value


func _match(type: String, value: Variant = null) -> bool:
	if _check(type, value):
		_advance()
		return true
	return false


func _expect(type: String, value: Variant, message: String) -> Dictionary:
	if _check(type, value):
		return _advance()
	_fail(message)
	return {"type": "error", "value": "", "line": _peek()["line"]}


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_errors.append("line %d: %s" % [_peek()["line"], message])


# --- grammar --------------------------------------------------------------------

func _parse_file() -> Dictionary:
	var behaviors := {}
	while not _check("eof") and not _failed:
		var entry := _parse_behavior_block()
		if _failed:
			break
		behaviors[entry["name"]] = entry["root"]
	return behaviors


func _parse_behavior_block() -> Dictionary:
	_expect("ident", "behavior", "expected 'behavior'")
	if _failed:
		return {}
	var name_token := _expect("string", null, "a behavior's name must be a string")
	if _failed:
		return {}
	_expect("punct", "{", "expected '{' after the behavior name")
	if _failed:
		return {}
	var root := _parse_node()
	if _failed:
		return {}
	_expect("punct", "}", "expected '}' to close the behavior block")
	if _failed:
		return {}
	return {"name": name_token["value"], "root": root}


## One node: a composition block (priority/sequence/parallel), a gate, or a
## leaf call -- decided purely by which reserved keyword (if any) starts it.
func _parse_node() -> Dictionary:
	if _check("ident") and _COMPOSITION_KEYWORDS.has(_peek()["value"]):
		return _parse_composition_block()
	if _check("ident") and _peek()["value"] == _GATE_KEYWORD:
		return _parse_gate()
	return _parse_leaf()


func _parse_composition_block() -> Dictionary:
	var kind: String = _advance()["value"]
	_expect("punct", "{", "expected '{' after '%s'" % kind)
	if _failed:
		return {}
	var children: Array = []
	while not _check("punct", "}") and not _check("eof") and not _failed:
		children.append(_parse_node())
	_expect("punct", "}", "expected '}' to close '%s'" % kind)
	if _failed:
		return {}
	return {"kind": kind, "children": children}


## gate(CONDITION) { CHILD } -- the condition is exactly one call (never a
## composition block, never a bare identifier), and the child is exactly
## one ordinary node.
func _parse_gate() -> Dictionary:
	_advance()  # "gate"
	_expect("punct", "(", "expected '(' after 'gate'")
	if _failed:
		return {}
	if not _check("ident"):
		_fail("gate's condition must be a call, e.g. above(need: hunger, threshold: 0.5)")
		return {}
	var condition := _parse_call()
	if _failed:
		return {}
	_expect("punct", ")", "expected ')' after the gate's condition")
	if _failed:
		return {}
	_expect("punct", "{", "expected '{' after 'gate(...)'")
	if _failed:
		return {}
	var child := _parse_node()
	if _failed:
		return {}
	_expect("punct", "}", "expected '}' to close the gate")
	if _failed:
		return {}
	return {"kind": "gate", "condition": condition, "child": child}


func _parse_leaf() -> Dictionary:
	if not _check("ident"):
		_fail("expected a behavior node: 'priority', 'sequence', 'parallel', 'gate', or an atom call")
		return {}
	var call := _parse_call()
	if _failed:
		return {}
	return {"kind": "leaf", "atom": call["name"], "args": call["args"]}


## IDENT "(" (IDENT ":" value ("," IDENT ":" value)*)? ")" -- shared by a
## leaf and by a gate's condition. A repeated key accumulates into a list
## in written order; a single occurrence stays a scalar.
func _parse_call() -> Dictionary:
	var name_token := _expect("ident", null, "expected a name")
	if _failed:
		return {}
	var name: String = name_token["value"]
	_expect("punct", "(", "expected '(' after '%s'" % name)
	if _failed:
		return {}
	var args := {}
	if not _check("punct", ")"):
		while true:
			var key_token := _expect("ident", null, "expected an argument name")
			if _failed:
				return {}
			_expect("punct", ":", "expected ':' after the argument name")
			if _failed:
				return {}
			var value: Variant = _parse_value()
			if _failed:
				return {}
			_accumulate_arg(args, key_token["value"], value)
			if not _match("punct", ","):
				break
			if _check("punct", ")"):
				_fail("expected another argument after ',' (trailing commas are not allowed)")
				return {}
	_expect("punct", ")", "expected ')' to close '%s(...)'" % name)
	if _failed:
		return {}
	return {"name": name, "args": args}


func _accumulate_arg(args: Dictionary, key: String, value: Variant) -> void:
	if not args.has(key):
		args[key] = value
		return
	if args[key] is Array:
		args[key].append(value)
	else:
		args[key] = [args[key], value]


func _parse_value() -> Variant:
	if _check("ident", "true"):
		_advance()
		return true
	if _check("ident", "false"):
		_advance()
		return false
	if _check("ident"):
		return _advance()["value"]
	if _check("string"):
		return _advance()["value"]
	if _check("number"):
		return _advance()["value"]
	_fail("expected a value: an identifier, a string, a number, or true/false")
	return null
