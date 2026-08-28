extends RefCounted

const AlloyBlend = preload("res://src/gameplay/alloy_blend.gd")
const AssemblyId = preload("res://src/gameplay/assembly_id.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

## Heat treatment: one steel, a whole family of tools.
##
## A file and a spring are the same steel in the same shape. No part graph can
## express that difference -- `part_graph.gd` knows geometry and material and
## nothing else, so a wedge of iron 70 cm long is one item to it no matter what
## the smith did in the fire. Heat treatment is the axis that separates them,
## and it is the cheapest large win available: three operations turn a single
## row of `material_properties.gd` into a continuum of usable tools.
##
## Like `alloy_blend.gd`, everything here takes the ordinary eight-scalar
## property vector in and returns a NEW one out. Nothing downstream --
## `impact_resolver`, `descriptors_for_vector`, `mass_kg_for` -- learns a new
## type, and nothing is ever mutated: the caller's vector comes back untouched
## (`test_treatment_is_pure`).
##
## `alloy_blend.gd` deliberately left this out ("What comes out is an as-cast
## vector ... tempering ... belongs in whatever models the forge"), and named
## the resulting hole plainly: it "cannot yet say that the same steel, quenched
## to martensite, is not [tough]". This file is that fix -- as-cast steel is
## single-phase and tough but not hard enough to be a blade, quenching makes it
## hard and unusable, and only the pair together is a tool.
##
##
## ## The one law: heat treatment slides along a curve, it never leaves it
##
## Both thermal operations are the *same* private helper, `_slide_to_hardness`.
## That is not code reuse, it is the anti-degeneracy law made structural: there
## is no code path in this file that can raise hardness and toughness at once,
## because there is only one path and it trades them. "Temper to max
## everything" is not a strategy the model can express.
##
## The conserved quantity is **hardness^n x toughness**, with n derived below.
##
## ### Why not a plain sum
##
## `hardness + toughness = const` is the obvious guess and it is wrong three
## ways:
##
##  1. **It is not a real exchange rate.** A sum asserts that one point of
##     hardness is worth exactly one point of toughness *everywhere on the
##     curve*. Every published temper table says otherwise: coming off the
##     as-quenched end, a few points of hardness buy a large toughness return,
##     and down at the soft end you give up a great deal of hardness for very
##     little. dT/dH is emphatically not -1.
##  2. **It is not dimensionally coherent.** Hardness is an indentation
##     pressure and toughness is an energy; the 0-10 legibility scale puts them
##     on one axis for *reading*, not for adding. The power law only ever
##     multiplies and divides, so it survives a rescaling of that axis that a
##     sum would silently change the answers under.
##  3. **It has no derivation.** The exponent below falls out of three real
##     relations. A sum falls out of nothing.
##
## ### Where n comes from
##
## Three published relations, no fitting:
##
##  - **Tabor**: HV ~= 3 sigma_y, so yield strength is proportional to hardness.
##  - **The strength-toughness tradeoff along a temper line**: drawing AISI 4340
##    from a low temper to a high one takes sigma_y ~1700 -> ~1000 MPa while
##    K_IC goes ~50 -> ~110 MPa*m^0.5. That is K_IC proportional to
##    sigma_y^-1.486 (`FRACTURE_ANCHOR`, below).
##  - **Work of fracture**: the energy an impact spends is the fracture energy
##    K_IC^2/E over the plastic zone it opens, whose depth goes as
##    (K_IC/sigma_y)^2. Young's modulus E is famously *structure-insensitive*
##    -- martensite, pearlite and ferrite are all ~205 GPa, so heat treatment
##    does not move it and it drops out of the ratio entirely. What is left is
##    absorbed energy proportional to K_IC^2 / sigma_y.
##
## Composing them: toughness ~ sigma_y^(-2*1.486) / sigma_y = sigma_y^-3.97,
## and sigma_y ~ hardness, so **toughness ~ hardness^-3.97**. Re-derived from
## the anchor by `test_the_toughness_exponent_is_the_published_fracture_anchor_
## solved_for_n`, so it cannot drift away from the measurement it encodes.
##
## ### What this model deliberately does NOT claim
##
## Quenching here is envelope-*conserving*: it drives the material to the hard
## end of its own curve and takes the matching toughness price. Real quenching
## does slightly better than that -- tempered martensite is a genuinely better
## structure than annealed pearlite, worth roughly a factor of two in
## hardness^2 x toughness -- but *how much* better is set by carbon content,
## and an eight-scalar property vector does not carry composition. Inventing a
## number for it would be exactly the free lunch this file exists to refuse, so
## the model stays conservative and says so.
##
## The same missing composition is why **this file cannot tell a hardenable
## steel from wrought iron.** Real wrought iron does not harden by quenching at
## all, and real bronze *softens*; the vector has no way to know. Pinned as a
## known-wrong case by
## `test_the_vector_cannot_express_hardenability_so_quench_overstates_pure_iron`
## rather than hidden -- the same standard `alloy_blend.gd` holds itself to when
## it blends wood with stone.

## The eight scalars a treated vector carries, in MATERIALS' own order. An
## explicit list for the same reason `AlloyBlend.BLENDED_PROPERTIES` is one:
## a ninth scalar on the shared table has to be a deliberate decision here too.
const TREATED_PROPERTIES: Array[String] = [
	"density",
	"hardness",
	"toughness",
	"elasticity",
	"sharpness_capacity",
	"flammability",
	"conductivity",
	"decay_rate",
]

## The top of the 0-10 legibility scale. Read from `alloy_blend.gd` rather than
## restated, because a treated vector and an alloy vector are the same kind of
## object and a second copy of this number is a second thing to drift.
const SCALE_MAX: float = AlloyBlend.SCALE_MAX

## Hardness of a fully martensitic plain-carbon (~0.8 % C) steel, in Vickers,
## and of the same steel fully annealed. Both are standard published figures,
## and their ratio -- not a chosen multiplier -- is how hard quenching gets.
## 0.8 % C is the eutectoid composition every reference tabulates and the
## classic blade/file carbon level.
const AS_QUENCHED_HV: float = 832.0
const ANNEALED_HV: float = 180.0

## How much harder quenching makes a material: 832/180 = 4.62. The famous
## "quenching roughly quadruples hardness", as a quotient of two measurements
## instead of a number somebody liked. Pinned by
## test_the_martensite_hardness_ratio_is_the_published_quotient.
const MARTENSITE_HARDNESS_RATIO: float = AS_QUENCHED_HV / ANNEALED_HV

## Hardness against tempering ("draw") temperature for a water-quenched 0.8 % C
## steel, as [draw C, Vickers] pairs. The published figures are in Rockwell C --
## 65 as-quenched, then 62 / 58 / 55 / 51 / 48 at 200 / 250 / 300 / 350 / 400 C
## -- converted here through the standard ASTM E140 HRC->HV table, because HRC
## is a depth scale and RATIOS OF HRC NUMBERS MEAN NOTHING. Taking 55/65 as a
## retention of 0.85 (it is really 0.72) is a real and easy bug; converting
## first is what avoids it.
##
## The first row is the untempered blade: `AS_QUENCHED_DRAW_C` is room
## temperature, so `hardness_retention` is exactly 1.0 there by construction.
const TEMPER_HV: Array = [
	[20.0, 832.0],
	[200.0, 746.0],
	[250.0, 653.0],
	[300.0, 595.0],
	[350.0, 530.0],
	[400.0, 484.0],
]

## Room temperature: a blade straight out of the quench, drawn to nothing.
const AS_QUENCHED_DRAW_C: float = 20.0

## The temper colours, in ascending draw temperature -- the real ladder a smith
## reads off a polished blade as the oxide film thickens, and the reason this
## mechanic is legible without a single number on screen. Temperatures are the
## standard workshop values (they are usually tabulated in Fahrenheit: 400 F
## pale straw, 440 F dark straw, 490 F bronze, 540 F purple, 570 F blue, 610 F
## pale blue, 640 F grey).
##
## The colour comes from interference in an iron-oxide film whose thickness
## grows with temperature, which is why it depends only on how hot the steel
## got -- NOT on its carbon content. That is exactly why the ladder is a
## separate table from TEMPER_HV above: one is optics, the other is metallurgy,
## and a low-carbon steel drawn to blue is still blue.
##
## `use` is the tool each draw is historically for. It is not decoration: it is
## the assertion `test_the_colour_ladder_names_the_tools_it_really_makes`
## checks the model against -- razors hard, chisels in the middle, springs and
## saws soft and tough.
const TEMPER_COLOURS: Array = [
	{"colour": "pale straw", "draw_c": 205.0, "use": "razors, scrapers, lathe tools"},
	{"colour": "dark straw", "draw_c": 230.0, "use": "drills, punches, knives, files"},
	{"colour": "bronze", "draw_c": 255.0, "use": "wood chisels, shears, hammers"},
	{"colour": "purple", "draw_c": 280.0, "use": "cold chisels, axes, press tools"},
	{"colour": "blue", "draw_c": 300.0, "use": "springs, screwdrivers, needles"},
	{"colour": "pale blue", "draw_c": 320.0, "use": "hand saws, spring steel"},
	{"colour": "grey", "draw_c": 340.0, "use": "too soft to hold an edge"},
]

## The published strength/fracture-toughness pair the toughness exponent is
## solved out of: AISI 4340, quenched and tempered low (~200 C) and high
## (~550 C), as [yield MPa, K_IC MPa*m^0.5]. 4340 is the textbook
## strength-toughness case precisely because both ends are so well measured.
const FRACTURE_ANCHOR: Array = [
	[1700.0, 50.0],
	[1000.0, 110.0],
]

## toughness ~ hardness^-n along a temper line. NOT eyeballed and not fitted:
## n = 2 * 1.4859 + 1, where 1.4859 = ln(110/50) / ln(1700/1000) is the
## FRACTURE_ANCHOR slope and the "2 * ... + 1" is K_IC^2 / sigma_y (see the
## class doc). Re-derived from the anchor by
## test_the_toughness_exponent_is_the_published_fracture_anchor_solved_for_n.
const TOUGHNESS_HARDNESS_EXPONENT: float = 3.97178

## How many rungs a whetstone progression has. Read from
## `AssemblyId.TREATMENT_LEVELS` rather than restated, because an item's
## content-addressed id quantizes its process levels on exactly this ladder:
## a keenness finer than one rung would be a distinction no hand can make AND
## an id the registry would have to mint. The two must be one number or honing
## a blade mints ids the ladder says do not exist.
const KEEN_STEPS: int = AssemblyId.TREATMENT_LEVELS


# --- the thermal pair ------------------------------------------------------


## Rapid cooling: austenite traps its carbon and shears into martensite.
## Hardness up to MARTENSITE_HARDNESS_RATIO times its old value (or the top of
## the scale, whichever comes first), toughness paying the envelope price.
##
## The result is *supposed* to be unusable. An as-quenched blade shatters --
## that is the entire reason tempering was ever invented, and
## `test_an_as_quenched_blade_falls_below_the_shipped_brittle_toughness_threshold`
## holds the model to it against the cutoff the impact model already fractures
## at, not a number typed into this file.
##
## The toughness price is charged on the hardness ACTUALLY DELIVERED, not on
## the drive: a material already at the top of the 0-10 scale gets no hardness
## from quenching and therefore pays nothing for it. That is not a special
## case, it falls out of `_slide_to_hardness` being the only operation.
##
## That clamp used to make quenching a modelled carbon steel an outright no-op,
## because the old hardness column had iron at 8.0 on a scale stopping at 10.0
## and `alloy_blend.gd` therefore saturated every Fe-C composition. It does not
## any more: `MaterialProperties.HARDNESS_MAX_HV` anchors the column on
## martensite at 1000 HV, so as-cast steel arrives with room above it and a
## full quench lands ON the ceiling for the right reason -- the ceiling IS
## martensite. Pinned by
## test_quenching_a_modelled_carbon_steel_really_hardens_it.
static func quench(vector: Dictionary) -> Dictionary:
	var hardness := _scalar(vector, "hardness")
	return _slide_to_hardness(vector, hardness * MARTENSITE_HARDNESS_RATIO)


## Reheating the quenched piece to `draw_c` and letting some of the trapped
## carbon precipitate out: hardness back down, toughness back up, along the one
## curve. This is the operation that makes a family -- pale straw is a razor,
## blue is a spring, and they are the same steel.
##
## **Takes an AS-QUENCHED vector.** `hardness_retention` is defined relative to
## the untempered state, so tempering an already-tempered vector draws it a
## second time from a lower start and lands somewhere no fire would put it. A
## smith re-hardens before re-drawing and so should a caller: `quench()` returns
## a tempered blade exactly to the as-quenched state (that round trip is real,
## and is pinned by
## test_re_hardening_a_tempered_blade_returns_it_to_the_as_quenched_state), so
## `temper(quench(blade), hotter_draw)` is always the right call.
static func temper(as_quenched: Dictionary, draw_c: float) -> Dictionary:
	var hardness := _scalar(as_quenched, "hardness")
	return _slide_to_hardness(as_quenched, hardness * hardness_retention(draw_c))


## Fraction of its as-quenched hardness a 0.8 % C steel keeps after being drawn
## to `draw_c`, by linear interpolation through TEMPER_HV. Flat outside the
## table's range in both directions: below room temperature nothing has been
## drawn, and past 400 C this file has no measurements and will not invent any
## (the same "no modelled metallurgy, no invented curve" rule
## `alloy_blend.SOLID_SOLUBILITY` follows).
static func hardness_retention(draw_c: float) -> float:
	return _interpolate_hv(draw_c) / AS_QUENCHED_HV


## The oxide colour a blade shows at `draw_c` -- the whole player-facing
## surface of this mechanic. Returns the hottest colour the steel has reached,
## and "" below the first one (an undrawn blade is still bright).
static func temper_colour(draw_c: float) -> String:
	var reached := ""
	for entry in TEMPER_COLOURS:
		if draw_c + 0.0001 >= float(entry["draw_c"]):
			reached = String(entry["colour"])
	return reached


## The draw temperature a named colour stands for, or -1.0 for a colour that is
## not on the ladder.
static func draw_c_for_colour(colour: String) -> float:
	for entry in TEMPER_COLOURS:
		if String(entry["colour"]) == colour:
			return float(entry["draw_c"])
	return -1.0


# --- sharpening ------------------------------------------------------------


## The edge actually on this material after `keen_step` rungs of a whetstone
## progression, on a 0..SCALE_MAX keenness scale.
##
## Ceilinged at the material's OWN `sharpness_capacity` -- which is exactly
## what that scalar means. You cannot hone iron to an obsidian edge no matter
## how long you sit at the stone; obsidian parts along a conchoidal fracture a
## few molecules wide and iron's grain will not go finer than its carbides.
## That ceiling, not a durability stat, is why obsidian beats iron on edge and
## loses on everything else.
##
## `keen_step` is clamped rather than left to run off the end. This deliberately
## diverges from `AssemblyId.quantize_treatment`, which does NOT clamp so that
## an upstream bug stays visible in the id: here the ceiling is a physical fact
## about the material and letting a caller past it would be modelling a lie.
static func keenness(vector: Dictionary, keen_step: int) -> float:
	var capacity := _scalar(vector, "sharpness_capacity")
	var step := clampi(keen_step, 0, KEEN_STEPS)
	return capacity * float(step) / float(KEEN_STEPS)


## The same, as a vector: `sharpness_capacity` carries the edge the material
## ACTUALLY has rather than the edge it could have.
##
## That is what makes `MaterialProperties.descriptors_for_vector` honest --
## before this, an unworked iron bar read as "keen" because the table's
## capacity is 8.0, which is the ceiling and not the edge. A blank is not a
## blade until somebody grinds it.
##
## **Takes the material's own vector**, for the same reason `temper` takes an
## as-quenched one: the returned vector's capacity has been overwritten with an
## achieved keenness, so re-sharpening its own output would grind against a
## ceiling that has already been lowered. Pinned by
## test_sharpen_takes_the_materials_vector_not_one_it_already_returned.
static func sharpen(vector: Dictionary, keen_step: int) -> Dictionary:
	var treated := _copy(vector)
	treated["sharpness_capacity"] = keenness(vector, keen_step)
	return treated


# --- the single trade ------------------------------------------------------


## Move a vector along its own strength-toughness envelope to `target_hardness`.
##
## THE only place hardness or toughness changes in this file. Everything else
## is a wrapper that decides where on the curve to stand:
##
##  - hardness goes where it is told, capped by the scale;
##  - toughness pays or is repaid `hardness^n x toughness = const`;
##  - sharpness_capacity rides hardness exactly, because edge retention is
##    downstream of hardness -- the same rule and the same reason
##    `AlloyBlend.blend` gives (a soft metal's edge rolls over on first
##    contact, which is why a copper knife lost to a flint one);
##  - elasticity rides toughness exactly. That column is NOT Young's modulus:
##    the table's own obsidian row is the proof, scoring 0.0 while being *more*
##    compliant by modulus than the iron row at 2.0. It is usable bend-and-
##    return, and what limits that is whether the piece survives the bend. So a
##    blue-drawn saw is springy and an as-quenched one is a pane of glass.
##
## Neither rider needs a second tuned number, which is the point:
## `alloy_blend.gd` made the same choice for the same reason, and a tradeoff
## with no free parameters cannot be quietly turned into a free lunch later.
static func _slide_to_hardness(vector: Dictionary, target_hardness: float) -> Dictionary:
	var treated := _copy(vector)
	var hardness := _scalar(vector, "hardness")
	if hardness <= 0.0 or target_hardness <= 0.0:
		return treated
	var hardened := minf(target_hardness, SCALE_MAX)
	var ratio := hardened / hardness

	var toughness := _scalar(vector, "toughness")
	var traded := minf(toughness * pow(1.0 / ratio, TOUGHNESS_HARDNESS_EXPONENT), SCALE_MAX)

	treated["hardness"] = hardened
	treated["toughness"] = traded
	treated["sharpness_capacity"] = minf(_scalar(vector, "sharpness_capacity") * ratio, SCALE_MAX)
	if toughness > 0.0:
		treated["elasticity"] = minf(_scalar(vector, "elasticity") * traded / toughness, SCALE_MAX)
	return treated


## Vickers hardness at `draw_c`, interpolated through TEMPER_HV and flat past
## either end.
static func _interpolate_hv(draw_c: float) -> float:
	var first: Array = TEMPER_HV[0]
	if draw_c <= float(first[0]):
		return float(first[1])
	for index in range(1, TEMPER_HV.size()):
		var lower: Array = TEMPER_HV[index - 1]
		var upper: Array = TEMPER_HV[index]
		if draw_c <= float(upper[0]):
			var span := float(upper[0]) - float(lower[0])
			if span <= 0.0:
				return float(upper[1])
			var share := (draw_c - float(lower[0])) / span
			return lerpf(float(lower[1]), float(upper[1]), share)
	return float((TEMPER_HV[TEMPER_HV.size() - 1] as Array)[1])


## A complete eight-scalar vector, always freshly built. Missing scalars fall
## back to DEFAULT_PROPERTIES exactly as `MaterialProperties.property_value`
## does, so a treated vector is shape-identical to a MATERIALS row and nothing
## downstream can tell the difference.
static func _copy(vector: Dictionary) -> Dictionary:
	var copied: Dictionary = {}
	for property_name in TREATED_PROPERTIES:
		copied[property_name] = _scalar(vector, property_name)
	return copied


static func _scalar(vector: Dictionary, property_name: String) -> float:
	return float(vector.get(property_name, MaterialProperties.DEFAULT_PROPERTIES[property_name]))
