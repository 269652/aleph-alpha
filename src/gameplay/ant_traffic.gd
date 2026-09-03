extends RefCounted

## Workers trickling out of an ant mound and back (see
## docs/concept/soil_fauna.md's "What the player sees").
##
## Reported live, looking at a real grassland chunk: "the bare grass parts feel
## empty". Ten colonies per chunk were quietly moving seed around ground that
## drew nothing at all -- and once the mound itself is drawn, a bump of soil
## with nothing on it reads as a rock. Movement is what makes it read as a
## colony.
##
## **This is ambient animation, not a second simulation.** `soil_fauna.md`'s own
## scope note says a colony is "not something that needs (or would even read as)
## an individually-pathed sprite", and that stays true of SIMULATION: there is
## no per-ant marker, no ant AI, no pathfinding, and the foraging that actually
## moves seed is still `AntColony`'s colony-level roll. This is the same
## category as `WindSway` animating grass blades nothing simulates individually.
##
## Two rules keep the decoration honest rather than a lying simulation:
##
##   The drawn range never exceeds the SIMULATED one -- MAX_RANGE_PX is derived
##   from `AntColony.FORAGE_RADIUS_TILES`, the radius
##   `EarthChunkManager._forage_seed_near_mound` really searches, so the traffic
##   can never advertise a reach the colony does not have.
##
##   Every trip starts and ends at the entrance. Workers come out of the nest
##   and go back into it; one that drifted away would read as an escaped bug.
##
## Pure and engine-free, and stateless per ant: a worker's offset is a function
## of its seed and the elapsed time, so nothing is stored and the whole thing is
## testable headlessly.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How many workers one mound draws. These are 2px dots: a handful reads as
## traffic, a crowd reads as a static texture, and the mound is meant to be
## noticed rather than to dominate the tile.
const WORKERS_PER_MOUND := 3

## The furthest a drawn worker gets from its own entrance. Derived from the
## colony's OWN foraging radius rather than picked, and deliberately short of
## it: the art must never claim more reach than the simulation has. Pinned by
## test_a_worker_never_ranges_further_than_the_colony_actually_forages.
const RANGE_FRACTION_OF_FORAGE := 0.8
const MAX_RANGE_PX := (
	AntColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE) * RANGE_FRACTION_OF_FORAGE
)

## How long one out-and-back trip takes. Varied per worker and per trip so a
## nest does not pulse in unison.
const MIN_TRIP_SECONDS := 4.0
const MAX_TRIP_SECONDS := 9.0

## How far a worker may move in one 60 fps frame before it reads as a jump
## rather than as a walk. Not a tuning knob -- it is the ceiling
## test_a_worker_never_teleports_between_frames holds the motion to, and the
## reason the excursion curve below is smooth rather than a triangle.
const MAX_STEP_PX_PER_FRAME := 1.0

## How far a worker wanders off its own bearing as it goes, as a fraction of
## its current distance out. Real ants do not walk rays; a little lateral
## wander is what stops the traffic reading as spokes on a wheel.
const WANDER_FRACTION := 0.35

## How many wobbles a worker makes over one trip.
const WANDER_CYCLES := 2.0

## How many trips a worker's traffic repeats after.
##
## Two jobs. It bounds the search loop in worker_offset, so that stays O(a few)
## however long the game has been running. And it is the period the whole
## pattern wraps on: at these trip lengths that is minutes of wall clock, far
## longer than a mound stays on screen, and the seam is invisible because every
## trip both starts and ends at the entrance.
##
## Public because trip_start_time is only meaningful WITHIN one cycle -- a
## trip_index at or past this wraps to a different trip at a different phase,
## which is a trap for anything reasoning about a specific trip.
const TRIPS_PER_CYCLE := 8

## The shortest trip a worker makes, as a fraction of MAX_RANGE_PX. Not every
## excursion is a full patrol -- some are short sorties -- or all three workers
## pace three fixed radii and the nest reads as a mechanism rather than as
## animals (test_some_trips_are_short_sorties).
const MIN_TRIP_RANGE_FRACTION := 0.45

