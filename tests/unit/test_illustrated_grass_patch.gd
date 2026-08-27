extends GutTest

const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
const GroundTint = preload("res://src/rendering/ground_tint.gd")


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


## SUPERSEDED (2026-08-26, reported live with a real screenshot): the
## previous fix for "the player's head is behind the long grass blades"
## used a per-pixel alpha fade (`occlusion_fade`, reusing the unrelated
## push effect's `walker_radius = 22.0`) as a stand-in for true occlusion.
## That both under- and over-corrected at once: any blade whose root sat
## MORE than 22 world units (~1.4 tiles) behind the player never faded at
## all, so it kept drawing solid on top of the player's upper body/head
## whenever it shared an in-front BAND with the player (a real, frequent
## case -- see the old BAND_COUNT=8 comment: each band was 4 tiles/64 world
## units tall) -- while every blade WITHIN that radius faded to fully
## invisible as the player simply walked near it, reported separately as
## "grass becomes transparent when walking over it". Both symptoms were the
## same undersized, wrongly-purposed heuristic standing in for real Y-sort.
##
## The real fix is architectural, not a bigger fade radius: shrink
## BAND_COUNT's own band height (see its own doc comment and
## test_band_height_leaves_a_real_safety_margin_under_the_players_own_max_reach
## below) until it's fine enough that Godot's OWN native Y-sort -- the exact
## mechanism every ordinary Sprite2D already uses correctly -- places each
## band in the right draw order on its own. Once that's true, no alpha hack
## is needed at all: grass is either genuinely behind the player (drawn
## first, correctly covered) or genuinely in front (drawn after, correctly
## covering) -- always fully opaque either way, matching what was reported.
func test_grass_opacity_is_never_reduced_by_the_players_own_proximity():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	assert_false(code.contains("occlusion_fade"), "the alpha-fade occlusion hack must be gone")
	assert_false(code.contains("passed_by_walker"), "the alpha-fade occlusion hack must be gone")
	assert_false(code.contains("COLOR.a *="), "grass must never have its opacity reduced")


## The player's own real max reach above their feet/root -- HeadSlot, the
## topmost node in scenes/character_view.tscn, sits at local Y = -42 (world
## units above the character's own origin, which is the same root a grass
## blade's own card grows up from -- see mesh()'s doc comment). A blade
## card is WORLD_SIZE tall and grows from ITS OWN root upward too, so the
## worst case is a blade sitting at the very TOP of an "in front" band: its
## own root can be up to one full band-height behind the player's root
## (see band_anchor_world_y's own bottom-edge anchoring), and its card then
## reaches another WORLD_SIZE past that. For native Y-sort to never let
## that worst-case card visually reach as high as the player's own real
## head, band_height + WORLD_SIZE must stay comfortably under 42.
##
## SUPERSEDED accounting (2026-08-27): the above ignored a real term.
## card_specs_for_seed gives every individual CARD its own random offset
## from its cell's nominal ground position, up to a real max magnitude --
## computed below from the live formula (never hardcoded: the formula's own
## bucket math is 17 buckets, centered to -8..8, times a 0.85 step, so the
## true bound is exactly 8.0 * 0.85 = 6.8, confirmed empirically across a
## wide seed sweep, not just algebraically assumed). Added ON TOP of the
## existing band_height + WORLD_SIZE bound (a deliberately conservative
## choice, not the tightest possible one -- see
## test_per_card_banding_matches_cell_level_banding_at_the_real_production_
## ratio in this same file for why today's actual BAND_COUNT/CHUNK_SIZE
## ratio never lets a card's own offset cross a band boundary at all, which
## would make the tighter bound even smaller; this stays a safe upper bound
## regardless of whether that ratio ever changes).
func test_band_height_leaves_a_real_safety_margin_under_the_players_own_max_reach():
	const PLAYER_MAX_REACH_ABOVE_ROOT := 42.0  # character_view.tscn's own real HeadSlot offset
	var chunk_size := 32  # EarthChunkManager.CHUNK_SIZE
	var tile_size := 16.0  # TerrainRenderer.TILE_SIZE

	# The real max |offset.y| any card can carry -- computed from the live
	# formula across a wide seed range, not hardcoded.
	var max_card_offset_y := 0.0
	for seed_value in range(500):
		for spec in IllustratedGrassPatch.card_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			max_card_offset_y = maxf(max_card_offset_y, absf(offset.y))
	assert_almost_eq(
		max_card_offset_y, 8.0 * 0.85, 0.001,
		"precondition: the empirically observed max must match the formula's own real bound (17 buckets centered to +/-8, step 0.85)"
	)

	var band_height_world_units: float = (float(chunk_size) / float(IllustratedGrassPatch.BAND_COUNT)) * tile_size
	var worst_case_reach: float = band_height_world_units + max_card_offset_y + IllustratedGrassPatch.WORLD_SIZE
	assert_almost_eq(worst_case_reach, 38.8, 0.001, "pin the real number this margin is actually computed from")
	assert_lt(
		worst_case_reach, PLAYER_MAX_REACH_ABOVE_ROOT,
		"a band's own worst-case blade, real per-card offset included, must never be able to visually reach the player's real head height"
	)
	# Honest: the real margin (42 - 38.8 = 3.2 world units) is real but
	# thin -- far short of the ~10-unit margin the pre-offset accounting
	# above claimed. Named here rather than left implicit.
	var real_margin: float = PLAYER_MAX_REACH_ABOVE_ROOT - worst_case_reach
	assert_gt(real_margin, 3.0, "the real margin, honestly accounted for")
	assert_lt(real_margin, 4.0, "...and it really is this thin -- not a rounding artifact of a generous bound")


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


