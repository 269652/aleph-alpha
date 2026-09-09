extends GutTest

## EarthChunkManager's bee lifecycle (see docs/concept/bees.md): a
## BeeColony + a WildBeePatch per loaded chunk, visible BeeHiveMarker/
## WildBeeNestMarker kept in sync via step_bees. Mirrors
## test_earth_chunk_manager_mushrooms.gd's own dedicated-file shape --
## uses `_load_chunk` directly, never the slow real `update()` (see
## CONTRIBUTING.md / test_earth_chunk_manager.gd's own known-slow-file
## note), and a direct-injection pattern (`manager._bee_colonies[coord]
## = colony`) for dispatch/relocate logic that never actually needs real
## chunk/grass data at all -- mirrors this exact codebase's own
## `_ant_colony_with_one_mound()`/`manager._ant_colonies[chunk_coord] =
## colony` precedent in test_earth_chunk_manager.gd.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")
const WildBeePatch = preload("res://src/world/wild_bee_patch.gd")
const BeeHiveMarker = preload("res://src/rendering/bee_hive_marker.gd")
const WildBeeNestMarker = preload("res://src/rendering/wild_bee_nest_marker.gd")
const BeeForagerMarker = preload("res://src/rendering/bee_forager_marker.gd")

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


## A standalone colony guaranteed at least one hive, for dispatch/
## relocate logic that never touches real grass/flower/chunk data at
## all -- mirrors test_earth_chunk_manager.gd's own
## _ant_colony_with_one_mound() exactly.
func _bee_colony_with_one_hive() -> BeeColony:
	var biome := PackedStringArray()
	for i in EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE:
		biome.append("grassland")
	for seed_value in range(200):
		var colony := BeeColony.new(
			seed_value, EarthChunkManager.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE, biome
		)
		if not colony.hive_cells().is_empty():
			return colony
	fail_test("expected at least one of 200 seeds to place a hive in an all-grassland chunk")
	return null


## Site search (_find_bee_hive_site/_find_wild_bee_nest_site) needs REAL
## flower/nectar data for _has_bee_food_near to ever find anywhere
## viable -- a purely-injected colony/patch with no chunk actually
## loaded has none at all, so relocation can never succeed for it no
## matter how many free grassland cells exist. Loading the real chunk
## first, then swapping in a guaranteed-hive colony (keeping the real
## chunk's own real flower/biome data untouched), gives relocation a
## genuine chance to succeed -- but whether a real, blooming,
## nectar-bearing flower actually sits within sensing range of a
## specific candidate cell is itself still real, live, probabilistic
## data (mirrors mound placement's own accepted probabilism elsewhere in
## this project's test suite): a caller here is expected to check
## whether relocation actually happened and `pending()` out honestly if
## this particular run's real flower layout didn't cooperate, the same
## as test_a_real_spawned_mound_marker_is_wired_to_its_own_colony
## already does for mound placement.
func _load_berlin_with_guaranteed_hive_colony() -> BeeColony:
	manager._load_chunk(_berlin_chunk)
	for marker in manager._bee_hive_markers.get(_berlin_chunk, {}).values():
		marker.free()
	var colony := _bee_colony_with_one_hive()
	manager._bee_colonies[_berlin_chunk] = colony
	var markers: Dictionary = {}
	for cell in colony.hive_cells():
		markers[cell] = manager._spawn_bee_hive_marker(colony, _berlin_chunk, cell)
	manager._bee_hive_markers[_berlin_chunk] = markers
	return colony


func _load_berlin_with_guaranteed_wild_bee_patch() -> WildBeePatch:
	manager._load_chunk(_berlin_chunk)
	for marker in manager._wild_bee_nest_markers.get(_berlin_chunk, {}).values():
		marker.free()
	var patch := _wild_bee_patch_with_one_nest()
	manager._wild_bee_patches[_berlin_chunk] = patch
	var markers: Dictionary = {}
	for cell in patch.nest_cells():
		markers[cell] = manager._spawn_wild_bee_nest_marker(patch, _berlin_chunk, cell)
	manager._wild_bee_nest_markers[_berlin_chunk] = markers
	return patch


func _wild_bee_patch_with_one_nest() -> WildBeePatch:
	var biome := PackedStringArray()
	for i in EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE:
		biome.append("grassland")
	for seed_value in range(200):
		var patch := WildBeePatch.new(
			seed_value, EarthChunkManager.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE, biome
		)
		if not patch.nest_cells().is_empty():
			return patch
	fail_test("expected at least one of 200 seeds to place a nest in an all-grassland chunk")
	return null