const _WORKER_SALT := 7919
const _TRIP_SALT := 104729


## A stable per-worker seed for worker `index` on the mound identified by
## `mound_seed`. Keeps two workers on one mound from moving as one animal in
## two places, and two mounds from running identical traffic.
static func worker_seed(mound_seed: int, index: int) -> int:
	return PixelNoise.value(mound_seed + _WORKER_SALT, index, 0)


## How long this worker's `trip_index`-th trip takes.
static func trip_seconds_for(worker_seed_value: int, trip_index: int) -> float:
	var unit := PixelNoise.unit(worker_seed_value + _TRIP_SALT, trip_index, 0)
	return lerpf(MIN_TRIP_SECONDS, MAX_TRIP_SECONDS, unit)


## When this worker's `trip_index`-th trip begins, in seconds since the clock
## this is sampled against started. Only meaningful for a `trip_index` inside
## one cycle (0 .. TRIPS_PER_CYCLE - 1): past that the traffic has wrapped, and
## the time this returns lands in a different trip at a different phase.
##
## Summed rather than multiplied because trips have DIFFERENT lengths: with one
## shared duration the whole nest would step in time, and with a multiply the
## trip a given moment falls in could not be found consistently.
static func trip_start_time(worker_seed_value: int, trip_index: int) -> float:
	var start := 0.0
	for index in maxi(trip_index, 0):
		start += trip_seconds_for(worker_seed_value, index)
	return start


## Where this worker is right now, as an offset in world pixels from its own
## mound's entrance.
static func worker_offset(worker_seed_value: int, elapsed_seconds: float) -> Vector2:
	var elapsed := maxf(elapsed_seconds, 0.0)
	# Walk forward through the trips to find which one `elapsed` falls in.
	# Trips vary in length, so there is no closed form -- but the loop is
	# bounded by wrapping the clock into a whole number of trips first, which
	# keeps this O(a few) however long the game has been running.
	var cycle := _cycle_seconds(worker_seed_value)
	var within_cycle := fmod(elapsed, cycle)
	var trip_index := 0
	var trip_start := 0.0
	while trip_index < TRIPS_PER_CYCLE - 1:
		var length := trip_seconds_for(worker_seed_value, trip_index)
		if within_cycle < trip_start + length:
			break
		trip_start += length
		trip_index += 1
	var trip_length := trip_seconds_for(worker_seed_value, trip_index)
	var t := clampf((within_cycle - trip_start) / trip_length, 0.0, 1.0)
	return _excursion(worker_seed_value, trip_index, t)


## How far along its bearing a worker is at `t` (0 leaving, 1 back), and where
## the lateral wander has taken it.
##
## The out-and-back profile is a SINE rather than a triangle: a triangle peaks
## with a corner, which at the top of the trip reverses the worker's direction
## in a single frame and reads as a bounce. A sine turns it around smoothly,
## which is also what keeps the per-frame step under MAX_STEP_PX_PER_FRAME.
static func _excursion(worker_seed_value: int, trip_index: int, t: float) -> Vector2:
	var bearing := PixelNoise.unit(worker_seed_value, trip_index, 1) * TAU
	var direction := Vector2(cos(bearing), sin(bearing))
	var out := sin(t * PI) * MAX_RANGE_PX * _trip_range_fraction(worker_seed_value, trip_index)
	var sideways := direction.orthogonal() * out * WANDER_FRACTION * sin(t * TAU * WANDER_CYCLES)
	return direction * out + sideways


## Not every trip goes the full distance -- some are short sorties. Keeps a
## worker's excursions from all reaching exactly the same ring.
static func _trip_range_fraction(worker_seed_value: int, trip_index: int) -> float:
	return lerpf(MIN_TRIP_RANGE_FRACTION, 1.0, PixelNoise.unit(worker_seed_value, trip_index, 2))


static func _cycle_seconds(worker_seed_value: int) -> float:
	var total := 0.0
	for index in TRIPS_PER_CYCLE:
		total += trip_seconds_for(worker_seed_value, index)
	return total
