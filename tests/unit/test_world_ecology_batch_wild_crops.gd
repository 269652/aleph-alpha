extends GutTest

## Regression: EarthChunkManager.step_wild_crops is a real, tested function
## (see test_earth_chunk_manager.gd's test_step_wild_crops_advances_growth_
## toward_maturity) -- but World's own per-frame ecology step never actually
## called it, unlike its sibling step_tall_grass, which IS wired into
## World._step_ecology_batch (see scenes/world.gd). A wild crop patch would
## therefore render when a chunk loads and then sit at whatever growth it was
## seeded with forever in a real play session -- only direct test/manager
## calls ever advanced it.
##
## World itself has no direct unit tests (see test_world_persistence.gd's own
## framing: its _ready() builds an entire menu/UI/multiplayer stack that
## assumes the real scene tree, so a bare World.new() is deliberately never
## add_child()'d). This follows the same "call the private step directly on
## an un-added instance" pattern, wiring up only the one dependency
## (_chunk_manager) _step_ecology_batch actually reads.
##
## TestWorld overrides the two reproduction/food-consumption steps
## _step_ecology_batch also calls at the end of its sequence, which reach
## get_tree() -- null and erroring for a node deliberately never added to the
## tree -- with no-ops: they are unrelated to wild crops, and GUT fails a
## test on ANY engine error logged during it (see addons/gut/error_tracker.gd),
## so leaving them live would fail this test for the wrong reason.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const WildCropPatch = preload("res://src/world/wild_crop_patch.gd")

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
var _berlin_tile: Vector2i


func before_each():
	# Deliberately NOT add_child()'d -- see test_world_persistence.gd.
	world = TestWorld.new()
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	# step_ground_food (one of _step_ecology_batch's own steps) reads
	# _entities_parent.get_tree() -- real for the test node itself (GUT adds
	# it to the running tree), so parenting entities_parent under it gives
	# the manager a real tree to find, exactly like
	# test_step_ground_food_ages_an_item_with_an_active_fly_colony_faster
	# does in test_earth_chunk_manager.gd.
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	# Berlin -- same spawn point world.gd uses, and the same tile
	# test_earth_chunk_manager.gd's own wild-crop tests use; reliably inland
	# so the surrounding loaded chunks sustain wild crop patches.
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_berlin_tile)
	world._chunk_manager = manager


func after_each():
	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _chunk_coord_for_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


## The case that was broken: a real per-frame World ecology batch step must
## actually grow a wild crop patch over simulated time, not just leave it at
## whatever growth it was seeded with.
func test_ecology_batch_advances_a_real_wild_crop_patchs_growth():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	if not manager._wild_crop_sims.has(chunk_coord) or not manager._wild_crop_sims[chunk_coord].has("carrot"):
		pass_test("precondition unmet (no carrot patch near Berlin this run) -- nothing to check")
		return
	var sim: WildCropPatch = manager._wild_crop_sims[chunk_coord]["carrot"]

	# Every initially-seeded patch starts already mature (see
	# WildCropPatch._seed_initial_patches's own "Initial crops start mature,
	# like map-generated grass/trees" comment) -- only a SPREAD tick ever
	# produces an immature cell. Retry advancing a full SPREAD_INTERVAL at a
	# time (mirrors test_wild_crop_patch.gd's own
	# test_advance_grows_immature_patches_toward_maturity: a single tick's
	# one spread attempt can land on an ineligible/occupied neighbor and do
	# nothing) until one shows up. This calls step_wild_crops directly on the
	# manager purely as scene SETUP -- the actual assertion below drives
	# growth through World._step_ecology_batch instead, which is the thing
	# under test.
	var immature_cell := Vector2i(-1, -1)
	for i in 50:
		manager.step_wild_crops(WildCropPatch.SPREAD_INTERVAL)
		for cell in sim.get_patch_cells():
			if sim.get_growth(cell) < 1.0:
				immature_cell = cell
		if immature_cell != Vector2i(-1, -1):
			break
	if immature_cell == Vector2i(-1, -1):
		pass_test("precondition unmet (no spread tick produced an immature carrot patch this run) -- nothing to regress")
		return
	var before: float = sim.get_growth(immature_cell)

	world._step_ecology_batch(EarthChunkManager.GRASS_REFRESH_INTERVAL, null)

	assert_gt(sim.get_growth(immature_cell), before)
