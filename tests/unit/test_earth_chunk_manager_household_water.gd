extends GutTest

## A house's water as a real thing in the world (docs/concept/
## village_water.md): a level on the building record, drunk by whoever
## lives there, refilled a bucket at a time, and surviving a chunk round
## trip because it is a fact about the house.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const HouseholdWater = preload("res://src/emergence/household_water.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

const HOUSE := "house_small"

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var _placed: Array = []


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))


func after_each():
	for site in _placed:
		chunk_manager.remove_building(site["chunk_coord"], site["origin"])
	_placed.clear()
	chunk_manager.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Berlin's chunk -- the origin neighbourhood is open ocean.
func _a_dry_site_for(building_id: String) -> Dictionary:
	var footprint := BuildingCatalog.footprint_of(building_id)
	var geo := GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	var size := EarthChunkManager.CHUNK_SIZE
	var chunk_coord := Vector2i(floori(float(berlin.x) / size), floori(float(berlin.y) / size))
	chunk_manager._load_chunk(chunk_coord)
	for y in range(2, size - footprint.y - 2):
		for x in range(2, size - footprint.x - 2):
			var origin := Vector2i(x, y)
			var global_origin: Vector2i = chunk_coord * size + origin
			var cells: Array = BuildingCatalog.footprint_cells(building_id, global_origin)
			cells.append(global_origin + BuildingCatalog.doorstep_of(building_id))
			var clear := true
			for cell in cells:
				if (
					chunk_manager.is_water_at_global(cell.x, cell.y)
					or chunk_manager.modification_at_global(cell.x, cell.y) != ""
				):
					clear = false
					break
			if clear:
				return {"chunk_coord": chunk_coord, "origin": origin}
	return {}


func _a_house(seed_value: int, resident_seed: int = 4242) -> Dictionary:
	var site := _a_dry_site_for(HOUSE)
	assert_false(site.is_empty(), "precondition: somewhere dry to raise a house")
	if site.is_empty():
		return {}
	assert_true(chunk_manager.place_building(
		site["chunk_coord"], site["origin"], HOUSE, Vector2i(0, 1), seed_value, "", "farmer", resident_seed
	), "precondition: the house stands")
	_placed.append(site)
	return chunk_manager.building_record_at(site["chunk_coord"], site["origin"])


func _reread(record: Dictionary) -> Dictionary:
	return chunk_manager.building_record_at(record["chunk_coord"], record["origin_local"])


# -- a house has water in it ------------------------------------------------

func test_a_new_house_already_has_water_in_its_tank():
	var record := _a_house(11)
	assert_gt(chunk_manager.house_water_at(record), 0.0)


func test_a_new_house_is_not_already_due_a_trip():
	# A village founded this morning must not send every household to the
	# well before noon.
	for seed_value in [3, 17, 91, 404]:
		var record := _a_house(seed_value)
		assert_false(chunk_manager.water_trip_due_at(record), "seed %d" % seed_value)


func test_two_houses_start_with_different_amounts():
	var levels := {}
	for seed_value in [5, 23, 61, 77, 128]:
		levels[chunk_manager.house_water_at(_a_house(seed_value))] = true
	assert_gt(levels.size(), 1, "every house started with the same water, so they will run dry together")


func test_a_house_that_is_not_a_home_holds_no_tank():
	var site := _a_dry_site_for("city_hall")
	assert_false(site.is_empty(), "precondition")
	assert_true(chunk_manager.place_building(site["chunk_coord"], site["origin"], "city_hall", Vector2i(0, 1), 9))
	_placed.append(site)
	var hall: Dictionary = chunk_manager.building_record_at(site["chunk_coord"], site["origin"])
	assert_eq(chunk_manager.house_water_at(hall), 0.0)


# -- the household drinks ---------------------------------------------------

func test_living_in_a_house_drinks_its_water():
	var record := _a_house(11)
	var before := chunk_manager.house_water_at(record)
	chunk_manager.drink_household_water_in(record["chunk_coord"], 1.0)
	assert_lt(chunk_manager.house_water_at(_reread(record)), before)


func test_an_empty_house_drinks_nothing():
	var record := _a_house(11, 0)
	var before := chunk_manager.house_water_at(record)
	chunk_manager.drink_household_water_in(record["chunk_coord"], 5.0)
	assert_almost_eq(chunk_manager.house_water_at(_reread(record)), before, 0.0001)


func test_drinking_long_enough_makes_a_trip_due():
	var record := _a_house(11)
	chunk_manager.drink_household_water_in(record["chunk_coord"], 100.0)
	assert_true(chunk_manager.water_trip_due_at(_reread(record)))


func test_a_tank_never_drinks_itself_below_empty():
	var record := _a_house(11)
	chunk_manager.drink_household_water_in(record["chunk_coord"], 10000.0)
	assert_eq(chunk_manager.house_water_at(_reread(record)), 0.0)


