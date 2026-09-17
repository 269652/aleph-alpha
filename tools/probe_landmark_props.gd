extends SceneTree

## Every village prop's own procedural drawing, side by side and upscaled,
## so "does a hunter's spot read as a hunter's spot and not as a well" is
## answered by looking rather than by asserting pixel colours.
##
## Used exactly that way on 2026-09-17: a first pass drew the hide as a
## symmetric oval, which rendered as a drum head rather than a skin, so the
## shape was retuned (widest across the shoulders a third of the way down,
## tapering to a narrow tail) and looked at again.

const OUT := "res://tools/landmark_prop_renders/props.png"
const SCALE := 5
const PAD := 4


func _initialize() -> void:
	var ProceduralLandmarkSprite = load("res://src/rendering/procedural_landmark_sprite.gd")
	var generator = ProceduralLandmarkSprite.new()
	var ids: Array = ProceduralLandmarkSprite.LANDMARK_IDS
	var images: Array = []
	var width := 0
	var height := 0
	for id in ids:
		var image: Image = generator.generate_image(id)
		images.append(image)
		width += image.get_width() + PAD
		height = maxi(height, image.get_height())
	var sheet := Image.create(width + PAD, height + PAD * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.18, 0.2, 0.16, 1.0))
	var x := PAD
	for image in images:
		sheet.blend_rect(
			image, Rect2i(Vector2i.ZERO, image.get_size()),
			Vector2i(x, PAD + height - image.get_height())
		)
		x += image.get_width() + PAD
	sheet.resize(sheet.get_width() * SCALE, sheet.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	sheet.save_png(OUT)
	print("order: ", ids)
	print("saved ", ProjectSettings.globalize_path(OUT))
	quit()
