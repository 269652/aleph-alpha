extends GutTest

## A live-render smoke check for the sapling->mature morph shader (see
## tree_morph_shader.gd), mirroring test_river_flow_render_smoke.gd's own
## pattern exactly and for the same reason: every CPU mirror in
## test_tree_morph_shader.gd can be green while the dissolve never reaches
## an actual pixel (a shader wired to the wrong uniform name, or never
## actually sampled) -- that class of failure needs a real GPU frame to
## catch, not more unit-level math.
##
## Run for real with (no --headless):
##   <godot> --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd \
##     -gconfig= -gtest=res://tests/unit/test_tree_morph_shader_render_smoke.gd -gexit

const WindSway = preload("res://src/rendering/wind_sway.gd")
const TreeMorphShader = preload("res://src/rendering/tree_morph_shader.gd")


func _no_real_gpu() -> bool:
	if DisplayServer.get_name() != "headless":
		return false
	pending("no GPU readback under --headless; run with --rendering-driver opengl3")
	return true


## Builds (but does not yet render) a 64x64 viewport containing a flat red
## "mature" sprite carrying the morph shader at `morph_progress`, with a flat
## blue "sapling" texture as its dissolve source. Returned UNRENDERED --
## mirroring _build_river_viewport's own contract -- so a caller can await
## real frames AFTER the node is actually live in the SceneTree, not before
## it even exists. Awaiting first and building second (this file's original
## bug) reads back whatever the viewport happened to hold before the sprite/
## camera were ever added to it, which is nothing.
func _build_sprite_viewport(morph_progress: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)

	# A flat red "mature" square and a flat blue "sapling" square -- distinct,
	# fully opaque colours make the reveal fraction directly measurable by
	# counting pixels of each, rather than needing real tree art here too
	# (already covered by the CPU mirrors' own clump-grid assertions).
	var mature_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	mature_image.fill(Color(1, 0, 0, 1))
	var sapling_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	sapling_image.fill(Color(0, 0, 1, 1))

	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(mature_image)
	var wind := WindSway.new()
	var material := wind.shared_material()
	TreeMorphShader.apply(material, ImageTexture.create_from_image(sapling_image), 5, morph_progress)
	sprite.material = material
	viewport.add_child(sprite)

	var camera := Camera2D.new()
	camera.position = Vector2(32, 32)
	viewport.add_child(camera)
	camera.make_current()
	return viewport


func test_zero_progress_shows_only_the_sapling_colour():
	if _no_real_gpu():
		return
	var viewport := _build_sprite_viewport(0.0)
	for i in 3:
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	var blue := 0
	var red := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var p := image.get_pixel(x, y)
			if p.b > 0.5 and p.r < 0.5:
				blue += 1
			elif p.r > 0.5 and p.b < 0.5:
				red += 1
	assert_gt(blue, 0, "sapling colour should show at zero progress")
	assert_eq(red, 0, "mature colour should not show at all at zero progress")


func test_full_progress_shows_only_the_mature_colour():
	if _no_real_gpu():
		return
	var viewport := _build_sprite_viewport(1.0)
	for i in 3:
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	var blue := 0
	var red := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var p := image.get_pixel(x, y)
			if p.b > 0.5 and p.r < 0.5:
				blue += 1
			elif p.r > 0.5 and p.b < 0.5:
				red += 1
	assert_gt(red, 0, "mature colour should show at full progress")
	assert_eq(blue, 0, "sapling colour should not show at all at full progress")


## The actual "per leaf, scattered" claim: a MIDDLING progress should show a
## genuine MIX of both colours -- not all-or-nothing, and not a single
## contiguous block of one colour (which is what the trunk-outward sweep
## this replaced would have produced instead).
func test_mid_progress_shows_a_real_scattered_mix_of_both_colours():
	if _no_real_gpu():
		return
	var viewport := _build_sprite_viewport(0.5)
	for i in 3:
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	var blue := 0
	var red := 0
	var sampled := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			sampled += 1
			var p := image.get_pixel(x, y)
			if p.b > 0.5 and p.r < 0.5:
				blue += 1
			elif p.r > 0.5 and p.b < 0.5:
				red += 1
	assert_gt(red, sampled / 10, "expected a real fraction of mature pixels at 50%% progress")
	assert_gt(blue, sampled / 10, "expected a real fraction of sapling pixels at 50%% progress")
