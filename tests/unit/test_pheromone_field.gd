extends GutTest

## A real ant colony's trail pheromone -- see docs/concept/soil_fauna.md
## "Pheromone trails: recruitment to a known-good source". Deliberately NOT
## a reuse of ScentField: a trail has to persist and fade after the ant
## that laid it moves on (ScentField recomputes fresh from whichever
## flowers are CURRENTLY alive, with nothing to persist), so this is a
## real stateful, decaying store, borrowing ScentField's falloff/gradient-
## sampling MATH, not its statelessness.

const PheromoneField = preload("res://src/world/pheromone_field.gd")

const TILE_SIZE := 16.0

var field: PheromoneField


func before_each():
	field = PheromoneField.new()


# -- falloff: the same squared-taper shape ScentField.falloff uses --------

func test_falloff_is_full_strength_at_zero_distance():
	assert_almost_eq(PheromoneField.falloff(0.0), 1.0, 0.001)


func test_falloff_is_zero_at_and_beyond_the_radius():
	assert_eq(PheromoneField.falloff(PheromoneField.RADIUS_TILES), 0.0)
	assert_eq(PheromoneField.falloff(PheromoneField.RADIUS_TILES * 2.0), 0.0)


func test_falloff_decreases_monotonically_with_distance():
	var previous := PheromoneField.falloff(0.0)
	for i in 10:
		var distance := float(i + 1) * (PheromoneField.RADIUS_TILES / 10.0)
		var current := PheromoneField.falloff(distance)
		assert_lte(current, previous, "falloff should never increase with distance")
		previous = current


# -- concentration: a fresh deposit read at its own location ---------------

func test_field_starts_empty():
	assert_true(field.is_empty())
	assert_eq(field.concentration_at(Vector2(100, 100), TILE_SIZE), 0.0)


func test_a_fresh_deposit_reads_at_roughly_full_strength_at_its_own_tile_center():
	var tile := Vector2i(5, 5)
	field.deposit(tile, PheromoneField.DEPOSIT_AMOUNT)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	assert_almost_eq(
		field.concentration_at(tile_center, TILE_SIZE), PheromoneField.DEPOSIT_AMOUNT, 0.01
	)
	assert_false(field.is_empty())


func test_concentration_fades_with_distance_from_the_deposit():
	var tile := Vector2i(5, 5)
	field.deposit(tile)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	var near := field.concentration_at(tile_center + Vector2(TILE_SIZE, 0.0), TILE_SIZE)
	var far := field.concentration_at(tile_center + Vector2(TILE_SIZE * 10.0, 0.0), TILE_SIZE)
	assert_gt(near, far)
	assert_eq(far, 0.0, "well beyond RADIUS_TILES, a deposit should contribute nothing")


func test_two_deposits_at_the_same_tile_accumulate():
	var tile := Vector2i(2, 2)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	field.deposit(tile, 1.0)
	var once := field.concentration_at(tile_center, TILE_SIZE)
	field.deposit(tile, 1.0)
	var twice := field.concentration_at(tile_center, TILE_SIZE)
	assert_almost_eq(twice, once * 2.0, 0.01, "a second deposit at the same tile should add, not replace")


# -- decay: real, over elapsed time, eventually pruned ----------------------

func test_decay_halves_concentration_after_one_half_life():
	var tile := Vector2i(1, 1)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	field.deposit(tile, 1.0)
	var before := field.concentration_at(tile_center, TILE_SIZE)
	field.decay(PheromoneField.HALF_LIFE_SECONDS)
	var after := field.concentration_at(tile_center, TILE_SIZE)
	assert_almost_eq(after, before * 0.5, 0.01)


func test_decay_with_zero_elapsed_time_changes_nothing():
	var tile := Vector2i(1, 1)
	field.deposit(tile, 1.0)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	var before := field.concentration_at(tile_center, TILE_SIZE)
	field.decay(0.0)
	assert_eq(field.concentration_at(tile_center, TILE_SIZE), before)


func test_decay_eventually_prunes_a_fully_faded_deposit():
	field.deposit(Vector2i(3, 3), 1.0)
	for i in 50:  # comfortably many half-lives
		field.decay(PheromoneField.HALF_LIFE_SECONDS)
	assert_true(field.is_empty(), "a long-faded deposit should be pruned, not lingering at a near-zero amount")


# -- gradient: mirrors ScentField.gradient_direction's own sampling shape --

func test_gradient_direction_is_zero_with_no_deposits():
	assert_eq(field.gradient_direction(Vector2(50, 50), TILE_SIZE), Vector2.ZERO)


func test_gradient_direction_points_roughly_toward_a_nearby_deposit():
	var tile := Vector2i(10, 0)
	field.deposit(tile, 1.0)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	# Sample from due west of the deposit -- the gradient should point east.
	var sample_point := tile_center - Vector2(TILE_SIZE * 2.0, 0.0)
	var direction := field.gradient_direction(sample_point, TILE_SIZE)
	assert_gt(direction.x, 0.5, "the gradient should point toward the deposit, roughly east")

