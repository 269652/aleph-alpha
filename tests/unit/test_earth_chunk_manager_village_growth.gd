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
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
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
			# BOTH a real square AND real houses. Deliberately NOT
			# _civic_plot_origin_for: that answers null once a hall STANDS
			# on the plot, and a founded village now has one -- which is
			# success, not failure. What this file needs is a village with
			# a square and households to make decisions for.
			var has_square := _plaza_is_real(coord)
			var houses := 0
			for record in manager.buildings_in_chunk(coord):
				if BuildingCatalog.capacity_of(record.get("id", "")) > 0:
					houses += 1
			manager._unload_chunk(coord)
			_scrub_chunk(coord)
			if has_square and houses > 0:
				return coord
			if loads >= 20:
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


## Loading a village ALREADY takes a growth decision (_load_chunk calls
## _apply_village_growth_decision), and a founded village with its hall up
## is immediately owed its next rung -- so a project can exist before a
## test body runs a line. A test that asserts what ONE decision queued has
## to start from an empty ledger, or it is really asserting what the load
## did.
func _clear_ledger() -> void:
	for project in manager.construction_project_store().active_projects_in_chunk(_chunk_coord):
		manager.construction_project_store().abandon_project(project.id)


## Puts the plot back the way it was before founding placed a hall on it --
## the state the over-time civic build is about. Same shape
## test_earth_chunk_manager_city_hall_rising.gd uses.
func _remove_the_founded_hall() -> void:
	if not manager.remove_building(_chunk_coord, _civic_origin):
		return
	var cells: Array = BuildingCatalog.footprint_cells("city_hall", _civic_origin)
	cells.append(_civic_origin + BuildingCatalog.doorstep_of("city_hall"))
	for local in cells:
		var g := _global(local)
		manager.build_at_global(g.x, g.y, TerrainRenderer.ROAD_TILE_ID)


## Every plaza cell is either paved or built on -- what a village that
## really laid its square looks like, whether or not a hall stands on it
## yet.
func _plaza_is_real(coord: Vector2i) -> bool:
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(coord))["plaza"]
	var chunk = manager._loaded_chunks.get(coord)
	if chunk == null:
		return false
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			var tile: String = chunk.modifications.get(Vector2i(x, y), "")
			if not (TerrainRenderer.is_road_tile(tile) or BuildingCatalog.occupies(tile)):
				return false
	return true


## The hall stands, so the ladder moves past the rung CivicBuildDecision
## owns and this file can exercise the rungs the growth decision owns. A
## founded village already has one, so this is usually a no-op now -- it
## stays because these tests are about what the ladder does ONCE the hall
## is up, and must not quietly depend on founding having put it there.
func _raise_the_hall() -> void:
	for record in manager.buildings_in_chunk(_chunk_coord):
		if record.get("id", "") == "city_hall":
			return
	manager._place_building_over_roads(_chunk_coord, _civic_origin, "city_hall", 1, _settlement_id)


## The rung these machinery tests act on: whichever one this village is
## really owed, with everything below it standing and the village grown big
## enough for the ladder to name it.
##
## Asked of the ladder rather than named, because a hardcoded rung is a test
## that silently stops testing anything the day that rung stops being one.
## That has now happened TWICE. All of these were written against
## "warehouse", which became something every village is founded with
## (docs/concept/village_warehouse.md) rather than something it climbs to;
## naming the farmhouse instead only moved the problem, because the founding
## raises farmhouses too. Measured on this village: 5 households, all housed,
## with city_hall, sawmill, farmhouse AND warehouse already standing, and so
## owed nothing at all -- every assertion about a queued project failing on
## an empty array.
##
## The sawmill is raised and stepped over rather than returned: it is the one
## rung sited at the forest rather than on the street, and one of these tests
## asserts street frontage.
const INDUSTRY_RUNG := "sawmill"


## The next street-fronting rung this village will really raise.
##
## ASKED OF THE MANAGER rather than predicted here. Since docs/concept/
## village_estates.md a village VOTES on its next rung (VillageAssembly)
## instead of walking a fixed table, so a second copy of the ladder order
## in this file would be predicting a decision nothing makes any more --
## which is exactly how this helper broke when the assembly landed.
##
## Anything that is not a street-fronting works is cleared out of the way
## first: the hall has its own decision and is already up, a house means
## somebody is still unroofed, and the industry rung is sited at the forest
## rather than on the street, so each is satisfied for real and the village
## is asked again.
func _rung_the_village_is_owed() -> String:
	_raise_the_hall()
	# ONE household at a time. Every household this helper adds costs the
	# street a house, and the frontage is finite -- growing in threes
	# overshot the first rung the village actually wanted by a house or two
	# and left the later tests with nowhere to build (which is how this
	# helper failed once already).
	for _attempt in 40:
		var rung := manager.next_building_for_settlement(_chunk_coord)
		if rung == "" or BuildingCatalog.BUILDING_IDS.has(rung):
			# Nothing wanted yet, or a roof owed -- a bigger village wants
			# more, so grow it by one and ask again.
			_grow_to(manager.household_count_for_settlement(_settlement_id) + 1)
			continue
		if rung == "city_hall":
			_raise_the_hall()
			continue
		var origin = manager._growth_site_for(_chunk_coord, rung)
		if origin == null:
			_grow_to(manager.household_count_for_settlement(_settlement_id) + 1)
			continue
		if rung == INDUSTRY_RUNG:
			manager._place_building_over_roads(_chunk_coord, origin, rung, 2, _settlement_id)
			continue
		return rung
	fail_test("this village is owed no street-fronting rung it could build")
	return ""


