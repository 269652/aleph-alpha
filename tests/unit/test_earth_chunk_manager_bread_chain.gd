extends GutTest

## The emergent need, end to end at the real chunk-load boundary (docs/
## concept/milling_and_baking.md, "The emergent need"): a DECLINING
## settlement with spare hands and its own gathered material raises a
## fenced Farm at a real buildable cell, then a Mill, then a Bakery -- in
## that order, at distinct cells -- through the existing SettlementBuild
## Decision / ConstructionProject pipeline; its construction labor advances
## in real time while the player is near; and bread on its own shelves
## counts toward the food that clears the need.
##
## Berlin's real chunk (land, unlike the (0, 0) fixture the sibling fast
## files use) loaded directly via _load_chunk, never update() -- see
## test_earth_chunk_manager.gd's own known-slow-file note -- with every
## disk-persisted modification file for that chunk scrubbed first, since
## tests share one real user:// dir and a leftover "farm" there would make
## the decision name the Mill instead.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementGathering = preload("res://src/emergence/settlement_gathering.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _settlement_id: String


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_chunk_coord = Vector2i(
		floori(float(berlin.x) / EarthChunkManager.CHUNK_SIZE), floori(float(berlin.y) / EarthChunkManager.CHUNK_SIZE)
	)
	_scrub_persisted_chunk()
	manager._load_chunk(_chunk_coord)
	_settlement_id = EntityRef.for_settlement(_chunk_coord)


