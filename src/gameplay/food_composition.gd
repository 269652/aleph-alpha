extends RefCounted

const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")

## The actual "Material DSL" data (see docs/concept/material_dsl.md):
## per-food nutrient composition as plain fractions of substance. No control
## flow to a composition record, so -- mirroring ethogram.gd's own
## data-not-program convention -- this is a flat dictionary, not a parsed
## grammar.
##
## Water and sugar fractions are real (USDA-ballpark) figures for the raw
## fruit. "vitamins" is a deliberately coarse gameplay abstraction, not
## literal vitamin-C mass (real vitamin C content is under 0.01% by mass --
## far too small a number to be a legible gameplay lever): it stands in for
## the combined micronutrient/mineral/fiber value of a whole fruit, scaled
## to be meaningful. Named here rather than presented as measured fact.
##
## Only apple and cherry are modeled -- soft, shell-less fruit (see the
## concept doc's Status list for why nuts, with their own separate
## crack-open mechanic, are not here yet). Every other food_id returns an
## empty composition and keeps today's flat eating behaviour untouched,
## exactly item_durability.md's "only a modeled material gets the real
## behaviour" rule.
const COMPOSITION: Dictionary = {
	"apple": {"water": 0.86, "sugar": 0.10, "vitamins": 0.02},
	"cherry": {"water": 0.82, "sugar": 0.13, "vitamins": 0.025},
}

## One shared, real composition for every `MushroomSpecies.IDS` entry (see
## docs/concept/mushrooms.md "Animals can find and eat wild mushrooms") --
## real fungi don't differ enough in gross macro composition, at this
## level of abstraction, to warrant six duplicated literal entries. Real
## mushrooms are famously mostly water, with negligible sugar but a real,
## well-documented B-vitamin/mineral density -- a genuinely HIGHER
## vitamins fraction than either fruit above, not just a filled-in guess.
## `MushroomSpecies.is_toxic` is deliberately never consulted here: a boar
## eats a toxic species exactly like any other (see that doc's own
## reasoning).
const _MUSHROOM_COMPOSITION: Dictionary = {"water": 0.90, "sugar": 0.02, "vitamins": 0.03}


## `food_id`'s real composition, or an empty dict for anything unmodeled --
## the unmodeled-material fallback shape this project uses throughout
## (MaterialProperties.property_value, ItemDurability.max_wear). Falls
## back to the shared mushroom vector for any MushroomSpecies id not
## already in the explicit table above -- including a "_bitten" variant
## (see MushroomBiting.base_item_id_for), so a partially-eaten mushroom
## still resolves a real composition instead of silently skipping the
## whole nutrient pipeline (see docs/concept/metabolism.md's "the two
## named mushroom gaps" -- a bitten id is not itself a MushroomSpecies id,
## so this used to fall straight through to "unmodeled" for every
## partially-eaten mushroom regardless of mass).
func composition_for(food_id: String) -> Dictionary:
	if COMPOSITION.has(food_id):
		return COMPOSITION[food_id]
	if MushroomSpecies.IDS.has(MushroomBiting.base_item_id_for(food_id)):
		return _MUSHROOM_COMPOSITION
	return {}
