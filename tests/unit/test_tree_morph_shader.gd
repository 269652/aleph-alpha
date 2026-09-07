extends GutTest

## The GPU per-leaf morph dissolve from a tree's sapling art into its real
## mature texture (see tree_morph_shader.gd's own header for the "why a
## shader, why per-clump and not a trunk-outward sweep" reasoning, and
## docs/concept/flora.md's "Sapling phase"). A fragment shader can't be
## asserted headlessly, so everything here is the CPU mirror of the exact
## math the GLSL runs -- the same convention RiverFlowShader/WaterShader
## already use for their own hashes and ripple packets.

const TreeMorphShader = preload("res://src/rendering/tree_morph_shader.gd")


func test_value_hash_is_deterministic():
	assert_eq(TreeMorphShader.value_hash(3.0, 7.0), TreeMorphShader.value_hash(3.0, 7.0))


func test_value_hash_stays_within_unit_range():
	for i in 50:
		var h := TreeMorphShader.value_hash(float(i) * 1.7, float(i) * 2.3)
		assert_between(h, 0.0, 1.0)


func test_value_hash_differs_across_neighbouring_cells():
	# Not a hard mathematical guarantee for every possible pair, but true
	# for this specific, fixed sample -- if this ever regresses to a
	# constant-output hash (the exact class of bug the sine-hash history
	# this mirrors warns about), every clump would flip at once instead of
	# scattering, which is the whole point of using a hash at all here.
	var seen := {}
	for x in 20:
		for y in 20:
			seen[TreeMorphShader.value_hash(float(x), float(y))] = true
	assert_gt(seen.size(), 300, "expected real per-cell variance, got %d distinct values" % seen.size())


func test_clump_of_groups_several_texels_into_one_cell():
	assert_eq(TreeMorphShader.clump_of(0, 0), TreeMorphShader.clump_of(1, 1))
	assert_ne(TreeMorphShader.clump_of(0, 0), TreeMorphShader.clump_of(10, 10))


## At progress 0.0 nothing should ever reveal; at 1.0 everything should --
## the two ends a caller actually relies on (a fresh sapling; a fully
## morphed tree).
func test_no_clump_reveals_at_zero_progress():
	for x in 30:
		for y in 30:
			assert_false(TreeMorphShader.clump_is_revealed(x, y, 5.0, 0.0))


func test_every_clump_reveals_at_full_progress():
	for x in 30:
		for y in 30:
			assert_true(TreeMorphShader.clump_is_revealed(x, y, 5.0, 1.0))


## A real live-GPU regression: at seed 5.0, clump (30, 8) has the smallest
## hashed roll of any clump in a 64x64/2px-clump (32x32) grid -- about
## 0.0008 in this function's own float64 CPU math, close enough to zero
## that the real GPU's float32 arithmetic rounded it down to exactly 0.0
## and revealed it at progress 0.0 (caught by test_tree_morph_shader_
## render_smoke.gd, not by this file -- a float64 mirror cannot reproduce a
## float32 rounding artifact, which is why the render smoke test exists at
## all). test_no_clump_reveals_at_zero_progress above never touched clump
## 30 (its loop only reaches 29), so it could not have caught this. This
## pins the exact clump and seed so the fix (the explicit progress <= 0.0
## short-circuit in both morph_canopy and clump_is_revealed) can't quietly
## regress even though the CPU math alone would never fail here again.
func test_the_smallest_known_roll_in_a_real_canopy_grid_stays_unrevealed_at_zero_progress():
	assert_false(TreeMorphShader.clump_is_revealed(30, 8, 5.0, 0.0))


## The whole point of a per-clump hash instead of a geodesic sweep: at a
## middling progress, revealed clumps should be SCATTERED across the grid,
## not all clustered at one edge/corner (which is what a directional sweep
## from a single seed would produce instead).
func test_revealed_clumps_are_scattered_not_swept_from_one_corner():
	var grid_size := 24
	var revealed_per_quadrant := [0, 0, 0, 0]
	for x in grid_size:
		for y in grid_size:
			if TreeMorphShader.clump_is_revealed(x, y, 11.0, 0.5):
				var quadrant := (1 if x >= grid_size / 2 else 0) + (2 if y >= grid_size / 2 else 0)
				revealed_per_quadrant[quadrant] += 1
	for count in revealed_per_quadrant:
		assert_gt(count, 0, "a scattered reveal should touch every quadrant, not sweep from one")


## Two different trees (different variant seeds) at the SAME progress must
## reveal a DIFFERENT scatter -- "each individual tree looks different
## when maturing", the same property test_two_saplings_grow_different_
## branches already pins for the (unrelated) trunk-outward mechanism.
func test_different_trees_reveal_different_clumps_at_the_same_progress():
	var tree_a := {}
	var tree_b := {}
	for x in 20:
		for y in 20:
			tree_a[Vector2i(x, y)] = TreeMorphShader.clump_is_revealed(x, y, 3.0, 0.5)
			tree_b[Vector2i(x, y)] = TreeMorphShader.clump_is_revealed(x, y, 97.0, 0.5)
	assert_ne(tree_a, tree_b)


func test_apply_pushes_the_real_uniforms_onto_a_material():
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\n" + TreeMorphShader.GLSL_SNIPPET + "\nvoid fragment() { COLOR = morph_canopy(texture(TEXTURE, UV), UV, vec2(textureSize(TEXTURE, 0))); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	var sapling_texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))

	TreeMorphShader.apply(material, sapling_texture, 7, 0.4)

	assert_eq(material.get_shader_parameter("morph_sapling_texture"), sapling_texture)
	assert_almost_eq(float(material.get_shader_parameter("morph_variant_seed")), 7.0, 0.001)
	assert_almost_eq(float(material.get_shader_parameter("morph_progress")), 0.4, 0.001)


func test_clear_resets_progress_to_fully_mature():
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\n" + TreeMorphShader.GLSL_SNIPPET + "\nvoid fragment() { COLOR = morph_canopy(texture(TEXTURE, UV), UV, vec2(textureSize(TEXTURE, 0))); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	TreeMorphShader.apply(material, ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8)), 1, 0.3)

	TreeMorphShader.clear(material)

	assert_almost_eq(float(material.get_shader_parameter("morph_progress")), 1.0, 0.001)
