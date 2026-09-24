extends SceneTree

## Audits a candidate illustrated-art sheet against the REAL pipeline before
## anyone registers it: the same SpriteSheetSlicer.detect_frames the engine
## runs, with the same parameters IllustratedAnimalSprite._slice_bands passes
## it (note min_frame_width 60, not the slicer's own default 8), plus the
## checks that decide whether a sheet is usable at all -- what the background
## actually measures, whether the dividers read as dividers, how many frames
## each row really slices to, and whether any frame's content overflows the
## shared canvas (which raises in Image.set_pixel rather than clipping).
##
##   godot --headless --path . -s tools/probe_sheet_audit.gd -- <image path>

const CANVAS_SIZE := Vector2i(340, 330)
const BASELINE_Y := 310
## What _slice_bands really passes -- a frame narrower than this is DROPPED.
const MIN_FRAME_WIDTH := 60
const MIN_DIVIDER_WIDTH := 1
const ALPHA_THRESHOLD := 0.3
const DIVIDER_GRAY_MIN := 0.7

var _slicer


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else ""
	if path == "":
		print("usage: -s tools/probe_sheet_audit.gd -- <image path>")
		quit()
		return
	_slicer = load("res://src/rendering/sprite_sheet_slicer.gd").new()

	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		print("could not load %s (error %d)" % [path, err])
		quit()
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	print("== %s ==" % path)
	print("size: %dx%d  format: RGBA8" % [image.get_width(), image.get_height()])
	_report_background(image)
	_report_dividers(image)
	var bands := _content_bands(image)
	print("\ncontent bands (rows) found: %d" % bands.size())
	for index in bands.size():
		_report_band(image, index, bands[index])
	quit()


## What the "empty" areas really measure. The slicer treats an opaque pixel
## as background only when it is transparent, pale-and-unsaturated (a
## divider), or EXACTLY black -- see detect_frames' own `mx == 0` branch. A
## near-black background that is not exactly 0,0,0 reads as drawing.
func _report_background(image: Image) -> void:
	var samples := {
		"top-left": Vector2i(2, 2),
		"top-right": Vector2i(image.get_width() - 3, 2),
		"bottom-left": Vector2i(2, image.get_height() - 3),
		"bottom-right": Vector2i(image.get_width() - 3, image.get_height() - 3),
	}
	print("\nbackground samples:")
	var any_opaque_nonblack := false
	for label in samples:
		var at: Vector2i = samples[label]
		var c := image.get_pixel(at.x, at.y)
		var r := int(round(c.r * 255.0))
		var g := int(round(c.g * 255.0))
		var b := int(round(c.b * 255.0))
		var a := int(round(c.a * 255.0))
		var verdict := "transparent -> empty"
		if a >= int(ALPHA_THRESHOLD * 255.0):
			if maxi(maxi(r, g), b) == 0:
				verdict = "opaque PURE black -> empty (the mx == 0 branch)"
			else:
				verdict = "opaque, NOT pure black -> reads as CONTENT"
				any_opaque_nonblack = true
		print("  %-14s rgba(%3d,%3d,%3d,%3d)  %s" % [label, r, g, b, a, verdict])
	# How much of the whole sheet is opaque-but-not-black: if the background
	# is off-black everywhere, every column reads as content and each row
	# slices to exactly one frame.
	var total := 0
	var offblack := 0
	var y := 0
	while y < image.get_height():
		var x := 0
		while x < image.get_width():
			var c := image.get_pixel(x, y)
			total += 1
			if c.a >= ALPHA_THRESHOLD:
				var mx: int = int(round(maxf(maxf(c.r, c.g), c.b) * 255.0))
				if mx > 0 and mx <= 40:
					offblack += 1
			x += 7
		y += 7
	print("  sampled %d px: %.1f%% are opaque near-black but NOT pure black" % [
		total, 100.0 * float(offblack) / float(maxi(total, 1))
	])
	if any_opaque_nonblack or offblack > total / 20:
		print("  !! a background like this defeats detect_frames unless it is chroma-keyed out")


