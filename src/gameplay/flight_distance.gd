extends RefCounted

## How close the player gets before an animal breaks (see
## docs/concept/animal_husbandry.md "The approach").
##
## `CreatureMarker.SENSE_RADIUS` is ONE constant, 80 px, for every creature in
## the world. A mouse and a horse therefore react identically, nothing the
## player does changes it, and the only way inside it is to be faster than the
## animal -- which, on an ordinary wet afternoon, the player is not (the live
## session that produced this module measured HUD speeds of 23-75% against a
## fleeing animal's effective 50%).
##
## This is its replacement for the PLAYER half of that radius. Creature-vs-
## creature sensing is untouched: a wolf does not care whether the deer trusts
## anyone.
##
## **One owner, one signature.** Every doc that needs a flight radius calls
## this; none defines a second. `taming.md` explains what earning `trust`
## MEANS; this file decides what trust DOES.
##
## Two channels, because a real animal has two, and they do different things:
##
##   SIGHT decides FLIGHT -- `radius()` below, composed from body size, how
##   rattled the individual is, how much it trusts the player, and whether they
##   are crouched. Inside it, the animal runs.
##
##   SMELL decides WARINESS -- `smells_player()`, which reaches further than
##   sight and is stretched downwind / squashed upwind by the caller (see
##   WindScent). Catching the player's scent does NOT make an animal bolt; the
##   caller feeds it to `Wariness.after_scent`, which widens this same radius.
##   Keeping it that way is what leaves this file the single owner of "when
##   does this animal run", and it is the truer behaviour: a deer that catches
##   your scent across a meadow does not sprint, it stops trusting the meadow.
##
## Pure and engine-free. Gathering the inputs and acting on the answer is the
## caller's job (see CreatureMarker).

const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")


# -- the species term --------------------------------------------------------

## Flight-initiation distance genuinely scales with body size in the field
## literature: a larger prey animal is visible further off, is worth more to a
## predator, and breaks sooner. So the species term is read from
## `AnimalAnatomy.profile_for(species)["world_scale"]` -- the SAME number that
## decides how big the animal is drawn -- rather than from a second
## hand-authored size table that could drift away from the art.

## The radius for the smallest body on the roster (a mouse, world_scale 0.35).
const SPECIES_MIN_RADIUS := 52.0

## ...and for anything at or above SCALE_SATURATION.
const SPECIES_MAX_RADIUS := 88.0

## The world_scale at which the curve tops out. Above this an animal is simply
## "large"; a kraken does not flee twice as early as a bear.
##
## Set so a HORSE (world_scale 1.2) lands just above the flat 80 px
## `CreatureMarker.SENSE_RADIUS` this replaces. That is deliberate calibration
## rather than coincidence: the big animals keep behaving as they always did,
## and the change is felt as small animals letting the player much closer --
## which is the direction that opens play up rather than taking it away.
const SCALE_SATURATION := 1.5

## Ceiling on everything below. `CreatureMarker.FLEE_RELEASE_RADIUS` is 120,
## and fleeing is a Schmitt trigger: entered at the flight radius, released out
## there. If a composed radius crept up to the release radius the trigger would
## invert and the measured dithering bug would come straight back, so the
## composition is capped with a real gap left below it -- pinned by
## test_a_graded_flight_radius_never_dithers, the single owner of that
## invariant, and by test_the_ceiling_leaves_a_real_schmitt_gap.
##
## It only ever binds on the largest bodies, where the species term is already
## saturated anyway; a sheep or a deer never reaches it, spooked or not.
const MAX_RADIUS := 100.0


# -- the modifiers -----------------------------------------------------------

## How much a fully spooked animal widens its own radius (see Wariness).
const WARINESS_WIDENING := 0.35

## What a fully trusting animal's radius shrinks to. Never zero: even a tame
## horse has a personal space, and a tamed animal stops treating the player as
## a threat by a different route entirely (see CreatureMarker).
const TRUST_FLOOR := 0.25

## What crouching multiplies the radius by. The stalk's whole payoff.
const CROUCH_MULTIPLIER := 0.55

## What crouching costs, as a fraction of an ordinary walking pace. Without a
## cost, crouching is a free permanent state and there is no decision in it.
const CROUCH_SPEED_MULTIPLIER := 0.45


