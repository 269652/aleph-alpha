extends RefCounted

## How independent movement penalties compose into one multiplier.
##
## Everything that slows you used to be multiplied straight into one product:
## weather x slope x condition x crouch x water x spells, each a perfectly
## reasonable number on its own. Multiplied, they compound catastrophically.
## Measured against the real constants, six ordinary conditions at once left
## **2.5% of base speed** -- two pixels a second -- and a plausible crouched
## stalk in rain on a hill came out at 23%, which is not a stalk, it is a
## standstill. A live session recorded it as "the speed product is a hidden
## pass/fail line, and the HUD does not say so"
## (docs/playtests/2026-09-02-approach-and-substrate-session.md, finding 1).
##
## ## The model
##
## **You never move faster than your worst constraint allows, and additional
## constraints matter but not at full multiplicative force.** The result is
## interpolated between "the worst penalty alone" and "all of them multiplied",
## which gives the two bounds that make this a smoothing rather than a
## rebalance:
##
##   - a SINGLE penalty is completely unchanged, so every individual mechanic
##     still bites exactly as hard as its own author tuned it to;
##   - the composed result is never below the old product, so this can only
##     ever relieve compounding, never add to it.
##
## Real grounding: the metabolic cost of moving is dominated by its binding
## constraint. Wading through water while carrying an injury does not cost the
## product of the two -- the deeper limit sets the pace and the other adds to
## it. Independent multiplicative penalties are a bookkeeping convenience, not
## a description of how bodies move.

## How far toward the full product the composition travels once more than one
## penalty applies.
##
## At 0 only the worst constraint would count, and stacking would be free; at 1
## this is the old product and nothing is smoothed. Between them it is the one
## knob, and it is deliberately below the middle: several things going wrong at
## once should be worse than the worst of them, but not multiplicatively worse.
##
## Explicitly a placeholder pending real playtesting -- the same honesty
## convention Taming.PREDATOR_BREAK_FREE_MULTIPLIER's own doc comment uses.
## What the tests pin is not this number but the bracket around it.
const STACKING_BLEND := 0.35

## The slowest the player or a creature can ever be brought by penalties.
##
## A safety rail, not a balance knob: the same "debuffs, not death" rule the
## survival pillar states for every unmet need. It sits BELOW the harshest
## single penalty in the game (TerrainPassability.MIN_SPEED_MULTIPLIER), so it
## can only ever bind once penalties have compounded -- a mechanic's own tuning
## is never quietly overridden by it
## (test_the_floor_sits_below_any_single_penalty).
const FLOOR := 0.12


## One multiplier for a set of independent ones.
##
## Values at or above 1.0 are BONUSES (a worn path, see PathScarring) and
## compose straight: they are not constraints, and folding them into the
## worst-constraint logic would let a path cancel a mountainside.
static func compose(multipliers: Array) -> float:
	var worst := 1.0
	var product := 1.0
	var bonus := 1.0
	for value in multipliers:
		var multiplier := float(value)
		if multiplier >= 1.0:
			bonus *= multiplier
			continue
		multiplier = maxf(multiplier, 0.0)
		worst = minf(worst, multiplier)
		product *= multiplier
	return maxf(lerpf(worst, product, STACKING_BLEND), FLOOR) * bonus
