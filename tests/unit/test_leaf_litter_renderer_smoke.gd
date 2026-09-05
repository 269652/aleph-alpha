extends GutTest

## A live-render smoke check for the GPU leaf-litter overlay
## (leaf_litter_renderer.gd, leaf_litter_atlas.gd) -- everything CPU-testable
## about this feature (packing, the ported fall/sway math, atlas cropping)
## already has dedicated coverage in test_leaf_litter_renderer.gd and
## test_leaf_litter_atlas.gd; this test instead builds the exact real
## MultiMeshInstance2D + ShaderMaterial combination EarthChunkManager wires
## for real, adds it to a LIVE SceneTree/SubViewport, and lets it actually
## run and render -- if the shader failed to compile or the vertex-offset
## math never reached the GPU, this is the only place either would show up.
## Mirrors test_river_flow_render_smoke.gd's own established pattern for
## this project.
##
## Run for real with (no GPU readback under --headless):
##   <godot> --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd \
##     -gconfig= -gtest=res://tests/unit/test_leaf_litter_renderer_smoke.gd -gexit

const LeafLitterRenderer = preload("res://src/rendering/leaf_litter_renderer.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")


func _no_real_gpu() -> bool:
	if DisplayServer.get_name() != "headless":
		return false
	pending("no GPU readback under --headless; run with --rendering-driver opengl3")
	return true


func test_a_real_multimesh_with_the_shared_material_runs_several_frames_with_no_engine_error():
	var renderer := LeafLitterRenderer.new()
	var mmi := MultiMeshInstance2D.new()
	add_child_autofree(mmi)
	var leaves: Array[Dictionary] = [{
		"position": Vector2(100, 100), "transition_from": Vector2(100, 100),
		"species": "cherry", "season": "autumn", "transition_start": 0.0,
	}]
	renderer.fill(mmi, leaves)

	assert_true(mmi.material is ShaderMaterial, "precondition: a real ShaderMaterial is assigned")
	assert_eq(mmi.multimesh.instance_count, 1)

	# Let the engine actually process/draw several frames with this node
	# live in the tree -- a shader compile failure surfaces as a real
	# engine error during this, not silently.
	for i in range(5):
		await get_tree().process_frame

	assert_true(is_instance_valid(mmi), "the node must still be alive after several live frames")
	assert_true(mmi.material is ShaderMaterial, "the material must still be attached after several live frames")
	assert_eq(mmi.multimesh.instance_count, 1, "the filled instance count must be unaffected by rendering")


## Builds (but does not yet render) a small viewport with one leaf instance,
## camera centred on `world_offset`. Zoomed in hard: a leaf is only ~5 world
## units wide (LeafLitterRenderer.WORLD_SIZE), so a normal gameplay camera
## zoom would show it as a handful of pixels -- too few to sample reliably.
func _build_leaf_viewport(leaves: Array[Dictionary], world_offset: Vector2) -> SubViewport:
	var renderer := LeafLitterRenderer.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)

	var mmi := MultiMeshInstance2D.new()
	viewport.add_child(mmi)
	renderer.fill(mmi, leaves)

	var camera := Camera2D.new()
	camera.zoom = Vector2(8.0, 8.0)
	camera.position = world_offset
	viewport.add_child(camera)
	camera.make_current()
	return viewport


func _visible_fraction(image: Image) -> float:
	var visible := 0
	var sampled := 0
	for py in range(0, image.get_height(), 2):
		for px in range(0, image.get_width(), 2):
			sampled += 1
			if image.get_pixel(px, py).a > 0.1:
				visible += 1
	return float(visible) / float(maxi(sampled, 1))


## THE real-art-samples-correctly check, on the real GPU -- proof the
## fragment shader's atlas UV math (see LeafLitterRenderer's own vertex()
## cell_x0/x1/y0/y1 derivation) actually lands on real content rather than
## the atlas's own transparent gutter or an unrelated neighbouring cell.
func test_a_settled_leaf_actually_renders_visible_pixels_at_its_position():
	if _no_real_gpu():
		return
	var target := Vector2(200, 200)
	var leaves: Array[Dictionary] = [{
		"position": target, "transition_from": target,
		"species": "cherry", "season": "autumn", "transition_start": 0.0,
	}]
	var viewport := _build_leaf_viewport(leaves, target)
	for i in range(4):
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return  # no GPU readback in this environment
	assert_gt(
		_visible_fraction(image), 0.01,
		"a settled leaf drew no visible pixels at all -- the shader/atlas sampling is broken"
	)


## THE vertex-offset check, on the real GPU -- the only place the reported
## "leaves should visibly fall/scatter" symptom can actually be observed
## rather than just reasoned about from the GDScript mirror. A leaf whose
## transition just started (t == 0, full FALL_HEIGHT offset still applied)
## must render DIFFERENTLY from an otherwise-identical, already-settled leaf
## (t == 1, zero offset) -- proof the GPU vertex shader is actually moving
## instances, not merely that it compiles and textures something in place.
func test_a_freshly_started_transition_renders_away_from_its_settled_position():
	if _no_real_gpu():
		return
	var target := Vector2(400, 400)
	var settled: Array[Dictionary] = [{
		"position": target, "transition_from": target,
		"species": "cherry", "season": "autumn", "transition_start": 0.0,
	}]
	var falling: Array[Dictionary] = [{
		"position": target,
		"transition_from": target - Vector2(0.0, LeafLitterField.FALL_HEIGHT),
		"species": "cherry", "season": "autumn",
		# Both viewports share the material's own default current_time_
		# fraction (0.0, neither ever calls set_current_time) -- packing
		# transition_start as 0.0 here too makes elapsed read as exactly
		# zero (t == 0, the full offset still applies), isolating the
		# transition math itself rather than a clock mismatch between the
		# two viewports.
		"transition_start": 0.0,
	}]
	var settled_viewport := _build_leaf_viewport(settled, target)
	var falling_viewport := _build_leaf_viewport(falling, target)
	for i in range(4):
		await get_tree().process_frame
	var settled_image := settled_viewport.get_texture().get_image()
	var falling_image := falling_viewport.get_texture().get_image()
	settled_viewport.queue_free()
	falling_viewport.queue_free()
	if settled_image == null or falling_image == null:
		return  # no GPU readback in this environment

	var changed := 0
	var sampled := 0
	for py in range(0, settled_image.get_height(), 2):
		for px in range(0, settled_image.get_width(), 2):
			sampled += 1
			if settled_image.get_pixel(px, py) != falling_image.get_pixel(px, py):
				changed += 1
	assert_gt(
		float(changed) / float(maxi(sampled, 1)), 0.01,
		"a still-falling leaf rendered identically to a settled one -- the GPU offset never applied"
	)
