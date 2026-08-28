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

## The illustrated coverage sheet: a 5-column x 5-row contact sheet, each
## cell one hand/AI-illustrated coverage stage (see DEPTH_BANDS below, and
## OVERLAY_BAND_CELLS for how those 25 cells map onto depth bands).
##
## Declared before DEPTH_BANDS, which is DERIVED from these -- GDScript const
## expressions can't reference a const declared later in the same file (see
## IllustratedCharacterSprite.HERO_COMPOSITE_BACKGROUND_FLOOD_STEP_TOLERANCE's
## own doc comment for the same constraint hit there).
const OVERLAY_PATH := "res://assets/sprites/terrain/snowoverlay.png"
const OVERLAY_COLUMNS := 5
const OVERLAY_ROWS := 5

## How many depths of cover there are, from a dusting to full.
##
## Ground goes bare, dusted, covered, deep -- rather than snapping between two
## states, which is what makes a snowfall something you watch arrive.
##
## Used to be 4 hand-picked procedural bands; now it is the real illustrated
## sheet's own frame count (see OVERLAY_COLUMNS/OVERLAY_ROWS and
## assets/sprites/terrain/snowoverlay.png, a 5x5 contact sheet of 25
## real coverage stages) -- a tile's own visible transition now has 25 real
## rungs instead of 4, closing the "hard-cuts between bands" gap
## docs/progress.md flagged as the one thing left undone in snow's own
## spreading fix.
const DEPTH_BANDS := OVERLAY_COLUMNS * OVERLAY_ROWS

## Real measured Y ranges (art pixels of the SOURCE sheet, half-open [a, b))
## for each of the sheet's 5 rows -- NOT an even 1086/5 (217.2px) grid.
##
## The sheet is a contact sheet with a ~3-6px near-opaque near-white DIVIDER
## LINE baked in between rows (a generation artifact, not intended snow
## texture), and those lines sit at increasingly early offsets the deeper
## into the sheet you go -- measured directly (a full-width/min-across-all-
## 5-columns alpha scan, since a real divider spans every column
## simultaneously while real snow content only lights up individual cells):
## the row0/row1 divider centers at y~208.5, row1/row2 at y~416.5, row2/row3
## at y~624, row3/row4 at y~831 -- versus a naive 217.2px-per-row grid, which
## would put those dividers 9 / 18 / 28 / 38px LATER and slice a crop
## boundary right through the middle of each one. Using a naive uniform grid
## here bakes a stray light border line into a sliced tile and crops away
## real content from the row below the divider. Each band below stops with a
## few pixels of margin clear of its neighbouring divider's own antialiased
## fade (measured: alpha is already back under 0.05 a few pixels past every
## boundary printed above).
const OVERLAY_ROW_BANDS: Array[Vector2i] = [
	Vector2i(5, 205), Vector2i(213, 412), Vector2i(421, 619), Vector2i(629, 826), Vector2i(836, 1079)
]

## Real measured X ranges for each of the sheet's 5 columns -- much closer to
## an even 1448/5 (289.6px) grid than the rows are (measured column divider
## centers: x~291, ~579, ~867.5, ~1156, all within 2px of the naive
## floor-based boundaries), but still given as measured bands rather than
## computed, so a column crop never straddles its own divider line either.
const OVERLAY_COLUMN_BANDS: Array[Vector2i] = [
	Vector2i(5, 288), Vector2i(294, 577), Vector2i(583, 865), Vector2i(871, 1153), Vector2i(1160, 1442)
]

