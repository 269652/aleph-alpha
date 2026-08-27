extends RefCounted

## id -> structure map for emergent, crafted items: the thing that lets a
## crafted item survive a save.
##
## The bug this exists for is real and verified in the shipped loader.
## scenes/player.gd loads inventory with
##     for entry in data.get("inventory", []):
##         if _item_catalog.has(entry.id):
## and equipment with a matching `continue` a few lines below -- so any id the
## static ItemCatalog does not know is SILENTLY DROPPED. Without somewhere to
## resolve a content-addressed id, every emergent item evaporates on save/load.
## This registry is that somewhere; ItemCatalog.has()/make() fall back to it
## (see docs/concept/item_identity.md).
##
## Keyed by AssemblyId.assembly_id, so the key IS the value's content. Three
## things fall out of that and none of them needed a refactor elsewhere:
##   - registering the same object twice is automatically one entry, however
##     the player happened to list its parts;
##   - item_stack.gd:45's id-only `can_stack_with` becomes CORRECT rather than
##     a latent merge bug, because an id can no longer name two structures;
##   - the id a save file carries is the same id in every session and on every
##     other player's machine, so a traded item needs no id negotiation.
##
## What is stored is the CANONICAL form, not the raw assembly: two listings of
## one sword must not round-trip into two different blobs, and the canonical
## form is already the thing the id was computed from.

const Item = preload("res://src/gameplay/item.gd")
const AssemblyId = preload("res://src/gameplay/assembly_id.gd")
const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

## Item.kind for anything this registry builds. Deliberately NOT "weapon" /
## "tool" / "armor": what an assembly IS mechanically is the part-graph
## compiler's decision, and stamping a kind here would be this file guessing at
## it. Pinned by test_a_crafted_item_reports_the_crafted_kind.
const CRAFTED_KIND := "crafted"

## Every assembled object in the shipped catalog -- weapon, tool, armor alike --
## is max_stack 1 (see ItemCatalog._ITEMS: iron_sword, iron_axe, saw,
## leather_chest, every instrument). An assembly IS an assembled object, so it
## stacks the same way.
##
## Restated here rather than preloaded from ItemCatalog, because ItemCatalog is
## about to preload THIS file for its unknown-id fallback and the reverse
## preload would be a cycle -- the same reason (and the same remedy)
## MaterialProperties.BRITTLE_TOUGHNESS restates ImpactResolver's cutoff instead
## of importing it. The two cannot drift apart silently: pinned EQUAL to the
## catalog's own value by
## test_a_crafted_item_stacks_like_every_other_assembled_object.
const ASSEMBLED_MAX_STACK := 1

## Shown when an assembly names neither a material nor a pattern -- an empty or
## hand-corrupted structure. A visible placeholder rather than "", so a bad
## entry reads as a bug in the inventory instead of as a blank row.
const UNNAMED_DISPLAY_NAME := "Curious Assembly"

var _assemblies := {}
var _material_properties := MaterialProperties.new()


## Stores `assembly` under its content id and returns that id. Idempotent by
## construction: the same object, listed any way round, canonicalises to the
## same form and therefore to the same key.
##
## Canonicalises twice -- once for the key, once for the stored blob -- rather
## than reaching into AssemblyId's private serializer to do both in one pass.
## Registration happens when a player finishes a craft or when a save loads, not
## per frame, so the honest use of the public API is worth more here than the
## saved pass.
func register(assembly: Dictionary) -> String:
	var item_id := AssemblyId.assembly_id(assembly)
	_assemblies[item_id] = AssemblyId.canonical_form(assembly)
	return item_id


func has(item_id: String) -> bool:
	return _assemblies.has(item_id)


## The stored canonical form, or null for an id this registry has never seen --
## an unknown id is a normal condition on a hand-edited or partial save, not an
## error worth taking the game down over.
func get_assembly(item_id: String):
	if not _assemblies.has(item_id):
		return null
	return _assemblies[item_id]


## `item_id`'s category, or "" for an unknown id -- deliberately the same
## signature and the same "" -for-unknown contract ItemCatalog.kind_of already
## uses, so a caller can consult either without special-casing which it got.
func kind_of(item_id: String) -> String:
	if not _assemblies.has(item_id):
		return ""
	return CRAFTED_KIND


func size() -> int:
	return _assemblies.size()


