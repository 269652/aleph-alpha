extends SceneTree

## Dev tool: verifies the tree-specific DETAIL_MULTIPLIER=4 change two ways,
## both directly comparable against images already saved earlier THIS
## session under the OLD DETAIL_MULTIPLIER=2:
##
## 1. NATIVE CANVAS, cleanly upscaled for inspection (same 8x factor
##    tools/probe_tree_all_seasons.gd used) -- shows how much of the real
##    source composite-sheet detail actually survives the CPU-side downscale
##    now, independent of camera/screen scaling. Compare against that
##    script's own tree_all_seasons_spring.png / tree_all_seasons_winter.png.
##
## 2. TRUE REAL IN-GAME SCALE (camera zoom 4.0x, sprite drawn at this file's
##    own SPRITE_SCALE -- exactly what TreeRenderer does), full frame --
##    shows how it will actually look to the player. NOTE:
##    tools/probe_wind_sway_shear.gd's own still-frame screenshots
##    (sway_spring_still.png / sway_winter_still.png) left sprite.scale at
##    its Sprite2D default (1.0) rather than setting it to SPRITE_SCALE, so
##    those actually rendered at 4x screen-pixels-per-art-pixel -- DOUBLE the
##    old true in-game ratio of 2.0 -- not a fair same-ratio baseline. This
##    probe's own render is the correct ratio (1.0, this multiplier's true
##    720p ratio) and should be judged on its own terms, not pixel-diffed
##    against that earlier screenshot.
##
## Reported directly, with real evidence (two gameplay screenshots showing a
## season-dependent crispness gap, and a screenshot of the real illustrated
## source sheet at ITS OWN native resolution): "please render the sprites at
## native resolution???" -- mirrors this session's own established rule to
## verify at true rendering scale before claiming something is fixed.
##
## NOT headless-safe: needs a real GPU viewport readback.
## Usage: godot --path <project> --rendering-driver opengl3 -s <this file>

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


func _save_native_upscaled(tree_sprite: ProceduralTreeSprite, cherry_bias: float, season: String) -> void:
	var image := tree_sprite.generate_texture_with_fruit(cherry_bias, 5, 2, season).get_image()
	var big := image.duplicate()
	big.resize(image.get_width() * UPSCALE, image.get_height() * UPSCALE, Image.INTERPOLATE_NEAREST)
	var out_name := "native_res_after_tree_all_seasons_%s.png" % season
	var err: Error = big.save_png(OUT_DIR + out_name)
	print("%s: saved (native %dx%d) err=%s" % [out_name, image.get_width(), image.get_height(), err])


func _render_real_scale(root: Node2D, tree_sprite: ProceduralTreeSprite, cherry_bias: float, season: String, out_name: String) -> void:
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
	var err: Error = full.save_png(OUT_DIR + out_name)
	print("%s: saved err=%s (true in-game ratio=%.2f screen-px/art-px)" % [
		out_name, err, ProceduralTreeSprite.SPRITE_SCALE * 4.0
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
	var cherry_bias := _bias_for("cherry")

	_save_native_upscaled(tree_sprite, cherry_bias, "spring")
	_save_native_upscaled(tree_sprite, cherry_bias, "winter")

	await _render_real_scale(root, tree_sprite, cherry_bias, "spring", "native_res_after_spring_realscale.png")
	await _render_real_scale(root, tree_sprite, cherry_bias, "winter", "native_res_after_winter_realscale.png")

	quit()


func _initialize() -> void:
	call_deferred("_setup")
