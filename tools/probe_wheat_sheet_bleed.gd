extends SceneTree

## One-off measurement tool (see illustrated_grass_patch.gd's
## ROW_TOP_BLEED_PX_BY_SEASON doc comment for the exact methodology this
## mirrors): for each of the two new wheat sheets (wheat_spring.png,
## wheat_summer.png, both 1254x1254, 10 columns x 10 rows, chroma-keyed on
## black), measures whether row R's own real (post-chroma-key) content
## extends past its own nominal BOTTOM edge into row R+1's nominal top
## strip -- the exact bleed shape long_grass.md's own art already has and
## was fixed for. Prints, per sheet, per row: the row's own real bottom
## content edge (as an offset PAST its nominal bottom, in native px, 0 or
## negative meaning no bleed) so a real ROW_TOP_BLEED table can be pinned
## from measured numbers instead of eyeballed.
##
## Usage: godot --headless --path . -s tools/probe_wheat_sheet_bleed.gd

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const SHEETS := {
	"wheat_spring": "res://assets/sprites/plants/wheat_spring.png",
	"wheat_summer": "res://assets/sprites/plants/wheat_summer.png",
	"wheat_autumn": "res://assets/sprites/plants/wheat_autumn.png",
}
const COLUMNS := 10
const ROWS := 10
const CHROMA_KEY := Color(0.0, 0.0, 0.0)
const CHROMA_KEY_TOLERANCE := 0.05


func _initialize() -> void:
	for sheet_name: String in SHEETS:
		_probe_sheet(sheet_name, SHEETS[sheet_name])
	quit()


func _probe_sheet(sheet_name: String, path: String) -> void:
	var raw := Image.load_from_file(ProjectSettings.globalize_path(path))
	if raw == null:
		print("%s: FAILED TO LOAD" % sheet_name)
		return
	var keyed := SpriteSheetSlicer.chroma_keyed(raw, CHROMA_KEY, CHROMA_KEY_TOLERANCE)
	var width := keyed.get_width()
	var height := keyed.get_height()
	var cell_w := width / COLUMNS
	var cell_h := height / ROWS
	print("=== %s (%dx%d, cell %dx%d) ===" % [sheet_name, width, height, cell_w, cell_h])

	for row in ROWS:
		var nominal_top := row * height / ROWS
		var nominal_bottom := (row + 1) * height / ROWS
		# Real content bottom edge across the WHOLE row strip's own columns,
		# ignoring column boundaries (a plant can lean into a neighbouring
		# column's own horizontal space without that being "bleed" -- only
		# vertical bleed across the ROW boundary is the concern here,
		# mirroring the grass fix's own per-ROW, not per-cell, table shape).
		var max_content_bottom := -1
		for y in range(nominal_top, nominal_bottom):
			for x in width:
				if keyed.get_pixel(x, y).a > 0.01:
					max_content_bottom = maxi(max_content_bottom, y)
		var bleed_past_own_bottom := max_content_bottom - (nominal_bottom - 1)
		# Real content TOP edge within this row's own nominal strip -- if it
		# starts BEFORE (above) this row's own nominal top, that means
		# something from the row ABOVE bled INTO this row's top strip (the
		# actual symptom grass's ROW_TOP_BLEED table crops away).
		var min_content_top := height
		for y in range(nominal_top, nominal_bottom):
			for x in width:
				if keyed.get_pixel(x, y).a > 0.01:
					min_content_top = mini(min_content_top, y)
					break
		var content_starts_at_own_top := min_content_top <= nominal_top
		print("  row %d: nominal [%d, %d) | real content top=%d bottom=%d | bleeds past own bottom by %dpx | own top starts flush with nominal top: %s" % [
			row, nominal_top, nominal_bottom, min_content_top, max_content_bottom,
			maxi(bleed_past_own_bottom, 0), content_starts_at_own_top
		])