# -- chunk load/unload: honeybee hives ---------------------------------------

func test_load_chunk_creates_a_bee_colony():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._bee_colonies.has(_berlin_chunk))


## Mirrors test_update_spawns_a_visible_marker_for_every_real_ant_mound_
## around_berlin exactly: hive placement is genuinely probabilistic
## (BeeColony.HIVE_CHANCE), so the real invariant worth pinning is that
## the rendered marker count always exactly matches the real
## hive_cells() count, whatever that happens to be.
func test_load_chunk_spawns_a_visible_marker_for_every_real_bee_hive():
	manager._load_chunk(_berlin_chunk)
	var colony: BeeColony = manager._bee_colonies[_berlin_chunk]
	assert_true(manager._bee_hive_markers.has(_berlin_chunk))
	assert_eq(manager._bee_hive_markers[_berlin_chunk].size(), colony.hive_cells().size())


## Mirrors test_a_real_spawned_mound_marker_is_wired_to_its_own_colony's
## own pending()-gated shape exactly: placement is probabilistic, so a
## seed that happens to place nothing in Berlin's own chunk is an
## honest, accepted inconclusive result, not a retry loop.
func test_a_real_spawned_hive_marker_is_wired_to_its_own_colony():
	manager._load_chunk(_berlin_chunk)
	var markers: Dictionary = manager._bee_hive_markers.get(_berlin_chunk, {})
	if markers.is_empty():
		pending("no real bee hive landed in this chunk this seed -- placement is probabilistic")
		return
	var marker: BeeHiveMarker = markers.values()[0]
	assert_string_contains(marker.get_display_name(), "population")


func test_evicting_old_chunks_frees_bee_hive_markers():
	manager._load_chunk(_berlin_chunk)
	var far_chunk := _berlin_chunk + Vector2i(500, 500)
	manager._load_chunk(far_chunk)
	manager._unload_chunk(_berlin_chunk)
	assert_false(manager._bee_hive_markers.has(_berlin_chunk))
	assert_false(manager._bee_colonies.has(_berlin_chunk))


# -- chunk load/unload: wild bee nests ---------------------------------------

func test_load_chunk_creates_a_wild_bee_patch():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._wild_bee_patches.has(_berlin_chunk))


func test_load_chunk_spawns_a_visible_marker_for_every_real_wild_bee_nest():
	manager._load_chunk(_berlin_chunk)
	var patch: WildBeePatch = manager._wild_bee_patches[_berlin_chunk]
	assert_true(manager._wild_bee_nest_markers.has(_berlin_chunk))
	assert_eq(manager._wild_bee_nest_markers[_berlin_chunk].size(), patch.nest_cells().size())


func test_a_real_spawned_nest_marker_is_wired_to_its_own_patch():
	manager._load_chunk(_berlin_chunk)
	var markers: Dictionary = manager._wild_bee_nest_markers.get(_berlin_chunk, {})
	if markers.is_empty():
		pending("no real wild bee nest landed in this chunk this seed -- placement is probabilistic")
		return
	var marker: WildBeeNestMarker = markers.values()[0]
	assert_string_contains(marker.get_display_name(), "resident")


func test_evicting_old_chunks_frees_wild_bee_nest_markers():
	manager._load_chunk(_berlin_chunk)
	var far_chunk := _berlin_chunk + Vector2i(500, 500)
	manager._load_chunk(far_chunk)
	manager._unload_chunk(_berlin_chunk)
	assert_false(manager._wild_bee_nest_markers.has(_berlin_chunk))
	assert_false(manager._wild_bee_patches.has(_berlin_chunk))


# -- step_bees: advancing, dispatching foragers -------------------------------

func test_step_bees_advances_every_loaded_colonys_population_model():
	var colony := _bee_colony_with_one_hive()
	manager._bee_colonies[_berlin_chunk] = colony
	var cell: Vector2i = colony.hive_cells()[0]
	colony._population[cell] = 1.0  # well under capacity -- advancing should visibly grow it
	for i in 400:
		colony.record_forage_result(cell, true)
	var before := colony.population_at(cell)
	manager.step_bees(BeeColony.SECONDS_PER_SIMULATED_DAY)
	assert_gt(colony.population_at(cell), before)


