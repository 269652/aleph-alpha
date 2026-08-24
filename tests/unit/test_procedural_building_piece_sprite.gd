extends GutTest

## Tile art for BuildingPiece.PIECE_IDS -- see docs/concept/building.md.
## Mirrors test_procedural_structure_sprite.gd's shape: one generator, one
## opaque ART_TILE_SIZE tile per known id, deterministic, real texture (not
## a flat fill), category/material visually distinguishable from each other.

const ProceduralBuildingPieceSprite = preload("res://src/rendering/procedural_building_piece_sprite.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var generator: ProceduralBuildingPieceSprite


func before_each():
	generator = ProceduralBuildingPieceSprite.new()


func _pixel_diff_count(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func test_generated_image_has_the_expected_size():
	for piece_id in BuildingPiece.PIECE_IDS:
		var image: Image = generator.generate_image(piece_id)
		assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE, piece_id)
		assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE, piece_id)


## Every piece tile is fully opaque -- these render as full ground-plane
## tiles like plain earth/campfire/furnace, not a sprite over transparent
## background.
func test_generated_image_is_fully_opaque():
	for piece_id in BuildingPiece.PIECE_IDS:
		var image: Image = generator.generate_image(piece_id)
		for y in image.get_height():
			for x in image.get_width():
				assert_eq(image.get_pixel(x, y).a, 1.0, "%s (%d,%d)" % [piece_id, x, y])


func test_generated_image_is_not_a_flat_color_fill():
	for piece_id in BuildingPiece.PIECE_IDS:
		var image: Image = generator.generate_image(piece_id)
		var first_pixel := image.get_pixel(0, 0)
		var all_same := true
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y) != first_pixel:
					all_same = false
		assert_false(all_same, "%s tile should use real procedural texture, not a flat fill" % piece_id)


func test_generated_image_is_deterministic():
	for piece_id in BuildingPiece.PIECE_IDS:
		var first: Image = generator.generate_image(piece_id)
		var second: Image = generator.generate_image(piece_id)
		assert_eq(_pixel_diff_count(first, second), 0, piece_id)


## Every piece must be visually distinguishable from every other -- a floor
## must not look like a wall, a door must stand out from the wall it's set
## into, and wood must read differently from stone.
func test_every_piece_is_visually_distinct_from_every_other():
	var images := {}
	for piece_id in BuildingPiece.PIECE_IDS:
		images[piece_id] = generator.generate_image(piece_id)
	for i in BuildingPiece.PIECE_IDS.size():
		for j in range(i + 1, BuildingPiece.PIECE_IDS.size()):
			var a: String = BuildingPiece.PIECE_IDS[i]
			var b: String = BuildingPiece.PIECE_IDS[j]
			assert_gt(
				_pixel_diff_count(images[a], images[b]), TerrainRenderer.ART_TILE_SIZE,
				"%s and %s should look clearly different" % [a, b]
			)


## Wood pieces should read warmer (more saturated toward red/brown) than
## their stone counterpart, mirroring campfire/furnace's warm-vs-cool
## distinction.
func test_wood_and_stone_of_the_same_category_are_distinct_materials():
	for category in [
		BuildingPiece.CATEGORY_FLOOR, BuildingPiece.CATEGORY_WALL,
		BuildingPiece.CATEGORY_DOOR, BuildingPiece.CATEGORY_WINDOW, BuildingPiece.CATEGORY_ROOF,
	]:
		var wood: Image = generator.generate_image("wood_%s" % category)
		var stone: Image = generator.generate_image("stone_%s" % category)
		assert_gt(_pixel_diff_count(wood, stone), TerrainRenderer.ART_TILE_SIZE, category)


func test_generate_texture_returns_an_image_texture_of_matching_size():
	var texture: ImageTexture = generator.generate_texture("wood_wall")
	assert_eq(texture.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(texture.get_height(), TerrainRenderer.ART_TILE_SIZE)


## Fail-safe default -- an unrecognized id still returns a well-formed tile
## instead of crashing.
func test_unknown_piece_id_falls_back_without_crashing():
	var image: Image = generator.generate_image("mystery_piece")
	assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE)


# -- pitched roof variants -----------------------------------------------------
#
# See docs/concept/building.md "How a house reads from above". A roof drawn
# as one flat shingle texture reads from above as a brick patio, which is a
# large part of why village houses "don't resemble houses at all". These
# variants carry the PITCH (a shade band, brightest at the ridge, falling to
# the eaves -- see RoofShape) and the building's SILHOUETTE (an edge mask,
# so the rim is drawn on the structure's outer boundary instead of around
# every individual tile).

const RoofShape = preload("res://src/rendering/roof_shape.gd")


func test_every_shade_band_renders_at_the_pinned_size():
	for band in RoofShape.TOTAL_SHADE_BANDS:
		var image := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, band, 0)
		assert_eq(image.get_width(), ProceduralBuildingPieceSprite.SIZE, "band %d" % band)
		assert_eq(image.get_height(), ProceduralBuildingPieceSprite.SIZE, "band %d" % band)


