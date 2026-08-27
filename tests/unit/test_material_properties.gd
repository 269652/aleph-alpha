extends GutTest

var MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")

var mp: RefCounted


func before_each() -> void:
	mp = MaterialProperties.new()


func test_wood_density_exact() -> void:
	assert_almost_eq(mp.property_value("wood", "density"), 0.6, 0.0001)


func test_wood_is_less_dense_than_water() -> void:
	assert_true(mp.property_value("wood", "density") < 1.0, "wood should float")


func test_stone_is_denser_than_water() -> void:
	assert_true(mp.property_value("stone", "density") > 1.0, "stone should sink")


func test_obsidian_toughness_exact() -> void:
	assert_almost_eq(mp.property_value("obsidian", "toughness"), 1.0, 0.0001)


func test_obsidian_sharpness_capacity_exact() -> void:
	assert_almost_eq(mp.property_value("obsidian", "sharpness_capacity"), 10.0, 0.0001)


func test_iron_hardness_exceeds_wood_hardness() -> void:
	assert_true(mp.property_value("iron", "hardness") > mp.property_value("wood", "hardness"))


func test_fiber_toughness_exact() -> void:
	assert_almost_eq(mp.property_value("fiber", "toughness"), 7.0, 0.0001)


func test_unknown_material_defaults_density_to_one() -> void:
	assert_almost_eq(mp.property_value("unobtainium", "density"), 1.0, 0.0001)


## Was test_unknown_material_defaults_hardness_to_one. The default moved to 0.0
## when the hardness column became real Vickers, because 1.0 stopped meaning
## "the bottom of a legibility scale" and started meaning 100 HV -- wrought
## iron, and the exact "hard" cutoff. See
## test_an_unmodeled_material_is_not_assumed_to_be_hard for the full argument;
## it is the same one DEFAULT_PROPERTIES' conductivity entry already carries.
func test_unknown_material_defaults_hardness_to_zero() -> void:
	assert_almost_eq(mp.property_value("unobtainium", "hardness"), 0.0, 0.0001)


func test_unknown_property_on_known_material_defaults_to_one() -> void:
	assert_almost_eq(mp.property_value("wood", "made_up_property"), 1.0, 0.0001)


func test_wood_is_viable_raft_material() -> void:
	assert_true(mp.is_viable_for_tool("wood", "raft"))


func test_iron_is_not_viable_raft_material() -> void:
	assert_false(mp.is_viable_for_tool("iron", "raft"))


func test_stone_is_not_viable_raft_material() -> void:
	assert_false(mp.is_viable_for_tool("stone", "raft"))


func test_fiber_is_viable_grapple_rope_material() -> void:
	assert_true(mp.is_viable_for_tool("fiber", "grapple_rope"))


func test_obsidian_is_not_viable_grapple_rope_material() -> void:
	assert_false(mp.is_viable_for_tool("obsidian", "grapple_rope"))


func test_unknown_tool_type_is_never_viable() -> void:
	assert_false(mp.is_viable_for_tool("wood", "spaceship"))


# -- real mass, for the shared momentum model (docs/concept/materials.md's --
# -- momentum = mass * velocity, see impact_resolver.gd/throwable.gd) -------
#
# mass_kg_for(material, volume_cm3) = density (already real g/cm^3, since
# it's expressed relative to water == 1.0 g/cm^3) x volume, generalizing
# StoneSize.mass_kg_for's "density x volume" shape to an arbitrary item
# rather than a sphere specifically -- so a sword/axe/club can get a real
## mass from the SAME shared density table stone already uses.

func test_mass_kg_for_matches_density_times_volume() -> void:
	# iron's density (7.8) x a 100cm^3 volume = 780g = 0.78kg.
	assert_almost_eq(mp.mass_kg_for("iron", 100.0), 0.78, 0.0001)


func test_mass_kg_for_scales_with_volume() -> void:
	assert_almost_eq(mp.mass_kg_for("iron", 200.0), mp.mass_kg_for("iron", 100.0) * 2.0, 0.0001)


func test_mass_kg_for_a_denser_material_masses_more_at_the_same_volume() -> void:
	assert_gt(mp.mass_kg_for("iron", 100.0), mp.mass_kg_for("wood", 100.0))


func test_mass_kg_for_zero_volume_is_zero_mass() -> void:
	assert_almost_eq(mp.mass_kg_for("iron", 0.0), 0.0, 0.0001)


# -- timber (docs/concept/timber_construction.md): a real MATERIALS entry for
# -- BuildingPiece.MATERIAL_TIMBER, previously absent and silently falling
# -- back to DEFAULT_PROPERTIES' decay_rate=1.0 (stone-like) -- almost
# -- certainly wrong for a worked-but-still-organic material. See
# -- material_properties.gd's own "timber" entry doc comment for the full
# -- real-world grounding.

func test_timber_decay_rate_is_pinned() -> void:
	assert_almost_eq(mp.property_value("timber", "decay_rate"), 4.0, 0.0001)


func test_timber_decays_slower_than_raw_wood_but_faster_than_stone() -> void:
	var timber_rate: float = mp.property_value("timber", "decay_rate")
	assert_lt(
		timber_rate, mp.property_value("wood", "decay_rate"),
		"seasoned, squared timber should resist decay better than raw green wood"
	)
	assert_gt(
		timber_rate, mp.property_value("stone", "decay_rate"),
		"timber is still organic -- nowhere near stone's near-permanence"
	)


func test_timber_shares_every_other_property_with_wood() -> void:
	for property_name in [
		"density", "hardness", "toughness", "elasticity",
		"sharpness_capacity", "flammability", "conductivity",
	]:
		assert_almost_eq(
			mp.property_value("timber", property_name), mp.property_value("wood", property_name), 0.0001,
			"timber is the same wood, just worked/seasoned -- only decay_rate should differ"
		)


