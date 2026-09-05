extends SceneTree

## Dev tool: renders spring's canopy scaled to several CANDIDATE box sizes
## (bigger than the current ~108x95, which the direct comparison against
## summer showed is not enough) to find the smallest that reads comparably
## legible to summer's current, already-accepted size -- grounding the
## chosen multiplier in an actual visual check rather than picking one
## blind.
##
## Headless-safe: pure Image work, no GPU/viewport.
## Usage: godot --headless --path <project> -s <this file>

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/"
const UPSCALE := 4


func _initialize() -> void:
	var illustrated := IllustratedTree.new()
	var raw := illustrated.canopy_for("cherry", "spring").get_image()
	print("spring raw source crop: %dx%d" % [raw.get_width(), raw.get_height()])

	# Current box width is ~108 (SIZE.x=100 * ~1.08 variance roll). Candidates
	# at 1.5x/2x/2.5x/3x that, each preserving the source's own aspect ratio.
	var current_width := 108
	for candidate_multiplier in [1.0, 1.5, 2.0, 2.5, 3.0]:
		var width := int(round(current_width * candidate_multiplier))
		var height := int(round(float(raw.get_height()) * float(width) / float(raw.get_width())))
		var scaled := ProceduralTreeSprite.scale_piece(raw, Vector2i(width, height))
		var big := scaled.duplicate()
		big.resize(width * UPSCALE, height * UPSCALE, Image.INTERPOLATE_NEAREST)
		var out_name := "spring_box_candidate_%.1fx.png" % candidate_multiplier
		var err: Error = big.save_png(OUT_DIR + out_name)
		print("%.1fx: box=%dx%d saved %s err=%s" % [candidate_multiplier, width, height, out_name, err])

	quit()
