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
## ## Two regimes, split by one published number
##
## The mechanical scalars run on a two-regime model separated by the
## SECOND_PHASE_ONSET of each pair -- the composition, off a real binary phase
## diagram, where a brittle intermetallic starts coming out of solution:
##
## - **Below the onset** the alloy is a single solid solution. Hardness rises by
##   Labusch's concentrated-solution law (c^(2/3)) and toughness simply follows
##   the rule of mixtures, because one ductile phase is still one ductile phase.
## - **Above it** a hard brittle compound precipitates, its volume fraction
##   grows by the LEVER RULE, hardness keeps climbing toward it, and toughness
##   collapses toward zero -- a continuous brittle network on the grain
##   boundaries is a crack highway.
##
## That single number is enough to reproduce three unrelated historical optima
## with nothing else fitted: weapons bronze at 13.5% tin, Muntz metal at 39%
## zinc, and eutectoid steel at 0.76% carbon. See optimal_solute_fraction.
##
## It also means the knowledge does not transfer between pairs, which is the
## whole design argument for a blend SPACE over a recipe list: a player who
## learns "about one part in seven" from bronze is wrong about brass by ~3x and
## wrong about steel by ~18x.
##
## Deliberately NOT in this file: heat treatment. What comes out is an as-cast
## vector. Tempering and quenching -- which trade hardness against toughness on
## a FINISHED part rather than by composition -- are operations, not properties
## of a composition, and belong in whatever models the forge. This is why the
## model says eutectoid steel is tough (as normalized pearlitic steel genuinely
## is) and cannot yet say that the same steel, quenched to martensite, is not.


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
	"zinc": 134.0,
	# Arsenic's 12-coordinate metallic radius. Arsenic substitutes for copper in
	# the fcc lattice rather than squeezing between atoms, so it is measured the
	# ordinary substitutional way. Its misfit against copper (~9%) comes out
	# almost identical to tin's, which is the right answer: arsenical bronze and
	# tin bronze really are comparable metals, and arsenic was used FIRST
	# because it comes out of the same ores and needs no tin trade at all.
	"arsenic": 139.0,
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

## The composition at which a continuous brittle SECOND PHASE starts to appear,
## as a mass fraction of SOLUTE in SOLVENT, read off the published binary phase
## diagrams. This one number per pair is what separates the model's two regimes,
## and it is the single most important input in the file.
##
## - **Cu-Sn 13.5 wt%.** The practical as-cast limit: published casting practice
##   is that no macroscopic segregation occurs below it even under ordinary
##   conditions, and above it the hard, brittle delta constituent forms. The
##   equilibrium alpha boundary is higher (15.8 wt% at 586 C) but bronze is a
##   CAST material and coring is what a caster actually meets.
## - **Cu-Zn 39 wt%.** The alpha/(alpha+beta) boundary at ~454-470 C -- a true
##   maximum solid solubility.
## - **Cu-As 7.96 wt%.** The maximum solid solubility of arsenic in copper, at
##   685 C.
## - **Fe-C 0.76 wt%.** The eutectoid, and deliberately NOT a solubility limit:
##   ferrite dissolves a mere 0.02% C. It is the right boundary for this model
##   anyway, because it is the composition above which proeutectoid cementite
##   begins precipitating as a film on prior-austenite grain boundaries -- and
##   that film, not the dissolved carbon, is what collapses toughness. Named
##   honestly as an ONSET rather than a solubility for exactly this reason.
##
## Only one direction of each pair is listed, because only one direction is
## real: tin dissolves essentially no copper and graphite dissolves no iron at
## all. blend() finds whichever direction has data (see _oriented_pair), so
## blend("tin", "copper", x) is still the mirror image of blend("copper", "tin",
## 1-x) rather than an unmodeled pair.
##
## A pair absent from this table has no modeled metallurgy and gets a pure rule
## of mixtures -- an honest "not modeled", not an invented curve.
const SECOND_PHASE_ONSET: Dictionary = {
	"copper": {"tin": 0.135, "zinc": 0.39, "arsenic": 0.0796},
	"iron": {"carbon": 0.0076},
}

