extends GutTest

## Snow as a per-tile overlay, so footprints can be carved out of it (see
## docs/concept/weather.md).
##
## Snow started as a tint on the whole ground layer, which cannot express "this
## tile is trodden and that one is not" -- the tint is one number for the world.
## Making it a layer of tiles is what lets a trail through a field exist at all.

const SnowLayer = preload("res://src/rendering/snow_layer.gd")
const SnowTrail = preload("res://src/world/snow_trail.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

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


## DEPTH_BANDS is now the real illustrated sheet's own frame count (a 5x5
## contact sheet, see snowoverlay.png), not a hand-picked number -- pinned so
## nobody quietly drops back to a coarser hand-picked count without updating
## this test (and OVERLAY_BAND_CELLS, which has one entry per band).
func test_depth_bands_matches_the_illustrated_sheets_real_frame_count():
	assert_eq(SnowLayer.DEPTH_BANDS, SnowLayer.OVERLAY_COLUMNS * SnowLayer.OVERLAY_ROWS)
	assert_eq(SnowLayer.OVERLAY_BAND_CELLS.size(), SnowLayer.DEPTH_BANDS)


## Guards OVERLAY_ROW_BANDS/OVERLAY_COLUMN_BANDS, which are pixel positions
## measured directly against the real PNG (see their own doc comments) --
## if the asset is ever replaced with a differently-sized sheet, this fails
## loudly instead of silently slicing the wrong regions.
func test_the_overlay_sheet_has_the_measured_dimensions():
	var image := SpriteSheetLoader.load_image(SnowLayer.OVERLAY_PATH)
	assert_not_null(image, "snowoverlay.png must load from " + SnowLayer.OVERLAY_PATH)
	assert_eq(image.get_width(), 1448)
	assert_eq(image.get_height(), 1086)


## build_band_image feeds straight into build_tile_set's blit_rect at
## ART_TILE_SIZE -- a mismatched size would silently crop or leave the rest
## of an atlas cell blank.
func test_band_image_is_sized_for_the_atlas():
	var art := TerrainRenderer.ART_TILE_SIZE
	for band in [0, SnowLayer.DEPTH_BANDS / 2, SnowLayer.DEPTH_BANDS - 1]:
		var image := layer.build_band_image(band)
		assert_eq(image.get_width(), art)
		assert_eq(image.get_height(), art)


## OVERLAY_ROW_BANDS/OVERLAY_COLUMN_BANDS exist specifically to crop AROUND
## the sheet's own near-opaque divider lines (see their own doc comments for
## the measured divider centers) -- a regression here (an asset re-export
## that shifts the grid, or a future edit that widens a band back toward its
## neighbour) would bake a stray light border line into a real in-game tile.
## Guards the geometry directly rather than inspecting resized pixel alpha
## (which would also pick up the Lanczos resize's own blending, and would
## have to special-case cells that are legitimately near-opaque at full
## coverage): every measured divider center must fall in the GAP between
## two consecutive bands, never inside one.
func test_band_crops_stay_clear_of_the_sheets_divider_lines():
	var row_dividers := [208.5, 416.5, 624.0, 831.0]
	var column_dividers := [291.0, 579.0, 867.5, 1156.0]
	for divider in row_dividers:
		for band in SnowLayer.OVERLAY_ROW_BANDS:
			assert_true(
				divider < float(band.x) or divider >= float(band.y),
				"row divider at %.1f must not fall inside band %s" % [divider, band]
			)
	for divider in column_dividers:
		for band in SnowLayer.OVERLAY_COLUMN_BANDS:
			assert_true(
				divider < float(band.x) or divider >= float(band.y),
				"column divider at %.1f must not fall inside band %s" % [divider, band]
			)


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


## A dusting is snow lying in the dips with GRASS SHOWING THROUGH. The code
## claimed that in a comment and did the opposite: every covered pixel was
## written fully opaque, so a 45%-coverage shallow band was 45% of the tile
## switched hard to near-white and 55% punched out -- a 50/50 dither of
## near-white at the finest grain the atlas can express, reported as "~50%
## pure-white 1px noise, reads as texture corruption". The ground can only
## show through if the layer lets it composite through, because SnowLayer
## bakes ONE tile set for every biome and so has no ground colour to blend
## with itself.
func test_a_dusting_lets_the_ground_show_through_and_full_cover_does_not():
	assert_lt(
		_mean_alpha(layer.build_band_image(0)), SnowLayer.DUSTING_MAX_MEAN_ALPHA,
		"a dusting must read as frost the ground tints through, not as opaque white specks"
	)
	assert_gte(
		_mean_alpha(layer.build_band_image(SnowLayer.DEPTH_BANDS - 1)),
		SnowLayer.FULL_COVER_MIN_MEAN_ALPHA,
		"deep snow buries the ground -- nothing shows through the top band"
	)


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


# -- per-tile onset: a field fills in, it does not flip all at once ----------
#
# Every tile used to read the SAME global depth, so a whole chunk snapped to
# whatever band the clock said the instant it was evaluated (reported: "snow
# covers a whole chunk instantly instead of spreading progressively"). Each
# tile now gets its own seeded lead/lag on the global depth -- the same
# per-cell-seeded-jitter idea TallGrass/FlowerPatch already use to avoid a
# uniform field reading as synchronized (see PixelNoise's own doc comment:
# this project has hit that "same value everywhere" clustering bug five
# times already, just applied to TIME here instead of position).

func test_onset_offset_varies_by_tile():
	var seen := {}
	for x in range(20):
		seen[layer.onset_offset_for(x, 0)] = true
	assert_gt(seen.size(), 1, "every tile rolling the same onset is the bug this exists to fix")


func test_onset_offset_is_bounded_by_the_variance_constant():
	for x in range(20):
		var offset: float = layer.onset_offset_for(x, x * 7 + 3)
		assert_gte(offset, -SnowLayer.ONSET_VARIANCE)
		assert_lte(offset, SnowLayer.ONSET_VARIANCE)


func test_onset_offset_is_deterministic_for_the_same_tile():
	assert_eq(layer.onset_offset_for(42, -17), layer.onset_offset_for(42, -17))


## A lagging tile stays bare a little longer than the field's overall
## reading -- this is what makes some tiles hold out while others catch on.
func test_a_lagging_onset_delays_a_tiles_own_snow():
	assert_eq(layer.band_for(0.05, 0.0, -SnowLayer.ONSET_VARIANCE), -1)


## A leading tile picks up snow before the plain global depth alone would put
## it there -- this is what makes some tiles go first.
func test_a_leading_onset_shows_snow_before_the_bare_global_reading_would():
	assert_gte(layer.band_for(0.05, 0.0, SnowLayer.ONSET_VARIANCE), 0)


## Onset is a bounded lead/lag, not a teleport: it cannot invent snow on a
## genuinely bare field, nor hide snow once the field is genuinely full.
func test_onset_cannot_show_snow_on_a_genuinely_bare_field():
	assert_eq(layer.band_for(0.0, 0.0, SnowLayer.ONSET_VARIANCE), -1)


func test_onset_cannot_hide_snow_once_the_field_is_fully_covered():
	assert_eq(layer.band_for(1.0, 0.0, -SnowLayer.ONSET_VARIANCE), SnowLayer.DEPTH_BANDS - 1)


## The default (no onset passed) must keep behaving exactly as before -- every
## existing band_for(depth, tread) call site elsewhere must not change.
func test_band_for_without_an_onset_argument_is_unchanged():
	assert_eq(layer.band_for(0.6, 0.2), layer.band_for(0.6, 0.2, 0.0))


# -- the onset field is a DRIFT, not per-tile static -------------------------
#
# The onset offset was rolled per tile with PixelNoise.range_value -- white
# noise, so the offset of tile (x, y) said nothing whatever about (x + 1, y).
# Two touching tiles could land 2 * ONSET_VARIANCE apart, which was MORE than
# one whole depth band at the DEPTH_BANDS=4 this was fixed under (1.0 / 4 =
# 0.25), and band_for speaks for a whole tile. The field therefore rendered
# as a checkerboard of bare / dusted / covered SQUARES with a razor edge on
# the tile grid -- reported as texture corruption rather than as snow.
#
# Snow drifts and shelters in patches many metres across (a hollow, a lee
# side, a tree line's shade), so the field deciding which ground catches
# first is low-frequency by construction: neighbours nearly identical, only
# tens of tiles apart fully different.


## Touching tiles must almost agree -- this is the whole fix.
func test_neighbouring_tiles_have_nearly_the_same_onset():
	var worst := 0.0
	var worst_at := Vector2i.ZERO
	for x in range(-60, 60):
		for y in range(-6, 6):
			var here: float = layer.onset_offset_for(x, y)
			var across := absf(here - layer.onset_offset_for(x + 1, y))
			var down := absf(here - layer.onset_offset_for(x, y + 1))
			if maxf(across, down) > worst:
				worst = maxf(across, down)
				worst_at = Vector2i(x, y)
	assert_lte(
		worst, SnowLayer.MAX_NEIGHBOUR_ONSET_STEP,
		(
			"tile %s and a neighbour are %.4f apart (one depth band is %.4f) -- "
			+ "onset must be a drift field, not per-tile static"
		) % [worst_at, worst, 1.0 / float(SnowLayer.DEPTH_BANDS)]
	)


## GUARD, not a red driver: it passes before and after. It exists so nobody
## "fixes" the test above by flattening the field to a constant -- a smooth
## onset that never varies puts the whole chunk back on one shared threshold,
## which is the bug the onset offset was introduced to fix in the first place.
func test_the_drift_field_still_covers_the_ground_unevenly():
	var lowest := INF
	var highest := -INF
	for x in range(-200, 200):
		var offset: float = layer.onset_offset_for(x, 0)
		lowest = minf(lowest, offset)
		highest = maxf(highest, offset)
	assert_gt(
		highest - lowest, SnowLayer.ONSET_VARIANCE,
		"the drift has to span real ground, or every tile catches snow together again"
	)


# -- the onset field needs FINE grain too, not just a broad drift -----------
#
# Reported live, after the 4-to-25-illustrated-band change landed: "it's not
# using accumulation per tile and sth like perlin noise or so instead whole
# areas increment to next sprite without variations" -- large, visually
# uniform AREAS were stepping to the next illustrated band all at once. This
# is a DIFFERENT bug from the checkerboard above (that was neighbours
# differing TOO MUCH); this is close to the opposite: a single ONSET_DRIFT_
# TILES=12-tile-period smooth field has near-zero local slope across most of
# any one on-screen view, so a realistic ~20-30 tile window sees only a
# couple of distinct bands -- a plateau, not texture.
#
# Measured directly, not assumed: sweeping every 24x24 window across a real
# 400x120-tile swath of the OLD single-broad-layer field, the worst case
## (global tile origin (-42, -48), at a mid snowfall depth of 0.5) contains
# only 3 distinct depth bands -- confirmed the worst in the whole swept area,
# not a cherry-picked spot.
func test_a_local_window_shows_real_per_tile_variation_not_a_uniform_plateau():
	var origin := Vector2i(-42, -48)
	var bands := {}
	for dx in range(24):
		for dy in range(24):
			var offset: float = layer.onset_offset_for(origin.x + dx, origin.y + dy)
			bands[layer.band_for(0.5, 0.0, offset)] = true
	assert_gt(
		bands.size(), 3,
		(
			"a realistic 24x24 local view at %s shows only %d distinct bands -- "
			+ "a whole neighbourhood is stepping together instead of showing per-tile texture"
		) % [origin, bands.size()]
	)


func _mean_alpha(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y).a
			count += 1
	return total / float(maxi(count, 1))


func _whiteness(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			total += pixel.v * pixel.a
			count += 1
	return total / float(maxi(count, 1))
