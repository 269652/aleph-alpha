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
## Reported live, repeatedly, as "Still at 1fps": a --solo boot instrumented
## end to end traced its own ~52-88s real cost to functions in THIS file --
## every one of them a plain GDScript double for calling Image.get_pixel/
## set_pixel once per pixel. Fixed as one pass over the image's own raw
## PackedByteArray (get_data/create_from_data, 4 bytes/pixel, R,G,B,A
## order) -- comparing/writing raw 0-255 byte values has the exact same
## tolerance semantics as the original 0.0-1.0 float compare (both sides
## scaled by the same 255).
##
## A real trap along the way, worth naming so it isn't repeated: a first
## pass at this factored the "is this pixel empty" check (see is_empty()
## above) into its own small helper function and called it once per pixel
## from the byte-array loop -- and measured SLOWER than the original
## get_pixel version, not faster. Isolated directly (see this fix's own
## commit): a 1254x1254 get_pixel loop measured ~220ms; the SAME loop
## reading raw bytes but still calling a per-pixel helper function measured
## ~1070ms; the same loop again with that helper's body INLINED (no
## function call at all) measured ~170ms. The bottleneck was never
## get_pixel vs. byte-array access -- it is GDScript's own per-call
## overhead for a user-defined function, which a tight per-pixel loop pays
## a huge number of times regardless of what that function does internally.
## get_pixel/set_pixel are single C++ builtin calls with no such overhead,
## which is exactly why the ORIGINAL naive version, despite calling
## is_empty() once per pixel too, wasn't dramatically slower on its own
## pixel-access side -- its real cost was elsewhere (the sheer number of
## get_pixel+is_empty call PAIRS). The fix that actually works is this
## function's own shape below: inline the whole per-pixel check directly
## in the loop, calling only built-in global functions (absf/mini/maxi --
## themselves cheap VM builtins, not user function calls) rather than a
## project-defined helper. detect_frames/content_rect/_clear_background
## below repeat this same inlined check three times rather than sharing one
## helper function for exactly this reason -- a deliberate, measured DRY
## violation, not an oversight. See test_sprite_sheet_slicer.gd's own
## "-- performance --" section for the budgeted timing pins this now has to
## keep passing, and illustrated_mushroom_sprite.gd's own identical fix
## (same reported bug, found first in that file's own duplicate of this
## exact technique) for the fuller live-measurement writeup.
static func chroma_keyed(image: Image, key: Color, tolerance: float) -> Image:
	var keyed: Image = image.duplicate()
	if keyed.get_format() != Image.FORMAT_RGBA8:
		keyed.convert(Image.FORMAT_RGBA8)
	var width := keyed.get_width()
	var height := keyed.get_height()
	var data := keyed.get_data()
	var key_r := key.r * 255.0
	var key_g := key.g * 255.0
	var key_b := key.b * 255.0
	var byte_tolerance := tolerance * 255.0
	var i := 0
	for _pixel in width * height:
		if (
			absf(float(data[i]) - key_r) <= byte_tolerance
			and absf(float(data[i + 1]) - key_g) <= byte_tolerance
			and absf(float(data[i + 2]) - key_b) <= byte_tolerance
		):
			data[i] = 0
			data[i + 1] = 0
			data[i + 2] = 0
			data[i + 3] = 0
		i += 4
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)


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

	# Byte-array pass, inlined check, no per-pixel helper function call --
	# see this file's own performance doc comment on chroma_keyed for why
	# both of those matter, not just the first one. data/width are fetched
	# ONCE here, not once per column.
	var img: Image = image
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	var width := img.get_width()
	var data := img.get_data()
	var alpha_threshold_byte := alpha_threshold * 255.0
	var divider_gray_min_byte := divider_gray_min * 255.0

	var start := -1
	var empty_run := 0
	for x in width:
		var column_is_empty := true
		for y in range(top, bottom):
			var idx := (y * width + x) * 4
			if float(data[idx + 3]) < alpha_threshold_byte:
				continue  # transparent -- still empty, keep scanning the column
			var r := data[idx]
			var g := data[idx + 1]
			var b := data[idx + 2]
			if r < divider_gray_min_byte or g < divider_gray_min_byte or b < divider_gray_min_byte:
				column_is_empty = false
				break
			var mx := maxi(maxi(r, g), b)
			if mx == 0:
				continue  # opaque black -- matches is_empty()'s own zero-max case
			var mn := mini(mini(r, g), b)
			if float(mx - mn) / float(mx) > DIVIDER_MAX_SATURATION:
				column_is_empty = false
				break
		if column_is_empty:
			empty_run += 1
			continue
		if start >= 0 and empty_run >= min_divider_width:
			var frame_width := x - empty_run - start
			if frame_width >= min_frame_width:
				frames.append(Rect2i(start, top, frame_width, bottom - top))
			start = -1
		empty_run = 0
		if start < 0:
			start = x
	if start >= 0:
		var last_width := width - empty_run - start
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
		var content := content_rect(image, frame, alpha_threshold, divider_gray_min)
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
		var drawing: Image = image.get_region(content)
		# The canvas below is RGBA8, and blit_rect refuses to mix formats --
		# a sheet loaded as anything else (RGB8, indexed) fails at the last
		# step otherwise.
		if drawing.get_format() != Image.FORMAT_RGBA8:
			drawing.convert(Image.FORMAT_RGBA8)
		drawing = _clear_background(drawing, alpha_threshold, divider_gray_min)

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
## divider pixels around it. Public (not `_content_rect`): normalize_frames'
## own content-crop-then-scale step and illustrated_art_addressing.md's
## `center` anchor (content-cropped, centered on a square canvas, rather
## than normalize_frames' own baseline-positioned centering) both need this
## exact box -- reused rather than re-derived.
func content_rect(
	image: Image, rect: Rect2i, alpha_threshold: float, divider_gray_min: float
) -> Rect2i:
	var clipped := rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return Rect2i(rect.position, Vector2i.ZERO)
	# Byte-array pass, inlined check, no per-pixel helper function call --
	# see this file's own performance doc comment on chroma_keyed for why
	# both of those matter, not just the first one. Called once per FRAME
	# (up to 25/sheet) by normalize_frames, so this is exactly as hot a
	# path as chroma_keyed's own whole-sheet pass.
	var img: Image = image
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	var width := img.get_width()
	var data := img.get_data()
	var alpha_threshold_byte := alpha_threshold * 255.0
	var divider_gray_min_byte := divider_gray_min * 255.0
	var left: int = clipped.position.x + clipped.size.x
	var right: int = clipped.position.x - 1
	var top: int = clipped.position.y + clipped.size.y
	var bottom: int = clipped.position.y - 1
	for y in range(clipped.position.y, clipped.position.y + clipped.size.y):
		var row_base := y * width
		for x in range(clipped.position.x, clipped.position.x + clipped.size.x):
			var idx := (row_base + x) * 4
			var pixel_is_empty := true
			if float(data[idx + 3]) >= alpha_threshold_byte:
				var r := data[idx]
				var g := data[idx + 1]
				var b := data[idx + 2]
				if r < divider_gray_min_byte or g < divider_gray_min_byte or b < divider_gray_min_byte:
					pixel_is_empty = false
				else:
					var mx := maxi(maxi(r, g), b)
					if mx > 0:
						var mn := mini(mini(r, g), b)
						pixel_is_empty = float(mx - mn) / float(mx) <= DIVIDER_MAX_SATURATION
			if pixel_is_empty:
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
##
## Returns a NEW Image rather than mutating `drawing` in place (its one call
## site, normalize_frames, now reassigns its own `drawing` local from this
## return value) -- see this file's own performance doc comment on
## chroma_keyed: reconstructing via Image.create_from_data after a raw byte-
## array pass is the same shape that function and content_rect already use,
## and Image has no in-place "replace my own pixel data" method to mutate
## through instead.
func _clear_background(
	drawing: Image, alpha_threshold: float, divider_gray_min: float
) -> Image:
	var img: Image = drawing
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	var width := img.get_width()
	var height := img.get_height()
	var data := img.get_data()
	var alpha_threshold_byte := alpha_threshold * 255.0
	var divider_gray_min_byte := divider_gray_min * 255.0
	# Inlined check, no per-pixel helper function call -- see this file's
	# own performance doc comment on chroma_keyed for why.
	var i := 0
	for _pixel in width * height:
		var pixel_is_empty := true
		if float(data[i + 3]) >= alpha_threshold_byte:
			var r := data[i]
			var g := data[i + 1]
			var b := data[i + 2]
			if r < divider_gray_min_byte or g < divider_gray_min_byte or b < divider_gray_min_byte:
				pixel_is_empty = false
			else:
				var mx := maxi(maxi(r, g), b)
				if mx > 0:
					var mn := mini(mini(r, g), b)
					pixel_is_empty = float(mx - mn) / float(mx) <= DIVIDER_MAX_SATURATION
		if pixel_is_empty:
			data[i] = 0
			data[i + 1] = 0
			data[i + 2] = 0
			data[i + 3] = 0
		i += 4
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)


