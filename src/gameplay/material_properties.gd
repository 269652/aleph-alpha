extends RefCounted

## Material property vector + traversal-tool viability check. Pure logic.
##
## Per docs/concept/materials.md: every material carries a small, fixed
## property vector -- this is the "mineral" track of that doc's deliberate
## two-track split (fixed/reliable), not the DNA-driven organic track (see
## dna.md/evolution.md), which is out of scope here. This is the shared data
## the impact-resolution model (impact_resolver.gd) and the traversal-tool
## check below both read from.
##
## Density is expressed relative to water (water == 1.0) so buoyancy is a
## direct density comparison. Most other scalars are small "8-bit" numbers
## (roughly 0..10) per materials.md's determinism/legibility goal, placed
## against each other rather than converted from external units -- iron sits at
## hardness 8 and stone at 7, which is a legibility ordering, not a
## measurement. Two columns are exceptions and say so: `density` is a real
## g/cm^3 figure, and `conductivity` is now derived from published %IACS (see
## conductivity_from_iacs below). Unknown materials/properties fall back to
## DEFAULT_PROPERTIES, mirroring material_damage.gd's existing default-fallback
## convention.

const DEFAULT_PROPERTIES: Dictionary = {
	"density": 1.0,
	"hardness": 1.0,
	"toughness": 1.0,
	"elasticity": 1.0,
	"sharpness_capacity": 1.0,
	"flammability": 1.0,
	# The one default that is deliberately NOT 1.0. Since the rescale below,
	# 1.0 on this column means "10.5% IACS" -- a real metal -- so the old
	# all-1.0 default silently promoted every unmodeled substance to a usable
	# conductor. Not having measured something is not a reason to call it a
	# wire. Pinned by test_an_unmodeled_material_is_not_assumed_to_conduct.
	"conductivity": 0.0,
	"decay_rate": 1.0,
}

## The top of the 0-10 legibility scale, for the conductivity column's anchor.
##
## This is the SAME ceiling AlloyBlend.SCALE_MAX already pins to the largest
## value the table actually uses (obsidian's sharpness_capacity of 10.0).
## Restated here rather than preloaded because alloy_blend.gd already preloads
## THIS file and the reverse would be a cycle -- exactly the arrangement
## BRITTLE_TOUGHNESS already uses against ImpactResolver -- so the two are
## pinned equal by
## test_the_conductivity_ceiling_is_the_alloy_models_own_legibility_ceiling
## instead, and cannot drift apart silently.
const CONDUCTIVITY_MAX: float = 10.0

## Silver's conductivity as a percentage of the International Annealed Copper
## Standard, and therefore the anchor of the whole conductivity column.
##
## Silver is chosen because it is the true maximum of the entire periodic table
## -- nothing conducts better than silver, at any temperature, so the top of
## this scale never has to move again no matter what material is added later.
## (Copper would have been the obvious anchor, being the 100% definition of
## IACS itself, but then silver would have to sit ABOVE the ceiling.)
##
## 105% is the published figure for commercial annealed silver; the pure-metal
## figure runs a little higher (106-108%, depending on the reference and the
## purity), which is exactly why this is a named, sourced constant rather than
## a number inlined into a division.
const IACS_SILVER_PERCENT: float = 105.0

