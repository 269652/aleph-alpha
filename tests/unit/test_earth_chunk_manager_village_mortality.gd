extends GutTest

## A villager's death, as the settlement sees it (docs/concept/
## village_mortality.md mechanism 3).
##
## A death is a DEPARTURE WITH A REASON, not a second mechanism beside it:
## it goes out through the same `npc_departed` event the estate exodus
## already appends, so _households_in_settlement, the census, the tier, the
## growth ladder and the settlement card all see it with no new plumbing.
##
## In-memory only -- record_settlement_founded_if_new and a FakeNpc, no
## chunk loading -- the same fast fixture
## test_earth_chunk_manager_village_estates.gd uses.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

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


const _FIRST_SEED := 770_000


## Founds a settlement of `count` villagers and returns their seeds, so a
## test can name exactly who dies.
func _found(count: int) -> Array:
	var npcs: Array = []
	var seeds: Array = []
	for i in count:
		npcs.append(FakeNpc.new(_FIRST_SEED + i))
		seeds.append(_FIRST_SEED + i)
	manager.record_settlement_founded_if_new(CHUNK, npcs)
	return seeds


func _roster() -> int:
	return manager.household_count_for_settlement(_settlement_id)


func test_a_villager_who_dies_leaves_the_roster():
	var seeds := _found(3)
	assert_eq(_roster(), 3, "precondition: three live here")
	assert_true(manager.record_villager_death(_settlement_id, seeds[0]))
	assert_eq(_roster(), 2, "the dead were still counted among the living")


func test_the_others_are_untouched():
	var seeds := _found(3)
	manager.record_villager_death(_settlement_id, seeds[1])
	assert_eq(_roster(), 2)
	# The survivors, not whoever happened to be left.
	var living: Array = manager.household_ids_in_settlement(_settlement_id)
	var died = manager.household_store().household_for(EntityRef.for_npc(seeds[1]))
	assert_false(living.has(died.id), "the villager who died is still on the roster")


func test_dying_twice_is_still_one_death():
	var seeds := _found(3)
	manager.record_villager_death(_settlement_id, seeds[0])
	manager.record_villager_death(_settlement_id, seeds[0])
	assert_eq(_roster(), 2, "one death cost the village two households")


func test_a_villager_who_never_lived_here_cannot_die_here():
	_found(3)
	assert_false(manager.record_villager_death(_settlement_id, 999_999))
	assert_eq(_roster(), 3)


## The village can recover: a death frees a place, and somebody new is a
## NEW household rather than the dead one walking back in.
func test_the_dead_are_not_readmitted_by_a_later_arrival():
	var seeds := _found(3)
	manager.record_villager_death(_settlement_id, seeds[0])
	assert_eq(_roster(), 2, "precondition")
	manager.admit_household(CHUNK)
	assert_eq(_roster(), 3, "the village could not take anybody in after a death")
	var died = manager.household_store().household_for(EntityRef.for_npc(seeds[0]))
	assert_false(
		manager.household_ids_in_settlement(_settlement_id).has(died.id),
		"the dead villager was readmitted"
	)
