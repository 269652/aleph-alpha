extends SceneTree

## Real-render verification for BlueprintPaletteView (docs/concept/
## planner_mode.md, "The build palette") -- per this codebase's own
## discipline, headless tests alone are not evidence for "what does this
## look like". Renders the REAL widget, configured the way World configures
## it, at every tab.
##
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_build_palette.gd
##
## Reports, per tab: each slot's icon size and how much of that icon is
## really art rather than transparent padding -- the number that says
## whether a picture reads at 48px or is a smudge in a large empty box.
##
## And it sweeps every UI scale the player can actually pick
## (UiScale.MIN_SCALE .. MAX_SCALE), because that setting scales FONT SIZES
## and deliberately not card widths (UiScale's own documented limit). A slot
## too narrow for its own name at 1.75 is exactly how that limit would show
## up here, so the name's real rendered width is measured against the slot
## rather than eyeballed.

const BlueprintPaletteView = preload("res://src/ui/blueprint_palette_view.gd")
const BlueprintPaletteModel = preload("res://src/ui/blueprint_palette_model.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const UiScale = preload("res://src/ui/ui_scale.gd")

const OUT_DIR := "res://tools/build_palette_renders"

var _viewport: SubViewport
var _backdrop: ColorRect
const MARGIN := 8


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame

	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	# An opaque grass-ish backdrop: the palette is drawn OVER the world, and
	# a transparent capture would not show whether the card really carries
	# its own weight against terrain (hud.md's pillar 1).
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.29, 0.45, 0.22, 1.0)
	viewport.add_child(backdrop)

	var view := BlueprintPaletteView.new()
	view.position = Vector2(MARGIN, MARGIN)
	viewport.add_child(view)
	_backdrop = backdrop
	_viewport = viewport
	view.configure(
		UiTheme.new().build_theme(),
		func(blueprint_id: String) -> float:
			return BuildingCatalog.labor_hours_of(blueprint_id),
		func(item_id: String) -> String:
			return String(item_id).capitalize()
	)

	for scale in [UiScale.MIN_SCALE, UiScale.DEFAULT_SCALE, UiScale.MAX_SCALE]:
		UiTheme.new().apply_scale(view.theme, scale)
		print("\n#### ui scale %.2f -- button font %d" % [
			scale, UiScale.font_size(UiTheme.BASE_FONT_SIZE, scale)
		])
		await _sweep_tabs(view, viewport, scale)
	quit()


func _sweep_tabs(view, viewport: SubViewport, scale: float) -> void:
	for category in BlueprintPaletteModel.categories():
		var category_id := String(category["id"])
		var ids: Array = category["blueprint_ids"]
		view.show_category(category_id)
		# The LAST slot armed, not the first: the mark has to land on the
		# right one, and an off-by-one would be invisible with the first.
		var armed := String(ids[ids.size() - 1])
		view.set_selected(armed)
		# The card sizes itself to its slots now (World._fit_blueprint_palette
		# does the same in the game), so the capture follows it rather than a
		# fixed canvas that would simply crop the defect out of the picture.
		var wanted: Vector2 = view.get_combined_minimum_size()
		view.size = wanted
		_viewport.size = Vector2i(wanted) + Vector2i(MARGIN * 2, MARGIN * 2)
		_backdrop.size = Vector2(_viewport.size)
		await process_frame
		await process_frame
		print("\n== tab %s == armed %s" % [category_id, armed])
		print("   footer: %s" % view.footer_text())
		for slot in view.slots():
			print("   %s" % _slot_report(slot))
		var shot := await _capture(viewport)
		if shot == null:
			print("   NO CAPTURE (no rendering device -- use --rendering-driver opengl3)")
			continue
		shot.save_png("%s/palette_%s_%d.png" % [OUT_DIR, category_id, int(round(scale * 100.0))])


func _slot_report(slot: Button) -> String:
	var blueprint_id := String(slot.get_meta("blueprint_id"))
	if slot.icon == null:
		return "%-14s NO ICON" % blueprint_id
	var image := slot.icon.get_image()
	var name_px := slot.get_theme_font("font").get_string_size(
		slot.text, HORIZONTAL_ALIGNMENT_LEFT, -1, slot.get_theme_font_size("font_size")
	).x
	# What the name really has to fit in: the slot minus the stylebox's own
	# left and right padding, not the slot's outer width.
	var padding := slot.get_theme_stylebox("normal").content_margin_left * 2.0
	var room := slot.size.x - padding
	return "%-14s icon %dx%d  art %d%%  name %dpx in %dpx%s" % [
		blueprint_id, image.get_width(), image.get_height(),
		int(round(100.0 * _art_share(image))),
		int(round(name_px)), int(round(room)),
		"   <-- CLIPPED" if name_px > room else "",
	]


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
