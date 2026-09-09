extends GutTest

## BirdFlocking: pure, engine-free bird-to-bird steering (see
## docs/concept/soil_fauna.md's "Sparrows flock, robins don't"). Mirrors
## FishSchooling's own ZONAL MODEL exactly (Aoki 1982; Huth & Wissel 1992) --
## AmbientFlyerMarker gathers a real nearest same-species flockmate and its
## heading; this decides what to do about it. Deliberately WITHOUT
## FishSchooling's play-chase extra (not asked for here, and a fish-specific
## flourish, not part of the zonal model itself).

const BirdFlocking = preload("res://src/gameplay/bird_flocking.gd")


# -- the three zones, purely by distance (identical shape to FishSchooling,
# re-derived at a real sparrow's own body scale) -----------------------------

func test_a_neighbor_inside_the_repulsion_zone_is_avoided():
	var inside_repulsion := BirdFlocking.REPULSION_RADIUS_PX / 2.0
	var steering := BirdFlocking.steering_for_neighbor(
		Vector2.ZERO, Vector2(inside_repulsion, 0), Vector2.ZERO
	)
	assert_almost_eq(steering.x, -1.0, 1e-6, "should point directly away from the too-close neighbor")
	assert_almost_eq(steering.y, 0.0, 1e-6)


func test_a_neighbor_in_the_orientation_zone_is_matched_by_heading():
	var mid_orientation := (BirdFlocking.REPULSION_RADIUS_PX + BirdFlocking.ORIENTATION_RADIUS_PX) / 2.0
	var steering := BirdFlocking.steering_for_neighbor(
		Vector2.ZERO, Vector2(mid_orientation, 0), Vector2(0, 1)
	)
	assert_almost_eq(steering.x, 0.0, 1e-6, "should match the neighbor's heading, not its position")
	assert_almost_eq(steering.y, 1.0, 1e-6)


func test_a_neighbor_in_the_orientation_zone_with_no_known_heading_is_approached_instead():
	var mid_orientation := (BirdFlocking.REPULSION_RADIUS_PX + BirdFlocking.ORIENTATION_RADIUS_PX) / 2.0
	var steering := BirdFlocking.steering_for_neighbor(
		Vector2.ZERO, Vector2(mid_orientation, 0), Vector2.ZERO
	)
	assert_almost_eq(steering.x, 1.0, 1e-6, "a still/unknown-heading neighbor should still be drifted toward")
	assert_almost_eq(steering.y, 0.0, 1e-6)


func test_a_neighbor_in_the_attraction_zone_is_approached():
	var mid_attraction := (BirdFlocking.ORIENTATION_RADIUS_PX + BirdFlocking.ATTRACTION_RADIUS_PX) / 2.0
	var steering := BirdFlocking.steering_for_neighbor(
		Vector2.ZERO, Vector2(mid_attraction, 0), Vector2.ZERO
	)
	assert_almost_eq(steering.x, 1.0, 1e-6, "should fly toward a distant-but-noticed flockmate")
	assert_almost_eq(steering.y, 0.0, 1e-6)


func test_a_neighbor_beyond_the_attraction_zone_has_no_influence():
	var beyond := BirdFlocking.ATTRACTION_RADIUS_PX * 2.0
	var steering := BirdFlocking.steering_for_neighbor(
		Vector2.ZERO, Vector2(beyond, 0), Vector2.ZERO
	)
	assert_eq(steering, Vector2.ZERO, "a flockmate too far off to notice should not steer this bird at all")


func test_an_overlapping_neighbor_has_no_influence():
	var steering := BirdFlocking.steering_for_neighbor(
		Vector2(50, 50), Vector2(50, 50), Vector2.ZERO
	)
	assert_eq(steering, Vector2.ZERO, "exactly overlapping gives no direction to avoid toward")


func test_zone_radii_are_ordered_repulsion_lt_orientation_lt_attraction():
	assert_lt(BirdFlocking.REPULSION_RADIUS_PX, BirdFlocking.ORIENTATION_RADIUS_PX)
	assert_lt(BirdFlocking.ORIENTATION_RADIUS_PX, BirdFlocking.ATTRACTION_RADIUS_PX)


## The zones are stated in real BODY LENGTHS, converted via GroundSlide.
## PX_PER_METER -- the same real-world-to-world-px idiom this codebase
## already uses for every other body-scale constant (see that class's own
## doc comment), rather than borrowing FishSchooling's own FISH_BODY_
## LENGTH_PX, an unrelated species' scale.
func test_body_length_constant_is_a_real_sparrow_length_in_meters():
	assert_between(
		BirdFlocking.SPARROW_BODY_LENGTH_METERS, 0.12, 0.18,
		"a house sparrow is roughly 14-16cm bill to tail"
	)


# -- species gate: sparrows flock, robins don't ------------------------------

func test_sparrow_flocks():
	assert_true(BirdFlocking.flocks("sparrow"))


func test_robin_does_not_flock():
	assert_false(
		BirdFlocking.flocks("robin"),
		"a real European robin is territorial and solitary outside a mated pair"
	)


func test_blackbird_does_not_flock():
	assert_false(BirdFlocking.flocks("blackbird"))


func test_an_unknown_species_does_not_flock():
	assert_false(BirdFlocking.flocks("not_a_real_species"))
