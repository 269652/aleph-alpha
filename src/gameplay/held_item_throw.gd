extends RefCounted

## The release half of hold-E-to-charge-then-release (see docs/concept/
## stone.md's held-item pickup/throw mechanism, ChargeMeter's own doc
## comment for the bounce logic behind `power_fraction`). Maps the charge
## meter's release power to a real throw speed, feeding the SAME momentum
## model (Throwable.impact_knockback, docs/concept/materials.md) and the
## SAME real sliding kinematics (GroundSlide) Kick already uses -- not a
## parallel physics system.
##
## Judgment call, documented rather than guessed at silently: flight
## DISTANCE is modeled from release speed alone (how hard the throw was),
## not divided by the thrown item's own mass the way Kick's
## foot-delivers-a-fixed-momentum model is. A thrown item is actively swung
## by the player at whatever speed the charge meter dictates, not a passive
## object receiving an external momentum transfer the way a kicked stone is
## -- so speed, not momentum-vs-mass, is what determines how far the arm
## sends it. Momentum (mass x release speed, via Throwable.impact_knockback)
## is still what should feed impact/damage on landing.

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## A weak, barely-charged toss -- a soft underhand release.
const MIN_THROW_SPEED_MPS := 2.0

## A fully-charged, deliberate overhand throw -- well below an athletic
## pitch (a baseball fastball is ~40 m/s) but a clearly forceful release.
const MAX_THROW_SPEED_MPS := 8.0

## The furthest a full-power throw can ever send something -- comfortably
## further than Kick.MAX_KICK_DISTANCE_PX (a deliberate arm throw should
## outreach an incidental foot kick), but still a bounded, sane in-game
## distance rather than an unbounded launch.
const MAX_THROW_DISTANCE_PX := 96.0


## The real throw speed for a release at `power_fraction` (see
## ChargeMeter.fraction_at) -- linear between MIN/MAX_THROW_SPEED_MPS,
## clamped so an out-of-range fraction can't produce a speed outside the
## documented bounds.
static func release_speed_mps(power_fraction: float) -> float:
	var clamped := clampf(power_fraction, 0.0, 1.0)
	return lerpf(MIN_THROW_SPEED_MPS, MAX_THROW_SPEED_MPS, clamped)


## How far a release at `power_fraction` sends the thrown item, via the same
## real sliding kinematics Kick uses (GroundSlide), driven by release speed
## alone (see the module's own doc comment on why mass isn't a factor here).
static func throw_distance_px(power_fraction: float) -> float:
	return GroundSlide.distance_px(release_speed_mps(power_fraction), MAX_THROW_DISTANCE_PX)
