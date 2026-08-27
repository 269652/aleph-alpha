extends GutTest

var AlloyBlend: GDScript = preload("res://src/gameplay/alloy_blend.gd")
var MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")

var mp: RefCounted


func before_each() -> void:
	mp = MaterialProperties.new()


# -- endpoints: a blend model that cannot reproduce its own inputs is broken --

func test_blending_none_of_b_returns_exactly_material_a() -> void:
	var pure: Dictionary = AlloyBlend.blend("copper", "tin", 0.0)
	assert_eq(pure, MaterialProperties.MATERIALS["copper"],
		"0% tin IS copper -- the blend must reproduce its own endpoint exactly")


func test_blending_all_of_b_returns_exactly_material_b() -> void:
	var pure: Dictionary = AlloyBlend.blend("copper", "tin", 1.0)
	assert_eq(pure, MaterialProperties.MATERIALS["tin"],
		"100% tin IS tin")


func test_fractions_outside_the_unit_range_clamp_to_the_endpoints() -> void:
	assert_eq(AlloyBlend.blend("copper", "tin", -2.0), MaterialProperties.MATERIALS["copper"])
	assert_eq(AlloyBlend.blend("copper", "tin", 5.0), MaterialProperties.MATERIALS["tin"])


# -- the result must be a complete, usable property vector -------------------
#
# An alloy is "one more way to arrive at a property vector" (materials.md's
# 2026-08-24 revision), so it has to be indistinguishable in SHAPE from a
# table row -- same eight keys, every one finite -- or every downstream
# consumer (impact_resolver, descriptors_for, mass_kg_for) breaks on it.

func test_a_blend_is_a_complete_eight_scalar_vector_with_no_missing_keys() -> void:
	var alloy: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	assert_eq(alloy.keys().size(), MaterialProperties.DEFAULT_PROPERTIES.keys().size(),
		"an alloy vector must have exactly the same shape as a table row")
	for property_name in MaterialProperties.DEFAULT_PROPERTIES:
		assert_true(alloy.has(property_name), "alloy vector is missing '%s'" % property_name)


func test_every_scalar_is_finite_across_the_whole_composition_range() -> void:
	for step in range(0, 101):
		var x := float(step) / 100.0
		for pair in [["copper", "tin"], ["iron", "carbon"], ["wood", "stone"], ["tin", "copper"]]:
			var alloy: Dictionary = AlloyBlend.blend(pair[0], pair[1], x)
			for property_name in alloy:
				var value: float = alloy[property_name]
				assert_true(is_finite(value),
					"%s/%s at %f produced a non-finite %s" % [pair[0], pair[1], x, property_name])
				assert_true(value >= 0.0,
					"%s/%s at %f produced a negative %s" % [pair[0], pair[1], x, property_name])


func test_the_blend_is_deterministic() -> void:
	var first: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	for _repeat in range(5):
		assert_eq(AlloyBlend.blend("copper", "tin", 0.12), first,
			"same inputs must always give the same vector -- no RNG anywhere in here")


## Swapping which material you call "a" is a relabelling, not a different
## alloy. Every asymmetry in the model (the two solubility limits, the two
## lattice misfits) is keyed by SOLVENT, so the swap has to map region to
## region exactly.
func test_swapping_the_two_materials_mirrors_the_composition_axis() -> void:
	for step in range(0, 101):
		var x := float(step) / 100.0
		var forward: Dictionary = AlloyBlend.blend("copper", "tin", x)
		var mirrored: Dictionary = AlloyBlend.blend("tin", "copper", 1.0 - x)
		for property_name in forward:
			assert_almost_eq(float(forward[property_name]), float(mirrored[property_name]), 0.0005,
				"blend(a,b,x) and blend(b,a,1-x) disagree on %s at x=%f" % [property_name, x])


# -- rule of mixtures: the linear baseline every scalar starts from ----------

## Mass fractions do NOT mix linearly into a density -- volume fractions do.
## For a given MASS split the exact relation is the harmonic one,
## 1/rho = w_a/rho_a + w_b/rho_b, and it is worth getting right because it is
## checkable against reality: 88Cu-12Sn comes out at 8.72 g/cm^3 against a
## measured ~8.78 for cast tin bronze.
func test_density_mixes_harmonically_and_matches_real_cast_bronze() -> void:
	var bronze: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	assert_almost_eq(float(bronze["density"]), 8.72, 0.05,
		"88Cu-12Sn should land on measured cast-bronze density (~8.78 g/cm^3)")
	var naive_linear := 8.96 * 0.88 + 7.31 * 0.12
	assert_true(absf(float(bronze["density"]) - 8.72) < absf(naive_linear - 8.72),
		"the harmonic mix should beat the naive mass-fraction average against reality")


func test_inert_scalars_follow_the_plain_rule_of_mixtures() -> void:
	var alloy: Dictionary = AlloyBlend.blend("copper", "tin", 0.25)
	for property_name in ["elasticity", "flammability", "conductivity", "decay_rate"]:
		var expected: float = (
			mp.property_value("copper", property_name) * 0.75
			+ mp.property_value("tin", property_name) * 0.25
		)
		assert_almost_eq(float(alloy[property_name]), expected, 0.0001,
			"%s has no modeled non-linearity and should mix linearly" % property_name)


## LINEAR_PROPERTIES documents which scalars have no modeled non-linearity, and
## a list like that is worthless the moment it can drift away from what the code
## does. So this OBSERVES which scalars actually come out on the rule-of-mixtures
## line and asserts the declared list is exactly that set -- the const is checked
## against behaviour rather than merely asserted alongside it.
##
## Two pairs are probed, not one, because copper and tin are both flammability 0
## and would make that scalar look linear no matter what the code did to it;
## iron/carbon (0 -> 9) actually exercises it. A scalar counts as linear only if
## it lands on the line for BOTH pairs.
##
## The drift this catches: add a ninth scalar to BLENDED_PROPERTIES and it
## silently receives a linear mix while going unmentioned here. This test fails
## until someone decides, deliberately, which side of the line it belongs on.
func test_the_declared_linear_scalars_are_exactly_the_ones_the_blend_leaves_linear() -> void:
	var probes := [["copper", "tin", 0.25], ["iron", "carbon", 0.5]]
	var observed_linear: Array[String] = []
	for property_name in AlloyBlend.BLENDED_PROPERTIES:
		var linear_everywhere := true
		for probe in probes:
			var alloy: Dictionary = AlloyBlend.blend(probe[0], probe[1], probe[2])
			var expected: float = lerpf(
				mp.property_value(probe[0], property_name),
				mp.property_value(probe[1], property_name),
				probe[2]
			)
			if absf(float(alloy[property_name]) - expected) > 0.000001:
				linear_everywhere = false
		if linear_everywhere:
			observed_linear.append(property_name)
	assert_eq(observed_linear, AlloyBlend.LINEAR_PROPERTIES,
		"LINEAR_PROPERTIES must name exactly the scalars blend() actually mixes linearly")


