extends GutTest

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Kick = preload("res://src/gameplay/kick.gd")

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


## Rare/legendary catches (see FishingMinigame.fish_rarity) are their own food
## items -- not just the generic "fish" -- so a rare catch's rarity survives
## into the inventory instead of being lost after the reward is granted.
func test_catalog_has_rare_and_legendary_fish_as_distinct_food_items():
	for item_id in ["rare_fish", "legendary_fish"]:
		assert_true(catalog.has(item_id), "missing %s" % item_id)
		assert_eq(catalog.make(item_id).kind, "food")


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


## Named fruit tree species (see docs/concept/flora.md#named-fruit-and-nut-tree-species)
## drop their OWN item id -- cherry/apple/walnut -- rather than the generic
## "fruit"/"nut" every tree used to drop regardless of species.
func test_catalog_knows_the_named_tree_fruit_items():
	for item_id in ["cherry", "apple", "walnut"]:
		assert_true(catalog.has(item_id), "missing %s" % item_id)
		assert_eq(catalog.make(item_id).kind, "food")


# -- taming gear (see docs/concept/taming.md) --------------------------------

func test_a_lasso_is_a_tool_you_hold():
	var lasso = catalog.make("lasso")
	assert_not_null(lasso, "the lasso has to exist to be crafted")
	assert_eq(lasso.kind, "tool", "it is held in hand, like the fishing rod")


## Carrots are the taming reward -- high-sugar roots are the traditional
## horse treat for a reason -- so they have to be food the animal wants.
func test_a_carrot_is_food():
	var carrot = catalog.make("carrot")
	assert_not_null(carrot)
	assert_eq(carrot.kind, "food")


## The other wild root crop (see docs/concept/wild_crops.md) -- a pulled
## potato is food the same way a pulled carrot is.
func test_a_potato_is_food():
	var potato = catalog.make("potato")
	assert_not_null(potato)
	assert_eq(potato.kind, "food")


# -- woodworking (see docs/concept/woodworking.md) ---------------------------

func test_catalog_knows_the_woodworking_materials():
	for item_id in ["log", "beam", "plank"]:
		var item = catalog.make(item_id)
		assert_not_null(item, item_id)
		assert_eq(item.kind, "material", item_id)


func test_a_saw_is_a_tool_that_reports_as_a_saw():
	var saw = catalog.make("saw")
	assert_not_null(saw)
	assert_eq(saw.kind, "tool")
	assert_true(saw.is_saw())


# -- real weapon mass (see MaterialProperties.mass_kg_for, docs/concept/ -----
# -- materials.md's momentum = mass * velocity model) ------------------------

## Real one-handed swords are typically ~1-1.5kg -- the sanity check the
## user explicitly asked for on whatever volume estimate backs this.
func test_iron_sword_has_a_plausible_real_sword_mass():
	assert_between(catalog.make("iron_sword").mass_kg, 1.0, 1.5)


## Every weapon-kind item should carry a real, positive mass -- not just the
## sword the user named explicitly (see item_catalog.gd's own doc comment on
## why tools are a documented, separate follow-up rather than guessed at
## here).
func test_every_weapon_kind_item_has_a_positive_mass():
	for item_id in ["iron_sword", "wooden_club", "crude_blade"]:
		assert_gt(catalog.make(item_id).mass_kg, 0.0, "%s should have a real mass" % item_id)


## A denser material (iron) should mass more than a less dense one (wood) at
## a comparable real-world item scale -- not a coincidence of the specific
## volumes chosen, a real consequence of the shared density table.
func test_the_iron_sword_masses_more_than_the_wooden_club():
	assert_gt(catalog.make("iron_sword").mass_kg, catalog.make("wooden_club").mass_kg)


# -- kind_of: an item's category without building a whole Item first --------
#
## Exposed standalone (the same "kind" make() already stamps onto the built
## Item) so a caller can classify an item id, e.g. "is this food?", without
## constructing one -- see Player.sell_food_to_village's village-feeding
## fallback (docs/concept/progression.md "Ecological literacy").

func test_kind_of_matches_the_kind_make_builds():
	assert_eq(catalog.kind_of("cherry"), catalog.make("cherry").kind)
	assert_eq(catalog.kind_of("cherry"), "food")
	assert_eq(catalog.kind_of("iron_axe"), "tool")


func test_kind_of_unknown_item_is_empty_string():
	assert_eq(catalog.kind_of("not_a_real_item"), "")


# -- real produce mass (docs/concept/wild_crops.md: a pulled root should be --
# -- a real physical object, kickable/throwable like anything else) ---------

## A medium carrot averages roughly 60-70g in the real world.
func test_carrot_has_a_plausible_real_carrot_mass():
	assert_between(catalog.make("carrot").mass_kg, 0.04, 0.12)


## A medium potato averages roughly 150-200g in the real world.
func test_potato_has_a_plausible_real_potato_mass():
	assert_between(catalog.make("potato").mass_kg, 0.1, 0.3)


## Both are far below Kick's leg-mass cutoff -- a real vegetable is trivially
## light enough to kick, the same way a pebble is.
func test_carrot_and_potato_are_both_light_enough_to_kick():
	assert_true(Kick.is_kickable(catalog.make("carrot").mass_kg))
	assert_true(Kick.is_kickable(catalog.make("potato").mass_kg))