func test_drinking_in_one_chunk_does_not_drain_a_house_in_another():
	# The settlement step runs once per settlement, so a global drink would
	# empty every house once per village in range.
	var record := _a_house(11)
	var before := chunk_manager.house_water_at(record)
	chunk_manager.drink_household_water_in(Vector2i(record["chunk_coord"]) + Vector2i(1, 0), 50.0)
	assert_almost_eq(chunk_manager.house_water_at(_reread(record)), before, 0.0001)


# -- the bucket comes home --------------------------------------------------

func test_pouring_a_bucket_in_raises_the_tank():
	var record := _a_house(11)
	chunk_manager.drink_household_water_in(record["chunk_coord"], 100.0)
	var dry := chunk_manager.house_water_at(_reread(record))
	chunk_manager.pour_bucket_into_house(record["chunk_coord"], record["origin_local"])
	assert_almost_eq(
		chunk_manager.house_water_at(_reread(record)),
		HouseholdWater.poured_into(dry, HouseholdWater.BUCKET_LITRES), 0.0001
	)


func test_pouring_into_a_full_tank_spills_rather_than_overfilling():
	var record := _a_house(11)
	for i in 20:
		chunk_manager.pour_bucket_into_house(record["chunk_coord"], record["origin_local"])
	assert_almost_eq(chunk_manager.house_water_at(_reread(record)), HouseholdWater.TANK_LITRES, 0.0001)


func test_pouring_into_nothing_is_a_no_op_rather_than_a_crash():
	assert_false(chunk_manager.pour_bucket_into_house(Vector2i(0, 0), Vector2i(3, 3)))


# -- it is a fact about the house -------------------------------------------

func test_a_houses_water_survives_a_chunk_round_trip():
	var record := _a_house(11)
	chunk_manager.drink_household_water_in(record["chunk_coord"], 3.0)
	var level := chunk_manager.house_water_at(_reread(record))
	var chunk_coord: Vector2i = record["chunk_coord"]
	var origin: Vector2i = record["origin_local"]

	chunk_manager.update(chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(4000, 4000))
	chunk_manager._load_chunk(chunk_coord)

	var reloaded: Dictionary = chunk_manager.building_record_at(chunk_coord, origin)
	assert_false(reloaded.is_empty(), "the house did not come back")
	assert_almost_eq(chunk_manager.house_water_at(reloaded), level, 0.0001)


# -- the farmhouse holds a tank for its field -------------------------------

## A farmhouse is nobody's home (capacity 0) and so drinks nothing, but its
## FIELD drinks -- docs/concept/village_water.md mechanism 3. That makes it
## the one building that holds a tank without anyone living in it.

const FARMHOUSE := "farmhouse"
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")


func _a_farmhouse(seed_value: int) -> Dictionary:
	var site := _a_dry_site_for(FARMHOUSE)
	assert_false(site.is_empty(), "precondition: somewhere dry to raise a farmhouse")
	if site.is_empty():
		return {}
	assert_true(chunk_manager.place_building(
		site["chunk_coord"], site["origin"], FARMHOUSE, Vector2i(0, 1), seed_value
	), "precondition: the farmhouse stands")
	_placed.append(site)
	return chunk_manager.building_record_at(site["chunk_coord"], site["origin"])


func _global_anchor_of(record: Dictionary) -> Vector2i:
	return (
		Vector2i(record["chunk_coord"]) * EarthChunkManager.CHUNK_SIZE
		+ Vector2i(record["origin_local"])
	)


func test_a_farmhouse_holds_water_even_though_nobody_lives_there():
	assert_gt(chunk_manager.house_water_at(_a_farmhouse(31)), 0.0)


func test_a_farmhouse_drinks_nothing_itself():
	var farm := _a_farmhouse(31)
	var before := chunk_manager.house_water_at(farm)
	chunk_manager.drink_household_water_in(farm["chunk_coord"], 50.0)
	assert_almost_eq(chunk_manager.house_water_at(_reread(farm)), before, 0.0001)


func test_a_bucket_can_be_poured_into_a_farmhouse():
	var farm := _a_farmhouse(31)
	var anchor := _global_anchor_of(farm)
	while chunk_manager.draw_crop_water_at_global(anchor.x, anchor.y):
		pass
	var dry := chunk_manager.house_water_at(_reread(farm))
	assert_true(chunk_manager.pour_bucket_into_house(farm["chunk_coord"], farm["origin_local"]))
	assert_gt(chunk_manager.house_water_at(_reread(farm)), dry)


# -- watering the beds is paid for ------------------------------------------

func test_watering_the_beds_takes_water_out_of_the_farmhouse():
	var farm := _a_farmhouse(31)
	var anchor := _global_anchor_of(farm)
	var before := chunk_manager.house_water_at(farm)
	assert_true(chunk_manager.draw_crop_water_at_global(anchor.x, anchor.y))
	assert_almost_eq(
		chunk_manager.house_water_at(_reread(farm)),
		HouseholdWater.level_after_tending(before), 0.0001
	)


