extends GutTest

## Curated real-world rivers -- see docs/concept/rivers.md. Waypoints are
## stored as Vector2(latitude_deg, longitude_deg) -- NOT engine (x, y); x
## holds latitude here, matching how every real-world coordinate in this
## project is written (e.g. "48.007669, 7.805657" reads left-to-right as
## lat, lon).

const RiverCatalog = preload("res://src/world/river_catalog.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

var catalog: RiverCatalog
var geo: GeoCoordinates


func before_each():
	catalog = RiverCatalog.new()
	geo = GeoCoordinates.new()


func _tile_for(lat: float, lon: float) -> Vector2i:
	return geo.tile_for_coordinate(
		lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)


## The Gaskugel is one of the Dreisam's own curated waypoints (it's this
## game's spawn point specifically because it sits on the river) -- distance
## there must be (almost) exactly zero.
func test_distance_is_almost_zero_exactly_on_a_curated_waypoint():
	var tile := _tile_for(48.007669, 7.805657)
	var distance := catalog.distance_to_nearest_river_tiles(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_lt(distance, 1.0)


## A point known to be far from every curated river (mid-Pacific, nowhere
## near any real river on the roster) must read as clearly far away.
func test_distance_is_large_far_from_any_curated_river():
	var tile := _tile_for(0.0, -160.0)
	var distance := catalog.distance_to_nearest_river_tiles(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_gt(distance, 100.0)


## Distance must come from real point-to-SEGMENT projection, not just
## nearest-waypoint: a point abeam the middle of a long segment (between two
## widely-spaced waypoints) should be much closer than the distance to
## either endpoint alone, if segment projection is actually happening.
func test_distance_uses_point_to_segment_projection_not_just_nearest_waypoint():
	# Midpoint between the Dreisam's Freiburg-center and Gaskugel waypoints,
	# nudged slightly off the line -- closer to the segment than to either end.
	var near_segment := _tile_for(48.0031, 7.8238)
	var to_segment := catalog.distance_to_nearest_river_tiles(
		near_segment.x, near_segment.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var freiburg_center := _tile_for(47.9990, 7.8421)
	var to_nearest_waypoint_only := Vector2(near_segment).distance_to(Vector2(freiburg_center))
	assert_lt(to_segment, to_nearest_waypoint_only)


## The width floor from docs/concept/rivers.md: a curated river must read as
## at least 4 tiles wide in-game, so the half-width the distance query is
## compared against must be at least 2 tiles.
func test_half_width_gives_at_least_four_tiles_of_total_width():
	assert_gte(RiverCatalog.RIVER_HALF_WIDTH_TILES * 2.0, 4.0)


func test_is_river_tile_true_within_half_width_of_a_waypoint():
	var tile := _tile_for(48.007669, 7.805657)
	assert_true(catalog.is_river_tile(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	))


func test_is_river_tile_false_far_from_any_curated_river():
	var tile := _tile_for(0.0, -160.0)
	assert_false(catalog.is_river_tile(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	))


## Every river the Roster in docs/concept/rivers.md names for phase 1 must
## actually be present in the data table -- prevents "documented but never
## actually added" drift.
func test_phase_one_roster_is_present():
	var expected_rivers := [
		"Rhine", "Danube", "Elbe", "Weser", "Main",
		"Mosel", "Neckar", "Oder", "Spree", "Isar", "Dreisam"
	]
	for river_name in expected_rivers:
		assert_true(RiverCatalog.RIVERS.has(river_name), "missing river: %s" % river_name)


## Every waypoint must be a plausible real (lat, lon) -- catches an
## accidental lat/lon swap or a stray placeholder value at data-entry time.
func test_every_waypoint_is_a_plausible_real_coordinate():
	for river_name in RiverCatalog.RIVERS:
		var waypoints: Array = RiverCatalog.RIVERS[river_name]
		assert_gt(waypoints.size(), 1, "%s needs at least 2 waypoints to form a segment" % river_name)
		for waypoint in waypoints:
			assert_between(waypoint.x, -90.0, 90.0, "%s latitude out of range" % river_name)
			assert_between(waypoint.y, -180.0, 180.0, "%s longitude out of range" % river_name)
