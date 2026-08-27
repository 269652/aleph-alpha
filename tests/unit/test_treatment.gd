extends GutTest

var Treatment: GDScript = preload("res://src/gameplay/treatment.gd")
var MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")
var ImpactResolver: GDScript = preload("res://src/gameplay/impact_resolver.gd")
var AlloyBlend: GDScript = preload("res://src/gameplay/alloy_blend.gd")
var AssemblyId: GDScript = preload("res://src/gameplay/assembly_id.gd")

## 0.6 wt% carbon: a real high-carbon blade/spring steel (1060, 5160 -- leaf
## springs, machetes, swords). Everything about the acceptance case below is
## checked against what `alloy_blend.gd` actually produces for it, never
## against numbers copied out of here.
const BLADE_CARBON_FRACTION: float = 0.006

var mp: RefCounted


func before_each() -> void:
	mp = MaterialProperties.new()


func _iron() -> Dictionary:
	return (MaterialProperties.MATERIALS["iron"] as Dictionary).duplicate(true)


func _blade_steel() -> Dictionary:
	return AlloyBlend.blend("iron", "carbon", BLADE_CARBON_FRACTION)


# -- quench: the as-quenched blade really does shatter -----------------------

## The one fact everybody knows about a hardened blade: as-quenched, it
## shatters. Read against the SHIPPED cutoff (MaterialProperties.
## BRITTLE_TOUGHNESS) rather than a number typed in here, so the physics and
## the word a tooltip prints cannot drift apart.
func test_an_as_quenched_blade_falls_below_the_shipped_brittle_toughness_threshold() -> void:
	var iron := _iron()
	assert_gte(float(iron["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"the benchmark blade material is not brittle before treatment")
	var quenched: Dictionary = Treatment.quench(iron)
	assert_lt(float(quenched["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"an as-quenched blade must actually be brittle, not nearly brittle")


## `brittle` is a word the tooltip prints (descriptors_for_vector) and a
## behaviour the impact model acts on (T_BRITTLE_TOUGHNESS). This file must be
## measured against BOTH, or a blade could read "brittle" and still cut.
func test_the_as_quenched_blade_is_brittle_by_the_impact_models_own_cutoff_too() -> void:
	assert_almost_eq(MaterialProperties.BRITTLE_TOUGHNESS,
		ImpactResolver.T_BRITTLE_TOUGHNESS, 0.0001,
		"the tooltip word and the fracture behaviour must be one number")
	var quenched: Dictionary = Treatment.quench(_iron())
	assert_lt(float(quenched["toughness"]), ImpactResolver.T_BRITTLE_TOUGHNESS,
		"the impact model must agree the as-quenched blade shatters")
	assert_true(mp.descriptors_for_vector(quenched).has("brittle"),
		"and the player must be told so in words")


func test_quenching_makes_it_harder_and_less_tough_at_the_same_time() -> void:
	var iron := _iron()
	var quenched: Dictionary = Treatment.quench(iron)
	assert_gt(float(quenched["hardness"]), float(iron["hardness"]))
	assert_lt(float(quenched["toughness"]), float(iron["toughness"]))


# -- temper: the anti-degeneracy law ----------------------------------------

## The law this whole file lives or dies on. If any draw could raise hardness
## AND toughness together, "temper to max everything" would be the only move
## anybody ever made and the mechanic would be dead on arrival.
##
## Two assertions, because they are two different claims: (a) no draw Pareto-
## dominates another -- whatever you gain in one you paid for in the other; and
## (b) the thing that is actually conserved is the POWER LAW, hardness^n x
## toughness. Pairs where toughness has hit the top of the 0-10 scale are
## skipped in (b): that is the legibility scale clamping, not the law failing,
## and (a) still covers them.
func test_temper_moves_the_hardness_toughness_tradeoff_and_cannot_mint_both() -> void:
	var quenched: Dictionary = Treatment.quench(_iron())
	var draws: Array = []
	for step in range(0, 20):
		draws.append(float(Treatment.AS_QUENCHED_DRAW_C) + float(step) * 20.0)

	for a in draws:
		for b in draws:
			if a == b:
				continue
			var left: Dictionary = Treatment.temper(quenched, a)
			var right: Dictionary = Treatment.temper(quenched, b)
			var harder: bool = float(left["hardness"]) > float(right["hardness"])
			var tougher: bool = float(left["toughness"]) > float(right["toughness"])
			assert_false(harder and tougher,
				"draw %s dominates draw %s -- tempering minted both" % [a, b])
			if float(left["toughness"]) >= Treatment.SCALE_MAX:
				continue
			if float(right["toughness"]) >= Treatment.SCALE_MAX:
				continue
			assert_almost_eq(_envelope(left), _envelope(right), _envelope(right) * 0.001,
				"draw %s and draw %s are not on the same envelope" % [a, b])


## A plain sum is the obvious invariant and it is NOT the one this file uses.
## Asserted rather than merely argued in a comment: if somebody ever swaps the
## power law for a sum, this test says so.
func test_the_conserved_quantity_is_a_power_law_and_demonstrably_not_a_sum() -> void:
	var quenched: Dictionary = Treatment.quench(_iron())
	var cold: Dictionary = Treatment.temper(quenched, 200.0)
	var hot: Dictionary = Treatment.temper(quenched, 280.0)

	assert_almost_eq(_envelope(cold), _envelope(hot), _envelope(hot) * 0.001,
		"the power-law envelope must be conserved across the draw")
	var cold_sum := float(cold["hardness"]) + float(cold["toughness"])
	var hot_sum := float(hot["hardness"]) + float(hot["toughness"])
	assert_gt(absf(hot_sum - cold_sum), 0.5,
		"the SUM must visibly not be conserved -- real temper is not a 1:1 trade")


func test_tempering_can_never_raise_hardness() -> void:
	var quenched: Dictionary = Treatment.quench(_iron())
	for step in range(0, 40):
		var draw: float = Treatment.AS_QUENCHED_DRAW_C + float(step) * 10.0
		assert_lte(float(Treatment.temper(quenched, draw)["hardness"]),
			float(quenched["hardness"]) + 0.0001,
			"drawing a blade cannot make it harder than as-quenched")


## Hardness falling and toughness rising, all the way, with no local reversal.
## A single wobble here would let a player find a draw that is strictly better
## than a hotter one in both columns, which is the degenerate case again by
## the back door.
##
## Toughness is asserted STRICTLY increasing only while it is below the top of
## the scale; past that the 0-10 clamp flattens it and the assertion relaxes to
## non-decreasing. That flattening is the scale, not the metallurgy, and it is
## pinned separately by test_treatment_never_leaves_the_zero_to_ten_scale.
##
## "The full draw range" is exactly the range TEMPER_HV has measurements for.
## The bound is read off the table rather than typed in, because past its last
## row the model deliberately goes FLAT rather than extrapolating a curve it
## has no data for (`test_a_draw_past_the_measured_table_stops_moving`) -- and
## a flat tail is not a monotonicity failure, it is the refusal to invent.
func test_the_full_draw_range_is_monotonic_in_both_directions() -> void:
	var quenched: Dictionary = Treatment.quench(_blade_steel())
	var last_row: Array = Treatment.TEMPER_HV[Treatment.TEMPER_HV.size() - 1]
	var measured_to: float = float(last_row[0])
	var previous: Dictionary = quenched
	var draw: float = float(Treatment.AS_QUENCHED_DRAW_C)
	while draw < measured_to:
		draw = minf(draw + 5.0, measured_to)
		var current: Dictionary = Treatment.temper(quenched, draw)
		assert_lt(float(current["hardness"]), float(previous["hardness"]),
			"hardness reversed at draw %s C" % draw)
		if float(previous["toughness"]) < Treatment.SCALE_MAX:
			assert_gt(float(current["toughness"]), float(previous["toughness"]),
				"toughness reversed at draw %s C" % draw)
		else:
			assert_gte(float(current["toughness"]), float(previous["toughness"]),
				"toughness fell after saturating at draw %s C" % draw)
		previous = current


## Past its last measurement the model stops moving instead of extrapolating.
## Real steel does keep softening above 400 C; this file simply has no figures
## for that and says so by going flat, the same "no modelled metallurgy, no
## invented curve" rule AlloyBlend.SOLID_SOLUBILITY follows. Recorded as a
## limit, not sold as physics.
func test_a_draw_past_the_measured_table_stops_moving() -> void:
	var quenched: Dictionary = Treatment.quench(_blade_steel())
	var last_row: Array = Treatment.TEMPER_HV[Treatment.TEMPER_HV.size() - 1]
	var edge: Dictionary = Treatment.temper(quenched, float(last_row[0]))
	var far_past: Dictionary = Treatment.temper(quenched, float(last_row[0]) + 400.0)
	assert_eq(far_past, edge,
		"beyond the table the model must go flat rather than invent more softening")


# -- the colour ladder is real, and ordered ---------------------------------

## The headline legibility claim: a smith reads the draw off the oxide colour,
## and the colours in TEMPER_COLOURS have to actually be in ascending
## temperature order for that to mean anything.
func test_the_oxide_colour_ladder_is_ordered_and_round_trips() -> void:
	var previous := -1.0
	for entry in Treatment.TEMPER_COLOURS:
		var draw := float(entry["draw_c"])
		assert_gt(draw, previous, "the colour ladder must ascend in temperature")
		previous = draw
		var colour := String(entry["colour"])
		assert_eq(Treatment.draw_c_for_colour(colour), draw)
		assert_eq(Treatment.temper_colour(draw), colour,
			"%s must be the colour showing at %s C" % [colour, draw])
	assert_eq(Treatment.draw_c_for_colour("chartreuse"), -1.0,
		"a colour that is not on the ladder has no draw temperature")
	assert_eq(Treatment.temper_colour(Treatment.AS_QUENCHED_DRAW_C), "",
		"an undrawn blade is still bright -- no oxide film yet")


## "a saw draw is springier than a razor draw" -- the ladder's whole point.
## Reads the two draws BY THEIR COLOUR NAMES, not by temperature, because the
## colour is what the smith and the player actually work from.
func test_a_saw_draw_is_springier_than_a_razor_draw() -> void:
	var quenched: Dictionary = Treatment.quench(_blade_steel())
	var razor: Dictionary = Treatment.temper(quenched, Treatment.draw_c_for_colour("pale straw"))
	var saw: Dictionary = Treatment.temper(quenched, Treatment.draw_c_for_colour("pale blue"))

	assert_gt(float(saw["elasticity"]), float(razor["elasticity"]),
		"a saw drawn to pale blue must be springier than a razor drawn to pale straw")
	assert_gt(float(saw["toughness"]), float(razor["toughness"]),
		"and tougher")
	assert_lt(float(saw["hardness"]), float(razor["hardness"]),
		"and it paid for both in hardness")


## The ladder's `use` column is a claim about what each draw MAKES, so the
## model has to actually make those things. A razor keeps its edge and chips; a
## file/knife draw keeps its edge and survives; a spring/saw draw gives up the
## edge for the flex; grey is past the point of being a cutting tool at all.
func test_the_colour_ladder_names_the_tools_it_really_makes() -> void:
	var quenched: Dictionary = Treatment.quench(_blade_steel())
	var razor: Dictionary = Treatment.temper(quenched, Treatment.draw_c_for_colour("pale straw"))
	var knife: Dictionary = Treatment.temper(quenched, Treatment.draw_c_for_colour("dark straw"))
	var saw: Dictionary = Treatment.temper(quenched, Treatment.draw_c_for_colour("pale blue"))
	var dead: Dictionary = Treatment.temper(quenched, Treatment.draw_c_for_colour("grey"))

	assert_gte(float(razor["sharpness_capacity"]), MaterialProperties.KEEN_SHARPNESS,
		"a razor draw must still be able to hold a keen edge")
	assert_lt(float(razor["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"and a straight razor really does chip -- that is the price of the draw")

	assert_gte(float(knife["sharpness_capacity"]), MaterialProperties.KEEN_SHARPNESS,
		"a knife/file draw must still hold a keen edge")
	assert_gte(float(knife["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"and unlike the razor it must survive being used")

	assert_lt(float(saw["sharpness_capacity"]), MaterialProperties.KEEN_SHARPNESS,
		"a spring draw has traded the razor edge away")
	assert_lt(float(dead["sharpness_capacity"]), MaterialProperties.KEEN_SHARPNESS,
		"grey is 'too soft to hold an edge' and must actually be so")


# -- the acceptance case: alloy_blend's brittle steel, made usable ----------

## The single best proof this module earns its place. `alloy_blend.gd` can now
## produce high-carbon iron, and its own write-up records that as-cast steel
## comes out brittle with no way to fix it. This is the fix: quench and temper
## the same vector and it is BOTH harder than plain iron AND out of the
## brittle band -- a blade you can actually hit something with.
##
## Every number is read from the shipped tables (`MATERIALS["iron"]`,
## `BRITTLE_TOUGHNESS`, `KEEN_SHARPNESS`) rather than restated here.
func test_a_quenched_and_tempered_high_carbon_blade_beats_plain_iron_without_being_brittle() -> void:
	var steel := _blade_steel()
	assert_lt(float(steel["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"as-cast high-carbon steel is brittle -- that is the problem being solved")

	var blade: Dictionary = Treatment.temper(
		Treatment.quench(steel), Treatment.draw_c_for_colour("dark straw")
	)
	var iron := _iron()
	assert_gt(float(blade["hardness"]), float(iron["hardness"]),
		"a quenched-and-tempered blade must beat plain iron on hardness")
	assert_gte(float(blade["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"and must not be brittle")
	assert_gte(float(blade["sharpness_capacity"]), MaterialProperties.KEEN_SHARPNESS,
		"and must still take a keen edge")
	assert_false(mp.descriptors_for_vector(blade).has("brittle"),
		"the tooltip must not call the finished blade brittle")
	assert_true(mp.descriptors_for_vector(blade).has("hard"))
	assert_true(mp.descriptors_for_vector(blade).has("keen"))


## Honest scope note, pinned in code: the window that acceptance test lands in
## is NARROW. Plain iron is hardness 8 and the scale stops at 10, so a
## quenched-and-tempered blade has two points of headroom to work in and comes
## out barely a third of a point above iron. That is the 0-10 legibility scale
## saturating -- the limitation `alloy_blend.gd` already names as its biggest --
## and not a claim that real tempered tool steel is only 4 % harder than
## wrought iron.
func test_the_useful_draw_window_is_narrow_because_the_scale_saturates() -> void:
	var quenched: Dictionary = Treatment.quench(_blade_steel())
	var iron_hardness: float = float(_iron()["hardness"])
	var usable: Array = []
	for step in range(0, 78):
		var draw: float = Treatment.AS_QUENCHED_DRAW_C + float(step) * 5.0
		var drawn: Dictionary = Treatment.temper(quenched, draw)
		var hard_enough: bool = float(drawn["hardness"]) > iron_hardness
		var tough_enough: bool = float(drawn["toughness"]) >= MaterialProperties.BRITTLE_TOUGHNESS
		if hard_enough and tough_enough:
			usable.append(draw)
	assert_gt(usable.size(), 0, "there must BE a draw that beats iron without being brittle")
	assert_lt(float(usable[usable.size() - 1]) - float(usable[0]), 60.0,
		"and the window is only tens of degrees wide -- the scale, not the metallurgy")


# -- sharpening --------------------------------------------------------------

## sharpness_capacity is a CEILING, and that is the entire content of the word
## "capacity". You cannot hone iron to an obsidian edge.
func test_sharpening_cannot_exceed_the_materials_own_sharpness_capacity() -> void:
	for material in ["iron", "obsidian", "stone", "copper", "wood"]:
		var vector: Dictionary = (MaterialProperties.MATERIALS[material] as Dictionary).duplicate(true)
		var ceiling := float(vector["sharpness_capacity"])
		for step in range(-4, Treatment.KEEN_STEPS + 5):
			var honed: float = Treatment.keenness(vector, step)
			assert_lte(honed, ceiling,
				"%s honed %d steps went past its own capacity" % [material, step])
			assert_gte(honed, 0.0, "%s honed %d steps went negative" % [material, step])
		assert_almost_eq(Treatment.keenness(vector, Treatment.KEEN_STEPS), ceiling, 0.0001,
			"the top of the ladder must reach the ceiling exactly, for %s" % material)


## Obsidian beats iron on edge and loses on everything else -- the fact
## sharpness_capacity exists to express, checked through this file rather than
## asserted about the table directly.
func test_obsidian_hones_keener_than_iron_at_every_rung() -> void:
	var obsidian: Dictionary = (MaterialProperties.MATERIALS["obsidian"] as Dictionary).duplicate(true)
	var iron := _iron()
	for step in range(1, Treatment.KEEN_STEPS + 1):
		assert_gt(Treatment.keenness(obsidian, step), Treatment.keenness(iron, step),
			"obsidian must out-edge iron at rung %d" % step)
	assert_lt(float(obsidian["toughness"]), float(iron["toughness"]),
		"and pay for it in the column that gets it shattered")


## The quantization has to be the SAME ladder `assembly_id.gd` content-
## addresses process levels on, or honing a blade mints ids for distinctions
## the id model says do not exist.
func test_sharpening_is_quantized_on_the_ladder_assembly_id_content_addresses_with() -> void:
	assert_eq(Treatment.KEEN_STEPS, AssemblyId.TREATMENT_LEVELS,
		"the whetstone ladder and the id ladder must be one number")
	var iron := _iron()
	var distinct := {}
	for permille in range(0, 1001):
		var level := float(permille) / 1000.0
		distinct[Treatment.keenness(iron, AssemblyId.quantize_treatment(level))] = true
	assert_lte(distinct.size(), Treatment.KEEN_STEPS + 1,
		"a thousand honing levels must collapse onto the ladder's rungs")


## Before this file, an unworked iron bar read as "keen" in words, because the
## table's 8.0 is the edge it COULD hold. A blank is not a blade until somebody
## grinds it.
func test_an_unsharpened_blank_does_not_read_as_keen_but_a_honed_one_does() -> void:
	var iron := _iron()
	assert_true(mp.descriptors_for_vector(iron).has("keen"),
		"the raw table row reads keen -- that is the honesty problem")
	assert_false(mp.descriptors_for_vector(Treatment.sharpen(iron, 0)).has("keen"),
		"an unground blank must not")
	assert_true(mp.descriptors_for_vector(Treatment.sharpen(iron, Treatment.KEEN_STEPS)).has("keen"),
		"a fully honed one must")


## sharpen() overwrites the capacity slot with the achieved edge, so feeding
## its own output back grinds against a ceiling that has already been lowered.
## The documented precondition, pinned so it cannot be forgotten.
func test_sharpen_takes_the_materials_vector_not_one_it_already_returned() -> void:
	var iron := _iron()
	var full: Dictionary = Treatment.sharpen(iron, Treatment.KEEN_STEPS)
	var restacked: Dictionary = Treatment.sharpen(
		Treatment.sharpen(iron, 4), Treatment.KEEN_STEPS
	)
	assert_lt(float(restacked["sharpness_capacity"]), float(full["sharpness_capacity"]),
		"re-sharpening an already-sharpened vector must NOT reach the material's ceiling")


# -- calibration: every tuned number re-derived from its source -------------

## n is not chosen. It is 2k + 1 where k is the FRACTURE_ANCHOR's own log-log
## slope, because absorbed energy goes as K_IC^2 / sigma_y and hardness is
## proportional to sigma_y (Tabor).
func test_the_toughness_exponent_is_the_published_fracture_anchor_solved_for_n() -> void:
	var low: Array = Treatment.FRACTURE_ANCHOR[0]
	var high: Array = Treatment.FRACTURE_ANCHOR[1]
	var slope := log(float(high[1]) / float(low[1])) / log(float(low[0]) / float(high[0]))
	assert_almost_eq(slope, 1.4859, 0.0005,
		"the anchor's K_IC-versus-yield slope")
	assert_almost_eq(Treatment.TOUGHNESS_HARDNESS_EXPONENT, 2.0 * slope + 1.0, 0.0001,
		"the exponent must be the anchor solved for n, not a number that felt right")


## Quenching's hardness drive is a quotient of two published Vickers numbers,
## not a multiplier somebody liked. It is also the famous "quenching roughly
## quadruples hardness".
func test_the_martensite_hardness_ratio_is_the_published_quotient() -> void:
	assert_almost_eq(Treatment.MARTENSITE_HARDNESS_RATIO,
		Treatment.AS_QUENCHED_HV / Treatment.ANNEALED_HV, 0.000001)
	assert_gt(Treatment.MARTENSITE_HARDNESS_RATIO, 4.0)
	assert_lt(Treatment.MARTENSITE_HARDNESS_RATIO, 5.0)


## The easy, real bug this table's Vickers conversion avoids. The published
## temper figures are Rockwell C -- 65 as-quenched, 55 at 300 C -- and HRC is a
## DEPTH scale, so 55/65 = 0.85 is meaningless. Converted properly the blade
## keeps 0.72 of its hardness, not 0.85: a 13-point error in a 2-point-wide
## window would wreck every draw in the ladder.
func test_hardness_retention_is_read_in_vickers_not_as_a_ratio_of_rockwell_numbers() -> void:
	assert_almost_eq(Treatment.hardness_retention(300.0), 595.0 / 832.0, 0.0001)
	assert_gt(absf(Treatment.hardness_retention(300.0) - 55.0 / 65.0), 0.1,
		"a ratio of raw HRC numbers would be badly wrong and must not be what this returns")


func test_an_undrawn_blade_retains_all_of_its_as_quenched_hardness() -> void:
	assert_almost_eq(Treatment.hardness_retention(Treatment.AS_QUENCHED_DRAW_C), 1.0, 0.000001)
	assert_almost_eq(Treatment.hardness_retention(-500.0), 1.0, 0.000001,
		"below the table the model does not invent extra hardening")
	var last: Array = Treatment.TEMPER_HV[Treatment.TEMPER_HV.size() - 1]
	assert_almost_eq(Treatment.hardness_retention(5000.0),
		float(last[1]) / Treatment.AS_QUENCHED_HV, 0.000001,
		"past the table the model does not invent a curve either")


func test_the_temper_table_is_strictly_softening_with_temperature() -> void:
	var previous := INF
	var previous_draw := -INF
	for row in Treatment.TEMPER_HV:
		assert_gt(float(row[0]), previous_draw, "temper rows must ascend in temperature")
		assert_lt(float(row[1]), previous, "and descend in hardness")
		previous_draw = float(row[0])
		previous = float(row[1])


# -- purity, determinism, shape ---------------------------------------------

func test_treatment_is_pure() -> void:
	var iron := _iron()
	var untouched := iron.duplicate(true)
	var quenched: Dictionary = Treatment.quench(iron)
	assert_eq(iron, untouched, "quench mutated the vector it was given")
	Treatment.temper(quenched, 250.0)
	Treatment.sharpen(iron, 3)
	Treatment.keenness(iron, 3)
	assert_eq(iron, untouched, "some operation mutated the caller's vector")
	assert_false(quenched == iron, "quench must return a NEW vector, not the same one")


func test_treatment_is_deterministic() -> void:
	var steel := _blade_steel()
	var first: Dictionary = Treatment.temper(Treatment.quench(steel), 245.0)
	for _repeat in range(5):
		assert_eq(Treatment.temper(Treatment.quench(steel), 245.0), first,
			"same inputs must always give the same vector -- no RNG anywhere in here")
		assert_eq(Treatment.sharpen(steel, 5), Treatment.sharpen(steel, 5))


## A treated vector has to be indistinguishable in SHAPE from a MATERIALS row,
## for exactly the reason an alloy vector does: every downstream consumer
## (impact_resolver, descriptors_for_vector, mass_kg_for) takes the eight
## scalars and nothing else.
func test_a_treated_vector_is_a_complete_eight_scalar_vector() -> void:
	var treated: Dictionary = Treatment.temper(Treatment.quench(_iron()), 260.0)
	assert_eq(treated.keys().size(), MaterialProperties.DEFAULT_PROPERTIES.keys().size())
	for property_name in MaterialProperties.DEFAULT_PROPERTIES:
		assert_true(treated.has(property_name), "treated vector is missing '%s'" % property_name)
	assert_eq(Treatment.TREATED_PROPERTIES.size(),
		MaterialProperties.DEFAULT_PROPERTIES.keys().size(),
		"a ninth scalar on the shared table must be a deliberate decision here too")


func test_a_vector_missing_scalars_falls_back_to_the_shared_defaults() -> void:
	var sparse: Dictionary = {"hardness": 4.0, "toughness": 6.0}
	var treated: Dictionary = Treatment.quench(sparse)
	assert_almost_eq(float(treated["density"]),
		float(MaterialProperties.DEFAULT_PROPERTIES["density"]), 0.0001,
		"unknown scalars must default exactly as property_value does")


## Density is a real g/cm^3 measurement and is exempt from the 0-10 scale, the
## same exemption AlloyBlend.SCALE_MAX documents.
func test_treatment_never_leaves_the_zero_to_ten_scale() -> void:
	assert_almost_eq(Treatment.SCALE_MAX, AlloyBlend.SCALE_MAX, 0.000001,
		"the scale ceiling must be read from one place, not restated")
	for material in ["iron", "obsidian", "copper", "wood", "fiber", "tin", "stone", "flesh"]:
		var vector: Dictionary = (MaterialProperties.MATERIALS[material] as Dictionary).duplicate(true)
		var quenched: Dictionary = Treatment.quench(vector)
		for step in range(0, 45):
			var draw: float = Treatment.AS_QUENCHED_DRAW_C + float(step) * 10.0
			var drawn: Dictionary = Treatment.temper(quenched, draw)
			for property_name in drawn:
				var value: float = float(drawn[property_name])
				assert_true(is_finite(value),
					"%s at %s C produced a non-finite %s" % [material, draw, property_name])
				assert_gte(value, 0.0,
					"%s at %s C produced a negative %s" % [material, draw, property_name])
				if property_name != "density":
					assert_lte(value, Treatment.SCALE_MAX,
						"%s at %s C blew past the scale on %s" % [material, draw, property_name])


## Five of the eight scalars are untouched by heat treatment, and that is a
## CLAIM, not an oversight: density moves under a percent between martensite
## and pearlite, and a fire changes nothing at all about how flammable, how
## conductive or how rot-prone a piece of steel is. Asserting it here stops
## somebody quietly adding a "hardened steel rusts slower" fudge later.
func test_heat_treatment_leaves_the_scalars_it_has_no_business_touching_alone() -> void:
	var steel := _blade_steel()
	var drawn: Dictionary = Treatment.temper(Treatment.quench(steel), 270.0)
	for property_name in ["density", "flammability", "conductivity", "decay_rate"]:
		assert_almost_eq(float(drawn[property_name]), float(steel[property_name]), 0.000001,
			"heat treatment must not touch %s" % property_name)


# -- documented limits, pinned rather than hidden ---------------------------

## Re-hardening a drawn blade puts it back exactly where the quench left it --
## real (a smith re-hardens before re-drawing) and structural: both operations
## are the same slide along the same envelope. It is also what makes `temper`'s
## "takes an as-quenched vector" precondition livable.
func test_re_hardening_a_tempered_blade_returns_it_to_the_as_quenched_state() -> void:
	var quenched: Dictionary = Treatment.quench(_blade_steel())
	var drawn: Dictionary = Treatment.temper(quenched, 280.0)
	var rehardened: Dictionary = Treatment.quench(drawn)
	for property_name in quenched:
		assert_almost_eq(float(rehardened[property_name]), float(quenched[property_name]), 0.0001,
			"re-hardening must land back on the as-quenched %s" % property_name)


## An honest no-op, pinned. `alloy_blend.gd` saturates hardness at the top of
## the scale for ANY Fe-C composition, so a modelled carbon steel arrives with
## nothing left to harden -- and because the toughness price is charged on the
## hardness actually delivered, it pays nothing either. Tempering, not
## quenching, is what does the work for steel in this model.
func test_quenching_a_modelled_carbon_steel_is_a_no_op_because_the_scale_is_full() -> void:
	var steel := _blade_steel()
	assert_almost_eq(float(steel["hardness"]), Treatment.SCALE_MAX, 0.0001,
		"alloy_blend already saturates hardness for any carbon steel")
	var quenched: Dictionary = Treatment.quench(steel)
	for property_name in steel:
		assert_almost_eq(float(quenched[property_name]), float(steel[property_name]), 0.000001,
			"quenching a saturated steel must change %s by nothing at all" % property_name)


## The limitation this file cannot fix, recorded in code rather than only in
## prose: an eight-scalar property vector carries no composition, so nothing
## here can tell hardenable steel from wrought iron. Real wrought iron does not
## harden by quenching at all and real bronze SOFTENS; the model hardens both.
## Fixing it needs a composition-aware caller, which is named as unbuilt in
## docs/concept/heat_treatment.md.
func test_the_vector_cannot_express_hardenability_so_quench_overstates_pure_metals() -> void:
	var iron := _iron()
	assert_gt(float(Treatment.quench(iron)["hardness"]), float(iron["hardness"]),
		"KNOWN WRONG: real wrought iron does not quench-harden")
	var copper: Dictionary = (MaterialProperties.MATERIALS["copper"] as Dictionary).duplicate(true)
	assert_gt(float(Treatment.quench(copper)["hardness"]), float(copper["hardness"]),
		"KNOWN WRONG: quenching real copper anneals it soft")


# -- helpers -----------------------------------------------------------------

func _envelope(vector: Dictionary) -> float:
	return (
		pow(float(vector["hardness"]), Treatment.TOUGHNESS_HARDNESS_EXPONENT)
		* float(vector["toughness"])
	)
