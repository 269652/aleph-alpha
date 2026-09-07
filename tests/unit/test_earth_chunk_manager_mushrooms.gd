extends GutTest

## EarthChunkManager's wild-mushroom lifecycle (see docs/concept/
## mushrooms.md): a WildMushroomPatch per loaded chunk, visible
## MushroomMarkers kept in sync via step_wild_mushrooms.
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note: a single
## `_load_chunk` costs a small fraction of a full `update()`'s radius of
## chunks).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const WildMushroomPatch = preload("res://src/world/wild_mushroom_patch.gd")
const CrushMechanic = preload("res://src/world/crush_mechanic.gd")
const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i
var _berlin_chunk: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	# Berlin -- same real-world spawn tile every other test file in this
	# project uses; reliably inland forest/grassland nearby.
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func test_loading_a_chunk_creates_a_wild_mushroom_patch():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._mushroom_sims.has(_berlin_chunk))
	assert_true(manager._mushroom_sims[_berlin_chunk] is WildMushroomPatch)


func test_loading_a_chunk_spawns_a_marker_per_fruiting_cell():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	assert_true(manager._mushroom_markers.has(_berlin_chunk))
	assert_eq(manager._mushroom_markers[_berlin_chunk].size(), sim.get_fruiting_cells().size())


func test_unloading_a_chunk_frees_its_mushroom_state():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._mushroom_sims.has(_berlin_chunk), "precondition: chunk actually loaded mushroom state")

	manager._unload_chunk(_berlin_chunk)

	assert_false(manager._mushroom_sims.has(_berlin_chunk))
	assert_false(manager._mushroom_markers.has(_berlin_chunk))


func test_step_wild_mushrooms_removes_a_marker_whose_mushroom_was_picked():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	var fruiting: Array = sim.get_fruiting_cells()
	if fruiting.is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return
	var cell: Vector2i = fruiting[0]
	var marker = manager._mushroom_markers[_berlin_chunk][cell]

	sim.pick(cell)
	manager.step_wild_mushrooms(EarthChunkManager.CHUNK_SIZE)  # comfortably past the refresh interval

	assert_false(manager._mushroom_markers[_berlin_chunk].has(cell))
	assert_true(marker.is_queued_for_deletion())


# -- force_mushroom_near: the /mushroom dev-console command's real entry --
# point (see World._handle_mushroom_command) -- see WildMushroomPatch's own
# force_fruit_near for why this needs to exist at all.

func test_force_mushroom_near_spawns_a_real_marker_right_away():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	if sim.site_count() == 0:
		pass_test("precondition unmet (no mushroom site near Berlin this run) -- nothing to check")
		return
	var site: Vector2i = sim.get_site_cells()[0]
	var global_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + site

	var species := manager.force_mushroom_near(global_tile)

	assert_eq(species, sim.species_at(site))
	assert_true(sim.has_fruiting(site))
	assert_true(manager._mushroom_markers[_berlin_chunk].has(site))


func test_force_mushroom_near_returns_empty_string_for_an_unloaded_chunk():
	var far_away_tile := Vector2i(999999, 999999)
	assert_eq(manager.force_mushroom_near(far_away_tile), "")


# -- crush_mushroom_at: the real entry point World._client_process calls --
# (see docs/concept/soil_fauna.md "Crushed underfoot", CrushMechanic).
# Mirrors crush_worm_at's exact three-step shape: resolve the chunk/sim
# from a real pixel position, delegate to the sim, resync markers.

func _pixel_position_for(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE)


## Reported live, art delivered: crushed underfoot now leaves a lingering
## corpse rather than the site going bare instantly (see docs/concept/
## soil_fauna.md's "A corpse is new ground", WildMushroomPatch.is_corpse) --
## this test used to assert the OLD marker-just-vanishes behaviour;
## updated to assert the new one instead of merely dropping the coverage.
func test_crush_mushroom_at_removes_a_fruiting_marker():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	var fruiting: Array = sim.get_fruiting_cells()
	if fruiting.is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return
	var cell: Vector2i = fruiting[0]
	var marker = manager._mushroom_markers[_berlin_chunk][cell]
	var tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + cell

	assert_true(
		manager.crush_mushroom_at(_pixel_position_for(tile), CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S * 10.0)
	)

	assert_false(sim.has_fruiting(cell))
	# The OLD live marker is freed and replaced -- but a crushed corpse now
	# lingers at the same cell rather than the site going bare instantly.
	assert_true(marker.is_queued_for_deletion())
	assert_true(
		manager._mushroom_markers[_berlin_chunk].has(cell),
		"a crushed corpse should still have a marker, not vanish outright"
	)
	assert_eq(manager._mushroom_markers[_berlin_chunk][cell].corpse_kind, "crushed")


