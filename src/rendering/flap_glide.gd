extends RefCounted

const FlightIrregularity = preload("res://src/gameplay/flight_irregularity.gd")
const WingbeatBounce = preload("res://src/rendering/wingbeat_bounce.gd")

## The GAIT of a flying animal: bursts of beating alternating with phases
## where the wings are not driving (see docs/concept/ecosystem_dynamics.md's
## "The wingbeat bounce").
##
## Asked for as "can you add more random bounces and flaps?". The wing
## animation stepped frames at a fixed AmbientFlyerMarker.FLAP_SECONDS_PER_
## FRAME and the bob was a clean sinusoid at a fixed frequency -- both
## metronomic, which is exactly what reads as mechanical.
##
## ## What real flyers actually do
##
## Butterflies FLAP-GLIDE: monarchs especially alternate bursts of flapping
## with gliding and soaring, and their wingbeat is genuinely irregular. Small
## passerines do the related thing, FLAP-BOUNDING: bursts of beating between
## wings-folded ballistic phases. Bees and flies do neither -- they hum.
##
## So the metronome is not a simplification of one motion, it is the wrong
## motion. This module holds the gait; WingbeatBounce holds what the body does
## under it, and AmbientFlyerMarker._animate_wings drives both.
##
## Pure functions and constants, no nodes and no state: the gait is a function
## of time and of which individual it is, so it survives SimulationLod
## handing a flyer one large step instead of thirty small ones. Accumulating
## it per frame instead would make the gait depend on frame rate, which is the
## class of bug this system has already produced three separate ways.

## Above this wingbeat frequency an animal has ASYNCHRONOUS flight muscle, and
## does not alternate at all.
##
## This is a real physiological boundary rather than a threshold picked to
## split this game's roster. Synchronous flight muscle fires once per nerve
## impulse, which caps it in the low hundreds of hertz at the very most and in
## practice far lower; asynchronous muscle oscillates against the resonance of
## the thorax itself and is what lets a bee do a couple of hundred beats a
## second where a butterfly does ten. An animal beating that fast is not
## alternating with anything.
##
## Structural rather than conditional, the same way a bee simply cannot enter
## SpiralFlight and the same way WingbeatBounce needs no species gate: the
## frequency in WingbeatBounce.FLIGHT decides it, so a species added to that
## table gets the right answer without anybody maintaining a second roster.
const ASYNCHRONOUS_MUSCLE_HZ := 100.0

## What share of its flying time an alternating flyer spends NOT driving.
##
## Derived, not chosen. In level flight the mean lift across a whole gait
## cycle has to equal body weight. The wings supply none of it during the
## non-driving phase, so the flapping phase has to supply all of it -- and the
## most a wing can make is the ceiling WingbeatBounce already derives from "a
## wing cannot pull the body DOWN through its stroke": peak lift is at most
## (1 + e) x weight with e <= 1, i.e. twice weight. Flapping at that ceiling
## for (1 - f) of the time and making nothing for f of it gives
## (1 - f) x 2W = W, so f = 1/2.
##
## One number for every alternating flyer rather than a per-species table of
## guesses: the constraint it comes out of (level flight, against a lift
## ceiling that is itself a property of having wings) is the same for all of
## them.
const GLIDE_FRACTION := 1.0 - 1.0 / (1.0 + WingbeatBounce.MAX_LIFT_SWING)

## How many visible wing-beats a flapping bout lasts.
##
## The one figure here that is NOT derived. Two is the smallest number that is
## a burst rather than a single flap -- one beat followed by a pause is a
## stutter, not a gait -- and the tests pin the properties that actually
## matter (the flapping half is at least two visible beats, and the whole gait
## repeats inside a couple of seconds so a player watching sees it happen)
## rather than the digit.
##
## Counted in ANIMATION beats, not real ones, for exactly the reason
## WingbeatBounce phase-locks the bob to the animation: the sprite's beat is
## stylised and slower than the real one, and the gait has to be a rhythm of
## what the player can actually see the wings doing.
const BOUT_BEATS := 2

