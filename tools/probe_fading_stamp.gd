extends SceneTree

## Dev tool: visually verify LeafLitterAtlas's new "fading" stamp (the
## middle of the reported "3 seasons" decay -- fresh -> fading -> winter)
## actually reads as a believable HALFWAY-decayed leaf, not indistinguishable
## from either endpoint -- numeric tests (silhouette match, saturation
## strictly between the two, exact pinned blend, real shading preserved) can
## confirm the MECHANISM without confirming the visual result reads right.
##
## Headless-safe: pure Image/CompositeSheetSlicer work, no GPU/viewport.
##
## Usage: godot --headless --path . -s tools/probe_fading_stamp.gd

const LeafLitterAtlas = preload("res://src/rendering/leaf_litter_atlas.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const OUT_PATH := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/leaf_fading_stamps.png"


func _initialize() -> void:
	var atlas := LeafLitterAtlas.new()
	var species_list: Array = TreeSpecies.IDS
	var stamp_size := LeafLitterAtlas.STAMP_SIZE
	var margin := 8
	var cell_w := stamp_size * 3 + margin * 2
	var row_h := stamp_size + margin

	var sheet := Image.create(cell_w, row_h * species_list.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.15, 1.0))

	for i in species_list.size():
		var species: String = species_list[i]
		var autumn := atlas.build_stamp_image(species, "autumn")
		var fading := atlas.build_stamp_image(species, "fading")
		var winter := atlas.build_stamp_image(species, "winter")
		sheet.blit_rect(autumn, Rect2i(0, 0, stamp_size, stamp_size), Vector2i(0, i * row_h))
		sheet.blit_rect(
			fading, Rect2i(0, 0, stamp_size, stamp_size), Vector2i(stamp_size + margin, i * row_h)
		)
		sheet.blit_rect(
			winter, Rect2i(0, 0, stamp_size, stamp_size), Vector2i((stamp_size + margin) * 2, i * row_h)
		)
		print("row %d: %s -- autumn (left) | fading (mid) | winter (right)" % [i, species])

	var err := sheet.save_png(OUT_PATH)
	print("saved: %s (err=%s)" % [OUT_PATH, err])
	quit()
