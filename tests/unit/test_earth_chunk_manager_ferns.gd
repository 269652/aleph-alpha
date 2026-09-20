extends GutTest

## Ferns, wired into the world (docs/concept/ferns.md). Asked for directly:
## *"can you wire it and make it grow in forest biome"*.
##
## The sim and the renderer are tested on their own; what is pinned here is
## that a loaded chunk really GETS one, that it grows on the world's own
## ecology tick, that a building's floor clears it like every other ground
## cover, and that the wind and the season reach it -- a step nothing calls
## grows nothing, which is a bug this repo has already shipped once with
## wild crops.
##
## Anchored on the Harz (51.75, 10.60), a genuinely wooded chunk -- measured
## 573 of its 1024 cells forest. Berlin's own chunk, which most of these
## suites use, is 29. A fixture with almost no wood in it would pass these
## by accident.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const ForestFern = preload("res://src/world/forest_fern.gd")

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


func _ferns():
	return manager._fern_sims.get(_chunk_coord)


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * EarthChunkManager.CHUNK_SIZE + local


# -- a wood gets ferns -------------------------------------------------------

func test_a_loaded_chunk_carries_a_fern_simulation():
	assert_not_null(_ferns(), "every loaded chunk needs its own fern sim, like its grass one")


func test_a_wood_really_grows_some():
	assert_gt(_ferns().get_patch_cells().size(), 0, "precondition: the Harz chunk is wooded")


func test_every_fern_stands_on_forest_ground():
	var chunk = manager._loaded_chunks.get(_chunk_coord)
	assert_not_null(chunk)
	for cell in _ferns().get_patch_cells():
		var local: Vector2i = cell
		assert_eq(
			chunk.biome[local.y * chunk.width + local.x], ForestFern.HOME_BIOME,
			"a fern at %s is out of the wood" % str(local)
		)


## Nothing grows in water, whatever the biome array says -- the same mask
## every other ground cover on this chunk is handed.
func test_no_fern_stands_in_water():
	for cell in _ferns().get_patch_cells():
		var g := _global(cell)
		assert_false(manager.is_water_at_global(g.x, g.y), "a fern at %s is wading" % str(cell))


# -- they grow on the world's own tick ---------------------------------------

func test_ferns_grow_when_the_world_steps_them():
	var ferns = _ferns()
	var cell := _a_bare_forest_cell()
	assert_true(ferns.plant(cell), "precondition: bare wood floor to plant on")
	var before: float = ferns.get_growth(cell)
	for _tick in 20:
		manager.step_ferns(60.0)
	assert_gt(ferns.get_growth(cell), before, "a step nothing calls grows nothing")


func _a_bare_forest_cell() -> Vector2i:
	var chunk = manager._loaded_chunks.get(_chunk_coord)
	var ferns = _ferns()
	for y in chunk.height:
		for x in chunk.width:
			var cell := Vector2i(x, y)
			if chunk.biome[y * chunk.width + x] != ForestFern.HOME_BIOME:
				continue
			if ferns.has_fern(cell):
				continue
			var g := _global(cell)
			if manager.is_water_at_global(g.x, g.y):
				continue
			return cell
	fail_test("no bare forest cell in this chunk")
	return Vector2i.ZERO


# -- a building's floor grows nothing ---------------------------------------

func test_building_on_a_fern_takes_it_and_keeps_it_gone():
	var ferns = _ferns()
	var cell: Vector2i = ferns.get_patch_cells()[0]
	var g := _global(cell)
	manager.build_at_global(g.x, g.y, "wood_floor")
	assert_false(ferns.has_fern(cell), "the floor took the fern")
	assert_false(ferns.plant(cell), "...and nothing roots through it")


func test_tearing_the_floor_up_gives_the_wood_floor_back():
	var ferns = _ferns()
	var cell: Vector2i = ferns.get_patch_cells()[0]
	var g := _global(cell)
	manager.build_at_global(g.x, g.y, "wood_floor")
	manager.destroy_at_global(g.x, g.y)
	assert_true(ferns.plant(cell), "bare ground again")


func test_a_persisted_floor_keeps_ferns_out_on_reload():
	var cell: Vector2i = _ferns().get_patch_cells()[0]
	var g := _global(cell)
	manager.build_at_global(g.x, g.y, "wood_floor")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	assert_false(_ferns().has_fern(cell), "the reloaded chunk seeded a fern through a floor")


# -- the wind and the season reach them --------------------------------------

func test_the_live_wind_reaches_the_ferns():
	manager.set_wind_strength(2.5)
	assert_almost_eq(
		float(manager._illustrated_ferns.material().get_shader_parameter("wind_strength")),
		2.5, 0.0001, "a wood must sway in the same wind the meadow does"
	)