## Published electrical conductivity of every material in the table, as a
## percentage of the International Annealed Copper Standard (annealed copper ==
## 100% by definition, which is 5.80e7 S/m at 20 C).
##
## ## Why this column, alone, is a real measurement
##
## Every other scalar here is placed against its neighbours because the game's
## 0-10 scale has no defined transfer function to HV, Mohs or MPa. Conductivity
## is different: %IACS is ALREADY a unit-free, universally published ratio
## scale, so there is nothing to invent -- the figures below are looked up, and
## conductivity_from_iacs() is the only thing that touches them.
##
## ## What this fixes
##
## The old column had iron at 9.0 against copper's 10.0 and flesh at 3.0. Both
## are badly wrong in the direction that matters. Iron is one of the WORST of
## the common metals (15.6% IACS -- near the bottom, not the top), and wet
## tissue is seven orders of magnitude below any metal, not a third of one.
## concept/electromagnetism.md is written against this scalar ("a wire's
## resistance falls out of its material's existing conductivity scalar";
## "copper makes a genuinely better wire than iron"; "wood or stone simply
## doesn't conduct and can't complete a circuit at all") and none of those three
## sentences was supported by the old numbers. All three are now.
##
## Metals are the published %IACS figures directly. Non-metals are computed
## from published conductivity in S/m as `100 * sigma / 5.80e7`, with the sigma
## each one encodes named beside it -- because for an insulator "%IACS" is not
## a figure anyone tabulates, it is just the arithmetic.
const IACS_PERCENT: Dictionary = {
	# -- metals: published %IACS ------------------------------------------
	"silver": 105.0,   # the anchor; see IACS_SILVER_PERCENT
	"copper": 100.0,   # the definition of the standard itself
	"gold": 70.0,
	"zinc": 27.0,      # pure zinc; zinc alloys run 20-28%
	"iron": 15.6,      # iron ingot, 99.9% Fe -- near the BOTTOM of the metals
	"tin": 15.0,
	# -- non-metals: 100 * sigma / 5.80e7 ---------------------------------
	"carbon": 0.345,    # graphite, polycrystalline, in-plane: sigma ~ 2.0e5 S/m
	"flesh": 6.9e-7,    # skeletal muscle, low frequency:      sigma ~ 4.0e-1
	"sinew": 6.9e-7,    # tendon is the same wet collagen:     sigma ~ 4.0e-1
	"hide": 1.7e-7,     # raw, still-moist skin:               sigma ~ 1.0e-1
	"stone": 1.7e-10,   # dry granite:                         sigma ~ 1.0e-4
	"bone": 1.7e-12,    # dry cortical bone:                   sigma ~ 1.0e-6
	"obsidian": 1.7e-14, # dry rhyolitic glass:                sigma ~ 1.0e-8
	"leather": 1.7e-16, # dry vegetable-tanned leather:        sigma ~ 1.0e-10
	"fiber": 1.7e-18,   # dry plant fibre:                     sigma ~ 1.0e-12
	"wood": 1.7e-19,    # air-dry wood at ~12% moisture:       sigma ~ 1.0e-13
	"timber": 1.7e-19,  # seasoned: the same substance, drier
	"glass": 1.7e-19,   # soda-lime glass at 20 C:             sigma ~ 1.0e-13
}

