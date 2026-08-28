extends RefCounted

## WHEN a tree wears which canopy (see docs/concept/seasons.md#winter-stays-
## bare-the-canopy-has-its-own-phenology).
##
## Reported from a world that started in WINTER: pink cherry blossom and green
## leafy crowns standing in a frozen world. Nothing was mis-mapped --
## IllustratedTree's table is right and nothing had regressed. It was
## SeasonTransition working as written: TURN_FRACTION is 0.34, so the last
## third of EVERY season already reports {from: winter, to: spring} while
## SeasonCycle.season_at -- and the HUD -- still says Winter.
##
## And it read even earlier than the progress number says, because the ground
## expresses a turn as a COLOUR LERP while a canopy expresses it as PIXEL
## REPLACEMENT between frames of very different density. Measured off the
## shipped cherry sheet: bare is 62,512 opaque px of brown, blossom is 157,928
## of pink -- 2.5x the picture -- so one step of six already reads as "in
## blossom" where one step of six toward spring green is imperceptible on a
## lawn.
##
## So a canopy gets its own schedule. A real cherry stands bare all winter,
## flowers on bare branches for about a fortnight in early spring, and leafs
## out after. The GROUND keeps SeasonTransition: the two still share one clock,
## one set of season names and one quantiser -- what they no longer share is
## the curve.
##
## Pure and engine-free, the same shape as SeasonTransition itself: this says
## which two canopy frames a moment is between and how far along. Blending the
## art is the renderer's job.

const SeasonCycle = preload("res://src/world/season_cycle.gd")
const SeasonTransition = preload("res://src/world/season_transition.gd")

## ## The four stages, in the order a canopy walks them
##
## bare -> blossom -> leaf -> turning -> bare, round again.
##
## Named by the SEASON whose canopy frame each one selects, so this drops
## straight into IllustratedTree.canopy_for and into the {from, to, progress}
## shape the renderer already consumes -- these are canopy KEYS, not claims
## about what month it is.
##
## The order is deliberately the SHEET order (IllustratedTree.CANOPY_BARE = 0
## .. CANOPY_TURNING = 3), so a stage index and a canopy frame index are the
## same number. Pinned by test, since it is otherwise exactly the kind of
## coincidence that silently rots.
const BARE := "winter"
const BLOSSOM := "spring"
const LEAF := "summer"
const TURNING := "autumn"

const CANOPY_KEYS := [BARE, BLOSSOM, LEAF, TURNING]
const STAGE_COUNT := 4

## The stages by index, for arithmetic on the walk.
const BARE_STAGE := 0
const BLOSSOM_STAGE := 1
const LEAF_STAGE := 2
const TURNING_STAGE := 3

## ## How long blossom lasts, and where the number comes from
##
## MEASURED against the real tree rather than picked, the way Snowfall's
## covering time is measured in weather spells rather than in "how long should
## a player watch this take". These four figures are real Prunus bloom records
## in real days; every fraction below is derived from them, so the schedule
## cannot be nudged without changing a claim about an actual tree.
##
## Spring is the astronomical one, equinox to solstice.
const REAL_SPRING_DAYS := 92.0
## Bud break to full bloom: the tree coming INTO flower.
const REAL_OPENING_DAYS := 5.0
## Full bloom held, to petal fall.
const REAL_FULL_BLOOM_DAYS := 7.0
## Petal fall to a fully expanded canopy.
const REAL_LEAF_OUT_DAYS := 14.0

## The same spans as fractions of an in-game spring.
const OPENING_FRACTION := REAL_OPENING_DAYS / REAL_SPRING_DAYS
const FULL_BLOOM_FRACTION := REAL_FULL_BLOOM_DAYS / REAL_SPRING_DAYS
const LEAF_OUT_FRACTION := REAL_LEAF_OUT_DAYS / REAL_SPRING_DAYS

## How much of spring has blossom on the tree AT ALL -- coming into it, then
## holding it. About 13%, against the 34% an ordinary season turn occupies
## (SeasonTransition.TURN_FRACTION): blossom is the briefest seasonal change in
## the game, which is what makes it an event rather than wallpaper.
const BLOSSOM_FRACTION := OPENING_FRACTION + FULL_BLOOM_FRACTION


## How many in-game days a season runs to. A SeasonCycle year is 48, so 12.
static func season_days() -> float:
	return SeasonCycle.DAYS_PER_YEAR / float(SeasonCycle.SEASONS.size())


## How many in-game days a tree carries blossom -- a little over a day and a
## half. Derived, so the real-day ratio above is the only place a number is
## chosen.
static func blossom_days() -> float:
	return season_days() * BLOSSOM_FRACTION


