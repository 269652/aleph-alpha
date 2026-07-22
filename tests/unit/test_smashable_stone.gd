extends GutTest

const SmashableStone = preload("res://src/rendering/smashable_stone.gd")

var stone: SmashableStone


func before_each():
	stone = SmashableStone.new()
	stone.stone_seed = 42
	add_child_autofree(stone)


func test_is_in_the_stone_group():
	assert_true(stone.is_in_group(SmashableStone.GROUP_NAME))


func test_smashing_bare_handed_yields_the_rock_itself():
	watch_signals(WorldItemBus)
	stone.smash(false)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 1)
	var stack = get_signal_parameters(WorldItemBus, "item_dropped", 0)[0]
	assert_eq(stack.item.id, "rock")
	assert_true(stone.is_queued_for_deletion())


func test_smashing_with_a_rock_in_hand_can_also_yield_sharp_shards():
	# Deterministic per stone_seed: pick a seed the knapping roll succeeds for,
	# by scanning -- the test then pins that a successful roll emits a shard
	# stack in addition to the rock.
	var knapping = load("res://src/gameplay/knapping.gd").new()
	var lucky_seed := -1
	for candidate in 100:
		if knapping.shard_yield(candidate) > 0:
			lucky_seed = candidate
			break
	assert_gt(lucky_seed, -1, "expected at least one shard-yielding seed in 0..99")

	stone.stone_seed = lucky_seed
	watch_signals(WorldItemBus)
	stone.smash(true)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 2)
	var shard_stack = get_signal_parameters(WorldItemBus, "item_dropped", 1)[0]
	assert_eq(shard_stack.item.id, "sharp_shard")
	assert_eq(shard_stack.count, knapping.shard_yield(lucky_seed))


func test_a_failed_knapping_roll_still_yields_the_rock_but_no_shards():
	var knapping = load("res://src/gameplay/knapping.gd").new()
	var unlucky_seed := -1
	for candidate in 100:
		if knapping.shard_yield(candidate) == 0:
			unlucky_seed = candidate
			break
	assert_gt(unlucky_seed, -1, "expected at least one shardless seed in 0..99")

	stone.stone_seed = unlucky_seed
	watch_signals(WorldItemBus)
	stone.smash(true)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 1)
