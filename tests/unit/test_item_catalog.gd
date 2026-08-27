extends GutTest

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const CraftedItemRegistry = preload("res://src/gameplay/crafted_item_registry.gd")

var catalog := ItemCatalog.new()


## An iron-bladed, wood-gripped sword -- the same shape
## test_crafted_item_registry.gd builds, so the two files agree about what an
## assembly looks like.
func _sword() -> Dictionary:
	return {
		"pattern": "sword",
		"parts": [
			{"material": "iron", "geometry": "blade", "role": "edge", "length_cm": 70.0},
			{"material": "wood", "geometry": "rod", "role": "grip", "length_cm": 12.0},
		],
		"joints": [{"kind": "tang", "a": 0, "b": 1}],
	}


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


## Campfire/furnace/sagewerk are structures you build into the world, not
## inert materials -- see HotbarAction.PLACE.
func test_campfire_and_furnace_are_placeable():
	assert_eq(catalog.make("campfire").kind, "placeable")
	assert_eq(catalog.make("furnace").kind, "placeable")


## The Sägewerk (sawmill) worksite -- see docs/concept/timber_construction.md.
## A placeable structure like campfire/furnace, not an inert material.
func test_sagewerk_is_placeable():
	assert_true(catalog.has("sagewerk"))
	assert_eq(catalog.make("sagewerk").kind, "placeable")


## Storage (see docs/concept/timber_construction.md's "Storage, logistics,
## and the autonomous dependency chain" section) is the same placeable kind
## as campfire/furnace -- a tile-based structure, not an inert material.
func test_storage_is_placeable():
	assert_true(catalog.has("storage"))
	assert_eq(catalog.make("storage").kind, "placeable")


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


# -- wayfinding & citizenship instruments (see docs/concept/wayfinding.md, --
# -- docs/concept/player_citizenship.md) -- Compass/RoughCompass, Map, -------
# -- Spyglass, WeatherForecast, SeasonAlmanac, and the property/contract/ ----
# -- journal citizenship tools all get a craftable, held item id now that ----
# -- their pure-logic modules exist. --------------------------------------

const WAYFINDING_AND_CITIZENSHIP_ITEM_IDS := [
	"rough_compass", "compass", "map", "spyglass", "weather_glass",
	"star_chart", "deed", "ledger", "field_journal", "charter",
]


func test_catalog_knows_the_wayfinding_and_citizenship_tools():
	for item_id in WAYFINDING_AND_CITIZENSHIP_ITEM_IDS:
		assert_true(catalog.has(item_id), "missing %s" % item_id)
		assert_eq(catalog.make(item_id).kind, "tool", item_id)


## These are instruments/documents, not consumables -- matching the existing
## tool-kind convention (lasso, saw, stone_pickaxe, fishing_rod all cap at 1).
func test_wayfinding_and_citizenship_tools_do_not_stack():
	for item_id in WAYFINDING_AND_CITIZENSHIP_ITEM_IDS:
		assert_eq(catalog.make(item_id).max_stack, 1, item_id)


# -- "Three Fragments" hunt items (docs/concept/easter_eggs.md) -------------
#
## The three fragments each source egg (signed secret room/ancient terminal/
## WarGames) quietly leaves behind, plus the bonus item ThreeFragmentsHunt
## grants once all three are held together -- all deliberately inert
## ("material" kind, zero weapon_damage) matching this whole Easter-egg
## family's zero-mechanical-weight design pillar.

const ThreeFragmentsHunt = preload("res://src/gameplay/three_fragments_hunt.gd")

func test_catalog_knows_the_three_fragments_and_the_bonus_item():
	for item_id in [
		ThreeFragmentsHunt.TERMINAL_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.SECRET_ROOM_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.WARGAMES_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.BONUS_ITEM_ID,
	]:
		assert_true(catalog.has(item_id), "missing %s" % item_id)


## Zero mechanical weight (pillar 2): none of these four items is a weapon,
## and none carries any real weapon damage.
func test_three_fragments_and_bonus_item_carry_no_weapon_damage():
	for item_id in [
		ThreeFragmentsHunt.TERMINAL_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.SECRET_ROOM_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.WARGAMES_FRAGMENT_ITEM_ID,
		ThreeFragmentsHunt.BONUS_ITEM_ID,
	]:
		var item := catalog.make(item_id)
		assert_false(item.is_weapon(), "%s should not be a weapon" % item_id)
		assert_eq(item.weapon_damage, 0.0, "%s should carry no weapon damage" % item_id)
		assert_eq(item.kind, "material", "%s should be an inert material item" % item_id)