# -- plain-language descriptors (docs/concept/materials.md, "Learning an ------
# -- emergent system") ------------------------------------------------------
#
# That section specifies descriptors + discovery as the player-facing default,
# NOT a raw scalar spreadsheet, so the 8-scalar property vector reaches an item
# tooltip as words ("Iron - hard, keen") rather than numbers. Every threshold
# below is a named constant with its own calibration test, and the two lines
# the game has ALREADY calibrated elsewhere are reused rather than re-guessed.

func test_iron_and_stone_read_as_hard_but_wood_does_not() -> void:
	assert_true(mp.descriptors_for("iron").has("hard"), "iron (100 HV) should read as hard")
	assert_true(mp.descriptors_for("stone").has("hard"), "stone (700 HV) should read as hard")
	assert_false(mp.descriptors_for("wood").has("hard"), "wood (3.7 HV) should not read as hard")


func test_obsidian_and_iron_read_as_keen_but_stone_does_not() -> void:
	assert_true(mp.descriptors_for("obsidian").has("keen"), "obsidian (sharpness 10) takes a keen edge")
	assert_true(mp.descriptors_for("iron").has("keen"), "iron (sharpness 8) takes a keen edge")
	assert_false(mp.descriptors_for("stone").has("keen"), "stone (sharpness 4) does not take a keen edge")


## The "brittle" word must mean exactly what the impact model already means by
## it -- one cutoff, not two that can silently drift apart.
func test_the_brittle_descriptor_uses_the_same_toughness_cutoff_the_impact_model_does() -> void:
	var ImpactResolver := preload("res://src/gameplay/impact_resolver.gd")
	assert_eq(MaterialProperties.BRITTLE_TOUGHNESS, ImpactResolver.T_BRITTLE_TOUGHNESS,
		"the brittle descriptor and the impact model must share one toughness cutoff")
	assert_true(mp.descriptors_for("obsidian").has("brittle"), "obsidian (toughness 1) is brittle")
	assert_false(mp.descriptors_for("iron").has("brittle"), "iron (toughness 7) is not brittle")


## "buoyant" is the raft-viability line the game already calibrated, reused --
## see is_viable_for_tool / WATER_DENSITY.
func test_wood_and_fiber_read_as_buoyant_at_the_water_density_line() -> void:
	assert_true(mp.descriptors_for("wood").has("buoyant"), "wood floats")
	assert_true(mp.descriptors_for("fiber").has("buoyant"), "fiber floats")
	assert_false(mp.descriptors_for("iron").has("buoyant"), "iron does not float")
	assert_eq(MaterialProperties.WATER_DENSITY, 1.0,
		"the buoyant descriptor rides on the existing water-density cutoff")


## A material with nothing notable says nothing -- an empty list, not a row of
## hedged words.
func test_flesh_has_no_notable_descriptors() -> void:
	assert_eq(mp.descriptors_for("flesh"), [] as Array[String])


func test_an_unknown_material_has_no_descriptors() -> void:
	assert_eq(mp.descriptors_for("not_a_material"), [] as Array[String])


# -- copper / tin / carbon: the three rows alloy_blend.gd needs ---------------
#
# docs/concept/smelting.md's "Alloying: emergent metallurgy" names the gap
# outright -- "copper itself has no property vector yet ... bronze can't be
# computed without it" -- and tin/carbon are the two solutes that make the
# blend space a space at all (bronze, steel). Densities are literal real
# g/cm^3 like every other row; the 0-10 scalars are placed against the rows
# that already exist, with the reasoning in each entry's doc comment.

func test_copper_density_is_the_real_measured_value() -> void:
	assert_almost_eq(mp.property_value("copper", "density"), 8.96, 0.0001,
		"copper is 8.96 g/cm^3 -- denser than iron, which the density column must show")


func test_tin_density_is_the_real_measured_value() -> void:
	assert_almost_eq(mp.property_value("tin", "density"), 7.31, 0.0001)


func test_graphite_carbon_density_is_the_real_measured_value() -> void:
	assert_almost_eq(mp.property_value("carbon", "density"), 2.26, 0.0001)


## The whole reason the Bronze Age needed tin: pure copper is too soft to hold
## a working edge. Copper must sit below stone, or a copper knife would already
## beat the flint one it historically did not.
func test_pure_copper_is_softer_than_stone_and_iron() -> void:
	assert_lt(mp.property_value("copper", "hardness"), mp.property_value("stone", "hardness"),
		"a pure copper edge loses to a knapped flint one -- that is why the Bronze Age needed tin")
	assert_lt(mp.property_value("copper", "hardness"), mp.property_value("iron", "hardness"))


## Copper is the most ductile of the game's metals (annealed elongation ~45%
## against wrought iron's ~25%) and the best conductor there is (59.6 MS/m
## against iron's 10.0) -- it is the benchmark both columns are scaled to.
func test_copper_is_the_toughest_and_most_conductive_metal_in_the_table() -> void:
	assert_gt(mp.property_value("copper", "toughness"), mp.property_value("iron", "toughness"))
	assert_gt(mp.property_value("copper", "conductivity"), mp.property_value("iron", "conductivity"))


## Tin is soft enough to mark with a fingernail (Mohs 1.5, ~5 HV against
## copper's ~50) and takes no edge at all.
##
## This used to assert tin is softer than WOOD, and the real numbers say it is
## not: pure tin measures ~5 HV against red oak's Brinell 3.7. That was a Mohs
## intuition (tin 1.5, wood ~2.5) standing in for an indentation measurement,
## and scratch hardness and indentation hardness genuinely disagree about a
## porous cellular solid -- oak resists a scratch better than tin and a punch
## worse. The claim that actually matters about tin is unchanged and is what is
## asserted now: it is the softest METAL in the table, by a wide margin, and no
## edge will stay on it.
func test_tin_is_the_softest_metal_in_the_table_and_takes_no_edge() -> void:
	for metal in ["copper", "iron", "silver", "gold", "zinc"]:
		assert_lt(mp.property_value("tin", "hardness"), mp.property_value(metal, "hardness"),
			"tin must be softer than %s" % metal)
	assert_almost_eq(mp.property_value("tin", "sharpness_capacity"), 0.0, 0.0001)


