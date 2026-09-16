extends GutTest

## The player's own house as a whole-building entity (docs/concept/
## building.md "Player building re-route", workforce.md "Starting a real
## player-owned construction project"): a learned blueprint places ONE real
## BuildingCatalog building through EarthChunkManager.place_building --
## never the legacy per-tile piece pipeline -- and the existing
## construction ledger (a COMPLETE ConstructionProject, HouseholdStore
## property, move-in) runs exactly as before. Replaces the chunk-(0,0)
## piece-house group test_earth_chunk_manager.gd used to carry.
##
## Berlin's real chunk, loaded directly via _load_chunk (the fast fixture
## test_earth_chunk_manager_buildings.gd already uses -- see
## test_earth_chunk_manager.gd's own known-slow-file note); persisted files
## scrubbed before and after, since tests share one real user:// dir.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _origin: Vector2i  # a real, dry, buildable GLOBAL origin for a house_large + doorstep


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
	_scrub()
	manager._load_chunk(_chunk_coord)
	_origin = _a_clear_site_origin("house_large")


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## A GLOBAL origin, well inside the chunk, where every footprint cell of
## `building_id` AND its doorstep are dry buildable ground with nothing
## modified yet.
func _a_clear_site_origin(building_id: String) -> Vector2i:
	var footprint := BuildingCatalog.footprint_of(building_id)
	for y in range(2, EarthChunkManager.CHUNK_SIZE - footprint.y - 3):
		for x in range(2, EarthChunkManager.CHUNK_SIZE - footprint.x - 2):
			var origin := _chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(x, y)
			if _site_is_clear(building_id, origin):
				return origin
	fail_test("no clear site for %s in this chunk" % building_id)
	return Vector2i.ZERO


func _site_is_clear(building_id: String, origin: Vector2i) -> bool:
	var cells: Array = BuildingCatalog.footprint_cells(building_id, origin)
	cells.append(origin + BuildingCatalog.doorstep_of(building_id))
	for cell in cells:
		if not manager.is_buildable_terrain_at(cell.x, cell.y) or manager.modification_at_global(cell.x, cell.y) != "":
			return false
	return true


func _doorstep(building_id: String, origin: Vector2i) -> Vector2i:
	return origin + BuildingCatalog.doorstep_of(building_id)


# -- the recipe -> building mapping ------------------------------------------

func test_the_three_house_tiers_map_to_the_three_catalog_houses():
	assert_eq(EarthChunkManager.BUILDING_ID_BY_RECIPE_ID["small_house"], "house_small")
	assert_eq(EarthChunkManager.BUILDING_ID_BY_RECIPE_ID["cottage"], "house_medium")
	assert_eq(EarthChunkManager.BUILDING_ID_BY_RECIPE_ID["manor"], "house_large")


## The ten two-story blueprints have no whole-building form yet (their
## recipe prices are pinned to legacy shapes a single catalog house cannot
## honestly stand in for) -- mapped explicitly to "", never silently
## missing, so nothing falls through to a stale default.
func test_every_two_story_recipe_is_explicitly_unmapped():
	for recipe_id in HouseBlueprint.TWO_STORY_BLUEPRINT_IDS:
		assert_true(EarthChunkManager.BUILDING_ID_BY_RECIPE_ID.has(recipe_id), recipe_id)
		assert_eq(EarthChunkManager.BUILDING_ID_BY_RECIPE_ID[recipe_id], "", recipe_id)


func test_every_legacy_house_recipe_has_a_mapping_entry():
	for recipe_id in EarthChunkManager.HOUSE_BLUEPRINT_SHAPE_BY_RECIPE_ID:
		assert_true(EarthChunkManager.BUILDING_ID_BY_RECIPE_ID.has(recipe_id), recipe_id)


func test_every_mapped_building_id_is_a_real_catalog_house():
	for recipe_id in EarthChunkManager.BUILDING_ID_BY_RECIPE_ID:
		var building_id: String = EarthChunkManager.BUILDING_ID_BY_RECIPE_ID[recipe_id]
		if building_id != "":
			assert_true(BuildingCatalog.BUILDING_IDS.has(building_id), "%s -> %s" % [recipe_id, building_id])


# -- can_build_house_from_blueprint: a pure site query ----------------------

func test_can_build_refuses_an_unlearned_blueprint():
	assert_false(manager.can_build_house_from_blueprint("manor", _origin))


func test_can_build_refuses_a_recipe_with_no_whole_building_form():
	manager.record_blueprint_learned_if_new("townhouse_narrow")
	assert_false(manager.can_build_house_from_blueprint("townhouse_narrow", _origin))