# -- which real material an item is made of ---------------------------------
#
# The catalog already derives a weapon's real mass from a material + a volume
# estimate (see _WEAPON_MATERIAL_AND_VOLUME / _mass_kg_for), but that material
# was private, so nothing could tell the player WHAT the sword is made of --
# only how heavy it came out. Named after the existing
# BuildingPiece.material_of rather than inventing a second spelling.

func test_material_of_names_the_real_material_a_weapons_mass_was_derived_from():
	assert_eq(catalog.material_of("iron_sword"), "iron")
	assert_eq(catalog.material_of("wooden_club"), "wood")
	assert_eq(catalog.material_of("crude_blade"), "stone")


## Same "not modeled yet" convention Item.mass_kg's 0.0 uses -- an empty
## string, so a caller omits the line rather than inventing a material.
func test_material_of_is_empty_for_an_item_with_no_modeled_material():
	assert_eq(catalog.material_of("rock"), "")
	assert_eq(catalog.material_of("not_a_real_item"), "")


## The material an item is named after must be the same one its mass was
## computed from -- one fact, not two that can drift.
func test_material_of_is_the_material_the_items_mass_was_computed_from():
	var mp := preload("res://src/gameplay/material_properties.gd").new()
	var sword := catalog.make("iron_sword")
	assert_almost_eq(
		sword.mass_kg,
		mp.mass_kg_for(catalog.material_of("iron_sword"), ItemCatalog.IRON_SWORD_VOLUME_CM3),
		0.0001
	)


# --- the crafted-item seam -------------------------------------------------
#
# scenes/player.gd loads inventory with `if _item_catalog.has(entry.id)`
# (:861-862) and equipment with a matching `continue` (:868-870), so the ONE
# place deciding whether a saved item survives a load is this catalog's has().
# Putting the emergent fallback here rather than in player.gd is what keeps it a
# single seam instead of a conditional spreading through a hot file -- and every
# other caller (the shop, /give, cooking, crafting output, tile pickup) gets it
# at the same time and for free.


func test_a_crafted_id_is_unknown_until_a_registry_is_attached():
	assert_false(catalog.has("asm_0000000000000000"))


## THE regression this whole slice exists to prevent: an id the static table has
## never heard of must survive a load once its structure is known.
func test_a_registered_crafted_id_becomes_known_to_the_catalog():
	var registry := CraftedItemRegistry.new()
	var id := registry.register(_sword())
	catalog.use_crafted_registry(registry)
	assert_true(catalog.has(id), "the loader's `if _item_catalog.has(entry.id)` now passes")


func test_the_catalog_builds_a_crafted_item_from_its_id():
	var registry := CraftedItemRegistry.new()
	var id := registry.register(_sword())
	catalog.use_crafted_registry(registry)

	var item := catalog.make(id)
	assert_eq(item.id, id)
	assert_eq(item.display_name, "Iron Sword")
	assert_eq(item.kind, CraftedItemRegistry.CRAFTED_KIND)


func test_kind_of_answers_for_a_crafted_id_too():
	var registry := CraftedItemRegistry.new()
	var id := registry.register(_sword())
	catalog.use_crafted_registry(registry)
	assert_eq(catalog.kind_of(id), CraftedItemRegistry.CRAFTED_KIND)


## An attached registry must never shadow a shipped item. The authored table is
## what the rest of the game has wired up (the shop prices it, recipes output
## it), so it wins any id that somehow appears in both.
func test_an_attached_registry_never_shadows_a_shipped_item():
	var registry := CraftedItemRegistry.new()
	registry.register(_sword())
	catalog.use_crafted_registry(registry)
	assert_eq(catalog.make("iron_sword").display_name, "Iron Sword")
	assert_eq(catalog.make("iron_sword").kind, "weapon")


## A registry-less catalog is the shipped default -- every existing caller
## constructs one with a bare new(). It must behave exactly as it did before
## this seam existed, rather than needing a registry injected first.
func test_a_catalog_with_no_registry_still_answers_for_shipped_items():
	assert_true(catalog.has("iron_sword"))
	assert_eq(catalog.kind_of("iron_sword"), "weapon")
	assert_false(catalog.has("asm_deadbeefdeadbeef"))
	assert_eq(catalog.kind_of("asm_deadbeefdeadbeef"), "")


## Detaching is what a New Game does -- a fresh world must not inherit the
## previous save's crafted items through a catalog that outlived it.
func test_clearing_the_registry_makes_its_ids_unknown_again():
	var registry := CraftedItemRegistry.new()
	var id := registry.register(_sword())
	catalog.use_crafted_registry(registry)
	catalog.use_crafted_registry(null)
	assert_false(catalog.has(id))
