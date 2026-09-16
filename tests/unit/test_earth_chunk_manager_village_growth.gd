extends GutTest

## A village grows (docs/concept/village_growth.md): households move in when
## it is fed and has room (VillageImmigration), and whatever VillageGrowth's
## ladder says it owes itself next is queued as a real ConstructionProject
## at a real site and raised over real labour hours -- never stamped into
## existence.
##
## Drives the REAL EarthChunkManager end to end on a real, hash-confirmed
## settlement chunk near Berlin (test_earth_chunk_manager_city_hall_rising.
## gd's own finder, verbatim -- a village that actually laid its plaza, so
## the hall's own decision and this one both have somewhere to act);
## persisted files scrubbed before and after, since tests share one real
## user:// dir.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const VillageImmigration = preload("res://src/emergence/village_immigration.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const SettlementSpareCapacity = preload("res://src/emergence/settlement_spare_capacity.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _settlement_id: String
var _civic_origin: Vector2i

static var _cached_chunk_coord: Vector2i
static var _cached_chunk_coord_found := false

var _generator := SettlementGenerator.new()
var _biome_classifier := BiomeClassifier.new()


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
	_settlement_id = EntityRef.for_settlement(_chunk_coord)
	_civic_origin = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord))["civic_plot"]["origin"]
	_scrub_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)


func after_each():
	_scrub_chunk(_chunk_coord)
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _find_settlement_chunk() -> Vector2i:
	var geo := GeoCoordinates.new()
	var center := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	var loads := 0
	for dy in range(-15, 16):
		for dx in range(-15, 16):
			var coord := center + Vector2i(dx, dy)
			if not _generator.has_settlement_at(coord, "grassland"):
				continue
			var chunk := manager.generator.generate_chunk(coord, CHUNK_SIZE)
			if not _generator.has_settlement_at(coord, _biome_classifier.dominant_biome(chunk.biome)):
				continue
			if not _plaza_terrain_is_open(coord):
				continue
			loads += 1
			_scrub_chunk(coord)
			manager._load_chunk(coord)
			var plot_origin = manager._civic_plot_origin_for(coord)
			manager._unload_chunk(coord)
			_scrub_chunk(coord)
			if plot_origin != null:
				return coord
			if loads >= 12:
				break
	fail_test("no real settlement chunk that laid its plaza found within the scanned neighborhood")
	return Vector2i.ZERO


func _plaza_terrain_is_open(coord: Vector2i) -> bool:
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["plaza"]
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			var g := coord * CHUNK_SIZE + Vector2i(x, y)
			if not manager.is_buildable_terrain_at(g.x, g.y):
				return false
	return true


func _scrub_chunk(coord: Vector2i) -> void:
	for path in [
		manager._modifications_path(coord), manager._buildings_path(coord),
		manager._roof_modifications_path(coord), manager._furniture_modifications_path(coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * CHUNK_SIZE + local


func _market():
	return manager.market_store().market_for(_settlement_id)


## Enough of everything the whole ladder is priced in, so nothing in these
## tests ever waits on stock (SettlementConstruction's own hysteresis is
## already tested where it belongs).
func _stock_everything() -> void:
	var market = _market()
	market.add_stock("wood", 400.0)
	market.add_stock("stone", 200.0)
	market.add_stock("plant_fibre", 200.0)


## The hall stands, so the ladder moves past the rung CivicBuildDecision
## owns and this file can exercise the rungs the growth decision owns.
func _raise_the_hall() -> void:
	manager._place_building_over_roads(_chunk_coord, _civic_origin, "city_hall", 1, _settlement_id)


func _projects_for(building_id: String) -> Array:
	var out: Array = []
	for project in manager.construction_project_store().active_projects_in_chunk(_chunk_coord):
		if project.blueprint_id == building_id:
			out.append(project)
	return out


# -- the ladder is walked in order, behind the hall the civic decision owns

func test_a_village_without_its_hall_yet_queues_no_later_rung():
	_stock_everything()
	manager._apply_village_growth_decision(_chunk_coord)
	for building_id in ["warehouse", "farmhouse", "blacksmith", "brewery"]:
		assert_true(_projects_for(building_id).is_empty(), "%s must wait behind the hall" % building_id)


func test_a_village_with_its_hall_up_queues_the_next_rung_it_is_entitled_to():
	_stock_everything()
	_raise_the_hall()

	manager._apply_village_growth_decision(_chunk_coord)

	var queued: Array = _projects_for("warehouse")
	assert_eq(queued.size(), 1, "the ladder's next rung for a village of this size")
	assert_eq(queued[0].household_id, _settlement_id, "a warehouse is the settlement's own commons")
	assert_eq(queued[0].status, ConstructionProject.Status.IN_PROGRESS, "stocked, so it really started")


func test_a_growth_building_is_sited_fronting_the_villages_own_street():
	_stock_everything()
	_raise_the_hall()
	manager._apply_village_growth_decision(_chunk_coord)
	var queued: Array = _projects_for("warehouse")
	assert_eq(queued.size(), 1, "precondition")

	# The main street or one of the further streets south of it at the
	# layout's own fixed pitch -- a village whose first frontage is already
	# full of houses builds on the next street, which is the layout working,
	# not the siting drifting off the road network.
	var doorstep: Vector2i = queued[0].origin + BuildingCatalog.doorstep_of("warehouse")
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord))["street_y"]
	var offset := doorstep.y - street_y
	assert_gte(offset, 0, "a growth building never fronts north of the main street")
	assert_eq(offset % VillageLayout.STREET_PITCH_TILES, 0, "the doorstep is on one of the village's own streets")


