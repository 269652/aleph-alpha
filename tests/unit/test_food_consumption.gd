extends GutTest

const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")

func test_eat_radius_constant() -> void:
	assert_eq(FoodConsumption.EAT_RADIUS, 12.0)

func test_returns_minus_one_for_empty_array() -> void:
	assert_eq(FoodConsumption.nearest_food_index(Vector2(10, 10), [], 12.0), -1)

func test_returns_minus_one_when_all_food_out_of_radius() -> void:
	var foods := [Vector2(100, 100), Vector2(-50, 0)]
	assert_eq(FoodConsumption.nearest_food_index(Vector2.ZERO, foods, 12.0), -1)

func test_returns_index_of_food_within_radius() -> void:
	var foods := [Vector2(100, 100), Vector2(5, 0)]
	assert_eq(FoodConsumption.nearest_food_index(Vector2.ZERO, foods, 12.0), 1)

func test_returns_nearest_when_multiple_within_radius() -> void:
	var foods := [Vector2(10, 0), Vector2(3, 0), Vector2(8, 0)]
	assert_eq(FoodConsumption.nearest_food_index(Vector2.ZERO, foods, 12.0), 1)

func test_food_exactly_at_radius_is_eaten() -> void:
	var foods := [Vector2(12, 0)]
	assert_eq(FoodConsumption.nearest_food_index(Vector2.ZERO, foods, 12.0), 0)

func test_food_just_outside_radius_not_eaten() -> void:
	var foods := [Vector2(12.001, 0)]
	assert_eq(FoodConsumption.nearest_food_index(Vector2.ZERO, foods, 12.0), -1)

func test_uses_creature_position_offset() -> void:
	var foods := [Vector2(205, 300), Vector2(0, 0)]
	assert_eq(FoodConsumption.nearest_food_index(Vector2(200, 300), foods, 12.0), 0)


## -- Active food-buff slots: fixed, one per category (docs/concept/cooking.md
## "Buff slots: fixed, and typed by category") -- eating a dish occupies its
## category's slot, replacing whatever was there; different categories each
## get their own slot.

const _STEW := {"dish_id": "hearty_stew", "category": "sustenance", "buff": "stamina_regen", "buff_duration": 300.0}
const _FISH := {"dish_id": "herbed_fish", "category": "sustenance", "buff": "health_regen", "buff_duration": 240.0}
const _NUT := {"dish_id": "roasted_nut_meat", "category": "combat", "buff": "damage_boost", "buff_duration": 180.0}


func test_apply_food_buff_adds_entry_to_empty_slots() -> void:
	var active := FoodConsumption.apply_food_buff([], _STEW)
	assert_eq(active.size(), 1)
	assert_eq(active[0].dish_id, "hearty_stew")
	assert_eq(active[0].category, "sustenance")
	assert_eq(active[0].buff, "stamina_regen")
	assert_eq(active[0].time_remaining, 300.0)


func test_apply_food_buff_different_categories_both_occupy_their_own_slot() -> void:
	var active := FoodConsumption.apply_food_buff([], _STEW)
	active = FoodConsumption.apply_food_buff(active, _NUT)
	assert_eq(active.size(), 2)


func test_apply_food_buff_same_category_replaces_instead_of_stacking() -> void:
	var active := FoodConsumption.apply_food_buff([], _STEW)
	active = FoodConsumption.apply_food_buff(active, _FISH)
	assert_eq(active.size(), 1)
	assert_eq(active[0].dish_id, "herbed_fish")
	assert_eq(active[0].buff, "health_regen")
	assert_eq(active[0].time_remaining, 240.0)


func test_apply_food_buff_does_not_mutate_callers_original_array() -> void:
	var original := FoodConsumption.apply_food_buff([], _STEW)
	var updated := FoodConsumption.apply_food_buff(original, _FISH)
	assert_eq(original.size(), 1)
	assert_eq(original[0].dish_id, "hearty_stew")
	assert_eq(updated.size(), 1)
	assert_eq(updated[0].dish_id, "herbed_fish")


func test_buff_in_category_returns_the_active_entry() -> void:
	var active := FoodConsumption.apply_food_buff([], _STEW)
	assert_eq(FoodConsumption.buff_in_category(active, "sustenance").dish_id, "hearty_stew")


func test_buff_in_category_returns_empty_sentinel_when_absent() -> void:
	var found := FoodConsumption.buff_in_category([], "combat")
	assert_eq(found.dish_id, "")
	assert_eq(found.category, "")
	assert_eq(found.buff, "")
	assert_eq(found.time_remaining, 0.0)


func test_advance_food_buffs_reduces_time_remaining_by_delta() -> void:
	var active := FoodConsumption.apply_food_buff([], _STEW)
	active = FoodConsumption.advance_food_buffs(active, 100.0)
	assert_eq(active[0].time_remaining, 200.0)


func test_advance_food_buffs_drops_expired_entries() -> void:
	var active := FoodConsumption.apply_food_buff([], _STEW)
	active = FoodConsumption.advance_food_buffs(active, 300.0)
	assert_eq(active.size(), 0)


func test_advance_food_buffs_keeps_unexpired_entries_only() -> void:
	var active := FoodConsumption.apply_food_buff([], _STEW)
	active = FoodConsumption.apply_food_buff(active, _NUT)
	active = FoodConsumption.advance_food_buffs(active, 200.0)
	assert_eq(active.size(), 1)
	assert_eq(active[0].dish_id, "hearty_stew")


func test_advance_food_buffs_does_not_mutate_callers_original_array() -> void:
	var original := FoodConsumption.apply_food_buff([], _STEW)
	var advanced := FoodConsumption.advance_food_buffs(original, 100.0)
	assert_eq(original[0].time_remaining, 300.0)
	assert_eq(advanced[0].time_remaining, 200.0)
