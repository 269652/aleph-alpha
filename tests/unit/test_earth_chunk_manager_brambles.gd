extends GutTest

## Brambles, wired into the world (docs/concept/brambles.md). Asked for with
## the art dropped in -- *"And I added blackberry.png"* -- and then
## *"Forageable, bearing with the seasons"*.
##
## The sim is tested on its own; what is pinned here is that a loaded chunk
## really GETS one, that it is drawn, and that a building's floor clears it
## like every other ground cover. A sim nothing creates grows nothing, which
## is the bug this repo has already shipped once with wild crops -- and the
## reason its sibling ForestFern has a file just like this one.
##
## Anchored on the Harz (51.75, 10.60), a genuinely wooded chunk -- measured
## 573 of its 1024 cells forest. Berlin's own chunk, which most of these
## suites use, is 29. A fixture with almost no wood in it would pass these
## by accident.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const BlackberryBramble = preload("res://src/world/blackberry_bramble.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var harz := Vector2i(
		geo.tile_for_longitude(10.60, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(51.75, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_chunk_coord = Vector2i(
		floori(float(harz.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(harz.y) / EarthChunkManager.CHUNK_SIZE)
	)
	_scrub()
	manager._load_chunk(_chunk_coord)


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._roof_modifications_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# -- a loaded wood really gets brambles -------------------------------------

func test_a_loaded_chunk_gets_a_bramble_sim():
	assert_true(manager._bramble_sims.has(_chunk_coord), "a wood has brambles in it")


func test_brambles_seed_only_on_this_chunks_forest_cells():
	var sim = manager._bramble_sims[_chunk_coord]
	var chunk = manager._loaded_chunks[_chunk_coord]
	for cell in sim.get_patch_cells():
		assert_eq(
			chunk.biome[cell.y * chunk.width + cell.x], "forest",
			"%s is not wood" % cell
		)


## Scattered where bracken carpets -- the same ordering the sim's own test
## pins, checked here against the REAL chunk both are seeded on rather than
## against a fixture.
func test_a_wood_holds_fewer_brambles_than_ferns():
	assert_lt(
		manager._bramble_sims[_chunk_coord].get_patch_cells().size(),
		manager._fern_sims[_chunk_coord].get_patch_cells().size()
	)


## A sim nothing draws is a sim nobody sees -- the whole of the report this
## work came from was *"not visible"*.
func test_every_bramble_is_really_drawn():
	var sim = manager._bramble_sims[_chunk_coord]
	assert_gt(sim.get_patch_cells().size(), 0, "precondition: this wood has brambles")
	var sprites: Dictionary = manager._bramble_sprites.get(_chunk_coord, {})
	assert_eq(sprites.size(), sim.get_patch_cells().size(), "one sprite per thicket")
	for cell in sim.get_patch_cells():
		assert_not_null(sprites.get(cell), "%s is drawn" % cell)
		assert_not_null(sprites[cell].texture, "...with real art")


## Two brambles in one wood must not be the same picture -- the sheet has
## twenty-five clumps precisely so a thicket is not a repeated stamp.
func test_neighbouring_brambles_do_not_all_wear_the_same_clump():
	var sprites: Dictionary = manager._bramble_sprites.get(_chunk_coord, {})
	var seen := {}
	for cell in sprites:
		seen[sprites[cell].texture.get_rid()] = true
	assert_gt(seen.size(), 1, "a wood is not one bramble stamped over and over")


func test_a_building_clears_the_brambles_under_its_floor():
	var sim = manager._bramble_sims[_chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	sim.block_cells([cell])
	assert_false(sim.has_bramble(cell), "a floor is not a thicket")