## ANY footprint cell answers, the same rule building_at_global already
## keeps -- a farmer standing at the far corner of their own farmhouse is
## still at their own farmhouse.
func test_any_corner_of_the_farmhouse_pays_for_the_field():
	var farm := _a_farmhouse(31)
	var footprint := BuildingCatalog.footprint_of(FARMHOUSE)
	var far_corner := _global_anchor_of(farm) + footprint - Vector2i(1, 1)
	assert_true(chunk_manager.draw_crop_water_at_global(far_corner.x, far_corner.y))


func test_a_farmhouse_down_to_its_reserve_refuses_to_water():
	var farm := _a_farmhouse(31)
	var anchor := _global_anchor_of(farm)
	var drawn := 0
	while chunk_manager.draw_crop_water_at_global(anchor.x, anchor.y) and drawn < 10000:
		drawn += 1
	assert_gt(drawn, 0, "a full farmhouse could not water its beds even once")
	assert_lt(drawn, 10000, "the field drank the tank forever")
	assert_gte(
		chunk_manager.house_water_at(_reread(farm)),
		HouseholdWater.DRINKING_RESERVE_LITRES,
		"the field drank the household's own reserve"
	)


func test_a_cottage_never_pays_for_crop_water():
	var house := _a_house(11)
	var anchor := _global_anchor_of(house)
	var before := chunk_manager.house_water_at(house)
	assert_false(chunk_manager.draw_crop_water_at_global(anchor.x, anchor.y))
	assert_almost_eq(chunk_manager.house_water_at(_reread(house)), before, 0.0001)


func test_drawing_crop_water_off_bare_ground_is_a_no_op_rather_than_a_crash():
	assert_false(chunk_manager.draw_crop_water_at_global(3, 3))


# -- so the farmer is sent to the well for it -------------------------------

func test_a_new_farmhouse_is_not_already_due_a_trip():
	for seed_value in [3, 17, 91, 404]:
		assert_false(chunk_manager.water_trip_due_at(_a_farmhouse(seed_value)), "seed %d" % seed_value)


func test_watering_the_field_long_enough_makes_a_trip_due():
	var farm := _a_farmhouse(31)
	var anchor := _global_anchor_of(farm)
	for i in 10000:
		if not chunk_manager.draw_crop_water_at_global(anchor.x, anchor.y):
			break
	assert_true(chunk_manager.water_trip_due_at(_reread(farm)))


## The premise HouseholdWater.LITRES_PER_TENDING is grounded in: a bed
## withers if it is not re-watered inside its own grace, and that grace is
## shorter than a simulated day -- so a field that STAYS ALIVE is tended
## more than once a day, and a tending costing more than a day's drinking
## really does make the farmhouse the thirstier building.
func test_a_living_field_is_tended_more_than_once_a_simulated_day():
	assert_lt(FarmPlot.MIN_WATER_GRACE_SECONDS, EarthChunkManager.SECONDS_PER_SIMULATED_DAY)


# -- the bucket lives in the house ------------------------------------------
#
# Asked for directly: *"each NPC should have a bucket in its house
# inventory"*. The bucket belongs to the HOUSEHOLD rather than to the
# villager -- it is what the water is carried in, and it is by the door
# whether or not anybody is out with it right now. Every building that
# holds a tank keeps exactly one, which is why this is stepped rather than
# seeded at placement: a house raised before any of this existed gets one
# the first time its village is stepped, with no migration and no new
# field on the record.


func _buckets_at(record: Dictionary) -> int:
	var anchor := _global_anchor_of(record)
	return chunk_manager.building_stock_at(anchor.x, anchor.y, HouseholdWater.BUCKET_ITEM_ID)


func test_a_house_keeps_a_bucket_by_its_door():
	var record := _a_house(11)
	chunk_manager.stock_household_buckets_in(record["chunk_coord"])
	assert_eq(_buckets_at(record), 1)


func test_a_farmhouse_keeps_a_bucket_too():
	var farm := _a_farmhouse(31)
	chunk_manager.stock_household_buckets_in(farm["chunk_coord"])
	assert_eq(_buckets_at(farm), 1)


func test_a_household_never_accumulates_buckets():
	var record := _a_house(11)
	for i in 6:
		chunk_manager.stock_household_buckets_in(record["chunk_coord"])
	assert_eq(_buckets_at(record), 1, "the village step put a new pail by the door every time it ran")


func test_a_building_with_no_tank_keeps_no_bucket():
	var site := _a_dry_site_for("city_hall")
	assert_false(site.is_empty(), "precondition")
	assert_true(chunk_manager.place_building(site["chunk_coord"], site["origin"], "city_hall", Vector2i(0, 1), 9))
	_placed.append(site)
	var hall: Dictionary = chunk_manager.building_record_at(site["chunk_coord"], site["origin"])
	chunk_manager.stock_household_buckets_in(site["chunk_coord"])
	assert_eq(_buckets_at(hall), 0)


func test_stocking_buckets_in_an_unloaded_chunk_is_a_no_op_rather_than_a_crash():
	chunk_manager.stock_household_buckets_in(Vector2i(9999, 9999))
	assert_true(true, "it did not crash")
