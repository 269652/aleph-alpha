extends RefCounted

## Kick: a deliberate one-time momentum delivered to the nearest liftable
## stone within reach (see docs/concept/stone.md, bound to K --
## Keybindings). Reuses the SAME momentum model as impact_resolver.gd/
## throwable.gd (momentum = mass * velocity, docs/concept/materials.md's
## "one damage model for the whole world") rather than a parallel physics
## system: the "leg" (StoneSize.LEG_MASS_KG) delivers momentum at a real
## kick-swing speed, and how far a stone flies falls out of that momentum
## vs. the stone's OWN mass -- exactly Throwable.impact_knockback's own
## reasoning, just applied to a stone instead of a thrown item.
##
## Only pebbles (and the lightest cobbles) are kickable, by design: a stone
## at or above LEG_MASS_KG is too heavy for a kick's delivered momentum to
## meaningfully move at all (the user's explicit cutoff) -- most cobbles and
## every boulder sit above that line already (a cobble at the very top of
## its range, ~25.6cm, already masses more than a leg), so this single mass
## cutoff naturally excludes them with no separate per-class check needed.

const StoneSize = preload("res://src/world/stone_size.gd")
const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## A brisk, deliberate kick swing -- well below an athletic punt (20+ m/s)
## but clearly faster than FOOTSTEP_SPEED_MPS's casual walking pace (see
## PebbleDispersion), since a kick is a purposeful action, not an incidental
## brush. Roughly triple walking pace.
const KICK_SPEED_MPS := 4.0

## The real momentum (mass x velocity) a deliberate kick delivers -- the
## same "leg" mass reference as the kick-cutoff itself, at kick-swing speed
## rather than footstep speed.
const KICK_MOMENTUM_KG_M_S := StoneSize.LEG_MASS_KG * KICK_SPEED_MPS

## Real gravitational acceleration, m/s^2 -- re-exported from GroundSlide so
## existing callers/tests that read Kick.GRAVITY_MPS2 keep working; the
## VALUE lives in one place (GroundSlide), shared with the held-item throw.
const GRAVITY_MPS2 := GroundSlide.GRAVITY_MPS2

## A typical kinetic friction coefficient for rock sliding across packed
## earth/grass -- see GroundSlide's own doc comment; re-exported here for
## the same reason as GRAVITY_MPS2 above.
const GROUND_FRICTION_COEFFICIENT := GroundSlide.GROUND_FRICTION_COEFFICIENT

## World pixels per real metre -- see GroundSlide's own doc comment;
## re-exported here for the same reason as GRAVITY_MPS2 above.
const PX_PER_METER := GroundSlide.PX_PER_METER

## The furthest a kick can ever send a stone, however light -- naive
## momentum conservation (v = p/m) sends a near-weightless pebble to an
## absurd velocity, so this caps the real-world kinematics formula at a
## still-satisfying but sane in-game distance: about four tiles (TILE_SIZE
## 16px), a clearly visible, deliberate shove rather than a teleport.
const MAX_KICK_DISTANCE_PX := 64.0


## Whether a stone of this mass can be kicked at all. AT OR ABOVE leg mass,
## a kick's delivered momentum can't meaningfully move it -- the user's
## explicit design (see the module's own doc comment).
static func is_kickable(mass_kg: float) -> bool:
	return mass_kg < StoneSize.LEG_MASS_KG


## How far a kick sends a stone of this mass, in world pixels. Real
## kinematics: the kick delivers KICK_MOMENTUM_KG_M_S, so the stone leaves
## at velocity_after = momentum / mass (heavier stone = lower exit velocity,
## exactly Throwable.impact_knockback's momentum-vs-mass reasoning); a
## sliding object under constant kinetic friction covers
## distance = velocity^2 / (2 * mu * g) before friction stops it -- the
## standard stopping-distance kinematics equation. Clamped to
## MAX_KICK_DISTANCE_PX (see its own doc comment on why the raw formula
## alone isn't sane for a near-weightless stone).
static func kick_distance_px(mass_kg: float) -> float:
	if mass_kg <= 0.0:
		return MAX_KICK_DISTANCE_PX
	var velocity_after := KICK_MOMENTUM_KG_M_S / mass_kg
	return GroundSlide.distance_px(velocity_after, MAX_KICK_DISTANCE_PX)


## Where a stone of this mass ends up after being kicked from `kicker_
## position`: pushed directly away by kick_distance_px(mass_kg) -- same
## "shoved out from underfoot" shape as PebbleDispersion.nudge, just with a
## mass-derived distance instead of a fixed one. Falls back to a fixed
## direction if the kicker is standing exactly on the stone (no meaningful
## "away" to compute otherwise) -- it still has to go somewhere.
static func landing_position(kicker_position: Vector2, stone_position: Vector2, mass_kg: float) -> Vector2:
	var away := stone_position - kicker_position
	if away.length() < 0.001:
		away = Vector2.RIGHT
	return stone_position + away.normalized() * kick_distance_px(mass_kg)
