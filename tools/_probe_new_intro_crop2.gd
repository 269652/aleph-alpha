extends SceneTree

func _init() -> void:
	var img := Image.load_from_file("res://assets/sprites/intro.png")
	var h := img.get_height()
	var last_row := img.get_region(Rect2i(0, h - 160, 1200, 160))
	last_row.save_png("res://tools/_probe_last_row.png")
	quit()
