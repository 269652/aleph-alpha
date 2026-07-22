extends GutTest

const Equipment = preload("res://src/gameplay/equipment.gd")
const Item = preload("res://src/gameplay/item.gd")

var eq: Equipment


func before_each():
	eq = Equipment.new()


func _helm(armor: float = 2.0) -> Item:
	return Item.new("leather_helm", "Leather Helm", "armor", 1, 0.0, "head", armor)


func _chest(armor: float = 4.0) -> Item:
	return Item.new("leather_chest", "Leather Chest", "armor", 1, 0.0, "chest", armor)


func _sword() -> Item:
	return Item.new("iron_sword", "Iron Sword", "weapon", 1, 15.0)


func test_slots_include_the_standard_armor_and_weapon_slots():
	for slot in ["head", "chest", "legs", "feet", "weapon"]:
		assert_true(Equipment.SLOTS.has(slot), "missing slot %s" % slot)


func test_equipping_puts_the_item_in_its_slot():
	assert_null(eq.equip(_helm()))
	assert_eq(eq.equipped_in("head").id, "leather_helm")


func test_equipping_a_second_item_returns_the_displaced_one():
	eq.equip(_helm(2.0))
	var displaced = eq.equip(_helm(5.0))
	assert_eq(displaced.armor, 2.0, "the old helm should be returned to the caller")
	assert_eq(eq.equipped_in("head").armor, 5.0)


func test_equip_rejects_a_non_equippable_item():
	var wood := Item.new("wood", "Wood", "material", 40)
	# Returns the item straight back (nothing equipped) so the caller keeps it.
	assert_eq(eq.equip(wood), wood)
	assert_true(eq.equipped_in("head") == null)


func test_unequip_frees_the_slot_and_returns_the_item():
	eq.equip(_chest())
	var removed = eq.unequip("chest")
	assert_eq(removed.id, "leather_chest")
	assert_null(eq.equipped_in("chest"))


func test_total_armor_sums_every_equipped_piece():
	eq.equip(_helm(2.0))
	eq.equip(_chest(4.0))
	assert_eq(eq.total_armor(), 6.0)


func test_total_armor_ignores_the_weapon_slot():
	eq.equip(_sword())
	assert_eq(eq.total_armor(), 0.0)


func test_equipped_items_lists_what_is_worn():
	eq.equip(_helm())
	eq.equip(_sword())
	assert_eq(eq.equipped_items().size(), 2)
