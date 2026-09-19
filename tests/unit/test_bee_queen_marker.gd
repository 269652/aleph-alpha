extends GutTest

## BeeQueenMarker (src/rendering/bee_queen_marker.gd): the hive's queen, a
## visual whose presence follows the colony's real queen state every
## REFRESH_INTERVAL_SECONDS. FPS regression round 13: that refresh comes
## from a Timer child now, not from an engine _process paying ~7 us of
## dispatch every frame per queen.

const BeeQueenMarker = preload("res://src/rendering/bee_queen_marker.gd")

var marker: BeeQueenMarker


func before_each():
	marker = BeeQueenMarker.new()
	add_child_autofree(marker)


func test_the_refresh_comes_from_a_timer_not_from_engine_frames():
	assert_false(marker.is_processing(), "no per-frame dispatch")
	var timer := marker.get_node_or_null("TickTimer") as Timer
	assert_not_null(timer)
	assert_almost_eq(timer.wait_time, BeeQueenMarker.REFRESH_INTERVAL_SECONDS, 0.0001)
	# is_stopped(), not autostart: Godot's own Timer CLEARS autostart the
	# moment it acts on it (NOTIFICATION_READY starts the timer and sets
	# autostart false), so reading it back from a marker already in the tree
	# can only ever be false. Asserting the timer is genuinely RUNNING is
	# what this line was always trying to say, and it is true of the real
	# marker either way.
	assert_false(timer.is_stopped(), "running the moment the marker is in the tree")
	assert_false(timer.one_shot)


func test_a_refresh_without_a_colony_is_harmless():
	(marker.get_node("TickTimer") as Timer).timeout.emit()
	pass_test("no colony: _process returns before touching anything")
