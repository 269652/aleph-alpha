extends GutTest

## Workers trickling out of a mound and back (see docs/concept/soil_fauna.md's
## "What the player sees").
##
## This is AMBIENT ANIMATION, not a second simulation: there is no per-ant
## marker, no ant AI, and the foraging that actually moves seed is still
## `AntColony`'s own colony-level roll. What this owns is where a drawn worker
## is, relative to its own entrance, at a given moment -- pure, so it can be
## tested without a renderer and stores nothing per ant.
##
## Two properties keep the decoration honest rather than a lying simulation,
## and they are the two tests that matter here: a worker never ranges further
## than the colony actually forages, and every trip starts and ends at the
## entrance.

const AntTraffic = preload("res://src/gameplay/ant_traffic.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


# -- the honesty rules -------------------------------------------------------


## The drawn range can never advertise a reach the colony does not have. Pinned
## against `AntColony.FORAGE_RADIUS_TILES` -- the radius
## `_forage_seed_near_mound` really searches -- rather than as a number of
## pixels, so retuning the sim's reach cannot leave the art overstating it.
func test_a_worker_never_ranges_further_than_the_colony_actually_forages():
	var limit := AntColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	for worker in 8:
		for step in 400:
			var offset := AntTraffic.worker_offset(worker * 977 + 5, float(step) * 0.11)
			assert_lte(
				offset.length(),
				limit,
				"a drawn worker reached further than the colony forages"
			)


## Workers come out of the nest and go back into it. One that drifted away
## would read as an escaped bug rather than as a colony.
func test_every_trip_starts_and_ends_at_the_entrance():
	for worker in 6:
		var seed_value := worker * 313 + 11
		for trip in 4:
			var trip_seconds := AntTraffic.trip_seconds_for(seed_value, trip)
			var start := AntTraffic.worker_offset(seed_value, AntTraffic.trip_start_time(seed_value, trip))
			var finish := AntTraffic.worker_offset(
				seed_value, AntTraffic.trip_start_time(seed_value, trip) + trip_seconds
			)
			assert_almost_eq(start.length(), 0.0, 0.6, "a trip did not start at the entrance")
			assert_almost_eq(finish.length(), 0.0, 0.6, "a trip did not end at the entrance")


## ...and it really does go OUT in between, or the workers just sit on the
## entrance and the whole layer is a static dot.
func test_a_worker_actually_leaves_the_nest_mid_trip():
	for worker in 6:
		var seed_value := worker * 313 + 11
		var trip_seconds := AntTraffic.trip_seconds_for(seed_value, 0)
		var midpoint := AntTraffic.worker_offset(
			seed_value, AntTraffic.trip_start_time(seed_value, 0) + trip_seconds * 0.5
		)
		assert_gt(midpoint.length(), 2.0, "a worker never left its entrance")


# -- it has to read as an animal, not a jump ---------------------------------


## Continuous: a worker walks, it does not teleport. A frame-to-frame jump
## would read as a flicker rather than as an ant.
func test_a_worker_never_teleports_between_frames():
	var seed_value := 4242
	var previous := AntTraffic.worker_offset(seed_value, 0.0)
	for step in 2000:
		var now := AntTraffic.worker_offset(seed_value, float(step) * (1.0 / 60.0))
		assert_lt(
			previous.distance_to(now),
			AntTraffic.MAX_STEP_PX_PER_FRAME,
			"a worker jumped between frames at t=%.3f" % (float(step) / 60.0)
		)
		previous = now


## Successive trips head different ways, or a worker paces one groove forever.
func test_successive_trips_take_different_bearings():
	var seed_value := 99
	var bearings := {}
	for trip in AntTraffic.TRIPS_PER_CYCLE:
		var trip_seconds := AntTraffic.trip_seconds_for(seed_value, trip)
		var out := AntTraffic.worker_offset(
			seed_value, AntTraffic.trip_start_time(seed_value, trip) + trip_seconds * 0.5
		)
		bearings[snappedf(out.angle(), 0.1)] = true
	assert_gt(bearings.size(), 4, "a worker walks the same line out every trip")


## Two workers on the same mound must not move as one animal in two places.
func test_two_workers_on_one_mound_are_not_synchronised():
	var together := 0
	for step in 200:
		var elapsed := float(step) * 0.1
		var first := AntTraffic.worker_offset(AntTraffic.worker_seed(77, 0), elapsed)
		var second := AntTraffic.worker_offset(AntTraffic.worker_seed(77, 1), elapsed)
		if first.distance_to(second) < 1.0:
			together += 1
	assert_lt(together, 40, "two workers move as one")


## Deterministic, like everything else in this codebase: the same mound redraws
## the same traffic, so a chunk that unloads and reloads does not resnap its
## ants somewhere else.
func test_the_same_worker_at_the_same_moment_is_in_the_same_place():
	assert_eq(AntTraffic.worker_offset(5, 12.75), AntTraffic.worker_offset(5, 12.75))


func test_two_mounds_do_not_run_the_same_traffic():
	var here := AntTraffic.worker_offset(AntTraffic.worker_seed(1, 0), 3.0)
	var next_door := AntTraffic.worker_offset(AntTraffic.worker_seed(2, 0), 3.0)
	assert_ne(here, next_door)


# -- the roster --------------------------------------------------------------


## A mound draws a few workers, not a swarm: these are 2px dots, and a crowd
## would read as static rather than as traffic.
func test_a_mound_draws_a_handful_of_workers():
	assert_between(AntTraffic.WORKERS_PER_MOUND, 2, 5)


## Trip lengths vary per worker, or the whole nest pulses in unison.
func test_trip_lengths_vary_between_workers():
	var lengths := {}
	for worker in 8:
		lengths[snappedf(AntTraffic.trip_seconds_for(worker * 91 + 3, 0), 0.01)] = true
	assert_gt(lengths.size(), 1)


func test_trip_lengths_stay_sane():
	for worker in 20:
		for trip in 5:
			assert_between(
				AntTraffic.trip_seconds_for(worker * 91 + 3, trip),
				AntTraffic.MIN_TRIP_SECONDS,
				AntTraffic.MAX_TRIP_SECONDS
			)


## Not every trip goes the full distance. Without this a worker's excursions
## all reach exactly the same ring and the nest reads as a mechanism rather
## than as animals -- three ants pacing three fixed radii.
func test_some_trips_are_short_sorties():
	var reaches := []
	# Within ONE cycle: past it trip_start_time wraps to another trip.
	for trip in AntTraffic.TRIPS_PER_CYCLE:
		var seconds := AntTraffic.trip_seconds_for(31, trip)
		var midpoint := AntTraffic.worker_offset(
			31, AntTraffic.trip_start_time(31, trip) + seconds * 0.5
		)
		reaches.append(midpoint.length())
	var shortest: float = reaches.min()
	var longest: float = reaches.max()
	assert_lt(
		shortest,
		longest * 0.8,
		"every trip reaches the same ring"
	)
	# At the midpoint the lateral wander is exactly zero (it completes whole
	# cycles over a trip), so the reach there IS the trip's range fraction --
	# which makes MIN_TRIP_RANGE_FRACTION an exact floor rather than a guess.
	assert_gte(
		shortest,
		AntTraffic.MAX_RANGE_PX * AntTraffic.MIN_TRIP_RANGE_FRACTION - 0.001,
		"a sortie so short the worker barely leaves the nest"
	)
