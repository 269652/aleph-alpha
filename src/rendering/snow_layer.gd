extends RefCounted

## Snow as a per-tile overlay, so footprints can be carved out of it.
##
## Snow started as a tint on the whole ground layer, which cannot express
## "this tile is trodden and that one is not" -- a tint is one number for the
## entire world. Making it a layer of TILES is what lets a trail through a
## field exist at all.
##
## The layer sits above the terrain and below everything that stands on it, so
## grass and stones keep their shape under the cover: the ground is covered,
## not replaced.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## The illustrated coverage sheet: a clean 10-column x 10-row grid (this is
## the SECOND real illustrated asset this layer has drawn from -- the user
## replaced the first, a 5x5 contact sheet with baked-in divider lines, with
## this one; see git history / docs/progress.md for that sheet's own
## migration). Two independent axes, not one: ROW is coverage/depth (mean
## alpha climbs substantially and monotonically row 0 -> row 9: measured
## 0.037, 0.105, 0.126, 0.230, 0.256, 0.279, 0.303, 0.329, 0.398, 0.432 --
## row 0 a tiny scattered dusting, row 9 one large puff nearly filling the
## cell), while COLUMN is a genuinely separate hand/AI-illustrated shape
## VARIANT at roughly (not exactly) that same depth -- real per-column spread
## exists within a row (row 0 alone measures 0.015-0.051 across its 10
## columns) but does not trend monotonically column to column the way rows
## do: it is shape variety, not a second gradient (see variant_for below,
## which picks a tile's own column independently of its depth band).
##
## Declared before DEPTH_BANDS, which is DERIVED from these -- GDScript const
## expressions can't reference a const declared later in the same file (see
## IllustratedCharacterSprite.HERO_COMPOSITE_BACKGROUND_FLOOD_STEP_TOLERANCE's
## own doc comment for the same constraint hit there).
const OVERLAY_PATH := "res://assets/sprites/terrain/snowoverlay.png"
const OVERLAY_COLUMNS := 10
const OVERLAY_ROWS := 10

## How many depths of cover there are, from a dusting to full.
##
## Ground goes bare, dusted, covered, deep -- rather than snapping between two
## states, which is what makes a snowfall something you watch arrive.
##
## OVERLAY_ROWS, deliberately NOT OVERLAY_COLUMNS * OVERLAY_ROWS: the
## immediately-prior sheet was a 5x5 grid where every one of its 25 cells was
## a distinct coverage stage, so DEPTH_BANDS was the product of both axes.
## This sheet's two axes mean two DIFFERENT things (row = depth, column =
## shape variant at that depth, see OVERLAY_COLUMNS' own doc comment) -- a
## variant is not a finer depth rung, it is a different PICTURE of the same
## rung, so counting it into DEPTH_BANDS would be wrong, not just imprecise.
## This is therefore a real, deliberate drop from 25 depth bands to 10 -- a
## coarser depth ladder -- traded for genuine per-tile visual variety at each
## rung (ten real illustrated shapes instead of one), which the immediately
## prior fine-grain onset noise layer (see onset_offset_for's own doc comment,
## and docs/progress.md's "Fifth follow-up" snow entry) existed specifically
## to fake in the absence of real per-tile art. Ten discrete depth rungs is
## still comfortably more than the "bare, a dusting, and cover at the very
## least" floor (see test_there_is_a_tile_for_every_depth_band).
const DEPTH_BANDS := OVERLAY_ROWS

## A dusting must let its ground through; full cover must not, for EVERY one
## of the ten shape variants a tile might draw at that depth (see
## variant_for) -- not just one column, since which variant a given tile
## shows is now a real per-tile choice rather than always the sheet's first.
##
## Re-derived for the new sheet (was 0.06 / 0.80 against the old 5x5 sheet's
## own single least/fullest CELL, ~0.010 / ~0.922): measured directly across
## every one of the ten built variants of row 0 and row 9 through the real
## build_band_image path (crop + Lanczos resize to ART_TILE_SIZE, the same
## pipeline a painted tile actually uses), not assumed from the raw sheet's
## row means, since the resize itself measurably shifts mean alpha. Row 0's
## ten built variants measure 0.0148-0.0554 (max 0.0554); row 9's measure
## 0.3381-0.5163 (min 0.3381) -- a real per-variant spread wider than the old
## sheet ever had to account for, since the old constants only ever had to
## clear ONE fixed cell's value rather than the worst of ten. Both thresholds
## sit with real margin outside their respective measured range (see
## test_a_dusting_lets_the_ground_show_through_and_full_cover_does_not, which
## checks every variant, not just one).
const DUSTING_MAX_MEAN_ALPHA := 0.06
const FULL_COVER_MIN_MEAN_ALPHA := 0.32

## How much a fully trodden tile drops in depth, as a fraction of
## DEPTH_BANDS rather than a literal band count.
##
## Walking PACKS snow rather than clearing it: a trail should read as tracks
## through a field, not as a trench dug to the soil. Only where the cover was
## thin to begin with does a boot reach the ground. The ORIGINAL intent was a
## literal `2.0` out of DEPTH_BANDS=4 -- half the visible depth range packed
## down by a full tread. Left as a bare literal, that intent would silently
## drift every time DEPTH_BANDS changed for an unrelated reason (25, now 10)
## -- expressing it as a fraction of DEPTH_BANDS instead preserves the same
## "packs down about half the visible range" behaviour at ANY band count.
## Still the right formula at DEPTH_BANDS=10 (`TREAD_BANDS` = 5.0, half of
## 10) for the exact same reason it was still right at 25 -- confirmed by
## test_a_footprint_in_a_dusting_shows_the_ground and
## test_a_single_pass_does_not_clear_deep_snow, both still passing unchanged
## because the ratio, not the literal number, is what those tests depend on.
const TREAD_BANDS := float(DEPTH_BANDS) / 2.0

## The tile set: one tile per (depth band, shape variant) pair -- a real 2D
## atlas now, not the old 1D strip. The old 5x5 sheet had one visual per
## depth band; this one has OVERLAY_COLUMNS (10) real illustrated shapes at
## EACH of the DEPTH_BANDS (10) depths, so build_tile_set produces
## DEPTH_BANDS * OVERLAY_COLUMNS = 100 tile images, atlas-addressed at
## Vector2i(band, variant) to match how EarthChunkManager._paint_snow_tile
## calls set_cell (band decided by band_for, variant by variant_for).
func build_tile_set() -> TileSet:
	var art := TerrainRenderer.ART_TILE_SIZE
	var sheet := Image.create(DEPTH_BANDS * art, OVERLAY_COLUMNS * art, false, Image.FORMAT_RGBA8)
	for band in DEPTH_BANDS:
		for variant in OVERLAY_COLUMNS:
			sheet.blit_rect(
				build_band_image(band, variant), Rect2i(0, 0, art, art),
				Vector2i(band * art, variant * art)
			)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(sheet)
	source.texture_region_size = Vector2i(art, art)
	for band in DEPTH_BANDS:
		for variant in OVERLAY_COLUMNS:
			source.create_tile(Vector2i(band, variant))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(art, art)
	tile_set.add_source(source, 0)
	return tile_set


