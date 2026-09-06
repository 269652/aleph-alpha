extends RefCounted

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


## `food_id`'s real composition, or an empty dict for anything unmodeled --
## the unmodeled-material fallback shape this project uses throughout
## (MaterialProperties.property_value, ItemDurability.max_wear).
func composition_for(food_id: String) -> Dictionary:
	return COMPOSITION.get(food_id, {})
