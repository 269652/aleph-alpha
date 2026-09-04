extends RefCounted

## Cuts a strip of illustrated frames apart and lines them up.
##
## The illustrated sheets (see IllustratedAnimalSprite, IllustratedFlowerHead)
## are drawn as horizontal strips: a row of poses or bloom stages side by side,
## separated by a divider line. This finds the frames in such a strip and
## normalizes each one onto a shared canvas.
##
## Two steps, kept separate because callers slice several bands out of one
## sheet before normalizing them together:
##
## 1. `detect_frames` -- where the frames are, within a band of rows.
## 2. `normalize_frames` -- each frame cropped to its drawing, scaled to fit a
##    shared canvas, and stood on a shared BASELINE.
##
## The baseline is the whole point of the second step. Frames drawn by hand
## sit at different heights and sizes within their cells, and an animation
## whose subject bobs up and down between frames reads as broken. Standing
## every frame's feet on the same line makes a strip of separate drawings play
## as one animation.

## What counts as empty when looking for the edges of a drawing.
##
## Overridable per sheet: some sheets carry a soft vignette that never quite
## reaches zero alpha, and would otherwise measure as content everywhere.
const DEFAULT_ALPHA_THRESHOLD := 0.3

## How light a pixel must be to read as part of a DIVIDER rather than as
## drawing. The sheets separate their frames with a pale line rather than with
## empty space, so "background" here means transparent OR near-white.
##
## Overridable per sheet: most sheets divide with a near-white line, but some
## measure considerably darker.
const DEFAULT_DIVIDER_GRAY_MIN := 0.7

## How colourful a pale pixel may be and still read as divider. A pale drawing
## -- bone, cream fur, a white blossom -- carries a tint that a printed grey
## line does not.
const DIVIDER_MAX_SATURATION := 0.12

## The narrowest run of columns that can be a frame. Anything thinner is a
## speck of noise beside a divider rather than a drawing.
const DEFAULT_MIN_FRAME_WIDTH := 8

## The narrowest run of divider columns that actually separates two frames.
## One column is enough for a drawn line; the parameter exists because a sheet
## with dithered edges may need more before its frames stop bleeding together.
const DEFAULT_MIN_DIVIDER_WIDTH := 1


## Whether this pixel is background: either transparent, or part of the pale
## divider line between frames.
static func is_empty(
	color: Color,
	alpha_threshold: float = DEFAULT_ALPHA_THRESHOLD,
	divider_gray_min: float = DEFAULT_DIVIDER_GRAY_MIN
) -> bool:
	if color.a < alpha_threshold:
		return true
	return (
		color.r >= divider_gray_min
		and color.g >= divider_gray_min
		and color.b >= divider_gray_min
		and color.s <= DIVIDER_MAX_SATURATION
	)


## A copy of `image` with every pixel within `tolerance` of `key` (each of
## R/G/B independently, ignoring alpha) turned fully transparent.
##
## Sheets cut out on a solid chroma-key colour (magenta, by this project's
## prompts) rather than real transparency: keying them up front lets
## detect_frames/normalize_frames treat the ground as the low-alpha
## background they already understand, with no "or matches this colour"
## branch anywhere downstream. Per-channel rather than one combined
## distance, so a saturated key can use a generous tolerance for the
## anti-aliased blend at a drawing's silhouette without also swallowing a
## pale, low-saturation drawing colour of similar overall brightness.
static func chroma_keyed(image: Image, key: Color, tolerance: float) -> Image:
	var keyed := image.duplicate()
	if keyed.get_format() != Image.FORMAT_RGBA8:
		keyed.convert(Image.FORMAT_RGBA8)
	for y in keyed.get_height():
		for x in keyed.get_width():
			var c: Color = keyed.get_pixel(x, y)
			if (
				absf(c.r - key.r) <= tolerance
				and absf(c.g - key.g) <= tolerance
				and absf(c.b - key.b) <= tolerance
			):
				keyed.set_pixel(x, y, Color(0, 0, 0, 0))
	return keyed


## The frames in the band of rows between `top_y` and `bottom_y`.
##
## Scans column by column: a column with nothing but background in it is a
## divider, and the runs of columns between dividers are the frames. Returned
## as full rectangles carrying the band's own rows, so normalize_frames has
## everything it needs without being told the band again.
func detect_frames(
	image: Image,
	top_y: int,
	bottom_y: int,
	min_frame_width: int = DEFAULT_MIN_FRAME_WIDTH,
	min_divider_width: int = DEFAULT_MIN_DIVIDER_WIDTH,
	alpha_threshold: float = DEFAULT_ALPHA_THRESHOLD,
	divider_gray_min: float = DEFAULT_DIVIDER_GRAY_MIN
) -> Array[Rect2i]:
	var frames: Array[Rect2i] = []
	if image == null:
		return frames
	var top: int = clampi(top_y, 0, image.get_height())
	var bottom: int = clampi(bottom_y, top, image.get_height())
	if bottom <= top:
		return frames

	var start := -1
	var empty_run := 0
	for x in image.get_width():
		if _column_is_empty(image, x, top, bottom, alpha_threshold, divider_gray_min):
			empty_run += 1
			continue
		if start >= 0 and empty_run >= min_divider_width:
			var width := x - empty_run - start
			if width >= min_frame_width:
				frames.append(Rect2i(start, top, width, bottom - top))
			start = -1
		empty_run = 0
		if start < 0:
			start = x
	if start >= 0:
		var last_width := image.get_width() - empty_run - start
		if last_width >= min_frame_width:
			frames.append(Rect2i(start, top, last_width, bottom - top))
	return frames


