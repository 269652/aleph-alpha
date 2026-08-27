extends RefCounted

const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

## Blend two mineral property vectors into a third, by real metallurgy.
##
## docs/concept/materials.md's 2026-08-24 revision is the whole brief: an alloy
## is "just one more way to arrive at a property vector", so this file's only
## output is an ordinary eight-scalar vector of exactly the shape
## material_properties.gd's MATERIALS rows already have. Nothing downstream --
## impact_resolver, descriptors_for, mass_kg_for -- learns a new type.
##
## The point of the exercise is that the blend is NOT LINEAR. A linear
## interpolation between two property vectors is a calculator: every alloy
## lands between its parents and there is nothing to find. Real metallurgy has
## peaks -- bronze is harder than copper AND harder than tin -- and peaks are
## what make a composition space worth searching. Everything non-linear in here
## is a named, documented real effect, not a curve shaped until it felt good.
##
## Deliberately NOT in this file: heat treatment. What comes out is an as-cast
## / as-quenched vector. Quenched high-carbon steel really is hard and really
## does shatter; tempering (which trades hardness back for toughness) is a
## separate OPERATION on a finished part, not a property of a composition, and
## belongs in whatever models the forge.


## The eight scalars a blend produces, in MATERIALS' own order. Kept as an
## explicit list rather than iterating DEFAULT_PROPERTIES so that adding a
## ninth scalar to the shared table is a deliberate decision here too.
const BLENDED_PROPERTIES: Array[String] = [
	"density",
	"hardness",
	"toughness",
	"elasticity",
	"sharpness_capacity",
	"flammability",
	"conductivity",
	"decay_rate",
]

## Scalars with no modeled non-linearity: a plain rule of mixtures.
##
## Real alloys track the linear mix closely for these, and where they do not
## the game's 0-10 scale cannot honestly express the deviation -- see this
## file's conductivity note (Nordheim's rule) in docs/concept/smelting.md's
## open questions.
const LINEAR_PROPERTIES: Array[String] = [
	"elasticity",
	"flammability",
	"conductivity",
	"decay_rate",
]

## The top of materials.md's "roughly 0..10" legibility scale, pinned to the
## largest value the existing table actually uses (obsidian's
## sharpness_capacity of 10.0) rather than declared. Density is exempt: it is
## a real g/cm^3 measurement, not a legibility score.
const SCALE_MAX: float = 10.0

## Metallic radii in picometres, from standard tables. These are the ONLY
## atomic data the strengthening model needs, and they are measurements, not
## settings: the size mismatch between a solute atom and the hole it has to sit
## in is what physically impedes dislocation motion, so it is what the model is
## built out of. Carbon's 77 pm is its covalent radius -- carbon in iron is not
## a metal atom sitting in a metal lattice.
const METALLIC_RADIUS_PM: Dictionary = {
	"copper": 128.0,
	"tin": 140.0,
	"iron": 126.0,
	"carbon": 77.0,
}

## Solutes small enough to squeeze into the gaps BETWEEN host atoms instead of
## replacing one. Keyed by solute alone because that is what the distinction
## actually depends on -- carbon is interstitial in essentially every metal
## that will take it, not just in iron.
const INTERSTITIAL_SOLUTES: Array[String] = ["carbon"]

## An octahedral hole in a close-packed lattice has exactly sqrt(2) - 1 times
## the radius of the atoms packed around it. Pure packing geometry -- derived,
## never chosen -- and it is the whole reason interstitial solutes are so much
## more potent than substitutional ones: carbon's 77 pm has to fit a 52 pm
## hole, a 48% overstuff, against tin's mere 9% size mismatch in copper.
## Restated as a literal because GDScript consts cannot call sqrt(); pinned
## equal to sqrt(2) - 1 by test_the_interstitial_site_ratio_is_the_exact_
## packing_geometry_result.
const OCTAHEDRAL_SITE_RADIUS_RATIO: float = 0.4142135624

