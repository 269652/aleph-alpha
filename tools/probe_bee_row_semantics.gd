extends SceneTree

## Measurement tool for bee.png/honeybee.png/honeybee_queen.png -- see
## tools/probe_worm_sheet.gd/probe_caterpillar_sheet.gd's own precedent:
## kept as the permanent record of how this was confirmed, not deleted
## once the answer was found.
##
## Live user correction: "Rows are: walking, flying, foraging, building
## hive / nest, dying" -- FIVE named concepts, against all three sheets
## confirmed 1536x1024. The row shipped as "fly" (row 0 of an ASSUMED 8
## cols x 4 EQUAL rows x 192x256 grid, ported unverified from worm/
## caterpillar/millipede's own sheets, which really are 4 equal rows) was
## never independently probed for these three sheets at all -- unlike
## every other illustrated sheet in this codebase, which each got their
## own tools/probe_*_sheet.gd before shipping.
##
## FINDINGS:
## - A blank-row scan (any pixel with alpha>0.1 counts as "content") found
##   exactly ONE band spanning the full 0-1024 height on all three sheets
##   -- there is no blank divider row anywhere, so boundaries can't be
##   found by scanning for gaps the way probe_beehive_sheet.gd's row-vs-
##   row split could.
## - Slicing on the assumed 4-EQUAL-row grid produced strips that visually
##   showed TWO different poses stacked per assumed 256px band (confirmed
##   by re-slicing on an 8-EQUAL-row (128px) hypothesis instead: several
##   of those 128px bands cut a single pose clean in half -- top half in
##   one band, legs/bottom half in the next).
## - The real layout is FIVE bands of NON-uniform height (three tall
##   256px bands, two compact 128px bands), packed edge to edge with zero
##   gap, summing exactly to the real 1024px height -- confirmed
##   identically on bee.png AND honeybee.png (same pixel-density shape),
##   and honeybee_queen.png shares the SAME five bands too (she is not
##   laid out differently just because a hypothesis said she might be):
##     walk      y[0,   256) -- ground contact: legs planted, real shadow.
##     fly       y[256, 384) -- level flight: legs tucked, no shadow,
##               minimal frame-to-frame variation.
##     forage_a  y[384, 640) -- taller, more dynamic reaching pose, a
##               visible orange/red mark at the mouthparts on several
##               frames (active nectar/pollen engagement).
##     forage_b  y[640, 768) -- compact variant of forage_a, same mark.
##     dying     y[768, 1024)-- progressive collapse across 8 frames:
##               upright -> leaning -> legs curling inward -> lying on
##               its side. The queen's own crown stays visible through
##               her own collapse.
## - "Building hive/nest" has no matching row on any of the three sheets
##   -- a real, honest "doesn't map" finding: the hive STRUCTURE's own
##   construction is already fully represented by the separate
##   beehive.png sheet (IllustratedBeehiveSprite.growth_stage_index), and
##   no bee-body pose is needed for it.
## - The queen IS visually distinct from a worker on this same grid: a
##   gold crown with a red jewel, and a notably longer, more elongated,
##   golden-amber abdomen versus a worker's shorter black-striped one --
##   confirmed here directly against real pixels, not assumed from real
##   queen honeybee biology alone.
##
## This is what src/rendering/illustrated_bee_sprite.gd's own _ROW_BAND
## constant now encodes.

const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _MAGENTA_CAST_MARGIN := 0.03

const _COLUMNS := 8

## The real, confirmed bands -- name -> [top, height].
const _BANDS := [
	["walk", 0, 256],
	["fly", 256, 128],
	["forage_a", 384, 256],
	["forage_b", 640, 128],
	["dying", 768, 256],
]

const _SHEETS := [
	"res://assets/sprites/animals/bee.png",
	"res://assets/sprites/animals/honeybee.png",
	"res://assets/sprites/animals/honeybee_queen.png",
]


func _init() -> void:
	for path in _SHEETS:
		_investigate(path)
	print("\ndumped strips to: ", OS.get_user_data_dir())
	quit()


func _investigate(path: String) -> void:
	print("\n=== ", path, " ===")
	var raw := Image.load_from_file(path)
	print("size: ", raw.get_width(), "x", raw.get_height())

	var image := raw.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if _is_magenta(p):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(p))

	# Blank-row-band scan, confirming there is no divider row: this should
	# print exactly ONE band spanning the whole height on every sheet.
	var row_has_content: Array = []
	for y in image.get_height():
		var found := false
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.1:
				found = true
				break
		row_has_content.append(found)
	var blank_bands := _bands_from(row_has_content)
	print("blank-row-scan bands (expect exactly 1, no real divider): ", blank_bands.size(), " -> ", blank_bands)

	var basename := path.get_file().get_basename()
	for band in _BANDS:
		var label: String = band[0]
		var top: int = band[1]
		var height: int = band[2]
		var band_img := Image.create(image.get_width(), height, false, Image.FORMAT_RGBA8)
		band_img.blit_rect(image, Rect2i(0, top, image.get_width(), height), Vector2i(0, 0))
		var scale: int = 3 if height <= 128 else 2
		band_img.resize(band_img.get_width() * scale, band_img.get_height() * scale, Image.INTERPOLATE_NEAREST)
		var backed := Image.create(band_img.get_width(), band_img.get_height(), false, Image.FORMAT_RGBA8)
		backed.fill(Color(0.55, 0.55, 0.55, 1.0))
		backed.blend_rect(band_img, Rect2i(Vector2i.ZERO, band_img.get_size()), Vector2i.ZERO)
		var out_path := "user://%s_%s.png" % [basename, label]
		backed.save_png(out_path)
		print("  saved '", label, "' (y ", top, "-", top + height, ") -> ", out_path)


static func _bands_from(flags: Array) -> Array:
	var bands: Array = []
	var in_band := false
	var start := 0
	for i in flags.size():
		if flags[i] and not in_band:
			in_band = true
			start = i
		elif not flags[i] and in_band:
			in_band = false
			bands.append([start, i])
	if in_band:
		bands.append([start, flags.size()])
	return bands


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)