const MATERIALS: Dictionary = {
	"wood": {
		"density": 0.6,
		"hardness": 3.0,
		"toughness": 6.0,
		"elasticity": 5.0,
		"sharpness_capacity": 3.0,
		"flammability": 8.0,
		"conductivity": 1.619048e-20,
		"decay_rate": 6.0,
	},
	# Worked/seasoned structural timber (see BuildingPiece.MATERIAL_TIMBER,
	# docs/concept/timber_construction.md). Shares every property with plain
	# "wood" -- it IS wood, just hewn/riven and seasoned at a Sägewerk, not a
	# different substance -- except decay_rate: removing bark and sapwood
	# (the layers with the highest moisture/nutrient content, where fungal
	# decay establishes fastest) and seasoning down the remaining moisture
	# content measurably slows rot relative to a raw, green, bark-on log in
	# real vernacular construction, without approaching stone's near-
	# permanence -- a decayed or waterlogged Balken is still exactly as
	# flammable/soft/rot-prone as any other wood once decay conditions are
	# actually met. 4.0 is two-thirds of wood's own 6.0 -- a real, moderate
	# reduction (timber survives roughly 50% longer than green wood under
	# the same exposure before reaching the same condition), not stone's
	# near-immunity (1.0). Before this entry existed, BuildingDecay's
	# material lookup would have silently fallen back to
	# DEFAULT_PROPERTIES' decay_rate=1.0 (stone-like) for every timber
	# piece in the game -- an unnoticed but real bug this entry closes.
	# Pinned by test_timber_decay_rate_is_pinned/
	# test_timber_decays_slower_than_raw_wood_but_faster_than_stone
	# (test_material_properties.gd) and
	# test_timber_decays_slower_than_raw_wood_for_the_same_elapsed_time
	# (test_building_decay.gd).
	"timber": {
		"density": 0.6,
		"hardness": 3.0,
		"toughness": 6.0,
		"elasticity": 5.0,
		"sharpness_capacity": 3.0,
		"flammability": 8.0,
		"conductivity": 1.619048e-20,
		"decay_rate": 4.0,
	},
	"flesh": {
		"density": 1.05,
		"hardness": 1.0,
		"toughness": 4.0,
		"elasticity": 3.0,
		"sharpness_capacity": 0.0,
		"flammability": 2.0,
		"conductivity": 6.571429e-08,
		"decay_rate": 9.0,
	},
	"stone": {
		"density": 2.5,
		"hardness": 7.0,
		"toughness": 5.0,
		"elasticity": 1.0,
		"sharpness_capacity": 4.0,
		"flammability": 0.0,
		"conductivity": 1.619048e-11,
		"decay_rate": 1.0,
	},
	"iron": {
		"density": 7.8,
		"hardness": 8.0,
		"toughness": 7.0,
		"elasticity": 2.0,
		"sharpness_capacity": 8.0,
		"flammability": 0.0,
		"conductivity": 1.485714,
		"decay_rate": 3.0,
	},
	"obsidian": {
		"density": 2.4,
		"hardness": 9.0,
		"toughness": 1.0,
		"elasticity": 0.0,
		"sharpness_capacity": 10.0,
		"flammability": 0.0,
		"conductivity": 1.619048e-15,
		"decay_rate": 0.0,
	},
	# -- the mineral rows the alloy model blends (see alloy_blend.gd) ---------
	#
	# docs/concept/smelting.md's "Alloying: emergent metallurgy" section named
	# copper's absence as "a real, pre-existing small gap this design needs
	# filled as a first concrete step (bronze can't be computed without it)".
	# Tin and carbon are the two solutes that turn the table into a blend
	# SPACE rather than a list -- Cu-Sn (substitutional) and Fe-C
	# (interstitial) are the two archetypes real metallurgy is built on.
	#
	# Density is a literal measured g/cm^3, exactly like every other row. The
	# 0-10 scalars are placed against the rows that ALREADY exist rather than
	# converted from external units, because the existing scale has no defined
	# transfer function to HV/Mohs/MS-per-m -- iron sits at hardness 8 and
	# stone at 7, which is a legibility ordering, not a measurement.
	#
	# Copper: 8.96 g/cm^3 (denser than iron, which surprises people and is
	# real). Hardness 4.0 -- annealed copper is ~50 HB against wrought iron's
	# ~150 HB, and crucially it is SOFTER THAN STONE: a copper knife loses to
	# a flint one, which is the entire reason the Bronze Age needed tin rather
	# than just copper. Toughness 8.0, above iron's 7.0: copper is the most
	# ductile metal here (~45% elongation annealed vs wrought iron's ~25%).
	# Elasticity 3.0 -- E = 110 GPa against iron's 200 GPa, so it springs and
	# bends where iron resists. Sharpness_capacity 4.0, level with stone, for
	# the same historical reason as hardness. Conductivity is the IACS standard
	# itself (100%), second only to silver -- see IACS_PERCENT.
	# Decay_rate 2.0, below iron's 3.0 -- copper corrodes to a patina
	# that then PROTECTS what is under it, which is why copper roofs outlast
	# iron ones by centuries.
	"copper": {
		"density": 8.96,
		"hardness": 4.0,
		"toughness": 8.0,
		"elasticity": 3.0,
		"sharpness_capacity": 4.0,
		"flammability": 0.0,
		"conductivity": 9.52381,
		"decay_rate": 2.0,
	},
	# Tin: 7.31 g/cm^3 (white/beta tin). Hardness 1.5 -- Mohs 1.5, ~5 HB, soft
	# enough to mark with a fingernail, so it sits BELOW wood (2.5 Mohs).
	# Toughness 4.0: tin is weak but ductile, not brittle -- it bends and
	# creeps rather than shattering, so it must stay above BRITTLE_TOUGHNESS.
	# Sharpness_capacity 0.0: you cannot put a working edge on tin at all.
	# Conductivity 15% IACS, the bottom of the metals, just under iron's 15.6.
	# Decay_rate 1.0:
	# tin's oxide is passivating, which is the whole premise of tinplate.
	"tin": {
		"density": 7.31,
		"hardness": 1.5,
		"toughness": 4.0,
		"elasticity": 2.0,
		"sharpness_capacity": 0.0,
		"flammability": 0.0,
		"conductivity": 1.428571,
		"decay_rate": 1.0,
	},
	# Carbon (graphite): 2.26 g/cm^3. This row exists as the SOLUTE that turns
	# iron into steel, not as a material anyone builds with -- graphite is
	# Mohs 1-2 (softer than wood), friable enough to read as brittle, and its
	# job in this game is to burn (flammability 9.0, above wood's 8.0: charcoal
	# is the hotter fuel, which is why it and not firewood smelts ore).
	# Conductivity 0.345% IACS -- graphite is a semi-metal and conducts along
	# its basal planes well enough to be an electrode, which makes it the only
	# non-metal in the table that registers on the conductivity column at all;
	# it is still ~45x worse than the worst metal here.
	# Decay_rate 0.0: charcoal does not rot, which is precisely why it is the
	# datable thing in a burnt archaeological layer millennia later.
	"carbon": {
		"density": 2.26,
		"hardness": 1.0,
		"toughness": 0.5,
		"elasticity": 0.0,
		"sharpness_capacity": 0.0,
		"flammability": 9.0,
		"conductivity": 0.03285714,
		"decay_rate": 0.0,
	},
	"fiber": {
		"density": 0.3,
		"hardness": 1.0,
		"toughness": 7.0,
		"elasticity": 6.0,
		"sharpness_capacity": 0.0,
		"flammability": 7.0,
		"conductivity": 1.619048e-19,
		"decay_rate": 7.0,
	},
	# -- the organic rows every animal-sourced part needs ---------------------
	#
	# docs/concept/crafting.md's headline promise is "a hide from a rare,
	# high-fitness boar is a better material input". That was unreachable in
	# code: hide, leather, bone and sinew had no rows, so every organic part in
	# the design resolved through DEFAULT_PROPERTIES' all-1.0 vector and every
	# one of them realized IDENTICALLY -- a boar hide and a length of tendon
	# were the same material. These four rows close that.
	#
	# Raw hide: ~1.0 g/cm^3 (protein and water, so essentially water's own
	# density). Toughness 7.0, level with plant fibre: rawhide is the classic
	# tough-not-hard material -- drum heads, shield facings, lashings that
	# SHRINK TIGHT as they dry, which is why it fastens things no knot would
	# hold. Hardness 1.5 -- dried rawhide is stiff but a fingernail still marks
	# it. Sharpness_capacity 0.0: skin takes no edge. Flammability 3.0, well
	# under wood's 8.0: keratin and collagen are genuinely hard to ignite (this
	# is the same chemistry that makes wool a flame-retardant fibre) -- they
	# char and self-extinguish rather than sustaining a flame. Decay_rate 8.0,
	# just under raw flesh's 9.0 and far above leather's: an untanned hide rots
	# within days in the wet, which is precisely the problem tanning solves.
	"hide": {
		"density": 1.0,
		"hardness": 1.5,
		"toughness": 7.0,
		"elasticity": 4.0,
		"sharpness_capacity": 0.0,
		"flammability": 3.0,
		"conductivity": 1.619048e-08,
		"decay_rate": 8.0,
	},
	# Vegetable-tanned leather: 0.9 g/cm^3 (tanning drives out water and
	# deposits tannin, and the result floats). Shares hide's shape but for two
	# changes, both of which ARE the tanning: toughness 8.0 (cross-linked
	# collagen is tear-resistant enough to be armour) and decay_rate 3.0 against
	# hide's 8.0. That drop is the whole invention -- tannins cross-link the
	# collagen and poison the microbes that eat raw skin, so leather artifacts
	# survive centuries where rawhide does not survive a wet season. Exactly the
	# same wood -> timber shape this table already uses for seasoning, and
	# pinned by test_tanning_is_what_makes_leather_outlast_a_raw_hide.
	"leather": {
		"density": 0.9,
		"hardness": 2.0,
		"toughness": 8.0,
		"elasticity": 4.0,
		"sharpness_capacity": 0.0,
		"flammability": 3.0,
		"conductivity": 1.619048e-17,
		"decay_rate": 3.0,
	},
	# Cortical bone: 1.9 g/cm^3, a real measured figure. Bone is a natural
	# composite -- brittle mineral (hydroxyapatite) reinforced by ductile
	# collagen -- so it lands where no purely mineral row can: hardness 3.5,
	# level with wood, but toughness 5.0, five times obsidian's, because the
	# collagen blunts cracks. Sharpness_capacity 3.0, below stone's 4.0 and far
	# below the keen line: bone needles, awls and harpoon points are real and
	# bone razors are not. Elasticity 3.0 (E ~ 18 GPa) -- bone genuinely springs,
	# which is why antler and bone back real bows. Decay_rate 2.0, lower than
	# any other organic row here by a wide margin: bone is what survives to be
	# dug up, and that is why there is a fossil record at all.
	"bone": {
		"density": 1.9,
		"hardness": 3.5,
		"toughness": 5.0,
		"elasticity": 3.0,
		"sharpness_capacity": 3.0,
		"flammability": 2.0,
		"conductivity": 1.619048e-13,
		"decay_rate": 2.0,
	},
	# Dried sinew (tendon): 1.1 g/cm^3. This row exists to be the best cordage
	# in the game and it earns both superlatives honestly. Elasticity 7.0, the
	# highest in the table, above plant fibre's 6.0: tendon is the biological
	# spring -- it returns something like 90% of the elastic energy put into it,
	# which is the entire mechanism of a sinew-backed bow. Toughness 9.0, also
	# the highest: a sinew bowstring beats a bast one, and every hafting in a
	# pre-textile toolkit is sinew or rawhide. Hardness 1.0 and
	# sharpness_capacity 0.0 -- it is a rope, not a tool. Decay_rate 7.0: dry
	# sinew keeps for years and wet sinew rots, so it sits with plant fibre
	# rather than with hide.
	"sinew": {
		"density": 1.1,
		"hardness": 1.0,
		"toughness": 9.0,
		"elasticity": 7.0,
		"sharpness_capacity": 0.0,
		"flammability": 3.0,
		"conductivity": 6.571429e-08,
		"decay_rate": 7.0,
	},
	# Soda-lime glass: 2.5 g/cm^3. Deliberately placed against obsidian rather
	# than measured independently, because the two ARE the same class of
	# substance -- a silicate glass -- and the table's job is to keep them
	# legible against each other. Obsidian keeps the edge on both hardness (9.0
	# vs 8.0) and sharpness_capacity (10.0 vs 9.0) for a real reason: obsidian
	# is ~70-75% SiO2 with little alkali, while soda-lime glass trades ~15% of
	# that network for Na2O to melt at a workable temperature, and the alkali is
	# what softens it. Toughness 0.8, BELOW obsidian's 1.0 and the lowest in the
	# table: manufactured glass is the archetype of a brittle solid. Elasticity
	# 0.0, like obsidian -- there is no plastic range at all, it is elastic right
	# up to the instant it shatters. Decay_rate 0.0: glass is chemically inert,
	# which is why Roman glass comes out of the ground intact.
	"glass": {
		"density": 2.5,
		"hardness": 8.0,
		"toughness": 0.8,
		"elasticity": 0.0,
		"sharpness_capacity": 9.0,
		"flammability": 0.0,
		"conductivity": 1.619048e-20,
		"decay_rate": 0.0,
	},
	# Silver: 10.49 g/cm^3, and the anchor of the conductivity column (105%
	# IACS -- the true maximum of the periodic table, see IACS_SILVER_PERCENT).
	# Everything else about it says "not a tool": hardness 2.5 (Mohs 2.5-3,
	# ~25 HB annealed, HALF copper's ~50 HB, and copper was already too soft to
	# beat flint), sharpness_capacity 2.5 below copper's 4.0. Toughness 8.5,
	# above copper's 8.0 -- silver is more ductile still. Decay_rate 1.5: silver
	# tarnishes to a sulfide film but does not corrode away, so it outlasts
	# copper without reaching gold's total immunity.
	"silver": {
		"density": 10.49,
		"hardness": 2.5,
		"toughness": 8.5,
		"elasticity": 2.5,
		"sharpness_capacity": 2.5,
		"flammability": 0.0,
		"conductivity": 10.0,
		"decay_rate": 1.5,
	},
	# Gold: 19.30 g/cm^3, by a wide margin the densest thing in the table --
	# which is not decoration, it is why panning works and why a gilded fake is
	# detectable by weight alone. The softest metal here (hardness 2.0, Mohs
	# 2.5) and the most ductile (toughness 9.0: one gram draws to two kilometres
	# of wire). Decay_rate 0.0 -- gold is noble, it does not corrode at all, and
	# that single fact is why it became money and why grave goods come up
	# bright after three thousand years.
	"gold": {
		"density": 19.30,
		"hardness": 2.0,
		"toughness": 9.0,
		"elasticity": 2.5,
		"sharpness_capacity": 1.5,
		"flammability": 0.0,
		"conductivity": 6.666667,
		"decay_rate": 0.0,
	},
	# Zinc: 7.14 g/cm^3, the brass solute. Hardness 2.5 -- above tin's 1.5 and
	# below copper's 4.0, which is the ordering brass needs to make sense.
	# Toughness 3.5, the LOWEST of any metal here: cast zinc genuinely cleaves
	# where cast copper bends, and it sits just above the brittle cutoff rather
	# than below it because rolled zinc is workable. Flammability 2.0, alone
	# among the metals: zinc boils at 907 C, below copper's melting point, so
	# it burns off as vapour -- which is exactly why brass had to be made by
	# cementation with zinc ORE for two thousand years before anyone could add
	# zinc metal to a melt. Decay_rate 1.0: zinc's carbonate patina is
	# passivating, which is the entire premise of galvanizing.
	"zinc": {
		"density": 7.14,
		"hardness": 2.5,
		"toughness": 3.5,
		"elasticity": 3.0,
		"sharpness_capacity": 1.0,
		"flammability": 2.0,
		"conductivity": 2.571429,
		"decay_rate": 1.0,
	},
}

