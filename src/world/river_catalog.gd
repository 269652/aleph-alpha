extends RefCounted

## Curated real-world rivers -- see docs/concept/rivers.md. A small, growing
## table of actual named rivers, each a simplified real polyline (source -> a
## handful of real via-points -> mouth), not a survey-grade centerline. This
## is deliberately separate from BiomeClassifier: a river never changes what
## land biome a cell is (see rivers.md's "Rendering" section) -- this class
## only answers "how far is this tile from a real curated river's course."

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

## Minimum total in-game width a curated river renders at, in tiles (see
## rivers.md's "Width" section: real width would be sub-tile and invisible
## at this world's ~1km/tile scale, so the game deliberately widens it).
## Half-width is what the tile-space distance query compares against, so it
## must be at least half of the 4-tile total-width floor -- pinned by
## test_half_width_gives_at_least_four_tiles_of_total_width.
const RIVER_HALF_WIDTH_TILES := 2.0

## How far past the bank line the flow overlay still paints cells, in
## tiles. The shader clips the water at the real bank curve (|across| == 1)
## and feathers it out just past that -- but a fragment can only be clipped
## if its CELL was painted at all, and the smooth curve passes through
## cells whose centres sit beyond the half-width. 0.75 covers a tile whose
## centre is just outside while its inner corner still holds water
## (half a tile diagonal is ~0.71).
const RIVER_BANK_APRON_TILES := 0.75

## How close the second-nearest segment must be (beyond the nearest) for
## the corner blend to engage -- see the CORNER BLEND note in
## nearest_river_at. Small: only the neighbourhood of a flip line blends;
## everywhere else the hard winner stands alone.
const SEGMENT_BLEND_BAND_TILES := 1.5

