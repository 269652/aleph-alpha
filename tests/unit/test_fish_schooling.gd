extends GutTest

## FishSchooling: pure, engine-free fish-to-fish steering (see
## docs/concept/ecosystem_dynamics.md#a-shoal-finds-its-shape). Mirrors
## CreatureBehavior/ThreatAvoidantWander's own "plain vector math over plain
## data, no nodes" shape -- FishMarker gathers a real nearest schoolmate and
## its heading; this decides what to do about it.

const FishSchooling = preload("res://src/gameplay/fish_schooling.gd")
const FishMarker = preload("res://src/rendering/fish_marker.gd")


# -- the three zones, purely by distance -------------------------------------

func test_a_neighbor_inside_the_repulsion_zone_is_avoided():
	var steering := FishSchooling.steering_for_neighbor(
		Vector2.ZERO, Vector2(5, 0), Vector2.ZERO
	)
	assert_almost_eq(steering.x, -1.0, 1e-6, "should point directly away from the too-close neighbor")
	assert_almost_eq(steering.y, 0.0, 1e-6)


func test_a_neighbor_in_the_orientation_zone_is_matched_by_heading():
	var steering := FishSchooling.steering_for_neighbor(
		Vector2.ZERO, Vector2(30, 0), Vector2(0, 1)
	)
	assert_almost_eq(steering.x, 0.0, 1e-6, "should match the neighbor's heading, not its position")
	assert_almost_eq(steering.y, 1.0, 1e-6)


func test_a_neighbor_in_the_orientation_zone_with_no_known_heading_is_approached_instead():
	var steering := FishSchooling.steering_for_neighbor(
		Vector2.ZERO, Vector2(30, 0), Vector2.ZERO
	)
	assert_almost_eq(steering.x, 1.0, 1e-6, "a still/unknown-heading neighbor should still be drifted toward")
	assert_almost_eq(steering.y, 0.0, 1e-6)


func test_a_neighbor_in_the_attraction_zone_is_approached():
	var steering := FishSchooling.steering_for_neighbor(
		Vector2.ZERO, Vector2(80, 0), Vector2.ZERO
	)
	assert_almost_eq(steering.x, 1.0, 1e-6, "should swim toward a distant-but-noticed schoolmate")
	assert_almost_eq(steering.y, 0.0, 1e-6)


func test_a_neighbor_beyond_the_attraction_zone_has_no_influence():
	var steering := FishSchooling.steering_for_neighbor(
		Vector2.ZERO, Vector2(200, 0), Vector2.ZERO
	)
	assert_eq(steering, Vector2.ZERO, "a schoolmate too far off to notice should not steer this fish at all")


func test_an_overlapping_neighbor_has_no_influence():
	var steering := FishSchooling.steering_for_neighbor(
		Vector2(50, 50), Vector2(50, 50), Vector2.ZERO
	)
	assert_eq(steering, Vector2.ZERO, "exactly overlapping gives no direction to avoid toward")


func test_zone_radii_are_ordered_repulsion_lt_orientation_lt_attraction():
	assert_lt(FishSchooling.REPULSION_RADIUS_PX, FishSchooling.ORIENTATION_RADIUS_PX)
	assert_lt(FishSchooling.ORIENTATION_RADIUS_PX, FishSchooling.ATTRACTION_RADIUS_PX)


## The zones are stated in BODY LENGTHS, the same unit the real shoaling
## literature uses -- cross-checked directly against FishMarker's own
## CLEARANCE_PX (documented there as "roughly the sprite's half-extent", so
## doubled is a full body length) rather than trusting a comment alone. The
## two scripts deliberately don't import each other (FishMarker preloads
## FishSchooling to use it; the reverse would be circular), so this is the
## one place that relationship is actually verified.
func test_body_length_constant_matches_fish_markers_own_clearance_diameter():
	assert_eq(FishSchooling.FISH_BODY_LENGTH_PX, FishMarker.CLEARANCE_PX * 2.0)


# -- play: a rare, deterministic per-interval roll ---------------------------

func test_rolls_for_play_is_probabilistically_close_to_its_pinned_chance():
	var trials := 20000
	var hits := 0
	for i in trials:
		if FishSchooling.rolls_for_play(i, i * 7 + 3):
			hits += 1
	var fraction := float(hits) / float(trials)
	assert_almost_eq(
		fraction, FishSchooling.PLAY_CHANCE, 0.02,
		"empirical play-roll rate should track the pinned chance (got %.4f)" % fraction
	)


func test_rolls_for_play_is_deterministic_for_the_same_seed_and_interval():
	var first := FishSchooling.rolls_for_play(42, 5)
	var second := FishSchooling.rolls_for_play(42, 5)
	assert_eq(first, second, "the same fish re-checking the same interval must get the same answer")


func test_rolls_for_play_chance_is_low_not_constant():
	assert_lt(FishSchooling.PLAY_CHANCE, 0.2, "play should be a rare interruption, not the usual case")
	assert_gt(FishSchooling.PLAY_CHANCE, 0.0, "must be reachable at all")
