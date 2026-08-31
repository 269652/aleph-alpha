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
##
## 1536x1024, NOT the previous 1254x1254: the illustrated sheet was replaced
## again (a genuinely different, non-square grid -- 153.6 wide x 102.4 tall
## cells, not the old 125.4x125.4 square ones), confirmed directly by loading
## the real committed asset. This was found RED against the stale 1254
## pinning while investigating the slicer-artefact bug -- see
## _cropped_cell's and build_band_image's own doc comments for why the
## shorter, non-square cells are directly relevant to that bug (a roughly
## circular "puff" shape presses across a 102px-tall row boundary at
## substantial alpha long before it presses across a 154px-wide column one).
func test_the_overlay_sheet_has_the_measured_dimensions():
	var image := SpriteSheetLoader.load_image(SnowLayer.OVERLAY_PATH)
	assert_not_null(image, "snowoverlay.png must load from " + SnowLayer.OVERLAY_PATH)
	assert_eq(image.get_width(), 1536)
	assert_eq(image.get_height(), 1024)


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


# -- a continuous base tint beneath the puff, so tiles meet edge to edge ----
#
# Real, user-visible complaint with a screenshot: a field of piled snow reads
# as a GRID of separate white blobs, not a continuous blanket -- every tile's
# own illustrated puff carries real, deliberate transparent padding within its
# own cell (see OVERLAY_COLUMNS' own doc comment), so two neighbouring tiles'
# puffs never actually touch. Every fix so far (variant selection, the bleed
# removal, the flip transform) operates entirely WITHIN one puff's own crop
# and cannot paint anything in the gap BETWEEN two tiles, because nothing is
# painted there at all.
#
# The fix is a second, flat tint composited BENEATH the existing puff, baked
# directly into build_band_image's own output (see base_alpha_for_band's own
# doc comment for why this reuses the existing (band, variant) atlas rather
# than adding a new layer or a finer discretisation).
#
# `band`, not the raw continuous (depth + onset_offset) value, drives the
# tint's own alpha -- investigated, not assumed: the finite (band, variant)
# atlas `build_tile_set` bakes ONCE and reuses for every tile of that band, so
# a tint that needed a genuinely unique value per exact tile POSITION could
# not be expressed by it at all (that would need either an unbounded number
# of baked combinations or a shader-driven layer whose actual pixels this
# project's own house convention already can't assert in a headless GUT test
# -- see test_ground_tint.gd's own header comment, "Contract tests only -- the
# visual result can't be asserted headless"). Reusing `band` costs nothing
# extra AND is provably safe: `MAX_NEIGHBOUR_ONSET_STEP` (0.07) already sits
# under one band's own width (1.0 / DEPTH_BANDS = 0.1), so two edge-adjacent
# tiles' bands can never differ by more than exactly one
# (test_worst_realistic_neighbour_band_difference_is_at_most_one confirms
# this by direct sweep, not just arithmetic) -- the "coarser gridline" risk a
# naive re-band-quantisation could reintroduce is bounded to one curve step,
# which base_alpha_for_band's own shallow slope plus edge compression (see
# `_base_edge_alpha_for_band`) keeps small in absolute terms.


## Band 0 is the sheet's own dusting rung (`DUSTING_MAX_MEAN_ALPHA` is pinned
## against exactly this band's real measured range -- see that constant's own
## doc comment) -- real gaps are still allowed there by design (a dusting is
## snow lying in the dips, not a blanket), so the base tint must leave it
## completely untouched rather than paint a first, thin coverage over it.
func test_base_alpha_is_absent_at_the_dusting_band():
	assert_eq(layer.base_alpha_for_band(0), 0.0)


## From the first band beyond dusting up, the tint has to actually climb with
## depth -- a flat value at every band would still close the gap but would
## read as a single uniform wash rather than tracking real coverage.
func test_base_alpha_increases_monotonically_from_band_1_up():
	var previous := 0.0
	for band in range(1, SnowLayer.DEPTH_BANDS):
		var alpha := layer.base_alpha_for_band(band)
		assert_gt(alpha, previous, "band %d's base alpha is no higher than the one below" % band)
		previous = alpha


## Pins the two ends of the curve so a future edit cannot silently drift it
## far enough to wash out the puff (see the contrast tests below) or too
## faint to close a gap at all.
func test_base_alpha_curve_endpoints_are_pinned():
	assert_eq(layer.base_alpha_for_band(1), SnowLayer.BASE_TINT_MIN_ALPHA)
	assert_eq(layer.base_alpha_for_band(SnowLayer.DEPTH_BANDS - 1), SnowLayer.BASE_TINT_MAX_ALPHA)


