extends GutTest

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")


func test_item_carries_its_identity():
	var hide := Item.new("hide", "Hide", "material", 40)
	assert_eq(hide.id, "hide")
	assert_eq(hide.display_name, "Hide")
	assert_eq(hide.kind, "material")
	assert_eq(hide.max_stack, 40)


func test_a_weapon_item_carries_damage():
	var sword := Item.new("iron_sword", "Iron Sword", "weapon", 1, 25.0)
	assert_true(sword.is_weapon())
	assert_eq(sword.weapon_damage, 25.0)


func test_a_material_item_is_not_a_weapon():
	var hide := Item.new("hide", "Hide", "material", 40)
	assert_false(hide.is_weapon())
	assert_eq(hide.weapon_damage, 0.0)


func test_a_tool_item_reports_as_an_axe():
	var axe := Item.new("iron_axe", "Iron Axe", "tool", 1)
	assert_true(axe.is_axe())


func test_a_weapon_item_is_not_an_axe():
	var sword := Item.new("iron_sword", "Iron Sword", "weapon", 1, 25.0)
	assert_false(sword.is_axe())


func test_a_pickaxe_tool_reports_as_a_pickaxe():
	var pick := Item.new("stone_pickaxe", "Stone Pickaxe", "tool", 1)
	assert_true(pick.is_pickaxe())
	assert_false(pick.is_axe(), "a pickaxe is not a wood-felling axe")


func test_a_non_pickaxe_is_not_a_pickaxe():
	assert_false(Item.new("iron_axe", "Iron Axe", "tool", 1).is_pickaxe())
	assert_false(Item.new("iron_sword", "Iron Sword", "weapon", 1, 5.0).is_pickaxe())


func test_stack_reports_its_item_and_count():
	var stack := ItemStack.new(Item.new("meat", "Meat", "food", 20), 3)
	assert_eq(stack.item.id, "meat")
	assert_eq(stack.count, 3)


func test_stacks_of_the_same_item_can_combine():
	var a := ItemStack.new(Item.new("meat", "Meat", "food", 20), 3)
	var b := ItemStack.new(Item.new("meat", "Meat", "food", 20), 2)
	assert_true(a.can_stack_with(b))


func test_stacks_of_different_items_cannot_combine():
	var a := ItemStack.new(Item.new("meat", "Meat", "food", 20), 3)
	var b := ItemStack.new(Item.new("hide", "Hide", "material", 40), 2)
	assert_false(a.can_stack_with(b))


func test_merge_moves_as_much_as_fits_and_returns_the_overflow():
	var a := ItemStack.new(Item.new("meat", "Meat", "food", 20), 18)
	var overflow := a.merge(5)  # 18 + 5 = 23, capped at 20 -> 3 overflow
	assert_eq(a.count, 20)
	assert_eq(overflow, 3)


func test_merge_with_room_leaves_no_overflow():
	var a := ItemStack.new(Item.new("meat", "Meat", "food", 20), 2)
	var overflow := a.merge(5)
	assert_eq(a.count, 7)
	assert_eq(overflow, 0)


func test_remaining_capacity_reflects_how_much_more_fits():
	var a := ItemStack.new(Item.new("meat", "Meat", "food", 20), 15)
	assert_eq(a.remaining_capacity(), 5)


func test_a_weapon_equips_to_the_weapon_slot():
	assert_eq(Item.new("iron_sword", "Iron Sword", "weapon", 1, 15.0).equip_slot_name(), "weapon")


func test_armor_equips_to_its_declared_slot_and_carries_armor_value():
	var helm := Item.new("leather_helm", "Leather Helm", "armor", 1, 0.0, "head", 2.0)
	assert_eq(helm.equip_slot_name(), "head")
	assert_true(helm.is_equippable())
	assert_eq(helm.armor, 2.0)


func test_a_material_is_not_equippable():
	var wood := Item.new("wood", "Wood", "material", 40)
	assert_false(wood.is_equippable())
	assert_eq(wood.equip_slot_name(), "")
	assert_eq(wood.armor, 0.0)
