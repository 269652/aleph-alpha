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
	_print_depression_histograms(data)

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
	_print_candidates(candidates, count, lat_min, lat_max, lon_min, lon_max)
	quit()


## Depression size, depth (spill minus floor, in 8-bit asset steps of
## 56.5 m) and inflow-per-cell histograms -- the numbers the lake filters
## in tools/bake_hydrology.gd are chosen against.
func _print_depression_histograms(data: HydrologyData) -> void:
	var step := 1.0 / 255.0
	var by_size := {}
	var by_depth := {}
	var by_inflow := {}
	var cells_by_size := {}
	for depression in data.depressions:
		var size_bucket := _bucket(int(depression["cell_count"]), [4, 8, 16, 32, 64, 128, 512, 100000])
		by_size[size_bucket] = by_size.get(size_bucket, 0) + 1
		cells_by_size[size_bucket] = cells_by_size.get(size_bucket, 0) + int(depression["cell_count"])
		var depth_steps := (float(depression["spill_elevation"]) - float(depression["floor_elevation"])) / step
		var depth_bucket := _bucket(int(floor(depth_steps + 0.5)), [1, 2, 3, 5, 10, 100000])
		by_depth[depth_bucket] = by_depth.get(depth_bucket, 0) + 1
		var inflow := data.discharge_at(int(depression["spill_index"])) / float(depression["cell_count"])
		var inflow_bucket := _bucket(int(floor(inflow * 10.0)), [1, 3, 6, 10, 30, 100, 100000])
		by_inflow[inflow_bucket] = by_inflow.get(inflow_bucket, 0) + 1
	print("depressions by cell count (upper bound: count / cells): %s" % _sorted(by_size, cells_by_size))
	print("depressions by depth in 8-bit steps (upper bound: count): %s" % _sorted(by_depth, {}))
	print("depressions by inflow per cell, tenths of full rain (upper bound: count): %s" % _sorted(by_inflow, {}))


func _bucket(value: int, bounds: Array) -> int:
	for bound in bounds:
		if value <= bound:
			return bound
	return bounds[-1]


func _sorted(counts: Dictionary, cells: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		if cells.is_empty():
			parts.append("<=%d: %d" % [key, counts[key]])
		else:
			parts.append("<=%d: %d / %d" % [key, counts[key], cells[key]])
	return ", ".join(parts)


func _print_candidates(candidates: Array, count: int, lat_min: float, lat_max: float, lon_min: float, lon_max: float) -> void:
	print("strongest emergent channels in lat %.1f..%.1f lon %.1f..%.1f (>= %d tiles from curated rivers):" % [
		lat_min, lat_max, lon_min, lon_max, int(CURATED_CLEARANCE_TILES)
	])
	for i in mini(count, candidates.size()):
		var c: Dictionary = candidates[i]
		print("  lat %8.4f lon %8.4f  Q=%8.1f  elev %5.0fm  tile (%d, %d)  curated %.0f tiles away" % [
			c["lat"], c["lon"], c["discharge"], c["elevation_m"], c["tile"].x, c["tile"].y, c["curated_distance"]
		])
