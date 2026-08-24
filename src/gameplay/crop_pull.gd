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
