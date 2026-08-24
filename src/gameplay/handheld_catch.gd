extends RefCounted

## Pure catch/collection mechanic for docs/concept/easter_eggs.md's "hidden
## retro handheld" entry: a "deterministic (seed-derived, not random) success
## chance based on a defeated creature's remaining health fraction" per this
## stage's own task -- mirroring this project's other deterministic-from-
## seed systems (CreatureInfo's own `level = 1 + (absi(seed_value) %
## LEVEL_RANGE)`) rather than a dice roll. Never calls randf() -- the same
## (remaining_health_fraction, seed_value) pair always produces the exact
## same outcome, reproducibly.
##
## Deliberately separate from HandheldBattle -- catching is something
## HandheldBattleView offers the player INSTEAD of a battle move (see that
## module's own doc comment); this file never touches battle state at all,
## only the two pure questions "how likely" and "did this attempt succeed".
##
## In real play, HandheldBattleView derives `seed_value` from something that
## changes between attempts on the same encounter (e.g. hash("%s_%d" %
## [enemy_species, attempt_count])) -- a plain deterministic hash of
## already-known identity, the same "hash real, already-known inputs, never
## randf()" idiom CreatureRenderer's own wander_seed/species_seed already
## use, not this module's own concern.

## Chance to catch at full health (remaining_health_fraction == 1.0) -- a
## slim chance always exists, even against an undamaged creature. First-pass
## placeholder, no real playtesting data yet (same situation as every other
## tuned constant in this doc's family), pinned by test_handheld_catch.gd's
## own exact-value assertions.
const BASE_CATCH_CHANCE := 0.05
## How much additional chance is earned as remaining_health_fraction falls
## all the way to 0.0 -- catch_chance(0.0) == BASE_CATCH_CHANCE +
## MAX_CATCH_BONUS. Kept below (1.0 - BASE_CATCH_CHANCE) is not required by
## anything below; catch_chance clamps its own output to [0, 1] regardless.
const MAX_CATCH_BONUS := 0.90


## Linear: full health is hardest to catch (BASE_CATCH_CHANCE alone), and
## chance rises toward BASE_CATCH_CHANCE + MAX_CATCH_BONUS as
## remaining_health_fraction falls toward 0.0. Clamped to [0, 1] so a
## caller passing an out-of-[0,1]-range fraction (e.g. a slight negative
## from float rounding at exactly 0 hp) never produces a nonsense chance.
func catch_chance(remaining_health_fraction: float) -> float:
	var raw := BASE_CATCH_CHANCE + (1.0 - remaining_health_fraction) * MAX_CATCH_BONUS
	return clampf(raw, 0.0, 1.0)


## True if this exact (remaining_health_fraction, seed_value) pair clears
## the catch_chance threshold -- deterministic, not a coin flip: the same
## pair always returns the same bool.
func attempt_catch(remaining_health_fraction: float, seed_value: int) -> bool:
	return _seeded_roll(seed_value) < catch_chance(remaining_health_fraction)


## A deterministic pseudo-"roll" in [0, 1) derived from `seed_value` -- never
## Godot's RandomNumberGenerator/randf(), the same "looks varied, is actually
## a pure hash of its input" idiom PixelNoise already uses for this
## project's procedural art. absi() first, since GDScript's `%` on a
## negative int can itself return a negative remainder.
func _seeded_roll(seed_value: int) -> float:
	return float(absi(seed_value) % 1000) / 1000.0
