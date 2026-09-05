extends GutTest

## Red-first spec for docs/concept/standard_model.md's derivation table
## ("6. Derived, not authored"): the functions that read an element's
## parameters off a part's real material and geometry, or off a real fluid,
## instead of letting an author type them.
##
## Every number asserted below is a published figure or the arithmetic of
## one: 100 %IACS is 5.80e7 S/m by definition, a flat plate's drag
## coefficient is 1.28, water is 1000 kg/m^3 and sea-level air 1.225.

const DevicePhysics = preload("res://src/gameplay/device_physics.gd")
const DeviceElements = preload("res://src/gameplay/device_elements.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")
const ItemPart = preload("res://src/gameplay/item_part.gd")
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")


# --- conductivity, inverted out of the shipped 0-10 scalar --------------------

func test_the_iacs_definition_is_the_published_one():
	assert_eq(DevicePhysics.IACS_SIEMENS_PER_M, 5.80e7)


func test_copper_comes_back_as_exactly_the_iacs_standard():
	# The table's conductivity column IS %IACS through a linear map; running
	# it backwards must land copper on the definition itself.
	assert_almost_eq(DevicePhysics.conductivity_s_per_m("copper") / 5.80e7, 1.0, 1e-6)


func test_metals_keep_their_published_ordering_and_ratios():
	var copper: float = DevicePhysics.conductivity_s_per_m("copper")
	var silver: float = DevicePhysics.conductivity_s_per_m("silver")
	var iron: float = DevicePhysics.conductivity_s_per_m("iron")
	# To the precision the table is STORED at: MATERIALS' conductivity column
	# carries six decimals (iron's 1.485714 for 1.4857142857...), so the
	# inversion reproduces a published ratio to a few parts in ten million,
	# not to the last bit. 1e-5 on a ratio of ~6.4 states that honestly.
	assert_almost_eq(silver / copper, MaterialProperties.IACS_PERCENT["silver"] / 100.0, 1e-5)
	assert_almost_eq(copper / iron, 100.0 / MaterialProperties.IACS_PERCENT["iron"], 1e-5)


func test_wood_does_not_conduct_by_twenty_orders_of_magnitude():
	# electromagnetism.md: "wood or stone simply doesn't conduct and can't
	# complete a circuit at all". Now arithmetic.
	assert_lt(DevicePhysics.conductivity_s_per_m("wood"), 1e-10)
	assert_lt(DevicePhysics.conductivity_s_per_m("stone"), 1e-3)


func test_an_unmodeled_material_has_no_conductivity():
	assert_eq(DevicePhysics.conductivity_s_per_m("unobtainium"), 0.0)


# --- a wire's resistance: Pouillet's law over real geometry -------------------

func test_ten_metres_of_three_millimetre_copper_wire_is_a_few_hundredths_of_an_ohm():
	# R = L / (sigma A): 10 m / (5.80e7 S/m * pi * (0.0015 m)^2) = 0.0244 ohm.
	assert_almost_eq(DevicePhysics.wire_resistance_ohms("copper", 1000.0, 0.3), 0.0244, 0.0002)


func test_iron_wire_is_worse_than_copper_by_exactly_the_published_iacs_ratio():
	var copper: float = DevicePhysics.wire_resistance_ohms("copper", 1000.0, 0.3)
	var iron: float = DevicePhysics.wire_resistance_ohms("iron", 1000.0, 0.3)
	# Same six-decimal table precision as test_metals_keep_their_published_ordering_and_ratios.
	assert_almost_eq(iron / copper, 100.0 / MaterialProperties.IACS_PERCENT["iron"], 1e-5)


func test_a_wooden_wire_cannot_complete_a_circuit():
	assert_gt(DevicePhysics.wire_resistance_ohms("wood", 100.0, 1.0), 1e15)


func test_an_unmodeled_wire_has_infinite_resistance_rather_than_a_guess():
	assert_eq(DevicePhysics.wire_resistance_ohms("unobtainium", 100.0, 1.0), INF)


func test_resistance_grows_with_length_and_shrinks_with_section():
	var base: float = DevicePhysics.wire_resistance_ohms("copper", 100.0, 0.2)
	assert_almost_eq(DevicePhysics.wire_resistance_ohms("copper", 300.0, 0.2) / base, 3.0, 1e-9)
	# Doubling the diameter quadruples the section.
	assert_almost_eq(DevicePhysics.wire_resistance_ohms("copper", 100.0, 0.4) / base, 0.25, 1e-9)


