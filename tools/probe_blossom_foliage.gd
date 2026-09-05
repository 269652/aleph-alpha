extends SceneTree

## Dev tool: visually verify IllustratedTree's new spring/blossom foliage
## closeup detection actually looks like a plausible blossom/petal/catkin,
## not an accidental crop of trunk, twig, or unrelated art -- numeric tests
## (real content, differs from summer/autumn, no hue restriction needed)
## can confirm the MECHANISM picked something without confirming the
## result reads as believable blossom.
##
## Headless-safe: pure Image/IllustratedTree work, no GPU/viewport.
##
## Usage: godot --headless --path . -s tools/probe_blossom_foliage.gd

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const OUT_PATH := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/blossom_foliage.png"


func _initialize() -> void:
	var trees := IllustratedTree.new()
	var species_list: Array = TreeSpecies.IDS
	var cell := 160
	var margin := 8
	var cell_w := cell * 3 + margin * 2
	var row_h := cell + margin

	var sheet := Image.create(cell_w, row_h * species_list.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.15, 1.0))

	for i in species_list.size():
		var species: String = species_list[i]
		var seasons := ["spring", "summer", "autumn"]
		for j in seasons.size():
			var frame := trees.foliage_leaf_for(species, seasons[j])
			if frame == null:
				continue
			var image := frame.get_image()
			image = image.duplicate()
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
			var scale: float = minf(float(cell) / image.get_width(), float(cell) / image.get_height())
			var w := maxi(1, int(image.get_width() * scale))
			var h := maxi(1, int(image.get_height() * scale))
			image.resize(w, h, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(
				image, Rect2i(0, 0, w, h),
				Vector2i(j * (cell + margin) + (cell - w) / 2, i * row_h + (cell - h) / 2)
			)
		print("row %d: %s -- spring | summer | autumn" % [i, species])

	var err := sheet.save_png(OUT_PATH)
	print("saved: %s (err=%s)" % [OUT_PATH, err])
	quit()
