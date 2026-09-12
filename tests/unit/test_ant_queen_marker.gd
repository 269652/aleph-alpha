extends GutTest

## AntQueenMarker (src/rendering/ant_queen_marker.gd): the mound's queen, a
## visual whose presence follows the colony's real queen state every
## REFRESH_INTERVAL_SECONDS. FPS regression round 13: that refresh comes
## from a Timer child now, not from an engine _process paying ~7 us of
## dispatch every frame per queen (60 of them loaded at once).

const AntQueenMarker = preload("res://src/rendering/ant_queen_marker.gd")

var marker: AntQueenMarker


func before_each():
	marker = AntQueenMarker.new()
	add_child_autofree(marker)


func test_the_refresh_comes_from_a_timer_not_from_engine_frames():
	assert_false(marker.is_processing(), "no per-frame dispatch")
	var timer := marker.get_node_or_null("TickTimer") as Timer
	assert_not_null(timer)
	assert_almost_eq(timer.wait_time, AntQueenMarker.REFRESH_INTERVAL_SECONDS, 0.0001)
	assert_true(timer.autostart)
	assert_false(timer.one_shot)


func test_a_refresh_without_a_colony_is_harmless():
	(marker.get_node("TickTimer") as Timer).timeout.emit()
	pass_test("no colony: _process returns before touching anything")