## Maximum solid solubility, as a mass fraction of SOLUTE in SOLVENT, read off
## the published binary phase diagrams:
##
## - 15.8 wt% Sn in Cu (the alpha-bronze boundary at 520 C).
## - 2.1 wt% C in austenitic Fe (the boundary at 1147 C).
##
## Both reverse directions are ~0: tin dissolves essentially no copper, and
## graphite dissolves no iron at all. That asymmetry is not a simplification,
## it IS the Cu-Sn and Fe-C systems, and it is what lets one model produce both
## bronze's broad symmetric-looking bulge and steel's violent early spike.
##
## A pair absent from this table has no modeled metallurgy and gets a pure rule
## of mixtures -- an honest "not modeled", not an invented curve.
const SOLID_SOLUBILITY: Dictionary = {
	"copper": {"tin": 0.158},
	"tin": {"copper": 0.0},
	"iron": {"carbon": 0.021},
	"carbon": {"iron": 0.0},
}

## The one sourced anchor in the whole model. Cast 88Cu-12Sn bronze measures
## roughly twice annealed copper's hardness (~100 HB against ~50 HB), and
## 12% tin is the composition the Bronze Age actually settled on.
const BRONZE_ANCHOR_TIN_FRACTION: float = 0.12
const BRONZE_ANCHOR_HARDNESS_RATIO: float = 2.0

## Lattice misfit -> relative hardness gain. NOT eyeballed: the misfit (0.09375)
## and the solubility limit (0.158) were both already fixed by real
## measurements, so this is the single remaining unknown and it is the bronze
## anchor above SOLVED FOR, not tuned:
##
##   K = (ratio * H_copper / baseline(x) - 1) / (misfit * sqrt(x / solubility))
##     = (2.0 * 4.0 / 3.70 - 1) / (0.09375 * 0.87149)
##     = 14.2244
##
## Re-derived from the anchors by test_the_strengthening_coefficient_is_the_
## measured_bronze_anchor_solved_for_k, so it cannot drift away from the
## measurement it encodes.
const SOLUTION_STRENGTHENING_COEFFICIENT: float = 14.2244

## Published physical constants for the elements the melting model needs.
##
## These are NOT a second property vector and must not become one: molar mass
## and enthalpy of fusion are real measurements that simply cannot be derived
## from the game's 0-10 legibility scalars, and the alternative to looking them
## up is inventing a melting curve.
##
## `molar_mass_g` is present for every element here, because the mass fraction
## a smith weighs out has to become a MOLE fraction before any of the
## thermodynamics applies. `melting_k`/`fusion_j_per_mol` are optional and
## their absence is a real physical statement: carbon has neither because
## graphite does not melt at atmospheric pressure, it sublimes at ~3915 K. So
## Fe-C runs on iron's liquidus branch alone -- correct physics, not a missing
## row -- while carbon still counts properly as dissolved particles.
##
## A material absent entirely (wood, flesh, stone) is not an element and has no
## liquidus at all.
const ELEMENT_CONSTANTS: Dictionary = {
	"copper": {"molar_mass_g": 63.546, "melting_k": 1357.77, "fusion_j_per_mol": 13260.0},
	"tin": {"molar_mass_g": 118.710, "melting_k": 505.08, "fusion_j_per_mol": 7030.0},
	"iron": {"molar_mass_g": 55.845, "melting_k": 1811.0, "fusion_j_per_mol": 13810.0},
	"carbon": {"molar_mass_g": 12.011},
}

## The molar gas constant, J/(mol K). A defined SI value since 2019.
const GAS_CONSTANT: float = 8.314462618

const ABSOLUTE_ZERO_C: float = -273.15

## What melting_point_c answers for something that has no liquidus. Wood chars
## and flesh cooks; neither has a melting point, and INF says "there is no
## temperature at which this pours" rather than pretending to a number.
const DOES_NOT_MELT: float = INF

## What eutectic_fraction answers when fewer than two constituents have a
## liquidus, so there is nothing for two branches to cross.
const NO_EUTECTIC: float = -1.0


