extends SceneTree

## Dev tool: measures the real per-tile near-shore ocean slope across many
## real generated shorelines, to ground WaterMovementModel.OCEAN_DEPTH_
## RANGE_METERS in actual world data rather than a guess. Reported
## directly: "the players submerged tint should gradually fill from the
## feet upwards as he walks down the shore into deeper water based on the
## elevation and slope" (already true for river/lake), then "ocean depth
## too" once ocean was named as the one remaining gap.
##
## Player._resolve_water_state already fed BiomeClassifier.depth_meters_at
## continuous, real per-tile elevation for ocean -- the bug was the
## CONVERSION SCALE: EarthChunkGenerator.EARTH_OCEAN_DEPTH_RANGE_METERS
## (8000.0, the real bathymetric depth this world's bundled elevation data
## encodes at its lowest point) is correct as "real metres of depth" but
## is a wild mismatch against WaterMovementModel.WADE_DEPTH_METERS (1.5m).
##
## Part 1 scans a spread of world columns for genuine near-sea-level
## shoreline starts (skipping any "shoreline" that was already deep at
## first hit -- a steep cliff, not a slope worth measuring) and computes
## the depth-FRACTION delta over the next 3 tiles, giving a robust
## min/median/max/percentile picture of real near-shore slope rather than
## one hand-picked transect. Part 2 checks 5 real, unambiguously deep
## open-ocean points to confirm a smaller gameplay scale does not
## accidentally make genuine deep ocean read as merely wadeable.
##
## Headless-safe: pure elevation/depth math, no GPU.
## Usage: godot --headless --path <project> -s <this file>

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")

## Candidate gameplay depth-range scales to compare against the real
## bathymetric one (8000.0) -- WaterMovementModel.OCEAN_DEPTH_RANGE_METERS
## (50.0) was picked from this comparison.
const CANDIDATE_SCALES := [8000.0, 200.0, 100.0, 50.0, 25.0, 10.0, 4.0]

## Real, unambiguously deep open-ocean points (lat, lon, name) -- guards
## against the chosen scale making genuine deep ocean read as shallow.
const DEEP_OCEAN_POINTS := [
	["mid-Pacific", 0.0, -150.0],
	["mid-Pacific-2", 10.0, -170.0],
	["mid-Atlantic", 20.0, -40.0],
	["Mariana-Trench-area", 11.0, 142.0],
	["Indian-Ocean", -20.0, 80.0],
]


func _find_shoreline(generator: EarthChunkGenerator, x: int, start_y: int, max_scan: int) -> int:
	for offset in max_scan:
		var y: int = start_y + offset
		var elevation: float = generator.elevation_at_global(x, y)
		if elevation < EarthChunkGenerator.EARTH_SEA_LEVEL:
			return y
	return -1


