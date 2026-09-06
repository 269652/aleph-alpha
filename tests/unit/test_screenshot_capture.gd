extends GutTest

## ScreenshotCapture is the thin glue half of the screenshot feature (see
## docs/concept/screenshots.md and ScreenshotNaming's own pure half). Most
## of these tests stay headless-safe by injecting `_image_source` instead of
## exercising the real viewport read -- calling the real one under
## --headless raises its own engine-level error regardless of how
## gracefully the resulting Nil is handled afterward (see
## godot-install-location memory / test_river_flow_render_smoke.gd's
## identical guard), so the one test that needs a real frame is a separate,
## explicitly gated smoke test at the bottom.

const ScreenshotCapture = preload("res://src/ui/screenshot_capture.gd")
const ScreenshotNaming = preload("res://src/ui/screenshot_naming.gd")

var capture: ScreenshotCapture


func before_each():
	capture = ScreenshotCapture.new()
	add_child(capture)


func after_each():
	remove_child(capture)
	capture.free()
	InputMap.erase_action(ScreenshotCapture.ACTION)


func test_ready_registers_the_screenshot_action():
	assert_true(InputMap.has_action(ScreenshotCapture.ACTION))


func test_the_screenshot_action_is_bound_to_f12_by_default():
	var events := InputMap.action_get_events(ScreenshotCapture.ACTION)
	assert_eq(events.size(), 1, "exactly one bound event")
	assert_eq(events[0].physical_keycode, KEY_F12)


func test_a_screenshot_key_press_event_is_recognized_as_the_action():
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F12
	event.pressed = true
	assert_true(event.is_action_pressed(ScreenshotCapture.ACTION))


func test_pressing_the_key_calls_take_screenshot():
	var calls := {"count": 0}
	capture._image_source = func():
		calls["count"] += 1
		return null
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F12
	event.pressed = true
	capture._unhandled_input(event)
	assert_eq(calls["count"], 1)


func test_a_failed_capture_emits_screenshot_failed_not_a_crash():
	capture._image_source = func(): return null
	watch_signals(capture)
	capture.take_screenshot()
	assert_signal_emitted(capture, "screenshot_failed")
	assert_signal_not_emitted(capture, "screenshot_saved")


func test_a_successful_capture_saves_to_the_unique_path_and_emits_saved():
	var fake_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	capture._image_source = func(): return fake_image
	capture._now = func(): return {"year": 2026, "month": 9, "day": 6, "hour": 8, "minute": 3, "second": 9}
	# A fresh screenshots/ dir in a fresh worktree never has this exact
	# fixed-clock filename in it already, so the plain (non-collision) path
	# is the one real assertion worth pinning here -- ScreenshotNaming's own
	# tests already cover the collision-suffix search in isolation.
	var expected_path := ScreenshotNaming.path_for(capture._now.call())
	if FileAccess.file_exists(expected_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(expected_path))

	watch_signals(capture)
	capture.take_screenshot()

	assert_signal_emitted(capture, "screenshot_saved")
	var params = get_signal_parameters(capture, "screenshot_saved", 0)
	assert_eq(params[0], expected_path)
	assert_true(FileAccess.file_exists(expected_path), "a real file should exist at the emitted path")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(expected_path))


# -- one real-GPU smoke test: the actual viewport read, not an injected fake -
func _no_real_gpu() -> bool:
	if DisplayServer.get_name() != "headless":
		return false
	pending("no GPU readback under --headless; run with --rendering-driver opengl3")
	return true


func test_take_screenshot_captures_the_real_viewport():
	if _no_real_gpu():
		return
	watch_signals(capture)
	capture.take_screenshot()
	assert_signal_emitted(capture, "screenshot_saved")
	var params = get_signal_parameters(capture, "screenshot_saved", 0)
	var path: String = params[0]
	assert_true(FileAccess.file_exists(path), "expected a real file at %s" % path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