## Graphite is soft, friable and burns -- it is in the table as the carbon that
## dissolves into iron, not as a structural material.
##
## The hardness clause used to compare it against WOOD and the real numbers say
## the opposite: graphite's published VHN10 is 7-11 kgf/mm^2 against red oak's
## Brinell 3.7. Mohs says graphite (1-2) is softer than wood (~2.5) because a
## layered mineral shears along its basal planes under a scratch, but this
## column is indentation, not scratch, and under an indenter graphite is the
## harder of the two. What made the row soft and friable in the first place is
## the toughness clause below -- it is under the shipped brittle cutoff, which
## is the property that actually keeps anyone from building with it -- and that
## is asserted unchanged. The hardness clause now says the true thing: graphite
## is softer than every metal in the table, which is why it is a solute and
## never a tool.
func test_carbon_is_soft_friable_and_burns() -> void:
	for metal in ["copper", "iron", "silver", "gold", "zinc"]:
		assert_lt(mp.property_value("carbon", "hardness"), mp.property_value(metal, "hardness"),
			"graphite must be softer than %s -- it is a solute, not a tool" % metal)
	assert_lt(mp.property_value("carbon", "toughness"), MaterialProperties.BRITTLE_TOUGHNESS)
	assert_gt(mp.property_value("carbon", "flammability"), mp.property_value("wood", "flammability"))


## Charcoal survives millennia in archaeological deposits -- pure carbon does
## not rot, which is exactly why it is the datable thing in a burnt layer.
func test_carbon_does_not_decay() -> void:
	assert_almost_eq(mp.property_value("carbon", "decay_rate"), 0.0, 0.0001)


# -- descriptors from a bare vector -----------------------------------------
#
# materials.md's 2026-08-24 revision claims an alloy is "just one more way to
# arrive at a property vector". That claim was not TRUE in code: every consumer
# here took a material NAME and looked it up, so a computed vector -- which by
# definition has no name -- could not reach any of them. descriptors_for_vector
# is the name-free half, and descriptors_for is now a thin lookup in front of
# it, so the two can never disagree about what a word means.

func test_descriptors_from_a_vector_match_descriptors_from_the_same_named_row() -> void:
	for material in ["iron", "obsidian", "wood", "fiber", "flesh", "copper"]:
		assert_eq(
			mp.descriptors_for_vector(MaterialProperties.MATERIALS[material]),
			mp.descriptors_for(material),
			"%s must read the same whether reached by name or by vector" % material
		)


## A vector assembled on the fly -- no MATERIALS row, no name -- still gets
## words. This is the thing that was impossible before.
func test_an_unnamed_computed_vector_still_yields_descriptors() -> void:
	var invented: Dictionary = {
		"density": 5.0,
		"hardness": 9.0,
		"toughness": 1.0,
		"elasticity": 0.0,
		"sharpness_capacity": 9.0,
		"flammability": 0.0,
		"conductivity": 5.0,
		"decay_rate": 0.0,
	}
	assert_eq(mp.descriptors_for_vector(invented), ["hard", "keen", "brittle"] as Array[String])


# -- thermal failure: a real temperature, in real degrees --------------------
#
# materials.md's property list has always named "melting/damage thresholds" and
# the table has never had one. It is deliberately NOT a ninth 0-10 scalar: the
# whole point is that it must be comparable against real furnace temperatures
# and real eutectic temperatures, both of which are published numbers in
# degrees Celsius, and `density` already ships in real g/cm^3 so the precedent
# for a real-units column exists.
#
# It is also deliberately NOT part of the property vector. An alloy vector has
# to stay shape-identical to a MATERIALS row (that is what lets a computed
# blend flow through the existing pipeline unchanged), and AlloyBlend already
# argues the same case from the other side. So it is a lookup with an honest
# function pair in front of it instead.

func test_thermal_failure_is_a_real_celsius_temperature_not_a_zero_to_ten_band() -> void:
	assert_almost_eq(mp.thermal_failure_c("copper"), 1084.62, 0.01,
		"copper melts at 1084.62 C -- a real number, comparable against a real furnace")
	assert_gt(mp.thermal_failure_c("iron"), MaterialProperties.CONDUCTIVITY_MAX,
		"this column is degrees, not a 0-10 legibility band")


## Every material must answer, and answer with one of the four modes -- an
## unlisted material would silently read as INF ("nothing can ever hurt this"),
## which is exactly the kind of quiet default this pass exists to remove.
func test_every_material_has_a_real_thermal_failure_temperature_and_mode() -> void:
	for material in MaterialProperties.MATERIALS:
		assert_true(is_finite(mp.thermal_failure_c(material)),
			"%s has no thermal failure temperature" % material)
		assert_true(MaterialProperties.THERMAL_FAILURE_MODES.has(mp.thermal_failure_mode(material)),
			"%s's failure mode '%s' is not one of the four" % [material, mp.thermal_failure_mode(material)])


