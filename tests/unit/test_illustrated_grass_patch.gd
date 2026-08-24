extends GutTest

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")


func test_each_seed_selects_one_tile_inside_the_delivered_10x10_atlas():
	var rect := IllustratedGrassPatch.atlas_region_for_seed(42)
	assert_between(rect.size.x, 125, 126)
	assert_between(rect.size.y, 125, 126)
	assert_gte(rect.position.x, 0)
	assert_gte(rect.position.y, 0)
	assert_lt(rect.position.x, 1254)
	assert_lt(rect.position.y, 1254)


func test_a_patch_has_multiple_deterministically_placed_blade_cards():
	var first := IllustratedGrassPatch.card_specs_for_seed(42)
	assert_eq(first, IllustratedGrassPatch.card_specs_for_seed(42))
	assert_gte(first.size(), 3)
	assert_gt(first[0].depth, first[first.size() - 1].depth)


func test_card_count_is_high_enough_to_read_as_a_dense_field_not_a_sparse_clump():
	# Reported live: "make grass blades volumetric... looks and feels like a
	# dense field of grass" once spread across the tile (see the spread test
	# below) rather than clustered in one small area - spreading the SAME
	# small card count over a bigger area would read as sparser, not denser,
	# so the count is raised alongside the spread to keep the field feeling
	# full. Pinned exactly (not just a floor) so a future "just bump it a
	# bit" edit is a deliberate, tested change, not a silent drift.
	# Lowered from 12 to reduce grass overdraw/fill-rate cost on weak
	# (integrated) GPUs -- each card is an alpha-blended shaded quad, and a
	# dense field of them was a measurable per-frame cost (see CARD_COUNT's doc).
	assert_eq(IllustratedGrassPatch.CARD_COUNT, 8)


## Reported live: "make grass blades volumetric, so that more than one
## entity spawns on the same tile not only at bottom corner". Offsets used
## to span only ~3.3x1.4 world units, a small sub-region hugging the tile's
## own center - visually one clump sitting somewhere on the tile rather than
## grass filling its whole footprint. Cards must spread across most of the
## tile's actual size (TILE_SIZE), not a fraction of it, for the "walking
## through a dense field" feel.
func test_card_offsets_spread_across_most_of_a_full_tile_not_a_small_corner():
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for seed_value in range(30):
		for spec in IllustratedGrassPatch.card_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			min_x = minf(min_x, offset.x)
			max_x = maxf(max_x, offset.x)
			min_y = minf(min_y, offset.y)
			max_y = maxf(max_y, offset.y)
	assert_gt(max_x - min_x, IllustratedGrassPatch.WORLD_SIZE * 0.7, "offsets must spread across most of the tile's width")
	assert_gt(max_y - min_y, IllustratedGrassPatch.WORLD_SIZE * 0.7, "offsets must spread across most of the tile's height")


## Spreading across the tile is the goal, but a root landing outside the
## tile it belongs to would visibly bleed into a neighboring cell's own
## footprint.
func test_card_offsets_stay_within_the_tiles_own_bounds():
	for seed_value in range(30):
		for spec in IllustratedGrassPatch.card_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			assert_lte(absf(offset.x), IllustratedGrassPatch.WORLD_SIZE * 0.5)
			assert_lte(absf(offset.y), IllustratedGrassPatch.WORLD_SIZE * 0.5)


func test_shader_bends_each_pixel_row_along_a_curved_per_blade_path():
	# A per-vertex shear can only ever move a quad's 4 corners, which linearly
	# interpolates into a flat parallelogram - every blade drawn on the card
	# leans by the same amount at a given height. Real path-traced bending
	# needs a fragment-stage, per-pixel UV offset (so it can follow a curved,
	# non-linear profile) that also varies with UV.x (so blades drawn side by
	# side in the same card don't sway in perfect lockstep).
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "player_world_position")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "walker_radius")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "void fragment()")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "pow(")


func test_shader_reads_its_atlas_region_from_per_instance_color():
	# This shader always draws through one shared MultiMesh material, so the
	# only way one instance's card can differ from another's atlas region is
	# per-instance data. `instance uniform` hits a global, hardware-capped
	# buffer shared by the WHOLE SCENE (measured on real hardware: 4096
	# total) - a single loaded chunk's worth of cards already overflowed it
	# ("Too many instances using shader instance variables"), silently
	# falling back to a wrong default region past the cap.
	#
	# It also isn't plain per-instance COLOR (MultiMesh's use_colors) read
	# directly in fragment(): under this project's gl_compatibility
	# renderer that produced a dithered/checkerboard mix of neighboring
	# instances' data instead of a clean per-instance constant, confirmed
	# with a real render (visible speckle noise even with zero bend math
	# involved). INSTANCE_CUSTOM read in vertex() and carried via varying is
	# the path that actually renders cleanly.
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "INSTANCE_CUSTOM")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "v_region.rg")
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "v_region.ba")
	assert_false(IllustratedGrassPatch.SHADER_CODE.contains("instance uniform vec2"), "instance uniform hits a global hardware-capped buffer at real card counts")