## WHICH brittle compound appears past the onset, as its chemical formula.
##
## Stored as a formula rather than as a composition on purpose: the compound's
## solute mass fraction is then ARITHMETIC over the molar masses already in
## ELEMENT_CONSTANTS (see second_phase_solute_fraction), not a fifth number
## someone had to look up and could get wrong. The check that the derivation is
## right is that it reproduces the published figures -- Cu31Sn8 comes out at
## 32.5 wt% Sn against a literature 32.6, and Fe3C at 6.69 against the textbook
## 6.67.
##
## These are real, named phases, and every one of them is the reason its alloy
## system has a ceiling:
##
## - **delta, Cu31Sn8** -- the hard brittle constituent of high-tin bronze; it
##   is also what makes a bronze BELL ring and crack.
## - **beta-prime, CuZn** -- ordered bcc brass; Muntz metal sits right at the
##   boundary where it starts.
## - **gamma, Cu3As** -- the arsenide of arsenical bronze.
## - **cementite, Fe3C** -- the single most consequential intermetallic in human
##   history.
const SECOND_PHASE: Dictionary = {
	"copper": {
		"tin": {"name": "delta (Cu31Sn8)", "solvent_atoms": 31.0, "solute_atoms": 8.0},
		"zinc": {"name": "beta-prime (CuZn)", "solvent_atoms": 1.0, "solute_atoms": 1.0},
		"arsenic": {"name": "gamma (Cu3As)", "solvent_atoms": 3.0, "solute_atoms": 1.0},
	},
	"iron": {
		"carbon": {"name": "cementite (Fe3C)", "solvent_atoms": 3.0, "solute_atoms": 1.0},
	},
}

## Labusch's concentration exponent for solid-solution strengthening.
##
## Two published laws compete here and the choice is not stylistic. **Fleischer**
## gives sqrt(c) and is explicitly the DILUTE result, documented as valid below
## about 1 at% solute, where each solute atom pins a dislocation independently.
## **Labusch** gives c^(2/3) and is the CONCENTRATED result, from the collective
## action of the solutes lying on the glide plane.
##
## Every alloy this model cares about is far outside Fleischer's range: 12 wt%
## tin in copper is 6.8 at%, and 39 wt% zinc is 38 at%. So Labusch is simply the
## applicable law, and using the dilute one -- as the first version of this file
## did -- was a real error, not a simplification.
const LABUSCH_EXPONENT: float = 2.0 / 3.0

## The one sourced anchor in the whole model. Cast 88Cu-12Sn bronze measures
## roughly twice annealed copper's hardness (~100 HB against ~50 HB), and
## 12% tin is the composition the Bronze Age actually settled on.
const BRONZE_ANCHOR_TIN_FRACTION: float = 0.12
const BRONZE_ANCHOR_HARDNESS_RATIO: float = 2.0

## Lattice misfit -> relative hardness gain. NOT eyeballed: the misfit (0.09375)
## and the second-phase onset (0.135) were both already fixed by real
## measurements, so this is the single remaining unknown and it is the bronze
## anchor above SOLVED FOR, not tuned:
##
##   K = (ratio * H_copper / baseline(x) - 1) / (misfit * (x / onset)^(2/3))
##     = (2.0 * 0.50 / 0.446 - 1) / (0.09375 * 0.9244817)
##     = 14.33195
##
## The inputs H_copper and H_tin moved when material_properties.gd's hardness
## column was rescaled from a placed 0-10 ordering to published Vickers (copper
## 4.0 -> 0.50 == 50 HV, tin 1.5 -> 0.05 == 5 HV), so K moved with them -- which
## is exactly what a solved constant is supposed to do. Note the anchor itself
## is unchanged and so is what it means: cast 88Cu-12Sn is still twice annealed
## copper's hardness, and 2 x 50 HV = 100 HV is now literally the published
## ~100 HB figure for cast tin bronze rather than a ratio on an abstract scale.
##
## Re-derived from the anchors by test_the_strengthening_coefficient_is_the_
## measured_bronze_anchor_solved_for_k, so it cannot drift away from the
## measurement it encodes.
const SOLUTION_STRENGTHENING_COEFFICIENT: float = 14.33195

