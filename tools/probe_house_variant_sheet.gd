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
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const VariantSheetGrid = preload("res://src/rendering/variant_sheet_grid.gd")

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
			var frame: Image = sprite.variant_frame_image(path, columns, rows, row, column)
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
	# With a DETECTED grid every band is cropped to its own art, so every
	# cell touching its own edge is the expected result rather than a
	# warning -- the verdict below is the real signal.
	print("cells whose art runs to their own edge: %d (expected: a detected band IS the art)" % bleeding)

	# Touching the edge is only a PROBLEM if the art actually straddles a
	# cut. Art drawn edge-to-edge inside its own cell is fine; a grid off by
	# a row is not, and the two look identical from the bounds alone. So
	# measure the real question: does each declared cut line fall on
	# background, or does it slice through a house?
	_report_cut_lines(path, columns, rows)
	quit()


## How much art each declared cut line actually passes through, as a share
## of that line's length. Near zero means the cut lands in the gutter
## between two buildings, which is what a correctly aligned grid looks
## like however tightly the art fills its cell.
func _report_cut_lines(path: String, columns: int, rows: int) -> void:
	var image := SpriteSheetLoader.load_image(path)
	if image == null:
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	print("")
	print("sheet is %dx%d; the renderer's own cut lines checked against the real art:" % [w, h])

	var detected_rows: Array = VariantSheetGrid.row_bands(image, rows)
	var detected_columns: Array = VariantSheetGrid.column_bands(image, columns)
	print("  detected row bands:    %s" % str(detected_rows))
	print("  detected column bands: %s" % str(detected_columns))
	print("")

	# The cuts that MATTER are the ones the renderer really makes -- the
	# gaps between detected bands, not an even division of the image.
	var worst := 0.0
	for i in range(1, columns):
		var x := int((detected_columns[i - 1].y + detected_columns[i].x) / 2)
		var hits := 0
		for y in h:
			if not _is_background(image.get_pixel(mini(x, w - 1), y)):
				hits += 1
		var share := float(hits) / float(h)
		worst = maxf(worst, share)
		print("  vertical cut %d at x=%4d: %5.1f%% of it lands on art" % [i, x, share * 100.0])
	for i in range(1, rows):
		var y := int((detected_rows[i - 1].y + detected_rows[i].x) / 2)
		var hits := 0
		for x in w:
			if not _is_background(image.get_pixel(x, mini(y, h - 1))):
				hits += 1
		var share := float(hits) / float(w)
		worst = maxf(worst, share)
		print("  horizontal cut %d at y=%4d: %5.1f%% of it lands on art" % [i, y, share * 100.0])

	print("")
	print("worst cut passes through %.1f%% art" % (worst * 100.0))
	print("verdict: %s" % (
		"OK -- every cut lands in the gutter, the grid matches the art"
		if worst < 0.05 else "NEEDS A LOOK -- a cut is slicing through a building"
	))


## The sheet's own background: near-black, the same reading
## IllustratedStructureSprite keys out when it cuts a frame.
static func _is_background(color: Color) -> bool:
	return color.r <= 0.08 and color.g <= 0.08 and color.b <= 0.08


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
