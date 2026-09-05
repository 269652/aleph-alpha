extends GutTest

const CreatureNeeds = preload("res://src/gameplay/creature_needs.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")

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


# -- warmth ------------------------------------------------------------------
#
# Reported live: a kept horse's cold was not visible anywhere. It was not
# visible because it did not exist -- animals tracked hunger and thirst and
# nothing about being out in weather, while the PLAYER standing next to them
# had a full body-temperature meter.
#
# Deliberately the same model the player already uses (SurvivalMeters.warmth /
# regulate_temperature): warmth eases toward a local ambient target rather than
# snapping, and the ambient figure comes from the same
# EarthChunkManager.ambient_warmth the player's own meter reads. One climate,
# one answer -- an animal and the player standing on the same tile in the same
# storm should not disagree about how cold it is there.

func test_an_animal_starts_comfortable():
	var needs := CreatureNeeds.new(1)
	assert_almost_eq(needs.warmth, 1.0, 0.001)
	assert_false(needs.is_cold())


func test_standing_somewhere_cold_cools_the_animal_down():
	var needs := CreatureNeeds.new(1)
	needs.regulate_temperature(0.0, 10.0)
	assert_lt(needs.warmth, 1.0)


## Eased, not snapped -- the same reason the player's meter eases: walking one
## step into shelter should warm an animal up over a moment, not instantly.
func test_warmth_eases_toward_the_ambient_rather_than_snapping_to_it():
	var needs := CreatureNeeds.new(1)
	needs.regulate_temperature(0.0, 0.1)
	assert_gt(needs.warmth, 0.0, "one short step should not empty the meter")


func test_a_cold_animal_warms_back_up_somewhere_warm():
	var needs := CreatureNeeds.new(1)
	needs.regulate_temperature(0.0, 60.0)
	var chilled := needs.warmth
	needs.regulate_temperature(1.0, 60.0)
	assert_gt(needs.warmth, chilled)


func test_warmth_never_leaves_its_range():
	var needs := CreatureNeeds.new(1)
	needs.regulate_temperature(0.0, 10000.0)
	assert_between(needs.warmth, 0.0, 1.0)
	needs.regulate_temperature(1.0, 10000.0)
	assert_between(needs.warmth, 0.0, 1.0)


## The verdict the readouts branch on, at the same threshold the player's own
## meter uses -- an animal and a person on the same tile agreeing about what
## "cold" means is the point of sharing the model.
func test_cold_is_the_same_threshold_the_player_uses():
	var needs := CreatureNeeds.new(1)
	needs.warmth = SurvivalMeters.COLD_THRESHOLD - 0.01
	assert_true(needs.is_cold())
	needs.warmth = SurvivalMeters.COLD_THRESHOLD + 0.01
	assert_false(needs.is_cold())


# -- one drive vector underneath (docs/concept/ethogram.md §5, slice 3) --------

const Ethogram = preload("res://src/gameplay/ethogram.gd")


## CreatureNeeds is now a facade over Drives with the mammal profile: its
## numbers are the ethogram record, not a second copy.
func test_the_numbers_are_the_ethograms_mammal_profile():
	var profile := Ethogram.drive_profile("", "mammal")
	assert_almost_eq(CreatureNeeds.HUNGER_RATE_PER_SECOND, 1.0 / profile["hunger"]["rise_seconds"], 0.000001)
	assert_almost_eq(CreatureNeeds.THIRST_RATE_PER_SECOND, 1.0 / profile["thirst"]["rise_seconds"], 0.000001)
	assert_almost_eq(CreatureNeeds.HUNGRY_THRESHOLD, profile["hunger"]["threshold"], 0.0)
	assert_almost_eq(CreatureNeeds.START_STAGGER, profile["hunger"]["stagger"], 0.0)


## The drives are the gains the behaviour kernel gates on.
func test_gains_are_the_needs_as_gates():
	assert_eq(needs.gains(), {"hunger": 0.0, "thirst": 0.0})
	needs.advance(100000.0)
	assert_eq(needs.gains(), {"hunger": 1.0, "thirst": 1.0})
	needs.drink()
	assert_eq(needs.gains()["thirst"], 0.0)
