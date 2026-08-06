extends GutTest

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

var catalog := ItemCatalog.new()


func test_has_returns_true_for_a_known_item():
	assert_true(catalog.has("iron_axe"))


func test_has_returns_false_for_an_unknown_item():
	assert_false(catalog.has("not_a_real_item"))


func test_make_builds_the_right_material_item():
	var item := catalog.make("hide")
	assert_eq(item.id, "hide")
	assert_eq(item.kind, "material")
	assert_false(item.is_weapon())


func test_make_builds_the_right_weapon_with_damage():
	var item := catalog.make("iron_sword")
	assert_eq(item.id, "iron_sword")
	assert_true(item.is_weapon())
	assert_gt(item.weapon_damage, 0.0)


func test_make_builds_the_right_tool():
	var item := catalog.make("iron_axe")
	assert_true(item.is_axe())


func test_catalog_knows_the_craftable_output_items():
	for item_id in ["torch", "campfire", "cooked_meat"]:
		assert_true(catalog.has(item_id), "expected the catalog to know %s" % item_id)


func test_cooked_meat_is_food():
	var item := catalog.make("cooked_meat")
	assert_eq(item.kind, "food")


func test_catalog_knows_the_primitive_knapping_items():
	for item_id in ["rock", "stick", "sharp_shard", "plant_fibre", "crude_blade"]:
		assert_true(catalog.has(item_id), "missing %s" % item_id)


func test_crude_blade_is_a_weapon_better_than_bare_hands_but_worse_than_iron():
	var blade := catalog.make("crude_blade")
	assert_eq(blade.kind, "weapon")
	assert_gt(blade.weapon_damage, 5.0)  # UNARMED_DAMAGE
	assert_lt(blade.weapon_damage, 15.0)  # iron_sword


func test_catalog_knows_mining_and_cooking_items():
	for item_id in ["stone", "iron_ore", "copper_ore", "coal", "fish", "cooked_fish", "stone_pickaxe"]:
		assert_true(catalog.has(item_id), "missing %s" % item_id)


func test_stone_pickaxe_is_a_tool():
	assert_eq(catalog.make("stone_pickaxe").kind, "tool")


func test_catalog_has_leather_armor_pieces_with_slots():
	for item_id in ["leather_helm", "leather_chest", "leather_legs", "leather_boots"]:
		assert_true(catalog.has(item_id), "missing %s" % item_id)
	var chest := catalog.make("leather_chest")
	assert_eq(chest.kind, "armor")
	assert_eq(chest.equip_slot_name(), "chest")
	assert_gt(chest.armor, 0.0)


func test_catalog_has_smelting_items_and_iron_armor():
	for item_id in ["iron_ingot", "copper_ingot", "furnace",
			"iron_helm", "iron_chest", "iron_legs", "iron_boots"]:
		assert_true(catalog.has(item_id), "missing %s" % item_id)
	assert_gt(catalog.make("iron_chest").armor, catalog.make("leather_chest").armor)
	assert_eq(catalog.make("iron_helm").equip_slot_name(), "head")


func test_catalog_has_a_fishing_rod():
	assert_true(catalog.has("fishing_rod"))
	assert_eq(catalog.make("fishing_rod").kind, "tool")


## Campfire/furnace are structures you build into the world, not inert
## materials -- see HotbarAction.PLACE.
func test_campfire_and_furnace_are_placeable():
	assert_eq(catalog.make("campfire").kind, "placeable")
	assert_eq(catalog.make("furnace").kind, "placeable")
