extends RefCounted

## Tile art for the structural pieces a house is built from (see
## docs/concept/building.md#pieces). Until this existed, BuildingPiece
## described pieces that nothing could actually draw.
##
## Pieces render as full ground tiles at TerrainRenderer.ART_TILE_SIZE, the
## same way placed structures (campfire, furnace) already do -- a built cell
## replaces its biome tile rather than layering a sprite over it, so a wall
## is part of the terrain the player collides with.
##
## Flat colour with one shadow side and hand-placed detail, per the
## codebase's 16-bit convention (see docs/concept/pixel_art_engine.md):
## planks and grain for wood, coursed blocks for stone.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Base colours per material -- warm timber against cool masonry, so a
## stone house reads as a different building from a wood one at a glance.
const MATERIAL_COLORS := {
	BuildingPiece.MATERIAL_WOOD: Color(0.52, 0.35, 0.19),
	BuildingPiece.MATERIAL_STONE: Color(0.53, 0.53, 0.57),
}

## Ramp stops used for the shadow side, mortar//seams, and a door's opening.
const _SHADOW_STOP := 0.25
const _SEAM_STOP := 0.1
const _OPENING_STOP := 0.15

## A floor is darker than the walls standing on it -- an interior should
## read as shaded ground, not as a bright slab.
const _FLOOR_DARKEN := 0.22

## How thick a wall's own edge shading is, as a fraction of the tile.
const _EDGE_FRACTION := 0.16

var _palette := PixelPalette.new()
var _ramp := PixelRamp.new()


func generate_texture(piece_id: String, seed_value: int = 0) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(piece_id, seed_value))


## Unknown ids fall back to a plain wood floor rather than crashing, the
## same fail-safe convention TerrainRenderer.atlas_coords_for_modification
## uses.
func generate_image(piece_id: String, seed_value: int = 0) -> Image:
	var size := TerrainRenderer.ART_TILE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

	var material := BuildingPiece.material_of(piece_id)
	if material == "":
		material = BuildingPiece.MATERIAL_WOOD
	var base: Color = MATERIAL_COLORS.get(material, MATERIAL_COLORS[BuildingPiece.MATERIAL_WOOD])

	match BuildingPiece.category_of(piece_id):
		BuildingPiece.CATEGORY_WALL:
			_paint_wall(image, size, base, material, seed_value)
		BuildingPiece.CATEGORY_DOOR:
			_paint_door(image, size, base, material, seed_value)
		BuildingPiece.CATEGORY_WINDOW:
			_paint_window(image, size, base, material, seed_value)
		BuildingPiece.CATEGORY_ROOF:
			_paint_roof(image, size, base, seed_value)
		_:
			_paint_floor(image, size, base, material, seed_value)
	return image


## A wall: solid material, coursed, with a shaded right/bottom edge so a run
## of walls reads as having thickness rather than as flat colour.
func _paint_wall(image: Image, size: int, base: Color, material: String, seed_value: int) -> void:
	var shadow := _ramp.sample(base, _SHADOW_STOP)
	var seam := _ramp.sample(base, _SEAM_STOP)
	var edge := int(float(size) * _EDGE_FRACTION)
	for y in size:
		for x in size:
			var shaded := x >= size - edge or y >= size - edge
			image.set_pixel(x, y, shadow if shaded else base)
	_paint_courses(image, size, seam, material, seed_value)


## A door: the wall's frame around a darker opening, so it reads as a way in
## rather than as another wall.
func _paint_door(image: Image, size: int, base: Color, material: String, seed_value: int) -> void:
	_paint_wall(image, size, base, material, seed_value)
	var opening := _ramp.sample(base, _OPENING_STOP)
	var frame := maxi(int(float(size) * 0.18), 2)
	for y in range(frame, size):
		for x in range(frame, size - frame):
			image.set_pixel(x, y, opening)
	# A handle, so the opening reads as a door leaf rather than a hole.
	var handle_x := size - frame - maxi(size / 12, 2)
	var handle_y := size / 2
	for dy in maxi(size / 16, 1):
		image.set_pixel(handle_x, handle_y + dy, _palette.highlight(base))


## A window: wall with a bright pane set into it. Not walkable (see
## BuildingPiece), but visibly open.
func _paint_window(image: Image, size: int, base: Color, material: String, seed_value: int) -> void:
	_paint_wall(image, size, base, material, seed_value)
	var pane := _ramp.sample(Color(0.45, 0.62, 0.78), 0.8)
	var inset := maxi(int(float(size) * 0.26), 2)
	for y in range(inset, size - inset):
		for x in range(inset, size - inset):
			image.set_pixel(x, y, pane)
	# A mullion down the middle so the pane reads as a window, not a hole.
	for y in range(inset, size - inset):
		image.set_pixel(size / 2, y, _ramp.sample(base, _SEAM_STOP))


## A floor: the material, darkened, so an interior reads as shaded ground
## underfoot rather than a bright slab.
func _paint_floor(image: Image, size: int, base: Color, material: String, seed_value: int) -> void:
	var floor_color := base.darkened(_FLOOR_DARKEN)
	image.fill(floor_color)
	_paint_courses(image, size, _ramp.sample(floor_color, _SEAM_STOP), material, seed_value)


## A roof: the material lightened toward the sky it faces, with courses
## running across it like shingles or slates.
func _paint_roof(image: Image, size: int, base: Color, seed_value: int) -> void:
	var roof_color := base.lightened(0.1)
	image.fill(roof_color)
	var shingle := _ramp.sample(roof_color, _SEAM_STOP)
	var course := maxi(size / 5, 2)
	for y in size:
		if y % course != 0:
			continue
		for x in size:
			image.set_pixel(x, y, shingle)
	# Offset every other course, so shingles overlap like real ones.
	for y in size:
		if y % course != 0:
			continue
		var offset := 0 if (y / course) % 2 == 0 else course / 2
		var x := offset
		while x < size:
			for dy in mini(course, size - y):
				if y + dy < size:
					image.set_pixel(x, y + dy, shingle)
			x += course


## Plank joints for timber, block coursing for masonry -- the detail that
## tells the two materials apart beyond their colour.
func _paint_courses(image: Image, size: int, seam: Color, material: String, seed_value: int) -> void:
	var course := maxi(size / 4, 2)
	if material == BuildingPiece.MATERIAL_STONE:
		# Running-bond blocks: horizontal courses with staggered joints.
		for y in size:
			if y % course == 0:
				for x in size:
					image.set_pixel(x, y, seam)
				continue
			var offset := 0 if (y / course) % 2 == 0 else course / 2
			for x in size:
				if (x + offset) % course == 0:
					image.set_pixel(x, y, seam)
		return

	# Timber: vertical plank joints, with a little seeded grain between them.
	for x in size:
		if x % course == 0:
			for y in size:
				image.set_pixel(x, y, seam)
	for i in size:
		var gx := PixelNoise.range_index(seed_value, i, 0, size)
		var gy := PixelNoise.range_index(seed_value + 977, i, 0, size)
		if gx % course != 0:
			image.set_pixel(gx, gy, seam)
