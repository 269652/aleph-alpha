extends SceneTree

## Bake tool for docs/concept/hydrology.md Layer 0: runs DrainageNetwork
## over the real elevation asset's native pixel grid and writes the
## shipped rasters + JSON HydrologyData reads at runtime. Deterministic
## from the asset alone; re-run whenever the asset changes, commit the
## output (assets/data/hydrology/), same "bake once, ship the result"
## relationship the illustrated sprite atlases have to their sources.
##
## Usage (minutes, pure GDScript over 7.4M cells):
##   godot --headless --path . -s tools/bake_hydrology.gd
##
## Discharge is hydrology.md's phase-1 stand-in: StandInPrecipitation over
## latitude, accumulated downstream. Phase 3 replaces it with the live
## climate grid and this bake then ships geometry only.

const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const DrainageNetwork = preload("res://src/world/drainage_network.gd")
const HydrologyData = preload("res://src/world/hydrology_data.gd")
const StandInPrecipitation = preload("res://src/world/stand_in_precipitation.gd")

## Depressions smaller than this many asset cells are data noise (a
## single 8-bit step pixel), filled through rather than kept as lake
## candidates. At ~10km/pixel, four cells is a few hundred km^2 -- the
## smallest lake the data can physically represent (hydrology.md Layer 0).
const MIN_DEPRESSION_AREA_CELLS := 4


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var map: Dictionary = EarthElevationSource.shared_map(EarthElevationSource.DEFAULT_IMAGE_PATH)
	var width: int = map["width"]
	var height: int = map["height"]
	var bytes: PackedByteArray = map["bytes"]
	var heights := PackedFloat32Array()
	heights.resize(width * height)
	for index in heights.size():
		heights[index] = float(bytes[index]) / 255.0
	print("bake_hydrology: %dx%d cells decoded" % [width, height])

	var network = DrainageNetwork.new().build(
		heights, width, height, EarthChunkGenerator.EARTH_SEA_LEVEL, true,
		DrainageNetwork.DEFAULT_MIN_DEPRESSION_DEPTH, MIN_DEPRESSION_AREA_CELLS
	)
	print("bake_hydrology: filled and routed, %d depressions (%.1fs)" % [
		network.depressions.size(), (Time.get_ticks_msec() - started) / 1000.0
	])

	var weights := PackedFloat32Array()
	weights.resize(width * height)
	for y in height:
		var latitude := 90.0 - (float(y) + 0.5) / float(height) * 180.0
		var rain: float = StandInPrecipitation.at_latitude(latitude)
		for x in width:
			weights[y * width + x] = rain
	var discharge: PackedFloat32Array = network.accumulate_weighted(weights)

	var data = HydrologyData.new().build_from_network(network, discharge)
	data.save_to(HydrologyData.DEFAULT_DIRECTORY)
	print("bake_hydrology: wrote %s (%.1fs total)" % [
		HydrologyData.DEFAULT_DIRECTORY, (Time.get_ticks_msec() - started) / 1000.0
	])
	quit()
