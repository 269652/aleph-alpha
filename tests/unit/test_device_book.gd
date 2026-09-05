extends GutTest

## Red-first spec for device_book.gd -- the small fixed table of pre-authored
## device texts (docs/concept/standard_model.md's worked examples A and B),
## parsed once and cached, the same role capture_book.gd and spell_book.gd
## play for their DSLs -- and the END-TO-END proof that the whole standard
## model holds together: text -> AST -> part graph + chain -> solved loop ->
## fired rules, with every number below produced by the shipped physics
## rather than typed in.
##
## The headline is test_without_a_gear_train_the_same_wheel_lights_nothing:
## a water wheel turns at about a radian and a half a second, far too slow
## to generate from directly, and real mills geared up by ten or more for
## exactly that reason. Nobody wrote that rule; the algebra says it.

const DeviceBook = preload("res://src/gameplay/device_book.gd")
const DeviceParser = preload("res://src/gameplay/device_parser.gd")
const DeviceCompiler = preload("res://src/gameplay/device_compiler.gd")
const DeviceNetwork = preload("res://src/gameplay/device_network.gd")
const DeviceExecutor = preload("res://src/gameplay/device_executor.gd")

var book: DeviceBook


func before_each():
	book = DeviceBook.new()


# --- the table ----------------------------------------------------------------------

func test_the_book_carries_the_two_worked_examples_in_order():
	assert_eq(book.known_ids(), ["mill_race_light", "windmill_mill"])
	assert_true(book.has("mill_race_light"))
	assert_false(book.has("perpetual_motion_machine"))


func test_an_unknown_device_has_no_ast_and_no_compile():
	assert_null(book.ast_for("perpetual_motion_machine"))
	assert_null(book.compiled_for("perpetual_motion_machine"))


func test_every_entry_parses_compiles_and_solves():
	for id in book.known_ids():
		var ast = book.ast_for(id)
		assert_not_null(ast, id)
		assert_eq(ast["kind"], "device", id)
		var compiled = book.compiled_for(id)
		assert_not_null(compiled, id)
		assert_true(compiled["ok"], "%s: %s" % [id, compiled["errors"]])
		var solved: Dictionary = DeviceNetwork.solve(compiled["chain"], 1.0)
		assert_true(solved["ok"], "%s: %s" % [id, solved["errors"]])
		assert_gt(solved["source_power"], 0.0, id)


func test_the_cache_hands_back_the_same_parsed_and_compiled_objects():
	assert_same(book.ast_for("mill_race_light"), DeviceBook.new().ast_for("mill_race_light"))
	assert_same(book.compiled_for("mill_race_light"), DeviceBook.new().compiled_for("mill_race_light"))


# --- worked example A: the mill race light ------------------------------------------

func _light() -> Dictionary:
	return DeviceNetwork.solve(book.compiled_for("mill_race_light")["chain"], 1.0)


func test_the_mill_race_light_is_a_real_assembly_with_a_real_mass():
	var compiled: Dictionary = book.compiled_for("mill_race_light")
	var graph: RefCounted = compiled["graph"]
	assert_true(graph.is_well_formed())
	assert_true(graph.has_part("wheel"))
	assert_true(graph.has_part("filament"))
	# A two-metre wooden wheel on an iron axle: about a hundred kilograms.
	assert_between(compiled["mass_kg"], 90.0, 120.0)


func test_the_river_the_wheel_the_dynamo_and_the_wires_are_all_derived():
	var chain: Array = book.compiled_for("mill_race_light")["chain"]
	var by_id := {}
	for element in chain:
		by_id[element["id"]] = element
	assert_almost_eq(by_id["river"]["params"]["effort"], 720.0, 1e-6)       # 1/2 rho Cd A v^2
	assert_almost_eq(by_id["river"]["params"]["resistance"], 480.0, 1e-6)   # F / v
	assert_almost_eq(by_id["wheel"]["params"]["ratio"], 1.0, 1e-9)          # its metre of radius
	assert_almost_eq(by_id["gears"]["params"]["ratio"], 0.1, 1e-9)          # 1:10 step-up
	assert_almost_eq(by_id["dynamo"]["params"]["ratio"], 2.0, 1e-9)         # B A N
	assert_between(by_id["wire"]["params"]["resistance"], 0.024, 0.025)     # 10 m of 3 mm copper
	assert_between(by_id["filament"]["params"]["resistance"], 12.5, 13.0)   # 2 cm of 0.1 mm graphite


