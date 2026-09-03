extends GutTest

## The illustrated snow STAMPS the GPU bombing shader draws with (see
## docs/concept/snow_cover.md, src/rendering/snow_bomb_shader.gd).
##
## Snow used to be a baked TileSet of one image per (depth band, shape
## variant) pair, painted per tile by EarthChunkManager's own 2-second sweep
## over every loaded tile. This replaces that with a single stamp ATLAS: the
## art, cropped and normalized once, handed to a fragment shader that decides
## per PIXEL which stamps overlap it. Nothing here knows about depth bands,
## tiles, or coverage -- it only prepares the art.

const SnowStampAtlas = preload("res://src/rendering/snow_stamp_atlas.gd")

var atlas: SnowStampAtlas


func before_each():
	atlas = SnowStampAtlas.new()


# -- the level ladder --------------------------------------------------------

## The ladder is whichever `snow_<level>.png` sheets actually exist, ascending
## -- deliberately NOT a hardcoded list. The artist has drawn levels 1, 5 and
## 6 so far; dropping in snow_2/3/4.png must extend the ladder with no code
## change (see docs/concept/snow_cover.md's "The art" section).
func test_the_level_ladder_is_whichever_sheets_actually_exist():
	var levels := atlas.levels()
	assert_gte(levels.size(), 3, "a dusting, a patch and near-full cover at the very least")
	assert_eq(levels[0], 1, "snow_1.png is the sparsest sheet the artist drew")
	var previous := -1
	for level in levels:
		assert_gt(level, previous, "the ladder must be ascending, not sheet-listing order")
		previous = level


## Every sheet is a 5x2 grid of ten shape variants at that level. Measured
## from the real PNGs rather than assumed: an occupancy sweep (is there ANY
## non-transparent pixel in this column / row?) must find exactly five
## column runs and two row runs, with real empty gutters between them.
func test_every_sheet_is_a_five_by_two_grid_with_real_gutters():
	assert_eq(SnowStampAtlas.VARIANTS_PER_LEVEL, 10)
	for level in atlas.levels():
		var sheet := atlas.sheet_image(level)
		assert_not_null(sheet, "snow_%d.png must load" % level)
		assert_eq(
			atlas.occupied_column_runs(sheet).size(), SnowStampAtlas.SHEET_COLUMNS,
			"snow_%d.png must show %d separated columns" % [level, SnowStampAtlas.SHEET_COLUMNS]
		)
		assert_eq(
			atlas.occupied_row_runs(sheet).size(), SnowStampAtlas.SHEET_ROWS,
			"snow_%d.png must show %d separated rows" % [level, SnowStampAtlas.SHEET_ROWS]
		)


## The sheets carry clean alpha: transparent backgrounds, and no dark opaque
## matte fringe that would draw as a black halo around every stamp. Checked
## because the sheets LOOK like they have black backgrounds when previewed --
## that is the transparency, and this is what proves it.
func test_the_sheets_carry_clean_alpha_with_no_dark_matte():
	for level in atlas.levels():
		var sheet := atlas.sheet_image(level)
		assert_almost_eq(
			sheet.get_pixel(0, 0).a, 0.0, 0.01,
			"snow_%d.png's corner must be transparent, not a background colour" % level
		)
		assert_lt(
			atlas.dark_opaque_fraction(sheet), 0.001,
			"snow_%d.png must carry no dark opaque matte fringe" % level
		)


# -- one stamp ---------------------------------------------------------------

## A stamp is a square of exactly the size the atlas packs, so the shader can
## address any stamp by a fixed cell stride.
func test_a_stamp_is_a_square_of_the_stamp_size():
	for level in atlas.levels():
		for variant in SnowStampAtlas.VARIANTS_PER_LEVEL:
			var stamp := atlas.build_stamp_image(level, variant)
			assert_eq(stamp.get_width(), SnowStampAtlas.STAMP_SIZE)
			assert_eq(stamp.get_height(), SnowStampAtlas.STAMP_SIZE)


## Every one of the thirty stamps carries real snow -- an empty or
## near-empty cell would draw as a hole in the cover that no amount of
## depth could fill.
func test_every_stamp_of_every_level_carries_real_snow():
	for level in atlas.levels():
		for variant in SnowStampAtlas.VARIANTS_PER_LEVEL:
			assert_gt(
				atlas.stamp_mean_alpha(level, variant), 0.01,
				"snow_%d variant %d is empty" % [level, variant]
			)


## The illustrated shapes must not be STRETCHED into the square cell: the
## source content bounding boxes are not square (measured: level 1's first
## cell is 197x216), so a naive resize to a square would squash every puff.
## Scaling by the smaller ratio and centring preserves the shape, which this
## checks by comparing the stamp's own drawn content aspect against the
## source content's.
func test_a_stamp_preserves_its_shapes_aspect_ratio():
	for level in atlas.levels():
		for variant in SnowStampAtlas.VARIANTS_PER_LEVEL:
			var source := atlas.source_content_aspect(level, variant)
			var drawn := atlas.stamp_content_aspect(level, variant)
			assert_almost_eq(
				drawn, source, 0.08,
				"snow_%d variant %d is stretched: %.3f drawn vs %.3f in the sheet"
					% [level, variant, drawn, source]
			)


## Deeper levels genuinely cover more ground -- the whole reason the level
## axis exists. Averaged across all ten variants per level, not one cell, so
## a single unusually-full variant cannot carry a level past its neighbour.
func test_deeper_levels_cover_more_ground():
	var previous := -1.0
	for level in atlas.levels():
		var mean := atlas.level_mean_alpha(level)
		assert_gt(
			mean, previous,
			"snow_%d covers %.4f, no more than the level below it" % [level, mean]
		)
		previous = mean


