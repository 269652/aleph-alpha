extends SceneTree

## Real-render check for the HUD's right-hand column (docs/concept/hud.md).
##
## Reported with both open: *"The Town Panel and Warehouse / Building panel
## overlap.. a panel should occupy space and make other panels render below
## it.. don't use fixed coords"*. The unit tests pin that the cards stack;
## this shows what stacking actually LOOKS like, and prints each card's own
## rect so an overlap is a number rather than an impression.
##
##   xvfb-run -a <godot> --path . --rendering-driver opengl3 \
##     -s tools/probe_hud_column_flow.gd

const HousePanel = preload("res://scenes/house_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const OUT_DIR := "res://tools/hud_column_renders"
const SIZE := Vector2i(420, 480)
const MARGIN := 8.0

## A warehouse, the building in the report.
const REPORT := {
	"title": "Warehouse",
	"building_id": "warehouse",
	"stored": 205,
	"capacity": 240,
	"needs": {},
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await process_frame

	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.29, 0.45, 0.22, 1.0)
	backdrop.size = Vector2(SIZE)
	viewport.add_child(backdrop)

	var theme := UiTheme.new().build_theme()

	# The same column shape World builds: anchored top-right, growing down
	# and leftward, every card hugging the right edge.
	var column := VBoxContainer.new()
	column.theme = theme
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.offset_left = -MARGIN
	column.offset_right = -MARGIN
	column.offset_top = MARGIN
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.add_theme_constant_override("separation", 4)
	viewport.add_child(column)

	var town := _stand_in_card(theme, "TOWN\nHamlet of Ellingen\n14 households\nFood  stable")
	column.add_child(town)
	town.size_flags_horizontal = Control.SIZE_SHRINK_END

	var panel := HousePanel.new()
	column.add_child(panel)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.show_report(REPORT)

	await process_frame
	await process_frame

	print("town  rect %s" % str(town.get_global_rect()))
	print("panel rect %s" % str(panel.get_global_rect()))
	print("overlap: %s" % ("YES -- STILL BROKEN" if town.get_global_rect().intersects(
		panel.get_global_rect()
	) else "none"))
	print("panel starts %.0fpx below the town card's bottom" % (
		panel.get_global_rect().position.y - town.get_global_rect().end.y
	))

	var shot := await _capture(viewport)
	if shot == null:
		print("NO CAPTURE (use --rendering-driver opengl3 under xvfb-run)")
	else:
		shot.save_png("%s/right_column.png" % OUT_DIR)
		print("saved %s/right_column.png" % OUT_DIR)
	quit()


## A stand-in for the settlement card: World's own builder needs a whole
## live World, and what is being checked here is the COLUMN, not that card's
## contents.
func _stand_in_card(theme: Theme, text: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme = theme
	var label := Label.new()
	label.text = text
	card.add_child(label)
	return card


func _capture(viewport: SubViewport) -> Image:
	await process_frame
	var texture := viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()
