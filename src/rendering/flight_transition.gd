extends RefCounted

## How a flyer gets from one thing it is doing to the next WITHOUT teleporting.
##
## ## The bug this exists for
##
## Reported as a question, which is the same thing: "can you interpolate the
## state transitions?" Every state entry in AmbientFlyerMarker used to be a
## bare `position = <wherever the new state wants me>`, and a state entry is
## exactly the frame the player is most likely to be looking at the animal.
## Measured against the shipped constants, on 1/60 s frames:
##
## - a butterfly flies 0.267 px per frame (16 px/s)
## - the courtship dance put it 14.9 px away on the frame after it began
## - the whirl swung it 3.27 px, the player-head orbit 6.31 px
## - each of the four bird ground-forage arrivals snapped it 3.52 px
##
## ## The one invariant
##
## **Nothing may move further in one step than the airspeed it is flying at
## carries it.** That single statement catches all of the above, catches any
## future state entry, and needs no tuned number at all: the time to cross a
## gap is the gap divided by the flyer's own airspeed. NectaringPosture
## already derived its landing that way (LANDING_DISTANCE / airspeed); this is
## that idea with the distance left as a parameter, so every other entry can
## use it too rather than copying the shape seven times.
##
## Pure functions and constants, no nodes, engine-free -- the same shape as
## NectaringPosture, FlapGlide, WingbeatBounce and FlightIrregularity, which
## own the other things a flyer's body does.

const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")


## How much faster than its average a SMOOTHSTEPPED crossing runs at its
## fastest moment.
##
## Derived, not measured off a graph: the ease below is t*t*(3 - 2t), whose
## derivative is 6t(1 - t), which peaks at t = 0.5 with the value 1.5. So a
## smoothstepped crossing of a gap in `gap / airspeed` seconds is travelling at
## one and a half times that airspeed halfway through -- which is the whole
## invariant broken in the middle of the very move that exists to honour it.
## settling_seconds below pays for it by stretching the crossing; pinned by
## test_the_peak_of_a_smoothstepped_settle_is_exactly_the_flyers_airspeed.
const EASE_PEAK_RATE := 1.5


func _init() -> void:
	pass


## How long it takes this flyer, at its own airspeed, to cover `gap_px` at a
## STEADY rate. The whole duration model, and it is a division rather than a
## constant: a bee (faster) crosses the same gap quicker than a monarch
## without a second tuned number having to exist.
##
## Used where the crossing really is linear -- the converging orbits, whose
## closed-form turn rate (see SpiralFlight.orbit_clock) needs a radius that
## ramps linearly. Use settling_seconds instead wherever `ease` shapes it.
static func crossing_seconds(gap_px: float, airspeed_px_per_second: float) -> float:
	if airspeed_px_per_second <= 0.0:
		return 0.0
	return maxf(gap_px, 0.0) / airspeed_px_per_second


## How long an EASED crossing of `gap_px` has to take for its fastest moment
## to be exactly this flyer's airspeed -- the linear crossing stretched by
## EASE_PEAK_RATE.
##
## An eased settle is worth the stretch: it means the flyer decelerates onto
## the thing it is landing on rather than arriving at full speed and stopping
## dead, which is the other half of "it does not teleport".
static func settling_seconds(gap_px: float, airspeed_px_per_second: float) -> float:
	return EASE_PEAK_RATE * crossing_seconds(gap_px, airspeed_px_per_second)


## How far through a transition it is: 0 the instant it began, 1 once it is
## finished. Smoothstepped, so the body eases in and out of the move rather
## than starting and stopping dead.
static func eased_progress(seconds_since_entry: float, span_seconds: float) -> float:
	if span_seconds <= 0.0:
		return 1.0
	var t := clampf(seconds_since_entry / span_seconds, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Where a body that began at `from` and is easing onto `to` sits right now.
## The whole eased-entry idiom in one call, so a site that has to do this is
## three lines rather than eight.
static func eased_position(
	from: Vector2, to: Vector2, seconds_since_entry: float, span_seconds: float
) -> Vector2:
	return from.lerp(to, eased_progress(seconds_since_entry, span_seconds))


## The fastest this flyer can go, in world pixels per second: its cruise times
## the burst multiple this game already derived (FlyerPersonality.
## ESCAPE_SPEED_MULTIPLIER, which is itself SpiralFlight.BURST_SPEED_MPS over
## Courtship.CRUISE_SPEED_MPS). Not a new number, and the ceiling a fleeing
## flyer already moves at.
static func burst_px_per_second(cruise_px_per_second: float) -> float:
	return maxf(cruise_px_per_second, 0.0) * FlyerPersonality.ESCAPE_SPEED_MULTIPLIER


## The furthest anything with these wings may move in one step of `delta`.
## The invariant this whole module exists for, as a number a caller can assert
## against.
static func step_ceiling_px(airspeed_px_per_second: float, delta: float) -> float:
	return maxf(airspeed_px_per_second, 0.0) * maxf(delta, 0.0)
