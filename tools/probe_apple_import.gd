extends SceneTree

## Is the imported apple sheet the same pixels as the source PNG on disk?

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")


func _init() -> void:
	var path := "res://assets/sprites/trees/composite_apple.png"
	var imported := (load(path) as Texture2D).get_image()
	var raw := Image.new()
	raw.load(path)
	if raw.get_format() != imported.get_format():
		raw.convert(imported.get_format())
	print("imported: ", imported.get_size(), " fmt=", imported.get_format())
	print("raw:      ", raw.get_size(), " fmt=", raw.get_format())
	print("identical bytes: ", imported.get_data() == raw.get_data())
	var differing := 0
	var differing_opaque := 0
	for y in range(0, imported.get_height(), 3):
		for x in range(0, imported.get_width(), 3):
			var a := imported.get_pixel(x, y)
			var b := raw.get_pixel(x, y)
			if a != b:
				differing += 1
				if a.a > 0.5 or b.a > 0.5:
					differing_opaque += 1
	print("sampled differing pixels: ", differing, " of which opaque: ", differing_opaque)
	quit()