## Reported live: "the player's head is behind the long grass blades when
## the feet already are past it" -- a single MultiMeshInstance2D draw call
## can only Y-sort as ONE unit against the player (see BAND_COUNT's own doc
## comment), using this anchor as that unit's sort key. A CENTER anchor
## means every row in the LOWER half of a band sits below (a larger world Y
## than) the anchor -- so a player standing on one of those rows, having
## already walked past every blade in the band's upper half, still sees the
## WHOLE band (including blades whose own root the player is already past)
## Y-sort in front of them, since the comparison uses the band's midpoint,
## not any individual blade's real position. A blade card is exactly
## WORLD_SIZE (one tile) tall (see `mesh()`), so this isn't a sub-pixel
## rounding error -- a mid-band player can end up visibly behind a blade
## whose root is a full tile or more BEHIND their own feet, and since the
## card renders upward from its root, that reads exactly as "my head is
## behind grass my feet have already passed."
##
## The anchor must instead sit at the band's own BOTTOM edge (its largest
## row's world Y, not its midpoint): an entity standing anywhere within or
## above the band then always sorts BEHIND the whole band (grass draws in
## front while you're walking through it -- normal, expected concealment,
## see docs/concept/combat.md's vegetation-concealment pillar), and only
## pops in front of the entire band once genuinely past its very last row.
## That trades "occasionally covered a beat longer than a single blade's
## own root would justify" for "never shows a body part behind grass it has
## unambiguously already passed" -- the same choice BAND_COUNT's own doc
## comment already argues for ("the whole field flickering... is what
## actually reads as broken").
func test_band_anchor_world_y_is_never_smaller_than_any_row_actually_in_that_band():
	var chunk_size := 32
	var chunk_origin_y := 96  # nonzero, so this doesn't accidentally pass via origin canceling out
	var tile_size := 16.0
	for local_y in range(chunk_size):
		var band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size)
		var anchor_y := IllustratedGrassPatch.band_anchor_world_y(band, chunk_origin_y, chunk_size, tile_size)
		var row_world_y := float(chunk_origin_y + local_y) * tile_size
		assert_gte(
			anchor_y, row_world_y,
			"row %d (band %d)'s own world Y must never exceed its band's anchor, or a player standing on it would wrongly Y-sort in front of blades from earlier rows in the same band" % [local_y, band]
		)