## Grows this real village until it has `count` households, each with a roof
## of its own.
##
## The ladder is a function of household count, so a test about a rung has
## to be run for a village big enough to be entitled to it -- and the
## founding roster of whichever chunk the finder above settles on is not a
## number this file gets to choose. Every newcomer is housed as they arrive
## because an unhoused household outranks every rung (a village shelters its
## people before it adorns itself), which would otherwise quietly turn every
## test below into a test about houses.
##
## Bounded by construction rather than by a condition: a failed assertion
## does not end a GDScript loop, so a village that could not grow would
## otherwise spin here forever instead of failing.
func _grow_to(count: int) -> void:
	var house_id: String = BuildingCatalog.BUILDING_IDS[0]
	for attempt in 50:
		if manager.household_count_for_settlement(_settlement_id) >= count:
			return
		var household_id := manager.admit_household(_chunk_coord)
		if household_id == "":
			fail_test("the village refused a newcomer")
			return
		var origin = manager._growth_site_for(_chunk_coord, house_id)
		if origin == null:
			fail_test("nowhere left to house a newcomer")
			return
		manager._place_building_over_roads(_chunk_coord, origin, house_id, 3 + attempt, household_id)
		# Placing the house is not what houses anybody. Residency is resolved
		# through the property-id scheme (VillageCensus.household_owning ->
		# HouseholdStore.owner_of), never through the building record's own
		# owner field -- so without this grant every newcomer stayed
		# UNHOUSED, the ladder went on owing a house ahead of every rung, and
		# no test below ever saw the rung it was asking about. Exactly what
		# record_settlement_founded_if_new does for the founding roster.
		manager._household_store.grant_property(
			household_id, ConstructionProject.for_site(_chunk_coord, origin, "", "").property_id()
		)
	fail_test("this village never reached %d households" % count)


func _projects_for(building_id: String) -> Array:
	var out: Array = []
	for project in manager.construction_project_store().active_projects_in_chunk(_chunk_coord):
		if project.blueprint_id == building_id:
			out.append(project)
	return out


# -- the ladder is walked in order, behind the hall the civic decision owns

func test_a_village_without_its_hall_yet_queues_no_later_rung():
	_stock_everything()
	_remove_the_founded_hall()
	_clear_ledger()

	manager._apply_village_growth_decision(_chunk_coord)
	# Deliberately not "warehouse": it is founded with the village rather
	# than climbed to, so asking whether it waits behind the hall would pass
	# for a reason that has nothing to do with the hall.
	for building_id in ["farmhouse", "blacksmith", "brewery"]:
		assert_true(_projects_for(building_id).is_empty(), "%s must wait behind the hall" % building_id)


func test_a_village_with_its_hall_up_queues_the_next_rung_it_is_entitled_to():
	_stock_everything()
	var rung := _rung_the_village_is_owed()

	manager._apply_village_growth_decision(_chunk_coord)

	var queued: Array = _projects_for(rung)
	assert_eq(queued.size(), 1, "the ladder's next rung for a village of this size")
	assert_eq(
		queued[0].household_id, _settlement_id,
		"a growth rung is the settlement's own commons, not any one household's"
	)
	assert_eq(queued[0].status, ConstructionProject.Status.IN_PROGRESS, "stocked, so it really started")


func test_a_growth_building_is_sited_fronting_the_villages_own_street():
	_stock_everything()
	var rung := _rung_the_village_is_owed()
	manager._apply_village_growth_decision(_chunk_coord)
	var queued: Array = _projects_for(rung)
	assert_eq(queued.size(), 1, "precondition")

	# The main street or one of the further streets south of it at the
	# layout's own fixed pitch -- a village whose first frontage is already
	# full of houses builds on the next street, which is the layout working,
	# not the siting drifting off the road network.
	var doorstep: Vector2i = queued[0].origin + BuildingCatalog.doorstep_of(rung)
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord))["street_y"]
	var offset := doorstep.y - street_y
	assert_gte(offset, 0, "a growth building never fronts north of the main street")
	assert_eq(offset % VillageLayout.STREET_PITCH_TILES, 0, "the doorstep is on one of the village's own streets")


