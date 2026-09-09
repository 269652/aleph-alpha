extends GutTest

## Real illustrated art for the boot intro splash (assets/sprites/intro.png)
## -- see docs/concept/intro_splash.md. Same "hand/AI-illustrated sheet ->
## SpriteSheetSlicer -> cached frames" shape as IllustratedWormSprite, but
## the sheet's own grid is NOT perfectly regular (AI-generated at
## 1983x793, not evenly divisible by its own 9 columns x 5 rows --
## confirmed with tools/probe_intro_sheet.gd), so this hand-measures the 5
## ROW bands (pinned constants) and reuses SpriteSheetSlicer.detect_frames
## for the columns within each band, rather than assuming arithmetic
## division the way the worm sheet's own (genuinely regular) grid can.
##
## Deliberately does NOT run frames through SpriteSheetSlicer.
## normalize_frames the way every other illustrated sheet in this codebase
## does: normalize_frames picks ONE shared scale from the WIDEST/TALLEST
## content bounding box across the frames it's given, and here the "ALEPH
## ALPHA" wordmark's own ink extent genuinely grows across the sequence --
## content-cropping and rescaling would make the globe itself appear to
## change size as the text builds in, which the source art's own
## consistent camera framing (see the intro-generation prompt) already
## avoids by construction. Frames are extracted as plain, un-rescaled
## regions instead.

const IntroSplashSheet = preload("res://src/rendering/intro_splash_sheet.gd")
const IntroSplashSequencer = preload("res://src/rendering/intro_splash_sequencer.gd")

var sheet: IntroSplashSheet


func before_each():
	sheet = IntroSplashSheet.new()


## A real cross-check, not two independently-hardcoded numbers that could
## silently drift apart -- IntroSplashSequencer.FRAME_COUNT is what
## actually decides how many frames get shown; this proves the sheet
## really produces exactly that many, not a number this test also has to
## remember to update by hand every time the sheet's own real grid changes.
func test_frame_count_matches_the_sequencer():
	assert_eq(sheet.generate_textures().size(), IntroSplashSequencer.FRAME_COUNT)


func test_every_frame_has_real_content():
	var frames := sheet.generate_textures()
	for i in frames.size():
		assert_true(_has_opaque_pixels(frames[i]), "frame %d is blank" % i)


## NOT the same corner-transparency check test_illustrated_worm_sprite.gd
## uses alongside its own magenta sweep -- confirmed by direct pixel probe
## that several real frames here (the light-streak/starfield reaching a
## cell's own edge) legitimately paint opaque content into their corners,
## unlike a worm silhouette drawn with generous blank padding around it.
## This sheet is meant to fill the WHOLE screen edge to edge, so a full
## sweep for any surviving OPAQUE MAGENTA pixel -- the thing that would
## actually look broken -- is the real invariant, and the only one a
## full-bleed sheet like this one can honestly assert.
func test_frames_have_no_leftover_magenta_background():
	var frames := sheet.generate_textures()
	for i in frames.size():
		var frame: Image = frames[i].get_image()
		var magenta_survivors := 0
		for y in frame.get_height():
			for x in frame.get_width():
				var c := frame.get_pixel(x, y)
				if c.a > 0.5 and c.r >= 0.85 and c.b >= 0.85 and c.g <= 0.15:
					magenta_survivors += 1
		assert_eq(magenta_survivors, 0, "frame %d: no opaque magenta pixel should survive chroma-keying" % i)


## The first frame (no wordmark yet) and the last frame (full wordmark,
## sparkle flourish) must genuinely differ -- a real multi-frame animation,
## not FRAME_COUNT copies of one drawing.
func test_first_and_last_frames_differ():
	var frames := sheet.generate_textures()
	assert_ne(
		frames[0].get_image().get_data(),
		frames[IntroSplashSequencer.FRAME_COUNT - 1].get_image().get_data()
	)


## Every one of the 32 frames must differ from its own immediate neighbour
## -- catches a slicing bug that accidentally duplicates a column/row
## boundary (e.g. an off-by-one that reads the same cell twice) even if
## the first-vs-last check above would not.
func test_consecutive_frames_differ():
	var frames := sheet.generate_textures()
	for i in range(frames.size() - 1):
		assert_ne(
			frames[i].get_image().get_data(), frames[i + 1].get_image().get_data(),
			"frame %d and %d are identical" % [i, i + 1]
		)


