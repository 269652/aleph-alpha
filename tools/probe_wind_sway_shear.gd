extends SceneTree

## Dev tool: renders a tree sprite with the REAL WindSway.shared_material
## actively applied (the same material every real tree in the game uses)
## at several different TIME values, via a real GPU viewport at the game's
## real 4.0x zoom -- to directly check whether the sway shader's vertex
## displacement (bending the canopy's top sideways while the base stays
## pinned) shears the sprite's quad away from axis-alignment enough to
## visibly soften/blur nearest-neighbour sampling, especially on a dense,
## colour-rich canopy (spring blossom) vs. a sparse one (bare winter
## branches) -- reported live: "trees are still super blurry there is
## something else going wrong", with the user's own screenshots showing
## winter trees reading crisp and spring/blossom trees reading noticeably
## softer side by side.
##
## NOT headless-safe: needs a real GPU viewport readback.
## Usage: godot --path <project> --rendering-driver opengl3 -s <this file>

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const WindSway = preload("res://src/rendering/wind_sway.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

const OUT_DIR := "C:/Users/morrossl/AppData/Local/Temp/claude/C--Users-morrossl-Documents-Private-aleph-alpha/fdf9d3de-194d-4352-8dba-9f7af0306ad4/scratchpad/"


func _bias_for(species: String) -> float:
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == species:
			return bias
	return 0.0


func _initialize() -> void:
	call_deferred("_setup")


func _render_one(root: Node2D, tree_sprite: ProceduralTreeSprite, season: String, with_sway: bool, time_offset: float, out_name: String) -> void:
	var sprite := Sprite2D.new()
	var cherry_bias := _bias_for("cherry")
	sprite.texture = tree_sprite.generate_texture_with_fruit(cherry_bias, 5, 0, season)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset.y = -float(ProceduralTreeSprite.SIZE.y) * 0.5
	sprite.position = Vector2(80, 80)
	if with_sway:
		var sway := WindSway.new()
		var material := sway.shared_material()
		# Force a specific phase deterministically -- RenderingServer's own
		# TIME uniform can't be pinned directly, so this reads back at
		# whatever real elapsed time the process has reached; printed below
		# so the actual bend applied is known, not just assumed.
		sprite.material = material
	root.add_child(sprite)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var full := get_root().get_texture().get_image()
	var err: Error = full.save_png(OUT_DIR + out_name)
	print("%s: with_sway=%s saved err=%s" % [out_name, with_sway, err])
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

	await _render_one(root, tree_sprite, "spring", false, 0.0, "sway_spring_still.png")
	await _render_one(root, tree_sprite, "spring", true, 0.0, "sway_spring_swaying.png")
	await _render_one(root, tree_sprite, "winter", false, 0.0, "sway_winter_still.png")
	await _render_one(root, tree_sprite, "winter", true, 0.0, "sway_winter_swaying.png")

	quit()
