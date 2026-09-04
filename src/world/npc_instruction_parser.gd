extends RefCounted

## Parser for the NPC instruction DSL (docs/concept/npc_instructions.md): turns
## a player-written instruction script into the canonical AST -- plain Godot
## Dictionaries/Arrays -- that npc_instruction_cost.gd and
## npc_instruction_executor.gd will consume once they exist. Pure, no side
## effects, no engine dependency: same text -> data contract as
## spell_parser.gd, parsing only (no evaluation here).
##
## Unlike spell_parser.gd -- which is purely structural and defers atom
## legality to a separate validator, because its surface syntax names its own
## params (`fire_damage(magnitude: 8)`) -- this grammar's args are
## positional (`inventory_at_least(wood, 20)`), and the concept doc's AST
## contract wants them turned into *named* args
## (`{"item": "wood", "count": 20}`). That conversion is only possible if the
## parser knows each primitive's own signature, so for these 4 v1 primitives
## that signature table lives here rather than in a separate catalog module.
## An unknown primitive name, a condition/action used in the wrong slot, a
## wrong arg count, a wrong arg type, or an empty script all fail closed with
## a "line N: ..." error -- never a crash, never silently accepted.
##
## Surface syntax:
##   instruct "haul_and_forage" {
##       if inventory_at_least(wood, 20): haul(wood, base)
##       if need_above(hunger, 0.7): gather(berries)
##       otherwise: gather(wood)
##   }
##
## parse() returns {ok: bool, ast: Dictionary, errors: Array[String]}.

## {fn_name -> {kind: "condition"|"action", params: [{name, type}, ...]}}.
## type is "ident" (a bareword, stored as String) or "number" (int/float).
const _PRIMITIVES := {
	"inventory_at_least": {"kind": "condition", "params": [
		{"name": "item", "type": "ident"},
		{"name": "count", "type": "number"},
	]},
	"need_above": {"kind": "condition", "params": [
		{"name": "need", "type": "ident"},
		{"name": "threshold", "type": "number"},
	]},
	"haul": {"kind": "action", "params": [
		{"name": "item", "type": "ident"},
		{"name": "destination_tag", "type": "ident"},
	]},
	"gather": {"kind": "action", "params": [
		{"name": "resource_tag", "type": "ident"},
	]},
}

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
	var ast := _parse_instruct()
	if _failed or _errors.size() > 0:
		return {"ok": false, "ast": {}, "errors": _errors}
	return {"ok": true, "ast": ast, "errors": _errors}


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


# --- grammar ----------------------------------------------------------------------

func _parse_instruct() -> Dictionary:
	_expect("ident", "instruct", "expected 'instruct' to start the script")
	var name_token := _expect("string", null, "expected a quoted name after 'instruct'")
	_expect("punct", "{", "expected '{' to open the instruction body")
	var rules: Array = []
	while not _failed and not _check("punct", "}") and not _check("eof"):
		rules.append(_parse_rule())
	_expect("punct", "}", "expected '}' to close the instruction body")
	if not _failed and rules.size() == 0:
		_fail("an instruction script must have at least one rule")
	if not _failed:
		_check_otherwise_placement(rules)
	return {"kind": "instruct", "name": name_token["value"], "rules": rules}


## "otherwise" is the catch-all and, per the spec, must be last if present --
## and there can only be one.
func _check_otherwise_placement(rules: Array) -> void:
	for i in rules.size():
		var rule: Dictionary = rules[i]
		if rule["condition"] == null and i != rules.size() - 1:
			_fail("'otherwise' must be the last rule in the script")
			return


func _parse_rule() -> Dictionary:
	if _match("ident", "otherwise"):
		_expect("punct", ":", "expected ':' after 'otherwise'")
		var action := _parse_call("action")
		return {"condition": null, "action": action}
	_expect("ident", "if", "expected 'if' or 'otherwise' to start a rule")
	var condition := _parse_call("condition")
	_expect("punct", ":", "expected ':' after the condition")
	var action := _parse_call("action")
	return {"condition": condition, "action": action}


## Parses `name(arg, arg, ...)`, validating the primitive exists, is the
## expected kind (condition vs. action), and takes the right argument count
## and types -- then returns {"fn": name, "args": {named_arg -> value}}.
func _parse_call(expected_kind: String) -> Dictionary:
	var name_token := _expect("ident", null, "expected a %s" % expected_kind)
	if _failed:
		return {}
	var fn_name: String = String(name_token["value"])
	if not _PRIMITIVES.has(fn_name):
		_fail("unknown primitive '%s'" % fn_name)
		return {}
	var sig: Dictionary = _PRIMITIVES[fn_name]
	if sig["kind"] != expected_kind:
		_fail("wrong primitive kind for '%s': found a %s, expected a %s" % [fn_name, sig["kind"], expected_kind])
		return {}
	_expect("punct", "(", "expected '(' after '%s'" % fn_name)
	if _failed:
		return {}
	var arg_tokens: Array = _parse_args()
	if _failed:
		return {}
	_expect("punct", ")", "expected ')' to close '%s'" % fn_name)
	if _failed:
		return {}
	var params: Array = sig["params"]
	if arg_tokens.size() != params.size():
		_fail("'%s' expects %d argument(s), got %d" % [fn_name, params.size(), arg_tokens.size()])
		return {}
	var args := {}
	for i in params.size():
		var param: Dictionary = params[i]
		var token: Dictionary = arg_tokens[i]
		if param["type"] == "number":
			if token["type"] != "number":
				_fail("argument '%s' of '%s' must be a number" % [param["name"], fn_name])
				return {}
			args[param["name"]] = token["value"]
		else:
			if token["type"] != "ident":
				_fail("argument '%s' of '%s' must be a name" % [param["name"], fn_name])
				return {}
			args[param["name"]] = String(token["value"])
	return {"fn": fn_name, "args": args}


func _parse_args() -> Array:
	var tokens: Array = []
	if _check("punct", ")"):
		return tokens
	while not _failed:
		var token := _peek()
		if token["type"] == "number" or token["type"] == "ident":
			tokens.append(token)
			_advance()
		else:
			_fail("expected a name or number argument")
			return tokens
		if not _match("punct", ","):
			break
	return tokens
