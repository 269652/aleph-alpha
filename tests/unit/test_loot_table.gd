extends GutTest

const LootTable = preload("res://src/gameplay/loot_table.gd")

var loot: LootTable


func before_each():
	loot = LootTable.new()


func test_herbivore_drops_hide_and_meat():
	var drops := loot.drops_for("herbivore")
	var ids := _ids(drops)
	assert_true(ids.has("hide"))
	assert_true(ids.has("meat"))


func test_predator_drops_fang_and_meat():
	var drops := loot.drops_for("predator")
	var ids := _ids(drops)
	assert_true(ids.has("fang"))
	assert_true(ids.has("meat"))


func test_boar_drops_hide_and_meat():
	var drops := loot.drops_for("boar")
	var ids := _ids(drops)
	assert_true(ids.has("hide"))
	assert_true(ids.has("meat"))


func test_lynx_drops_fang_and_meat():
	var drops := loot.drops_for("lynx")
	var ids := _ids(drops)
	assert_true(ids.has("fang"))
	assert_true(ids.has("meat"))


func test_drops_have_positive_counts():
	for stack in loot.drops_for("herbivore"):
		assert_gt(stack.count, 0)


func test_drops_are_item_stacks_with_real_items():
	var drops := loot.drops_for("predator")
	assert_gt(drops.size(), 0)
	for stack in drops:
		assert_ne(stack.item, null)
		assert_ne(stack.item.display_name, "")


func test_unknown_species_drops_nothing():
	assert_eq(loot.drops_for("dragon"), [])


func test_drops_are_deterministic_for_a_species():
	assert_eq(_ids(loot.drops_for("herbivore")), _ids(loot.drops_for("herbivore")))


func _ids(drops: Array) -> Array:
	var ids := []
	for stack in drops:
		ids.append(stack.item.id)
	return ids