## The provable bound base_alpha_for_band's own doc comment leans on: swept
## directly (not just derived from the arithmetic) across a real range of
## depths and coordinates, using the exact same band_for/onset_offset_for a
## painted tile actually goes through.
func test_worst_realistic_neighbour_band_difference_is_at_most_one():
	assert_lt(
		SnowLayer.MAX_NEIGHBOUR_ONSET_STEP, 1.0 / float(SnowLayer.DEPTH_BANDS),
		"the onset step no longer sits under one band's width -- the base tint's band-driven design assumes it does"
	)
	var worst := 0
	for depth_step in range(1, 20):
		var depth := float(depth_step) / 20.0
		for x in range(-60, 60):
			for y in range(-6, 6):
				var here := layer.band_for(depth, 0.0, layer.onset_offset_for(x, y))
				var across := layer.band_for(depth, 0.0, layer.onset_offset_for(x + 1, y))
				var down := layer.band_for(depth, 0.0, layer.onset_offset_for(x, y + 1))
				worst = maxi(worst, maxi(absi(here - across), absi(here - down)))
	assert_lte(worst, 1, "two edge-adjacent tiles' bands differed by %d, not at most 1" % worst)


## The actual gap-closing claim, at the single-tile level: from band 1 up,
## EVERY pixel of a built tile -- edges included -- must carry some real
## alpha, for every shape variant. A tile that individually reaches full
## coverage on all four of its own edges cannot leave a fully-transparent
## seam against ANY neighbour, whatever band that neighbour happens to be in.
func test_built_tile_has_no_fully_transparent_pixel_from_band_1_up():
	for band in range(1, SnowLayer.DEPTH_BANDS):
		for variant in SnowLayer.OVERLAY_COLUMNS:
			var image := layer.build_band_image(band, variant)
			var worst_alpha := 1.0
			for y in image.get_height():
				for x in image.get_width():
					worst_alpha = minf(worst_alpha, image.get_pixel(x, y).a)
			assert_gt(
				worst_alpha, 0.0,
				"band %d variant %d has a fully-transparent pixel -- the base tint did not reach every edge" % [band, variant]
			)


## Regression guard the other direction: band 0 must render byte-identical to
## the base-tint-free pipeline, so a dusting still shows the real gaps it
## always has (see this section's own header comment).
func test_dusting_band_still_shows_real_transparent_gaps():
	for variant in SnowLayer.OVERLAY_COLUMNS:
		var image := layer.build_band_image(0, variant)
		var puff_only := layer._build_puff_image(0, variant)
		for y in image.get_height():
			for x in image.get_width():
				assert_eq(
					image.get_pixel(x, y), puff_only.get_pixel(x, y),
					"band 0 variant %d pixel (%d,%d) changed -- the base tint must not touch the dusting band" % [variant, x, y]
				)


## `_base_edge_alpha_for_band` exists specifically so a real curve step
## between two adjacent bands reads as a softer gradient at the shared tile
## edge than it does tile-interior -- confirmed here as an actual measured
## reduction, not merely a differently-shaped formula.
func test_base_edge_alpha_softens_the_interior_step():
	for band in range(1, SnowLayer.DEPTH_BANDS - 1):
		var interior_step := absf(layer.base_alpha_for_band(band + 1) - layer.base_alpha_for_band(band))
		var edge_step := absf(layer._base_edge_alpha_for_band(band + 1) - layer._base_edge_alpha_for_band(band))
		assert_lt(
			edge_step, interior_step,
			"band %d->%d: edge step (%.4f) is not softer than the interior step (%.4f)" % [band, band + 1, edge_step, interior_step]
		)


## The real, end-to-end claim: build a small strip of ADJACENT real tiles
## (real global coordinates, real onset/band/variant/transform, the same
## pipeline EarthChunkManager._paint_snow_tile drives) at a realistic partial
## snowfall, assemble them side by side the way they'd actually render, and
## confirm there is no fully-transparent column at any shared border once
## both sides of it are beyond the dusting band -- the actual "seamless
## piling" claim, measured rather than eyeballed.
func test_adjacent_real_tiles_show_no_transparent_seam_at_their_shared_border():
	var art := TerrainRenderer.ART_TILE_SIZE
	var depth := 0.6
	var origin_y := 100
	var checked_a_real_seam := false
	for origin_x in range(-40, 40):
		var left_band := layer.band_for(depth, 0.0, layer.onset_offset_for(origin_x, origin_y))
		var right_band := layer.band_for(depth, 0.0, layer.onset_offset_for(origin_x + 1, origin_y))
		if left_band < 1 or right_band < 1:
			continue  # Dusting (or bare) legitimately still shows gaps -- not this test's claim.
		checked_a_real_seam = true
		var left := layer.build_band_image(left_band, layer.variant_for(origin_x, origin_y))
		var right := layer.build_band_image(right_band, layer.variant_for(origin_x + 1, origin_y))
		for y in art:
			var seam_alpha := left.get_pixel(art - 1, y).a + right.get_pixel(0, y).a
			assert_gt(
				seam_alpha, 0.0,
				"tiles at x=%d/%d: both sides of the shared border are fully transparent at row %d" % [origin_x, origin_x + 1, y]
			)
	assert_true(checked_a_real_seam, "precondition: never found a real adjacent pair both beyond the dusting band to check")