# -- the shy threshold -------------------------------------------------------

## The approach speed above which the player reads as a RUSH regardless of
## bait, crouch or trust: the flight response is not suppressed at all, and a
## hand-offered treat is refused.
##
## Not an eyeballed number of pixels per second -- it is pinned by ORDERING
## against constants that already exist: strictly above a crouched pace
## (`Player.BASE_SPEED * CROUCH_SPEED_MULTIPLIER`, 36 px/s), at or below an
## ordinary walk (`Player.BASE_SPEED`, 80 px/s), and therefore far below
## `Taming.MOUNTED_SPEED` (150 px/s) -- so riding a horse up to a wild sheep can
## never work, which today it silently might.
const SHY_SPEED := 56.0


## Whether moving at this speed reads as a rush to any animal, whatever else
## the player is doing right.
static func is_a_rush(speed_px_per_second: float) -> bool:
	return absf(speed_px_per_second) > SHY_SPEED


## The radius, in world pixels, inside which this animal breaks and runs.
##
## `wariness` and `trust` are both 0..1. `wariness` multiplies it UP (see
## Wariness), `trust` multiplies it DOWN (see Taming), and a crouch multiplies
## it down again.
static func radius(species: String, wariness: float, trust: float, crouched: bool) -> float:
	var base := species_radius(species)
	var spook := 1.0 + WARINESS_WIDENING * clampf(wariness, 0.0, 1.0)
	var familiarity := lerpf(1.0, TRUST_FLOOR, clampf(trust, 0.0, 1.0))
	var stance := CROUCH_MULTIPLIER if crouched else 1.0
	return minf(base * spook * familiarity * stance, MAX_RADIUS)


## The species term alone: what an unrattled, untrusting animal of this species
## allows a standing player. An unknown id gets the generic grazer's build (the
## same fallback `AnimalAnatomy.profile_for` already makes), so a species added
## without a profile is merely ordinary rather than fearless.
static func species_radius(species: String) -> float:
	var scale := float(AnimalAnatomy.profile_for(species).get("world_scale", 1.0))
	var t := clampf(scale / SCALE_SATURATION, 0.0, 1.0)
	return lerpf(SPECIES_MIN_RADIUS, SPECIES_MAX_RADIUS, t)


# -- the smell channel -------------------------------------------------------

## How loud the player's musk has to be before an animal treats it as a threat.
##
## Tuned as a RELATIONSHIP, not a number: at this value a keen-nosed grazer
## smells a standing player from roughly one and a half times its own flight
## radius in still air, so smell is the channel that reaches first -- and the
## wind then swings that either well beyond sight (downwind) or well inside it
## (upwind), which is the entire reason to care which way you approach from.
const MUSK_ALARM_STRENGTH := 0.5

## ...and how faint it has to get before an already-uneasy animal stops
## smelling them. Strictly below MUSK_ALARM_STRENGTH: the same Schmitt gap
## `CreatureMarker.FLEE_RELEASE_RADIUS` gives the sight channel, expressed in
## strength instead of distance, so an animal parked exactly at the alarm
## threshold cannot flicker in and out of being alarmed -- and therefore cannot
## flicker its own flight radius, which is what the alarm actually drives.
const MUSK_RELEASE_STRENGTH := 0.3


## Whether this species can smell the player at `effective_distance_tiles`.
##
## The distance is EFFECTIVE, not geometric: the caller passes the
## wind-adjusted distance (see `WindScent.effective_distance_tiles`), which is
## shorter than the real gap when the animal is downwind of the player and much
## longer when it is upwind. Keeping the wind out of this function is what lets
## the same call serve a still-air test and a live gale.
##
## `already_alarmed` selects the release threshold, so the caller passes
## whatever it uses for "is this animal already fleeing".
static func smells_player(
	species: String, effective_distance_tiles: float, already_alarmed: bool = false
) -> bool:
	if not Olfaction.has_nose(species):
		return false
	var strength := Olfaction.perceived_strength(
		species, Olfaction.PLAYER_MIXTURE, effective_distance_tiles
	)
	var threshold := MUSK_RELEASE_STRENGTH if already_alarmed else MUSK_ALARM_STRENGTH
	return strength >= threshold
