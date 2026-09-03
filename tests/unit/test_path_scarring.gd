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


# -- what a path is FOR (docs/concept/infrastructure.md) ---------------------


## Paths have worn in and rendered as earth since PathScarring was written,
## and they did nothing: walking the same line every day changed the picture
## and not the walk. A trodden path is faster than rough ground -- that is why
## real desire paths form at all -- and without the benefit the loop is open at
## both ends: habit makes a path, and the path makes nothing.
func test_untouched_ground_gives_no_advantage():
	assert_eq(PathScarring.speed_multiplier(0.0), 1.0)


func test_a_worn_path_is_faster_than_rough_ground():
	assert_gt(PathScarring.speed_multiplier(PathScarring.WORN_THRESHOLD), 1.0)


## Continuous rather than a switch at the threshold: real ground compacts
## progressively under repeated use, so a half-worn track already helps a
## little. That is also what makes the loop reinforce smoothly instead of
## paying out all at once.
func test_the_advantage_grows_with_use():
	assert_gt(
		PathScarring.speed_multiplier(PathScarring.WORN_THRESHOLD * 0.8),
		PathScarring.speed_multiplier(PathScarring.WORN_THRESHOLD * 0.3)
	)


## A path is a real convenience, not a highway: bracketed from both sides so
## neither edge can drift into "pointless" or "the only way to travel".
func test_the_advantage_is_worth_having_and_not_absurd():
	assert_between(PathScarring.speed_multiplier(PathScarring.MAX_WEAR), 1.05, 1.5)


## Wear is capped, so the multiplier is too -- walking one tile forever must
## not compound into a slipstream.
func test_the_advantage_stops_climbing_once_the_ground_is_fully_compacted():
	assert_eq(
		PathScarring.speed_multiplier(PathScarring.MAX_WEAR),
		PathScarring.speed_multiplier(PathScarring.MAX_WEAR * 10.0)
	)


func test_a_path_never_slows_you():
	for wear in [0.0, 0.1, 0.5, 1.0, 1.5, 99.0]:
		assert_gte(PathScarring.speed_multiplier(wear), 1.0)


## And it really is the SAME wear the renderer reads, not a parallel number:
## a tile the world has drawn as a path is a tile that carries the advantage.
func test_the_tile_the_world_drew_as_a_path_is_the_one_that_is_faster():
	var scarring := PathScarring.new()
	var tile := Vector2i(3, 4)
	while not scarring.is_worn(tile):
		scarring.step_on(tile)
	assert_gt(PathScarring.speed_multiplier(scarring.wear_at(tile)), 1.0)


# -- the trail tier: sustained, heavier use of an already-worn path --------
#
# docs/concept/infrastructure.md's own "path -> trail -> road" escalation:
# "Trail -- sustained, heavier use of an already-worn path over a longer
# window." Found missing by playing: a path re-textures once at
# WORN_THRESHOLD and then NOTHING further is perceptible, however much more
# it is walked -- the wear number keeps climbing underneath (pinned above,
# test_wear_is_capped_at_max_wear), but nothing distinguishes a path crossed
# once from one walked to the ground. Trail is that second, real tier: it
# reaches the existing ceiling (MAX_WEAR) rather than inventing a new one,
# so "trail" means "as compacted as this ground can ever get."

func test_trail_threshold_is_the_max_wear_itself():
	# Not a separately-chosen number: MAX_WEAR is already "as compacted as
	# ground gets" (test_wear_is_capped_at_max_wear), so a second, higher
	# threshold would either be unreachable (above MAX_WEAR) or redundant
	# with the existing ceiling. Trail IS that ceiling, seen as a tier.
	assert_eq(PathScarring.TRAIL_THRESHOLD, PathScarring.MAX_WEAR)


func test_fresh_tile_is_not_a_trail():
	assert_false(scarring.is_trail(Vector2i(3, 4)))


## A tile that is merely WORN (crossed the first threshold) is not yet a
## trail -- the two tiers have to be genuinely distinguishable, not the same
## gate under two names.
func test_a_merely_worn_tile_is_not_yet_a_trail():
	var tile := Vector2i(1, 1)
	var steps_to_worn := int(ceil(PathScarring.WORN_THRESHOLD / PathScarring.WEAR_PER_STEP))
	for i in steps_to_worn:
		scarring.step_on(tile)
	assert_true(scarring.is_worn(tile), "precondition: the tile is worn")
	assert_false(scarring.is_trail(tile), "worn once is not yet a trail")


func test_a_tile_walked_to_the_ceiling_is_a_trail():
	var tile := Vector2i(2, 2)
	for i in 1000:
		scarring.step_on(tile)
	assert_true(scarring.is_trail(tile))


## Trail tiles are also worn tiles -- a strictly deeper tier of the same
## thing, not a separate, disjoint state.
func test_every_trail_tile_is_also_worn():
	var tile := Vector2i(4, 4)
	for i in 1000:
		scarring.step_on(tile)
	assert_true(scarring.is_worn(tile))
	assert_true(scarring.is_trail(tile))


func test_trail_tiles_returns_only_tiles_at_the_ceiling():
	var trodden := Vector2i(0, 0)
	var trailed := Vector2i(9, 9)
	var steps_to_worn := int(ceil(PathScarring.WORN_THRESHOLD / PathScarring.WEAR_PER_STEP))
	for i in steps_to_worn:
		scarring.step_on(trodden)
	for i in 1000:
		scarring.step_on(trailed)
	var trails: Array = scarring.trail_tiles()
	assert_true(trails.has(trailed))
	assert_false(trails.has(trodden))


## Decaying back down below the ceiling demotes a trail back to an ordinary
## worn path -- the tiers track the SAME live wear number in both
## directions, not a one-way ratchet.
func test_decaying_below_the_ceiling_demotes_a_trail_to_an_ordinary_path():
	var tile := Vector2i(6, 6)
	for i in 1000:
		scarring.step_on(tile)
	assert_true(scarring.is_trail(tile), "precondition: reached trail")
	scarring.advance(1.0)
	assert_true(scarring.is_worn(tile), "still worn -- one second of decay is not a full recovery")
	assert_false(scarring.is_trail(tile), "no longer compacted enough to be a trail")
