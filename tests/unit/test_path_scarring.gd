extends GutTest

const PathScarring := preload("res://src/world/path_scarring.gd")

var scarring


func before_each() -> void:
	scarring = PathScarring.new()


func test_constants_are_sane() -> void:
	assert_gt(PathScarring.WEAR_PER_STEP, 0.0, "wear per step positive")
	assert_gt(PathScarring.WORN_THRESHOLD, PathScarring.WEAR_PER_STEP, "threshold requires multiple steps")
	assert_gt(PathScarring.DECAY_PER_SECOND, 0.0, "decay positive")
	assert_lt(PathScarring.DECAY_PER_SECOND, PathScarring.WEAR_PER_STEP, "decay slower than a step")
	assert_lte(PathScarring.MAX_WEAR, 2.0 * PathScarring.WORN_THRESHOLD, "max wear bounded")
	assert_gte(PathScarring.MAX_WEAR, PathScarring.WORN_THRESHOLD, "max wear reachable")


func test_fresh_tile_has_no_wear() -> void:
	assert_eq(scarring.wear_at(Vector2i(3, 4)), 0.0)
	assert_false(scarring.is_worn(Vector2i(3, 4)))


func test_step_on_accumulates_wear() -> void:
	scarring.step_on(Vector2i(1, 1))
	scarring.step_on(Vector2i(1, 1))
	assert_almost_eq(scarring.wear_at(Vector2i(1, 1)), 2.0 * PathScarring.WEAR_PER_STEP, 0.0001)


func test_tile_becomes_worn_after_enough_steps() -> void:
	var tile := Vector2i(0, 0)
	var steps_needed := int(ceil(PathScarring.WORN_THRESHOLD / PathScarring.WEAR_PER_STEP))
	for i in range(steps_needed - 1):
		scarring.step_on(tile)
	assert_false(scarring.is_worn(tile), "not worn one step early")
	scarring.step_on(tile)
	assert_true(scarring.is_worn(tile), "worn after enough steps")


func test_wear_is_capped_at_max_wear() -> void:
	var tile := Vector2i(5, 5)
	for i in range(1000):
		scarring.step_on(tile)
	assert_almost_eq(scarring.wear_at(tile), PathScarring.MAX_WEAR, 0.0001)


func test_advance_decays_wear() -> void:
	var tile := Vector2i(2, 2)
	scarring.step_on(tile)
	var before: float = scarring.wear_at(tile)
	scarring.advance(1.0)
	assert_almost_eq(scarring.wear_at(tile), before - PathScarring.DECAY_PER_SECOND, 0.0001)


func test_worn_tile_recovers_after_enough_time() -> void:
	var tile := Vector2i(7, 7)
	for i in range(100):
		scarring.step_on(tile)
	assert_true(scarring.is_worn(tile))
	var seconds_to_recover := PathScarring.MAX_WEAR / PathScarring.DECAY_PER_SECOND
	scarring.advance(seconds_to_recover + 1.0)
	assert_false(scarring.is_worn(tile))
	assert_eq(scarring.wear_at(tile), 0.0)


func test_fully_recovered_tiles_are_dropped() -> void:
	scarring.step_on(Vector2i(9, 9))
	scarring.advance(PathScarring.WEAR_PER_STEP / PathScarring.DECAY_PER_SECOND + 1.0)
	assert_eq(scarring.tracked_tile_count(), 0, "recovered tiles dropped from storage")


func test_worn_tiles_returns_only_tiles_at_or_above_threshold() -> void:
	var worn := Vector2i(1, 0)
	var faint := Vector2i(2, 0)
	for i in range(100):
		scarring.step_on(worn)
	scarring.step_on(faint)
	var result: Array = scarring.worn_tiles(PathScarring.WORN_THRESHOLD)
	assert_eq(result.size(), 1)
	assert_eq(result[0], worn)


func test_worn_tiles_with_custom_threshold() -> void:
	scarring.step_on(Vector2i(4, 4))
	var result: Array = scarring.worn_tiles(PathScarring.WEAR_PER_STEP / 2.0)
	assert_eq(result, [Vector2i(4, 4)])


func test_advance_with_zero_delta_changes_nothing() -> void:
	scarring.step_on(Vector2i(6, 6))
	var before: float = scarring.wear_at(Vector2i(6, 6))
	scarring.advance(0.0)
	assert_eq(scarring.wear_at(Vector2i(6, 6)), before)