# -- per-card Y-sort banding: real position, not the cell's raw row -------
#
# Reported live, after the BAND_COUNT 8->32 fix: "y sorting works for some
# [tufts] but not all... it parts and bends but y ordering is correct only
# for some." Root cause: EarthChunkManager used to bucket a whole cell's
# CARD_COUNT cards into a Y-sort band from the cell's own raw, un-offset
# tile row -- before any card's own random offset (card_specs_for_seed) was
# even applied. cards_for_cell (below) is the single seam that expands a
# cell into its real, offset-adjusted per-card positions; both
# EarthChunkManager's own banding and instances_for_cards' own final
# placement math read from it, so the two can never drift apart.


func test_cards_for_cell_expands_a_cell_into_card_count_real_per_card_specs():
	var ground := Vector2(37.0, -12.0)
	var cell_spec := {"seed": 5, "ground_position": ground, "growth": 0.3}
	var cards := IllustratedGrassPatch.cards_for_cell(cell_spec)
	assert_eq(cards.size(), IllustratedGrassPatch.CARD_COUNT)
	var specs := IllustratedGrassPatch.card_specs_for_seed(5)
	for i in cards.size():
		assert_eq(cards[i].atlas_seed, specs[i].seed)
		assert_true((cards[i].position as Vector2).is_equal_approx(ground + (specs[i].offset as Vector2)))
		assert_eq(cards[i].growth, 0.3)


func test_local_row_for_world_y_inverts_a_cells_own_ground_position_math():
	# A cell's own ground_position is (tile.y + 0.5) * tile_size, where
	# tile.y = chunk_origin_y + local_y -- so feeding that same world Y back
	# through local_row_for_world_y must recover local_y + 0.5 (the row's
	# own center, i.e. the position a card with zero offset would sit at).
	var tile_size := 16.0
	var chunk_origin_y := 96  # nonzero, matches this file's own convention above
	var local_y := 5
	var world_y: float = float(chunk_origin_y + local_y) * tile_size + 0.5 * tile_size
	var recovered := IllustratedGrassPatch.local_row_for_world_y(world_y, chunk_origin_y, tile_size)
	assert_almost_eq(recovered, float(local_y) + 0.5, 0.001)


func test_local_row_for_world_y_matches_the_cells_own_raw_row_for_an_unoffset_position():
	# The invariant the whole per-card refactor's regression case depends
	# on: with zero offset, converting a card's real world Y back through
	# local_row_for_world_y and into band_index_for_local_y must land in the
	# SAME band band_index_for_local_y(cell.y, ...) already gives directly.
	var chunk_size := 32
	var tile_size := 16.0
	var chunk_origin_y := 0
	for local_y in range(chunk_size):
		var world_y: float = float(local_y) * tile_size + 0.5 * tile_size
		var real_row := IllustratedGrassPatch.local_row_for_world_y(world_y, chunk_origin_y, tile_size)
		var real_band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size)
		var naive_band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size)
		assert_eq(real_band, naive_band)


## The direct, real proof that per-card banding differs from the OLD
## cell-raw-row banding once a card's own offset genuinely crosses a band
## boundary -- verified numbers, not assumed. Real seed 7's cell has 8
## cards whose offset.y is either exactly +6.8 (6 cards, indices 0-5) or
## exactly -6.8 (2 cards, indices 6-7) -- confirmed by direct inspection of
## card_specs_for_seed(7). At today's real production BAND_COUNT=32/
## CHUNK_SIZE=32 ratio (one band == one full tile row == 16 world units)
## neither offset is large enough to cross a boundary (see the regression
## test below) -- so this test deliberately uses a finer band_count (48,
## band_height = 32/48 tile = 10.667 world units) purely to exercise the
## underlying mechanism, the same way this file's other band_index tests
## already use literal chunk_size/band_count values decoupled from
## EarthChunkManager's own real ones.
func test_per_card_banding_splits_a_single_cells_cards_across_two_real_bands():
	var chunk_size := 32
	var band_count := 48
	var tile_size := 16.0
	var chunk_origin_y := 0
	var local_y := 0

	var cell_spec := {
		"seed": 7,
		"ground_position": Vector2(8.0, (float(local_y) + 0.5) * tile_size),
		"growth": 1.0,
	}
	var naive_band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)

	var cards := IllustratedGrassPatch.cards_for_cell(cell_spec)
	assert_eq(cards.size(), 8, "precondition: CARD_COUNT is still 8")

	var crossed := 0
	var stayed := 0
	for card in cards:
		var real_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, chunk_origin_y, tile_size)
		var real_band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size, band_count)
		if real_band == naive_band:
			stayed += 1
		else:
			assert_eq(real_band, naive_band + 1, "a crossing card must land in the immediately-next band, not further")
			crossed += 1
	assert_eq(crossed, 6, "the 6 cards whose real offset.y is +6.8 must cross into the next band")
	assert_eq(stayed, 2, "the 2 cards whose real offset.y is -6.8 must stay in the cell's own nominal band")