## Wood does not melt, it ignites; stone does not melt, it cracks; a hide does
## neither, it chars. Reporting a "melting point" for any of them would be a
## number in place of the truth, which is why the mode travels with the
## temperature instead of the temperature standing alone.
func test_the_failure_mode_says_what_actually_happens_to_each_material() -> void:
	assert_eq(mp.thermal_failure_mode("wood"), "ignite", "wood does not melt, it burns")
	assert_eq(mp.thermal_failure_mode("stone"), "fracture", "stone does not melt in any fire, it spalls")
	assert_eq(mp.thermal_failure_mode("hide"), "char", "protein neither melts nor sustains a flame")
	assert_eq(mp.thermal_failure_mode("iron"), "melt")
	assert_eq(mp.thermal_failure_mode("glass"), "melt")


## Fire-cracked rock is a diagnostic artifact class in real archaeology: hearth
## stones shatter, and they shatter for one specific published reason -- the
## alpha-to-beta quartz inversion at 573 C, where quartz abruptly changes volume
## and tears the rock apart. That is a real, sourced number, not "some hot".
func test_stone_fractures_at_the_quartz_inversion_temperature() -> void:
	assert_almost_eq(mp.thermal_failure_c("stone"), 573.0, 0.01,
		"the alpha-beta quartz inversion at 573 C is why hearth stones crack")
	assert_false(mp.can_melt("stone", MaterialProperties.STATION_TEMPERATURE_C["crucible_furnace"]),
		"a stone that has already fractured has not melted -- no station melts stone")


## The metals' melting points are NOT restated here. They are the same
## published constants alloy_blend.gd's cryoscopic model already runs on, and a
## tooltip that said 1085 while the physics used 1084.62 would be exactly the
## drift this project keeps warning about. Pinned equal instead, since the
## preload can only go one way.
func test_the_metal_melting_points_are_the_alloy_models_own_published_constants() -> void:
	var AlloyBlend := preload("res://src/gameplay/alloy_blend.gd")
	for metal in ["copper", "tin", "iron", "silver", "gold", "zinc"]:
		var kelvin: float = float(AlloyBlend.ELEMENT_CONSTANTS[metal]["melting_k"])
		assert_almost_eq(mp.thermal_failure_c(metal), kelvin + AlloyBlend.ABSOLUTE_ZERO_C, 0.01,
			"%s's melting point must be the one number, not two that can drift" % metal)


## THE payoff, and the reason this is a real temperature rather than a band:
## station temperature gates the tech tree for free, with zero authored gating.
## Nothing anywhere says "iron requires a crucible" -- iron requires a crucible
## because 1538 > 1200, and the three station temperatures are what real
## furnaces reach.
func test_station_temperature_gates_the_tech_tree_with_no_authored_gating() -> void:
	var campfire: float = MaterialProperties.STATION_TEMPERATURE_C["campfire"]
	var bloomery: float = MaterialProperties.STATION_TEMPERATURE_C["bloomery"]
	var crucible: float = MaterialProperties.STATION_TEMPERATURE_C["crucible_furnace"]

	assert_true(mp.can_melt("tin", campfire), "an open fire really does melt tin -- ~800 C vs 232 C")
	assert_true(mp.can_melt("zinc", campfire))
	assert_false(mp.can_melt("copper", campfire),
		"and it comes nowhere near copper at 1085 C, which is the whole Chalcolithic problem")
	assert_false(mp.can_melt("silver", campfire), "even silver needs a real furnace")

	assert_true(mp.can_melt("copper", bloomery), "a bellows-blown bloomery at ~1200 C pours copper")
	assert_true(mp.can_melt("gold", bloomery))
	assert_false(mp.can_melt("iron", bloomery),
		"but not wrought iron at 1538 C -- which is why a bloomery makes a solid-state BLOOM, not a pour")

	assert_true(mp.can_melt("iron", crucible),
		"only a crucible furnace at ~1600 C melts iron, which is exactly when crucible steel appears")


## The same gate, read the other way round: what a station can work is a list
## that falls out of the temperatures, so a new material joins the tech tree by
## having a melting point rather than by being added to a recipe gate.
func test_what_a_station_can_work_is_derived_not_listed() -> void:
	assert_eq(mp.materials_meltable_at(MaterialProperties.STATION_TEMPERATURE_C["campfire"]),
		["glass", "obsidian", "tin", "zinc"] as Array[String],
		"a campfire works the low-melting glasses and the low-melting metals, and nothing else")
	var bloomery: Array[String] = mp.materials_meltable_at(
		MaterialProperties.STATION_TEMPERATURE_C["bloomery"]
	)
	assert_true(bloomery.has("copper") and bloomery.has("silver") and bloomery.has("gold"))
	assert_false(bloomery.has("iron"))


## A material that cannot melt at all must say so with something that is not a
## temperature, exactly as AlloyBlend.DOES_NOT_MELT already does for a blend.
func test_a_material_that_never_melts_is_never_meltable_at_any_temperature() -> void:
	for material in ["wood", "fiber", "flesh", "bone", "stone"]:
		assert_false(mp.can_melt(material, 100000.0),
			"%s has no melting point at any temperature -- it fails some other way" % material)


# -- conductivity, on a real IACS scale -------------------------------------
#
# Every other column in this table is placed against its neighbours on a 0-10
# legibility scale; conductivity is the one column that did not have to be,
# because electrical conductivity has a real, universally published unit-free
# scale already -- %IACS, the International Annealed Copper Standard, where
# annealed copper is 100 by definition. So the column is now DERIVED from
# published %IACS figures through one pure function rather than eyeballed
# against iron.
#
# This was free exactly once: the lead verified, and so did a repo-wide grep,
# that nothing in src/ or scenes/ reads "conductivity" at all. It is the scalar
# concept/electromagnetism.md is written against ("a wire's resistance falls out
# of its material's existing conductivity scalar"), so getting it right BEFORE
# anything consumes it is the whole point.

