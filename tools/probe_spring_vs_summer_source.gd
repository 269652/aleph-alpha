extends SceneTree

## Dev tool: user narrowed the report considerably after the native-resolution
## fix landed -- "It's only spring... summer is crisp", "autumn is fine as
## well", "winter also", "please fix spring". So this is NOT a generic
## resolution shortfall (which would hit every season alike): something about
## SPRING specifically. Dumps the RAW, untouched per-season canopy crop
## (straight off the composite sheet, no scale_piece involved at all) for
## every season side by side, to see whether the softness is already present
## in the SOURCE ART itself (an authoring/content difference) or only
## appears after this codebase's own processing (a real pipeline bug).
##
## Headless-safe: pure Image work, no GPU/viewport.
## Usage: godot --headless --path <project> -s <this file>

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/"
const UPSCALE := 4


func _initialize() -> void:
	var illustrated := IllustratedTree.new()

	for season in ["spring", "summer", "autumn", "winter"]:
		var canopy_tex := illustrated.canopy_for("cherry", season)
		if canopy_tex == null:
			print("%s: canopy_for returned null" % season)
			continue
		var image := canopy_tex.get_image()
		print(
			"%s: RAW source crop size=%dx%d format=%d has_mipmaps=%s"
			% [season, image.get_width(), image.get_height(), image.get_format(), image.has_mipmaps()]
		)
		var big := image.duplicate()
		big.resize(image.get_width() * UPSCALE, image.get_height() * UPSCALE, Image.INTERPOLATE_NEAREST)
		var err: Error = big.save_png(OUT_DIR + "raw_source_crop_%s.png" % season)
		print("  saved raw_source_crop_%s.png err=%s" % [season, err])

	quit()
