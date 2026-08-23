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
	var outward_amount := maxf(0.0, roam.dot(outward))
	var contained := roam - outward * outward_amount * containment
	if contained.length() < 0.001:
		contained = Vector2(-outward.y, outward.x)

	if distance <= radius:
		return contained.normalized()

	var pull_span := radius * (HOME_PULL_FULL_RADIUS_FACTOR - 1.0)
	var pull := clampf((distance - radius) / pull_span, 0.0, 1.0)
	# `contained` has no outward component left out here, so it and `inward`
	# are at worst perpendicular -- they cannot cancel (see CreatureWander).
	return contained.normalized().lerp(inward, pull).normalized()


func _roam_direction(elapsed_time: float, seed_value: int) -> Vector2:
	var interval_index := int(elapsed_time / direction_change_interval)
	var angle_seed := hash("%d_%d" % [seed_value, interval_index])
	var angle := float(angle_seed % 360) * PI / 180.0
	return Vector2(cos(angle), sin(angle))


## Advances `current` by one step of flight motion over `delta` seconds.
func step_position(
	home: Vector2, current: Vector2, elapsed_time: float, delta: float, seed_value: int
) -> Vector2:
	var direction := direction_at(home, current, elapsed_time, seed_value)
	return current + direction * speed * delta