## Which (column, row) sheet cell each depth band draws, ascending from
## least to most coverage.
##
## NOT row-major, and not the "frame 0 = top-left, frame 24 = bottom-right"
## reading order a contact sheet might suggest at a glance: the sheet's real
## mean coverage increases along BOTH axes AT ONCE, a genuine diagonal
## gradient rather than a left-to-right-then-wrap one -- row 0's own
## rightmost cell (col 4) already reads MORE covered (mean alpha 0.22) than
## row 1's own leftmost cell (col 0, mean alpha 0.06), so naively reading the
## sheet row-major would make band 5 LESS covered than band 4, breaking
## band_for's whole contract (more depth never gets a shallower band -- see
## test_deeper_snow_is_whiter). Measured directly instead: mean alpha of
## every one of the 25 real cropped cells (see _cropped_cell), sorted
## strictly ascending (confirmed strictly monotonic, no ties, and mean
## whiteness*alpha sorts to the identical order) -- least-covered
## (row 0, col 0, mean alpha ~0.01) through fullest (row 4, col 4, mean alpha
## ~0.92).
const OVERLAY_BAND_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1),
	Vector2i(3, 0), Vector2i(0, 2), Vector2i(2, 1), Vector2i(4, 0), Vector2i(1, 2),
	Vector2i(0, 3), Vector2i(3, 1), Vector2i(2, 2), Vector2i(4, 1), Vector2i(1, 3),
	Vector2i(3, 2), Vector2i(0, 4), Vector2i(2, 3), Vector2i(4, 2), Vector2i(1, 4),
	Vector2i(3, 3), Vector2i(2, 4), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4),
]

## A dusting must let its ground through; full cover must not.
##
## Re-derived for the real illustrated sheet (was 0.35 / 0.99 against the old
## procedural bands' own 0.28 / 1.00): the real least-covered cell (row 0,
## col 0) measures mean alpha ~0.010 -- far more transparent than the old
## procedural dusting ever was, because it is real hand-illustrated frost
## rather than a coverage-percentage dither, so the ceiling drops with it.
## The real fullest cell (row 4, col 4) measures mean alpha ~0.922 -- short
## of the old bands' literal 1.00 (those were painted fully opaque by
## construction), but still comfortably "buries the ground" in the sense
## this test cares about, so the floor drops to match. Both given margin
## either side of their measured value for the Lanczos resize's own small
## averaging effect (see build_band_image).
const DUSTING_MAX_MEAN_ALPHA := 0.06
const FULL_COVER_MIN_MEAN_ALPHA := 0.80

## How much a fully trodden tile drops in depth, as a fraction of
## DEPTH_BANDS rather than a literal band count.
##
## Walking PACKS snow rather than clearing it: a trail should read as tracks
## through a field, not as a trench dug to the soil. Only where the cover was
## thin to begin with does a boot reach the ground. The ORIGINAL intent was a
## literal `2.0` out of DEPTH_BANDS=4 -- half the visible depth range packed
## down by a full tread. A literal `2.0` left unchanged at DEPTH_BANDS=25
## would only drop 2/25 = 8% of the range, a much weaker footprint than
## before purely because the band count grew, not because the intended
## packing amount changed. Expressing it as a fraction of DEPTH_BANDS instead
## preserves the same "packs down about half the visible range" behaviour at
## any band count -- confirmed by test_a_footprint_in_a_dusting_shows_the_
## ground and test_a_single_pass_does_not_clear_deep_snow, which both still
## pass unchanged at DEPTH_BANDS=25 because the ratio, not the literal
## number, is what those tests actually depend on.
const TREAD_BANDS := float(DEPTH_BANDS) / 2.0

## The tile set: one tile per depth band.
func build_tile_set() -> TileSet:
	var art := TerrainRenderer.ART_TILE_SIZE
	var sheet := Image.create(DEPTH_BANDS * art, art, false, Image.FORMAT_RGBA8)
	for band in DEPTH_BANDS:
		sheet.blit_rect(
			build_band_image(band), Rect2i(0, 0, art, art), Vector2i(band * art, 0)
		)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(sheet)
	source.texture_region_size = Vector2i(art, art)
	for band in DEPTH_BANDS:
		source.create_tile(Vector2i(band, 0))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(art, art)
	tile_set.add_source(source, 0)
	return tile_set