## Regression, at TODAY's real production ratio: every card of every cell
## stays in its own cell's raw-row band -- per-card banding must not
## silently reshuffle anything under the actual live BAND_COUNT/CHUNK_SIZE
## the game really runs with (band_height=16 world units, comfortably more
## than double any card's real max |offset.y|=6.8), only under a
## deliberately finer ratio like the crossing test above. Proven generally
## (every row in a real chunk, many real cell seeds), not spot-checked.
func test_per_card_banding_matches_cell_level_banding_at_the_real_production_ratio():
	var chunk_size := 32  # EarthChunkManager.CHUNK_SIZE
	var band_count := IllustratedGrassPatch.BAND_COUNT  # today's real value
	var tile_size := 16.0
	var chunk_origin_y := 0
	for local_y in range(chunk_size):
		var naive_band := IllustratedGrassPatch.band_index_for_local_y(local_y, chunk_size, band_count)
		for seed_value in range(20):
			var cell_spec := {
				"seed": seed_value,
				"ground_position": Vector2(8.0, (float(local_y) + 0.5) * tile_size),
				"growth": 1.0,
			}
			for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
				var real_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, chunk_origin_y, tile_size)
				var real_band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size, band_count)
				assert_eq(real_band, naive_band, "at the real production ratio no card's own offset can cross a band boundary")


## No card is gained or lost by which band it ends up grouped into --
## summing a chunk's bands' instance counts must always equal
## CARD_COUNT * num_cells, whether banding is coarse (every card of every
## cell landing in one band) or fine enough that cards from the same cell
## genuinely split across two (mirrors the split proven above).
func test_regrouping_cards_by_band_never_gains_or_loses_a_card():
	var chunk_size := 32
	var tile_size := 16.0
	var cell_seeds := [3, 7, 42, 100]
	for band_count in [8, 32, 48, 96]:
		var cards_by_band: Dictionary = {}
		for seed_value in cell_seeds:
			var cell_spec := {
				"seed": seed_value,
				"ground_position": Vector2(8.0, 8.0),
				"growth": 1.0,
			}
			for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
				var real_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, 0, tile_size)
				var band := IllustratedGrassPatch.band_index_for_local_y(real_row, chunk_size, band_count)
				var list: Array = cards_by_band.get(band, [])
				list.append(card)
				cards_by_band[band] = list
		var total := 0
		for band in cards_by_band:
			total += (cards_by_band[band] as Array).size()
		assert_eq(
			total, IllustratedGrassPatch.CARD_COUNT * cell_seeds.size(),
			"band_count=%d must not change how many cards exist in total, only their grouping" % band_count
		)


# -- instances_for_cards: pure placement math over pre-expanded cards -----
#
# Takes CARD specs directly (not cell specs) -- deliberately does NOT
# expand a cell itself (that is cards_for_cell's own single job above), so
# a cell whose cards straddle two bands can be split across two separate
# calls without any card being drawn twice or silently dropped.


