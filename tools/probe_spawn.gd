extends SceneTree

## Dev tool: prints an ASCII map of water around the spawn point
## (World.SPAWN_LATITUDE/LONGITUDE) straight from EarthChunkGenerator --
## '~' ocean, 'R' river, 'L' lake, '.' land, '@' the spawn tile -- plus
## the nearest-river geometry there, for checking that the dry-land spawn
## search has land to find.
##
## Usage: godot --headless --path . -s tools/probe_spawn.gd [radius]

const World = preload("res://scenes/world.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var radius := 8
	if args.size() >= 1:
		radius = int(args[0])
	var generator := EarthChunkGenerator.new()
	var geo := GeoCoordinates.new()
	var spawn := geo.tile_for_coordinate(
		World.SPAWN_LATITUDE, World.SPAWN_LONGITUDE,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	print("spawn tile %s, hydrology loaded: %s, rivers enabled: %s" % [
		spawn, generator.has_hydrology(), generator.hydrology_rivers_enabled
	])
	var nearest := generator.nearest_river_at(spawn.x, spawn.y)
	print("nearest river: name '%s' distance %.2f bearing %.1f across %.2f" % [
		nearest.name, nearest.distance_tiles, nearest.course_bearing_deg, nearest.signed_across_tiles
	])
	print("hydraulics: %s" % generator.river_hydraulics_at_global(spawn.x, spawn.y))
	# World._find_dry_land_spawn, emulated on the generator alone: the same
	# expanding-square scan, the same three rejections.
	var found := spawn
	var search_done := false
	for ring in range(World.SPAWN_SEARCH_RADIUS + 1):
		if search_done:
			break
		for dy in range(-ring, ring + 1):
			if search_done:
				break
			for dx in range(-ring, ring + 1):
				var tile := spawn + Vector2i(dx, dy)
				if (
					generator.biome_at_global(tile.x, tile.y) != "ocean"
					and not generator.is_river_at_global(tile.x, tile.y)
					and not generator.is_lake_at_global(tile.x, tile.y)
				):
					found = tile
					search_done = true
					break
	print("dry-land search: %s -> %s (river there: %s, lake there: %s, depth %.2f m)" % [
		spawn, found, generator.is_river_at_global(found.x, found.y),
		generator.is_lake_at_global(found.x, found.y),
		maxf(generator.river_depth_meters_at_global(found.x, found.y), generator.lake_depth_meters_at_global(found.x, found.y))
	])
	for dy in range(-radius, radius + 1):
		var line := ""
		for dx in range(-radius, radius + 1):
			var x := spawn.x + dx
			var y := spawn.y + dy
			var glyph := "."
			if generator.biome_at_global(x, y) == "ocean":
				glyph = "~"
			elif generator.is_lake_at_global(x, y):
				glyph = "L"
			elif generator.is_river_at_global(x, y):
				glyph = "R"
			if dx == 0 and dy == 0:
				glyph = "@"
			line += glyph
		print(line)
	quit()
