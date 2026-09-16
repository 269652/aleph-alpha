extends SceneTree

## Renders every cottage variant at the EXACT size the game draws it, into
## one contact sheet -- so "does this art survive the game's own scale?"
## is answered by looking at it rather than by arguing about pixel counts.
##
## A village house is drawn ART_TILE_SIZE px per footprint tile and then
## scaled by ArtResolution.SPRITE_SCALE (docs/concept/art_resolution.md), so
## a 2-tile-wide cottage really occupies 32 world units. This draws each
## variant at that true pixel size for all three house tiers side by side.
##
## Usage: godot --headless -s tools/probe_house_variants_at_game_scale.gd

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const OUT_PATH := "res://screenshots/house_variants_at_game_scale.png"
const PAD := 6
const BACKDROP := Color(0.24, 0.33, 0.19)  # grass, so white roofs are not read on white


func _initialize() -> void:
	var sprite := IllustratedStructureSprite.new()
	var tiers := ["house_small", "house_medium", "house_large"]
	var columns := BuildingCatalog.VARIANT_SHEET_COLUMNS
	var rows := BuildingCatalog.VARIANT_SHEET_ROWS

	# Measure first: every tier's frames share a cell size, but each tier
	# draws at its own footprint width.
	var tier_widths: Array = []
	var tier_heights: Array = []
	for building_id in tiers:
		var footprint := BuildingCatalog.footprint_of(building_id)
		var probe: ImageTexture = sprite.footprint_frame_texture(
			BuildingCatalog.variant_sheet_of(building_id), columns, rows, 0, 0,
			TerrainRenderer.ART_TILE_SIZE, footprint.x, true
		)
		if probe == null:
			print("no variant sheet on disk for %s" % building_id)
			quit()
			return
		tier_widths.append(int(round(probe.get_width() * 0.5)))
		tier_heights.append(int(round(probe.get_height() * 0.5)))

	var cell_w := 0
	for w in tier_widths:
		cell_w += int(w) + PAD
	var cell_h := 0
	for h in tier_heights:
		cell_h = maxi(cell_h, int(h))
	cell_h += PAD

	var out := Image.create_empty(cell_w * columns + PAD, cell_h * rows + PAD, false, Image.FORMAT_RGBA8)
	out.fill(BACKDROP)

	for row in rows:
		for column in columns:
			var x := PAD + column * cell_w
			for t in tiers.size():
				var building_id: String = tiers[t]
				var footprint := BuildingCatalog.footprint_of(building_id)
				var texture: ImageTexture = sprite.footprint_frame_texture(
					BuildingCatalog.variant_sheet_of(building_id), columns, rows, row, column,
					TerrainRenderer.ART_TILE_SIZE, footprint.x, true
				)
				var frame := texture.get_image()
				# The real on-screen size: art pixels times SPRITE_SCALE.
				var w: int = int(tier_widths[t])
				var h: int = int(tier_heights[t])
				frame.resize(w, h, Image.INTERPOLATE_LANCZOS)
				if frame.get_format() != Image.FORMAT_RGBA8:
					frame.convert(Image.FORMAT_RGBA8)
				var y := PAD + row * cell_h + (cell_h - PAD - h)
				out.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(x, y))
				x += w + PAD

	var absolute := ProjectSettings.globalize_path(OUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	out.save_png(absolute)
	print("wrote %s  (%dx%d)" % [OUT_PATH, out.get_width(), out.get_height()])
	print("each group of three is one variant drawn as a Cottage / House / Manor,")
	print("at the exact pixel size the game puts on screen.")
	for t in tiers.size():
		print("  %-13s %d x %d px on screen" % [tiers[t], int(tier_widths[t]), int(tier_heights[t])])
	quit()
