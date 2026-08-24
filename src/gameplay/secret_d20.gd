extends RefCounted

## "A d20 in an otherwise dice-free game" (docs/concept/easter_eggs.md):
## this project deliberately has NO random rolls anywhere in its actual
## gameplay systems -- combat, crafting, and spellcasting are all fully
## deterministic by design (see materials.md, magic.md). This module is the
## ONE sanctioned exception: a single, secret, genuinely-random d20 roll
## that does something harmless and silly on a natural 20, and nothing at
## all otherwise (1-19 are all no-ops).
##
## ISOLATION IS THE WHOLE POINT: this is intentionally its own small,
## obviously-named module rather than a helper tucked into some shared
## utility file, specifically so it can never be mistaken for, or
## accidentally reused as, a general-purpose RNG source elsewhere in this
## project. Nothing else in this codebase should ever import SecretD20 or
## call roll() -- if some other system ever wants randomness, that is a
## deliberate, separate design decision, not something to bolt onto this
## file.
##
## roll() takes a caller-supplied RandomNumberGenerator rather than calling
## the engine's global randi()/randf() itself -- the same "caller supplies
## the real primitive, module only decides" shape every other Easter-egg
## module in this project uses for its own roll (compare EasterEggSightings/
## EasterEggCreatures/KrakenTrigger, which all take a caller-supplied
## roll: float). scenes/world.gd wires this to its own dedicated
## RandomNumberGenerator instance (named to make the "one narrow purpose"
## intent obvious at the call site too), never the ambient randf() the
## cameo-rarity checks already use elsewhere in this file.
##
## Findable "somewhere unlikely" per the doc: wired as an undocumented
## secret console command (scenes/world.gd's dispatcher, never listed in
## /help) -- the same "a player has to already be digging around to find
## it" register as the WarGames egg, reusing this project's existing
## "secret console command" trigger shape (mechanism #2 in the doc) rather
## than inventing a new discovery mechanic just for one die roll.

const SIDES := 20
const NATURAL_20 := 20

const NATURAL_20_MESSAGE := "The die skitters to a stop on 20. Somewhere, a stat sheet that doesn't exist gains a bonus that applies to nothing. You feel briefly, inexplicably lucky."


## One roll of a d20 (1..20 inclusive), using the caller-supplied `rng`.
func roll(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, SIDES)


## True only for the one special result a roll can land on.
func is_natural_20(value: int) -> bool:
	return value == NATURAL_20


## The harmless, silly payoff text for a natural 20 -- "" for every other
## result (the doc: "nothing at all otherwise").
func outcome_message(value: int) -> String:
	if not is_natural_20(value):
		return ""
	return NATURAL_20_MESSAGE
