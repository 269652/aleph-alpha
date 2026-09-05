extends SceneTree

## Dev tool: visually verify LeafLitterAtlas's derived "winter" (decayed
## fallen-leaf) stamp actually looks acceptable -- side by side with the
## real illustrated "autumn" stamp it's derived from -- since numeric tests
## (silhouette match / reduced saturation / preserved shading) can confirm
## the MECHANISM is doing what it claims without confirming the result
## reads as a believable decayed leaf rather than, say, a flat brown smear.
##
## Headless-safe: build_stamp_image is pure Image/CPU work, no GPU/viewport
## involved.
##
## Usage: godot --headless --path . -s tools/probe_leaf_winter_stamp.gd

const LeafLitterAtlas = preload("res://src/rendering/leaf_litter_atlas.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const OUT_PATH := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/leaf_winter_stamps.png"


func _initialize() -> void:
	var atlas := LeafLitterAtlas.new()
	var species_list: Array = TreeSpecies.IDS
	var stamp_size := LeafLitterAtlas.STAMP_SIZE
	var margin := 8
	var cell_w := stamp_size * 2 + margin
	var row_h := stamp_size + margin

	var sheet := Image.create(
		cell_w, row_h * species_list.size(), false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(0.15, 0.15, 0.15, 1.0))

	for i in species_list.size():
		var species: String = species_list[i]
		var autumn := atlas.build_stamp_image(species, "autumn")
		var winter := atlas.build_stamp_image(species, "winter")
		sheet.blit_rect(
			autumn, Rect2i(0, 0, stamp_size, stamp_size), Vector2i(0, i * row_h)
		)
		sheet.blit_rect(
			winter, Rect2i(0, 0, stamp_size, stamp_size), Vector2i(stamp_size + margin, i * row_h)
		)
		print("row %d: %s -- autumn (left) vs winter (right)" % [i, species])

	var err := sheet.save_png(OUT_PATH)
	print("saved: %s (err=%s)" % [OUT_PATH, err])
	quit()