## A card must always sample its own atlas art - never an unconditional
## flat color. Reported live: "all grass blades are a magenta square tile"
## after a restart, traced to a literal `COLOR = vec4(1,0,1,1)` left in the
## shader gated on `wake > 0.01` (i.e. whenever a walker is anywhere within
## walker_radius) - a debug override that never should have shipped, self-
## labeled "TEMP DIAGNOSTIC" by whoever added it but never reverted.
func test_shader_never_unconditionally_overrides_color_to_a_flat_debug_tint():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	assert_false(code.contains("1.0, 0.0, 1.0"), "no hardcoded magenta debug override")
	# The only assignment to COLOR must be the real texture sample - anything
	# else (an `if` block reassigning it afterward) is debug scaffolding.
	var color_assignments := 0
	for line in code.split("\n"):
		if line.strip_edges().begins_with("COLOR ="):
			color_assignments += 1
	assert_eq(color_assignments, 1, "COLOR must be assigned exactly once - the real texture sample, unconditionally")


func test_walker_push_amplitude_matches_its_own_tuned_constant_not_a_debug_crank():
	# WALKER_PUSH_UV_AMPLITUDE >= 0.4 (see the "dense bush art" test above) is
	# a floor, not license for an arbitrary debug value - reported live
	# alongside the magenta override: `const WALKER_PUSH_UV_AMPLITUDE := 5.0
	# # TEMP DIAGNOSTIC CRANK`. Pin the real tuned value exactly so a future
	# debug crank fails loudly instead of silently shipping. Climbed
	# 0.45 -> 0.6 -> 0.7 -> 1.5 across several live "still not enough"
	# reports; 1.5 stays well clear (< 1/3) of the ~5.0 region where
	# bend_offset overshoots the shader's own UV clamp and the curve
	# collapses into a static-looking clamped sliver instead of a visible
	# sway (see docs/concept/long_grass.md's History) - the earlier small
	# nudges (0.6, 0.7) apparently still read as weak in practice, so this
	# jump is deliberately much larger rather than another small increment.
	assert_eq(IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE, 1.5)


func test_bend_curve_pins_the_root_and_reaches_full_displacement_at_the_tip():
	assert_eq(IllustratedGrassPatch.bend_curve(0.0), 0.0)
	assert_eq(IllustratedGrassPatch.bend_curve(1.0), 1.0)


func test_bend_curve_eases_in_so_bending_concentrates_near_the_tip():
	# A straight-line (vertex-shear) profile would put the midpoint at exactly
	# 0.5. A believable blade instead barely moves near its root and whips
	# increasingly near its tip, so the midpoint sits below the linear value.
	assert_lt(IllustratedGrassPatch.bend_curve(0.5), 0.5)


func test_bend_curve_is_monotonically_increasing_toward_the_tip():
	var previous := IllustratedGrassPatch.bend_curve(0.0)
	for step in range(1, 11):
		var top_t := step / 10.0
		var value := IllustratedGrassPatch.bend_curve(top_t)
		assert_gte(value, previous)
		previous = value


func test_blade_phase_differs_across_the_cards_width():
	# Different horizontal positions within one card approximate different
	# blades in the same tuft; they must not share an identical wind phase.
	assert_eq(IllustratedGrassPatch.blade_phase(0.0), 0.0)
	assert_ne(IllustratedGrassPatch.blade_phase(1.0), IllustratedGrassPatch.blade_phase(0.0))


func test_blade_amplitude_scale_never_fully_flattens_any_column():
	var uv_x := 0.0
	while uv_x <= 1.0:
		assert_gt(IllustratedGrassPatch.blade_amplitude_scale(uv_x), 0.0)
		uv_x += 0.1


func test_walker_push_amplitude_dominates_over_ambient_wind_amplitude():
	# The pass/sway "parting" reaction the player triggers must read as
	# clearly stronger than idle wind sway.
	assert_gt(IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE, IllustratedGrassPatch.WIND_UV_AMPLITUDE)