## The relative comparison every conductivity assertion below uses. These values
## span 21 orders of magnitude, so an absolute epsilon is meaningless -- 1e-6
## relative is the honest way to check a table of published figures.
func assert_relative(actual: float, expected: float, message: String) -> void:
	assert_almost_eq(actual, expected, absf(expected) * 1.0e-6 + 1.0e-30, message)


## The column is not assigned, it is computed. Every row must equal
## conductivity_from_iacs() of its own published %IACS figure, so a value can
## never be nudged without changing the physical measurement it claims.
func test_conductivity_is_derived_from_real_iacs_not_assigned() -> void:
	for material in MaterialProperties.MATERIALS:
		assert_true(MaterialProperties.IACS_PERCENT.has(material),
			"%s has no published %%IACS figure -- its conductivity would be eyeballed" % material)
		assert_relative(
			mp.property_value(material, "conductivity"),
			mp.conductivity_from_iacs(float(MaterialProperties.IACS_PERCENT[material])),
			"%s's conductivity must be its %%IACS figure put through the one function" % material
		)


## Silver is the anchor because it is the true maximum of the entire periodic
## table -- nothing conducts better, so the top of the scale never has to move
## again. (Published commercial annealed silver is 105% IACS; the pure figure
## runs a little higher, 106-108%, which is why the constant is named and
## sourced rather than inlined.)
func test_silver_is_the_scale_maximum() -> void:
	assert_almost_eq(mp.conductivity_from_iacs(MaterialProperties.IACS_SILVER_PERCENT),
		MaterialProperties.CONDUCTIVITY_MAX, 0.0001,
		"the silver anchor must land exactly on the top of the scale")
	assert_almost_eq(mp.property_value("silver", "conductivity"),
		MaterialProperties.CONDUCTIVITY_MAX, 0.0001)
	for material in MaterialProperties.MATERIALS:
		assert_lte(mp.property_value(material, "conductivity"),
			mp.property_value("silver", "conductivity"),
			"nothing may out-conduct silver -- it is the periodic table's own maximum")


## The scale's ceiling is the SAME 0-10 legibility ceiling the alloy model
## already pins to the largest value the table uses. Restated here rather than
## preloaded because alloy_blend.gd already preloads THIS file and the reverse
## would be a cycle -- exactly the arrangement BRITTLE_TOUGHNESS already uses
## against ImpactResolver -- so the two are pinned equal instead.
func test_the_conductivity_ceiling_is_the_alloy_models_own_legibility_ceiling() -> void:
	var AlloyBlend := preload("res://src/gameplay/alloy_blend.gd")
	assert_eq(MaterialProperties.CONDUCTIVITY_MAX, AlloyBlend.SCALE_MAX,
		"one legibility ceiling, not two that can drift apart")


## The ordering is the real periodic-table ordering of the metals, which is a
## genuinely checkable external fact: Ag > Cu > Au > Zn > Fe > Sn. The old
## column had iron SECOND, above gold, zinc and tin -- inverted.
func test_the_metal_ordering_matches_the_real_periodic_table_ordering() -> void:
	var real_order := ["silver", "copper", "gold", "zinc", "iron", "tin"]
	for index in range(real_order.size() - 1):
		assert_gt(
			mp.property_value(real_order[index], "conductivity"),
			mp.property_value(real_order[index + 1], "conductivity"),
			"%s must out-conduct %s" % [real_order[index], real_order[index + 1]]
		)


## And the honest consequence of anchoring a LINEAR scale on silver: every
## non-metal collapses to effectively zero, because real conductivity spans
## about 24 orders of magnitude and no linear 0-10 scale can hold that. This is
## the right answer for what the scale is for -- electromagnetism.md's "wood or
## stone simply doesn't conduct and can't complete a circuit at all" was not
## true of the old table, where stone sat at 1.0 against iron's 9.0. It is true
## now. What the scale cannot do is rank insulators against each other, and this
## test pins that limitation rather than hiding it.
func test_no_non_metal_registers_at_all_on_a_conductor_scale() -> void:
	var metals := ["silver", "copper", "gold", "zinc", "iron", "tin"]
	for material in MaterialProperties.MATERIALS:
		if metals.has(material):
			continue
		assert_lt(mp.property_value(material, "conductivity"), 0.1,
			"%s is not a conductor and must not read as one" % material)


# -- hardness: a real Vickers column, not a legibility ordering --------------
#
# The column used to be a placed 0-10 ordering (iron 8, obsidian 9) with almost
# no room above iron, and the consequence was not cosmetic: alloy_blend.gd's
# steel pinned the ceiling for EVERY carbon content, so carbon bought nothing,
# treatment.gd's quench became a no-op on the one material it exists for, and
# tempered toughness slid up past plain iron's. Every one of those is a
# saturation artifact, and every one of them is gone once the column is a real
# measurement -- exactly the move the conductivity column above already made.

## The column is not assigned, it is computed. Every row must equal
## hardness_from_hv() of its own published Vickers figure, so a value can never
## be nudged without changing the measurement it claims. Same shape, and the
## same guarantee, as test_conductivity_is_derived_from_real_iacs_not_assigned.
func test_hardness_is_derived_from_real_vickers_not_assigned() -> void:
	for material in MaterialProperties.MATERIALS:
		assert_true(MaterialProperties.HARDNESS_HV.has(material),
			"%s has no Vickers figure -- its hardness would be eyeballed" % material)
		assert_relative(
			mp.property_value(material, "hardness"),
			mp.hardness_from_hv(float(MaterialProperties.HARDNESS_HV[material])),
			"%s's hardness must be its HV figure put through the one function" % material
		)