## Where this moment sits on the four-stage walk, as ONE monotone number in
## [0, STAGE_COUNT): the integer part is the stage a tree is on, the fraction
## is how far into the change to the next one.
##
## One number rather than a pair of names, because the property that actually
## matters is that it never JUMPS -- a canopy that skipped a stage would change
## between one step and the next, which is the exact failure SeasonTransition
## was built to remove. Expressed this way the guarantee is testable directly.
static func canopy_position_at(year_fraction: float) -> float:
	var count := SeasonCycle.SEASONS.size()
	var span := 1.0 / float(count)
	var position := fposmod(year_fraction, 1.0)
	var index := clampi(int(position * float(count)), 0, count - 1)
	var within := (position - float(index) * span) / span
	match SeasonCycle.SEASONS[index]:
		"spring":
			return _spring_position(within)
		"summer":
			return float(LEAF_STAGE) + _settled_then_turn(within)
		"autumn":
			return float(TURNING_STAGE) + _settled_then_turn(within)
		_:
			# ## Winter is bare until its last hours
			#
			# The pre-turn is no longer SUPPRESSED here, only SHORTENED. It exists
			# so a season arrives already saturated rather than swapping on a frame
			# boundary, and spring is the one season whose arrival state is not
			# simply what the season before it wore -- so winter is where the work
			# has to happen. Reported live against /season spring: the HUD read
			# Spring over bare brown branches and snow-capped pines, because this
			# was the year's one season start that arrived unsaturated.
			#
			# It rides OPENING_FRACTION -- the measured bud-break span -- and NOT
			# SeasonTransition.TURN_FRACTION. A third of winter spent visibly
			# pinker is what put blossom in the snow in the first place: blossom
			# carries 2.5x the opaque pixels of bare wood (docs/concept/seasons.md),
			# so it reads as arrived long before its progress number does. Moving
			# the same short ramp earlier costs no extra cached images and leaves
			# the total blossom span exactly the measured 5+7 days -- it just ends
			# on the boundary instead of starting there.
			return _bare_then_open(within)


## Which two canopy frames this moment is between, and how far along, as
## {from, to, progress} -- the shape the renderer already consumes, so this
## drops in wherever SeasonTransition.state_at fed a CANOPY.
##
## A settled stage reports progress 0.0 with `to` naming whatever comes next,
## so a caller can use the same path all year rather than branching on "is it
## turning" (ProceduralTreeSprite only blends when progress > 0).
static func canopy_state_at(year_fraction: float) -> Dictionary:
	var position := canopy_position_at(year_fraction)
	var stage := int(floorf(position)) % STAGE_COUNT
	return {
		"from": CANOPY_KEYS[stage],
		"to": CANOPY_KEYS[(stage + 1) % STAGE_COUNT],
		# The SAME quantiser the ground turns on: the granularity is a
		# rendering budget, not a property of the calendar, so a second
		# schedule must not come with a second answer to it.
		"progress": SeasonTransition.quantise(position - floorf(position)),
	}


## Spring, the season that actually does the work: out of bare into blossom,
## hold, then out of blossom into leaf, then settled leaf for the rest of it.
##
## Every span is gradual on the shared quantised steps, including the FIRST --
## the winter/spring boundary is where a hard frame change would be most
## visible, so blossom arrives across it rather than at it.
static func _spring_position(within: float) -> float:
	if within < FULL_BLOOM_FRACTION:
		return float(BLOSSOM_STAGE)
	if within < FULL_BLOOM_FRACTION + LEAF_OUT_FRACTION:
		return float(BLOSSOM_STAGE) + (within - FULL_BLOOM_FRACTION) / LEAF_OUT_FRACTION
	# Spring's own last third used to be the blossom->leaf turn. It is now
	# leaf->leaf and does nothing, which is why summer needs no fixing up.
	return float(LEAF_STAGE)


## Winter: settled bare, then the bud-break ramp against its END rather than
## against the start of spring -- which is the whole fix. A tree finishes
## opening exactly ON the winter/spring boundary, so the first instant of
## spring (where /season spring puts you) is already full blossom.
static func _bare_then_open(within: float) -> float:
	var settled := 1.0 - OPENING_FRACTION
	if within < settled:
		return float(BARE_STAGE)
	return float(BARE_STAGE) + (within - settled) / OPENING_FRACTION


## Summer and autumn, unchanged: settled for the first part, then turning
## across SeasonTransition's own window, so in those two seasons the crown and
## the lawn beneath it turn at exactly the same rate.
static func _settled_then_turn(within: float) -> float:
	if within < 1.0 - SeasonTransition.TURN_FRACTION:
		return 0.0
	return (within - (1.0 - SeasonTransition.TURN_FRACTION)) / SeasonTransition.TURN_FRACTION
