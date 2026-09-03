extends RefCounted

## The illustrated snow STAMPS the GPU bombing shader draws with (see
## docs/concept/snow_cover.md, snow_bomb_shader.gd).
##
## This class only prepares ART. It knows nothing about depth, tiles or
## coverage -- it crops the artist's leveled sheets into uniform square
## stamps and packs them into one atlas texture, which the fragment shader
## then stamps across world space at hashed positions (texture bombing).
##
## It replaces snow_layer.gd's build_tile_set, which baked one image per
## (depth band, shape variant) pair -- 100 images -- into a TileSet that
## EarthChunkManager then painted tile by tile. The art is the same KIND of
## thing; what changes is that the GPU now decides where it goes, so nothing
## here scales with how much ground is loaded.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")


## Where a level's sheet lives. The level number is part of the FILENAME --
## `snow_1.png`, `snow_5.png`, `snow_6.png` -- which is what makes the ladder
## extensible without touching code (see `levels`).
const SHEET_PATH_TEMPLATE := "res://assets/sprites/terrain/snow_%d.png"

## How far up to probe for sheets. Deliberately well past the highest level
## drawn so far (6), so `snow_7.png` would be picked up too; small enough that
## the probe is a handful of `FileAccess.file_exists` calls, not a directory
## walk. Not a claim that nine levels exist -- see `levels`, which returns
## only the ones that really do.
const LEVEL_SEARCH_MAX := 9

## Each sheet is a 5-column x 2-row grid of shape variants at that level --
## measured from the real PNGs, not assumed (see occupied_column_runs /
## occupied_row_runs, and test_every_sheet_is_a_five_by_two_grid_with_real_
## gutters, which re-measures it on every run so a re-exported sheet with a
## different layout fails loudly instead of silently cropping wrong).
const SHEET_COLUMNS := 5
const SHEET_ROWS := 2
const VARIANTS_PER_LEVEL := SHEET_COLUMNS * SHEET_ROWS

## How many pixels of art one stamp carries.
##
## A stamp spans SnowBombShader.STAMP_WORLD_SIZE world units, which at
## ArtResolution.DETAIL_MULTIPLIER art pixels per world unit is 48 art
## pixels; 64 leaves real headroom above that, so a stamp is never magnified
## past its own resolution at the game's camera zoom (the GPU samples this
## with bilinear filtering, and minifying slightly is free while magnifying
## visibly softens illustrated edges). The whole atlas at this size is
## 30 cells x 68^2 x RGBA8 = about 555 KB, so buying that headroom costs
## nothing worth measuring.
const STAMP_SIZE := 64

## A transparent gutter around every cell.
##
## The shader samples this atlas with the GPU's own bilinear filtering, which
## at a cell's outermost pixel row averages in whatever lies beyond it. With
## cells packed edge to edge that is the NEXT stamp, which draws as a faint
## ghost of the wrong shape along every stamp's border. Two pixels, not one:
## one is enough for the filter kernel itself, and the second absorbs the
## half-pixel rounding of the shader's own cell-to-UV arithmetic.
const STAMP_PADDING := 2
const CELL_SIZE := STAMP_SIZE + STAMP_PADDING * 2

## What counts as "there is art here" when measuring content extents. Low
## enough to catch the faint outer pixels of an illustrated puff's soft edge,
## high enough to ignore the near-zero ringing a Lanczos resize leaves just
## outside a hard edge.
const CONTENT_ALPHA_THRESHOLD := 0.05