## And the complement: every scalar NOT declared linear must genuinely bend away
## from the rule-of-mixtures line somewhere, or it is claiming a non-linearity it
## does not have.
func test_every_scalar_not_declared_linear_actually_bends_off_the_line() -> void:
	for property_name in AlloyBlend.BLENDED_PROPERTIES:
		if AlloyBlend.LINEAR_PROPERTIES.has(property_name):
			continue
		var alloy: Dictionary = AlloyBlend.blend("copper", "tin", 0.25)
		var expected: float = lerpf(
			mp.property_value("copper", property_name),
			mp.property_value("tin", property_name),
			0.25
		)
		assert_true(absf(float(alloy[property_name]) - expected) > 0.000001,
			"%s is not declared linear but mixes linearly anyway" % property_name)


## An unknown pair has no phase diagram in the table, so the honest answer is
## "we do not model this pair's metallurgy" -- a pure rule of mixtures with no
## invented strengthening, not a guess.
func test_a_pair_with_no_phase_data_falls_back_to_a_pure_linear_mix() -> void:
	var mix: Dictionary = AlloyBlend.blend("wood", "stone", 0.5)
	assert_almost_eq(float(mix["hardness"]), (3.0 + 7.0) / 2.0, 0.0001,
		"no solubility data means no modeled strengthening, not a made-up bonus")
	assert_almost_eq(AlloyBlend.solution_strengthening("wood", "stone", 0.5), 0.0, 0.0001)


# -- the geometry the strengthening model is built out of --------------------

## The octahedral hole in a close-packed metal lattice is not a tuned number:
## it is sqrt(2) - 1 times the host atom's radius, exactly, from packing
## geometry alone. It is what makes carbon an INTERSTITIAL solute rather than
## a substitutional one, and therefore what makes it so much more potent.
func test_the_interstitial_site_ratio_is_the_exact_packing_geometry_result() -> void:
	assert_almost_eq(AlloyBlend.OCTAHEDRAL_SITE_RADIUS_RATIO, sqrt(2.0) - 1.0, 0.000001,
		"the octahedral hole radius ratio is derived, not chosen")


## Substitutional misfit is the plain size mismatch of the two metallic radii,
## measured against the SOLVENT -- Cu 128 pm, Sn 140 pm.
func test_substitutional_misfit_is_the_metallic_radius_mismatch() -> void:
	assert_almost_eq(AlloyBlend.lattice_misfit("copper", "tin"), 12.0 / 128.0, 0.0001)


## The single most important number in real ferrous metallurgy: carbon does not
## replace an iron atom, it is jammed into a hole far too small for it, so its
## misfit is roughly FIVE TIMES tin's in copper. That -- not any game-balance
## choice -- is why 0.8% carbon transforms iron while it takes 12% tin to
## transform copper.
func test_interstitial_carbon_is_a_far_more_potent_solute_than_substitutional_tin() -> void:
	var carbon_misfit: float = AlloyBlend.lattice_misfit("iron", "carbon")
	var tin_misfit: float = AlloyBlend.lattice_misfit("copper", "tin")
	assert_gt(carbon_misfit / tin_misfit, 4.0,
		"an interstitial solute must be far more distorting than a substitutional one")
	assert_lt(carbon_misfit / tin_misfit, 6.0)


## The four published phase boundaries the whole two-regime model turns on.
## Each is the composition above which a continuous brittle SECOND PHASE starts
## to appear, read off a real binary phase diagram:
##
## - **Cu-Sn 13.5 wt%** -- the practical as-cast limit: below it no macroscopic
##   segregation occurs even under ordinary casting conditions; above it the
##   hard, brittle delta constituent forms. (The equilibrium alpha boundary is
##   15.8 wt% at 586 C, but bronze is a CAST material and coring is what a
##   caster actually meets.)
## - **Cu-Zn 39 wt%** -- the alpha/(alpha+beta) boundary at ~454-470 C, a true
##   maximum solid solubility.
## - **Cu-As 7.96 wt%** -- the maximum solid solubility of arsenic in copper at
##   685 C.
## - **Fe-C 0.76 wt%** -- the EUTECTOID, and deliberately not a solubility
##   limit (ferrite dissolves a mere 0.02% C). It is nonetheless the right
##   boundary for this model, because it is the composition above which
##   proeutectoid cementite starts precipitating as a continuous film on the
##   prior-austenite grain boundaries. That film is what collapses toughness,
##   and 0.76% is where it begins.
##
## Rewritten from test_solubility_limits_are_the_real_phase_diagram_values,
## which pinned 15.8/2.1 -- the equilibrium solid-solubility numbers. Those are
## the right answer to a different question ("how much will dissolve") than the
## one the model actually asks ("when does the crack highway appear").
func test_the_second_phase_onsets_are_the_published_phase_boundaries() -> void:
	assert_almost_eq(AlloyBlend.second_phase_onset("copper", "tin"), 0.135, 0.0001)
	assert_almost_eq(AlloyBlend.second_phase_onset("copper", "zinc"), 0.39, 0.0001)
	assert_almost_eq(AlloyBlend.second_phase_onset("copper", "arsenic"), 0.0796, 0.0001)
	assert_almost_eq(AlloyBlend.second_phase_onset("iron", "carbon"), 0.0076, 0.0001)