## name -> ordered Array[Vector2] of (latitude_deg, longitude_deg) waypoints,
## source to mouth -- NOT engine (x, y); x holds latitude here, matching how
## every real-world coordinate in this project is written left-to-right
## (e.g. "48.007669, 7.805657" reads as lat, lon). Real sources: Wikipedia
## (EN/DE) infoboxes and Wikimedia Commons/OpenStreetMap geo-tags,
## cross-checked the same way this project verified the Freiburg spawn
## point (test_world_spawn_location.gd). None of these cross the ±180
## antimeridian, so the plain (not wraparound-aware) segment math below is
## exact for every entry here.
const RIVERS := {
	"Dreisam": [
		Vector2(47.974167, 7.960556),  # source: Rotbach/Wagensteigbach confluence, Kirchzarten
		Vector2(47.9990, 7.8421),      # Freiburg im Breisgau city center
		Vector2(48.007669, 7.805657),  # Gaskugel, Betzenhausen -- this game's own spawn point
		Vector2(48.1475, 7.755),       # mouth: confluence with the Elz, Riegel am Kaiserstuhl
	],
	# Germany's major rivers, phase 1 of the roster (docs/concept/rivers.md).
	# Every via-point is a city's own Wikipedia infobox coordinate (its
	# historic centre), not a river-crossing-specific point -- an accepted
	# simplification for a curated, non-survey-grade polyline.
	"Rhine": [
		Vector2(46.63250, 8.67222),   # source: Tomasee / Lai da Tuma, Graubünden, Switzerland
		Vector2(47.55472, 7.59056),   # Basel
		Vector2(48.58333, 7.74583),   # Strasbourg
		Vector2(49.00921, 8.40395),   # Karlsruhe
		Vector2(49.99944, 8.27361),   # Mainz
		Vector2(50.35972, 7.59778),   # Koblenz (Rhine/Mosel confluence area)
		Vector2(50.93639, 6.95278),   # Cologne
		Vector2(51.43472, 6.76250),   # Duisburg
		Vector2(51.98167, 4.08056),   # mouth: North Sea at Hoek van Holland, Netherlands
	],
	"Danube": [
		Vector2(47.95083, 8.52028),   # source: Donaueschingen (Brigach/Breg confluence)
		Vector2(48.39861, 9.99111),   # Ulm
		Vector2(49.017, 12.083),      # Regensburg
		Vector2(48.57444, 13.46472),  # Passau
		Vector2(45.2175, 29.7614),    # mouth: Danube Delta at Sulina, Romania (Black Sea)
	],
	"Elbe": [
		Vector2(50.77572, 15.53615),  # source: Elbe Spring, Krkonoše (Riesengebirge), Czech Republic
		Vector2(51.05000, 13.74000),  # Dresden
		Vector2(52.13167, 11.63917),  # Magdeburg
		Vector2(53.550, 10.000),      # Hamburg
		Vector2(53.92222, 8.72222),   # mouth: North Sea near Cuxhaven
	],
	"Weser": [
		Vector2(51.42139, 9.64806),   # source: Werra/Fulda confluence, Hann. Münden
		Vector2(52.100, 9.367),       # Hamelin
		Vector2(52.28833, 8.91667),   # Minden
		Vector2(53.07583, 8.80722),   # Bremen
		Vector2(53.53556, 8.56556),   # mouth: Wadden Sea/North Sea near Bremerhaven
	],
	"Main": [
		Vector2(50.0869, 11.3978),    # source: White Main/Red Main confluence, Kulmbach-Melkendorf
		Vector2(49.89139, 10.88694),  # Bamberg
		Vector2(49.783, 9.933),       # Würzburg
		Vector2(50.11056, 8.68222),   # Frankfurt am Main
		Vector2(49.99444, 8.29333),   # mouth: confluence with the Rhine near Mainz
	],
	"Mosel": [
		Vector2(47.8895, 6.8927),     # source: Col de Bussang, Vosges mountains, France
		Vector2(49.12028, 6.17778),   # Metz, France
		Vector2(49.75667, 6.64139),   # Trier, Germany
		Vector2(50.3656, 7.6063),     # mouth: confluence with the Rhine at Koblenz
	],
	"Neckar": [
		Vector2(48.0449, 8.5283),     # source: Schwenninger Moos, Villingen-Schwenningen
		Vector2(48.52000, 9.05556),   # Tübingen
		Vector2(48.77750, 9.18000),   # Stuttgart
		Vector2(49.150, 9.217),       # Heilbronn
		Vector2(49.417, 8.717),       # Heidelberg
		Vector2(49.51194, 8.43722),   # mouth: confluence with the Rhine at Mannheim
	],
	"Oder": [
		Vector2(49.61306, 17.52083),  # source: near Kozlov, Oderské vrchy, Czech Republic
		Vector2(51.11000, 17.03250),  # Wrocław, Poland
		Vector2(52.34194, 14.55167),  # Frankfurt (Oder), Germany
		Vector2(53.43250, 14.54806),  # Szczecin, Poland
		Vector2(53.67194, 14.52361),  # mouth: Szczecin Lagoon -> Baltic Sea
	],
	"Spree": [
		Vector2(51.00971, 14.64959),  # source: near Ebersbach-Neugersdorf, Oberlausitz
		Vector2(51.18139, 14.42417),  # Bautzen
		Vector2(51.76056, 14.33417),  # Cottbus
		Vector2(51.867, 13.967),      # Lübbenau / Spreewald
		Vector2(52.52000, 13.40500),  # Berlin
		Vector2(52.53622, 13.20883),  # mouth: confluence with the Havel at Berlin-Spandau
	],
	"Isar": [
		Vector2(47.3756, 11.4081),    # source: Hinterautal, Karwendel range, Tyrol, Austria
		Vector2(47.417, 11.250),      # Mittenwald
		Vector2(47.76028, 11.55667),  # Bad Tölz
		Vector2(48.13750, 11.57500),  # Munich
		Vector2(48.53972, 12.15083),  # Landshut
		Vector2(48.80306, 12.97639),  # mouth: confluence with the Danube near Deggendorf
	],
}

var _geo := GeoCoordinates.new()

## river name -> Array[Vector2] of TILE-space polyline points, keyed by world
## size, shared by the whole process.
##
## Converting RIVERS' real lat/lon waypoints into tile space depends on
## nothing but (world_width, world_height), and never changes -- yet this
## used to be redone inside every distance_to_nearest_river_tiles call: ~50
## GeoCoordinates.tile_for_coordinate conversions plus ~44 segment tests, per
## call. That function is called PER TILE from five separate hot paths
## (EarthChunkGenerator.generate_chunk, EarthChunkManager's water/river-flow/
## snow painters, and _can_root_at), so one 32x32 chunk load paid the
## conversion cost thousands of times over for an answer that is identical
## every time. Same `static var _..._cache: Dictionary` shape
## EarthElevationSource._decoded_cache already uses, for the same reason.
##
## Pinned by test_tile_polylines_are_cached_per_world_size and
## test_caching_does_not_change_the_distance_answer.
static var _polyline_cache: Dictionary = {}

## Memo of the most recent _course_cache lookup. The world size is the same
## on essentially every call in a running game, so the Dictionary lookup --
## and, more expensively, the "%d_%d" String allocation used to key it --
## are pure waste per call in the five per-tile hot paths. Measured: removing
## them roughly halved nearest_river_at's remaining cost again on top of the
## polyline caching itself.
static var _last_width := -1
static var _last_height := -1
static var _last_courses: Dictionary = {}