# best_candidate_index (an omniscient "score every known candidate from a
# stationary point and pick the best one" primitive) was removed here
# (see docs/concept/soil_fauna.md "Scouting: real search, not omniscient
# dispatch" -- reported live: "no omniscience please"). gradient_direction
# above is what real recruitment reads instead now: a LOCAL concentration
# sensed exactly where a scout currently stands, not a list of known
# destinations compared from afar. See AntScoutWander for how that local
# gradient biases a scout's own wander heading.

# -- deposit_trail: direction + amount, so a later ant knows which way ------
# is OUT without inferring it from a noisy concentration gradient (reported
# live: "he encodes direction and amount in the pheromones so other ants
# don't follow it back into the mound on the way back from a discovery").
# deposit(tile, amount) above still works completely unchanged -- it is
# deposit_trail(tile, Vector2.ZERO, amount) under the hood, same storage,
# same concentration_at/gradient_direction math, just no direction encoded
# (nothing before this needed one).

func test_deposit_trail_is_read_back_by_nearest_trail_near():
	var tile := Vector2i(4, 0)
	var direction := Vector2(1, 0)
	field.deposit_trail(tile, direction, 3.0)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	var found := field.nearest_trail_near(tile_center, TILE_SIZE)
	assert_eq(found.get("direction"), direction)
	assert_eq(found.get("amount"), 3.0)


func test_nearest_trail_near_finds_nothing_beyond_radius_tiles():
	field.deposit_trail(Vector2i(0, 0), Vector2(1, 0), 3.0)
	var far_point := Vector2(PheromoneField.RADIUS_TILES * TILE_SIZE * 10.0, 0.0)
	assert_eq(field.nearest_trail_near(far_point, TILE_SIZE), {})


func test_nearest_trail_near_ignores_a_plain_scalar_deposit_with_no_direction():
	# deposit() (used by nothing but its own tests any more, kept for full
	# backward compatibility) never sets a real direction -- there is
	# nothing directional to follow there, so a trail-follower must not
	# mistake it for a real trail.
	var tile := Vector2i(0, 0)
	field.deposit(tile, 1.0)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	assert_eq(field.nearest_trail_near(tile_center, TILE_SIZE), {})


func test_nearest_trail_near_picks_the_closest_of_several():
	field.deposit_trail(Vector2i(10, 0), Vector2(1, 0), 3.0)
	field.deposit_trail(Vector2i(1, 0), Vector2(1, 0), 5.0)
	var origin := Vector2(0, 0)
	var found := field.nearest_trail_near(origin, TILE_SIZE)
	assert_eq(found.get("amount"), 5.0, "should read the CLOSER deposit, not an arbitrary/farther one")


# -- has_active_trail: whether resolvers are worth dispatching at all -------

func test_has_active_trail_is_false_when_empty():
	assert_false(field.has_active_trail())


func test_has_active_trail_is_true_after_a_real_trail_deposit():
	field.deposit_trail(Vector2i(2, 2), Vector2(0, 1), 3.0)
	assert_true(field.has_active_trail())


func test_has_active_trail_is_false_for_a_plain_scalar_deposit_with_no_direction():
	field.deposit(Vector2i(2, 2), 1.0)
	assert_false(field.has_active_trail(), "a directionless deposit is not a trail a resolver could follow")


# -- invalidate_near: masking a spent trail with a real stop signal ---------
# (reported live: "the last ant which takes home the last piece or one that
# encounters it empty invalidates the pheromone trail by masking the
# existing pheromone trail with complete marker")

func test_invalidate_near_marks_a_nearby_trail_exhausted():
	var tile := Vector2i(5, 5)
	field.deposit_trail(tile, Vector2(1, 0), 3.0)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	field.invalidate_near(tile_center, PheromoneField.RADIUS_TILES, TILE_SIZE)
	assert_false(field.has_active_trail(), "an invalidated trail should no longer be worth resolving")
	assert_eq(field.nearest_trail_near(tile_center, TILE_SIZE), {}, "a resolver must not be sent to a spent trail")


func test_invalidate_near_does_not_touch_a_trail_outside_the_radius():
	var far_tile := Vector2i(1000, 1000)
	field.deposit_trail(far_tile, Vector2(1, 0), 3.0)
	field.invalidate_near(Vector2.ZERO, PheromoneField.RADIUS_TILES, TILE_SIZE)
	assert_true(field.has_active_trail(), "a trail far outside the invalidated area should be untouched")


func test_an_exhausted_deposit_no_longer_contributes_concentration():
	var tile := Vector2i(6, 6)
	field.deposit_trail(tile, Vector2(1, 0), 3.0)
	var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	var before := field.concentration_at(tile_center, TILE_SIZE)
	field.invalidate_near(tile_center, PheromoneField.RADIUS_TILES, TILE_SIZE)
	assert_gt(before, 0.0, "precondition: the trail was sensed before invalidation")
	assert_eq(
		field.concentration_at(tile_center, TILE_SIZE), 0.0,
		"an exhausted deposit must stop pulling a scout's own ambient wander toward a known-empty spot"
	)
