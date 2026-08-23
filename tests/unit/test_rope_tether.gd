extends GutTest

## The rope itself: what a lassoed animal is allowed to do at the end of it,
## whether the far end is held by the player (led) or tied to a tree
## (anchored). See docs/concept/taming.md.

const RopeTether = preload("res://src/gameplay/rope_tether.gd")


## Slack rope: the animal is free to mill about. A rope that pulled constantly
## would drag a led horse onto the player's feet and make a tied one stand
## rigidly at its anchor, neither of which is an animal.
func test_a_slack_rope_does_not_pull():
	assert_eq(
		RopeTether.pull_direction(Vector2(10, 0), Vector2.ZERO, RopeTether.ROPE_LENGTH),
		Vector2.ZERO
	)


func test_a_taut_rope_pulls_the_animal_back_toward_the_anchor():
	var animal := Vector2(RopeTether.ROPE_LENGTH * 3.0, 0)
	var pull := RopeTether.pull_direction(animal, Vector2.ZERO, RopeTether.ROPE_LENGTH)
	assert_almost_eq(pull.x, -1.0, 0.001, "pulled back the way it came")
	assert_almost_eq(pull.y, 0.0, 0.001)


func test_the_pull_is_a_direction_not_a_distance():
	var far := RopeTether.pull_direction(Vector2(900, 900), Vector2.ZERO, RopeTether.ROPE_LENGTH)
	assert_almost_eq(far.length(), 1.0, 0.001)


## An animal standing exactly on its anchor has no direction to be pulled in;
## normalising a zero vector is the ill-conditioned blend-then-normalise
## mistake that produced the flee-jitter bugs, so it is ruled out here.
func test_an_animal_on_top_of_its_anchor_is_not_pulled_anywhere():
	assert_eq(RopeTether.pull_direction(Vector2.ZERO, Vector2.ZERO, RopeTether.ROPE_LENGTH), Vector2.ZERO)


# -- the hard limit ----------------------------------------------------------

func test_a_slack_rope_leaves_the_animal_where_it_is():
	var animal := Vector2(12, -5)
	assert_eq(RopeTether.clamped_position(animal, Vector2.ZERO, RopeTether.ROPE_LENGTH), animal)


## The rope is a rope: whatever the AI wanted, the animal cannot end a frame
## further out than the rope is long. Without this a fleeing horse simply
## outruns its tether.
func test_the_animal_can_never_end_up_past_the_end_of_the_rope():
	var clamped := RopeTether.clamped_position(Vector2(500, 500), Vector2(10, 10), RopeTether.ROPE_LENGTH)
	assert_almost_eq(
		clamped.distance_to(Vector2(10, 10)), RopeTether.ROPE_LENGTH, 0.001,
		"held at rope length, not teleported to the anchor"
	)


func test_clamping_keeps_the_animal_on_the_side_it_ran_to():
	var clamped := RopeTether.clamped_position(Vector2(-400, 0), Vector2.ZERO, RopeTether.ROPE_LENGTH)
	assert_lt(clamped.x, 0.0, "it stays where it pulled, just no further")


func test_clamping_an_animal_standing_on_its_anchor_is_safe():
	assert_eq(
		RopeTether.clamped_position(Vector2.ZERO, Vector2.ZERO, RopeTether.ROPE_LENGTH), Vector2.ZERO
	)


func test_is_taut_agrees_with_whether_there_is_a_pull():
	for distance in [0.0, RopeTether.ROPE_LENGTH * 0.5, RopeTether.ROPE_LENGTH * 2.0]:
		var animal := Vector2(distance, 0)
		assert_eq(
			RopeTether.is_taut(animal, Vector2.ZERO, RopeTether.ROPE_LENGTH),
			RopeTether.pull_direction(animal, Vector2.ZERO, RopeTether.ROPE_LENGTH) != Vector2.ZERO
		)


## A led animal has to have room to walk behind the player rather than being
## welded to them, but not so much rope that it trails off screen.
func test_the_rope_is_a_believable_length():
	assert_gt(RopeTether.ROPE_LENGTH, 16.0, "longer than a tile, or it is a leash on a collar")
	assert_lt(RopeTether.ROPE_LENGTH, 160.0, "and short enough to stay on screen with the player")
