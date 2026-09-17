extends SceneTree

## Throwaway: inspect why LandmarkSheet.frame_image("stall", ...) has no
## transparent pixels -- checking whether VariantSheetGrid.art_bands is
## picking the wrong row/column bands for assets/sprites/buildings/
## stand.png (a 5x5 grid whose per-cell internal roof/table gap can read as
## a false extra divider row).

const VariantSheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")
const LandmarkSheet = preload("res://src/rendering/landmark_sheet.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")


func _init() -> void:
	var path := LandmarkSheet.sheet_path_for("stall")
	var image := Image.load_from_file("res://assets/sprites/buildings/stand.png")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var row_bands := VariantSheetGrid.art_bands(image, 5, true)
	var column_bands := VariantSheetGrid.art_bands(image, 5, false)
	print("art row bands: ", row_bands)
	print("art column bands: ", column_bands)

	var cell: Vector2i = LandmarkSheet.variant_cell_for("stall", 11)
	print("cell for seed 11: ", cell)
	var rect := VariantSheetGrid.divider_cell_rect(image, 5, 5, cell.y, cell.x)
	print("rect: ", rect)

	var frame: Image = LandmarkSheet.frame_image("stall", 11, IllustratedStructureSprite.new())
	print("frame size: ", frame.get_size())
	var transparent := 0
	var opaque := 0
	for y in range(0, frame.get_height(), 3):
		for x in range(0, frame.get_width(), 3):
			if frame.get_pixel(x, y).a < 0.5:
				transparent += 1
			else:
				opaque += 1
	print("transparent=", transparent, " opaque=", opaque)
	print("sample corner pixel: ", frame.get_pixel(2, 2))
	print("sample center pixel: ", frame.get_pixel(frame.get_width() / 2, frame.get_height() / 2))
	quit()
