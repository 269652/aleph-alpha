extends GutTest

## The guild chest, live (docs/concept/village_estates.md's second novel
## mechanic). A guild's relief chest lives on the Institution itself -- the
## same reason a household's standing lives on the Household: an
## institution is this project's persistent unit for a body of people, so
## InstitutionStorePersistence carries the chest with no new file and no
## second source of truth.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const Institution = preload("res://src/emergence/institution.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")

const CHUNK := Vector2i(5151, 5151)

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _settlement_id: String


class FakeNpc:
	extends RefCounted
	var seed_value: int
	func _init(a_seed: int) -> void:
		seed_value = a_seed


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	_settlement_id = EntityRef.for_settlement(CHUNK)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _found(count: int) -> Array:
	var npcs: Array = []
	for i in count:
		npcs.append(FakeNpc.new(700_000 + i))
	manager.record_settlement_founded_if_new(CHUNK, npcs)
	return manager.household_ids_in_settlement(_settlement_id)


func _form_guild(household_ids: Array) -> Institution:
	return manager.institution_store().form("guild", household_ids, 0.0)


# -- the chest is a real, persisted property of the institution ----------

func test_a_new_institution_holds_an_empty_chest():
	assert_eq(Institution.new("guild", [], 0.0).chest, {})


func test_a_chest_survives_a_save_and_a_load():
	var store := InstitutionStore.new()
	var guild := store.form("guild", ["household:1", "household:2"], 0.0)
	guild.chest = {"wood": 12.5}

	var reloaded = InstitutionStore.from_dicts(store.to_dicts())
	assert_almost_eq(float(reloaded.get_institution(guild.id).chest["wood"]), 12.5, 0.0001)


## A save written before chests existed reads back with an empty one, not
## with a missing key every later read then fails on.
func test_a_save_from_before_chests_existed_reads_back_with_an_empty_one():
	var reloaded = InstitutionStore.from_dicts([
		{"id": "inst_0_guild", "type": "guild", "members": ["household:1"], "leader": "",
		 "goals": [], "status": Institution.ACTIVE, "created_at": 0.0},
	])
	assert_eq(reloaded.get_institution("inst_0_guild").chest, {})


# -- a village finds its own guild ---------------------------------------

func test_a_village_with_no_guild_has_no_chest_to_draw_on():
	_found(4)
	assert_null(manager.guild_for_settlement(_settlement_id))


func test_a_village_whose_households_formed_a_guild_finds_it():
	var households := _found(4)
	var guild := _form_guild([households[0], households[1]])
	assert_eq(manager.guild_for_settlement(_settlement_id).id, guild.id)


## A guild that dissolved is not a guild any more, and its chest is not a
## larder the village can still eat out of.
func test_a_dissolved_guild_is_not_found():
	var households := _found(4)
	var guild := _form_guild([households[0], households[1]])
	manager.institution_store().dissolve(guild.id, 0.0)
	assert_null(manager.guild_for_settlement(_settlement_id))


## Only a GUILD. A militia is a real institution and holds no relief chest.
func test_a_militia_is_not_mistaken_for_a_guild():
	var households := _found(4)
	manager.institution_store().form("militia", [households[0], households[1]], 0.0)
	assert_null(manager.guild_for_settlement(_settlement_id))


# -- and it really carries the village -----------------------------------

## The claim the whole mechanic exists for, end to end: two identical
## villages with nothing on the shelf, and the one whose guild banked
## firewood reads better supplied than the one that has none.
func test_a_guilds_chest_really_carries_its_village_through_a_shortage():
	var households := _found(5)
	var guild := _form_guild(households)
	guild.chest = {VillageEstates.FUEL_ITEM_ID: 500.0}
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	var relieved: float = float(
		manager.estate_satisfaction_for_settlement(_settlement_id).get(VillageEstates.FUEL_ITEM_ID, 0.0)
	)
	assert_almost_eq(relieved, 1.0, 0.0001, "the guild's chest did not reach its own village")
	assert_true(
		float(guild.chest.get(VillageEstates.FUEL_ITEM_ID, 0.0)) < 500.0,
		"the village was relieved out of a chest that never went down"
	)


## A supplied village banks instead of drawing, which is what fills the
## chest in the first place.
func test_a_supplied_village_really_banks_into_its_guilds_chest():
	var households := _found(5)
	var guild := _form_guild(households)
	manager.market_store().market_for(_settlement_id).add_stock(VillageEstates.FUEL_ITEM_ID, 400)
	manager.market_store().market_for(_settlement_id).add_stock("herb", 400)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_true(
		float(guild.chest.get(VillageEstates.FUEL_ITEM_ID, 0.0)) > 0.0,
		"a supplied guild village banked nothing at all"
	)


## And a village with no guild is untouched end to end -- the mechanic can
## never change a village that has no guild to run it.
func test_a_village_with_no_guild_behaves_exactly_as_before():
	_found(5)
	var market = manager.market_store().market_for(_settlement_id)
	market.add_stock(VillageEstates.FUEL_ITEM_ID, 400)
	var before: int = market.stock_of(VillageEstates.FUEL_ITEM_ID)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	var drawn: int = before - market.stock_of(VillageEstates.FUEL_ITEM_ID)
	assert_true(drawn >= 0 and drawn < 10, "a guildless village lost stock to a chest it has not got")
