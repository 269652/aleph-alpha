extends GutTest

## StarterKit: the curated pool a new player picks 3 starting items from at
## character creation (docs/concept/starting_kit.md) -- pure data, mirroring
## class_archetype.gd's own shape exactly: flat consts, a couple of query
## functions, zero UI/blurb text (that lives in main_menu.gd, the same split
## CLASS_BLURBS already uses for classes).

const StarterKit = preload("res://src/gameplay/starter_kit.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")


func test_the_pool_has_exactly_the_curated_items():
	assert_eq(StarterKit.POOL, [
		"wooden_club", "crude_blade", "stone_pickaxe", "fishing_rod",
		"lasso", "rough_compass", "iron_sword", "iron_axe",
		"butterfly_net", "glass_bottle",
	])


func test_every_pool_item_is_a_real_known_item():
	var catalog := ItemCatalog.new()
	for item_id in StarterKit.POOL:
		assert_true(catalog.has(item_id), "%s must be a real item" % item_id)


func test_max_choices_is_three():
	assert_eq(StarterKit.MAX_CHOICES, 3)


func test_default_choices_has_exactly_max_choices_entries():
	assert_eq(StarterKit.DEFAULT_CHOICES.size(), StarterKit.MAX_CHOICES)


func test_every_default_choice_is_a_real_pool_member():
	for item_id in StarterKit.DEFAULT_CHOICES:
		assert_true(StarterKit.is_valid_choice(item_id))


func test_is_valid_choice_true_for_a_pool_member():
	assert_true(StarterKit.is_valid_choice("lasso"))


func test_is_valid_choice_false_for_a_non_pool_item():
	# leather_chest is a real item but never in the curated pool.
	assert_false(StarterKit.is_valid_choice("leather_chest"))


func test_is_valid_choice_false_for_an_unknown_id():
	assert_false(StarterKit.is_valid_choice("not_a_real_item_zzz"))
