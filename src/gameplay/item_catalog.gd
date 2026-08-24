extends RefCounted

## Item id -> full Item definition lookup, for anything that needs to build a
## real Item from just its string id (currently: DevConsole's /give command).
## Not the sole source of truth for drops -- loot_table.gd, forage_scheduler.gd
## and choppable_tree.gd each define their own drop-specific item specs
## independently -- this is a superset covering every id used anywhere in the
## game, so /give doesn't need to know which subsystem originally defined it.

const Item = preload("res://src/gameplay/item.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

## Real weapon mass (see docs/concept/materials.md's momentum = mass *
## velocity model, MaterialProperties.mass_kg_for): each weapon-kind item's
## material + an estimated real-world volume for that item type. Only
## weapon-kind items so far (wooden_club, iron_sword, crude_blade) -- tools
## (axe, pickaxe, fishing rod, lasso) are a documented follow-up (see
## docs/progress.md), not guessed at here, since the user's explicit ask was
## "a sword should have a proper mass" and weapons are the items an attack's
## knockback actually reads mass from (see Player._attack_step).
##
## iron_sword: real one-handed swords are typically ~1-1.5kg; at iron's real
## density (7.8 g/cm^3, MaterialProperties.MATERIALS) that implies roughly
## 130-190cm^3 of metal (blade + hilt/guard/pommel) -- 154cm^3 sits centrally
## and lands at ~1.2kg, within the cited real range (see
## test_iron_sword_has_a_plausible_real_sword_mass).
const IRON_SWORD_VOLUME_CM3 := 154.0

## wooden_club: a real wooden club/baton (a stout ~40cm haft) is roughly
## 0.5-0.7kg; at wood's density (0.6 g/cm^3) that implies roughly 800-1200
## cm^3 of wood -- 1000cm^3 sits centrally and lands at 0.6kg.
const CLUB_VOLUME_CM3 := 1000.0

## crude_blade: a primitive hafted stone/flint hand-tool (the start of the
## knapping tech chain, see docs/concept/crafting.md) is commonly cited in
## the 0.3-1kg range; at stone's density (2.5 g/cm^3) that implies roughly
## 120-400cm^3 -- 300cm^3 sits centrally and lands at 0.75kg.
const CRUDE_BLADE_VOLUME_CM3 := 300.0

## item_id -> [material, volume_cm3] for every weapon-kind item with a real
## mass modeled -- an item_id with no entry here gets mass_kg 0.0 (see
## make()).
const _WEAPON_MATERIAL_AND_VOLUME := {
	"iron_sword": ["iron", IRON_SWORD_VOLUME_CM3],
	"wooden_club": ["wood", CLUB_VOLUME_CM3],
	"crude_blade": ["stone", CRUDE_BLADE_VOLUME_CM3],
}

var _material_properties := MaterialProperties.new()

## item_id -> [display_name, kind, max_stack, weapon_damage, equip_slot?, armor?]
## (equip_slot and armor are optional trailing fields, used by armor items).
const _ITEMS := {
	"hide": ["Hide", "material", 40, 0.0],
	"meat": ["Raw Meat", "food", 20, 0.0],
	"fang": ["Fang", "material", 40, 0.0],
	"fruit": ["Fruit", "food", 20, 0.0],
	"nut": ["Nut", "food", 20, 0.0],
	# Named fruit tree species (see docs/concept/flora.md#named-fruit-and-nut-
	# tree-species): a Cherry/Apple/Walnut tree drops its OWN item id rather
	# than the generic "fruit"/"nut" above, which the ambient (far-from-
	# player) forage tier still uses -- see EarthChunkManager.step_forage vs
	# step_fruiting.
	"cherry": ["Cherry", "food", 20, 0.0],
	"apple": ["Apple", "food", 20, 0.0],
	"walnut": ["Walnut", "food", 20, 0.0],
	# The other three tree crops (see TreeSpecies -- a tree's species id IS the
	# id of the item it drops).
	"acorn": ["Acorn", "food", 20, 0.0],
	"hazelnut": ["Hazelnut", "food", 20, 0.0],
	"pine": ["Pine Nut", "food", 20, 0.0],
	"wood": ["Wood", "material", 40, 0.0],
	"wooden_club": ["Wooden Club", "weapon", 1, 8.0],
	"iron_sword": ["Iron Sword", "weapon", 1, 15.0],
	"iron_axe": ["Iron Axe", "tool", 1, 0.0],
	"torch": ["Torch", "material", 10, 0.0],
	# Structures you build into the world (see HotbarAction.PLACE), not inert
	# materials -- selecting one from the hotbar/inventory arms it for the next
	# build-input press instead of equipping/using it.
	"campfire": ["Campfire", "placeable", 5, 0.0],
	"cooked_meat": ["Cooked Meat", "food", 20, 0.0],
	# Primitive knapping-tech chain (see docs/concept/crafting.md's
	# gather-craft loop): pick up rocks, smash rock-on-rock for sharp shards,
	# lash a shard to a stick with grass fibre for a first crude weapon.
	"rock": ["Rock", "material", 20, 0.0],
	"stick": ["Stick", "material", 40, 0.0],
	"sharp_shard": ["Sharp Shard", "material", 20, 0.0],
	"plant_fibre": ["Plant Fibre", "material", 40, 0.0],
	# Taming gear (see docs/concept/taming.md). The lasso is held in hand like
	# the fishing rod and throws at an animal; the carrot is what buys its
	# trust afterwards.
	"lasso": ["Lasso", "tool", 1, 0.0],
	"carrot": ["Carrot", "food", 20, 0.0],
	# The other wild root crop -- see docs/concept/wild_crops.md.
	"potato": ["Potato", "food", 20, 0.0],
	# Woodworking chain (see docs/concept/woodworking.md): a bare felled
	# trunk bucks into logs by hand, or (saw + trained Carpentry) is sawn
	# whole into beam/plank instead.
	"log": ["Log", "material", 20, 0.0],
	"beam": ["Beam", "material", 20, 0.0],
	"plank": ["Plank", "material", 20, 0.0],
	"saw": ["Saw", "tool", 1, 0.0],
	"crude_blade": ["Crude Blade", "weapon", 1, 9.0],
	# Mining chain: a stone pickaxe knocks ore out of ore-bearing boulders.
	"stone": ["Stone", "material", 40, 0.0],
	"stone_pickaxe": ["Stone Pickaxe", "tool", 1, 0.0],
	"iron_ore": ["Iron Ore", "material", 40, 0.0],
	"copper_ore": ["Copper Ore", "material", 40, 0.0],
	"coal": ["Coal", "material", 40, 0.0],
	# Cooking chain: fish caught/dropped, cooked over a campfire.
	"fish": ["Fish", "food", 20, 0.0],
	"cooked_fish": ["Cooked Fish", "food", 20, 0.0],
	# Rare/legendary catches (see FishingMinigame.fish_rarity) are their own
	# item ids, not just "fish" -- so the rarity survives into the
	# inventory and grants a buff on eating (see FoodConsumption.FISH_BUFFS).
	"rare_fish": ["Rare Fish", "food", 20, 0.0],
	"legendary_fish": ["Legendary Fish", "food", 20, 0.0],
	# Wearable armor (see Equipment / concept/items.md's equipment slots).
	"leather_helm": ["Leather Helm", "armor", 1, 0.0, "head", 2.0],
	"leather_chest": ["Leather Chest", "armor", 1, 0.0, "chest", 4.0],
	"leather_legs": ["Leather Legs", "armor", 1, 0.0, "legs", 3.0],
	"leather_boots": ["Leather Boots", "armor", 1, 0.0, "feet", 1.0],
	# Smelting/metalworking (see concept/smelting.md): ore + coal -> ingot at a
	# heat source; ingots forge the iron tier that out-protects leather.
	"iron_ingot": ["Iron Ingot", "material", 40, 0.0],
	"copper_ingot": ["Copper Ingot", "material", 40, 0.0],
	"furnace": ["Furnace", "placeable", 5, 0.0],
	"iron_helm": ["Iron Helm", "armor", 1, 0.0, "head", 4.0],
	"iron_chest": ["Iron Chest", "armor", 1, 0.0, "chest", 8.0],
	"iron_legs": ["Iron Legs", "armor", 1, 0.0, "legs", 6.0],
	"iron_boots": ["Iron Boots", "armor", 1, 0.0, "feet", 2.0],
	# Fishing (see concept/fishing.md): a rod cast at water lands fish.
	"fishing_rod": ["Fishing Rod", "tool", 1, 0.0],
	# "Three Fragments" hunt (docs/concept/easter_eggs.md, see
	# ThreeFragmentsHunt for the aggregation logic): three small,
	# unremarkable items, each quietly granted the first time its own source
	# egg is found (signed secret room / ancient terminal / WarGames console
	# command -- see scenes/world.gd's own granting logic), plus the bonus
	# item granted once all three are held together. All four are purely
	# inert "material" items with zero weapon_damage -- no fanfare, no
	# mechanical weight, matching this whole Easter-egg family's design
	# pillars.
	"terminal_fragment": ["Pitted Circuit Shard", "material", 5, 0.0],
	"secret_room_token": ["Tarnished Token", "material", 5, 0.0],
	"wargames_punch_card": ["Scorched Punch Card", "material", 5, 0.0],
	"curious_keepsake": ["Curious Keepsake", "material", 5, 0.0],
}


func has(item_id: String) -> bool:
	return _ITEMS.has(item_id)


## `item_id`'s category ("food", "weapon", "tool", ...) -- the same string
## make() stamps onto the built Item's `kind`, exposed standalone so a caller
## can classify an item id (e.g. "is this food?") without constructing a
## whole Item first (see Player.sell_food_to_village's village-feeding
## fallback, docs/concept/progression.md "Ecological literacy"). "" for an
## unknown id.
func kind_of(item_id: String) -> String:
	if not _ITEMS.has(item_id):
		return ""
	return String(_ITEMS[item_id][1])


func make(item_id: String) -> Item:
	var spec: Array = _ITEMS[item_id]
	var equip_slot: String = spec[4] if spec.size() > 4 else ""
	var armor: float = spec[5] if spec.size() > 5 else 0.0
	var mass_kg := _mass_kg_for(item_id)
	return Item.new(item_id, spec[0], spec[1], spec[2], spec[3], equip_slot, armor, mass_kg)


## Real average mass of one harvested root/tuber, kilograms (see
## docs/concept/wild_crops.md) -- a REAL reference weight for the whole
## vegetable, not a material-density x volume estimate the way weapon mass
## is: a carrot/potato isn't a uniform block of "carrot material" the way a
## sword is iron, so the honest real-world number is a whole-item average
## rather than a derived one. Real, so a pulled root can enter the same
## momentum model (Kick/HeldItemThrow, docs/concept/materials.md) every other
## physical object already does -- "a real physical entity, not just an
## inventory grant" (docs/concept/wild_crops.md's own framing for the pull).
##
## carrot: a medium carrot averages roughly 60-70g.
## potato: a medium potato averages roughly 150-200g.
const _PRODUCE_MASS_KG := {
	"carrot": 0.07,
	"potato": 0.17,
}


## Real mass for `item_id` -- a real weapon (material + volume estimate, see
## _WEAPON_MATERIAL_AND_VOLUME) or a real harvested vegetable
## (_PRODUCE_MASS_KG); 0.0 for anything with no real mass modeled yet.
func _mass_kg_for(item_id: String) -> float:
	if _PRODUCE_MASS_KG.has(item_id):
		return _PRODUCE_MASS_KG[item_id]
	if not _WEAPON_MATERIAL_AND_VOLUME.has(item_id):
		return 0.0
	var material_and_volume: Array = _WEAPON_MATERIAL_AND_VOLUME[item_id]
	return _material_properties.mass_kg_for(material_and_volume[0], material_and_volume[1])


## Every id this catalog can build, for a /help-style listing.
func known_ids() -> Array:
	return _ITEMS.keys()
