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
