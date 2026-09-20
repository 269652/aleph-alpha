extends SceneTree

## What a house under construction is actually cut out of, and how badly.
##
## Reported live with a screenshot of a village building a cottage: *"it's
## clipped and doesn't use the intermediate construction sprites so you can
## see the progress... also it's scaled improperly"*.
##
## Cuts the cell BuildingCatalog.construction_sheet_chain asks for, both the
## way the chain names it and the way the SHEET declares itself
## (BuildingLifecycleSheet.grid_for), and measures each:
##   - the cell's own size, against the sheet's even pitch
##   - how much of the cell the drawing actually fills
##   - whether the drawing runs off the cell's edge, which is the clip
##
## Usage: godot --headless --path . -s tools/probe_construction_stage.gd

const OUT_DIR := "res://tools/construction_stage_renders"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var BuildingLifecycleSheet = load("res://src/rendering/building_lifecycle_sheet.gd")
	var sprite = load("res://src/rendering/illustrated_structure_sprite.gd").new()

	for building_id in ["house_small", "house_medium", "house_large"]:
		var seed_value := 4242
		var sheet_grid: Dictionary = BuildingLifecycleSheet.grid_for(building_id)
		var declared := String(sheet_grid.get("grid", "(none)"))
		print("\n=== %s   sheet declares grid=%s ===" % [building_id, declared])
		var finished: Dictionary = BuildingCatalog.finished_sheet_chain(building_id, seed_value)[0]
		var finished_frame: Image = sprite.frame_image(
			String(finished["path"]), int(finished["columns"]), int(finished["rows"]),
			int(finished["row"]), int(finished["column"]), String(finished["grid"])
		)
		if finished_frame != null:
			print("  FINISHED  %s row %d col %d grid=%s -> cell %dx%d" % [
				String(finished["path"]).get_file(), int(finished["row"]), int(finished["column"]),
				String(finished["grid"]), finished_frame.get_width(), finished_frame.get_height(),
			])
		for progress in [0.0, 0.25, 0.5, 0.75, 0.95]:
			var chain: Array = BuildingCatalog.construction_sheet_chain(building_id, seed_value, progress)
			var entry: Dictionary = chain[0]
			print("  progress %.2f -> %s  row %d col %d, chain says grid=%s" % [
				progress, String(entry["path"]).get_file(),
				int(entry["row"]), int(entry["column"]), String(entry["grid"]),
			])
			for grid in [String(entry["grid"])]:
				if grid == "(none)":
					continue
				var frame: Image = sprite.frame_image(
					String(entry["path"]), int(entry["columns"]), int(entry["rows"]),
					int(entry["row"]), int(entry["column"]), grid
				)
				if frame == null:
					print("      %-9s -> no frame" % grid)
					continue
				_report(frame, grid, String(entry["path"]), int(entry["columns"]), int(entry["rows"]))
				if progress == 0.5:
					var path := "%s/%s_%s.png" % [OUT_DIR, building_id, grid]
					frame.save_png(path)
	print("\ndumped to: ", ProjectSettings.globalize_path(OUT_DIR))
	quit()


## The cell, against what it should be: how much of it the drawing fills,
## and whether that drawing is cut off by the cell's own edge.
func _report(frame: Image, grid: String, path: String, columns: int, rows: int) -> void:
	var sheet := Image.load_from_file(path)
	var even := Vector2i(sheet.get_width() / columns, sheet.get_height() / rows) if sheet != null else Vector2i.ZERO
	var low := Vector2i(frame.get_width(), frame.get_height())
	var high := Vector2i(-1, -1)
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a <= 0.5:
				continue
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0:
		print("      %-9s cell %dx%d -- nothing opaque in it at all" % [grid, frame.get_width(), frame.get_height()])
		return
	var drawn := high - low + Vector2i.ONE
	var touches: Array = []
	if low.y == 0:
		touches.append("top")
	if high.y == frame.get_height() - 1:
		touches.append("bottom")
	if low.x == 0:
		touches.append("left")
	if high.x == frame.get_width() - 1:
		touches.append("right")
	print("      %-9s cell %dx%d (even pitch %dx%d)  drawing %dx%d = %.0f%% of the cell   %s" % [
		grid, frame.get_width(), frame.get_height(), even.x, even.y, drawn.x, drawn.y,
		100.0 * float(drawn.x * drawn.y) / float(frame.get_width() * frame.get_height()),
		("CLIPPED at " + ", ".join(touches)) if not touches.is_empty() else "clear of every edge",
	])
