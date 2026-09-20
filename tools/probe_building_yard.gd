extends SceneTree

## Does the yard a building is declared to stand in actually come back as a
## PICTURE?
##
## Reported live, with the game running: *"farm houses don't use the 3x2
## background image as background..."*, and then *"I also added bg overlays
## for cottages ..."*. BuildingCatalog._BACKGROUND_SHEETS declares the sheet
## and EarthChunkManager._spawn_building_node grows a "Yard" Sprite2D from
## it, so the wiring reads as finished from both ends -- which is exactly why
## it has to be measured rather than read.
##
## Measures, for every building the catalog knows: the yard it declares, the
## cell that comes out of the sheet, the texture that cell scales to at the
## building's own plot width, and how much of that texture is actually
## OPAQUE. A yard that loads but is 100% transparent is invisible in
## precisely the same way as a yard that never loaded at all, and the two
## want opposite fixes.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const SEED := 4711


func _initialize() -> void:
	var sprite := IllustratedStructureSprite.new()
	print("=== sheets on disk ===")
	var seen_paths := {}
	for building_id in BuildingCatalog.all_building_ids():
		var yard: Dictionary = BuildingCatalog.background_sheet_for(building_id, SEED)
		if yard.is_empty():
			continue
		seen_paths[String(yard["path"])] = true
	for path in seen_paths.keys():
		var image := SpriteSheetLoader.load_image(path)
		print("%-58s exists=%s sidecar=%s loaded=%s%s" % [
			path,
			FileAccess.file_exists(path),
			FileAccess.file_exists(path + ".import"),
			image != null,
			"" if image == null else " %dx%d" % [image.get_width(), image.get_height()],
		])
	print()
	print("%-14s %-6s %-30s %-11s %-13s %s" % [
		"building", "plot", "yard sheet", "cell", "texture", "opaque",
	])
	for building_id in BuildingCatalog.all_building_ids():
		var yard: Dictionary = BuildingCatalog.background_sheet_for(building_id, SEED)
		var footprint := BuildingCatalog.footprint_of(building_id)
		if yard.is_empty():
			print("%-14s %-6s %s" % [building_id, "%dx%d" % [footprint.x, footprint.y], "-- none declared"])
			continue
		var texture := sprite.plot_background_texture(
			String(yard["path"]), int(yard["columns"]), int(yard["rows"]),
			int(yard["row"]), int(yard["column"]),
			TerrainRenderer.ART_TILE_SIZE, footprint, String(yard["grid"])
		)
		var cell := "%d,%d" % [int(yard["column"]), int(yard["row"])]
		if texture == null:
			print("%-14s %-6s %-30s %-11s %s" % [
				building_id, "%dx%d" % [footprint.x, footprint.y],
				String(yard["path"]).get_file(), cell, "NULL -- no picture",
			])
			continue
		var house := _first_texture_of(
			sprite, BuildingCatalog.finished_sheet_chain(building_id, SEED), footprint.x, building_id
		)
		var house_size := "none" if house == null else "%dx%d" % [house.get_width(), house.get_height()]
		print("%-14s %-6s %-30s %-11s %-13s %5.1f%%  house %-9s visible %5.1f%%" % [
			building_id, "%dx%d" % [footprint.x, footprint.y],
			String(yard["path"]).get_file(), cell,
			"%dx%d" % [texture.get_width(), texture.get_height()],
			_opaque_share(texture.get_image()) * 100.0,
			house_size,
			_visible_share(texture.get_image(), null if house == null else house.get_image()) * 100.0,
		])
	quit()


func _opaque_share(image: Image) -> float:
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	return float(opaque) / float(maxi(1, image.get_width() * image.get_height()))


## How much of the yard a viewer can actually SEE: yard pixels that are
## opaque and are NOT covered by an opaque house pixel. Both sprites are
## bottom-centred on the same node origin (see _spawn_building_node), so
## they are aligned on their bottom edge and on their horizontal centre.
func _visible_share(yard: Image, house: Image) -> float:
	if house == null:
		return _opaque_share(yard)
	var visible := 0
	var total := 0
	for y in yard.get_height():
		for x in yard.get_width():
			if yard.get_pixel(x, y).a <= 0.5:
				continue
			total += 1
			var hx := x - (yard.get_width() - house.get_width()) / 2
			var hy := y - (yard.get_height() - house.get_height())
			if hx < 0 or hy < 0 or hx >= house.get_width() or hy >= house.get_height():
				visible += 1
			elif house.get_pixel(hx, hy).a <= 0.5:
				visible += 1
	return float(visible) / float(maxi(1, total))


## EarthChunkManager._first_texture_of, inlined: the first sheet of the
## chain that really resolves.
func _first_texture_of(
	sprite: IllustratedStructureSprite, chain: Array, footprint_width_tiles: int, building_id: String
) -> ImageTexture:
	for entry in chain:
		var texture := sprite.footprint_frame_texture(
			entry["path"], entry["columns"], entry["rows"], entry["row"], entry["column"],
			TerrainRenderer.ART_TILE_SIZE, footprint_width_tiles, entry["grid"], building_id
		)
		if texture != null:
			return texture
	return null
