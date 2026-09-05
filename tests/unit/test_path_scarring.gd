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


# -- the trail tier (docs/concept/infrastructure.md's "path -> trail -> road") --
#
# Reported live: "path scarring only is computed once and walking back and
# forth doesn't deepen it." wear_at already climbed all the way to MAX_WEAR
# on repeated step_on calls (test_wear_is_capped_at_max_wear, above) -- the
# gap was legibility: nothing distinguished "crossed once" from "walked to
# the ground" once WORN_THRESHOLD was reached. TRAIL_THRESHOLD is
# deliberately not a new number -- it IS MAX_WEAR, the ceiling this module
# already enforces, read as a tier rather than picked again above or below.


func test_trail_threshold_is_the_existing_wear_ceiling() -> void:
	assert_eq(PathScarring.TRAIL_THRESHOLD, PathScarring.MAX_WEAR)


func test_fresh_tile_is_not_a_trail() -> void:
	assert_false(scarring.is_trail(Vector2i(3, 4)))


func test_a_tile_worn_to_the_ceiling_is_a_trail() -> void:
	var tile := Vector2i(1, 1)
	for i in range(1000):
		scarring.step_on(tile)
	assert_true(scarring.is_trail(tile))


func test_a_tile_merely_worn_is_not_yet_a_trail() -> void:
	var tile := Vector2i(2, 2)
	var steps_needed := int(ceil(PathScarring.WORN_THRESHOLD / PathScarring.WEAR_PER_STEP))
	for i in range(steps_needed):
		scarring.step_on(tile)
	assert_true(scarring.is_worn(tile), "should already be a worn path")
	assert_false(scarring.is_trail(tile), "should not yet be worn all the way to the trail ceiling")


func test_every_trail_is_also_worn() -> void:
	var tile := Vector2i(5, 5)
	for i in range(1000):
		scarring.step_on(tile)
	assert_true(scarring.is_trail(tile))
	assert_true(scarring.is_worn(tile), "a trail is a strictly deeper tier of worn, not a separate state")


func test_trail_tiles_returns_only_tiles_worn_to_the_ceiling() -> void:
	var trail := Vector2i(1, 0)
	var merely_worn := Vector2i(2, 0)
	for i in range(1000):
		scarring.step_on(trail)
	for i in range(int(ceil(PathScarring.WORN_THRESHOLD / PathScarring.WEAR_PER_STEP))):
		scarring.step_on(merely_worn)
	var result: Array = scarring.trail_tiles()
	assert_eq(result.size(), 1)
	assert_eq(result[0], trail)


func test_a_trail_tapers_back_to_merely_worn_before_it_fully_recovers() -> void:
	var tile := Vector2i(7, 7)
	for i in range(1000):
		scarring.step_on(tile)
	assert_true(scarring.is_trail(tile))
	# Decay by HALF the gap between the two thresholds -- comfortably past
	# the trail ceiling, comfortably short of dropping below "merely worn"
	# too, unlike decaying the FULL gap (which would land exactly back on
	# WORN_THRESHOLD, one epsilon away from failing either way).
	var half_gap := (PathScarring.MAX_WEAR - PathScarring.WORN_THRESHOLD) * 0.5
	scarring.advance(half_gap / PathScarring.DECAY_PER_SECOND)
	assert_false(scarring.is_trail(tile), "should have tapered off the trail ceiling")
	assert_true(scarring.is_worn(tile), "should still be an ordinary worn path")