## One (band, variant) tile: a real crop of OVERLAY_PATH's matching cell,
## downscaled to ART_TILE_SIZE. `variant` defaults to 0 so existing call
## sites that only care about depth (most of test_snow_layer.gd's art
## assertions) don't have to pass one.
##
## Replaces the old per-pixel procedural paint (noise-picked coverage mask +
## per-block grain + a flat blue-white shade curve) entirely -- the real
## sheet's own pixels already carry coverage, grain and a faint blue tint, so
## there is nothing left for a synthetic mask to add. See build_tile_set for
## why this being called 100 times is still a one-time cost, not a runtime
## one.
##
## Lanczos, not nearest-neighbour, for the downscale: this is shrinking a
## ~125px source crop down to ART_TILE_SIZE (32 at the current
## DETAIL_MULTIPLIER), the same direction IllustratedTerrainSprite/
## TerrainRenderer._normalized_for_compositing already establishes Lanczos
## for in this exact codebase -- nearest-neighbour is the right call for
## UPSCALING small procedural art (see TerrainRenderer._blit_tile), but
## aliases fine illustrated per-pixel detail into visible "static" when
## SHRINKING (see _normalized_for_compositing's own doc comment for the
## measured, reported bug that convention fixed). This snow art is exactly
## the kind of fine illustrated detail (lumpy cloud-shaped patches) that bug
## was about.
##
## TWO further fixes live here, both against real measured slicer artefacts
## (reported: "fix the slicer so no artefacts appear") -- neither is a bug in
## _cropped_cell's own partition math (confirmed exact: gap-free,
## overlap-free, see that function's own doc comment), both are about the
## ILLUSTRATED CONTENT not being perfectly confined to its own nominal cell:
##
## 1. PREMULTIPLIED-ALPHA resize. Image.resize operates on straight
## (non-premultiplied) alpha, so a pixel that reads as fully transparent but
## still carries real, non-black colour underneath (confirmed directly: a
## sheet-wide sample crossing a real cell boundary -- row 6, column 2/3 --
## holds a consistent bluish RGB, ~0.57/0.65/0.78, all the way down to alpha
## 0.004-0.02, not noise) gets blended into the Lanczos kernel at FULL
## weight regardless of how invisible it actually is, producing a colour
## halo/fringe around real edges after the shrink. A sheet-wide scan of all
## 100 built tiles found 61,204 pixels with alpha<0.05 but a channel>0.15
## against the unfixed pipeline (see this file's own test,
## test_no_built_tile_shows_a_strongly_coloured_pixel_at_near_zero_alpha,
## which was red at 59,209 violations at this function's own stricter
## alpha<0.02 threshold before this fix, 0 after). `_UNPREMULTIPLY_MIN_ALPHA`
## guards the divide back out: at alpha this close to zero, dividing by it
## amplifies ordinary 8-bit quantization noise into an arbitrary colour
## (measured directly: an unguarded divide produced a pure white (1,1,1)
## pixel at alpha exactly 1/255 on a tile that should be nearly empty) --
## below that guard the pixel is just written black, which is correct since
## a colour under alpha this low is genuinely imperceptible either way.
##
## 2. EDGE FEATHER. Premultiplying suppresses near-invisible colour in
## proportion to its own alpha, but it cannot fix a neighbour's OWN paint
## pressing across the boundary at substantial -- even near-opaque -- alpha,
## which the illustrated sheet also genuinely has at its largest, high-row
## shapes (this sheet's cells are 153.6 x 102.4 native px, NOT square -- see
## _cropped_cell's own doc comment -- so a shape drawn to roughly fill a cell
## is tall relative to the shorter ROW dimension and some genuinely press
## past it). Confirmed on the two worst real cases found by rendering
## through this exact pipeline: `band=5,variant=2` shows a disconnected
## "ghost" blob sitting at the very top of the crop (unfixed top-row mean
## alpha 0.449, fading to background by native sheet row ~18, with this
## cell's OWN real content only starting around native row 36 -- literally a
## fragment of row 4's own shape bleeding down); `band=9,variant=7` shows a
## flat ~0.9 mean-alpha PLATEAU starting immediately at row 0 with no taper
## at all (unfixed row-by-row mean alpha 0.915/0.902/0.878/0.854/0.834..., a
## near-constant shelf, not a fade) -- that variant's own real content
## presses UP into the row-8 cell above it, so the fixed grid crop simply
## cannot recover the part that lives on the other side of the boundary; the
## best a crop CAN do is stop presenting the cut as a hard, un-tapered edge.
## `_feather_crop_edges` ramps alpha down to zero over `CROP_EDGE_FEATHER_PX`
## native pixels from whichever of the crop's four edges is nearest, using a
## smoothstep (not linear) ramp specifically because a linear ramp's
## discontinuous-derivative kink at the far edge of the feather zone measurably
## rings under the later Lanczos resize (observed directly while tuning this:
## a linear ramp left a visible alpha OVERSHOOT back toward 1.0 a few pixels
## in from the edge on some tiles; smoothstep's continuous derivative there
## did not). Applied to the crop BEFORE premultiply, so the two techniques
## compose correctly: the feathered alpha IS the alpha premultiply weights by.
##
## Both known-bad tiles' own top-row mean alpha dropped from 0.449 -> 0.028
## and 0.915 -> 0.059 respectively after this fix (see
## test_known_bad_reference_tiles_no_longer_spike_at_their_own_top_edge) --
## `band=9,variant=7` in particular now shows a genuine gradient (row means
## 0.059/0.470/0.808/0.800/0.777...) instead of the unfixed flat plateau, i.e.
## it now TAPERS rather than clips. Neither technique alone was sufficient:
## premultiply-only left both known-bad tiles visually near-identical to the
## unfixed render (row-0 means 0.449/0.902 with premultiply alone, since
## these are near-OPAQUE overflows, not the near-invisible colour premultiply
## targets); feather-only without premultiply would still leave the
## sheet-wide near-invisible-colour halo untouched. `CROP_EDGE_FEATHER_PX`
## was swept from both sides (measured at 4/6/8/10/12/16/20/24): a wider
## feather suppresses the known-bad tiles' top-row plateau further but costs
## real alpha off EVERY tile's edge, including row 9's -- "one large puff
## nearly filling the cell" (see OVERLAY_COLUMNS' own doc comment), which
## already touches its own nominal cell edge at every one of its ten variants
## (measured margin-to-edge: 0px on at least one side for all ten). 8px keeps
## row 9's worst-variant mean alpha at 0.339 -- real, if not huge, margin over
## FULL_COVER_MIN_MEAN_ALPHA (0.32) -- while still cutting the known-bad
## tiles' own top-row spike by ~87% each; see
## test_full_cover_still_clears_the_min_mean_alpha_after_the_edge_fix, which
## pins that this tradeoff was actually checked rather than assumed safe.
##
## THIS WAS STILL NOT ENOUGH -- an independent re-check measured the feather
## alone directly against the two known-bad tiles' own actual pixels (not
## just their row-0 mean) and found the "top-row spike" test above passes by
## ACCIDENT, not by fixing anything: feathering pushes the whole alpha
## profile down a couple of rows without deleting any of it, so row 0 reads
## low while the ghost content is now sitting, fully intact, at row 2
## (measured: unfixed row means 0.449/0.487/0.460/0.342/0.131/0.012, feather-
## only row means 0.028/0.266/0.449/0.344/0.130/0.012 -- feather-only's row 2
## equals unfixed row 0 almost exactly). `band=9,variant=7`'s left-edge stray
## fragment (see this comment's own EDGE FEATHER section above) was not
## addressed by the feather AT ALL: it sits well inside the crop's own left
## edge, entirely outside the 8px feather zone. See
## `_discard_disconnected_bleed`'s own doc comment below for the real fix.
const CROP_EDGE_FEATHER_PX := 8
const _UNPREMULTIPLY_MIN_ALPHA := 0.02

## Alpha a pixel must clear to count as "painted" for `_discard_disconnected_
## bleed`'s own connected-component search -- see that function's own doc
## comment for why a THIRD technique is needed at all (the feather above
## tapers an edge, it cannot delete a neighbour's content that survives
## several pixels deep).
##
## Not the same threshold as `_UNPREMULTIPLY_MIN_ALPHA` (0.02) -- that one
## exists to avoid amplifying 8-bit quantization noise into colour, an
## entirely different concern. This one has to sit ABOVE the sheet-wide
## near-invisible colour halo (measured at alpha 0.004-0.02, see this file's
## own PREMULTIPLIED-ALPHA doc comment above) so that halo can never bridge
## two genuinely separate drawings into one false connected blob, while
## sitting comfortably BELOW the real paint of every actual drawing on this
## sheet (measured: swept 0.05/0.1/0.15/0.2/0.3/0.5/0.7 against both
## known-bad tiles' own raw crops -- every value in that range gives the
## IDENTICAL component split, gap-free real margin on both sides). 0.3 is
## the middle of that measured-stable range.
const BLEED_COMPONENT_ALPHA := 0.3

## How far, in native sheet px, `_discard_disconnected_bleed` looks PAST a
## crop's own nominal boundary to tell a genuine neighbour intrusion apart
## from a small shape that merely touches this cell's own edge. See that
## function's own doc comment for the full reasoning.
##
## Measured, not guessed: the worst bleed depth found across all 100 tiles
## (band=5,variant=2's ghost blob, see this file's own EDGE FEATHER doc
## comment above) reaches about 36 native px past its own boundary. 45 clears
## that with real margin, confirmed by re-running the same growth check at
## 60/77/102/120/150px against several real components and finding the
## classification never changes past 45 -- a genuinely self-contained shape
## stays exactly the same size no matter how far the window is widened
## (measured directly: one of band=5,variant=2's own three top fragments
## holds at precisely 222px from 45px of padding all the way to 150px),
## while a genuine bleed fragment keeps growing as more of its real owner
## comes into view. 45 also stays safely inside a single neighbouring cell in
## both directions (half a cell is ~51px row-wise, ~77px column-wise, see
## _cropped_cell's own doc comment on the sheet's non-square cells) rather
## than reaching a second cell over.
const BLEED_NEIGHBOUR_PAD_PX := 45

