extends RefCounted

## Pure flight math for a homing projectile cast (docs/concept/
## spell_runtime.md, "Projectile flight: a cast that truly homes"). Mirrors
## spell_targeting.gd's own pure, instance-based shape -- testable without a
## scene tree or physics.
##
## True homing, the simple and correct form of it: position_after takes a
## FRESH aim point every call rather than storing a heading anywhere. There
## is no separate steering/turn-rate model -- recomputing the direction from
## scratch each call against wherever the target currently is already
## produces a path that curves to follow it, which is the whole mechanism.

## Faster than SpeciesBite.FASTEST_PURSUIT_TILES_PER_SECOND (the fastest any
## creature in this roster can move, itself already pinned faster than
## player sprint) converted to px/s at TerrainRenderer.TILE_SIZE -- by a wide
## enough margin that a bolt can never lose a fleeing target to raw speed,
## and crossing SpellTargeting.PROJECTILE_RANGE still stays well under half
## of Player.ATTACK_COOLDOWN's own pace. Both ends pinned by
## test_spell_projectile_flight.gd, not eyeballed.
const TRAVEL_SPEED_PX_PER_SEC := 500.0


## One frame's step from `current` toward `aim_at`, at TRAVEL_SPEED_PX_PER_SEC.
## Snaps exactly to `aim_at` rather than overshooting past it when the
## remaining distance is less than this step's own length -- the arrival
## condition (has_arrived) is then a plain equality check, no separate
## epsilon tuning anywhere.
func position_after(current: Vector2, aim_at: Vector2, delta: float) -> Vector2:
	var to_aim := aim_at - current
	var step := TRAVEL_SPEED_PX_PER_SEC * delta
	if to_aim.length() <= step:
		return aim_at
	return current + to_aim.normalized() * step


func has_arrived(current: Vector2, aim_at: Vector2) -> bool:
	return current == aim_at
