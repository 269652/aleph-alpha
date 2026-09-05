extends GutTest

## Red-first spec for capture_book.gd (docs/concept/capture_dsl.md): the
## small, fixed table of pre-authored capture-device text, parsed, compiled
## and validated once and cached -- same role spell_book.gd and
## device_book.gd play for their DSLs: a real, usable set of content while
## any future device-authoring UI stays unbuilt. Kept honest on purpose:
## only devices that are actually wired belong here (v1: just butterfly_net).
##
## Revised 2026-09-05: the net is DEVICE text (standard_model.md's grammar,
## parsed by device_parser.gd), with a real bag whose mesh has an aperture,
## so the book also hands out the compiler's part facts the catch context
## needs, and refuses at load any text CaptureExecutor.validate rejects.

const CaptureBook = preload("res://src/gameplay/capture_book.gd")
const CaptureExecutor = preload("res://src/gameplay/capture_executor.gd")
const BodyDimensions = preload("res://src/gameplay/body_dimensions.gd")

var book: CaptureBook
var executor: CaptureExecutor


func before_each():
	book = CaptureBook.new()
	executor = CaptureExecutor.new()


func test_has_returns_true_for_a_known_device():
	assert_true(book.has("butterfly_net"))


func test_has_returns_false_for_an_unknown_device():
	assert_false(book.has("bug_jar"))


func test_known_ids_includes_butterfly_net():
	assert_true(book.known_ids().has("butterfly_net"))


func test_ast_for_returns_null_for_an_unknown_id():
	assert_null(book.ast_for("bug_jar"))
	assert_null(book.compiled_for("bug_jar"))
	assert_eq(book.facts_for("bug_jar"), {})


func test_ast_for_butterfly_net_parses_into_a_real_device_block():
	var ast: Dictionary = book.ast_for("butterfly_net")
	assert_not_null(ast)
	assert_eq(ast["kind"], "device")
	assert_eq(ast["name"], "Butterfly Net")


func test_the_net_is_a_real_assembly_with_a_bag_a_hoop_and_a_handle():
	var compiled: Dictionary = book.compiled_for("butterfly_net")
	assert_true(compiled["ok"], str(compiled["errors"]))
	var graph: RefCounted = compiled["graph"]
	assert_true(graph.is_well_formed(), str(graph.validation_errors()))
	for part_id in ["handle", "hoop", "bag"]:
		assert_true(graph.has_part(part_id), part_id)
	assert_true(graph.is_one_assembly())
	# A wooden handle, a thin iron hoop and a fibre bag: under half a kilo.
	assert_between(compiled["mass_kg"], 0.3, 0.5)


func test_the_bag_is_a_ten_millimetre_mesh_with_a_thirty_centimetre_mouth():
	var facts: Dictionary = book.facts_for("butterfly_net")
	assert_eq(facts["bag"]["aperture_mm"], 10)
	assert_eq(facts["bag"]["width_cm"], 30)
	assert_eq(facts["bag"]["material"], "fiber")


func test_facts_for_is_a_copy():
	var facts: Dictionary = book.facts_for("butterfly_net")
	facts["bag"]["aperture_mm"] = 1
	assert_eq(book.facts_for("butterfly_net")["bag"]["aperture_mm"], 10)


# --- a regression guard on the fixed table itself ----------------------------
# (mirrors test_spell_book.gd's own "every known spell must actually parse
# and cast" guard -- catches a typo in the hardcoded DSL source before it
# silently ships an uncatchable device.)

func test_every_known_device_parses_compiles_validates_and_has_its_three_rules():
	for device_id in book.known_ids():
		var ast: Dictionary = book.ast_for(device_id)
		assert_not_null(ast, "%s must parse" % device_id)
		assert_eq(ast.get("kind", ""), "device", "%s must be a device block" % device_id)
		assert_true(book.compiled_for(device_id)["ok"], "%s must compile" % device_id)
		assert_eq(executor.validate(ast), [], "%s must validate clean" % device_id)
		assert_not_null(executor.capture_rule(ast), "%s must have a real 'on catch' rule" % device_id)
		assert_not_null(executor.release_rule(ast), "%s must have a real 'on release' rule" % device_id)
		assert_not_null(executor.transfer_rule(ast, "glass_bottle"), "%s must handle the glass bottle" % device_id)


func test_the_cache_hands_back_the_same_objects_across_instances():
	assert_same(book.ast_for("butterfly_net"), CaptureBook.new().ast_for("butterfly_net"))
	assert_same(book.compiled_for("butterfly_net"), CaptureBook.new().compiled_for("butterfly_net"))


# --- the net, end to end: what the standard net actually catches ----------------

func _context(species: String) -> Dictionary:
	var context := {"target": {"species": species, "extents_mm": BodyDimensions.extents_mm(species)}}
	context.merge(book.facts_for("butterfly_net"))
	return context


func _verdict(species: String, roll: float) -> Dictionary:
	return executor.resolve_catch(executor.capture_rule(book.ast_for("butterfly_net")), _context(species), roll)


func test_the_butterfly_nets_catch_rule_actually_catches_at_its_documented_base():
	# Pins docs/concept/capture_dsl.md's own worked example: base := 0.65.
	assert_true(_verdict("monarch", 0.5)["caught"], "a roll of 0.5 must beat a base chance of 0.65")
	assert_false(_verdict("monarch", 0.99)["caught"], "a roll of 0.99 must lose to a base chance of 0.65")


func test_the_standard_net_holds_butterflies_small_birds_and_small_fish():
	for species in ["monarch", "swallowtail", "blue_morpho", "sparrow", "robin", "goldfish", "bluegill"]:
		var verdict := _verdict(species, 0.0)
		assert_true(verdict["caught"], "%s: %s" % [species, verdict["reason"]])
		assert_eq(verdict["effects"], [{"atom": "confine", "params": {"in": "bag"}}], species)


func test_bees_and_flies_slip_through_the_standard_net():
	for species in ["bee", "fly"]:
		var verdict := _verdict(species, 0.0)
		assert_false(verdict["caught"], species)
		assert_true(verdict["reason"].contains("slips through"), verdict["reason"])
		assert_true(verdict["reason"].contains(species), verdict["reason"])


func test_trout_and_koi_are_too_big_for_the_standard_net():
	for species in ["trout", "koi"]:
		var verdict := _verdict(species, 0.0)
		assert_false(verdict["caught"], species)
		assert_true(verdict["reason"].contains("too big"), verdict["reason"])


func test_release_frees_the_bag_and_transfer_moves_the_captive():
	var ast: Dictionary = book.ast_for("butterfly_net")
	assert_eq(executor.resolve_release(executor.release_rule(ast), {})["effects"],
		[{"atom": "free", "params": {"from": "bag"}}])
	assert_eq(executor.resolve_transfer(executor.transfer_rule(ast, "glass_bottle"), {})["effects"],
		[{"atom": "move_captive", "params": {}}])
