extends SceneTree

## Dev tool: final verification of DETAIL_MULTIPLIER=12 across ALL FOUR
## seasons -- both a clean native-canvas upscale (direct before/after
## comparison against the DETAIL_MULTIPLIER=4 native_res_after_* renders
## from the prior pass) and a render at the TRUE real in-game camera ratio
## (0.33 at 720p -- genuinely minified now, not neutral), full frame, so
## nothing is judged from an artificially zoomed-in crop alone.
##
## NOT headless-safe: needs a real GPU viewport readback.
## Usage: godot --path <project> --rendering-driver opengl3 -s <this file>

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/"
const UPSCALE := 4


func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


func _save_native_upscaled(tree_sprite: ProceduralTreeSprite, cherry_bias: float, season: String) -> void:
	var image := tree_sprite.generate_texture_with_fruit(cherry_bias, 5, 2, season).get_image()
	var big := image.duplicate()
	big.resize(image.get_width() * UPSCALE, image.get_height() * UPSCALE, Image.INTERPOLATE_NEAREST)
	var out_name := "final_v2_native_%s.png" % season
	var err: Error = big.save_png(OUT_DIR + out_name)
	print("%s: saved (native %dx%d) err=%s" % [out_name, image.get_width(), image.get_height(), err])


func _render_real_scale(root: Node2D, tree_sprite: ProceduralTreeSprite, cherry_bias: float, season: String) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = tree_sprite.generate_texture_with_fruit(cherry_bias, 5, 0, season)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * ProceduralTreeSprite.SPRITE_SCALE
	sprite.offset.y = -float(ProceduralTreeSprite.SIZE.y) * 0.5
	sprite.position = Vector2(80, 80)
	root.add_child(sprite)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var full := get_root().get_texture().get_image()
	var out_name := "final_v2_realscale_%s.png" % season
	var err: Error = full.save_png(OUT_DIR + out_name)
	print("%s: saved err=%s" % [out_name, err])
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
	var cherry_bias := _bias_for("cherry")
	print("SIZE=%dx%d DETAIL_MULTIPLIER=%d" % [
		ProceduralTreeSprite.SIZE.x, ProceduralTreeSprite.SIZE.y, ProceduralTreeSprite.DETAIL_MULTIPLIER
	])

	for season in ["spring", "summer", "autumn", "winter"]:
		_save_native_upscaled(tree_sprite, cherry_bias, season)
		await _render_real_scale(root, tree_sprite, cherry_bias, season)

	quit()


func _initialize() -> void:
	call_deferred("_setup")