## Builds the Item a crafted id resolves to, or null for an unknown id (rather
## than ItemCatalog.make's raw `_ITEMS[item_id]`, which would crash).
##
## Damage, armor and equip slot stay at item.gd's "not modelled yet" 0.0/"":
## deriving those from a part graph is the compiler's job, and inventing them
## here would put a second, quieter opinion in the codebase for the compiler to
## later contradict. Mass is different -- it is not a design decision, it is
## density x volume, and MaterialProperties already computes it.
func make_item(item_id: String) -> Item:
	if not _assemblies.has(item_id):
		return null
	var canonical: Dictionary = _assemblies[item_id]
	return Item.new(
		item_id,
		_display_name_for(canonical),
		CRAFTED_KIND,
		ASSEMBLED_MAX_STACK,
		0.0,
		"",
		0.0,
		_mass_kg_for(canonical)
	)


## An object is colloquially named for the material that does its work, and on
## a tool or a weapon that is the hardest part: an "iron sword" has a wooden
## grip, a "stone axe" a wooden haft. Reuses MaterialProperties' own hardness
## scalar rather than a second opinion on which material "counts", so the name
## and the physics agree about what the thing is made of.
##
## Ties break on canonical part order, which is itself order-independent, so
## two listings of one object never disagree about their own name.
func _display_name_for(canonical: Dictionary) -> String:
	var words := PackedStringArray()
	var material := _hardest_material(canonical)
	if material != "":
		words.append(material.capitalize())
	var pattern := String(canonical.get("pattern", ""))
	if pattern != "":
		words.append(pattern.capitalize())
	if words.is_empty():
		return UNNAMED_DISPLAY_NAME
	return " ".join(words)


func _hardest_material(canonical: Dictionary) -> String:
	var hardest := ""
	var best_hardness := -1.0
	for part in canonical.get("parts", []):
		var material := String((part as Dictionary).get("material", ""))
		if material == "":
			continue
		var hardness := _material_properties.property_value(material, "hardness")
		if hardness > best_hardness:
			best_hardness = hardness
			hardest = material
	return hardest


## Real mass: density x volume summed over the parts, straight out of
## MaterialProperties.mass_kg_for -- exactly what ItemCatalog._mass_kg_for
## already does for the hand-authored weapons, just over a graph instead of one
## authored [material, volume] pair. Volumes come back through
## AssemblyId.dequantize_volume_cm3 so this never needs to know the quantum.
##
## A part with NO volume leaves the whole item unmodelled (0.0), rather than
## contributing nothing to a sum. Summing the measured parts alone would report
## a sword lighter than its own blade and present that as physics -- and mass
## feeds the shared momentum model (a swing's knockback reads it, see
## docs/concept/materials.md), so a wrong number propagates where a visibly
## absent 0.0 does not. item.gd's own convention is that 0.0 means "nobody has
## modelled this yet", which is the honest reading of a half-measured assembly.
## Pinned by test_a_part_with_no_volume_leaves_the_mass_unmodelled /
## test_an_assembly_with_only_some_volumes_measured_reports_no_mass.
func _mass_kg_for(canonical: Dictionary) -> float:
	var parts: Array = canonical.get("parts", [])
	if parts.is_empty():
		return 0.0
	var total := 0.0
	for part in parts:
		var fields: Dictionary = part
		if not fields.has("volume_cm3"):
			return 0.0
		var volume_cm3 := AssemblyId.dequantize_volume_cm3(int(fields["volume_cm3"]))
		total += _material_properties.mass_kg_for(String(fields.get("material", "")), volume_cm3)
	return total


## id -> canonical form, ready for store_var. Matches EventStore.to_dicts'
## "hand the persistence layer plain data, keep the file format's knowledge
## here" split rather than letting the persistence layer reach into this
## registry's internals.
func to_dicts() -> Dictionary:
	return _assemblies.duplicate(true)


## Rebuilds a registry from to_dicts()' output.
##
## Every entry is re-registered through register() rather than trusted into the
## dictionary, which means the id is RE-DERIVED from the structure instead of
## read off the key. That is the one thing content addressing makes free: the
## key is redundant, so a hand-edited save cannot leave an id naming a structure
## it is not -- the entry simply lands under whatever it now genuinely is. For
## an untouched save this is a no-op, guaranteed by canonicalisation being
## idempotent (test_re_registering_a_stored_assembly_is_idempotent).
##
## Anything that is not id -> Dictionary is skipped, and a `data` that is not a
## Dictionary at all yields an empty registry: a truncated or corrupt save must
## leave the player with no crafted items rather than a half-built registry or
## a crash on the load path.
static func from_dicts(data) -> RefCounted:
	var registry = new()
	if typeof(data) != TYPE_DICTIONARY:
		return registry
	for item_id in data:
		if typeof(data[item_id]) != TYPE_DICTIONARY:
			continue
		registry.register(data[item_id])
	return registry
