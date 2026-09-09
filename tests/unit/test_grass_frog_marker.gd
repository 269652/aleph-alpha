extends GutTest

## A grass frog -- part of the seasonal-behavior epic's phase 10
## (docs/concept/seasonal_behavior.md). Mirrors CaterpillarMarker's own
## test shape, but real frog locomotion is a genuinely discrete gait (long
## still periods between short hop bursts), not AmbientFlyerMovement's
## continuous smooth roam every other ambient creature uses -- see the
## class's own doc comment for why. That makes "hop" a real discrete state
## (mid-hop-burst or not), tested directly here rather than inferred from a
## continuous movement magnitude.

const GrassFrogMarker = preload("res://src/rendering/grass_frog_marker.gd")
const IllustratedGrassFrogSprite = preload("res://src/rendering/illustrated_grass_frog_sprite.gd")

var marker: GrassFrogMarker


func before_each():
	marker = GrassFrogMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 7
	add_child_autofree(marker)


func test_starts_idle():
	assert_eq(marker._current_action(), "idle")


func test_stays_near_home_across_many_hops():
	for i in 30:
		marker._process(0.5)
	assert_lt(
		marker.position.distance_to(marker.home), GrassFrogMarker.WANDER_RADIUS_PX * 2.5,
		"a frog ranges over its home patch, it doesn't wander off unbounded"
	)


func test_hops_instead_of_sitting_frozen_forever():
	var start := marker.position
	for i in 30:
		marker._process(0.5)
	assert_ne(marker.position, start, "15 simulated seconds should include at least one real hop")


## The idle/hop choice is a real discrete state (mid-hop-burst or not), not
## a proxy read off per-frame movement size -- confirmed by driving a hop
## directly and checking the action mid-burst, then after it ends.
func test_plays_the_hop_animation_only_while_a_hop_is_actually_in_progress():
	marker._begin_hop()
	assert_eq(marker._current_action(), "hop", "a hop burst was just started")
	marker._process(GrassFrogMarker.HOP_DURATION_SECONDS + 0.01)
	assert_ne(marker._current_action(), "hop", "the hop burst's own duration has fully elapsed")


func test_a_hop_actually_moves_the_frog_toward_its_target():
	var start := marker.position
	marker._begin_hop()
	marker._step_hop(GrassFrogMarker.HOP_DURATION_SECONDS)
	assert_almost_eq(
		marker.position.distance_to(start), GrassFrogMarker.HOP_DISTANCE_PX, 0.5,
		"one full hop covers its own real, fixed distance"
	)


## Real frogs call while stationary -- confirmed by driving croak directly
## and checking the action mid-call, then after it ends.
func test_plays_the_croak_animation_only_while_a_croak_is_actually_in_progress():
	marker._begin_croak()
	assert_eq(marker._current_action(), "croak", "a croak was just started")
	marker._process(GrassFrogMarker.CROAK_DURATION_SECONDS + 0.01)
	assert_ne(marker._current_action(), "croak", "the croak's own duration has fully elapsed")


func test_a_croak_does_not_move_the_frog_at_all():
	var start := marker.position
	marker._begin_croak()
	for i in 5:
		marker._process(0.1)
	assert_eq(marker.position, start, "a real frog call doesn't relocate it")


func test_draws_real_illustrated_art_at_its_real_world_size():
	var sprite := marker.get_child(0) as Sprite2D
	assert_not_null(sprite.texture)
	assert_eq(sprite.scale, Vector2.ONE * IllustratedGrassFrogSprite.new().world_scale())


## Two frogs with different seeds must not hop/croak in lockstep -- a pond
## full of frogs all calling on the exact same frame would read as one
## mechanical metronome, not a real population of individuals.
func test_two_different_seeds_do_not_hop_in_perfect_lockstep():
	var other := GrassFrogMarker.new()
	other.home = Vector2(100, 100)
	other.position = Vector2(100, 100)
	other.wander_seed = 99
	add_child_autofree(other)
	var a_positions: Array = []
	var b_positions: Array = []
	for i in 20:
		marker._process(0.3)
		other._process(0.3)
		a_positions.append(marker.position)
		b_positions.append(other.position)
	assert_ne(a_positions, b_positions, "different seeds should hop at different moments")
