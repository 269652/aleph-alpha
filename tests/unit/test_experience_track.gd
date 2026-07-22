extends GutTest

const ExperienceTrack = preload("res://src/gameplay/experience_track.gd")

var xp: ExperienceTrack


func before_each():
	xp = ExperienceTrack.new()


func test_starts_at_level_one_with_no_points():
	assert_eq(xp.level, 1)
	assert_eq(xp.total_xp, 0)
	assert_eq(xp.unspent_points, 0)


func test_xp_for_next_level_grows_with_level():
	assert_gt(xp.xp_for_next_level(), 0)
	var early := xp.xp_for_next_level()
	xp.add_xp(early)  # reach level 2
	assert_gt(xp.xp_for_next_level(), early, "later levels should cost more XP")


func test_adding_enough_xp_levels_up_and_grants_a_point():
	var gained := xp.add_xp(xp.xp_for_next_level())
	assert_eq(gained, 1)
	assert_eq(xp.level, 2)
	assert_eq(xp.unspent_points, 1)


func test_a_big_xp_dump_can_grant_multiple_levels():
	var gained := xp.add_xp(100000)
	assert_gt(gained, 1)
	assert_eq(xp.unspent_points, gained)
	assert_eq(xp.level, 1 + gained)


func test_partial_xp_does_not_level_up():
	var gained := xp.add_xp(1)
	assert_eq(gained, 0)
	assert_eq(xp.level, 1)


func test_progress_fraction_is_in_range_and_reflects_partial_xp():
	assert_almost_eq(xp.progress_fraction(), 0.0, 0.001)
	xp.add_xp(int(xp.xp_for_next_level() / 2))
	assert_between(xp.progress_fraction(), 0.4, 0.6)


func test_xp_into_level_resets_after_leveling():
	xp.add_xp(xp.xp_for_next_level())  # exactly to level 2
	assert_eq(xp.xp_into_level(), 0)


func test_spending_points_reduces_unspent():
	xp.add_xp(100000)
	var before := xp.unspent_points
	assert_true(xp.spend_point())
	assert_eq(xp.unspent_points, before - 1)


func test_cannot_spend_points_you_do_not_have():
	assert_false(xp.spend_point())


func test_spend_points_spends_multiple_when_available():
	xp.add_xp(100000)
	var before := xp.unspent_points
	assert_true(xp.spend_points(2))
	assert_eq(xp.unspent_points, before - 2)


func test_spend_points_fails_when_not_enough():
	xp.add_xp(xp.xp_for_next_level())  # exactly 1 point
	assert_false(xp.spend_points(2))
	assert_eq(xp.unspent_points, 1)
