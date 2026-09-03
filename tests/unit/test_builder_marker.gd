extends GutTest

## BuilderMarker: the engine glue for a Builder worker (see docs/concept/
## timber_construction.md's NPC construction section -- the Lumberjack's own
## loop stops at DEPOSIT; this is CARRY_MATERIAL/PLACE_PIECE). Mirrors
## LogisticsMarker's own engine-level test shape: a real EarthChunkManager, a
## real Storage with real deposited stock, then real ticks until the real
## world state (modification_at_global, structure_stock_at, the real
## ConstructionProject/HouseholdStore) reflects the whole loop having run.
##
## `target_pieces` is injected directly (a bare, generic worker -- see
## builder_marker.gd's own header for why no live ConstructionProject-lookup
## spawner exists yet).
##
## This real EarthChunkManager loads/persists real disk state for the exact
## real-world Berlin tile every test below anchors on (EarthChunkManager.
## _load_chunk reads user://chunk_modifications/<chunk>.bin on ANY chunk
## load, not just a reload) -- state that is NEVER cleared between separate
## Godot process invocations, and (user:// is keyed only by the Godot
## project name, not by checkout path) is the SAME real directory every git
## worktree on this machine shares. test_earth_chunk_manager.gd's own
## "moving far away unloads" tests deliberately persist real modifications
## for this SAME coordinate. before_each/after_each below scrub exactly this
## file's own real chunk_coord (never the whole shared directory) before
## trusting/leaving a fresh EarthChunkManager, so a previous full-suite run
## or a concurrent session elsewhere can never leak into these assertions --
## see _forget_persisted_berlin_chunk and
## test_a_stale_persisted_modification_from_an_earlier_process_does_not_leak_in.

