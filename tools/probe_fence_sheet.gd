extends SceneTree

## Does VariantSheetGrid read assets/sprites/buildings/fence.png the way the
## sheet is actually drawn? Delivered 2026-09-17 as 1536x1024 with magenta
## dividers, a printed column-label row across the top and a row-label
## gutter down the left -- the same contract the house lifecycle sheets use
## (tools/probe_building_lifecycle_sheet.gd), but 4 orientation columns by
## 3 condition rows.
##
## Prints the bands it detects and writes every cell out as a PNG, so the
## crop is LOOKED AT rather than assumed.

const OUT_DIR := "user://fence_probe"


func _initialize() -> void:
	var SpriteSheetLoader = load("res://src/rendering/sprite_sheet_loader.gd")
	var VariantSheetGrid = load("res://src/rendering/variant_sheet_grid.gd")
	var path := "res://assets/sprites/buildings/fence.png"
	var image = SpriteSheetLoader.load_image(path)
	if image == null:
		print("could not load ", path)
		quit()
		return
	print("sheet: ", image.get_width(), "x", image.get_height())

	var all_cols: Array = VariantSheetGrid.divider_bands(image, false)
	var all_rows: Array = VariantSheetGrid.divider_bands(image, true)
	print("divider bands: ", all_cols.size(), " columns, ", all_rows.size(), " rows")
	print("  columns: ", all_cols)
	print("  rows:    ", all_rows)

	var art_cols: Array = VariantSheetGrid.art_bands(image, 4, false)
	var art_rows: Array = VariantSheetGrid.art_bands(image, 3, true)
	print("art bands (4 x 3):")
	print("  columns: ", art_cols)
	print("  rows:    ", art_rows)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var names := ["north", "south", "east", "west"]
	var conditions := ["pristine", "worn", "destroyed"]
	for r in art_rows.size():
		for c in art_cols.size():
			var rect := Rect2i(
				art_cols[c].x, art_rows[r].x,
				art_cols[c].y - art_cols[c].x, art_rows[r].y - art_rows[r].x
			)
			var cell = image.get_region(rect)
			var out := "%s/%s_%s.png" % [OUT_DIR, conditions[r], names[c]]
			cell.save_png(ProjectSettings.globalize_path(out))
			print("  ", conditions[r], " ", names[c], " -> ", rect, " saved ", out)
	quit()