func test_the_same_rung_is_never_queued_twice():
	_stock_everything()
	var rung := _rung_the_village_is_owed()
	manager._apply_village_growth_decision(_chunk_coord)
	manager._apply_village_growth_decision(_chunk_coord)
	assert_eq(_projects_for(rung).size(), 1, "a repeated decision finds its own earlier project")


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
	var rung := _rung_the_village_is_owed()
	manager.admit_household(_chunk_coord)
	_clear_ledger()

	manager._apply_village_growth_decision(_chunk_coord)

	var houses: Array = _projects_for(BuildingCatalog.BUILDING_IDS[0])
	assert_eq(houses.size(), 1, "shelter outranks every civic and production rung")
	assert_true(_projects_for(rung).is_empty(), "every rung waits until everyone has a roof")


func test_the_house_is_credited_to_the_household_waiting_for_it():
	_stock_everything()
	# The rung itself is not this test's question -- only that the village is
	# past the point where the ladder would otherwise be owed one.
	_rung_the_village_is_owed()
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


## Raises one more house than this village has people for, and answers with
## the spare capacity that left standing -- the room an arrival needs.
func _raise_a_spare_house() -> int:
	var house_id: String = BuildingCatalog.BUILDING_IDS[0]
	var origin = manager._growth_site_for(_chunk_coord, house_id)
	if origin == null:
		return 0
	manager._place_building_over_roads(_chunk_coord, origin, house_id, 3, _settlement_id)
	var census := manager._village_census_for(
		_chunk_coord, manager._households_in_settlement(_settlement_id)
	)
	return int(census["spare_house_capacity"])


func _draw_for_a_while() -> void:
	# Many steps: the draw is a real rate per day, not one arrival per call.
	for i in 400:
		manager._step_village_immigration(
			_settlement_id, _market(), manager._households_in_settlement(_settlement_id)
		)


## **Rewritten 2026-09-20**, and the rewrite is the point. This used to drive
## the immigration step alone and expect the village to grow, which worked
## only because the old gate admitted one household per step on the strength
## of FRONTAGE -- somewhere to BUILD, not somewhere to live. Reported live:
## "NPCs should only move in when a new unoccupied house exists for them".
##
## So "a fed village grows" is two steps now, and this drives both: a village
## whose roofs are all full takes nobody in however fed it is, and the same
## village takes somebody in the moment one really stands empty.
func test_a_well_fed_village_grows_once_a_house_really_stands_empty():
	_market().add_stock("cooked_meat", 500.0)
	var before := manager.household_count_for_settlement(_settlement_id)

	_draw_for_a_while()
	assert_eq(
		manager.household_count_for_settlement(_settlement_id), before,
		"a village with every roof full takes nobody in, however well fed"
	)

	var spare := _raise_a_spare_house()
	if spare <= 0:
		pending("no street frontage left in this village to raise a spare house on")
		return

	_draw_for_a_while()
	assert_gt(
		manager.household_count_for_settlement(_settlement_id), before,
		"an empty house is exactly what a fed village grows into"
	)


## And the ladder is what puts that house there -- otherwise the gate above
## would simply stop every village for ever. A village with every roof full
## owes itself a house, whatever else it already has.
func test_a_village_with_every_roof_full_owes_itself_a_house():
	var census := manager._village_census_for(
		_chunk_coord, manager._households_in_settlement(_settlement_id)
	)
	assert_eq(int(census["spare_house_capacity"]), 0, "the premise: nowhere for anyone to move in")
	assert_eq(
		VillageGrowth.next_building(
			manager.household_count_for_settlement(_settlement_id),
			int(census["housed_count"]),
			VillageGrowth.LADDER_BUILDING_IDS,
			int(census["spare_house_capacity"])
		),
		BuildingCatalog.BUILDING_IDS[0]
	)


# -- productivity is not decoration: it scales what the village gathers ----

