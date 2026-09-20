extends SceneTree

## Draws every apple sapling stage in every season onto one contact sheet,
## plus the shared strip beside it, so what the grid really slices can be
## looked at rather than only asserted. Headless-safe: composited with
## Image.blend_rect, never through a SubViewport (no renderer here).

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const CELL := Vector2i(160, 240)
const BACKGROUND := Color(0.42, 0.51, 0.35, 1.0)


func _init() -> void:
	var art := IllustratedTree.new()
	var stages := art.sapling_frame_count("apple")
	var seasons: Array = SeasonCycle.SEASONS.duplicate()
	seasons.append("SNOW")
	var sheet := Image.create(
		CELL.x * stages, CELL.y * seasons.size(), false, Image.FORMAT_RGBA8
	)
	sheet.fill(BACKGROUND)
	for row in seasons.size():
		var season: String = seasons[row]
		var snow := 1.0 if season == "SNOW" else 0.0
		var asked: String = "winter" if season == "SNOW" else season
		for stage in stages:
			var frame := art.sapling_frame(stage, "apple", asked, snow)
			var image := frame.get_image()
			image.convert(Image.FORMAT_RGBA8)
			image.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
			sheet.blend_rect(
				image, Rect2i(Vector2i.ZERO, CELL), Vector2i(stage * CELL.x, row * CELL.y)
			)
	sheet.save_png("user://apple_sapling_stages.png")
	print("stages=", stages, " seasons=", seasons.size())
	print("written: ", ProjectSettings.globalize_path("user://apple_sapling_stages.png"))
	quit()