## Keying a delivered CHECKERBOARD background — what a sheet paints when it
## was authored without a real alpha channel. Lives here, beside
## chroma_keyed, because it is the same kind of problem: a background that
## has to become transparency at load. Two sheets need it (the building
## yard overlays and the fern sheet), which is why it is one routine rather
## than two copies.
##
## A FLOOD, not a flat key, and the difference is the whole point: the
## checker's lighter square and the art's white highlights are THE SAME
## COLOUR, so keying on colour alone punches holes through every bright
## pixel of the drawing.


## The same key, answering with a NEW image and leaving the caller's own
## untouched — which is what a cached source sheet needs, since whoever
## else holds it must not find it quietly modified. Upgrades an opaque RGB
## sheet to RGBA8 on the way, the way these sheets are actually delivered.
static func checkerboard_keyed(image: Image) -> Image:
	var keyed := Image.new()
	keyed.copy_from(image)
	if keyed.get_format() != Image.FORMAT_RGBA8:
		keyed.convert(Image.FORMAT_RGBA8)
	checkerboard_key_in_place(keyed)
	return keyed


## How unsaturated and how bright a pixel must be to be checkerboard at all.
## The checker's two tones measure (253, 253, 253) and about (213, 213, 213),
## so both clear these comfortably while the art's own lightest real colour
## -- the sandy path -- does not, being visibly warm.
const _CHECKER_MAX_CHANNEL_SPREAD := 0.06
const _CHECKER_MIN_CHANNEL := 0.78