## Productivity scales what a village BUILDS, not what it gathers. A
## starving village must still be able to cut the timber for the farm that
## would fix its hunger -- scaling the gathering itself would be a doom
## loop, where the villages most in need of building their way out are the
## ones least able to. It raises what it gathered more slowly instead,
## which is the real penalty and a recoverable one.
func _labour_after(steps: int, project) -> float:
	for i in steps:
		manager._advance_construction_labor(_chunk_coord, EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	return project.labor_hours_accumulated


func test_an_unhappy_village_builds_slower_than_a_thriving_one():
	var household_ids := manager._households_in_settlement(_settlement_id)
	assert_gt(
		SettlementSpareCapacity.for_settlement(
			household_ids.size(), manager._household_occupations_for_settlement(_settlement_id)
		), 0, "precondition: this village has spare hands to build with at all"
	)
	_stock_everything()
	var rung := _rung_the_village_is_owed()
	manager._apply_village_growth_decision(_chunk_coord)
	var queued: Array = _projects_for(rung)
	assert_eq(queued.size(), 1, "precondition: something is actually rising")

	# Destitute: no larder at all, so hunger is total and productivity floors.
	var destitute_labour := _labour_after(4, queued[0])
	assert_gt(destitute_labour, 0.0, "even a miserable village keeps building")

	# Thriving: a full larder lifts the food need, and with it happiness
	# and productivity.
	queued[0].labor_hours_accumulated = 0.0
	_market().add_stock("cooked_meat", 500.0)
	var thriving_labour := _labour_after(4, queued[0])

	assert_gt(thriving_labour, destitute_labour, "a happier village builds faster")


## The material itself is NEVER scaled: a hungry village cuts timber at the
## same rate as a happy one, because that is what lets it build its way out
## of being hungry at all.
func test_a_hungry_village_gathers_material_just_as_fast_as_a_fed_one():
	var household_ids := manager._households_in_settlement(_settlement_id)
	for i in 8:
		manager._step_settlement_gathering(_settlement_id, _market(), household_ids)
	var hungry_wood: float = _market().stock.get("wood", 0.0)
	assert_gt(hungry_wood, 0.0, "a hungry village still cuts its own timber")

	_market().stock.clear()
	manager._settlement_material_carry.clear()
	_market().add_stock("cooked_meat", 500.0)
	for i in 8:
		manager._step_settlement_gathering(_settlement_id, _market(), household_ids)
	var fed_wood: float = _market().stock.get("wood", 0.0)

	assert_almost_eq(fed_wood, hungry_wood, 0.001, "hunger must never slow the gathering")


func test_the_settlements_own_mean_productivity_is_a_real_readable_number():
	var productivity: float = manager.settlement_productivity(_settlement_id)
	assert_between(productivity, HouseholdWellbeing.MIN_PRODUCTIVITY, 1.0)


# -- the readout: clicking a house (docs/concept/village_growth.md, 5) -----
#
# A consumer, never a driver: it reads state that already exists and
# changes nothing. Every number it reports is derived at the moment it is
# asked for, so it cannot drift from the simulation.

func _any_house_record() -> Dictionary:
	for record in manager.buildings_in_chunk(_chunk_coord):
		if BuildingCatalog.capacity_of(record.get("id", "")) > 0:
			return record
	return {}


func test_clicking_empty_ground_reports_nothing():
	var open_cell := _global(Vector2i(0, 0))
	assert_true(manager.building_at_global(open_cell.x, open_cell.y).is_empty(), "precondition: nothing here")
	assert_true(manager.household_report_at(open_cell.x, open_cell.y).is_empty())


func test_clicking_a_house_reports_its_resident_and_their_household():
	var house := _any_house_record()
	assert_false(house.is_empty(), "precondition: a real village has houses")
	var anchor := _global(house["origin_local"])

	var report: Dictionary = manager.household_report_at(anchor.x, anchor.y)

	assert_eq(report["building_id"], house["id"])
	assert_eq(report["settlement_id"], _settlement_id)
	assert_true(report["is_home"], "a house is somebody's home")
	assert_ne(report["household_id"], "", "a village house belongs to the household living in it")
	assert_ne(report["resident_name"], "", "the readout names the person, not just the plot")
	assert_ne(report["resident_occupation"], "")


## Any footprint cell answers, not just the anchor -- a click lands
## wherever the player clicked on the building, not on its corner.
func test_clicking_any_part_of_a_house_reports_the_same_household():
	var house := _any_house_record()
	assert_false(house.is_empty(), "precondition")
	var anchor_report: Dictionary = manager.household_report_at(_global(house["origin_local"]).x, _global(house["origin_local"]).y)
	for cell in BuildingCatalog.footprint_cells(house["id"], house["origin_local"]):
		var g := _global(cell)
		assert_eq(
			manager.household_report_at(g.x, g.y).get("household_id", "<none>"), anchor_report["household_id"],
			"cell %s must report the same household as the anchor" % str(cell)
		)


func test_a_house_reports_every_need_plus_happiness_and_productivity():
	var house := _any_house_record()
	assert_false(house.is_empty(), "precondition")
	var anchor := _global(house["origin_local"])

	var report: Dictionary = manager.household_report_at(anchor.x, anchor.y)

	for need_id in HouseholdWellbeing.NEED_IDS:
		assert_between(float(report["needs"][need_id]), 0.0, 1.0, "%s must be a real satisfaction" % need_id)
	assert_between(float(report["happiness"]), 0.0, 1.0)
	assert_between(float(report["productivity"]), HouseholdWellbeing.MIN_PRODUCTIVITY, 1.0)


## Feeding the village really moves the readout -- proof the numbers are
## derived from live state rather than snapshotted at founding.
func test_the_readout_follows_the_village_it_reports_on():
	var house := _any_house_record()
	assert_false(house.is_empty(), "precondition")
	var anchor := _global(house["origin_local"])
	var hungry: float = manager.household_report_at(anchor.x, anchor.y)["happiness"]

	_market().add_stock("cooked_meat", 500.0)

	assert_gt(
		float(manager.household_report_at(anchor.x, anchor.y)["happiness"]), hungry,
		"a fed village reads happier the moment it is fed"
	)


## A commons has no household and no needs of its own -- reported honestly
## as a building of the settlement rather than given invented residents.
func test_a_civic_building_reports_itself_without_inventing_a_resident():
	_raise_the_hall()
	var anchor := _global(_civic_origin)

	var report: Dictionary = manager.household_report_at(anchor.x, anchor.y)

	assert_eq(report["building_id"], "city_hall")
	assert_false(report["is_home"], "nobody lives in the town hall")
	assert_eq(report["resident_name"], "")
	assert_true((report["needs"] as Dictionary).is_empty(), "a hall has no needs of its own")
	assert_between(float(report["settlement_productivity"]), HouseholdWellbeing.MIN_PRODUCTIVITY, 1.0)


func test_the_readout_changes_nothing_it_reports_on():
	var house := _any_house_record()
	assert_false(house.is_empty(), "precondition")
	var anchor := _global(house["origin_local"])
	var households_before := manager.household_count_for_settlement(_settlement_id)
	var stock_before: Dictionary = _market().stock.duplicate()
	var buildings_before := manager.buildings_in_chunk(_chunk_coord).size()

	manager.household_report_at(anchor.x, anchor.y)

	assert_eq(manager.household_count_for_settlement(_settlement_id), households_before)
	assert_eq(_market().stock, stock_before)
	assert_eq(manager.buildings_in_chunk(_chunk_coord).size(), buildings_before)


## VillageRenderer asks this to put a villager at their own front door on
## reload. A newcomer's house was raised by the growth ladder and carries
## none of the founding per-index seeds, so ownership -- not a seed -- is
## what finds it.
func test_the_house_a_villager_owns_is_found_from_their_own_seed():
	var house := _any_house_record()
	assert_false(house.is_empty(), "precondition: a real village has houses")
	var resident_seed := int(house.get("resident_seed", 0))
	assert_ne(resident_seed, 0, "precondition: a founded house remembers its villager")

	assert_eq(manager.house_origin_for_villager(_chunk_coord, resident_seed), house["origin_local"])


func test_a_villager_who_owns_nothing_here_is_reported_as_owning_nothing():
	assert_null(manager.house_origin_for_villager(_chunk_coord, 123456789))


# -- two siting algorithms, one patch of ground --------------------------
#
# _settlement_build_origin_for (the older spiral, for single-tile
# structures like a farm or a mill) and VillageLayout.next_street_plot
# (this pass's street frontage) both look for UNMODIFIED ground, and a
# building project that is merely rising has not modified anything yet. Two
# projects on the same cells means the second to complete finds its site
# taken and silently places nothing -- a COMPLETE ledger entry with no
# building. Each siting must see the other's reservations.

func test_the_spiral_site_search_never_offers_ground_a_building_is_rising_on():
	_stock_everything()
	var rung := _rung_the_village_is_owed()
	manager._apply_village_growth_decision(_chunk_coord)
	var queued: Array = _projects_for(rung)
	assert_eq(queued.size(), 1, "precondition")

	for cell in BuildingCatalog.footprint_cells(rung, queued[0].origin):
		assert_false(
			manager._is_clear_settlement_site(_chunk_coord, cell),
			"cell %s is already spoken for by a rising rung" % str(cell)
		)


func test_a_growth_building_is_never_sited_on_ground_another_project_already_claims():
	_stock_everything()
	var rung := _rung_the_village_is_owed()
	manager._apply_village_growth_decision(_chunk_coord)
	var first: Array = _projects_for(rung)
	assert_eq(first.size(), 1, "precondition")
	var claimed := {}
	for cell in BuildingCatalog.footprint_cells(rung, first[0].origin):
		claimed[cell] = true

	# The NEXT thing sited has to find its own ground rather than share the
	# one already rising -- asked for directly, since the ladder will not
	# name anything else until this rung actually stands.
	#
	# A house, not the next ladder rung. The question here is whether the
	# spiral search respects a live project's claim, and the rung this
	# village happens to be owed may be the last one on the ladder or simply
	# too big for what frontage is left -- neither of which is this test's
	# subject, and both of which made it fail for the wrong reason.
	var after: String = BuildingCatalog.BUILDING_IDS[0]
	var next_origin = manager._growth_site_for(_chunk_coord, after)
	assert_not_null(next_origin, "the village still has frontage somewhere")
	for cell in BuildingCatalog.footprint_cells(after, next_origin):
		assert_false(claimed.has(cell), "cell %s overlaps the rung already rising" % str(cell))


# -- the sawmill really stands, in the real pipeline ----------------------
#
# Reported live as missing. The pure siting is tested in
# test_village_layout.gd and the renderer wiring against a stub in
# test_village_renderer.gd, but neither proves that a REAL chunk load ends
# with a real mill in the world -- which is the thing that was doubted.

func _forest_cells_in_chunk() -> Dictionary:
	var chunk = manager._loaded_chunks.get(_chunk_coord)
	var forest := {}
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if chunk.biome[y * CHUNK_SIZE + x] == "forest":
				forest[Vector2i(x, y)] = true
	return forest


func _sawmill_record() -> Dictionary:
	for record in manager.buildings_in_chunk(_chunk_coord):
		if record.get("id", "") == "sawmill":
			return record
	return {}


func test_a_real_chunk_load_leaves_a_real_sawmill_standing_at_the_timber():
	var forest := _forest_cells_in_chunk()
	if forest.is_empty():
		pass_test("this village has no timber in reach, so honestly no mill")
		return

	var mill := _sawmill_record()
	assert_false(mill.is_empty(), "a village with forest in reach must end its load with a real mill")

	var origin: Vector2i = mill["origin_local"]
	var near_timber := false
	for cell in BuildingCatalog.footprint_cells("sawmill", origin):
		assert_false(forest.has(cell), "the mill stands IN the wood it cuts, at %s" % str(cell))
		for dy in range(-VillageLayout.INDUSTRY_FOREST_REACH_TILES, VillageLayout.INDUSTRY_FOREST_REACH_TILES + 1):
			for dx in range(-VillageLayout.INDUSTRY_FOREST_REACH_TILES, VillageLayout.INDUSTRY_FOREST_REACH_TILES + 1):
				if forest.has(cell + Vector2i(dx, dy)):
					near_timber = true
	assert_true(near_timber, "the mill must stand at real timber")


## The spur is the part that makes it part of the village -- verified by
## walking real paved cells in the real chunk, not by trusting a list.
func test_the_real_sawmill_is_walkable_back_to_the_street_on_road():
	if _forest_cells_in_chunk().is_empty():
		pass_test("no mill to walk to")
		return
	var mill := _sawmill_record()
	assert_false(mill.is_empty(), "precondition: a mill stands")

	var doorstep: Vector2i = mill["origin_local"] + BuildingCatalog.doorstep_of("sawmill")
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord))["street_y"]
	var chunk = manager._loaded_chunks.get(_chunk_coord)

	assert_true(TerrainRenderer.is_road_tile(chunk.modifications.get(doorstep, "")), "the doorstep itself is paved")
	var seen := {doorstep: true}
	var frontier: Array = [doorstep]
	var reached := false
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if cell.y == street_y:
			reached = true
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = cell + step
			if seen.has(next_cell):
				continue
			if not TerrainRenderer.is_road_tile(chunk.modifications.get(next_cell, "")):
				continue
			seen[next_cell] = true
			frontier.append(next_cell)
	assert_true(reached, "the mill must be walkable back to the street on real road")


