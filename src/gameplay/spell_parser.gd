extends RefCounted

## The magic DSL parser (docs/concept/magic.md): turns player-written spell text
## into the canonical AST -- plain Godot Dictionaries/Arrays -- that spell_cost,
## the validator, and the runtime all consume. Pure, no side effects, in the
## spirit of console_command_parser.gd but recursive (a small lexer + a
## recursive-descent parser).
##
## Deliberately PURELY structural: it knows the grammar, not the game. It does
## not check whether an atom exists, whether params are legal, or whether the
## caster has unlocked anything -- those are the validator's job. That keeps the
## language's surface decoupled from the atom catalog, so an unknown atom parses
## fine and is rejected one layer up.
##
## Surface syntax (pipeline + blocks):
##   enchant "Flame Brand" {
##     on hit when wielder.mana >= @cost:
##       fire_damage(magnitude: 8) |> ignite(duration: 3, spread: true)
##   }
##
## parse() returns {ok: bool, ast: Dictionary, errors: Array[String]}. Player
## input is fallible, so malformed text yields ok:false with human-readable
## "line N: ..." errors rather than crashing.

const _BLOCK_KINDS := ["spell", "enchant", "instruct"]
const _COMPARISONS := [">=", "<=", ">", "<", "==", "!="]

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
		# Lexical errors -- don't attempt to parse a broken token stream.
		return {"ok": false, "ast": {}, "errors": _errors}
	var ast := _parse_block()
	if _failed or _errors.size() > 0:
		return {"ok": false, "ast": {}, "errors": _errors}
	return {"ok": true, "ast": ast, "errors": _errors}


# --- lexer ------------------------------------------------------------------

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
		elif c == "|":
			if i + 1 < n and source[i + 1] == ">":
				tokens.append({"type": "op", "value": "|>", "line": line})
				i += 2
			else:
				_errors.append("line %d: unexpected '|' (did you mean '|>'?)" % line)
				i += 1
		elif c == ">" or c == "<":
			if i + 1 < n and source[i + 1] == "=":
				tokens.append({"type": "op", "value": c + "=", "line": line})
				i += 2
			else:
				tokens.append({"type": "op", "value": c, "line": line})
				i += 1
		elif c == "=":
			if i + 1 < n and source[i + 1] == "=":
				tokens.append({"type": "op", "value": "==", "line": line})
				i += 2
			else:
				_errors.append("line %d: expected '==' (a single '=' is not an operator)" % line)
				i += 1
		elif c == "!":
			if i + 1 < n and source[i + 1] == "=":
				tokens.append({"type": "op", "value": "!=", "line": line})
				i += 2
			else:
				_errors.append("line %d: unexpected '!' (did you mean '!='?)" % line)
				i += 1
		elif c == "{" or c == "}" or c == "(" or c == ")" or c == ":" or c == "," or c == "." or c == "@":
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


# --- token cursor -----------------------------------------------------------

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


## Consume a token of the expected type/value, or record the first parse error.
func _expect(type: String, value: Variant, message: String) -> Dictionary:
	if _check(type, value):
		return _advance()
	_fail(message)
	return {"type": "error", "value": "", "line": _peek()["line"]}


## Record the first parse error and stop. Later calls short-circuit so one
## mistake yields one clear message, not a cascade.
func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_errors.append("line %d: %s" % [_peek()["line"], message])


# --- grammar ----------------------------------------------------------------

func _parse_block() -> Dictionary:
	var kind_token := _peek()
	if not (_check("ident") and _BLOCK_KINDS.has(kind_token["value"])):
		_fail("expected 'spell', 'enchant', or 'instruct'")
		return {}
	_advance()
	var name_token := _expect("string", null, "expected a quoted name after '%s'" % kind_token["value"])
	_expect("punct", "{", "expected '{' to open the block")
	var rules: Array = []
	while not _failed and not _check("punct", "}") and not _check("eof"):
		rules.append(_parse_rule())
	_expect("punct", "}", "expected '}' to close the block")
	return {"kind": kind_token["value"], "name": name_token["value"], "rules": rules}


func _parse_rule() -> Dictionary:
	_expect("ident", "on", "expected 'on' to start a rule")
	var event_token := _expect("ident", null, "expected an event name after 'on'")
	var event_arg: Variant = null
	if _match("punct", "("):
		var arg := _peek()
		if arg["type"] == "number" or arg["type"] == "ident":
			event_arg = arg["value"]
			_advance()
		else:
			_fail("expected a name or number as the event argument")
		_expect("punct", ")", "expected ')' after the event argument")
	var guard: Variant = null
	if _check("ident", "when"):
		_advance()
		guard = _parse_guard()
	_expect("punct", ":", "expected ':' before the effect pipeline")
	var pipeline := _parse_pipeline()
	return {"event": event_token["value"], "event_arg": event_arg, "guard": guard, "pipeline": pipeline}


func _parse_guard() -> Dictionary:
	var lhs: Variant = _parse_operand()
	var op_token := _peek()
	if op_token["type"] != "op" or not _COMPARISONS.has(op_token["value"]):
		_fail("expected a comparison operator (>=, <=, >, <, ==, !=) in the guard")
		return {}
	_advance()
	var rhs: Variant = _parse_operand()
	return {"op": op_token["value"], "lhs": lhs, "rhs": rhs}


## An operand is a number literal, an @-reference (e.g. @cost), or a dotted path
## (e.g. wielder.mana). Paths and @-refs are returned as strings; numbers as
## their numeric value.
func _parse_operand() -> Variant:
	var token := _peek()
	if token["type"] == "number":
		_advance()
		return token["value"]
	if _match("punct", "@"):
		var ref := _expect("ident", null, "expected a name after '@'")
		return "@" + String(ref["value"])
	if token["type"] == "ident":
		var path := String(token["value"])
		_advance()
		while _match("punct", "."):
			var segment := _expect("ident", null, "expected a name after '.'")
			path += "." + String(segment["value"])
		return path
	_fail("expected an operand (a path, number, or @reference)")
	return ""


func _parse_pipeline() -> Array:
	var steps: Array = []
	if _failed:
		return steps
	steps.append(_parse_step())
	while not _failed and _match("op", "|>"):
		steps.append(_parse_step())
	return steps


func _parse_step() -> Dictionary:
	var name_token := _expect("ident", null, "expected an effect atom")
	var params := {}
	if _match("punct", "("):
		params = _parse_params()
		_expect("punct", ")", "expected ')' to close the atom's parameters")
	return {"atom": String(name_token["value"]), "params": params}


func _parse_params() -> Dictionary:
	var params := {}
	if _check("punct", ")"):
		return params
	while not _failed:
		var key := _expect("ident", null, "expected a parameter name")
		_expect("punct", ":", "expected ':' after parameter name '%s'" % key["value"])
		var value: Variant = _parse_value()
		params[String(key["value"])] = value
		if not _match("punct", ","):
			break
	return params


func _parse_value() -> Variant:
	var token := _peek()
	if token["type"] == "number":
		_advance()
		return token["value"]
	if token["type"] == "string":
		_advance()
		return token["value"]
	if token["type"] == "ident":
		_advance()
		if token["value"] == "true":
			return true
		if token["value"] == "false":
			return false
		return String(token["value"])
	_fail("expected a value (number, string, true/false, or a name)")
	return null