func test_can_build_refuses_an_unloaded_chunk():
	manager.record_blueprint_learned_if_new("manor")
	assert_false(manager.can_build_house_from_blueprint("manor", Vector2i(99999, 99999)))


func test_can_build_accepts_a_clear_site():
	manager.record_blueprint_learned_if_new("manor")
	assert_true(manager.can_build_house_from_blueprint("manor", _origin))


func test_can_build_refuses_a_site_whose_footprint_is_occupied():
	manager.record_blueprint_learned_if_new("manor")
	var inside: Vector2i = _origin + Vector2i(1, 1)
	manager.build_at_global(inside.x, inside.y, "campfire")
	assert_false(manager.can_build_house_from_blueprint("manor", _origin))


func test_can_build_refuses_a_site_whose_doorstep_is_occupied():
	manager.record_blueprint_learned_if_new("manor")
	var doorstep := _doorstep("house_large", _origin)
	manager.build_at_global(doorstep.x, doorstep.y, "campfire")
	assert_false(manager.can_build_house_from_blueprint("manor", _origin))


## A doorstep ON a village street is exactly where a house belongs (every
## village house's doorstep is a road cell) -- a road doorstep is accepted;
## only a genuinely occupied one is refused.
func test_can_build_accepts_a_road_doorstep():
	manager.record_blueprint_learned_if_new("manor")
	var doorstep := _doorstep("house_large", _origin)
	manager.build_at_global(doorstep.x, doorstep.y, TerrainRenderer.ROAD_TILE_ID)
	assert_true(manager.can_build_house_from_blueprint("manor", _origin))


func test_can_build_refuses_a_footprint_under_a_road():
	manager.record_blueprint_learned_if_new("manor")
	var inside: Vector2i = _origin + Vector2i(1, 1)
	manager.build_at_global(inside.x, inside.y, TerrainRenderer.ROAD_TILE_ID)
	assert_false(manager.can_build_house_from_blueprint("manor", _origin))


## A building lives in exactly one chunk's record (place_building's own
## contract) -- a footprint that would straddle the chunk edge is refused
## rather than half-placed.
func test_can_build_refuses_a_footprint_that_crosses_the_chunk_edge():
	manager.record_blueprint_learned_if_new("manor")
	var last_column := _chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(EarthChunkManager.CHUNK_SIZE - 1, _origin.y - _chunk_coord.y * EarthChunkManager.CHUNK_SIZE)
	assert_false(manager.can_build_house_from_blueprint("manor", last_column))


# -- stamp_house_and_grant_ownership: one real building + the same ledger ----

func test_stamp_house_places_a_real_building_owned_by_the_household():
	var household := manager.household_store().form_household(PlayerIdentity.PLAYER_ENTITY_ID)

	var project_id := manager.stamp_house_and_grant_ownership("manor", _origin, household.id)

	assert_ne(project_id, "", "a real project id should come back")
	var record := manager.building_at_global(_origin.x, _origin.y)
	assert_eq(record.get("id", ""), "house_large", "a real whole-building house stands at the origin")
	assert_eq(record.get("owner_household_id", ""), household.id)
	for cell in BuildingCatalog.footprint_cells("house_large", _origin):
		var expected := "house_large" if cell == _origin else BuildingCatalog.FOOTPRINT_TILE_ID
		assert_eq(manager.modification_at_global(cell.x, cell.y), expected, str(cell))
	var project := manager.construction_project_store().get_project(project_id)
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
	assert_eq(project.household_id, household.id)
	assert_true(household.property.has(project.property_id()))


func test_stamp_house_never_stamps_legacy_pieces():
	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")
	for cell in BuildingCatalog.footprint_cells("house_small", _origin):
		var tile_id := manager.modification_at_global(cell.x, cell.y)
		assert_ne(tile_id, "wood_floor", str(cell))
		assert_ne(tile_id, "wood_wall", str(cell))
	var chunk = manager._loaded_chunks[_chunk_coord]
	assert_true(chunk.roof_modifications.is_empty(), "no legacy roof pieces")
	assert_true(chunk.furniture_modifications.is_empty(), "no legacy furniture pieces")


func test_stamp_house_settles_a_resident_automatically():
	var project_id := manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")
	var project := manager.construction_project_store().get_project(project_id)
	assert_ne(project.resident_household_id, "", "a completed house already has a real resident")
	assert_ne(project.resident_household_id, "household:owner", "the resident is not the owner")


