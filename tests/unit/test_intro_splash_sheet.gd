extends GutTest

## Real illustrated art for the boot intro splash (assets/sprites/intro.png)
## -- see docs/concept/intro_splash.md. Same "hand/AI-illustrated sheet ->
## SpriteSheetSlicer -> cached frames" shape as IllustratedWormSprite, but
## the sheet's own grid is NOT perfectly regular (AI-generated at
## 1983x793, not evenly divisible by the prompted 8 columns x 4 rows --
## confirmed with tools/probe_intro_sheet.gd), so this hand-measures the 4
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

var sheet: IntroSplashSheet


func before_each():
	sheet = IntroSplashSheet.new()


func test_frame_count_matches_the_sequencer():
	assert_eq(sheet.generate_textures().size(), 32)


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
## globe rotated) must genuinely differ -- a real 32-frame animation, not
## 32 copies of one drawing.
func test_first_and_last_frames_differ():
	var frames := sheet.generate_textures()
	assert_ne(frames[0].get_image().get_data(), frames[31].get_image().get_data())


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


func _has_opaque_pixels(texture: Texture2D) -> bool:
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false
