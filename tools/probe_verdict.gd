extends SceneTree

## Dev tool: measures the real-world size of the distance-vs-across split
## that test_signed_across_has_the_true_distance_as_its_magnitude_
## everywhere caught.
##
## nearest_channel_geometry used to report `distance_tiles` from the hit
## with the smallest BANK REACH while blending `signed_across_tiles` over
## the hits that CONTAIN the tile -- possibly a different channel. probe()
## calls a tile river when distance <= half_width; the shader calls it wet
## when |across| / half < 1. Where the two numbers disagree, the CPU and
## the GPU disagree about where the water is.
##
## This walks a window of real tiles, recomputes BOTH verdicts, and counts
## how many tiles flip -- so "does this bug actually show on screen" is a
## measurement rather than an argument.
##
## Usage: godot --headless --path . -s tools/probe_verdict.gd -- lat lon radius

const HydrologyData = preload("res://src/world/hydrology_data.gd")
const HydrologyField = preload("res://src/world/hydrology_field.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lat := float(args[0]) if args.size() > 0 else 47.2031
	var lon := float(args[1]) if args.size() > 1 else -1.5469
	var radius := int(args[2]) if args.size() > 2 else 60

	var data := HydrologyData.new()
	if not data.load_from(HydrologyData.DEFAULT_DIRECTORY):
		print("probe_verdict: no bake at %s" % HydrologyData.DEFAULT_DIRECTORY)
		quit()
		return
	var field := HydrologyField.new(
		data, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var geo := GeoCoordinates.new()
	var center := geo.tile_for_coordinate(
		lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	print("verdict scan around %s, radius %d (%d tiles)" % [
		center, radius, (2 * radius + 1) * (2 * radius + 1)
	])

	var examined := 0
	var flips := 0
	var worst := 0.0
	var worst_tile := Vector2i.ZERO
	var disagreements := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := center.x + dx
			var y := center.y + dy
			var hits: Array = field._channel_hits(x, y)
			if hits.is_empty():
				continue
			var geometry: Dictionary = field.nearest_channel_geometry(x, y)
			if geometry.is_empty():
				continue
			examined += 1
			# The OLD distance: the hit with the smallest bank reach.
			var old_distance := INF
			var old_half := 0.0
			var nearest_reach := INF
			for hit in hits:
				var reach: float = hit["distance_tiles"] - hit["half_width_tiles"]
				if reach < nearest_reach:
					nearest_reach = reach
					old_distance = hit["distance_tiles"]
					old_half = hit["half_width_tiles"]
			var new_distance: float = geometry["distance_tiles"]
			var half: float = geometry["half_width_tiles"]
			var gap := absf(new_distance - old_distance)
			if gap > 1e-6:
				disagreements += 1
			if gap > worst:
				worst = gap
				worst_tile = Vector2i(x, y)
			# The verdict each number produces.
			var old_wet := old_distance <= old_half
			var new_wet := new_distance <= half
			if old_wet != new_wet:
				flips += 1

	print("tiles with a channel in reach: %d" % examined)
	print("tiles where the two distances disagreed at all: %d (%.1f%%)" % [
		disagreements, 100.0 * float(disagreements) / maxf(1.0, float(examined))
	])
	print("tiles whose WET/DRY VERDICT flipped: %d (%.1f%%)" % [
		flips, 100.0 * float(flips) / maxf(1.0, float(examined))
	])
	print("worst distance disagreement: %.3f tiles at %s" % [worst, worst_tile])
	quit()