## Why LINEAR and not logarithmic, asserted rather than only argued: both
## models that move hardness are built out of Vickers RATIOS and nothing else.
## Treatment.MARTENSITE_HARDNESS_RATIO is 832/180 HV, hardness_retention is
## HV(draw)/HV(as-quenched), and AlloyBlend multiplies a baseline by
## (1 + solution_strengthening). A ratio of HVs may only be multiplied into a
## column that is PROPORTIONAL to HV; on a log column the same multiplication
## would exponentiate the hardness instead. So the map has no freedom: it is
## linear, and this test is what stops anybody "fixing" the crushed soft end by
## making it logarithmic without also rewriting both those models.
func test_the_hardness_map_is_linear_in_hv_because_the_models_are_hv_ratios() -> void:
	var Treatment := preload("res://src/gameplay/treatment.gd")
	assert_almost_eq(mp.hardness_from_hv(0.0), 0.0, 0.000001,
		"a scale multiplied by ratios must pass through the origin")
	for hv in [5.0, 50.0, 180.0, 400.0]:
		assert_relative(mp.hardness_from_hv(2.0 * hv), 2.0 * mp.hardness_from_hv(hv),
			"doubling the Vickers figure must double the scale value")
	assert_almost_eq(
		Treatment.MARTENSITE_HARDNESS_RATIO,
		mp.hardness_from_hv(Treatment.AS_QUENCHED_HV) / mp.hardness_from_hv(Treatment.ANNEALED_HV),
		0.000001,
		"the quench ratio must mean the same thing in HV and on the game scale"
	)


## The anchor, and why it never has to move again -- the same argument
## IACS_SILVER_PERCENT makes for conductivity. 1000 HV is the published Vickers
## figure for martensite, and martensite is the hardest thing a forge can
## produce: no smelting, alloying or heat treatment this game models can make
## anything harder, so the top of the column is a real ceiling rather than an
## accident of where iron happened to be placed.
##
## And it leaves genuine headroom, which is the whole point of the exercise:
## treatment.gd's own AS_QUENCHED_HV (832 HV, water-quenched 0.8% C) lands
## BELOW the ceiling rather than on it, so quenching is an operation with room
## to work in instead of a clamp.
func test_the_hardness_ceiling_is_martensite_the_hardest_thing_a_forge_can_make() -> void:
	var Treatment := preload("res://src/gameplay/treatment.gd")
	var AlloyBlend := preload("res://src/gameplay/alloy_blend.gd")
	assert_almost_eq(mp.hardness_from_hv(MaterialProperties.HARDNESS_MAX_HV),
		MaterialProperties.HARDNESS_MAX, 0.000001,
		"the martensite anchor must land exactly on the top of the scale")
	assert_eq(MaterialProperties.HARDNESS_MAX, AlloyBlend.SCALE_MAX,
		"one legibility ceiling, not two that can drift apart")
	assert_lt(Treatment.AS_QUENCHED_HV, MaterialProperties.HARDNESS_MAX_HV,
		"the hardest thing the forge actually makes must fit UNDER the ceiling")
	for material in MaterialProperties.MATERIALS:
		assert_lte(mp.property_value(material, "hardness"), MaterialProperties.HARDNESS_MAX,
			"%s must not sit above the top of the scale" % material)


## The full ordering, pinned in one place. Every neighbour pair here is a real,
## checkable relation between two published indentation figures -- and the two
## that matter most for the game are that obsidian out-hards iron six times
## over (which is why a knapped edge beats a bloomery one on edge-taking) and
## that rock out-hards both (Mohs 7 quartz against Mohs 5.5 volcanic glass),
## which is why obsidian's advantage is edge FINENESS and never durability.
func test_the_hardness_ordering_is_the_real_vickers_ordering() -> void:
	var real_order := [
		"stone", "obsidian", "glass", "iron", "copper", "bone", "zinc",
		"silver", "gold", "carbon", "tin", "wood", "leather", "hide",
		"fiber", "flesh",
	]
	for index in range(real_order.size() - 1):
		assert_gt(
			mp.property_value(real_order[index], "hardness"),
			mp.property_value(real_order[index + 1], "hardness"),
			"%s must out-hard %s" % [real_order[index], real_order[index + 1]]
		)


## "hard" is now the benchmark-METAL line, not the stone line. On a real
## Vickers column rock is seven times harder than wrought iron, so stone can no
## longer be the cutoff without iron falling out of the word -- and "iron reads
## as hard" is the shipped vocabulary items.md documents. So the cutoff moves to
## iron's own hardness, exactly the way KEEN_SHARPNESS is iron's own
## sharpness_capacity: hard means "at least as hard as the benchmark metal".
func test_the_hard_cutoff_is_the_benchmark_metals_own_hardness() -> void:
	assert_almost_eq(MaterialProperties.HARD_HARDNESS,
		mp.property_value("iron", "hardness"), 0.000001,
		"the hard line must be a shipped material's own figure, not a number typed in")
	assert_true(mp.descriptors_for("iron").has("hard"))
	assert_true(mp.descriptors_for("stone").has("hard"))
	assert_false(mp.descriptors_for("copper").has("hard"),
		"copper being SOFT is the whole reason the Bronze Age needed tin")
	assert_false(mp.descriptors_for("bone").has("hard"))
	assert_false(mp.descriptors_for("wood").has("hard"))


