extends GutTest

## DiggableRock mirrors MinableOre's contract exactly (see
## test_minable_ore.gd) plus the Strata write-back a real underground cell
## needs (docs/concept/geology.md "Reveal-on-entry, reused recursively").

const DiggableRock = preload("res://src/rendering/diggable_rock.gd")
const Strata = preload("res://src/world/strata.gd")

var rock: DiggableRock


func before_each():
	rock = DiggableRock.new()
	add_child_autofree(rock)


func test_is_in_the_stone_group_so_the_players_swing_targets_it():
	assert_true(rock.is_in_group(DiggableRock.GROUP_NAME))


func test_mining_a_solid_cell_yields_only_stone():
	rock.kind = Strata.KIND_SOLID
	watch_signals(WorldItemBus)
	rock.mine(0.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 1)
	var stack = get_signal_parameters(WorldItemBus, "item_dropped", 0)[0]
	assert_eq(stack.item.id, "stone")
	assert_true(rock.is_queued_for_deletion())


func test_mining_a_solid_cell_bare_handed_still_yields_stone():
	rock.kind = Strata.KIND_SOLID
	watch_signals(WorldItemBus)
	rock.mine(0.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 1)


func test_mining_an_ore_cell_bare_handed_yields_only_stone():
	rock.kind = Strata.KIND_ORE
	rock.ore_type = "iron"
	watch_signals(WorldItemBus)
	rock.mine(0.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 1)
	var stack = get_signal_parameters(WorldItemBus, "item_dropped", 0)[0]
	assert_eq(stack.item.id, "stone")


func test_mining_an_ore_cell_with_a_pickaxe_yields_stone_plus_ore():
	rock.kind = Strata.KIND_ORE
	rock.ore_type = "iron"
	watch_signals(WorldItemBus)
	rock.mine(1.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 2)
	var ids := []
	for i in 2:
		ids.append(get_signal_parameters(WorldItemBus, "item_dropped", i)[0].item.id)
	assert_true(ids.has("stone"))
	assert_true(ids.has("iron_ore"))


func test_mining_writes_the_tunnel_back_into_strata():
	var strata := Strata.new(Strata.LAYER_TOPSOIL_REGOLITH, Vector2i.ZERO)
	var cell := Vector2i(3, 3)
	rock.strata = strata
	rock.local_cell = cell
	rock.kind = strata.cell_kind_at(cell)
	rock.mine(0.0)
	assert_eq(strata.cell_kind_at(cell), Strata.KIND_TUNNEL)


# -- hover tooltip: name + available actions ---------------------------------

func test_solid_display_name_is_rock():
	rock.kind = Strata.KIND_SOLID
	assert_eq(rock.get_display_name(), "Rock")


func test_ore_display_name_matches_the_ores_own_item_name():
	rock.kind = Strata.KIND_ORE
	rock.ore_type = "iron"
	assert_eq(rock.get_display_name(), "Iron Ore")


func test_hover_action_is_mine_bound_to_attack():
	var actions: Array = rock.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["verb"], "Mine")
	assert_eq(actions[0]["action"], "attack")
