extends RefCounted

## Pure motion/timing math for the wild-crop "pull" harvest animation (see
## WildCropMarker, docs/concept/wild_crops.md) -- the same "runtime tween
## over static parts, not baked animation frames" idiom Knockback.step
## already established for hit displacement: a pure function of elapsed
## time, so the curve itself is headlessly testable rather than living
## inside an opaque Godot Tween. A marker's own _process just samples this
## every frame and stops once is_complete says so.

## How long a pull takes, start to finish.
const DURATION_SECONDS := 0.5

## How far (world px) the leaves+root group rises as it clears the soil
## mound -- small: this is a yank out of the ground, not a launch.
const RISE_PX := 14.0


## Eased 0..1 progress at `elapsed` seconds into the pull (clamped to
## [0, DURATION_SECONDS]) -- cubic ease-OUT (fast start, settling into
## place), matching a real yank rather than a linear slide.
static func progress_at(elapsed: float) -> float:
	var t := clampf(elapsed / DURATION_SECONDS, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


## The leaves+root group's own upward offset (negative Y) at this elapsed
## time.
static func rise_offset_at(elapsed: float) -> Vector2:
	return Vector2(0.0, -RISE_PX * progress_at(elapsed))


## Whether the pull has finished -- the marker finalizes (drops the root,
## frees itself) once this is true.
static func is_complete(elapsed: float) -> bool:
	return elapsed >= DURATION_SECONDS


## The root sprite's growing reveal region as the pull progresses --
## `canvas_size.y` tall at full progress, `canvas_size.x` wide throughout,
## always anchored at the canvas's own top-left. The root texture's crown
## (canvas y=0, where it attaches to the leaves -- see
## IllustratedCropSprite's own baseline-anchoring convention) is the part
## revealed FIRST and stays there; only the bottom edge of this rect moves
## as progress grows, exposing more of the shaft/tip.
##
## Reported live: "carrots/potatoes render a huge blob behind the leaves."
## An earlier version paired a rect exactly like this one with an OFFSET
## that also grew with progress (see root_reveal_offset below for why that
## was wrong) -- the crown's own DRAWN position climbed steadily upward,
## away from the leaves, the more of the root became revealed, instead of
## the root visibly hanging below the leaf cluster it never actually
## detaches from.
static func root_reveal_rect(canvas_size: Vector2i, progress: float) -> Rect2:
	var revealed_height := clampf(progress, 0.0, 1.0) * float(canvas_size.y)
	return Rect2(Vector2.ZERO, Vector2(canvas_size.x, revealed_height))


## The root sprite's drawn offset -- horizontal centering only, and
## deliberately CONSTANT across the whole pull (no `progress` parameter).
## The buggy version this replaces set offset.y to `-revealed_height`,
## shifting the crown's own screen position upward in lockstep with how
## much of the root had been revealed -- correct-looking at a glance
## (the rect appeared to "grow up and out of the ground"), but it moved
## the CROWN itself, which should stay fixed where the leaves are; only
## the newly-revealed tip end should extend away from that fixed point.
static func root_reveal_offset(canvas_size: Vector2i) -> Vector2:
	return Vector2(-float(canvas_size.x) / 2.0, 0.0)
