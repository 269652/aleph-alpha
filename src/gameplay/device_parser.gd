extends RefCounted

## The `device` DSL parser (docs/concept/standard_model.md, "The DSL"): turns
## a device's authored text into the canonical AST -- plain Godot
## Dictionaries/Arrays -- that device_compiler.gd, device_network.gd and
## device_executor.gd consume.
##
## A fourth structural sibling of spell_parser.gd, capture_parser.gd and
## npc_instruction_parser.gd: same tokenizer, same `on EVENT(ARG) when GUARD:
## pipeline` rule shape, same recursive-descent approach, deliberately NOT a
## subclass of any of them or a shared parser -- devices are their own domain
## with their own clauses, exactly the way capture is its own domain with its
## own one block kind.
##
## What is new is everything in front of the rules: four declarative clauses.
##
##   part ID: MATERIAL GEOMETRY ROLE (dims...)        -> an ItemPart
##   joint ID: A to B TYPE FASTENING MATERIAL (axis: z) -> a PartJoint
##   law ID: ELEMENT(params...)                        -> a physics element
##   loop A |> B |> C                                  -> the energy path
##
## Deliberately PURELY structural, exactly like its siblings: it knows the
## grammar, not the game. It does not check whether a material, geometry,
## role, element kind or atom exists, whether a dimension is missing, or
## whether the loop's domains agree -- that is device_compiler.gd's job. An
## unknown anything parses fine and is rejected, with a reason, one layer up.
##
## Surface syntax:
##   device "Mill Race Light" {
##     part wheel: wood face working (width_cm: 200, height_cm: 200, thickness_cm: 4)
##     part axle: iron haft structure (length_cm: 60, diameter_cm: 4)
##     joint hub: wheel to axle rigid fit iron
##     law river: source(domain: translation, fluid: water, area_m2: 0.5, velocity: 1.5)
##     law wheel: transform(in: translation, out: rotation, part: wheel)
##     loop river |> wheel
##     on step when wheel.power >= 1: turn(target: wheel)
##   }
##
## parse() returns {ok: bool, ast: Dictionary, errors: Array[String]}. Device
## text is authored (and, per the concept doc, may one day be player-authored)
## and therefore fallible, so malformed text yields ok:false with
## human-readable "line N: ..." errors rather than crashing.

const _BLOCK_KINDS := ["device"]
const _CLAUSE_KEYWORDS := ["part", "joint", "law", "loop", "on"]
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


# --- token cursor -------------------------------------------------------------

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


# --- grammar ------------------------------------------------------------------

func _parse_block() -> Dictionary:
	var kind_token := _peek()
	if not (_check("ident") and _BLOCK_KINDS.has(kind_token["value"])):
		_fail("expected 'device'")
		return {}
	_advance()
	var name_token := _expect("string", null, "expected a quoted name after '%s'" % kind_token["value"])
	_expect("punct", "{", "expected '{' to open the block")
	var ast := {
		"kind": kind_token["value"],
		"name": name_token["value"],
		"parts": [],
		"joints": [],
		"laws": [],
		"loops": [],
		"rules": [],
	}
	while not _failed and not _check("punct", "}") and not _check("eof"):
		_parse_clause(ast)
	_expect("punct", "}", "expected '}' to close the block")
	return ast


## One clause, dispatched on its keyword, appended to the list it belongs to
## so every list keeps source order within itself.
func _parse_clause(ast: Dictionary) -> void:
	var keyword := _peek()
	if keyword["type"] != "ident" or not _CLAUSE_KEYWORDS.has(keyword["value"]):
		_fail("expected a clause (part, joint, law, loop, or on), got '%s'" % keyword["value"])
		return
	match keyword["value"]:
		"part":
			ast["parts"].append(_parse_part())
		"joint":
			ast["joints"].append(_parse_joint())
		"law":
			ast["laws"].append(_parse_law())
		"loop":
			ast["loops"].append(_parse_loop())
		"on":
			ast["rules"].append(_parse_rule())


## part ID: MATERIAL GEOMETRY ROLE [(dims)]
func _parse_part() -> Dictionary:
	_expect("ident", "part", "expected 'part'")
	var id := _expect("ident", null, "expected a part id after 'part'")
	_expect("punct", ":", "expected ':' after the part id")
	var material := _expect("ident", null, "expected a material after ':'")
	var geometry := _expect("ident", null, "expected a geometry after the material")
	var role := _expect("ident", null, "expected a role after the geometry")
	var dimensions := {}
	if _match("punct", "("):
		dimensions = _parse_params()
		_expect("punct", ")", "expected ')' to close the part's dimensions")
	return {
		"id": String(id["value"]),
		"material": String(material["value"]),
		"geometry": String(geometry["value"]),
		"role": String(role["value"]),
		"dimensions": dimensions,
	}


## joint ID: A to B TYPE FASTENING MATERIAL [(params)]
func _parse_joint() -> Dictionary:
	_expect("ident", "joint", "expected 'joint'")
	var id := _expect("ident", null, "expected a joint id after 'joint'")
	_expect("punct", ":", "expected ':' after the joint id")
	var part_a := _expect("ident", null, "expected the first member after ':'")
	_expect("ident", "to", "expected 'to' between the joint's two members")
	var part_b := _expect("ident", null, "expected the second member after 'to'")
	var type := _expect("ident", null, "expected a joint type after the members")
	var fastening := _expect("ident", null, "expected a fastening after the joint type")
	var material := _expect("ident", null, "expected the joint's material after the fastening")
	var params := {}
	if _match("punct", "("):
		params = _parse_params()
		_expect("punct", ")", "expected ')' to close the joint's parameters")
	return {
		"id": String(id["value"]),
		"part_a": String(part_a["value"]),
		"part_b": String(part_b["value"]),
		"type": String(type["value"]),
		"fastening": String(fastening["value"]),
		"material": String(material["value"]),
		"params": params,
	}


## law ID: ELEMENT [(params)]
func _parse_law() -> Dictionary:
	_expect("ident", "law", "expected 'law'")
	var id := _expect("ident", null, "expected an element id after 'law'")
	_expect("punct", ":", "expected ':' after the law's id")
	var element := _expect("ident", null, "expected an element kind after ':'")
	var params := {}
	if _match("punct", "("):
		params = _parse_params()
		_expect("punct", ")", "expected ')' to close the law's parameters")
	return {"id": String(id["value"]), "element": String(element["value"]), "params": params}


## loop A |> B |> C -- bare element ids only; a loop step carries no
## parameters, because the physics is on the law, not on the path.
func _parse_loop() -> Array:
	_expect("ident", "loop", "expected 'loop'")
	var chain: Array = []
	chain.append(String(_expect("ident", null, "expected an element id after 'loop'")["value"]))
	while not _failed and _match("op", "|>"):
		chain.append(String(_expect("ident", null, "expected an element id after '|>'")["value"]))
	if not _failed and _check("punct", "("):
		_fail("a loop step names an element and carries no parameters (put them on its law)")
	return chain


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


## An operand is a number literal, a string literal, an @-reference (e.g.
## @mass_kg), or a dotted path (e.g. wire.power). Strings/paths/@-refs are
## returned as plain strings; numbers as their numeric value.
func _parse_operand() -> Variant:
	var token := _peek()
	if token["type"] == "number":
		_advance()
		return token["value"]
	if token["type"] == "string":
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
	_fail("expected an operand (a path, string, number, or @reference)")
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
