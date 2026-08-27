extends GutTest

## RainOverlay: actually VISIBLE falling rain (see rain_overlay.gd).
##
## Rain existed only as a `rain_intensity` uniform driving water ripples and
## a word in the HUD -- during a downpour nothing fell anywhere on screen
## (reported: "it's raining but there are no visible raindrops falling").
##
## Contract tests only; the drawn result can't be asserted headless, the same
## limitation test_water_shader.gd works around.

const RainOverlay = preload("res://src/rendering/rain_overlay.gd")

var rain: RainOverlay


func before_each():
	rain = RainOverlay.new()


func test_make_material_returns_a_shader_material_with_a_shader():
	var material := rain.make_material()
	assert_true(material is ShaderMaterial)
	assert_not_null(material.shader)


func test_shader_draws_animated_screen_space_streaks():
	var code: String = RainOverlay.SHADER_CODE
	assert_string_contains(code, "shader_type canvas_item")
	assert_string_contains(code, "TIME")
	# Placement moved from the fragment stage (FRAGCOORD) to the vertex
	# stage: the streak shape is now the quad, so nothing is carved per
	# pixel any more -- see the header note on why the drops are geometry.
	assert_string_contains(code, "void vertex()")
	assert_string_contains(code, "INSTANCE_CUSTOM")


## Dry weather must cost nothing and show nothing -- the overlay is always
## mounted, so a zero default is what keeps a clear day clear.
func test_rain_is_off_by_default():
	assert_eq(rain.make_material().get_shader_parameter("intensity"), 0.0)


func test_set_intensity_updates_the_shared_materials_uniform():
	var material := rain.shared_material()
	rain.set_intensity(1.0)
	assert_eq(material.get_shader_parameter("intensity"), 1.0)
	rain.set_intensity(0.0)
	assert_eq(material.get_shader_parameter("intensity"), 0.0)


func test_set_intensity_clamps_out_of_range_values():
	var material := rain.shared_material()
	rain.set_intensity(5.0)
	assert_eq(material.get_shader_parameter("intensity"), 1.0)
	rain.set_intensity(-3.0)
	assert_eq(material.get_shader_parameter("intensity"), 0.0)


func test_shared_material_is_reused():
	assert_eq(rain.shared_material(), rain.shared_material())


# -- how a drop looks -------------------------------------------------------

## A raindrop is a falling STREAK, not a dot -- length has to beat width or
## it reads as static noise rather than rain.
func test_a_drop_is_a_streak_not_a_dot():
	assert_gt(RainOverlay.STREAK_LENGTH, RainOverlay.STREAK_WIDTH * 3.0)
	var mesh_size := RainOverlay.drop_mesh_size()
	assert_gt(mesh_size.y, mesh_size.x * 3.0, "and the quad it is drawn as agrees")


## Chunky enough to read as pixel art rather than a hairline scratch, in
## keeping with the rest of the art (see docs/concept/pixel_art_engine.md).
func test_a_drop_is_chunky_enough_to_read_as_pixel_art():
	assert_gte(RainOverlay.STREAK_WIDTH, 2.0)


func test_drops_actually_fall():
	assert_gt(RainOverlay.FALL_SPEED, 0.0)


## Rain must fall DOWN. Screen-space y grows downward, so the shader's
## `travel` term has to SUBTRACT elapsed distance -- adding it solves to a
## drop head whose y shrinks over time, i.e. rain climbing the screen
## (reported: "rain is falling from bottom to top not the other way round").
## drop_head_y mirrors that term so the direction is pinned on the CPU.
func test_drops_fall_downward_not_upward():
	var previous := RainOverlay.drop_head_y(0.0)
	# Sampled well inside one wrap period, so a decrease can only mean the
	# stream is travelling the wrong way rather than having wrapped around.
	var period: float = RainOverlay.DROP_SPACING / RainOverlay.FALL_SPEED
	for step in range(1, 6):
		var time: float = period * 0.15 * float(step)
		var current := RainOverlay.drop_head_y(time)
		assert_gt(current, previous, "a drop's screen y must grow (fall) over time")
		previous = current


func test_a_drops_fall_wraps_around_instead_of_running_off_forever():
	var period: float = RainOverlay.DROP_SPACING / RainOverlay.FALL_SPEED
	assert_almost_eq(RainOverlay.drop_head_y(period), RainOverlay.drop_head_y(0.0), 0.01)


## Rain reads as pale blue-white and must stay translucent -- opaque drops
## would punch holes through the world behind them.
func test_drops_are_pale_blue_and_translucent():
	assert_lt(RainOverlay.DROP_COLOR.a, 1.0, "drops must not be opaque")
	assert_gt(RainOverlay.DROP_COLOR.b, RainOverlay.DROP_COLOR.r, "rain should read cool, not warm")
	assert_gt(RainOverlay.DROP_COLOR.b, 0.5, "drops should read pale against dark ground")


