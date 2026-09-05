extends GutTest

## Red-first spec for the series-loop solver of docs/concept/standard_model.md
## ("5. Resolution order"): one Thevenin source driving a chain of transformers,
## gyrators, resistors and stores, solved in closed form by reflecting every
## load back to the source, then propagated forward.
##
## The anchor test is test_there_is_an_optimum_load_for_delivered_power -- the
## maximum power transfer theorem emerging from the solver rather than being
## written into it, this model's twin of emergent_crafting.md's "optimum head
## mass". The other load-bearing property is conservation: source power out
## equals dissipated plus stored, to the watt, on every chain.

const DeviceNetwork = preload("res://src/gameplay/device_network.gd")
const DeviceElements = preload("res://src/gameplay/device_elements.gd")


func _source(id: String, effort: float, resistance: float) -> Dictionary:
	return {"id": id, "kind": "source", "params": {"effort": effort, "resistance": resistance}}


func _resist(id: String, resistance: float) -> Dictionary:
	return {"id": id, "kind": "resist", "params": {"resistance": resistance}}


func _transform(id: String, ratio: float) -> Dictionary:
	return {"id": id, "kind": "transform", "params": {"ratio": ratio}}


func _gyrate(id: String, ratio: float) -> Dictionary:
	return {"id": id, "kind": "gyrate", "params": {"ratio": ratio}}


func _store(id: String, capacity: float, full_effort: float, level: float, resistance: float = 0.0) -> Dictionary:
	return {"id": id, "kind": "store", "params": {
		"capacity": capacity, "full_effort": full_effort, "level": level, "resistance": resistance,
	}}


func _solved(chain: Array, dt: float = 0.0) -> Dictionary:
	var result: Dictionary = DeviceNetwork.solve(chain, dt)
	assert_true(result["ok"], "expected a solve, errors: %s" % [result["errors"]])
	return result


# --- refusals ------------------------------------------------------------------

func test_result_always_has_the_same_keys_whether_or_not_it_solved():
	for chain in [[], [_source("s", 1.0, 1.0), _resist("r", 1.0)]]:
		var result: Dictionary = DeviceNetwork.solve(chain, 0.0)
		for key in ["ok", "errors", "order", "elements", "stores", "source_flow",
				"source_effort", "source_power", "dissipated_power", "stored_power",
				"residual_effort"]:
			assert_true(result.has(key), "missing %s" % key)


func test_an_empty_chain_is_refused():
	var result: Dictionary = DeviceNetwork.solve([], 0.0)
	assert_false(result["ok"])
	assert_gt(result["errors"].size(), 0)


func test_a_loop_needs_a_source_first():
	var result: Dictionary = DeviceNetwork.solve([_resist("r", 1.0), _source("s", 1.0, 1.0)], 0.0)
	assert_false(result["ok"])
	assert_true(String(result["errors"][0]).contains("source"), str(result["errors"]))


func test_a_second_source_is_refused_in_this_slice():
	var result: Dictionary = DeviceNetwork.solve(
		[_source("a", 1.0, 1.0), _resist("r", 1.0), _source("b", 1.0, 1.0)], 0.0
	)
	assert_false(result["ok"])
	assert_true(String(result["errors"][0]).contains("one source"), str(result["errors"]))


func test_element_validation_errors_bubble_up_naming_the_element():
	var result: Dictionary = DeviceNetwork.solve(
		[_source("river", 1.0, 1.0), {"id": "wheel", "kind": "transform", "params": {}}], 0.0
	)
	assert_false(result["ok"])
	assert_true(String(result["errors"][0]).contains("wheel"), str(result["errors"]))
	assert_true(String(result["errors"][0]).contains("ratio"), str(result["errors"]))


func test_duplicate_ids_are_refused():
	var result: Dictionary = DeviceNetwork.solve(
		[_source("s", 1.0, 1.0), _resist("x", 1.0), _resist("x", 2.0)], 0.0
	)
	assert_false(result["ok"])
	assert_true(String(result["errors"][0]).contains("x"), str(result["errors"]))


func test_an_ideal_source_driving_a_short_has_no_finite_flow_and_says_so():
	var result: Dictionary = DeviceNetwork.solve([_source("s", 10.0, 0.0), _resist("r", 0.0)], 0.0)
	assert_false(result["ok"])
	assert_gt(result["errors"].size(), 0)


