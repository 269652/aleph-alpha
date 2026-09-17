extends GutTest

## GroundImprint: whether real ground takes a footprint AT ALL, decided by
## real indentation physics rather than by a list of exempt tile ids.
##
## Reported live: "walking over cobblestone streets should not leave
## footprints", answered with: "this should work out of the box through
## physics." A footprint IS an indentation, and indentation hardness --
## the Vickers column `MaterialProperties.HARDNESS_HV` already publishes,
## in kgf/mm^2, which is a pressure -- is by definition the mean contact
## pressure it takes to leave one. So the whole question is one
## comparison: does a foot press harder than the ground resists?
##
## See docs/concept/snow_cover.md's "Ground that is too hard to take a
## print" and docs/concept/infrastructure.md's Road tier.

const GroundImprint = preload("res://src/world/ground_imprint.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const PartMechanics = preload("res://src/gameplay/part_mechanics.gd")


# -- what a foot actually presses with -------------------------------------

## Weight over a real plantar contact area -- no free parameter, and no
## second "how hard does a step press" knob anywhere.
func test_a_footfall_is_weight_spread_over_a_real_plantar_contact_area():
	var expected := (
		CreatureMass.PLAYER_MASS_KG * GroundSlide.GRAVITY_MPS2
		/ GroundImprint.REFERENCE_PLANTAR_AREA_M2 / 1000.0
	)
	assert_almost_eq(
		GroundImprint.footfall_pressure_kpa(CreatureMass.PLAYER_MASS_KG), expected, 0.001,
		"the player's own footfall must be exactly its own weight over its own sole"
	)


## Contact area follows the SQUARE of a linear dimension while mass
## follows its CUBE (the same relation CreatureMass.linear_scale_for_mass_
## ratio already encodes in the other direction), so plantar pressure
## rises only as the CUBE ROOT of mass: eight times the animal presses
## just twice as hard.
func test_footfall_pressure_rises_only_as_the_cube_root_of_mass():
	var light := GroundImprint.footfall_pressure_kpa(10.0)
	var eightfold := GroundImprint.footfall_pressure_kpa(80.0)
	assert_almost_eq(eightfold / light, 2.0, 0.001)


## The same "narrows, never crashes" contract every other defensive
## numeric guard in this codebase follows -- a massless walker presses
## with nothing, it does not divide by zero.
func test_a_non_positive_mass_presses_with_nothing():
	assert_eq(GroundImprint.footfall_pressure_kpa(0.0), 0.0)
	assert_eq(GroundImprint.footfall_pressure_kpa(-5.0), 0.0)


# -- what the ground resists with ------------------------------------------

## Vickers hardness is quoted in kgf/mm^2, which IS a pressure: one
## kilogram-force over a square millimetre, and the kilogram-force is
## DEFINED against standard gravity. Pinned against the standard-gravity
## figure this project already carries rather than against a second copy
## of the same digits -- see GroundImprint.KPA_PER_HV's own doc comment on
## why it is restated rather than preloaded.
func test_vickers_hardness_is_a_real_pressure():
	assert_almost_eq(GroundImprint.KPA_PER_HV, PartMechanics.GRAVITY_MS2 * 1000.0, 0.001)


## Granite's hardness is read straight off the published column this
## project already keeps (see MaterialProperties.HARDNESS_HV's own doc
## comment on why 700 HV is the mineral-fraction-weighted figure) -- a
## second, independently-placed granite number here would be exactly the
## kind of drift that column exists to prevent.
func test_laid_stone_reads_the_published_vickers_column_rather_than_a_second_number():
	assert_almost_eq(
		GroundImprint.indentation_hardness_kpa("stone"),
		float(MaterialProperties.HARDNESS_HV["stone"]) * GroundImprint.KPA_PER_HV,
		0.001
	)


## Soft ground is a real measurement too, not an absence: settled snow's
## own ram hardness and soft cohesive soil's own unconfined compressive
## strength, both in the same kPa the footfall above is expressed in.
func test_soft_ground_carries_real_figures_and_keeps_its_real_ordering():
	var snow := GroundImprint.indentation_hardness_kpa(GroundImprint.SNOW)
	var soil := GroundImprint.indentation_hardness_kpa(GroundImprint.SOIL)
	assert_gt(snow, 0.0, "snow resists something, it is not a free fall")
	assert_lt(snow, soil, "settled snow gives way more readily than soil does")
	assert_lt(
		soil, GroundImprint.footfall_pressure_kpa(CreatureMass.PLAYER_MASS_KG),
		"ordinary ground yields to an ordinary step -- that is why prints exist at all"
	)


## Mirrors MaterialProperties.DEFAULT_PROPERTIES' own established rule --
## "not having measured something is not a reason to call it iron" -- for
## ground: unmeasured ground is ordinary ground, never a hard surface.
func test_unmeasured_ground_is_not_assumed_to_be_stone():
	assert_eq(GroundImprint.indentation_hardness_kpa("no_such_material"), 0.0)
	assert_true(GroundImprint.yields_to_footfall("no_such_material"))


# -- the comparison itself -------------------------------------------------

## The heart of it: laid granite is not marginally too hard, it is five
## orders of magnitude too hard, so NOTHING that walks in this world --
## not the heaviest real species this game tabulates -- can dent a street.
## The margin is what makes the per-material verdict below safe to state
## once for every walker instead of per footfall.
func test_no_animal_in_this_world_can_indent_laid_stone():
	var heaviest := CreatureMass.mass_kg_for("horse")
	assert_gt(
		GroundImprint.indentation_hardness_kpa("stone"),
		GroundImprint.footfall_pressure_kpa(heaviest) * 1000.0,
		"a 500kg horse is still a thousandfold short of denting granite"
	)
	assert_false(GroundImprint.yields_to_footfall("stone"))


## Pins the other half of the margin GroundImprint.yields_to_footfall's
## own doc comment rests its per-material verdict on: it is not granite
## alone that is out of reach, it is the SOFTEST thing anything here is
## built of, for the HEAVIEST thing that walks.
func test_not_even_the_heaviest_walker_reaches_the_softest_built_material():
	var heaviest_footfall := GroundImprint.footfall_pressure_kpa(CreatureMass.mass_kg_for("horse"))
	var softest_built := GroundImprint.indentation_hardness_kpa("timber")
	for material in ["stone", "wood"]:
		assert_gte(
			GroundImprint.indentation_hardness_kpa(material), softest_built,
			"%s must not be softer than timber, or this test pins the wrong floor" % material
		)
	assert_gt(
		softest_built, heaviest_footfall * 100.0,
		"a 500kg horse is still two orders of magnitude short of denting a timber floor"
	)


func test_soft_ground_yields_but_built_materials_do_not():
	for material in [GroundImprint.SOIL, GroundImprint.SNOW]:
		assert_true(GroundImprint.yields_to_footfall(material), material)
	for material in ["stone", "timber", "wood"]:
		assert_false(GroundImprint.yields_to_footfall(material), material)


# -- what is actually underfoot at a cell ----------------------------------

func test_untouched_ground_is_soil():
	assert_eq(GroundImprint.material_underfoot("", false), GroundImprint.SOIL)


## A laid road is cobble setts (docs/concept/infrastructure.md's Road
## tier -- "a flat cobble surface"), i.e. stone.
func test_a_laid_road_is_stone():
	assert_eq(GroundImprint.material_underfoot(TerrainRenderer.ROAD_TILE_ID, false), "stone")


## Dug earth and a PathScarring-worn trail are the same soil they were
## worn out of -- a trail is literally made BY feet, so it had better keep
## taking their prints.
func test_dug_earth_and_a_worn_trail_are_still_soil():
	for tile_id in [TerrainRenderer.EARTH_TILE_ID, TerrainRenderer.TRAIL_TILE_ID]:
		assert_eq(GroundImprint.material_underfoot(tile_id, false), GroundImprint.SOIL, tile_id)


## A built piece is whatever it is built OF -- read from BuildingPiece's
## own material column, never re-listed here.
func test_a_built_floor_is_the_material_it_is_built_of():
	assert_eq(GroundImprint.material_underfoot("timber_floor", false), "timber")
	assert_eq(GroundImprint.material_underfoot("stone_floor", false), "stone")
	assert_eq(GroundImprint.material_underfoot("wood_floor", false), "wood")


## Snow lies ON TOP of everything, streets included (snow_depth() is a
## single global scalar -- see EarthChunkManager.footstep_surface_for's
## own snow-first precedence, mirrored here exactly): what the foot
## touches on a snowed-over street is the snow.
func test_snow_lies_on_top_of_whatever_is_underneath():
	assert_eq(GroundImprint.material_underfoot("", true), GroundImprint.SNOW)
	assert_eq(GroundImprint.material_underfoot(TerrainRenderer.ROAD_TILE_ID, true), GroundImprint.SNOW)
	assert_eq(GroundImprint.material_underfoot("stone_floor", true), GroundImprint.SNOW)


# -- the one call the world actually makes ---------------------------------

func test_takes_a_print_answers_the_whole_question_in_one_call():
	assert_true(GroundImprint.takes_a_print("", false), "untouched ground")
	assert_false(GroundImprint.takes_a_print(TerrainRenderer.ROAD_TILE_ID, false), "a cobbled street")
	assert_true(GroundImprint.takes_a_print(TerrainRenderer.ROAD_TILE_ID, true), "snow on that same street")
	assert_true(GroundImprint.takes_a_print(TerrainRenderer.TRAIL_TILE_ID, false), "a worn trail")
	assert_false(GroundImprint.takes_a_print("timber_floor", false), "a timber floor")