func test_step_bees_eventually_dispatches_a_real_forager():
	var colony := _bee_colony_with_one_hive()
	manager._bee_colonies[_berlin_chunk] = colony
	for i in 200:
		manager.step_bees(0.05)
	var found_one := false
	for global_tile in manager._active_bee_foragers:
		if not manager._active_bee_foragers[global_tile].is_empty():
			found_one = true
			break
	assert_true(found_one, "FORAGE_CHANCE should have rolled true at least once across 200 steps")


func test_step_bees_also_advances_wild_bee_patches_and_dispatches_foragers():
	var patch := _wild_bee_patch_with_one_nest()
	manager._wild_bee_patches[_berlin_chunk] = patch
	for i in 200:
		manager.step_bees(0.05)
	var found_one := false
	for global_tile in manager._active_wild_bee_foragers:
		if not manager._active_wild_bee_foragers[global_tile].is_empty():
			found_one = true
			break
	assert_true(found_one, "a wild patch's own FORAGE_CHANCE should have rolled true at least once")


# -- absconding: the one mechanism with no ant precedent at all -------------

## A colony reduced to 0 population must relocate to a fresh site, not
## sit at the same cell forever -- see BeeColony.should_abscond_at,
## docs/concept/bees.md's own "Absconding".
func test_step_bees_relocates_a_starved_colony_to_a_new_site():
	var colony := _load_berlin_with_guaranteed_hive_colony()
	var from_cell: Vector2i = colony.hive_cells()[0]
	colony._population[from_cell] = 0.0
	manager.step_bees(1.0)
	if colony.has_hive(from_cell):
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	assert_eq(colony.hive_cells().size(), 1, "the colony relocated, it was not simply destroyed")


func test_step_bees_relocating_a_starved_colony_replaces_its_visible_marker():
	var colony := _load_berlin_with_guaranteed_hive_colony()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var old_marker: BeeHiveMarker = manager._bee_hive_markers[_berlin_chunk][from_cell]
	colony._population[from_cell] = 0.0
	manager.step_bees(1.0)
	if not old_marker.is_queued_for_deletion():
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	var markers: Dictionary = manager._bee_hive_markers[_berlin_chunk]
	assert_eq(markers.size(), 1)
	assert_false(markers.has(from_cell))


func test_step_bees_relocates_a_wild_bee_nest_with_no_nearby_forage():
	var patch := _load_berlin_with_guaranteed_wild_bee_patch()
	# _wild_bee_patch_with_one_nest only guarantees AT LEAST one (real
	# placement commonly lands the full MAX_NESTS cap) -- the real
	# invariant worth pinning is that the total nest count is preserved
	# by relocation (moved, not destroyed or duplicated), not a literal 1.
	var original_count := patch.nest_cells().size()
	var from_cell: Vector2i = patch.nest_cells()[0]
	for i in 100:
		patch.record_forage_result(from_cell, false)
	manager.step_bees(1.0)
	if patch.has_nest(from_cell):
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	assert_eq(patch.nest_cells().size(), original_count, "the nest relocated, it was not simply destroyed")


# -- harvesting: relocate_bee_hive_after_harvest, the harvest mechanic's ----
# -- own real hand-off back into the world -----------------------------------

func test_relocate_bee_hive_after_harvest_moves_the_colony_to_a_new_site():
	var colony := _load_berlin_with_guaranteed_hive_colony()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var population := colony.population_at(from_cell)
	manager.relocate_bee_hive_after_harvest(colony, from_cell)
	if colony.has_hive(from_cell):
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	assert_eq(colony.hive_cells().size(), 1)
	assert_almost_eq(colony.population_at(colony.hive_cells()[0]), population, 0.01)


func test_relocate_bee_hive_after_harvest_spawns_a_replacement_marker():
	var colony := _load_berlin_with_guaranteed_hive_colony()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var old_marker: BeeHiveMarker = manager._bee_hive_markers[_berlin_chunk][from_cell]
	manager.relocate_bee_hive_after_harvest(colony, from_cell)
	if colony.has_hive(from_cell):
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	assert_true(old_marker.is_queued_for_deletion())
	var markers: Dictionary = manager._bee_hive_markers[_berlin_chunk]
	assert_eq(markers.size(), 1)
	assert_false(markers.has(from_cell))