## How much the beat rate swings inside a bout, as a fraction.
##
## Real wingbeats are irregular -- a bout builds and tails off rather than
## ticking -- and the size of that swing is derived rather than picked.
## Quasi-steady lift goes as the square of the flapping speed (L ~ v^2, and a
## flapping wing's speed goes as its frequency), so a lift that can swing by e
## corresponds to a rate that swings by sqrt(1 + e) - 1. With WingbeatBounce's
## e = 1 ceiling that is sqrt(2) - 1.
##
## Comfortably under 1, which is what guarantees the wing clock below can
## never run backwards.
const RATE_SWING := sqrt(1.0 + WingbeatBounce.MAX_LIFT_SWING) - 1.0


func _init() -> void:
	pass


## Whether this flyer alternates at all. See ASYNCHRONOUS_MUSCLE_HZ: read off
## the wingbeat frequency, so there is no roster to keep in step.
static func glides(species: String) -> bool:
	var beat: Dictionary = WingbeatBounce.FLIGHT.get(
		species, WingbeatBounce.FLIGHT[WingbeatBounce.FALLBACK_SPECIES]
	)
	return float(beat["wingbeat_hz"]) < ASYNCHRONOUS_MUSCLE_HZ


## How long one whole bout-plus-glide takes, given the length of one visible
## wing-beat (AmbientFlyerMarker's FLAP_SECONDS_PER_FRAME x frame count).
##
## The BOUT is the fixed part -- BOUT_BEATS visible beats -- and the glide is
## whatever makes GLIDE_FRACTION come out right, which is the same shape
## SpiralFlight.COOLDOWN_SECONDS uses: state the duty cycle, derive the gap.
static func gait_seconds(species: String, cycle_seconds: float) -> float:
	if not glides(species) or cycle_seconds <= 0.0:
		return 0.0
	return cycle_seconds * float(BOUT_BEATS) / (1.0 - GLIDE_FRACTION)


## Where in its own gait this individual is, as 0..1. The per-individual phase
## offset is what stops a meadow beating in unison, hash-derived like the rest
## of the world's per-individual variation.
static func gait_progress(
	species: String, elapsed_seconds: float, cycle_seconds: float, seed_value: int
) -> float:
	var gait := gait_seconds(species, cycle_seconds)
	if gait <= 0.0:
		return 0.0
	var offset := FlightIrregularity.phase(seed_value) / TAU * gait
	return fposmod(elapsed_seconds + offset, gait) / gait


## True while the wings are not driving. The bout comes FIRST in the cycle, so
## a flyer at gait progress 0 is beginning a burst.
static func is_gliding(
	species: String, elapsed_seconds: float, cycle_seconds: float, seed_value: int
) -> bool:
	if not glides(species):
		return false
	return gait_progress(species, elapsed_seconds, cycle_seconds, seed_value) > (
		1.0 - GLIDE_FRACTION
	)


## How far through the current phase this flyer is, 0..1 -- through the bout
## while it is beating, through the glide while it is not. What the body's
## sag is ramped on (see WingbeatBounce.bounce_offset).
static func phase_progress(
	species: String, elapsed_seconds: float, cycle_seconds: float, seed_value: int
) -> float:
	if not glides(species):
		return 0.0
	var progress := gait_progress(species, elapsed_seconds, cycle_seconds, seed_value)
	var flapping := 1.0 - GLIDE_FRACTION
	if progress <= flapping:
		return progress / flapping
	return (progress - flapping) / GLIDE_FRACTION


