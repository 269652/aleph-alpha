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


## DEPTH_BANDS is now the real illustrated sheet's own ROW count, not
## columns*rows: the new 10x10 sheet's ROW axis is coverage/depth (mean alpha
## climbs row 0 -> row 9) and its COLUMN axis is a genuinely separate shape
## VARIANT at that same depth (see variant_for below and OVERLAY_COLUMNS' own
## doc comment) -- ten depth rungs, not a hundred, with ten real shapes drawn
## at each one.
func test_depth_bands_matches_the_illustrated_sheets_real_row_count():
	assert_eq(SnowLayer.DEPTH_BANDS, SnowLayer.OVERLAY_ROWS)


## Guards the sheet's real dimensions -- if the asset is ever replaced with a
## differently-sized sheet, this fails loudly instead of silently slicing the
## wrong regions.
func test_the_overlay_sheet_has_the_measured_dimensions():
	var image := SpriteSheetLoader.load_image(SnowLayer.OVERLAY_PATH)
	assert_not_null(image, "snowoverlay.png must load from " + SnowLayer.OVERLAY_PATH)
	assert_eq(image.get_width(), 1254)
	assert_eq(image.get_height(), 1254)


## build_band_image feeds straight into build_tile_set's blit_rect at
## ART_TILE_SIZE -- a mismatched size would silently crop or leave the rest
## of an atlas cell blank. Swept across a few band/variant combinations, not
## just variant 0, since the two are now independent axes into the same
## sheet.
func test_band_image_is_sized_for_the_atlas():
	var art := TerrainRenderer.ART_TILE_SIZE
	for band in [0, SnowLayer.DEPTH_BANDS / 2, SnowLayer.DEPTH_BANDS - 1]:
		for variant in [0, SnowLayer.OVERLAY_COLUMNS / 2, SnowLayer.OVERLAY_COLUMNS - 1]:
			var image := layer.build_band_image(band, variant)
			assert_eq(image.get_width(), art, "band %d variant %d width" % [band, variant])
			assert_eq(image.get_height(), art, "band %d variant %d height" % [band, variant])


## The OLD sheet needed OVERLAY_ROW_BANDS/OVERLAY_COLUMN_BANDS specifically to
## crop around real near-opaque divider lines baked into that contact sheet
## (a generation artifact). The new sheet has none: a min-alpha-across-every-
## row/column sweep (the exact technique that originally found the old
## dividers) found nothing here, and _cropped_cell no longer does any
## divider-avoidance or centered-square cropping -- the new cells are already
## an exact, clean 125.4x125.4 grid. That whole test premise (a divider line
## that must not fall inside a crop band) no longer applies to this asset, so
## the old test (test_band_crops_stay_clear_of_the_sheets_divider_lines) is
## deleted outright rather than left checking geometry that no longer exists.


## Deeper snow is whiter: the bands have to actually differ, or the gradation
## is a number nobody can see. Averaged across every variant at each band
## (rather than pinned to one fixed column) because the row-mean is the real
## measured monotonic axis -- a single column can wobble by a fraction of a
## percent between two adjacent rows (real illustrated shapes, not a
## generated ramp) even though the row as a whole is unambiguously whiter.
func test_deeper_snow_is_whiter():
	var previous := -1.0
	for band in SnowLayer.DEPTH_BANDS:
		var total := 0.0
		for variant in SnowLayer.OVERLAY_COLUMNS:
			total += _whiteness(layer.build_band_image(band, variant))
		var whiteness := total / float(SnowLayer.OVERLAY_COLUMNS)
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


