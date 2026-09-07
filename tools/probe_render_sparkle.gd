extends SceneTree

## Renders REAL sparkle output and saves PNGs to look at -- per this
## codebase's own established technique (see [[canopy-snow-settles-top-down]]
## memory / docs/concept/snow_cover.md): code tracing alone is not enough
## evidence for "what does this look like". Needs a REAL GPU/window, not
## --headless (SubViewport.get_texture().get_image() returns null under the
## headless driver). Run:
##   <godot> --path . --rendering-driver opengl3 -s tools/probe_render_sparkle.gd

const SnowBombShader = preload("res://src/rendering/snow_bomb_shader.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const OUT_DIR := "res://tools/sparkle_renders"


func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame
	await _render_ground()
	await _render_canopy()
	print("DONE")
	quit()


func _capture(viewport: SubViewport) -> Image:
	RenderingServer.force_draw()
	await process_frame
	RenderingServer.force_draw()
	return viewport.get_texture().get_image()


func _render_ground():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 320)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	root.add_child(viewport)

	var snow := SnowBombShader.new()
	snow.set_snow_depth(1.0)

	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.size = Vector2(320, 320)
	rect.position = Vector2.ZERO
	rect.material = snow.shared_material()
	viewport.add_child(rect)

	Engine.time_scale = 40.0
	for i in 4:
		await create_timer(0.12).timeout
		var img: Image = await _capture(viewport)
		img.save_png("%s/ground_snow_t%d.png" % [OUT_DIR, i])
		print("saved ground_snow_t%d.png" % i)
	Engine.time_scale = 1.0

	viewport.queue_free()


func _position_for_species(species_id: String) -> Vector2:
	var scheduler := ForageScheduler.new()
	for step in 4000:
		var position := Vector2(step * 37, step * 53)
		if TreeSpecies.species_for_bias(scheduler.genome_for(position).species_bias) == species_id:
			return position
	return Vector2.ZERO


func _render_canopy():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(420, 420)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	root.add_child(viewport)

	var generator := ProceduralTreeSprite.new()
	var scheduler := ForageScheduler.new()
	var cherry_pos := _position_for_species("cherry")
	var bias := scheduler.genome_for(cherry_pos).species_bias

	# Spring (blossom) canopy under FULL snow coverage -- the exact scenario
	# the colour gate exists to protect: real illustrated pink blossom AND
	# real illustrated snow on the same composited texture at once.
	var texture := generator.generate_texture_with_fruit(
		bias, hash("cherry"), 0, "spring", "spring", 0.0, 1.0, 1.0
	)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2.ZERO
	var wind := WindSway.new()
	wind.set_snow_coverage(1.0)
	# Sway OFF for this capture: isolates sparkle's own visual contribution
	# from the pre-existing, unrelated wind-sway vertex animation, which
	# otherwise dominates a frame-to-frame diff (canopy edges move several
	# pixels from sway alone -- far more than a handful of glint pixels).
	wind.set_wind_strength(0.0)
	sprite.material = wind.shared_material()
	viewport.add_child(sprite)

	print("cherry spring+snow texture size: ", texture.get_size())

	Engine.time_scale = 40.0
	for i in 4:
		await create_timer(0.12).timeout
		var img: Image = await _capture(viewport)
		img.save_png("%s/cherry_blossom_snow_t%d.png" % [OUT_DIR, i])
		print("saved cherry_blossom_snow_t%d.png" % i)
	Engine.time_scale = 1.0

	viewport.queue_free()