func test_instances_for_cards_produces_one_instance_per_given_card_with_no_further_expansion():
	var card_specs: Array[Dictionary] = [
		{"atlas_seed": 11, "position": Vector2(0, 0), "growth": 1.0},
		{"atlas_seed": 22, "position": Vector2(16, 0), "growth": 0.5},
	]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	assert_eq(instances.size(), 2)


func test_instances_for_cards_packs_each_instances_atlas_region_into_its_color():
	var card_specs: Array[Dictionary] = [{"atlas_seed": 7, "position": Vector2.ZERO, "growth": 1.0}]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var packed: Color = instances[0].custom_data
	var region_uv0 := Vector2(packed.r, packed.g)
	var region_uv1 := Vector2(packed.b, packed.a)
	assert_gte(region_uv0.x, 0.0)
	assert_lte(region_uv1.x, 1.0)
	assert_gt(region_uv1.x, region_uv0.x)
	assert_gt(region_uv1.y, region_uv0.y)


func test_instances_for_cards_places_the_root_exactly_at_the_given_position_regardless_of_growth():
	# Growth scales the card, but the root (transform origin, pre-mesh-
	# offset) must stay exactly at the given position - never drift with
	# scale.
	var position := Vector2(37.0, -12.0)
	var card_specs: Array[Dictionary] = [{"atlas_seed": 5, "position": position, "growth": 0.3}]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var transform: Transform2D = instances[0].transform
	assert_true(transform.origin.is_equal_approx(position))


func test_instances_for_cards_scales_uniformly_by_growth_without_moving_the_root():
	var card_specs: Array[Dictionary] = [{"atlas_seed": 5, "position": Vector2(10, 10), "growth": 0.6}]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var transform: Transform2D = instances[0].transform
	assert_almost_eq(transform.x.x, 0.6, 0.001)
	assert_almost_eq(transform.y.y, 0.6, 0.001)


func test_instances_for_cards_never_scales_below_the_minimum_visible_floor():
	# maxf(0.3, growth): a barely-sprouted patch (growth near 0) must not
	# shrink to invisible.
	var card_specs: Array[Dictionary] = [{"atlas_seed": 5, "position": Vector2.ZERO, "growth": 0.0}]
	var instances := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2.ZERO, Vector2i(1254, 1254))
	var transform: Transform2D = instances[0].transform
	assert_almost_eq(transform.x.x, 0.3, 0.001)


## Whichever band a card ultimately lands in, its own atlas region/root
## position/growth-derived scale must be byte-identical -- only the
## band_anchor (a local-position offset, not a placement input) may differ.
func test_instances_for_cards_placement_is_independent_of_which_band_anchor_it_is_drawn_relative_to():
	var card_specs: Array[Dictionary] = [{"atlas_seed": 9, "position": Vector2(50.0, 80.0), "growth": 0.75}]
	var instances_a := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2(0.0, 0.0), Vector2i(1254, 1254))
	var instances_b := IllustratedGrassPatch.instances_for_cards(card_specs, Vector2(200.0, -400.0), Vector2i(1254, 1254))
	var transform_a: Transform2D = instances_a[0].transform
	var transform_b: Transform2D = instances_b[0].transform
	assert_true(
		(transform_a.origin + Vector2(0.0, 0.0)).is_equal_approx(transform_b.origin + Vector2(200.0, -400.0)),
		"absolute placement must not depend on the band_anchor used to draw it"
	)
	assert_eq(instances_a[0].custom_data, instances_b[0].custom_data, "atlas region must not depend on the band_anchor")
	assert_almost_eq(transform_a.x.x, transform_b.x.x, 0.001, "growth-derived scale must not depend on the band_anchor")


