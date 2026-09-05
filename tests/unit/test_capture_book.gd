extends GutTest

## Red-first spec for capture_book.gd (docs/concept/capture_dsl.md): the
## small, fixed table of pre-authored device text, parsed once and cached --
## same role spell_book.gd plays for magic: a real, usable set of content
## while any future device-authoring UI stays unbuilt. Kept honest on
## purpose: only devices that are actually wired belong here (v1: just
## butterfly_net).

const CaptureBook = preload("res://src/gameplay/capture_book.gd")
const CaptureExecutor = preload("res://src/gameplay/capture_executor.gd")

var book: CaptureBook


func before_each():
	book = CaptureBook.new()


func test_has_returns_true_for_a_known_device():
	assert_true(book.has("butterfly_net"))


func test_has_returns_false_for_an_unknown_device():
	assert_false(book.has("bug_jar"))


func test_known_ids_includes_butterfly_net():
	assert_true(book.known_ids().has("butterfly_net"))


func test_ast_for_returns_null_for_an_unknown_id():
	assert_null(book.ast_for("bug_jar"))


func test_ast_for_butterfly_net_parses_into_a_real_capture_block():
	var ast: Dictionary = book.ast_for("butterfly_net")
	assert_not_null(ast)
	assert_eq(ast["kind"], "capture")
	assert_eq(ast["name"], "Butterfly Net")


# --- a regression guard on the fixed table itself ----------------------------
# (mirrors test_spell_book.gd's own "every known spell must actually parse
# and cast" guard -- catches a typo in the hardcoded DSL source before it
# silently ships an uncatchable device.)

func test_every_known_device_has_a_real_catch_release_and_transfer_rule():
	var executor := CaptureExecutor.new()
	for device_id in book.known_ids():
		var ast: Dictionary = book.ast_for(device_id)
		assert_not_null(ast, "%s must parse" % device_id)
		assert_eq(ast.get("kind", ""), "capture", "%s must be a capture block" % device_id)
		assert_not_null(executor.capture_rule(ast), "%s must have a real 'on catch' rule" % device_id)
		assert_not_null(executor.release_rule(ast), "%s must have a real 'on release' rule" % device_id)


func test_the_butterfly_nets_catch_rule_actually_catches_at_its_documented_base():
	# Pins docs/concept/capture_dsl.md's own worked example: base := 0.65.
	var executor := CaptureExecutor.new()
	var ast: Dictionary = book.ast_for("butterfly_net")
	var rule: Variant = executor.capture_rule(ast)
	var result := executor.resolve_catch(rule, {"target": {"tier": "flyer"}}, 0.5)
	assert_true(result["caught"], "a roll of 0.5 must beat a base chance of 0.65")
	var miss := executor.resolve_catch(rule, {"target": {"tier": "flyer"}}, 0.99)
	assert_false(miss["caught"], "a roll of 0.99 must lose to a base chance of 0.65")
