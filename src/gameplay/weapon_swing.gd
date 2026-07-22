extends RefCounted

## Pure angle logic for the equipped weapon's attack animation: a pendulum
## swing centered on a base orientation that depends on which way the player
## is facing -- left/right face a horizontal-oriented base (0 or PI), up/down
## a vertical-oriented base (+-PI/2), so a slash naturally reads as a
## horizontal or vertical swing depending on attack direction.

const AMPLITUDE := PI / 3.0  # 60 degrees either side of the base orientation

const _BASE_ORIENTATION := {
	"right": 0.0,
	"left": PI,
	"down": PI / 2.0,
	"up": -PI / 2.0,
}


## progress in [0, 1] across the swing's duration (clamped); returns the
## weapon's rotation in radians. 0 -> base - AMPLITUDE, 0.5 -> base,
## 1 -> base + AMPLITUDE (a smooth wind-up-to-follow-through pendulum).
func rotation_at(progress: float, facing: String) -> float:
	var t := clampf(progress, 0.0, 1.0)
	var base: float = _BASE_ORIENTATION.get(facing, 0.0)
	return base + AMPLITUDE * (t * 2.0 - 1.0)