## How much a component must grow, once the crop's boundary is lifted, to
## count as belonging mostly to a neighbour rather than to this cell.
##
## Expressed as a growth RATIO (grown-size / original-size) rather than an
## absolute pixel count, so it means the same thing for a tiny fragment and a
## large one. 2.0 is "more than half of this shape's real extent turned out
## to sit outside our own nominal cell" (ratio 2.0 <=> exactly half outside;
## see this function's own doc comment for the derivation) -- the plainest
## version of "this more plausibly belongs next door than here".
##
## NOT a clean bimodal split: measured across every non-largest component on
## the real sheet, growth ratios form a smooth continuum from 1.000 (never
## reaches a pixel of padding, e.g. band=6,variant=0's own second cloud lobe,
## a real deliberate second puff confirmed by direct render, ratio 1.190) up
## past 10 (e.g. band=5,variant=2's worst ghost fragment, ratio 29.25) with
## no gap to pick a threshold out of -- this sheet genuinely has shapes that
## brush against their neighbours by every degree, not just "clean" or
## "bled". 2.0 is a deliberately CONSERVATIVE line through that continuum:
## it protects every measured case that stays under 2x (including
## band=6,variant=0's real second lobe at 1.190, and one of band=5,variant=2's
## OWN three ghost fragments, which -- confirmed directly, swept up to 150px
## of padding -- never grows past 222px and so is kept rather than deleted;
## see _discard_disconnected_bleed's own doc comment for why that specific
## leftover speck is a known, named limitation rather than a silently missed
## bug), while still catching both tiles' DOMINANT, most visually damaging
## fragments (ratios 7.47-29.25 and 11.51 respectively) and, measured as a
## side effect, a further batch of real bleed elsewhere on the sheet (e.g.
## band=4,variant=5, confirmed by direct render: a real lobe of band=3's own
## cloud pressing down across the row boundary). Sheet-wide, this keeps
## 88.25% of the sheet's total painted mass (total measured before: 554,440
## px; after: 489,282 px) -- the worst SINGLE tile's own loss is band=4,
## variant=5 at 30.3% (its one dropped component IS that band=3 lobe, not a
## fragment of its own drawing, confirmed by the same render).
const BLEED_GROWTH_RATIO := 2.0

func build_band_image(band: int, variant: int = 0) -> Image:
	var clamped_band := clampi(band, 0, DEPTH_BANDS - 1)
	var clamped_variant := clampi(variant, 0, OVERLAY_COLUMNS - 1)
	var image := _build_puff_image(clamped_band, clamped_variant)
	_composite_base_beneath(image, clamped_band)
	return image


## The illustrated-puff pipeline alone, with no base tint composited under it
## -- exactly what `build_band_image` returned before the base tint existed
## (see this file's own "a continuous base tint" section below). Factored out
## so `_composite_base_beneath` has something real to composite onto, and so
## tests can compare the tint's effect against a real puff-only baseline (see
## test_dusting_band_still_shows_real_transparent_gaps and
## test_puff_detail_remains_distinguishable_over_the_base_tint in
## test_snow_layer.gd) rather than assuming what "no base tint" would have
## looked like.
##
## Takes ALREADY-CLAMPED band/variant -- build_band_image does the clamping
## once, at the public boundary, the same way it always did.
func _build_puff_image(band: int, variant: int) -> Image:
	var art := TerrainRenderer.ART_TILE_SIZE
	var cropped := _cropped_cell(variant, band)
	if cropped.get_format() != Image.FORMAT_RGBA8:
		cropped.convert(Image.FORMAT_RGBA8)
	_discard_disconnected_bleed(cropped, variant, band)
	_feather_crop_edges(cropped, CROP_EDGE_FEATHER_PX)
	_premultiply_alpha(cropped)
	cropped.resize(art, art, Image.INTERPOLATE_LANCZOS)
	_unpremultiply_alpha(cropped)
	return cropped


## Zeroes out any painted content in `cropped` that is NOT connected to this
## cell's own dominant content, when a neighbour's paint has pressed far
## enough across a cell boundary to survive as a substantial, separate blob
## rather than a thin edge fringe -- the case the edge feather above cannot
## reach (see this file's own "THIS WAS STILL NOT ENOUGH" doc comment).
##
## Reuses CompositeSheetSlicer's own core idea (see that file's own "Why
## blobs and not gutters" doc comment): a drawing is a connected run of
## content, and a stray mark is a SEPARATE blob, not a fainter continuation
## of the real one. That file finds and keeps every blob above a size floor
## because its sheet lays several independent, non-overlapping drawings out
## with real gutters between them. This sheet is different -- every cell
## shares its rectangle with exactly one drawing that's expected to nearly
## fill it (see OVERLAY_COLUMNS' own doc comment), so "keep every blob above
## a size floor" is the wrong rule here: band=6,variant=0's own real content
## is legitimately TWO separate touching-but-disconnected cloud puffs (
## confirmed by direct render), and a light dusting band's real content is
## legitimately MANY small separate specks (confirmed by direct render on
## band=1). Blindly discarding every blob but the largest would gut both.
##
## So this asks a different question per blob: not "is it big enough to be a
## drawing", but "does it keep growing once you look past this cell's own
## boundary". A piece of THIS cell's own content -- however small, however
## many separate touching puffs it is split into -- is already complete
## within its own nominal rectangle and does not grow when the window
## widens. A piece of a NEIGHBOUR's content that merely presses across the
## boundary keeps growing, because most of the shape it belongs to is still
## sitting on the other side. Confirmed directly on both known-bad tiles and
## on band=6,variant=0's real second lobe -- see BLEED_GROWTH_RATIO's own doc
## comment for the actual measured numbers.
##
## KNOWN LIMITATION, named rather than silently missed: one of band=5,
## variant=2's own three top fragments (the smallest, ~203px) never grows
## even at 150px of padding (see BLEED_NEIGHBOUR_PAD_PX's own doc comment) --
## by this function's own test it is indistinguishable from a genuine small
## separate puff (like band=6,variant=0's own second lobe), so it is left in
## place rather than guessed at. It is real, but a small minority of the
## original ghost blob's total mass (~20%, 203 of 1024px across the three
## fragments) -- the two dominant fragments (~80%) are removed. See
## docs/progress.md's own follow-up entry for this named honestly.
func _discard_disconnected_bleed(cropped: Image, column: int, row: int) -> void:
	var components := _connected_components(cropped, BLEED_COMPONENT_ALPHA)
	if components.size() <= 1:
		return
	components.sort_custom(func(a, b): return a.pixels.size() > b.pixels.size())

	var sheet := _overlay_sheet()
	var bounds := _cell_bounds(column, row)
	var pad_x0 := maxi(0, bounds.position.x - BLEED_NEIGHBOUR_PAD_PX)
	var pad_y0 := maxi(0, bounds.position.y - BLEED_NEIGHBOUR_PAD_PX)
	var pad_x1 := mini(sheet.get_width(), bounds.position.x + bounds.size.x + BLEED_NEIGHBOUR_PAD_PX)
	var pad_y1 := mini(sheet.get_height(), bounds.position.y + bounds.size.y + BLEED_NEIGHBOUR_PAD_PX)
	var padded := sheet.get_region(Rect2i(pad_x0, pad_y0, pad_x1 - pad_x0, pad_y1 - pad_y0))
	var offset_in_padded := Vector2i(bounds.position.x - pad_x0, bounds.position.y - pad_y0)

	# Component 0 is this cell's own dominant content and is never a removal
	# candidate -- every other component is tested on its own.
	for i in range(1, components.size()):
		var pixels: Array = components[i].pixels
		var seed_in_padded: Vector2i = pixels[0] + offset_in_padded
		var grown_size := _flood_fill_size(padded, BLEED_COMPONENT_ALPHA, seed_in_padded)
		if float(grown_size) / float(pixels.size()) >= BLEED_GROWTH_RATIO:
			for pixel in pixels:
				cropped.set_pixel(pixel.x, pixel.y, Color(0.0, 0.0, 0.0, 0.0))


