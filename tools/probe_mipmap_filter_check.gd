extends SceneTree

## Dev tool: with DETAIL_MULTIPLIER temporarily raised to 12 (matching
## spring's measured native source width almost exactly), the true
## screen-pixels-per-art-pixel ratio drops to ~0.33 at 720p -- the texture
## WILL be minified live. Renders spring at the REAL resulting on-screen
## scale, once with NEAREST (today's filter) and once with mipmapped LINEAR,
## to check whether mipmaps actually resolve the minification cleanly rather
## than just moving the "arbitrary pixel, discard the rest" problem from
## CPU authoring time to the GPU, every frame.
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


func _render_one(root: Node2D, tree_sprite: ProceduralTreeSprite, season: String, use_mipmaps: bool, out_name: String) -> void:
	var sprite := Sprite2D.new()
	var cherry_bias := _bias_for("cherry")
	var image := tree_sprite.generate_texture_with_fruit(cherry_bias, 5, 0, season).get_image()
	var texture: ImageTexture
	if use_mipmaps:
		var with_mips := image.duplicate()
		with_mips.generate_mipmaps()
		texture = ImageTexture.create_from_image(with_mips)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	else:
		texture = ImageTexture.create_from_image(image)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = texture
	# Real screen ratio: SPRITE_SCALE(1/12) * zoom(4.0) = ~0.33 at 720p (this
	# viewport's own resolution below), matching the true in-game 720p case.
	sprite.scale = Vector2.ONE * ProceduralTreeSprite.SPRITE_SCALE
	sprite.offset.y = -float(ProceduralTreeSprite.SIZE.y) * 0.5
	sprite.position = Vector2(80, 80)
	root.add_child(sprite)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var full := get_root().get_texture().get_image()
	var err: Error = full.save_png(OUT_DIR + out_name)
	# Also save a cropped, upscaled version -- at the true minified on-screen
	# size (~25x33px before this crop) the difference between NEAREST and
	# LINEAR_WITH_MIPMAPS is real but too small in a full 1280x720 frame to
	# actually see; this is what the doc comments above and in
	# docs/progress.md's "spring specifically fixed" entry were judged from.
	var cropped := full.get_region(Rect2i(580, 225, 120, 160))
	cropped.resize(120 * 6, 160 * 6, Image.INTERPOLATE_NEAREST)
	var cropped_name := out_name.replace(".png", "_cropped.png")
	var cropped_err: Error = cropped.save_png(OUT_DIR + cropped_name)
	print("%s: saved err=%s (mipmaps=%s), %s: saved err=%s" % [
		out_name, err, use_mipmaps, cropped_name, cropped_err
	])
	sprite.queue_free()
	await process_frame


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

	var tree_sprite := ProceduralTreeSprite.new()
	print("SIZE=%dx%d SPRITE_SCALE=%.4f real_ratio_at_720p=%.3f" % [
		ProceduralTreeSprite.SIZE.x, ProceduralTreeSprite.SIZE.y,
		ProceduralTreeSprite.SPRITE_SCALE, ProceduralTreeSprite.SPRITE_SCALE * 4.0
	])

	await _render_one(root, tree_sprite, "spring", false, "mipcheck_spring_nearest.png")
	await _render_one(root, tree_sprite, "spring", true, "mipcheck_spring_mipmap_linear.png")
	await _render_one(root, tree_sprite, "summer", false, "mipcheck_summer_nearest.png")
	await _render_one(root, tree_sprite, "summer", true, "mipcheck_summer_mipmap_linear.png")

	quit()


func _initialize() -> void:
	call_deferred("_setup")
