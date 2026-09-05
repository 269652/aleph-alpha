extends GutTest

## Red-first spec for the five element laws of docs/concept/standard_model.md
## ("The formal model / 3. The element algebra"): source, resist, transform,
## gyrate, store as pure functions, plus the two affine-load reflection rules
## the series solver is built from.
##
## The anchor properties are LOSSLESSNESS (a transformer and a gyrator pass
## power through exactly) and the reflection CONSISTENCY checks (a load
## reflected upstream reproduces the downstream relation once pushed back
## through the element). If either ever breaks, energy is being made or lost
## by the algebra itself, and no device built on it can be trusted.

const DeviceElements = preload("res://src/gameplay/device_elements.gd")


# --- the closed set of kinds --------------------------------------------------

func test_the_five_kinds_in_a_fixed_order():
	assert_eq(DeviceElements.KINDS, ["source", "resist", "transform", "gyrate", "store"])


func test_one_port_and_two_port_kinds():
	for kind in ["source", "resist", "store"]:
		assert_false(DeviceElements.is_two_port(kind), kind)
	for kind in ["transform", "gyrate"]:
		assert_true(DeviceElements.is_two_port(kind), kind)
	assert_false(DeviceElements.is_two_port("bogus"))


# --- power -------------------------------------------------------------------

func test_power_is_effort_times_flow():
	assert_almost_eq(DeviceElements.power(3.0, 4.0), 12.0, 1e-9)
	assert_almost_eq(DeviceElements.power(3.0, -4.0), -12.0, 1e-9)


# --- transform: e2 = r e1, f2 = f1 / r ---------------------------------------

func test_a_transformer_multiplies_effort_and_divides_flow_by_its_ratio():
	var out: Dictionary = DeviceElements.transform_out(10.0, 2.0, 4.0)
	assert_almost_eq(out["effort"], 40.0, 1e-9)
	assert_almost_eq(out["flow"], 0.5, 1e-9)


func test_a_transformer_is_lossless_across_a_sweep():
	for ratio in [0.1, 0.5, 1.0, 2.0, 7.25]:
		for effort in [0.0, 1.5, 300.0]:
			for flow in [-2.0, 0.3, 12.0]:
				var out: Dictionary = DeviceElements.transform_out(effort, flow, ratio)
				assert_almost_eq(
					DeviceElements.power(out["effort"], out["flow"]),
					DeviceElements.power(effort, flow), 1e-9,
					"r=%s e=%s f=%s" % [ratio, effort, flow]
				)


func test_a_unit_transformer_is_a_rigid_coupling():
	var out: Dictionary = DeviceElements.transform_out(10.0, 2.0, 1.0)
	assert_almost_eq(out["effort"], 10.0, 1e-9)
	assert_almost_eq(out["flow"], 2.0, 1e-9)


# --- gyrate: e2 = k f1, f2 = e1 / k -------------------------------------------

func test_a_gyrator_turns_flow_into_effort_and_effort_into_flow():
	var out: Dictionary = DeviceElements.gyrate_out(10.0, 2.0, 4.0)
	assert_almost_eq(out["effort"], 8.0, 1e-9)
	assert_almost_eq(out["flow"], 2.5, 1e-9)


func test_a_gyrator_is_lossless_across_a_sweep():
	for ratio in [0.1, 0.5, 1.0, 2.0, 7.25]:
		for effort in [0.0, 1.5, 300.0]:
			for flow in [-2.0, 0.3, 12.0]:
				var out: Dictionary = DeviceElements.gyrate_out(effort, flow, ratio)
				assert_almost_eq(
					DeviceElements.power(out["effort"], out["flow"]),
					DeviceElements.power(effort, flow), 1e-9,
					"k=%s e=%s f=%s" % [ratio, effort, flow]
				)


# --- resist: e = R f ---------------------------------------------------------

func test_a_resistor_drops_effort_in_proportion_to_flow_and_dissipates_it():
	assert_almost_eq(DeviceElements.resist_effort(5.0, 3.0), 15.0, 1e-9)
	assert_almost_eq(DeviceElements.dissipated(5.0, 3.0), 45.0, 1e-9)
	# Dissipation never goes negative: a backwards flow still heats the wire.
	assert_almost_eq(DeviceElements.dissipated(5.0, -3.0), 45.0, 1e-9)