## The checker's two squares are anti-aliased into each other, and into the
## art, so the pixels along every square's edge land at everything between
## the two tones and below. The seed threshold above cannot be loosened to
## take those -- at that width it would also swallow a grey rock -- so the
## flood WIDENS by a bounded few pixels from background it has already
## cleared, under a looser rule. Anti-aliasing is one or two pixels wide, so
## a bounded widening cannot reach a rock's interior however grey it is.
##
## Measured before it: 338 opaque unsaturated pixels survived in one yard,
## about 40 of them real white flower highlights; pinned now by
## test_no_grey_checkerboard_fringe_survives_around_a_yard.
const _CHECKER_FRINGE_MIN_CHANNEL := 0.55
const _CHECKER_FRINGE_MAX_CHANNEL_SPREAD := 0.09
const _CHECKER_FRINGE_DEPTH := 2

## The checker's DARKER square, which is a safe seed anywhere in the cell --
## not only at the border. Its two tones measure about 253 and 213: a white
## flower highlight sits at 235 and above, so nothing in the art is this
## particular grey. Seeding from it as well as from the border is what
## clears the checker seen through small gaps in the foliage, which is
## enclosed by art and so is never reachable from the cell's own edge.
## Measured: 86 such pixels in one cell.
const _CHECKER_DARK_MIN_CHANNEL := 0.76
const _CHECKER_DARK_MAX_CHANNEL := 0.91