## The composition, as a mass fraction of `material_b`, that yields the alloy.
##
## Both endpoints are returned EXACTLY rather than computed, because the
## harmonic density mix round-trips 1/(1/rho) with float error and an alloy
## that is 0% tin has to BE copper, bit for bit, not copper to six decimals.
static func blend(material_a: String, material_b: String, fraction_b: float) -> Dictionary:
	var properties := MaterialProperties.new()
	var x := clampf(fraction_b, 0.0, 1.0)
	if is_zero_approx(x):
		return _vector_of(properties, material_a)
	if is_equal_approx(x, 1.0):
		return _vector_of(properties, material_b)

	var alloy: Dictionary = {}
	for property_name in BLENDED_PROPERTIES:
		var a_value := properties.property_value(material_a, property_name)
		var b_value := properties.property_value(material_b, property_name)
		alloy[property_name] = lerpf(a_value, b_value, x)
	alloy["density"] = _mass_weighted_density(
		properties.property_value(material_a, "density"),
		properties.property_value(material_b, "density"),
		x
	)

	# The one non-linearity, applied to the three scalars it physically
	# reaches. Everything else stays on the rule-of-mixtures line above.
	var gain := 1.0 + solution_strengthening(material_a, material_b, x)
	alloy["hardness"] = minf(float(alloy["hardness"]) * gain, SCALE_MAX)
	# Strength-ductility tradeoff, the "banana curve" every alloy system lies
	# on: the same solute atoms that pin dislocations stop the metal deforming
	# gracefully, so roughly doubling the strength roughly halves the
	# elongation. Dividing by the same factor hardness multiplies by is the
	# honest one-parameter form of that -- it uses no second tuned number, and
	# it guarantees the tradeoff can never silently vanish.
	alloy["toughness"] = float(alloy["toughness"]) / gain
	# Edge retention is downstream of hardness: a soft metal's edge rolls over
	# on first contact. That is why a copper knife lost to a flint one and a
	# bronze knife did not, so sharpness_capacity has to ride the same factor
	# rather than mix linearly (which would make bronze a WORSE blade than
	# copper -- visibly the wrong answer).
	alloy["sharpness_capacity"] = minf(float(alloy["sharpness_capacity"]) * gain, SCALE_MAX)
	return alloy


## The relative hardness gain an alloy gets over its own rule-of-mixtures
## baseline, as a fraction (0.0 = no gain, 1.0 = twice the baseline).
##
## ## The model, and why it has this shape
##
## Solid-solution strengthening: a solute atom of the wrong size strains the
## host lattice around it, and a dislocation trying to glide past has to do
## work against that strain field. More solute, more obstacles, harder metal.
## Two real facts set the curve:
##
## 1. **Fleischer's law** -- the strengthening goes as the SQUARE ROOT of
##    solute concentration, not linearly. A pure parabola centred at 50/50
##    would be the tidy guess and it would be wrong in the way that matters:
##    it says the first 1% of solute does almost nothing, when in reality the
##    first 1% does more than the tenth. The sqrt puts the steep part at the
##    dilute end, which is why historical recipes are all found down there.
##
## 2. **The solubility limit** -- this, not any chosen peak fraction, is what
##    puts the maximum off-centre. The lattice can only hold so much solute in
##    solution; past that the excess stops dissolving and forms a second phase.
##    So the peak sits AT the solubility limit (15.8% for tin in copper), and
##    the reason historical bronze is 10-12% rather than 15.8% falls out of
##    Fleischer's sqrt: by 12% you already hold 87% of the available hardening,
##    and the rest costs scarce tin and real toughness for almost nothing.
##
## Between the two saturated single-phase regions the alloy is a mechanical
## mixture of them, and a two-phase mixture's properties follow the LEVER RULE
## -- linear in the phase fractions. That is why the middle of the range is
## linear here: not a shortcut, the actual rule for that region.
##
## Both directions are looked up separately (tin in copper, copper in tin), so
## a system where only one direction dissolves anything -- which is both of the
## real systems modeled here -- comes out correctly asymmetric.
static func solution_strengthening(
	material_a: String, material_b: String, fraction_b: float
) -> float:
	var x := clampf(fraction_b, 0.0, 1.0)
	var b_in_a := solid_solubility(material_a, material_b)
	var a_in_b := solid_solubility(material_b, material_a)

	# What each single-phase region is worth once it is fully saturated. A
	# direction that dissolves nothing is worth nothing -- there is no solid
	# solution there to strengthen.
	var alpha_peak := 0.0
	if b_in_a > 0.0:
		alpha_peak = SOLUTION_STRENGTHENING_COEFFICIENT * lattice_misfit(material_a, material_b)
	var beta_peak := 0.0
	if a_in_b > 0.0:
		beta_peak = SOLUTION_STRENGTHENING_COEFFICIENT * lattice_misfit(material_b, material_a)

	if b_in_a > 0.0 and x <= b_in_a:
		return alpha_peak * sqrt(x / b_in_a)
	if a_in_b > 0.0 and x >= 1.0 - a_in_b:
		return beta_peak * sqrt((1.0 - x) / a_in_b)

	var two_phase_span := (1.0 - a_in_b) - b_in_a
	if two_phase_span <= 0.0:
		return 0.0
	var second_phase_share := clampf((x - b_in_a) / two_phase_span, 0.0, 1.0)
	return lerpf(alpha_peak, beta_peak, second_phase_share)


