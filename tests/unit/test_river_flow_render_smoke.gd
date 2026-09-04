extends GutTest

## A live-render smoke check for the GPU river-flow overlay (river_flow_
## shader.gd, procedural_river_flow_sprite.gd, terrain_renderer.gd's
## build_river_flow_tile_set/atlas_coords_for_river_flow) -- everything
## CPU-testable about this feature (streak math, atlas indexing, tile
## uniqueness) already has dedicated coverage in test_river_flow_shader.gd,
## test_terrain_renderer.gd and test_procedural_river_flow_sprite.gd; this
## test instead builds the exact same TileMapLayer + ShaderMaterial +
## data-tile_set combination scenes/world.gd wires for real, adds it to a
## LIVE SceneTree, and lets it actually run for several frames -- if the
## shader failed to compile, Godot pushes a real engine error/warning that
## a plain code review can't see. No such error/warning ever surfaced
## across a real run of this test (see docs/concept/rivers.md's entry on
## this investigation for how that was confirmed).
##
## This test does NOT by itself prove the fix for "flow animations don't
## work" -- that was a z-order/layering bug (see
## test_world_ground_layer_order.gd), not a shader-compile failure. It
## exists because the failure mode "shader silently fails to compile" was
## an explicitly named alternate hypothesis worth ruling out with real
## engine feedback, not just by reading the GLSL by eye.

const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")


func test_a_real_tile_map_layer_with_the_shared_river_flow_material_runs_several_frames_with_no_engine_error():
	var renderer := TerrainRenderer.new()
	var flow_shader := RiverFlowShader.new()

	var layer := TileMapLayer.new()
	layer.tile_set = renderer.build_river_flow_tile_set()
	layer.material = flow_shader.shared_material()
	add_child_autofree(layer)

	# A real river cell, painted exactly the way
	# EarthChunkManager._paint_river_flow_overlay does.
	var atlas_coords := renderer.atlas_coords_for_river_flow(135.0, true)
	layer.set_cell(Vector2i(0, 0), 0, atlas_coords)

	assert_true(layer.material is ShaderMaterial, "precondition: a real ShaderMaterial is assigned")
	assert_eq(layer.get_cell_atlas_coords(Vector2i(0, 0)), atlas_coords)

	# Let the engine actually process/draw several frames with this node
	# live in the tree -- a shader compile failure surfaces as a real
	# engine error during this, not silently.
	for i in range(5):
		await get_tree().process_frame

	# If we got here without GUT's own error-collecting assertions firing
	# (GUT fails a test on unhandled script errors during the run) and the
	# node/material/cell are all still exactly what we set, the shader
	# survived being live-rendered for multiple frames.
	assert_true(is_instance_valid(layer), "the layer must still be alive after several live frames")
	assert_true(layer.material is ShaderMaterial, "the material must still be attached after several live frames")
	assert_eq(layer.get_cell_atlas_coords(Vector2i(0, 0)), atlas_coords, "the painted cell must be unaffected by rendering")


## THE far-world float32 check, on the REAL GPU -- the one failure mode no
## CPU mirror can ever catch, found live: at the Rhine near Basel
## (world_pos ~ 334,000 px) a long straight reach rendered with NO current
## strokes at all, while every CPU-mirror statistic guaranteed one within
## ~85 px. The mirror runs in float64; the GPU runs float32, and a hash
## built on sin() of millions of radians dies of range reduction there --
## the noise goes regionally near-constant, the field rails, and the
## contour strokes vanish over whole reaches.
##
## So this renders the real material at those exact coordinates, reads the
## frame back, and requires the wave strokes to actually APPEAR: pale
## stroke pixels among the dark deep-water body, in a real measured
## fraction. A control at the origin separates "the harness is broken"
## from "the far coordinates are broken".
func test_the_strokes_survive_far_world_coordinates_on_the_real_gpu():
	if _no_real_gpu():
		return
	var origin_fraction := await _stroke_pixel_fraction_at(Vector2(0.0, 0.0))
	var basel := Vector2(20870.0 * 16.0, 4750.0 * 16.0)
	var far_fraction := await _stroke_pixel_fraction_at(basel)
	assert_between(
		origin_fraction, 0.02, 0.6,
		"control broken: %.1f%% stroke pixels at the origin" % (origin_fraction * 100.0)
	)
	assert_between(
		far_fraction, 0.02, 0.6,
		"%.1f%% stroke pixels at Basel coordinates -- the field is dead there"
			% (far_fraction * 100.0)
	)



## THE ripple check, on the real GPU -- the only place the reported symptom
## ("fishes don't produce interferencing ripples anymore in the new unified
## river water") can actually be observed. Every CPU mirror in
## test_river_flow_shader.gd can be green while the ring still never
## reaches a pixel, which is exactly the class of failure that produced the
## report in the first place: the wake was being recorded and aged all
## along, into a surface that no longer existed.
##
## Two blocks of the SAME river, quiet and disturbed, rendered in the SAME
## FRAME. Sharing the frame is not a convenience -- it is the whole
## experiment. This surface advects continuously, so two renders taken a
## few frames apart differ in every pixel no matter what the ripple does,
## and a comparison across frames "passes" with the ripple term deleted
## outright (measured: it did). Same frame means one shared TIME, so the
## disturbance buffer is the only thing left that can differ.
func test_a_recorded_disturbance_actually_changes_what_the_river_draws():
	if _no_real_gpu():
		return
	# Mid-block, mid-life: the front has expanded a couple of tiles and the
	# packet still carries most of its amplitude.
	var quiet := _build_river_viewport(
		Vector2.ZERO, PackedVector2Array(), PackedFloat32Array()
	)
	var rippled := _build_river_viewport(
		Vector2.ZERO, PackedVector2Array([Vector2(64.0, 64.0)]), PackedFloat32Array([0.35])
	)
	for i in range(4):
		await get_tree().process_frame

	var quiet_image := quiet.get_texture().get_image()
	var rippled_image := rippled.get_texture().get_image()
	quiet.queue_free()
	rippled.queue_free()
	if quiet_image == null or rippled_image == null:
		return  # no GPU readback in this environment (see _read_stroke_fraction)

	var changed := 0
	var sampled := 0
	for py in range(0, quiet_image.get_height(), 2):
		for px in range(0, quiet_image.get_width(), 2):
			sampled += 1
			if quiet_image.get_pixel(px, py) != rippled_image.get_pixel(px, py):
				changed += 1
	var changed_fraction := float(changed) / float(maxi(sampled, 1))
	assert_gt(
		changed_fraction, 0.01,
		"a live wake left %.2f%% of the river's pixels different -- the ring never reaches the screen"
			% (changed_fraction * 100.0)
	)
	# And it is a LOCAL disturbance, not a wash over the whole surface: the
	# ring has a real radius, so a good part of the block must be untouched.
	assert_lt(
		changed_fraction, 0.9,
		"a wake that repaints nearly every pixel is not a ring, it is a filter"
	)


