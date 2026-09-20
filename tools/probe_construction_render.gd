extends SceneTree

## What a house actually looks like while it is going up.
##
## Reported live with a village raising a cottage: *"it's clipped and
## doesn't use the intermediate construction sprites so you can see the
## progress... also it's scaled improperly"*. A headless run paints no
## pixels, so this needs a real GPU context:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_construction_render.gd
##
## Starts five REAL ConstructionProjects side by side on real ground, one
## per stage of the build, and draws them in one frame through the real
## _sync_construction_site -- so the strip reads left to right as the
## house rising, and any stage cut wrong or drawn at the wrong scale shows
## up against its own neighbours.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const OUT_DIR := "res://tools/construction_stage_renders"
const VIEW := Vector2i(900, 360)
const STAGES: Array[float] = [0.0, 0.25, 0.5, 0.75, 0.99]
const BUILDING_ID := "house_small"

const Player = preload("res://scenes/player.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")


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
	world.scale = Player.CAMERA_ZOOM * 0.5
	viewport.add_child(world)
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	entities.y_sort_enabled = true
	var creatures := Node2D.new()
	world.add_child(tile_map_layer)
	world.add_child(entities)
	world.add_child(creatures)

	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
	var geo = GeoCoordinates.new()
	var tile := Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(tile)
	await process_frame

	var chunk_coord := Vector2i(
		floori(float(tile.x) / CHUNK_SIZE), floori(float(tile.y) / CHUNK_SIZE)
	)
	var footprint := BuildingCatalog.footprint_of(BUILDING_ID)
	var row := _a_clear_row(manager, chunk_coord, footprint, STAGES.size())
	if row.is_empty():
		print("no clear row of %d sites in this chunk" % STAGES.size())
		quit()
		return

	var store = manager.construction_project_store()
	var required: float = ConstructionLabor.labor_hours_required(BUILDING_ID, manager._recipe_book)
	for i in STAGES.size():
		var origin: Vector2i = row[i]
		var project = store.start_project(chunk_coord, origin, BUILDING_ID, "")
		project.labor_hours_accumulated = required * STAGES[i]
		manager._sync_construction_site(chunk_coord, project)
		print("stage %.2f at %s" % [STAGES[i], origin])
	await process_frame

	var first: Vector2i = chunk_coord * CHUNK_SIZE + row[0]
	var last: Vector2i = chunk_coord * CHUNK_SIZE + row[row.size() - 1]
	var centre := (Vector2(first + last) * 0.5 + Vector2(1.0, 1.0)) * float(TerrainRenderer.TILE_SIZE)
	world.position = Vector2(VIEW) * 0.5 - centre * world.scale
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	var image: Image = viewport.get_texture().get_image()
	image.save_png("%s/rising.png" % OUT_DIR)
	print("saved %s/rising.png   left to right: %s" % [OUT_DIR, str(STAGES)])
	_report_sizes(manager, chunk_coord, row)
	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


## Five clear sites in a row, a tile apart, all real buildable ground.
func _a_clear_row(manager, chunk_coord: Vector2i, footprint: Vector2i, count: int) -> Array:
	var pitch := footprint.x + 1
	for y in range(2, CHUNK_SIZE - footprint.y - 2):
		for x in range(2, CHUNK_SIZE - pitch * count - 2):
			var row: Array = []
			for i in count:
				var origin := Vector2i(x + i * pitch, y)
				if not _is_clear(manager, chunk_coord, origin, footprint):
					row.clear()
					break
				row.append(origin)
			if row.size() == count:
				return row
	return []


func _is_clear(manager, chunk_coord: Vector2i, origin: Vector2i, footprint: Vector2i) -> bool:
	for dy in footprint.y + 1:
		for dx in footprint.x:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + origin + Vector2i(dx, dy)
			if not manager.is_buildable_terrain_at(g.x, g.y):
				return false
			if manager.modification_at_global(g.x, g.y) != "":
				return false
	return true


## What each stage is really drawn at -- the "scaled improperly" half of
## the report, in world units rather than by eye.
func _report_sizes(manager, chunk_coord: Vector2i, row: Array) -> void:
	for i in row.size():
		var node = manager._construction_site_nodes.get(chunk_coord, {}).get(row[i])
		if node == null:
			continue
		var sprite: Sprite2D = node.get_node("Stage")
		print("  stage %.2f drawn %.1f x %.1f world units (plot is %d wide)" % [
			STAGES[i], sprite.texture.get_width() * sprite.scale.x,
			sprite.texture.get_height() * sprite.scale.y,
			BuildingCatalog.footprint_of(BUILDING_ID).x * TerrainRenderer.TILE_SIZE,
		])
