extends SceneTree

## Dev tool: the CURRENT (DETAIL_MULTIPLIER=4) composited canopy for spring
## vs summer/autumn/winter, all at the identical treatment, side by side --
## isolates whether spring specifically fares worse under the SAME pipeline/
## canvas size the other three seasons already read fine at (per direct
## report: "summer is crisp... autumn is fine as well... winter also...
## please fix spring").
##
## Headless-safe: pure Image work, no GPU/viewport.
## Usage: godot --headless --path <project> -s <this file>

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/"
const UPSCALE := 8


func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


func _save_upscaled(image: Image, out_name: String) -> void:
	var big := image.duplicate()
	big.resize(image.get_width() * UPSCALE, image.get_height() * UPSCALE, Image.INTERPOLATE_NEAREST)
	var err: Error = big.save_png(OUT_DIR + out_name)
	print("saved %s (native %dx%d) err=%s" % [out_name, image.get_width(), image.get_height(), err])


func _initialize() -> void:
	var sprite := ProceduralTreeSprite.new()
	var cherry_bias := _bias_for("cherry")

	print("SIZE=%dx%d WORLD_SIZE=%dx%d DETAIL_MULTIPLIER=%d" % [
		ProceduralTreeSprite.SIZE.x, ProceduralTreeSprite.SIZE.y,
		ProceduralTreeSprite.WORLD_SIZE.x, ProceduralTreeSprite.WORLD_SIZE.y,
		ProceduralTreeSprite.DETAIL_MULTIPLIER
	])

	for season in ["spring", "summer", "autumn", "winter"]:
		var canopy_box := sprite.illustrated_canopy_box("cherry", 5, season)
		print("%s: canopy box=%dx%d at (%d,%d)" % [
			season, canopy_box.size.x, canopy_box.size.y, canopy_box.position.x, canopy_box.position.y
		])
		var image := sprite.generate_texture_with_fruit(cherry_bias, 5, 2, season).get_image()
		_save_upscaled(image, "current_pipeline_%s.png" % season)

	quit()
