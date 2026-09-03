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
	# How long one streamed chunk costs to generate here, cold and warm.
	var chunk_coord := Vector2i(floori(float(spawn.x) / 32.0), floori(float(spawn.y) / 32.0))
	var started := Time.get_ticks_usec()
	generator.generate_chunk(chunk_coord, 32)
	var cold_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	generator.generate_chunk(chunk_coord, 32)
	var warm_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	generator.set_hydrology(null)
	generator.generate_chunk(chunk_coord, 32)
	var bare_ms := (Time.get_ticks_usec() - started) / 1000.0
	generator.set_hydrology(generator._shared_hydrology_field())
	print("generate_chunk 32x32 at spawn: %.0f ms cold, %.0f ms memoized, %.0f ms without hydrology" % [cold_ms, warm_ms, bare_ms])
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
	# The across field the water painter writes, as digits: |across| in
	# tenths (0 = centreline, 9 = near the bank), '.' dry, '#' beyond 1.
	# Concentric structure here is what the shader draws as arcs.
	print("across field (|signed across| / half-width, tenths):")
	for dy in range(-radius, radius + 1):
		var line := ""
		for dx in range(-radius, radius + 1):
			var hit := generator.nearest_river_at(spawn.x + dx, spawn.y + dy)
			var half: float = hit.get("half_width_tiles", 2.0)
			var across: float = absf(hit.signed_across_tiles) / maxf(half, 0.01)
			if hit.distance_tiles > half + 0.75:
				line += "."
			elif across >= 1.0:
				line += "#"
			else:
				line += str(int(across * 10.0))
		print(line)
	if args.size() >= 3:
		# Every channel hit at one tile (dx dy from the spawn), raw.
		var tile := spawn + Vector2i(int(args[1]), int(args[2]))
		var field = generator._shared_hydrology_field()
		field.river_min_discharge = generator._hydrology.river_min_discharge
		print("hits at %s (probe %s):" % [tile, generator.hydrology_at_global(tile.x, tile.y)])
		for hit in field._channel_hits(tile.x, tile.y):
			print("  cell %d Q %.1f distance %.2f half %.2f tangent %s" % [
				hit["cell"], hit["discharge"], hit["distance_tiles"], hit["half_width_tiles"], hit["tangent"]
			])
		print("  geometry: %s" % field.nearest_channel_geometry(tile.x, tile.y))
	print("bearing field (tens of degrees, downstream):")
	for dy in range(-radius, radius + 1):
		var line := ""
		for dx in range(-radius, radius + 1):
			var hit := generator.nearest_river_at(spawn.x + dx, spawn.y + dy)
			if hit.distance_tiles > hit.get("half_width_tiles", 2.0) + 0.75:
				line += "."
			else:
				line += str(int(hit.course_bearing_deg / 36.0))
		print(line)
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