## And the square the whole civic system depends on really got paved.
func test_a_real_chunk_load_leaves_the_plaza_paved():
	var plaza: Rect2i = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord))["plaza"]
	var chunk = manager._loaded_chunks.get(_chunk_coord)
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			var tile: String = chunk.modifications.get(Vector2i(x, y), "")
			assert_true(
				TerrainRenderer.is_road_tile(tile) or BuildingCatalog.occupies(tile),
				"plaza cell (%d,%d) is '%s' -- neither paved nor built on" % [x, y, tile]
			)


# -- a traveling merchant pays the village (traveling_merchants.md) -------
#
# Reported live: "all villagers have 0 gold". The persistent-purse bug was
# half of it; the other half is that a village's gold came from nowhere --
# conjured per food unit gathered whether or not anyone ever bought it.
# Here the outside world turns up and pays for goods it carries away.

const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")


func test_a_village_with_goods_is_eventually_paid_by_a_merchant():
	var market = _market()
	market.add_stock("fish", 60.0)
	assert_eq(NpcEconomy.purse_of(market), 0.0, "precondition: an empty purse")

	for i in 400:
		manager._step_merchant_visits(_settlement_id, market)

	assert_gt(NpcEconomy.purse_of(market), 0.0, "somebody carried the catch away and paid for it")
	assert_lt(market.stock.get("fish", 0.0), 60.0, "and the fish really left the village")


