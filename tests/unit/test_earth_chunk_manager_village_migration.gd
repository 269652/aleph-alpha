extends GutTest

## Old-save migration (docs/concept/building.md "Older saves"): a settlement
## chunk that still holds OLD-STYLE piece-built houses (real BuildingPiece
## cells in chunk.modifications, from before whole-building village houses
## existed) has those pieces wiped once on load, and the village then
## regenerates as real whole-building entities in the SAME load -- the exact
## "detect stale state, mutate, persist if changed" shape
## _reclaim_pieces_standing_in_water/_reclaim_buildings_standing_in_water
## already use, run at the same point in _load_chunk. A player-owned piece
## structure (a real, COMPLETE ConstructionProject owned by the player's own
## household) is protected -- never touched by this pass, per
## concept/building.md's own explicit "Legacy" carve-out.
##
## Piece cells are seeded directly into the persisted modifications file
## BEFORE the very first _load_chunk call on a fresh manager, so the chunk
## genuinely looks like an old save on disk rather than something
## spawn_village itself placed this session.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

const CHUNK_SIZE := 32

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _generator := SettlementGenerator.new()
var _biome_classifier := BiomeClassifier.new()
var _chunk_coord: Vector2i

## _find_settlement_chunk's own real-terrain scan (generate_chunk per
## candidate, see its own doc comment) is genuinely expensive -- cached at
## the SCRIPT level (GDScript static vars are shared across every instance
## of this test script for the process's lifetime) so the whole file scans
## exactly once, not once per test. The scan result depends only on
## `manager.generator`/`_generator`, both stateless pure generators built
## identically for every instance, so reusing the first answer for every
## later instance is exact, not an approximation. A separate `_found` flag
## (rather than a magic coordinate sentinel) so a genuine scan FAILURE is
## never mistaken for a cached hit and silently reused by every later test.
static var _cached_chunk_coord: Vector2i
static var _cached_chunk_coord_found := false


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	if not _cached_chunk_coord_found:
		_cached_chunk_coord = _find_settlement_chunk()
		_cached_chunk_coord_found = true
	_chunk_coord = _cached_chunk_coord
	_scrub()


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord),
		manager._roof_modifications_path(_chunk_coord), manager._furniture_modifications_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## has_settlement_at's own hash roll depends only on chunk_coord, never the
## biome argument (it's checked only against _UNINHABITABLE_BIOMES) -- so
## scanning with an ASSUMED biome (as test_village_renderer.gd's own
## identically-named helper does, against a stub world that never asks
## generator for the real one) can find a coordinate whose REAL dominant
## biome is actually uninhabitable, where spawn_village places nothing at
## all. This file drives the real EarthChunkManager end to end, so it
## must confirm the REAL dominant biome the same way _load_chunk itself
## will (generator.generate_chunk + BiomeClassifier.dominant_biome) before
## trusting a candidate -- a real settlement chunk, not merely a
## coordinate that would be one under a hypothetical biome.
##
## generate_chunk is genuinely expensive (real elevation/hydrology/
## vegetation sampling for a whole 32x32 chunk), so it must never be paid
## for on every scanned x -- has_settlement_at("grassland") first, a cheap
## coordinate-only hash roll ("grassland" is never in
## _UNINHABITABLE_BIOMES, so this is a pure pre-filter, never a false
## negative), and only a candidate that ALREADY passes it pays for a real
## chunk generation to confirm the biome that mattered was hypothetical.
##
## An x=0..399 sweep at a fixed latitude is NOT "a wide sample of real
## terrain" -- x is a LONGITUDE tile, so a fixed narrow x range can land
## entirely inside one single ocean at ANY latitude, depending on where
## x=0 itself falls on this world's map. Centered on a real, known,
## non-oceanic coordinate instead (GeoCoordinates.tile_for_longitude/
## latitude, the same conversion test_earth_chunk_manager_buildings.gd's
## own Berlin fixture already relies on) -- real land is contiguous over
## hundreds of kilometers, so a small neighborhood around a real city
## reliably contains a real, hash-confirmed grassland settlement chunk.
##
## This search is also exactly what caught a real, severe production bug
## while this file was first being built: every real settlement chunk
## found this way placed ZERO real buildings (VillageRenderer used to
## stamp a plot's own doorstep as a road cell BEFORE calling
## place_building for that plot, so place_building's real occupancy check
## always refused it over its own front step -- see the "CRITICAL" fix
## commit on this same branch). No terrain-heterogeneity workaround is
## needed here now that the real bug is fixed -- a real, hash-confirmed,
## grassland-biome chunk reliably places real buildings.
func _find_settlement_chunk() -> Vector2i:
	var geo := GeoCoordinates.new()
	var center := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	var radius := 15
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := center + Vector2i(dx, dy)
			if not _generator.has_settlement_at(coord, "grassland"):
				continue
			var chunk := manager.generator.generate_chunk(coord, CHUNK_SIZE)
			var dominant_biome: String = _biome_classifier.dominant_biome(chunk.biome)
			if _generator.has_settlement_at(coord, dominant_biome):
				return coord
	fail_test("no real settlement chunk found within the scanned neighborhood")
	return Vector2i.ZERO


