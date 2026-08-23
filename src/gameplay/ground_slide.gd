extends RefCounted

## Shared real kinematics: how far something slides across the ground after
## leaving at some velocity, under constant kinetic friction -- used by BOTH
## Kick (a foot's delivered momentum divided by the stone's own mass) and the
## held-item throw (a deliberate arm throw at the charge meter's release
## speed), so both read the SAME real physical constants rather than
## independently duplicating gravity/friction.

## Real gravitational acceleration, m/s^2.
const GRAVITY_MPS2 := 9.81

## A typical kinetic friction coefficient for rock sliding across packed
## earth/grass -- commonly cited stone-on-soil friction coefficients sit
## roughly in the 0.4-0.6 range; 0.5 splits the difference.
const GROUND_FRICTION_COEFFICIENT := 0.5

const StoneSize = preload("res://src/world/stone_size.gd")

## World pixels per real metre, derived from StoneSize's own existing
## player-height grounding (PLAYER_WORLD_HEIGHT_PX represents
## PLAYER_HEIGHT_CM) rather than a second, independently-invented scale
## factor -- the same yardstick every other real-world-grounded size in this
## codebase is read against.
const PX_PER_METER := StoneSize.PLAYER_WORLD_HEIGHT_PX / (StoneSize.PLAYER_HEIGHT_CM / 100.0)


## How far something leaving at `velocity_mps` slides before kinetic
## friction stops it: the standard stopping-distance kinematics equation,
## distance = velocity^2 / (2 * mu * g), converted to world pixels and
## clamped to `max_distance_px` (naive velocity-based sliding gets absurd at
## very light masses/high velocities -- see callers' own docs for why a cap
## is still needed even with a real formula underneath).
static func distance_px(velocity_mps: float, max_distance_px: float) -> float:
	if velocity_mps <= 0.0:
		return 0.0
	var distance_m := (velocity_mps * velocity_mps) / (2.0 * GROUND_FRICTION_COEFFICIENT * GRAVITY_MPS2)
	return clampf(distance_m * PX_PER_METER, 0.0, max_distance_px)
