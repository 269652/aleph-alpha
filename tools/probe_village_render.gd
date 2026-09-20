extends SceneTree

## What a real village's ground actually LOOKS like -- the question the
## screenshot behind docs/concept/building.md's "The ground a building
## stands on, and the kerb round its plot" asked, answered the same way:
## with a picture, not a test. A headless run paints no pixels, so this
## needs a real GPU context. Run:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_village_render.gd
##
## Streams the REAL EarthChunkManager along the same line
## tools/probe_village_props.gd walks until a settlement with a town hall
## loads, then draws that village into a SubViewport at the game's own
## camera zoom and saves two frames: the hall on its square, and a house
## plot out on the street.
##
## CONFIRMED (2026-09-20): the hall's plot is cobbled continuously into
## the plaza around it -- no seam, no brown square -- and every plot,
## paved or not, carries a visible kerb exactly on its own collision rect.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 30
const OUT_DIR := "res://tools/village_ground_renders"
const VIEW := Vector2i(720, 480)

const Player = preload("res://scenes/player.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")


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
	world.add_child(tile_map_layer)
	world.add_child(entities)
	world.add_child(creatures)

	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
	var geo = GeoCoordinates.new()
	var origin := Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)

	var village := {}
	for step in STEPS:
		manager.update(origin + Vector2i(step * CHUNK_SIZE, 0))
		await process_frame
		village = _village_with_a_hall(manager)
		if not village.is_empty():
			break
	if village.is_empty():
		print("no settlement with a hall found in %d steps" % STEPS)
		quit()
		return

	# Settle on the village itself so nothing of it is half-streamed.
	for i in 3:
		manager.update(village["hall_tile"])
		await process_frame

	for shot in [
		{"name": "hall_on_the_square", "tile": village["hall_tile"]},
		{"name": "house_on_the_street", "tile": village["house_tile"]},
	]:
		var centre := Vector2(shot["tile"]) * float(TerrainRenderer.TILE_SIZE)
		world.position = Vector2(VIEW) * 0.5 - centre * world.scale
		RenderingServer.force_draw()
		await process_frame
		RenderingServer.force_draw()
		var image: Image = viewport.get_texture().get_image()
		var path := "%s/%s.png" % [OUT_DIR, shot["name"]]
		image.save_png(path)
		print("saved %s   centred on tile %s" % [path, shot["tile"]])

	print("village chunk %s  hall %s  house %s" % [
		village["chunk_coord"], village["hall_tile"], village["house_tile"]
	])
	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


## The first loaded chunk carrying a real town hall, with the hall's own
## centre tile and the centre tile of a dwelling standing away from it.
func _village_with_a_hall(manager) -> Dictionary:
	for chunk_coord in manager._loaded_chunks:
		var hall := {}
		var house := {}
		for record in manager.buildings_in_chunk(chunk_coord):
			if record["id"] == "city_hall":
				hall = record
			elif BuildingCatalog.capacity_of(record["id"]) > 0 and house.is_empty():
				house = record
		if hall.is_empty() or house.is_empty():
			continue
		return {
			"chunk_coord": chunk_coord,
			"hall_tile": _centre_tile(chunk_coord, hall),
			"house_tile": _centre_tile(chunk_coord, house),
		}
	return {}


func _centre_tile(chunk_coord: Vector2i, record: Dictionary) -> Vector2i:
	var footprint := BuildingCatalog.footprint_of(record["id"])
	return chunk_coord * CHUNK_SIZE + record["origin_local"] + footprint / 2
