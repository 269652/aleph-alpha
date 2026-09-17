extends GutTest

## Reported in play: "the river is clipped to the windows original size when
## toggling fullscreen".
##
## The river is not drawn straight into the world canvas -- it renders into
## a SubViewport of its own (RiverFlowPass) sized from how much world the
## frame shows, which World derives from get_viewport_rect().size every
## frame. That rect follows the window's content scale, and the content
## scale is computed from the window's size by _apply_render_resolution --
## which only ever ran when the RESOLUTION OPTION changed. Toggling
## fullscreen changes the window and nothing recomputed the content scale,
## so the framed world stayed whatever it was before the toggle and the
## river's viewport stayed that size: a rectangle of river, clipped to the
## old window, with the rest of the frame drawn around it.
##
## The fix is not to patch the fullscreen branch: a window also changes size
## when the player drags its edge or moves it to another monitor. World
## follows the window's own size_changed signal instead, so every one of
## those is handled by the same rule.

const World = preload("res://scenes/world.gd")
const RenderResolution = preload("res://src/rendering/render_resolution.gd")


func test_world_follows_a_windows_resizes_once_it_has_applied_its_resolution():
	# The window is injected rather than fetched: a bare World cannot reach
	# one without entering the tree, and entering it runs _ready against
	# scene children an isolated World does not have. _apply_render_
	# resolution passes its own get_window() here, so this pins the rule
	# that function applies.
	var world := World.new()
	autofree(world)
	var window := Window.new()
	add_child_autofree(window)

	world._follow_window_resizes(window)

	assert_true(
		window.size_changed.is_connected(world._apply_render_resolution),
		"nothing recomputed the content scale when the window changed, so the river kept the old frame"
	)


func test_following_a_window_twice_connects_it_once():
	# _apply_render_resolution runs on every resolution change and on every
	# resize it is itself connected to, so this has to be idempotent or the
	# signal fans out into a growing pile of duplicate calls.
	var world := World.new()
	autofree(world)
	var window := Window.new()
	add_child_autofree(window)

	world._follow_window_resizes(window)
	world._follow_window_resizes(window)

	assert_eq(window.size_changed.get_connections().size(), 1)


func test_following_no_window_at_all_is_a_no_op():
	var world := World.new()
	autofree(world)
	world._follow_window_resizes(null)
	pass_test("a World without a window simply never follows one")


# -- why a stale content scale is visible at all --------------------------


func test_a_scaled_render_resolution_really_does_depend_on_the_window_size():
	# If it did not, a stale one would be harmless. It is not: the same
	# option on two window sizes is two different framebuffers, so keeping
	# the pre-fullscreen one keeps the pre-fullscreen frame.
	var small := RenderResolution.render_size("half", Vector2i(1280, 720))
	var large := RenderResolution.render_size("half", Vector2i(2560, 1440))
	assert_ne(small, large)
