extends RefCounted
## Pure logic for herbivores eating dropped ground food (fruit/nuts).

const EAT_RADIUS := 12.0

## Index of the nearest food within eat_radius of creature_position, -1 if none.
static func nearest_food_index(creature_position: Vector2, food_positions: Array, eat_radius: float) -> int:
	var best_index := -1
	var best_distance := INF
	for i in food_positions.size():
		var distance: float = creature_position.distance_to(food_positions[i])
		if distance <= eat_radius and distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


## -- Active player food buffs (docs/concept/cooking.md's "Buff slots: fixed,
## and typed by category") --
## A player has a fixed number of active food-buff slots, one per dish
## category (sustenance/resistance/combat/...), rather than an unbounded
## stack of same-type buffs. Eating a dish occupies its category's slot,
## replacing whatever was there; a dish of a different category gets its own
## slot. Entries are {"dish_id", "category", "buff", "time_remaining"}.
## Callers own the array; every function returns a NEW array, never mutating
## the one passed in (same convention as debuff_stack.gd).

const _EMPTY_FOOD_BUFF := {"dish_id": "", "category": "", "buff": "", "time_remaining": 0.0}


## Applies dish (as returned by CookingRecipeBook.cook) to active: replaces
## whichever entry already occupies dish's category, or appends a fresh
## entry if that category's slot is empty.
static func apply_food_buff(active: Array, dish: Dictionary) -> Array:
	var result: Array = active.duplicate()
	for i in result.size():
		if result[i]["category"] == dish["category"]:
			result.remove_at(i)
			break
	result.append({
		"dish_id": dish["dish_id"],
		"category": dish["category"],
		"buff": dish["buff"],
		"time_remaining": dish["buff_duration"],
	})
	return result


## The active entry occupying category, or the empty sentinel if none.
static func buff_in_category(active: Array, category: String) -> Dictionary:
	for entry in active:
		if entry["category"] == category:
			return entry
	return _EMPTY_FOOD_BUFF


## Reduces time_remaining on every entry by delta, dropping any entry whose
## time_remaining falls to 0-or-below (expired food buffs disappear).
static func advance_food_buffs(active: Array, delta: float) -> Array:
	var result: Array = []
	for entry in active:
		var remaining: float = float(entry["time_remaining"]) - delta
		if remaining > 0.0:
			var updated: Dictionary = entry.duplicate()
			updated["time_remaining"] = remaining
			result.append(updated)
	return result
