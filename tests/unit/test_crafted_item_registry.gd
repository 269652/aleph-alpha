extends GutTest

## CraftedItemRegistry: the id -> structure map that lets a crafted item
## survive a save.
##
## The bug this exists for is verified in scenes/player.gd: inventory loads
## with `if _item_catalog.has(entry.id)` (:860-862) and equipment with a
## matching `continue` (:866-868), so any id the static ItemCatalog does not
## know is silently dropped. Without somewhere to resolve a content-addressed
## id, every emergent item evaporates on save/load.

const CraftedItemRegistry = preload("res://src/gameplay/crafted_item_registry.gd")
const CraftedItemRegistryPersistence = preload(
	"res://src/gameplay/crafted_item_registry_persistence.gd"
)
const AssemblyId = preload("res://src/gameplay/assembly_id.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

const TEST_PATH := "user://test_crafted_items.bin"

var registry: CraftedItemRegistry
var persistence: CraftedItemRegistryPersistence


func before_each():
	registry = CraftedItemRegistry.new()
	persistence = CraftedItemRegistryPersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


## An iron-bladed, wood-gripped, bronze-pommelled sword with a real volume on
## every part, so its mass is a real number rather than "not modelled".
func _sword(blade_material: String = "iron") -> Dictionary:
	return {
		"pattern": "sword",
		"parts": [
			{
				"material": blade_material,
				"geometry": "blade",
				"role": "edge",
				"length_cm": 70.0,
				"volume_cm3": 120.0,
				"treatment": {"sharpening": 0.75},
			},
			{
				"material": "wood",
				"geometry": "rod",
				"role": "grip",
				"length_cm": 12.0,
				"volume_cm3": 100.0,
			},
		],
		"joints": [{"kind": "tang", "a": 0, "b": 1}],
	}


# --- registration ----------------------------------------------------------


func test_registering_an_assembly_returns_its_content_id():
	assert_eq(registry.register(_sword()), AssemblyId.assembly_id(_sword()))


func test_a_registered_id_is_known():
	var id := registry.register(_sword())
	assert_true(registry.has(id))


func test_registering_the_same_assembly_twice_stores_one_entry():
	registry.register(_sword())
	registry.register(_sword())
	assert_eq(registry.size(), 1)


## The whole point of canonicalisation reaching the registry: a player who
## listed the grip first has not crafted a second, near-duplicate item.
func test_registering_a_reordered_listing_does_not_add_a_second_entry():
	var listed_blade_first := _sword()
	var listed_grip_first := _sword()
	listed_grip_first["parts"] = [listed_blade_first["parts"][1], listed_blade_first["parts"][0]]
	listed_grip_first["joints"] = [{"kind": "tang", "a": 1, "b": 0}]

	assert_eq(registry.register(listed_blade_first), registry.register(listed_grip_first))
	assert_eq(registry.size(), 1)


func test_two_different_assemblies_are_two_entries():
	registry.register(_sword("iron"))
	registry.register(_sword("obsidian"))
	assert_eq(registry.size(), 2)


func test_a_looked_up_assembly_keeps_its_structure():
	var id := registry.register(_sword())
	var stored: Dictionary = registry.get_assembly(id)
	assert_eq(stored["pattern"], "sword")
	assert_eq((stored["parts"] as Array).size(), 2)
	assert_eq((stored["joints"] as Array).size(), 1)


## Re-registering what came back out must land on the same id, or the registry
## would grow a new entry every time a save was reloaded.
func test_re_registering_a_stored_assembly_is_idempotent():
	var id := registry.register(_sword())
	assert_eq(registry.register(registry.get_assembly(id)), id)
	assert_eq(registry.size(), 1)


# --- unknown ids must fail clearly, never crash ---------------------------


func test_an_unknown_id_is_not_known():
	assert_false(registry.has("asm_0000000000000000"))


func test_an_unknown_id_has_no_assembly():
	assert_null(registry.get_assembly("asm_0000000000000000"))


func test_an_unknown_id_makes_no_item():
	assert_null(registry.make_item("asm_0000000000000000"))


func test_an_unknown_id_has_no_kind():
	assert_eq(registry.kind_of("asm_0000000000000000"), "")


# --- THE test: identity that survives a save ------------------------------


func test_a_crafted_item_survives_a_save_load_round_trip():
	var id := registry.register(_sword())
	persistence.save(registry, TEST_PATH)

	registry = null
	var restored := persistence.load_registry(TEST_PATH)

	assert_true(restored.has(id), "the id is still known after the round trip")
	assert_eq(restored.register(_sword()), id, "and still names the same structure")
	assert_eq(restored.get_assembly(id), AssemblyId.canonical_form(_sword()))
	assert_eq(restored.make_item(id).id, id)


func test_a_round_trip_keeps_every_registered_item():
	registry.register(_sword("iron"))
	registry.register(_sword("obsidian"))
	registry.register(_sword("stone"))
	persistence.save(registry, TEST_PATH)
	assert_eq(persistence.load_registry(TEST_PATH).size(), 3)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_has_save_is_true_after_saving():
	persistence.save(registry, TEST_PATH)
	assert_true(persistence.has_save(TEST_PATH))


func test_loading_with_no_save_file_returns_an_empty_registry():
	assert_eq(persistence.load_registry(TEST_PATH).size(), 0)


func test_wipe_removes_an_existing_save():
	persistence.save(registry, TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


## A corrupt or truncated save must leave the player with an empty registry,
## not a half-built one and not a crash on the load path.
func test_a_registry_restored_from_garbage_is_empty_rather_than_broken():
	assert_eq(CraftedItemRegistry.from_dicts(null).size(), 0)
	assert_eq(CraftedItemRegistry.from_dicts("not a registry").size(), 0)
	assert_eq(CraftedItemRegistry.from_dicts({"asm_bad": 17}).size(), 0)


# --- the Item a crafted id resolves to ------------------------------------


## An object is colloquially named for the material that does its work, and on
## a tool or a weapon that is the hardest part -- an iron sword has a wooden
## grip, a stone axe a wooden haft. Reuses MaterialProperties' own hardness
## rather than a second opinion on which material "counts".
func test_a_crafted_item_is_named_after_its_hardest_working_material():
	var id := registry.register(_sword())
	assert_eq(registry.make_item(id).display_name, "Iron Sword")


func test_a_stone_headed_axe_is_named_for_its_head_not_its_haft():
	var axe := {
		"pattern": "axe",
		"parts": [
			{"material": "stone", "geometry": "wedge", "role": "head"},
			{"material": "wood", "geometry": "rod", "role": "haft"},
		],
		"joints": [{"kind": "lashed", "a": 0, "b": 1}],
	}
	assert_eq(registry.make_item(registry.register(axe)).display_name, "Stone Axe")


## And the name it derives for an iron sword is the one the shipped catalog
## already uses for its hand-authored iron_sword -- the emergent track and the
## authored track must not read as two different games.
func test_the_derived_name_matches_the_shipped_catalogs_own_wording():
	var id := registry.register(_sword())
	assert_eq(registry.make_item(id).display_name, ItemCatalog.new().make("iron_sword").display_name)


## Every assembled object in the shipped catalog -- weapon, tool, armor -- is
## max_stack 1, and an assembly IS an assembled object. Read from the catalog
## rather than retyped, so the two cannot drift.
func test_a_crafted_item_stacks_like_every_other_assembled_object():
	var id := registry.register(_sword())
	assert_eq(registry.make_item(id).max_stack, ItemCatalog.new().make("iron_sword").max_stack)


## The second verified bug, fixed by construction rather than by touching
## item_stack.gd: `can_stack_with` compares ids and nothing else (:45), which
## is only safe if an id cannot name two different structures. Content
## addressing makes that true.
func test_content_addressing_makes_id_only_stacking_correct():
	var iron := registry.make_item(registry.register(_sword("iron")))
	var iron_again := registry.make_item(registry.register(_sword("iron")))
	var obsidian := registry.make_item(registry.register(_sword("obsidian")))

	assert_true(ItemStack.new(iron, 1).can_stack_with(ItemStack.new(iron_again, 1)))
	assert_false(ItemStack.new(iron, 1).can_stack_with(ItemStack.new(obsidian, 1)))


## Real mass, from the shipped MaterialProperties.mass_kg_for (density x
## volume) summed over the parts -- 120cm^3 of iron at 7.8 g/cm^3 plus 100cm^3
## of wood at 0.6. Nothing about mass is authored here; the material model
## produces it, exactly as ItemCatalog._mass_kg_for already does for the
## hand-authored weapons.
func test_a_crafted_items_mass_is_its_parts_real_masses_summed():
	var id := registry.register(_sword())
	assert_almost_eq(registry.make_item(id).mass_kg, 7.8 * 0.120 + 0.6 * 0.100, 0.0001)


## item.gd's documented convention: 0.0 means "nobody has modelled this yet",
## not "weighs nothing". A part with no volume has no modelled mass, so the
## item honestly carries none rather than a guess.
func test_a_part_with_no_volume_leaves_the_mass_unmodelled():
	var axe := {
		"pattern": "axe",
		"parts": [{"material": "stone", "geometry": "wedge", "role": "head"}],
		"joints": [],
	}
	assert_eq(registry.make_item(registry.register(axe)).mass_kg, 0.0)


## And a PARTIALLY measured assembly is still unmodelled, not partially
## weighed. Summing only the parts that happen to carry a volume would report a
## sword lighter than its own blade and present it as physics -- worse than
## item.gd's honest "nobody has modelled this yet" 0.0, because a wrong number
## propagates into the momentum model (knockback reads mass) while a zero is
## visibly absent.
func test_an_assembly_with_only_some_volumes_measured_reports_no_mass():
	var half_measured := _sword()
	(half_measured["parts"][1] as Dictionary).erase("volume_cm3")
	assert_eq(registry.make_item(registry.register(half_measured)).mass_kg, 0.0)


## Damage, armor and equip slot are the part-graph compiler's job, not this
## registry's. Until it lands they stay at item.gd's "not modelled yet" 0.0
## rather than being invented here.
func test_combat_stats_are_left_unmodelled_for_the_compiler():
	var item := registry.make_item(registry.register(_sword()))
	assert_eq(item.weapon_damage, 0.0)
	assert_eq(item.armor, 0.0)
	assert_eq(item.equip_slot, "")


func test_a_crafted_item_reports_the_crafted_kind():
	var id := registry.register(_sword())
	assert_eq(registry.make_item(id).kind, CraftedItemRegistry.CRAFTED_KIND)
	assert_eq(registry.kind_of(id), CraftedItemRegistry.CRAFTED_KIND)
