extends SceneTree

## Acceptance check for a building VARIANT sheet (see docs/concept/
## building.md's "Building variant sheets"): loads the real file, cuts it
## on the declared grid, and reports whether every cell actually holds one
## whole building.
##
## Run this the moment a sheet is dropped in, BEFORE trusting it in game:
## a grid that is off by a row, a sheet with a stray margin, or art that
## bleeds across a cell boundary all look fine in a thumbnail and wrong in
## a village.
##
## Usage: godot --headless -s tools/probe_house_variant_sheet.gd

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")

## A cell whose art reaches within this many pixels of its own edge is
## flagged: either the grid is misaligned or the art bleeds into its
## neighbour, and both read as a house with a slice of the next one glued
## to it.
const _EDGE_BLEED_MARGIN := 2


func _initialize() -> void:
	var building_id := "house_small"
	var path := BuildingCatalog.variant_sheet_of(building_id)
	if path == "":
		print("no variant sheet declared for %s" % building_id)
		quit()
		return
	if not FileAccess.file_exists(path):
		print("variant sheet not on disk yet: %s" % path)
		print("drop the 5x5 cottage sheet there and re-run; nothing else needs changing.")
		quit()
		return

	var sprite := IllustratedStructureSprite.new()
	var columns := BuildingCatalog.VARIANT_SHEET_COLUMNS
	var rows := BuildingCatalog.VARIANT_SHEET_ROWS
	print("sheet: %s" % path)
	print("grid: %d columns x %d rows (%d variants)" % [columns, rows, columns * rows])
	print("")

	var empty := 0
	var bleeding := 0
	for row in rows:
		var line := ""
		for column in columns:
			var frame: Image = sprite.sheet_frame_image(path, columns, rows, row, column)
			if frame == null:
				line += "  ??  "
				empty += 1
				continue
			var bounds := _opaque_bounds(frame)
			if bounds.size == Vector2i.ZERO:
				line += "  --  "
				empty += 1
				continue
			var touches := (
				bounds.position.x < _EDGE_BLEED_MARGIN
				or bounds.position.y < _EDGE_BLEED_MARGIN
				or bounds.end.x > frame.get_width() - _EDGE_BLEED_MARGIN
				or bounds.end.y > frame.get_height() - _EDGE_BLEED_MARGIN
			)
			if touches:
				bleeding += 1
			line += " %3dx%-3d%s" % [bounds.size.x, bounds.size.y, "!" if touches else " "]
		print(line)

	print("")
	print("empty cells: %d  (every one is a variant that would draw as nothing)" % empty)
	print("cells touching their own edge: %d  (grid misaligned, or art bleeding into its neighbour)" % bleeding)
	print("verdict: %s" % ("OK" if empty == 0 and bleeding == 0 else "NEEDS A LOOK"))
	quit()


## The bounding box of everything that survived the background key -- what
## the cell actually draws.
func _opaque_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.02:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