## Every connected run of `image`'s own painted (alpha > `threshold`) pixels,
## eight-connected (a diagonal-only touch still counts as one blob -- same
## convention CompositeSheetSlicer._blob_boxes uses and for the same reason:
## a real illustrated edge can touch corner-to-corner without a cardinal
## connection). Returns each blob's own pixel list, unsorted; the caller
## decides what "biggest" or "keep" means for its own purpose.
func _connected_components(image: Image, threshold: float) -> Array:
	var width := image.get_width()
	var height := image.get_height()
	var visited := {}
	var components: Array = []
	var offsets: Array[Vector2i] = [
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
			var pixels: Array[Vector2i] = []
			while not queue.is_empty():
				var at: Vector2i = queue.pop_back()
				pixels.append(at)
				for offset in offsets:
					var next := at + offset
					if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
						continue
					if visited.has(next) or image.get_pixel(next.x, next.y).a <= threshold:
						continue
					visited[next] = true
					queue.append(next)
			components.append({"pixels": pixels})
	return components


## The size of the single connected blob of `image`'s own painted (alpha >
## `threshold`) pixels that contains `seed` -- eight-connected, same
## convention as `_connected_components`. Returns 0 if `seed` itself is out
## of bounds or not painted (defensive: every real call site's seed is
## already a painted pixel from the source image, so this only guards
## against a coordinate mistake rather than a case expected in practice).
func _flood_fill_size(image: Image, threshold: float, seed: Vector2i) -> int:
	var width := image.get_width()
	var height := image.get_height()
	if seed.x < 0 or seed.x >= width or seed.y < 0 or seed.y >= height:
		return 0
	if image.get_pixel(seed.x, seed.y).a <= threshold:
		return 0
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	var visited := {seed: true}
	var queue: Array[Vector2i] = [seed]
	var size := 0
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		size += 1
		for offset in offsets:
			var next := at + offset
			if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
				continue
			if visited.has(next) or image.get_pixel(next.x, next.y).a <= threshold:
				continue
			visited[next] = true
			queue.append(next)
	return size


## Ramps this image's own alpha down to zero over `feather_px` pixels from
## whichever of its four edges is nearest -- see build_band_image's own doc
## comment for why this exists and how `feather_px` was measured. Smoothstep
## (`t*t*(3-2t)`), not a linear ramp: a linear ramp's kinked derivative at the
## far edge of the feather zone measurably rings under the Lanczos resize
## that follows (see build_band_image's own doc comment). Mutates `image` in
## place; called on a fresh per-call crop, never on the shared cached sheet.
func _feather_crop_edges(image: Image, feather_px: int) -> void:
	if feather_px <= 0:
		return
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		var edge_distance_y := mini(y, height - 1 - y)
		for x in width:
			var edge_distance_x := mini(x, width - 1 - x)
			var edge_distance := mini(edge_distance_x, edge_distance_y)
			if edge_distance >= feather_px:
				continue
			var t := float(edge_distance) / float(feather_px)
			var ramp := t * t * (3.0 - 2.0 * t)
			var pixel := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, pixel.a * ramp))


## Multiplies each pixel's own RGB by its own alpha, in place -- the first
## half of the premultiplied-alpha resize (see build_band_image's own doc
## comment). Must run AFTER feathering, so the feathered alpha is the alpha
## this weights by, not the crop's original one.
func _premultiply_alpha(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * pixel.a, pixel.g * pixel.a, pixel.b * pixel.a, pixel.a))


## Divides each pixel's own RGB back out of its own alpha, in place -- the
## second half of the premultiplied-alpha resize, run after the Lanczos
## resize this file's own resize() call performs. Alpha itself is clamped to
## [0,1] first: Lanczos's negative lobes can overshoot slightly past the
## input range, and RGBA8 storage already clamps this silently on write, but
## clamping explicitly here keeps the divide's own input well-defined rather
## than relying on that implicit behaviour. Guarded by
## `_UNPREMULTIPLY_MIN_ALPHA` -- see build_band_image's own doc comment for
## the measured amplified-noise failure this guard exists to prevent.
func _unpremultiply_alpha(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var alpha := clampf(pixel.a, 0.0, 1.0)
			if alpha > _UNPREMULTIPLY_MIN_ALPHA:
				image.set_pixel(x, y, Color(
					clampf(pixel.r / alpha, 0.0, 1.0),
					clampf(pixel.g / alpha, 0.0, 1.0),
					clampf(pixel.b / alpha, 0.0, 1.0),
					alpha
				))
			else:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))


## The real, loaded sheet image -- read from disk once and shared by every
## SnowLayer instance (mirrors IllustratedTerrainSprite._frame_cache/
## IllustratedCharacterSprite._head_sheet's own "load once, reuse forever"
## convention: the sheet's pixels never change between instances or tests).
static var _overlay_sheet_image: Image = null


func _overlay_sheet() -> Image:
	if _overlay_sheet_image == null:
		_overlay_sheet_image = SpriteSheetLoader.load_image(OVERLAY_PATH)
	return _overlay_sheet_image


## A real crop of sheet cell (column, row) -- no centered-square cropping or
## divider avoidance needed, unlike the OLD 5x5 sheet's own `_cropped_cell`
## (see OVERLAY_COLUMNS' own doc comment): this sheet's cells are an exact
## grid with no divider-line artefacts anywhere, confirmed by the same
## min-alpha-across-every-row/column sweep that originally found the old
## sheet's divider lines -- that sweep finds nothing on this one. Cell
## boundaries are nearest-integer-rounded rather than floored, so the cells
## across a dimension partition it exactly with no 1px gap or overlap
## anywhere regardless of whether the sheet's own size divides evenly by
## OVERLAY_COLUMNS/OVERLAY_ROWS; get_region needs an int rect regardless.
##
## The grid is NOT square: `test_the_overlay_sheet_has_the_measured_
## dimensions` pins the sheet at 1536x1024 (154 wide x 102 tall cells,
## before rounding) -- corrected here from an earlier 1254x1254 (125.4x125.4
## square cells) after the illustrated sheet was replaced again; re-confirm
## against that test if this ever looks wrong, since another replacement can
## change it again without this comment being updated in lockstep. A grid
## this much SHORTER than it is wide is exactly why the high-row shapes
## press across their own ROW boundary at substantial alpha (see
## build_band_image's own doc comment on the edge feather this exact
## asymmetry motivates) far more than they press across a COLUMN boundary:
## a roughly-circular "puff" drawn to fill a cell is tall relative to a
## 102px-high row long before it is wide relative to a 154px-wide column.
func _cropped_cell(column: int, row: int) -> Image:
	var sheet := _overlay_sheet()
	return sheet.get_region(_cell_bounds(column, row))


## `_cropped_cell`'s own partition math, factored out so
## `_discard_disconnected_bleed` can pad OUT from the exact same rectangle
## rather than risk a second, drifting copy of this arithmetic (see this
## file's own GDScript typed-array/const-ordering conventions elsewhere for
## why a shared source of truth matters here). Returns the cell's bounds in
## SHEET (not crop-local) pixel coordinates.
func _cell_bounds(column: int, row: int) -> Rect2i:
	var sheet := _overlay_sheet()
	var cell_width := float(sheet.get_width()) / float(OVERLAY_COLUMNS)
	var cell_height := float(sheet.get_height()) / float(OVERLAY_ROWS)
	var x0 := int(round(column * cell_width))
	var x1 := int(round((column + 1) * cell_width))
	var y0 := int(round(row * cell_height))
	var y1 := int(round((row + 1) * cell_height))
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


## Which of OVERLAY_COLUMNS illustrated shape variants a tile draws at its
## own depth band -- a SEPARATE axis from band_for's coverage decision (see
## OVERLAY_COLUMNS' own doc comment for why the sheet has one at all): band
## says how MUCH snow, variant says which real illustrated SHAPE draws it, so
## neighbouring tiles at the same depth don't all show the identical blob.
##
## Deliberately NOT sampled like onset_offset_for's smooth drift field.
## Onset has to be low-frequency (see that function's own doc comment: a
## per-tile-independent onset checkerboarded the tile grid), because it
## drives a THRESHOLD decision where two neighbours landing on opposite
## sides of a boundary is the bug. Variant drives no threshold -- it is
## cosmetic shape choice at a FIXED depth -- so it has no such coherence
## requirement, and in fact wants the opposite: two edge-adjacent tiles at
## the same depth SHOULD often show different shapes, since that variety is
## the entire reason this axis exists (see
## test_neighbouring_tiles_often_show_different_variants). Uses
## PixelNoise.range_index, built on `unit` -- PixelNoise's genuinely
## per-cell-independent form (see `smooth`'s own doc comment: "unlike
## `unit`'s per-pixel scatter"), the opposite of the smooth field onset
## needs.
##
## Seeded from GLOBAL tile coordinates, the same convention onset_offset_for
## uses, so the pattern neither repeats nor seams at a chunk boundary, and is
## a pure, deterministic function of the tile's own coordinates for its whole
## loaded lifetime -- cached the same way onset is (see
## EarthChunkManager._snow_variant_by_tile).
const _VARIANT_SALT := 7727

func variant_for(global_x: int, global_y: int) -> int:
	return PixelNoise.range_index(_VARIANT_SALT, global_x, global_y, OVERLAY_COLUMNS)


