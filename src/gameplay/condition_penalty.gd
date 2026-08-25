extends RefCounted

## What poor overall CONDITION actually costs you (docs/concept/survival.md,
## "Debuffs, not death" / "What poor condition costs you").
##
## SurvivalMeters.fitness is already this game's single accumulator of
## survival neglect -- it falls while starving, while dehydrated and while
## cold, and recovers otherwise (SurvivalMeters.advance) -- but nothing read
## it, so hunger and thirst had no mechanical consequence at all and cold had
## only the separate freezing movement slow. This is the missing consumer:
## one pure fitness -> movement-multiplier curve, in the SAME "environment
## scales a movement multiplier" shape Player._weather_speed_multiplier and
## _terrain_speed_multiplier already use.
##
## Deliberately NOT damage and deliberately not a health cap: the doc's own
## pillar is explicit that unmet needs "never kill the player outright".
##
## Reading ONE accumulated number is also the honest first answer to the
## doc's open "exact debuff curve/stacking rules for compounding neglect"
## question -- hungry AND dehydrated AND cold at once already drive the same
## meter down, so they compound by construction instead of by an invented
## stacking matrix.

## The multiplier at rock-bottom condition. NOT a new eyeballed number: it is
## exactly the penalty this codebase already committed to for its one
## existing severe exposure debuff, the freezing movement slow, which now
## references this constant so there is a single definition (pinned by
## test_the_worst_penalty_is_the_same_magnitude_as_the_freezing_slow).
const WORST_SPEED_MULTIPLIER := 0.75


## Movement multiplier for `fitness` in [0,1]: 1.0 at full condition, falling
## linearly to WORST_SPEED_MULTIPLIER at zero. Never zero -- a neglected
## player is slow, never immobilised.
static func speed_multiplier(fitness: float) -> float:
	return lerpf(WORST_SPEED_MULTIPLIER, 1.0, clampf(fitness, 0.0, 1.0))
