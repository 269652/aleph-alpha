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
