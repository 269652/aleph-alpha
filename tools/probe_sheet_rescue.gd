extends SceneTree

## Can a sheet delivered on a NEAR-black background be rescued by chroma-
## keying that background out, or does the key eat the drawing's own dark
## outlines too? Sweeps the tolerance and reports both halves of the trade
## at each step: how the sheet slices, and how much of the creature dies.
##
##   godot --headless --path . -s tools/probe_sheet_rescue.gd -- <image path>

const ALPHA_THRESHOLD := 0.3
const DIVIDER_GRAY_MIN := 0.7
const MIN_FRAME_WIDTH := 60
const MIN_DIVIDER_WIDTH := 1

var _slicer
var _sheet_slicer_script


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else ""
	_sheet_slicer_script = load("res://src/rendering/sprite_sheet_slicer.gd")
	_slicer = _sheet_slicer_script.new()

	var original := Image.new()
	if original.load(path) != OK:
		print("could not load %s" % path)
		quit()
		return
	if original.get_format() != Image.FORMAT_RGBA8:
		original.convert(Image.FORMAT_RGBA8)

	# How dark the DRAWING's own pixels get, measured only inside a region
	# that is unambiguously creature -- so "how much would a black key eat"
	# is answered against the art, not against the background.
	_report_subject_darkness(original)

	for tolerance in [0.06, 0.10, 0.14, 0.18, 0.24]:
		var keyed: Image = _sheet_slicer_script.chroma_keyed(original, Color(0, 0, 0), tolerance)
		var bands := _content_bands(keyed)
		var counts := []
		var overflow := false
		for band in bands:
			var frames: Array[Rect2i] = _slicer.detect_frames(
				keyed, band.x, band.y, MIN_FRAME_WIDTH, MIN_DIVIDER_WIDTH, ALPHA_THRESHOLD, DIVIDER_GRAY_MIN
			)
			counts.append(frames.size())
			for frame in frames:
				var content := _content_rect(keyed, frame)
				if content.size.x > 340 or content.size.y > 330:
					overflow = true
		print("key black +/- %.2f (<= %3d): %d band(s), frames per band %s%s" % [
			tolerance, int(tolerance * 255.0), bands.size(), str(counts),
			"   !! a frame overflows the canvas" if overflow else ""
		])
	quit()


## What share of a known-creature area is dark enough that a black chroma
## key would delete it. Sampled from the widest content band's own middle
## third, vertically -- the goblin's body, never the empty margins.
func _report_subject_darkness(image: Image) -> void:
	var buckets := {0: 0, 20: 0, 30: 0, 40: 0, 60: 0}
	var lit := 0
	var y := int(image.get_height() * 0.15)
	while y < int(image.get_height() * 0.9):
		var x := 0
		while x < image.get_width():
			var c := image.get_pixel(x, y)
			var mx := int(round(maxf(maxf(c.r, c.g), c.b) * 255.0))
			# Only count pixels that are plainly drawing, not background:
			# a real colour cast (the goblin is green/brown, the backdrop
			# is neutral) at any brightness.
			var mn := int(round(minf(minf(c.r, c.g), c.b) * 255.0))
			var saturated := mx > 0 and float(mx - mn) / float(mx) > 0.25
			if saturated:
				lit += 1
				for edge in buckets:
					if mx <= int(edge):
						buckets[edge] += 1
			x += 3
		y += 3
	print("drawn (colour-cast) pixels sampled: %d" % lit)
	for edge in [20, 30, 40, 60]:
		print("  %.2f%% of them are at or below max-channel %d (a black key +/- %.2f deletes these)" % [
			100.0 * float(buckets[edge]) / float(maxi(lit, 1)), edge, float(edge) / 255.0
		])


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