## Item 3's own concern: compositing a base UNDER the puff must not wash the
## puff's own texture into a flat, feature-less field. Measured as the
## STANDARD DEVIATION of alpha across the tile, not raw min-max range: range
## is the wrong metric here on purpose, because raising the minimum alpha
## above 0 (closing a previously-fully-transparent gap) is this whole
## feature's own INTENDED effect, not a sign of washing out -- a metric that
## penalises exactly that would fail by design, not by a real regression
## (confirmed directly: an earlier version of this test used range and failed
## at bands 5 and 9 purely from filling real gaps, not from any loss of
## texture). Stddev instead captures whether the puff's own lumpy variation
## survives, independent of where the floor sits.
##
## 0.6 is a real, measured floor, not a guess: swept directly across bands
## 1/5/9 (variant 0) through this exact pipeline, the composite/puff-only
## stddev ratio measures 0.889/0.799/0.720 respectively -- 0.6 sits with real
## margin under the worst of those (0.720) while still catching a tint strong
## enough to flatten the puff toward a uniform wash.
func test_puff_detail_remains_distinguishable_over_the_base_tint():
	for band in [1, SnowLayer.DEPTH_BANDS / 2, SnowLayer.DEPTH_BANDS - 1]:
		var composite := layer.build_band_image(band, 0)
		var puff_only := layer._build_puff_image(band, 0)
		var composite_stddev := _alpha_stddev(composite)
		var puff_stddev := _alpha_stddev(puff_only)
		assert_gt(
			composite_stddev, puff_stddev * 0.6,
			"band %d: compositing the base tint shrank the puff's own alpha stddev from %.3f to %.3f -- texture is washing out" % [band, puff_stddev, composite_stddev]
		)


func _alpha_stddev(image: Image) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var n := width * height
	var sum := 0.0
	for y in height:
		for x in width:
			sum += image.get_pixel(x, y).a
	var mean := sum / float(n)
	var squared_diff := 0.0
	for y in height:
		for x in width:
			var d: float = image.get_pixel(x, y).a - mean
			squared_diff += d * d
	return sqrt(squared_diff / float(n))


# -- the slicer must not reproduce a neighbour's bleed ----------------------
#
# `_cropped_cell` partitions `snowoverlay.png` into an exact, gap-free 10x10
# grid -- the partition MATH is not the bug (confirmed: cell boundaries are
# round()-based and cover the sheet exactly with no 1px gap or overlap
# anywhere). The bug is that the ILLUSTRATED CONTENT is not perfectly confined
# to its own nominal cell: a shape's soft edge extends past its own boundary
# at near-invisible alpha (measured: real RGB persisting at alpha as low as
# 0.004-0.02 at a real boundary, e.g. row 6's column-2/3 crossing), and at the
# largest, high-row shapes a neighbour's OWN paint presses across the
# boundary at substantial, even near-opaque, alpha (measured directly on
# `band=5,variant=2`: a disconnected "ghost" island sits at the very top of
# the crop, mean alpha 0.449 at the tile's own row 0, fading to background by
# native sheet row ~18 before the REAL content for that cell begins at row
# ~36; `band=9,variant=7` shows the mirror case -- a flat ~0.9 mean-alpha
# PLATEAU starting immediately at row 0 with no taper at all, because that
# variant's own real content presses UP into the row-8 cell above it and the
# fixed grid crop simply cannot recover the part that lives on the other side
# of the boundary).
#
# The fix is two techniques together: `build_band_image` premultiplies alpha
# before the Lanczos resize and un-premultiplies after (so a near-invisible
# colour contributes to the resize kernel in proportion to how invisible it
# actually is, rather than at full weight), and feathers the crop's own outer
# border down to transparent before that resize (so whatever of a
# neighbour's overflow lands within this cell's own nominal boundary is
# discounted, and any of THIS cell's own content that was hard-clipped by the
# fixed grid at least TAPERS to transparent at the tile edge instead of
# ending in an unnatural, un-tapered cut).


## Technique (a)'s own regression guard: a pixel that reads as fully
## transparent must not still carry a strong, real colour underneath it.
## Threshold chosen from the ORIGINAL bug's own measured signature (real RGB
## persisting at alpha 0.004-0.02 at a real sheet boundary) -- alpha<0.02
## catches exactly that range. A sheet-wide scan of all 100 built tiles at
## this threshold measures 61,204 violating pixels against the unfixed
## pipeline (plain resize() on straight alpha); after premultiply + a
## `UNPREMULTIPLY_MIN_ALPHA`-guarded un-premultiply (dividing by a
## near-but-not-exactly-zero alpha otherwise amplifies 8-bit quantization
## noise into an arbitrary colour -- measured: an unguarded divide produced a
## pure white (1,1,1) pixel at alpha 1/255 on a tile that should be nearly
## empty), this measures exactly 0 -- not merely fewer, zero, because the
## channel>0.15 threshold sits comfortably above ordinary low-alpha
## antialiasing (measured real AA colour at alpha in (0.02, 0.05) tops out
## around 0.9-1.0 in a single pale channel with the others similarly pale,
## nothing like the original bug's distinctly-tinted 0.57/0.65/0.78 leaking
## through solid background).
func test_no_built_tile_shows_a_strongly_coloured_pixel_at_near_zero_alpha():
	var violations := 0
	var first_violation := ""
	for band in SnowLayer.DEPTH_BANDS:
		for variant in SnowLayer.OVERLAY_COLUMNS:
			var image := layer.build_band_image(band, variant)
			for y in image.get_height():
				for x in image.get_width():
					var pixel := image.get_pixel(x, y)
					var channel := maxf(pixel.r, maxf(pixel.g, pixel.b))
					if pixel.a < 0.02 and channel > 0.15:
						violations += 1
						if first_violation == "":
							first_violation = (
								"band %d variant %d at (%d,%d): rgba=%s"
								% [band, variant, x, y, pixel]
							)
	assert_eq(
		violations, 0,
		"%d pixels read as transparent but still carry real colour underneath -- first: %s"
		% [violations, first_violation]
	)