## Maximum mass fraction of `solute` that `solvent` will hold in solution.
## Zero for any pair with no published entry -- see SOLID_SOLUBILITY.
static func solid_solubility(solvent: String, solute: String) -> float:
	var limits: Dictionary = SOLID_SOLUBILITY.get(solvent, {})
	return float(limits.get(solute, 0.0))


## How badly a solute atom fits the site it occupies in the solvent lattice,
## as a fraction of that site's own radius. This is the physical quantity
## strengthening scales with.
##
## A substitutional solute takes an atom's place, so it is measured against the
## host ATOM. An interstitial solute takes a hole's place, so it is measured
## against the much smaller HOLE -- which is why the same formula gives carbon
## in iron five times tin's misfit in copper, and therefore why 0.8% carbon
## does what it takes 12% tin to do.
static func lattice_misfit(solvent: String, solute: String) -> float:
	var solvent_radius := float(METALLIC_RADIUS_PM.get(solvent, 0.0))
	var solute_radius := float(METALLIC_RADIUS_PM.get(solute, 0.0))
	if solvent_radius <= 0.0 or solute_radius <= 0.0:
		return 0.0
	if INTERSTITIAL_SOLUTES.has(solute):
		var site_radius := OCTAHEDRAL_SITE_RADIUS_RATIO * solvent_radius
		return absf(solute_radius - site_radius) / site_radius
	return absf(solute_radius - solvent_radius) / solvent_radius


