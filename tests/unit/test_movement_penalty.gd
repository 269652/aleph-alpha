extends GutTest

## How independent movement penalties compose (see docs/concept/survival.md's
## "Debuffs, not death", and the playtest finding this closes).
##
## Everything that slows you used to be multiplied straight into one product:
## weather x slope x condition x crouch x water x spells. Measured against the
## real constants, six ordinary conditions at once left **2.5% of base speed**
## -- two pixels a second -- and even a plausible crouched stalk in rain on a
## hill came out at 23%. A live session recorded it as "the speed product is a
## hidden pass/fail line, and the HUD does not say so".
##
## The model here: you never move faster than your WORST constraint allows,
## and additional constraints matter but not at full multiplicative force.

const MovementPenalty = preload("res://src/gameplay/movement_penalty.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")


func _product(multipliers: Array) -> float:
	var total := 1.0
	for m in multipliers:
		total *= m
	return total


# -- the bounds that make it a smoothing rather than a rebalance -------------


func test_nothing_wrong_means_full_speed():
	assert_eq(MovementPenalty.compose([]), 1.0)
	assert_eq(MovementPenalty.compose([1.0, 1.0]), 1.0)


## One penalty on its own is completely unchanged. This is what makes the pass
## a SMOOTHING rather than a rebalance: every individual mechanic still bites
## exactly as hard as its own author tuned it to.
func test_a_single_penalty_is_untouched():
	for m in [0.85, 0.65, 0.5, 0.3]:
		assert_almost_eq(MovementPenalty.compose([m]), m, 0.0001)


## You are never faster than your worst constraint allows -- a steep slope is a
## steep slope whatever else is true.
func test_you_are_never_faster_than_your_worst_constraint():
	var multipliers := [0.85, 0.6, 0.45]
	assert_lte(MovementPenalty.compose(multipliers), 0.45)


## ...and never slower than multiplying them all would have been. The composed
## result is bracketed BETWEEN the two, which is exactly what "smoothing" means
## here: it can only ever relieve the compounding, never add to it.
func test_you_are_never_slower_than_the_old_product():
	for multipliers in [[0.85, 0.6], [0.65, 0.3, 0.75], [0.65, 0.75, 0.3, 0.75, 0.45, 0.5]]:
		assert_gte(MovementPenalty.compose(multipliers), _product(multipliers))


# -- and it still has to behave like a penalty -------------------------------


## More things wrong is still slower. Smoothing must not mean ignoring.
func test_more_wrong_is_still_slower():
	assert_lt(MovementPenalty.compose([0.6, 0.6]), MovementPenalty.compose([0.6]))
	assert_lt(MovementPenalty.compose([0.6, 0.6, 0.6]), MovementPenalty.compose([0.6, 0.6]))


## A worse penalty is still worse.
func test_a_worse_penalty_is_still_worse():
	assert_lt(MovementPenalty.compose([0.3, 0.8]), MovementPenalty.compose([0.6, 0.8]))


## Order cannot matter -- these are independent conditions, not a pipeline.
func test_the_order_they_are_listed_in_does_not_matter():
	assert_almost_eq(
		MovementPenalty.compose([0.3, 0.8, 0.5]), MovementPenalty.compose([0.5, 0.3, 0.8]), 0.0001
	)


## Never immobilised: the same "debuffs, not death" rule the survival pillar
## states for every unmet need. A safety rail rather than a balance knob -- it
## sits below any single penalty in the game, so it only ever binds when
## penalties have compounded.
func test_you_are_never_brought_to_a_standstill():
	assert_gte(MovementPenalty.compose([0.1, 0.1, 0.1, 0.1, 0.1, 0.1]), MovementPenalty.FLOOR)
	assert_gt(MovementPenalty.FLOOR, 0.0)



## The floor must not be reachable by ONE condition, or it would quietly
## override that mechanic's own tuning -- pinned under the harshest single
## penalty the game has (a near-vertical slope).
func test_the_floor_sits_below_any_single_penalty():
	assert_lt(MovementPenalty.FLOOR, TerrainPassability.MIN_SPEED_MULTIPLIER)


# -- bonuses ----------------------------------------------------------------


## A worn path makes you faster (see PathScarring). Bonuses are not penalties
## and must not be folded into the worst-constraint logic -- they compose
## straight.
func test_a_bonus_still_speeds_you_up():
	assert_gt(MovementPenalty.compose([1.18]), 1.0)


func test_a_bonus_helps_even_when_something_is_slowing_you():
	assert_gt(MovementPenalty.compose([0.6, 1.18]), MovementPenalty.compose([0.6]))


# -- the case that started it -----------------------------------------------


## The measured worst case: storm, freezing, a steep slope, starving, crouched
## and wading, all at once. It has to stay slow -- that is six things going
## wrong -- but it has to stay MOVEMENT.
func test_the_worst_case_is_slow_but_is_still_walking():
	var everything := [0.65, 0.75, 0.3, 0.75, 0.45, 0.5]
	var composed := MovementPenalty.compose(everything)
	assert_lt(composed, 0.35, "six things going wrong should be genuinely bad")
	assert_gt(composed, _product(everything) * 3.0, "and not six times worse than the worst of them")


## And the case a player actually meets: stalking an animal, crouched, in rain,
## on a slope. This is a normal thing to be doing, and at 23% of base speed it
## was unplayable.
func test_a_crouched_stalk_in_the_rain_on_a_hill_is_playable():
	assert_gt(MovementPenalty.compose([0.85, 0.6, 0.45]), 0.3)
