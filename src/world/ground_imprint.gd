extends RefCounted

## Whether real ground takes a footprint AT ALL -- one real physical
## comparison, not a list of tile ids that are exempt from footprints.
##
## Reported live: "walking over cobblestone streets should not leave
## footprints", answered with: "this should work out of the box through
## physics." It does, and this file is that sentence written out:
##
##   A footprint IS an indentation. Indentation hardness is BY DEFINITION
##   the mean contact pressure it takes to leave a permanent indentation
##   in a material. So a print forms exactly when the foot presses harder
##   than the ground resists -- and on nothing else.
##
## Both sides of that comparison are already real, published numbers this
## project keeps: the Vickers column in `MaterialProperties.HARDNESS_HV`
## is quoted in kgf/mm^2, which IS a pressure (see KPA_PER_HV), and a
## walker's own mass is `CreatureMass`'s own real, cited figure. Laid
## granite setts lose that comparison by roughly five orders of
## magnitude, which is why a cobbled street takes no print.
##
## The road tile IS named once, in `material_underfoot` below -- but only
## to answer what a paved cell is MADE OF (setts, i.e. stone). Nothing
## anywhere asks whether a road should have footprints; that follows from
## the material, like it does for every other surface, which is what
## makes a timber floor fall out of the same rule for free.
##
## Deliberately says nothing about how BIG a print is: that is already
## mass's job (`CreatureMass.linear_scale_for_mass_ratio`, see
## docs/concept/snow_cover.md's "Footprints depend on real mass, not just
## surface"), and nothing here changes it. This file answers only the
## prior question -- whether there is a mark to size in the first place.
##
## See docs/concept/snow_cover.md's "Ground that is too hard to take a
## print" and docs/concept/infrastructure.md's Road tier.