## The cached tile-space polylines for a given world size (see
## _polyline_cache). Public so a test can assert the sharing directly, and so
## a caller doing its own geometry over the courses need not rebuild them.
static func tile_polylines(world_width: int, world_height: int) -> Dictionary:
	var by_river := {}
	for river_name in _course_cache(world_width, world_height):
		by_river[river_name] = _course_cache(world_width, world_height)[river_name]["points"]
	return by_river


## The UNsmoothed tile-space waypoints, straight from the curated lat/lon
## data -- what tile_polylines starts from before Chaikin. Exists so tests
## can hold the smoothing to its contract (length preserved, endpoints
## pinned) against the genuine source rather than a copy of the answer.
static func raw_tile_polylines(world_width: int, world_height: int) -> Dictionary:
	var geo := GeoCoordinates.new()
	var by_river := {}
	for river_name in RIVERS:
		var raw_points: Array[Vector2] = []
		for waypoint in RIVERS[river_name]:
			var t := geo.tile_for_coordinate(waypoint.x, waypoint.y, world_width, world_height)
			raw_points.append(Vector2(t.x, t.y))
		by_river[river_name] = raw_points
	return by_river


## Targeted follow-up to the two global Chaikin passes: a near-hairpin in
## the source data (the Rhine knee) still turns ~56 degrees after two
## passes, and a third GLOBAL pass would double every river's point count
## -- and nearest_river_at walks those segments in five per-tile hot paths
## -- to fix a handful of vertices. So only vertices still turning past 45
## degrees get their corner cut again, locally.
static func _cut_remaining_sharp_corners(points: Array[Vector2]) -> Array[Vector2]:
	var current := points
	for _round in 4:
		var sharpest := 0.0
		var result: Array[Vector2] = []
		result.append(current[0])
		for i in range(1, current.size() - 1):
			var ab := current[i] - current[i - 1]
			var bc := current[i + 1] - current[i]
			var turn := absf(rad_to_deg(ab.angle_to(bc)))
			sharpest = maxf(sharpest, turn)
			if turn > 45.0:
				result.append(current[i - 1].lerp(current[i], 0.75))
				result.append(current[i].lerp(current[i + 1], 0.25))
			else:
				result.append(current[i])
		result.append(current[-1])
		current = result
		if sharpest <= 45.0:
			break
	return current


