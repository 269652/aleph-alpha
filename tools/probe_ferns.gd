extends SceneTree

## What the ferns actually look like, and whether they really bend
## (docs/concept/ferns.md). Per this codebase's own discipline a headless
## test is not evidence for "what does this look like" -- it needs a real
## GPU context. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . \
##     --rendering-driver opengl3 -s tools/probe_ferns.gd
##
## Streams the REAL EarthChunkManager into the Harz (51.75, 10.60), a
## genuinely wooded chunk -- 573 of its 1024 cells are forest, measured --
## and saves what a player standing in it would see. Then it MEASURES three
## things a picture alone would let you talk yourself into:
##
##   1. that the sheet's painted checkerboard is really gone, by counting
##      how many drawn pixels are the pale grey it keys off;
##   2. that fern cards are on screen at all, by counting green;
##   3. that they BEND, by rendering the same frame twice with a walker
##      standing in different places and diffing -- a card that does not
##      move under a walker is not bending, however good the still looks.
##
## MEASURED (2026-09-20), under xvfb + Mesa software GL, on the Harz chunk:
##
##   ferns             30 on 242 forest cells, 0 in water — 12.4% against
##                     the 12.0% ForestFern.SEED_CHANCE asks for
##   checkerboard      0.00% of drawn pixels, i.e. gone
##   render path       13 bands, 66 instances, every one with its texture
##   the bend          16.0% of the frame moved when a walker stepped in
##
## And one thing the pictures say that no number does: a closed wood seen
## from above is ALL CROWN. The first frame here is what a player really
## sees, and the ferns are almost entirely hidden under the canopy; the
## second lifts the trees so the floor can be checked at all. That is an
## honest fact about a top-down camera in a forest rather than a fault in
## the ferns, and it is recorded rather than quietly cropped out.

const CHUNK_SIZE := 32
const LAT := 51.75
const LON := 10.60
const OUT_DIR := "res://tools/fern_renders"
const VIEW := Vector2i(640, 420)

