extends GutTest

## Cross-checks docs/concept/illustrated_art_addressing.md's registry
## against ItemCatalog's own real item ids -- see item_illustrations.md's
## "Icon" states-table row ("Eventually, per item -- but see `sprite_id`
## below; nothing blocks on this today"). Scaffolds the FIRST 100 catalog
## ids (in `_ITEMS`' own declared order, see item_catalog.gd) with at
## least a bare `icon`-context registry entry, so every one of them is
## addressable through the resolver -- procedural remains the terminal
## fallback for anything still missing real pixels (pillar 4, "author the
## base, fill in the rest") -- rather than leaving registry coverage at
## just the two hand-picked pilot subjects (`wooden_club`, `campfire`)
## illustrated_art_addressing.md's own worked examples cover so far.
##
## Deliberately a hardcoded snapshot of "the first 100 ids as of this
## pass", not a live `catalog.known_ids().slice(0, 100)` -- item_catalog.gd
## grows constantly in this shared repo (102 entries as of this writing,
## up from 101 earlier the same session), and a live slice would make
## this test's pass/fail silently depend on whatever the catalog's 100th
## entry happens to be on any given day, rather than checking the fixed
## set this pass actually scaffolded. `test_first_100_ids_are_all_real_
## known_catalog_ids` guards against a stale/typo'd id in the list below.

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const IllustratedArtRegistry = preload("res://src/rendering/illustrated_art_registry.gd")

var catalog := ItemCatalog.new()
var registry := IllustratedArtRegistry.new()

## _ITEMS' own declared order, item_catalog.gd, up to and including
## "glass_bottle" (the 100th entry) -- "climbing_rope"/"honey" (101st/
## 102nd) are deliberately excluded, matching "the first 100" exactly.
const _FIRST_100_ITEM_IDS := [
	"hide", "meat", "fang", "fruit", "nut",
	"cherry", "apple", "walnut",
	"acorn", "hazelnut", "pine",
	"fly_agaric", "psylo", "black_trumpet", "champignon", "chanterelle", "parasol", "death_cap", "false_death_cap",
	"fly_agaric_bitten", "psylo_bitten", "black_trumpet_bitten", "champignon_bitten", "chanterelle_bitten",
	"parasol_bitten", "death_cap_bitten", "false_death_cap_bitten",
	"wood", "wooden_club", "iron_sword", "iron_axe", "torch",
	"campfire", "cooked_meat",
	"rock", "stick", "sharp_shard", "plant_fibre",
	"lasso", "carrot",
	"potato",
	"log", "beam", "plank", "saw", "crude_blade",
	"stone", "stone_pickaxe", "iron_ore", "copper_ore", "coal",
	"worm",
	"fish", "cooked_fish",
	"trout", "cooked_trout", "bluegill", "cooked_bluegill", "koi", "cooked_koi", "goldfish", "cooked_goldfish",
	"rare_fish", "legendary_fish",
	"leather_helm", "leather_chest", "leather_legs", "leather_boots",
	"iron_ingot", "copper_ingot", "furnace", "iron_helm", "iron_chest", "iron_legs", "iron_boots",
	"fishing_rod",
	"sagewerk",
	"storage",
	"stone_dam",
	"rough_compass", "compass", "map", "spyglass", "weather_glass", "star_chart", "deed", "ledger",
	"field_journal", "charter",
	"terminal_fragment", "secret_room_token", "wargames_punch_card", "curious_keepsake",
	"snare", "butterfly_net", "trap", "reinforced_rope",
	"jarred_insect", "caged_songbird",
	"glass_bottle",
]


func test_first_100_item_ids_list_is_exactly_100_long():
	assert_eq(_FIRST_100_ITEM_IDS.size(), 100)


func test_first_100_ids_are_all_real_known_catalog_ids():
	for item_id in _FIRST_100_ITEM_IDS:
		assert_true(catalog.has(item_id), "%s is not a real ItemCatalog id" % item_id)


func test_first_100_item_ids_has_no_duplicates():
	var seen := {}
	for item_id in _FIRST_100_ITEM_IDS:
		seen[item_id] = true
	assert_eq(_FIRST_100_ITEM_IDS.size(), seen.size(), "the first-100 list repeats an id")


## The actual scaffolding requirement: every one of the 100 has a
## registry entry, and that entry declares the icon context specifically
## (the one surface item_illustrations.md says every item eventually
## needs, see its states table).
func test_every_one_of_the_first_100_items_has_an_icon_registry_entry():
	for item_id in _FIRST_100_ITEM_IDS:
		assert_true(
			registry.has_subject(item_id),
			"%s has no illustrated_art_registry entry yet" % item_id
		)
		var entry: Dictionary = registry.entry_for(item_id)
		assert_true(
			entry.get("contexts", {}).has("icon"),
			"%s's registry entry has no icon context" % item_id
		)