## The sparsest level must let its ground through, and the fullest must not --
## the two ends of the ramp the shader builds between (see docs/concept/
## snow_cover.md's "Density, not steps").
##
## Measured through the real build_stamp_image path (content crop +
## aspect-preserving Lanczos fit), not from the raw sheets' own means: the
## crop discards each sheet's large empty margins, so a stamp's mean alpha is
## substantially HIGHER than its source cell's (level 1's raw sheet means
## 0.058; its cropped stamps mean 0.229). Measured across all ten variants of
## each level, not one cell, so a single unusually-full variant cannot carry a
## level past its threshold -- see
## test_the_sparsest_level_lets_the_ground_through_and_the_fullest_does_not,
## which checks every variant.
##
## The real measured ladder, all thirty stamps:
##   level 1: mean 0.2285, per-variant 0.1499 - 0.2903
##   level 5: mean 0.5171, per-variant 0.4390 - 0.5553
##   level 6: mean 0.8188, per-variant 0.8063 - 0.8246
## So the pins sit outside the extremes they guard with real margin (0.35 vs
## level 1's worst 0.2903; 0.75 vs level 6's worst 0.8063), and level 5 falls
## cleanly between them, which is what a middle rung should do. Re-derive both
## if the artist re-exports a sheet -- the test re-measures every variant on
## every run, so a changed sheet fails loudly rather than silently shifting
## what "a dusting" means.
const DUSTING_MAX_MEAN_ALPHA := 0.35
const FULL_COVER_MIN_MEAN_ALPHA := 0.75


## Which levels the artist has actually drawn, ascending.
##
## Read from the filesystem rather than hardcoded, so dropping in
## `snow_2.png` extends the ladder with no code change (see docs/concept/
## snow_cover.md's "The art" section -- levels 1, 5 and 6 exist today, and
## the gaps at 2/3/4 are real gaps in the art, not in the mechanism).
##
## Cached in a static var, the same "load once, reuse forever" convention
## snow_layer.gd's own _overlay_sheet_image and IllustratedTerrainSprite's
## _frame_cache use: the set of files on disk does not change mid-process.
static var _levels_cache: PackedInt32Array = PackedInt32Array()


func levels() -> PackedInt32Array:
	if _levels_cache.is_empty():
		var found := PackedInt32Array()
		for level in range(1, LEVEL_SEARCH_MAX + 1):
			var path := SHEET_PATH_TEMPLATE % level
			if ResourceLoader.exists(path) or FileAccess.file_exists(path):
				found.append(level)
		_levels_cache = found
	return _levels_cache


## One level's loaded sheet, shared across instances -- the pixels never
## change, and re-decoding a ~1MB PNG per caller would be pure waste.
static var _sheet_cache: Dictionary = {}


func sheet_image(level: int) -> Image:
	if not _sheet_cache.has(level):
		var image := SpriteSheetLoader.load_image(SHEET_PATH_TEMPLATE % level)
		if image != null and image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		_sheet_cache[level] = image
	return _sheet_cache[level]


## The runs of consecutive columns that hold ANY art at all, as [start, end]
## pairs. A sheet laid out as a clean grid of separated cells produces exactly
## one run per column of cells, with the empty gutters between them showing up
## as the gaps -- which is how the 5x2 layout above is measured rather than
## assumed, and how a re-exported sheet with a different layout gets caught.
func occupied_column_runs(image: Image) -> Array:
	var runs: Array = []
	var start := -1
	for x in image.get_width():
		var occupied := false
		for y in range(0, image.get_height(), 2):
			if image.get_pixel(x, y).a > CONTENT_ALPHA_THRESHOLD:
				occupied = true
				break
		if occupied and start < 0:
			start = x
		elif not occupied and start >= 0:
			runs.append(Vector2i(start, x - 1))
			start = -1
	if start >= 0:
		runs.append(Vector2i(start, image.get_width() - 1))
	return runs


## The same measurement across rows -- see occupied_column_runs.
func occupied_row_runs(image: Image) -> Array:
	var runs: Array = []
	var start := -1
	for y in image.get_height():
		var occupied := false
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).a > CONTENT_ALPHA_THRESHOLD:
				occupied = true
				break
		if occupied and start < 0:
			start = y
		elif not occupied and start >= 0:
			runs.append(Vector2i(start, y - 1))
			start = -1
	if start >= 0:
		runs.append(Vector2i(start, image.get_height() - 1))
	return runs


