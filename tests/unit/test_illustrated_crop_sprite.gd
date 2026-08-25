extends GutTest

## Slices the real AI-illustrated carrot/potato sheets (see
## docs/art/ai_sprite_prompts.md section 2, docs/concept/wild_crops.md) into
## ready-to-use textures: 3 growth-stage leaf frames + several root/tuber
## color variants, per crop. Chroma-keyed magenta background + near-white
## divider lines -- the same sheep.png recipe IllustratedAnimalSprite
## already established.

const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")

var crop: IllustratedCropSprite


func before_each():
	crop = IllustratedCropSprite.new()


func test_has_crop_is_true_for_registered_crops():
	assert_true(crop.has_crop("carrot"))
	assert_true(crop.has_crop("potato"))


func test_has_crop_is_false_for_an_unregistered_crop():
	assert_false(crop.has_crop("cabbage"))


func test_leaf_texture_returns_a_real_texture_for_every_growth_stage():
	for stage in 3:
		var texture := crop.leaf_texture("carrot", stage)
		assert_not_null(texture, "stage %d should have a texture" % stage)
		assert_gt(texture.get_width(), 0)


func test_leaf_texture_stages_are_visually_distinct():
	var seedling := crop.leaf_texture("carrot", 0).get_image().get_data()
	var vegetative := crop.leaf_texture("carrot", 1).get_image().get_data()
	var mature := crop.leaf_texture("carrot", 2).get_image().get_data()
	assert_ne(seedling, vegetative)
	assert_ne(vegetative, mature)


func test_leaf_texture_is_deterministic():
	var a := crop.leaf_texture("carrot", 2).get_image().get_data()
	var b := crop.leaf_texture("carrot", 2).get_image().get_data()
	assert_eq(a, b)


func test_leaf_texture_works_for_potato_too():
	var texture := crop.leaf_texture("potato", 1)
	assert_not_null(texture)


## Reported live: "it seems they don't use the illustrated crop variants for
## potato and carrot" -- direct proof the two crops' art is not, in fact,
## the same file/frames.
func test_carrot_and_potato_leaf_textures_are_visually_distinct():
	for stage in 3:
		var carrot_data := crop.leaf_texture("carrot", stage).get_image().get_data()
		var potato_data := crop.leaf_texture("potato", stage).get_image().get_data()
		assert_ne(carrot_data, potato_data, "stage %d should look different between crops" % stage)


func test_carrot_and_potato_root_textures_are_visually_distinct():
	for seed_value in 3:
		var carrot_data := crop.root_texture("carrot", seed_value).get_image().get_data()
		var potato_data := crop.root_texture("potato", seed_value).get_image().get_data()
		assert_ne(carrot_data, potato_data, "seed %d should look different between crops" % seed_value)


func test_leaf_texture_returns_null_for_an_unregistered_crop():
	assert_null(crop.leaf_texture("cabbage", 0))


func test_root_texture_returns_a_real_texture():
	var texture := crop.root_texture("carrot", 0)
	assert_not_null(texture)
	assert_gt(texture.get_width(), 0)


## The sheet has several color variants (see the art prompt's 7-cell root
## sheet) -- different seeds should be able to land on different variants,
## not just always returning the same one frame.
func test_root_texture_varies_by_seed():
	var images := []
	for seed_value in 7:
		images.append(crop.root_texture("carrot", seed_value).get_image().get_data())
	var distinct := {}
	for image_data in images:
		distinct[image_data] = true
	assert_gt(distinct.size(), 1, "different seeds should not all land on the exact same root variant")


func test_root_texture_works_for_potato_too():
	assert_not_null(crop.root_texture("potato", 3))


func test_root_texture_returns_null_for_an_unregistered_crop():
	assert_null(crop.root_texture("cabbage", 0))


# -- mapping continuous growth (0..1) onto a discrete stage index -----------

func test_growth_stage_index_seedling_below_a_third():
	assert_eq(IllustratedCropSprite.growth_stage_index(0.0), 0)
	assert_eq(IllustratedCropSprite.growth_stage_index(0.3), 0)


