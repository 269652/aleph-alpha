extends GutTest

const LivesTracker = preload("res://src/gameplay/lives_tracker.gd")

var tracker: LivesTracker


func before_each():
	tracker = LivesTracker.new()


func test_starts_at_default_life_count():
	assert_eq(tracker.lives_remaining, 9)


func test_constructor_accepts_custom_starting_lives():
	var custom_tracker := LivesTracker.new(3)
	assert_eq(custom_tracker.lives_remaining, 3)


func test_lose_life_decrements_by_one():
	tracker.lose_life()
	assert_eq(tracker.lives_remaining, 8)


func test_lose_life_returns_true_while_lives_remain():
	var still_alive := tracker.lose_life()
	assert_true(still_alive)


func test_lose_life_on_last_life_returns_false():
	var single_life_tracker := LivesTracker.new(1)
	var still_alive := single_life_tracker.lose_life()
	assert_false(still_alive)


func test_lose_life_on_last_life_sets_permanently_dead():
	var single_life_tracker := LivesTracker.new(1)
	single_life_tracker.lose_life()
	assert_true(single_life_tracker.is_permanently_dead())


func test_is_permanently_dead_false_while_lives_remain():
	assert_false(tracker.is_permanently_dead())


func test_lose_life_never_goes_below_zero():
	var single_life_tracker := LivesTracker.new(1)
	single_life_tracker.lose_life()
	single_life_tracker.lose_life()
	single_life_tracker.lose_life()
	assert_eq(single_life_tracker.lives_remaining, 0)


func test_add_life_increases_count():
	tracker.add_life()
	assert_eq(tracker.lives_remaining, 10)


func test_add_life_with_custom_amount():
	tracker.add_life(3)
	assert_eq(tracker.lives_remaining, 12)


func test_add_life_revives_after_permadeath():
	var single_life_tracker := LivesTracker.new(1)
	single_life_tracker.lose_life()
	assert_true(single_life_tracker.is_permanently_dead())
	single_life_tracker.add_life()
	assert_false(single_life_tracker.is_permanently_dead())
