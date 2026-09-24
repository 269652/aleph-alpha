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
##   godot --headless --path . -s tools/probe_sheet_audit.gd -- <image path> [key_hex] [tolerance]
##
## The chroma key matters: _slice_bands applies it BEFORE anything else
## runs, so a sheet measured without the key it actually ships with is not
## being measured as the engine sees it. Checked against sheep.png, which
## ships and works: audited raw it reports a broken sheet (its magenta
## backdrop counts as drawing, so every frame's "content" is the whole cell
## and every row appears to overflow the canvas); audited with its own key
## it reports the sheet the game really slices. A probe that lies is worse
## than no probe.

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
		print("usage: -s tools/probe_sheet_audit.gd -- <image path> [key_hex] [tolerance]")
		quit()
		return
	var slicer_script := load("res://src/rendering/sprite_sheet_slicer.gd")
	_slicer = slicer_script.new()

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

	# Raw first -- what the backdrop really is, before anything is keyed out,
	# because that is the question a candidate sheet is usually failing.
	_report_background(image)

	# Then key, exactly the way _slice_bands does, before measuring anything
	# that describes the DRAWING (frames, feet, scale). Without this the
	# backdrop counts as drawing and every number below describes a
	# rectangle rather than a creature.
	if args.size() > 1:
		var key := Color(args[1])
		var tolerance: float = float(args[2]) if args.size() > 2 else 0.1
		image = slicer_script.chroma_keyed(image, key, tolerance)
		print("\nchroma key %s +/- %.2f applied, as _slice_bands would" % [args[1], tolerance])
	else:
		print("\nno chroma key given -- measuring the file as-is. A sheet that")
		print("  ships with one MUST be audited with it, or every measurement")
		print("  below describes its backdrop instead of its creature.")
	_report_dividers(image)
	var bands := _content_bands(image)
	print("\ncontent bands (rows) found: %d" % bands.size())
	var single_frame_rows := 0
	for index in bands.size():
		if _report_band(image, index, bands[index]) <= 1:
			single_frame_rows += 1
	_report_verdict(bands.size(), single_frame_rows)
	quit()


## The judgement, drawn from what the sheet actually DID rather than from a
## guess about its backdrop. A row that slices to one frame is the failure;
## everything else is diagnosis of it.
func _report_verdict(band_count: int, single_frame_rows: int) -> void:
	print("")
	if band_count == 0:
		print("VERDICT: nothing sliced at all.")
		return
	if single_frame_rows == 0:
		print("VERDICT: slices cleanly. Hand-measure each band's y range into")
		print("  \"<action>_bands\" and register it.")
		return
	print("VERDICT: %d of %d row(s) slice to a single frame -- not usable." % [
		single_frame_rows, band_count
	])
	print("  Almost always the backdrop. detect_frames calls a pixel empty when it")
	print("  is transparent, or opaque-but-pale-and-near-neutral (the divider rule).")
	print("  Anything else -- dark, or saturated -- is drawing, so every column is")
	print("  occupied and the row cannot be split. Two backdrops work:")
	print("    WHITE, needing no chroma_key at all (boar/deer/horse) -- but the same")
	print("      rule swallows near-white ART, so not for a creature with bone or")
	print("      cream on it.")
	print("    MAGENTA plus a chroma_key (sheep/wolf/the bosses) -- safe for any")
	print("      palette, since no drawing is near magenta.")
	print("  Re-run with the key to audit a sheet that declares one.")


