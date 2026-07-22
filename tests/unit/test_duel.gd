extends GutTest

const Duel = preload("res://src/gameplay/duel.gd")

var duel: Duel


func before_each():
	duel = Duel.new()


func test_request_duel_returns_requested_state_with_full_timeout():
	var result := duel.request_duel()
	assert_eq(result.state, "requested")
	assert_eq(result.time_remaining, Duel.REQUEST_TIMEOUT)


func test_advance_counts_down_time_remaining():
	var result := duel.advance("requested", 10.0, 4.0)
	assert_almost_eq(result.time_remaining, 6.0, 0.001)
	assert_eq(result.state, "requested")


func test_advance_transitions_requested_to_expired_at_exactly_zero_remaining():
	var result := duel.advance("requested", 0.1, 0.1)
	assert_eq(result.state, "expired")
	assert_eq(result.time_remaining, 0.0)


func test_advance_leaves_none_state_alone_aside_from_timer():
	var result := duel.advance("none", 5.0, 1.0)
	assert_eq(result.state, "none")
	assert_almost_eq(result.time_remaining, 4.0, 0.001)


func test_advance_leaves_accepted_state_alone_aside_from_timer():
	var result := duel.advance("accepted", 5.0, 1.0)
	assert_eq(result.state, "accepted")
	assert_almost_eq(result.time_remaining, 4.0, 0.001)


func test_accept_transitions_requested_to_accepted():
	assert_eq(duel.accept("requested"), "accepted")


func test_accept_on_non_requested_state_is_noop():
	assert_eq(duel.accept("accepted"), "accepted")
	assert_eq(duel.accept("declined"), "declined")
	assert_eq(duel.accept("none"), "none")
	assert_eq(duel.accept("expired"), "expired")


func test_decline_transitions_requested_to_declined():
	assert_eq(duel.decline("requested"), "declined")


func test_decline_on_non_requested_state_is_noop():
	assert_eq(duel.decline("accepted"), "accepted")
	assert_eq(duel.decline("declined"), "declined")
	assert_eq(duel.decline("none"), "none")
	assert_eq(duel.decline("expired"), "expired")


func test_is_active_true_only_for_accepted():
	assert_true(duel.is_active("accepted"))
	assert_false(duel.is_active("requested"))
	assert_false(duel.is_active("none"))
	assert_false(duel.is_active("declined"))
	assert_false(duel.is_active("expired"))


func test_can_request_true_for_none_declined_expired():
	assert_true(duel.can_request("none"))
	assert_true(duel.can_request("declined"))
	assert_true(duel.can_request("expired"))


func test_can_request_false_for_requested_accepted():
	assert_false(duel.can_request("requested"))
	assert_false(duel.can_request("accepted"))


func test_is_pvp_allowed_in_zone_true_when_zone_flagged_regardless_of_duel_state():
	assert_true(duel.is_pvp_allowed_in_zone(true, "none"))
	assert_true(duel.is_pvp_allowed_in_zone(true, "requested"))


func test_is_pvp_allowed_in_zone_true_when_duel_state_accepted_regardless_of_zone_flagged():
	assert_true(duel.is_pvp_allowed_in_zone(false, "accepted"))
	assert_true(duel.is_pvp_allowed_in_zone(true, "accepted"))


func test_is_pvp_allowed_in_zone_false_when_neither_condition_holds():
	assert_false(duel.is_pvp_allowed_in_zone(false, "none"))
	assert_false(duel.is_pvp_allowed_in_zone(false, "requested"))
	assert_false(duel.is_pvp_allowed_in_zone(false, "declined"))
	assert_false(duel.is_pvp_allowed_in_zone(false, "expired"))