## How a material fails when it gets hot enough, in real degrees Celsius.
##
## ## Why real degrees and not a ninth 0-10 scalar
##
## Because the only thing this number is FOR is being compared against other
## real temperatures -- a furnace's, a eutectic's -- and both of those are
## published in Celsius. A 0-10 band could not be compared with either.
## `density` already ships in real g/cm^3, so a real-units column is not a new
## precedent here, it is the second one.
##
## ## Why it is not part of the property vector
##
## An alloy vector has to stay shape-identical to a MATERIALS row -- that is
## what lets a computed blend flow through impact_resolver/descriptors_for/
## mass_kg_for unchanged -- and AlloyBlend.melting_point_c makes exactly the
## same argument from the other side. Adding a ninth key would also force every
## non-melting material to report a melting point it does not have. So it lives
## beside the vector, with the mode travelling alongside the number.
##
## ## The four modes, and why three were not enough
##
## The brief for this pass named three (melt/ignite/fracture). Protein tissue
## needs a fourth: a hide neither melts nor sustains a flame -- keratin and
## collagen char and self-extinguish, which is the same chemistry that makes
## wool a flame-retardant fibre -- so "char" is a real distinction rather than a
## softer word for "ignite".
##
## ## Grounding, per mode
##
## - **melt** (metals, glasses). The metals are NOT restated here: they are
##   AlloyBlend.ELEMENT_CONSTANTS' own published melting points converted out of
##   kelvin, pinned equal by
##   test_the_metal_melting_points_are_the_alloy_models_own_published_constants,
##   because a tooltip saying 1085 while the cryoscopic model used 1084.62 is
##   exactly the drift this project keeps warning about. The two glasses are
##   different in kind: a glass has no melting POINT, it has a transition, so
##   these are the published glass-transition temperatures -- ~550 C for
##   soda-lime glass and ~700 C for rhyolitic obsidian -- i.e. the temperature
##   at which each stops being a solid. That is why glassworking is possible at
##   a heat that cannot pour bronze.
## - **fracture** (stone). 573 C is the alpha-to-beta quartz inversion, where
##   quartz changes volume abruptly and tears the rock apart. This is why
##   fire-cracked rock is a diagnostic artifact class in real archaeology --
##   hearth stones shatter, reliably, at a specific published temperature.
## - **ignite** (the cellulose fuels). Wood's autoignition sits at ~300 C, and
##   charcoal's is higher (~349 C) despite burning hotter, which is exactly why
##   charcoal is harder to light and better to smelt with.
## - **char** (the protein tissues). Collagen and keratin decompose in the
##   200-300 C band without a melt and without a self-sustaining flame; bone
##   holds out a little longer (~300 C) because only its collagen fraction is
##   organic, and what is left when that burns off is the mineral that survives
##   in the ground. Note that COOKING is a completely different and far lower
##   threshold -- protein denatures around 65 C -- and belongs to cooking.gd;
##   this column is about structural failure, not edibility.
const THERMAL_FAILURE: Dictionary = {
	"tin": {"c": 231.93, "mode": "melt"},
	"zinc": {"c": 419.53, "mode": "melt"},
	"silver": {"c": 961.78, "mode": "melt"},
	"gold": {"c": 1064.18, "mode": "melt"},
	"copper": {"c": 1084.62, "mode": "melt"},
	"iron": {"c": 1537.85, "mode": "melt"},
	"glass": {"c": 550.0, "mode": "melt"},
	"obsidian": {"c": 700.0, "mode": "melt"},
	"stone": {"c": 573.0, "mode": "fracture"},
	"wood": {"c": 300.0, "mode": "ignite"},
	"timber": {"c": 300.0, "mode": "ignite"},
	"fiber": {"c": 300.0, "mode": "ignite"},
	"carbon": {"c": 349.0, "mode": "ignite"},
	"flesh": {"c": 250.0, "mode": "char"},
	"hide": {"c": 250.0, "mode": "char"},
	"leather": {"c": 250.0, "mode": "char"},
	"sinew": {"c": 250.0, "mode": "char"},
	"bone": {"c": 300.0, "mode": "char"},
}