const BuilderMarker = preload("res://src/rendering/builder_marker.gd")
const BuilderBehavior = preload("res://src/gameplay/builder_behavior.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const ChunkSerializer = preload("res://src/world/chunk_serializer.gd")

var manager: EarthChunkManager
var marker: BuilderMarker
var project_store: ConstructionProjectStore
var household_store: HouseholdStore
var _berlin_tile: Vector2i
var _chunk_coord: Vector2i
var _origin: Vector2i
var _geo_coordinates := GeoCoordinates.new()
var _tile_map_layer: TileMapLayer
var _entities_parent: Node2D
var _creatures_parent: Node2D


func before_all():
	# Simulates exactly what a PRIOR, unrelated process can really leave
	# behind at this file's own real-world Berlin tile -- EarthChunkManager.
	# _unload_chunk persists modifications here the SAME way, for real (see
	# this file's own header). Runs ONCE, before the very first before_each
	# below, so every test in this file proves its own fixture starts clean
	# regardless of whatever was already sitting on disk when this process
	# launched.
	var berlin_tile := Vector2i(
		_geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		_geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	var chunk_coord := _berlin_chunk_coord()
	var local_cell := berlin_tile - chunk_coord * BuilderMarker.CHUNK_SIZE
	DirAccess.make_dir_recursive_absolute(EarthChunkManager.MODIFICATIONS_DIR)
	ChunkSerializer.new().save_modifications(
		{local_cell: "wood_wall"},
		"%s/%d_%d.bin" % [EarthChunkManager.MODIFICATIONS_DIR, chunk_coord.x, chunk_coord.y]
	)


func after_all():
	_forget_persisted_berlin_chunk()


func before_each():
	_tile_map_layer = TileMapLayer.new()
	_entities_parent = Node2D.new()
	_creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(_tile_map_layer, _entities_parent, _creatures_parent)
	_berlin_tile = Vector2i(
		_geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		_geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)

	# local_cell Vector2i(0, 0) resolves to exactly _berlin_tile -- see
	# _global_cell_for's own "chunk_coord * CHUNK_SIZE + origin + local_cell"
	# contract. Computed BEFORE manager.update() below (pure geometry, no
	# dependency on it) so _forget_persisted_berlin_chunk can scrub real
	# disk state for exactly this real-world tile first.
	_chunk_coord = Vector2i(
		floori(float(_berlin_tile.x) / float(BuilderMarker.CHUNK_SIZE)),
		floori(float(_berlin_tile.y) / float(BuilderMarker.CHUNK_SIZE))
	)
	_origin = _berlin_tile - _chunk_coord * BuilderMarker.CHUNK_SIZE

	_forget_persisted_berlin_chunk()
	manager.update(_berlin_tile)

	project_store = ConstructionProjectStore.new()
	household_store = HouseholdStore.new()

	marker = BuilderMarker.new()
	marker.earth = manager
	marker.project_store = project_store
	marker.household_store = household_store
	marker.position = Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	add_child_autofree(marker)


func after_each():
	_tile_map_layer.free()
	_entities_parent.free()
	_creatures_parent.free()
	# Mirrors before_each's own scrub -- this test's own real
	# EarthChunkManager never triggers a real unload itself today (a single
	# update() call, never re-centered), so it never writes here, but a
	# future test added to this file that DOES move the load center must not
	# leak real state forward into whatever runs against this SAME
	# real-world tile next.
	_forget_persisted_berlin_chunk()


## The real-world Berlin tile's own chunk_coord -- pure geometry, no
## EarthChunkManager dependency, so before_all/before_each/after_each can all
## reach it without needing a live manager instance first.
func _berlin_chunk_coord() -> Vector2i:
	var berlin_tile := Vector2i(
		_geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		_geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	return Vector2i(
		floori(float(berlin_tile.x) / float(BuilderMarker.CHUNK_SIZE)),
		floori(float(berlin_tile.y) / float(BuilderMarker.CHUNK_SIZE))
	)


## Removes REAL persisted modifications/roof_modifications/planted_trees for
## the real-world Berlin chunk this whole file anchors on -- narrow ON
## PURPOSE (never the whole shared user://chunk_modifications directory) so
## a concurrent session's own real-world tile elsewhere is never touched by
## this file's own tests. Safe to call whether or not anything is actually
## there (FileAccess.file_exists guards each real path). See this file's own
## header for why this exists.
func _forget_persisted_berlin_chunk() -> void:
	var chunk_coord := _berlin_chunk_coord()
	for dir in [
		EarthChunkManager.MODIFICATIONS_DIR,
		EarthChunkManager.ROOF_MODIFICATIONS_DIR,
		EarthChunkManager.PLANTED_TREES_DIR,
	]:
		# Mirrors EarthChunkManager's own private _modifications_path/
		# _roof_modifications_path/_planted_trees_path exactly -- all three
		# use this SAME "%d_%d.bin" naming (see that file).
		var path := "%s/%d_%d.bin" % [dir, chunk_coord.x, chunk_coord.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Regression coverage for this file's own header note: before_all above
## persists a real, disk-backed "wood_wall" modification at this exact
## real-world tile ONCE, before the very first before_each -- proving every
## fresh fixture below (this test included) starts from a real clean slate
## regardless, the same as if some OTHER process/worktree had left it there.
func test_a_stale_persisted_modification_from_an_earlier_process_does_not_leak_in():
	assert_eq(
		manager.modification_at_global(_berlin_tile.x, _berlin_tile.y), "",
		"before_each must scrub whatever a PRIOR process really persisted at this exact real-world tile before trusting a freshly loaded chunk"
	)


func _new_project(household_id: String, blueprint_id: String = "storage") -> ConstructionProject:
	var project := project_store.start_project(_chunk_coord, _origin, blueprint_id, household_id)
	project.status = ConstructionProject.Status.IN_PROGRESS
	return project


func test_joins_the_builder_group():
	assert_true(marker.is_in_group(BuilderMarker.GROUP_NAME))


func test_chunk_size_matches_earth_chunk_manager():
	assert_eq(BuilderMarker.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE)


func test_stays_seeking_with_nothing_injected():
	for i in 10:
		marker._process(1.0)
	assert_eq(marker._behavior.phase, BuilderBehavior.Phase.SEEKING)


func test_stays_seeking_when_no_storage_exists():
	var household := household_store.form_household("npc:1")
	marker.target_project = _new_project(household.id)
	marker.target_pieces = {Vector2i(0, 0): "timber_floor"}
	for i in 20:
		marker._process(1.0)
	assert_eq(marker._behavior.phase, BuilderBehavior.Phase.SEEKING)


# -- withdrawal: pulls the SPECIFIC piece's own real cost_of material --------

func test_withdrawal_pulls_the_pieces_own_real_cost_from_storage():
	var storage_tile := _berlin_tile + Vector2i(2, 0)
	manager.build_at_global(storage_tile.x, storage_tile.y, "storage")
	manager.deposit_to_structure_at(storage_tile.x, storage_tile.y, "plank", 10)

	var household := household_store.form_household("npc:1")
	marker.target_project = _new_project(household.id)
	# timber_floor costs plank: 2 -- a floor placement never needs adjacency,
	# so this isolates the withdrawal amount from any placement-refusal path.
	marker.target_pieces = {Vector2i(0, 0): "timber_floor"}

	for i in 1200:
		marker._process(0.25)
		if manager.modification_at_global(_berlin_tile.x, _berlin_tile.y) == "timber_floor":
			break

	assert_eq(manager.modification_at_global(_berlin_tile.x, _berlin_tile.y), "timber_floor")
	assert_eq(
		manager.structure_stock_at(storage_tile.x, storage_tile.y, "plank"), 8,
		"exactly the piece's own 2-plank cost was withdrawn, not more, not less"
	)


# -- a refused placement is skipped, never force-placed -----------------------

func test_a_refused_placement_is_skipped_and_its_material_returned_not_force_placed():
	var storage_tile := _berlin_tile + Vector2i(2, 0)
	manager.build_at_global(storage_tile.x, storage_tile.y, "storage")
	manager.deposit_to_structure_at(storage_tile.x, storage_tile.y, "beam", 20)

	var household := household_store.form_household("npc:1")
	marker.target_project = _new_project(household.id)
	# timber_wall needs a floor beneath/beside it -- none exists anywhere
	# near this cell, so BuildingPlacement.can_place must refuse it every
	# single attempt.
	marker.target_pieces = {Vector2i(0, 0): "timber_wall"}

	for i in 1600:
		marker._process(0.25)

	assert_eq(
		manager.modification_at_global(_berlin_tile.x, _berlin_tile.y), "",
		"a refused piece must never be force-placed"
	)
	assert_eq(
		manager.structure_stock_at(storage_tile.x, storage_tile.y, "beam"), 20,
		"every withdrawal for a refused placement is returned to Storage, not lost"
	)


# -- completing every piece drives the real project to COMPLETE --------------

func test_completing_every_piece_completes_the_project_and_grants_the_household_its_property():
	var storage_tile := _berlin_tile + Vector2i(3, 0)
	manager.build_at_global(storage_tile.x, storage_tile.y, "storage")
	manager.deposit_to_structure_at(storage_tile.x, storage_tile.y, "wood", 20)

	var household := household_store.form_household("npc:1")
	var project := _new_project(household.id)
	# A wall one cell NORTH of the floor -- refused on its first attempt
	# (no floor placed yet), then real once the floor lands, exercising the
	# real round-robin retry as part of reaching real completion.
	marker.target_project = project
	marker.target_pieces = {
		Vector2i(0, 0): "wood_floor",
		Vector2i(0, -1): "wood_wall",
	}

	var floor_tile := _berlin_tile
	var wall_tile := _berlin_tile + Vector2i(0, -1)

	for i in 2400:
		marker._process(0.25)
		if project.status == ConstructionProject.Status.COMPLETE:
			break

	assert_eq(manager.modification_at_global(floor_tile.x, floor_tile.y), "wood_floor")
	assert_eq(manager.modification_at_global(wall_tile.x, wall_tile.y), "wood_wall")
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
	assert_eq(household_store.owner_of(project.property_id()), household.id)
	assert_almost_eq(
		project.labor_hours_accumulated,
		ConstructionLabor.labor_hours_required_for_pieces(marker.target_pieces),
		0.001
	)