func test_the_season_tint_reaches_the_ferns():
	manager.set_season_tint(Color(0.6, 0.5, 0.3))
	var tint = manager._illustrated_ferns.material().get_shader_parameter("season_tint")
	assert_almost_eq(float(tint.x), 0.6, 0.0001)
	assert_almost_eq(float(tint.y), 0.5, 0.0001)


func test_the_walker_parts_the_ferns_too():
	manager.set_grass_walker_position(Vector2(123.0, 456.0))
	assert_eq(
		manager._illustrated_ferns.material().get_shader_parameter("player_world_position"),
		Vector2(123.0, 456.0)
	)


# -- and they are freed with the chunk ---------------------------------------

func test_unloading_a_chunk_takes_its_ferns_with_it():
	manager._unload_chunk(_chunk_coord)
	assert_false(manager._fern_sims.has(_chunk_coord))
	assert_false(manager._fern_sprites.has(_chunk_coord))


# -- something eats them ----------------------------------------------------
#
# Asked for directly: *"make ferns grazeable by herbivores"*. The sim has
# had `graze` since it landed and nothing called it — recorded as an
# honest gap in docs/concept/ferns.md rather than left to be discovered.
#
# GRASS FIRST, and that is the whole rule. A fern is what a grazer takes
# when there is nothing better under it: bracken is toxic to livestock and
# most grazers leave it standing while there is grass to be had, and deer
# browse fronds mainly when the grazing is poor. That also fits the model
# ecosystem_dynamics.md already states — *"an animal that can see no bite
# but stands on living ground crops what is under it"* — so this is the
# standing-on-it path, not a new thing to walk to. Nothing seeks a fern
# out.


## A real loaded herbivore, or null when this chunk spawned none.
func _a_herbivore():
	for creature in manager._loaded_creatures.get(_chunk_coord, []):
		if creature.info != null and not creature.info.is_predator:
			return creature
	return null


## A mature fern with no grass standing on the same cell.
func _a_fern_cell_with_no_grass() -> Vector2i:
	var ferns = _ferns()
	var grass = manager._grass_sims.get(_chunk_coord)
	for cell in ferns.get_patch_cells():
		var local: Vector2i = cell
		if ferns.get_growth(local) < 1.0:
			continue
		if grass != null and grass.has_grass(local):
			continue
		return local
	fail_test("no mature fern clear of grass in this chunk")
	return Vector2i.ZERO


func _stand_on(creature, local: Vector2i) -> void:
	var g := _global(local)
	creature.position = Vector2(
		(g.x + 0.5) * 16.0, (g.y + 0.5) * 16.0
	)


func test_a_herbivore_standing_on_a_fern_crops_it():
	var creature = _a_herbivore()
	assert_not_null(creature, "precondition: this wood spawned a herbivore")
	if creature == null:
		return
	var cell := _a_fern_cell_with_no_grass()
	_stand_on(creature, cell)

	manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)

	assert_false(_ferns().has_fern(cell), "the fern at %s was left standing" % str(cell))


## Grass outranks a fern in the code, and that ordering can never actually
## be observed — which is worth pinning, because a reader meeting the
## `elif` will otherwise assume it settles a real contest.
##
## The first version of this test tried to stand mature grass on a fern's
## own cell and failed at its own precondition: `TallGrass.plant` refuses
## anything that is not grassland, and `ForestFern.plant` refuses anything
## that is not forest. The two sims are gated to mutually exclusive biomes,
## so no cell can ever carry both. The ordering is a safety rail, not a
## preference a grazer expresses.
func test_a_cell_is_either_meadow_or_wood_so_the_two_never_compete():
	var ferns = _ferns()
	var grass = manager._grass_sims.get(_chunk_coord)
	assert_not_null(grass, "precondition: the chunk has a grass sim")
	for cell in ferns.get_patch_cells():
		assert_false(
			grass.has_grass(cell as Vector2i),
			"%s carries both a fern and grass, which no biome allows" % str(cell)
		)
	var wood := _a_bare_forest_cell()
	assert_false(grass.plant(wood), "grass does not root in a wood")
	for cell in grass.get_patch_cells():
		assert_false(ferns.plant(cell as Vector2i), "a fern does not root in a meadow")
		break


## A young fern is not a meal, the same rule grass already has: what is
## croppable is what is grown.
func test_a_young_fern_is_not_cropped():
	var creature = _a_herbivore()
	if creature == null:
		return
	var ferns = _ferns()
	var cell := _a_bare_forest_cell()
	assert_true(ferns.plant(cell), "precondition: a young clump to stand on")
	_stand_on(creature, cell)

	manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)

	assert_true(ferns.has_fern(cell), "a shoot is not a mouthful")