## How many visible wing-beats this flyer has completed by `elapsed_seconds`.
##
## THE WING CLOCK, and the thing both the frame animation and the bob are
## driven off, so they can never disagree about what the wings are doing. Two
## properties matter and both are tested:
##
## - it only advances while the wings are BEATING. A gliding butterfly holds
##   its wings out; cycling the flap frames with nothing driving them is the
##   metronome again with extra steps.
## - it is monotone. A wing clock that could go backwards would run the flap
##   animation in reverse.
##
## The rate swing inside a bout is applied in the clock's OWN time and
## integrated exactly (FlightIrregularity.wobble_integral), so the beat varies
## without the phase ever depending on how the caller happened to step time.
static func wing_cycles(
	species: String, elapsed_seconds: float, cycle_seconds: float, seed_value: int
) -> float:
	if cycle_seconds <= 0.0:
		return 0.0
	if not glides(species):
		return elapsed_seconds / cycle_seconds
	var gait := gait_seconds(species, cycle_seconds)
	var bout := gait * (1.0 - GLIDE_FRACTION)
	var offset := FlightIrregularity.phase(seed_value) / TAU * gait
	# Beating time since this flyer came into existence: the individual's own
	# phase offset cancels out, so t = 0 is always exactly zero beats.
	var beating := (
		_beating_seconds(elapsed_seconds + offset, gait, bout)
		- _beating_seconds(offset, gait, bout)
	)
	# ...advanced at a rate that varies inside the bout rather than ticking.
	# Applied in the CLOCK's own time and integrated exactly, so the beat
	# varies without the phase ever depending on how the caller stepped time.
	return (
		beating + RATE_SWING * FlightIrregularity.wobble_integral(beating, seed_value)
	) / cycle_seconds


## How much of `shifted` was spent inside a bout rather than a glide.
static func _beating_seconds(shifted: float, gait: float, bout: float) -> float:
	var whole_gaits := floorf(shifted / gait)
	var within := shifted - whole_gaits * gait
	return whole_gaits * bout + minf(within, bout)


## The body's draw offset under this gait, in whatever units `body_px` is in.
## NEGATIVE is up: screen-up is -Y in this top-down world.
##
## Composed from WingbeatBounce rather than replacing it -- that module owns
## how big the bob is and why, and still knows nothing about gaits (its
## amplitude derivation and all of its tests are untouched). This owns WHEN
## the wings are driving. Two things add up here:
##
## - THE BOB, which is WingbeatBounce's pulse-driven rise and fall, but locked
##   to the wing clock above rather than to wall time -- so when the wings
##   pause, the bob pauses with them, which is the whole point ("the bounce
##   should follow whatever the wings are actually doing").
## - THE SAG. A gliding butterfly is not being held up by lift pulses any
##   more, and it sinks. It then climbs back through the next bout, so the two
##   cancel over a whole gait and the flyer stays in level flight -- a
##   sawtooth with no net drift, which is what flap-gliding IS. Its size is
##   not a new number: it is the same amplitude, because the height a bout
##   gains is exactly the height the glide gives back.
##
## The bob is windowed by sin(pi x bout progress), which is zero at both ends
## of a bout. Real, and load-bearing: a flap-glide bout builds and tails off
## rather than starting and stopping at full stroke, and the window is also
## what makes this continuous across every phase boundary however the rate
## swing has shifted the wing clock.
##
## Like WingbeatBounce, this is a DRAW offset and the caller must never apply
## it to `position` -- see AmbientFlyerMarker._bounce_on_the_wingbeat.
static func body_offset(
	species: String,
	elapsed_seconds: float,
	seconds_per_frame: float,
	frame_count: int,
	body_px: float,
	seed_value: int
) -> float:
	if frame_count <= 0 or seconds_per_frame <= 0.0:
		return 0.0
	var cycle_seconds := seconds_per_frame * float(frame_count)
	var amplitude := WingbeatBounce.amplitude_bodies(species) * body_px
	var cycles := wing_cycles(species, elapsed_seconds, cycle_seconds, seed_value)
	if not glides(species):
		return -amplitude * sin(TAU * cycles)
	var progress := phase_progress(species, elapsed_seconds, cycle_seconds, seed_value)
	if is_gliding(species, elapsed_seconds, cycle_seconds, seed_value):
		# Sinking, wings still: no pulse, so no bob.
		return amplitude * progress
	# Climbing back out of the sag, bobbing on the beat as it goes.
	return amplitude * (1.0 - progress) - amplitude * sin(TAU * cycles) * sin(PI * progress)
