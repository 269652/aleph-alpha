extends GutTest

const MinableOre = preload("res://src/rendering/minable_ore.gd")

var ore: MinableOre


func before_each():
	ore = MinableOre.new()
	ore.ore_type = "iron"
	ore.ore_seed = 7
	add_child_autofree(ore)


func test_is_in_the_stone_group_so_the_players_swing_targets_it():
	assert_true(ore.is_in_group(MinableOre.GROUP_NAME))


func test_mining_bare_handed_yields_only_stone_no_ore():
	watch_signals(WorldItemBus)
	ore.mine(0.0)
	# ore_yield with power 0 yields only stone -- one drop, and it's "stone".
	assert_signal_emit_count(WorldItemBus, "item_dropped", 1)
	var stack = get_signal_parameters(WorldItemBus, "item_dropped", 0)[0]
	assert_eq(stack.item.id, "stone")
	assert_true(ore.is_queued_for_deletion())


func test_mining_with_a_pickaxe_yields_stone_plus_ore():
	watch_signals(WorldItemBus)
	ore.mine(1.0)
	# With power > 0, ore_yield adds the ore item on top of the stone.
	assert_signal_emit_count(WorldItemBus, "item_dropped", 2)
	var ids := []
	for i in 2:
		ids.append(get_signal_parameters(WorldItemBus, "item_dropped", i)[0].item.id)
	assert_true(ids.has("stone"))
	assert_true(ids.has("iron_ore"))
