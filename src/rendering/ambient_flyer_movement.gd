extends RefCounted

## Pure, deterministic idle-flight motion for ambient wildlife (butterflies,
## songbirds -- see docs/concept/ecosystem_dynamics.md's Species roster).
## Same shape as CreatureWander's direction_at/step_position (interval-stable
## pseudo-random heading, home-biased once too far away), but
## per-instance-configurable speed/radius/interval instead of fixed
## constants -- butterflies flutter (fast interval, small radius, slow
## speed) and songbirds glide (slower interval, larger radius, faster speed)
## share this one tested algorithm instead of two near-duplicate ones. Not
## AI (no needs/perception/behavior) -- purely decorative presence, like
## CreatureWander's own role for placeholder markers.

var speed: float
var radius: float
var direction_change_interval: float


func _init(a_speed: float, a_radius: float, a_direction_change_interval: float) -> void:
	speed = a_speed
	radius = a_radius
	direction_change_interval = a_direction_change_interval


## See CreatureWander's identically-named constants: the home anchor is
## CONTAINMENT (outward component progressively projected away inside a band
## just under `radius`), with a genuine inward pull easing in past the
## radius, complete by HOME_PULL_FULL_RADIUS_FACTOR x radius.
const HOME_PULL_FULL_RADIUS_FACTOR := 1.5
const HOME_CONTAINMENT_BAND_FRACTION := 0.25
## How much of the homeward pull is already applied the instant a flyer
## crosses `radius`, rather than easing in from nothing.
##
## Without a floor here the pull is ~0 at the boundary itself, so a flyer
## turned along the boundary by containment simply orbits there forever, at
## a measured 70.04 against a radius of 70. That is stable and jitter-free
## but it parks the flyer permanently just OUTSIDE `radius`, which silently
## breaks anything gated on it having come home -- `_relocate` (see
## AmbientFlyerMarker) never fires, so a flyer on barren ground rides its
## own fence instead of moving on to look elsewhere.
##
## Small enough that the boundary still reads as a soft turn rather than a
## bounce, big enough that a flyer riding it spirals back inside within a
## few seconds.
const MIN_HOME_PULL := 0.15


## A unit-length heading for a flyer at `current`, home-anchored at `home`.
## Deterministic for (home, elapsed_time, seed_value): the same flyer
## re-derives the same heading within a given direction_change_interval
## window.
##
## Home-anchoring is the same containment shape CreatureWander.direction_at
## earned the hard way (see its long doc comment): this used to hard-switch
## to "head straight home" past `radius`, which is a frame-rate limit cycle
## for a flyer parked ON the boundary -- outward roam, snap home, back
## inside, outward roam again -- read on screen as birds flickering/flipping
## erratically (reported alongside the boar/land-creature equivalent:
## "Boars and Birds now also get stuck, flicker and flip erratically").
func direction_at(home: Vector2, current: Vector2, elapsed_time: float, seed_value: int) -> Vector2:
	var roam := _roam_direction(elapsed_time, seed_value)
	var to_home := home - current
	var distance := to_home.length()
	if distance < 0.001:
		return roam
	var inward := to_home / distance
	var outward := -inward

	var band := radius * HOME_CONTAINMENT_BAND_FRACTION
	var containment := clampf((distance - (radius - band)) / band, 0.0, 1.0)
	# ROTATE the roam toward the boundary tangent. Three earlier shapes were
	# tried and measured, and each fixed less than it looked like it did:
	#
	# - Subtracting the outward component (the original) collapses to float
	#   residue when roam points nearly straight out -- measured
	#   roam.dot(outward) == +1.00 leaving a vector of length 0.002 -- and
	#   normalising residue turns numerical noise into a heading: consecutive
	#   frames came back (+0.17, -0.99) then (-0.18, +0.98), a 180-degree
	#   reversal every frame. Reported live as birds that "stall and jitter
	#   on a fixed spot", measured at 5.55 simulated seconds inside a 3px
	#   circle sitting exactly on the boundary (distance 70.04, radius 70).
	# - Widening that guard's length threshold only moves the cliff: the two
	#   sides of any cutoff disagree about which way round to go, measured as
	#   a 0.5px tremor instead of a flip.
	# - Reflecting the outward component is norm-preserving, so it does end
	#   the numerical jitter -- but a radial roam then simply bounces out and
	#   back in for its whole 1.4s interval, which still nets no travel
	#   (measured: worst stall got slightly WORSE, 6.23s).
	#
	# Rotation fixes both halves at once. It preserves length by
	# construction, so nothing can degenerate at any containment strength;
	# and at full containment the flyer flies ALONG its boundary rather than
	# into it, so it actually goes somewhere. The turn sense comes from the
	# seed/interval pair (see _turn_sign), never from the roam/outward
	# geometry -- that geometry is precisely what degenerates here, and
	# reading a direction out of it is what every earlier attempt got wrong.
	var tangent := Vector2(-outward.y, outward.x) * _turn_sign(elapsed_time, seed_value)
	var contained := _rotated_toward(roam, tangent, containment)

	if distance <= radius:
		return contained.normalized()

	var pull_span := radius * (HOME_PULL_FULL_RADIUS_FACTOR - 1.0)
	var pull := lerpf(MIN_HOME_PULL, 1.0, clampf((distance - radius) / pull_span, 0.0, 1.0))
	# `contained` has no outward component left out here, so it and `inward`
	# are at worst perpendicular -- they cannot cancel (see CreatureWander).
	return contained.normalized().lerp(inward, pull).normalized()