## One pass of Chaikin corner cutting: every interior segment (a, b) is
## replaced by the two points 1/4 and 3/4 of the way along it, which slices
## the tip off every corner. Endpoints are kept exactly.
static func _chaikin_smoothed(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() < 3:
		return points.duplicate()
	var smoothed: Array[Vector2] = []
	smoothed.append(points[0])
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		smoothed.append(a.lerp(b, 0.25))
		smoothed.append(a.lerp(b, 0.75))
	smoothed.append(points[-1])
	return smoothed


## Everything about a course that depends only on the world size, computed
## once: the tile-space points, the cumulative length to each point, the
## total length, and a bounding rectangle.
##
## The cumulative lengths exist so course_fraction costs no extra traversal;
## the bounds exist so nearest_river_at can reject a whole river with one
## rectangle test rather than walking all its segments. Most queried tiles
## are nowhere near most of the 11 rivers, so that rejection is what keeps
## this affordable in the five per-tile hot paths that call it.
static func _course_cache(world_width: int, world_height: int) -> Dictionary:
	if world_width == _last_width and world_height == _last_height:
		return _last_courses

	var key := "%d_%d" % [world_width, world_height]
	if _polyline_cache.has(key):
		_last_width = world_width
		_last_height = world_height
		_last_courses = _polyline_cache[key]
		return _last_courses

	var geo := GeoCoordinates.new()
	var by_river := {}
	for river_name in RIVERS:
		var raw_points: Array[Vector2] = []
		for waypoint in RIVERS[river_name]:
			var t := geo.tile_for_coordinate(waypoint.x, waypoint.y, world_width, world_height)
			raw_points.append(Vector2(t.x, t.y))
		# Chaikin corner-cutting, twice. The curated waypoints are
		# city-to-city straight lines, so every vertex was a sharp corner:
		# the bank (an offset of this course) inherited each kink, adjacent
		# tiles near a vertex snapped to different segments with visibly
		# different tangents ("hard cuts / misalignments"), and the outside
		# of every bend was a patch of endpoint-clamped cells. Each pass
		# quarters the turn angle at every vertex; two passes bring even a
		# hairpin under 45 degrees. Endpoints are pinned -- a river must
		# still rise at its real source and end at its real mouth.
		var tile_points := _cut_remaining_sharp_corners(
			_chaikin_smoothed(_chaikin_smoothed(raw_points))
		)

		var cumulative: Array[float] = []
		var travelled := 0.0
		var minimum := tile_points[0]
		var maximum := tile_points[0]
		for i in tile_points.size():
			cumulative.append(travelled)
			if i < tile_points.size() - 1:
				travelled += tile_points[i].distance_to(tile_points[i + 1])
			minimum = Vector2(minf(minimum.x, tile_points[i].x), minf(minimum.y, tile_points[i].y))
			maximum = Vector2(maxf(maximum.x, tile_points[i].x), maxf(maximum.y, tile_points[i].y))

		by_river[river_name] = {
			"points": tile_points,
			"cumulative": cumulative,
			"total_length": travelled,
			"bounds": Rect2(minimum, maximum - minimum),
		}
	_polyline_cache[key] = by_river
	_last_width = world_width
	_last_height = world_height
	_last_courses = by_river
	return by_river


## True if (tile_x, tile_y) is within RIVER_HALF_WIDTH_TILES of any curated
## river's simplified course, on a world_width x world_height grid.
func is_river_tile(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	return (
		distance_to_nearest_river_tiles(tile_x, tile_y, world_width, world_height)
		<= RIVER_HALF_WIDTH_TILES
	)


## The minimum tile-space distance from (tile_x, tile_y) to any curated
## river's simplified polyline, across every consecutive waypoint segment of
## every river -- the same "distance in tile space, not real spherical
## distance" tradeoff GeoCoordinates.tile_is_within_radius already makes.
## INF if RIVERS is empty (never true today).
func distance_to_nearest_river_tiles(
	tile_x: int, tile_y: int, world_width: int, world_height: int
) -> float:
	return nearest_river_at(tile_x, tile_y, world_width, world_height).distance_tiles


## Which curated river is nearest to (tile_x, tile_y), how far away it is, and
## how far ALONG that river's course the nearest point sits:
##   {name: String, distance_tiles: float, course_fraction: float}
##
## course_fraction is 0.0 at the source waypoint and 1.0 at the mouth,
## measured by real accumulated tile-space length along the polyline (not by
## waypoint index -- waypoints are unevenly spaced, so index would badly
## misreport position on a river whose via-points cluster near one city).
## That fraction is what real discharge interpolation needs: a real river's
## flow grows from source to mouth as its drainage area accumulates.
##
## Always answers, even far from every river -- the caller decides whether
## the distance disqualifies it, exactly as is_river_tile already does.
## Empty name and INF distance only if RIVERS itself is empty.
func nearest_river_at(
	tile_x: int, tile_y: int, world_width: int, world_height: int
) -> Dictionary:
	var point := Vector2(tile_x, tile_y)
	var best_name := ""
	var best_distance := INF
	var best_fraction := 0.0
	var best_tangent := Vector2(0.0, -1.0)
	var best_signed_across := 0.0
	var _projection_is_cap := false

	var courses := _course_cache(world_width, world_height)
	for river_name in courses:
		var course: Dictionary = courses[river_name]
		# Reject the whole river with one rectangle test when even its
		# closest possible point is farther than the best hit so far.
		# Distance to the bounding rect is a true lower bound on distance to
		# any segment inside it, so this can never change the answer -- only
		# skip work. Pinned by test_caching_does_not_change_the_distance_answer.
		if _distance_to_rect(point, course["bounds"]) >= best_distance:
			continue

		var tile_points: Array = course["points"]
		var cumulative: Array = course["cumulative"]
		var total_length: float = course["total_length"]
		for i in range(tile_points.size() - 1):
			var a: Vector2 = tile_points[i]
			var b: Vector2 = tile_points[i + 1]
			var t := _projection_fraction(point, a, b)
			var d := point.distance_to(a + (b - a) * t)
			if d < best_distance:
				best_distance = d
				best_name = river_name
				# The winning segment's own direction IS the downstream
				# tangent -- course points are stored source-to-mouth, so
				# b - a already points the way the water goes.
				if not b.is_equal_approx(a):
					best_tangent = (b - a).normalized()
				# The perpendicular component of (point - closest), SIGNED
				# by which bank side -- the cross product's z with the unit
				# tangent gives exactly that in one step. This is the field
				# the flow shader's per-fragment reconstruction refines, so
				# it must be the perpendicular COMPONENT (smooth through
				# clamped segment ends at bends), not sign * euclidean
				# distance (which kinks there).
				#
				# EXCEPT past the course's very tips: beyond the source or
				# mouth the perpendicular component degenerates (it shrinks
				# while the real distance does not), which painted the
				# region around every tip as mid-channel water in a ragged
				# patch -- most visibly at confluences, where a tributary
				# mouth sits mid-junction. Radial distance there caps each
				# end in a clean semicircle instead.
				var closest := a + (b - a) * t
				var past_source := i == 0 and t <= 0.0
				var past_mouth := i == tile_points.size() - 2 and t >= 1.0
				if past_source or past_mouth:
					var side := signf(best_tangent.cross(point - closest))
					best_signed_across = (1.0 if side == 0.0 else side) * d
					_projection_is_cap = true
				else:
					best_signed_across = best_tangent.cross(point - closest)
					_projection_is_cap = false
				best_fraction = (
					(cumulative[i] + a.distance_to(b) * t) / total_length
					if total_length > 0.0 else 0.0
				)

	# CORNER SMOOTHING -- the fix for "parts of the stream are mirrored and
	# connect wrongly". At the Voronoi boundary between two segments the
	# hard winner flips, and the across field jumped a full measured tile
	# mid-channel. Instead of one winner, every segment of the winning
	# river within SEGMENT_BLEND_BAND_TILES of the best distance
	# contributes to a smoothly weighted average -- weights fade to zero as
	# a segment leaves the band and as its tangent disagrees with the
	# winner (the far bank of a hairpin must not pull), so the field is
	# continuous through every corner BY CONSTRUCTION. Past-tip radial
	# caps keep the hard answer: a cap is a line end, and its radial value
	# is pinned exact by test.
	if best_name != "" and not _projection_is_cap:
		var course: Dictionary = _course_cache(world_width, world_height)[best_name]
		var tile_points: Array = course["points"]
		var cumulative: Array = course["cumulative"]
		var total_length: float = course["total_length"]
		var weight_sum := 0.0
		var across_sum := 0.0
		var fraction_sum := 0.0
		var tangent_sum := Vector2.ZERO
		for i in range(tile_points.size() - 1):
			var a: Vector2 = tile_points[i]
			var b: Vector2 = tile_points[i + 1]
			if b.is_equal_approx(a):
				continue
			var t := _projection_fraction(point, a, b)
			var closest := a + (b - a) * t
			var d := point.distance_to(closest)
			if d - best_distance >= SEGMENT_BLEND_BAND_TILES:
				continue
			var tangent := (b - a).normalized()
			var agreement := clampf((tangent.dot(best_tangent) - 0.2) / 0.3, 0.0, 1.0)
			if agreement <= 0.0:
				continue
			var band_weight := 1.0 - (d - best_distance) / SEGMENT_BLEND_BAND_TILES
			var weight := band_weight * band_weight * agreement
			weight_sum += weight
			across_sum += weight * tangent.cross(point - closest)
			fraction_sum += weight * (
				(cumulative[i] + a.distance_to(b) * t) / total_length
				if total_length > 0.0 else 0.0
			)
			tangent_sum += weight * tangent
		if weight_sum > 0.0:
			best_signed_across = across_sum / weight_sum
			best_fraction = fraction_sum / weight_sum
			if tangent_sum.length() > 0.0001:
				best_tangent = tangent_sum.normalized()

	return {
		"name": best_name,
		"distance_tiles": best_distance,
		"course_fraction": clampf(best_fraction, 0.0, 1.0),
		"course_bearing_deg": bearing_degrees(best_tangent),
		"signed_across_tiles": best_signed_across,
	}


## Compass bearing of a tile-space direction, in the convention
## ProceduralRiverFlowSprite bakes and the flow shader reads: 0 is north,
## 90 is east, and +Y is DOWN because this is screen space, not a map.
static func bearing_degrees(direction: Vector2) -> float:
	if direction.is_zero_approx():
		return 0.0
	return fposmod(rad_to_deg(atan2(direction.x, -direction.y)), 360.0)


## How far along segment a-b the perpendicular projection of `point` falls,
## clamped to [0, 1] so it never runs off either end of the segment. Shared
## by the distance and the along-course-position answers, which are two
## readings of this one projection.
func _projection_fraction(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq == 0.0:
		return 0.0
	return clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)


## Shortest distance from `point` to anywhere inside `rect` -- 0.0 when the
## point is inside it. A true LOWER BOUND on the distance to any segment
## contained by the rect, which is what makes nearest_river_at's early
## rejection safe.
func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return sqrt(dx * dx + dy * dy)