## Rain falls at a slight angle, not as a perfectly vertical grid -- dead
## vertical streaks read as a screen-door artifact.
func test_rain_falls_at_a_slight_angle():
	assert_gt(absf(RainOverlay.SLANT), 0.0)
	assert_lt(absf(RainOverlay.SLANT), 1.0, "rain should lean, not fly sideways")


## The tuning the CPU pins must be what the GPU actually draws with --
## duplicated literals in the shader source would let the two drift apart.
## Streak SIZE and fall SPEED are no longer uniforms: the size is the quad's
## own dimensions and the speed rides in each instance's custom data, so
## there is nothing left for a duplicated literal to drift from.
func test_make_material_pushes_the_drop_tuning_uniforms():
	var material := rain.make_material()
	assert_eq(material.get_shader_parameter("slant"), RainOverlay.SLANT)
	assert_eq(material.get_shader_parameter("column_width"), RainOverlay.COLUMN_WIDTH)
	assert_eq(material.get_shader_parameter("fall_span"), RainOverlay.FALL_SPAN)
	assert_eq(material.get_shader_parameter("drop_color"), RainOverlay.DROP_COLOR)


func test_every_drop_carries_its_own_stream_in_its_instance_data():
	var drops := rain.build_drops()
	var speeds := {}
	for i in drops.multimesh.instance_count:
		var custom := drops.multimesh.get_instance_custom_data(i)
		# Channels are 0..1 fractions: instance custom data is 8 bits per
		# channel in this renderer, so raw pixel values read back as 0.
		for channel in [custom.r, custom.g, custom.b, custom.a]:
			assert_between(channel, 0.0, 1.0, "drop %d stores fractions, not pixels" % i)
		assert_gt(RainOverlay.speed_for(i), 0.0, "drop %d must actually fall" % i)
		speeds[snappedf(RainOverlay.speed_for(i), 0.01)] = true
	assert_gt(speeds.size(), 1, "streams fall at different rates, not in lockstep")
	drops.free()


# -- the mounted overlay node ------------------------------------------------

func test_build_overlay_returns_a_canvas_layer_under_the_ui_layer():
	var overlay := rain.build_overlay()
	assert_true(overlay is CanvasLayer)
	assert_lt(
		overlay.layer, RainOverlay.UI_CANVAS_LAYER,
		"rain must draw beneath the HUD, not over it"
	)
	overlay.free()


## Screen-space: rain fills the view rather than tracking a world position,
## and the drop field carries the shared material so set_intensity reaches it.
func test_the_overlay_carries_the_shared_material():
	var overlay := rain.build_overlay()
	var drops: MultiMeshInstance2D = overlay.get_child(0)
	assert_eq(drops.material, rain.shared_material())
	overlay.free()


## Rain must never eat clicks meant for the world or the HUD beneath it. It
## no longer CAN: the drop field is a Node2D, not a Control, so there is no
## mouse_filter to get wrong -- which is what the full-screen rect needed.
func test_the_overlay_does_not_swallow_mouse_input():
	var overlay := rain.build_overlay()
	assert_false(overlay.get_child(0) is Control, "nothing in the rain layer takes input")
	overlay.free()


# -- rain costs what it covers, not what the screen is ------------------------
#
# Rain was one full-screen alpha-blended quad. Measured on this machine's
# integrated GPU: hiding it took the game from 42 fps to 57.7, and the frame
# spikes with it -- and the cost was NOT the shader. A trivial `COLOR =
# vec4(0.0)` fragment still cost the same 15 fps, a plain untextured
# translucent ColorRect the same again, and shrinking the SAME shader to a
# 64x64 rect gave nearly all of it back. What the pass costs is the SCREEN
# AREA it rasterises, and vsync turns "just over 16.7ms" into a dropped frame,
# which is why rain read as heavy lag.
#
# Streaks cover about 1% of the screen. The overlay now rasterises only the
# streaks -- one MultiMesh instance per drop, positioned by the vertex shader
# off TIME -- instead of every pixel between them.

func test_the_overlay_draws_only_the_drops_not_the_whole_screen():
	var overlay := RainOverlay.new()
	var layer := overlay.build_overlay()
	var drops := layer.get_node("RainDrops") as MultiMeshInstance2D
	assert_not_null(drops, "rain is drawn as drop geometry")
	assert_not_null(drops.multimesh)
	autofree(layer)


## The whole point: rasterised area is a small fraction of the screen. Any
## regression that puts rain back on a full-screen quad fails here.
func test_rain_rasterises_a_small_fraction_of_the_screen():
	var overlay := RainOverlay.new()
	var layer := overlay.build_overlay()
	var drops := layer.get_node("RainDrops") as MultiMeshInstance2D
	var covered := (
		float(drops.multimesh.instance_count) * RainOverlay.STREAK_WIDTH * RainOverlay.STREAK_LENGTH
	)
	var screen := RainOverlay.DESIGN_WIDTH * RainOverlay.DESIGN_HEIGHT
	assert_lt(covered / screen, 0.05, "rain must cover a few percent of the screen, not all of it")
	autofree(layer)


