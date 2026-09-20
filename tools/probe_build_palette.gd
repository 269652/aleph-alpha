extends SceneTree

## Real-render verification for BlueprintPaletteView (docs/concept/
## planner_mode.md, "The build palette") -- per this codebase's own
## discipline, headless tests alone are not evidence for "what does this
## look like". Renders the REAL widget, configured the way World configures
## it, at every tab and with something armed.
##
##   <godot> --path . --rendering-driver opengl3 -s tools/probe_build_palette.gd
##
## Reports, per tab: the slot count, each slot's own icon size and how much
## of that icon is really art rather than transparent padding -- the number
## that says whether a picture reads at 48px or is a smudge in a large
## empty box.

const BlueprintPaletteView = preload("res://src/ui/blueprint_palette_view.gd")
const BlueprintPaletteModel = preload("res://src/ui/blueprint_palette_model.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const OUT_DIR := "res://tools/build_palette_renders"
const SIZE := Vector2i(500, 210)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame

	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	# An opaque grass-ish backdrop: the palette is drawn OVER the world, and
	# a transparent capture would not show whether the card really carries
	# its own weight against terrain (hud.md's pillar 1).
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.29, 0.45, 0.22, 1.0)
	backdrop.size = Vector2(SIZE)
	viewport.add_child(backdrop)

	var view := BlueprintPaletteView.new()
	view.position = Vector2(8, 8)
	view.size = Vector2(SIZE.x - 16, SIZE.y - 16)
	viewport.add_child(view)
	view.configure(
		UiTheme.new().build_theme(),
		func(blueprint_id: String) -> float:
			return BuildingCatalog.labor_hours_of(blueprint_id),
		func(item_id: String) -> String:
			return String(item_id).capitalize()
	)

	for category in BlueprintPaletteModel.categories():
		var category_id := String(category["id"])
		view.show_category(category_id)
		var armed := String(category["blueprint_ids"][0])
		view.set_selected(armed)
		print("\n== tab %s == armed %s" % [category_id, armed])
		print("   footer: %s" % view.footer_text())
		for slot in view.slots():
			var blueprint_id := String(slot.get_meta("blueprint_id"))
			var texture: Texture2D = slot.icon
			if texture == null:
				print("   %-14s NO ICON" % blueprint_id)
				continue
			var image := texture.get_image()
			print("   %-14s icon %dx%d  art %d%%  tooltip %s" % [
				blueprint_id, image.get_width(), image.get_height(),
				int(round(100.0 * _art_share(image))),
				" / ".join(slot.tooltip_text.split("\n")),
			])
		await process_frame
		await process_frame
		var shot := await _capture(viewport)
		if shot != null:
			shot.save_png("%s/palette_%s.png" % [OUT_DIR, category_id])
			print("   saved %s/palette_%s.png" % [OUT_DIR, category_id])
		else:
			print("   NO CAPTURE (no rendering device -- run with --rendering-driver opengl3)")
	quit()


## How much of the boxed icon is really art. A low number means the picture
## is a smudge floating in transparent padding.
func _art_share(image: Image) -> float:
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				opaque += 1
	return float(opaque) / float(maxi(image.get_width() * image.get_height(), 1))


func _capture(viewport: SubViewport) -> Image:
	await process_frame
	var texture := viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()