## How far a tile's own snow onset can lead or lag the field's overall
## coverage, so a chunk fills in as a visible spread rather than every tile
## crossing the same threshold in the same instant.
##
## Every tile used to read the exact same `depth` (see EarthChunkManager's
## single shared `_snow_depth`), so the moment that one number ticked past a
## band boundary the WHOLE loaded field flipped together -- reported as "snow
## covers a whole chunk instantly instead of spreading progressively". This is
## the same seeded-per-cell-jitter idea TallGrass/FlowerPatch already use so a
## uniform process doesn't read as synchronized (see PixelNoise's own doc
## comment: this project has hit that "same value everywhere" clustering bug
## five times already), just applied to WHEN a tile catches on rather than
## WHERE something is placed.
##
## Bounded well under the full 0..1 depth range: wide enough that a partial
## snowfall genuinely mixes bare and covered tiles instead of everyone
## crossing together, narrow enough that full cover (depth 1.0) still reaches
## the deepest band even for the most-lagging tile, and bare ground (depth
## 0.0) still shows nothing even for the most-leading one -- both guaranteed
## unconditionally by band_for's own clamping regardless of DEPTH_BANDS (see
## test_onset_cannot_show_snow_on_a_genuinely_bare_field/test_onset_cannot_
## hide_snow_once_the_field_is_fully_covered).
##
## This is a fraction of the DEPTH range, not of a depth BAND, so it does not
## need re-deriving when DEPTH_BANDS changes (was illustratively described as
## "well under one full depth band, 0.25" back when DEPTH_BANDS was 4 --
## at DEPTH_BANDS=25 the SAME 0.18 now spans about 4.5 of the much finer
## bands rather than under one of the old coarse ones, which is fine: it
## means a leading/lagging tile can range further across the illustrated
## sheet's 25 real gradient steps, reading as an even richer spread, not a
## broken one -- see MAX_NEIGHBOUR_ONSET_STEP below for the constant that
## DID need re-deriving for the new band count.
##
## Still true at the current DEPTH_BANDS=10 (the sheet changed again, see
## OVERLAY_COLUMNS' own doc comment, but onset_offset_for below reads none of
## DEPTH_BANDS/OVERLAY_COLUMNS/OVERLAY_ROWS -- literally the same field either
## way): confirmed by re-running every onset test in this file unchanged.
const ONSET_VARIANCE := 0.18
const _ONSET_SALT := 5303

## How much of ONSET_VARIANCE's budget goes to the FINE layer below, versus
## the broad one above -- see onset_offset_for's own doc comment for why a
## second layer exists at all.
##
## Measured, not eyeballed: swept every 24x24 window across a real 400x120-
## tile swath for several broad/fine amplitude splits at ONSET_FINE_DRIFT_
## TILES=2 (see onset_offset_for). The OLD single-broad-layer field's worst
## window anywhere in that swath held only 3 distinct depth bands (tile
## origin (-42, -48), the exact case test_a_local_window_shows_real_per_
## tile_variation_not_a_uniform_plateau pins). A 0.13/0.05 broad/fine split
## raised that SAME worst-case-anywhere window to 5 distinct bands -- a real,
## swath-wide improvement, not a fix for one cherry-picked spot -- while only
## raising the worst neighbour step from 0.0357 to 0.0612 (see
## MAX_NEIGHBOUR_ONSET_STEP below). Smaller fine budgets (0.03-0.04) barely
## moved the worst case (4 bands); larger ones (0.07+) pushed the neighbour
## step close to double with only marginal further gain. Expressed as the
## FINE share with broad DERIVED from it (`ONSET_VARIANCE - ONSET_FINE_
## VARIANCE`) so the two can never drift out of sync and silently blow the
## overall bound every other onset test depends on.
const ONSET_FINE_VARIANCE := 0.05
const ONSET_BROAD_VARIANCE := ONSET_VARIANCE - ONSET_FINE_VARIANCE
const _ONSET_FINE_SALT := 9013

## How many TILES one lift of the drift field spans.
##
## This offset used to be rolled per tile with PixelNoise.range_value --
## white noise, so two touching tiles could land 2 * ONSET_VARIANCE apart
## (measured: 0.3582) which is MORE than one whole depth band (1.0 /
## DEPTH_BANDS = 0.25). Snow then rendered as a checkerboard of bare /
## dusted / covered SQUARES with a razor edge on the tile grid, reported as
## texture corruption rather than as snow: the tile is the smallest thing
## band_for can speak about, so the noise driving it has to be much COARSER
## than a tile, not finer.
##
## Snow drifts and shelters in patches many metres across -- a hollow, a lee
## side, the shade of a tree line -- so the field deciding which ground
## catches first is low-frequency by construction: neighbours nearly
## identical, only tens of tiles apart fully different. Same PixelNoise
## everything else draws with, just its `smooth` form rather than its
## per-cell scatter (see PixelNoise's own doc comment).
##
## Measured, not eyeballed: 12 tiles gives a max neighbour step of 0.0436
## while the field still spans the whole +/-ONSET_VARIANCE range. Pinned
## from both sides -- MAX_NEIGHBOUR_ONSET_STEP says it is coarse enough,
## test_the_drift_field_still_covers_the_ground_unevenly says it has not
## been flattened into a constant.
const ONSET_DRIFT_TILES := 12.0

## How many TILES one lift of the FINE grain layer spans -- see
## onset_offset_for's own doc comment for why a second layer exists.
##
## Measured alongside ONSET_FINE_VARIANCE (see its own doc comment for the
## full sweep): 2 tiles gave the best real improvement in swath-wide worst-
## case local variation (3 -> 5 distinct bands in the worst 24x24 window)
## for the smallest neighbour-step cost among the periods tried (1.5, 2, 3
## tiles). Deliberately much shorter than ONSET_DRIFT_TILES=12 -- the broad
## layer still decides which general AREA catches on first (a hollow, a lee
## side, a tree line's shade), the fine layer only adds texture WITHIN
## whatever area the broad layer already chose.
const ONSET_FINE_DRIFT_TILES := 2.0

## The most two edge-adjacent tiles' onsets may differ.
##
## Used to be a literal quarter of a depth band (`0.25 / DEPTH_BANDS`), so a
## band boundary took at least four tiles to cross. Left as that same
## formula at DEPTH_BANDS=25 it would demand 0.01 -- TIGHTER than the drift
## field's own real, unchanged, measured worst case of 0.0436 (see
## ONSET_DRIFT_TILES's own doc comment: onset_offset_for does not read
## DEPTH_BANDS at all, so that field's real behaviour is identical before and
## after this pass), which would fail test_neighbouring_tiles_have_nearly_
## the_same_onset outright unless the drift field were made drastically
## coarser -- a much bigger, undesired change to how snow visually spreads
## (see ONSET_DRIFT_TILES) just to chase a band count that changed for a
## different reason entirely.
##
## Re-derived instead of blindly rescaled: a literal quarter-band was never
## really the point -- the point was "two neighbours can never look like a
## whole extra depth STATE apart". At the old DEPTH_BANDS=4, one band was
## 25% of the whole visible range, so crossing a whole one was a large,
## obvious jump worth guarding hard against. At DEPTH_BANDS=25, one band is
## only 4% of the range -- crossing a whole extra one is a subtle step, not
## the "checkerboard with a razor edge" bug this constant exists to prevent.
## Pinned instead with real margin over the drift field's own measured
## worst-case (0.0436), so this stays a genuine regression guard on that
## field rather than an unreachable target: the field itself is bounded
## exactly as before.
##
## RE-MEASURED again for the added fine layer (see ONSET_FINE_VARIANCE):
## adding real per-tile texture necessarily makes neighbours differ MORE,
## not less, so this had to move -- the question was only "by how much is
## real, and by how much is too much". Over the same -60..60 x -6..6 sweep
## test_neighbouring_tiles_have_nearly_the_same_onset already uses, the
## combined broad+fine field's worst measured neighbour step is 0.0612 (was
## 0.0357 broad-only -- note this differs slightly from the 0.0436 quoted
## above, which was measured at a different point in this file's history;
## re-measuring the CURRENT broad-only field over this exact sweep gives
## 0.0357). 0.0612 is about 1.53 depth bands (0.04 each) -- close to but
## still under a full 2-band jump, and nowhere close to the old
## checkerboard's 2 * ONSET_VARIANCE (0.36) jump, which crossed the ENTIRE
## old 4-band range in one step. Re-pinned to 0.07 with real (if narrower
## than first estimated) margin over that fresh measurement -- re-verify
## this margin if ONSET_FINE_VARIANCE or ONSET_FINE_DRIFT_TILES ever change
## again, since it is closer to the ceiling than the first pass assumed.
##
## Re-checked, not just re-scaled, for the DEPTH_BANDS 25 -> 10 asset change:
## a band is now 0.1 wide (was 0.04), a much coarser grid, so it would be
## tempting to assume this constant needs to grow with it. It does not --
## onset_offset_for reads no DEPTH_BANDS-derived value at all, so the real
## field this bounds is byte-for-byte unchanged, and re-running the exact
## same sweep test_neighbouring_tiles_have_nearly_the_same_onset already uses
## still measures the identical worst case, 0.0612. 0.0612 against a 0.1-wide
## band is a bigger FRACTION of one band than it was against 0.04 (roughly
## 0.6 of a band now, versus 1.53 of the old finer ones) -- coarser bands
## mean a given absolute onset spread now covers proportionally MORE of one
## band, not less, which is the opposite direction a naive ratio-rescale
## would have moved this constant. Left at 0.07: still real margin over the
## unchanged 0.0612 measurement, and still nowhere near a whole-band jump.
const MAX_NEIGHBOUR_ONSET_STEP := 0.07