func _survey_near_shore_slopes(generator: EarthChunkGenerator, classifier: BiomeClassifier) -> void:
	var per_tile_fractions: Array[float] = []
	var sample_coords: Array[Vector2i] = []
	var samples := 0
	for x in range(500, EarthChunkGenerator.WORLD_WIDTH_TILES - 500, 800):
		for start_y in range(200, EarthChunkGenerator.WORLD_HEIGHT_TILES - 200, 1400):
			var shore_y := _find_shoreline(generator, x, start_y, 400)
			if shore_y < 0:
				continue
			var shore_elevation: float = generator.elevation_at_global(x, shore_y)
			# Skip a "shoreline" already deep at first hit (a steep cliff or
			# pre-existing deep water, not a genuine slope to measure).
			var shore_fraction := classifier.depth_at(shore_elevation, EarthChunkGenerator.EARTH_SEA_LEVEL)
			if shore_fraction > 0.05:
				continue
			var far_elevation: float = generator.elevation_at_global(x, shore_y + 3)
			var far_fraction := classifier.depth_at(far_elevation, EarthChunkGenerator.EARTH_SEA_LEVEL)
			var per_tile := (far_fraction - shore_fraction) / 3.0
			if per_tile > 0.0:
				per_tile_fractions.append(per_tile)
				sample_coords.append(Vector2i(x, shore_y))
				samples += 1

	var order: Array[int] = []
	for i in samples:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return per_tile_fractions[a] < per_tile_fractions[b])

	print("=== Part 1: near-shore slope survey ===")
	print("genuine near-shore samples found: %d" % samples)
	if samples == 0:
		return
	var geo := GeoCoordinates.new()
	var median_i: int = order[samples / 2]
	var median_coord := sample_coords[median_i]
	var median_lat := geo.latitude_for_tile(median_coord.y, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var median_lon := geo.longitude_for_tile(median_coord.x, EarthChunkGenerator.WORLD_WIDTH_TILES)
	print("min per-tile depth-fraction: %.6f at %s" % [per_tile_fractions[order[0]], sample_coords[order[0]]])
	print(
		"median per-tile depth-fraction: %.6f at tile %s (lat=%.4f, lon=%.4f)"
		% [per_tile_fractions[median_i], median_coord, median_lat, median_lon]
	)
	print("max per-tile depth-fraction: %.6f at %s" % [per_tile_fractions[order[samples - 1]], sample_coords[order[samples - 1]]])
	print("25th pct: %.6f at %s" % [per_tile_fractions[order[int(samples * 0.25)]], sample_coords[order[int(samples * 0.25)]]])
	print("75th pct: %.6f at %s" % [per_tile_fractions[order[int(samples * 0.75)]], sample_coords[order[int(samples * 0.75)]]])

	var median: float = per_tile_fractions[median_i]
	for candidate: float in CANDIDATE_SCALES:
		var tiles_to_wade: float = WaterMovementModel.WADE_DEPTH_METERS / (median * candidate)
		print(
			"candidate max_depth_meters=%.1f -> median slope reaches wade depth in ~%.2f tiles"
			% [candidate, tiles_to_wade]
		)

	# Detailed transect at the median sample -- the exact numbers
	# tests/unit/test_player_ocean_water_state.gd's SHORE_TILE fixture cites.
	print("--- detailed transect at the median sample (used as the test fixture) ---")
	for step in [0, 1, 2, 3, 4, 5, 8, 10]:
		var y: int = median_coord.y + step
		var elevation: float = generator.elevation_at_global(median_coord.x, y)
		var fraction: float = classifier.depth_at(elevation, EarthChunkGenerator.EARTH_SEA_LEVEL)
		print(
			"  +%dtiles: elevation=%.6f depth_fraction=%.6f depth_m(range=%.0f)=%.3f"
			% [step, elevation, fraction, WaterMovementModel.OCEAN_DEPTH_RANGE_METERS,
				fraction * WaterMovementModel.OCEAN_DEPTH_RANGE_METERS]
		)


func _check_deep_ocean_points(generator: EarthChunkGenerator, classifier: BiomeClassifier) -> void:
	print("=== Part 2: real deep-ocean confirmation ===")
	var geo := GeoCoordinates.new()
	for entry in DEEP_OCEAN_POINTS:
		var point_name: String = entry[0]
		var lat: float = entry[1]
		var lon: float = entry[2]
		var tile := geo.tile_for_coordinate(lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES)
		var elevation: float = generator.elevation_at_global(tile.x, tile.y)
		var fraction: float = classifier.depth_at(elevation, EarthChunkGenerator.EARTH_SEA_LEVEL)
		var depth_m := fraction * WaterMovementModel.OCEAN_DEPTH_RANGE_METERS
		print(
			"%s (lat=%.2f,lon=%.2f) -> tile=%s depth_m(range=%.0f)=%.2f wade=%s"
			% [point_name, lat, lon, tile, WaterMovementModel.OCEAN_DEPTH_RANGE_METERS, depth_m,
				depth_m >= WaterMovementModel.WADE_DEPTH_METERS]
		)


func _initialize() -> void:
	var generator := EarthChunkGenerator.new()
	var classifier := BiomeClassifier.new()
	_survey_near_shore_slopes(generator, classifier)
	_check_deep_ocean_points(generator, classifier)
	quit()