## Clears, IN PLACE, the checkerboard a delivered sheet paints instead of
## transparency, by flooding inward from the image's own edges.
##
## A FLOOD, not a flat key, and the difference is the whole point: the
## checker's lighter square and the art's white flower highlights are THE
## SAME COLOUR. The tones measure about 253 and 213; a flower highlight sits
## at 235 and above. Measured, one source cell holds 46,354 near-white
## pixels, almost all of them checker, and 63 survive keying at drawn size
## -- those are the flowers, and a flat key takes every one of them.
##
## What separates them is connectivity, not colour: the checker reaches the
## cell's own edge and a flower enclosed in foliage does not.
##
## Unlike IllustratedCharacterSprite's own flood (head.png), this one steps
## between the checker's two tones freely rather than within a per-step
## tolerance: those differ by about 40/255, far wider than any tolerance
## would allow, because what is followed here is a KNOWN two-tone pattern
## rather than an unknown gradient into the art.
static func checkerboard_key_in_place(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return
	var cleared := {}
	var queue: Array[Vector2i] = []
	for x in range(width):
		for y in [0, height - 1]:
			var edge := Vector2i(x, y)
			if not cleared.has(edge) and _is_checker(image.get_pixelv(edge)):
				cleared[edge] = true
				queue.append(edge)
	for y in range(height):
		for x in [0, width - 1]:
			var edge := Vector2i(x, y)
			if not cleared.has(edge) and _is_checker(image.get_pixelv(edge)):
				cleared[edge] = true
				queue.append(edge)
	# ...and from the darker square anywhere in the cell, which no part of
	# the art shares, so checker showing through a gap in the foliage is
	# cleared even though it cannot be reached from the edge.
	for y in range(height):
		for x in range(width):
			var inside := Vector2i(x, y)
			if not cleared.has(inside) and _is_dark_checker(image.get_pixelv(inside)):
				cleared[inside] = true
				queue.append(inside)
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if cleared.has(next) or not _is_checker(image.get_pixelv(next)):
				continue
			cleared[next] = true
			queue.append(next)
	# ...then widen by a bounded depth, so the checker's anti-aliased edges
	# go with it without the seed rule having to be loose enough to eat art.
	var frontier: Array[Vector2i] = queue
	for _depth in range(_CHECKER_FRINGE_DEPTH):
		var next_frontier: Array[Vector2i] = []
		for at in frontier:
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var near: Vector2i = at + step
				if near.x < 0 or near.y < 0 or near.x >= width or near.y >= height:
					continue
				if cleared.has(near) or not _is_checker_fringe(image.get_pixelv(near)):
					continue
				cleared[near] = true
				next_frontier.append(near)
		frontier = next_frontier

	for cell in cleared:
		image.set_pixelv(cell, Color(0, 0, 0, 0))


## The looser rule the bounded widening uses -- grey, and bright enough to
## be a checker edge rather than a shadow, but reachable only from
## background already cleared and only _CHECKER_FRINGE_DEPTH pixels deep.
static func _is_checker_fringe(color: Color) -> bool:
	var lowest: float = minf(color.r, minf(color.g, color.b))
	var highest: float = maxf(color.r, maxf(color.g, color.b))
	return (
		lowest >= _CHECKER_FRINGE_MIN_CHANNEL
		and highest - lowest <= _CHECKER_FRINGE_MAX_CHANNEL_SPREAD
	)


static func _is_dark_checker(color: Color) -> bool:
	var lowest: float = minf(color.r, minf(color.g, color.b))
	var highest: float = maxf(color.r, maxf(color.g, color.b))
	return (
		lowest >= _CHECKER_DARK_MIN_CHANNEL
		and lowest <= _CHECKER_DARK_MAX_CHANNEL
		and highest - lowest <= _CHECKER_MAX_CHANNEL_SPREAD
	)


static func _is_checker(color: Color) -> bool:
	var lowest: float = minf(color.r, minf(color.g, color.b))
	var highest: float = maxf(color.r, maxf(color.g, color.b))
	return (
		lowest >= _CHECKER_MIN_CHANNEL
		and highest - lowest <= _CHECKER_MAX_CHANNEL_SPREAD
	)