## This tile's own onset offset, in [-ONSET_VARIANCE, ONSET_VARIANCE] --
## seeded from its GLOBAL tile coordinates (not chunk-local, so the pattern
## doesn't repeat or seam at chunk boundaries) via PixelNoise rather than
## Godot's own `hash()`, which correlates neighbouring inputs (see
## PixelNoise's doc comment).
##
## Sampled from a SMOOTH field at ONSET_DRIFT_TILES tiles per lift rather
## than rolled per tile, so the bare/dusted boundary reads as a meandering
## snow line rather than as grid squares (see ONSET_DRIFT_TILES).
##
## TWO layers, not one -- reported live (after DEPTH_BANDS went 4 -> 25):
## "it's not using accumulation per tile and sth like perlin noise or so
## instead whole areas increment to next sprite without variations". The
## single ONSET_DRIFT_TILES=12 broad layer above is exactly what its own doc
## comment says it should be -- low-frequency, so a hollow or a lee side
## catches snow as one coherent patch rather than a checkerboard -- but a
## realistic ~20-30 tile on-screen view often sits entirely inside one lobe
## of a 12-tile-period field, where the local slope is close to flat. Every
## tile in that view then rounds to nearly the same band: not the
## checkerboard bug (neighbours differing too much), closer to the opposite
## (a whole neighbourhood reads as one flat plateau). Measured directly: the
## worst 24x24 window found sweeping a real 400x120-tile swath of the
## broad-only field held only 3 distinct bands at a mid snowfall (depth 0.5)
## -- see test_a_local_window_shows_real_per_tile_variation_not_a_uniform_
## plateau, which pins that exact case.
##
## PixelNoise.fractal already builds "broad shape plus fine grain" by
## stacking doubling-frequency octaves of the SAME seed, but every octave
## there shares one salt -- fine here needs its own salt (_ONSET_FINE_SALT)
## so its lattice points don't correlate with the broad layer's (two octaves
## of one seed can share zero-crossings; two independent salts can't). A
## second, much shorter-period SMOOTH layer (ONSET_FINE_DRIFT_TILES = 2)
## adds real tile-to-tile texture within whatever broad-scale patch the
## first layer already chose, at a deliberately small slice of the shared
## ONSET_VARIANCE budget (see ONSET_FINE_VARIANCE) so the broad layer still
## dominates which general area goes first. Re-measured on the combined
## field: that same worst window rose from 3 to 5 distinct bands, while the
## worst neighbour step rose from 0.0357 to 0.0612 (see MAX_NEIGHBOUR_
## ONSET_STEP, re-pinned for this).
func onset_offset_for(global_x: int, global_y: int) -> float:
	var broad := PixelNoise.smooth(
		_ONSET_SALT,
		float(global_x) / ONSET_DRIFT_TILES,
		float(global_y) / ONSET_DRIFT_TILES
	)
	var fine := PixelNoise.smooth(
		_ONSET_FINE_SALT,
		float(global_x) / ONSET_FINE_DRIFT_TILES,
		float(global_y) / ONSET_FINE_DRIFT_TILES
	)
	return (
		lerpf(-ONSET_BROAD_VARIANCE, ONSET_BROAD_VARIANCE, broad)
		+ lerpf(-ONSET_FINE_VARIANCE, ONSET_FINE_VARIANCE, fine)
	)


## Which of two flip transforms a tile's snow overlay renders with -- an
## axis independent of variant_for/band_for entirely (own salt, reads only
## the tile's own global coordinates), so it can break up a "wallpaper" look
## that neither of those two axes can fix on their own.
##
## Reported live, with screenshots: a field of deep/near-full snow renders as
## an obviously artificial, grid-aligned repeating pattern -- the same
## rounded double-lobed blob, tile after tile, in the same on-screen
## position and orientation. Investigated directly rather than assumed a
## regression: variant_for and band_for both independently confirmed to
## spread genuinely across a real 10x10 tile grid (all 10 variants present,
## no repetition pattern), and build_band_image's painted-pixel counts at
## band 9 measured BYTE-IDENTICAL against a reconstruction of this file from
## before this session's two rounds of cross-cell bleed-removal fixes (see
## build_band_image's own "EDGE FEATHER"/"THIS WAS STILL NOT ENOUGH" doc
## comments) -- so this was never a variant-selection, band-selection, or
## slicing bug. It is a real property of the illustrated ART at the highest
## coverage band: "one large puff nearly filling the cell" (see
## OVERLAY_COLUMNS' own doc comment) leaves little room for silhouette
## variety across ten hand/AI-illustrated variants, so several of them read
## as visually similar rounded blobs at a glance even though a duplicate-pair
## sweep across all 45 pairs at bands 7/8/9 found zero exact pixel
## duplicates -- the pixels genuinely differ, the SILHOUETTE reads the same.
##
## Two tiles showing a similar-looking blob in the identical on-screen
## POSITION and ORIENTATION read as "the same tile repeated" -- the actual
## wallpaper look. Two mirrored/rotated copies of that same similar-looking
## blob do not, even though the underlying art convergence at this band is
## unchanged: orientation is a genuinely separate axis of visual variety from
## "which picture is shown", the same way variant_for is separate from
## band_for's depth.
##
## Combines TileSetAtlasSource's own TRANSFORM_FLIP_H/TRANSFORM_FLIP_V bit
## constants (bitwise OR) and returns the result directly as a
## TileMapLayer.set_cell `alternative_tile` argument -- confirmed against a
## real, minimal TileSetAtlasSource/TileMapLayer instead of assumed from
## memory: a raw flip-bit value works as `alternative_tile` with NO
## `create_alternative_tile` registration call needed at all
## (`TileSetAtlasSource.has_alternative_tile` already reports one of these as
## present without ever creating it, and `create_alternative_tile` called
## with one is a no-op that returns the same id back), and a real render of
## an asymmetric probe tile confirmed the pixels actually move (a marked
## quadrant shifted from top-left to top-right under a raw FLIP_H value) --
## so `build_tile_set` needs no changes to register anything, and
## `EarthChunkManager._paint_snow_tile` can pass this function's return value
## straight through as `set_cell`'s fourth argument.
##
## Deliberately only TWO combinations -- identity and flip_h -- NOT the full
## eight-member orthogonal group TileSetAtlasSource also exposes via
## TRANSFORM_TRANSPOSE and TRANSFORM_FLIP_V. Checked directly, not assumed
## safe, by rendering real built band-9 tiles (the exact "puff nearly filling
## the cell" shapes this axis exists for) through all four orthogonal-group
## members side by side: transpose visibly distorts a wide, roughly-oval
## mound into a tall, narrow one -- swapping x/y rotates a shape's own aspect
## ratio, a much bigger and more obviously wrong change than mirroring it.
## Several bands' real content is markedly NOT top/bottom symmetric (band 9's
## built tiles measure top-half alpha mass roughly 30x their own bottom half,
## e.g. variant 0: 363.7 vs 10.3, variant 5: 374.2 vs 12.5) in a way a simple
## flip preserves -- a mirrored mound is still a mound, just facing the other
## way -- but a transpose does not: it turns "wide and short at the bottom"
## into "tall and narrow along one side", which reads as a different, wrong
## shape rather than the same puff seen differently.
##
## FOLLOW-UP -- FLIP_V removed too: originally included alongside FLIP_H on
## the reasoning above ("a mirrored mound is still a mound"), but that
## reasoning only actually holds for FLIP_H. Reported live, with a
## screenshot, after this axis had already shipped: "the bigger the snow
## tiles get the wronger they become". Investigated directly: NOT a
## residual-bleed regression (rendering every real (band,variant) tile at
## bands 7/8/9 -- the "bigger" tiles -- through the current pipeline and
## running the same connected-component check `_discard_disconnected_bleed`
## itself uses finds 29 of 30 tiles a single component, the one exception's
## stray fragment only 2.6% of its own dominant blob's size). It IS a real
## defect in FLIP_V specifically: a fresh sweep of top/bottom alpha-mass
## ratio through build_band_image, every band, all 10 variants each, finds
## real, substantial, per-band-CONSISTENT asymmetry from band 1 up (worst
## deviation-from-1 by band: 3.34, 6.86, 9.24, 2.53, 26.25, 9.27, 3.22, 2.38,
## 5.44, 69.51 for bands 0-9) -- and the DIRECTION flips partway through the
## ladder: bands 1-8 are bottom-heavy (a mound anchored low, tapering
## upward), band 9 is dramatically TOP-heavy (up to 69.5x -- the one band
## whose content is known to press UP past its own cell into row 8, see
## build_band_image's own EDGE FEATHER doc comment). FLIP_V inverts exactly
## this axis. A rendered side-by-side of real band 7/8/9 tiles through all
## four transforms confirmed this is not merely a number: FLIP_H siblings
## both still read as the same coherent mound facing a different way, but
## FLIP_V siblings at band 9 read as a visibly smaller, sparser patch
## floating away from the bottom of the tile with an empty gap above it --
## the tiles meant to show the FULLEST cover are exactly the ones a vertical
## flip damages most, which is the live report's "bigger... wronger" in one
## sentence. Left/right asymmetry was re-checked the same way and stayed
## comparatively safe (worst deviation-from-1 by band: 6.43, 4.98, 3.65,
## 4.04, 2.59, 2.74, 2.73, 2.50, 1.95, 1.68 for bands 0-9 -- an order of
## magnitude milder, and consistently one direction rather than flipping),
## so FLIP_H alone stays. See test_snow_layer.gd's own "per-tile transform"
## section for the full write-up and the regression tests
## (test_transform_never_flips_vertically,
## test_band_9_content_is_severely_top_bottom_asymmetric).
const _TRANSFORM_SALT := 4271

