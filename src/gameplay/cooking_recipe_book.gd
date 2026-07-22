extends RefCounted

## Fixed recipe table for the cooking system: sorted ingredient id sets ->
## dish (display name + buff). Deterministic, no RNG -- the same ingredients
## always cook the same dish regardless of the order they were combined in.

const _EMPTY_DISH := {"dish_id": "", "display_name": "", "buff": "", "buff_duration": 0.0, "category": ""}

## joined-sorted-ingredient-ids -> dish. "category" is the fixed food-buff
## slot (see docs/concept/cooking.md's "Buff slots: fixed, and typed by
## category") a dish's buff occupies -- eating another dish of the same
## category replaces the active buff in that slot rather than stacking.
const _RECIPES := {
	"fruit_meat": {"dish_id": "hearty_stew", "display_name": "Hearty Stew", "buff": "stamina_regen", "buff_duration": 300.0, "category": "sustenance"},
	"meat_nut": {"dish_id": "roasted_nut_meat", "display_name": "Roasted Nut Meat", "buff": "damage_boost", "buff_duration": 180.0, "category": "combat"},
	"fish_herb": {"dish_id": "herbed_fish", "display_name": "Herbed Fish", "buff": "health_regen", "buff_duration": 240.0, "category": "sustenance"},
	"berry_water": {"dish_id": "berry_cooler", "display_name": "Berry Cooler", "buff": "heat_resistance", "buff_duration": 200.0, "category": "resistance"},
}


## Sorts a COPY of ingredient_ids so combination order never matters, then
## looks up the matching dish. Returns the empty sentinel (not null) so
## callers never need a null check.
func cook(ingredient_ids: Array) -> Dictionary:
	var sorted_ids := ingredient_ids.duplicate()
	sorted_ids.sort()
	var key := "_".join(sorted_ids)
	return _RECIPES.get(key, _EMPTY_DISH)


func known_dish_ids() -> Array:
	var ids: Array = []
	for recipe in _RECIPES.values():
		ids.append(recipe.dish_id)
	return ids