## The soft organics are the honest gap in this column: there is no published
## Vickers figure for wet muscle, rawhide or cordage, because indentation
## hardness is not how any of them is measured. Their figures are PLACED to
## preserve the real ordering (dry tanned leather stiffer than rawhide, both
## stiffer than a bundle of fibres, all far above wet tissue) and this test
## pins the placement so it cannot drift. Wood and bone, by contrast, are real
## measurements (red oak HBW 10/100 = 3.7 kgf/mm^2; cortical bone ~45 HV).
func test_the_soft_organics_are_placed_not_measured_and_keep_their_real_ordering() -> void:
	for material in ["leather", "hide", "fiber", "sinew", "flesh"]:
		assert_lt(float(MaterialProperties.HARDNESS_HV[material]),
			float(MaterialProperties.HARDNESS_HV["wood"]),
			"%s must sit below solid wood, the softest thing here with a real figure" % material)
	assert_gt(float(MaterialProperties.HARDNESS_HV["leather"]),
		float(MaterialProperties.HARDNESS_HV["hide"]),
		"tanning stiffens collagen -- that is what tanning IS")
	assert_almost_eq(float(MaterialProperties.HARDNESS_HV["sinew"]),
		float(MaterialProperties.HARDNESS_HV["fiber"]), 0.000001,
		"cordage is cordage: neither has an indentation hardness of its own")
	assert_lt(float(MaterialProperties.HARDNESS_HV["flesh"]), 1.0,
		"wet tissue is below the bottom of every indentation standard there is")


## Not having measured something is not a reason to call it iron. 1.0 on this
## column now means 100 HV -- wrought iron, and the exact cutoff the "hard"
## descriptor uses -- so the old all-1.0 default would silently promote every
## unmodeled substance to a hard metal. The same argument, and the same fix,
## the conductivity default already carries.
func test_an_unmodeled_material_is_not_assumed_to_be_hard() -> void:
	assert_almost_eq(mp.property_value("unobtainium", "hardness"), 0.0, 0.000001)
	assert_false(mp.descriptors_for_vector({"toughness": 9.0}).has("hard"),
		"a vector that never said how hard it is must not read as hard")
	assert_lt(
		mp.property_value("flesh", "conductivity") / mp.property_value("iron", "conductivity"),
		1.0e-6,
		"wet tissue is orders of magnitude below the worst metal, not a third of it"
	)


## Graphite is the one non-metal that is even measurable here -- it is a
## semi-metal and conducts along its basal planes well enough to be an
## electrode -- but it is still ~300x worse than the worst real metal in the
## table, not comparable to iron as the old 7.0 claimed.
func test_graphite_is_the_only_non_metal_that_registers_and_still_loses_to_every_metal() -> void:
	assert_gt(mp.property_value("carbon", "conductivity"),
		mp.property_value("stone", "conductivity") * 1000.0,
		"graphite is a semi-metal; granite is not")
	assert_lt(mp.property_value("carbon", "conductivity"),
		mp.property_value("tin", "conductivity") / 10.0,
		"but graphite still loses badly to the worst metal here")


## An unmodeled material must not be assumed to be a wire. This is the one
## DEFAULT_PROPERTIES entry that is deliberately not 1.0: on a silver-anchored
## scale 1.0 means "10.5% IACS", i.e. a real metal, so the old default silently
## promoted every unmodeled substance to a usable conductor -- the same class of
## quiet bug the iron/copper inversion was.
func test_an_unmodeled_material_is_not_assumed_to_conduct() -> void:
	assert_almost_eq(mp.property_value("unobtainium", "conductivity"), 0.0, 0.0001,
		"not having measured something is not a reason to call it a conductor")


## The inversion this whole rescale exists to fix. Iron is one of the WORST
## conductors of the common metals (15.6% IACS) and copper is the standard the
## whole scale is defined against (100% IACS) -- a factor of six and a half.
## The table used to ship iron at 9.0 against copper's 10.0, an 11% gap, which
## makes electromagnetism.md's "copper makes a genuinely better wire than iron"
## a statement the numbers cannot support.
func test_iron_conducts_far_worse_than_copper() -> void:
	assert_gt(
		mp.property_value("copper", "conductivity") / mp.property_value("iron", "conductivity"), 5.0,
		"copper is 100%% IACS and iron 15.6%% -- the table must show a factor of six, not 11%%"
	)


## Every row must carry all eight scalars -- a missing key would silently
## fall back to DEFAULT_PROPERTIES and read as a different material. Widened
## from the three alloy rows to the whole table, because the organic rows added
## below are exactly the ones most likely to be added in a hurry.
func test_every_row_carries_the_full_eight_scalar_vector() -> void:
	for material in MaterialProperties.MATERIALS:
		var vector: Dictionary = MaterialProperties.MATERIALS[material]
		for property_name in MaterialProperties.DEFAULT_PROPERTIES:
			assert_true(vector.has(property_name),
				"%s is missing '%s' and would silently read as the default" % [material, property_name])


# -- the organic and decorative rows the design already promised --------------
#
# crafting.md's headline promise is "a hide from a rare, high-fitness boar is a
# better material input". That promise was unreachable in code: hide, leather,
# bone, sinew, glass, silver, gold and zinc had no rows at all, so every organic
# part in the design resolved through DEFAULT_PROPERTIES' all-1.0 vector and
# every one of them realized IDENTICALLY -- a boar hide and a pane of glass were
# the same material.

func test_the_materials_the_design_already_promises_all_have_real_rows() -> void:
	for material in ["hide", "leather", "bone", "sinew", "glass", "silver", "gold", "zinc"]:
		assert_true(MaterialProperties.MATERIALS.has(material),
			"%s is named in the design and must not resolve through DEFAULT_PROPERTIES" % material)
		assert_ne(MaterialProperties.MATERIALS[material], MaterialProperties.DEFAULT_PROPERTIES,
			"%s must be a measured material, not the all-1.0 fallback wearing a name" % material)


## Two different organic inputs must not realize identically -- that is the
## whole substance of the crafting promise, and it was false before these rows
## existed.
func test_two_different_organic_inputs_no_longer_realize_identically() -> void:
	assert_ne(MaterialProperties.MATERIALS["hide"], MaterialProperties.MATERIALS["bone"])
	assert_ne(mp.descriptors_for("bone"), mp.descriptors_for("glass"))


