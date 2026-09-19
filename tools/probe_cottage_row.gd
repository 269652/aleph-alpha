extends SceneTree

## Three real cottages standing on three ADJACENT plots, sliced and scaled
## exactly the way the game does it -- the picture behind "make them a bit
## smaller and put a gap between them".
##
## Usage: godot --headless -s tools/probe_cottage_row.gd

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const OUT := "/tmp/claude-0/-home-user-aleph-alpha/70e7bac8-cb28-5bf7-b632-10ffe5d682ba/scratchpad/cottage_row.png"
const SEEDS := [3, 11, 29]
const PAVING := Color(0.38, 0.38, 0.40)
const PAVING_LINE := Color(0.30, 0.30, 0.32)
const ZOOM := 3


func _initialize() -> void:
	var sprite := IllustratedStructureSprite.new()
	var footprint := BuildingCatalog.footprint_of("house_small")
	var plot_px := footprint.x * TerrainRenderer.ART_TILE_SIZE

	var textures: Array = []
	var tallest := 0
	for seed_value in SEEDS:
		var texture: ImageTexture = _texture_for(sprite, seed_value, footprint.x)
		if texture == null:
			print("no art for seed %d" % seed_value)
			continue
		textures.append(texture)
		tallest = maxi(tallest, texture.get_height())

	var width := plot_px * textures.size()
	var height := tallest + TerrainRenderer.ART_TILE_SIZE * 2
	var canvas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var on_line := (x % TerrainRenderer.ART_TILE_SIZE == 0) or (y % TerrainRenderer.ART_TILE_SIZE == 0)
			canvas.set_pixel(x, y, PAVING_LINE if on_line else PAVING)

	# Bottom-centre on each plot, exactly as _spawn_building_node anchors it.
	var ground := height - TerrainRenderer.ART_TILE_SIZE
	for i in textures.size():
		var frame: Image = textures[i].get_image()
		var centre := i * plot_px + plot_px / 2
		var left := centre - frame.get_width() / 2
		var top := ground - frame.get_height()
		canvas.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(left, top))
		print("cottage %d: drawn %dpx wide on a %dpx plot -- %d px of air" % [
			i, frame.get_width(), plot_px, plot_px - frame.get_width()
		])

	var big := canvas.duplicate() as Image
	big.resize(width * ZOOM, height * ZOOM, Image.INTERPOLATE_NEAREST)
	big.save_png(OUT)
	print("wrote %s (%dx%d)" % [OUT, big.get_width(), big.get_height()])
	quit()


func _texture_for(sprite, seed_value: int, footprint_width: int):
	for entry in BuildingCatalog.finished_sheet_chain("house_small", seed_value):
		var texture = sprite.footprint_frame_texture(
			entry["path"], int(entry["columns"]), int(entry["rows"]), int(entry["row"]),
			int(entry["column"]), TerrainRenderer.ART_TILE_SIZE, footprint_width, String(entry["grid"])
		)
		if texture != null:
			return texture
	return null
