extends SceneTree

## What the character-creator diorama ACTUALLY looks like, framed exactly
## the way scenes/main_menu.gd frames it (see docs/concept/
## character_creator_preview_scene.md): one SubViewport at
## DIORAMA_VIEW_SIZE, one Camera2D at the same uniform zoom, one real
## CharacterPreviewDiorama built for a seed.
##
## A headless run paints no pixels, so this needs a real GPU context. Run:
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     -s tools/probe_diorama_render.gd
##
## Saves one PNG per seed plus a measurement of how much of the frame the
## HERO actually occupies -- the number the "make the character way bigger"
## report is really about, measured rather than eyeballed.

## load(), not preload(): preloading compiles the whole diorama/CharacterView
## dependency chain at THIS script's own compile time, before the autoload
## singletons it references (WorldItemBus) exist as identifiers.
var Diorama
var MainMenu

const OUT_DIR := "res://tools/diorama_renders"
const SEEDS := [4021, 99, 1234]
const SETTLE_FRAMES := 40
## The opening frame a player sees when the creator first paints.
const OPENING_FRAMES := 2


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame
	await process_frame
	Diorama = load("res://src/rendering/character_preview_diorama.gd")
	MainMenu = load("res://scenes/main_menu.gd")

	var view: Vector2i = MainMenu.DIORAMA_VIEW_SIZE
	var footprint: Vector2 = Diorama.FOOTPRINT
	print("view=%s footprint=%s zoom=%.3f" % [view, footprint, float(view.x) / footprint.x])

	for seed_value in SEEDS:
		var viewport := SubViewport.new()
		viewport.size = view
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)

		var camera := Camera2D.new()
		camera.zoom = Vector2.ONE * (float(view.x) / footprint.x)
		camera.position = footprint * 0.5
		viewport.add_child(camera)

		var diorama = Diorama.new()
		viewport.add_child(diorama)
		diorama.build(seed_value)

		for _i in OPENING_FRAMES:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		var opening: Image = viewport.get_texture().get_image()
		opening.save_png(ProjectSettings.globalize_path("%s/opening_%d.png" % [OUT_DIR, seed_value]))

		for _i in SETTLE_FRAMES:
			await process_frame
		RenderingServer.force_draw()
		await process_frame

		var image: Image = viewport.get_texture().get_image()
		var path := "%s/diorama_%d.png" % [OUT_DIR, seed_value]
		image.save_png(ProjectSettings.globalize_path(path))
		print("%s  hero=%s" % [path, _hero_extent(diorama, camera, view, footprint)])
		var boar = diorama.boar_node
		if boar != null and boar.texture != null:
			var used: Rect2i = boar.texture.get_image().get_used_rect()
			print("    boar: used=%s local_scale=%s global_scale=%s -> %.1f x %.1f world units at %s" % [
				used.size, boar.scale, boar.global_scale,
				float(used.size.x) * boar.global_scale.x, float(used.size.y) * boar.global_scale.y,
				boar.global_position])
		viewport.queue_free()
		await process_frame

	quit()


## How tall the hero reads ON SCREEN, as a share of the frame -- the honest
## version of "the character is too small".
func _hero_extent(diorama, _camera, view: Vector2i, footprint: Vector2) -> String:
	var hero = diorama.get("character_view")
	if hero == null:
		return "no character view"
	var zoom := float(view.x) / footprint.x
	var rect: Rect2 = _visual_rect(hero)
	if rect.size == Vector2.ZERO:
		return "character view has no drawn extent"
	return "%.1f x %.1f world units -> %.0f x %.0f px of %s (%.0f%% of frame height)" % [
		rect.size.x, rect.size.y,
		rect.size.x * zoom, rect.size.y * zoom, view,
		100.0 * rect.size.y * zoom / float(view.y),
	]


## Union of every descendant Sprite2D's own drawn rect, in the subject's
## own local space -- CharacterView is a rig of sprites with no single
## "size" property to read.
func _visual_rect(node: Node) -> Rect2:
	var rect := Rect2()
	var seen := false
	for child in node.get_children():
		if child is Sprite2D and child.texture != null and child.visible:
			var size: Vector2 = child.texture.get_size() * child.scale
			var at: Vector2 = child.position - size * 0.5
			var own := Rect2(at, size)
			rect = own if not seen else rect.merge(own)
			seen = true
		var nested := _visual_rect(child)
		if nested.size != Vector2.ZERO:
			var moved := Rect2(nested.position + child.position, nested.size) if child is Node2D else nested
			rect = moved if not seen else rect.merge(moved)
			seen = true
	return rect
