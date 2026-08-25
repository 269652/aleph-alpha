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


func before_each():
	_tile_map_layer = TileMapLayer.new()
	_entities_parent = Node2D.new()
	_creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(_tile_map_layer, _entities_parent, _creatures_parent)
	_berlin_tile = Vector2i(
		_geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		_geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_berlin_tile)

	# local_cell Vector2i(0, 0) resolves to exactly _berlin_tile -- see
	# _global_cell_for's own "chunk_coord * CHUNK_SIZE + origin + local_cell"
	# contract.
	_chunk_coord = Vector2i(
		floori(float(_berlin_tile.x) / float(BuilderMarker.CHUNK_SIZE)),
		floori(float(_berlin_tile.y) / float(BuilderMarker.CHUNK_SIZE))
	)
	_origin = _berlin_tile - _chunk_coord * BuilderMarker.CHUNK_SIZE

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