## Ambient wind sway must scale with the live wind strength (see
## WeatherModel.wind_strength_for, forwarded via EarthChunkManager.
## set_wind_strength) -- reusing the SAME live value water's own
## wind_strength already does, not a parallel wind concept.
## DEFAULT_WIND_STRENGTH is calibrated to wind_strength_for("clear") == 1.0,
## so the default reproduces today's fixed-amplitude look exactly at that
## baseline.
func test_material_defaults_wind_strength_to_the_calibration_anchor():
	var patch := IllustratedGrassPatch.new()
	var material := patch.material()
	assert_eq(material.get_shader_parameter("wind_strength"), IllustratedGrassPatch.DEFAULT_WIND_STRENGTH)
	assert_eq(IllustratedGrassPatch.DEFAULT_WIND_STRENGTH, 1.0)


func test_ambient_wind_sway_scales_by_the_live_wind_strength_uniform():
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "uniform float wind_strength")
	var code: String = IllustratedGrassPatch.SHADER_CODE
	var wind_line_start := code.find("float wind = ")
	var wind_line := code.substr(wind_line_start, code.find(";", wind_line_start) - wind_line_start)
	assert_string_contains(wind_line, "wind_strength")


## Parting is the WALKER's own reaction, not ambient wind -- a calm day must
## not make walking through grass part it any less than a stormy one would.
func test_walker_push_is_not_scaled_by_wind_strength():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	var push_line_start := code.find("float push = ")
	var push_line := code.substr(push_line_start, code.find(";", push_line_start) - push_line_start)
	assert_false(push_line.contains("wind_strength"), "walker push must stay independent of ambient wind: %s" % push_line)


func test_set_wind_strength_updates_the_materials_uniform():
	var patch := IllustratedGrassPatch.new()
	patch.set_wind_strength(1.8)
	assert_eq(patch.material().get_shader_parameter("wind_strength"), 1.8)
	patch.set_wind_strength(IllustratedGrassPatch.DEFAULT_WIND_STRENGTH)
	assert_eq(patch.material().get_shader_parameter("wind_strength"), IllustratedGrassPatch.DEFAULT_WIND_STRENGTH)


func test_walker_push_amplitude_is_strong_enough_to_read_against_dense_bush_art():
	# A rendered-pixel probe measured that a dense, busy bush card (many
	# overlapping similarly-colored blades filling the whole cell) shows
	# almost no *visible* parting at small UV shifts, even though the
	# pixels genuinely change: a small positional shift of dense, repetitive
	# texture still looks like the same dense texture. A sparse single-blade
	# card reads clearly at a much smaller shift because moving its
	# silhouette edge is high-contrast. The amplitude has to be large enough
	# for the busier case, reported live as "bigger bushes don't part...
	# don't sway anymore".
	assert_gte(IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE, 0.4)


func test_band_index_stays_within_bounds_across_the_whole_chunk_height():
	var chunk_size := 32
	var band_count := IllustratedGrassPatch.BAND_COUNT
	for local_y in range(chunk_size):
		var band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)
		assert_gte(band, 0)
		assert_lt(band, band_count)


func test_band_index_is_monotonically_non_decreasing_down_the_chunk():
	# A band groups a contiguous vertical slice of the chunk - cells further
	# down must never land in an earlier band than cells above them, or the
	# same visual row could split across non-adjacent bands.
	var chunk_size := 32
	var previous := IllustratedGrassPatch.band_index_for_local_y(0, chunk_size)
	for local_y in range(1, chunk_size):
		var band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size)
		assert_gte(band, previous)
		previous = band


func test_band_index_actually_uses_all_bands_across_a_full_chunk():
	# Not just in-bounds - a real spread, or the "8 bands" is theoretical
	# and every cell is actually landing in band 0.
	var chunk_size := 32
	var seen := {}
	for local_y in range(chunk_size):
		seen[IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size)] = true
	assert_eq(seen.size(), IllustratedGrassPatch.BAND_COUNT)


func test_band_anchor_world_y_orders_the_same_as_band_index():
	# The whole point of banding by Y: band 0's anchor must sit above (a
	# smaller world Y than) band 1's, etc., so Y-sort against the player
	# actually tracks vertical position through the chunk.
	var chunk_size := 32
	var previous := -INF
	for band in range(IllustratedGrassPatch.BAND_COUNT):
		var anchor_y := IllustratedGrassPatch.band_anchor_world_y(band, 0, chunk_size, 16.0)
		assert_gt(anchor_y, previous)
		previous = anchor_y