# --- source: a Thevenin pair ---------------------------------------------------

func test_a_source_terminal_effort_sags_with_the_flow_it_delivers():
	assert_almost_eq(DeviceElements.source_terminal_effort(100.0, 10.0, 0.0), 100.0, 1e-9)
	assert_almost_eq(DeviceElements.source_terminal_effort(100.0, 10.0, 4.0), 60.0, 1e-9)


func test_a_source_free_running_flow_is_where_its_terminal_effort_reaches_zero():
	assert_almost_eq(DeviceElements.source_free_flow(100.0, 10.0), 10.0, 1e-9)
	assert_almost_eq(
		DeviceElements.source_terminal_effort(100.0, 10.0, DeviceElements.source_free_flow(100.0, 10.0)),
		0.0, 1e-9
	)


func test_a_source_maximum_deliverable_power_is_the_matched_load_figure():
	# e0^2 / (4 R): 100 V behind 10 ohms can deliver at most 250 W.
	assert_almost_eq(DeviceElements.source_max_power(100.0, 10.0), 250.0, 1e-9)


func test_an_ideal_source_has_no_ceiling_on_power():
	assert_eq(DeviceElements.source_max_power(100.0, 0.0), INF)
	assert_eq(DeviceElements.source_free_flow(100.0, 0.0), INF)


# --- store: a linear capacitor -----------------------------------------------

func test_a_store_effort_rises_linearly_with_its_level():
	assert_almost_eq(DeviceElements.store_effort(1000.0, 12.0, 0.0), 0.0, 1e-9)
	assert_almost_eq(DeviceElements.store_effort(1000.0, 12.0, 500.0), 6.0, 1e-9)
	assert_almost_eq(DeviceElements.store_effort(1000.0, 12.0, 1000.0), 12.0, 1e-9)


func test_a_store_with_no_capacity_has_no_effort_rather_than_dividing_by_zero():
	assert_eq(DeviceElements.store_effort(0.0, 12.0, 0.0), 0.0)


# --- affine loads and the two reflection rules --------------------------------

func test_series_composition_adds_resistance_and_opposing_effort():
	var load: Dictionary = DeviceElements.closed_load()
	load = DeviceElements.in_series(load, 3.0, 0.0)
	load = DeviceElements.in_series(load, 4.0, 2.5)
	assert_almost_eq(load["resistance"], 7.0, 1e-9)
	assert_almost_eq(load["effort"], 2.5, 1e-9)


func test_a_load_seen_through_a_transformer_scales_as_one_over_ratio_squared():
	# A lever with ratio 2 doubles effort and halves flow, so the load on its
	# far side feels a QUARTER as stiff from the near side.
	var reflected: Dictionary = DeviceElements.reflect_through_transform(
		DeviceElements.affine_load(8.0, 4.0), 2.0
	)
	assert_almost_eq(reflected["resistance"], 2.0, 1e-9)
	assert_almost_eq(reflected["effort"], 2.0, 1e-9)


func test_a_load_seen_through_a_gyrator_becomes_a_conductance_with_a_flipped_offset():
	var reflected: Dictionary = DeviceElements.reflect_through_gyrate(
		DeviceElements.affine_load(8.0, 4.0), 2.0
	)
	# k^2 / R and -k e0 / R
	assert_almost_eq(reflected["resistance"], 0.5, 1e-9)
	assert_almost_eq(reflected["effort"], -1.0, 1e-9)


## The consistency property that makes the reflection rules the solver: pick
## an upstream (e1, f1) on the reflected line, push it through the element,
## and the downstream point must sit exactly on the original load's line.
func test_reflection_through_a_transformer_is_consistent_with_its_law():
	for ratio in [0.25, 1.0, 3.0]:
		for resistance in [0.5, 8.0]:
			for offset in [0.0, 4.0]:
				var load: Dictionary = DeviceElements.affine_load(resistance, offset)
				var reflected: Dictionary = DeviceElements.reflect_through_transform(load, ratio)
				var flow_in := 1.7
				var effort_in: float = reflected["resistance"] * flow_in + reflected["effort"]
				var out: Dictionary = DeviceElements.transform_out(effort_in, flow_in, ratio)
				assert_almost_eq(
					out["effort"], resistance * out["flow"] + offset, 1e-9,
					"r=%s R=%s e0=%s" % [ratio, resistance, offset]
				)