## A pair with no published boundary has no modeled metallurgy at all, in
## either direction -- an honest "not modeled", not an invented curve.
func test_a_pair_with_no_published_boundary_has_no_modeled_second_phase() -> void:
	assert_almost_eq(AlloyBlend.second_phase_onset("tin", "copper"), 0.0, 0.0001)
	assert_almost_eq(AlloyBlend.second_phase_onset("carbon", "iron"), 0.0, 0.0001)
	assert_almost_eq(AlloyBlend.second_phase_onset("wood", "stone"), 0.0, 0.0001)


## The second phase's COMPOSITION is not a fifth looked-up number: it is
## computed from the compound's formula and the elements' published molar
## masses, which is arithmetic, not a measurement. That it lands on the real
## published figures is the check that the derivation is right --
## Cu31Sn8 comes out at 32.5 wt% Sn against a literature 32.6, and Fe3C at
## 6.69 wt% C against the textbook 6.67.
func test_the_second_phase_composition_is_derived_from_its_formula_not_looked_up() -> void:
	assert_almost_eq(AlloyBlend.second_phase_solute_fraction("copper", "tin"), 0.326, 0.002,
		"delta bronze is Cu31Sn8, which IS 32.6 wt%% tin")
	assert_almost_eq(AlloyBlend.second_phase_solute_fraction("iron", "carbon"), 0.0667, 0.001,
		"cementite is Fe3C, which IS 6.67 wt%% carbon")
	assert_almost_eq(AlloyBlend.second_phase_solute_fraction("copper", "zinc"), 0.507, 0.002,
		"beta-prime brass is the ordered equiatomic CuZn")
	# Cu3As comes out at 28.2 wt% As against the real gamma homogeneity range of
	# 28.6-29.6 wt%. Deriving from stoichiometry lands just under the real phase
	# field, which is what deriving costs -- recorded rather than papered over.
	assert_almost_eq(AlloyBlend.second_phase_solute_fraction("copper", "arsenic"), 0.282, 0.002)


## Every second phase must be RICHER in solute than the boundary it appears at,
## or the lever rule would run backwards.
func test_every_second_phase_is_richer_than_the_boundary_it_appears_at() -> void:
	for pair in [["copper", "tin"], ["copper", "zinc"], ["copper", "arsenic"], ["iron", "carbon"]]:
		assert_gt(
			AlloyBlend.second_phase_solute_fraction(pair[0], pair[1]),
			AlloyBlend.second_phase_onset(pair[0], pair[1]),
			"%s-%s's second phase must be richer than the composition it starts at" % pair
		)


# -- solid-solution strengthening: the headline emergent claim ---------------

## THE claim. Bronze is harder than copper and harder than tin -- a real peak
## in the middle of a blend space, not an interpolation between its ends.
func test_bronze_is_harder_than_both_pure_copper_and_pure_tin() -> void:
	var bronze: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	assert_gt(float(bronze["hardness"]), mp.property_value("copper", "hardness"),
		"bronze must beat pure copper -- this is the entire point of the Bronze Age")
	assert_gt(float(bronze["hardness"]), mp.property_value("tin", "hardness"),
		"bronze must beat pure tin as well, or it is just a weighted average")


## Not merely above the endpoints: a genuine interior maximum, so the space has
## something to search FOR. Scanned rather than asserted at one point, because
## the shape is the claim.
##
## Rewritten from a version that asserted the peak sits at the solubility limit.
## Under the two-regime model that is no longer true and should not be: past the
## boundary the alloy keeps getting HARDER as the brittle intermetallic's volume
## fraction grows, so raw hardness peaks at the intermetallic's own composition.
## What peaks at the boundary is *usable* hardness, which is the next test.
func test_the_copper_tin_hardness_peak_is_strictly_interior() -> void:
	var best_x := 0.0
	var best_hardness := -1.0
	for step in range(0, 1001):
		var x := float(step) / 1000.0
		var hardness: float = AlloyBlend.blend("copper", "tin", x)["hardness"]
		if hardness > best_hardness:
			best_hardness = hardness
			best_x = x
	assert_gt(best_x, 0.0, "the hardness maximum must not sit at pure copper")
	assert_lt(best_x, 1.0, "the hardness maximum must not sit at pure tin")
	assert_almost_eq(best_x, AlloyBlend.second_phase_solute_fraction("copper", "tin"), 0.002,
		"raw hardness peaks at the intermetallic itself -- delta bronze is hard and useless")


# -- the payoff: three real historical optima, from three published numbers ---

## THE test this rewrite exists to earn. The optimum is NOT placed anywhere: it
## is the richest composition that has not yet grown a continuous brittle
## network, and where that falls is decided entirely by the published phase
## boundary. Three unrelated binary systems, three published boundaries, three
## real historical answers:
##
## - **Cu-Sn at 13.5% tin.** Real weapons bronze is 10-14% Sn.
## - **Cu-Zn at 39% zinc.** Muntz metal -- the alpha+beta brass that actually
##   got used for ship sheathing and cheap castings -- is 40% Zn.
## - **Fe-C at 0.76% carbon.** That is eutectoid steel, the classic carbon
##   content of an edged tool, exactly.
##
## Nothing in the formula knows any of those three historical facts.
func test_the_model_reproduces_three_real_historical_optima() -> void:
	var bronze: float = AlloyBlend.optimal_solute_fraction("copper", "tin")
	assert_between(bronze, 0.10, 0.14,
		"the Cu-Sn optimum must land in the real 10-14%% weapons-bronze band")

	var brass: float = AlloyBlend.optimal_solute_fraction("copper", "zinc")
	assert_almost_eq(brass, 0.40, 0.02, "the Cu-Zn optimum must land on Muntz metal's 40%% zinc")

	var steel: float = AlloyBlend.optimal_solute_fraction("iron", "carbon")
	assert_almost_eq(steel, 0.0076, 0.0002,
		"the Fe-C optimum must land on the eutectoid -- 0.76%% carbon, the classic edged-tool steel")

	for pair in [["copper", "tin"], ["copper", "zinc"], ["iron", "carbon"]]:
		assert_almost_eq(
			AlloyBlend.optimal_solute_fraction(pair[0], pair[1]),
			AlloyBlend.second_phase_onset(pair[0], pair[1]), 0.0002,
			"%s-%s's optimum must FALL OUT of the published boundary, not be placed" % pair
		)


