extends GutTest

## Wheat's own real illustrated art, sliced from the same 10x10 grid/black-
## chroma-key convention long grass's own atlases use (see
## docs/concept/long_grass.md's "A second atlas family: farmed wheat" and
## tools/probe_wheat_sheet_bleed.gd, which measured zero cross-row bleed on
## all three delivered sheets -- unlike grass's own art).

const IllustratedWheatPatch = preload("res://src/rendering/illustrated_wheat_patch.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")

var wheat: IllustratedWheatPatch


func before_each():
	wheat = IllustratedWheatPatch.new()


# -- sheet selection ----------------------------------------------------------


func test_has_sheet_is_true_for_every_delivered_season():
	assert_true(wheat.has_sheet("spring"))
	assert_true(wheat.has_sheet("summer"))
	assert_true(wheat.has_sheet("autumn"))


func test_has_sheet_is_false_for_an_undelivered_season():
	assert_false(wheat.has_sheet("winter"))


func test_sheet_for_season_passes_through_a_delivered_season():
	assert_eq(wheat.sheet_for_season("spring"), "spring")
	assert_eq(wheat.sheet_for_season("autumn"), "autumn")


## No wheat_winter.png exists yet -- an undelivered/unrecognised season name
## falls back to DEFAULT_SEASON, mirroring IllustratedGrassPatch's own
## fallback shape for a season it doesn't have art for.
func test_sheet_for_season_falls_back_to_default_for_an_undelivered_season():
	assert_eq(wheat.sheet_for_season("winter"), IllustratedWheatPatch.DEFAULT_SEASON)
	assert_eq(wheat.sheet_for_season("not_a_real_season"), IllustratedWheatPatch.DEFAULT_SEASON)


func test_default_season_is_itself_a_delivered_sheet():
	assert_true(wheat.has_sheet(IllustratedWheatPatch.DEFAULT_SEASON))


# -- atlas region math (reuses IllustratedGrassPatch's own grid constants) ---


func test_region_for_row_0_column_0_is_the_top_left_cell():
	var region := IllustratedWheatPatch.region_for(0, 0, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE)
	assert_eq(region.position, Vector2i(0, 0))
	assert_between(region.size.x, 125, 126)
	assert_between(region.size.y, 125, 126)


func test_region_for_the_last_row_and_column_reaches_the_sheets_own_far_edge():
	var region := IllustratedWheatPatch.region_for(9, 9, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE)
	assert_eq(region.position + region.size, IllustratedGrassPatch.DEFAULT_ATLAS_SIZE)


func test_row_for_growth_climbs_from_shoot_to_full_bush():
	assert_eq(IllustratedWheatPatch.row_for_growth(0.0), 0)
	assert_eq(IllustratedWheatPatch.row_for_growth(1.0), IllustratedGrassPatch.ATLAS_ROWS - 1)
	assert_eq(IllustratedWheatPatch.row_for_growth(0.45), 4)


func test_row_for_growth_clamps_out_of_range_input():
	assert_eq(IllustratedWheatPatch.row_for_growth(-1.0), 0)
	assert_eq(IllustratedWheatPatch.row_for_growth(5.0), IllustratedGrassPatch.ATLAS_ROWS - 1)


## Measured directly (tools/probe_wheat_sheet_bleed.gd) against all three
## real delivered sheets -- a genuine "measured, found none" result, unlike
## IllustratedGrassPatch's own ROW_TOP_BLEED_PX_BY_SEASON. Pinned by test so
## a future remeasurement against a regenerated sheet has to touch this
## deliberately rather than the table silently going stale.
func test_bleed_table_is_measured_zero_for_every_row():
	assert_eq(IllustratedWheatPatch.BLEED_PX_BY_ROW, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])


# -- real frame slicing (headless-safe: Image loading, no renderer needed) ---


func test_frame_texture_returns_a_real_texture_for_a_delivered_season():
	var texture := wheat.frame_texture("summer", 9, 0)
	assert_not_null(texture)
	assert_gt(texture.get_width(), 0)
	assert_gt(texture.get_height(), 0)


func test_frame_texture_falls_back_to_the_default_seasons_art_for_winter():
	var winter := wheat.frame_texture("winter", 5, 2).get_image().get_data()
	var summer := wheat.frame_texture("summer", 5, 2).get_image().get_data()
	assert_eq(winter, summer)


func test_frame_texture_growth_stages_are_visually_distinct():
	var shoot := wheat.frame_texture("summer", 0, 0).get_image().get_data()
	var bush := wheat.frame_texture("summer", 9, 0).get_image().get_data()
	assert_ne(shoot, bush)


