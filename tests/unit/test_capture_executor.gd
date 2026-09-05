extends GutTest

## Red-first spec for capture_executor.gd (docs/concept/capture_dsl.md): the
## pure GO/NO-GO layer that decides whether a capture action happens and
## which effect atoms actually apply -- it does not mutate any game state
## itself (capture_atom_effects.gd does that), and it does not generate its
## own randomness (the roll is supplied by the caller, same split
## CreatureMarker._step_restraint's own hash roll already keeps).
##
## Revised 2026-09-05: the net is device text (standard_model.md's grammar),
## the first atom of its catch pipeline is the physics gate (mesh_holds,
## which fails WITH a reason), and confine(in: PART) is statically required
## to follow a mesh_holds on the same part -- validate() is that check.

const CaptureExecutor = preload("res://src/gameplay/capture_executor.gd")
const DeviceParser = preload("res://src/gameplay/device_parser.gd")
const DeviceCompiler = preload("res://src/gameplay/device_compiler.gd")
const BodyDimensions = preload("res://src/gameplay/body_dimensions.gd")

var executor: CaptureExecutor
var parser: DeviceParser


func before_each():
	executor = CaptureExecutor.new()
	parser = DeviceParser.new()


func _ast(source: String) -> Dictionary:
	var result: Dictionary = parser.parse(source)
	assert_true(result["ok"], "expected parse to succeed, errors: %s" % [result["errors"]])
	return result["ast"]


const NET := """
	device "Butterfly Net" {
	  part handle: wood haft grip (length_cm: 120, diameter_cm: 2.5)
	  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
	  joint hem: handle to bag rigid lashing fiber
	  on catch:
	    mesh_holds(mesh: bag) |> catch_roll(base: 0.65) |> confine(in: bag)
	  on release:
	    free(from: bag)
	  on transfer(glass_bottle):
	    move_captive()
	}
"""


func _net_ast() -> Dictionary:
	return _ast(NET)


## The context Player builds at the throw site: the subject's species and
## measured extents, plus the net's own part facts from the compiler.
func _context(species: String, boldness = null) -> Dictionary:
	var target := {"species": species, "extents_mm": BodyDimensions.extents_mm(species)}
	if boldness != null:
		target["boldness"] = boldness
	var context := {"target": target}
	context.merge(DeviceCompiler.compile(_net_ast())["facts"])
	return context


# --- finding rules ------------------------------------------------------------

func test_capture_rule_finds_the_on_catch_rule():
	var rule: Variant = executor.capture_rule(_net_ast())
	assert_not_null(rule)
	assert_eq(rule["event"], "catch")


func test_capture_rule_is_null_when_the_device_has_none():
	var ast := _ast('device "X" { on release: free(from: bag) }')
	assert_null(executor.capture_rule(ast))


func test_release_rule_finds_the_on_release_rule():
	var rule: Variant = executor.release_rule(_net_ast())
	assert_not_null(rule)
	assert_eq(rule["event"], "release")


func test_transfer_rule_finds_the_matching_container():
	var rule: Variant = executor.transfer_rule(_net_ast(), "glass_bottle")
	assert_not_null(rule)
	assert_eq(rule["event"], "transfer")
	assert_eq(rule["event_arg"], "glass_bottle")


func test_transfer_rule_is_null_for_an_unhandled_container():
	assert_null(executor.transfer_rule(_net_ast(), "jam_jar"))


# --- guard evaluation ---------------------------------------------------------

func test_a_null_guard_always_passes():
	assert_true(executor.evaluate_guard(null, {}))


func test_a_string_equality_guard_matches_the_context():
	var guard := {"op": "==", "lhs": "target.tier", "rhs": "flyer"}
	assert_true(executor.evaluate_guard(guard, {"target": {"tier": "flyer"}}))
	assert_false(executor.evaluate_guard(guard, {"target": {"tier": "legless"}}))


func test_guard_honors_the_full_comparison_set_on_a_numeric_path():
	var context := {"target": {"boldness": 0.5}}
	var cases := {
		">=": [0.4, true], "<=": [0.6, true], ">": [0.6, false],
		"<": [0.4, false], "==": [0.5, true], "!=": [0.5, false],
	}
	for op in cases:
		var rhs = cases[op][0]
		var expected: bool = cases[op][1]
		var guard := {"op": op, "lhs": "target.boldness", "rhs": rhs}
		assert_eq(executor.evaluate_guard(guard, context), expected, "op '%s' rhs %s" % [op, rhs])


func test_an_unresolved_path_makes_the_guard_false_rather_than_crash():
	var guard := {"op": "==", "lhs": "target.nonexistent", "rhs": "anything"}
	assert_false(executor.evaluate_guard(guard, {"target": {"tier": "flyer"}}))


# --- resolve_catch: the mesh gate, then the roll -------------------------------