## The commonest opaque colour, which is what a backdrop actually is --
## unlike a corner, which may be margin rather than backdrop.
func _report_modal_opaque_colour(image: Image) -> void:
	var counts := {}
	var y := 0
	while y < image.get_height():
		var x := 0
		while x < image.get_width():
			var c := image.get_pixel(x, y)
			if c.a >= ALPHA_THRESHOLD:
				# Quantised to 8 levels per channel: an exact-colour tally
				# is defeated by any compression noise.
				var key := Vector3i(
					int(c.r * 255.0) / 32, int(c.g * 255.0) / 32, int(c.b * 255.0) / 32
				)
				counts[key] = int(counts.get(key, 0)) + 1
			x += 5
		y += 5
	var best := Vector3i.ZERO
	var best_count := 0
	var total := 0
	for key in counts:
		total += int(counts[key])
		if int(counts[key]) > best_count:
			best_count = int(counts[key])
			best = key
	if total == 0:
		print("  commonest opaque colour: none (fully transparent sheet)")
		return
	print("  commonest opaque colour: ~rgb(%d,%d,%d), %.0f%% of opaque pixels" % [
		best.x * 32 + 16, best.y * 32 + 16, best.z * 32 + 16,
		100.0 * float(best_count) / float(total)
	])


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
	var pale_neutral_backdrop := true
	var saw_opaque := false
	for label in samples:
		var at: Vector2i = samples[label]
		var c := image.get_pixel(at.x, at.y)
		var r := int(round(c.r * 255.0))
		var g := int(round(c.g * 255.0))
		var b := int(round(c.b * 255.0))
		var a := int(round(c.a * 255.0))
		var verdict := "transparent -> empty"
		if a >= int(ALPHA_THRESHOLD * 255.0):
			saw_opaque = true
			any_opaque_nonblack = true
			# The one opaque case detect_frames calls empty: pale on every
			# channel and near-neutral, i.e. the divider rule.
			var mx: int = maxi(maxi(r, g), b)
			var mn: int = mini(mini(r, g), b)
			var pale := mn >= int(DIVIDER_GRAY_MIN * 255.0)
			var neutral := mx == 0 or float(mx - mn) / float(mx) <= 0.12
			if pale and neutral:
				verdict = "opaque, pale + neutral -> empty (the divider rule)"
			else:
				verdict = "opaque, not pale -> reads as CONTENT"
				pale_neutral_backdrop = false
		print("  %-14s rgba(%3d,%3d,%3d,%3d)  %s" % [label, r, g, b, a, verdict])
	# Verdict from the CORNERS alone, deliberately. A whole-image count of
	# "opaque near-black" pixels sounds more thorough and is not: it counts
	# the drawing's own dark outlines and fur as backdrop, so it fired on
	# boar_walk.png -- a transparent-background sheet that ships and works.
	# The corners are the one place a sheet is reliably backdrop.
	print("  (corner samples are raw data, not a verdict -- sheep.png's corners")
	print("   read near-white while the backdrop INSIDE its cells is magenta, so")
	print("   the diagnosis below comes from how the sheet actually slices.)")
	_report_modal_opaque_colour(image)


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
func _report_band(image: Image, index: int, band: Vector2i) -> int:
	var frames: Array[Rect2i] = _slicer.detect_frames(
		image, band.x, band.y, MIN_FRAME_WIDTH, MIN_DIVIDER_WIDTH, ALPHA_THRESHOLD, DIVIDER_GRAY_MIN
	)
	print("\nband %d: y %d..%d (%d px tall) -> %d frame(s)" % [
		index, band.x, band.y, band.y - band.x, frames.size()
	])
	if frames.is_empty():
		print("  !! nothing sliced")
		return 0
	var widest := 0
	var tallest := 0
	var baselines := []
	var areas := []
	for frame in frames:
		var content := _content_rect(image, frame)
		if content.size == Vector2i.ZERO:
			print("  frame at x=%d: no content" % frame.position.x)
			continue
		widest = maxi(widest, content.size.x)
		tallest = maxi(tallest, content.size.y)
		baselines.append(content.position.y + content.size.y)
		areas.append(_opaque_area(image, frame))
	# What normalize_frames will do with this row: ONE scale for the whole
	# set, min(canvas.x / widest, baseline_y / tallest). Oversized content
	# does not overflow -- it is scaled to fit (pinned by
	# test_content_far_larger_than_the_canvas_is_scaled_down_not_overflowed)
	# -- but because the scale is shared, the widest/tallest frame in a row
	# sets the size every other frame in it renders at.
	var fit: float = minf(
		float(CANVAS_SIZE.x) / float(maxi(widest, 1)), float(BASELINE_Y) / float(maxi(tallest, 1))
	)
	print("  content: widest %d px, tallest %d px -> normalize_frames scales this row by x%.3f" % [
		widest, tallest, fit
	])
	if baselines.size() > 1:
		var span := _span(baselines)
		if tallest >= band.y - band.x:
			# Every frame's content box fills the whole band, so the
			# "bottom" being measured is the band's own edge, not the
			# creature's feet. Says so rather than reporting a perfect
			# alignment it did not actually observe -- which is what a
			# shipped sheet with a fringe at its band edges does here.
			print("  feet: not measurable -- content fills the band, so this is the band edge")
		else:
			print("  feet (content bottom) sit %d px apart across the row: %d..%d%s" % [
				span.y - span.x, span.x, span.y,
				"   !! every frame of a row must share one ground line" if span.y - span.x > 8 else ""
			])
	_report_scale_drift(areas)
	return frames.size()


## Whether the creature is drawn at ONE size across the row. Measured as
## opaque pixel AREA rather than content height, deliberately: height is
## pose-sensitive -- a crouch, a lunge and a body settling on the ground
## legitimately change it by half -- while area is roughly conserved by
## pose and scales as the SQUARE of size, so a creature drawn 20% bigger in
## one frame shows up as ~44% more pixels. The ratio is reported rather
## than a verdict, because a row whose pose genuinely extends the
## silhouette (a club swung out to full reach) moves it too; what a real
## scale wobble looks like is the WALK/IDLE rows drifting, where the pose
## barely changes at all.
func _report_scale_drift(areas: Array) -> void:
	if areas.size() < 2:
		return
	var span := _span(areas)
	var lo: float = maxf(float(span.x), 1.0)
	var ratio := float(span.y) / lo
	print("  drawn area per frame: %d..%d px (x%.2f smallest to largest)%s" % [
		span.x, span.y, ratio,
		"   <- a locomotion row should sit near x1.15" if ratio > 1.5 else ""
	])


func _span(values: Array) -> Vector2i:
	var lo: int = int(values[0])
	var hi: int = int(values[0])
	for value in values:
		lo = mini(lo, int(value))
		hi = maxi(hi, int(value))
	return Vector2i(lo, hi)


## How many pixels inside `frame` are actually drawing.
func _opaque_area(image: Image, frame: Rect2i) -> int:
	var count := 0
	for y in range(frame.position.y, frame.end.y):
		for x in range(frame.position.x, frame.end.x):
			if not _slicer.is_empty(image.get_pixel(x, y), ALPHA_THRESHOLD, DIVIDER_GRAY_MIN):
				count += 1
	return count


## The drawn content's own bounding box inside `frame` -- the SLICER'S own
## content_rect, not a copy of it. A probe that measures the pipeline with
## its own reimplementation of the pipeline can disagree with it, which is
## the one thing a probe must never do.
func _content_rect(image: Image, frame: Rect2i) -> Rect2i:
	return _slicer.content_rect(image, frame, ALPHA_THRESHOLD, DIVIDER_GRAY_MIN)