func test_a_village_with_nothing_to_sell_is_never_paid():
	var market = _market()
	for i in 400:
		manager._step_merchant_visits(_settlement_id, market)
	assert_eq(NpcEconomy.purse_of(market), 0.0, "no goods, no merchant, no gold")


## The gold and the goods have to balance: this is the one place new money
## enters a village, so it must enter for a reason.
func test_the_gold_paid_is_exactly_the_goods_taken():
	var market = _market()
	market.add_stock("beam", 40.0)
	var before: float = market.stock["beam"]

	for i in 200:
		manager._step_merchant_visits(_settlement_id, market)

	var taken: float = before - float(market.stock.get("beam", 0.0))
	assert_gt(taken, 0.0, "precondition: a sale happened")
	assert_almost_eq(
		NpcEconomy.purse_of(market), taken * MerchantVisit.price_of("beam"), 0.001,
		"the purse holds exactly what the beams were worth"
	)


## And that gold is spendable: VillageWages pays subsistence out of this
## same purse, which is what carries a merchant's visit to the villagers
## who did not catch anything.
func test_the_gold_lands_in_the_purse_the_village_pays_wages_from():
	var VillageWages = load("res://src/world/village_wages.gd")
	var market = _market()
	market.add_stock("hide", 50.0)
	for i in 300:
		manager._step_merchant_visits(_settlement_id, market)
	var purse := NpcEconomy.purse_of(market)
	assert_gt(purse, 0.0, "precondition")

	var payout: Dictionary = VillageWages.pay_subsistence(purse)

	assert_gt(int(payout["paid"]), 0, "a villager who caught nothing can still be paid a wage")
	assert_lt(float(payout["purse"]), purse, "and the village really spent it")