func test_the_filament_receives_about_sixty_watts():
	var solved := _light()
	assert_between(solved["elements"]["filament"]["dissipated"], 55.0, 70.0)


func test_the_wire_is_negligible_next_to_the_filament_as_a_wire_should_be():
	var solved := _light()
	assert_lt(
		solved["elements"]["wire"]["dissipated"],
		0.01 * solved["elements"]["filament"]["dissipated"]
	)


func test_the_loaded_wheel_runs_a_little_under_stream_speed():
	# The river runs at 1.5 m/s; the wheel rim, loaded, a few percent under.
	var solved := _light()
	assert_between(solved["source_flow"], 1.30, 1.49)


func test_the_geared_dynamo_turns_at_over_a_hundred_rpm():
	var solved := _light()
	var rpm: float = solved["elements"]["dynamo"]["flow"] * 60.0 / TAU
	assert_between(rpm, 100.0, 200.0)


func test_the_light_conserves_energy_to_the_watt():
	var solved := _light()
	assert_almost_eq(
		solved["source_power"], solved["dissipated_power"] + solved["stored_power"], 1e-9
	)


func test_the_shine_rule_fires_on_the_lit_filament():
	var executor := DeviceExecutor.new()
	var compiled: Dictionary = book.compiled_for("mill_race_light")
	var context: Dictionary = executor.context_for(_light(), {"mass_kg": compiled["mass_kg"]})
	var result: Dictionary = executor.resolve(book.ast_for("mill_race_light"), "step", context)
	assert_eq(result["effects"], [{"atom": "shine", "params": {"target": "filament"}}])


## The headline. Same river, same wheel, same dynamo, same filament -- take
## the gear train out and the filament gets under a watt, because a water
## wheel simply does not turn fast enough to generate from directly. Real
## mills geared up by ten or more for exactly this reason; here it is a
## consequence, not a rule.
func test_without_a_gear_train_the_same_wheel_lights_nothing():
	var parsed: Dictionary = DeviceParser.new().parse(DeviceBook.MILL_RACE_LIGHT_WITHOUT_GEARS)
	assert_true(parsed["ok"], str(parsed["errors"]))
	var compiled: Dictionary = DeviceCompiler.compile(parsed["ast"])
	assert_true(compiled["ok"], str(compiled["errors"]))
	var solved: Dictionary = DeviceNetwork.solve(compiled["chain"], 1.0)
	assert_true(solved["ok"], str(solved["errors"]))
	assert_lt(solved["elements"]["filament"]["dissipated"], 1.0)
	var executor := DeviceExecutor.new()
	var result: Dictionary = executor.resolve(parsed["ast"], "step", executor.context_for(solved))
	assert_eq(result["effects"], [], "a sub-watt filament does not shine")


# --- worked example B: the windmill grain mill ----------------------------------------

func _mill() -> Dictionary:
	return DeviceNetwork.solve(book.compiled_for("windmill_mill")["chain"], 1.0)


func test_the_windmill_is_the_same_paddle_law_with_air():
	var chain: Array = book.compiled_for("windmill_mill")["chain"]
	assert_eq(chain[0]["id"], "wind")
	# 1/2 * 1.225 * 1.28 * 10 m^2 * (8 m/s)^2 = 501.76 N
	assert_almost_eq(chain[0]["params"]["effort"], 501.76, 1e-6)


func test_the_millstone_receives_most_of_a_kilowatt():
	var solved := _mill()
	assert_between(solved["elements"]["stone"]["dissipated"], 800.0, 1000.0)


func test_the_millstone_turns_at_a_real_millstones_speed():
	# Sixty-odd rpm: real millstones ran at roughly 60-125 rpm depending on
	# their diameter. The sails themselves turn at a tenth of that.
	var solved := _mill()
	var stone_rpm: float = solved["elements"]["stone"]["flow"] * 60.0 / TAU
	assert_between(stone_rpm, 55.0, 75.0)
	assert_lt(solved["elements"]["sails"]["flow_out"], solved["elements"]["stone"]["flow"])


func test_the_grind_rule_fires_on_the_turning_stone():
	var executor := DeviceExecutor.new()
	var result: Dictionary = executor.resolve(book.ast_for("windmill_mill"), "step", executor.context_for(_mill()))
	assert_eq(result["effects"], [{"atom": "grind", "params": {"target": "stone"}}])


func test_the_mill_conserves_energy_to_the_watt():
	var solved := _mill()
	assert_almost_eq(
		solved["source_power"], solved["dissipated_power"] + solved["stored_power"], 1e-9
	)
