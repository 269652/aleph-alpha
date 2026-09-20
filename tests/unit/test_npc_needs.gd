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


# -- one drive vector underneath (docs/concept/ethogram.md §5, slice 3) --------

const Ethogram = preload("res://src/gameplay/ethogram.gd")


## NpcNeeds is now a facade over Drives with the villager profile -- the
## copy of CreatureNeeds it used to be is one implementation again.
func test_the_numbers_are_the_ethograms_villager_profile():
	var profile := Ethogram.drive_profile("", "villager")
	assert_almost_eq(NpcNeeds.HUNGER_RATE_PER_SECOND, 1.0 / profile["hunger"]["rise_seconds"], 0.000001)
	assert_almost_eq(NpcNeeds.HUNGRY_THRESHOLD, profile["hunger"]["threshold"], 0.0)
	assert_almost_eq(NpcNeeds.START_STAGGER, profile["hunger"]["stagger"], 0.0)
	# All four now, not hunger alone: a villager really gets thirsty, tired
	# and lonely (docs/concept/npc_social_life.md), and every one of them is
	# on the same drive vector underneath.
	assert_eq(needs.gains().keys(), profile.keys())
	assert_true(needs.gains().has("hunger"))


# -- starving (docs/concept/village_mortality.md mechanism 1) ---------------
#
# The clock lives here, beside the drive it reads, so it advances on
# exactly the same advance(delta) every villager already ticks -- a
# villager with no world still ages normally, and no caller has to
# remember to tick a second thing.

const Starvation = preload("res://src/emergence/starvation.gd")


func test_a_fresh_villager_is_not_starving():
	var needs := NpcNeeds.new(7)
	assert_eq(needs.starved_seconds, 0.0)
	assert_false(needs.has_starved_to_death())


func test_hunger_left_to_rise_eventually_kills():
	var needs := NpcNeeds.new()
	# Long enough to empty, then long enough at the top to die.
	needs.advance(Starvation.hunger_cycle_seconds())
	assert_false(needs.has_starved_to_death(), "precondition: emptying alone is not fatal")
	needs.advance(Starvation.seconds_to_die())
	assert_true(needs.has_starved_to_death())


func test_a_villager_who_eats_never_starves():
	var needs := NpcNeeds.new()
	for i in 200:
		needs.advance(Starvation.hunger_cycle_seconds() * 0.5)
		needs.feed()
	assert_false(needs.has_starved_to_death())
	assert_eq(needs.starved_seconds, 0.0)


## The cart of grain arriving mid-famine really does save them.
func test_a_meal_at_the_last_moment_saves_them():
	var needs := NpcNeeds.new()
	needs.advance(Starvation.hunger_cycle_seconds())
	needs.advance(Starvation.seconds_to_die() * 0.9)
	assert_false(needs.has_starved_to_death(), "precondition: not dead yet")
	needs.feed()
	assert_eq(needs.starved_seconds, 0.0, "a fed villager is still dying from last week")
	assert_false(needs.has_starved_to_death())