## How finely optimal_solute_fraction scans the composition axis. 1/10000 is
## fine enough to resolve the Fe-C onset (0.76%) to two significant figures,
## which is the tightest of the four.
const COMPOSITION_SCAN_STEPS: int = 10000

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
## graphite does not melt at atmospheric pressure, it sublimes at ~3915 K, and
## arsenic has neither for the same reason (it sublimes at ~887 K). So Fe-C
## runs on iron's liquidus branch alone -- correct physics, not a missing row --
## while carbon still counts properly as dissolved particles.
##
## Molar masses are also what turns an intermetallic's FORMULA into its
## composition (see second_phase_solute_fraction), so every element that
## appears in a SECOND_PHASE compound must have one.
##
## A material absent entirely (wood, flesh, stone) is not an element and has no
## liquidus at all.
const ELEMENT_CONSTANTS: Dictionary = {
	"copper": {"molar_mass_g": 63.546, "melting_k": 1357.77, "fusion_j_per_mol": 13260.0},
	"tin": {"molar_mass_g": 118.710, "melting_k": 505.08, "fusion_j_per_mol": 7030.0},
	"iron": {"molar_mass_g": 55.845, "melting_k": 1811.0, "fusion_j_per_mol": 13810.0},
	"carbon": {"molar_mass_g": 12.011},
	"zinc": {"molar_mass_g": 65.380, "melting_k": 692.68, "fusion_j_per_mol": 7320.0},
	"silver": {"molar_mass_g": 107.868, "melting_k": 1234.93, "fusion_j_per_mol": 11300.0},
	"gold": {"molar_mass_g": 196.967, "melting_k": 1337.33, "fusion_j_per_mol": 12550.0},
	# Arsenic is here for its molar mass alone: it is the solute of arsenical
	# bronze -- the alloy that PRECEDED tin bronze, because arsenic occurs in
	# the same copper ores and needed no tin trade at all -- and it is what the
	# gamma-Cu3As second phase is made of. It has no liquidus for the same
	# reason graphite has none: arsenic sublimes at 887 K (615 C) rather than
	# melting at atmospheric pressure.
	"arsenic": {"molar_mass_g": 74.9216},
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

	var pair := _oriented_pair(material_a, material_b, x)
	if pair.is_empty():
		# No published phase boundary for this pair: no modeled metallurgy, so
		# every scalar keeps the rule-of-mixtures value above. An honest "not
		# modeled" rather than an invented curve.
		return alloy

	var solvent: String = pair["solvent"]
	var solute: String = pair["solute"]
	var c: float = pair["c"]
	var hardness_baseline := _baseline(properties, solvent, solute, "hardness", c)
	alloy["hardness"] = _alloy_hardness(properties, solvent, solute, c)
	alloy["toughness"] = _alloy_toughness(properties, solvent, solute, c)
	# Edge retention is downstream of hardness: a soft metal's edge rolls over
	# on first contact. That is why a copper knife lost to a flint one and a
	# bronze knife did not, so sharpness_capacity rides whatever factor hardness
	# actually gained over its own baseline, rather than mixing linearly (which
	# would make bronze a WORSE blade than copper -- visibly the wrong answer).
	var hardness_factor := 1.0
	if hardness_baseline > 0.0:
		hardness_factor = float(alloy["hardness"]) / hardness_baseline
	alloy["sharpness_capacity"] = minf(
		float(alloy["sharpness_capacity"]) * hardness_factor, SCALE_MAX
	)
	return alloy


## Hardness across all three regimes, on the 0-10 legibility scale.
##
## 1. **Single-phase (c <= onset).** The rule-of-mixtures baseline multiplied by
##    Labusch solid-solution strengthening. Steep at first, flattening toward
##    the boundary -- which is why every historical recipe lives down in the
##    dilute end and why nobody ever pushed to the boundary exactly.
## 2. **Two-phase (onset < c <= the compound's own composition).** A lever-rule
##    mix between the saturated solid solution and the intermetallic. The alpha
##    phase's own composition is FROZEN here -- that is what the lever rule
##    means -- so all the change comes from the growing volume fraction of a
##    hard, brittle compound.
## 3. **Past the compound.** A lever-rule mix between the intermetallic and the
##    pure solute, which is how the curve gets back down to soft pure tin at the
##    far end instead of falling off a cliff.
##
## The intermetallic is placed at SCALE_MAX rather than given a looked-up
## hardness per compound. That is a deliberate approximation and worth naming:
## delta bronze, cementite, beta-prime and Cu3As are ALL hard brittle compounds,
## and telling them apart on this scale would need an HV-to-legibility transfer
## function the game explicitly does not have (material_properties.gd says so).
## Four invented numbers would be worse than one honest ceiling.
static func _alloy_hardness(
	properties: RefCounted, solvent: String, solute: String, c: float
) -> float:
	var onset := second_phase_onset(solvent, solute)
	var compound := second_phase_solute_fraction(solvent, solute)
	var baseline := _baseline(properties, solvent, solute, "hardness", c)
	if c <= onset:
		return minf(baseline * (1.0 + solution_strengthening(solvent, solute, c)), SCALE_MAX)
	var saturated := minf(
		_baseline(properties, solvent, solute, "hardness", onset)
		* (1.0 + solution_strengthening(solvent, solute, onset)),
		SCALE_MAX
	)
	if c <= compound:
		return lerpf(saturated, SCALE_MAX, brittle_phase_fraction(solvent, solute, c))
	var past := (c - compound) / maxf(1.0 - compound, 0.000001)
	return lerpf(SCALE_MAX, properties.property_value(solute, "hardness"), clampf(past, 0.0, 1.0))


## Toughness across the same three regimes -- and the shape of THIS curve is the
## design argument for the whole rewrite.
##
## In the single-phase field toughness simply follows the rule of mixtures: a
## solid solution is still one ductile phase, and pretending otherwise is
## contradicted by the most-produced copper alloy there is (cartridge brass at
## 30% zinc is both stronger than pure copper AND more ductile than it).
##
## Past the boundary it collapses by the lever rule toward the intermetallic's
## own zero, because a brittle compound precipitating on the grain boundaries is
## a continuous crack highway: a crack that finds one never has to break
## anything tough on its way through. That is what makes cast iron shatter,
## what cracks bronze bells, and what put the historical optimum exactly where
## the boundary is.
##
## Honest limitation: a real grain-boundary FILM embrittles faster than its
## volume fraction alone suggests, because it sits precisely on the crack path
## rather than being randomly dispersed. The lever rule is the stereologically
## correct answer for a randomly dispersed phase and is therefore a little
## generous to high-solute alloys -- the Cu-Sn brittleness crossover lands
## around 25% tin where reality is nearer 20%.
static func _alloy_toughness(
	properties: RefCounted, solvent: String, solute: String, c: float
) -> float:
	var onset := second_phase_onset(solvent, solute)
	var compound := second_phase_solute_fraction(solvent, solute)
	if c <= onset:
		return _baseline(properties, solvent, solute, "toughness", c)
	var saturated := _baseline(properties, solvent, solute, "toughness", onset)
	if c <= compound:
		return lerpf(saturated, 0.0, brittle_phase_fraction(solvent, solute, c))
	var past := (c - compound) / maxf(1.0 - compound, 0.000001)
	return lerpf(0.0, properties.property_value(solute, "toughness"), clampf(past, 0.0, 1.0))


## The rule-of-mixtures value of one scalar at composition `c`, measured with
## the solvent at 0 and the solute at 1. Every regime above is expressed as a
## departure from this line.
static func _baseline(
	properties: RefCounted, solvent: String, solute: String, property_name: String, c: float
) -> float:
	return lerpf(
		properties.property_value(solvent, property_name),
		properties.property_value(solute, property_name),
		c
	)


## Which way round a pair's published phase data runs, and the solute mass
## fraction on that orientation. Empty when neither direction is modeled.
##
## This is what keeps blend(a, b, x) and blend(b, a, 1-x) the same alloy: the
## phase diagram is asymmetric (tin dissolves essentially no copper) so the
## model has one orientation, and the composition axis is flipped to match
## rather than the pair being declared unmodeled in one direction.
static func _oriented_pair(material_a: String, material_b: String, fraction_b: float) -> Dictionary:
	if second_phase_onset(material_a, material_b) > 0.0:
		return {"solvent": material_a, "solute": material_b, "c": fraction_b}
	if second_phase_onset(material_b, material_a) > 0.0:
		return {"solvent": material_b, "solute": material_a, "c": 1.0 - fraction_b}
	return {}


## The relative hardness gain the SOLID SOLUTION takes up, as a fraction
## (0.0 = no gain, 1.0 = twice the rule-of-mixtures baseline).
##
## ## The model, and why it has this shape
##
## Solid-solution strengthening: a solute atom of the wrong size strains the
## host lattice around it, and a dislocation trying to glide past has to do
## work against that strain field. More solute, more obstacles, harder metal.
## Two real facts set the curve:
##
## 1. **Labusch's law** -- the strengthening goes as c^(2/3), not linearly and
##    not as Fleischer's sqrt. See LABUSCH_EXPONENT: Fleischer is the dilute
##    result and every alloy here is concentrated. Either way the shape claim is
##    the same and it is the one that matters: the curve is steep at the dilute
##    end, so the first 1% of solute does more than the tenth, which is why
##    every historical recipe is found down there rather than at 50/50.
##
## 2. **The second-phase onset** -- this, not any chosen peak fraction, is what
##    puts the useful maximum where it is. Below it the alloy is one solid
##    solution; at it the solution is saturated. Past it the solution's own
##    composition stops changing -- extra solute makes MORE second phase, it
##    does not enrich the alpha further -- so this function freezes at its
##    boundary value rather than continuing to climb. That is the lever rule
##    talking, not a clamp for tidiness.
##
## Directional by design: this describes `solute` dissolved in `solvent`, and a
## pair with no published boundary in that direction returns 0. blend() takes
## care of finding the modeled orientation (see _oriented_pair), so callers who
## have an unordered pair should go through blend() rather than guessing.
static func solution_strengthening(solvent: String, solute: String, solute_fraction: float) -> float:
	var onset := second_phase_onset(solvent, solute)
	if onset <= 0.0:
		return 0.0
	var c := clampf(solute_fraction, 0.0, onset)
	return (
		SOLUTION_STRENGTHENING_COEFFICIENT
		* lattice_misfit(solvent, solute)
		* pow(c / onset, LABUSCH_EXPONENT)
	)


## The composition at which `solvent` starts throwing a brittle second phase out
## of solution. Zero for any pair with no published entry -- see
## SECOND_PHASE_ONSET.
static func second_phase_onset(solvent: String, solute: String) -> float:
	var onsets: Dictionary = SECOND_PHASE_ONSET.get(solvent, {})
	return float(onsets.get(solute, 0.0))


## The name of the brittle compound that appears past that onset, for a tooltip
## or a smelting log. Empty when the pair has no modeled second phase.
static func second_phase_name(solvent: String, solute: String) -> String:
	var phases: Dictionary = SECOND_PHASE.get(solvent, {})
	return String(phases.get(solute, {}).get("name", ""))


## The intermetallic's own composition, as a solute mass fraction, DERIVED from
## its formula and the two elements' published molar masses.
##
## Deriving rather than looking up is the point: Fe3C's 6.67 wt% carbon and
## Cu31Sn8's 32.6 wt% tin are textbook figures, and the fact that pure
## arithmetic over molar masses reproduces both is the check that the formulas
## and the molar masses are right. It also means adding a fifth alloy system
## needs one published boundary and one chemical formula -- not a composition
## someone had to measure.
static func second_phase_solute_fraction(solvent: String, solute: String) -> float:
	var phases: Dictionary = SECOND_PHASE.get(solvent, {})
	var phase: Dictionary = phases.get(solute, {})
	if phase.is_empty():
		return 0.0
	var solvent_mass: float = float(ELEMENT_CONSTANTS.get(solvent, {}).get("molar_mass_g", 0.0))
	var solute_mass: float = float(ELEMENT_CONSTANTS.get(solute, {}).get("molar_mass_g", 0.0))
	if solvent_mass <= 0.0 or solute_mass <= 0.0:
		return 0.0
	var solvent_total := float(phase["solvent_atoms"]) * solvent_mass
	var solute_total := float(phase["solute_atoms"]) * solute_mass
	if solvent_total + solute_total <= 0.0:
		return 0.0
	return solute_total / (solvent_total + solute_total)


## What fraction of the alloy is the brittle second phase, by the LEVER RULE --
## the standard construction on any binary phase diagram. Zero below the onset
## (there is no second phase at all), one at the compound's own composition (the
## alloy IS the compound), and linear between.
static func brittle_phase_fraction(solvent: String, solute: String, solute_fraction: float) -> float:
	var onset := second_phase_onset(solvent, solute)
	var compound := second_phase_solute_fraction(solvent, solute)
	if onset <= 0.0 or compound <= onset:
		return 0.0
	return clampf((solute_fraction - onset) / (compound - onset), 0.0, 1.0)


## The richest composition that has NOT yet grown a continuous brittle network
## -- i.e. the best alloy a smith can actually make, found by scanning the
## model's own output rather than by returning the onset constant.
##
## This is the whole payoff of the two-regime model. Nothing here knows any
## history, and yet:
##
## - Cu-Sn lands at 13.5% tin, inside the real 10-14% weapons-bronze band;
## - Cu-Zn lands at 39% zinc, which is Muntz metal's 40%;
## - Fe-C lands at 0.76% carbon, which is eutectoid steel exactly.
##
## Three real historical answers out of three published phase boundaries and one
## formula. "Richest single-phase" is only the same thing as "hardest usable"
## because hardness climbs all the way to the boundary and never doubles back,
## which is a real claim about the curve and is scanned by
## test_hardness_climbs_all_the_way_to_the_boundary_for_every_modeled_pair
## rather than assumed here.
static func optimal_solute_fraction(solvent: String, solute: String) -> float:
	if second_phase_onset(solvent, solute) <= 0.0:
		return 0.0
	var best := 0.0
	for step in range(0, COMPOSITION_SCAN_STEPS + 1):
		var c := float(step) / float(COMPOSITION_SCAN_STEPS)
		if brittle_phase_fraction(solvent, solute, c) > 0.0:
			break
		best = c
	return best


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
