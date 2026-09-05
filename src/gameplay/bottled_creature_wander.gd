extends RefCounted

## A live creature's position/animation state while confined to a small
## container (docs/concept/capture_dsl.md's "Rendering a bottled catch") --
## deliberately much simpler than AmbientFlyerMarker's open-world state
## machine: no courtship, no nectaring, no perched-bird logic, because
## nothing in a sealed bottle forages or courts. Two states only, alternating
## on a deterministic hash-seeded timer -- the same "no RNG held anywhere"
## discipline every other per-individual timing in this codebase holds to.
##
## ## The two states
##
## FLYING: drifting from wherever the previous leg ended toward a fresh,
## deterministic destination inside the bounds. RESTING: settled at that
## destination, wings folded, for a (longer, on average) pause before the
## next flying leg begins.
##
## ## Why a leg's "from" is always the previous leg's "to"
##
## Each leg N has exactly one destination, `_destination(bounds, seed, N)`,
## used as BOTH where leg N flies to and where leg N then rests. Leg N+1's
## flying phase starts from that same point. So the path never pops at a
## fly<->rest boundary in either direction -- pinned by
## test_position_is_continuous_across_a_fly_rest_transition.

const MIN_FLY_SECONDS := 1.5
const MAX_FLY_SECONDS := 3.5
const MIN_REST_SECONDS := 2.0
const MAX_REST_SECONDS := 6.0


static func _unit(seed_value: int, salt: String) -> float:
	return float(absi(hash("%d_%s_bottled" % [seed_value, salt])) % 10000) / 10000.0


static func _duration(seed_value: int, salt: String, lo: float, hi: float) -> float:
	return lerpf(lo, hi, _unit(seed_value, salt))


## Which leg `elapsed_seconds` falls in, whether it's the resting half of
## that leg, and how far into that half it is.
static func _cycle_at(elapsed_seconds: float, seed_value: int) -> Dictionary:
	var t := 0.0
	var leg := 0
	while true:
		var fly := _duration(seed_value, "fly_%d" % leg, MIN_FLY_SECONDS, MAX_FLY_SECONDS)
		if elapsed_seconds < t + fly:
			return {"resting": false, "leg": leg, "into_leg": elapsed_seconds - t, "leg_seconds": fly}
		t += fly
		var rest := _duration(seed_value, "rest_%d" % leg, MIN_REST_SECONDS, MAX_REST_SECONDS)
		if elapsed_seconds < t + rest:
			return {"resting": true, "leg": leg, "into_leg": elapsed_seconds - t, "leg_seconds": rest}
		t += rest
		leg += 1
	return {}  # unreachable -- the loop above always returns for a finite elapsed_seconds


static func is_resting(elapsed_seconds: float, seed_value: int) -> bool:
	return _cycle_at(elapsed_seconds, seed_value)["resting"]


## Leg `leg`'s single destination -- both its flight target and its resting
## spot. Leg -1 is the fixed starting point (the bottle's own centre),
## before any leg has run.
static func _destination(bounds: Rect2, seed_value: int, leg: int) -> Vector2:
	if leg < 0:
		return bounds.position + bounds.size / 2.0
	return bounds.position + Vector2(
		_unit(seed_value, "dest_%d_x" % leg) * bounds.size.x,
		_unit(seed_value, "dest_%d_y" % leg) * bounds.size.y
	)


## Where inside `bounds` the creature is at `elapsed_seconds`.
static func position_in(bounds: Rect2, elapsed_seconds: float, seed_value: int) -> Vector2:
	var cycle := _cycle_at(elapsed_seconds, seed_value)
	var leg: int = cycle["leg"]
	var to := _destination(bounds, seed_value, leg)
	if cycle["resting"]:
		return to
	var from := _destination(bounds, seed_value, leg - 1)
	var progress: float = clampf(float(cycle["into_leg"]) / maxf(float(cycle["leg_seconds"]), 0.001), 0.0, 1.0)
	return from.lerp(to, progress)
