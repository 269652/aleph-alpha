extends GutTest

## docs/concept/village_economy_balance.md mechanism 6, wired: the assembly
## is told how many of a settlement's households hold a trade that works a
## field -- the conscripted roster's trades, which are who really farms --
## so the next farmstead is voted for while one of them stands without one.
##
## In memory, without a chunk, like the other settlement-step suites.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const SettlementFoodDemand = preload("res://src/emergence/settlement_food_demand.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const CHUNK := Vector2i(4646, 4646)

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
		npcs.append(FakeNpc.new(950_000 + i))
	manager.record_settlement_founded_if_new(CHUNK, npcs)
	return manager.household_ids_in_settlement(_settlement_id)


## The field hands the assembly is told about are the households of the
## roster this settlement really spawns -- conscription included.
func test_the_assembly_is_told_how_many_households_work_a_field():
	var households := _found(6)
	var state: Dictionary = manager._village_assembly_state(CHUNK)
	assert_true(state.has("field_hands"), "the assembly was never told")
	var roster: Dictionary = manager._settlement_generator.generate_settlement(
		CHUNK, CHUNK * EarthChunkManager.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE,
		TerrainRenderer.TILE_SIZE, households.size(), manager._is_dry_local(CHUNK),
		manager.seeded_region_for_chunk(CHUNK)
	)
	var expected := 0
	for npc in roster.npcs:
		if VillageFarm.crop_for(npc.occupation) != "":
			expected += 1
	assert_eq(int(state["field_hands"]), expected)
	assert_between(int(state["field_hands"]), 0, households.size())


## And the founding roster's conscription is what the count reflects: the
## field hands, with whoever fishes beside them, are at least the producers
## the village's own demand asks for.
func test_the_field_hands_and_the_fishers_are_at_least_what_demand_conscripted():
	var households := _found(6)
	var state: Dictionary = manager._village_assembly_state(CHUNK)
	var roster: Dictionary = manager._settlement_generator.generate_settlement(
		CHUNK, CHUNK * EarthChunkManager.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE,
		TerrainRenderer.TILE_SIZE, households.size(), manager._is_dry_local(CHUNK),
		manager.seeded_region_for_chunk(CHUNK)
	)
	var fishers := 0
	for npc in roster.npcs:
		if npc.occupation == "fisher":
			fishers += 1
	assert_gte(
		int(state["field_hands"]) + fishers, SettlementFoodDemand.producers_needed(households.size())
	)


func test_a_settlement_nobody_founded_has_no_assembly_state_at_all():
	assert_eq(manager._village_assembly_state(Vector2i(4647, 4647)), {})