## Technique (b) (the edge feather alone) turned out NOT to fix either
## known-bad tile -- an independent re-check found this exact test passing
## by ACCIDENT. Feathering pushes the whole alpha profile down a couple of
## rows without deleting any of it: measured directly, the feather-only row
## means for `band=5,variant=2` are 0.028/0.266/0.449/0.344/0.130/0.012 (rows
## 0-5) -- row 2 equals the UNFIXED row 0 (0.449) almost exactly, so the
## "top row" this test used to check just moved, carrying the ghost blob
## with it. `band=9,variant=7`'s left-edge stray fragment was not addressed
## by the feather AT ALL (it sits well inside the crop's own left edge,
## outside the 8px feather zone) -- the feather only ever fixed that tile's
## TOP hard-clip, a genuinely separate issue. See `_discard_disconnected_
## bleed`'s own doc comment on `build_band_image` for the real, third fix
## (a connectivity check, reusing CompositeSheetSlicer's own "blobs not
## gutters" technique) this test now guards.
##
## Replaced with a connected-component count instead of a row/column mean,
## specifically because a mean can be moved without being reduced (see
## above) while a component count cannot: it asks whether a genuinely
## SEPARATE run of paint survives anywhere in the crop, not which row or
## column it happens to sit in. Checked on the RAW crop, immediately after
## `_discard_disconnected_bleed` runs, at the same native resolution the
## bleed was originally measured at -- checking the final resized tile
## instead would understate a survivor (measured: the same fragment that is
## 203 native px here is only 11px after the 32x32 resize).
##
## `band=9,variant=7`'s stray fragment is now fully gone: exactly 1
## component remains (its own real content, 7118px). `band=5,variant=2`'s
## ghost blob is NOT fully gone -- one of its original three fragments
## (203px) never grows even when the crop's own boundary is lifted 150
## native px in every direction (confirmed directly, see BLEED_NEIGHBOUR_
## PAD_PX's own doc comment), so by the same connectivity test that removes
## genuine bleed elsewhere this one is indistinguishable from a real small
## separate puff (like band=6,variant=0's own second cloud lobe) and is left
## in place -- a named, honest limitation (see docs/progress.md's own
## follow-up entry), not a silently missed bug. 300 sits with real margin
## above that known survivor (203) and real margin below the two DOMINANT
## fragments this fix does remove (654px and 167px) -- so this test is red
## against the crop before `_discard_disconnected_bleed` runs (which leaves
## a 654px fragment, comfortably over 300) and green after.
func test_known_bad_reference_tiles_have_no_substantial_stray_component():
	var ghost := layer._cropped_cell(2, 5)
	if ghost.get_format() != Image.FORMAT_RGBA8:
		ghost.convert(Image.FORMAT_RGBA8)
	layer._discard_disconnected_bleed(ghost, 2, 5)
	var ghost_worst_stray := _largest_non_dominant_component(ghost, SnowLayer.BLEED_COMPONENT_ALPHA)
	assert_lt(
		ghost_worst_stray, 300,
		"band=5 variant=2 still has a substantial disconnected fragment (%d native px) after bleed removal" % ghost_worst_stray
	)

	var clipped := layer._cropped_cell(7, 9)
	if clipped.get_format() != Image.FORMAT_RGBA8:
		clipped.convert(Image.FORMAT_RGBA8)
	layer._discard_disconnected_bleed(clipped, 7, 9)
	var clipped_worst_stray := _largest_non_dominant_component(clipped, SnowLayer.BLEED_COMPONENT_ALPHA)
	assert_eq(
		clipped_worst_stray, 0,
		"band=9 variant=7's left-edge stray fragment (%d native px) is still present after bleed removal" % clipped_worst_stray
	)