## The temperature in Celsius at which this composition first becomes liquid --
## its liquidus.
##
## ## Why this is a separate function and not a ninth scalar
##
## materials.md's property list already names "melting/damage thresholds", so
## the shared vector wants this eventually. It is kept out of blend()'s result
## for now on purpose: an alloy vector has to stay shape-identical to a
## MATERIALS row (that is what lets it flow through the existing pipeline
## unchanged), and half the table has no meaningful melting point at all --
## wood chars, flesh cooks, graphite sublimes. Adding a ninth key would either
## make every one of those lie via DEFAULT_PROPERTIES' fallback, or fragment
## the vector. Melting matters because it GATES -- whether a furnace can work
## a given alloy is a real progression lever -- so it is modeled, honestly,
## alongside rather than inside.
##
## ## The physics
##
## Dissolving anything in a melt lowers its freezing point, because the solute
## raises the liquid's entropy and so stabilizes it. For an ideal dilute
## solution the van 't Hoff cryoscopic relation gives the slope exactly:
##
##   dT = (R * T_melt^2 / dH_fusion) * mole_fraction_of_solute
##
## No alloy-specific constant appears anywhere in that -- only each metal's own
## published melting point and enthalpy of fusion. Both branches are computed
## (each metal as the solvent) and the higher one wins, because the liquidus at
## any composition belongs to whichever primary phase can still be solid at the
## higher temperature. Where the two branches cross is the EUTECTIC, and it
## falls out rather than being authored.
##
## ## What this gets right, and what it does not
##
## Validated: Cu-12%Sn comes out at ~1006 C against a real liquidus of ~1000 C,
## and Fe-4.3%C at ~1197 C against the real Fe-C eutectic of 1147 C. Both from
## published constants with nothing fitted.
##
## Not validated: the ideal-dilute linearization over-extrapolates far from
## either pure end, so while a Cu-Sn eutectic does emerge on the correct
## (tin-rich) side, its predicted position (~88 wt% Sn, 169 C) is well off the
## real one (99.3 wt% Sn, 227 C). Real activity coefficients are what close
## that gap and they are not modeled here. The solvent-rich regime -- which is
## where every alloy anyone actually makes lives -- is the part to trust.
static func melting_point_c(material_a: String, material_b: String, fraction_b: float) -> float:
	var x := clampf(fraction_b, 0.0, 1.0)
	var mole_b := _mole_fraction_b(material_a, material_b, x)
	# Only what actually goes INTO solution counts as solute. Cryoscopic
	# depression is a colligative effect -- it counts dissolved particles -- so a
	# constituent with no place in the melt depresses nothing: sawdust in molten
	# tin is a suspension, and the tin still freezes at 231.93 C.
	var branch_a := _liquidus_branch_k(material_a, mole_b if dissolves(material_b) else 0.0)
	var branch_b := _liquidus_branch_k(material_b, (1.0 - mole_b) if dissolves(material_a) else 0.0)
	if is_inf(branch_a) and is_inf(branch_b):
		return DOES_NOT_MELT
	# is_inf covers the "this material has no liquidus" case for exactly one
	# side; maxf then simply picks the branch that exists. Fe-C runs on iron's
	# branch alone for this reason, which is the physically correct treatment:
	# graphite genuinely has no melting point at atmospheric pressure.
	var liquidus_k := maxf(
		branch_a if not is_inf(branch_a) else 0.0,
		branch_b if not is_inf(branch_b) else 0.0
	)
	return maxf(liquidus_k, 0.0) + ABSOLUTE_ZERO_C


## The composition, as a mass fraction of `material_b`, where the two liquidus
## branches cross -- the lowest-melting blend of the pair. NO_EUTECTIC when
## fewer than two of the constituents have a liquidus to cross.
##
## Solved rather than searched: two straight lines in mole-fraction space meet
## at one point, and turning that point back into a mass fraction is the only
## other step.
static func eutectic_fraction(material_a: String, material_b: String) -> float:
	if not _has_liquidus(material_a) or not _has_liquidus(material_b):
		return NO_EUTECTIC
	var a: Dictionary = ELEMENT_CONSTANTS[material_a]
	var b: Dictionary = ELEMENT_CONSTANTS[material_b]
	var slope_a := _cryoscopic_slope_k(material_a)
	var slope_b := _cryoscopic_slope_k(material_b)
	if slope_a + slope_b <= 0.0:
		return NO_EUTECTIC
	var mole_b := (float(a["melting_k"]) - float(b["melting_k"]) + slope_b) / (slope_a + slope_b)
	mole_b = clampf(mole_b, 0.0, 1.0)
	var mass_b := mole_b * float(b["molar_mass_g"])
	var mass_a := (1.0 - mole_b) * float(a["molar_mass_g"])
	if mass_a + mass_b <= 0.0:
		return NO_EUTECTIC
	return mass_b / (mass_a + mass_b)


## One liquidus branch in kelvin: `material` as the solvent, depressed by
## `solute_mole_fraction` of everything else. INF when `material` has no
## liquidus at all -- the caller treats that as "this branch does not exist"
## rather than as a temperature.
static func _liquidus_branch_k(material: String, solute_mole_fraction: float) -> float:
	if not _has_liquidus(material):
		return INF
	var melting_k := float(ELEMENT_CONSTANTS[material]["melting_k"])
	return melting_k - _cryoscopic_slope_k(material) * solute_mole_fraction