func after_each():
	_scrub_persisted_chunk()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub_persisted_chunk() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._roof_modifications_path(_chunk_coord),
		manager._furniture_modifications_path(_chunk_coord), manager._upper_floor_modifications_path(_chunk_coord),
		manager._upper_floor_furniture_modifications_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Four non-producer households: no food of their own (DECLINING with an
## empty Market), four spare hands.
func _found_a_hungry_village() -> void:
	var npcs: Array = []
	for i in 4:
		var npc := NpcIdentity.new(100 + i)
		npc.occupation = "blacksmith"
		npcs.append(npc)
	manager.record_settlement_founded_if_new(_chunk_coord, npcs)


func _stock_materials() -> void:
	var market = manager._market_store.market_for(_settlement_id)
	market.add_stock("wood", 60)
	market.add_stock("stone", 30)
	market.add_stock("plant_fibre", 20)


func _active_project(blueprint_id: String):
	for project in manager.construction_project_store().active_projects_in_chunk(_chunk_coord):
		if project.blueprint_id == blueprint_id:
			return project
	return null


func _complete_and_place(project) -> void:
	manager.construction_project_store().complete_project(project.id, manager._household_store)
	manager._place_completed_construction_project(project)


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * EarthChunkManager.CHUNK_SIZE + local


# -- the decision fires, for real, at a real cell ----------------------------

func test_a_hungry_village_with_material_and_spare_hands_starts_a_farm_at_a_real_buildable_cell():
	_found_a_hungry_village()
	_stock_materials()
	assert_eq(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING, "precondition: nothing to eat")

	manager._apply_settlement_build_decision(_chunk_coord)

	var farm = _active_project("farm")
	assert_not_null(farm, "the deepest missing link of bread's chain is the Farm")
	assert_eq(farm.status, ConstructionProject.Status.IN_PROGRESS, "material was on hand, so work began")
	var cell := _global(farm.origin)
	assert_true(manager.is_buildable_terrain_at(cell.x, cell.y), "sited on real buildable ground")
	assert_eq(manager.modification_at_global(cell.x, cell.y), "", "...that nothing already occupies")
	assert_null(_active_project("bakery"), "never a bakery with no flour coming")
	assert_null(_active_project("mill"))


func test_the_same_decision_taken_twice_queues_one_farm_not_two():
	_found_a_hungry_village()
	_stock_materials()
	manager._apply_settlement_build_decision(_chunk_coord)
	manager._apply_settlement_build_decision(_chunk_coord)
	var farms := 0
	for project in manager.construction_project_store().active_projects_in_chunk(_chunk_coord):
		if project.blueprint_id == "farm":
			farms += 1
	assert_eq(farms, 1)


func test_a_well_fed_village_wants_no_farm():
	_found_a_hungry_village()
	_stock_materials()
	manager._market_store.market_for(_settlement_id).add_stock("cooked_meat", 40)  # capacity 10 for 4 households
	manager._apply_settlement_build_decision(_chunk_coord)
	assert_null(_active_project("farm"), "no food need, nothing to raise")


# -- completion places a FENCED farm, and the chain climbs -------------------

func test_a_completed_farm_project_places_a_fenced_farm_that_a_farmer_moves_into():
	_found_a_hungry_village()
	_stock_materials()
	manager._apply_settlement_build_decision(_chunk_coord)
	var farm = _active_project("farm")

	_complete_and_place(farm)

	var cell := _global(farm.origin)
	assert_eq(manager.modification_at_global(cell.x, cell.y), "farm")
	assert_true(
		manager.has_structure_near(cell.x, cell.y, "wooden_fence", 1),
		"a village raises a fenced plot in one go -- the Farm's own gate rule needs it"
	)
	assert_true(manager._farm_farmers.get(_chunk_coord, {}).has(farm.origin), "...so its Farmer moved in")


func test_the_chain_climbs_farm_then_mill_then_bakery_at_distinct_cells():
	_found_a_hungry_village()
	_stock_materials()
	var cells := {}
	for expected in ["farm", "mill", "bakery"]:
		manager._apply_settlement_build_decision(_chunk_coord)
		var project = _active_project(expected)
		assert_not_null(project, "next link to raise: %s" % expected)
		if project == null:
			return
		var cell := _global(project.origin)
		assert_false(cells.has(cell), "%s must not be stamped over an earlier link" % expected)
		cells[cell] = true
		_complete_and_place(project)
		assert_eq(manager.modification_at_global(cell.x, cell.y), expected)

	manager._apply_settlement_build_decision(_chunk_coord)
	assert_true(
		manager.construction_project_store().active_projects_in_chunk(_chunk_coord).is_empty(),
		"the whole chain stands; bread is now a matter of time, not construction"
	)


# -- material and labor accrue in real time while the player is near --------

func test_spare_hands_gather_building_material_between_assessments():
	_found_a_hungry_village()
	var market = manager._market_store.market_for(_settlement_id)
	assert_eq(market.stock_of("wood"), 0, "precondition")

	for i in 8:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_gt(market.stock_of("wood"), 0, "a village with idle hands cuts its own timber")
	assert_gt(market.stock_of("stone"), 0)
	assert_gt(market.stock_of("plant_fibre"), 0)


func test_construction_labor_advances_while_the_player_is_near_not_only_on_reload():
	_found_a_hungry_village()
	_stock_materials()
	manager._apply_settlement_build_decision(_chunk_coord)
	var farm = _active_project("farm")
	assert_almost_eq(farm.labor_hours_accumulated, 0.0, 0.0001, "precondition")

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_gt(farm.labor_hours_accumulated, 0.0, "the settlement kept building while loaded")


func test_enough_loaded_time_completes_the_farm_and_places_it():
	_found_a_hungry_village()
	_stock_materials()
	manager._apply_settlement_build_decision(_chunk_coord)
	var farm = _active_project("farm")
	var cell := _global(farm.origin)

	for i in 200:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		if farm.status == ConstructionProject.Status.COMPLETE:
			break

	assert_eq(farm.status, ConstructionProject.Status.COMPLETE)
	assert_eq(manager.modification_at_global(cell.x, cell.y), "farm", "and it stands in the world")


# -- bread on the village's own shelves is food the classification sees -----

func test_bread_in_a_storage_lifts_the_settlement_out_of_declining():
	_found_a_hungry_village()
	assert_eq(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING)
	var storage := _global(Vector2i(12, 12))
	manager.build_at_global(storage.x, storage.y, "storage")
	manager.deposit_to_structure_at(storage.x, storage.y, "bread", 40)
	assert_ne(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING)
