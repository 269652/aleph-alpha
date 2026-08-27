extends GutTest

## Player.to_save_dict()/apply_save_dict(): the domain-level "what actually
## needs remembering" round-trip (see docs/concept/persistence.md).
## PlayerSave (test_player_save.gd) is the separate, dumber I/O layer this
## Dictionary eventually flows through -- these tests never touch disk.

const PlayerScene = preload("res://scenes/player.tscn")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

var source: Player
var restored: Player
var _item_catalog := ItemCatalog.new()
var _appearance_maker := HeroAppearance.new()


func before_each():
	source = PlayerScene.instantiate()
	add_child(source)
	restored = PlayerScene.instantiate()
	add_child(restored)


func after_each():
	remove_child(source)
	source.free()
	remove_child(restored)
	restored.free()


## Previously the creator's authored look was applied to the character view
## once and then forgotten -- nothing on Player retained it, so it couldn't
## be saved (see docs/concept/persistence.md).
func test_apply_class_remembers_the_authored_appearance():
	var look := _appearance_maker.appearance_for("mage", 7)
	source.apply_class("mage", {}, look)
	assert_eq(source.appearance, look)


func test_to_save_dict_captures_position_class_and_appearance():
	var look := _appearance_maker.appearance_for("ranger", 3)
	source.apply_class("ranger", {}, look)
	source.position = Vector2(320, 480)
	source.respawn_position = Vector2(64, 64)

	var data := source.to_save_dict()

	assert_eq(data.position, Vector2(320, 480))
	assert_eq(data.respawn_position, Vector2(64, 64))
	assert_eq(data.character_class, "ranger")
	assert_eq(data.appearance, look)


## The whole point of apply_save_dict existing separately from apply_class:
## apply_class alone always fully heals (see its own health = max_health),
## which is correct for a brand new character but would silently patch up a
## loaded character's damage every time they reload.
func test_a_restored_player_keeps_the_saved_health_not_a_full_heal():
	source.apply_class("warrior", {"max_health": 40.0})
	source.health = 55.0  # damaged, below its own max_health

	restored.apply_save_dict(source.to_save_dict())

	assert_eq(restored.health, 55.0)
	assert_eq(restored.max_health, source.max_health)


func test_a_restored_player_carries_the_same_inventory_contents():
	# Start from a clean slate so the assertion isn't fighting _ready()'s
	# starter grants (sword/axe/leather set/fishing rod).
	source.inventory = load("res://src/gameplay/inventory.gd").new(source.inventory.slot_count)
	source.inventory.add(_item_catalog.make("wood"), 12)
	source.inventory.add(_item_catalog.make("iron_ore"), 3)

	restored.apply_save_dict(source.to_save_dict())

	var restored_counts := {}
	for stack in restored.inventory.stacks():
		restored_counts[stack.item.id] = stack.count
	assert_eq(restored_counts.get("wood"), 12)
	assert_eq(restored_counts.get("iron_ore"), 3)


func test_a_restored_player_keeps_worn_armor_and_the_held_weapon():
	source.equip_armor(_item_catalog.make("leather_helm"))
	source.equip_item(_item_catalog.make("iron_sword"))

	restored.apply_save_dict(source.to_save_dict())

	assert_eq(restored.equipment.equipped_in("head").id, "leather_helm")
	assert_not_null(restored.equipped_item)
	assert_eq(restored.equipped_item.id, "iron_sword")
	assert_eq(restored.equipment.equipped_in("weapon").id, "iron_sword")


func test_a_restored_player_keeps_wallet_experience_and_skill_progress():
	source.wallet.balance = 250
	source.experience.total_xp = 900
	source.experience.level = 4
	source.experience.unspent_points = 2
	source.allocated_nodes = {"vitality_1": true}
	source.unlocked_keystones = {"iron_will": true}

	restored.apply_save_dict(source.to_save_dict())

	assert_eq(restored.wallet.balance, 250)
	assert_eq(restored.experience.total_xp, 900)
	assert_eq(restored.experience.level, 4)
	assert_eq(restored.experience.unspent_points, 2)
	assert_eq(restored.allocated_nodes, {"vitality_1": true})
	assert_eq(restored.unlocked_keystones, {"iron_will": true})


func test_a_restored_player_keeps_hotbar_bindings():
	source.hotbar.assign(0, "iron_sword")
	source.hotbar.assign(2, "fishing_rod")

	restored.apply_save_dict(source.to_save_dict())

	assert_eq(restored.hotbar.item_id_at(0), "iron_sword")
	assert_eq(restored.hotbar.item_id_at(2), "fishing_rod")


# --- emergent, crafted items (see docs/concept/item_identity.md) ------------


func _sword() -> Dictionary:
	return {
		"pattern": "sword",
		"parts": [
			{"material": "iron", "geometry": "blade", "role": "edge", "length_cm": 70.0},
			{"material": "wood", "geometry": "rod", "role": "grip", "length_cm": 12.0},
		],
		"joints": [{"kind": "tang", "a": 0, "b": 1}],
	}


## THE regression this whole slice exists to prevent, at the level it actually
## bit: apply_save_dict loads inventory with `if _item_catalog.has(entry.id)`,
## so before the registry rode along in the same save dict, an id the static
## catalog had never heard of was silently dropped and every crafted item
## evaporated on load.
func test_a_crafted_item_survives_the_save_dict_round_trip():
	var id: String = source.crafted_items.register(_sword())
	source.inventory.add(source.crafted_items.make_item(id), 1)

	restored.apply_save_dict(source.to_save_dict())

	assert_true(restored.inventory.has(id), "the crafted item is still in the inventory")
	assert_eq(restored.inventory.count_of(id), 1)


## And it comes back as the same OBJECT, not just the same id -- the structure
## has to travel with it or the id names nothing on the other side.
func test_a_restored_crafted_item_still_knows_what_it_is_made_of():
	var id: String = source.crafted_items.register(_sword())
	source.inventory.add(source.crafted_items.make_item(id), 1)

	restored.apply_save_dict(source.to_save_dict())

	assert_true(restored.crafted_items.has(id))
	assert_eq(restored.crafted_items.get_assembly(id), source.crafted_items.get_assembly(id))
	assert_eq(restored.inventory.stacks()[0].item.display_name, "Iron Sword")


## A save with no crafted items at all (every save written before this existed)
## must load exactly as it did, not fail on a missing key.
func test_a_save_predating_crafted_items_still_loads():
	var legacy := source.to_save_dict()
	legacy.erase("crafted_items")

	restored.apply_save_dict(legacy)

	assert_eq(restored.crafted_items.size(), 0)
