extends GutTest

## How fast a plant yields to a walker and how fast it comes back
## (docs/concept/long_grass.md). Reported live, for every plant at once:
## *"it bounces back too fast and also bending too fast giving the
## impression of rubber instead of natural plant"*.
##
## The cause is that there was no time in the model at all. The shader's
## push term is a pure function of the walker's CURRENT distance, so a
## blade reaches full lean the instant the walker is in range and snaps
## upright the instant they leave -- the plant tracks the walker exactly,
## with no inertia and no settling. That reads as rubber because rubber is
## what zero damping looks like.
##
## What the shader is given instead is a walker position that LAGS: the
## bend still follows one point, but the point takes real time to arrive
## and real time to leave. One state, shared by every plant, so grass,
## ferns, wheat and brambles cannot drift into swaying by different rules.

const PlantSway = preload("res://src/rendering/plant_sway.gd")

const FRAME := 1.0 / 60.0


func _settle(start: Vector2, target: Vector2, seconds: float) -> Vector2:
	var at := start
	var elapsed := 0.0
	while elapsed < seconds:
		at = PlantSway.eased_walker_position(at, target, FRAME)
		elapsed += FRAME
	return at


# -- it takes time, in both directions ---------------------------------------

func test_a_plant_does_not_reach_full_lean_in_one_frame():
	var after := PlantSway.eased_walker_position(Vector2(100.0, 0.0), Vector2.ZERO, FRAME)
	assert_gt(after.length(), 0.0, "it has to move at all")
	assert_gt(
		after.length(), 50.0,
		"one frame must not carry it most of the way there -- that is the snap being fixed"
	)


func test_it_does_get_there_if_the_walker_stays():
	var after := _settle(Vector2(100.0, 0.0), Vector2.ZERO, 2.0)
	assert_lt(after.length(), 1.0, "a walker standing still is eventually just where they are")


## The whole complaint, in one assertion: leaving is not instant.
func test_a_plant_is_still_leaning_a_frame_after_the_walker_has_gone():
	var pressed := Vector2.ZERO
	var gone := Vector2(1000.0, 0.0)
	var after := PlantSway.eased_walker_position(pressed, gone, FRAME)
	assert_lt(
		after.length(), 100.0,
		"the walker teleported away and the plant went with them, which is the snap-back"
	)


## ...and coming back takes LONGER than going over. A cane pushed aside
## springs back slowly; it does not mirror the push.
func test_coming_back_takes_longer_than_going_over():
	assert_gt(PlantSway.RELEASE_SECONDS, PlantSway.YIELD_SECONDS)


func test_the_response_is_frame_rate_independent():
	var at_60 := _settle(Vector2(100.0, 0.0), Vector2.ZERO, 0.5)
	var at_30 := Vector2(100.0, 0.0)
	var elapsed := 0.0
	while elapsed < 0.5:
		at_30 = PlantSway.eased_walker_position(at_30, Vector2.ZERO, 1.0 / 30.0)
		elapsed += 1.0 / 30.0
	assert_almost_eq(
		at_60.length(), at_30.length(), 3.0,
		"a plant must not bend faster on a faster machine"
	)


## A huge delta (a stalled frame, a loading hitch) must not overshoot past
## the walker and come back -- that is a wobble nobody asked for.
func test_a_long_frame_never_overshoots():
	var after := PlantSway.eased_walker_position(Vector2(100.0, 0.0), Vector2.ZERO, 10.0)
	assert_gte(after.x, 0.0, "it swung through the walker and out the other side")
	assert_lte(after.x, 100.0)


# -- the constants, derived rather than picked -------------------------------

## A real frond settles in a fraction of a second, not instantly and not
## over a second. Both are pinned so a change has to be deliberate.
func test_the_timings_are_the_ones_that_were_measured():
	assert_almost_eq(PlantSway.YIELD_SECONDS, 0.18, 0.0001)
	assert_almost_eq(PlantSway.RELEASE_SECONDS, 0.55, 0.0001)


## The first placement SNAPS, because there is nothing to ease from. Easing
## in from the sentinel would take the bend point several seconds to cross
## a hundred thousand units, so the opening seconds of a fresh session
## would have no plant parting at all.
func test_the_very_first_placement_snaps():
	assert_eq(
		PlantSway.eased_walker_position(PlantSway.UNSET_POSITION, Vector2(500.0, 500.0), FRAME),
		Vector2(500.0, 500.0)
	)