## The four ways a material can fail under heat. A fixed list so that adding a
## fifth is a deliberate decision, checked by
## test_every_material_has_a_real_thermal_failure_temperature_and_mode.
const THERMAL_FAILURE_MODES: Array[String] = ["melt", "ignite", "char", "fracture"]

## What thermal_failure_c answers for a material with no entry: nothing this
## game models will ever hurt it. INF says that, where a large number would
## quietly be a claim.
const NO_THERMAL_FAILURE: float = INF

## What thermal_failure_mode answers for a material with no entry.
const NO_FAILURE_MODE: String = ""

## What real heat sources actually reach, in Celsius.
##
## These three numbers are the entire tech tree's gating, and NONE of them is a
## game-balance choice -- they are what the real stations reach, and the
## progression they produce is the real one:
##
## - **campfire, ~800 C.** An open wood fire runs 600-900 C. It melts tin and
##   zinc and works glass, and it comes nowhere near copper -- which is exactly
##   the Chalcolithic problem, and why native copper was hammered cold for
##   millennia before anyone cast it.
## - **bloomery, ~1200 C.** A shaft furnace with forced draught reaches
##   1200-1300 C at the tuyere. That pours copper (1085), bronze (which melts
##   BELOW copper, ~1000 -- see AlloyBlend.melting_point_c) and cast iron
##   (~1200 at the eutectic), but it cannot melt wrought iron at 1538. Which is
##   precisely why a bloomery produces a solid-state *bloom* to be hammered
##   rather than a pour, for the whole of the Iron Age.
## - **crucible furnace, ~1600 C.** The temperature at which iron and steel
##   finally pour, and historically the temperature at which crucible steel
##   appears.
##
## The payoff is that no recipe anywhere needs a "requires: crucible" flag.
## Iron requires a crucible because 1537.85 > 1200. Pinned by
## test_station_temperature_gates_the_tech_tree_with_no_authored_gating.
const STATION_TEMPERATURE_C: Dictionary = {
	"campfire": 800.0,
	"bloomery": 1200.0,
	"crucible_furnace": 1600.0,
}