const MaterialProperties = preload("res://src/gameplay/material_properties.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## The two ground materials that are ground rather than a craft material,
## so `MaterialProperties`' own table has no row for them (adding one
## would put "soil" in a column the forge, the alloy model and the impact
## resolver all read). Their own real figures live in
## GROUND_HARDNESS_KPA below.
const SOIL := "soil"
const SNOW := "snow"

## Real single-foot plantar contact area of the reference walker
## (`CreatureMass.PLAYER_MASS_KG`, the same 70kg human the existing print
## art is sized for -- see that constant's own doc comment). Published
## adult plantar contact areas in standing/walking stance run roughly
## 130-150 cm^2; 0.014 m^2 (140 cm^2) is the middle of that. Expressed as
## ONE foot, not two, because a footprint is what ONE foot leaves: at any
## instant during a walking stride the body's whole weight is over a
## single sole.
const REFERENCE_PLANTAR_AREA_M2 := 0.014

## One kgf/mm^2 -- the unit Vickers hardness is quoted in -- is one
## STANDARD gravity times a kilogram over a square millimetre, i.e.
## 9.80665 MPa, i.e. 9806.65 kPa. A definition, not a tuning knob, and
## what lets the published hardness column be compared directly against a
## real footfall.
##
## Deliberately NOT `GroundSlide.GRAVITY_MPS2` (9.81, the rounded local g
## this project's gameplay dynamics use): the kilogram-force is DEFINED
## against standard gravity, 9.80665 exactly, which is the figure
## `PartMechanics.GRAVITY_MS2` already carries. Restated here rather than
## preloading that file -- it pulls the whole item/part graph in behind it
## for one number -- and pinned equal to it by
## test_vickers_hardness_is_a_real_pressure instead, so the two cannot
## drift apart silently. The same arrangement `MaterialProperties.
## CONDUCTIVITY_MAX` already uses against `AlloyBlend.SCALE_MAX`.
const KPA_PER_HV := 9806.65

## Real indentation resistance, kPa, of the ground materials that have no
## Vickers figure because indentation hardness is not how either is
## measured (the same honesty `MaterialProperties.HARDNESS_HV`'s own five
## placed organics already practise, stated on their own lines).
##
## Snow: the ram-hardness range quoted for new/settled snow runs roughly
## 1-10 kPa; 5 kPa is the middle of it. Soil: the standard consistency
## classification for cohesive soil puts the very-soft/soft boundary at an
## unconfined compressive strength of 25 kPa, which is the figure for
## exactly the moist, unconsolidated topsoil a footprint appears in.
##
## Both sit BELOW the reference footfall below, which is the whole reason
## footprints exist in this game at all -- pinned by
## test_soft_ground_carries_real_figures_and_keeps_its_real_ordering.
const GROUND_HARDNESS_KPA := {
	SNOW: 5.0,
	SOIL: 25.0,
}


## The real pressure, kPa, a walker of `mass_kg` puts on the ground under
## one foot: its weight over its own plantar contact area.
##
## Contact area follows the SQUARE of a linear dimension while mass
## follows its CUBE -- the same real geometric relationship
## `CreatureMass.linear_scale_for_mass_ratio` already encodes in the other
## direction -- so the area scales as the 2/3 power of the mass ratio and
## the PRESSURE rises only as its cube root: eight times the animal
## presses just twice as hard. That compression is what keeps a built
## surface out of reach of EVERYTHING that walks rather than merely of
## light things -- see yields_to_footfall, which states both sides of
## that argument, including the one it does not win outright.
##
## Zero (never a division by zero or a negative pressure) for a
## non-positive mass -- the same "narrows, never crashes" contract
## `CreatureMass.linear_scale_for_mass_ratio` itself already follows.
static func footfall_pressure_kpa(mass_kg: float) -> float:
	if mass_kg <= 0.0:
		return 0.0
	var area_m2: float = REFERENCE_PLANTAR_AREA_M2 * pow(mass_kg / CreatureMass.PLAYER_MASS_KG, 2.0 / 3.0)
	return mass_kg * GroundSlide.GRAVITY_MPS2 / area_m2 / 1000.0


## The pressure the reference walker -- the player, the same 70kg human
## the print art is sized for -- actually presses with. The threshold
## every material below is measured against.
static func reference_footfall_pressure_kpa() -> float:
	return footfall_pressure_kpa(CreatureMass.PLAYER_MASS_KG)


## Real indentation hardness, kPa: the mean contact pressure it takes to
## leave a permanent mark in `material`. Ground materials come from
## GROUND_HARDNESS_KPA above; everything else is read straight off
## `MaterialProperties.HARDNESS_HV`'s published Vickers column, converted
## -- never re-stated here, so granite cannot end up with two different
## hardnesses in one codebase.
##
## An unlisted material resists nothing (0.0), mirroring
## `MaterialProperties.DEFAULT_PROPERTIES`' own established rule -- "not
## having measured something is not a reason to call it iron" -- in the
## direction that matters for ground: unmeasured ground is ordinary
## ground, never a hard surface that silently swallows footprints.
static func indentation_hardness_kpa(material: String) -> float:
	if GROUND_HARDNESS_KPA.has(material):
		return float(GROUND_HARDNESS_KPA[material])
	return float(MaterialProperties.HARDNESS_HV.get(material, 0.0)) * KPA_PER_HV


## Whether ground of this material gives way under a real footfall.
##
## Stated per MATERIAL rather than per walker, and the two sides of that
## choice are honestly different sizes.
##
## The BUILT side is not close at ANY mass. Timber is the softest thing
## anything here is built of, 36 MPa, and the heaviest species
## `CreatureMass` tabulates -- a 500kg horse, pressing with ~94 kPa
## against the reference walker's own ~49 -- is still some 380x short of
## it; granite is a further ~190x beyond timber. Nothing that walks in
## this world reaches a laid surface, so a street is a street for every
## one of them (pinned by
## test_no_animal_in_this_world_can_indent_laid_stone and
## test_not_even_the_heaviest_walker_reaches_the_softest_built_material).
##
## The SOFT side is a deliberate simplification, and says so: soil's 25
## kPa sits below the reference walker's own footfall but ABOVE a light
## enough animal's (a 20g mouse presses with only ~3 kPa), so asking this
## per walker would stop a mouse leaving a print on turf. That is a real
## effect -- and a different, unasked change to a documented mechanic, in
## which mass scales how big the mark is and never whether there is one
## (see docs/concept/snow_cover.md's "Footprints depend on real mass, not
## just surface"). This pass deliberately leaves that alone.
static func yields_to_footfall(material: String) -> bool:
	return indentation_hardness_kpa(material) <= reference_footfall_pressure_kpa()


## What a foot actually touches at a cell whose modification is `tile_id`
## ("" for untouched ground).
##
## Snow first, mirroring `EarthChunkManager.footstep_surface_for`'s own
## snow-first precedence exactly and for the same real reason: snow lies
## ON TOP of whatever is underneath it, streets included, so a snowed-over
## street is snow underfoot.
##
## A laid road is cobble setts -- stone (docs/concept/infrastructure.md's
## Road tier: "a flat cobble surface"). A built piece is whatever
## `BuildingPiece` already says it is built OF, never a second list here.
## Everything else -- untouched ground, dug earth, a PathScarring-worn
## trail -- is the soil it always was; a trail is literally made BY feet,
## so it had better keep taking theirs.
static func material_underfoot(tile_id: String, snow_lying: bool) -> String:
	if snow_lying:
		return SNOW
	if TerrainRenderer.is_road_tile(tile_id):
		return BuildingPiece.MATERIAL_STONE
	if BuildingPiece.has_piece(tile_id):
		return BuildingPiece.material_of(tile_id)
	return SOIL


## The one call the world makes (see `EarthChunkManager.record_footstep`):
## does a footfall on this cell leave a mark behind?
static func takes_a_print(tile_id: String, snow_lying: bool) -> bool:
	return yields_to_footfall(material_underfoot(tile_id, snow_lying))
