extends GutTest

## Snow as a per-tile overlay, so footprints can be carved out of it (see
## docs/concept/weather.md).
##
## Snow started as a tint on the whole ground layer, which cannot express "this
## tile is trodden and that one is not" -- the tint is one number for the world.
## Making it a layer of tiles is what lets a trail through a field exist at all.

const SnowLayer = preload("res://src/rendering/snow_layer.gd")
const SnowTrail = preload("res://src/world/snow_trail.gd")

var layer: SnowLayer


func before_each():
	layer = SnowLayer.new()


# -- the art -----------------------------------------------------------------

## One tile per depth band, so ground goes from bare through a dusting to full
## cover rather than snapping between two states.
func test_there_is_a_tile_for_every_depth_band():
	var tile_set := layer.build_tile_set()
	assert_not_null(tile_set)
	assert_gte(SnowLayer.DEPTH_BANDS, 3, "bare, a dusting and cover at the very least")


## Deeper snow is whiter: the bands have to actually differ, or the gradation
## is a number nobody can see.
func test_deeper_snow_is_whiter():
	var previous := -1.0
	for band in SnowLayer.DEPTH_BANDS:
		var whiteness := _whiteness(layer.build_band_image(band))
		assert_gt(whiteness, previous, "band %d is no whiter than the one below" % band)
		previous = whiteness


## Snow is not a flat white rectangle -- it has grain, or a covered field reads
## as a hole in the world.
func test_snow_has_some_texture():
	var image := layer.build_band_image(SnowLayer.DEPTH_BANDS - 1)
	var shades := {}
	for y in image.get_height():
		for x in image.get_width():
			shades[snappedf(image.get_pixel(x, y).v, 0.02)] = true
	assert_gt(shades.size(), 1, "flat white is not snow")


# -- which band a tile gets --------------------------------------------------

func test_bare_ground_gets_no_snow():
	assert_eq(layer.band_for(0.0, 0.0), -1, "no snow means no tile at all")


func test_deep_snow_gets_the_deepest_band():
	assert_eq(layer.band_for(1.0, 0.0), SnowLayer.DEPTH_BANDS - 1)


func test_more_snow_never_gets_a_shallower_band():
	var previous := -2
	for step in 20:
		var band := layer.band_for(float(step) / 19.0, 0.0)
		assert_gte(band, previous)
		previous = band


# -- footprints carve it out -------------------------------------------------

## The whole point: a trodden tile shows less snow than the field around it.
func test_a_trodden_tile_shows_less_snow():
	var untrodden := layer.band_for(1.0, 0.0)
	var trodden := layer.band_for(1.0, 1.0)
	assert_lt(trodden, untrodden, "a footprint should displace the snow in it")


## Walking through deep snow does not clear it to bare earth -- it packs it
## down. A trail should read as tracks, not as a dug trench.
func test_a_single_pass_does_not_clear_deep_snow():
	assert_gte(
		layer.band_for(1.0, SnowTrail.TREAD_PER_STEP), 0,
		"one step through deep snow should pack it, not clear it"
	)


## In a thin dusting, though, a footprint does show the ground.
func test_a_footprint_in_a_dusting_shows_the_ground():
	assert_eq(layer.band_for(0.25, 1.0), -1, "a boot through a dusting reaches the ground")


func test_treading_never_deepens_the_snow():
	for step in 10:
		var tread := float(step) / 9.0
		assert_lte(layer.band_for(0.8, tread), layer.band_for(0.8, 0.0))


# -- per-tile spread (see docs/concept/weather.md's "It fills in tile by
# tile, not the whole field at once") ----------------------------------------
#
# One lying-snow DEPTH still drives the whole snowfall, but each tile warps
# that depth by its own deterministic amount before banding it (`tile_warp`),
# so different tiles cross into a deeper band at different points along the
# SAME snowfall -- reported: "snow still covers a percentage of a whole chunk
# instantly instead of gradually filling individual tiles".

## The old 2-arg call and the default warp=1.0 must behave IDENTICALLY to
## before this change -- every test above calls band_for with exactly two
## arguments and must keep passing unmodified.
func test_default_warp_reproduces_the_original_banding_exactly():
	for step in 20:
		var depth := float(step) / 19.0
		assert_eq(layer.band_for(depth, 0.0), layer.band_for(depth, 0.0, 1.0))


