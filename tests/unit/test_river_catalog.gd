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


# -- cached tile-space polylines --------------------------------------------
#
# distance_to_nearest_river_tiles used to re-convert EVERY waypoint of EVERY
# river through GeoCoordinates.tile_for_coordinate on EVERY call -- ~50
# conversions plus ~44 segment tests, per call. It is called per-tile from
# five separate hot paths (generate_chunk, _paint_water_overlay,
# _paint_river_flow_overlay, _paint_snow_tile, _can_root_at), so a single
# 32x32 chunk load paid it thousands of times over. The conversion depends
# only on (world_width, world_height), so it belongs to the process, not the
# call -- same `static var _..._cache` shape EarthElevationSource._decoded_cache
# already uses for exactly this reason.

func test_tile_polylines_are_cached_per_world_size():
	var first := RiverCatalog.tile_polylines(1000, 500)
	var second := RiverCatalog.tile_polylines(1000, 500)
	assert_true(first == second, "the same world size must reuse one decoded polyline set")


func test_a_different_world_size_gets_its_own_polylines():
	var small := RiverCatalog.tile_polylines(1000, 500)
	var large := RiverCatalog.tile_polylines(2000, 1000)
	assert_ne(small["Dreisam"], large["Dreisam"])


func test_every_river_has_a_tile_polyline_of_the_same_length_as_its_waypoints():
	var polylines := RiverCatalog.tile_polylines(
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	for river_name in RiverCatalog.RIVERS:
		assert_true(polylines.has(river_name), "missing polyline for %s" % river_name)
		assert_eq(polylines[river_name].size(), RiverCatalog.RIVERS[river_name].size())


## The cache must not change any answer -- the whole point is that it's a
## pure speed change.
func test_caching_does_not_change_the_distance_answer():
	var tile := _tile_for(48.007669, 7.805657)
	assert_almost_eq(
		catalog.distance_to_nearest_river_tiles(
			tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		),
		0.0, 1.0
	)


# -- nearest_river_at: which river, and how far along it ---------------------
#
# Real river discharge grows from source to mouth as drainage area
# accumulates, so a hydraulic model needs BOTH which river a cell belongs to
# and how far down its course the cell sits. Both fall straight out of the
# same point-to-segment sweep distance_to_nearest_river_tiles already does,
# so they're answered together rather than by a second traversal.

func test_nearest_river_at_identifies_the_dreisam_at_the_gaskugel():
	var tile := _tile_for(48.007669, 7.805657)
	var found := catalog.nearest_river_at(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_eq(found.name, "Dreisam")


func test_nearest_river_at_identifies_the_spree_at_berlin():
	var tile := _tile_for(52.52, 13.405)
	var found := catalog.nearest_river_at(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_eq(found.name, "Spree")


func test_nearest_river_at_reports_the_same_distance_as_the_distance_query():
	var tile := _tile_for(48.0031, 7.8238)
	var found := catalog.nearest_river_at(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_almost_eq(
		found.distance_tiles,
		catalog.distance_to_nearest_river_tiles(
			tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		),
		0.0001
	)


## 0.0 at the source waypoint, 1.0 at the mouth -- the fraction real
## discharge interpolation needs.
func test_course_fraction_is_zero_at_the_source_and_one_at_the_mouth():
	var source_tile := _tile_for(47.974167, 7.960556)  # Dreisam source, Kirchzarten
	var mouth_tile := _tile_for(48.1475, 7.755)        # Dreisam mouth, confluence with the Elz
	var at_source := catalog.nearest_river_at(
		source_tile.x, source_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var at_mouth := catalog.nearest_river_at(
		mouth_tile.x, mouth_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_almost_eq(at_source.course_fraction, 0.0, 0.02)
	assert_almost_eq(at_mouth.course_fraction, 1.0, 0.02)


func test_course_fraction_increases_downstream_along_the_dreisam():
	var waypoints: Array = RiverCatalog.RIVERS["Dreisam"]
	var previous := -1.0
	for waypoint in waypoints:
		var tile := _tile_for(waypoint.x, waypoint.y)
		var found := catalog.nearest_river_at(
			tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		)
		assert_gt(found.course_fraction, previous, "course fraction must grow toward the mouth")
		previous = found.course_fraction


func test_course_fraction_always_stays_in_unit_range():
	for lat_lon in [[48.007669, 7.805657], [52.52, 13.405], [50.93639, 6.95278], [0.0, -160.0]]:
		var tile := _tile_for(lat_lon[0], lat_lon[1])
		var found := catalog.nearest_river_at(
			tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		)
		assert_between(found.course_fraction, 0.0, 1.0)


## Far from every curated river there is still a NEAREST one -- the caller
## decides whether the distance disqualifies it, exactly as
## distance_to_nearest_river_tiles already leaves that to is_river_tile.
func test_nearest_river_at_still_answers_far_from_any_river():
	var tile := _tile_for(0.0, -160.0)
	var found := catalog.nearest_river_at(
		tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_ne(found.name, "")
	assert_gt(found.distance_tiles, 100.0)


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
