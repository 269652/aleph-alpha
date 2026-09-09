extends GutTest

## EarthChunkManager.nearest_water_distance_tiles -- the raw geometric fact
## behind the ambient river-proximity layer (see docs/concept/soundscape.md's
## "Proximity layers" gap, and docs/concept/creature_and_footstep_audio.md
## for the sibling "individual nearby animals" half of the same live
## request: "fully build the soundscape out of individual nearby animals
## and environment"). The actual ring-scan geometry is pure and tested
## against synthetic coordinates in test_water_proximity.gd -- this only
## proves the WIRING (right predicates, right radius constant), not exact
## results against unpredictable real generated terrain, the same
## reasoning test_earth_chunk_manager_footprints.gd's own record_footstep
## tests already document.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const WaterProximity = preload("res://src/world/water_proximity.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Cross-checks against the exact same two real predicates this delegates
## to, called directly through the pure WaterProximity module -- proves
## the wiring (the right predicates combined with `or`, the right radius
## constant) rather than hard-coding an expectation about whether the
## Berlin test tile specifically happens to be near water.
func test_nearest_water_distance_tiles_matches_a_manual_scan_with_the_same_predicates():
	var result := manager.nearest_water_distance_tiles(_berlin_tile.x, _berlin_tile.y)
	var expected := WaterProximity.nearest_distance_tiles(
		_berlin_tile.x, _berlin_tile.y, EarthChunkManager.WATER_PROXIMITY_SCAN_RADIUS_TILES,
		func(x: int, y: int) -> bool:
			return manager.is_river_at_global(x, y) or manager.is_lake_at_global(x, y)
	)
	assert_eq(result, expected)


func test_returns_zero_when_standing_directly_on_a_river_or_lake_tile():
	# Doesn't depend on the real terrain at any specific coordinate --
	# scans a modest area for a tile the manager's own real predicates
	# already agree is water, skips gracefully if none turns up nearby.
	for dx in range(-40, 41, 4):
		for dy in range(-40, 41, 4):
			var x := _berlin_tile.x + dx
			var y := _berlin_tile.y + dy
			if manager.is_river_at_global(x, y) or manager.is_lake_at_global(x, y):
				assert_eq(manager.nearest_water_distance_tiles(x, y), 0.0)
				return
	pending("no river/lake tile found near Berlin within this scan -- geometry covered directly by test_water_proximity.gd regardless")