## The fraction of sampled pixels that are opaque AND nearly black -- a matte
## fringe, the artifact a sheet exported against a black background instead of
## real transparency would carry. Snow is white, so any such pixel is an
## export accident, and stamping it would draw a black halo around every puff.
func dark_opaque_fraction(image: Image) -> float:
	var dark := 0
	var sampled := 0
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			sampled += 1
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.9 and pixel.r + pixel.g + pixel.b < 0.25:
				dark += 1
	if sampled == 0:
		return 0.0
	return float(dark) / float(sampled)


## Which (column, row) of its sheet a variant index addresses -- row-major
## across the five columns, then the second row, the order the sheets read.
static func variant_cell(variant: int) -> Vector2i:
	var clamped := clampi(variant, 0, VARIANTS_PER_LEVEL - 1)
	return Vector2i(clamped % SHEET_COLUMNS, clamped / SHEET_COLUMNS)


## The even 5x2 partition of a sheet -- the cell a variant lives somewhere
## inside. Nearest-integer rounded so the cells partition the sheet exactly
## with no 1px gap or overlap (the sheet dimensions do not divide evenly).
func cell_rect(level: int, variant: int) -> Rect2i:
	var sheet := sheet_image(level)
	var cell := variant_cell(variant)
	var cell_width := float(sheet.get_width()) / float(SHEET_COLUMNS)
	var cell_height := float(sheet.get_height()) / float(SHEET_ROWS)
	var x0 := int(round(cell.x * cell_width))
	var x1 := int(round((cell.x + 1) * cell_width))
	var y0 := int(round(cell.y * cell_height))
	var y1 := int(round((cell.y + 1) * cell_height))
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


## The tight bounding box of the art INSIDE a variant's cell.
##
## Cropping the even cell rect directly would keep each sheet's large empty
## margins, so a stamp would be mostly transparent padding and the shader
## would have to stamp far more of them to cover any ground. Cropping to the
## content instead makes every stamp a full-bleed puff, which is what lets
## STAMP_WORLD_SIZE mean what it says.
func content_rect(level: int, variant: int) -> Rect2i:
	var sheet := sheet_image(level)
	var cell := cell_rect(level, variant)
	var min_x := cell.position.x + cell.size.x
	var max_x := cell.position.x - 1
	var min_y := cell.position.y + cell.size.y
	var max_y := cell.position.y - 1
	for y in range(cell.position.y, cell.position.y + cell.size.y):
		for x in range(cell.position.x, cell.position.x + cell.size.x):
			if sheet.get_pixel(x, y).a <= CONTENT_ALPHA_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return cell
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## One stamp: a variant's own art, cropped to its content and fitted into a
## STAMP_SIZE square.
##
## Fitted by the SMALLER of the two ratios and centred, never resized to the
## square outright: the content boxes are not square (level 1's first cell
## measures 197x216) and stretching them would squash every illustrated puff
## into a different shape than the artist drew. Pinned by
## test_a_stamp_preserves_its_shapes_aspect_ratio.
##
## Lanczos, not nearest-neighbour: this SHRINKS a ~200-300px crop to 64, the
## same direction TerrainRenderer._normalized_for_compositing and the old
## snow_layer.build_band_image already established Lanczos for in this
## codebase -- nearest-neighbour is right for UPSCALING small procedural art,
## but aliases fine illustrated detail into visible static when shrinking.
func build_stamp_image(level: int, variant: int) -> Image:
	var content := content_rect(level, variant)
	var cropped := sheet_image(level).get_region(content)
	if cropped.get_format() != Image.FORMAT_RGBA8:
		cropped.convert(Image.FORMAT_RGBA8)
	var scale: float = minf(
		float(STAMP_SIZE) / float(content.size.x), float(STAMP_SIZE) / float(content.size.y)
	)
	var fitted_width := clampi(int(round(content.size.x * scale)), 1, STAMP_SIZE)
	var fitted_height := clampi(int(round(content.size.y * scale)), 1, STAMP_SIZE)
	cropped.resize(fitted_width, fitted_height, Image.INTERPOLATE_LANCZOS)
	var stamp := Image.create(STAMP_SIZE, STAMP_SIZE, false, Image.FORMAT_RGBA8)
	stamp.blit_rect(
		cropped, Rect2i(0, 0, fitted_width, fitted_height),
		Vector2i((STAMP_SIZE - fitted_width) / 2, (STAMP_SIZE - fitted_height) / 2)
	)
	return stamp