# -- and a growth building really joins the streets it fronts --------------
#
# Reported in play, with a screenshot: "There are still Farmhouses not
# connected by a street". The founding layout only paves a further street
# once that street really got a plot, so the FIRST building raised on a
# fresh row used to get a single paved tile at its door and nothing else
# (see VillageLayout._frontage_spur).


## Whether `cell` can be walked back to the village's main street over real
## road tiles -- the same walk test_the_real_sawmill_is_walkable_back_to_
## the_street_on_road already makes for the mill.
func _walkable_back_to_the_street(cell: Vector2i) -> bool:
	var street_y: int = VillageLayout.skeleton(CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord))["street_y"]
	var chunk = manager._loaded_chunks.get(_chunk_coord)
	if chunk == null or not TerrainRenderer.is_road_tile(chunk.modifications.get(cell, "")):
		return false
	var seen := {cell: true}
	var frontier: Array = [cell]
	while not frontier.is_empty():
		var at: Vector2i = frontier.pop_back()
		if at.y == street_y:
			return true
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = at + step
			if seen.has(next_cell):
				continue
			if not TerrainRenderer.is_road_tile(chunk.modifications.get(next_cell, "")):
				continue
			seen[next_cell] = true
			frontier.append(next_cell)
	return false


func test_every_rung_the_village_raises_is_walkable_back_to_its_street():
	_stock_everything()
	var raised: Array = []
	var stranded: Array = []
	for rung in VillageGrowth.LADDER_BUILDING_IDS:
		if rung == "city_hall":
			continue
		if manager._present_structure_ids_for_settlement_chunk(_chunk_coord).has(rung):
			continue
		var origin = manager._growth_site_for(_chunk_coord, rung)
		if origin == null:
			continue
		# The PUBLIC wrapper, which is what the village itself places
		# through -- a player's own house deliberately gets no street laid
		# for it (see _place_building_over_roads' own join_street flag).
		if not manager.place_building_over_roads(_chunk_coord, origin, rung, 2, _settlement_id):
			continue
		raised.append(rung)
		var doorstep: Vector2i = origin + BuildingCatalog.doorstep_of(rung)
		if not _walkable_back_to_the_street(doorstep):
			stranded.append("%s at %s opens onto %s" % [rung, str(origin), str(doorstep)])
	assert_gt(raised.size(), 0, "precondition: the village raised at least one rung")
	assert_eq(
		stranded.size(), 0,
		"%d of %d rungs stand on paving no street reaches: %s" % [stranded.size(), raised.size(), str(stranded)]
	)



# -- an arrival you can actually see ----------------------------------------
#
# Reported live with the town panel in shot: *"despite showing 20 population
# only 10 NPCs are there"*.
#
# `spawn_village` runs only from `_load_chunk`, so the villager roster is
# fixed at the moment the chunk loaded -- while `admit_household` goes on
# adding to the settlement's household count. A household that moved in
# while you were standing in the village had no villager at all until you
# walked far enough away to unload the chunk and came back.


