extends SceneTree

## Dev tool: dumps the across/width fields the flow overlay reads around
## a real lat/lon, for tracing an artifact seen in play back to its data.
## Usage: godot --headless --path . -s tools/probe_latlon.gd [lat lon radius]

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lat := float(args[0])
	var lon := float(args[1])
	var radius := int(args[2]) if args.size() > 2 else 25
	var generator := EarthChunkGenerator.new()
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	print("tile %s" % [tile])
	print("across field (|signed across| / half-width, tenths):")
	for dy in range(-radius, radius + 1):
		var line := ""
		for dx in range(-radius, radius + 1):
			var hit := generator.nearest_river_at(tile.x + dx, tile.y + dy)
			var half: float = hit.get("half_width_tiles", 2.0)
			var across: float = absf(hit.signed_across_tiles) / maxf(half, 0.01)
			if hit.distance_tiles > half + 0.75:
				line += "."
			elif across >= 1.0:
				line += "#"
			else:
				line += str(int(across * 10.0))
		print(line)
	print("width field (half-width in tenths of a tile):")
	for dy in range(-radius, radius + 1):
		var line := ""
		for dx in range(-radius, radius + 1):
			var hit := generator.nearest_river_at(tile.x + dx, tile.y + dy)
			var half: float = hit.get("half_width_tiles", 2.0)
			if hit.distance_tiles > half + 0.75:
				line += "."
			else:
				line += str(clampi(int(half * 2.0), 0, 9))
		print(line)
	quit()
