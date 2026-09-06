extends SceneTree

## Measurement tool, kept per tools/probe_worm_sheet.gd's own precedent (a
## hand-verified fixed-grid sheet keeps its probe as the record of how that
## was confirmed): assets/sprites/animals/caterpillar.png shares worm.png's
## exact 1536x1024, 8-column x 4-row, 192x256-cell grid -- slicing the KNOWN
## fixed grid directly rather than trusting detect_frames' content-gap
## heuristic. Confirms every one of the 32 cells has real content, and
## dumped each row's frame 0 + a mid-row frame to disk (both crops WITH the
## same second despill pass IllustratedWormSprite._build_textures runs
## after normalize_frames -- without it, a raw normalized frame can still
## carry a magenta-tinted divider-line remnant right at its crop edge,
## confirmed and fixed here before it ever reached the shipped class) to
## confirm the row-semantic read directly against real pixels:
##   row 1 "crawl" -- a flat, level inching gait, the resting/travel pose.
##   row 2 "climb" -- rears up near-vertical at its peak frames, the one
##     row shaped for moving up a vertical surface like a trunk, not level
##     ground.
##   row 3 "eat" -- head held low to the ground/surface throughout, a
##     grazing posture level travel never uses.
##   row 4 "rest" -- progressively flattens into a fully level, motionless
##     pose by its later frames -- the settle-and-hold idle.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

const _COLUMNS := 8
const _ROWS := 4
const _CELL_W := 192
const _CELL_H := 256

const _ROW_NAMES := ["crawl", "climb", "eat", "rest"]


func _init() -> void:
	var raw := Image.load_from_file("res://assets/sprites/animals/caterpillar.png")
	print("sheet size: ", raw.get_width(), "x", raw.get_height())

	var image := raw.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))

	var slicer := SpriteSheetSlicer.new()
	var canvas_size := Vector2i(200, 260)
	var baseline_y := 250

	for row in _ROWS:
		var frames: Array[Rect2i] = []
		for col in _COLUMNS:
			frames.append(Rect2i(col * _CELL_W, row * _CELL_H, _CELL_W, _CELL_H))
		var normalized := slicer.normalize_frames(image, frames, canvas_size, baseline_y)
		print("row ", row + 1, " (guess: ", _ROW_NAMES[row], "): ", normalized.size(), " normalized frames")
		var blanks := 0
		for i in normalized.size():
			var bounds := _painted_bounds(normalized[i])
			if bounds.size.x <= 0:
				blanks += 1
			print("  frame ", i, " content bounds: ", bounds)
		print("  blanks in this row: ", blanks)
		# Dump frame 0 and a mid-row frame for visual confirmation -- WITH the
		# same second despill pass IllustratedWormSprite._build_textures runs
		# after normalize_frames, since a raw normalized frame can still carry
		# a magenta-tinted divider-line remnant at its crop edge that this
		# second pass is specifically what cleans up.
		_despill_image(normalized[0])
		_despill_image(normalized[4])
		normalized[0].save_png("user://caterpillar_row%d_frame0.png" % (row + 1))
		normalized[4].save_png("user://caterpillar_row%d_frame4.png" % (row + 1))

	print("dumped crops to: ", OS.get_user_data_dir())
	quit()


const _MAGENTA_CAST_MARGIN := 0.03


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


static func _despill_image(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)


static func _painted_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.1:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
