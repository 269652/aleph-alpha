extends GutTest

## Pure targeting for a spell cast (docs/concept/spell_runtime.md) -- mirrors
## melee_attack.gd's own pure/index-based test shape, but for a DIRECTED cast
## (touch/projectile/area) rather than melee's radius-only AOE sweep.

const SpellTargeting = preload("res://src/gameplay/spell_targeting.gd")

var targeting := SpellTargeting.new()


func test_nearest_touch_finds_the_closest_candidate_in_range():
	var far := Vector2(20, 0)
	var near := Vector2(5, 0)
	var index := targeting.nearest_touch(Vector2.ZERO, [far, near], 24.0)
	assert_eq(index, 1)


func test_nearest_touch_returns_negative_one_when_nothing_in_range():
	var index := targeting.nearest_touch(Vector2.ZERO, [Vector2(100, 0)], 24.0)
	assert_eq(index, -1)


func test_nearest_touch_returns_negative_one_for_no_candidates():
	assert_eq(targeting.nearest_touch(Vector2.ZERO, [], 24.0), -1)


func test_nearest_in_facing_ignores_a_candidate_behind_the_caster():
	var behind := Vector2(-10, 0)
	var index := targeting.nearest_in_facing(Vector2.ZERO, Vector2.RIGHT, [behind], 120.0, 30.0)
	assert_eq(index, -1, "a target directly behind the caster must not be hit by a directed cast")


func test_nearest_in_facing_finds_a_candidate_straight_ahead():
	var ahead := Vector2(50, 0)
	var index := targeting.nearest_in_facing(Vector2.ZERO, Vector2.RIGHT, [ahead], 120.0, 30.0)
	assert_eq(index, 0)


func test_nearest_in_facing_ignores_a_candidate_outside_the_cone_angle():
	# 50 world units right and 50 down is a 45-degree offset from straight
	# right -- outside a 30-degree half-angle cone.
	var off_to_the_side := Vector2(50, 50)
	var index := targeting.nearest_in_facing(Vector2.ZERO, Vector2.RIGHT, [off_to_the_side], 120.0, 30.0)
	assert_eq(index, -1)


func test_nearest_in_facing_includes_a_candidate_right_at_the_cone_edge():
	# Exactly 30 degrees off dead-ahead -- the edge is inclusive.
	var edge := Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * 50.0
	var index := targeting.nearest_in_facing(Vector2.ZERO, Vector2.RIGHT, [edge], 120.0, 30.0)
	assert_eq(index, 0)


func test_nearest_in_facing_returns_negative_one_beyond_range():
	var far := Vector2(500, 0)
	var index := targeting.nearest_in_facing(Vector2.ZERO, Vector2.RIGHT, [far], 120.0, 30.0)
	assert_eq(index, -1)


func test_nearest_in_facing_picks_the_closest_of_several_valid_candidates():
	var near := Vector2(30, 0)
	var far := Vector2(80, 0)
	var index := targeting.nearest_in_facing(Vector2.ZERO, Vector2.RIGHT, [far, near], 120.0, 30.0)
	assert_eq(index, 1)


func test_nearest_in_facing_with_a_zero_facing_direction_hits_nothing():
	var index := targeting.nearest_in_facing(Vector2.ZERO, Vector2.ZERO, [Vector2(10, 0)], 120.0, 30.0)
	assert_eq(index, -1, "an undefined facing direction can't define a cone")


func test_in_area_returns_every_candidate_within_radius():
	var inside_a := Vector2(5, 0)
	var inside_b := Vector2(0, 8)
	var outside := Vector2(100, 0)
	var hit := targeting.in_area(Vector2.ZERO, [inside_a, inside_b, outside], 10.0)
	assert_eq(hit, [0, 1])


func test_area_center_offsets_along_facing_direction():
	var center := targeting.area_center(Vector2.ZERO, Vector2.RIGHT, 40.0)
	assert_eq(center, Vector2(40, 0))


func test_area_center_falls_back_to_caster_position_with_no_facing():
	var center := targeting.area_center(Vector2(3, 4), Vector2.ZERO, 40.0)
	assert_eq(center, Vector2(3, 4))
