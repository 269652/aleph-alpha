extends GutTest

## One drive vector (docs/concept/ethogram.md §5, slice 3): the single clock
## behind every "rises over time, crosses a threshold, a meal takes it back
## down" need in the game. The numbers are a PROFILE -- per body plan or
## species, held in the ethogram -- so a horse, a villager, a songbird and a
## kingfisher run one implementation at their own rates.

const Drives = preload("res://src/gameplay/drives.gd")


## A profile with round numbers so the arithmetic is legible: hunger takes
## 100 s to go from nothing to starving, is urgent from half way, and a meal
## takes it all the way back; thirst is a partial-meal drive.
func _profile() -> Dictionary:
	return {
		"hunger": {"rise_seconds": 100.0, "threshold": 0.5, "meal": 1.0},
		"thirst": {"rise_seconds": 50.0, "threshold": 0.5, "meal": 0.3},
	}


# -- rising, urgency, meals ---------------------------------------------------

func test_every_drive_starts_at_nothing_by_default():
	var drives := Drives.new(_profile())
	assert_eq(drives.level("hunger"), 0.0)
	assert_eq(drives.level("thirst"), 0.0)
	assert_false(drives.is_urgent("hunger"))


func test_a_drive_rises_to_one_over_its_rise_seconds_and_clamps():
	var drives := Drives.new(_profile())
	drives.advance(25.0)
	assert_almost_eq(drives.level("hunger"), 0.25, 0.0001)
	assert_almost_eq(drives.level("thirst"), 0.5, 0.0001)
	drives.advance(100000.0)
	assert_eq(drives.level("hunger"), 1.0)
	assert_eq(drives.level("thirst"), 1.0)


func test_a_drive_is_urgent_from_its_threshold():
	var drives := Drives.new(_profile())
	drives.advance(49.0)
	assert_false(drives.is_urgent("hunger"))
	drives.advance(1.0)
	assert_true(drives.is_urgent("hunger"))


func test_a_full_meal_resets_a_drive_and_a_partial_one_takes_its_share():
	var drives := Drives.new(_profile())
	drives.advance(100000.0)
	drives.satisfy("hunger")
	assert_eq(drives.level("hunger"), 0.0)
	drives.satisfy("thirst")
	assert_almost_eq(drives.level("thirst"), 0.7, 0.0001)
	drives.satisfy("thirst")
	drives.satisfy("thirst")
	drives.satisfy("thirst")
	assert_eq(drives.level("thirst"), 0.0, "never below nothing")


func test_satisfying_one_drive_leaves_the_others_alone():
	var drives := Drives.new(_profile())
	drives.advance(100000.0)
	drives.satisfy("hunger")
	assert_eq(drives.level("thirst"), 1.0)


func test_a_profile_may_start_a_drive_part_way():
	var drives := Drives.new({"hunger": {"rise_seconds": 10.0, "threshold": 1.0, "meal": 1.0, "start": 1.0}})
	assert_eq(drives.level("hunger"), 1.0)
	assert_true(drives.is_urgent("hunger"))


func test_an_unknown_drive_is_nothing_and_never_urgent():
	var drives := Drives.new(_profile())
	assert_eq(drives.level("nonesuch"), 0.0)
	assert_false(drives.is_urgent("nonesuch"))
	assert_eq(drives.gain("nonesuch"), 0.0)


# -- the herd is not on one clock ----------------------------------------------

func _staggered() -> Dictionary:
	return {"hunger": {"rise_seconds": 100.0, "threshold": 0.5, "meal": 1.0, "stagger": 0.45}}


func test_two_individuals_do_not_get_hungry_on_the_same_tick():
	assert_ne(Drives.new(_staggered(), 11).level("hunger"), Drives.new(_staggered(), 12).level("hunger"))


func test_a_staggered_start_is_deterministic():
	assert_eq(Drives.new(_staggered(), 11).level("hunger"), Drives.new(_staggered(), 11).level("hunger"))


func test_no_staggered_individual_starts_out_already_urgent():
	for seed_value in 50:
		assert_false(Drives.new(_staggered(), seed_value).is_urgent("hunger"), "seed %d" % seed_value)


func test_the_stagger_spreads_across_the_run_up():
	var buckets := {}
	for seed_value in 40:
		var fraction: float = Drives.new(_staggered(), seed_value).level("hunger") / 0.45
		buckets[int(fraction * 4.0)] = true
	assert_gte(buckets.size(), 4)


func test_an_unseeded_individual_starts_from_nothing_even_with_a_stagger():
	assert_eq(Drives.new(_staggered()).level("hunger"), 0.0)


## The stagger is the same hash CreatureNeeds and NpcNeeds used, so every
## animal and villager already in the world keeps the onset it had.
func test_the_stagger_is_the_needs_modules_own_hash():
	var expected := float(absi(hash("%d_%s_need" % [11, "hunger"])) % 10000) / 10000.0 * 0.45
	assert_almost_eq(Drives.new(_staggered(), 11).level("hunger"), expected, 0.000001)


# -- gains: drives as the kernel's gates ----------------------------------------

## By default a gain is the step the needs modules always were: nothing
## below the threshold, fully open from it.
func test_the_gain_is_a_step_at_the_threshold_by_default():
	var drives := Drives.new(_profile())
	drives.advance(49.0)
	assert_eq(drives.gain("hunger"), 0.0)
	drives.advance(1.0)
	assert_eq(drives.gain("hunger"), 1.0)


## A profile may open the gate gradually from an onset below the threshold,
## so a slightly hungry animal is slightly interested (ethogram.md §5).
func test_a_profile_with_an_onset_ramps_the_gain_up_to_the_threshold():
	var drives := Drives.new({"hunger": {"rise_seconds": 100.0, "threshold": 0.5, "meal": 1.0, "onset": 0.3}})
	drives.advance(30.0)
	assert_almost_eq(drives.gain("hunger"), 0.0, 0.0001)
	drives.advance(10.0)
	assert_almost_eq(drives.gain("hunger"), 0.5, 0.0001)
	drives.advance(10.0)
	assert_almost_eq(drives.gain("hunger"), 1.0, 0.0001)
	drives.advance(50.0)
	assert_almost_eq(drives.gain("hunger"), 1.0, 0.0001, "never above one")


func test_gains_lists_every_drive_in_the_profile():
	var drives := Drives.new(_profile())
	drives.advance(60.0)
	var gains := drives.gains()
	assert_eq(gains.size(), 2)
	assert_eq(gains["hunger"], 1.0)
	assert_eq(gains["thirst"], 1.0)


# -- the stateless helpers the bird facades run on ------------------------------

func test_advanced_and_after_meal_are_the_same_arithmetic_without_the_state():
	assert_almost_eq(Drives.advanced(0.2, 100.0, 30.0), 0.5, 0.0001)
	assert_eq(Drives.advanced(0.9, 100.0, 100000.0), 1.0)
	assert_eq(Drives.advanced(0.5, 100.0, -5.0), 0.5, "time does not run backwards")
	assert_almost_eq(Drives.after_meal(1.0, 0.7), 0.3, 0.0001)
	assert_eq(Drives.after_meal(0.4, 1.0), 0.0)