## Tanning is the entire point of leather: tannins cross-link collagen and make
## it inedible to the microbes that eat a raw hide, so a tanned hide outlasts an
## untanned one by orders of magnitude (leather artifacts survive centuries;
## rawhide does not survive a wet season). Exactly the wood -> timber shape this
## table already uses for seasoning.
func test_tanning_is_what_makes_leather_outlast_a_raw_hide() -> void:
	assert_lt(
		mp.property_value("leather", "decay_rate"), mp.property_value("hide", "decay_rate"),
		"tanned leather must resist decay far better than the raw hide it is made from"
	)
	assert_lt(
		mp.property_value("hide", "decay_rate"), mp.property_value("flesh", "decay_rate"),
		"but a raw hide still keeps better than the meat it came off -- it is drier and mostly collagen"
	)


## Rawhide and sinew are the real cordage of a pre-textile toolkit -- rawhide
## lashings shrink tight as they dry, sinew backs bows. Both must pass the
## toughness gate the game already uses for rope; meat must not.
func test_rawhide_and_sinew_are_viable_cordage_but_flesh_is_not() -> void:
	assert_true(mp.is_viable_for_tool("sinew", "grapple_rope"), "sinew is the strongest cord here")
	assert_true(mp.is_viable_for_tool("hide", "grapple_rope"), "rawhide lashing is real cordage")
	assert_false(mp.is_viable_for_tool("flesh", "grapple_rope"))


## Tendon is the biological spring -- it stores and returns elastic energy
## better than anything else in this table, which is why it backs a bow -- and
## it out-pulls plant fibre, which is why a sinew bowstring beats a bast one.
func test_sinew_is_the_springiest_and_strongest_cord_in_the_table() -> void:
	for material in MaterialProperties.MATERIALS:
		assert_lte(mp.property_value(material, "elasticity"),
			mp.property_value("sinew", "elasticity"),
			"%s must not out-spring tendon" % material)
	assert_gt(mp.property_value("sinew", "toughness"), mp.property_value("fiber", "toughness"),
		"a sinew bowstring beats a plant-fibre one")


## Bone is the pre-metal point material: it takes a working point where flesh
## takes nothing, but it is not a keen edge -- bone needles and harpoons are
## real, bone razors are not.
func test_bone_holds_a_working_point_but_never_a_keen_edge() -> void:
	assert_gt(mp.property_value("bone", "sharpness_capacity"),
		mp.property_value("flesh", "sharpness_capacity"))
	assert_false(mp.descriptors_for("bone").has("keen"),
		"bone points are real; bone razors are not")


## Bone is why there is a fossil record: it is the one organic material that
## outlasts wood in the ground by orders of magnitude.
func test_bone_outlasts_every_other_organic_material() -> void:
	for material in ["wood", "timber", "fiber", "flesh", "hide", "leather", "sinew"]:
		assert_lt(mp.property_value("bone", "decay_rate"), mp.property_value(material, "decay_rate"),
			"bone must outlast %s -- that is why bone is what survives to be dug up" % material)


## Soda-lime glass and obsidian are the same class of substance -- a silicate
## glass -- so the existing descriptor vocabulary must reach the same three
## words for both, with obsidian keeping the edge (its higher silica and lower
## alkali content genuinely make it the harder, finer-fracturing glass).
func test_glass_reads_like_the_silicate_glass_it_is() -> void:
	assert_eq(mp.descriptors_for("glass"), ["hard", "keen", "brittle"] as Array[String])
	assert_lt(mp.property_value("glass", "hardness"), mp.property_value("obsidian", "hardness"),
		"soda-lime alkali softens the network; obsidian keeps the harder edge")
	assert_lt(mp.property_value("glass", "sharpness_capacity"),
		mp.property_value("obsidian", "sharpness_capacity"))


## The precious metals are decorative precisely BECAUSE they are useless as
## tools: both are softer than copper, which was already too soft to hold an
## edge against flint. Their value is that they do not corrode -- gold not at
## all, which is why grave goods come out of the ground still bright.
func test_the_precious_metals_are_too_soft_for_tools_and_do_not_corrode() -> void:
	for metal in ["silver", "gold"]:
		assert_lt(mp.property_value(metal, "hardness"), mp.property_value("copper", "hardness"),
			"%s is softer than copper, which was already too soft for an edge" % metal)
		assert_false(mp.descriptors_for(metal).has("keen"))
		assert_lt(mp.property_value(metal, "decay_rate"), mp.property_value("copper", "decay_rate"))
	assert_almost_eq(mp.property_value("gold", "decay_rate"), 0.0, 0.0001,
		"gold is noble -- it does not corrode at all")


## Gold is the densest thing in the table by a wide margin (19.30 g/cm^3), which
## is a real and useful fact: it is why panning works and why a gold-coloured
## fake is trivially detectable by weight.
func test_gold_is_by_far_the_densest_material_in_the_table() -> void:
	assert_almost_eq(mp.property_value("gold", "density"), 19.30, 0.0001)
	for material in MaterialProperties.MATERIALS:
		if material == "gold":
			continue
		assert_lt(mp.property_value(material, "density"), mp.property_value("gold", "density"))


## Zinc is the brass solute: soft, but not as soft as tin, and it is the one
## metal here that is genuinely weak enough to read near the brittle line --
## cast zinc cleaves where cast copper bends.
func test_zinc_sits_between_tin_and_copper_and_is_the_weakest_metal_here() -> void:
	assert_gt(mp.property_value("zinc", "hardness"), mp.property_value("tin", "hardness"))
	assert_lt(mp.property_value("zinc", "hardness"), mp.property_value("copper", "hardness"))
	for metal in ["copper", "tin", "iron", "silver", "gold"]:
		assert_lt(mp.property_value("zinc", "toughness"), mp.property_value(metal, "toughness"),
			"zinc must be the least ductile metal in the table, below %s" % metal)