func test_an_ideal_effort_behind_a_gyrator_is_refused_with_the_physical_reason():
	# A store with no internal resistance behind a gyrator would pin the shaft
	# speed -- a flow constraint the affine solver cannot express. Refused,
	# not mis-solved, and the reason names the store.
	var result: Dictionary = DeviceNetwork.solve(
		[_source("s", 0.0, 1.0), _gyrate("g", 2.0), _store("cell", 1000.0, 12.0, 1000.0, 0.0)], 0.0
	)
	assert_false(result["ok"])
	assert_true(String(result["errors"][0]).contains("cell"), str(result["errors"]))


# --- Ohm's law, the base case -------------------------------------------------

func test_a_source_into_one_resistor_is_ohms_law():
	var result := _solved([_source("s", 100.0, 10.0), _resist("r", 40.0)])
	assert_almost_eq(result["source_flow"], 2.0, 1e-9)
	assert_almost_eq(result["source_effort"], 80.0, 1e-9)
	assert_almost_eq(result["elements"]["r"]["effort"], 80.0, 1e-9)
	assert_almost_eq(result["elements"]["r"]["flow"], 2.0, 1e-9)
	assert_almost_eq(result["elements"]["r"]["dissipated"], 160.0, 1e-9)
	assert_almost_eq(result["source_power"], 160.0, 1e-9)
	assert_almost_eq(result["dissipated_power"], 160.0, 1e-9)


func test_two_resistors_in_a_chain_share_one_flow_and_split_the_effort():
	var result := _solved([_source("s", 100.0, 0.0), _resist("wire", 1.0), _resist("bulb", 4.0)])
	assert_almost_eq(result["source_flow"], 20.0, 1e-9)
	assert_almost_eq(result["elements"]["wire"]["effort"], 20.0, 1e-9)
	assert_almost_eq(result["elements"]["bulb"]["effort"], 80.0, 1e-9)
	assert_almost_eq(result["elements"]["bulb"]["flow"], 20.0, 1e-9)


func test_results_keep_construction_order_and_every_element_reports_its_power():
	var result := _solved([_source("s", 100.0, 10.0), _transform("t", 2.0), _resist("r", 40.0)])
	assert_eq(result["order"], ["s", "t", "r"])
	for id in result["order"]:
		for key in ["kind", "effort", "flow", "power", "power_in", "power_out", "dissipated", "stored_rate"]:
			assert_true(result["elements"][id].has(key), "%s is missing %s" % [id, key])


# --- conservation: the property everything else rests on ----------------------

func test_efforts_around_a_closed_loop_sum_to_zero():
	var result := _solved([
		_source("s", 100.0, 10.0), _transform("lever", 2.0), _resist("wire", 1.0),
		_gyrate("dynamo", 3.0), _resist("bulb", 5.0), _store("cell", 1000.0, 12.0, 250.0, 0.5),
	])
	assert_almost_eq(result["residual_effort"], 0.0, 1e-9)


func test_source_power_equals_dissipated_plus_stored_power():
	var result := _solved([
		_source("s", 100.0, 10.0), _transform("lever", 2.0), _resist("wire", 1.0),
		_gyrate("dynamo", 3.0), _resist("bulb", 5.0), _store("cell", 1000.0, 12.0, 250.0, 0.5),
	])
	assert_gt(result["source_power"], 0.0)
	assert_almost_eq(
		result["source_power"], result["dissipated_power"] + result["stored_power"], 1e-9
	)


func test_two_ports_pass_power_through_untouched():
	var result := _solved([
		_source("s", 100.0, 10.0), _transform("lever", 2.0), _gyrate("dynamo", 3.0), _resist("bulb", 5.0),
	])
	for id in ["lever", "dynamo"]:
		assert_almost_eq(result["elements"][id]["power_in"], result["elements"][id]["power_out"], 1e-9, id)
		assert_eq(result["elements"][id]["dissipated"], 0.0)