func test_result_always_carries_caught_effects_and_reason():
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), _context("monarch"), 0.0)
	for key in ["caught", "effects", "reason"]:
		assert_true(result.has(key), key)


func test_a_bee_is_refused_by_the_mesh_with_its_reason_before_any_roll():
	# A roll of 0.0 would catch anything the mesh holds; the mesh does not
	# hold a bee, so the swing never gets that far.
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), _context("bee"), 0.0)
	assert_false(result["caught"])
	assert_eq(result["effects"], [])
	assert_true(result["reason"].contains("slips through"), result["reason"])
	assert_true(result["reason"].contains("bee"), "the reason names the subject: %s" % result["reason"])


func test_a_fly_is_refused_the_same_way():
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), _context("fly"), 0.0)
	assert_false(result["caught"])
	assert_true(result["reason"].contains("slips through"), result["reason"])


func test_a_koi_is_refused_as_too_big_for_the_mouth():
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), _context("koi"), 0.0)
	assert_false(result["caught"])
	assert_true(result["reason"].contains("too big"), result["reason"])


func test_an_unmeasured_species_is_refused_with_its_own_reason():
	var context := _context("dragon")
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), context, 0.0)
	assert_false(result["caught"])
	assert_true(result["reason"].contains("size"), result["reason"])


func test_a_mesh_the_context_has_no_facts_for_refuses_and_names_it():
	var context := {"target": {"species": "monarch", "extents_mm": BodyDimensions.extents_mm("monarch")}}
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), context, 0.0)
	assert_false(result["caught"])
	assert_true(result["reason"].contains("bag"), result["reason"])


func test_a_monarch_is_held_and_a_winning_roll_confines_it_in_the_bag():
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), _context("monarch"), 0.1)
	assert_true(result["caught"])
	assert_eq(result["reason"], "")
	assert_eq(result["effects"], [{"atom": "confine", "params": {"in": "bag"}}])


func test_a_goldfish_is_held_and_netted_the_same_way():
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), _context("goldfish"), 0.1)
	assert_true(result["caught"])
	assert_eq(result["effects"], [{"atom": "confine", "params": {"in": "bag"}}])


func test_a_sparrow_is_held_too():
	assert_true(executor.resolve_catch(executor.capture_rule(_net_ast()), _context("sparrow"), 0.1)["caught"])


func test_a_lost_roll_is_a_silent_miss_not_a_refusal():
	var result := executor.resolve_catch(executor.capture_rule(_net_ast()), _context("monarch"), 0.99)
	assert_false(result["caught"])
	assert_eq(result["effects"], [])
	assert_eq(result["reason"], "", "a miss is a miss; only the mesh explains itself")


func test_resolve_catch_reads_boldness_out_of_the_target_context():
	# Same roll, same base -- a bolder target's higher chance is what flips
	# this specific roll from a miss to a catch (0.65 base + up to +0.15 for
	# boldness 1.0 = 0.80; a roll of 0.75 is a miss at middling but a catch
	# at maximum boldness).
	var rule: Variant = executor.capture_rule(_net_ast())
	var shy := executor.resolve_catch(rule, _context("monarch", 0.5), 0.75)
	var bold := executor.resolve_catch(rule, _context("monarch", 1.0), 0.75)
	assert_false(shy["caught"], "a middling target should not be caught by this roll")
	assert_true(bold["caught"], "a bolder target's better odds should catch this same roll")


func test_a_subject_with_no_personality_rolls_at_middling_boldness():
	# A fish has no traits: it gets exactly the device's own base, 0.65.
	var rule: Variant = executor.capture_rule(_net_ast())
	assert_true(executor.resolve_catch(rule, _context("goldfish"), 0.6)["caught"])
	assert_false(executor.resolve_catch(rule, _context("goldfish"), 0.7)["caught"])


func test_a_null_rule_never_catches():
	var result := executor.resolve_catch(null, _context("monarch"), 0.0)
	assert_false(result["caught"])
	assert_eq(result["reason"], "")


# --- resolve_release / resolve_transfer: no roll, guard-gated only -----------

func test_resolve_release_reports_its_effect():
	var rule: Variant = executor.release_rule(_net_ast())
	var result := executor.resolve_release(rule, {})
	assert_true(result["released"])
	assert_eq(result["effects"], [{"atom": "free", "params": {"from": "bag"}}])


func test_resolve_transfer_reports_its_effect():
	var rule: Variant = executor.transfer_rule(_net_ast(), "glass_bottle")
	var result := executor.resolve_transfer(rule, {})
	assert_true(result["transferred"])
	assert_eq(result["effects"], [{"atom": "move_captive", "params": {}}])


func test_resolve_transfer_with_a_null_rule_does_not_transfer():
	var result := executor.resolve_transfer(null, {})
	assert_false(result["transferred"])
	assert_eq(result["effects"], [])


# --- validate: the static constraint layer ---------------------------------------
# (an author cannot write a net that ignores its own mesh: confine(in: X)
# must follow mesh_holds(mesh: X) in the same pipeline, and every part a
# rule names must be declared.)

