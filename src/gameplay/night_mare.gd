extends RefCounted
## The Alp (docs/concept/monsters.md, entry 3) -- the night-mare.
##
## The roster's own statement of its one behaviour: *"it is only dangerous
## while you are not. It cannot be hit while you are standing; it approaches
## only while you rest and drains stamina rather than health. Waking is the
## counterplay, and the cost of waking is the rest you lose."*
##
## This was the roster's one BLOCKED entry. Its whole behaviour hangs off a
## sleep state, and `SurvivalMeters.rest(amount)` was an arithmetic helper
## rather than a condition -- there was nothing to attach to until
## docs/concept/sleep.md built one.
##
## It is the exact inverse of every other creature in this game, which is
## why it gets a rule of its own rather than a temperament: everything else
## is dangerous while you act, and this is dangerous while you do not.
##
## The word *nightmare* is this creature. It sits on a sleeper's chest and
## presses -- so what it takes is the rest itself, never health. A monster
## that killed you in your sleep would be a death with no counterplay; one
## that empties the bar you were sleeping to fill is a decision, because
## waking is always available and always costs you the night.
##
## Pure: RefCounted, static functions, no world, no creature, no scene tree
## -- and deliberately no way to reach for health, which a reflection test
## over this script's own method list keeps true.

const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")

## The one creature this rule is about. Named here so the pure rule can
## answer questions about it without a caller having to say which species
## it means; `CreatureMarker.ALP_SPECIES` is pinned to this by test.
const SPECIES := "alp"

## Night, by the same definition everything else in this game uses: the sun
## below civil twilight. Restated from `WitnessConditions` rather than
## preloaded (both are leaf rules and neither should depend on the other)
## and held to it by test, so "dark" is one fact.
const DARK_BELOW_SUN_ELEVATION_DEG := -6.0

## How long its pressing takes to empty a full stamina bar.
##
## Stated against the bar it empties rather than as a damage figure: this is
## the same meter `SprintCost` spends, and a night-mare that took a whole
## night to matter would be scenery while one that emptied it in a breath
## would give a sleeper nothing to wake up to. Long enough to notice the bar
## moving, short enough that sleeping through it is a real loss -- both ends
## pinned by test.
const SECONDS_TO_EMPTY_A_FULL_BAR := 20.0

## The drain per second, a consequence of the figure above rather than a
## second opinion about it.
const STAMINA_PER_SECOND := 1.0 / SECONDS_TO_EMPTY_A_FULL_BAR


## Whether this is its moment: a sleeper, in the dark.
##
## Both halves are required and neither is negotiable. A waking character is
## simply not its prey -- it is the only creature in the game that a player
## becomes safe from by standing up -- and a daylight nap is not its hour,
## because the word is night-mare.
##
## A missing fact is not an invitation: a caller with nothing wired reports
## nothing rather than conjuring a monster.
static func preys_on(facts: Dictionary) -> bool:
	return bool(facts.get("resting", false)) and bool(facts.get("dark", false))


## Whether it is dark enough for it, from the sun the world is drawing.
static func is_dark(sun_elevation_deg: float) -> bool:
	return sun_elevation_deg < DARK_BELOW_SUN_ELEVATION_DEG


## Whether `species` harms by PRESSING rather than by striking.
##
## The Alp is the only one, and it is the whole of what it is. An ordinary
## bite from it would not be a stronger version of its mechanic -- it would
## be the END of it, because `Player.take_damage` wakes a sleeper and a
## woken character is not its prey any more. So the creature that raises
## its own aggro to approach a sleeper must never reach the attack path it
## shares with every animal that does hunt.
##
## A rule rather than a species check at the call site: the reason lives
## here with the rest of what this creature is, and a second night-mare
## added later inherits it instead of re-deriving it.
static func presses_instead_of_striking(species: String) -> bool:
	return species == SPECIES


## One step of it sitting on a sleeper's chest.
##
## Takes the meters directly and spends through their own `spend_stamina`,
## so the bar it empties is the real one and there is no separate accounting
## of what a sleeper has left.
static func press(meters: SurvivalMeters, delta_seconds: float) -> void:
	if meters == null or delta_seconds <= 0.0:
		return
	meters.spend_stamina(STAMINA_PER_SECOND * delta_seconds)