## Water's relative density -- the buoyancy cutoff for RAFT viability.
## See test_iron_is_not_viable_raft_material / test_wood_is_viable_raft_material.
const WATER_DENSITY: float = 1.0

## Hardness at or above which a material reads as "hard" to the player (see
## descriptors_for). Set at stone's own hardness (7.0): stone is the everyday
## reference for "hard" in a hand -- a stone and everything harder (iron 8,
## obsidian 9) is hard, wood (3) and flesh (1) are not. Pinned by
## test_iron_and_stone_read_as_hard_but_wood_does_not.
const HARD_HARDNESS: float = 7.0

## Sharpness capacity at or above which a material reads as "keen" -- it can
## hold a genuinely cutting edge rather than merely a worked point. Set at
## iron's own sharpness_capacity (8.0), the material the game treats as the
## benchmark blade: iron and obsidian (10) are keen, knapped stone (4) is not.
## Pinned by test_obsidian_and_iron_read_as_keen_but_stone_does_not.
const KEEN_SHARPNESS: float = 8.0

## Toughness below which a material reads as "brittle". This is deliberately
## THE SAME cutoff the impact model already fractures things at
## (ImpactResolver.T_BRITTLE_TOUGHNESS) rather than a second opinion on the
## same line -- a word the tooltip uses and a behaviour the physics uses must
## mean one thing. Restated here rather than preloaded because
## impact_resolver.gd already preloads THIS file, and the reverse preload
## would be a cycle; the two are pinned equal by
## test_the_brittle_descriptor_uses_the_same_toughness_cutoff_the_impact_model_does,
## so they cannot drift apart silently.
const BRITTLE_TOUGHNESS: float = 3.0