const Player = preload("res://scenes/player.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ForestFern = preload("res://src/world/forest_fern.gd")

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
	_viewport.transparent_bg = false
	root.add_child(_viewport)

	_world = Node2D.new()
	_world.scale = Player.CAMERA_ZOOM
	_viewport.add_child(_world)
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	entities.y_sort_enabled = true
	var creatures := Node2D.new()
	_world.add_child(tile_map_layer)
	_world.add_child(entities)
	_world.add_child(creatures)

	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
	var geo = GeoCoordinates.new()
	var tile := Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_manager.update(tile)
	await process_frame

	var chunk_coord := Vector2i(
		floori(float(tile.x) / CHUNK_SIZE), floori(float(tile.y) / CHUNK_SIZE)
	)
	var sim = _manager._fern_sims.get(chunk_coord)
	if sim == null:
		print("no fern sim on the chunk at %s" % str(chunk_coord))
		quit()
		return
	var cells: Array = sim.get_patch_cells()
	# What the density really came out at, against what the constant asks
	# for. The seed chance is a share of FOREST cells, and a chunk's own
	# biome array is not the generator's raw answer — water and anything
	# already built are masked out before a fern may take a cell.
	var chunk = _manager._loaded_chunks.get(chunk_coord)
	var wood := 0
	var wet := 0
	for y in chunk.height:
		for x in chunk.width:
			if chunk.biome[y * chunk.width + x] != ForestFern.HOME_BIOME:
				continue
			wood += 1
			var g: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			if _manager.is_water_at_global(g.x, g.y):
				wet += 1
	print("ferns in this chunk: %d on %d forest cells (%d of them water) — %.1f%%, asked for %.1f%%" % [
		cells.size(), wood, wet,
		100.0 * float(cells.size()) / float(maxi(wood - wet, 1)),
		100.0 * ForestFern.SEED_CHANCE,
	])
	if cells.is_empty():
		print("nothing to look at")
		quit()
		return

	# Centre on the densest square of ferns rather than on the chunk's
	# middle, which may be the half of the Harz that is meadow.
	var centre_tile := _densest_tile(cells, chunk_coord)
	# Stream to where the camera is about to look, not just to where it
	# started. Ground cover is filtered to a window around the manager's own
	# disturbance centre (DecorationLod.keeps_decoration_tile) — the first
	# run of this probe pointed the camera at the densest stand while the
	# window stayed on the tile update() was first called with, 22 tiles
	# away, so the only bands built were ones off the bottom of the frame.
	# The picture showed bare floor and the numbers showed 12 live
	# instances, which is what made it obvious.
	_manager.update(centre_tile)
	# ...and re-sync, because update() only re-walks the ground cover on a
	# throttle or a chunk-boundary crossing, and this move is neither.
	_manager._sync_fern_sprites(chunk_coord)
	await process_frame
	print("  window now centred on %s" % str(_manager._disturbance_center_tile))
	_manager.set_wind_strength(1.0)
	var still := await _frame(centre_tile, Vector2(-9999.0, -9999.0))
	still.save_png("%s/ferns.png" % OUT_DIR)
	print("saved %s/ferns.png  centred on tile %s" % [OUT_DIR, str(centre_tile)])
	_report_pixels(still)

	# ...and the same view with the canopy lifted. A closed wood seen from
	# above is all crown: the first render of this probe showed nothing but
	# treetops, which is an honest fact about the camera rather than about
	# the ferns, and it also makes the picture useless for checking the
	# fern art itself. Both frames are kept.
	_hide_trees()
	var floor_view := await _frame(centre_tile, Vector2(-9999.0, -9999.0))
	floor_view.save_png("%s/ferns_no_canopy.png" % OUT_DIR)
	print("saved %s/ferns_no_canopy.png  the same view, canopy lifted" % OUT_DIR)
	_report_pixels(floor_view)

	# The same frame with a walker standing IN it. Anything that moves
	# between the two is the bend, and nothing else changes.
	var walker := (Vector2(centre_tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	var pushed := await _frame(centre_tile, walker)
	pushed.save_png("%s/ferns_walker.png" % OUT_DIR)
	print("saved %s/ferns_walker.png  walker standing at %s" % [OUT_DIR, str(walker)])
	_report_bend(floor_view, pushed)
	_report_bands(chunk_coord, centre_tile)
	_report_brambles(chunk_coord)

	# A bramble is sparse enough (a few per chunk against a fern's thirty)
	# that one is rarely in the same frame as the densest fern stand, so it
	# gets a shot of its own with the canopy already lifted. "Is it drawn
	# correctly" cannot be answered by a picture that does not contain one.
	var bramble_tile := _a_bramble_tile(chunk_coord)
	if bramble_tile != Vector2i.MAX:
		_manager.update(bramble_tile)
		_manager._sync_fern_sprites(chunk_coord)
		_hide_trees()
		var bramble_view := await _frame(bramble_tile, Vector2(-9999.0, -9999.0))
		bramble_view.save_png("%s/bramble.png" % OUT_DIR)
		print("saved %s/bramble.png  centred on a thicket at %s" % [OUT_DIR, str(bramble_tile)])
	print("dumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


## The tile with the most ferns within four tiles of it.
func _densest_tile(cells: Array, chunk_coord: Vector2i) -> Vector2i:
	var best := chunk_coord * CHUNK_SIZE
	var best_count := -1
	for cell in cells:
		var tile: Vector2i = chunk_coord * CHUNK_SIZE + (cell as Vector2i)
		var count := 0
		for other in cells:
			var o: Vector2i = chunk_coord * CHUNK_SIZE + (other as Vector2i)
			if absi(o.x - tile.x) <= 4 and absi(o.y - tile.y) <= 4:
				count += 1
		if count > best_count:
			best_count = count
			best = tile
	print("densest spot: %s with %d ferns within four tiles" % [str(best), best_count])
	return best


func _frame(centre_tile: Vector2i, walker: Vector2) -> Image:
	_manager.set_grass_walker_position(walker)
	var centre := (Vector2(centre_tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
	_world.position = Vector2(VIEW) * 0.5 - centre * _world.scale
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	return _viewport.get_texture().get_image()


## The checkerboard's own pale grey, and green. If the key failed, the
## first number is large and the ferns are pale rectangles; if nothing
## drew, the second is no bigger than the bare forest floor's.
func _report_pixels(image: Image) -> void:
	var checker := 0
	var green := 0
	var total := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var p := image.get_pixel(x, y)
			total += 1
			var lowest: float = minf(p.r, minf(p.g, p.b))
			var highest: float = maxf(p.r, maxf(p.g, p.b))
			if lowest >= 0.78 and highest - lowest <= 0.06:
				checker += 1
			if p.g > p.r and p.g > p.b:
				green += 1
	print("  checkerboard-grey pixels: %d of %d (%.2f%%)" % [
		checker, total, 100.0 * float(checker) / float(maxi(total, 1))
	])
	print("  green pixels:             %d of %d (%.2f%%)" % [
		green, total, 100.0 * float(green) / float(maxi(total, 1))
	])


## A card that does not move under a walker is not bending, however good
## the still looks.
func _report_bend(still: Image, pushed: Image) -> void:
	var moved := 0
	var total := 0
	for y in still.get_height():
		for x in still.get_width():
			total += 1
			if still.get_pixel(x, y).is_equal_approx(pushed.get_pixel(x, y)):
				continue
			moved += 1
	print("  pixels that moved when a walker stepped in: %d of %d (%.2f%%)" % [
		moved, total, 100.0 * float(moved) / float(maxi(total, 1))
	])


## Lifts the canopy for the floor shot. Nothing is unloaded — the trees
## are only made invisible — so every fern keeps the exact position and
## band it had in the shot above, and the two frames are comparable.
func _hide_trees() -> void:
	for chunk_coord in _manager._loaded_trees:
		for tree in _manager._loaded_trees[chunk_coord]:
			if is_instance_valid(tree):
				tree.visible = false


## What the render path actually built. A picture with no ferns in it has
## two very different causes -- nothing was ever handed to a MultiMesh, or
## it was and drew nothing -- and only this tells them apart.
func _report_bands(chunk_coord: Vector2i, centre_tile: Vector2i) -> void:
	var bands: Dictionary = _manager._fern_sprites.get(chunk_coord, {})
	var instances := 0
	for band in bands:
		var mmi: MultiMeshInstance2D = bands[band]
		if mmi.multimesh != null:
			instances += mmi.multimesh.instance_count
	print("  fern bands built: %d, instances in them: %d" % [bands.size(), instances])
	print("  decorates this chunk: %s" % str(_manager._decorates(chunk_coord)))
	print("  disturbance centre tile: %s, view centre: %s" % [
		str(_manager._disturbance_center_tile), str(centre_tile)
	])
	var sim = _manager._fern_sims.get(chunk_coord)
	var shown := 0
	for cell in sim.get_patch_cells():
		var tile: Vector2i = chunk_coord * CHUNK_SIZE + (cell as Vector2i)
		if absi(tile.x - centre_tile.x) <= 6 and absi(tile.y - centre_tile.y) <= 5:
			shown += 1
	print("  ferns inside the camera window: %d" % shown)
	for band in bands:
		var mmi: MultiMeshInstance2D = bands[band]
		print("    band %d at %s, %d instance(s), texture=%s" % [
			band, str(mmi.position),
			0 if mmi.multimesh == null else mmi.multimesh.instance_count,
			"yes" if mmi.texture != null else "NONE",
		])


## The wood's OTHER ground cover, reported from the same run because it
## lives on the same cells and was reported in the same breath:
## *"blackberrys are still not wired and don't grow in forest biome"*.
## Same three questions — is there a sim, does it hold anything, and is
## any of it actually DRAWN.
func _report_brambles(chunk_coord: Vector2i) -> void:
	var BlackberryBramble = load("res://src/world/blackberry_bramble.gd")
	var sim = _manager._bramble_sims.get(chunk_coord)
	if sim == null:
		print("  BRAMBLES: no sim on this chunk at all")
		return
	var chunk = _manager._loaded_chunks.get(chunk_coord)
	var wood := 0
	for y in chunk.height:
		for x in chunk.width:
			if chunk.biome[y * chunk.width + x] == BlackberryBramble.HOME_BIOME:
				wood += 1
	var cells: Array = sim.get_patch_cells()
	var drawn: int = _manager._bramble_sprites.get(chunk_coord, {}).size()
	print("  BRAMBLES: %d on %d forest cells — %.1f%%, asked for %.1f%%; %d drawn" % [
		cells.size(), wood,
		100.0 * float(cells.size()) / float(maxi(wood, 1)),
		100.0 * BlackberryBramble.SEED_CHANCE, drawn,
	])
	for cell in cells:
		var local: Vector2i = cell
		if chunk.biome[local.y * chunk.width + local.x] != BlackberryBramble.HOME_BIOME:
			print("    a bramble at %s is OUT OF THE WOOD" % str(local))


## The global tile of the first thicket in this chunk, or Vector2i.MAX when
## the wood grew none.
func _a_bramble_tile(chunk_coord: Vector2i) -> Vector2i:
	var sim = _manager._bramble_sims.get(chunk_coord)
	if sim == null or sim.get_patch_cells().is_empty():
		return Vector2i.MAX
	return chunk_coord * CHUNK_SIZE + (sim.get_patch_cells()[0] as Vector2i)