## The anti-wiki property, and the whole design argument for a blend space over
## a recipe list. A player who learns "about one part in seven" from bronze is
## wrong about brass by roughly 3x and wrong about steel by roughly 18x -- so
## the knowledge does not transfer, and each pair has to be explored on its own
## terms. One authored ratio could never do this.
func test_the_knee_is_wildly_different_per_pair_so_one_ratio_does_not_transfer() -> void:
	var bronze: float = AlloyBlend.second_phase_onset("copper", "tin")
	var brass: float = AlloyBlend.second_phase_onset("copper", "zinc")
	var steel: float = AlloyBlend.second_phase_onset("iron", "carbon")

	assert_between(brass / bronze, 2.5, 3.5, "brass wants ~3x the solute bronze does")
	assert_between(bronze / steel, 15.0, 20.0, "and steel wants ~18x LESS than bronze")

	# And the practical consequence: taking bronze's ratio to the forge and
	# using it on iron does not give you a slightly-off steel, it gives you
	# something well past cast iron that shatters.
	var bronze_ratio_applied_to_iron: Dictionary = AlloyBlend.blend("iron", "carbon", bronze)
	assert_lt(float(bronze_ratio_applied_to_iron["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"13.5%% carbon is not steel by any stretch -- it is twice cementite's own carbon content")


## The optimum is defined by the microstructure, not by a utility function
## someone chose: it is the last composition whose brittle-phase fraction is
## still exactly zero. One step further and the network exists.
func test_the_optimum_is_the_last_composition_free_of_the_brittle_network() -> void:
	for pair in [["copper", "tin"], ["copper", "zinc"], ["copper", "arsenic"], ["iron", "carbon"]]:
		var optimum: float = AlloyBlend.optimal_solute_fraction(pair[0], pair[1])
		assert_almost_eq(AlloyBlend.brittle_phase_fraction(pair[0], pair[1], optimum), 0.0, 1.0e-9,
			"%s-%s's optimum must still be a single-phase alloy" % pair)
		assert_gt(AlloyBlend.brittle_phase_fraction(pair[0], pair[1], optimum + 0.001), 0.0,
			"%s-%s: one step past the optimum the brittle network must exist" % pair)


## "Richest single-phase" is only the same thing as "hardest single-phase"
## because hardness climbs all the way to the boundary and never doubles back.
## That is a real claim about the curve, so it is scanned rather than assumed --
## if it were false, the optimum would sit somewhere inside the field and the
## three historical answers above would be a coincidence.
func test_hardness_climbs_all_the_way_to_the_boundary_for_every_modeled_pair() -> void:
	for pair in [["copper", "tin"], ["copper", "zinc"], ["copper", "arsenic"], ["iron", "carbon"]]:
		var onset: float = AlloyBlend.second_phase_onset(pair[0], pair[1])
		var previous := -1.0
		for step in range(1, 101):
			var c := onset * float(step) / 100.0
			var gain: float = AlloyBlend.solution_strengthening(pair[0], pair[1], c)
			assert_gt(gain, previous,
				"%s-%s's strengthening must still be climbing at %f" % [pair[0], pair[1], c])
			previous = gain


## The coefficient turning lattice misfit into a hardness gain is not eyeballed:
## it is the one sourced anchor in the model, solved for. Cast 88Cu-12Sn bronze
## measures roughly twice annealed copper's hardness (~100 HB against ~50 HB),
## so K is whatever value reproduces that, given a misfit and a solubility
## limit that were both already fixed by real data. This test re-derives it.
func test_the_strengthening_coefficient_is_the_measured_bronze_anchor_solved_for_k() -> void:
	var x: float = AlloyBlend.BRONZE_ANCHOR_TIN_FRACTION
	var baseline := 4.0 * (1.0 - x) + 1.5 * x
	var misfit: float = AlloyBlend.lattice_misfit("copper", "tin")
	var saturation: float = pow(x / AlloyBlend.second_phase_onset("copper", "tin"), AlloyBlend.LABUSCH_EXPONENT)
	var solved: float = (AlloyBlend.BRONZE_ANCHOR_HARDNESS_RATIO * 4.0 / baseline - 1.0) / (misfit * saturation)
	assert_almost_eq(AlloyBlend.SOLUTION_STRENGTHENING_COEFFICIENT, solved, 0.001,
		"K must be the bronze hardness anchor solved for, not a number that felt right")


## And the anchor itself has to come back out: historical bronze really is
## about twice as hard as the copper it replaced.
func test_historical_bronze_lands_on_twice_pure_coppers_hardness() -> void:
	var bronze: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	assert_almost_eq(float(bronze["hardness"]), 2.0 * mp.property_value("copper", "hardness"), 0.01)


## Why 10-12% tin and not 15.8%, where the model's peak actually sits: because
## strengthening goes as the SQUARE ROOT of solute concentration (Fleischer),
## so by 12% tin you already hold ~87% of everything the lattice has to give,
## and the remaining tin buys almost no hardness while still costing toughness
## and scarce, expensive tin. The historical recipe sits in the knee of a
## diminishing-returns curve, and the model reproduces that rather than
## asserting it.
func test_historical_bronze_sits_in_the_diminishing_returns_knee() -> void:
	var at_historical: float = AlloyBlend.solution_strengthening("copper", "tin", 0.12)
	var at_peak: float = AlloyBlend.solution_strengthening(
		"copper", "tin", AlloyBlend.second_phase_onset("copper", "tin")
	)
	var realized := at_historical / at_peak
	assert_gt(realized, 0.85, "12%% tin should already realize most of the achievable hardening")
	assert_lt(realized, 0.95, "but not all of it -- there is still a real peak further along")


## The sub-linear rise is the model's shape claim, so pin the EXPONENT directly:
## doubling the tin from 4% to 8% multiplies the gain by 2^(2/3), not by 2 and
## not by sqrt(2).
##
## Rewritten from a version asserting sqrt(2), i.e. Fleischer's law. Fleischer
## is the DILUTE result and is documented as valid below about 1 at% solute.
## Every alloy this model cares about is far outside that: 12 wt% tin in copper
## is 6.8 at%, and 39 wt% zinc is 38 at%. In that concentrated regime the
## published result is Labusch's, where the collective action of solutes on the
## glide plane gives c^(2/3) rather than c^(1/2). Using the dilute law for
## concentrated solutions was the previous model's central error.
func test_strengthening_follows_labuschs_two_thirds_law_not_fleischers_square_root() -> void:
	var at_four: float = AlloyBlend.solution_strengthening("copper", "tin", 0.04)
	var at_eight: float = AlloyBlend.solution_strengthening("copper", "tin", 0.08)
	assert_gt(at_eight, at_four, "more solute is still more strengthening")
	assert_lt(at_eight, 2.0 * at_four,
		"the law is sub-linear -- the first few percent do most of the work")
	assert_almost_eq(at_eight / at_four, pow(2.0, 2.0 / 3.0), 0.01,
		"Labusch's concentrated-solution result is c^(2/3)")
	assert_gt(absf(at_eight / at_four - sqrt(2.0)), 0.1,
		"and it is measurably NOT Fleischer's dilute sqrt(c)")


## Strengthening vanishes at the pure solvent -- there is no solute to
## strengthen it -- and then FREEZES at the boundary rather than continuing to
## climb. That is not a clamp for tidiness: past the boundary the solid
## solution's own composition stops changing (that is what the lever rule
## means -- extra solute makes more second phase, it does not enrich the alpha
## further), so the alpha phase's strengthening genuinely cannot rise any more.
##
## Rewritten from test_strengthening_vanishes_at_both_pure_endpoints, which
## asserted the gain returns to zero at 100% solute. That was true of the old
## two-sided model; under the one-directional solvent/solute model this
## function describes the ALPHA PHASE, which does not exist at all at the far
## end, so asking it about pure tin is asking a question with no referent.
func test_strengthening_vanishes_at_the_pure_solvent_and_freezes_at_the_boundary() -> void:
	assert_almost_eq(AlloyBlend.solution_strengthening("copper", "tin", 0.0), 0.0, 0.0001,
		"pure copper has no solute in it to strengthen it")
	var at_onset: float = AlloyBlend.solution_strengthening(
		"copper", "tin", AlloyBlend.second_phase_onset("copper", "tin")
	)
	assert_almost_eq(AlloyBlend.solution_strengthening("copper", "tin", 0.30), at_onset, 0.0001,
		"past the boundary the alpha phase stops changing, so its strengthening stops rising")


# -- the tradeoff: alloying is never a free lunch ---------------------------

## The single-phase field costs no toughness, and that is not generosity -- it
## is what the metallurgy says. A solid solution is still one ductile phase, and
## the famous case is flatly against the old model: cartridge brass at 30% zinc
## is BOTH stronger than pure copper AND more ductile than it (~65% elongation
## against copper's ~45%). A model that made every alloy less tough than its
## parent metal would be contradicted by the most-produced copper alloy there
## is.
##
## Rewritten from test_toughness_falls_where_hardness_peaks, which asserted
## toughness must fall below the rule-of-mixtures line at the hardness peak.
## That was the old single-regime model's "divide toughness by the same factor
## hardness multiplies by" -- a tidy one-parameter tradeoff that put the
## embrittlement in the wrong place. The tradeoff is real, but it lives past the
## boundary, not throughout, which the next test pins.
func test_toughness_holds_up_through_the_whole_single_phase_field() -> void:
	for pair in [["copper", "tin"], ["copper", "zinc"], ["iron", "carbon"]]:
		var onset: float = AlloyBlend.second_phase_onset(pair[0], pair[1])
		var alloy: Dictionary = AlloyBlend.blend(pair[0], pair[1], onset)
		var rule_of_mixtures := lerpf(
			mp.property_value(pair[0], "toughness"), mp.property_value(pair[1], "toughness"), onset
		)
		assert_almost_eq(float(alloy["toughness"]), rule_of_mixtures, 0.0001,
			"%s-%s is still one ductile phase at its boundary -- no embrittlement yet" % pair)
		assert_gt(float(alloy["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
			"%s-%s's optimum must be a usable tool, not a shatterable one" % pair)


## And past the boundary it collapses, by the lever rule, for a named reason: a
## brittle intermetallic precipitating on the grain boundaries is a continuous
## crack highway, and a crack that finds one does not have to break anything
## tough on its way through. Toughness therefore falls linearly toward the
## intermetallic's own (zero) toughness as its volume fraction grows.
func test_toughness_collapses_by_the_lever_rule_once_the_brittle_phase_appears() -> void:
	var onset: float = AlloyBlend.second_phase_onset("copper", "tin")
	var at_onset: float = AlloyBlend.blend("copper", "tin", onset)["toughness"]
	for probe in [0.18, 0.22, 0.28]:
		var fraction: float = AlloyBlend.brittle_phase_fraction("copper", "tin", probe)
		assert_almost_eq(float(AlloyBlend.blend("copper", "tin", probe)["toughness"]),
			at_onset * (1.0 - fraction), 0.0001,
			"toughness at %f tin must be the lever rule against the delta fraction" % probe)


## The lever rule itself: the second phase's volume fraction is linear between
## the boundary it appears at and the intermetallic's own composition, which is
## the standard construction on any binary phase diagram.
func test_the_brittle_phase_fraction_is_the_lever_rule() -> void:
	var onset: float = AlloyBlend.second_phase_onset("iron", "carbon")
	var compound: float = AlloyBlend.second_phase_solute_fraction("iron", "carbon")
	assert_almost_eq(AlloyBlend.brittle_phase_fraction("iron", "carbon", onset), 0.0, 1.0e-9,
		"at the eutectoid there is no proeutectoid cementite yet")
	assert_almost_eq(AlloyBlend.brittle_phase_fraction("iron", "carbon", compound), 1.0, 1.0e-9,
		"at 6.67%% carbon the alloy IS cementite")
	var midpoint := (onset + compound) / 2.0
	assert_almost_eq(AlloyBlend.brittle_phase_fraction("iron", "carbon", midpoint), 0.5, 1.0e-9,
		"and halfway between them it is half cementite -- that is all the lever rule is")


## Real high-tin bronze -- bell bronze, mirror bronze, 20-30% Sn -- is famously
## brittle: a cracked bell is a cliche because bells really do crack. Weapons
## bronze at 12% is not. The game's OWN shipped brittleness cutoff separates the
## two, with no rule anywhere that mentions bells.
func test_high_tin_bell_bronze_reads_brittle_where_weapons_bronze_does_not() -> void:
	assert_gt(float(AlloyBlend.blend("copper", "tin", 0.12)["toughness"]),
		MaterialProperties.BRITTLE_TOUGHNESS,
		"12%% weapons bronze must not shatter -- it was the best tool metal for two millennia")
	assert_lt(float(AlloyBlend.blend("copper", "tin", 0.30)["toughness"]),
		MaterialProperties.BRITTLE_TOUGHNESS,
		"30%% mirror bronze must shatter")
	# Where the crossover actually lands, scanned rather than asserted: the
	# model puts it around 25% tin against a real ~20%, so it is a little
	# generous to high-tin bronze. Recorded, not hidden.
	var crossover := 1.0
	for step in range(0, 1001):
		var c := float(step) / 1000.0
		if float(AlloyBlend.blend("copper", "tin", c)["toughness"]) < MaterialProperties.BRITTLE_TOUGHNESS:
			crossover = c
			break
	assert_between(crossover, 0.20, 0.30,
		"the brittleness crossover must land in the real high-tin-bronze band")


## Hardness and toughness must move in opposite directions across the whole
## single-phase range -- one curve, not two independent ones that could drift
## into "harder and tougher at the same time".
func test_hardness_and_toughness_move_in_opposite_directions() -> void:
	var previous_hardness := -1.0
	var previous_toughness := INF
	for step in range(0, 16):
		var x := float(step) / 100.0
		var alloy: Dictionary = AlloyBlend.blend("copper", "tin", x)
		if step > 0:
			assert_gt(float(alloy["hardness"]), previous_hardness,
				"hardness should still be climbing at %f tin" % x)
			assert_lt(float(alloy["toughness"]), previous_toughness,
				"toughness should still be falling at %f tin" % x)
		previous_hardness = float(alloy["hardness"])
		previous_toughness = float(alloy["toughness"])


## Edge retention is a consequence of hardness -- a soft metal's edge rolls
## over on first contact, which is why copper knives lost to flint and bronze
## ones did not. So sharpness_capacity carries the same strengthening factor,
## and bronze ends up out-edging early wrought iron: historically correct, and
## the reason iron took centuries to displace bronze on anything but cost.
func test_bronze_holds_a_better_edge_than_copper() -> void:
	var bronze: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	assert_gt(float(bronze["sharpness_capacity"]), mp.property_value("copper", "sharpness_capacity"),
		"a harder alloy holds a finer edge -- otherwise bronze blades make no sense")
	assert_lt(float(bronze["sharpness_capacity"]), mp.property_value("obsidian", "sharpness_capacity"),
		"but nothing out-edges obsidian, which is a molecular fracture edge")


# -- the asymmetric interstitial case, and the scale it breaks ---------------

## The same machinery, with iron's far smaller carbon solubility and carbon's
## far larger misfit, gives the steel curve for free -- no second model.
func test_a_trace_of_carbon_hardens_iron_far_faster_than_tin_hardens_copper() -> void:
	var steel_gain: float = AlloyBlend.solution_strengthening("iron", "carbon", 0.008)
	var bronze_gain: float = AlloyBlend.solution_strengthening("copper", "tin", 0.008)
	assert_gt(steel_gain, 10.0 * bronze_gain,
		"0.8%% carbon must do enormously more than 0.8%% tin -- interstitial, and a 15x smaller solubility limit")


## Honest limitation, pinned rather than hidden. The real hardness range from
## annealed copper (~50 HV) to quenched tool steel (~800 HV) is a factor of 16,
## and the existing table already spends its 0-10 budget putting copper at 4
## and iron at 8. So steel saturates the scale: the model is not wrong, the
## SCALE has no headroom left above iron. This is the single biggest known
## limitation of this slice and is written up in smelting.md's open questions.
func test_steel_saturates_the_games_hardness_scale() -> void:
	var steel: Dictionary = AlloyBlend.blend("iron", "carbon", 0.008)
	assert_almost_eq(float(steel["hardness"]), AlloyBlend.SCALE_MAX, 0.0001,
		"steel pins the 0-10 hardness scale -- a real limitation of the scale, not of the model")
	var mild: Dictionary = AlloyBlend.blend("iron", "carbon", 0.001)
	assert_almost_eq(float(mild["hardness"]), AlloyBlend.SCALE_MAX, 0.0001,
		"even 0.1%% carbon pins it: the scale cannot tell mild steel from tool steel")


## What the scale CAN still express past saturation is the cost. Hardness
## flattens against the ceiling while toughness keeps collapsing, so more
## carbon past the eutectoid is pure downside -- and this is now the right
## answer about cast iron for the RIGHT reason: cementite is modeled, and the
## toughness fall is its lever-rule volume fraction rather than an incidental
## consequence of the hardness clamp. (smelting.md's divergence 4 previously
## recorded that it was the right answer for the wrong reason. It no longer is.)
func test_past_the_hardness_ceiling_extra_carbon_only_costs_toughness() -> void:
	var eutectoid: Dictionary = AlloyBlend.blend("iron", "carbon", 0.008)
	var cast_iron: Dictionary = AlloyBlend.blend("iron", "carbon", 0.018)
	assert_almost_eq(float(cast_iron["hardness"]), float(eutectoid["hardness"]), 0.0001,
		"both are clamped at the ceiling -- no further hardness to be had")
	assert_lt(float(cast_iron["toughness"]), float(eutectoid["toughness"]),
		"but the extra carbon still costs toughness, so cast iron is the worse trade")


## Cast iron shatters, and feeding it to the impact model's EXISTING brittle
## rule with no new downstream logic is the payoff smelting.md's design asked
## for.
##
## Rewritten from a version that asserted this of 0.8% carbon steel. That was
## the old model saying eutectoid steel is brittle, which is simply false --
## normalized 0.76% pearlitic steel is the classic tough edged-tool material,
## and if it came out brittle the historical optimum this rewrite reproduces
## would be nonsense. What IS brittle is hypereutectoid iron, once the
## proeutectoid cementite network exists; the model now says exactly that,
## because the network is what it models.
func test_cast_iron_comes_out_brittle_by_the_impact_models_own_cutoff() -> void:
	var eutectoid: Dictionary = AlloyBlend.blend("iron", "carbon", 0.0076)
	assert_gt(float(eutectoid["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"eutectoid steel is the classic tough edged-tool material, not a shatterable one")
	var cast_iron: Dictionary = AlloyBlend.blend("iron", "carbon", 0.043)
	assert_lt(float(cast_iron["toughness"]), MaterialProperties.BRITTLE_TOUGHNESS,
		"cast iron at the 4.3%% eutectic is brittle -- which is why cast-iron pots crack and do not dent")


## Nothing on the legibility scale may exceed it, including the alloys.
func test_no_blended_scalar_ever_leaves_the_zero_to_ten_scale() -> void:
	for material in MaterialProperties.MATERIALS:
		for property_name in MaterialProperties.MATERIALS[material]:
			if property_name == "density":
				continue
			assert_lte(float(MaterialProperties.MATERIALS[material][property_name]), AlloyBlend.SCALE_MAX,
				"%s.%s is off the scale SCALE_MAX is pinned to" % [material, property_name])
	for step in range(0, 101):
		var x := float(step) / 100.0
		for pair in [["copper", "tin"], ["iron", "carbon"]]:
			var alloy: Dictionary = AlloyBlend.blend(pair[0], pair[1], x)
			for property_name in alloy:
				if property_name == "density":
					continue
				assert_lte(float(alloy[property_name]), AlloyBlend.SCALE_MAX,
					"%s/%s at %f pushed %s off the scale" % [pair[0], pair[1], x, property_name])


# -- eutectic melting depression --------------------------------------------
#
# The third real effect, and the one with a progression lever attached: an
# alloy can melt LOWER than either metal that went into it, which decides
# whether a given furnace can work it at all. Deliberately NOT part of the
# eight-scalar vector -- see melting_point_c's own doc comment for why.

func test_the_pure_endpoints_are_the_real_measured_melting_points() -> void:
	assert_almost_eq(AlloyBlend.melting_point_c("copper", "tin", 0.0), 1084.62, 0.1,
		"pure copper melts at 1084.62 C")
	assert_almost_eq(AlloyBlend.melting_point_c("copper", "tin", 1.0), 231.93, 0.1,
		"pure tin melts at 231.93 C")
	assert_almost_eq(AlloyBlend.melting_point_c("iron", "carbon", 0.0), 1537.85, 0.1,
		"pure iron melts at 1538 C")


## The headline surprise, and it is checkable: 88Cu-12Sn bronze pours at about
## 1000 C where pure copper needs 1085. The van 't Hoff cryoscopic law
## reproduces that to within a few kelvin from nothing but copper's melting
## point and its enthalpy of fusion -- no fitted alloy constant at all.
func test_bronze_melts_measurably_below_pure_copper_matching_the_real_liquidus() -> void:
	var bronze_c: float = AlloyBlend.melting_point_c("copper", "tin", 0.12)
	assert_lt(bronze_c, AlloyBlend.melting_point_c("copper", "tin", 0.0),
		"adding tin must LOWER the melting point -- the whole reason bronze is castable")
	assert_almost_eq(bronze_c, 1000.0, 12.0,
		"the real Cu-12Sn liquidus is ~1000 C")


## The same untuned law, on the other real system, lands within ~50 K of the
## Fe-C eutectic at 1147 C -- which is exactly why cast iron can be poured in a
## furnace that cannot come close to melting wrought iron. A real progression
## gate, arrived at from published thermodynamic constants.
func test_carbon_drops_irons_melting_point_toward_the_real_cast_iron_eutectic() -> void:
	var cast_iron_c: float = AlloyBlend.melting_point_c("iron", "carbon", 0.043)
	assert_almost_eq(cast_iron_c, 1147.0, 60.0,
		"4.3%% carbon is the real Fe-C eutectic at 1147 C")
	assert_lt(cast_iron_c, AlloyBlend.melting_point_c("iron", "carbon", 0.0) - 300.0,
		"it must be dramatically below wrought iron's 1538 C, not marginally")


## The eutectic is not authored anywhere: it is where the two cryoscopic
## branches cross. That it exists at all, below both pure melting points, is an
## emergent consequence of two published enthalpies of fusion.
func test_a_eutectic_emerges_below_both_pure_melting_points() -> void:
	var eutectic_x: float = AlloyBlend.eutectic_fraction("copper", "tin")
	assert_gt(eutectic_x, 0.0, "the eutectic must be a real interior composition")
	assert_lt(eutectic_x, 1.0)
	var eutectic_c: float = AlloyBlend.melting_point_c("copper", "tin", eutectic_x)
	assert_lt(eutectic_c, AlloyBlend.melting_point_c("copper", "tin", 0.0))
	assert_lt(eutectic_c, AlloyBlend.melting_point_c("copper", "tin", 1.0),
		"a eutectic melts below BOTH constituents -- that is what makes it a eutectic")


## And it sits on the tin-rich side, which is the right qualitative answer (the
## real Cu-Sn eutectic is at 99.3 wt% Sn). The model does NOT get its position
## right quantitatively -- the ideal-solution linearization is only honest near
## the dilute ends -- so only the side is asserted. See melting_point_c's doc
## comment and smelting.md's open questions.
func test_the_copper_tin_eutectic_falls_on_the_tin_rich_side() -> void:
	assert_gt(AlloyBlend.eutectic_fraction("copper", "tin"), 0.5)


## The eutectic really is the minimum of the liquidus envelope, not merely a
## crossing point -- scanned, because that is the claim.
func test_the_eutectic_is_the_minimum_of_the_liquidus_curve() -> void:
	var eutectic_c: float = AlloyBlend.melting_point_c(
		"copper", "tin", AlloyBlend.eutectic_fraction("copper", "tin")
	)
	for step in range(0, 1001):
		var x := float(step) / 1000.0
		assert_gte(AlloyBlend.melting_point_c("copper", "tin", x), eutectic_c - 0.5,
			"nothing may melt below the eutectic, but %f did" % x)


## Wood does not have a melting point; it chars. Saying so is the honest answer
## and is distinguishable from a number.
func test_a_material_with_no_liquidus_reports_that_it_does_not_melt() -> void:
	assert_eq(AlloyBlend.melting_point_c("wood", "fiber", 0.5), AlloyBlend.DOES_NOT_MELT)
	assert_eq(AlloyBlend.eutectic_fraction("wood", "fiber"), AlloyBlend.NO_EUTECTIC,
		"two things that do not melt have no eutectic between them")


## Carbon has no liquidus at atmospheric pressure at all -- graphite sublimes
## rather than melting -- so Fe-C is carried by iron's branch alone. That is
## not a shortcut around a missing number, it is the physically correct
## treatment, and it is why the Fe-C result above is as accurate as it is.
func test_a_pair_with_one_liquidus_still_melts_by_its_solvents_branch() -> void:
	assert_true(is_finite(AlloyBlend.melting_point_c("iron", "carbon", 0.008)),
		"steel obviously melts even though graphite has no melting point")
	assert_eq(AlloyBlend.eutectic_fraction("iron", "carbon"), AlloyBlend.NO_EUTECTIC,
		"one branch cannot cross anything -- no eutectic is computable here")


## Cryoscopic depression counts PARTICLES IN SOLUTION, so a constituent that
## never enters solution cannot lower anything's freezing point. Sawdust
## stirred into molten tin is a suspension, not an alloy: the tin still
## freezes at 231.93 C, and crushed stone in molten copper still freezes at
## copper's 1084.62 C.
##
## This is the bug the mass-fraction -> mole-fraction conversion hid. When a
## constituent has no molar mass to convert with, _mole_fraction_b falls back
## to returning the MASS fraction unchanged -- which the liquidus branches then
## consumed as though it were a real dissolved mole fraction. A half-wood,
## half-tin "alloy" therefore reported melting at 81 C, 150 K below pure tin,
## purely because wood is not in the table.
func test_a_constituent_that_never_dissolves_cannot_depress_the_melting_point() -> void:
	var pure_tin: float = AlloyBlend.melting_point_c("copper", "tin", 1.0)
	assert_almost_eq(AlloyBlend.melting_point_c("wood", "tin", 0.5), pure_tin, 0.01,
		"wood does not dissolve in tin, so it cannot lower tin's freezing point")
	var pure_copper: float = AlloyBlend.melting_point_c("copper", "tin", 0.0)
	assert_almost_eq(AlloyBlend.melting_point_c("copper", "stone", 0.5), pure_copper, 0.01,
		"crushed stone in molten copper is a suspension, not a solution")


## The guard on the fix above: a real dissolved element must still depress the
## liquidus exactly as before. Carbon is the case that proves the distinction is
## "is this a dissolved element" and not "does this melt" -- graphite has no
## melting point of its own at all, yet dissolved carbon genuinely does drop
## iron's liquidus, which is the entire cast-iron progression gate.
func test_a_dissolved_element_still_depresses_the_liquidus() -> void:
	assert_lt(
		AlloyBlend.melting_point_c("iron", "carbon", 0.043),
		AlloyBlend.melting_point_c("iron", "carbon", 0.0) - 300.0,
		"carbon has no liquidus but DOES dissolve, so it must still depress iron's"
	)


func test_melting_is_symmetric_under_swapping_the_two_materials() -> void:
	for step in range(0, 101):
		var x := float(step) / 100.0
		assert_almost_eq(
			AlloyBlend.melting_point_c("copper", "tin", x),
			AlloyBlend.melting_point_c("tin", "copper", 1.0 - x),
			0.01, "which material you call 'a' cannot change what the alloy melts at"
		)


## Melting is deliberately absent from the blended vector: an alloy vector must
## stay identical in shape to a MATERIALS row so nothing downstream needs to
## change, and MATERIALS has no melting scalar yet.
func test_melting_is_not_smuggled_into_the_property_vector() -> void:
	var bronze: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	assert_false(bronze.has("melting_point_c"),
		"the vector stays eight scalars; melting is a separate, additive question")


# -- the payoff, in the player's own words ----------------------------------
#
# The point of keeping the result shape-identical to a MATERIALS row is that
# the existing descriptor vocabulary reads it with no new downstream logic.
# These are the only tests here that touch anything outside this module, and
# they exist because a blend nothing can consume is not a feature.

## Copper on its own is notable for nothing the game has a word for. Alloy it
## and the SAME vocabulary calls it hard -- the discovery, surfaced.
func test_alloying_copper_produces_something_the_game_can_call_hard() -> void:
	assert_eq(mp.descriptors_for("copper"), [] as Array[String],
		"pure copper is unremarkable -- soft, unremarkable edge, sinks")
	var bronze: Dictionary = AlloyBlend.blend("copper", "tin", 0.12)
	assert_true(mp.descriptors_for_vector(bronze).has("hard"),
		"bronze must read as hard where copper did not -- that is the emergence, in one word")
	assert_false(mp.descriptors_for_vector(bronze).has("brittle"),
		"but 12%% tin is still a usable tool, not a shatterable one")


## And the same vocabulary separates the two ferrous alloys exactly as they
## deserve, through the impact model's own brittleness cutoff, with no rule
## written anywhere that says "steel" or "cast iron". Eutectoid steel is hard
## and keen; four percent more carbon and it is hard, keen and brittle.
##
## Rewritten from test_high_carbon_iron_reads_as_hard_keen_and_brittle, which
## expected "brittle" of 0.8% carbon. See
## test_cast_iron_comes_out_brittle_by_the_impact_models_own_cutoff for why that
## was the wrong invariant.
func test_the_descriptor_vocabulary_separates_eutectoid_steel_from_cast_iron() -> void:
	var steel: Dictionary = AlloyBlend.blend("iron", "carbon", 0.0076)
	assert_eq(mp.descriptors_for_vector(steel), ["hard", "keen"] as Array[String],
		"eutectoid steel: the best edge in the game, and it does not shatter")
	var cast_iron: Dictionary = AlloyBlend.blend("iron", "carbon", 0.043)
	assert_eq(mp.descriptors_for_vector(cast_iron), ["hard", "keen", "brittle"] as Array[String],
		"cast iron: just as hard, and it shatters")