func test_crush_mushroom_at_does_nothing_below_threshold():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	var fruiting: Array = sim.get_fruiting_cells()
	if fruiting.is_empty():
		pass_test("precondition unmet (no fruiting site near Berlin this run) -- nothing to check")
		return
	var cell: Vector2i = fruiting[0]
	var tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + cell

	assert_false(manager.crush_mushroom_at(_pixel_position_for(tile), 0.01))
	assert_true(sim.has_fruiting(cell))


func test_crush_mushroom_at_returns_false_for_an_unloaded_chunk():
	assert_false(manager.crush_mushroom_at(_pixel_position_for(Vector2i(999999, 999999)), 1000000.0))


# -- mushrooms_near/take_mushroom_at: a boar's own find-and-eat query -------
# (see docs/concept/mushrooms.md "Animals can find and eat wild mushrooms")
# -- the sight-based FOOD_MUSHROOM sibling to fruit_near/take_fruit_at.
# force_mushroom_near guarantees a real fruiting cell to test against,
# rather than the "precondition unmet" skip the crush tests above use --
# both are real, established patterns in this same file.

func test_mushrooms_near_finds_a_real_fruiting_mushroom():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	if sim.site_count() == 0:
		pass_test("precondition unmet (no mushroom site near Berlin this run) -- nothing to check")
		return
	var site: Vector2i = sim.get_site_cells()[0]
	var global_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + site
	var species := manager.force_mushroom_near(global_tile)
	var pixel := _pixel_position_for(global_tile)

	var found := manager.mushrooms_near(pixel, 8)

	var matching := found.filter(func(f): return f["position"].distance_to(pixel) < 1.0)
	assert_false(matching.is_empty(), "the forced fruiting mushroom should be found nearby")
	assert_eq(matching[0]["species"], species)


func test_mushrooms_near_does_not_find_anything_from_far_away():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	if sim.site_count() == 0:
		pass_test("precondition unmet (no mushroom site near Berlin this run) -- nothing to check")
		return
	var site: Vector2i = sim.get_site_cells()[0]
	var global_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + site
	manager.force_mushroom_near(global_tile)
	var far_pixel := _pixel_position_for(global_tile + Vector2i(500, 500))

	assert_true(manager.mushrooms_near(far_pixel, 8).is_empty())


## A bite is a real bite (see docs/concept/mushrooms.md "Bitten by a
## decomposer") -- distinct from pick()/crush(), it does NOT end the
## fruiting instance. A boar's bite marks the SAME live marker bitten
## (real bitten-look art where delivered) rather than replacing it with a
## corpse, exactly like a decomposer's own bite.
func test_take_mushroom_at_eats_a_real_fruiting_mushroom_and_marks_it_bitten():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	if sim.site_count() == 0:
		pass_test("precondition unmet (no mushroom site near Berlin this run) -- nothing to check")
		return
	var site: Vector2i = sim.get_site_cells()[0]
	var global_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + site
	var species := manager.force_mushroom_near(global_tile)
	var pixel := _pixel_position_for(global_tile)

	var eaten := manager.take_mushroom_at(pixel)

	assert_eq(eaten, species)
	assert_true(sim.has_fruiting(site), "a bite is not a pick or a crush -- it stays fruiting")
	assert_true(sim.is_bitten(site))
	assert_true(
		manager._mushroom_markers[_berlin_chunk][site].bitten,
		"the live marker itself, not just the sim, should show bitten"
	)


## A bigger, mass-scaled eater's bite (see docs/concept/soil_fauna.md's
## "Progressive, mass-scaled bites, and real toxic effects",
## MushroomBiting.bites_per_visit_for) can advance the mushroom's own real
## bite_stage by more than one in a single visit.
func test_take_mushroom_at_accepts_a_bigger_bite_count():
	manager._load_chunk(_berlin_chunk)
	var sim: WildMushroomPatch = manager._mushroom_sims[_berlin_chunk]
	if sim.site_count() == 0:
		pass_test("precondition unmet (no mushroom site near Berlin this run) -- nothing to check")
		return
	var site: Vector2i = sim.get_site_cells()[0]
	var global_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + site
	manager.force_mushroom_near(global_tile)
	var pixel := _pixel_position_for(global_tile)

	manager.take_mushroom_at(pixel, MushroomBiting.MAX_BITE_STAGES)

	assert_eq(manager._mushroom_markers[_berlin_chunk][site].bite_stage, MushroomBiting.MAX_BITE_STAGES)


func test_take_mushroom_at_returns_empty_string_when_nothing_is_there():
	manager._load_chunk(_berlin_chunk)
	assert_eq(manager.take_mushroom_at(_pixel_position_for(_berlin_tile + Vector2i(500, 500))), "")


func test_take_mushroom_at_returns_empty_string_for_an_unloaded_chunk():
	assert_eq(manager.take_mushroom_at(_pixel_position_for(Vector2i(999999, 999999))), "")