## Belt-and-braces companion to the component test above, checked on the
## FINAL built (resized) tile so a regression introduced downstream in
## feather/premultiply/resize would also be caught, not only one inside
## `_discard_disconnected_bleed` itself. Checks a RANGE of rows/columns
## rather than a single one, deliberately: a single fixed row (row 0) is
## exactly what the previous version of this test got away with checking
## (see this function's own doc comment above) -- a range wide enough to
## cover where a shifted peak would land is what actually holds up.
##
## Bounds: measured post-fix maxima are 0.108 (band=5,variant=2's own rows
## 0-10, i.e. everything before its real content starts ramping up at row
## 11) and 0.0068 (band=9,variant=7's own left four columns' mean). Both
## bounds below sit with real margin above those measured-fixed values and
## real margin below the pre-fix pipeline's own values at the same exact
## locations (0.449 and 0.1155 respectively).
##
## Checked against `_build_puff_image` (the illustrated-art pipeline alone),
## not the public `build_band_image` -- since the base tint was added
## (see this file's own "a continuous base tint" section), `build_band_image`
## deliberately paints real, nonzero alpha at every edge of every band >= 1,
## including band 5's and band 9's, which would otherwise fail THIS
## bleed-cleanliness claim for a reason that has nothing to do with bleed.
## The claim this test exists to protect -- the SLICER does not reproduce a
## neighbour's bleed -- is a claim about the illustrated art alone.
func test_known_bad_reference_tiles_stay_clean_through_the_full_pipeline():
	var ghost_tile := layer._build_puff_image(5, 2)
	var ghost_worst_row := 0.0
	for y in range(11):
		ghost_worst_row = maxf(ghost_worst_row, _row_mean_alpha(ghost_tile, y))
	assert_lt(
		ghost_worst_row, 0.2,
		"band=5 variant=2 still shows real ghost content somewhere in rows 0-10 (worst row mean %.3f)" % ghost_worst_row
	)

	var clipped_tile := layer._build_puff_image(9, 7)
	var clipped_left_edge := 0.0
	for x in range(4):
		clipped_left_edge += _col_mean_alpha(clipped_tile, x)
	clipped_left_edge /= 4.0
	assert_lt(
		clipped_left_edge, 0.05,
		"band=9 variant=7's left edge still carries real stray content (mean alpha %.4f across columns 0-3)" % clipped_left_edge
	)


## The connectivity fix could, in principle, sever a real tendril of a
## legitimately lobed or irregular blob rather than just a neighbour's
## bleed -- checked directly here across every one of the 100 real
## (band,variant) tiles, not just the two known-bad ones (the task this fix
## was built against explicitly asked for this: "measure it against all 100
## real tiles ... confirm no OTHER tile regresses").
##
## Measured: total painted mass retained sheet-wide is 88.25% (554,440
## native px before `_discard_disconnected_bleed`, 489,282 after), and the
## single worst-hit tile (band=4,variant=5) loses 30.3% of its own content --
## confirmed by direct render that this is a real lobe of band=3's own cloud
## pressing down across the row boundary (the exact same shape of defect as
## the two known-bad tiles, just not previously singled out), not a severed
## tendril of band=4,variant=5's own drawing. Bounds below sit with real
## margin on the safe side of both figures, so this is a genuine regression
## guard against a future re-tuning being far more aggressive than measured
## here, not a target dressed up as a guard.
func test_bleed_removal_does_not_gut_the_sheets_own_content():
	var total_before := 0
	var total_after := 0
	var worst_loss_fraction := 0.0
	var worst_tile := ""
	for band in SnowLayer.DEPTH_BANDS:
		for variant in SnowLayer.OVERLAY_COLUMNS:
			var before := layer._cropped_cell(variant, band)
			if before.get_format() != Image.FORMAT_RGBA8:
				before.convert(Image.FORMAT_RGBA8)
			var before_mass := _painted_pixel_count(before, SnowLayer.BLEED_COMPONENT_ALPHA)

			var after := layer._cropped_cell(variant, band)
			if after.get_format() != Image.FORMAT_RGBA8:
				after.convert(Image.FORMAT_RGBA8)
			layer._discard_disconnected_bleed(after, variant, band)
			var after_mass := _painted_pixel_count(after, SnowLayer.BLEED_COMPONENT_ALPHA)

			total_before += before_mass
			total_after += after_mass
			if before_mass > 0:
				var loss := float(before_mass - after_mass) / float(before_mass)
				if loss > worst_loss_fraction:
					worst_loss_fraction = loss
					worst_tile = "band=%d variant=%d" % [band, variant]

	var retained := float(total_after) / float(total_before)
	assert_gt(
		retained, 0.8,
		"bleed removal retained only %.1f%% of the sheet's total painted mass -- too aggressive" % (retained * 100.0)
	)
	assert_lt(
		worst_loss_fraction, 0.5,
		"%s lost %.1f%% of its own content to bleed removal -- likely a severed real tendril, not bleed"
		% [worst_tile, worst_loss_fraction * 100.0]
	)


