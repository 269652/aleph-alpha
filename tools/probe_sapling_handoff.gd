extends SceneTree

## The hand-off, drawn: the last sapling stage, the mature canopy it
## dissolves into, and the two overlaid -- so "seamless" can be looked at
## rather than only asserted. Headless-safe (Image.blend_rect, no viewport).

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const BACKGROUND := Color(0.42, 0.51, 0.35, 1.0)
const GROUND := Color(0.2, 0.16, 0.12, 1.0)


func _apple_bias() -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == "apple":
			return bias
	return 1.0


func _init() -> void:
	var art := IllustratedTree.new()
	var sprite := ProceduralTreeSprite.new()
	var season := "autumn"
	var sapling := art.sapling_frame(
		art.sapling_frame_count("apple") - 1, "apple", season, 0.0
	).get_image()
	sapling.convert(Image.FORMAT_RGBA8)
	var mature := sprite.generate_image_with_fruit(_apple_bias(), 7, 0, season)
	mature.convert(Image.FORMAT_RGBA8)
	var cell := sapling.get_size()
	var sheet := Image.create(cell.x * 3, cell.y, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKGROUND)
	# The ground line every one of them has to stand on.
	for x in sheet.get_width():
		sheet.set_pixel(x, cell.y - 1, GROUND)
		sheet.set_pixel(x, cell.y - 2, GROUND)
	sheet.blend_rect(sapling, Rect2i(Vector2i.ZERO, cell), Vector2i.ZERO)
	sheet.blend_rect(mature, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x, 0))
	sheet.blend_rect(sapling, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x * 2, 0))
	var half := mature.duplicate()
	for y in half.get_height():
		for x in half.get_width():
			var pixel: Color = half.get_pixel(x, y)
			half.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, pixel.a * 0.5))
	sheet.blend_rect(half, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x * 2, 0))
	sheet.save_png("user://apple_sapling_handoff.png")
	print("written: ", ProjectSettings.globalize_path("user://apple_sapling_handoff.png"))
	quit()