## Every cell of a `size`-cell-square at `origin` is real, dry, buildable
## ground -- checked directly rather than assumed (this codebase's own
## established caution around arbitrary in-chunk coordinates; see
## test_earth_chunk_manager_buildings.gd's own _a_clear_footprint_origin).
## Pure terrain queries only (is_buildable_terrain_at touches nothing but
## `generator`), so this is safe to call before the chunk is ever loaded --
## loading it first would let spawn_village place a real village and
## persist chunk.buildings as non-empty, defeating the "still empty, as an
## old save would have it" precondition every test here needs.
func _is_dry_square(origin: Vector2i, size: int) -> bool:
	for dy in size:
		for dx in size:
			var g: Vector2i = _chunk_coord * CHUNK_SIZE + origin + Vector2i(dx, dy)
			if not manager.is_buildable_terrain_at(g.x, g.y):
				return false
	return true


## The `skip`-th real, dry 2x2 local origin found by a deterministic scan --
## `skip=0` and `skip=1` are guaranteed non-overlapping (the scan stride is
## wider than the 2-cell footprint), so two calls always yield two distinct
## sites in the same chunk.
func _a_dry_local_origin(skip: int) -> Vector2i:
	var found := 0
	for y in range(4, CHUNK_SIZE - 6, 3):
		for x in range(4, CHUNK_SIZE - 6, 3):
			var origin := Vector2i(x, y)
			if _is_dry_square(origin, 2):
				if found == skip:
					return origin
				found += 1
	fail_test("no dry buildable origin #%d found in this chunk" % skip)
	return Vector2i.ZERO


## Seeds chunk.modifications on disk with a trivial 4-piece "house" (two
## walls, a floor, a door) at `origin` -- written directly to the same file
## _load_chunk itself reads, so the first-ever _load_chunk call on this
## manager for this chunk sees genuinely persisted old-style state, not
## anything spawn_village placed this session.
func _seed_old_style_piece_house(origin: Vector2i) -> void:
	var path := manager._modifications_path(_chunk_coord)
	var mods: Dictionary = manager._chunk_serializer.load_modifications(path)
	mods[origin] = "wood_wall"
	mods[origin + Vector2i(1, 0)] = "wood_wall"
	mods[origin + Vector2i(0, 1)] = "wood_floor"
	mods[origin + Vector2i(1, 1)] = "wood_door"
	manager._chunk_serializer.save_modifications(mods, path)


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * CHUNK_SIZE + local


# -- unprotected old-style pieces are wiped, and the village regenerates ----

func test_old_style_piece_house_cells_are_wiped_on_first_load():
	var origin := _a_dry_local_origin(0)
	_seed_old_style_piece_house(origin)

	manager._load_chunk(_chunk_coord)

	for cell in [origin, origin + Vector2i(1, 0), origin + Vector2i(0, 1), origin + Vector2i(1, 1)]:
		var g := _global(cell)
		assert_eq(manager.modification_at_global(g.x, g.y), "", str(cell))


