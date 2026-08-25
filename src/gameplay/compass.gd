extends RefCounted
## Compass bearing math -- docs/concept/wayfinding.md's Compass item. North
## is this world's own fixed +Y axis (a documented game convention, not a
## simulated magnetic field -- see world.md's toroidal-map decision). Reads
## real player/target positions; invents nothing.

## Nearest-compass-point snap step for a rough reading -- the compass rose
## has 8 points (N, NE, E, SE, S, SW, W, NW), each 360/8 = 45 degrees apart.
const ROUGH_STEP_DEGREES := 45.0


## Real bearing from `from_position` to `to_position`, in the compass-rose
## convention: 0=N(+Y), 90=E(+X), 180=S(-Y), 270=W(-X), clockwise-positive,
## wrapped to [0, 360). Direction-only -- distance to the target never
## affects the reading.
static func bearing_degrees(from_position: Vector2, to_position: Vector2) -> float:
	var offset := to_position - from_position
	# atan2(x, y) (arguments swapped from the usual atan2(y, x)) measures
	# the angle clockwise from +Y, which is exactly the compass-rose
	# convention this world uses for north.
	var radians := atan2(offset.x, offset.y)
	var degrees := rad_to_deg(radians)
	return wrapf(degrees, 0.0, 360.0)


## Snaps a bearing to the nearest of the 8 compass points (nearest
## 45-degree step), wrapped to [0, 360) so a snap to 360 reads as 0.
## Uses `roundf` (float-typed return) rather than the generic `round` --
## `round`'s return is Variant even for a float input, which this
## project's strict typing rejects for a `:=` local.
static func rough_reading(bearing: float) -> float:
	var snapped := roundf(bearing / ROUGH_STEP_DEGREES) * ROUGH_STEP_DEGREES
	return wrapf(snapped, 0.0, 360.0)


## Exact bearing, unchanged -- the fine-compass quality tier.
static func fine_reading(bearing: float) -> float:
	return bearing


## Dispatches to fine_reading or rough_reading depending on the compass's
## own quality tier (docs/concept/wayfinding.md's Compass quality axis).
static func reading_for(bearing: float, is_fine: bool) -> float:
	if is_fine:
		return fine_reading(bearing)
	return rough_reading(bearing)
