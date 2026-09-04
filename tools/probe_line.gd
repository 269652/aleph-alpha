extends SceneTree

## Dev tool: prints raw across/bearing/half-width along a straight line of
## tiles, for checking whether a transition is a smooth gradient or a
## real jump. Usage: godot --headless --path . -s tools/probe_line.gd
## -- lat lon dx dy steps [start_i] [x_offset] [y_offset]

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lat := float(args[0])
	var lon := float(args[1])
	var dx := int(args[2])
	var dy := int(args[3])
	var steps := int(args[4])
	var start_i := int(args[5]) if args.size() > 5 else 0
	var x_offset := int(args[6]) if args.size() > 6 else 0
	var y_offset := int(args[7]) if args.size() > 7 else 0
	var generator := EarthChunkGenerator.new()
	var geo := GeoCoordinates.new()
	var tile := geo.tile_for_coordinate(
		lat, lon, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	for i in range(start_i, start_i + steps):
		var x := tile.x + x_offset + dx * i
		var y := tile.y + y_offset + dy * i
		var hit := generator.nearest_river_at(x, y)
		if hit.is_empty():
			print("i=%3d (%d,%d) NO CHANNEL WITHIN REACH" % [i, x, y])
			continue
		var half: float = hit.get("half_width_tiles", 2.0)
		var across: float = hit.signed_across_tiles / maxf(half, 0.01)
		print("i=%3d (%d,%d) dist=%7.3f half=%6.3f across=%7.3f bearing=%8.3f discharge=%10.2f" % [
			i, x, y, hit.distance_tiles, half, across, hit.course_bearing_deg, hit.get("discharge", -1.0)
		])
	quit()
