extends GutTest

## The emergent need, end to end at the real chunk-load boundary (docs/
## concept/milling_and_baking.md, "The emergent need"): a DECLINING
## settlement with spare hands and its own gathered material raises the
## bread chain at real buildable cells, through the existing SettlementBuild
## Decision / ConstructionProject pipeline; its construction labor advances
## in real time while the player is near; and bread on its own shelves
## counts toward the food that clears the need.
##
## It raises that chain from a FARM it did not build. A village never raises
## the Farm placeable itself (SettlementBuildDecision.SETTLEMENT_WILL_NOT_
## RAISE, and docs/concept/npc_farm_production.md's own reversal) -- reported
## live with one standing in a field, *"it just should not spawn this weird
## looking npc with that 3 soil tiles"*. Once a farm really stands there,
## whoever put it down, everything above it in the chain works exactly as it
## always did, which is what most of this file now exercises through the Mill
## instead of the Farm.
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
const Shop = preload("res://src/gameplay/shop.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")
const Market = preload("res://src/emergence/market.gd")

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


## A farm already standing, put there by somebody who is not the village --
## the player, or a plan they raised. The village will not build one, but it
## reasons about the chain above one perfectly well, so this is the
## precondition for every "and then the mill" test below.
func _a_farm_already_stands() -> Vector2i:
	var cell := _global(Vector2i(20, 20))
	manager.build_at_global(cell.x, cell.y, "farm")
	return cell


# -- the decision fires, for real, at a real cell ----------------------------

## Rewritten, not deleted: this used to assert the opposite -- that a hungry
## village with material and spare hands STARTS a farm at a real buildable
## cell -- and that is precisely the spawn reported live. Everything it set
## up is kept, because the point is that a village with every reason and
## every resource to raise one still does not.
func test_a_hungry_village_raises_no_farm_however_badly_it_needs_bread():
	_found_a_hungry_village()
	_stock_materials()
	assert_eq(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING, "precondition: nothing to eat")

	manager._apply_settlement_build_decision(_chunk_coord)

	assert_null(_active_project("farm"), "a village does not build the player's Farm")
	assert_null(_active_project("mill"), "nor anything above one it will never have")
	assert_null(_active_project("bakery"), "never a bakery with no flour coming")


## ...and it is the FARM it refuses, not building in general: give the same
## village a farm it did not raise and the chain above it starts at once.
func test_with_a_farm_standing_the_same_village_raises_the_mill_at_a_real_buildable_cell():
	_found_a_hungry_village()
	_stock_materials()
	_a_farm_already_stands()

	manager._apply_settlement_build_decision(_chunk_coord)

	var mill = _active_project("mill")
	assert_not_null(mill, "the deepest missing link ABOVE the farm is the Mill")
	assert_eq(mill.status, ConstructionProject.Status.IN_PROGRESS, "material was on hand, so work began")
	var cell := _global(mill.origin)
	assert_true(manager.is_buildable_terrain_at(cell.x, cell.y), "sited on real buildable ground")
	assert_eq(manager.modification_at_global(cell.x, cell.y), "", "...that nothing already occupies")
	assert_null(_active_project("bakery"), "never a bakery with no flour coming")


## Re-pointed at the Mill, which is the link a village really does raise --
## the property under test is "one decision taken twice queues one project",
## and it was never about the Farm in particular.
func test_the_same_decision_taken_twice_queues_one_mill_not_two():
	_found_a_hungry_village()
	_stock_materials()
	_a_farm_already_stands()
	manager._apply_settlement_build_decision(_chunk_coord)
	manager._apply_settlement_build_decision(_chunk_coord)
	var mills := 0
	for project in manager.construction_project_store().active_projects_in_chunk(_chunk_coord):
		if project.blueprint_id == "mill":
			mills += 1
	assert_eq(mills, 1)


func test_a_well_fed_village_wants_no_farm():
	_found_a_hungry_village()
	_stock_materials()
	manager._market_store.market_for(_settlement_id).add_stock("cooked_meat", 40)  # capacity 10 for 4 households
	manager._apply_settlement_build_decision(_chunk_coord)
	assert_null(_active_project("farm"), "no food need, nothing to raise")


# -- completion places a FENCED farm, and the chain climbs -------------------

## The FARM project's own completion rule is unchanged and still covered --
## only who starts one moved. The village no longer decides a farm, so this
## starts the project directly, which is what a plan the player raises does
## through the same store.
func test_a_completed_farm_project_places_a_fenced_farm_that_a_farmer_moves_into():
	_found_a_hungry_village()
	_stock_materials()
	# Sited the same way the settlement sites anything -- the first free,
	# buildable, clear cell out from its own centre -- rather than a cell
	# picked by hand that might be water or already occupied.
	var origin = manager._settlement_build_origin_for(_chunk_coord)
	assert_not_null(origin, "precondition: the village has somewhere to build")
	var farm = manager.construction_project_store().start_project(
		_chunk_coord, origin, "farm", "household:bread_chain_test"
	)

	_complete_and_place(farm)

	var cell := _global(farm.origin)
	assert_eq(manager.modification_at_global(cell.x, cell.y), "farm")
	assert_true(
		manager.has_structure_near(cell.x, cell.y, "wooden_fence", 1),
		"a village raises a fenced plot in one go -- the Farm's own gate rule needs it"
	)
	assert_true(manager._farm_farmers.get(_chunk_coord, {}).has(farm.origin), "...so its Farmer moved in")