## Whether the cell borders actually read as dividers: pale (>= 0.7 on every
## channel) and near-neutral (saturation <= DIVIDER_MAX_SATURATION).
func _report_dividers(image: Image) -> void:
	var pale := 0
	var pale_saturated := 0
	var y := 0
	while y < image.get_height():
		var x := 0
		while x < image.get_width():
			var c := image.get_pixel(x, y)
			if c.a >= ALPHA_THRESHOLD and minf(minf(c.r, c.g), c.b) >= DIVIDER_GRAY_MIN:
				pale += 1
				var mx := maxf(maxf(c.r, c.g), c.b)
				var mn := minf(minf(c.r, c.g), c.b)
				if mx > 0.0 and (mx - mn) / mx > 0.12:
					pale_saturated += 1
			x += 3
		y += 3
	print("\npale pixels sampled: %d (of which %d are too saturated to count as divider)" % [pale, pale_saturated])


## Rows of the sheet that hold any non-empty pixel, grouped into bands --
## the same thing a human does by eye when hand-measuring "<action>_bands".
func _content_bands(image: Image) -> Array:
	var bands := []
	var start := -1
	for y in image.get_height():
		var has_content := false
		for x in image.get_width():
			if not _slicer.is_empty(image.get_pixel(x, y), ALPHA_THRESHOLD, DIVIDER_GRAY_MIN):
				has_content = true
				break
		if has_content and start < 0:
			start = y
		elif not has_content and start >= 0:
			if y - start > 8:
				bands.append(Vector2i(start, y))
			start = -1
	if start >= 0:
		bands.append(Vector2i(start, image.get_height()))
	return bands


## One row, through the real slicer: how many frames it yields, how wide
## each frame's drawn content is, and where each frame's feet land.
func _report_band(image: Image, index: int, band: Vector2i) -> void:
	var frames: Array[Rect2i] = _slicer.detect_frames(
		image, band.x, band.y, MIN_FRAME_WIDTH, MIN_DIVIDER_WIDTH, ALPHA_THRESHOLD, DIVIDER_GRAY_MIN
	)
	print("\nband %d: y %d..%d (%d px tall) -> %d frame(s)" % [
		index, band.x, band.y, band.y - band.x, frames.size()
	])
	if frames.is_empty():
		print("  !! nothing sliced")
		return
	var widest := 0
	var tallest := 0
	var baselines := []
	for frame in frames:
		var content := _content_rect(image, frame)
		if content.size == Vector2i.ZERO:
			print("  frame at x=%d: no content" % frame.position.x)
			continue
		widest = maxi(widest, content.size.x)
		tallest = maxi(tallest, content.size.y)
		baselines.append(content.position.y + content.size.y)
	print("  content: widest %d px, tallest %d px  (canvas is %dx%d)" % [
		widest, tallest, CANVAS_SIZE.x, CANVAS_SIZE.y
	])
	if widest > CANVAS_SIZE.x or tallest > CANVAS_SIZE.y:
		print("  !! OVERFLOWS the shared canvas -- Image.set_pixel raises, it does not clip")
	if baselines.size() > 1:
		var lo: int = baselines[0]
		var hi: int = baselines[0]
		for b in baselines:
			lo = mini(lo, int(b))
			hi = maxi(hi, int(b))
		print("  feet (content bottom) span %d px across the row: %d..%d" % [hi - lo, lo, hi])


## The drawn content's own bounding box inside `frame`.
func _content_rect(image: Image, frame: Rect2i) -> Rect2i:
	var min_x := frame.end.x
	var min_y := frame.end.y
	var max_x := -1
	var max_y := -1
	for y in range(frame.position.y, frame.end.y):
		for x in range(frame.position.x, frame.end.x):
			if _slicer.is_empty(image.get_pixel(x, y), ALPHA_THRESHOLD, DIVIDER_GRAY_MIN):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
