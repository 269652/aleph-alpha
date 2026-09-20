extends SceneTree

## Does a house stand in the same place the moment it finishes?
##
## Reported live: *"The construction phase places the cottage at a different
## position than the finished cottage ... please align it so it doesn't jump
## that much"*.
##
## Both nodes are anchored at the plot's bottom centre and both offset their
## sprite by half its texture height, so the TEXTURE's bottom edge always
## lands on the plot line. What can still move is the art INSIDE that
## texture: a stage cell whose house is drawn higher, or further left,
## within its own cell than the finished cell's is. This measures exactly
## that -- the opaque content rect of every stage and of the finished
## sheet, in world units, relative to the plot's own bottom centre.

const CHUNK_SIZE := 32
const BUILDING_ID := "house_small"
const SEED := 12345
const STAGES: Array[float] = [0.0, 0.25, 0.5, 0.75, 0.99]

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")


func _initialize() -> void:
	var sprites := IllustratedStructureSprite.new()
	var footprint := BuildingCatalog.footprint_of(BUILDING_ID)
	var world_width: int = footprint.x * TerrainRenderer.TILE_SIZE
	print("")
	print("=== %s (%dx%d tiles, %d world px wide) ===" % [
		BUILDING_ID, footprint.x, footprint.y, world_width
	])
	print("content box in WORLD units, measured from the plot's bottom centre")
	for progress in STAGES:
		_report("stage %.2f" % progress,
			BuildingCatalog.construction_sheet_chain(BUILDING_ID, SEED, progress), sprites, footprint)
	_report("FINISHED ",
		BuildingCatalog.finished_sheet_chain(BUILDING_ID, SEED), sprites, footprint)
	quit()


func _report(label: String, chain: Array, sprites, footprint: Vector2i) -> void:
	var texture = _first_texture_of(chain, footprint.x, sprites)
	if texture == null:
		print("   %s  no texture" % label)
		return
	var image: Image = texture.get_image()
	var min_x := image.get_width()
	var max_x := -1
	var min_y := image.get_height()
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.02:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_y < 0:
		print("   %s  %dx%d  empty" % [label, image.get_width(), image.get_height()])
		return
	var s: float = ArtResolution.SPRITE_SCALE
	# The sprite is centred on (0, -h/2*s), so the texture's bottom edge is
	# at y=0 (the plot line) and its centre column at x=0.
	var half_w := float(image.get_width()) * 0.5
	print("   %s  tex %dx%d   content x %.1f..%.1f  bottom %.1f above the plot line  top %.1f  height %.1f" % [
		label, image.get_width(), image.get_height(),
		(float(min_x) - half_w) * s, (float(max_x) + 1.0 - half_w) * s,
		float(image.get_height() - 1 - max_y) * s,
		float(image.get_height() - min_y) * s,
		float(max_y - min_y + 1) * s,
	])


func _first_texture_of(chain: Array, footprint_tiles: int, sprites):
	for entry in chain:
		var texture = sprites.footprint_frame_texture(
			String(entry["path"]), int(entry["columns"]), int(entry["rows"]),
			int(entry["row"]), int(entry["column"]),
			footprint_tiles * TerrainRenderer.ART_TILE_SIZE,
			int(entry.get("inset", 0)), String(entry.get("grid", ""))
		)
		if texture != null:
			return texture
	return null
