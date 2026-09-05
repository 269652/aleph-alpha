extends SceneTree

## Dev tool: renders the SAME tree canopy texture at a deliberately
## FRACTIONAL world pixel position (matching TreeRenderer._stand_position's
## own real continuous random jitter -- trees are NOT placed on a clean
## pixel grid) under a real Camera2D at this game's real 4.0x zoom, via a
## real GPU viewport -- to directly SEE whether sub-pixel sprite placement
## plus nearest-neighbour filtering produces uneven, blurry-looking pixel
## scaling, independent of source-texture quality (already fixed
## separately -- see art_resolution.md's Phase 3).
##
## Checked directly (2026-09-05), investigating a live "trees still look
## blurry" report: rendered with rendering/2d/snap/snap_2d_transforms_to_
## pixel OFF (this project's current setting) vs. ON (temporarily, in a
## local project.godot edit, since this setting only takes effect at
## engine start) at the exact same fractional position. No visible
## difference at normal viewing scale for a single tree -- inconclusive,
## not ruled out as a contributing factor for a whole scattered forest, but
## not the dominant cause here. The report traced instead to WORLD_SIZE
## being too small on screen for its own detail to read clearly (see
## ProceduralTreeSprite.WORLD_SIZE's own doc comment). Kept anyway: this is
## still the right tool for the next time a sub-pixel-alignment hypothesis
## needs checking, for trees or any other entity placed off the tile grid.
##
## NOT headless-safe: needs a real GPU viewport readback.
## Usage: godot --path <project> --rendering-driver opengl3 -s <this file>

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/"


func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


func _initialize() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	await process_frame

	var camera := Camera2D.new()
	root.add_child(camera)
	await process_frame
	camera.zoom = Vector2(4.0, 4.0)
	camera.position = Vector2(837.5, 412.5)  # near the tree, itself fractional
	camera.make_current()

	var sprite := Sprite2D.new()
	var tree_sprite := ProceduralTreeSprite.new()
	var cherry_bias := _bias_for("cherry")
	sprite.texture = tree_sprite.generate_texture_with_fruit(cherry_bias, 5, 2, "summer")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The real, reported cause: TreeRenderer._stand_position adds a
	# continuous random offset within the tile for natural variety, so a
	# real tree's own position is essentially never pixel-aligned.
	sprite.position = Vector2(837.37, 412.63)
	root.add_child(sprite)

	get_root().transparent_bg = false
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var viewport := get_root()
	var image := viewport.get_texture().get_image()
	var snap_state: String = "snap_%s" % str(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false))
	var out_path := OUT_DIR + "pixel_snap_test_%s.png" % snap_state
	var err: Error = image.save_png(out_path)
	print("snap_2d_transforms_to_pixel=%s" % ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false))
	print("saved %s err=%s" % [out_path, err])
	quit()