## The tradeoff named alongside the fix: feathering a crop's own border
## toward transparent removes real alpha from EVERY tile's edge, including
## row 9's -- "one large puff nearly filling the cell" (see OVERLAY_COLUMNS'
## own doc comment), whose content already touches its own nominal cell edge
## at every one of its ten variants (measured: margin-to-edge 0px on at least
## one side for every row-9 variant). An edge fix sized to actually suppress
## the worst bleed could just as easily have gutted this instead. Measured
## after the fix: row 9's ten variants range 0.339-0.407 mean alpha, comfortable
## real margin over `FULL_COVER_MIN_MEAN_ALPHA` (0.32) -- this test pins that
## the tradeoff was actually checked, not just hoped to be fine; the
## per-variant version of the same claim is also asserted directly by
## test_a_dusting_lets_the_ground_show_through_and_full_cover_does_not above.
func test_full_cover_still_clears_the_min_mean_alpha_after_the_edge_fix():
	var worst := INF
	for variant in SnowLayer.OVERLAY_COLUMNS:
		var alpha := _mean_alpha(layer.build_band_image(SnowLayer.DEPTH_BANDS - 1, variant))
		worst = minf(worst, alpha)
	assert_gte(
		worst, SnowLayer.FULL_COVER_MIN_MEAN_ALPHA,
		"the worst row-9 variant's mean alpha (%.4f) no longer clears FULL_COVER_MIN_MEAN_ALPHA (%.2f) -- the edge fix amputated real content instead of just the bleed"
		% [worst, SnowLayer.FULL_COVER_MIN_MEAN_ALPHA]
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


# -- per-tile transform: breaking up "wallpaper" at the highest bands -------
#
# Reported live, with screenshots: a field of deep/near-full snow renders as
# an obviously artificial, grid-aligned repeating pattern -- the same
# rounded double-lobed blob in the same on-screen position and orientation,
# tile after tile. Investigated directly: this is NOT a variant_for or
# band_for bug (both independently confirmed to spread genuinely across a
# real 10x10 tile grid, no repetition pattern, and byte-identical painted-
# pixel counts against a pre-bleed-removal-fix reconstruction of this file at
# band 9). It is a real property of the illustrated ART at the highest
# coverage band: "one large puff nearly filling the cell" (see
# OVERLAY_COLUMNS' own doc comment) leaves little room for silhouette
# variety across its ten variants, so several of them read as visually
# similar ROUNDED BLOBS at a glance even though their pixels genuinely
# differ. Two identically-POSITIONED, identically-ORIENTED similar blobs
# read as "the same tile repeated"; two mirrored copies of the same blob do
# not -- so this axis breaks up the wallpaper look by varying ORIENTATION,
# independent of which variant/band is shown (see transform_for's own doc
# comment).
#
# Only flip_h, flip_v, and flip_h+flip_v were used at first -- NOT transpose.
# Checked directly by rendering real built tiles (band 9's own "puff nearly
# filling the cell" shapes) through all four orthogonal-group members:
# transpose visibly distorts a wide, roughly-oval mound into a tall, narrow
# one -- rotating a shape's own aspect ratio is a much bigger, more obviously
# wrong change than mirroring it, and several bands' own real content is not
# top/bottom symmetric (band 9's built tiles measure top-half alpha mass
# roughly 30x their own bottom half, e.g. variant 0: 363.7 vs 10.3) in a way
# a simple flip preserves (a mirrored mound is still a mound) but a
# transpose does not (it turns "wide, short at the bottom" into "tall,
# narrow on one side").
#
# FOLLOW-UP (vertical flip removed too): reported live, with a screenshot,
# after the flip-transform fix above had already shipped -- "the bigger the
# snow tiles get the wronger they become". Investigated directly rather than
# assumed:
#
# 1. NOT a residual-bleed regression -- rendering all 30 real (band,variant)
#    tiles at bands 7/8/9 through the current pipeline and running the same
#    connected-component tooling `_discard_disconnected_bleed` itself uses
#    finds 29 of 30 with a single component; the one exception
#    (band=8,variant=4) has a stray fragment only 2.6% the size of its own
#    dominant blob, far under any real flag threshold. Bleed removal at
#    these bands is clean.
#
# 2. IS a real defect in transform_for's own vertical flip. The original
#    TRANSPOSE exclusion above was justified by real top/bottom asymmetry
#    (band 9's ~30x figure), but that same asymmetry evidence was only ever
#    checked against transpose, never against FLIP_V -- the one transform
#    that inverts top and bottom. A fresh sweep of top/bottom alpha-mass
#    ratio through build_band_image, EVERY band, all 10 variants each, finds
#    real, substantial, per-band-CONSISTENT asymmetry everywhere except band
#    0 (worst deviation-from-1 by band: 3.34, 6.86, 9.24, 2.53, 26.25, 9.27,
#    3.22, 2.38, 5.44, 69.51 for bands 0-9) -- and the DIRECTION flips
#    partway through the ladder: bands 1-8 are bottom-heavy (content
#    anchored low, tapering upward -- a mound resting on the ground), while
#    band 9 is dramatically TOP-heavy (up to 69.5x), the one band whose
#    content is known to press UP past its own cell into row 8 (see
#    build_band_image's own EDGE FEATHER doc comment). A rendered
#    side-by-side of real band 7/8/9 tiles through all four transforms
#    confirms this by eye: FLIP_H siblings both still read as the same
#    coherent mound facing a different way (the "still a mound" case the
#    original TRANSPOSE exclusion described), but FLIP_V siblings at band 9
#    read as a visibly SMALLER, sparser patch floating away from the bottom
#    of the tile with an empty gap above it -- not "the same mound facing
#    the other way" but a mound that no longer reads as full, deep coverage.
#    That is exactly what "the bigger the snow tiles get, the wronger they
#    become" describes: the tiles meant to show the FULLEST cover are the
#    ones a vertical flip damages most, and the damage scales with how
#    asymmetric that band's real content is -- worst at band 9, the deepest
#    band.
#
#    Left/right asymmetry was checked the same way and is comparatively
#    safe to keep (worst deviation-from-1 by band: 6.43, 4.98, 3.65, 4.04,
#    2.59, 2.74, 2.73, 2.50, 1.95, 1.68 for bands 0-9) -- an order of
#    magnitude milder than top/bottom's worst case, consistently in ONE
#    direction (content generally sits right-of-centre at every band, not a
#    "must face this way" ground-anchoring the way vertical position is),
#    and confirmed by the same rendered comparison to stay a coherent,
#    still-a-mound shape under FLIP_H at every band checked.
#
#    Fix: TRANSFORM_FLIP_V and TRANSFORM_FLIP_H|TRANSFORM_FLIP_V are dropped
#    from transform_for's combinations, leaving identity and FLIP_H only --
#    two safe orientations instead of four, excluded for the same kind of
#    reason TRANSPOSE was already excluded down to zero: a flip that
#    inverts a shape's own real, ground-anchored orientation reads as
#    broken, not just "facing a different way".
const _TRANSFORM_FLIP_H := 4096  # TileSetAtlasSource.TRANSFORM_FLIP_H
const _TRANSFORM_FLIP_V := 8192  # TileSetAtlasSource.TRANSFORM_FLIP_V
const _TRANSFORM_TRANSPOSE := 16384  # TileSetAtlasSource.TRANSFORM_TRANSPOSE


func test_transform_matches_the_engines_own_flip_constants():
	# Confirms this file's own local mirrors of TileSetAtlasSource's real
	# engine constants (used above so this test file does not have to
	# instantiate one just to read three integers) have not drifted from the
	# actual engine values.
	assert_eq(_TRANSFORM_FLIP_H, TileSetAtlasSource.TRANSFORM_FLIP_H)
	assert_eq(_TRANSFORM_FLIP_V, TileSetAtlasSource.TRANSFORM_FLIP_V)
	assert_eq(_TRANSFORM_TRANSPOSE, TileSetAtlasSource.TRANSFORM_TRANSPOSE)


func test_transform_is_one_of_the_two_safe_flip_combinations():
	var valid := [
		0,
		_TRANSFORM_FLIP_H,
	]
	for x in range(40):
		var transform := layer.transform_for(x, -x * 5 + 2)
		assert_true(
			valid.has(transform),
			"transform_for returned %d, not one of the two safe combinations %s" % [transform, valid]
		)
		assert_eq(
			transform & _TRANSFORM_TRANSPOSE, 0,
			"transform_for set the TRANSPOSE bit -- excluded deliberately, see this section's own doc comment"
		)


## Direct regression driver for the "bigger snow tiles get wronger" report --
## see this section's own FOLLOW-UP doc comment above for the full
## measurement. TRANSFORM_FLIP_V inverts top and bottom, which every band
## from 1-9's real content asymmetry makes unsafe (worst case: band 9 at up
## to 69.5x), so transform_for must never set that bit, regardless of which
## combination it picks it from.
func test_transform_never_flips_vertically():
	for x in range(-80, 80):
		for y in range(-15, 15):
			var transform := layer.transform_for(x, y)
			assert_eq(
				transform & _TRANSFORM_FLIP_V, 0,
				(
					"transform_for(%d, %d) = %d sets the vertical flip bit -- " +
					"excluded, see this section's own FOLLOW-UP doc comment"
				) % [x, y, transform]
			)


## Pins the actual measured top/bottom alpha-mass asymmetry that justifies
## excluding FLIP_V -- see this section's own FOLLOW-UP doc comment for the
## full per-band figures this reproduces the worst two of. Guards against a
## future re-tuning silently re-adding FLIP_V once the numbers backing this
## exclusion are only prose nobody re-checks.
##
## Checked against `_build_puff_image`, not `build_band_image`: the claim is
## about the illustrated ART's own real asymmetry, which is what makes
## flipping it vertically look wrong. The base tint added since (see this
## file's own "a continuous base tint" section) is a uniform, edge-symmetric
## fill by construction, so compositing it under the puff can only ever pull
## a real top/bottom ratio TOWARD 1 (confirmed directly: measured 2.63 through
## `build_band_image` at this exact band/variant, comfortably under this
## test's own 10.0 floor, purely from adding an equal amount of mass to both
## halves) -- that would make this guard fail for a reason that has nothing
## to do with whether FLIP_V is still unsafe.
func test_band_9_content_is_severely_top_bottom_asymmetric():
	var ratio := _top_bottom_ratio(layer._build_puff_image(9, 0))
	assert_gt(
		ratio, 10.0,
		"band 9 variant 0's top/bottom alpha-mass ratio (%.2f) is no longer severely asymmetric -- re-check whether FLIP_V is still unsafe to re-add" % ratio
	)


func _top_bottom_ratio(image: Image) -> float:
	var top := 0.0
	var bottom := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var a: float = image.get_pixel(x, y).a
			if y < image.get_height() / 2:
				top += a
			else:
				bottom += a
	return top / bottom if bottom > 0.001 else INF


func test_transform_is_deterministic_for_the_same_tile():
	assert_eq(layer.transform_for(23, -9), layer.transform_for(23, -9))


func test_transform_varies_across_tiles():
	var seen := {}
	for x in range(40):
		seen[layer.transform_for(x, 0)] = true
	assert_gt(seen.size(), 1, "every tile getting the same transform defeats the point of having four")


## The whole reason this axis exists: two tiles that land on the exact same
## (band, variant) pair -- i.e. would draw the IDENTICAL picture -- must not
## also draw it in the identical orientation, or the wallpaper look this was
## built to fix comes right back. transform_for is intentionally a SEPARATE
## noise field from variant_for/band_for (different salt, see transform_for's
## own doc comment), so this checks that independence holds in practice, not
## just by construction: find two tiles that genuinely share a band+variant
## pair on a real sweep, and confirm they render as different PIXELS once the
## transform is applied -- not just that the two transform ints differ.
func test_two_tiles_sharing_the_same_band_and_variant_render_visually_distinguishable():
	var tiles_by_key := {}
	for x in range(-80, 80):
		for y in range(-15, 15):
			var band := layer.band_for(1.0, 0.0, layer.onset_offset_for(x, y))
			if band < 0:
				continue
			var key := Vector2i(band, layer.variant_for(x, y))
			if not tiles_by_key.has(key):
				tiles_by_key[key] = []
			tiles_by_key[key].append(Vector2i(x, y))

	var checked_a_pair := false
	for key in tiles_by_key:
		var tiles: Array = tiles_by_key[key]
		if tiles.size() < 2:
			continue
		var transform_by_tile := {}
		for tile in tiles:
			transform_by_tile[tile] = layer.transform_for(tile.x, tile.y)
		var tile_a: Vector2i = tiles[0]
		var transform_a: int = transform_by_tile[tile_a]
		var tile_b = null
		for tile in tiles:
			if transform_by_tile[tile] != transform_a:
				tile_b = tile
				break
		if tile_b == null:
			continue  # This bucket happened to land on one transform for every tile -- try the next.

		checked_a_pair = true
		var base_image: Image = layer.build_band_image(key.x, key.y)
		var image_a := _rendered_with_transform(base_image, transform_a)
		var image_b := _rendered_with_transform(base_image, transform_by_tile[tile_b])
		var differing_pixels := 0
		for py in image_a.get_height():
			for px in image_a.get_width():
				if absf(image_a.get_pixel(px, py).a - image_b.get_pixel(px, py).a) > 0.01:
					differing_pixels += 1
		assert_gt(
			differing_pixels, 0,
			(
				"tiles %s and %s share band=%d variant=%d with different transforms (%d vs %d) " +
				"but rendered byte-identical -- transform isn't actually breaking up the wallpaper look"
			) % [tile_a, tile_b, key.x, key.y, transform_a, transform_by_tile[tile_b]]
		)
		break

	assert_true(
		checked_a_pair,
		"precondition: never found two tiles across the sweep sharing a (band, variant) pair with different transforms -- can't check the wallpaper claim without this"
	)


## Mirrors what TileMapLayer itself does with a TileSetAtlasSource
## alternative_tile carrying flip bits -- confirmed directly against a real
## TileSetAtlasSource/TileMapLayer render (an asymmetric probe tile's marked
## quadrant moved from top-left to top-right under a raw FLIP_H
## alternative_tile, with no explicit create_alternative_tile call needed;
## see docs/progress.md's own entry on this investigation).
func _rendered_with_transform(image: Image, transform: int) -> Image:
	var out := image.duplicate()
	if transform & _TRANSFORM_FLIP_H:
		out.flip_x()
	if transform & _TRANSFORM_FLIP_V:
		out.flip_y()
	return out


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


func _row_mean_alpha(image: Image, y: int) -> float:
	var total := 0.0
	for x in image.get_width():
		total += image.get_pixel(x, y).a
	return total / float(maxi(image.get_width(), 1))


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


func _col_mean_alpha(image: Image, x: int) -> float:
	var total := 0.0
	for y in image.get_height():
		total += image.get_pixel(x, y).a
	return total / float(maxi(image.get_height(), 1))


## Every eight-connected run of `image`'s own painted (alpha > `threshold`)
## pixels -- an independent re-implementation in the TEST file on purpose
## (rather than reusing `SnowLayer._connected_components`), so this test
## cannot pass merely because production and test share one buggy notion of
## "connected".
func _connected_component_sizes(image: Image, threshold: float) -> Array:
	var width := image.get_width()
	var height := image.get_height()
	var visited := {}
	var sizes: Array = []
	var offsets := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for y in height:
		for x in width:
			var start := Vector2i(x, y)
			if visited.has(start) or image.get_pixel(x, y).a <= threshold:
				continue
			var queue: Array[Vector2i] = [start]
			visited[start] = true
			var size := 0
			while not queue.is_empty():
				var at: Vector2i = queue.pop_back()
				size += 1
				for offset in offsets:
					var next: Vector2i = at + offset
					if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
						continue
					if visited.has(next) or image.get_pixel(next.x, next.y).a <= threshold:
						continue
					visited[next] = true
					queue.append(next)
			sizes.append(size)
	return sizes


## The size of the second-biggest connected blob of painted content in
## `image`, or 0 if there is at most one -- "how big is the worst stray
## fragment that isn't this cell's own dominant content".
func _largest_non_dominant_component(image: Image, threshold: float) -> int:
	var sizes := _connected_component_sizes(image, threshold)
	sizes.sort()
	sizes.reverse()
	if sizes.size() <= 1:
		return 0
	return sizes[1]


func _painted_pixel_count(image: Image, threshold: float) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > threshold:
				count += 1
	return count
