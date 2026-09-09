extends RefCounted

## Real per-step footfall detection -- alternates left/right exactly like a
## real walking gait, driven by ACTUAL distance travelled rather than a
## fixed per-frame or per-tile-entry event (unlike PathScarring/SnowTrail's
## own tile-entry debounce, which is the wrong granularity for an
## individual foot-fall). Reported live: "real footstep prints with
## left/right footprints spaced apart... stamped into the snow with
## displacement" -- see docs/concept/snow_cover.md's own "Footprints"
## section and docs/concept/infrastructure.md's path-scarring framing.
##
## Mirrors CreatureMarker._gait_distance's own "accumulate real travelled
## distance, threshold it" shape (src/rendering/creature_marker.gd:458,
## 1830-1832), generalized from indexing an ANIMATION FRAME into emitting a
## discrete, real WORLD event instead: "plant a foot here, alternate which
## one." Nothing in this codebase already did this -- confirmed by a
## dedicated research pass before writing this file (checked
## leg_gait_cycle.gd/quadruped_gait.gd, both pure bend-angle trig with no
## world-position event at all; PebbleDispersion/crush/water-disturbance,
## all continuous per-frame proximity checks, not discrete alternating
## events).
##
## Pure and stateless-per-instance (one FootstepGait per walker, the same
## "one accumulator per creature" shape _gait_distance already has) -- no
## Godot node/scene dependency, so this is fully unit-testable headlessly.

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## Real average adult walking stride length -- heel-to-heel between
## alternating feet, not an eyeballed pixel count. Converted via
## GroundSlide.PX_PER_METER, the same real-human-scale-to-world-pixels
## idiom this codebase already uses for exactly this kind of body-scale
## constant (see that class's own doc comment).
const STRIDE_LENGTH_METERS := 0.75
const STRIDE_LENGTH_PX := STRIDE_LENGTH_METERS * GroundSlide.PX_PER_METER

## How far apart a left and right print land to either side of the
## walked line, not the distance between consecutive steps (that's
## STRIDE_LENGTH_PX above). A person does not walk with their feet on a
## single line; each print offsets sideways from the centre by half of
## this.
##
## Widened from the real average adult stance width (0.12m) to a real,
## wider-gait value further along the same natural range -- reported
## live, directly: "space left and right foot a bit wider". Still a real
## human measurement, converted the same way, just further along the
## same real range rather than an eyeballed pixel bump.
const STANCE_WIDTH_METERS := 0.22
const STANCE_WIDTH_PX := STANCE_WIDTH_METERS * GroundSlide.PX_PER_METER

var _distance_since_last_step := 0.0
var _next_is_left := true
## This walker's own last-known real position -- Vector2(INF, INF) means
## "no prior call yet" (see step_at), the same sentinel EarthChunkManager.
## _last_footstep_position used to carry externally before this. Owning it
## HERE, not on the caller, is what makes one FootstepGait instance the
## WHOLE per-walker footstep record (see this file's own header doc
## comment: "one FootstepGait per walker") -- a CreatureMarker (or the
## player) needs no second, external position tracker alongside its own
## lazily-built FootstepGait, the same "one object, everything about this
## walker's own footfalls" contract current_mass_kg()'s lazily-built
## Metabolism already has for mass.
var _last_position := Vector2(INF, INF)


## Consumes `distance_travelled` (real world px moved since the last call)
## and returns "left", "right", or "" (no step due yet). A real gait
## alternates every single step. The remainder carries forward via fmod
## rather than resetting to zero, so calling this every physics frame with
## a small per-frame delta fires a step at exactly the same total distance
## as one big call would -- and a single very large jump (e.g. a teleport)
## still leaves the accumulator in a correct, in-range state for the next
## call rather than firing a burst of queued steps for a jump nobody could
## have seen the intermediate frames of anyway.
func step_if_due(distance_travelled: float) -> String:
	_distance_since_last_step += distance_travelled
	if _distance_since_last_step < STRIDE_LENGTH_PX:
		return ""
	_distance_since_last_step = fmod(_distance_since_last_step, STRIDE_LENGTH_PX)
	var side := "left" if _next_is_left else "right"
	_next_is_left = not _next_is_left
	return side


## Where a `side` print lands relative to the walker's own current
## position, given their current travel `heading` (need not be normalized).
## Perpendicular to the heading (never along it -- a footprint offsets
## sideways from the walked line, not forward/back of it), the same
## `(-y, x)` 90-degree-rotation convention LeafLitterRenderer's own vertex
## shader already uses for an unrelated wander effect (leaf_litter_
## renderer.gd:476) -- "left"/"right" here just needs to be a stable,
## alternating label for which side a print offsets to, not a literal
## anatomical claim, so reusing the existing rotation convention rather
## than inventing a second one is what matters.
static func print_offset(heading: Vector2, side: String) -> Vector2:
	var direction := heading.normalized()
	if direction == Vector2.ZERO:
		# No established heading yet (e.g. spawned standing still) -- fall
		# back to a fixed, stable direction rather than producing a
		# zero-length perpendicular (which would collapse both feet onto
		# the same point) or NaN (normalizing a zero vector).
		direction = Vector2.UP
	var perpendicular := Vector2(-direction.y, direction.x)
	var sign := -1.0 if side == "left" else 1.0
	return perpendicular * sign * (STANCE_WIDTH_PX / 2.0)


## The complete per-walker entry point: consumes this walker's CURRENT real
## `position` and returns "left"/"right"/"" exactly like step_if_due, but
## owning the distance-since-last-call AND teleport detection internally
## too (see _last_position's own doc comment) rather than needing a caller
## to track a separate last-position and pre-compute a distance itself.
## Mirrors EarthChunkManager.record_footstep's own original inline shape
## exactly (see that function's prior revision): the very first call
## establishes a baseline and reports no step yet; a jump past
## `teleport_gap_px` (a real dev-command/respawn/save-load discontinuity,
## not real walking) resets the stride accumulator AND restarts the
## left/right alternation from "left" -- the same full reset a brand new
## FootstepGait() used to give by being thrown away and replaced wholesale.
func step_at(position: Vector2, teleport_gap_px: float) -> String:
	if is_inf(_last_position.x):
		_last_position = position
		return ""
	var distance := position.distance_to(_last_position)
	_last_position = position
	if distance > teleport_gap_px:
		_distance_since_last_step = 0.0
		_next_is_left = true
		return ""
	return step_if_due(distance)