func test_reflection_through_a_gyrator_is_consistent_with_its_law():
	for ratio in [0.25, 1.0, 3.0]:
		for resistance in [0.5, 8.0]:
			for offset in [0.0, 4.0]:
				var load: Dictionary = DeviceElements.affine_load(resistance, offset)
				var reflected: Dictionary = DeviceElements.reflect_through_gyrate(load, ratio)
				var flow_in := 1.7
				var effort_in: float = reflected["resistance"] * flow_in + reflected["effort"]
				var out: Dictionary = DeviceElements.gyrate_out(effort_in, flow_in, ratio)
				assert_almost_eq(
					out["effort"], resistance * out["flow"] + offset, 1e-9,
					"k=%s R=%s e0=%s" % [ratio, resistance, offset]
				)


## An open output stays open through a transformer (nothing flows) and becomes
## a SHORT through a gyrator: an unloaded generator spins freely and pushes
## back with no torque at all. Electromagnetism.md's "an open circuit simply
## does nothing" is this arithmetic, not a special case.
func test_an_open_end_stays_open_through_a_transformer_and_vanishes_through_a_gyrator():
	var open: Dictionary = DeviceElements.open_load()
	assert_eq(open["resistance"], INF)
	assert_eq(DeviceElements.reflect_through_transform(open, 2.0)["resistance"], INF)
	var through_gyrator: Dictionary = DeviceElements.reflect_through_gyrate(open, 2.0)
	assert_almost_eq(through_gyrator["resistance"], 0.0, 1e-12)
	assert_almost_eq(through_gyrator["effort"], 0.0, 1e-12)


func test_series_composition_onto_an_open_end_stays_open():
	var load: Dictionary = DeviceElements.in_series(DeviceElements.open_load(), 3.0, 1.0)
	assert_eq(load["resistance"], INF)


# --- validation: every parameter named, nothing defaulted ---------------------

func test_required_parameters_per_kind():
	assert_eq(DeviceElements.required_params("source"), ["effort", "resistance"])
	assert_eq(DeviceElements.required_params("resist"), ["resistance"])
	assert_eq(DeviceElements.required_params("transform"), ["ratio"])
	assert_eq(DeviceElements.required_params("gyrate"), ["ratio"])
	assert_eq(DeviceElements.required_params("store"), ["capacity", "full_effort"])
	assert_eq(DeviceElements.required_params("bogus"), [])


func test_a_well_formed_element_validates_clean():
	assert_eq(DeviceElements.validation_error("resist", {"resistance": 12.0}), "")
	assert_eq(DeviceElements.validation_error("source", {"effort": 10.0, "resistance": 0.0}), "")
	assert_eq(DeviceElements.validation_error("transform", {"ratio": 0.5}), "")
	assert_eq(DeviceElements.validation_error("store", {"capacity": 100.0, "full_effort": 12.0}), "")


func test_validation_names_the_missing_parameter():
	var reason: String = DeviceElements.validation_error("resist", {})
	assert_true(reason.contains("resistance"), reason)
	assert_true(DeviceElements.validation_error("store", {"capacity": 1.0}).contains("full_effort"))


func test_validation_rejects_an_unknown_kind_by_name():
	assert_true(DeviceElements.validation_error("bogus", {}).contains("bogus"))


func test_validation_rejects_impossible_values():
	assert_ne(DeviceElements.validation_error("transform", {"ratio": 0.0}), "")
	assert_ne(DeviceElements.validation_error("gyrate", {"ratio": -1.0}), "")
	assert_ne(DeviceElements.validation_error("resist", {"resistance": -1.0}), "")
	assert_ne(DeviceElements.validation_error("source", {"effort": 1.0, "resistance": -1.0}), "")
	assert_ne(DeviceElements.validation_error("store", {"capacity": 0.0, "full_effort": 1.0}), "")
	# A store may start part-full, but never fuller than it can hold.
	assert_ne(DeviceElements.validation_error(
		"store", {"capacity": 10.0, "full_effort": 1.0, "level": 11.0}
	), "")
	assert_eq(DeviceElements.validation_error(
		"store", {"capacity": 10.0, "full_effort": 1.0, "level": 10.0}
	), "")