func test_a_wire_part_derives_its_resistance_from_its_own_span_and_section():
	var wire: RefCounted = ItemPart.new(
		"copper", ItemPart.GEOMETRY_HAFT, ItemPart.ROLE_STRUCTURE,
		{"length_cm": 1000.0, "diameter_cm": 0.3}
	)
	assert_true(DevicePhysics.can_derive_resistance(wire))
	assert_almost_eq(
		DevicePhysics.wire_resistance_of_part(wire),
		DevicePhysics.wire_resistance_ohms("copper", 1000.0, 0.3), 1e-12
	)


func test_only_a_haft_is_a_wire():
	# A wedge or a slab has a section, but "a wire" is a cylinder; deriving a
	# resistance for a blade would be a confident number for a thing that is
	# not a conductor run. The compiler asks this before deriving.
	var blade: RefCounted = ItemPart.new(
		"copper", ItemPart.GEOMETRY_EDGE, ItemPart.ROLE_WORKING,
		{"length_cm": 10.0, "width_cm": 2.0, "thickness_cm": 0.3, "angle_deg": 20.0}
	)
	assert_false(DevicePhysics.can_derive_resistance(blade))
	assert_eq(DevicePhysics.wire_resistance_of_part(blade), INF)


# --- a wheel's ratio: its radius --------------------------------------------

func test_a_wheel_ratio_is_its_radius_in_metres():
	var wheel: RefCounted = ItemPart.new(
		"wood", ItemPart.GEOMETRY_FACE, ItemPart.ROLE_WORKING,
		{"width_cm": 200.0, "height_cm": 200.0, "thickness_cm": 4.0}
	)
	assert_almost_eq(DevicePhysics.wheel_radius_m(wheel), 1.0, 1e-9)


func test_a_wheel_ratio_turns_force_into_torque_at_the_rim():
	# tau = F r and omega = v / r are the two lines of the transformer law with
	# the radius as the ratio -- electromagnetism.md's "leverage in reverse".
	var out: Dictionary = DeviceElements.transform_out(100.0, 1.5, 0.5)
	assert_almost_eq(out["effort"], 50.0, 1e-9)
	assert_almost_eq(out["flow"], 3.0, 1e-9)


# --- the paddle source: momentum flux, as a Thevenin pair ---------------------

func test_the_flat_plate_drag_coefficient_is_the_published_one():
	assert_eq(DevicePhysics.FLAT_PLATE_DRAG_COEFFICIENT, 1.28)


func test_fluid_densities_are_the_shipped_water_figure_and_sea_level_air():
	assert_eq(DevicePhysics.fluid_density("water"), OpenChannelFlow.WATER_DENSITY_KG_M3)
	assert_eq(DevicePhysics.fluid_density("air"), 1.225)
	assert_eq(DevicePhysics.fluid_density("aether"), 0.0)


func test_half_a_square_metre_of_paddle_in_a_river_stalls_at_the_drag_force():
	# 0.5 * 1000 * 1.28 * 0.5 * 1.5^2 = 720 N
	var source: Dictionary = DevicePhysics.paddle_source(1000.0, 0.5, 1.5)
	assert_almost_eq(source["effort"], 720.0, 1e-6)
	assert_almost_eq(source["resistance"], 480.0, 1e-6)


func test_a_paddle_runs_free_at_exactly_the_stream_speed():
	var source: Dictionary = DevicePhysics.paddle_source(1000.0, 0.5, 1.5)
	assert_almost_eq(
		DeviceElements.source_free_flow(source["effort"], source["resistance"]), 1.5, 1e-9
	)


func test_the_paddle_can_deliver_at_most_a_quarter_of_stall_force_times_stream_speed():
	var source: Dictionary = DevicePhysics.paddle_source(1000.0, 0.5, 1.5)
	assert_almost_eq(
		DeviceElements.source_max_power(source["effort"], source["resistance"]),
		720.0 * 1.5 / 4.0, 1e-6
	)


func test_the_same_paddle_in_air_pushes_less_by_exactly_the_density_ratio():
	var water: Dictionary = DevicePhysics.paddle_source(1000.0, 0.5, 1.5)
	var air: Dictionary = DevicePhysics.paddle_source(1.225, 0.5, 1.5)
	assert_almost_eq(water["effort"] / air["effort"], 1000.0 / 1.225, 1e-6)


func test_a_still_stream_pushes_nothing():
	var source: Dictionary = DevicePhysics.paddle_source(1000.0, 0.5, 0.0)
	assert_eq(source["effort"], 0.0)
	assert_eq(source["resistance"], 0.0)


# --- Faraday's constant for a rotating coil -----------------------------------

func test_the_gyrator_ratio_is_field_times_area_times_turns():
	assert_almost_eq(DevicePhysics.faraday_ratio(0.5, 200, 0.02), 2.0, 1e-9)