## Whether this material enters solution at all -- i.e. whether it is one of the
## elements this model has real molar data for, and can therefore contribute
## dissolved particles to a melt.
##
## Deliberately keyed on molar mass rather than on melting point, because those
## are two different questions and carbon is the case that separates them:
## graphite has no liquidus of its own (it sublimes) yet dissolved carbon very
## much does depress iron's, which is the whole cast-iron progression gate.
## Anything absent from ELEMENT_CONSTANTS -- wood, stone, flesh -- is not an
## element and cannot dissolve in anything; it rides along as a suspension.
static func dissolves(material: String) -> bool:
	return float(ELEMENT_CONSTANTS.get(material, {}).get("molar_mass_g", 0.0)) > 0.0


## Whether this material has a liquidus at all -- i.e. whether it is a thing
## that melts rather than one that chars or sublimes.
static func _has_liquidus(material: String) -> bool:
	var constants: Dictionary = ELEMENT_CONSTANTS.get(material, {})
	return constants.has("melting_k") and constants.has("fusion_j_per_mol")


## R * T_melt^2 / dH_fusion -- kelvin of freezing-point depression per unit
## mole fraction of solute. Every term is a published property of the SOLVENT
## alone; nothing here knows what is dissolved in it.
static func _cryoscopic_slope_k(material: String) -> float:
	if not _has_liquidus(material):
		return 0.0
	var constants: Dictionary = ELEMENT_CONSTANTS[material]
	var melting_k := float(constants["melting_k"])
	var fusion := float(constants["fusion_j_per_mol"])
	if fusion <= 0.0:
		return 0.0
	return GAS_CONSTANT * melting_k * melting_k / fusion


## Mass fraction -> mole fraction. The blend axis is a mass fraction throughout
## (that is what a smith actually weighs out), but cryoscopic depression counts
## PARTICLES, so the conversion is not optional -- 12 wt% tin is only 6.8 mol%,
## and 4.3 wt% carbon is a whacking 17.3 mol%. Getting this wrong is exactly
## the bug that first showed up as cast iron melting 250 C too high.
static func _mole_fraction_b(material_a: String, material_b: String, fraction_b: float) -> float:
	var mass_a: float = float(ELEMENT_CONSTANTS.get(material_a, {}).get("molar_mass_g", 0.0))
	var mass_b: float = float(ELEMENT_CONSTANTS.get(material_b, {}).get("molar_mass_g", 0.0))
	if mass_a <= 0.0 or mass_b <= 0.0:
		return fraction_b
	var moles_a := (1.0 - fraction_b) / mass_a
	var moles_b := fraction_b / mass_b
	if moles_a + moles_b <= 0.0:
		return 0.0
	return moles_b / (moles_a + moles_b)


## Density for a given MASS split is the harmonic mix, not the linear one.
##
## Mass fractions do not add to a density -- volume fractions do -- and
## converting between them gives 1/rho = w_a/rho_a + w_b/rho_b exactly. Worth
## the extra line because it is checkable: 88Cu-12Sn lands at 8.72 g/cm^3
## against a measured ~8.78 for real cast tin bronze, where the naive
## mass-fraction average gives 8.76 for the wrong reason.
##
## Falls back to the linear mix if either density is non-positive, which no
## real material has but DEFAULT_PROPERTIES-shaped nonsense could.
static func _mass_weighted_density(density_a: float, density_b: float, fraction_b: float) -> float:
	if density_a <= 0.0 or density_b <= 0.0:
		return lerpf(density_a, density_b, fraction_b)
	var specific_volume := (1.0 - fraction_b) / density_a + fraction_b / density_b
	return 1.0 / specific_volume


static func _vector_of(properties: RefCounted, material: String) -> Dictionary:
	var vector: Dictionary = {}
	for property_name in BLENDED_PROPERTIES:
		vector[property_name] = properties.property_value(material, property_name)
	return vector
