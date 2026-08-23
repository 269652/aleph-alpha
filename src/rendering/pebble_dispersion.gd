extends RefCounted

## Pebble dispersion: walking close enough to a loose stone has a MASS-
## WEIGHTED CHANCE, rolled fresh on every contact, of kicking it a small
## distance further out of the way (see docs/concept/stone.md). Pure
## positional/probability math only -- no state, no node access -- same
## split as PathScarring (pure wear math) vs. the tile-detection loop in
## world.gd: "is a walker now near this pebble" and "did this particular
## contact's roll actually succeed" both live at the wiring edge
## (LiftableStone.try_disperse, World._step_pebble_dispersion).
##
## A nudge that DOES happen stays displaced rather than settling back -- real
## kicked gravel doesn't crawl home -- but unlike the old one-shot design, a
## stone is never permanently "used up": every later contact rolls again, so
## a stone can keep drifting further across many walkovers (see
## LiftableStone.try_disperse). Lighter stones roll a much better chance per
## contact than heavier ones -- an incidental footstep reliably disturbs a
## light pebble but only occasionally nudges a heavy cobble, exactly the same
## momentum-vs-own-mass logic as the (much bigger) deliberate Kick action,
## just at footstep scale.

## How close a walker must stand to a pebble to kick it. Small: this should
## read as "you walked right onto it", not "it flinches away as you
## approach" -- a pebble a couple of tile-widths off to the side should
## never react.
const TRIGGER_RADIUS_PX := 6.0

## How far a kick displaces a pebble. Comfortably more than a pebble's own
## drawn footprint (a pebble is roughly 3-4 world pixels across, see
## StoneSize.world_height_px for a small diameter) so the kick reads as a
## real, visible shove, and comfortably less than a tile (16px) so a kicked
## pebble still lands roughly where it was kicked from rather than teleporting
## into unrelated ground.
const NUDGE_DISTANCE_PX := 5.0


## Whether a walker standing at `walker_position` is close enough to
## `pebble_position` to kick it.
static func is_within_trigger(walker_position: Vector2, pebble_position: Vector2) -> bool:
	return walker_position.distance_to(pebble_position) <= TRIGGER_RADIUS_PX


## Where the pebble ends up after being kicked: pushed directly away from the
## walker by exactly NUDGE_DISTANCE_PX. Reads as "shoved out from underfoot"
## regardless of which direction the walker approached from. Falls back to a
## fixed direction if the walker is standing exactly on the pebble (no
## meaningful "away" to compute otherwise) -- it still has to go somewhere.
static func nudge(walker_position: Vector2, pebble_position: Vector2) -> Vector2:
	var away := pebble_position - walker_position
	if away.length() < 0.001:
		away = Vector2.RIGHT
	return pebble_position + away.normalized() * NUDGE_DISTANCE_PX


# -- mass-weighted dispersion chance ------------------------------------------
#
# Same momentum-vs-own-mass logic as the (much bigger) deliberate Kick
# action, just modelled at footstep scale: a footstep delivers a small real
# momentum, and whether that is enough to nudge a given stone depends on the
# stone's own mass. Modelled as just the FOOT (not the whole leg -- an
# incidental brush against a stone underfoot, not a deliberate swing)
# travelling at ordinary walking pace.

const StoneSize = preload("res://src/world/stone_size.gd")

## Average human walking speed, metres/second -- a commonly cited figure is
## roughly 5 km/h (~1.4 m/s); used here as the speed the foot itself is
## moving at during an ordinary stride, not a deliberate kick swing (compare
## Kick.KICK_SPEED_MPS, which is deliberately faster).
const FOOTSTEP_SPEED_MPS := 1.4

## What fraction of total body mass a single FOOT (not the whole leg) is, per
## real anthropometric segment-mass tables (e.g. Winter's "Biomechanics and
## Motor Control of Human Movement": the foot segment alone is roughly 1.4%
## of total body mass, well under LEG_MASS_FRACTION's whole-leg 16.5%,
## because an incidental footstep brushes a stone with just the foot, not
## the full swinging leg).
const FOOT_MASS_FRACTION := 0.014

## One foot's real mass, kilograms -- FOOT_MASS_FRACTION of
## StoneSize.AVERAGE_BODY_MASS_KG, the same reference body mass LEG_MASS_KG
## is built from.
const FOOT_MASS_KG := StoneSize.AVERAGE_BODY_MASS_KG * FOOT_MASS_FRACTION

## The real momentum (mass x velocity) an ordinary footstep delivers to
## whatever it brushes -- the same momentum framing docs/concept/materials.md
## uses everywhere else (impact_resolver.gd, throwable.gd).
const FOOTSTEP_MOMENTUM_KG_M_S := FOOT_MASS_KG * FOOTSTEP_SPEED_MPS

## The most a single contact can ever be worth, even for an almost-weightless
## stone -- kept below certainty so even the lightest pebble doesn't nudge on
## literally every single footfall (an incidental brush glances unpredictably
## depending on exact foot placement). See
## test_dispersion_chance_is_at_the_max_for_a_near_weightless_stone.
const MAX_DISPERSION_CHANCE_PER_CONTACT := 0.6

## The least a single contact is ever worth, even for the heaviest liftable
## stone (a cobble at the lift/smash ceiling) -- never truly zero, since a
## footstep's force still varies contact to contact, but close to it. See
## test_dispersion_chance_is_at_the_floor_for_a_very_heavy_stone.
const MIN_DISPERSION_CHANCE_PER_CONTACT := 0.05


## The probability that ONE contact with a stone of this mass actually nudges
## it -- rolled fresh by the caller on every contact (see
## LiftableStone.try_disperse), not gated behind a one-time lifetime flag.
## `FOOTSTEP_MOMENTUM_KG_M_S / (FOOTSTEP_MOMENTUM_KG_M_S + mass_kg)` is the
## same "delivered momentum vs. the target's own mass" ratio the rest of the
## shared damage model reads as a threshold (see docs/concept/materials.md) --
## here read as a smooth probability instead of a hard cutoff, clamped to
## MIN/MAX_DISPERSION_CHANCE_PER_CONTACT at either end.
static func dispersion_chance(mass_kg: float) -> float:
	var momentum_ratio := FOOTSTEP_MOMENTUM_KG_M_S / (FOOTSTEP_MOMENTUM_KG_M_S + maxf(mass_kg, 0.0))
	return clampf(momentum_ratio, MIN_DISPERSION_CHANCE_PER_CONTACT, MAX_DISPERSION_CHANCE_PER_CONTACT)
