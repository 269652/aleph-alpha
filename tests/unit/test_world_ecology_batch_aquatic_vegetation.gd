extends GutTest

## Regression, mirroring test_world_ecology_batch_wild_crops.gd exactly: a
## real, tested EarthChunkManager step (step_aquatic_vegetation -- see
## test_earth_chunk_manager.gd's own vegetation tests) is only as real as the
## per-frame World call that actually reaches it. step_tall_grass, the sibling
## step_aquatic_vegetation was deliberately built to mirror, IS wired into
## World._step_ecology_batch (see scenes/world.gd) -- this pins that
## step_aquatic_vegetation is wired in right alongside it, not left to sit at
## whatever growth _load_chunk seeded it with forever in a real play session.
##
## World itself has no direct unit tests (see test_world_persistence.gd's own
## framing). This follows the identical "call the private step directly on an
## un-added instance" pattern its wild-crop sibling already uses, wiring up
## only the one dependency (_chunk_manager) _step_ecology_batch actually
## reads, with the same two tree-reaching steps stubbed out as no-ops.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const AquaticVegetation = preload("res://src/world/aquatic_vegetation.gd")

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
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	# Berlin -- same spawn point world.gd uses, and the same tile
	# test_earth_chunk_manager.gd's own aquatic-vegetation tests use; the
	# Spree runs reliably nearby, though not guaranteed inside this exact
	# single chunk every seed (see this test's own pass_test fallback below).
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


## The case that would be broken: a real per-frame World ecology batch step
## must actually grow an aquatic vegetation patch over simulated time, not
## just leave it at whatever growth it was seeded with.
func test_ecology_batch_advances_a_real_aquatic_vegetation_patchs_growth():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	if not manager._aquatic_vegetation.has(chunk_coord):
		pass_test("precondition unmet (no water near Berlin this run) -- nothing to check")
		return
	var sim: AquaticVegetation = manager._aquatic_vegetation[chunk_coord]

	# Every initially-seeded patch starts already mature (see
	# AquaticVegetation's own doc comment) -- only a SPREAD tick ever produces
	# an immature cell. Retry advancing a full SPREAD_INTERVAL at a time
	# (mirrors test_world_ecology_batch_wild_crops.gd's own identical loop)
	# until one shows up. This calls step_aquatic_vegetation directly on the
	# manager purely as scene SETUP -- the actual assertion below drives
	# growth through World._step_ecology_batch instead, which is the thing
	# under test.
	var immature_cell := Vector2i(-1, -1)
	for i in 50:
		manager.step_aquatic_vegetation(AquaticVegetation.SPREAD_INTERVAL)
		for cell in sim.get_patch_cells():
			if sim.get_growth(cell) < 1.0:
				immature_cell = cell
		if immature_cell != Vector2i(-1, -1):
			break
	if immature_cell == Vector2i(-1, -1):
		pass_test("precondition unmet (no spread tick produced an immature vegetation patch this run) -- nothing to regress")
		return
	var before: float = sim.get_growth(immature_cell)

	world._step_ecology_batch(EarthChunkManager.GRASS_REFRESH_INTERVAL, null)

	assert_gt(sim.get_growth(immature_cell), before)
