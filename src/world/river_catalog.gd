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
	var point := Vector2(tile_x, tile_y)
	var best := INF
	for river_name in RIVERS:
		var waypoints: Array = RIVERS[river_name]
		var tile_points: Array[Vector2] = []
		for waypoint in waypoints:
			var t := _geo.tile_for_coordinate(waypoint.x, waypoint.y, world_width, world_height)
			tile_points.append(Vector2(t.x, t.y))
		for i in range(tile_points.size() - 1):
			var d := _distance_to_segment(point, tile_points[i], tile_points[i + 1])
			best = minf(best, d)
	return best


## Real point-to-segment distance (not just nearest-endpoint): projects
## `point` onto the segment a-b, clamped to the segment itself, and returns
## the distance to that projection.
func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq == 0.0:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	var projection := a + ab * t
	return point.distance_to(projection)