## Re-pointed: the chain a VILLAGE climbs now starts above the farm. The
## property under test -- each link raised in order, at its own cell, never
## stamped over the last -- is untouched.
func test_with_a_farm_standing_the_chain_climbs_mill_then_bakery_at_distinct_cells():
	_found_a_hungry_village()
	_stock_materials()
	var cells := {_a_farm_already_stands(): true}
	for expected in ["mill", "bakery"]:
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


## Both re-pointed at the Mill for the same reason as the tests above: real
## time advancing a real project is the property, and the Mill is the link a
## village genuinely raises now.
func test_construction_labor_advances_while_the_player_is_near_not_only_on_reload():
	_found_a_hungry_village()
	_stock_materials()
	_a_farm_already_stands()
	manager._apply_settlement_build_decision(_chunk_coord)
	var mill = _active_project("mill")
	assert_almost_eq(mill.labor_hours_accumulated, 0.0, 0.0001, "precondition")

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_gt(mill.labor_hours_accumulated, 0.0, "the settlement kept building while loaded")


func test_enough_loaded_time_completes_the_mill_and_places_it():
	_found_a_hungry_village()
	_stock_materials()
	_a_farm_already_stands()
	manager._apply_settlement_build_decision(_chunk_coord)
	var mill = _active_project("mill")
	var cell := _global(mill.origin)

	for i in 200:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		if mill.status == ConstructionProject.Status.COMPLETE:
			break

	assert_eq(mill.status, ConstructionProject.Status.COMPLETE)
	assert_eq(manager.modification_at_global(cell.x, cell.y), "mill", "and it stands in the world")


# -- bread on the village's own shelves is food the classification sees -----

func test_bread_in_a_storage_lifts_the_settlement_out_of_declining():
	_found_a_hungry_village()
	assert_eq(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING)
	var storage := _global(Vector2i(12, 12))
	manager.build_at_global(storage.x, storage.y, "storage")
	manager.deposit_to_structure_at(storage.x, storage.y, "bread", 40)
	assert_ne(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING)


# -- the merchant's meat is eaten, and the need it masked appears ------------
#
# Reported directly: "the food should be actually consumed and not stay at
# 20 cooked meat." A visited merchant seeds 20 cooked meat into the same
# Market SettlementState counts as the village's food -- five households of
# capacity -- which nobody ever ate and the shop refilled whenever it hit
# zero. Villagers now eat from those stores, and the shop's food is a
# one-time opening inventory: what the village eats is gone until its own
# economy replaces it, so a merchant village comes to be hungry like any
# other.

func test_villagers_eat_the_merchants_meat_until_the_village_is_hungry_again():
	_found_a_hungry_village()
	_stock_materials()
	var market = manager._market_store.market_for(_settlement_id)
	Shop.new().stock_initial_goods(market)
	assert_eq(market.stock_of("cooked_meat"), Market.REFERENCE_STOCK, "precondition: the merchant arrived with meat")
	assert_ne(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING, "precondition: fed by it")
	manager._apply_settlement_build_decision(_chunk_coord)
	assert_null(_active_project("mill"), "precondition: nothing wanted while the meat lasts")

	var here := (Vector2(_global(Vector2i(16, 16))) + Vector2(0.5, 0.5)) * 16.0
	var meals := 0
	for i in 40:
		var wallet := Wallet.new()
		wallet.add(10)
		if manager.buy_village_meal_near(here, wallet) == "cooked_meat":
			meals += 1
	assert_eq(meals, Market.REFERENCE_STOCK, "every portion is a real meal, and then it is gone")
	assert_eq(market.stock_of("cooked_meat"), 0)

	Shop.new().stock_initial_goods(market)  # the player walks past the merchant again
	assert_eq(market.stock_of("cooked_meat"), 0, "the shop does not conjure the meat back")
	assert_eq(manager._settlement_status_for(_settlement_id), SettlementState.DECLINING)
	# The need is real again -- which is the whole point of this test, and
	# what "the food should be actually consumed" was reported about. What
	# the village does with it changed: it raises the chain above a farm it
	# has, and there is none here, so it raises nothing. A village that
	# cannot build its way out of hunger is the named cost of refusing to
	# drop a player's Farm in a field (docs/concept/npc_farm_production.md).
	manager._apply_settlement_build_decision(_chunk_coord)
	assert_null(_active_project("farm"), "still never a Farm, hungry or not")

	_a_farm_already_stands()
	manager._apply_settlement_build_decision(_chunk_coord)
	assert_not_null(_active_project("mill"), "given a farm, it builds the rest for itself")
