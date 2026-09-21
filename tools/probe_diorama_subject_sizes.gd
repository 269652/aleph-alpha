extends SceneTree

## Ground truth for "the character is too small": the REAL drawn extent, in
## world units, of each thing the character-creator diorama stages -- the
## hero, a fully grown tree, the ambient boar -- measured off rendered
## pixels rather than read off a constant that may not survive the rig's
## own scaling.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     -s tools/probe_diorama_subject_sizes.gd

const PROBE_ZOOM := 4.0
const VIEW := Vector2i(900, 900)

var CharacterViewScene
var TreeRenderer
var CreatureRenderer
var HeroAppearance
var TerrainRenderer


func _init() -> void:
	await process_frame
	await process_frame
	CharacterViewScene = load("res://scenes/character_view.tscn")
	TreeRenderer = load("res://src/rendering/tree_renderer.gd")
	CreatureRenderer = load("res://src/rendering/creature_renderer.gd")
	HeroAppearance = load("res://src/rendering/hero_appearance.gd")
	TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")

	await _measure("hero", func(parent):
		var view = CharacterViewScene.instantiate()
		parent.add_child(view)
		view.apply_appearance(HeroAppearance.new().appearance_for("warrior", 0))
		return view
	)
	await _measure("tree", func(parent):
		return TreeRenderer.new().spawn_tree_at(parent, Vector2.ZERO, 7, "acorn")
	)
	await _measure("boar", func(parent):
		return CreatureRenderer.new()._build_marker(
			parent, "boar", Vector2.ZERO, 11, null, TerrainRenderer.TILE_SIZE
		)
	)
	quit()


## Renders `make` alone on a transparent background and reports the opaque
## bounding box converted back to world units -- the honest drawn extent,
## whatever scaling the node applies to itself internally.
func _measure(label: String, make: Callable) -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEW
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * PROBE_ZOOM
	camera.position = Vector2.ZERO
	viewport.add_child(camera)

	var holder := Node2D.new()
	viewport.add_child(holder)
	make.call(holder)
	for _i in 20:
		await process_frame
	RenderingServer.force_draw()
	await process_frame

	var image: Image = viewport.get_texture().get_image()
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.15:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		print("%s: nothing drawn" % label)
	else:
		var w := float(max_x - min_x + 1) / PROBE_ZOOM
		var h := float(max_y - min_y + 1) / PROBE_ZOOM
		# Where the art sits relative to its own origin (the camera is at
		# the origin, so the view's centre IS the node's origin).
		var top := (float(min_y) - float(VIEW.y) * 0.5) / PROBE_ZOOM
		var bottom := (float(max_y + 1) - float(VIEW.y) * 0.5) / PROBE_ZOOM
		print("%s: %.1f x %.1f world units   (origin-relative y: %.1f .. %.1f)" % [label, w, h, top, bottom])
	viewport.queue_free()
	await process_frame
