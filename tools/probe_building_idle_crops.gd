extends SceneTree

## Reported live with two buildings in shot: "There are still two buildings
## with wrong crops ... Please fix the slicer".
##
## Renders the IDLE cell of every non-house building exactly the way the game
## slices it (BuildingCatalog.finished_sheet_chain -> IllustratedStructure
## Sprite), on a flat backdrop, so a bad crop is something to LOOK at.
##
## Usage: godot --headless -s tools/probe_building_idle_crops.gd

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")

const OUT_DIR := "/tmp/claude-0/-home-user-aleph-alpha/4db22097-3bec-5763-a71a-e826305ba8f9/scratchpad"
const PAD := 8
const BACKDROP := Color(0.24, 0.33, 0.19)
const IDS := ["sawmill", "warehouse", "city_hall", "farmhouse", "blacksmith", "brewery"]


func _initialize() -> void:
	var sprite := IllustratedStructureSprite.new()
	var frames: Array = []
	var cell_w := 0
	var cell_h := 0
	for building_id in IDS:
		var entry: Dictionary = BuildingCatalog.finished_sheet_for(building_id, 1)
		var image: Image = sprite._frame_image(
			entry["path"], entry["columns"], entry["rows"], entry["row"], entry["column"], entry["grid"]
		)
		if image == null:
			print("NO CELL for %s (%s)" % [building_id, entry["path"]])
			continue
		print("CELL %-10s %s grid=%s r%d c%d -> %dx%d" % [
			building_id, entry["path"].get_file(), entry["grid"], entry["row"], entry["column"],
			image.get_width(), image.get_height()
		])
		cell_w = maxi(cell_w, image.get_width())
		cell_h = maxi(cell_h, image.get_height())
		frames.append({"id": building_id, "image": image})
	if frames.is_empty():
		quit()
		return
	var out := Image.create_empty(
		(cell_w + PAD) * frames.size() + PAD, cell_h + PAD * 2, false, Image.FORMAT_RGBA8
	)
	out.fill(BACKDROP)
	for i in frames.size():
		var image: Image = frames[i]["image"]
		out.blend_rect(
			image, Rect2i(0, 0, image.get_width(), image.get_height()),
			Vector2i(PAD + i * (cell_w + PAD), PAD + (cell_h - image.get_height()))
		)
	out.save_png("%s/_idle_buildings.png" % OUT_DIR)
	print("SAVED %d buildings" % frames.size())
	quit()