## The sparsest level must let its ground through, and the fullest must not
## -- the two ends of the ramp the shader builds between. Both pinned against
## measurements taken through the real build_stamp_image path (crop + fit +
## Lanczos), not the raw sheet's own means, since the resize measurably
## shifts mean alpha.
func test_the_sparsest_level_lets_the_ground_through_and_the_fullest_does_not():
	var levels := atlas.levels()
	for variant in SnowStampAtlas.VARIANTS_PER_LEVEL:
		assert_lt(
			atlas.stamp_mean_alpha(levels[0], variant),
			SnowStampAtlas.DUSTING_MAX_MEAN_ALPHA,
			"snow_%d variant %d is too solid to read as a dusting" % [levels[0], variant]
		)
		assert_gt(
			atlas.stamp_mean_alpha(levels[levels.size() - 1], variant),
			SnowStampAtlas.FULL_COVER_MIN_MEAN_ALPHA,
			"snow_%d variant %d is too thin to read as full cover"
				% [levels[levels.size() - 1], variant]
		)


## The ten variants at one level are real, different illustrated shapes --
## not ten copies of one blob. This is what stops a field of stamps reading
## as wallpaper.
func test_the_variants_at_one_level_are_genuinely_different_shapes():
	for level in atlas.levels():
		for variant in SnowStampAtlas.VARIANTS_PER_LEVEL - 1:
			assert_gt(
				atlas.stamp_difference(level, variant, variant + 1), 0.05,
				"snow_%d variants %d and %d draw nearly the same shape"
					% [level, variant, variant + 1]
			)


# -- the packed atlas --------------------------------------------------------

## Levels down, variants across -- the layout the shader's own cell
## arithmetic assumes.
func test_the_atlas_packs_levels_down_and_variants_across():
	var image := atlas.build_atlas_image()
	assert_eq(image.get_width(), SnowStampAtlas.VARIANTS_PER_LEVEL * SnowStampAtlas.CELL_SIZE)
	assert_eq(image.get_height(), atlas.levels().size() * SnowStampAtlas.CELL_SIZE)


## A cell of the packed atlas really is the stamp build_stamp_image builds
## for that (level, variant) -- the packing must not transpose the axes or
## drop a row, which a size check alone would not catch.
func test_each_atlas_cell_holds_its_own_levels_own_variant():
	var image := atlas.build_atlas_image()
	var levels := atlas.levels()
	for level_index in levels.size():
		for variant in SnowStampAtlas.VARIANTS_PER_LEVEL:
			var stamp := atlas.build_stamp_image(levels[level_index], variant)
			var origin := Vector2i(
				variant * SnowStampAtlas.CELL_SIZE + SnowStampAtlas.STAMP_PADDING,
				level_index * SnowStampAtlas.CELL_SIZE + SnowStampAtlas.STAMP_PADDING
			)
			var probe := Vector2i(SnowStampAtlas.STAMP_SIZE / 2, SnowStampAtlas.STAMP_SIZE / 2)
			assert_almost_eq(
				image.get_pixel(origin.x + probe.x, origin.y + probe.y).a,
				stamp.get_pixel(probe.x, probe.y).a, 0.01,
				"atlas cell (%d, %d) does not hold snow_%d variant %d"
					% [variant, level_index, levels[level_index], variant]
			)


## Every cell is surrounded by a transparent gutter, so the GPU's own
## bilinear filtering at a cell's edge cannot pull in the neighbouring
## stamp's pixels -- which would draw as a faint ghost of the wrong shape
## along every stamp's border.
func test_atlas_cells_have_a_transparent_gutter_so_filtering_cannot_bleed():
	assert_gt(SnowStampAtlas.STAMP_PADDING, 0, "there must be a gutter at all")
	var image := atlas.build_atlas_image()
	var levels := atlas.levels()
	for level_index in levels.size():
		for variant in SnowStampAtlas.VARIANTS_PER_LEVEL:
			var cell := Vector2i(variant, level_index) * SnowStampAtlas.CELL_SIZE
			for offset in SnowStampAtlas.CELL_SIZE:
				assert_almost_eq(
					image.get_pixel(cell.x + offset, cell.y).a, 0.0, 0.001,
					"cell (%d, %d)'s top gutter row is not transparent" % [variant, level_index]
				)
				assert_almost_eq(
					image.get_pixel(cell.x, cell.y + offset).a, 0.0, 0.001,
					"cell (%d, %d)'s left gutter column is not transparent"
						% [variant, level_index]
				)


## The texture the shader actually samples, built from the packed image and
## shared: the atlas is identical for every instance, and rebuilding it per
## caller would repeat the whole crop-and-resize pass for nothing.
func test_the_atlas_texture_is_built_once_and_shared():
	var first := atlas.atlas_texture()
	var second := SnowStampAtlas.new().atlas_texture()
	assert_not_null(first)
	assert_same(first, second, "the atlas texture must be shared, not rebuilt per instance")
	assert_eq(first.get_width(), SnowStampAtlas.VARIANTS_PER_LEVEL * SnowStampAtlas.CELL_SIZE)


## Mipmaps would let a minified stamp average across its gutter into the
## neighbouring cell -- the same bleed the gutter exists to prevent, just at
## a coarser level. The shader samples this atlas at one level only.
func test_the_atlas_texture_carries_no_mipmaps():
	assert_false(
		atlas.atlas_texture().has_mipmaps(),
		"mipmapping an atlas bleeds neighbouring cells together"
	)
