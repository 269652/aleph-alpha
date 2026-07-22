extends GutTest

const Block = preload("res://src/gameplay/block.gd")

var block: Block


func before_each():
	block = Block.new()


# -- block_efficiency ---------------------------------------------------------

func test_sword_block_efficiency_is_0_7():
	assert_eq(block.block_efficiency("sword"), 0.7)


func test_axe_block_efficiency_is_0_4():
	assert_eq(block.block_efficiency("axe"), 0.4)


func test_unarmed_block_efficiency_is_0_2():
	assert_eq(block.block_efficiency("unarmed"), 0.2)


func test_sword_blocks_better_than_axe_which_blocks_better_than_unarmed():
	assert_gt(block.block_efficiency("sword"), block.block_efficiency("axe"))
	assert_gt(block.block_efficiency("axe"), block.block_efficiency("unarmed"))


func test_unknown_weapon_kind_falls_back_to_unarmed_efficiency():
	assert_eq(block.block_efficiency("banana"), block.block_efficiency("unarmed"))


func test_all_efficiencies_are_within_0_to_1():
	for kind in ["sword", "axe", "unarmed", "banana"]:
		var e: float = block.block_efficiency(kind)
		assert_between(e, 0.0, 1.0, "efficiency for %s" % kind)


# -- blocked_damage -----------------------------------------------------------

func test_blocked_damage_with_sword_reduces_10_to_3():
	assert_almost_eq(block.blocked_damage(10.0, "sword"), 3.0, 0.0001)


func test_blocked_damage_with_axe_reduces_10_to_6():
	assert_almost_eq(block.blocked_damage(10.0, "axe"), 6.0, 0.0001)


func test_blocked_damage_unarmed_reduces_10_to_8():
	assert_almost_eq(block.blocked_damage(10.0, "unarmed"), 8.0, 0.0001)


func test_blocked_damage_of_zero_incoming_is_zero():
	assert_eq(block.blocked_damage(0.0, "sword"), 0.0)


func test_blocked_damage_never_negative_for_negative_incoming():
	assert_eq(block.blocked_damage(-5.0, "sword"), 0.0)


# -- stamina/combat decoupling ------------------------------------------------
# Per docs/concept/survival.md's "Stamina scope: movement only, not combat"
# (decided 2026-07-16): stamina gates sprinting/climbing/swimming, never
# combat. Blocking must therefore expose no stamina-cost API at all.

func test_block_exposes_no_stamina_cost_api():
	assert_false(block.has_method("block_stamina_cost"), "blocking must never cost stamina -- combat stays cooldown-only, see docs/concept/survival.md")
