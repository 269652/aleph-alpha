extends GutTest

const Corpse = preload("res://src/gameplay/corpse.gd")

var corpse: Corpse


func before_each():
	corpse = Corpse.new(Vector2(10, 20), {"wood": 3, "stone": 5}, 100.0)


func test_starts_with_given_held_items():
	assert_eq(corpse.held_items, {"wood": 3, "stone": 5})


func test_starts_not_decayed():
	assert_false(corpse.is_decayed())


func test_starts_with_zero_elapsed_time():
	assert_eq(corpse.elapsed_time, 0.0)


func test_stores_given_position_and_decay_time():
	assert_eq(corpse.position, Vector2(10, 20))
	assert_eq(corpse.decay_time, 100.0)


func test_advance_accumulates_elapsed_time():
	corpse.advance(30.0)
	corpse.advance(10.0)
	assert_eq(corpse.elapsed_time, 40.0)


func test_is_decayed_false_just_before_threshold():
	corpse.advance(99.9)
	assert_false(corpse.is_decayed())


func test_is_decayed_true_at_exact_threshold():
	corpse.advance(100.0)
	assert_true(corpse.is_decayed())


func test_is_decayed_true_past_threshold():
	corpse.advance(150.0)
	assert_true(corpse.is_decayed())


func test_recover_on_fresh_corpse_returns_full_held_items():
	var recovered: Dictionary = corpse.recover()
	assert_eq(recovered, {"wood": 3, "stone": 5})


func test_recover_empties_held_items_so_second_recover_returns_nothing():
	corpse.recover()
	var second_recovery: Dictionary = corpse.recover()
	assert_eq(second_recovery, {})


func test_recover_on_decayed_corpse_returns_nothing():
	corpse.advance(100.0)
	var recovered: Dictionary = corpse.recover()
	assert_eq(recovered, {})


func test_recovered_dictionary_is_a_copy_not_a_reference():
	var recovered: Dictionary = corpse.recover()
	recovered["wood"] = 999
	var second_recovery: Dictionary = corpse.recover()
	assert_eq(second_recovery, {})