## How much of a stamp is actually covered -- its mean alpha. The measurement
## the level ladder's own monotonicity is asserted on.
func stamp_mean_alpha(level: int, variant: int) -> float:
	return _mean_alpha(build_stamp_image(level, variant))


## One level's mean coverage across all ten of its variants, so the ladder is
## compared level to level rather than cherry-picked cell to cell.
func level_mean_alpha(level: int) -> float:
	var total := 0.0
	for variant in VARIANTS_PER_LEVEL:
		total += stamp_mean_alpha(level, variant)
	return total / float(VARIANTS_PER_LEVEL)


## The aspect ratio (width / height) of a variant's art as the artist drew it.
func source_content_aspect(level: int, variant: int) -> float:
	var content := content_rect(level, variant)
	return float(content.size.x) / float(content.size.y)


## The aspect ratio of the art as it ended up drawn inside its stamp -- which
## must match source_content_aspect, or the fit stretched it.
func stamp_content_aspect(level: int, variant: int) -> float:
	var stamp := build_stamp_image(level, variant)
	var min_x := STAMP_SIZE
	var max_x := -1
	var min_y := STAMP_SIZE
	var max_y := -1
	for y in STAMP_SIZE:
		for x in STAMP_SIZE:
			if stamp.get_pixel(x, y).a <= CONTENT_ALPHA_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return 1.0
	return float(max_x - min_x + 1) / float(max_y - min_y + 1)


## How differently two variants of one level draw -- mean absolute alpha
## difference, pixel for pixel. Near zero would mean two copies of one blob,
## which is what would make a field of stamps read as wallpaper.
func stamp_difference(level: int, first_variant: int, second_variant: int) -> float:
	var first := build_stamp_image(level, first_variant)
	var second := build_stamp_image(level, second_variant)
	var total := 0.0
	for y in STAMP_SIZE:
		for x in STAMP_SIZE:
			total += absf(first.get_pixel(x, y).a - second.get_pixel(x, y).a)
	return total / float(STAMP_SIZE * STAMP_SIZE)


## The packed atlas: variants ACROSS, levels DOWN, every cell surrounded by
## its transparent gutter (see STAMP_PADDING). The layout the shader's own
## cell arithmetic assumes -- see SnowBombShader's atlas_columns/atlas_rows.
func build_atlas_image() -> Image:
	var level_list := levels()
	var image := Image.create(
		VARIANTS_PER_LEVEL * CELL_SIZE, level_list.size() * CELL_SIZE,
		false, Image.FORMAT_RGBA8
	)
	for level_index in level_list.size():
		for variant in VARIANTS_PER_LEVEL:
			image.blit_rect(
				build_stamp_image(level_list[level_index], variant),
				Rect2i(0, 0, STAMP_SIZE, STAMP_SIZE),
				Vector2i(
					variant * CELL_SIZE + STAMP_PADDING,
					level_index * CELL_SIZE + STAMP_PADDING
				)
			)
	return image


## The texture the shader samples, built once for the whole process.
##
## Every instance shares it: the atlas is a pure function of art on disk, and
## rebuilding it repeats thirty crop-and-Lanczos-resize passes for an
## identical result. Deliberately WITHOUT mipmaps -- a minified mip level
## averages across a cell's gutter into its neighbour, which is the same
## bleed the gutter exists to prevent (see STAMP_PADDING).
static var _atlas_texture: ImageTexture = null


func atlas_texture() -> ImageTexture:
	if _atlas_texture == null:
		_atlas_texture = ImageTexture.create_from_image(build_atlas_image())
	return _atlas_texture


func _mean_alpha(image: Image) -> float:
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y).a
	return total / float(image.get_width() * image.get_height())
