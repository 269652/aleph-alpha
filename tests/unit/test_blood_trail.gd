extends GutTest

## The trail a wounded animal leaves (docs/concept/olfaction.md, "Blood: the
## trail a wounded animal leaves").
##
## A struck animal runs, and FlightDistance makes it run early -- so before
## this, a hit that did not kill outright meant the animal was simply gone, and
## the hunt ended not because the player failed but because the world stopped
## representing what had happened. There was no third state between dead and
## untouched.

const BloodTrail = preload("res://src/gameplay/blood_trail.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


# -- it is a trail, not a stain ----------------------------------------------


## Marks go where the animal WENT. A radius around where it was hit is a
## stain; a line of marks along its escape is something you can follow.
func test_a_running_animal_marks_the_ground_it_crosses():
	var trail := BloodTrail.new()
	var dropped: Array[Vector2] = []
	var at := Vector2.ZERO
	for step in 200:
		at += Vector2(BloodTrail.SPACING_PX * 0.25, 0.0)
		var mark := trail.step(at, 1, 0.1)
		if mark:
			dropped.append(at)
	assert_gt(dropped.size(), 2, "a wounded animal ran a long way and marked nothing")
	for index in range(1, dropped.size()):
		assert_gt(dropped[index].x, dropped[index - 1].x, "the trail doubled back on itself")


## Marks are spaced along the ground rather than dropped every frame, or a
## standing animal would bleed a puddle the size of the tile it is on.
func test_an_animal_standing_still_does_not_pool_marks():
	var trail := BloodTrail.new()
	var marks := 0
	for step in 600:
		if trail.step(Vector2(10.0, 10.0), 1, 0.1):
			marks += 1
	assert_lte(marks, 1, "a motionless animal bled a puddle")


## An unwounded animal leaves nothing at all.
func test_an_unwounded_animal_leaves_no_trail():
	var trail := BloodTrail.new()
	var at := Vector2.ZERO
	for step in 200:
		at += Vector2(BloodTrail.SPACING_PX, 0.0)
		assert_false(trail.step(at, 0, 0.1))


## A worse wound bleeds more freely -- the trail itself tells you how badly you
## hit it, which is real tracking rather than a marker on a map.
func test_a_worse_wound_marks_more_often():
	assert_lt(BloodTrail.spacing_for(3), BloodTrail.spacing_for(1))


# -- and it fades ------------------------------------------------------------


## A trail is a window, not a permanent annotation: following it is something
## you do NOW. Marks thin out and stop as the wound clots.
func test_a_mark_fades():
	assert_gt(BloodTrail.freshness_after(0.0), BloodTrail.freshness_after(BloodTrail.MARK_LIFETIME_SECONDS * 0.5))


func test_a_mark_is_gone_once_its_lifetime_runs_out():
	assert_eq(BloodTrail.freshness_after(BloodTrail.MARK_LIFETIME_SECONDS), 0.0)
	assert_eq(BloodTrail.freshness_after(BloodTrail.MARK_LIFETIME_SECONDS * 10.0), 0.0)


## Long enough to actually follow: a trail that outlived the animal's flight by
## nothing would be useless. Bracketed against the world's own tile size and
## the speeds animals really move at.
func test_a_trail_outlasts_the_flight_that_made_it():
	assert_between(BloodTrail.MARK_LIFETIME_SECONDS, 20.0, 300.0)


# -- what it smells of -------------------------------------------------------


## The marks emit into the SAME smells_near field baits and carried food
## already use, so nothing new has to be taught about them.
func test_a_fresh_mark_smells_of_blood():
	var mixture := BloodTrail.mixture_for(1.0)
	assert_gt(float(mixture.get(Olfaction.BLOOD, 0.0)), 0.0)


func test_a_mixture_only_contains_real_molecules():
	for molecule in BloodTrail.mixture_for(1.0):
		assert_true(Olfaction.MOLECULES.has(molecule), "%s is not a molecule" % molecule)


## Blood going over turns to carrion-smell rather than simply getting quieter:
## an old mark is a different thing from a fresh one, which is the whole reason
## BLOOD and DECAY are separate molecules.
func test_an_old_mark_smells_more_of_decay_and_less_of_blood():
	var fresh := BloodTrail.mixture_for(1.0)
	var old := BloodTrail.mixture_for(0.15)
	assert_lt(float(old.get(Olfaction.BLOOD, 0.0)), float(fresh.get(Olfaction.BLOOD, 0.0)))
	assert_gt(float(old.get(Olfaction.DECAY, 0.0)), float(fresh.get(Olfaction.DECAY, 0.0)))
