extends GutTest

## NpcNeeds (docs/concept/npc.md "Needs and the local production economy":
## "NPCs get real hunger... Same shape as creature_needs.gd (hunger rises
## per second, is_hungry(), feed())") -- deliberately hunger-only, mirroring
## CreatureNeeds' pattern (hash-seeded stagger via seed_value, per-second
## rise, is_hungry()/feed()) without extending that class: thirst has no
## NPC-side consumer in this pass (the spec's own scope), so bolting an
## unused field on would misrepresent what's actually simulated.

const NpcNeeds = preload("res://src/world/npc_needs.gd")

var needs: NpcNeeds


func before_each():
	needs = NpcNeeds.new()


func test_starts_sated():
	assert_eq(needs.hunger, 0.0)
	assert_false(needs.is_hungry())


func test_hunger_rises_over_time():
	needs.advance(1.0)
	assert_gt(needs.hunger, 0.0)


func test_hunger_clamps_at_one():
	needs.advance(100000.0)
	assert_eq(needs.hunger, 1.0)


func test_becomes_hungry_once_past_the_threshold():
	assert_false(needs.is_hungry())
	while needs.hunger < NpcNeeds.HUNGRY_THRESHOLD:
		needs.advance(1.0)
	assert_true(needs.is_hungry())


func test_feeding_resets_hunger():
	needs.advance(100000.0)
	assert_true(needs.is_hungry())
	needs.feed()
	assert_eq(needs.hunger, 0.0)
	assert_false(needs.is_hungry())


# -- a village is not synchronised (mirrors CreatureNeeds' same herd-stagger
# reasoning: every NPC starting hunger at exactly 0 would cross the hungry
# threshold on the same tick and all queue for the market at once) ---------

func test_two_npcs_do_not_get_hungry_on_the_same_tick():
	var first := NpcNeeds.new(11)
	var second := NpcNeeds.new(12)
	assert_ne(first.hunger, second.hunger, "each NPC starts somewhere else in its own cycle")


func test_a_staggered_start_is_deterministic():
	assert_eq(NpcNeeds.new(11).hunger, NpcNeeds.new(11).hunger)


func test_no_npc_starts_out_already_hungry():
	for seed_value in 50:
		var staggered := NpcNeeds.new(seed_value)
		assert_false(staggered.is_hungry(), "seed %d starts fed" % seed_value)


func test_an_unseeded_npc_still_starts_from_nothing():
	assert_eq(NpcNeeds.new().hunger, 0.0)
