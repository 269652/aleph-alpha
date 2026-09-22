extends GutTest

## docs/concept/village_ponds.md "A pond dug the day the fisher's house
## stands": a fisher who arrives in play gets their pond the moment the
## growth ladder's house for them stands, not on the next chunk load.
##
## A real settlement chunk near Berlin whose NEXT villager fishes, loaded
## directly the way test_earth_chunk_manager_village_growth.gd does.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE
const HOUSE := "house_small"
const FISHER := "fisher"

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _generator := SettlementGenerator.new()
var _biome_classifier := BiomeClassifier.new()
var _chunk_coord: Vector2i
var _settlement_id: String
var _newcomer  # the NpcIdentity the roster gives the household admitted below

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
		_cached_chunk_coord = _find_settlement_chunk_whose_next_villager_fishes()
		_cached_chunk_coord_found = true
	_chunk_coord = _cached_chunk_coord
	_settlement_id = EntityRef.for_settlement(_chunk_coord)
	_scrub_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	_newcomer = _next_villager(_chunk_coord)


func after_each():
	_scrub_chunk(_chunk_coord)
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub_chunk(coord: Vector2i) -> void:
	for path in [
		manager._modifications_path(coord), manager._buildings_path(coord),
		manager._roof_modifications_path(coord), manager._furniture_modifications_path(coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var pond_fish := "%s/%d_%d.bin" % [EarthChunkManager.POND_FISH_DIR, coord.x, coord.y]
	if FileAccess.file_exists(pond_fish):
		DirAccess.remove_absolute(pond_fish)


## The identity the settlement's roster gives its next arrival: the same
## per-index seed admit_household continues past the founding roster.
func _next_villager(coord: Vector2i):
	var households := manager.household_count_for_settlement(EntityRef.for_settlement(coord))
	var roster: Dictionary = manager._settlement_generator.generate_settlement(
		coord, coord * CHUNK_SIZE, CHUNK_SIZE, TerrainRenderer.TILE_SIZE,
		households + 1, manager._is_dry_local(coord), manager.seeded_region_for_chunk(coord)
	)
	return roster["npcs"][households]


func _find_settlement_chunk_whose_next_villager_fishes() -> Vector2i:
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
			loads += 1
			_scrub_chunk(coord)
			manager._load_chunk(coord)
			# A village really founded here: its founding roster recorded
			# and housed, so the arrival below is a newcomer to a village
			# and not the first villager of a settlement that never rose.
			var founded: bool = (
				manager.household_count_for_settlement(EntityRef.for_settlement(coord))
				>= SettlementGenerator.POPULATION
			)
			var houses := 0
			for record in manager.buildings_in_chunk(coord):
				if BuildingCatalog.capacity_of(record.get("id", "")) > 0:
					houses += 1
			var fishes: bool = founded and _next_villager(coord).occupation == FISHER
			var has_room: bool = manager._growth_site_for(coord, HOUSE) != null
			var on_screen: bool = manager._loaded_villages.has(coord)
			manager._unload_chunk(coord)
			_scrub_chunk(coord)
			if founded and houses >= SettlementGenerator.POPULATION and fishes and has_room and on_screen:
				return coord
			if loads >= 30:
				break
	fail_test("no real settlement chunk whose next villager fishes was found near Berlin")
	return Vector2i.ZERO


func _record_at(origin: Vector2i) -> Dictionary:
	for record in manager.buildings_in_chunk(_chunk_coord):
		if record.get("origin_local", Vector2i(-1, -1)) == origin:
			return record
	return {}


func _pond_cells() -> int:
	var count := 0
	var chunk = manager._loaded_chunks.get(_chunk_coord)
	for cell in chunk.modifications:
		if VillagePond.is_pond_tile(String(chunk.modifications[cell])):
			count += 1
	return count


## Admits the newcomer: the arrival itself, which re-derives the village
## the way arrivals always have (admit_household -> _respawn_village).
func _admit_the_newcomer() -> String:
	# Loading a village already takes a growth decision, so a house project
	# of the village's own can be queued on the very plot the site search
	# answers with (it deliberately lands on its own earlier project). Those
	# are completed first, so the house raised below is the newcomer's.
	var store = manager.construction_project_store()
	for queued in store.active_projects_in_chunk(_chunk_coord):
		store.complete_project(queued.id, manager.household_store())
		manager._place_completed_construction_project(queued)
	var household_id: String = manager.admit_household(_chunk_coord)
	assert_ne(household_id, "", "precondition: the household arrived")
	return household_id


## Completes the ladder's house for them exactly as the labour tick does
## (_advance_construction_labor): the project on the growth site is marked
## complete -- which is what grants the household its property -- and then
## placed in the world.
func _complete_their_house(household_id: String) -> Vector2i:
	var origin = manager._growth_site_for(_chunk_coord, HOUSE)
	assert_not_null(origin, "precondition: the village has a plot for them")
	var store = manager.construction_project_store()
	var project = store.start_project(_chunk_coord, origin, HOUSE, household_id)
	assert_eq(project.household_id, household_id, "precondition: the project is the newcomer's own")
	assert_true(store.complete_project(project.id, manager.household_store()), "precondition: the project completes")
	manager._place_completed_construction_project(project)
	return origin


func _house_the_newcomer() -> Dictionary:
	var household_id := _admit_the_newcomer()
	return {"household_id": household_id, "origin": _complete_their_house(household_id)}


func test_the_premise_the_next_villager_here_fishes():
	assert_eq(_newcomer.occupation, FISHER)


func test_a_newcomers_house_carries_their_trade_the_day_it_stands():
	var housed := _house_the_newcomer()
	var record := _record_at(housed["origin"])
	assert_false(record.is_empty(), "the house stands")
	assert_eq(String(record.get("owner_household_id", "")), housed["household_id"], "precondition: the house is theirs")
	assert_eq(String(record.get("occupation", "")), FISHER, "the record says who lives there, without a reload")
	assert_eq(int(record.get("resident_seed", 0)), _newcomer.seed_value)


func test_a_newcomer_fisher_digs_their_pond_the_day_their_house_stands():
	var housed := _house_the_newcomer()
	assert_true(
		manager._village_renderer._has_pond_already(
			_chunk_coord, CHUNK_SIZE, manager, housed["origin"], HOUSE
		),
		"no pond within reach of the newcomer's house at %s" % str(housed["origin"])
	)


func test_a_further_re_derivation_digs_no_second_pond():
	_house_the_newcomer()
	var dug := _pond_cells()
	assert_gt(dug, 0, "precondition: a pond was dug")
	manager._respawn_village(_chunk_coord)
	assert_eq(_pond_cells(), dug, "a second re-derivation dug more water")


func _villager_markers() -> Array:
	var markers: Array = []
	for node in manager._loaded_villages.get(_chunk_coord, []):
		if is_instance_valid(node) and node is NpcMarker:
			markers.append(node)
	return markers


func _marker_of(seed_value: int):
	for marker in _villager_markers():
		if marker.identity != null and marker.identity.seed_value == seed_value:
			return marker
	return null


## The house standing is the newcomer's day, not everybody's: the village
## is not rebuilt around them. Measured with the economy probe when it
## was: every villager restarted their errand the moment a house
## completed, the fields lost a cycle (309 units harvested against 360),
## the food fell, and half the village left.
func test_a_house_standing_does_not_rebuild_the_rest_of_the_village():
	var household_id := _admit_the_newcomer()
	var before: Array = []
	for marker in _villager_markers():
		before.append(marker.get_instance_id())
	assert_gt(before.size(), 1, "precondition: a village of villagers stands")
	_complete_their_house(household_id)
	var after := {}
	for marker in _villager_markers():
		after[marker.get_instance_id()] = true
	var rebuilt := 0
	for id in before:
		if not after.has(id):
			rebuilt += 1
	assert_eq(rebuilt, 0, "%d of %d villagers were rebuilt for somebody else's house" % [rebuilt, before.size()])


func test_the_newcomer_fisher_is_handed_their_pond():
	_house_the_newcomer()
	var newcomer = _marker_of(_newcomer.seed_value)
	assert_not_null(newcomer, "the newcomer stands in the village")
	assert_false(newcomer.pond_cells.is_empty(), "the newcomer works no water")


func test_the_newcomers_home_is_their_own_door():
	var housed := _house_the_newcomer()
	var newcomer = _marker_of(_newcomer.seed_value)
	assert_not_null(newcomer)
	var doorstep: Vector2i = _chunk_coord * CHUNK_SIZE + housed["origin"] + BuildingCatalog.doorstep_of(HOUSE)
	var door := Vector2((doorstep.x + 0.5) * TerrainRenderer.TILE_SIZE, (doorstep.y + 0.5) * TerrainRenderer.TILE_SIZE)
	assert_eq(newcomer.home_position, door, "the newcomer's home is not their own door")


# -- and in real play the house is one already standing ------------------
#
# docs/concept/village_growth.md "...and nobody ever moved in": a newcomer
# is let in because a roof stands empty, and then stands under none, since
# a household is housed by OWNING a house and the empty one belongs to the
# village. On every settlement step each household with nowhere to live
# takes a standing house nobody on the roster owns, and the ground settles
# around them the same step -- measured with the economy probe: a fisher
# who arrived at 750 s worked no water for the rest of the run while two
# empty houses stood.

func _census() -> Dictionary:
	return manager._village_census_for(_chunk_coord, manager._households_in_settlement(_settlement_id))


func _spare_house_stands() -> bool:
	return int(_census()["spare_house_capacity"]) > 0


## A house the village raised for nobody in particular -- the ladder's
## lowest rung, owned by the settlement -- completed the way the labour
## tick completes it. What lets a newcomer in, and what they move into.
func _raise_a_roof_for_nobody() -> Vector2i:
	var origin = manager._growth_site_for(_chunk_coord, HOUSE)
	assert_not_null(origin, "precondition: the village has a plot for a roof")
	var store = manager.construction_project_store()
	var project = store.start_project(_chunk_coord, origin, HOUSE, _settlement_id)
	assert_true(store.complete_project(project.id, manager.household_store()))
	manager._place_completed_construction_project(project)
	return origin


func test_the_premise_a_roof_raised_for_nobody_stands_spare():
	_raise_a_roof_for_nobody()
	assert_true(_spare_house_stands(), "a roof the village raised for nobody counts as room")


func test_a_household_with_nowhere_to_live_takes_a_spare_house_on_the_settlement_step():
	_raise_a_roof_for_nobody()
	var household_id := _admit_the_newcomer()
	assert_true(_spare_house_stands(), "precondition: a roof stands empty")
	assert_null(manager.house_origin_for_villager(_chunk_coord, _newcomer.seed_value), "precondition: they own nothing yet")
	manager._house_the_waiting(_chunk_coord)
	assert_not_null(manager.house_origin_for_villager(_chunk_coord, _newcomer.seed_value), "the newcomer still owns no house")
	assert_false(_census()["unhoused_household_ids"].has(household_id), "the census still counts them unhoused")


func test_the_immigration_step_houses_the_waiting():
	_raise_a_roof_for_nobody()
	var household_id := _admit_the_newcomer()
	manager._step_village_immigration(
		_settlement_id, manager.market_store().market_for(_settlement_id),
		manager._households_in_settlement(_settlement_id)
	)
	assert_false(_census()["unhoused_household_ids"].has(household_id), "the step left them without a roof")


func test_the_house_they_move_into_gets_them_their_pond_the_same_step():
	_raise_a_roof_for_nobody()
	_admit_the_newcomer()
	manager._house_the_waiting(_chunk_coord)
	var origin = manager.house_origin_for_villager(_chunk_coord, _newcomer.seed_value)
	assert_not_null(origin, "precondition: they moved in")
	var record := _record_at(origin)
	assert_eq(String(record.get("occupation", "")), FISHER, "the house does not say a fisher lives there")
	assert_true(
		manager._village_renderer._has_pond_already(_chunk_coord, CHUNK_SIZE, manager, origin, String(record.get("id", HOUSE))),
		"no pond within reach of the house they moved into"
	)
	var newcomer = _marker_of(_newcomer.seed_value)
	assert_not_null(newcomer)
	assert_false(newcomer.pond_cells.is_empty(), "the newcomer works no water")


func test_one_household_to_a_roof():
	# Two arrivals, one spare roof: the second waits rather than sharing.
	_raise_a_roof_for_nobody()
	var first := _admit_the_newcomer()
	var second: String = manager.admit_household(_chunk_coord)
	assert_ne(second, "", "precondition: a second household arrived")
	var spare_before := int(_census()["spare_house_capacity"])
	manager._house_the_waiting(_chunk_coord)
	var housed := 0
	for household_id in [first, second]:
		if not _census()["unhoused_household_ids"].has(household_id):
			housed += 1
	assert_eq(housed, mini(2, spare_before), "roofs were shared or left empty")