## Minimum toughness a material needs to serve as a GRAPPLE_ROPE. This "8-bit"
## vector has no separate tensile-strength scalar, so toughness (resistance
## to fracture under stress) stands in for it -- the closest of the 8
## documented scalars to "won't snap under load". See
## test_fiber_is_viable_grapple_rope_material /
## test_obsidian_is_not_viable_grapple_rope_material.
const ROPE_MIN_TOUGHNESS: float = 5.0


## The temperature in Celsius at which `material` stops being usable as a
## solid. NO_THERMAL_FAILURE for anything unmodeled.
func thermal_failure_c(material: String) -> float:
	var failure: Dictionary = THERMAL_FAILURE.get(material, {})
	return float(failure.get("c", NO_THERMAL_FAILURE))


## WHAT happens at that temperature -- "melt", "ignite", "char" or "fracture".
## Half this table does not melt, and reporting a bare number for a hide or a
## hearth stone would be a number standing in place of the truth.
func thermal_failure_mode(material: String) -> String:
	var failure: Dictionary = THERMAL_FAILURE.get(material, {})
	return String(failure.get("mode", NO_FAILURE_MODE))


## Whether a station at `temperature_c` can actually MELT this material -- the
## tech gate. Failing some other way does not count: a stone that has spalled
## at 573 C has not become pourable, and neither has a charred hide.
func can_melt(material: String, temperature_c: float) -> bool:
	return thermal_failure_mode(material) == "melt" and thermal_failure_c(material) <= temperature_c


## Everything a station at `temperature_c` can melt, alphabetically (so the
## answer is deterministic and comparable). This is the tech tree as a derived
## query rather than an authored list -- a new material joins it by having a
## melting point, not by being added to a gate.
func materials_meltable_at(temperature_c: float) -> Array[String]:
	var meltable: Array[String] = []
	for material in MATERIALS:
		if can_melt(material, temperature_c):
			meltable.append(material)
	meltable.sort()
	return meltable


## A published %IACS figure put onto the table's 0-10 scale. The ONLY thing
## that may produce a value in the conductivity column.
##
## Linear, anchored on silver: `CONDUCTIVITY_MAX * iacs / IACS_SILVER_PERCENT`.
## Nothing else is chosen -- the anchor is a real measurement, the ceiling is a
## constant the table already had, and every input is a published figure, so
## there is no free parameter anywhere in the column.
##
## The honest cost of a LINEAR scale is worth stating plainly: real electrical
## conductivity spans roughly 24 orders of magnitude, so once silver is at the
## top every non-metal is indistinguishable from zero. That is the right answer
## for what this scalar is FOR -- electromagnetism.md wants to know whether a
## piece of material can carry a circuit, and the answer for wood, stone, bone
## and glass is no, by twenty orders of magnitude. What the scale cannot do is
## rank insulators against each other; the stored figures still can, and
## test_no_non_metal_registers_at_all_on_a_conductor_scale pins the limitation
## rather than hiding it. A log scale would preserve that ranking and destroy
## the ability to read the column as a plain "how good a conductor is this",
## which is the trade this column deliberately does not make.
func conductivity_from_iacs(iacs_percent: float) -> float:
	return CONDUCTIVITY_MAX * iacs_percent / IACS_SILVER_PERCENT


