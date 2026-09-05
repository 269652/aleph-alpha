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


# -- best_candidate_index: nearest by default, recruitment when marked -----

func test_best_candidate_index_picks_the_nearest_with_no_pheromone_field():
	var origin := Vector2(0, 0)
	var candidates := [
		{"position": Vector2(100, 0)},
		{"position": Vector2(20, 0)},
		{"position": Vector2(50, 0)},
	]
	assert_eq(PheromoneField.best_candidate_index(origin, candidates, null, TILE_SIZE), 1)


func test_best_candidate_index_picks_the_nearest_with_an_empty_pheromone_field():
	var origin := Vector2(0, 0)
	var candidates := [{"position": Vector2(100, 0)}, {"position": Vector2(20, 0)}]
	assert_eq(PheromoneField.best_candidate_index(origin, candidates, field, TILE_SIZE), 1)


## Real recruitment: a colony that has successfully foraged at a spot
## before should be willing to send the next forager a little further to
## revisit it, over an equally-plausible but never-visited closer spot.
##
## Both candidates are placed at the SAME y as the deposit's own tile
## centre (not y=0): a tile's centre sits at (tile + 0.5) * tile_size in
## BOTH axes, so anchoring only x and leaving y=0 would silently introduce
## an unaccounted diagonal offset into every distance in this test.
func test_best_candidate_index_prefers_a_marked_candidate_over_a_slightly_closer_unmarked_one():
	var origin := Vector2(0, 0)
	var marked_tile := Vector2i(7, 0)
	var marked_position := (Vector2(marked_tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	var closer_unmarked_position := marked_position - Vector2(20.0, 0.0)
	field.deposit(marked_tile, PheromoneField.DEPOSIT_AMOUNT)
	var candidates := [
		{"position": closer_unmarked_position},
		{"position": marked_position},
	]
	assert_eq(
		PheromoneField.best_candidate_index(origin, candidates, field, TILE_SIZE), 1,
		"a marked source only slightly further away should win over a closer, never-visited one"
	)


func test_best_candidate_index_does_not_let_pheromone_override_a_much_closer_candidate():
	var origin := Vector2(0, 0)
	var marked_tile := Vector2i(31, 0)
	var marked_far_position := (Vector2(marked_tile) + Vector2(0.5, 0.5)) * TILE_SIZE
	var much_closer_position := Vector2(20.0, marked_far_position.y)
	field.deposit(marked_tile, PheromoneField.DEPOSIT_AMOUNT)
	var candidates := [
		{"position": much_closer_position},
		{"position": marked_far_position},
	]
	assert_eq(
		PheromoneField.best_candidate_index(origin, candidates, field, TILE_SIZE), 0,
		"pheromone preference should not be strong enough to send a forager wildly out of its way"
	)