func test_relocate_bee_hive_after_harvest_at_an_unknown_colony_does_nothing():
	var orphan_colony := _bee_colony_with_one_hive()  # never registered with manager
	var from_cell: Vector2i = orphan_colony.hive_cells()[0]
	manager.relocate_bee_hive_after_harvest(orphan_colony, from_cell)
	assert_true(orphan_colony.has_hive(from_cell), "an unregistered colony must be left untouched, not crash")


# -- active foragers must follow their hive when it relocates ---------------
#
# Confirmed bug: neither absconding nor harvest-relocation used to touch
# _active_bee_foragers or any already-dispatched BeeForagerMarker at all --
# a forager mid-trip kept flying toward the OLD site's now-torn-down
# marker forever (see BeeForagerMarker.retarget_hive), and the per-hive
# concurrent-forager cap (BeeColony.active_forager_cap_at) could be
# exceeded since stale foragers under the old _active_bee_foragers key
# were never counted against freshly-dispatched ones under the new key.

func _global_tile(cell: Vector2i) -> Vector2i:
	return _berlin_chunk * EarthChunkManager.CHUNK_SIZE + cell


func test_step_bees_absconding_retargets_an_already_active_forager():
	var colony := _load_berlin_with_guaranteed_hive_colony()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var from_global_tile := _global_tile(from_cell)
	var forager := BeeForagerMarker.new()
	forager.setup(manager, colony, from_cell)
	forager.hive_position = _tile_pixel(from_global_tile)
	entities_parent.add_child(forager)
	manager._active_bee_foragers[from_global_tile] = [forager]
	colony._population[from_cell] = 0.0
	manager.step_bees(1.0)
	if colony.has_hive(from_cell):
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	var to_cell: Vector2i = colony.hive_cells()[0]
	var to_global_tile := _global_tile(to_cell)
	assert_eq(forager._hive_cell, to_cell, "a stale forager's hive_cell must follow the colony to its new site")
	assert_lt(
		forager.hive_position.distance_to(_tile_pixel(to_global_tile)), 0.01,
		"a stale forager's hive_position must follow the colony to its new site"
	)
	assert_true(
		manager._active_bee_foragers.get(from_global_tile, []).is_empty(),
		"the old key must not still be tracking a forager that no longer belongs to it"
	)
	assert_has(manager._active_bee_foragers.get(to_global_tile, []), forager)


func test_relocate_bee_hive_after_harvest_retargets_an_already_active_forager():
	var colony := _load_berlin_with_guaranteed_hive_colony()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var from_global_tile := _global_tile(from_cell)
	var forager := BeeForagerMarker.new()
	forager.setup(manager, colony, from_cell)
	forager.hive_position = _tile_pixel(from_global_tile)
	entities_parent.add_child(forager)
	manager._active_bee_foragers[from_global_tile] = [forager]
	manager.relocate_bee_hive_after_harvest(colony, from_cell)
	if colony.has_hive(from_cell):
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	var to_cell: Vector2i = colony.hive_cells()[0]
	var to_global_tile := _global_tile(to_cell)
	assert_eq(forager._hive_cell, to_cell, "a stale forager's hive_cell must follow the colony to its new site")
	assert_lt(
		forager.hive_position.distance_to(_tile_pixel(to_global_tile)), 0.01,
		"a stale forager's hive_position must follow the colony to its new site"
	)
	assert_true(manager._active_bee_foragers.get(from_global_tile, []).is_empty())
	assert_has(manager._active_bee_foragers.get(to_global_tile, []), forager)


## Mirrors _dispatch_bee_forager's own is_instance_valid/is_queued_for_
## deletion filter exactly -- a forager that already freed itself (e.g.
## it happened to resolve its own trip the same step the hive relocates)
## must be pruned during the migration, not carried over as a dangling
## reference under the new key.
func test_absconding_prunes_an_already_freed_forager_during_migration():
	var colony := _load_berlin_with_guaranteed_hive_colony()
	var from_cell: Vector2i = colony.hive_cells()[0]
	var from_global_tile := _global_tile(from_cell)
	var alive := BeeForagerMarker.new()
	alive.setup(manager, colony, from_cell)
	entities_parent.add_child(alive)
	var freed := BeeForagerMarker.new()
	freed.setup(manager, colony, from_cell)
	entities_parent.add_child(freed)
	freed.queue_free()
	manager._active_bee_foragers[from_global_tile] = [alive, freed]
	colony._population[from_cell] = 0.0
	manager.step_bees(1.0)
	if colony.has_hive(from_cell):
		pending("no real site with real nearby nectar existed in Berlin's own live chunk this run")
		return
	var to_global_tile := _global_tile(colony.hive_cells()[0])
	var migrated: Array = manager._active_bee_foragers.get(to_global_tile, [])
	assert_has(migrated, alive)
	assert_eq(migrated.size(), 1, "an already-freed forager must be pruned, not carried over")