# --- THE ANCHOR TEST -------------------------------------------------------------
#
# Fix a source and sweep the load it drives. Delivered power must RISE and
# then FALL with the optimum strictly inside the sweep -- at the load whose
# reflection equals the source's own internal resistance. Too light a load
# and there is nothing to deliver power into; too heavy and the source
# stalls. Nobody wrote that in: it is the maximum power transfer theorem,
# reached through a lever AND a generator, and a solver that ever became
# monotonic in load fails here.

func test_there_is_an_optimum_load_for_delivered_power():
	var source_resistance := 10.0
	var lever_ratio := 2.0
	var dynamo_ratio := 3.0
	var loads: Array[float] = []
	var load := 0.01
	while load <= 10.0001:
		loads.append(load)
		load *= 1.1
	var powers: Array[float] = []
	for bulb in loads:
		var result := _solved([
			_source("s", 100.0, source_resistance), _transform("lever", lever_ratio),
			_gyrate("dynamo", dynamo_ratio), _resist("bulb", bulb),
		])
		powers.append(result["elements"]["bulb"]["dissipated"])

	var best := 0
	for i in range(powers.size()):
		if powers[i] > powers[best]:
			best = i
	assert_gt(best, 0, "the optimum must not be the lightest load in the sweep")
	assert_lt(best, powers.size() - 1, "the optimum must not be the heaviest load in the sweep")
	for i in range(1, best + 1):
		assert_gt(powers[i], powers[i - 1], "power must still be rising at load %.4f" % loads[i])
	for i in range(best + 1, powers.size()):
		assert_lt(powers[i], powers[i - 1], "power must be falling at load %.4f" % loads[i])

	# Matched load: the bulb whose reflection through k^2/R and then 1/r^2
	# equals the source's own internal resistance.
	var matched := dynamo_ratio * dynamo_ratio / (lever_ratio * lever_ratio * source_resistance)
	assert_between(matched, loads[best] / 1.1, loads[best] * 1.1,
		"the optimum should sit at the matched load %.4f" % matched)
	# And the peak is the source's own ceiling, less the lever/dynamo costing
	# nothing: e0^2 / (4 R), reached within the sweep's resolution.
	assert_between(powers[best], 0.99 * 250.0, 250.0)


func test_more_grinding_load_slows_the_wheel():
	# A mill: paddle -> wheel radius -> millstone. A heavier stone (bigger
	# rotational resistance) turns slower. Monotone, no exception.
	var previous := INF
	for stone in [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]:
		var result := _solved([_source("river", 720.0, 480.0), _transform("wheel", 1.0), _resist("stone", stone)])
		assert_lt(result["source_flow"], previous, "stone %.1f" % stone)
		previous = result["source_flow"]


func test_more_electrical_load_slows_the_wheel_too():
	# Through a gyrator a SMALLER bulb resistance is a HEAVIER load on the
	# shaft (k^2 / R): a brighter lamp is a harder river to turn against.
	var previous := INF
	for bulb in [16.0, 8.0, 4.0, 2.0, 1.0, 0.5]:
		var result := _solved([
			_source("river", 720.0, 480.0), _transform("wheel", 1.0),
			_gyrate("dynamo", 2.0), _resist("bulb", bulb),
		])
		assert_lt(result["source_flow"], previous, "bulb %.1f" % bulb)
		previous = result["source_flow"]


# --- open ends ------------------------------------------------------------------

func test_an_open_ended_transformer_carries_no_flow_and_the_source_delivers_nothing():
	var result := _solved([_source("s", 100.0, 10.0), _transform("t", 2.0)])
	assert_eq(result["source_flow"], 0.0)
	assert_eq(result["source_power"], 0.0)
	assert_eq(result["elements"]["t"]["flow"], 0.0)


func test_an_unloaded_generator_runs_free_with_open_circuit_emf_and_no_current():
	var result := _solved([_source("s", 100.0, 10.0), _gyrate("dynamo", 3.0)])
	assert_almost_eq(result["source_flow"], 10.0, 1e-9)   # e0 / R: free running
	assert_almost_eq(result["source_effort"], 0.0, 1e-9)  # nothing to push against
	assert_almost_eq(result["elements"]["dynamo"]["effort_out"], 30.0, 1e-9)  # k * omega
	assert_almost_eq(result["elements"]["dynamo"]["flow_out"], 0.0, 1e-9)
	assert_almost_eq(result["source_power"], 0.0, 1e-9)


