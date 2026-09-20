extends SceneTree

## What a farmhouse yard really looks like once keyed, and how different the
## nine of them are.
##
## Asked for with the art dropped in: *"it should use a random variation so
## that each farmhouses bg looks different"*. This writes every yard out as
## a real PNG so the keying can be LOOKED at rather than reasoned about, and
## reports each one's opaque fraction.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const OUT := "user://yards"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var sprites := IllustratedStructureSprite.new()
	var sheet := BuildingCatalog.background_sheet_for("farmhouse", 1)
	for row in range(3):
		for column in range(3):
			var texture := sprites.footprint_frame_texture(
				String(sheet["path"]), 3, 3, row, column, 96, 3, "even"
			)
			if texture == null:
				print("RESULT yard %d,%d = null" % [column, row])
				continue
			var image := texture.get_image()
			var opaque := 0
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					if image.get_pixel(x, y).a > 0.5:
						opaque += 1
			image.save_png("%s/yard_%d%d.png" % [OUT, column, row])
			print("RESULT yard %d,%d %dx%d opaque=%.3f" % [
				column, row, image.get_width(), image.get_height(),
				float(opaque) / float(image.get_width() * image.get_height()),
			])
	print("RESULT wrote to %s" % ProjectSettings.globalize_path(OUT))
	quit()
