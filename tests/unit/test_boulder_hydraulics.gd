extends GutTest

## The force balance on a rock standing in a current -- see
## boulder_hydraulics.gd and docs/concept/rivers.md's "Boulders are
## hydrology" section. The water pushes with real dynamic-pressure drag;
## the rock resists with its real submerged weight times bed friction. A
## boulder holds because its resistance exceeds the drag, and THAT is why
## the water has to bend around it. Every number here is a textbook
## constant, checked against real cases (a metre boulder in an ordinary
## reach holds; a thirty-centimetre one in a flood does not -- which is
## what bedload transport actually does).

const BoulderHydraulics = preload("res://src/world/boulder_hydraulics.gd")
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")
const StoneSize = preload("res://src/world/stone_size.gd")


# -- the water's push --------------------------------------------------------

func test_dynamic_pressure_is_half_rho_v_squared():
	assert_almost_eq(
		BoulderHydraulics.dynamic_pressure_pa(2.0),
		0.5 * OpenChannelFlow.WATER_DENSITY_KG_M3 * 4.0, 1e-6
	)
	assert_eq(BoulderHydraulics.dynamic_pressure_pa(0.0), 0.0)


func test_drag_grows_with_the_square_of_the_current():
	var slow := BoulderHydraulics.drag_force_newtons(1.0, 100.0, 2.0)
	var fast := BoulderHydraulics.drag_force_newtons(2.0, 100.0, 2.0)
	assert_gt(slow, 0.0)
	assert_almost_eq(fast, slow * 4.0, 1e-6, "doubling the current quadruples the push")


func test_still_or_dry_water_pushes_nothing():
	assert_eq(BoulderHydraulics.drag_force_newtons(0.0, 100.0, 2.0), 0.0)
	assert_eq(BoulderHydraulics.drag_force_newtons(1.5, 100.0, 0.0), 0.0)


func test_a_rock_taller_than_the_water_only_takes_drag_on_its_wet_part():
	var shallow := BoulderHydraulics.drag_force_newtons(1.0, 200.0, 0.5)
	var drowned := BoulderHydraulics.drag_force_newtons(1.0, 200.0, 2.0)
	assert_lt(shallow, drowned, "the dry top of a rock is not in the current")
	assert_almost_eq(
		shallow, drowned * 0.25, 1e-6,
		"a quarter submerged, a quarter of the frontal area"
	)
	assert_almost_eq(
		BoulderHydraulics.drag_force_newtons(1.0, 200.0, 5.0), drowned, 1e-6,
		"deeper water past the rock's top adds no area"
	)


# -- the rock's resistance ---------------------------------------------------

func test_submerged_weight_is_lighter_than_dry_weight_but_never_negative():
	var dry := StoneSize.mass_kg_for(100.0) * OpenChannelFlow.GRAVITY_M_S2
	var wet := BoulderHydraulics.submerged_weight_newtons(100.0, 2.0)
	assert_gt(wet, 0.0)
	assert_lt(wet, dry, "buoyancy takes some of the weight")
	# Granite at 2.7 loses 1/2.7 of its weight fully submerged.
	assert_almost_eq(wet, dry * (1.0 - 1000.0 / 2700.0), 1e-3)


func test_a_rock_standing_out_of_the_water_loses_less_to_buoyancy():
	var drowned := BoulderHydraulics.submerged_weight_newtons(200.0, 5.0)
	var half_out := BoulderHydraulics.submerged_weight_newtons(200.0, 1.0)
	assert_gt(half_out, drowned, "only the wet half is buoyed")


func test_resistance_is_friction_on_the_submerged_weight():
	var weight := BoulderHydraulics.submerged_weight_newtons(80.0, 1.0)
	assert_almost_eq(
		BoulderHydraulics.resisting_force_newtons(80.0, 1.0),
		weight * BoulderHydraulics.BED_FRICTION_COEFFICIENT, 1e-6
	)
	assert_between(BoulderHydraulics.BED_FRICTION_COEFFICIENT, 0.4, 0.8, "loose rock on a bed: tan of the angle of repose")


# -- the balance -------------------------------------------------------------

func test_a_metre_boulder_in_an_ordinary_reach_holds_easily():
	var load := BoulderHydraulics.current_load(1.0, 100.0, 1.0)
	assert_lt(load, 0.1, "a metre of granite barely notices a 1 m/s current (load %.3f)" % load)
	assert_true(BoulderHydraulics.holds(1.0, 100.0, 1.0))


func test_a_small_boulder_in_a_flood_is_swept():
	# Thirty centimetres is a boulder on the Wentworth scale, and a 3 m/s
	# flood moves it -- which is exactly what bedload transport does.
	var load := BoulderHydraulics.current_load(3.0, 30.0, 1.0)
	assert_gt(load, 1.0, "a 30 cm rock cannot hold a 3 m/s flood (load %.3f)" % load)
	assert_false(BoulderHydraulics.holds(3.0, 30.0, 1.0))
	assert_true(BoulderHydraulics.holds(1.0, 30.0, 1.0), "but it holds an ordinary current")


func test_load_rises_with_the_current_and_falls_with_the_rock():
	assert_gt(BoulderHydraulics.current_load(2.0, 50.0, 1.0), BoulderHydraulics.current_load(1.0, 50.0, 1.0))
	assert_gt(BoulderHydraulics.current_load(1.0, 50.0, 1.0), BoulderHydraulics.current_load(1.0, 100.0, 1.0))


func test_holds_is_exactly_load_under_one():
	for speed in [0.5, 1.5, 2.5, 3.5]:
		for diameter in [30.0, 60.0, 120.0]:
			assert_eq(
				BoulderHydraulics.holds(speed, diameter, 1.0),
				BoulderHydraulics.current_load(speed, diameter, 1.0) < 1.0
			)


func test_a_rock_in_no_water_has_no_load_at_all():
	assert_eq(BoulderHydraulics.current_load(2.0, 60.0, 0.0), 0.0)
	assert_true(BoulderHydraulics.holds(2.0, 60.0, 0.0))