## Each frame cropped to its drawing, scaled to fit `canvas_size`, and stood
## with its feet on `baseline_y`.
##
## Aspect is preserved and the drawing is centred horizontally, so a frame
## never stretches; only its position and scale change. A drawing taller or
## wider than the canvas is scaled down to fit, which is what keeps a strip of
## hand-drawn frames of slightly different sizes reading as one subject.
func normalize_frames(
	image: Image,
	frames: Array,
	canvas_size: Vector2i,
	baseline_y: int,
	alpha_threshold: float = DEFAULT_ALPHA_THRESHOLD,
	divider_gray_min: float = DEFAULT_DIVIDER_GRAY_MIN
) -> Array[Image]:
	var normalized: Array[Image] = []
	if image == null:
		return normalized

	# One scale for the whole set, not one per frame.
	#
	# Scaling each frame to fill the canvas on its own equalizes them: every
	# drawing wider than the canvas aspect ends up exactly canvas-wide, and a
	# walk cycle and an idle pose drawn at quite different sizes come out
	# identical. That loses both the relative sizes WITHIN a cycle -- a
	# stretched-out stride really is longer than a gathered one -- and the
	# difference BETWEEN two actions drawn on different sheets, which callers
	# rely on to rescale a marker when its action changes.
	var contents: Array[Rect2i] = []
	var widest := 1
	var tallest := 1
	for frame in frames:
		var content := _content_rect(image, frame, alpha_threshold, divider_gray_min)
		contents.append(content)
		if content.size.x > 0 and content.size.y > 0:
			widest = maxi(widest, content.size.x)
			tallest = maxi(tallest, content.size.y)
	var scale: float = minf(
		float(canvas_size.x) / float(widest), float(baseline_y) / float(tallest)
	)

	for index in contents.size():
		var content: Rect2i = contents[index]
		if content.size.x <= 0 or content.size.y <= 0:
			continue
		var drawing := image.get_region(content)
		# The canvas below is RGBA8, and blit_rect refuses to mix formats --
		# a sheet loaded as anything else (RGB8, indexed) fails at the last
		# step otherwise.
		if drawing.get_format() != Image.FORMAT_RGBA8:
			drawing.convert(Image.FORMAT_RGBA8)
		_clear_background(drawing, alpha_threshold, divider_gray_min)

		var width := maxi(1, int(round(float(content.size.x) * scale)))
		var height := maxi(1, int(round(float(content.size.y) * scale)))
		drawing.resize(width, height, Image.INTERPOLATE_LANCZOS)

		var canvas := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
		var left := (canvas_size.x - width) / 2
		# Feet on the baseline, not the middle of the canvas: this is the whole
		# point of normalizing, and it is what stops an animation bobbing.
		var top := baseline_y - height
		canvas.blit_rect(drawing, Rect2i(0, 0, width, height), Vector2i(left, top))
		normalized.append(canvas)
	return normalized


## The box the actual drawing occupies inside `rect`, ignoring background and
## divider pixels around it.
func _content_rect(
	image: Image, rect: Rect2i, alpha_threshold: float, divider_gray_min: float
) -> Rect2i:
	var clipped := rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return Rect2i(rect.position, Vector2i.ZERO)
	var left: int = clipped.position.x + clipped.size.x
	var right: int = clipped.position.x - 1
	var top: int = clipped.position.y + clipped.size.y
	var bottom: int = clipped.position.y - 1
	for y in range(clipped.position.y, clipped.position.y + clipped.size.y):
		for x in range(clipped.position.x, clipped.position.x + clipped.size.x):
			if is_empty(image.get_pixel(x, y), alpha_threshold, divider_gray_min):
				continue
			left = mini(left, x)
			right = maxi(right, x)
			top = mini(top, y)
			bottom = maxi(bottom, y)
	if right < left or bottom < top:
		return Rect2i(clipped.position, Vector2i.ZERO)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


## Makes the background of a cut-out frame actually transparent.
##
## The sheets are drawn on a pale ground rather than on nothing, so a frame cut
## straight out carries that ground with it and composites as a pale box around
## the drawing.
func _clear_background(
	drawing: Image, alpha_threshold: float, divider_gray_min: float
) -> void:
	for y in drawing.get_height():
		for x in drawing.get_width():
			if is_empty(drawing.get_pixel(x, y), alpha_threshold, divider_gray_min):
				drawing.set_pixel(x, y, Color(0, 0, 0, 0))


func _column_is_empty(
	image: Image, x: int, top: int, bottom: int, alpha_threshold: float, divider_gray_min: float
) -> bool:
	for y in range(top, bottom):
		if not is_empty(image.get_pixel(x, y), alpha_threshold, divider_gray_min):
			return false
	return true
