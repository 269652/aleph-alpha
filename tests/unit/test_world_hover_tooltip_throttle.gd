extends GutTest

## World's hover-tooltip rescan gate (see World._hover_rescan_due, and
## HOVER_REFRESH_INTERVAL / HOVER_IDLE_REFRESH_INTERVAL). Same shape as
## test_world_interaction_prompt_throttle.gd: a bare World.new(), never added
## to the tree, driven through the gate directly.
##
## FPS regression round 10 (docs/concept/soil_fauna.md): _update_hover_tooltip
## walks EVERY hoverable node in the world (24 marker classes, thousands of
## nodes) with a per-node distance check, measured live at ~6.7ms per call --
## and its ~30 Hz cadence is a wall-clock interval, so at 4 fps it ran on
## every single frame. The scan only has anything new to say when the mouse
## has moved or, with the mouse still, when something may have walked under
## it -- so a stationary mouse now rescans at HOVER_IDLE_REFRESH_INTERVAL,
## and the ~30 Hz cadence is only paid while the mouse is actually moving.

const World = preload("res://scenes/world.gd")

const FRAME := 1.0 / 60.0
const MOUSE := Vector2(400.0, 300.0)

var world: World


func before_each():
	world = World.new()


func after_each():
	world.free()


func _rescans_over(frames: int, mouse_for_frame: Callable) -> int:
	var rescans := 0
	for frame in frames:
		if world._hover_rescan_due(FRAME, mouse_for_frame.call(frame)):
			rescans += 1
	return rescans


func test_the_idle_refresh_interval_is_exactly_pinned():
	assert_eq(World.HOVER_IDLE_REFRESH_INTERVAL, 0.25)
	assert_gt(World.HOVER_IDLE_REFRESH_INTERVAL, World.HOVER_REFRESH_INTERVAL, "idle must be the slower of the two cadences")


func test_the_very_first_frame_always_scans():
	assert_true(world._hover_rescan_due(FRAME, MOUSE), "nothing has ever been scanned, so there is nothing to be stale relative to")


func test_a_stationary_mouse_rescans_at_the_idle_rate_not_the_hover_rate():
	var rescans := _rescans_over(60, func(_frame: int) -> Vector2: return MOUSE)
	var idle_per_second := int(1.0 / World.HOVER_IDLE_REFRESH_INTERVAL)
	assert_between(rescans, idle_per_second - 1, idle_per_second + 1, "one second at 60fps with the mouse still: a handful of rescans, not thirty")


func test_a_moving_mouse_rescans_at_the_hover_rate():
	var rescans := _rescans_over(60, func(frame: int) -> Vector2: return MOUSE + Vector2(float(frame), 0.0))
	var hover_per_second := int(1.0 / World.HOVER_REFRESH_INTERVAL)
	assert_between(rescans, hover_per_second - 3, hover_per_second + 1, "one second at 60fps with the mouse moving: the full ~30 Hz cadence")


func test_a_mouse_that_moves_once_then_rests_scans_the_move_then_settles_to_the_idle_rate():
	_rescans_over(30, func(_frame: int) -> Vector2: return MOUSE)  # settle
	var moved := MOUSE + Vector2(5.0, 0.0)
	# Wait out the hover cadence with the mouse still, then move it: the very
	# next due frame must pick the move up.
	var due_after_move := false
	for frame in 3:
		due_after_move = world._hover_rescan_due(FRAME, moved) or due_after_move
	assert_true(due_after_move, "a move is picked up on the next hover-cadence frame")
	var settled := _rescans_over(60, func(_frame: int) -> Vector2: return moved)
	assert_lte(settled, int(1.0 / World.HOVER_IDLE_REFRESH_INTERVAL) + 1, "at rest again: back to the idle rate")
