extends RefCounted

## Open wounds: the slow half of being hurt (docs/concept/survival.md, "The
## four triggers" -> "Open wounds, not just HP"; docs/concept/olfaction.md,
## "Blood: the trail a wounded animal leaves").
##
## A gash on the player and a gash on a deer are mechanically the same real
## thing, so one model answers both -- how much a wound bleeds, what it costs
## to move with, and when an unbound one turns septic. That is the honest
## answer to this project's own earlier open question about whether a combat
## gash and a butchering cut should be the same mechanic.
##
## Shaped exactly like VenomModel: a per-stack `*_per_second` rule sitting over
## the generic DebuffStack, which owns the actual stacking state. Deliberately
## NOT a bespoke module holding its own severity -- venom and wounds then
## compose in one stack instead of running as two parallel damage systems.
##
## Supersedes `wounds.gd`, which predates this spec, holds its own severity
## rather than riding the stack, and heals itself at five times the rate it
## bleeds -- so a wound there lasted about two seconds and cost about a fifth
## of a hit point. It has never had a production caller.

const DEBUFF_ID := "wound"

## How long a wound takes to clot on its own, and how many can be open at once.
##
## Long against VenomModel.DURATION_SECONDS, and that ordering is the point
## rather than the numbers: venom is a dose that is survived or not within
## seconds, a gash is something you carry around. Pinned by
## test_a_wound_bleeds_slower_and_lasts_longer_than_venom.
const DURATION_SECONDS := 45.0
const MAX_STACKS := 3

## What one open wound costs per second. Below venom's own rate, for the same
## reason: the wound is the threat you have time to do something about.
const DAMAGE_PER_SECOND_PER_STACK := 0.4

## The smallest blow that opens a real wound rather than only taking health.
## Every scratch leaving a bleeding gash would make this noise rather than a
## threat -- the doc's own wording is "a hit above a real damage threshold".
const MIN_DAMAGE_TO_WOUND := 8.0

## What a wound costs in speed, per open wound.
##
## This is the constant that makes tracking worth doing: the trail is only
## worth following because the thing at the end of it is catchable. Real --
## blood loss is a genuine performance cost long before it is fatal, and it is
## why a hunted animal is followed rather than outrun. Never enough to
## immobilise, the same "debuffs, not death" rule ConditionPenalty follows.
const SPEED_PENALTY_PER_STACK := 0.12
const WORST_SPEED_MULTIPLIER := 0.5

## How long an unbound wound takes to become an infection risk.
##
## A duration, not an event: a wound is not infected the moment it is opened,
## and real wound sepsis is precisely a thing that develops in one left
## untreated. Deliberately longer than DURATION_SECONDS
## (test_a_wound_clots_before_it_turns_septic) so a wound simply left alone
## clots in time -- otherwise every wound would go septic and bandaging would
## be the only legal move rather than the good one.
const SECONDS_UNTIL_SEPSIS := 120.0

## The exposure a wound carries the moment it crosses SECONDS_UNTIL_SEPSIS,
## and the cap it climbs to with continued neglect.
##
## A floor rather than a ramp from zero -- unlike ColdExposure's staging
## boundary, which separates a harmless stage from a dangerous one. Here the
## threshold IS the onset: a wound that has been open past the sepsis window is
## already at risk, and naming a moment at which nothing yet happens would make
## SECONDS_UNTIL_SEPSIS a label rather than a clock
## (test_leaving_a_wound_unbound_eventually_risks_infection). Never 1.0: an
## untreated wound is dangerous, not certain death.
const MIN_INFECTION_EXPOSURE := 0.25
const MAX_INFECTION_EXPOSURE := 0.9

## The health a bleeding animal will not drop below. Bleeding is what lets you
## CATCH the animal, not what kills it for you -- the same "debuffs, not death"
## rule ConditionPenalty follows for the player, and the reason a wounded deer
## left alone recovers rather than quietly dying off-screen.
const BLEED_HEALTH_FLOOR := 1.0

## The sickness an untreated wound causes. A player sickness id (see
## Player.sickness_id), not one of DiseaseModel's wildlife SIRS archetypes:
## sepsis has no reservoir and no transmission, it is your own wound doing it.
const SICKNESS_ID := "wound_infection"


## Health lost per second to `stacks` open wounds.
static func damage_per_second(stacks: int) -> float:
	return float(clampi(stacks, 0, MAX_STACKS)) * DAMAGE_PER_SECOND_PER_STACK


## Whether a blow of `damage` opens a wound at all.
static func opens_a_wound(damage: float) -> bool:
	return damage >= MIN_DAMAGE_TO_WOUND


## Movement multiplier for `stacks` open wounds -- the same "environment scales
## a movement multiplier" shape ConditionPenalty and Player's weather/terrain
## multipliers already use, so this composes with them rather than competing.
static func speed_multiplier(stacks: int) -> float:
	var penalty := float(maxi(stacks, 0)) * SPEED_PENALTY_PER_STACK
	return maxf(1.0 - penalty, WORST_SPEED_MULTIPLIER)


## What to hand Sickness.infection_chance as its `exposure_level` for a wound
## that has been open `seconds_unbound` seconds.
##
## Zero until the clock has run, then rising with continued neglect -- the same
## shape ColdExposure uses for the prolonged-cold trigger, because they are the
## same kind of claim: a duration effect, not an event.
static func infection_exposure(seconds_unbound: float) -> float:
	if seconds_unbound < SECONDS_UNTIL_SEPSIS:
		return 0.0
	var overdue := (seconds_unbound - SECONDS_UNTIL_SEPSIS) / SECONDS_UNTIL_SEPSIS
	return lerpf(MIN_INFECTION_EXPOSURE, MAX_INFECTION_EXPOSURE, clampf(overdue, 0.0, 1.0))
