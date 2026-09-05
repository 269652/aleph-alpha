extends SceneTree

## Dev tool: renders a small grid of trees at REAL tile spacing (16 world
## units) with TreePlacement's own real per-tile density check and
## TreeRenderer._stand_position's own real per-tree jitter, via a real GPU
## viewport at the game's real 4.0x zoom -- built to directly check
## whether a WORLD_SIZE increase crowds a forest the way a previously-
## tried-and-reverted 2x (40x56) size once did, before trusting that a
## smaller increase is actually modest enough. Confirmed 2026-09-05 at the
## 25%-bigger WORLD_SIZE (25x33): individual canopies stay visually
## distinguishable even where crowns overlap, not an undifferentiated
## green mass. Kept for the next time a tree/decor size change needs the
## same "does a whole forest still read right" check, not just one tree in
## isolation.
##
## NOT headless-safe: needs a real GPU viewport readback.
## Usage: godot --path <project> --rendering-driver opengl3 -s <this file>

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

const OUT_PATH := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/forest_density.png"
const TILE_SIZE := 16
const STAND_OFFSET_FRACTION := 0.34  # mirrors TreeRenderer.STAND_OFFSET_FRACTION


func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


func _stand_position(global_x: int, global_y: int) -> Vector2:
	var span := float(TILE_SIZE) * STAND_OFFSET_FRACTION
	var across := float(PixelNoise.range_index(global_x * 7919 + global_y, 211, 0, 1001)) / 500.0 - 1.0
	var down := float(PixelNoise.range_index(global_x * 104729 + global_y, 223, 0, 1001)) / 500.0 - 1.0
	return Vector2(
		(float(global_x) + 0.5) * float(TILE_SIZE) + across * span,
		(float(global_y) + 0.5) * float(TILE_SIZE) + down * span
	)


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
	camera.position = Vector2(80, 80)
	camera.make_current()

	var placement := TreePlacement.new()
	var tree_sprite := ProceduralTreeSprite.new()
	var placed := 0
	for gy in range(-1, 8):
		for gx in range(-1, 8):
			if not placement.has_tree_at(gx, gy, "forest"):
				continue
			var pos := _stand_position(gx, gy)
			var bias := _bias_for(TreeSpecies.IDS[(gx * 13 + gy * 7) % TreeSpecies.IDS.size()])
			var sprite := Sprite2D.new()
			sprite.texture = tree_sprite.generate_texture_with_fruit(bias, 2, 0, "summer")
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
			sprite.offset.y = -float(ProceduralTreeSprite.SIZE.y) * 0.5
			sprite.position = pos
			sprite.z_index = gy
			root.add_child(sprite)
			placed += 1

	print("placed %d trees" % placed)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var image := get_root().get_texture().get_image()
	var err: Error = image.save_png(OUT_PATH)
	print("saved %s err=%s" % [OUT_PATH, err])
	quit()
