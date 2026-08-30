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


func test_every_river_has_a_smoothed_polyline_grown_from_its_waypoints():
	var polylines := RiverCatalog.tile_polylines(
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	for river_name in RiverCatalog.RIVERS:
		assert_true(polylines.has(river_name), "missing polyline for %s" % river_name)
		# Chaikin corner-cutting roughly quadruples the point count over
		# two passes -- MORE points than waypoints is the smoothing
		# actually having run; the exact count is its own business.
		assert_gt(
			polylines[river_name].size(), RiverCatalog.RIVERS[river_name].size(),
			"%s polyline was not corner-smoothed" % river_name
		)


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


# -- the downstream tangent --------------------------------------------------
#
# The flow overlay used to take its direction from the terrain ASPECT -- the
# steepest-descent direction of the elevation field. That sounds physical
# and is visibly wrong here: elevation is bilinear-interpolated from a
# coarse DEM, so its local gradient has little to do with the mapped course,
# and the flow lines came out running diagonally ACROSS a channel that runs
# straight down the screen.
#
# The course polyline is stored source-to-mouth, so its own tangent IS the
# downstream direction. No proxy needed.

## Bearing convention, shared with ProceduralRiverFlowSprite: 0 is north,
## 90 is east, +Y is DOWN because this is screen space and not a map. Getting
## this wrong flips every river's flow.
func test_bearing_degrees_uses_the_screen_space_compass():
	assert_almost_eq(RiverCatalog.bearing_degrees(Vector2(0, -1)), 0.0, 0.001)
	assert_almost_eq(RiverCatalog.bearing_degrees(Vector2(1, 0)), 90.0, 0.001)
	assert_almost_eq(RiverCatalog.bearing_degrees(Vector2(0, 1)), 180.0, 0.001)
	assert_almost_eq(RiverCatalog.bearing_degrees(Vector2(-1, 0)), 270.0, 0.001)


## THE property that matters, and it is checked against the course itself
## rather than any hard-coded heading: stepping along the reported bearing
## from a river tile must carry you FURTHER DOWN the course, and stepping
## back against it must carry you up.
func test_the_reported_bearing_actually_points_downstream():
	var catalog := RiverCatalog.new()
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	var checked := 0
	# Walk real course points, straight out of the catalog itself.
	var courses := RiverCatalog.tile_polylines(width, height)
	var points: Array = courses["Rhine"]
	for index in range(2, points.size() - 2):
		var probe: Vector2 = points[index]
		var here := catalog.nearest_river_at(int(probe.x), int(probe.y), width, height)
		if here.name == "" or here.distance_tiles > 2.0:
			continue
		# course_fraction is degenerate at the very ends of a polyline.
		if here.course_fraction < 0.02 or here.course_fraction > 0.98:
			continue
		var radians := deg_to_rad(here.course_bearing_deg)
		var forward := Vector2(sin(radians), -cos(radians)) * 3.0
		var ahead := catalog.nearest_river_at(
			int(probe.x + forward.x), int(probe.y + forward.y), width, height
		)
		var behind := catalog.nearest_river_at(
			int(probe.x - forward.x), int(probe.y - forward.y), width, height
		)
		if ahead.name != here.name or behind.name != here.name:
			continue
		assert_gt(
			ahead.course_fraction, behind.course_fraction,
			"bearing %.1f at %s does not run downstream"
				% [here.course_bearing_deg, probe]
		)
		checked += 1
	assert_gt(checked, 0, "found no river tiles to check the bearing on")


## A tile off in the ocean has no course to follow -- it must still report a
## usable bearing rather than something the atlas lookup would choke on.
func test_a_bearing_is_always_in_range_even_with_no_river():
	var catalog := RiverCatalog.new()
	var result := catalog.nearest_river_at(
		10, 10, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_between(result.course_bearing_deg, 0.0, 360.0)


# -- the signed across-offset ------------------------------------------------
#
# What the smooth-shoreline rendering runs on: not just HOW FAR a tile sits
# from the centreline but WHICH SIDE, as one signed perpendicular component.
# The flow shader reconstructs every fragment's own offset as
# (tile centre's signed offset) + (within-tile delta projected on the flow
# perpendicular), so the sign convention here and the shader's perp must be
# the same rotation -- pinned by the reconstruction identity test below.

## The two banks of one reach must carry opposite signs.
func test_opposite_banks_have_opposite_signs():
	var catalog := RiverCatalog.new()
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	var courses := RiverCatalog.tile_polylines(width, height)
	var points: Array = courses["Rhine"]
	var checked := 0
	for index in range(2, points.size() - 2):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		if a.distance_to(b) < 3.0:
			continue
		var mid := (a + b) * 0.5
		var tangent := (b - a).normalized()
		var perp := Vector2(-tangent.y, tangent.x)
		var left := catalog.nearest_river_at(
			int(mid.x + perp.x * 1.5), int(mid.y + perp.y * 1.5), width, height
		)
		var right := catalog.nearest_river_at(
			int(mid.x - perp.x * 1.5), int(mid.y - perp.y * 1.5), width, height
		)
		if left.name != "Rhine" or right.name != "Rhine":
			continue
		if absf(left.signed_across_tiles) < 0.5 or absf(right.signed_across_tiles) < 0.5:
			continue
		assert_lt(
			left.signed_across_tiles * right.signed_across_tiles, 0.0,
			"both banks at %s carry the same sign" % mid
		)
		checked += 1
	assert_gt(checked, 3, "found too few probe pairs to trust the sweep")


## THE identity the shader's per-fragment reconstruction depends on: the
## signed offset must BE the projection of (point - centreline) onto the
## rotated-90 tangent of the reported bearing. If the two rotations ever
## disagree, every reconstructed bank flips sides.
func test_signed_across_matches_the_bearing_perpendicular():
	var catalog := RiverCatalog.new()
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	var courses := RiverCatalog.tile_polylines(width, height)
	var checked := 0
	for river_name in courses:
		var points: Array = courses[river_name]
		for index in range(1, points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			if a.distance_to(b) < 6.0:
				continue
			var mid := (a + b) * 0.5
			var tangent := (b - a).normalized()
			var perp := Vector2(-tangent.y, tangent.x)
			var probe := mid + perp * 1.7
			# nearest_river_at takes integer tiles, so the ACTUAL queried
			# point is the truncated one -- the expectation must be built
			# from that same point or truncation alone eats a tile of slack.
			var queried := Vector2(float(int(probe.x)), float(int(probe.y)))
			var hit := catalog.nearest_river_at(int(probe.x), int(probe.y), width, height)
			if hit.name != river_name:
				continue
			var radians := deg_to_rad(hit.course_bearing_deg)
			var bearing_dir := Vector2(sin(radians), -cos(radians))
			var bearing_perp := Vector2(-bearing_dir.y, bearing_dir.x)
			var agreement := bearing_perp.dot(perp)
			if absf(agreement) < 0.99:
				continue  # bearing snapped to a neighbouring segment at a joint
			# This segment's own exact perpendicular component of the
			# queried point -- the identity says the catalog must report
			# exactly this (sign included).
			var expected := tangent.cross(queried - a)
			assert_almost_eq(
				hit.signed_across_tiles, expected, 0.35,
				"reconstruction identity broken at %s near %s" % [queried, river_name]
			)
			checked += 1
	assert_gt(checked, 3, "found too few probes to trust the identity sweep")


## Far from every river the answer must still be well-formed (the painter
## calls this for every cell of every chunk). NOTE: far beyond a course's
## endpoints the closest point clamps and the perpendicular COMPONENT is
## legitimately much smaller than the euclidean distance -- which is exactly
## why the painter must gate painting on distance_tiles, never on
## |signed_across_tiles|.
func test_signed_across_is_finite_everywhere():
	var catalog := RiverCatalog.new()
	var result := catalog.nearest_river_at(
		10, 10, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_true(is_finite(result.signed_across_tiles))


## Beside a reach (an interior projection), the two must agree -- there the
## residual IS the perpendicular.
func test_beside_a_reach_signed_magnitude_equals_the_distance():
	var catalog := RiverCatalog.new()
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	var courses := RiverCatalog.tile_polylines(width, height)
	var checked := 0
	for river_name in courses:
		var points: Array = courses[river_name]
		for index in range(1, points.size() - 1):
			var a: Vector2 = points[index]
			var b: Vector2 = points[index + 1]
			if a.distance_to(b) < 6.0:
				continue
			var mid := (a + b) * 0.5
			var tangent := (b - a).normalized()
			var perp := Vector2(-tangent.y, tangent.x)
			var probe := mid + perp * 1.4
			var hit := catalog.nearest_river_at(int(probe.x), int(probe.y), width, height)
			if hit.name != river_name:
				continue
			assert_almost_eq(
				absf(hit.signed_across_tiles), hit.distance_tiles, 0.05,
				"beside a reach at %s the perp component IS the distance" % probe
			)
			checked += 1
	assert_gt(checked, 3, "too few interior probes")


# -- corner-smoothed courses --------------------------------------------------
#
# Reported: "there are still hard cuts / misalignments and the curve could
# be smoother". The curated waypoints are city-to-city straight lines, so
# every vertex was a sharp corner: the bank (an offset of the course)
# inherited each kink, adjacent tiles near a vertex snapped to different
# segments with visibly different tangents, and the outside of every bend
# was a patch of endpoint-clamped cells. Chaikin corner-cutting fixes the
# whole family at the source.

## No bend anywhere in the smoothed roster may turn sharply between
## consecutive segments -- each Chaikin pass quarters the turn angle, so
## two passes bring even a hairpin under this bound.
func test_no_course_turns_sharply_between_consecutive_segments():
	var courses := RiverCatalog.tile_polylines(
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var worst := 0.0
	for river_name in courses:
		var points: Array = courses[river_name]
		for index in range(points.size() - 2):
			var ab: Vector2 = points[index + 1] - points[index]
			var bc: Vector2 = points[index + 2] - points[index + 1]
			if ab.length() < 0.5 or bc.length() < 0.5:
				continue
			worst = maxf(worst, absf(rad_to_deg(ab.angle_to(bc))))
	assert_lt(
		worst, 45.0,
		"a course still turns %.1f degrees at one vertex -- the bank kinks there" % worst
	)


## Smoothing must not meaningfully shorten a course -- corner cutting trims
## only the sharp tips, and the discharge interpolation runs on fractions of
## this length.
func test_smoothing_preserves_course_length():
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	var smoothed := RiverCatalog.tile_polylines(width, height)
	var raw := RiverCatalog.raw_tile_polylines(width, height)
	for river_name in smoothed:
		var smoothed_length := _polyline_length(smoothed[river_name])
		var raw_length := _polyline_length(raw[river_name])
		# Chaikin genuinely shortens at corners -- the Rhine gives up ~4%
		# rounding its knee -- and the curated straight lines were already
		# an UNDERestimate of the real winding course, so a small further
		# shortening is honest geometry, not damage. 6% is the measured
		# worst case with headroom; a collapsing-smoother bug would blow
		# far past it.
		assert_almost_eq(
			smoothed_length, raw_length, raw_length * 0.06,
			"%s changed length by more than 6%% in smoothing" % river_name
		)


## And both endpoints stay exactly where the source data puts them -- a
## river must still rise at its real source and end at its real mouth.
func test_smoothing_pins_both_endpoints():
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	var smoothed := RiverCatalog.tile_polylines(width, height)
	var raw := RiverCatalog.raw_tile_polylines(width, height)
	for river_name in smoothed:
		var s_points: Array = smoothed[river_name]
		var r_points: Array = raw[river_name]
		assert_eq(s_points[0], r_points[0], "%s source moved" % river_name)
		assert_eq(s_points[-1], r_points[-1], "%s mouth moved" % river_name)


func _polyline_length(points: Array) -> float:
	var total := 0.0
	for index in range(points.size() - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		total += a.distance_to(b)
	return total


# -- round end caps -----------------------------------------------------------
#
# Past a course's very tip the perpendicular component degenerates (it
# shrinks while the real distance does not), which painted the region
# around every source and mouth as mid-channel water in a ragged patch --
# most visibly at confluences, where a tributary's mouth tip sits in the
# middle of the junction. Radial distance at the tips caps each end in a
# clean semicircle instead.

func test_past_a_river_tip_the_across_offset_is_radial():
	var catalog := RiverCatalog.new()
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	var courses := RiverCatalog.tile_polylines(width, height)
	var checked := 0
	for river_name in courses:
		var points: Array = courses[river_name]
		var tip: Vector2 = points[-1]
		var prev: Vector2 = points[-2]
		if tip.is_equal_approx(prev):
			continue
		var out_dir: Vector2 = (tip - prev).normalized()
		# A probe clearly PAST the mouth tip, a little off-axis.
		var perp := Vector2(-out_dir.y, out_dir.x)
		var probe := tip + out_dir * 2.0 + perp * 0.8
		var hit := catalog.nearest_river_at(int(probe.x), int(probe.y), width, height)
		if hit.name != river_name:
			continue  # another river is closer to this mouth (a confluence)
		assert_almost_eq(
			absf(hit.signed_across_tiles), hit.distance_tiles, 0.02,
			"past the %s tip the across must be the radial distance" % river_name
		)
		checked += 1
	assert_gt(checked, 2, "too few free-standing river tips to trust the sweep")
