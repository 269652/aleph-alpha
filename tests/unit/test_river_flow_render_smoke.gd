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
	var atlas_coords := renderer.atlas_coords_for_river_flow(135.0, 0.6, 0.25)
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