func _villagers_on_screen() -> int:
	var found := 0
	for node in manager._loaded_villages.get(_chunk_coord, []):
		if is_instance_valid(node) and node is NpcMarker:
			found += 1
	return found


func test_a_loaded_village_starts_with_a_villager_for_every_household():
	assert_eq(
		_villagers_on_screen(), manager.household_count_for_settlement(_settlement_id),
		"the premise: a freshly loaded village already shows everyone who lives in it"
	)


func test_a_household_admitted_to_a_loaded_village_gets_a_villager_of_its_own():
	var before := _villagers_on_screen()
	assert_ne(manager.admit_household(_chunk_coord), "", "the premise: somebody really moved in")
	assert_eq(
		_villagers_on_screen(), before + 1,
		"a household that moved in while you were watching had nobody to show for it"
	)


## However many arrive, and whenever: the villagers you can see are the
## households that live there, not the roster the chunk happened to load with.
func test_the_villagers_on_screen_always_match_the_households_that_live_there():
	for arrival in 3:
		manager.admit_household(_chunk_coord)
		assert_eq(
			_villagers_on_screen(), manager.household_count_for_settlement(_settlement_id),
			"after %d arrivals the village shows the wrong number of people" % (arrival + 1)
		)


## ...and nobody is duplicated doing it. Re-deriving a village must replace
## its villagers, never add a second copy of everyone already standing there.
func test_nobody_is_duplicated_when_a_village_takes_somebody_in():
	manager.admit_household(_chunk_coord)
	var seen: Dictionary = {}
	for node in manager._loaded_villages.get(_chunk_coord, []):
		if not is_instance_valid(node) or not (node is NpcMarker):
			continue
		var identity = node.identity
		if identity == null:
			continue
		assert_false(seen.has(identity.seed_value), "two markers for the same villager")
		seen[identity.seed_value] = true


# -- a village that caught up with itself still starts the house ----------
#
# The ladder's lowest rung raises a house when no roof stands empty, so
# immigration has the spare capacity it gates on. That house has no
# household waiting for it BY DEFINITION -- everybody is housed, which is
# precisely why it is being raised.
#
# _apply_village_growth_decision credited a new home to `waiting[0]` and
# RETURNED when nobody was waiting, so the rung was chosen on every
# settlement step and never once begun. Measured
# (tools/probe_village_growth_gate.gd) with every other condition open:
#
#   seconds  house housed  room  food/hh  labour waiting  site   next build   building now
#         0     10     10     0     0.00       6      0   yes    house_small  -
#       200     10     10     0     3.60       6      0   yes    house_small  -
#       500     10     10     0     3.20       6      0   yes    house_small  -

## Stands every rung this ladder knows, owned by the settlement, so the
## village owes itself nothing above the house.
func _raise_every_rung() -> void:
	for building_id in VillageGrowth.LADDER_BUILDING_IDS:
		if manager._present_structure_ids_for_settlement_chunk(_chunk_coord).has(building_id):
			continue
		var origin = manager._growth_site_for(_chunk_coord, building_id)
		if origin == null:
			continue
		manager._place_building_over_roads(_chunk_coord, origin, building_id, 11, _settlement_id)


func test_a_fully_housed_village_really_starts_the_house_it_owes_itself():
	_stock_everything()
	_raise_every_rung()
	var household_ids := manager._households_in_settlement(_settlement_id)
	var census := manager._village_census_for(_chunk_coord, household_ids)
	assert_true(
		census["unhoused_household_ids"].is_empty(),
		"precondition: this village has housed everybody"
	)
	assert_eq(
		int(census["spare_house_capacity"]), 0, "precondition: and no roof stands empty"
	)
	var house_id: String = BuildingCatalog.BUILDING_IDS[0]
	assert_eq(
		manager.next_building_for_settlement(_chunk_coord), house_id,
		"precondition: so the village owes itself a house"
	)

	manager._apply_village_growth_decision(_chunk_coord)

	assert_false(
		_projects_for(house_id).is_empty(),
		"the village owed itself a roof, had the hands and the ground, and never began it"
	)


## ...and the village owns it, because nobody in particular does. A commons
## roof standing empty IS the invitation VillageImmigration gates on.
func test_the_house_for_nobody_in_particular_belongs_to_the_village():
	_stock_everything()
	_raise_every_rung()
	var house_id: String = BuildingCatalog.BUILDING_IDS[0]
	manager._apply_village_growth_decision(_chunk_coord)
	var projects := _projects_for(house_id)
	assert_false(projects.is_empty(), "precondition: the house was begun")
	assert_eq(
		projects[0].household_id, _settlement_id,
		"a roof for nobody in particular is the village's own"
	)
