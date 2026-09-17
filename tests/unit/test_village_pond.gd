extends GutTest

## VillagePond: the fisher's own 3x2 water, dug where the farmer's field is
## sown (see docs/concept/village_ponds.md). Asked for directly: "The Fisher
## should build a similar 3x2 enclosure but filled with water and a pond with
## river water physics and fish swimming in it which reproduce".
##
## These pin the SAMENESS as hard as the pond itself: a pond that sited or
## fenced itself by its own rule would drift away from the field it is
## modelled on, and "similar" is the whole of the ask.

const VillagePond = preload("res://src/gameplay/village_pond.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const HOUSE := "house_small"

var _anywhere := func(_cell: Vector2i) -> bool: return true


func test_a_pond_is_the_same_rectangle_a_field_would_be():
	var origin := Vector2i(6, 4)
	assert_eq(
		VillagePond.pond_rect(origin, HOUSE, _anywhere),
		VillageFarm.field_rect(origin, HOUSE, _anywhere),
		"a pond that sites itself by its own rule drifts away from the field"
	)


func test_a_pond_is_six_cells_in_one_of_the_shapes_that_was_asked_for():
	var rect = VillagePond.pond_rect(Vector2i(6, 4), HOUSE, _anywhere)
	assert_not_null(rect, "open ground has room for a pond")
	assert_true(VillageFarm.FIELD_SHAPES.has((rect as Rect2i).size), "3x2 or 2x3, as asked")
	assert_eq(VillagePond.pond_cells(Vector2i(6, 4), HOUSE, _anywhere).size(), 6)


func test_ground_with_no_room_gets_no_pond():
	var nowhere := func(_cell: Vector2i) -> bool: return false
	assert_null(VillagePond.pond_rect(Vector2i(6, 4), HOUSE, nowhere))
	assert_eq(VillagePond.pond_cells(Vector2i(6, 4), HOUSE, nowhere), [])


## The frame is the farm's frame, rails and all -- same ring, same facings,
## same corner posts.
func test_a_pond_is_fenced_exactly_the_way_a_field_is():
	var origin := Vector2i(6, 4)
	var cells := VillagePond.pond_cells(origin, HOUSE, _anywhere)
	assert_eq(
		VillagePond.fence_cells(origin, HOUSE, _anywhere),
		VillageFarm.fence_cells(cells, origin, HOUSE),
		"a pond's frame must be the field's frame"
	)


func test_the_water_has_a_tile_id_of_its_own():
	assert_ne(VillagePond.POND_TILE_ID, "", "built water has to persist as something")
	assert_true(VillagePond.is_pond_tile(VillagePond.POND_TILE_ID))
	assert_false(VillagePond.is_pond_tile(""))
	assert_false(VillagePond.is_pond_tile("farm_fence_north"))
	assert_false(
		VillageFarm.is_fence_tile(VillagePond.POND_TILE_ID),
		"water is not a rail -- it replaces the ground rather than standing on it"
	)


# -- fish that live there, and go on living there --------------------------
#
# "...and fish swimming in it which reproduce". A pond stocked once and
# fished flat is a bucket; a pond whose fish breed toward what the water can
# feed is a fishery (docs/concept/village_ponds.md).
#
# The population model is the world's OWN aquatic one, not a second one: a
# pond is a small body of water, and fish in it breed for the same reasons
# and at the same rate as fish anywhere else.

const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")

const MILD := 0.55  # AquaticPopulationModel.OPTIMAL_TEMPERATURE


func test_a_ponds_ceiling_is_the_worlds_own_aquatic_one_for_that_much_water():
	var cells := 6
	assert_almost_eq(
		VillagePond.carrying_capacity(cells, MILD),
		AquaticPopulationModel.new().carrying_capacity(float(cells), MILD),
		0.0001,
		"a pond with a ceiling of its own is a second model to keep in step"
	)


func test_more_water_feeds_more_fish():
	assert_gt(
		VillagePond.carrying_capacity(6, MILD), VillagePond.carrying_capacity(4, MILD),
		"a bigger pond has to feed more"
	)


## Cold or hot water feeds fewer, exactly as open water does.
func test_water_a_fish_cannot_thrive_in_feeds_fewer():
	assert_lt(VillagePond.carrying_capacity(6, 0.05), VillagePond.carrying_capacity(6, MILD))


## A pond is STOCKED, not spontaneous: nothing swims in water nobody put
## fish into, however good the water is.
func test_an_unstocked_pond_never_grows_fish_from_nothing():
	var population := VillagePond.step(0.0, 6, MILD, 30.0)
	assert_almost_eq(population, 0.0, 0.0001, "fish appeared in water nobody stocked")


func test_a_stocked_pond_breeds_toward_what_its_water_can_feed():
	var ceiling := VillagePond.carrying_capacity(6, MILD)
	var population := float(VillagePond.STOCKING_FISH)
	assert_lt(population, ceiling, "precondition: a stocking is below the ceiling")
	for _day in 40:
		population = VillagePond.step(population, 6, MILD, 1.0)
	assert_gt(population, float(VillagePond.STOCKING_FISH), "the stock never bred")
	assert_lte(population, ceiling + 0.0001, "a pond cannot feed more than its water can")


## And it does not overshoot: a pond already at its ceiling stays there.
func test_a_full_pond_stays_full():
	var ceiling := VillagePond.carrying_capacity(6, MILD)
	assert_almost_eq(VillagePond.step(ceiling, 6, MILD, 10.0), ceiling, 0.0001)


## Two is the smallest stocking that can breed at all -- one fish is a pet.
func test_a_stocking_is_enough_fish_to_breed():
	assert_gte(VillagePond.STOCKING_FISH, 2, "one fish cannot reproduce")
