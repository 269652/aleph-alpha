extends RefCounted

## What a creature drops when it dies. Deterministic (fixed drops, not
## randomized) so the loot economy is predictable and testable; a
## rarity/roll layer can come later. Returns fresh ItemStacks each call so
## callers can mutate them freely.
##
## Measured before this was derived: `_DROPS` was a four-row authored table
## -- herbivore, boar, predator, lynx -- and TWO of those keys are retired
## anonymous placeholders that no biome pool spawns any more. So killing a
## deer, a wolf, a bear, a lion, a jaguar, a horse or anything else in the
## live roster dropped literally nothing, and `CreatureMarker._spawn_carcass_
## if_eligible` early-returns when `drops_for` is empty, so it did not even
## leave a body. A player learned within minutes that fighting is a pure
## cost with no upside, which is why predators read as obstacles to route
## around rather than as things to hunt.
##
## So the counts are DERIVED from each animal's real mass rather than
## authored per species: eleven species do not need eleven hand-tuned rows,
## and a creature added to a biome pool tomorrow cannot ship worthless
## (test_every_species_the_world_spawns_drops_something holds that).
## `Butchering` owns the arithmetic -- what a knife takes off a carcass and
## what a kill promises are one number, not two.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const Butchering = preload("res://src/gameplay/butchering.gd")

## Shared item definitions for drops.
const _ITEMS := {
	"hide": ["Hide", "material", 40],
	"meat": ["Raw Meat", "food", 20],
	"fang": ["Fang", "material", 40],
}

## Which species this table knows at all is not listed here: it is exactly
## what `CreatureMass` has a real mass for, which every spawnable species is
## in by construction. A two-way drift test pins that against
## `CreatureRenderer`'s own biome pools -- read from the pools rather than
## preloaded, because a pure gameplay rule must not drag the rendering layer
## in -- so a creature added to a pool tomorrow cannot ship worthless and a
## row for something nothing spawns cannot sit here as dead weight.

## Below this live weight an animal is not skinned for a usable hide. Around
## rabbit size: the smallest animal whose skin is traditionally worth taking
## and tanning as a hide rather than discarded with the carcass.
const MIN_HIDE_MASS_KG := 1.5


## Every stack `species` leaves behind, or an empty array for anything this
## world does not spawn.
func drops_for(species: String) -> Array:
	# `CreatureMass.mass_kg_for` estimates a mass for ANY string from the
	# fallback anatomy profile, so a bare mass guard would hand a silent
	# handful of meat to a typo. Ask whether the world knows the animal.
	if not CreatureMass.knows(species):
		return []
	var mass := CreatureMass.mass_kg_for(species)
	if mass <= 0.0:
		return []
	var result: Array = []
	if mass >= MIN_HIDE_MASS_KG:
		result.append(_stack("hide", Butchering.HIDE_COUNT))
	if CreatureInfo.PREDATOR_SPECIES.get(species, false):
		result.append(_stack("fang", 1))
	result.append(_stack("meat", meat_for(species)))
	return result


## How many meals an animal is worth. NOT a second opinion about it: the
## exact cut `Butchering` hands a player who butchers that same carcass
## (test_the_meat_count_is_butcherings_own), so the drop a kill promises and
## the meat a knife actually takes off it cannot drift apart. 0 for anything
## this world does not spawn, which is a different answer from "the flat
## count" and the reason this is not simply Butchering.base_meat_for.
func meat_for(species: String) -> int:
	if not CreatureMass.knows(species):
		return 0
	return Butchering.base_meat_for(species)


func _stack(item_id: String, count: int) -> ItemStack:
	return ItemStack.new(_make_item(item_id), count)


func _make_item(item_id: String) -> Item:
	var spec: Array = _ITEMS[item_id]
	return Item.new(item_id, spec[0], spec[1], spec[2])