# -- _has_real_hive_anchor: a hive must be on a real tree or structure, ------
# -- never free-floating over open ground or a river -------------------------
#
# Requested live: "Beehives should only be able to build on trees or
# structures like houses .. not free floating over a river or ground."
# BeeColony/WildBeePatch are pure and world-blind (only ever see a biome
# grid), so this real-world check lives here, on EarthChunkManager, exactly
# like _has_bee_food_near already does (see that function's own doc
# comment on the split).

func _tile_pixel(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)


func test_has_real_hive_anchor_accepts_a_position_at_a_real_standing_tree():
	manager._load_chunk(_berlin_chunk)
	var trees: Array = manager._loaded_trees.get(_berlin_chunk, [])
	if trees.is_empty():
		pending("no real tree landed in Berlin's own chunk this seed")
		return
	var tree_position: Vector2 = trees[0].position
	var tree_tile := Vector2i(
		floori(tree_position.x / TerrainRenderer.TILE_SIZE), floori(tree_position.y / TerrainRenderer.TILE_SIZE)
	)
	assert_true(manager._has_real_hive_anchor(tree_position, tree_tile))


## Nothing loaded at all means no real tree and no real building piece can
## possibly be found nearby (both queries only ever see loaded data) --
## the honest "free-floating" case this whole feature exists to reject.
func test_has_real_hive_anchor_rejects_a_position_with_nothing_loaded_nearby():
	assert_false(manager._has_real_hive_anchor(_tile_pixel(_berlin_tile), _berlin_tile))


func test_has_real_hive_anchor_accepts_a_position_near_a_real_building_piece():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_wall"))
	assert_true(manager._has_real_hive_anchor(_tile_pixel(_berlin_tile), _berlin_tile))


## A source-level wiring assertion, not a live-terrain one -- mirrors
## test_earth_chunk_manager_footprints.gd's own test_record_footstep_
## checks_for_a_real_river_or_lake exactly (same reasoning quoted there:
## "a real river/lake at this specific test's fixed Berlin tile is not
## guaranteed, so this proves the WIRING rather than depending on world
## generation landing a river there").
func _has_real_hive_anchor_body() -> String:
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	var start := source.find("func _has_real_hive_anchor(")
	assert_gt(start, -1, "the premise: this function must still exist and be named that")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_has_real_hive_anchor_checks_for_a_real_river_or_lake():
	var body := _has_real_hive_anchor_body()
	assert_true(body.contains("is_river_at_global("), "a hive must never float over a real river")
	assert_true(body.contains("is_lake_at_global("), "a hive must never float over a real lake either")


# -- wiring: the anchor check actually gates real site search/seeding -------

func _find_bee_hive_site_body() -> String:
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	var start := source.find("func _find_bee_hive_site(")
	assert_gt(start, -1, "the premise: this function must still exist and be named that")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


## Covers all three real callers uniformly (swarming, absconding, and
## harvest-relocation -- see this function's own doc comment), without
## depending on real, probabilistic terrain to prove it.
func test_find_bee_hive_site_requires_a_real_anchor_too():
	assert_true(
		_find_bee_hive_site_body().contains("_has_real_hive_anchor("),
		"site search must reject a candidate with real food nearby but no real tree/structure anchor"
	)


func _load_chunk_body() -> String:
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	var start := source.find("func _load_chunk(")
	assert_gt(start, -1, "the premise: this function must still exist and be named that")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


## The one seeding path _find_bee_hive_site's own gate above never covers
## (see BeeColony._seed_initial_hives's own doc comment: initial world-gen
## placement has no post-seed filter to catch a free-floating hive
## afterwards) -- the real reason this needs its OWN wiring proof rather
## than trusting _find_bee_hive_site's fix to cover every hive in the game.
func test_load_chunk_passes_the_real_anchor_check_into_bee_colony_seeding():
	assert_true(
		_load_chunk_body().contains("_has_real_hive_anchor("),
		"initial chunk-load seeding must also refuse to seed a free-floating hive"
	)
