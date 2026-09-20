extends RefCounted

## How fast a plant yields to a walker, and how much longer it takes to
## come back (docs/concept/long_grass.md, "A plant is not rubber").
##
## Reported live, for every plant at once: *"it bounces back too fast and
## also bending too fast giving the impression of rubber instead of natural
## plant"*.
##
## The cause was that there was no TIME in the model at all. The bend
## shader's push term is a pure function of the walker's CURRENT distance,
## so a blade reached full lean the frame the walker came into range and
## stood upright again the frame they left — tracking them exactly, with
## no inertia and no settling. That is what zero damping looks like, and
## zero damping is what rubber looks like.
##
## The fix is one lagged point, not per-plant state. The shader is handed a
## walker position that takes real time to arrive and longer to leave;
## every plant still reads the same single point, so grass, ferns, wheat
## and brambles cannot drift into swaying by different rules, and nothing
## has to be stored per card. What it cannot express is a plant that is
## still settling while the walker presses a DIFFERENT one — a real
## spring per card — which is named as a gap in the doc rather than
## pretended away.

## Seconds for the bend to substantially develop as a walker arrives.
##
## A stalk gives quickly under a leg pushing through it, but not in one
## frame: at 60fps a frame is 0.017s, so anything at or below that IS the
## snap being fixed. Just under a fifth of a second is about how long a
## grass stem takes to fold over a boot going past at walking pace.
const YIELD_SECONDS := 0.18

## ...and seconds to come back once they have gone. THREE TIMES the yield,
## which is the whole asymmetry: a stem is pushed over by a force and
## returns on its own stiffness alone, so it always returns more slowly
## than it went. A cane springs back, it does not snap back.
const RELEASE_SECONDS := 0.55


## The walker position the bend should be drawn against this frame, eased
## from the one it was drawn against last frame toward where the walker
## really is.
##
## Exponential, not linear, so the response is frame-rate independent: the
## fraction covered depends on how much TIME passed, not on how many
## frames it took to pass. A linear step would bend faster on a faster
## machine, which is the kind of bug that only shows up on somebody else's
## computer.
##
## Clamped so a very long frame — a stall, a loading hitch — lands ON
## the walker rather than swinging through them and back, which would be a
## wobble nobody asked for.
##
## The rate is chosen per frame by which way the point is going: toward the
## walker is the plant YIELDING, away is it RECOVERING. "Toward" is decided
## by whether the gap is closing, so a walker who stops moving lets every
## plant round them relax at the slower rate, which is what a stand of
## grass really does once you stand still in it.
static func eased_walker_position(current: Vector2, target: Vector2, delta: float) -> Vector2:
	if delta <= 0.0:
		return current
	if current.is_equal_approx(UNSET_POSITION):
		# Nothing to ease FROM. Easing in from the sentinel would take the
		# bend point several seconds to cross a hundred thousand units,
		# so the first seconds of a fresh session would have no plant
		# parting for the player at all — found by a test asking only
		# that a standing walker is eventually where they are.
		return target
	var seconds := YIELD_SECONDS if _is_yielding(current, target) else RELEASE_SECONDS
	var fraction: float = clampf(1.0 - exp(-delta / maxf(seconds, 0.0001)), 0.0, 1.0)
	return current + (target - current) * fraction


## Whether this step is the plant giving way rather than standing back up.
##
## The eased point is always chasing the walker, so "yielding" cannot be
## read off the direction of travel — it is always toward them. What
## separates the two is HOW FAR: a walker arriving is near the point that
## is chasing them, and a walker leaving has already run off. So the gap
## itself is the signal, measured against the reach the push acts over
## (IllustratedGrassPatch.walker_radius's own default, restated rather than
## imported so this file stays pure geometry a headless test can reach).
static func _is_yielding(current: Vector2, target: Vector2) -> bool:
	return current.distance_to(target) <= WALKER_REACH


## What "no walker has been placed yet" looks like — the shader's own
## `player_world_position` default, restated here because this is the
## module that has to recognise it.
const UNSET_POSITION := Vector2(-100000.0, -100000.0)


## The distance the push acts over, in world units — the shader's own
## `walker_radius` default. Inside it, a walker is ON the plants and they
## are giving way; beyond it they have gone and the plants are coming back.
const WALKER_REACH := 22.0
