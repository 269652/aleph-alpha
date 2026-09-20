extends SceneTree

## What a fisher's dug pond actually LOOKS like -- reported live with a
## screenshot: "The built pond renders as earth instead of water", a fenced
## rectangle of flat brown with the pond's own fish swimming on it.
##
## A headless run paints no pixels, so this needs a real GPU context. Run:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_fisher_pond_render.gd
##
## Streams the REAL EarthChunkManager along the same line
## tools/probe_village_props.gd walks until a settlement digs a pond, wires
## the water surface exactly as scenes/world.gd does (the flow layer inside
## RiverFlowPass's own viewport -- without the pass the layer renders at
## the wrong resolution and the water is not what a player sees), then
## saves the pond and measures its own surface: what share of the pond's
## cells read as WATER rather than as the bare earth the report describes.
##
## MEASURED: see docs/concept/village_ponds.md, "A pond that is actually a
## pond" and the entry that follows it.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 40
const OUT_DIR := "res://tools/fisher_pond_renders"
const VIEW := Vector2i(640, 420)

const Player = preload("res://scenes/player.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const RiverFlowPass = preload("res://src/rendering/river_flow_pass.gd")

var _manager
var _flow_pass := RiverFlowPass.new()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	var viewport := SubViewport.new()
	viewport.size = VIEW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var world := Node2D.new()
	world.scale = Player.CAMERA_ZOOM
	viewport.add_child(world)
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	entities.y_sort_enabled = true
	var creatures := Node2D.new()
	var water_fx := TileMapLayer.new()
	var flow_fx := TileMapLayer.new()
	world.add_child(tile_map_layer)
	world.add_child(water_fx)
	world.add_child(flow_fx)
	world.add_child(entities)
	world.add_child(creatures)

	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
	_manager.set_water_layer(water_fx)
	_manager.set_river_flow_layer(flow_fx)
	_flow_pass.adopt(flow_fx)
	var geo = GeoCoordinates.new()
	var origin := Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)

	var pond: Array = []
	for step in STEPS:
		_manager.update(origin + Vector2i(step * CHUNK_SIZE, 0))
		await process_frame
		pond = _a_dug_pond()
		if not pond.is_empty():
			break
	if pond.is_empty():
		print("no fisher pond found in %d steps" % STEPS)
		quit()
		return

	var centre_tile := _centre_of(pond)
	for i in 3:
		_manager.update(centre_tile)
		await process_frame

	var centre := (Vector2(centre_tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	var view_top_left := centre - Vector2(VIEW) * 0.5 / world.scale.x
	world.position = Vector2(VIEW) * 0.5 - centre * world.scale
	_flow_pass.sync(view_top_left, Vector2(VIEW) / world.scale.x)
	RenderingServer.force_draw()
	await process_frame
	_flow_pass.sync(view_top_left, Vector2(VIEW) / world.scale.x)
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()

	_report_buildings(pond)
	var image: Image = viewport.get_texture().get_image()
	image.save_png("%s/pond.png" % OUT_DIR)
	print("saved %s/pond.png   pond of %d cells centred on tile %s" % [OUT_DIR, pond.size(), centre_tile])
	_report_surface(image, pond, centre, world.scale.x)
	var closeup := image.get_region(Rect2i(VIEW.x / 2 - 120, VIEW.y / 2 - 90, 240, 180))
	closeup.resize(240 * 3, 180 * 3, Image.INTERPOLATE_NEAREST)
	closeup.save_png("%s/pond_closeup.png" % OUT_DIR)
	print("saved %s/pond_closeup.png" % OUT_DIR)
	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


## Every cell of the first dug pond in any loaded chunk, in global tiles.
func _a_dug_pond() -> Array:
	for chunk_coord in _manager._loaded_chunks:
		var chunk = _manager._loaded_chunks[chunk_coord]
		var cells: Array = []
		for local in chunk.modifications:
			if VillagePond.is_pond_tile(chunk.modifications[local]):
				cells.append(chunk_coord * CHUNK_SIZE + (local as Vector2i))
		if not cells.is_empty():
			return cells
	return []


func _centre_of(cells: Array) -> Vector2i:
	var total := Vector2i.ZERO
	for cell in cells:
		total += cell as Vector2i
	return Vector2i(total.x / cells.size(), total.y / cells.size())


## What the pond's own surface reads as, pixel by pixel: water is bluer
## than it is red (every water tone this renderer draws is), earth is the
## other way round. The report was "renders as earth", so the number that
## answers it is the share of the pond's own area that is not.
func _report_surface(image: Image, pond: Array, centre: Vector2, zoom: float) -> void:
	var water := 0
	var dry := 0
	for cell in pond:
		var cell_top_left := Vector2(cell as Vector2i) * float(TerrainRenderer.TILE_SIZE)
		for y in range(2, TerrainRenderer.TILE_SIZE - 2):
			for x in range(2, TerrainRenderer.TILE_SIZE - 2):
				var world_point := cell_top_left + Vector2(x, y)
				var screen := (world_point - centre) * zoom + Vector2(VIEW) * 0.5
				if screen.x < 0 or screen.y < 0 or screen.x >= VIEW.x or screen.y >= VIEW.y:
					continue
				var pixel := image.get_pixel(int(screen.x), int(screen.y))
				if pixel.b > pixel.r:
					water += 1
				else:
					dry += 1
	var total := water + dry
	print("pond surface: %d of %d sampled pixels read as water (%.1f%%), %d as dry ground" % [
		water, total, 0.0 if total == 0 else 100.0 * water / total, dry
	])


## What stands round the water, and how far off -- the other half of the
## report was "it's missing a fisher hut", so the answer is a list of what
## is really there rather than a look at a picture.
func _report_buildings(pond: Array) -> void:
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	for chunk_coord in _manager._loaded_chunks:
		for record in _manager.buildings_in_chunk(chunk_coord):
			var origin: Vector2i = chunk_coord * CHUNK_SIZE + (record["origin_local"] as Vector2i)
			var nearest := INF
			for cell in BuildingCatalog.footprint_cells(record["id"], origin):
				for wet in pond:
					nearest = minf(nearest, Vector2(cell as Vector2i).distance_to(Vector2(wet as Vector2i)))
			if nearest > 6.0:
				continue
			print("  %-12s at %s  %.1f tiles from the water   occupation=%s" % [
				record["id"], origin, nearest, record.get("occupation", ""),
			])
