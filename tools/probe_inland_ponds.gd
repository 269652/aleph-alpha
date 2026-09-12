extends SceneTree

## Dev tool: counts "orphan ponds" -- tiles the BIOME calls ocean (their
## elevation sits below sea level) that the hydrology bake calls neither
## sea nor lake, so the terrain painter gives them plain water tiles while
## the one-water-surface overlay (docs/concept/hydrology.md) paints nothing
## over them: no waterline, no ripples, no flow. Reported live as "there
## are still lakes / ponds which don't use the river water system"
## (2026-09-12). Walks a window of real tiles around a few real places and
## prints how many such tiles there are, in how many connected blobs, with
## sample coordinates.
##
## Usage: godot --headless --path . -s tools/probe_inland_ponds.gd -- [radius_tiles]

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

const PLACES := {
	"Nantes (spawn, Loire)": Vector2(47.2031, -1.5469),
	"Hoek van Holland (Rhine mouth)": Vector2(51.98167, 4.08056),
	"Cologne (Rhine)": Vector2(50.93639, 6.95278),
	"Hamburg (Elbe)": Vector2(53.55, 9.99),
	"Freiburg (Dreisam)": Vector2(47.9990, 7.8421),
	"Regensburg (Danube)": Vector2(49.017, 12.083),
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var radius := 96
	if args.size() > 0 and args[0].is_valid_int():
		radius = int(args[0])
	var generator := EarthChunkGenerator.new()
	print("hydrology bake loaded: %s" % generator.has_hydrology())
	var geo := GeoCoordinates.new()
	var grand_total := 0
	for place in PLACES:
		var coordinate: Vector2 = PLACES[place]
		var center := geo.tile_for_coordinate(
			coordinate.x, coordinate.y, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		)
		var orphans: Dictionary = {}
		var ocean_tiles := 0
		var sea_tiles := 0
		var lake_tiles := 0
		var river_tiles := 0
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var x := center.x + dx
				var y := center.y + dy
				var biome := generator.biome_at_global(x, y)
				var probe := generator.hydrology_at_global(x, y)
				if probe["kind"] == "river":
					river_tiles += 1
				if probe["kind"] == "lake":
					lake_tiles += 1
				if probe.get("sea", false):
					sea_tiles += 1
				if biome != "ocean":
					continue
				ocean_tiles += 1
				if not probe.get("sea", false) and probe["kind"] != "lake":
					orphans[Vector2i(x, y)] = true
		var blobs := _count_blobs(orphans)
		grand_total += orphans.size()
		print(
			"%s: window %dx%d tiles -- ocean-biome %d (bake sea %d, lake %d, river %d); ORPHAN water-by-biome-only tiles: %d in %d blobs"
			% [place, radius * 2 + 1, radius * 2 + 1, ocean_tiles, sea_tiles, lake_tiles, river_tiles, orphans.size(), blobs]
		)
		var shown := 0
		for tile in orphans:
			if shown >= 3:
				break
			var lat := geo.latitude_for_tile(tile.y, EarthChunkGenerator.WORLD_HEIGHT_TILES)
			var lon := geo.longitude_for_tile(tile.x, EarthChunkGenerator.WORLD_WIDTH_TILES)
			print(
				"    sample %s  lat %.4f lon %.4f  macro %.4f (sea level %.4f)  probe kind='%s' sea=%s"
				% [tile, lat, lon, generator.macro_elevation_at_global(tile.x, tile.y), EarthChunkGenerator.EARTH_SEA_LEVEL, probe_kind(generator, tile), str(generator.hydrology_at_global(tile.x, tile.y).get("sea", false))]
			)
			shown += 1
	print("TOTAL orphan tiles across all windows: %d" % grand_total)
	quit()


func probe_kind(generator, tile: Vector2i) -> String:
	return generator.hydrology_at_global(tile.x, tile.y)["kind"]


## Connected components (4-neighbour) of the orphan set, so "how many
## ponds" is a number and not just "how many tiles".
func _count_blobs(tiles: Dictionary) -> int:
	var unvisited := tiles.duplicate()
	var blobs := 0
	while not unvisited.is_empty():
		blobs += 1
		var stack: Array = [unvisited.keys()[0]]
		while not stack.is_empty():
			var tile: Vector2i = stack.pop_back()
			if not unvisited.has(tile):
				continue
			unvisited.erase(tile)
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor: Vector2i = tile + offset
				if unvisited.has(neighbor):
					stack.append(neighbor)
	return blobs