## Enough drops that a downpour still reads as continuous rain: every column
## carries a full stream from the top of the screen to the bottom.
func test_there_are_enough_drops_to_fill_the_screen():
	assert_gte(
		RainOverlay.instance_count(), RainOverlay.column_count() * RainOverlay.drops_per_column()
	)
	assert_gte(RainOverlay.column_count(), int(RainOverlay.DESIGN_WIDTH / RainOverlay.COLUMN_WIDTH))
	assert_gte(
		RainOverlay.drops_per_column(), int(RainOverlay.DESIGN_HEIGHT / RainOverlay.DROP_SPACING)
	)


# -- snow is not rain painted white ------------------------------------------
#
# set_snowing swapped exactly three things -- drop_color, fall_speed, slant --
# and the drop's SHAPE was baked into the QuadMesh at STREAK_WIDTH x
# STREAK_LENGTH with no uniform that could touch it. So a snowstorm rendered
# 11px falling STREAKS in white, reported as rain still falling during a
# snowstorm. A streak is motion blur, and a flake drifting seven times slower
# than rain has none to blur. Nothing here exercised set_snowing at all, which
# is how it survived.


## A flake must not read as a falling streak, in either direction.
func test_a_snowflake_is_a_fleck_not_a_falling_streak():
	assert_string_contains(
		RainOverlay.SHADER_CODE, "drop_length_scale",
		"the GPU has to be told the drop's length, or only the colour changes"
	)
	rain.set_snowing(true)
	var scale = rain.shared_material().get_shader_parameter("drop_length_scale")
	assert_not_null(scale, "snowing must drive the drop's length, not just its colour")
	if scale == null:
		return
	var drawn: float = RainOverlay.STREAK_LENGTH * float(scale)
	assert_lte(
		drawn, RainOverlay.STREAK_WIDTH * 2.0,
		"a flake %.2fpx long is a falling streak, not a fleck" % drawn
	)
	assert_gte(
		drawn, RainOverlay.STREAK_WIDTH,
		"and it must stay a chunky pixel-art mark, not a sub-pixel dot"
	)
	rain.set_snowing(false)
	assert_eq(
		rain.shared_material().get_shader_parameter("drop_length_scale"), 1.0,
		"it streaks again once it warms"
	)


func test_the_drop_quad_starts_out_raining_not_snowing():
	assert_eq(rain.make_material().get_shader_parameter("drop_length_scale"), 1.0)


## The CPU constant and the value the GPU draws with cannot drift apart: the
## scale IS the ratio, derived rather than restated.
func test_a_flake_is_shorter_than_a_raindrops_streak():
	assert_lt(RainOverlay.FLAKE_LENGTH, RainOverlay.STREAK_LENGTH)
	assert_almost_eq(
		RainOverlay.drop_length_scale(true),
		RainOverlay.FLAKE_LENGTH / RainOverlay.STREAK_LENGTH,
		0.0001
	)
	assert_eq(RainOverlay.drop_length_scale(false), 1.0, "rain draws its quad at full length")


## One drop's quad is a streak, the same shape the fragment shader used to
## carve out of the full-screen rect.
func test_a_drop_quad_is_the_streak_shape():
	var mesh_size := RainOverlay.drop_mesh_size()
	assert_almost_eq(mesh_size.x, RainOverlay.STREAK_WIDTH, 0.001)
	assert_almost_eq(mesh_size.y, RainOverlay.STREAK_LENGTH, 0.001)


## Instances are spread across the columns rather than stacked in one place,
## and within a column they are spread down the screen -- otherwise "enough
## drops" would still rain in a single stripe.
func test_drops_are_spread_across_the_screen():
	var xs := {}
	var ys := {}
	for i in RainOverlay.instance_count():
		var placement := RainOverlay.placement_for(i)
		xs[int(placement.x / RainOverlay.COLUMN_WIDTH)] = true
		ys[int(placement.y / RainOverlay.DROP_SPACING)] = true
	assert_gte(xs.size(), RainOverlay.column_count() - 1, "every column carries rain")
	assert_gt(ys.size(), 1, "and drops are staggered down each column")


func test_every_drop_starts_on_screen():
	for i in RainOverlay.instance_count():
		var placement := RainOverlay.placement_for(i)
		assert_between(placement.x, -RainOverlay.COLUMN_WIDTH, RainOverlay.DESIGN_WIDTH)
		assert_between(placement.y, 0.0, RainOverlay.DESIGN_HEIGHT + RainOverlay.DROP_SPACING)
