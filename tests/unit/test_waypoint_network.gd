extends GutTest

const WaypointNetwork = preload("res://src/gameplay/waypoint_network.gd")

var waypoint_network: WaypointNetwork


func before_each():
	waypoint_network = WaypointNetwork.new()


func test_unlock_adds_a_known_waypoint_id_to_a_copy_of_the_array():
	var unlocked: Array = []
	var result: Array = waypoint_network.unlock(unlocked, "old_mill")
	assert_true(result.has("old_mill"))


func test_unlock_does_not_mutate_the_callers_original_array():
	var unlocked: Array = []
	waypoint_network.unlock(unlocked, "old_mill")
	assert_eq(unlocked.size(), 0)


func test_unlock_on_an_already_present_id_is_a_no_op():
	var unlocked: Array = ["old_mill"]
	var result: Array = waypoint_network.unlock(unlocked, "old_mill")
	assert_eq(result.size(), 1)
	assert_eq(result, ["old_mill"])


func test_unlock_on_an_unknown_waypoint_id_is_a_no_op():
	var unlocked: Array = []
	var result: Array = waypoint_network.unlock(unlocked, "nonexistent_place")
	assert_eq(result.size(), 0)


func test_is_unlocked_true_when_present():
	var unlocked: Array = ["old_mill"]
	assert_true(waypoint_network.is_unlocked(unlocked, "old_mill"))


func test_is_unlocked_false_when_absent():
	var unlocked: Array = []
	assert_false(waypoint_network.is_unlocked(unlocked, "old_mill"))


func test_reachable_waypoints_returns_positions_only_for_valid_unlocked_entries():
	var unlocked: Array = ["old_mill", "harbor_docks"]
	var result: Array = waypoint_network.reachable_waypoints(unlocked)
	assert_eq(result.size(), 2)
	for position in result:
		assert_true(position is Vector2)


func test_reachable_waypoints_ignores_a_bogus_unknown_id_that_snuck_into_unlocked():
	var unlocked: Array = ["old_mill", "made_up_place"]
	var result: Array = waypoint_network.reachable_waypoints(unlocked)
	assert_eq(result.size(), 1)


func test_nearest_unlocked_returns_the_genuinely_closest_waypoint():
	# old_mill, harbor_docks, stonepeak_pass, sunken_ruins, north_watch
	# constructed so from_position sits obviously closest to harbor_docks.
	var unlocked: Array = ["old_mill", "harbor_docks", "stonepeak_pass", "sunken_ruins", "north_watch"]
	var harbor_position: Vector2 = waypoint_network.KNOWN_WAYPOINTS["harbor_docks"]
	var from_position: Vector2 = harbor_position + Vector2(1.0, 1.0)
	var result: String = waypoint_network.nearest_unlocked(from_position, unlocked)
	assert_eq(result, "harbor_docks")


func test_nearest_unlocked_returns_empty_string_when_unlocked_is_empty():
	var unlocked: Array = []
	var result: String = waypoint_network.nearest_unlocked(Vector2.ZERO, unlocked)
	assert_eq(result, "")
