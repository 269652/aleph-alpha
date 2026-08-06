extends RefCounted

## Item id -> full Item definition lookup, for anything that needs to build a
## real Item from just its string id (currently: DevConsole's /give command).
## Not the sole source of truth for drops -- loot_table.gd, forage_scheduler.gd
## and choppable_tree.gd each define their own drop-specific item specs
## independently -- this is a superset covering every id used anywhere in the
## game, so /give doesn't need to know which subsystem originally defined it.

const Item = preload("res://src/gameplay/item.gd")

## item_id -> [display_name, kind, max_stack, weapon_damage, equip_slot?, armor?]
## (equip_slot and armor are optional trailing fields, used by armor items).
const _ITEMS := {
	"hide": ["Hide", "material", 40, 0.0],
	"meat": ["Raw Meat", "food", 20, 0.0],
	"fang": ["Fang", "material", 40, 0.0],
	"fruit": ["Fruit", "food", 20, 0.0],
	"nut": ["Nut", "food", 20, 0.0],
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
}


func has(item_id: String) -> bool:
	return _ITEMS.has(item_id)


func make(item_id: String) -> Item:
	var spec: Array = _ITEMS[item_id]
	var equip_slot: String = spec[4] if spec.size() > 4 else ""
	var armor: float = spec[5] if spec.size() > 5 else 0.0
	return Item.new(item_id, spec[0], spec[1], spec[2], spec[3], equip_slot, armor)


## Every id this catalog can build, for a /help-style listing.
func known_ids() -> Array:
	return _ITEMS.keys()
