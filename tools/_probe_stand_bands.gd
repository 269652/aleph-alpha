extends SceneTree

## Throwaway: print assets/sprites/buildings/stand.png's real divider_bands
## with absolute pixel positions (not just sizes), on both axes, so the
## tiny anti-aliased slivers next to each true divider can be merged with
## their neighbouring big content band into 5 real row/column bands by
## hand -- see tools/_probe_stand_frame.gd for why the generic
## VariantSheetGrid.art_bands heuristic cannot do this itself (every real
## band here alternates with a similarly-thin sliver, not just at the
## sheet's own margins).

const VariantSheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")


func _init() -> void:
	var image := Image.load_from_file("res://assets/sprites/buildings/stand.png")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	print("rows: ", VariantSheetGrid.divider_bands(image, true))
	print("columns: ", VariantSheetGrid.divider_bands(image, false))
	quit()
