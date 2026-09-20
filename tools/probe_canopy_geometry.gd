extends SceneTree

## Where the mature canopy texture's own content really sits, against where
## the sapling canvas puts a sapling's feet -- the two pictures the morph
## dissolves between have to line up or the hand-off visibly jumps.

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")


func _bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var right := -1
	var top := image.get_height()
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				left = mini(left, x)
				right = maxi(right, x)
				top = mini(top, y)
				bottom = maxi(bottom, y)
	if right < 0:
		return Rect2i()
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


func _init() -> void:
	print("ProceduralTreeSprite.SIZE = ", ProceduralTreeSprite.SIZE)
	print("sapling canvas = ", IllustratedTree.SAPLING_CANVAS_SIZE,
		"  baseline = ", IllustratedTree.SAPLING_BASELINE_Y)
	var bias := 0.0
	for step in 201:
		var at := float(step) / 200.0
		if TreeSpecies.species_for_bias(at) == "apple":
			bias = at
			break
	var sprite := ProceduralTreeSprite.new()
	for season in ["summer", "autumn"]:
		var image := sprite.generate_image_with_fruit(bias, 7, 0, season)
		print("mature apple/", season, ": size=", image.get_size(), " content=", _bounds(image))
	var art := IllustratedTree.new()
	for stage in art.sapling_frame_count("apple"):
		var frame := art.sapling_frame(stage, "apple", "summer", 0.0).get_image()
		print("sapling stage ", stage, ": size=", frame.get_size(), " content=", _bounds(frame))
	quit()