func _errors_of(source: String) -> Array:
	return executor.validate(_ast(source))


func test_the_net_validates_clean():
	assert_eq(executor.validate(_net_ast()), [])


func test_confine_without_a_preceding_mesh_holds_on_the_same_part_is_refused():
	var errors := _errors_of("""
		device "X" {
		  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
		  on catch: catch_roll(base: 1) |> confine(in: bag)
		}
	""")
	assert_eq(errors.size(), 1, str(errors))
	assert_true(String(errors[0]).contains("confine"), str(errors))
	assert_true(String(errors[0]).contains("mesh_holds"), str(errors))


func test_a_mesh_holds_on_a_different_part_does_not_license_the_confine():
	var errors := _errors_of("""
		device "X" {
		  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
		  part sack: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
		  on catch: mesh_holds(mesh: sack) |> confine(in: bag)
		}
	""")
	assert_eq(errors.size(), 1, str(errors))
	assert_true(String(errors[0]).contains("bag"), str(errors))


func test_a_mesh_holds_after_the_confine_does_not_count():
	var errors := _errors_of("""
		device "X" {
		  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
		  on catch: confine(in: bag) |> mesh_holds(mesh: bag)
		}
	""")
	assert_eq(errors.size(), 1, str(errors))


func test_a_rule_naming_an_undeclared_part_is_refused_by_name():
	for source in [
		'device "X" { on catch: mesh_holds(mesh: ghost) }',
		'device "X" { on release: free(from: ghost) }',
	]:
		var errors := _errors_of(source)
		assert_eq(errors.size(), 1, str(errors))
		assert_true(String(errors[0]).contains("ghost"), str(errors))


func test_an_unknown_atom_is_refused_by_name():
	var errors := _errors_of('device "X" { on catch: levitate() }')
	assert_eq(errors.size(), 1, str(errors))
	assert_true(String(errors[0]).contains("levitate"), str(errors))


func test_a_missing_atom_parameter_is_named():
	var errors := _errors_of("""
		device "X" {
		  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
		  on catch: mesh_holds() |> confine(in: bag)
		}
	""")
	assert_gt(errors.size(), 0)
	assert_true(String(errors[0]).contains("mesh"), str(errors))


func test_validate_reports_every_problem_not_only_the_first():
	var errors := _errors_of("""
		device "X" {
		  on catch: levitate() |> confine(in: ghost)
		}
	""")
	assert_gt(errors.size(), 1, str(errors))


# --- end to end: real device text into the real executor --------------------------

func test_a_device_parsed_from_real_dsl_text_can_actually_be_caught():
	var ast := _ast("""
		device "Sure Net" {
		  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
		  on catch: mesh_holds(mesh: bag) |> catch_roll(base: 1.0) |> confine(in: bag)
		}
	""")
	assert_eq(executor.validate(ast), [])
	var context := {"target": {"species": "monarch", "extents_mm": BodyDimensions.extents_mm("monarch")}}
	context.merge(DeviceCompiler.compile(ast)["facts"])
	var result := executor.resolve_catch(executor.capture_rule(ast), context, 0.999)
	assert_true(result["caught"], "base 1.0 must always catch what the mesh holds")


func test_a_finer_net_written_as_text_holds_the_bee():
	var ast := _ast("""
		device "Insect Net" {
		  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.02, aperture_mm: 1)
		  on catch: mesh_holds(mesh: bag) |> catch_roll(base: 1.0) |> confine(in: bag)
		}
	""")
	var context := {"target": {"species": "bee", "extents_mm": BodyDimensions.extents_mm("bee")}}
	context.merge(DeviceCompiler.compile(ast)["facts"])
	var result := executor.resolve_catch(executor.capture_rule(ast), context, 0.5)
	assert_true(result["caught"], "a 1 mm mesh holds a 6 mm bee: %s" % result["reason"])


func test_a_landing_net_written_as_text_takes_the_trout():
	var ast := _ast("""
		device "Landing Net" {
		  part bag: fiber face cover (width_cm: 40, height_cm: 60, thickness_cm: 0.1, aperture_mm: 25)
		  on catch: mesh_holds(mesh: bag) |> catch_roll(base: 1.0) |> confine(in: bag)
		}
	""")
	var context := {"target": {"species": "trout", "extents_mm": BodyDimensions.extents_mm("trout")}}
	context.merge(DeviceCompiler.compile(ast)["facts"])
	assert_true(executor.resolve_catch(executor.capture_rule(ast), context, 0.5)["caught"])
	var minnow := {"target": {"species": "fly", "extents_mm": BodyDimensions.extents_mm("fly")}}
	minnow.merge(DeviceCompiler.compile(ast)["facts"])
	assert_false(executor.resolve_catch(executor.capture_rule(ast), minnow, 0.5)["caught"],
		"a coarse landing net lets a fly straight through")