func test_growth_stage_index_vegetative_between_a_third_and_one():
	assert_eq(IllustratedCropSprite.growth_stage_index(1.0 / 3.0), 1)
	assert_eq(IllustratedCropSprite.growth_stage_index(0.6), 1)


func test_growth_stage_index_mature_at_and_above_one():
	assert_eq(IllustratedCropSprite.growth_stage_index(1.0), 2)
	assert_eq(IllustratedCropSprite.growth_stage_index(5.0), 2)


# -- final on-screen size: comparable to the existing dropped-fruit family,
# never tile-sized (the exact bug already fixed once for tree fruit -- see
# ProceduralItemSprite.WORLD_WIDTH_BY_ID's own doc comment: "gigantic").
#
# First pass sized off CANVAS WIDTH alone (LEAF_CANVAS_SIZE/ROOT_CANVAS_SIZE
# are portrait -- taller than wide -- to fit the source art's own elongated
## proportions), which left the actual on-screen HEIGHT of a portrait-shaped
# plant nowhere close to constrained -- reported live, twice, as "huge
# potato crops above soil" even after a first width-only re-tune. Replaced
# with a MEASURED scale (max_content_extent, mirroring
# IllustratedAnimalSprite.marker_scale's own "measure the real drawn
# pixels, not the nominal canvas" precedent): whichever of a frame's own
# width/height is larger is what gets constrained to the target size, so
# neither dimension can ever exceed it regardless of the source art's
# aspect ratio.

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func test_leaf_and_root_world_sizes_are_smaller_than_a_full_tile():
	assert_lt(IllustratedCropSprite.LEAF_WORLD_SIZE, TerrainRenderer.TILE_SIZE)
	assert_lt(IllustratedCropSprite.ROOT_WORLD_SIZE, TerrainRenderer.TILE_SIZE)


func test_max_content_extent_measures_the_real_drawn_pixels_not_the_canvas():
	# A frame's measured extent must be its own real opaque-pixel bounding
	# box, strictly smaller than the (padded) canvas it was normalized onto.
	var texture := crop.leaf_texture("carrot", 2)
	var extent := IllustratedCropSprite.max_content_extent(texture)
	assert_gt(extent, 0.0)
	assert_lt(extent, float(IllustratedCropSprite.LEAF_CANVAS_SIZE.y))


## The actual invariant that matters: applying the computed scale to EVERY
## stage's own real content extent must never exceed the declared target
## size, in either dimension -- not just at the canvas level.
func test_leaf_world_scale_keeps_every_stage_within_the_target_size():
	for crop_id in ["carrot", "potato"]:
		var scale: float = crop.leaf_world_scale(crop_id)
		assert_gt(scale, 0.0)
		for stage in 3:
			var extent := IllustratedCropSprite.max_content_extent(crop.leaf_texture(crop_id, stage))
			assert_lte(extent * scale, IllustratedCropSprite.LEAF_WORLD_SIZE + 0.01)


func test_root_world_scale_keeps_every_variant_within_the_target_size():
	for crop_id in ["carrot", "potato"]:
		var scale: float = crop.root_world_scale(crop_id)
		assert_gt(scale, 0.0)
		for seed_value in 7:
			var extent := IllustratedCropSprite.max_content_extent(crop.root_texture(crop_id, seed_value))
			assert_lte(extent * scale, IllustratedCropSprite.ROOT_WORLD_SIZE + 0.01)


## A raw `Image.load_from_file` on a `res://` path logs the engine warning
## "Loaded resource as image file, this will not work on export", which GUT's
## error tracker counts as an unhandled error -- see SpriteSheetLoader's own
## doc comment for why that warning is real (the raw source PNG does not ship
## in an exported build the way its imported resource does).
##
## The STATIC frame caches are cleared first (shared across every test in this
## file) so this genuinely re-reads carrot.png/carrot_leaves.png off disk
## rather than hitting a cache an earlier test already warmed.
func test_loading_a_crop_sheet_does_not_log_an_engine_warning():
	IllustratedCropSprite._leaf_frame_cache.clear()
	IllustratedCropSprite._root_frame_cache.clear()
	crop.root_texture("carrot", 0)
	crop.leaf_texture("carrot", 0)
	assert_engine_error_count(0, "loading a crop sheet should not warn")