## The whole point: at the SAME mid-snowfall depth, two tiles with different
## warps must be able to land in different bands -- otherwise nothing spreads.
func test_different_warps_can_land_in_different_bands_at_the_same_depth():
	var bands := {}
	for warp_step in 10:
		var warp: float = lerp(SnowLayer.WARP_MIN, SnowLayer.WARP_MAX, float(warp_step) / 9.0)
		bands[layer.band_for(0.5, 0.0, warp)] = true
	assert_gt(bands.size(), 1, "a mid-snowfall depth should show more than one band across different warps")


## Both ends of a snowfall still agree regardless of warp: a warp can only
## change WHEN a tile crosses into a band, never whether the field starts
## bare or ends fully covered together.
func test_every_warp_still_starts_bare_and_ends_fully_covered():
	for warp_step in 10:
		var warp: float = lerp(SnowLayer.WARP_MIN, SnowLayer.WARP_MAX, float(warp_step) / 9.0)
		assert_eq(layer.band_for(0.0, 0.0, warp), -1, "bare ground has no snow regardless of warp")
		assert_eq(
			layer.band_for(1.0, 0.0, warp), SnowLayer.DEPTH_BANDS - 1,
			"a complete snowfall reaches full cover regardless of warp"
		)


## Warping must never turn "more real snow" into "a shallower band" for one
## FIXED tile -- the same monotonicity test_more_snow_never_gets_a_shallower_band
## already pins for warp=1.0, extended to every warp a tile might carry.
func test_more_snow_never_gets_a_shallower_band_at_any_warp():
	for warp_step in 5:
		var warp: float = lerp(SnowLayer.WARP_MIN, SnowLayer.WARP_MAX, float(warp_step) / 4.0)
		var previous := -2
		for step in 20:
			var band := layer.band_for(float(step) / 19.0, 0.0, warp)
			assert_gte(band, previous, "warp %f" % warp)
			previous = band


# -- which warp a tile gets ----------------------------------------------------

func test_tile_warp_is_deterministic():
	var tile := Vector2i(17, -42)
	assert_eq(SnowLayer.tile_warp(tile), SnowLayer.tile_warp(tile))


func test_tile_warp_stays_within_its_declared_range():
	for x in range(0, 40, 3):
		for y in range(0, 40, 3):
			var warp := SnowLayer.tile_warp(Vector2i(x, y))
			assert_between(warp, SnowLayer.WARP_MIN, SnowLayer.WARP_MAX, "tile (%d, %d)" % [x, y])


## Neighbouring tiles must not all carry the identical warp, or the "spread"
## degenerates back into one field-wide value -- the same failure this whole
## change exists to fix.
func test_tile_warp_varies_across_a_field_of_tiles():
	var warps := {}
	for x in range(0, 24):
		for y in range(0, 24):
			warps[snappedf(SnowLayer.tile_warp(Vector2i(x, y)), 0.01)] = true
	assert_gt(warps.size(), 3, "a 24x24 field of tiles should carry real warp variety")


## Real snow drifts in coherent PATCHES (wind-sheltered hollows, tree shade),
## not pixel-to-pixel static -- immediately adjacent tiles should usually
## carry a similar warp, not a wildly different one every step.
func test_tile_warp_is_spatially_coherent_not_scattered():
	var large_jumps := 0
	var total := 0
	for x in range(0, 20):
		for y in range(0, 20):
			var here: float = SnowLayer.tile_warp(Vector2i(x, y))
			var right: float = SnowLayer.tile_warp(Vector2i(x + 1, y))
			total += 1
			if absf(here - right) > (SnowLayer.WARP_MAX - SnowLayer.WARP_MIN) * 0.5:
				large_jumps += 1
	assert_lt(
		float(large_jumps) / float(total), 0.2,
		"most adjacent tiles should carry a similar warp -- patches, not static"
	)


func _whiteness(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			total += pixel.v * pixel.a
			count += 1
	return total / float(maxi(count, 1))
