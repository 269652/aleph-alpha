extends SceneTree

## Dev tool: lists the strongest baked hydrology channels inside a
## latitude/longitude window, skipping any asset cell a curated river
## already reaches (docs/concept/rivers.md) -- for choosing a spawn point
## on an EMERGENT river, and for eyeballing whether the bake is sane.
##
## Usage:
##   godot --headless --path . -s tools/probe_hydrology.gd [lat_min lat_max lon_min lon_max] [count]

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

## How far (tiles) a candidate must sit from every curated river.
const CURATED_CLEARANCE_TILES := 400.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lat_min := 44.0
	var lat_max := 50.0
	var lon_min := -2.0
	var lon_max := 6.0
	var count := 12
	if args.size() >= 4:
		lat_min = float(args[0])
		lat_max = float(args[1])
		lon_min = float(args[2])
		lon_max = float(args[3])
	if args.size() >= 5:
		count = int(args[4])

	var data := HydrologyData.new()
	if not data.load_from(HydrologyData.DEFAULT_DIRECTORY):
		print("probe_hydrology: no bake at %s" % HydrologyData.DEFAULT_DIRECTORY)
		quit()
		return
	var map: Dictionary = EarthElevationSource.shared_map(EarthElevationSource.DEFAULT_IMAGE_PATH)
	var bytes: PackedByteArray = map["bytes"]
	var catalog := RiverCatalog.new()
	var geo := GeoCoordinates.new()

	var land := 0
	var channels := 0
	var lakes := 0
	for index in data.width * data.height:
		if data.is_sea(index):
			continue
		land += 1
		if data.discharge_at(index) >= 30.0:
			channels += 1
		if data.depression_at(index) >= 0:
			lakes += 1
	print("bake: %dx%d, %d land cells, %d channel cells (Q>=30), %d lake cells, %d depressions" % [
		data.width, data.height, land, channels, lakes, data.depressions.size()
	])

	var candidates: Array = []
	for py in data.height:
		var lat := 90.0 - (float(py) + 0.5) / float(data.height) * 180.0
		if lat < lat_min or lat > lat_max:
			continue
		for px in data.width:
			var lon := -180.0 + (float(px) + 0.5) / float(data.width) * 360.0
			if lon < lon_min or lon > lon_max:
				continue
			var index := py * data.width + px
			if data.is_sea(index):
				continue
			var discharge := data.discharge_at(index)
			if discharge < 30.0:
				continue
			var tile := geo.tile_for_coordinate(
				lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
			)
			var curated := catalog.distance_to_nearest_river_tiles(
				tile.x, tile.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
			)
			if curated < CURATED_CLEARANCE_TILES:
				continue
			candidates.append({
				"lat": lat, "lon": lon, "discharge": discharge,
				"elevation_m": -8000.0 + float(bytes[index]) / 255.0 * 14400.0,
				"tile": tile, "curated_distance": curated,
			})
	candidates.sort_custom(func(a, b): return a["discharge"] > b["discharge"])
	print("strongest emergent channels in lat %.1f..%.1f lon %.1f..%.1f (>= %d tiles from curated rivers):" % [
		lat_min, lat_max, lon_min, lon_max, int(CURATED_CLEARANCE_TILES)
	])
	for i in mini(count, candidates.size()):
		var c: Dictionary = candidates[i]
		print("  lat %8.4f lon %8.4f  Q=%8.1f  elev %5.0fm  tile (%d, %d)  curated %.0f tiles away" % [
			c["lat"], c["lon"], c["discharge"], c["elevation_m"], c["tile"].x, c["tile"].y, c["curated_distance"]
		])
	quit()
