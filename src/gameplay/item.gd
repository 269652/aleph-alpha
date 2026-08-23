extends RefCounted

## An item definition: immutable identity/stats shared by every stack of that
## item. Kinds today: "weapon" (has weapon_damage), "tool" (e.g. an axe --
## see is_axe()), "material"/"food" (loot).

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


func _init(
	a_id: String,
	a_display_name: String,
	a_kind: String,
	a_max_stack: int,
	a_weapon_damage: float = 0.0,
	a_equip_slot: String = "",
	a_armor: float = 0.0,
	a_mass_kg: float = 0.0
) -> void:
	id = a_id
	display_name = a_display_name
	kind = a_kind
	max_stack = a_max_stack
	weapon_damage = a_weapon_damage
	equip_slot = a_equip_slot
	armor = a_armor
	mass_kg = a_mass_kg


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