## A single named scalar from `material`'s property vector. Unknown
## materials, and unknown properties on known materials, both fall back to
## DEFAULT_PROPERTIES.
func property_value(material: String, property_name: String) -> float:
	var vector: Dictionary = MATERIALS.get(material, DEFAULT_PROPERTIES)
	return vector.get(property_name, DEFAULT_PROPERTIES.get(property_name, 1.0))


## Real mass in kilograms for `volume_cm3` of `material` -- density is
## already expressed in real g/cm^3 (relative to water == 1.0 g/cm^3, see
## DEFAULT_PROPERTIES' own doc comment), so this is exactly density x volume,
## the same "density x volume" shape StoneSize.mass_kg_for uses for a stone's
## sphere volume, generalized to an arbitrary item (see item_catalog.gd's
## weapon mass wiring). Feeds the shared momentum model (docs/concept/
## materials.md's momentum = mass * velocity, impact_resolver.gd/
## throwable.gd) for weapons/tools the same way StoneSize.mass_kg_for feeds
## it for loose stone.
func mass_kg_for(material: String, volume_cm3: float) -> float:
	var density_g_per_cm3 := property_value(material, "density")
	return density_g_per_cm3 * volume_cm3 / 1000.0


## Plain-language descriptors for `material`, in a fixed order (hard, keen,
## brittle, buoyant).
##
## docs/concept/materials.md's "Learning an emergent system" is explicit that
## the player-facing default is descriptors + discovery, NOT a raw scalar
## spreadsheet -- so this is how the 8-scalar property vector is allowed to
## reach a tooltip. Weight is deliberately NOT among the words: an item's real
## mass in kilograms is already shown as a real number (see
## MaterialProperties.mass_kg_for / ItemCatalog._mass_kg_for), so "heavy"
## would be a vaguer restatement of something the player can already read
## exactly.
##
## Every threshold is a named, calibration-tested constant (HARD_HARDNESS,
## KEEN_SHARPNESS, BRITTLE_TOUGHNESS, WATER_DENSITY), and the last two are the
## cutoffs the game had ALREADY calibrated for fracture and for raft buoyancy,
## reused rather than re-guessed.
##
## A material with no vector of its own gets NO words rather than the
## DEFAULT_PROPERTIES fallback's: describing an unmodeled material would be
## stating something the game has not decided (the same "not modeled yet"
## honesty Item.mass_kg's 0.0 stands for).
func descriptors_for(material: String) -> Array[String]:
	if not MATERIALS.has(material):
		return [] as Array[String]
	return descriptors_for_vector(MATERIALS[material])


## The same words, for a property vector that has no name.
##
## An alloy (alloy_blend.gd) is a computed vector, not a table row, so it can
## never be reached by name -- and materials.md's "an alloy is just one more
## way to arrive at a property vector" was quietly untrue in code until this
## existed, because every consumer took a String and looked it up.
##
## descriptors_for is now a lookup in front of this rather than a second
## implementation of the same four thresholds, so a named material and an
## identical computed vector cannot drift into describing themselves
## differently.
func descriptors_for_vector(vector: Dictionary) -> Array[String]:
	var words: Array[String] = []
	if float(vector.get("hardness", DEFAULT_PROPERTIES["hardness"])) >= HARD_HARDNESS:
		words.append("hard")
	if float(vector.get("sharpness_capacity", DEFAULT_PROPERTIES["sharpness_capacity"])) >= KEEN_SHARPNESS:
		words.append("keen")
	if float(vector.get("toughness", DEFAULT_PROPERTIES["toughness"])) < BRITTLE_TOUGHNESS:
		words.append("brittle")
	if float(vector.get("density", DEFAULT_PROPERTIES["density"])) < WATER_DENSITY:
		words.append("buoyant")
	return words


## Traversal-tool viability per docs/concept/transportation.md's "Traversal
## tools" section: a raft needs a buoyant (low-density) material, a grapple
## rope needs a tough material. Unknown tool types are never viable.
func is_viable_for_tool(material: String, tool_type: String) -> bool:
	match tool_type:
		"raft":
			return property_value(material, "density") < WATER_DENSITY
		"grapple_rope":
			return property_value(material, "toughness") >= ROPE_MIN_TOUGHNESS
		_:
			return false