## Whether this run has no GPU that can render a viewport and hand the
## frame back. The two readback tests above are meaningless without one:
## get_image() returns null under the headless driver, and the engine error
## that produces is itself enough to fail a GUT test, so an early return
## inside the harness cannot rescue them. They previously ran anyway and
## reported "the field is dead there" on every headless run -- a failure
## about the shader, for a reason that has nothing to do with it.
##
## Run them for real with:
##   <godot> --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd \
##     -gconfig= -gtest=res://tests/unit/test_river_flow_render_smoke.gd -gexit
## (no --headless), which is how this file's claims were last confirmed.
func _no_real_gpu() -> bool:
	if DisplayServer.get_name() != "headless":
		return false
	pending("no GPU readback under --headless; run with --rendering-driver opengl3")
	return true


## Builds (but does not yet render) an 8x8 block of mid-channel water cells
## drawn with the real shared material at a given world offset, optionally
## carrying live movement ripples. Returned unrendered so a caller can
## stand two of them up and let both reach the GPU in the SAME frame.
func _build_river_viewport(
	world_offset: Vector2,
	disturbance_positions: PackedVector2Array,
	disturbance_ages: PackedFloat32Array
) -> SubViewport:
	var renderer := TerrainRenderer.new()
	var flow_shader := RiverFlowShader.new()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)

	var layer := TileMapLayer.new()
	layer.tile_set = renderer.build_river_flow_tile_set()
	layer.material = flow_shader.shared_material()
	layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	# The layer sits AT the world offset, so the shader genuinely computes
	# with world_pos of that magnitude -- which is the whole point.
	layer.position = world_offset
	viewport.add_child(layer)

	var camera := Camera2D.new()
	camera.zoom = Vector2(2.0, 2.0)
	camera.position = world_offset + Vector2(64, 64)
	viewport.add_child(camera)
	camera.make_current()

	# A real cross-section: the across now comes from the bilinear float
	# map, so the harness builds one the way the manager does -- exact
	# per-tile values -- and hands it to the material.
	var side := RiverFlowShader.FLOW_MAP_TILES
	var map_image := Image.create(side, side, false, Image.FORMAT_RGBAF)
	var origin_tile := Vector2i(world_offset / 16.0)
	for y in range(-2, 10):
		for x in range(-2, 10):
			var across := (float(y) - 3.5) / 3.5 * 0.9
			# Flow south (bearing 180): dir = (sin, -cos) = (0, 1); a real
			# brisk current speed so the drift and fast-gate paths execute.
			map_image.set_pixel(
				posmod(origin_tile.x + x, side), posmod(origin_tile.y + y, side),
				Color(across, 0.0, 1.0, 1.5)
			)
	var map_texture := ImageTexture.create_from_image(map_image)
	flow_shader.shared_material().set_shader_parameter("flow_across_map", map_texture)

	# The disturbance buffer, padded exactly the way EarthChunkManager hands
	# it over (WaterShader's own padding: a sentinel age for the dead tail).
	var padded_positions := PackedVector2Array(disturbance_positions)
	padded_positions.resize(RiverFlowShader.DISTURBANCE_SLOTS)
	var padded_ages := PackedFloat32Array(disturbance_ages)
	while padded_ages.size() < RiverFlowShader.DISTURBANCE_SLOTS:
		padded_ages.append(-999.0)
	flow_shader.set_disturbances(padded_positions, padded_ages, disturbance_positions.size())

	var atlas_coords := renderer.atlas_coords_for_river_flow(180.0, true)
	for y in range(8):
		for x in range(8):
			layer.set_cell(Vector2i(x, y), 0, atlas_coords)
	return viewport


## Renders an 8x8 block of quiet mid-channel water at a given world offset
## and returns the fraction of its pixels that read as pale stroke ink
## rather than deep body colour. -1.0 where this environment cannot read a
## viewport back (headless has no real GPU target, and a null image is
## that, not a rendering bug).
func _stroke_pixel_fraction_at(world_offset: Vector2) -> float:
	var viewport := _build_river_viewport(
		world_offset, PackedVector2Array(), PackedFloat32Array()
	)
	for i in range(4):
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null:
		return -1.0
	var stroke_pixels := 0
	var sampled := 0
	for py in range(0, image.get_height(), 2):
		for px in range(0, image.get_width(), 2):
			sampled += 1
			if image.get_pixel(px, py).v > 0.6:
				stroke_pixels += 1
	if sampled == 0:
		return -1.0
	return float(stroke_pixels) / float(sampled)