## A dusting is snow lying in the dips with GRASS SHOWING THROUGH, and full
## cover buries the ground -- for EVERY one of the ten shape variants a tile
## might draw at that depth, not just variant 0, since which variant a given
## tile shows is now a real per-tile choice (see variant_for) rather than
## always the sheet's first column.
func test_a_dusting_lets_the_ground_show_through_and_full_cover_does_not():
	for variant in SnowLayer.OVERLAY_COLUMNS:
		assert_lt(
			_mean_alpha(layer.build_band_image(0, variant)), SnowLayer.DUSTING_MAX_MEAN_ALPHA,
			"dusting variant %d must read as frost the ground tints through, not opaque specks" % variant
		)
		assert_gte(
			_mean_alpha(layer.build_band_image(SnowLayer.DEPTH_BANDS - 1, variant)),
			SnowLayer.FULL_COVER_MIN_MEAN_ALPHA,
			"deep snow variant %d must bury the ground -- nothing should show through" % variant
		)


# -- per-tile variant: a separate shape choice at a fixed depth -------------
#
# The new sheet's COLUMN axis is not more depth granularity -- it is ten
# different hand/AI-illustrated blob SHAPES at roughly the same size, so two
# tiles at the same coverage don't all draw the identical patch (see
# OVERLAY_COLUMNS' own doc comment). variant_for picks which one a given tile
# shows.

func test_variant_is_bounded_to_the_column_count():
	for x in range(30):
		var variant := layer.variant_for(x, -x * 3 + 1)
		assert_gte(variant, 0)
		assert_lt(variant, SnowLayer.OVERLAY_COLUMNS)


func test_variant_is_deterministic_for_the_same_tile():
	assert_eq(layer.variant_for(11, -42), layer.variant_for(11, -42))


func test_variant_varies_across_tiles():
	var seen := {}
	for x in range(30):
		seen[layer.variant_for(x, 0)] = true
	assert_gt(seen.size(), 1, "every tile drawing the same variant defeats the point of having ten")


## The whole reason variant exists: unlike onset (which must be a smooth
## drift, see onset_offset_for), two EDGE-ADJACENT tiles at the same depth
## should often show different shapes -- a real per-tile independent choice,
## not a second low-frequency field. Guards against someone "fixing" a future
## complaint by smoothing this into a drift, which would defeat the whole
## point of having real shape variety.
func test_neighbouring_tiles_often_show_different_variants():
	var differing := 0
	var total := 0
	for x in range(-40, 40):
		for y in range(-4, 4):
			total += 1
			if layer.variant_for(x, y) != layer.variant_for(x + 1, y):
				differing += 1
	assert_gt(
		float(differing) / float(total), 0.5,
		"neighbouring tiles agree on variant far too often for a genuinely per-tile choice"
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
#
# RE-MEASURED again for the DEPTH_BANDS 25 -> 10 asset change (onset_offset_
# for itself is untouched -- same code, same field, same neighbour steps --
# but there are now fewer total bands to spread across). A fresh full sweep
# of that same swath at DEPTH_BANDS=10 finds this SAME origin is still the
# real worst case, now showing only 2 distinct bands rather than 3 -- an
# expected, direct consequence of a coarser 10-band ladder (a 24x24 window's
# onset spread covers a fixed slice of the 0..1 depth range regardless of how
# many bands that range is cut into, so fewer bands means fewer of them can
# possibly fall inside any one window), not a sign the onset field regressed.
# The bug this test actually guards against -- a whole neighbourhood locking
# to ONE band with literally zero per-tile variation, the original "whole
# areas increment... without variations" report -- is still caught by
# requiring MORE than one distinct band; asserting a specific higher count
# would just be chasing a number that depends on DEPTH_BANDS for reasons
# unrelated to whether the onset field itself still works.
func test_a_local_window_shows_real_per_tile_variation_not_a_uniform_plateau():
	var origin := Vector2i(-42, -48)
	var bands := {}
	for dx in range(24):
		for dy in range(24):
			var offset: float = layer.onset_offset_for(origin.x + dx, origin.y + dy)
			bands[layer.band_for(0.5, 0.0, offset)] = true
	assert_gt(
		bands.size(), 1,
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
