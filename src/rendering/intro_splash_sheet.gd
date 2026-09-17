extends RefCounted

## Real illustrated art for the boot intro splash (see
## docs/concept/intro_splash.md, IntroSplashSequencer, scenes/
## intro_splash.gd).
##
## assets/sprites/intro.png is a CONTACT SHEET, 1672x941: a 20-column x
## 6-row grid of 120 frames exported straight out of the source animation,
## with the export tool's own chrome drawn on top of it -- a light-grey grid
## line between every pair of cells, and each cell's own timestamp ("0.00s"
## through "4.96s") burned into its top-left corner. Those timestamps are
## 1/24 s apart, which is where IntroSplashSequencer.FPS comes from: this
## sheet states its own frame rate, it is not a style choice any more.
##
## The chrome matters to the slicing in two different ways, and they pull in
## opposite directions:
##
##  - The GRID LINES are not art. A crop that includes one shows a pale bar
##    down the edge of the frame, so every crop below stays strictly INSIDE
##    the lines (see _COLUMN_INTERIORS/_ROW_INTERIORS, measured from the
##    real lines, and test_no_frame_carries_a_slice_of_the_grid_line).
##  - The TIMESTAMPS are kept. They sit on top of real frame content rather
##    than in a margin of their own -- the starfield runs edge to edge under
##    them -- so cropping them away would cut the top ~14% off every frame.
##    Asked directly, when offered the choice: "Just crop with timestamp".
##    They also turn out to be the single best alignment witness this sheet
##    has (see test_every_frame_lands_its_timestamp_label_on_the_same_rows).
##
## This replaced an earlier, completely different sheet (1983x793, an 8x5
## grid of 40 frames on a MAGENTA background with real gutters between
## cells). Nothing about the old one survives: there is no magenta on this
## sheet at all, so there is no chroma-key or despill pass here any more --
## the background is opaque black space, and it is meant to stay that way.
## See docs/concept/intro_splash.md's "Re-measuring again: a contact
## sheet, not a sprite sheet".
##
## Every one of the 120 frames is cropped to the SAME fixed-size window
## (_FRAME_WIDTH x _FRAME_HEIGHT) -- deliberately NOT SpriteSheetSlicer
## .detect_frames' own per-frame CONTENT-based crop, which this file used
## until bug #6 (2026-09-09). That crop measured each frame's own content
## boundary independently, and a couple of pixels of instability, magnified
## by the display upscale, read on screen as "wobble". A single fixed window
## removes that at the source. See test_every_frame_is_the_same_size.
##
## Frames are extracted as PLAIN regions, never run through
## SpriteSheetSlicer.normalize_frames: that function picks ONE shared scale
## from the widest content across the frames it is given, and here the globe
## grows and the "aleph alpha" wordmark builds in, so normalizing would make
## the globe itself appear to change size. Do NOT reintroduce it -- this is
## a deliberate divergence from every other illustrated-sheet consumer, not
## an oversight.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_PATH := "res://assets/sprites/intro.png"

## The x of each column's crop window, and the y of each row's -- measured
## from the real file with tools/probe_intro_sheet.gd, never assumed by
## arithmetic division. The grid does not divide evenly (1672/20 = 83.6,
## 941/6 = 156.8), the grey lines are 1-3px wide and not evenly spaced, and
## the cells themselves therefore differ in width by up to 4px.
##
## Horizontally each window is CENTRED in its own cell: the globe sits at
## its cell's middle, so anchoring at the left edge instead would shift it
## by up to 2px from column to column -- reintroducing, in a new form,
## exactly the frame-to-frame wobble a fixed window exists to remove.
##
## Vertically each window is anchored to where the ART actually starts,
## which is NOT simply "just below the line above". Row 0 has no grid line
## above it at all -- its cell is flush with the sheet's own top edge --
## while every other row's cell begins ~1.5px inside the line above it, so
## a crop anchored on the raw inter-line span puts row 0's content 1px
## higher than the other five. That is measured, not theorised: the export
## draws each cell's timestamp at a constant offset below its own cell top,
## and row 0's landed on frame row 11 where every other row's landed on 10.
## +1 on row 0 alone puts all six on the same row. See
## test_every_frame_lands_its_timestamp_label_on_the_same_rows, which is
## the direct proof and would fail the moment any of these drifts.
const _COLUMN_WINDOW_LEFTS: Array[int] = [
	1, 85, 168, 252, 337, 420, 503, 587, 671, 755,
	839, 923, 1008, 1092, 1175, 1258, 1342, 1426, 1510, 1593,
]
const _ROW_WINDOW_TOPS: Array[int] = [1, 155, 309, 463, 617, 771]

## ONE fixed window, shared by all 120 frames -- sized to the SMALLEST cell
## on the sheet so it fits inside every one of them and can never pull in
## the grid line beside it. The narrowest column is the last, which the
## sheet's own right edge cuts short at 79px; the shortest row is 151px.
## Verified against the real lines by
## test_no_frame_carries_a_slice_of_the_grid_line (on the built frames, not
## on this arithmetic) rather than asserted in this comment -- CLAUDE.md: a
## tuned value is a tested function or a test-pinned constant, never an
## eyeballed comment.
const _FRAME_WIDTH := 79
const _FRAME_HEIGHT := 151

static var _frame_cache: Array[ImageTexture] = []


## Every frame in play order (row 0 left-to-right, then row 1, ...),
## sliced once and cached thereafter.
func generate_textures() -> Array[ImageTexture]:
	if _frame_cache.is_empty():
		_frame_cache = _build_textures()
	return _frame_cache


func _build_textures() -> Array[ImageTexture]:
	var image := SpriteSheetLoader.load_image(_SHEET_PATH)
	if image == null:
		return []
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
	var textures: Array[ImageTexture] = []
	for top in _ROW_WINDOW_TOPS:
		for left in _COLUMN_WINDOW_LEFTS:
			textures.append(
				ImageTexture.create_from_image(
					image.get_region(Rect2i(left, top, _FRAME_WIDTH, _FRAME_HEIGHT))
				)
			)
	return textures
