extends GutTest

const DebuffStack = preload("res://src/gameplay/debuff_stack.gd")

var stack: DebuffStack


func before_each():
	stack = DebuffStack.new()


func test_apply_on_fresh_id_creates_entry_with_one_stack():
	var active := stack.apply([], "poison", 5.0, 3)
	assert_eq(active.size(), 1)
	assert_eq(active[0]["debuff_id"], "poison")
	assert_eq(active[0]["stacks"], 1)
	assert_eq(active[0]["time_remaining"], 5.0)


func test_apply_same_id_again_increases_stacks():
	var active := stack.apply([], "poison", 5.0, 3)
	active = stack.apply(active, "poison", 5.0, 3)
	assert_eq(stack.stacks_of(active, "poison"), 2)


func test_apply_beyond_max_stacks_does_not_exceed_cap():
	var active := []
	for i in 5:
		active = stack.apply(active, "poison", 5.0, 3)
	assert_eq(stack.stacks_of(active, "poison"), 3)


func test_apply_same_id_resets_time_remaining_to_full_duration():
	var active := stack.apply([], "poison", 5.0, 3)
	active = stack.advance(active, 4.0)
	active = stack.apply(active, "poison", 5.0, 3)
	assert_eq(active[0]["time_remaining"], 5.0)


func test_apply_does_not_mutate_callers_original_array():
	var original := []
	var active := stack.apply(original, "poison", 5.0, 3)
	assert_eq(original.size(), 0)
	assert_eq(active.size(), 1)


func test_advance_reduces_time_remaining_for_all_entries():
	var active := stack.apply([], "poison", 5.0, 3)
	active = stack.apply(active, "burn", 5.0, 3)
	active = stack.advance(active, 2.0)
	assert_eq(stack.stacks_of(active, "poison"), 1)
	for entry in active:
		assert_eq(entry["time_remaining"], 3.0)


func test_advance_removes_entry_whose_time_remaining_reaches_exactly_zero():
	var active := stack.apply([], "poison", 5.0, 3)
	active = stack.advance(active, 5.0)
	assert_eq(active.size(), 0)


func test_advance_removes_entry_whose_time_remaining_drops_below_zero():
	var active := stack.apply([], "poison", 5.0, 3)
	active = stack.advance(active, 6.0)
	assert_eq(active.size(), 0)


func test_advance_does_not_mutate_callers_original_array():
	var original := stack.apply([], "poison", 5.0, 3)
	var advanced := stack.advance(original, 1.0)
	assert_eq(original[0]["time_remaining"], 5.0)
	assert_eq(advanced[0]["time_remaining"], 4.0)


func test_stacks_of_returns_zero_for_absent_debuff_id():
	assert_eq(stack.stacks_of([], "poison"), 0)


func test_stacks_of_returns_correct_count_for_present_id():
	var active := stack.apply([], "poison", 5.0, 3)
	active = stack.apply(active, "poison", 5.0, 3)
	assert_eq(stack.stacks_of(active, "poison"), 2)


func test_full_apply_then_advance_to_expiry_leaves_debuff_absent():
	var active := stack.apply([], "poison", 5.0, 3)
	active = stack.advance(active, 5.0)
	assert_eq(stack.stacks_of(active, "poison"), 0)
