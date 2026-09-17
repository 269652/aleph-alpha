extends SceneTree

## Measures the real grid of a building sheet that separates its cells with
## MAGENTA DIVIDER LINES, rather than assuming one (this codebase's own
## "probe before you trust a grid" convention -- see
## tools/probe_house_variant_sheet.gd and IllustratedStructureSprite's own
## header, where a flat row assumption visibly bled one roof into the next).
##
## The sheets delivered on 2026-09-17 (house_1_1.png .. house_1_5.png, 8
## columns x 10 rows) carry something the older 8x5 sheets do not: a row of
## COLUMN LABELS across the top and a column of ROW LABELS down the left,
## both drawn inside their own divider-separated cells, plus a blank margin
## on the right. An even division of the canvas therefore cuts every cell
## in the wrong place. This reports the real bands so the art window can be
## found rather than guessed.
##
## Run: godot --headless -s tools/probe_building_lifecycle_sheet.gd

const VariantSheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")

const _SHEETS := [
	"house_1_1", "house_1_2", "house_1_3", "house_1_4", "house_1_5", "well", "house_1", "stand",
]

const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
## A divider runs nearly the whole way across; a cell's own art never does.
const _LINE_SHARE := 0.6


func _init() -> void:
	for name in _SHEETS:
		var image := Image.load_from_file("res://assets/sprites/buildings/%s.png" % name)
		if image == null:
			print("== ", name, ": not on disk")
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		print("== ", name, " ", image.get_width(), "x", image.get_height())
		for horizontal in [true, false]:
			var axis := "rows" if horizontal else "columns"
			var bands := VariantSheetGrid.divider_bands(image, horizontal)
			var sizes: Array = []
			for band in bands:
				sizes.append((band as Vector2i).y - (band as Vector2i).x + 1)
			print("  %-7s %d bands between dividers: %s" % [axis, bands.size(), str(sizes)])
	quit()
