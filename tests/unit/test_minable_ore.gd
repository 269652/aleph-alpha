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


# -- hover tooltip: name + available actions ---------------------------------

## The display name is the actual yielded item's name (via ItemCatalog),
## not a naive "<ore_type> Ore" -- coal's own item is just "Coal", not
## "Coal Ore".
func test_display_name_matches_the_ores_own_item_name():
	assert_eq(ore.get_display_name(), "Iron Ore")


func test_coals_display_name_is_not_coal_ore():
	var coal := MinableOre.new()
	coal.ore_type = "coal"
	add_child_autofree(coal)
	assert_eq(coal.get_display_name(), "Coal")


func test_hover_action_is_mine_bound_to_attack():
	var actions: Array = ore.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["verb"], "Mine")
	assert_eq(actions[0]["action"], "attack")
