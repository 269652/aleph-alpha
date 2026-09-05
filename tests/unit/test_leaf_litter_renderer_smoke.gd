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
##
## "Settled" here means the transition has actually COMPLETED (t == 1, the
## real steady state LeafLitterField.advance's own transition_from-snap
## exists for -- see that field's doc comment), not merely that this leaf's
## raw_offset happens to be zero. At t == 0 (an active transition with
## nothing to travel) the shader's own oscillating flutter/tumble terms are
## still live regardless of raw_offset -- real motion this same rewrite
## deliberately widened (twirl/flutter, reported directly) can land a
## still-mid-transition leaf's WORST-CASE swing outside this test's own
## tightly-zoomed viewport for an unlucky hash-derived phase, which is a
## real risk of THIS SYNTHETIC SETUP (an isolated, position-agnostic zoom),
## not of the motion itself -- a real leaf's transitional flutter is a few
## world pixels against an on-screen tile many times larger. Pushing the
## clock a beat past TRANSITION_DURATION keeps this test doing what it says
## ("settled"), sidesteps that synthetic risk, and is the state a real
## leaf actually spends the overwhelming majority of its life in anyway.
func test_a_settled_leaf_actually_renders_visible_pixels_at_its_position():
	if _no_real_gpu():
		return
	var target := Vector2(200, 200)
	var leaves: Array[Dictionary] = [{
		"position": target, "transition_from": target,
		"species": "cherry", "season": "autumn", "transition_start": 0.0,
	}]
	var viewport := _build_leaf_viewport(leaves, target)
	var mmi := viewport.get_child(0) as MultiMeshInstance2D
	mmi.material.set_shader_parameter(
		"current_time_fraction",
		LeafLitterRenderer.pack_time_fraction(LeafLitterField.TRANSITION_DURATION + 0.1)
	)
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


## THE tumble-reaches-the-GPU check -- the only place the reported "leaves
## should twirl more" symptom can actually be observed rather than reasoned
## about from the GDScript mirror alone (see tumble_rotation's own doc
## comment). Two leaves share the exact same position (so the exact same
## position-derived phase/spin_direction -- see phase_for_position), and
## both are sampled at t == 1 (transition_start pushed a beat into the
## past, same technique as the settled-leaf test just above), where the
## LINEAR offset (raw_offset * remaining) is exactly zero for both
## regardless of how far apart their own transition_from points are --
## isolating rotation as the only possible difference between them. One
## travelled a negligible distance (tumble_turns_for_distance's own MIN);
## the other travelled the full MAX_TRANSITION_OFFSET reference journey
## (tumble_turns_for_distance's own MAX) -- a real difference of several
## full turns, which must render as visibly different pixels if the
## distance-scaled spin actually reached the shader.
func test_a_farther_traveling_leaf_tumbles_more_than_a_nearby_one():
	if _no_real_gpu():
		return
	var target := Vector2(600, 600)
	var short_journey: Array[Dictionary] = [{
		"position": target, "transition_from": target + Vector2(1.0, 0.0),
		"species": "cherry", "season": "autumn", "transition_start": 0.0,
	}]
	var long_journey: Array[Dictionary] = [{
		"position": target,
		"transition_from": target + Vector2(LeafLitterRenderer.MAX_TRANSITION_OFFSET, 0.0),
		"species": "cherry", "season": "autumn", "transition_start": 0.0,
	}]
	var settled_time := LeafLitterRenderer.pack_time_fraction(LeafLitterField.TRANSITION_DURATION + 0.1)
	var short_viewport := _build_leaf_viewport(short_journey, target)
	var long_viewport := _build_leaf_viewport(long_journey, target)
	(short_viewport.get_child(0) as MultiMeshInstance2D).material.set_shader_parameter(
		"current_time_fraction", settled_time
	)
	(long_viewport.get_child(0) as MultiMeshInstance2D).material.set_shader_parameter(
		"current_time_fraction", settled_time
	)
	for i in range(4):
		await get_tree().process_frame
	var short_image := short_viewport.get_texture().get_image()
	var long_image := long_viewport.get_texture().get_image()
	short_viewport.queue_free()
	long_viewport.queue_free()
	if short_image == null or long_image == null:
		return  # no GPU readback in this environment

	var changed := 0
	var sampled := 0
	for py in range(0, short_image.get_height(), 2):
		for px in range(0, short_image.get_width(), 2):
			sampled += 1
			if short_image.get_pixel(px, py) != long_image.get_pixel(px, py):
				changed += 1
	assert_gt(
		float(changed) / float(maxi(sampled, 1)), 0.01,
		"a leaf that travelled the full reference distance rendered identically to one that barely " +
		"moved -- the GPU never scaled tumble by distance"
	)
