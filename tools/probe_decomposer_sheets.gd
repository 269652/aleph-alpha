extends SceneTree

## Measurement tool for IllustratedDecomposerSprite's two sheets -- referenced
## by name in illustrated_decomposer_sprite.gd's own _SHEETS doc comment
## ("see tools/probe_decomposer_sheets.gd for the measurement this project
## keeps visible rather than eyeballed") but never actually committed until
## now. Written to root-cause test_illustrated_decomposer_sprite.gd's
## test_generate_textures_returns_four_idle_frames_for_ant/_bug failing on
## main with [6] instead of the pinned [4] (first flagged in passing by the
## ant-queen session, docs/progress.md's own "Found in passing" note under
## the ant queen entry) -- runs the EXACT same detect_frames call
## _build_textures does (top_y/bottom_y from the real band, min_frame_
## width=60, min_divider_width=1, alpha_threshold=0.3) and reports each
## detected frame's rect, content_rect, and opaque-pixel count, so "6" can
## be read off real measurements rather than guessed at.
##
## Result (both sheets, current idle band): 6 frames, every one 200px+ wide
## with thousands of opaque pixels each, evenly spaced across the full
## sheet width at the same per-column pitch as the already-6-frame walk/
## carry bands -- not a sliver/artifact from a false divider gap splitting
## one pose in two.
##
## Confirmed against history, not just the current file: `git show
## e25d52b6^:assets/sprites/animals/ant.png` and `git show
## 30d47d90^:assets/sprites/animals/beetle.png` (the last commit of each
## PNG before this class's own code was last touched, 3430a9cf on
## 2026-09-05) fed through this exact same detect_frames call BOTH still
## slice their idle band to exactly 4 frames, occupying only the first 4 of
## the sheet's 6 grid columns -- walk/carry were already 6 back then too.
## The Sep 6/7 "commit outstanding working-tree changes" sweeps
## (e25d52b6, 30d47d90) captured genuine art edits that filled in each
## sheet's remaining 2 idle-row columns with 2 more hand-drawn poses,
## catching idle up to match walk/carry's cadence. The art changed
## deliberately; the slicer (unmodified this whole time) was never wrong --
## see test_illustrated_decomposer_sprite.gd's now-renamed
## test_generate_textures_returns_six_idle_frames_for_ant/_bug.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _MAGENTA_CAST_MARGIN := 0.03
const _ALPHA_THRESHOLD := 0.3

const _SHEETS := {
	"ant": {
		"path": "res://assets/sprites/animals/ant.png",
		"bands": {"walk": Vector2i(95, 250), "carry": Vector2i(397, 550), "idle": Vector2i(710, 850)},
	},
	"bug": {
		"path": "res://assets/sprites/animals/beetle.png",
		"bands": {"walk": Vector2i(107, 308), "idle": Vector2i(458, 660)},
	},
}


func _init() -> void:
	var slicer := SpriteSheetSlicer.new()
	for species in _SHEETS:
		var sheet: Dictionary = _SHEETS[species]
		var raw := Image.load_from_file(sheet["path"])
		print("\n=== %s (%s): %dx%d ===" % [species, sheet["path"], raw.get_width(), raw.get_height()])
		var image := _prepared_for_slicing(raw)
		var bands: Dictionary = sheet["bands"]
		for action in bands:
			var band: Vector2i = bands[action]
			var frames := slicer.detect_frames(image, band.x, band.y, 60, 1, _ALPHA_THRESHOLD)
			print("  %s band (y %d-%d): %d frame(s) detected" % [action, band.x, band.y, frames.size()])
			for i in frames.size():
				var rect: Rect2i = frames[i]
				var content := slicer.content_rect(image, rect, _ALPHA_THRESHOLD, 0.7)
				var opaque_pixels := _count_opaque(image, rect)
				print(
					"    frame %d: rect=%s content=%s opaque_px=%d"
					% [i, rect, content, opaque_pixels]
				)
	quit()


func _prepared_for_slicing(image: Image) -> Image:
	var prepared := image.duplicate() as Image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	for y in prepared.get_height():
		for x in prepared.get_width():
			var pixel := prepared.get_pixel(x, y)
			if _is_magenta(pixel):
				prepared.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
			else:
				prepared.set_pixel(x, y, _despilled(pixel))
	return prepared


func _count_opaque(image: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if image.get_pixel(x, y).a > 0.5:
				count += 1
	return count


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