func transform_for(global_x: int, global_y: int) -> int:
	var combinations := [
		0,
		TileSetAtlasSource.TRANSFORM_FLIP_H,
	]
	return combinations[PixelNoise.range_index(_TRANSFORM_SALT, global_x, global_y, combinations.size())]


## Which band a tile shows, or -1 for bare ground.
##
## `depth` is how much snow is lying overall (see Snowfall), `tread` how much
## has been displaced by walking (see SnowTrail), and `onset_offset` this
## tile's own lead/lag on the field's coverage (see onset_offset_for) -- it is
## what turns one shared depth into a chunk that fills in tile by tile rather
## than snapping everywhere at once.
func band_for(depth: float, tread: float, onset_offset: float = 0.0) -> int:
	# A genuinely bare field (no snow has fallen ANYWHERE) stays bare even for
	# the most-leading tile -- onset is a lead/lag on real snow, not a way to
	# conjure some out of nothing.
	if depth <= 0.0:
		return -1
	var lying: float
	if depth >= 1.0:
		# Symmetric with the depth<=0.0 guard above: once the field is
		# GENUINELY fully snowed over, onset (a lead/lag on the CLIMB toward
		# full coverage -- see onset_offset_for) no longer has anything left
		# to lead or lag. Surfaced by raising DEPTH_BANDS 4 -> 25: at 4 bands
		# a whole band was 0.25 wide, comfortably more than ONSET_VARIANCE
		# (0.18), so a max-lagging tile's `depth + onset_offset` (0.82) still
		# happened to round up into the top band. At 25 bands a band is only
		# 0.04 wide, so that SAME 0.82 now lands 4 bands short of the top --
		# without this guard, a maximally-lagging tile would sit a few bands
		# below full FOREVER once depth pins at 1.0, rather than the lag
		# being a transient effect of an ongoing snowfall (see
		# test_onset_cannot_hide_snow_once_the_field_is_fully_covered).
		lying = 1.0
	else:
		lying = clampf(depth + onset_offset, 0.0, 1.0)
		if lying <= 0.0:
			return -1
	# Depth maps onto the bands, then treading knocks it down.
	var band := int(ceil(lying * float(DEPTH_BANDS))) - 1
	band -= int(round(clampf(tread, 0.0, 1.0) * TREAD_BANDS))
	return clampi(band, -1, DEPTH_BANDS - 1)


## -- a continuous base tint beneath the puff, so tiles meet edge to edge ----
##
## REAL, user-visible complaint, with a screenshot: a field of piled snow
## reads as a GRID of separate white blobs, each with a visible transparent
## gap to its neighbours on every side, not a continuous blanket. This is a
## real, correct description of a real architectural limit, not a bug in any
## of the fixes above: the illustrated puff `build_band_image` crops has REAL
## transparent padding around it within its own cell (deliberate, correct art
## -- see OVERLAY_COLUMNS' own doc comment), so two neighbouring tiles' puffs
## never actually touch. Every fix above (variant selection, bleed removal,
## the flip transform) operates entirely WITHIN one puff's own crop and
## cannot paint anything in the gap BETWEEN two tiles, because nothing is
## painted there at all -- there is no amount of per-puff cleanup that closes
## a gap between two SEPARATE puffs.
##
## The fix is a second, flat tint painted BENEATH the existing puff so a
## tile's own coverage reaches all four of its edges, closing the gap to its
## neighbours, while the puff keeps riding on top for real texture -- see
## `_composite_base_beneath`.
##
## WHERE this lives: baked directly into `build_band_image`'s own output
## (`_build_puff_image` + `_composite_base_beneath`, both feeding the same
## public `build_band_image`), not a second TileMapLayer/shader painted
## underneath, even though this codebase has real precedent for a separate
## shader-driven overlay layer (`GroundTint`, `SeasonalFoliage`; see
## `EarthChunkManager.set_snow_layer`'s own neighbourhood of overlay-layer
## setters). Two things rule that precedent out here rather than confirming
## it fits:
##
## 1. TESTABILITY. This project's own house convention for a canvas_item
## shader layer is "contract tests only -- the visual result can't be
## asserted headless" (see test_ground_tint.gd's own header comment) --
## GUT's headless runner has no GPU pixel readback. The actual claim this
## fix has to prove ("no fully-transparent pixel run along a shared tile
## border", "the puff stays visually distinguishable from the base") is a
## REAL PIXEL measurement, which only the CPU-side Image pipeline this file
## already uses can deliver in a real, run, deterministic test rather than a
## structural "the shader code contains this snippet" guard.
##
## 2. The band-driven design below (see `base_alpha_for_band`) needs no
## per-exact-tile-POSITION value at all -- only the tile's own `band`, which
## `build_tile_set` already bakes a fixed (DEPTH_BANDS x OVERLAY_COLUMNS)
## atlas for. A tint that DID need a genuinely continuous, unique-per-exact-
## position value could not be expressed by that finite, baked-once atlas
## (`build_tile_set` bakes 100 images ONE time and every tile of a given
## (band, variant) reuses the identical bitmap -- see that function's own
## doc comment) without an unbounded number of baked combinations, which
## WOULD be a real, concrete reason to prefer a shader layer instead. That
## case does not arise here: see `base_alpha_for_band`'s own doc comment for
## why `band` alone -- not the raw continuous depth+onset value -- is both
## sufficient and the provably safer choice.
##
## Given both, baking into the existing image pipeline is not merely the
## simpler option assumed sufficient -- it is the only one of the two that
## can actually be verified by the tests this fix needs.


## Cold, pale blue-white -- measured, not eyeballed: the average RGB of every
## near-opaque (alpha > 0.9) pixel across all ten of the deepest band's real
## built variants, i.e. the illustrated art's own real "fully covered" colour,
## sampled directly through `build_band_image` (post-resize, the same pixels a
## painted tile actually shows). Grounded in the real committed art rather
## than a guessed "snowy blue-white" so the base tint reads as the SAME snow,
## not a mismatched colour peeking out from underneath it.
const BASE_TINT_COLOR := Color(0.68, 0.745, 0.865)

