extends GutTest

## The rear-up a predator does before it strikes (docs/concept/
## predator_profiles.md, "The tell itself").
##
## It is drawn in code rather than animated, and that is forced rather than
## lazy: the complete creature action vocabulary is walk / idle / attack /
## eat / drink / swim, and for every illustrated species `"attack"` already
## falls back to the WALK row -- so an attacking boar is pixel-identical to
## a walking one. There is no rear-up frame to play.
##
## It is a shape and not a colour, and that is forced too. A CreatureMarker
## IS its Sprite2D, and that one 24-pixel body already says three things
## through `modulate`: warm-brighter is a good coat, pale green is sick, red
## is just-hit. A fourth meaning would make the body say everything and
## therefore nothing -- and the obvious hue for "about to hurt you" is the
## one already spoken for by "you just hurt it".

const BiteTell = preload("res://src/rendering/bite_tell.gd")


# -- nothing to show when nothing is coming -------------------------------

func test_a_creature_that_is_not_winding_up_is_its_own_size():
	assert_eq(BiteTell.scale_multiplier(0.0, 1.0), Vector2.ONE)
	assert_eq(BiteTell.scale_multiplier(-1.0, 1.0), Vector2.ONE)


## A species with no bite is owed no telegraph, and a zero-length windup
## must not divide by itself.
func test_a_windup_of_no_length_shows_nothing():
	assert_eq(BiteTell.scale_multiplier(0.5, 0.0), Vector2.ONE)
	assert_eq(BiteTell.scale_multiplier(0.5, -1.0), Vector2.ONE)


# -- the beat -------------------------------------------------------------

## Visible the instant it plants, so a player is never told about a bite
## only after it is too late to answer.
func test_the_plant_shows_at_once():
	var onset: Vector2 = BiteTell.scale_multiplier(1.0, 1.0)
	assert_gt(onset.y, 1.0, "a tell you cannot see is not a tell")


## And it BUILDS, so the last quarter second -- the window a dodge actually
## has to be pressed in -- looks different from the first.
func test_it_builds_toward_the_strike():
	var early: Vector2 = BiteTell.scale_multiplier(0.9, 1.0)
	var late: Vector2 = BiteTell.scale_multiplier(0.1, 1.0)
	assert_gt(late.y, early.y, "the jaws closing must read as closer")


func test_it_never_goes_further_than_its_peak():
	assert_almost_eq(
		BiteTell.scale_multiplier(0.0001, 1.0).y, 1.0 + BiteTell.PEAK_RISE, 0.001
	)


# -- it rears, it does not swell -------------------------------------------

func test_it_rises_more_than_it_widens():
	var tell: Vector2 = BiteTell.scale_multiplier(0.1, 1.0)
	assert_gt(tell.y, tell.x, "an animal rearing is taller, not rounder")


func test_the_shape_constants_are_a_rear_up_and_not_a_balloon():
	assert_gt(BiteTell.ONSET_RISE, 0.0, "a tell nobody can see is silence")
	assert_gt(BiteTell.PEAK_RISE, BiteTell.ONSET_RISE, "it builds")
	assert_lt(BiteTell.PEAK_RISE, 0.5, "and it is still the same animal")
	assert_lt(BiteTell.WIDTH_SHARE, 1.0, "it rears, it does not swell")
	assert_gt(BiteTell.WIDTH_SHARE, 0.0, "but a body is not a line")
