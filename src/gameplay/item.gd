extends RefCounted

## An item definition: identity/stats shared by every stack of that item.
## Kinds today: "weapon" (has weapon_damage), "tool" (e.g. an axe -- see
## is_axe()), "material"/"food" (loot). One field, `wear`, is a deliberate
## exception to "shared" -- see its own doc comment below.

var id: String
var display_name: String
var kind: String
var max_stack: int
var weapon_damage: float
## For armor (kind "armor"): which equipment slot it fills ("head"/"chest"/
## "legs"/"feet"). "" for non-armor; a weapon auto-slots to "weapon" (see
## equip_slot_name). And the flat armor value it grants when worn (see
## Equipment.total_armor / Player.take_damage mitigation).
var equip_slot: String
var armor: float

## Real mass in kilograms (see MaterialProperties.mass_kg_for, docs/concept/
## materials.md's momentum = mass * velocity model). 0.0 for anything with no
## mass modeled yet -- today that's every weapon-kind item (see
## ItemCatalog._ITEMS' own doc comment on which items carry a real material +
## volume estimate). A weapon's mass feeds a real swing's knockback the same
## way Throwable.impact_knockback already reads mass for a thrown item.
var mass_kg: float

## Which art this item's identity resolves to (see docs/concept/
## item_illustrations.md) -- every renderer (inventory/hotbar/paperdoll/
## dropped-item) looks up its picture via THIS, never `id` directly, so an
## item's identity and its art can diverge on purpose: a crafted/variant item
## can share a base item's art via a shared sprite_id instead of needing a
## second catalog art entry. Defaults to this item's own `id` (see _init)
## when the catalog doesn't specify one, so every item renders exactly as
## before until something actually asks for a divergent sprite_id.
var sprite_id: String

## Accumulated combat fatigue (see docs/concept/item_durability.md) -- the
## one deliberate exception to this file's own "immutable identity/stats"
## framing above. It has to survive the ItemStack -> Equipment transition
## (Equipment._worn stores a bare Item, not a stack), so it lives here
## rather than on ItemStack the way food's age_seconds does. Not a
## constructor parameter: unlike every field above, wear isn't part of an
## item's catalog definition, it's state that accumulates from zero over
## one specific item's own lifetime. 0.0 for every item today -- nothing
## mutates it yet outside Player's combat wiring.
var wear: float = 0.0

## Which species this specific tool is currently holding, if any (see
## docs/concept/capture_dsl.md) -- the same deliberate exception `wear`
## already is: not a constructor parameter, not part of an item's catalog
## definition, state that starts blank and accumulates over one specific
## item's own lifetime. A capture device typically has max_stack 1 (see
## item_catalog's butterfly_net entry), so this mutates in place with no
## stacking ambiguity, exactly the way `wear` already does.
var captive_species: String = ""


func _init(
	a_id: String,
	a_display_name: String,
	a_kind: String,
	a_max_stack: int,
	a_weapon_damage: float = 0.0,
	a_equip_slot: String = "",
	a_armor: float = 0.0,
	a_mass_kg: float = 0.0,
	a_sprite_id: String = ""
) -> void:
	id = a_id
	display_name = a_display_name
	kind = a_kind
	max_stack = a_max_stack
	weapon_damage = a_weapon_damage
	equip_slot = a_equip_slot
	armor = a_armor
	mass_kg = a_mass_kg
	sprite_id = a_sprite_id if a_sprite_id != "" else a_id


func is_weapon() -> bool:
	return kind == "weapon"


## The equipment slot this item fills: its declared slot (armor), else
## "weapon" for anything held in the hand -- a weapon or a tool (axe,
## pickaxe, fishing rod: see Player.equip_item, which puts both kinds in the
## same single equipped_item field) -- else "" (not equippable).
func equip_slot_name() -> String:
	if equip_slot != "":
		return equip_slot
	return "weapon" if (is_weapon() or kind == "tool") else ""


func is_equippable() -> bool:
	return equip_slot_name() != ""


## An axe fells trees. "pickaxe" contains "axe" but is a mining tool, not a
## felling axe -- exclude it explicitly (see is_pickaxe).
func is_axe() -> bool:
	return kind == "tool" and id.contains("axe") and not id.contains("pickaxe")


func is_pickaxe() -> bool:
	return kind == "tool" and id.contains("pickaxe")


## A saw is what turns a bare felled trunk straight into beam/plank instead
## of raw logs (see docs/concept/woodworking.md) -- an axe fundamentally
## cannot do this.
func is_saw() -> bool:
	return kind == "tool" and id.contains("saw")


func is_holding_captive() -> bool:
	return captive_species != ""
