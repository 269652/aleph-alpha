extends SceneTree

## Renders a REAL burst-family spell effect with SpellImpactDistortionShader
## applied, over a distinguishable checkerboard background, and saves PNGs --
## the same "code tracing alone is not enough evidence" technique
## probe_render_sparkle.gd established. Needs a REAL GPU/window, not
## --headless (SubViewport.get_texture().get_image() returns null under the
## headless driver). Run:
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 -s tools/probe_spell_distortion_render.gd
##
## Reported live: "spells show no improvement in rendering and now render a
## visible square which looks broken" -- this is the direct, photographic
## check for that report, not just the string/unit tests.

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

	# A distinguishable, non-uniform background -- a flat colour behind the
	# effect would make "shows the background" and "shows a flat colour"
	# look identical. A checkerboard makes them visibly different.
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.6, 0.2)
	bg.size = Vector2(200, 200)
	viewport.add_child(bg)
	for y in 4:
		for x in 4:
			if (x + y) % 2 == 0:
				continue
			var tile := ColorRect.new()
			tile.color = Color(0.9, 0.9, 0.1)
			tile.size = Vector2(25, 25)
			tile.position = Vector2(x * 50, y * 50)
			viewport.add_child(tile)

	var generator := ProceduralSpellEffectSprite.new()
	var sprite := Sprite2D.new()
	sprite.texture = generator.texture_for("fire_damage")
	sprite.position = Vector2(100, 100)
	sprite.scale = Vector2(3.0, 3.0)
	assert(SpellImpactDistortionShader.atom_gets_distortion("fire_damage"), "precondition: fire_damage is burst-family")
	sprite.material = SpellImpactDistortionShader.material_for()
	sprite.material.set_shader_parameter("progress", 0.2)
	sprite.material.set_shader_parameter("peak_fraction", 0.2)
	viewport.add_child(sprite)

	var img: Image = await _capture(viewport)
	img.save_png("%s/fire_damage_burst_distorted.png" % OUT_DIR)
	print("saved fire_damage_burst_distorted.png")

	# Same frame with the shader's own `progress` at 0 (no distortion
	# strength at all) -- the control: this should look like the sprite's
	# own burst shape with nothing behind it disturbed, proving the
	# shader's OWN art shows correctly with no warp contribution.
	sprite.material.set_shader_parameter("progress", 0.0)
	var img_zero: Image = await _capture(viewport)
	img_zero.save_png("%s/fire_damage_burst_zero_progress.png" % OUT_DIR)
	print("saved fire_damage_burst_zero_progress.png")

	viewport.queue_free()