func _roam_direction(elapsed_time: float, seed_value: int) -> Vector2:
	var interval_index := int((elapsed_time + _phase_offset(seed_value)) / direction_change_interval)
	var angle_seed := hash("%d_%d" % [seed_value, interval_index])
	var angle := float(angle_seed % 360) * PI / 180.0
	return Vector2(cos(angle), sin(angle))


## Per-flyer offset, in seconds, spread across one whole direction_change_
## interval. Every AmbientFlyerMarker starts its own _elapsed_time at 0.0
## on spawn, so without this every flyer's interval_index ticked over at
## the identical elapsed_time regardless of seed -- two birds spawned
## together (an ordinary chunk load) recomputed a new heading on the exact
## same frame for the rest of their lives, no matter how different their
## chosen headings were. Reported live: "all birds on the screen reverse
## direction at the exact same time... behaviour should be individual".
## Derived from seed_value alone, so it is itself deterministic and holds
## for one flyer's whole lifetime, the same contract direction_at already
## promises.
func _phase_offset(seed_value: int) -> float:
	return float(hash("%d_phase" % seed_value) % 10000) / 10000.0 * direction_change_interval


## Advances `current` by one step of flight motion over `delta` seconds.
func step_position(
	home: Vector2, current: Vector2, elapsed_time: float, delta: float, seed_value: int
) -> Vector2:
	var direction := direction_at(home, current, elapsed_time, seed_value)
	return current + direction * speed * delta


## Which way round its home a contained flyer turns during this roam
## interval, as +1 (counter-clockwise) or -1.
##
## Derived from the SAME (seed, interval) pair the roam direction itself uses
## (see _roam_direction), so it holds steady for a whole
## direction_change_interval and never depends on the flyer's position. That
## independence is the point: the roam/outward geometry is exactly what
## degenerates when a flyer sits on its boundary, so any turn sense read out
## of it flips frame to frame there -- which is the jitter this whole
## containment path exists to avoid.
## How many direction_change_interval windows a contained flyer commits to
## one rotational direction before it is allowed to re-roll. Re-rolling
## every single roam interval (the old behaviour, TURN_SIGN_INTERVALS
## effectively 1) is an unbiased coin flip that on average reverses which
## way a contained flyer circles its territory every OTHER interval --
## nowhere near long enough to travel more than a short arc before turning
## back. Reported live: "robins still cycle between two points". Pinned by
## test_a_contained_flyer_ranges_over_a_wide_arc_not_just_two_points, not
## eyeballed: below this the test's 150-degree sweep starts failing for
## some seeds (an unlucky short run of alternating flips), same as the bug.
const TURN_SIGN_INTERVALS := 5


func _turn_sign(elapsed_time: float, seed_value: int) -> float:
	var interval_index := int(
		(elapsed_time + _phase_offset(seed_value)) / (direction_change_interval * TURN_SIGN_INTERVALS)
	)
	return 1.0 if hash("%d_%d_turn" % [seed_value, interval_index]) % 2 == 0 else -1.0


## `from` rotated `amount` (0..1) of the way toward `to`, the short way
## round. Length-preserving, unlike lerping between two unit vectors, which
## collapses toward zero as they approach opposite -- the degenerate case
## that has to be impossible here rather than merely unlikely.
static func _rotated_toward(from: Vector2, to: Vector2, amount: float) -> Vector2:
	var turn := wrapf(to.angle() - from.angle(), -PI, PI)
	return Vector2.from_angle(from.angle() + turn * amount)