func test_fill_band_rebuilds_cleanly_when_called_again_with_fewer_cards():
	# A cell losing its grass (grazed, built on) must not leave stale
	# instances behind from the previous call.
	var patch := IllustratedGrassPatch.new()
	var mmi: MultiMeshInstance2D = autofree(MultiMeshInstance2D.new())
	var cell_a := {"seed": 1, "ground_position": Vector2(0, 0), "growth": 1.0}
	var cell_b := {"seed": 2, "ground_position": Vector2(16, 0), "growth": 1.0}
	var all_cards: Array[Dictionary] = []
	all_cards.append_array(IllustratedGrassPatch.cards_for_cell(cell_a))
	all_cards.append_array(IllustratedGrassPatch.cards_for_cell(cell_b))
	patch.fill_band(mmi, Vector2.ZERO, all_cards)
	var before := mmi.multimesh.instance_count
	patch.fill_band(mmi, Vector2.ZERO, IllustratedGrassPatch.cards_for_cell(cell_a))
	assert_lt(mmi.multimesh.instance_count, before)
	assert_eq(mmi.multimesh.instance_count, IllustratedGrassPatch.CARD_COUNT)


# -- a field carries the season, like the ground it stands in ----------------

## The blade shader had no colour term at all -- the sampled atlas texel was
## written straight through -- so tall grass stayed lush in deep winter while
## the trees above it stood bare. See SeasonalFoliage / concept/seasons.md.
func test_the_blade_shader_takes_a_season_tint_uniform():
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, "uniform vec3 season_tint")


## The delivered atlas already carries some dry/brown blades; those must not
## be turned again by a season they are already wearing.
func test_the_blade_shader_gates_the_season_tint_on_greenness_with_the_shared_gain():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	var fragment_body := code.substr(code.find("void fragment()"))
	assert_string_contains(fragment_body, "COLOR.g - max(COLOR.r, COLOR.b)")
	assert_string_contains(fragment_body, "* %s" % SeasonalFoliage.GREENNESS_GAIN)
	assert_string_contains(fragment_body, "mix(COLOR.rgb, COLOR.rgb * season_tint")


## A field and the ground under it must turn together -- a straw-coloured
## meadow standing on a bright green lawn is the same defect one layer up.
func test_the_blades_and_the_ground_under_them_use_the_same_greenness_gate():
	var gate := "clamp((COLOR.g - max(COLOR.r, COLOR.b)) * %s, 0.0, 1.0)" % SeasonalFoliage.GREENNESS_GAIN
	assert_string_contains(IllustratedGrassPatch.SHADER_CODE, gate)
	assert_string_contains(GroundTint.SHADER_CODE, gate)


## Mirrors set_wind_strength exactly, member re-applied at lazy build time.
func test_set_season_tint_survives_being_called_before_the_material_is_built():
	var patch := IllustratedGrassPatch.new()
	var winter := SeasonalFoliage.tint_for_season("winter")
	patch.set_season_tint(winter)
	var parameter = patch.material().get_shader_parameter("season_tint")
	assert_almost_eq(parameter.x, winter.r, 0.0001)
	assert_almost_eq(parameter.y, winter.g, 0.0001)
	assert_almost_eq(parameter.z, winter.b, 0.0001)


## The shader source is built by ONE positional `%` array, so appending the
## new greenness gain in the wrong slot would silently bake the wrong numbers
## into the bend math -- a shader that still compiles and just looks wrong.
## This pins the tuned constants that would move if that happened.
func test_the_bend_math_still_carries_its_own_tuned_constants():
	var code: String = IllustratedGrassPatch.SHADER_CODE
	assert_string_contains(
		code, "pow(clamp(UV.y, 0.0, 1.0), %s)" % IllustratedGrassPatch.BEND_CURVE_EXPONENT
	)
	assert_string_contains(code, "UV.x * %s" % IllustratedGrassPatch.PHASE_SPREAD)
	assert_string_contains(
		code,
		"%s + %s * sin(UV.x * %s)" % [
			IllustratedGrassPatch.AMPLITUDE_BASE,
			IllustratedGrassPatch.AMPLITUDE_VARIATION,
			IllustratedGrassPatch.AMPLITUDE_FREQUENCY,
		]
	)
	assert_string_contains(
		code, "* %s * wind_strength" % IllustratedGrassPatch.WIND_UV_AMPLITUDE
	)
	assert_string_contains(
		code, "wake * %s" % IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE
	)
