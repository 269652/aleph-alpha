extends SceneTree

## Follow-up to probe_spell_distortion_render.gd: that probe's 25px
## checkerboard tiles didn't reveal anything wrong by eye, which does not
## clear the shader -- a forced-opaque quad redrawing a sub-texel-shifted
## resample of its own background is a blur/seam defect, and a coarse
## checkerboard can hide a one-or-two-pixel blur completely. This probe
## uses a FINE (4px) high-contrast grid so any resampling mismatch at the
## quad's own silhouette-less corners becomes visible as a blurred patch
## against otherwise-crisp grid lines.
##
## Run: xvfb-run -a <godot> --path . --rendering-driver opengl3 -s tools/probe_spell_distortion_fine_grid.gd

const ProceduralSpellEffectSprite = preload("res://src/rendering/procedural_spell_effect_sprite.gd")
const SpellImpactDistortionShader = preload("res://src/rendering/spell_impact_distortion_shader.gd")

const OUT_DIR := "res://tools/spell_distortion_renders"


func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame
	await _render()
	print("DONE")
	quit()


func _capture(viewport: SubViewport) -> Image:
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	return viewport.get_texture().get_image()


func _render():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 200)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	# Fine 4px grid lines on a flat background -- any blur/offset from the
	# shader's resample shows as a fuzzed-out patch against otherwise
	# razor-sharp 1px-spaced lines.
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.5)
	bg.size = Vector2(200, 200)
	viewport.add_child(bg)
	for x in range(0, 200, 4):
		var line := ColorRect.new()
		line.color = Color(1.0, 1.0, 1.0)
		line.size = Vector2(1, 200)
		line.position = Vector2(x, 0)
		viewport.add_child(line)
	for y in range(0, 200, 4):
		var line := ColorRect.new()
		line.color = Color(1.0, 1.0, 1.0)
		line.size = Vector2(200, 1)
		line.position = Vector2(0, y)
		viewport.add_child(line)

	var generator := ProceduralSpellEffectSprite.new()
	var sprite := Sprite2D.new()
	sprite.texture = generator.texture_for("fire_damage")
	# A deliberately sub-pixel, non-grid-aligned position and a non-integer
	# scale -- exactly what real gameplay (camera following a moving
	# player) looks like, and exactly what my first attempt's grid-aligned
	# 3.0x scale at an integer position could have hidden.
	sprite.position = Vector2(100.37, 99.62)
	sprite.scale = Vector2(3.14159, 3.14159)
	sprite.material = SpellImpactDistortionShader.material_for()
	sprite.material.set_shader_parameter("progress", 0.2)
	sprite.material.set_shader_parameter("peak_fraction", 0.2)
	viewport.add_child(sprite)

	var img: Image = await _capture(viewport)
	img.save_png("%s/fine_grid_distorted.png" % OUT_DIR)
	print("saved fine_grid_distorted.png")

	# Control: same scene, no sprite/shader at all -- what the grid should
	# look like with nothing drawn over it, for a direct visual diff.
	sprite.visible = false
	var img_control: Image = await _capture(viewport)
	img_control.save_png("%s/fine_grid_control.png" % OUT_DIR)
	print("saved fine_grid_control.png")

	viewport.queue_free()