func test_stamp_house_keeps_a_road_doorstep_paved():
	var doorstep := _doorstep("house_small", _origin)
	manager.build_at_global(doorstep.x, doorstep.y, TerrainRenderer.ROAD_TILE_ID)

	var project_id := manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")

	assert_ne(project_id, "")
	assert_eq(manager.building_at_global(_origin.x, _origin.y).get("id", ""), "house_small")
	assert_eq(manager.modification_at_global(doorstep.x, doorstep.y), TerrainRenderer.ROAD_TILE_ID)


func test_stamp_house_returns_empty_and_places_nothing_for_an_unmapped_recipe():
	assert_eq(manager.stamp_house_and_grant_ownership("townhouse_narrow", _origin, "household:owner"), "")
	assert_true(manager.building_at_global(_origin.x, _origin.y).is_empty())
	assert_eq(manager.modification_at_global(_origin.x, _origin.y), "")


func test_stamp_house_returns_empty_when_the_site_is_occupied():
	var inside: Vector2i = _origin + Vector2i(1, 0)
	manager.build_at_global(inside.x, inside.y, "campfire")
	assert_eq(manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner"), "")
	assert_true(manager.construction_project_store().to_dicts().is_empty(), "no ledger entry for a house that never stood")


## The placed house is a real entity: it can be entered from its doorstep
## like any village house.
func test_a_stamped_house_is_found_by_the_doorstep_scan():
	manager.stamp_house_and_grant_ownership("cottage", _origin, "household:owner")
	var doorstep := _doorstep("house_medium", _origin)
	var record := manager.building_door_near((Vector2(doorstep) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE, 1.0)
	assert_eq(record.get("id", ""), "house_medium")


func test_a_stamped_house_survives_unloading_and_reloading_its_chunk():
	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")
	manager._unload_chunk(_chunk_coord)
	manager._load_chunk(_chunk_coord)
	var record := manager.building_at_global(_origin.x, _origin.y)
	assert_eq(record.get("id", ""), "house_small")
	assert_eq(record.get("owner_household_id", ""), "household:owner")


# -- move-in: docs/concept/workforce.md's "Move-in" section -- a narrow, -----
# -- directly-triggered shortcut, NOT quests.md's full migration system. ----
# -- settle_resident_if_new forms a real, deterministic-from-site resident --
# -- household distinct from the OWNING household stamp_house_and_grant_ ----
# -- ownership already grants property to (see ConstructionProject.own -----
# -- resident_household_id doc comment for why the two are kept separate). --
# -- (Moved here from test_earth_chunk_manager.gd's chunk-(0,0) piece-house -
# -- group when the player's house became a whole-building entity.) --------

func test_settle_resident_if_new_forms_a_real_household():
	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")

	var resident_id := manager.settle_resident_if_new("small_house", _origin)

	assert_ne(resident_id, "")
	assert_not_null(manager.household_store().get_household(resident_id))


## Idempotent -- a house that already has a resident does not get a second
## one just because move-in was asked about twice (the same reasoning
## form_household/record_blueprint_learned_if_new already apply).
func test_settle_resident_if_new_is_idempotent():
	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")

	var first := manager.settle_resident_if_new("small_house", _origin)
	var second := manager.settle_resident_if_new("small_house", _origin)

	assert_eq(first, second)
	assert_eq(manager.event_store().events_of_type("player_house_settled").size(), 1)


## The resident is deliberately NOT the owner -- a player-built house's
## owner (the player) and its resident are genuinely different households,
## unlike a procedurally-generated villager's own house.
func test_settle_resident_if_new_is_a_different_household_from_the_owner():
	var owner := manager.household_store().form_household(PlayerIdentity.PLAYER_ENTITY_ID)
	manager.stamp_house_and_grant_ownership("small_house", _origin, owner.id)

	var resident_id := manager.settle_resident_if_new("small_house", _origin)

	assert_ne(resident_id, owner.id)


## Two different sites resolve to two different residents -- deterministic
## from the site, not a shared constant.
func test_settle_resident_if_new_gives_different_sites_different_residents():
	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")
	var second_origin := _a_second_clear_site_origin("house_small", _origin)
	manager.stamp_house_and_grant_ownership("small_house", second_origin, "household:owner")

	var first := manager.settle_resident_if_new("small_house", _origin)
	var second := manager.settle_resident_if_new("small_house", second_origin)

	assert_ne(first, "")
	assert_ne(second, "")
	assert_ne(first, second)


func test_settle_resident_if_new_records_a_real_event_naming_its_own_project():
	var project_id := manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")

	var resident_id := manager.settle_resident_if_new("small_house", _origin)

	var settled_events := manager.event_store().events_of_type("player_house_settled")
	assert_eq(settled_events.size(), 1)
	assert_eq(settled_events[0].actors, [manager.household_store().get_household(resident_id).members[0]])
	assert_eq(settled_events[0].tags, [project_id])


## The house's own ConstructionProject records who lives there, distinct
## from who owns it (household_id).
func test_settle_resident_if_new_sets_the_projects_own_resident_field():
	var project_id := manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")

	var resident_id := manager.settle_resident_if_new("small_house", _origin)

	var project := manager.construction_project_store().get_project(project_id)
	assert_eq(project.resident_household_id, resident_id)
	assert_eq(project.household_id, "household:owner")


func test_settle_resident_if_new_for_a_site_with_no_real_project_does_nothing():
	assert_eq(manager.settle_resident_if_new("small_house", _origin), "")


## A house built inside a REAL, already-founded settlement's chunk makes its
## resident a real member of that settlement -- mirrors record_player_
## settled_if_new's own household_count_for_settlement wiring exactly, so
## every system that already asks "who lives here" (spare capacity,
## institution thresholds, settlement tier) picks a player-house resident up
## for free.
func test_settle_resident_if_new_joins_a_real_settlements_household_count():
	manager.record_settlement_founded_if_new(_chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(_chunk_coord)
	var before := manager.household_count_for_settlement(settlement_id)

	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")
	manager.settle_resident_if_new("small_house", _origin)

	assert_eq(manager.household_count_for_settlement(settlement_id), before + 1)


## Building far from any real, already-founded settlement still gives the
## house a real resident (pillar 4: "a house is population, not scenery"
## holds regardless) -- it just never joins a settlement that, per record_
## player_settled_if_new's own established reasoning, does not really exist
## ("a settlement with no history is not a settlement").
func test_settle_resident_if_new_still_settles_far_from_any_real_settlement():
	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")

	var resident_id := manager.settle_resident_if_new("small_house", _origin)

	assert_ne(resident_id, "")
	assert_eq(manager.household_count_for_settlement(EntityRef.for_settlement(_chunk_coord)), 0)


## free_workforce_in_chunk reads real, settled residents of player-built
## houses (workforce.md section 6) minus those currently assigned -- NOT a
## bare count of every household anywhere.
func test_free_workforce_in_chunk_counts_settled_unassigned_residents():
	manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")
	var resident_id := manager.settle_resident_if_new("small_house", _origin)

	assert_eq(manager.free_workforce_in_chunk(_chunk_coord), 1)

	manager.assign_resident_to_workplace(resident_id, Vector2i(5, 5))

	assert_eq(
		manager.free_workforce_in_chunk(_chunk_coord), 0,
		"an assigned resident is no longer FREE workforce, even though they are still a real resident"
	)


## A second clear site for `building_id` that does not touch the first
## house's own footprint or doorstep.
func _a_second_clear_site_origin(building_id: String, first_origin: Vector2i) -> Vector2i:
	var footprint := BuildingCatalog.footprint_of(building_id)
	for y in range(2, EarthChunkManager.CHUNK_SIZE - footprint.y - 3):
		for x in range(2, EarthChunkManager.CHUNK_SIZE - footprint.x - 2):
			var origin := _chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(x, y)
			if origin.distance_to(first_origin) < 8.0:
				continue
			if _site_is_clear(building_id, origin):
				return origin
	fail_test("no second clear site for %s in this chunk" % building_id)
	return Vector2i.ZERO


# -- resident happiness reads the building's own interior --------------------
#
# housing.md's appeal_score counts real furniture; for a whole-building
# house that is the record's own "interior" (docs/concept/housing.md
# "Decorating an entered interior"), not the legacy per-tile furniture
# layer the piece pipeline wrote.

func test_resident_happiness_reads_furniture_from_the_building_record():
	manager.record_settlement_founded_if_new(_chunk_coord, [NpcIdentity.new(1)])
	var project_id := manager.stamp_house_and_grant_ownership("small_house", _origin, "household:owner")
	var project := manager.construction_project_store().get_project(project_id)
	var resident_id: String = project.resident_household_id
	# No market stock -- the founded settlement reads DECLINING, and the
	# house is bare: both real signals bad at once.
	assert_eq(manager.resident_happiness(resident_id), "unhappy")

	var chunk = manager._loaded_chunks[_chunk_coord]
	chunk.buildings[project.origin]["interior"] = {Vector2i(1, 1): "wood_chair"}

	assert_eq(manager.resident_happiness(resident_id), "content")