func test_frame_texture_seasons_are_visually_distinct_at_the_same_row_and_column():
	var spring := wheat.frame_texture("spring", 9, 0).get_image().get_data()
	var summer := wheat.frame_texture("summer", 9, 0).get_image().get_data()
	var autumn := wheat.frame_texture("autumn", 9, 0).get_image().get_data()
	assert_ne(spring, summer)
	assert_ne(summer, autumn)


## Background is real black (see BACKGROUND_KEY), not the magenta
## IllustratedCropSprite's carrot/potato sheets use -- confirms the corner
## of a sliced frame (never real plant art in any cell) actually keyed out
## to transparent rather than showing as an opaque black square.
func test_frame_backgrounds_are_chroma_keyed_transparent():
	var image := wheat.frame_texture("summer", 0, 0).get_image()
	assert_lt(image.get_pixel(0, 0).a, 0.05)


# -- world scale (avoids the exact "gigantic sprite" bug already fixed once --
# -- see IllustratedCropSprite.LEAF_WORLD_SIZE's own doc comment) ------------


func test_blade_world_scale_is_positive_and_finite():
	var scale := wheat.blade_world_scale("summer", 9, 0)
	assert_gt(scale, 0.0)
	assert_lt(scale, 100.0)


# -- per-blade placement (reuses IllustratedGrassPatch's own deterministic --
# -- offset shape, scaled to the smaller soil-mound footprint) ---------------


func test_blade_specs_for_seed_returns_one_spec_per_blade():
	var specs := IllustratedWheatPatch.blade_specs_for_seed(7)
	assert_eq(specs.size(), IllustratedGrassPatch.CARD_COUNT)


func test_blade_specs_for_seed_is_deterministic():
	var a := IllustratedWheatPatch.blade_specs_for_seed(7)
	var b := IllustratedWheatPatch.blade_specs_for_seed(7)
	assert_eq(a, b)


func test_blade_specs_for_different_seeds_differ():
	var a := IllustratedWheatPatch.blade_specs_for_seed(7)
	var b := IllustratedWheatPatch.blade_specs_for_seed(8)
	assert_ne(a, b)


## Offsets must stay comfortably inside the soil mound's own real footprint
## (ProceduralSoilSprite.SOIL_WORLD_WIDTH), not spread across a whole tile
## the way IllustratedGrassPatch's own open-field offsets do -- a farm
## plot's crop must visually sit ON its own tilled soil, never spill past it.
func test_blade_specs_stay_within_the_soil_mounds_own_footprint():
	const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")
	var half_width: float = ProceduralSoilSprite.SOIL_WORLD_WIDTH * 0.5
	for seed_value in range(20):
		for spec in IllustratedWheatPatch.blade_specs_for_seed(seed_value):
			var offset: Vector2 = spec.offset
			assert_lte(absf(offset.x), half_width, "seed %d" % seed_value)
			assert_lte(absf(offset.y), half_width, "seed %d" % seed_value)


# -- shader reuses long grass's own bend/wind/push constants verbatim -------


func test_shader_code_embeds_the_exact_same_bend_curve_exponent_as_long_grass():
	assert_true(
		IllustratedWheatPatch.SHADER_CODE.contains(str(IllustratedGrassPatch.BEND_CURVE_EXPONENT)),
		"wheat's shader must reuse grass's own tuned constant, not restate a copy that can drift"
	)


func test_shader_code_embeds_the_exact_same_walker_push_amplitude_as_long_grass():
	assert_true(
		IllustratedWheatPatch.SHADER_CODE.contains(str(IllustratedGrassPatch.WALKER_PUSH_UV_AMPLITUDE))
	)


# -- shared material + live wind/walker uniforms (headless-safe: creating a --
# -- ShaderMaterial needs no renderer, only actually drawing with it does) ---


func test_material_is_a_real_shader_material_using_the_shared_shader_code():
	var material := IllustratedWheatPatch.material()
	assert_not_null(material)
	assert_eq(material.shader.code, IllustratedWheatPatch.SHADER_CODE)


func test_material_is_shared_across_calls():
	assert_eq(IllustratedWheatPatch.material(), IllustratedWheatPatch.material())


func test_set_wind_strength_pushes_the_live_uniform():
	IllustratedWheatPatch.set_wind_strength(2.5)
	assert_eq(IllustratedWheatPatch.material().get_shader_parameter("wind_strength"), 2.5)


func test_set_walker_position_pushes_the_live_uniform():
	IllustratedWheatPatch.set_walker_position(Vector2(10.0, 20.0))
	assert_eq(IllustratedWheatPatch.material().get_shader_parameter("player_world_position"), Vector2(10.0, 20.0))