func test_instances_for_cells_produces_one_instance_per_card_across_all_given_cells():
	var cell_specs: Array[Dictionary] = [
		{"seed": 11, "ground_position": Vector2(0, 0), "growth": 1.0},
		{"seed": 22, "ground_position": Vector2(16, 0), "growth": 0.5},
	]
	var instances := IllustratedGrassPatch.instances_for_cells(cell_specs, Vector2.ZERO, Vector2i(1254, 1254))
	assert_eq(instances.size(), IllustratedGrassPatch.CARD_COUNT * 2)


func test_instances_for_cells_packs_each_instances_atlas_region_into_its_color():
	var cell_specs: Array[Dictionary] = [{"seed": 7, "ground_position": Vector2.ZERO, "growth": 1.0}]
	var instances := IllustratedGrassPatch.instances_for_cells(cell_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var found_a_nontrivial_region := false
	for entry in instances:
		var packed: Color = entry.custom_data
		var region_uv0 := Vector2(packed.r, packed.g)
		var region_uv1 := Vector2(packed.b, packed.a)
		assert_gte(region_uv0.x, 0.0)
		assert_lte(region_uv1.x, 1.0)
		assert_gt(region_uv1.x, region_uv0.x)
		assert_gt(region_uv1.y, region_uv0.y)
		if region_uv1.x - region_uv0.x < 0.5:
			found_a_nontrivial_region = true
	assert_true(found_a_nontrivial_region, "precondition: real atlas regions are ~1/10th of the atlas width, not the whole [0,1] default")


func test_instances_for_cells_keeps_every_cards_root_at_its_own_ground_position_regardless_of_growth():
	# Growth scales the card, but the root (transform origin, pre-mesh-
	# offset) must stay exactly at ground_position - never drift with scale.
	var ground := Vector2(37.0, -12.0)
	var cell_specs: Array[Dictionary] = [{"seed": 5, "ground_position": ground, "growth": 0.3}]
	var instances := IllustratedGrassPatch.instances_for_cells(cell_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var specs := IllustratedGrassPatch.card_specs_for_seed(5)
	var offsets_seen: Dictionary = {}
	for spec in specs:
		offsets_seen[spec.offset] = true
	for entry in instances:
		var transform: Transform2D = entry.transform
		var matched := false
		for spec in specs:
			var expected_root: Vector2 = ground + (spec.offset as Vector2)
			if transform.origin.is_equal_approx(expected_root):
				matched = true
				break
		assert_true(matched, "instance root %s must match ground_position + some card's own offset" % transform.origin)


func test_instances_for_cells_scales_uniformly_by_growth_without_moving_the_root():
	var cell_specs: Array[Dictionary] = [{"seed": 5, "ground_position": Vector2(10, 10), "growth": 0.6}]
	var instances := IllustratedGrassPatch.instances_for_cells(cell_specs, Vector2.ZERO, Vector2i(1254, 1254))
	for entry in instances:
		var transform: Transform2D = entry.transform
		assert_almost_eq(transform.x.x, 0.6, 0.001)
		assert_almost_eq(transform.y.y, 0.6, 0.001)


func test_instances_for_cells_never_scales_below_the_minimum_visible_floor():
	# maxf(0.3, growth): a barely-sprouted patch (growth near 0) must not
	# shrink to invisible.
	var cell_specs: Array[Dictionary] = [{"seed": 5, "ground_position": Vector2.ZERO, "growth": 0.0}]
	var instances := IllustratedGrassPatch.instances_for_cells(cell_specs, Vector2.ZERO, Vector2i(1254, 1254))
	for entry in instances:
		var transform: Transform2D = entry.transform
		assert_almost_eq(transform.x.x, 0.3, 0.001)


func test_fill_band_rebuilds_cleanly_when_called_again_with_fewer_cells():
	# A cell losing its grass (grazed, built on) must not leave stale
	# instances behind from the previous call.
	var patch := IllustratedGrassPatch.new()
	var mmi: MultiMeshInstance2D = autofree(MultiMeshInstance2D.new())
	patch.fill_band(mmi, Vector2.ZERO, [
		{"seed": 1, "ground_position": Vector2(0, 0), "growth": 1.0},
		{"seed": 2, "ground_position": Vector2(16, 0), "growth": 1.0},
	])
	var before := mmi.multimesh.instance_count
	patch.fill_band(mmi, Vector2.ZERO, [
		{"seed": 1, "ground_position": Vector2(0, 0), "growth": 1.0},
	])
	assert_lt(mmi.multimesh.instance_count, before)
	assert_eq(mmi.multimesh.instance_count, IllustratedGrassPatch.CARD_COUNT)