## The base tint's own interior alpha at the first band beyond dusting (band
## 1) and at the deepest band (DEPTH_BANDS - 1) -- see `base_alpha_for_band`
## for the curve between them.
##
## Band 0 is deliberately excluded from this curve entirely (`base_alpha_for_
## band(0)` returns exactly 0.0, and `_composite_base_beneath` is a no-op at
## band 0) rather than given a very small value: band 0 is the sheet's own
## dusting rung, and `DUSTING_MAX_MEAN_ALPHA` is already pinned specifically
## against THIS band's own measured range (see that constant's own doc
## comment) precisely because a dusting is snow lying in the dips with real
## ground showing through, not a blanket -- see
## test_dusting_band_still_shows_real_transparent_gaps. Any base alpha at
## band 0, however small, would put a floor under band 0's own alpha and
## remove real gaps a dusting is supposed to keep.
##
## Values chosen so the tint stays clearly BELOW the puff's own near-opaque
## interior (measured: real painted puff content sits close to full alpha
## within its own shape, see BASE_TINT_COLOR's own >0.9 sampling threshold) at
## every band, so a base-filled gap and a puff-covered pixel remain visually
## distinct rather than the tint approaching the puff's own opacity and
## washing the two together -- see
## test_puff_detail_remains_distinguishable_over_the_base_tint, which checks
## this by real measured alpha range rather than by eye.
const BASE_TINT_MIN_ALPHA := 0.10
const BASE_TINT_MAX_ALPHA := 0.30

## How much of the interior curve's own value survives at a tile's outer edge
## -- see `_base_edge_alpha_for_band`. 0.5 halves the worst realistic
## adjacent-band step at the one place two tiles' base tints actually meet
## (their shared border), which is the whole point of feathering it at all:
## see test_base_edge_alpha_softens_the_interior_step, which confirms this is
## a real reduction against the SAME interior curve, not just a differently
## shaped one.
const BASE_EDGE_ALPHA_COMPRESSION := 0.5

## How far, in ART_TILE_SIZE pixels, `_composite_base_beneath` ramps from a
## tile's own compressed edge value in to its full interior value. 4 out of
## ART_TILE_SIZE=32 (12.5% in from each side) gives a real, visible gradient
## across the feather zone without eating the tile's own interior, where the
## curve's full value is what actually needs to show through gaps in the puff
## for the tint to read as tracking real depth rather than one flat wash.
const BASE_EDGE_FEATHER_PX := 4


## This band's own base tint alpha, BEFORE the per-tile edge feather in
## `_composite_base_beneath` -- a plain linear ramp from BASE_TINT_MIN_ALPHA
## at band 1 to BASE_TINT_MAX_ALPHA at the deepest band, climbing with depth
## the same direction the puff's own real coverage does (see
## test_base_alpha_increases_monotonically_from_band_1_up), and exactly 0.0 at
## band 0 (see BASE_TINT_MIN_ALPHA's own doc comment for why that band is
## excluded rather than merely small).
##
## Driven by `band` -- the SAME already-quantised value `build_band_image`
## uses to pick the puff -- rather than the raw continuous `depth +
## onset_offset` ("lying") value `band_for` computes on the way to it. This
## was investigated, not assumed: `build_tile_set` bakes one fixed image per
## (band, variant) pair ONCE and every tile of that pair reuses the identical
## bitmap for as long as the tile set lives, so a tint that needed a
## genuinely unique alpha per exact tile POSITION could not be baked into
## this atlas at all -- see this section's own header comment, "WHERE this
## lives", for the two real reasons that possibility is ruled out here rather
## than assumed away.
##
## Reusing `band` is not merely convenient, it is PROVABLY safe against the
## exact re-quantisation risk a coarser band-driven tint could otherwise
## reintroduce: `MAX_NEIGHBOUR_ONSET_STEP` (0.07) already sits under one
## band's own width (1.0 / DEPTH_BANDS = 0.1) -- confirmed by
## test_worst_realistic_neighbour_band_difference_is_at_most_one, which
## sweeps real `band_for`/`onset_offset_for` calls across a real range of
## depths and coordinates rather than trusting the arithmetic alone -- so two
## edge-adjacent tiles' bands can never differ by more than exactly one. The
## worst this curve's own re-quantisation can ever cost a real tile border is
## therefore bounded to ONE step of this curve (at most (BASE_TINT_MAX_ALPHA
## - BASE_TINT_MIN_ALPHA) / (DEPTH_BANDS - 2) alone, before
## `_base_edge_alpha_for_band`'s own compression shrinks it further) -- a
## small, known, one-band-wide quantity, not an unbounded "coarser gridline"
## risk.
func base_alpha_for_band(band: int) -> float:
	if band <= 0:
		return 0.0
	var clamped := clampi(band, 1, DEPTH_BANDS - 1)
	if DEPTH_BANDS <= 2:
		return BASE_TINT_MAX_ALPHA
	var t := float(clamped - 1) / float(DEPTH_BANDS - 2)
	return lerpf(BASE_TINT_MIN_ALPHA, BASE_TINT_MAX_ALPHA, t)


## This band's own base alpha at a tile's OUTER EDGE, where it actually meets
## a neighbour -- `base_alpha_for_band`'s own curve compressed toward the
## curve's midpoint by BASE_EDGE_ALPHA_COMPRESSION, so a real step between two
## adjacent bands (bounded to exactly one band, see `base_alpha_for_band`'s
## own doc comment) reads as a SOFTER step right at the border than it does
## through the tile's own interior.
##
## This is the "genuine edge-softening" a flat, uniform-alpha rectangle
## cannot provide on its own: two neighbours whose interiors differ by a full
## band's worth of curve would, painted as flat rectangles, meet at a hard,
## perfectly straight edge -- exactly the gridline complaint this whole
## section exists to fix, in a new form. Compressing toward the curve's own
## midpoint (rather than toward either endpoint) keeps the reduction
## symmetric regardless of which direction a real neighbour's band differs,
## since a single baked tile cannot know which side a given neighbour sits on
## -- see test_base_edge_alpha_softens_the_interior_step, which confirms the
## resulting edge-to-edge step is measurably smaller than the interior one,
## not merely reshaped.
##
## Band 0 still returns exactly 0.0 -- there is no edge to soften on a band
## that carries no base tint at all.
func _base_edge_alpha_for_band(band: int) -> float:
	if band <= 0:
		return 0.0
	var mid := (BASE_TINT_MIN_ALPHA + BASE_TINT_MAX_ALPHA) / 2.0
	return mid + (base_alpha_for_band(band) - mid) * BASE_EDGE_ALPHA_COMPRESSION


## Paints `BASE_TINT_COLOR` beneath `image`'s own existing content, in place,
## at an alpha that ramps from `_base_edge_alpha_for_band`'s compressed value
## at the image's outer edge to `base_alpha_for_band`'s full interior value
## over `BASE_EDGE_FEATHER_PX` pixels (same smoothstep ramp
## `_feather_crop_edges` uses, for the same reason: a linear ramp's kinked
## derivative rings under later resampling, though this tint is painted
## AFTER `build_band_image`'s own Lanczos resize, so that particular risk
## does not apply here -- smoothstep is used anyway for the same soft,
## continuous-derivative shape).
##
## A no-op at band 0 (`base_alpha_for_band`/`_base_edge_alpha_for_band` both
## return exactly 0.0 there, but this still short-circuits explicitly rather
## than relying on that, so `test_dusting_band_still_shows_real_transparent_
## gaps`'s byte-identical claim holds by construction rather than by a chain
## of zeros happening to multiply out to nothing).
##
## Standard "puff over base" alpha compositing (source-over): wherever the
## existing pixel is already opaque, the base contributes nothing visible
## (`out_a` saturates at the puff's own alpha, `inv` -> 0); wherever the puff
## is fully transparent, the pixel becomes the base tint alone at `base_a`.
func _composite_base_beneath(image: Image, band: int) -> void:
	if band <= 0:
		return
	var width := image.get_width()
	var height := image.get_height()
	var interior := base_alpha_for_band(band)
	var edge := _base_edge_alpha_for_band(band)
	for y in height:
		var edge_distance_y := mini(y, height - 1 - y)
		for x in width:
			var edge_distance_x := mini(x, width - 1 - x)
			var edge_distance := mini(edge_distance_x, edge_distance_y)
			var t := clampf(float(edge_distance) / float(BASE_EDGE_FEATHER_PX), 0.0, 1.0)
			var ramp := t * t * (3.0 - 2.0 * t)
			var base_a := lerpf(edge, interior, ramp)
			if base_a <= 0.0:
				continue
			var top := image.get_pixel(x, y)
			var out_a := top.a + base_a * (1.0 - top.a)
			if out_a <= 0.0:
				continue
			var inv := 1.0 - top.a
			image.set_pixel(x, y, Color(
				(top.r * top.a + BASE_TINT_COLOR.r * base_a * inv) / out_a,
				(top.g * top.a + BASE_TINT_COLOR.g * base_a * inv) / out_a,
				(top.b * top.a + BASE_TINT_COLOR.b * base_a * inv) / out_a,
				out_a
			))