func test_the_same_rung_is_never_queued_twice():
	_stock_everything()
	_raise_the_hall()
	manager._apply_village_growth_decision(_chunk_coord)
	manager._apply_village_growth_decision(_chunk_coord)
	assert_eq(_projects_for("warehouse").size(), 1, "a repeated decision finds its own earlier project")


## The subsistence gate (a village whose whole population works a survival
## occupation builds nothing) is the SAME SettlementSpareCapacity rule the
## hall already obeys, and is tested where it belongs against that module
## and CivicBuildDecision -- not re-staged here, which would need a fake
## occupation hook this file has no honest way to install.


# -- households move in ----------------------------------------------------

func test_admitting_a_household_really_grows_the_settlement():
	var before := manager.household_count_for_settlement(_settlement_id)
	var household_id := manager.admit_household(_chunk_coord)

	assert_ne(household_id, "")
	assert_eq(manager.household_count_for_settlement(_settlement_id), before + 1)


func test_every_admitted_household_is_a_distinct_one():
	var first := manager.admit_household(_chunk_coord)
	var second := manager.admit_household(_chunk_coord)
	assert_ne(first, second, "two arrivals are two households, not the same one twice")
	assert_eq(manager.household_count_for_settlement(_settlement_id), SettlementGenerator.POPULATION + 2)


func test_an_arriving_household_has_no_roof_until_the_village_builds_one():
	var household_id := manager.admit_household(_chunk_coord)
	var census := manager._village_census_for(_chunk_coord, manager._households_in_settlement(_settlement_id))
	assert_true(
		(census["unhoused_household_ids"] as Array).has(household_id),
		"a newcomer is homeless until the village raises a house"
	)


func test_a_homeless_household_makes_the_village_owe_a_house_before_any_other_rung():
	_stock_everything()
	_raise_the_hall()
	manager.admit_household(_chunk_coord)

	manager._apply_village_growth_decision(_chunk_coord)

	var houses: Array = _projects_for(BuildingCatalog.BUILDING_IDS[0])
	assert_eq(houses.size(), 1, "shelter outranks every civic and production rung")
	assert_true(_projects_for("warehouse").is_empty(), "the warehouse waits until everyone has a roof")


func test_the_house_is_credited_to_the_household_waiting_for_it():
	_stock_everything()
	_raise_the_hall()
	var newcomer := manager.admit_household(_chunk_coord)

	manager._apply_village_growth_decision(_chunk_coord)

	var houses: Array = _projects_for(BuildingCatalog.BUILDING_IDS[0])
	assert_eq(houses.size(), 1, "precondition")
	assert_eq(houses[0].household_id, newcomer, "the newcomer's own house, not the settlement's")


# -- the immigration step -------------------------------------------------

func test_a_hungry_village_takes_nobody_in():
	var before := manager.household_count_for_settlement(_settlement_id)
	manager._step_village_immigration(_settlement_id, _market(), manager._households_in_settlement(_settlement_id))
	assert_eq(manager.household_count_for_settlement(_settlement_id), before, "an empty larder attracts nobody")


func test_a_well_fed_village_with_room_eventually_takes_someone_in():
	_market().add_stock("cooked_meat", 500.0)
	var before := manager.household_count_for_settlement(_settlement_id)
	# Many steps: the draw is a real rate per day, not one arrival per call.
	for i in 400:
		manager._step_village_immigration(
			_settlement_id, _market(), manager._households_in_settlement(_settlement_id)
		)
	assert_gt(manager.household_count_for_settlement(_settlement_id), before, "a fed village with room grows")


# -- productivity is not decoration: it scales what the village gathers ----

## One step gathers a sub-unit fraction (a real rate per day against a
## 30-second assessment), so both conditions run long enough for whole
## units to actually land.
func _gather_for(steps: int) -> float:
	var household_ids := manager._households_in_settlement(_settlement_id)
	for i in steps:
		manager._step_settlement_gathering(_settlement_id, _market(), household_ids)
	return float(_market().stock.get("wood", 0.0))


func test_an_unhappy_village_gathers_less_than_a_thriving_one():
	var household_ids := manager._households_in_settlement(_settlement_id)
	assert_gt(
		SettlementSpareCapacity.for_settlement(
			household_ids.size(), manager._household_occupations_for_settlement(_settlement_id)
		), 0, "precondition: this village has spare hands to gather with at all"
	)

	# Destitute: no larder at all, so hunger is total and productivity floors.
	var destitute_wood := _gather_for(200)

	# Thriving: a full larder, which lifts the food need and with it
	# happiness and productivity.
	_market().stock.clear()
	manager._settlement_material_carry.clear()
	_market().add_stock("cooked_meat", 500.0)
	var thriving_wood := _gather_for(200)

	assert_gt(destitute_wood, 0.0, "even a miserable village gathers something")
	assert_gt(thriving_wood, destitute_wood, "a happier village gathers faster")


func test_the_settlements_own_mean_productivity_is_a_real_readable_number():
	var productivity: float = manager.settlement_productivity(_settlement_id)
	assert_between(productivity, HouseholdWellbeing.MIN_PRODUCTIVITY, 1.0)
