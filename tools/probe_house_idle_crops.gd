extends SceneTree

## Reported live with two houses in shot: "There are still two buildings with
## wrong crops ... Please fix the slicer".
##
## Renders every IDLE cell of every cottage lifecycle sheet exactly the way
## the game slices it (BuildingCatalog.finished_sheet_chain ->
## IllustratedStructureSprite.footprint_frame_texture, grid "dividers"), onto
## a flat backdrop, so a bad crop can be SEEN and counted rather than argued
## about.
##
## Usage: godot --headless -s tools/probe_house_idle_crops.gd

const BuildingLifecycleSheet = preload("res://src/rendering/building_lifecycle_sheet.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const OUT_DIR := "/tmp/claude-0/-home-user-aleph-alpha/4db22097-3bec-5763-a71a-e826305ba8f9/scratchpad"
const PAD := 8
const BACKDROP := Color(0.24, 0.33, 0.19)


func _initialize() -> void:
	var sprite := IllustratedStructureSprite.new()
	for s in BuildingLifecycleSheet._COTTAGE_VARIATIONS.size():
		var path: String = BuildingLifecycleSheet._COTTAGE_VARIATIONS[s]
		var frames: Array = []
		var cell_w := 0
		var cell_h := 0
		for row in BuildingLifecycleSheet.IDLE_ROWS:
			for column in BuildingLifecycleSheet.COLUMNS:
				var image: Image = sprite._frame_image(
					path, BuildingLifecycleSheet.COLUMNS, BuildingLifecycleSheet.ROWS,
					row, column, "dividers"
				)
				if image == null:
					print("NO TEXTURE %s r%d c%d" % [path, row, column])
					continue
				cell_w = maxi(cell_w, image.get_width())
				cell_h = maxi(cell_h, image.get_height())
				frames.append({"row": row, "column": column, "image": image})
		if frames.is_empty():
			continue
		var columns: int = BuildingLifecycleSheet.COLUMNS
		var rows: int = BuildingLifecycleSheet.IDLE_ROWS.size()
		var out := Image.create_empty(
			(cell_w + PAD) * columns + PAD, (cell_h + PAD) * rows + PAD, false, Image.FORMAT_RGBA8
		)
		out.fill(BACKDROP)
		for i in frames.size():
			var frame: Dictionary = frames[i]
			var r: int = BuildingLifecycleSheet.IDLE_ROWS.find(int(frame["row"]))
			var c: int = int(frame["column"])
			var image: Image = frame["image"]
			out.blend_rect(
				image, Rect2i(0, 0, image.get_width(), image.get_height()),
				Vector2i(PAD + c * (cell_w + PAD), PAD + r * (cell_h + PAD) + (cell_h - image.get_height()))
			)
		var name: String = path.get_file().get_basename()
		out.save_png("%s/_idle_%s.png" % [OUT_DIR, name])
		print("SAVED %s  cells=%d cell=%dx%d" % [name, frames.size(), cell_w, cell_h])
	quit()
