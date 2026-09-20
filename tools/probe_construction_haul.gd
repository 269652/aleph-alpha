extends SceneTree

## Does a builder really walk to the store and back with the material?
##
## Asked for directly: *"the builders should carry materials to the site"*.
## A headless run paints no pixels, so this needs a real GPU context:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_construction_haul.gd
##
## Runs ONE real ConstructionProject on a real village's own civic plot,
## through the real _sync_construction_worker, and steps the builder for a
## few simulated minutes -- reporting the round in numbers (how far the
## store is, how many loads came in, how his time split between the plot
## and the road) and saving the frames where he is loaded and where he is
## working, at the game's own zoom, so the loaded silhouette can be read
## rather than assumed.

const CHUNK_SIZE := 32
const OUT_DIR := "res://tools/construction_haul_renders"
const VIEW := Vector2i(900, 520)
const SECONDS := 240.0
const FRAME := 1.0 / 60.0

const Player = preload("res://scenes/player.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const ConstructionHaul = preload("res://src/gameplay/construction_haul.gd")

var _manager
var _world: Node2D
var _viewport: SubViewport


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame

	_viewport = SubViewport.new()
	_viewport.size = VIEW
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_world = Node2D.new()
	_world.scale = Player.CAMERA_ZOOM * 0.5
	_viewport.add_child(_world)
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	entities.y_sort_enabled = true
	var creatures := Node2D.new()
	_world.add_child(tile_map_layer)
	_world.add_child(entities)
	_world.add_child(creatures)

	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	_manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
	var chunk_coord := _a_village_chunk()
	if chunk_coord == Vector2i(-99999, -99999):
		print("no village with a store found")
		quit()
		return
	await process_frame

	# The civic plot the finder already cleared for this village.
	var origin: Vector2i = _manager._civic_plot_origin_for(chunk_coord)

	var store_of = _manager.construction_project_store()
	var project = store_of.start_project(chunk_coord, origin, "city_hall", "")
	for item_id in BuildingCatalog.cost_of("city_hall"):
		project.reserved_material[item_id] = float(BuildingCatalog.cost_of("city_hall")[item_id])
	_manager._sync_construction_site(chunk_coord, project)
	_manager._sync_construction_worker(chunk_coord, project, 1.0)
	var worker = _manager._construction_site_workers.get(chunk_coord, {}).get(origin)
	if worker == null:
		print("no builder spawned")
		quit()
		return

	print("village chunk %s, hall site at %s" % [chunk_coord, origin])
	print("reserved: %s  -> %d trips" % [
		project.reserved_material, ConstructionHaul.trips_required(project.reserved_material)
	])
	if worker.depot == null:
		print("NO STORE IN REACH -- he will work the plot (village_warehouse.md pillar 1)")
		var chunk = _manager._loaded_chunks.get(chunk_coord)
		var seen := {}
		if chunk != null:
			for local in chunk.modifications:
				var id: String = chunk.modifications[local]
				seen[id] = int(seen.get(id, 0)) + 1
		print("  what the chunk really holds: %s" % seen)
		print("  loaded chunks: %s" % str(_manager._loaded_chunks.keys()))
		print("  civic plot origin: %s" % str(_manager._civic_plot_origin_for(chunk_coord)))
		print("  entities spawned: %d" % _manager._entities_parent.get_child_count())
	else:
		print("store at %s, %.1f world units from the site (%.1f tiles)" % [
			worker.depot, worker.plot.get_center().distance_to(worker.depot),
			worker.plot.get_center().distance_to(worker.depot) / float(TerrainRenderer.TILE_SIZE)
		])

	var on_the_plot := 0
	var loaded_frames := 0
	var saved_loaded := false
	var saved_working := false
	var last: Vector2 = worker.position
	for i in int(SECONDS / FRAME):
		worker._process(FRAME)
		if i % 600 == 0:
			print("  t=%3ds phase %d at %s, %.1f px from the store, moved %.1f px" % [
				int(float(i) * FRAME), worker._phase, worker.position,
				worker.position.distance_to(worker.depot) if worker.depot != null else -1.0,
				worker.position.distance_to(last)
			])
			last = worker.position
		if worker.plot.has_point(worker.position):
			on_the_plot += 1
		if worker.carried_count > 0.0:
			loaded_frames += 1
		if worker.carried_count > 0.0 and not saved_loaded:
			if worker.position.distance_to(worker.plot.get_center()) > float(TerrainRenderer.TILE_SIZE) * 3.0:
				saved_loaded = true
				await _shoot(worker.position, "loaded")
		if worker.carried_count <= 0.0 and saved_loaded and not saved_working:
			if worker.plot.has_point(worker.position):
				saved_working = true
				await _shoot(worker.plot.get_center(), "working")

	var frames := float(int(SECONDS / FRAME))
	print("over %.0f simulated seconds:" % SECONDS)
	print("  delivered: %s of %s" % [worker.delivered, project.reserved_material])
	print("  %.0f%% of his time on the plot, %.0f%% of it carrying a load" % [
		100.0 * float(on_the_plot) / frames, 100.0 * float(loaded_frames) / frames
	])
	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


func _shoot(centre_px: Vector2, name: String) -> void:
	_world.position = Vector2(VIEW) * 0.5 - centre_px * _world.scale
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var image: Image = _viewport.get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("  saved %s.png at %s" % [name, centre_px])


## A real grassland village that really laid its plaza AND really raised
## its store -- both are needed for the round to have two ends, and
## neither is guaranteed (village_warehouse.md pillar 1's own caveat: a
## cramped site houses its people and goes without). Candidates are LOADED
## to find out, the way the rising-hall tests do, and unloaded again when
## they turn out not to be the one.
func _a_village_chunk() -> Vector2i:
	var SettlementGenerator = load("res://src/world/settlement_generator.gd")
	var BiomeClassifier = load("res://src/world/biome_classifier.gd")
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var generator = SettlementGenerator.new()
	var classifier = BiomeClassifier.new()
	var geo = GeoCoordinates.new()
	var center := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	var tried := 0
	for dy in range(-15, 16):
		for dx in range(-15, 16):
			var coord := center + Vector2i(dx, dy)
			if not generator.has_settlement_at(coord, "grassland"):
				continue
			var chunk = _manager.generator.generate_chunk(coord, CHUNK_SIZE)
			if not generator.has_settlement_at(coord, classifier.dominant_biome(chunk.biome)):
				continue
			tried += 1
			# Persisted chunks are shared with every other run against this
			# user:// dir, so a candidate is scrubbed before it is judged.
			_scrub_chunk(coord)
			_manager._load_chunk(coord)
			# Founding raises the hall outright now, so the plot a site
			# would stand on is occupied until it is lifted -- exactly what
			# the rising-hall tests do to get a village back to the state a
			# plaza is in before any hall exists.
			_clear_the_founded_hall(coord)
			var plot_origin = _manager._civic_plot_origin_for(coord)
			var store = null
			if plot_origin != null:
				var centre := (
					Vector2(coord * CHUNK_SIZE + plot_origin) + Vector2.ONE
				) * float(TerrainRenderer.TILE_SIZE)
				store = _manager._construction_store_near(centre)
			print("  %s: plaza %s, store %s" % [
				coord, "yes" if plot_origin != null else "no", "yes" if store != null else "no"
			])
			if plot_origin != null and store != null:
				print("scanned %d villages for one with a plaza and a store" % tried)
				return coord
			_manager._unload_chunk(coord)
			_scrub_chunk(coord)
			if tried >= 40:
				return Vector2i(-99999, -99999)
	return Vector2i(-99999, -99999)


func _scrub_chunk(coord: Vector2i) -> void:
	for path in [
		_manager._modifications_path(coord), _manager._buildings_path(coord),
		_manager._roof_modifications_path(coord), _manager._furniture_modifications_path(coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## The plaza put back the way founding found it: the hall lifted and the
## square's paving re-laid under it (test_earth_chunk_manager_city_hall_
## rising.gd's own _clear_the_founded_hall, verbatim in effect).
func _clear_the_founded_hall(coord: Vector2i) -> void:
	var origin: Vector2i = VillageLayout.skeleton(
		CHUNK_SIZE, VillageLayout.seed_for(coord)
	)["civic_plot"]["origin"]
	if not _manager.remove_building(coord, origin):
		return
	var cells: Array = BuildingCatalog.footprint_cells("city_hall", origin)
	cells.append(origin + BuildingCatalog.doorstep_of("city_hall"))
	for local in cells:
		var g: Vector2i = coord * CHUNK_SIZE + local
		_manager.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)