func test_the_village_regenerates_as_real_buildings_in_the_same_load():
	_seed_old_style_piece_house(_a_dry_local_origin(0))
	manager._load_chunk(_chunk_coord)
	assert_false(
		manager.buildings_in_chunk(_chunk_coord).is_empty(),
		"the village should have regenerated as real whole-building entities in the same load"
	)


## A fresh settlement chunk -- never carrying old-style pieces at all -- is
## entirely unaffected: spawn_village's own first-time placement already
## fills chunk.buildings, so the migration gate (buildings already
## non-empty) is a pure no-op here, exactly as intended.
func test_a_chunk_with_no_old_style_pieces_is_unaffected():
	manager._load_chunk(_chunk_coord)
	assert_false(manager.buildings_in_chunk(_chunk_coord).is_empty())


## A second load (the settlement already migrated once) must not re-wipe
## anything -- chunk.buildings is non-empty from the first load, so the
## gate skips real work the exact same way a never-stale chunk does.
func test_a_second_load_after_migration_does_not_touch_the_new_buildings():
	_seed_old_style_piece_house(_a_dry_local_origin(0))
	manager._load_chunk(_chunk_coord)
	var buildings_after_first_load := manager.buildings_in_chunk(_chunk_coord).size()
	assert_gt(buildings_after_first_load, 0, "precondition: migration produced real buildings")

	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)

	assert_eq(manager.buildings_in_chunk(_chunk_coord).size(), buildings_after_first_load)


# -- a player-owned piece house is protected ---------------------------------

## The core protection this pass exists for: a player-owned, COMPLETE
## ConstructionProject's own footprint is never touched, even though its
## pieces are indistinguishable in shape from the "old NPC house" case
## above -- only real ownership tells them apart.
func test_a_player_owned_piece_house_survives_migration():
	var player_origin := _a_dry_local_origin(0)
	_seed_old_style_piece_house(player_origin)
	var household = manager.household_store().form_household(PlayerIdentity.PLAYER_ENTITY_ID)
	var project = manager.construction_project_store().start_project(
		_chunk_coord, player_origin, "small_house", household.id
	)
	manager.construction_project_store().complete_project(project.id, manager.household_store())

	manager._load_chunk(_chunk_coord)

	var g := _global(player_origin)
	assert_eq(manager.modification_at_global(g.x, g.y), "wood_wall", "the player's own house must survive untouched")


## The player's protected house and an unrelated old NPC house can coexist
## in the same chunk -- only the unprotected one is wiped.
func test_an_unrelated_old_npc_house_is_wiped_even_when_the_player_owns_a_different_one_nearby():
	var player_origin := _a_dry_local_origin(0)
	var npc_origin := _a_dry_local_origin(1)
	_seed_old_style_piece_house(player_origin)
	_seed_old_style_piece_house(npc_origin)
	var household = manager.household_store().form_household(PlayerIdentity.PLAYER_ENTITY_ID)
	var project = manager.construction_project_store().start_project(
		_chunk_coord, player_origin, "small_house", household.id
	)
	manager.construction_project_store().complete_project(project.id, manager.household_store())

	manager._load_chunk(_chunk_coord)

	var player_g := _global(player_origin)
	var npc_g := _global(npc_origin)
	assert_eq(manager.modification_at_global(player_g.x, player_g.y), "wood_wall", "protected")
	assert_eq(manager.modification_at_global(npc_g.x, npc_g.y), "", "unprotected, wiped")


## A COMPLETE project belonging to some OTHER household (a different
## villager's own real ConstructionProject, once "One house id" -- see
## docs/progress.md -- grants one) must not protect a cell -- only the
## PLAYER's own household does. Guards against an overly broad "any
## complete project" reading of the protection rule.
func test_a_non_player_households_project_does_not_protect_its_cells():
	var origin := _a_dry_local_origin(0)
	_seed_old_style_piece_house(origin)
	var someone_elses_household = manager.household_store().form_household("npc:999")
	var project = manager.construction_project_store().start_project(
		_chunk_coord, origin, "small_house", someone_elses_household.id
	)
	manager.construction_project_store().complete_project(project.id, manager.household_store())

	manager._load_chunk(_chunk_coord)

	var g := _global(origin)
	assert_eq(manager.modification_at_global(g.x, g.y), "", "only the player's own household protects a site")
