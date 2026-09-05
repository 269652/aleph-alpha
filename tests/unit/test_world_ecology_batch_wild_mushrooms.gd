extends GutTest

## Regression: EarthChunkManager.step_wild_mushrooms/set_mushroom_
## identification are real, tested functions (see
## test_earth_chunk_manager_mushrooms.gd) -- but nothing proves World's own
## per-frame ecology step actually calls them, the exact same "wired but
## never called" trap test_world_ecology_batch_wild_crops.gd already caught
## for wild crops (see that file's own header comment). A wild mushroom
## patch would therefore render on chunk load and then never advance, and
## Player.knows_mushrooms() would never actually reach a real marker, in a
## real play session.
##
## World itself has no direct unit tests (see test_world_persistence.gd's
## own framing). This follows test_world_ecology_batch_wild_crops.gd's exact
## pattern: call the private step directly on an un-added World instance,
## wiring up only the one dependency (_chunk_manager) _step_ecology_batch
## actually reads.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const WildMushroomPatch = preload("res://src/world/wild_mushroom_patch.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")

class TestWorld extends World:
	func _step_reproduction(_delta: float) -> void:
		pass

	func _step_herbivore_food_consumption(_delta: float) -> void:
		pass


var world: TestWorld
var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_chunk: Vector2i


func before_each():
	# Deliberately NOT add_child()'d -- see test_world_persistence.gd.
	world = TestWorld.new()
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	var berlin_tile := Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	manager._load_chunk(_berlin_chunk)
	world._chunk_manager = manager


func after_each():
	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## The case that was broken for wild crops and could just as easily be
## broken here: a real per-frame World ecology batch step must actually
## push the focus player's OWN identification progress into the chunk
## manager, reaching an already-standing marker -- not wait for a respawn.
func test_ecology_batch_pushes_real_identification_onto_a_live_marker():
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	var fruiting: Array = sim.get_fruiting_cells()
	if fruiting.is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return
	var marker = manager._mushroom_markers[_berlin_chunk][fruiting[0]]
	assert_false(marker.identified, "precondition: starts unidentified")

	# Deliberately never add_child()'d -- see class doc comment. Only
	# mushrooms_eaten/knows_mushrooms() are touched, both pure data, no
	# scene-tree dependency.
	var player := PlayerScene.instantiate()
	player.mushrooms_eaten = MushroomSpecies.MUSHROOMS_TO_LEARN_IDENTIFICATION

	world._step_ecology_batch(EarthChunkManager.MUSHROOM_REFRESH_INTERVAL, player)

	assert_true(marker.identified)
	player.free()


## The other real case: step_wild_mushrooms itself must actually be called
## (not just set_mushroom_identification above) -- proven the same way
## test_ecology_batch_advances_a_real_wild_crop_patchs_growth proves its
## own step ran, by observing a real effect only the step produces.
func test_ecology_batch_actually_calls_step_wild_mushrooms():
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	var fruiting: Array = sim.get_fruiting_cells()
	if fruiting.is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return
	var cell: Vector2i = fruiting[0]
	var marker = manager._mushroom_markers[_berlin_chunk][cell]
	sim.pick(cell)

	world._step_ecology_batch(EarthChunkManager.MUSHROOM_REFRESH_INTERVAL, null)

	assert_false(manager._mushroom_markers[_berlin_chunk].has(cell))
	assert_true(marker.is_queued_for_deletion())