# --- stores: tanks stepped by the power that flows into them ----------------

func test_a_store_charges_by_the_power_flowing_into_it_times_dt():
	var result := _solved([_source("s", 20.0, 1.0), _resist("wire", 1.0), _store("cell", 1000.0, 12.0, 500.0)], 2.0)
	# e_store = 12 * 500/1000 = 6; f = (20 - 6) / 2 = 7; stored 6 * 7 = 42 W
	assert_almost_eq(result["source_flow"], 7.0, 1e-9)
	assert_almost_eq(result["stored_power"], 42.0, 1e-9)
	assert_almost_eq(result["stores"]["cell"]["level"], 500.0 + 42.0 * 2.0, 1e-9)
	assert_eq(result["stores"]["cell"]["overflow_j"], 0.0)


func test_a_full_store_at_the_source_effort_takes_no_charge():
	var result := _solved([_source("s", 12.0, 1.0), _store("cell", 1000.0, 12.0, 1000.0)], 1.0)
	assert_almost_eq(result["source_flow"], 0.0, 1e-9)
	assert_almost_eq(result["stores"]["cell"]["level"], 1000.0, 1e-9)


func test_overcharging_a_full_store_sheds_the_surplus_as_overflow():
	var result := _solved([_source("s", 20.0, 1.0), _store("cell", 1000.0, 12.0, 1000.0)], 1.0)
	# f = (20 - 12) / 1 = 8; 12 * 8 = 96 W into a full tank
	assert_almost_eq(result["stored_power"], 96.0, 1e-9)
	assert_almost_eq(result["stores"]["cell"]["level"], 1000.0, 1e-9)
	assert_almost_eq(result["stores"]["cell"]["overflow_j"], 96.0, 1e-9)


func test_a_charged_store_drives_the_loop_backwards_when_the_source_dies():
	# The river stops (0 effort, its internal resistance remains). The store's
	# own 6 V pushes 3 A the wrong way round the loop: the resistor still
	# heats, the store drains, and the dead source absorbs the rest.
	var result := _solved([_source("s", 0.0, 1.0), _resist("r", 1.0), _store("cell", 1000.0, 12.0, 500.0)], 10.0)
	assert_almost_eq(result["source_flow"], -3.0, 1e-9)
	assert_almost_eq(result["elements"]["r"]["dissipated"], 9.0, 1e-9)
	assert_almost_eq(result["stored_power"], -18.0, 1e-9)
	assert_almost_eq(result["source_power"], -9.0, 1e-9)
	assert_almost_eq(result["stores"]["cell"]["level"], 500.0 - 180.0, 1e-9)
	assert_almost_eq(
		result["source_power"], result["dissipated_power"] + result["stored_power"], 1e-9
	)


func test_a_store_never_drains_below_empty():
	# A nearly-empty store into a dead, low-resistance source: 0.12 V across
	# 0.002 ohm is 60 A, -7.2 W, and a thousand seconds of that would take
	# the level thousands of joules below zero. It stops at empty.
	var result := _solved([_source("s", 0.0, 0.001), _store("cell", 1000.0, 12.0, 10.0, 0.001)], 1000.0)
	assert_eq(result["stores"]["cell"]["level"], 0.0)
	assert_true(result["stores"]["cell"]["depleted"])


func test_a_charged_store_behind_a_generator_motors_the_shaft_when_the_river_stops():
	# Standard_model.md worked example D, series form: with the source dead
	# the store's effort reflects through the gyrator as a NEGATIVE offset on
	# the shaft side -- it turns the shaft. The generator is a motor now, and
	# no rule said so.
	var result := _solved([_source("river", 0.0, 1.0), _gyrate("dynamo", 2.0), _store("cell", 1000.0, 12.0, 1000.0, 0.5)], 1.0)
	assert_gt(result["source_flow"], 0.0, "the shaft turns with the river stopped")
	assert_lt(result["stored_power"], 0.0, "the store is draining")
	assert_lt(result["source_power"], 0.0, "the dead source is absorbing power")
	assert_almost_eq(
		result["source_power"], result["dissipated_power"] + result["stored_power"], 1e-9
	)
