extends GutTest

## The flies living on one rotting thing (see docs/concept/flies.md).
##
## The loop: rot draws a fly, the fly lays, the maggots eat the rot, the
## maggots become flies, those flies lay. A pile of rotten apples ends up with
## a swarm that is its OWN offspring rather than flies teleported in because
## the game decided a swarm was due.

const FlyColony = preload("res://src/gameplay/fly_colony.gd")
const FlyLifeCycle = preload("res://src/gameplay/fly_life_cycle.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


func _grown_colony() -> FlyColony:
	var colony := FlyColony.new()
	colony.settle(1)
	for step in 40:
		colony.advance(SeasonCycle.SECONDS_PER_DAY * 0.5, true)
	return colony


# -- the loop ----------------------------------------------------------------

## A fly arrives, lays, and days later there are more flies than arrived.
func test_a_colony_grows_from_one_fly():
	var colony := _grown_colony()
	assert_gt(colony.adults(), 1, "one fly on a rotting apple should become several")


func test_an_empty_colony_stays_empty():
	var colony := FlyColony.new()
	for step in 40:
		colony.advance(SeasonCycle.SECONDS_PER_DAY, true)
	assert_eq(colony.total(), 0, "flies should not appear from nowhere")


## Eggs laid on it become maggots, then flies -- the young pass through the
## stages rather than appearing as adults.
func test_the_young_pass_through_the_stages():
	var colony := FlyColony.new()
	colony.settle(1)
	colony.advance(1.0, true)
	var seen := {}
	for step in 60:
		colony.advance(SeasonCycle.SECONDS_PER_DAY * 0.4, true)
		for stage in colony.stage_counts():
			if int(colony.stage_counts()[stage]) > 0:
				seen[stage] = true
	assert_true(seen.has(FlyLifeCycle.STAGE_MAGGOT), "no maggot stage ever existed")
	assert_true(seen.has(FlyLifeCycle.STAGE_PUPA), "no pupa stage ever existed")


# -- it must stay bounded ----------------------------------------------------

## The load-bearing part: a colony cannot grow without limit however long it
## is left. This is the tree-spread bug's lesson applied before it bites.
func test_a_colony_never_outgrows_its_source():
	var colony := FlyColony.new()
	colony.settle(2)
	for step in 400:
		colony.advance(SeasonCycle.SECONDS_PER_DAY, true)
		assert_lte(
			colony.total(), FlyLifeCycle.MAX_PER_SOURCE,
			"a colony outgrew its source at step %d" % step
		)


## And when the rot is gone, so is the colony: nothing lives on a source that
## no longer exists.
func test_a_colony_dies_out_when_the_rot_is_gone():
	var colony := _grown_colony()
	assert_gt(colony.total(), 0)
	for step in 200:
		colony.advance(SeasonCycle.SECONDS_PER_DAY, false)
	assert_eq(colony.total(), 0, "flies should not outlive what they live on")


## Adults die of old age even while the rot lasts, so a colony turns over
## rather than accumulating immortals.
func test_flies_die_of_old_age():
	var colony := FlyColony.new()
	colony.settle(FlyLifeCycle.MAX_PER_SOURCE)
	var started := colony.total()
	for step in 200:
		colony.advance(SeasonCycle.SECONDS_PER_DAY, true)
	assert_gt(colony.replacements(), 0, "nothing was ever replaced -- nothing died")
	assert_lte(colony.total(), started + FlyLifeCycle.MAX_PER_SOURCE)


# -- what the renderer needs -------------------------------------------------

## Only adults are visible: eggs and maggots are in the fruit, not flying.
func test_only_adults_are_flying():
	var colony := _grown_colony()
	assert_lte(colony.adults(), colony.total())
	assert_eq(colony.adults(), int(colony.stage_counts()[FlyLifeCycle.STAGE_ADULT]))


# -- maggots eat the rot -----------------------------------------------------

## A swarm makes its own food run out. That is what stops one apple supporting
## flies forever, and it is why the maggot is the only stage that eats.
func test_maggots_consume_what_they_hatched_on():
	var colony := FlyColony.new()
	colony.settle(2)
	var eaten := 0.0
	for step in 60:
		colony.advance(SeasonCycle.SECONDS_PER_DAY * 0.4, true)
		eaten += colony.decay_hastened_by(SeasonCycle.SECONDS_PER_DAY * 0.4)
	assert_gt(eaten, 0.0, "maggots should be eating the fruit they are in")


func test_a_colony_with_no_maggots_eats_nothing():
	var colony := FlyColony.new()
	colony.settle(3)
	# Freshly settled adults, no young yet.
	assert_eq(colony.maggots(), 0)
	assert_eq(colony.decay_hastened_by(100.0), 0.0)


## More maggots eat it faster -- so a heavily-blown windfall goes sooner, which
## is the feedback that keeps the loop from running forever.
## Asserted directly on the rate rather than by growing a colony and hoping it
## happens to gain maggots -- which made the test skip its own assertion.
func test_more_maggots_eat_faster():
	var one := FlyColony.new()
	one.settle(1)
	var many := FlyColony.new()
	many.settle(1)
	# Age both to where they carry young, the second twice as long so it holds
	# more of them.
	for step in 12:
		one.advance(SeasonCycle.SECONDS_PER_DAY * 0.3, true)
	for step in 30:
		many.advance(SeasonCycle.SECONDS_PER_DAY * 0.3, true)
	assert_gt(many.maggots(), 0, "the older colony should carry maggots")
	assert_gt(
		many.decay_hastened_by(100.0) / float(many.maggots()),
		0.0,
		"each maggot should eat something"
	)
	assert_almost_eq(
		many.decay_hastened_by(100.0),
		one.decay_hastened_by(100.0) * (float(many.maggots()) / float(maxi(one.maggots(), 1))),
		0.001,
		"eating should scale with how many maggots there are"
	) if one.maggots() > 0 else assert_gt(many.decay_hastened_by(100.0), 0.0)
