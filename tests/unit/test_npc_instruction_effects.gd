extends GutTest

## Red-first spec for the NPC instruction DSL's impure edge (docs/concept/
## npc_instructions.md, "Turning a resolved action into a real effect is the
## impure edge, mirroring spell_atom_effects.gd's role exactly"):
## npc_instruction_effects.gd turns a resolved haul/gather action descriptor
## into a real inventory change, using whatever real nearest-X-near spatial
## query the live world already exposes for that resource --
## nearest_liftable_stone_near for stone/iron/gold, harvest_peak_fruit_near
## for berries. WOOD IS DELIBERATELY UNSUPPORTED -- see
## npc_instruction_effects.gd's own doc comment for why (no real
## nearest-tree query exists anywhere in this codebase yet, the same gap
## docs/progress.md's "Land Health" entry already documents).

const NpcInstructionEffects = preload("res://src/world/npc_instruction_effects.gd")


## Duck-typed stone node -- exposes queue_free() the same way every real
## Node2D does (see scenes/player.gd's own _try_pick_stone_into_hand, which
## consumes a found stone the identical way: stone.queue_free() directly,
## no Item/Inventory-class round-trip), so the "consume what was found"
## step is exercised without needing a real LiftableStone scene.
class StubStoneNode:
	var freed := false
	func queue_free() -> void:
		freed = true


## Duck-typed world -- exposes only the two real EarthChunkManager queries
## this module actually calls, with canned return values a test controls.
class StubWorld:
	var stone_to_return = null
	var fruit_to_return := {}
	func nearest_liftable_stone_near(_pixel_position: Vector2, _max_distance: float):
		return stone_to_return
	func harvest_peak_fruit_near(_pixel_position: Vector2, _max_distance: float) -> Dictionary:
		return fruit_to_return


# --- stone/iron/gold -> nearest_liftable_stone_near --------------------------

func test_gather_stone_collects_a_real_nearby_stone_into_inventory():
	var world := StubWorld.new()
	var stone := StubStoneNode.new()
	world.stone_to_return = stone
	var action := {"fn": "gather", "resource_tag": "stone"}

	var result: Dictionary = NpcInstructionEffects.dispatch(action, world, Vector2.ZERO, {})

	assert_true(result["ok"])
	assert_eq(result["inventory"]["stone"], 1)
	assert_true(stone.freed, "the found stone must be consumed from the world")


func test_gather_stone_fails_closed_when_nothing_is_near():
	var world := StubWorld.new()
	world.stone_to_return = null
	var action := {"fn": "gather", "resource_tag": "stone"}

	var result: Dictionary = NpcInstructionEffects.dispatch(action, world, Vector2.ZERO, {})

	assert_false(result["ok"])
	assert_eq(result["reason"], "not_found")


func test_iron_and_gold_also_route_through_the_stone_query():
	for resource_id in ["iron", "gold"]:
		var world := StubWorld.new()
		world.stone_to_return = StubStoneNode.new()
		var result: Dictionary = NpcInstructionEffects.dispatch(
			{"fn": "gather", "resource_tag": resource_id}, world, Vector2.ZERO, {}
		)
		assert_true(result["ok"], "expected %s to route through the stone query" % resource_id)
		assert_eq(result["inventory"][resource_id], 1)


## haul shares the same resource-id -> query mapping as gather -- this
## module only implements haul's FETCH half (see its own doc comment on the
## unresolved carry-phase, flagged and not resolved by the concept doc).
func test_haul_stone_uses_the_same_real_query_for_its_fetch_phase():
	var world := StubWorld.new()
	world.stone_to_return = StubStoneNode.new()
	var action := {"fn": "haul", "item": "stone", "destination_tag": "base"}

	var result: Dictionary = NpcInstructionEffects.dispatch(action, world, Vector2.ZERO, {})

	assert_true(result["ok"])
	assert_eq(result["inventory"]["stone"], 1)


# --- berries -> harvest_peak_fruit_near --------------------------------------

func test_gather_berries_collects_real_nearby_fruit_into_inventory():
	var world := StubWorld.new()
	world.fruit_to_return = {"species_id": "cherry", "is_peak": true}
	var action := {"fn": "gather", "resource_tag": "berries"}

	var result: Dictionary = NpcInstructionEffects.dispatch(action, world, Vector2.ZERO, {})

	assert_true(result["ok"])
	assert_eq(result["inventory"]["berries"], 1)


func test_gather_berries_fails_closed_when_nothing_is_near():
	var world := StubWorld.new()
	world.fruit_to_return = {}
	var action := {"fn": "gather", "resource_tag": "berries"}

	var result: Dictionary = NpcInstructionEffects.dispatch(action, world, Vector2.ZERO, {})

	assert_false(result["ok"])
	assert_eq(result["reason"], "not_found")


# --- wood: deliberately unsupported, fails closed with a clear result ------

func test_wood_fails_closed_with_a_clear_not_supported_result_rather_than_crashing():
	var world := StubWorld.new()
	var action := {"fn": "gather", "resource_tag": "wood"}

	var result: Dictionary = NpcInstructionEffects.dispatch(action, world, Vector2.ZERO, {})

	assert_false(result["ok"])
	assert_eq(result["reason"], "unsupported_resource")
	assert_eq(result["resource_id"], "wood")


func test_wood_via_haul_also_fails_closed():
	var world := StubWorld.new()
	var action := {"fn": "haul", "item": "wood", "destination_tag": "base"}

	var result: Dictionary = NpcInstructionEffects.dispatch(action, world, Vector2.ZERO, {})

	assert_false(result["ok"])
	assert_eq(result["reason"], "unsupported_resource")


# --- fails open, never crashes ------------------------------------------------

func test_dispatch_never_crashes_with_a_null_world():
	var result: Dictionary = NpcInstructionEffects.dispatch(
		{"fn": "gather", "resource_tag": "stone"}, null, Vector2.ZERO, {}
	)
	assert_false(result["ok"])
	assert_eq(result["reason"], "not_found")


func test_dispatch_never_mutates_the_passed_in_inventory():
	var world := StubWorld.new()
	world.stone_to_return = StubStoneNode.new()
	var original := {"stone": 2}
	NpcInstructionEffects.dispatch({"fn": "gather", "resource_tag": "stone"}, world, Vector2.ZERO, original)
	assert_eq(original["stone"], 2, "dispatch must be pure w.r.t. the caller's inventory Dictionary")
