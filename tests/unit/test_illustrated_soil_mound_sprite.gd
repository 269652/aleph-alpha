extends GutTest

## Real illustrated art for a farm bed's tilled soil mound (see
## FarmPlotMarker, ProceduralSoilSprite's own "swappable for real art
## later" doc comment, docs/concept/wild_crops.md's "Soil mound" entry) --
## a 3x3 grid of independent undisturbed-mound variants.
##
## assets/sprites/terrain/soil_mound.png's gutters are near-BLACK, not
## chroma-keyed magenta -- the exact same structural quirk
## IllustratedTerrainSprite's "soil" entry already hit (see
## test_illustrated_terrain_sprite.gd's own "a sheet whose background is
## BLACK" section) -- so this sheet is measured off its own real gutters
## at load time rather than assumed to divide evenly.

const IllustratedSoilMoundSprite = preload("res://src/rendering/illustrated_soil_mound_sprite.gd")

const EXPECTED_FRAME_COUNT := 9

var sprite: IllustratedSoilMoundSprite


func before_each():
	sprite = IllustratedSoilMoundSprite.new()


func test_has_variants_is_true():
	assert_true(sprite.has_variants())


func test_frame_for_returns_a_real_texture():
	assert_not_null(sprite.frame_for(0))


func test_sheet_slices_into_nine_frames():
	assert_eq(sprite.frame_count(), EXPECTED_FRAME_COUNT)


## Every variant has to be real tilled earth+mound, not a slab of the
## black gutter that separates the cells -- the same "mostly near-black
## means gutter, not content" guard test_illustrated_terrain_sprite.gd's
## soil test uses.
func test_every_variant_is_real_ground_not_gutter():
	for variant in sprite.frame_count():
		var frame: Image = sprite.frame_for(variant).get_image()
		assert_not_null(frame, "variant %d" % variant)
		var dark := 0
		var total := 0
		for y in frame.get_height():
			for x in frame.get_width():
				var c := frame.get_pixel(x, y)
				total += 1
				if maxf(c.r, maxf(c.g, c.b)) <= 0.06:
					dark += 1
		assert_lt(
			float(dark) / float(total),
			0.2,
			"variant %d is %d/%d near-black -- that is gutter, not ground" % [variant, dark, total]
		)


func test_frame_for_is_deterministic_for_the_same_seed():
	assert_eq(sprite.frame_for(7), sprite.frame_for(7))


func test_different_seeds_spread_across_the_full_variant_pool():
	var seen := {}
	for seed_value in 50:
		seen[sprite.frame_for(seed_value)] = true
	assert_gt(seen.size(), 1, "50 different seeds should pick more than one variant")


## The illustrated mound has to read at the same real-world footprint the
## procedural mound it replaces already does (FarmPlotMarker/WildCropMarker
## never changed, so a differently-scaled swap would suddenly render a
## giant or tiny mound under every bed).
func test_world_scale_matches_the_procedural_mounds_own_footprint():
	const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")
	var frame: Image = sprite.frame_for(0).get_image()
	assert_almost_eq(
		sprite.world_scale() * frame.get_width(),
		ProceduralSoilSprite.SOIL_WORLD_WIDTH,
		0.5
	)