func test_roof_variants_are_fully_opaque():
	var image := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_STONE, 2, 5)
	for y in image.get_height():
		for x in image.get_width():
			assert_eq(image.get_pixel(x, y).a, 1.0, "roof tiles are ground-plane cells, never see-through")


## The tuned brightness ramp is a tested FUNCTION, not eyeballed constants
## sprinkled through the drawing code (CLAUDE.md: "tuned values/thresholds
## must be tested functions or test-pinned constants").
func test_the_shade_ramp_is_brightest_at_the_lit_ridge_and_darkest_at_the_shaded_eave():
	var lit_ridge := ProceduralBuildingPieceSprite.shade_factor_for_band(0)
	var shaded_eave := ProceduralBuildingPieceSprite.shade_factor_for_band(RoofShape.TOTAL_SHADE_BANDS - 1)
	assert_gt(lit_ridge, shaded_eave, "the ridge catches the light; the far eave is in shade")


func test_the_shade_ramp_never_brightens_as_it_descends_a_slope():
	var previous := ProceduralBuildingPieceSprite.shade_factor_for_band(0)
	for band in range(1, RoofShape.TOTAL_SHADE_BANDS):
		var factor := ProceduralBuildingPieceSprite.shade_factor_for_band(band)
		assert_lte(factor, previous, "band %d brightened again; the ramp must fall" % band)
		previous = factor


## The ridge is where the two slopes meet, so the step ACROSS it (last lit
## band -> first shaded band) must be the most visible jump in the whole
## ramp -- that hard contrast line is what actually reads as a ridge beam,
## without needing a separate ridge tile.
func test_the_step_across_the_ridge_is_larger_than_any_step_within_one_slope():
	var lit_last: float = ProceduralBuildingPieceSprite.shade_factor_for_band(RoofShape.FIRST_SHADED_BAND - 1)
	var shaded_first: float = ProceduralBuildingPieceSprite.shade_factor_for_band(RoofShape.FIRST_SHADED_BAND)
	var ridge_step: float = lit_last - shaded_first
	for band in range(1, RoofShape.TOTAL_SHADE_BANDS):
		if band == RoofShape.FIRST_SHADED_BAND:
			continue
		var step: float = (
			ProceduralBuildingPieceSprite.shade_factor_for_band(band - 1)
			- ProceduralBuildingPieceSprite.shade_factor_for_band(band)
		)
		assert_gt(ridge_step, step, "the ridge step must dominate the within-slope step at band %d" % band)


func test_a_brighter_band_actually_renders_brighter():
	var bright := _mean_brightness(generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, 0, 0))
	var dark := _mean_brightness(
		generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, RoofShape.TOTAL_SHADE_BANDS - 1, 0)
	)
	assert_gt(bright, dark, "the shade band has to reach the actual pixels, not just the ramp function")


## The silhouette fix: an interior tile draws NO rim, so a run of roof cells
## reads as one continuous surface instead of a grid of outlined boxes (the
## reported "randomly placed panels" look).
func test_an_unmasked_tile_is_not_darkened_around_its_border():
	var image := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, 1, 0)
	var top_left := image.get_pixel(0, 0)
	var interior := image.get_pixel(ProceduralBuildingPieceSprite.SIZE / 2, 0)
	assert_almost_eq(top_left.r, interior.r, 0.02, "an unmasked edge must not be rimmed")


func test_a_masked_side_is_visibly_rimmed():
	var plain := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, 1, 0)
	var rimmed := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, 1, RoofShape.EDGE_NORTH)
	var mid := ProceduralBuildingPieceSprite.SIZE / 2
	assert_lt(
		rimmed.get_pixel(mid, 0).r, plain.get_pixel(mid, 0).r,
		"a north-facing outer edge should carry the building's outline"
	)


## Each side is rimmed independently -- a north-only mask must leave the
## other three sides untouched, or every tile ends up outlined again.
func test_masking_one_side_leaves_the_others_alone():
	var north_only := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, 1, RoofShape.EDGE_NORTH)
	var plain := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, 1, 0)
	var mid := ProceduralBuildingPieceSprite.SIZE / 2
	var last := ProceduralBuildingPieceSprite.SIZE - 1
	assert_almost_eq(north_only.get_pixel(mid, last).r, plain.get_pixel(mid, last).r, 0.02, "south untouched")
	assert_almost_eq(north_only.get_pixel(0, mid).r, plain.get_pixel(0, mid).r, 0.02, "west untouched")
	assert_almost_eq(north_only.get_pixel(last, mid).r, plain.get_pixel(last, mid).r, 0.02, "east untouched")


func test_roof_variants_are_deterministic():
	var a := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_STONE, 3, 9)
	var b := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_STONE, 3, 9)
	assert_eq(a.get_data(), b.get_data())


func test_wood_and_stone_roof_variants_differ():
	var wood := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_WOOD, 2, 0)
	var stone := generator.generate_roof_variant_image(BuildingPiece.MATERIAL_STONE, 2, 0)
	assert_ne(wood.get_data(), stone.get_data())


func _mean_brightness(image: Image) -> float:
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
	return total / float(image.get_width() * image.get_height())