func test_frames_are_cached_not_rebuilt_per_call():
	var a := sheet.generate_textures()
	var b := sheet.generate_textures()
	assert_same(a[0], b[0])


## Bug #6 (2026-09-09): every one of the 32 frames must be the exact same
## pixel size. IntroSplash's own TextureRect (EXPAND_IGNORE_SIZE +
## STRETCH_KEEP_ASPECT_COVERED, see scenes/intro_splash.gd) scales and
## re-centers EACH frame independently, driven by that frame's own size --
## so if frame sizes differ even by a couple pixels, the effective
## on-screen scale factor and crop-center shift frame to frame, magnified
## by the real ~5.5x this sheet gets stretched by at the project's default
## 1280x720 viewport (project.godot). That reads as visible "wobble".
##
## Confirmed red against the unfixed per-frame CONTENT-based crop
## (SpriteSheetSlicer.detect_frames called once per frame, independently):
## real measured widths ranged 232-234px and heights stepped 181/183/182/
## 182px across the 32 frames (throwaway verification probe, since
## deleted -- mirroring how the prior 5 intro-splash bugs in this file's
## own git history were each verified against real numbers, not trusted
## from a code trace alone). Left edges were separately confirmed to
## already be a stable, fixed 8-column grid (row 0, 2, and 3 independently
## re-detect the IDENTICAL lefts array; only row 1 -- the one row with
## both the light-streak sweep and the first wordmark letters already
## present -- drifted by 1px at a single column), so the crop instability
## was real but entirely in the RIGHT edge/width (content-driven) and, at
## the 3 row-transition points, in height (hand-measured _ROW_BANDS
## differing by 1-2px row to row) -- never in the left edge/column grid
## itself.
func test_every_frame_is_the_same_size():
	var frames := sheet.generate_textures()
	var first_size := frames[0].get_image().get_size()
	for i in frames.size():
		var size := frames[i].get_image().get_size()
		assert_eq(
			size,
			first_size,
			"frame %d is %s, expected %s (frame 0's size) -- unstable geometry reads as wobble once stretched to fill a real viewport" % [i, size, first_size]
		)


## Real, measured safety margins -- see this file's own header doc comment
## and docs/concept/intro_splash.md's own pass history for why a SINGLE
## fixed crop window (not per-frame content detection) is the whole point
## here: _FRAME_WIDTH/_FRAME_HEIGHT must both comfortably contain every
## real column/row's own measured content AND stay comfortably inside the
## tightest real gap to the next column/row, or a crop would either clip
## real content or bleed into a neighbour. Confirmed against a rendered
## swatch at the width chosen (a real visual check, not just these
## numbers alone -- tools/probe_intro_sheet.gd's own crop-preview pass,
## since deleted, mirroring how the eleventh pass's own numbers were
## verified).
func test_frame_width_fits_within_the_tightest_real_column_pitch():
	var tightest_pitch := 999999
	for i in IntroSplashSheet._COLUMN_LEFTS.size():
		var next_left: int = (
			IntroSplashSheet._COLUMN_LEFTS[i + 1] if i + 1 < IntroSplashSheet._COLUMN_LEFTS.size()
			else _sheet_width()
		)
		var pitch: int = next_left - IntroSplashSheet._COLUMN_LEFTS[i]
		tightest_pitch = mini(tightest_pitch, pitch)
	assert_lt(
		IntroSplashSheet._FRAME_WIDTH, tightest_pitch,
		"a frame width at or past the tightest real column pitch would bleed into the next column"
	)


func test_frame_height_fits_within_the_tightest_real_row_gap():
	for i in IntroSplashSheet._ROW_BANDS.size() - 1:
		var this_row_top: int = IntroSplashSheet._ROW_BANDS[i].x
		var next_row_top: int = IntroSplashSheet._ROW_BANDS[i + 1].x
		assert_lt(
			this_row_top + IntroSplashSheet._FRAME_HEIGHT, next_row_top,
			"row %d's own fixed-height crop would bleed into row %d's content" % [i, i + 1]
		)


func _sheet_width() -> int:
	return SpriteSheetLoader.load_image("res://assets/sprites/intro.png").get_width()


const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")


func _has_opaque_pixels(texture: Texture2D) -> bool:
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false
