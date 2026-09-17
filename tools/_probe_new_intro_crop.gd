extends SceneTree

## Throwaway: crop corners of the new intro.png to inspect grid structure.

func _init() -> void:
	var img := Image.load_from_file("res://assets/sprites/intro.png")
	print("size: ", img.get_width(), "x", img.get_height())
	var tl := img.get_region(Rect2i(0, 0, 200, 200))
	tl.save_png("res://tools/_probe_tl.png")
	var full_row := img.get_region(Rect2i(0, 0, img.get_width(), 160))
	full_row.save_png("res://tools/_probe_row0.png")
	quit()
