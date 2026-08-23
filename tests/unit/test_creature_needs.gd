extends GutTest

const CreatureNeeds = preload("res://src/gameplay/creature_needs.gd")

var needs: CreatureNeeds


func before_each():
	needs = CreatureNeeds.new()


func test_starts_sated_and_hydrated():
	assert_eq(needs.hunger, 0.0)
	assert_eq(needs.thirst, 0.0)
	assert_false(needs.is_hungry())
	assert_false(needs.is_thirsty())


func test_hunger_and_thirst_rise_over_time():
	needs.advance(1.0)
	assert_gt(needs.hunger, 0.0)
	assert_gt(needs.thirst, 0.0)


func test_hunger_and_thirst_clamp_at_one():
	needs.advance(100000.0)
	assert_eq(needs.hunger, 1.0)
	assert_eq(needs.thirst, 1.0)


func test_becomes_hungry_once_past_the_threshold():
	assert_false(needs.is_hungry())
	while needs.hunger < CreatureNeeds.HUNGRY_THRESHOLD:
		needs.advance(1.0)
	assert_true(needs.is_hungry())


func test_becomes_thirsty_once_past_the_threshold():
	assert_false(needs.is_thirsty())
	while needs.thirst < CreatureNeeds.THIRSTY_THRESHOLD:
		needs.advance(1.0)
	assert_true(needs.is_thirsty())


func test_feeding_resets_hunger():
	needs.advance(100000.0)
	assert_true(needs.is_hungry())
	needs.feed()
	assert_eq(needs.hunger, 0.0)
	assert_false(needs.is_hungry())


func test_drinking_resets_thirst():
	needs.advance(100000.0)
	assert_true(needs.is_thirsty())
	needs.drink()
	assert_eq(needs.thirst, 0.0)
	assert_false(needs.is_thirsty())


func test_feeding_does_not_affect_thirst_and_vice_versa():
	needs.advance(100000.0)
	needs.feed()
	assert_eq(needs.thirst, 1.0)
	needs.drink()
	assert_eq(needs.hunger, 0.0)


# -- a herd is not synchronised ----------------------------------------------
#
# Every creature started at hunger 0 and rose at the same fixed rate, so an
# entire herd crossed HUNGRY_THRESHOLD on the same tick, all switched to the
# "eat" action in the same frame, and all generated their eat frames at once
# (see ProceduralAnimalAnimation.LOOK_VARIANTS -- 1.18 seconds of drawing
# inside one 5-second window). Real animals are not on one clock, and neither
# the simulation nor the frame budget should assume they are.

func test_two_animals_do_not_get_hungry_on_the_same_tick():
	var first := CreatureNeeds.new(11)
	var second := CreatureNeeds.new(12)
	assert_ne(first.hunger, second.hunger, "each animal starts somewhere else in its own cycle")


func test_a_staggered_start_is_deterministic():
	assert_eq(CreatureNeeds.new(11).hunger, CreatureNeeds.new(11).hunger)


## The stagger must not start an animal already starving, or it would seek
## food the instant it spawned.
func test_no_animal_starts_out_already_hungry():
	for seed_value in 50:
		var needs := CreatureNeeds.new(seed_value)
		assert_false(needs.is_hungry(), "seed %d starts fed" % seed_value)
		assert_false(needs.is_thirsty(), "seed %d starts watered" % seed_value)


## Spread across the herd rather than clustered: over many individuals the
## first-hunger times should land all over the interval, not in one bunch.
func test_the_herd_spreads_across_the_run_up_to_hunger():
	var buckets := {}
	for seed_value in 40:
		var fraction: float = CreatureNeeds.new(seed_value).hunger / CreatureNeeds.START_STAGGER
		buckets[int(fraction * 4.0)] = true
	assert_gte(buckets.size(), 4, "hunger onset is spread over the herd, not bunched")


## The default (no seed) stays exactly as it was, so every existing caller and
## test that constructs a plain CreatureNeeds is unaffected.
func test_an_unseeded_creature_still_starts_from_nothing():
	assert_eq(CreatureNeeds.new().hunger, 0.0)
	assert_eq(CreatureNeeds.new().thirst, 0.0)