## One band's tile: a real square crop of OVERLAY_PATH's matching cell,
## downscaled to ART_TILE_SIZE.
##
## Replaces the old per-pixel procedural paint (noise-picked coverage mask +
## per-block grain + a flat blue-white shade curve) entirely -- the real
## sheet's own pixels already carry coverage, grain and a faint blue tint
## (see the sheet's own doc comment on OVERLAY_BAND_CELLS), so there is
## nothing left for a synthetic mask to add. See build_tile_set for why this
## being called 25 times is still a one-time cost, not a runtime one.
##
## Lanczos, not nearest-neighbour, for the downscale: this is shrinking a
## ~200px source crop down to ART_TILE_SIZE (32 at the current
## DETAIL_MULTIPLIER), the same direction IllustratedTerrainSprite/
## TerrainRenderer._normalized_for_compositing already establishes Lanczos
## for in this exact codebase -- nearest-neighbour is the right call for
## UPSCALING small procedural art (see TerrainRenderer._blit_tile), but
## aliases fine illustrated per-pixel detail into visible "static" when
## SHRINKING (see _normalized_for_compositing's own doc comment for the
## measured, reported bug that convention fixed). This snow art is exactly
## the kind of fine illustrated detail (lumpy cloud-shaped patches) that bug
## was about.
func build_band_image(band: int) -> Image:
	var art := TerrainRenderer.ART_TILE_SIZE
	var clamped := clampi(band, 0, DEPTH_BANDS - 1)
	var cell: Vector2i = OVERLAY_BAND_CELLS[clamped]
	var cropped := _cropped_cell(cell.x, cell.y)
	if cropped.get_format() != Image.FORMAT_RGBA8:
		cropped.convert(Image.FORMAT_RGBA8)
	cropped.resize(art, art, Image.INTERPOLATE_LANCZOS)
	return cropped


## The real, loaded sheet image -- read from disk once and shared by every
## SnowLayer instance (mirrors IllustratedTerrainSprite._frame_cache/
## IllustratedCharacterSprite._head_sheet's own "load once, reuse forever"
## convention: the sheet's pixels never change between instances or tests).
static var _overlay_sheet_image: Image = null


func _overlay_sheet() -> Image:
	if _overlay_sheet_image == null:
		_overlay_sheet_image = SpriteSheetLoader.load_image(OVERLAY_PATH)
	return _overlay_sheet_image


## A real, square, border-free crop of sheet cell (column, row) -- the
## largest square that fits centered within that cell's own measured content
## band (OVERLAY_ROW_BANDS x OVERLAY_COLUMN_BANDS), which is itself already
## clear of the sheet's own divider lines (see those constants' own doc
## comments). The source cell is a landscape rectangle (~283px wide x
## ~200-243px tall), not a square, so this crops to a centered square rather
## than stretching non-uniformly onto ART_TILE_SIZE's own square canvas,
## which would squash every illustrated patch shape sideways.
func _cropped_cell(column: int, row: int) -> Image:
	var row_band: Vector2i = OVERLAY_ROW_BANDS[row]
	var column_band: Vector2i = OVERLAY_COLUMN_BANDS[column]
	var height := row_band.y - row_band.x
	var width := column_band.y - column_band.x
	var side := mini(width, height)
	var center_x := (column_band.x + column_band.y) / 2
	var center_y := (row_band.x + row_band.y) / 2
	var rect := Rect2i(center_x - side / 2, center_y - side / 2, side, side)
	return _overlay_sheet().get_region(rect)


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
const ONSET_VARIANCE := 0.18
const _ONSET_SALT := 5303

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
const MAX_NEIGHBOUR_ONSET_STEP := 0.05


## This tile's own onset offset, in [-ONSET_VARIANCE, ONSET_VARIANCE] --
## seeded from its GLOBAL tile coordinates (not chunk-local, so the pattern
## doesn't repeat or seam at chunk boundaries) via PixelNoise rather than
## Godot's own `hash()`, which correlates neighbouring inputs (see
## PixelNoise's doc comment).
##
## Sampled from a SMOOTH field at ONSET_DRIFT_TILES tiles per lift rather
## than rolled per tile, so the bare/dusted boundary reads as a meandering
## snow line rather than as grid squares (see ONSET_DRIFT_TILES).
func onset_offset_for(global_x: int, global_y: int) -> float:
	var drift := PixelNoise.smooth(
		_ONSET_SALT,
		float(global_x) / ONSET_DRIFT_TILES,
		float(global_y) / ONSET_DRIFT_TILES
	)
	return lerpf(-ONSET_VARIANCE, ONSET_VARIANCE, drift)


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
