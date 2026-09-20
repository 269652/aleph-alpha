extends SceneTree

## Measures what slicing the apple sapling sheet actually costs, and what
## grid detect_rows/detect_frames find in it.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")


func _init() -> void:
	var path := "res://assets/sprites/trees/composite_apple_sapling.png"
	var start := Time.get_ticks_msec()
	var sheet := SpriteSheetLoader.load_image(path)
	print("load: ", Time.get_ticks_msec() - start, "ms  size=", sheet.get_size())

	var slicer := SpriteSheetSlicer.new()
	start = Time.get_ticks_msec()
	var rows := slicer.detect_rows(sheet, 0, sheet.get_width(), 40)
	print("detect_rows on the RAW sheet: ", Time.get_ticks_msec() - start, "ms")
	for row in rows:
		print("   row ", row, "  columns: ", slicer.detect_frames(sheet, row.position.y, row.end.y, 40))

	start = Time.get_ticks_msec()
	var keyed := SpriteSheetSlicer.checkerboard_keyed(sheet)
	print("whole-sheet checkerboard flood: ", Time.get_ticks_msec() - start, "ms")
	start = Time.get_ticks_msec()
	var keyed_rows := slicer.detect_rows(keyed, 0, keyed.get_width(), 40)
	print("detect_rows on the KEYED sheet: ", Time.get_ticks_msec() - start, "ms -> ", keyed_rows.size(), " rows")
	for row in keyed_rows:
		print("   row ", row, "  columns: ", slicer.detect_frames(keyed, row.position.y, row.end.y, 40).size())
	quit()
