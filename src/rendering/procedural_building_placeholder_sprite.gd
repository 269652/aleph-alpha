extends RefCounted

## A roof-over-walls box drawn for a building whose real sheet has not
## landed yet (docs/concept/building.md "Asset contract") -- the fallback
## EarthChunkManager's building node uses when IllustratedStructureSprite.
## footprint_frame_texture answers null, so the whole-building system is
## playable and testable before any art exists. Deterministic (PixelNoise-
## seeded speckle, no RandomNumberGenerator), PixelPalette shading, drawn at
## TerrainRenderer.ART_TILE_SIZE like every other procedural generator here.
##
## Shape: as wide as the footprint, one extra tile TALL -- the roof rises
## above the footprint the way every real sheet's building does, so a
## placeholder and a real sheet anchor identically (bottom edge on the
## footprint's south edge, see EarthChunkManager._spawn_building_node).

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const TILE := TerrainRenderer.ART_TILE_SIZE

const _ROOF := Color(0.55, 0.26, 0.16)
const _ROOF_COURSE := Color(0.42, 0.19, 0.11)
const _WALL := Color(0.84, 0.78, 0.64)
const _WALL_SPECKLE := Color(0.78, 0.71, 0.56)
const _PLINTH := Color(0.48, 0.47, 0.5)
const _DOOR := Color(0.36, 0.22, 0.08)
const _COURSE_SPACING := 6
const _PLINTH_ROWS := 4

var _palette := PixelPalette.new()


## The box at art resolution: `footprint.x * TILE` wide, `(footprint.y + 1)
## * TILE` tall. Roof over the top tile-and-a-bit, walls below, a plinth at
## the very bottom and a door at the front's middle.
func generate_image(footprint: Vector2i, seed_value: int) -> Image:
	var width := maxi(footprint.x, 1) * TILE
	var height := (maxi(footprint.y, 1) + 1) * TILE
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(_WALL)
	var roof_rows := TILE + TILE / 3
	for y in roof_rows:
		var course := _ROOF_COURSE if y % _COURSE_SPACING == 0 else _ROOF
		for x in width:
			image.set_pixel(x, y, course)
	for x in width:
		image.set_pixel(x, roof_rows, _palette.shade(_ROOF))
	for y in range(roof_rows + 1, height - _PLINTH_ROWS):
		for x in width:
			if PixelNoise.value(seed_value, x, y) % 11 == 0:
				image.set_pixel(x, y, _WALL_SPECKLE)
	for y in range(height - _PLINTH_ROWS, height):
		for x in width:
			image.set_pixel(x, y, _PLINTH)
	var door_width := TILE / 2
	var door_left := width / 2 - door_width / 2
	var door_top := height - _PLINTH_ROWS - TILE * 3 / 4
	for y in range(door_top, height - _PLINTH_ROWS):
		for x in range(door_left, door_left + door_width):
			image.set_pixel(x, y, _DOOR)
	for x in range(door_left - 1, door_left + door_width + 1):
		image.set_pixel(x, door_top - 1, _palette.shade(_WALL))
	return image


## The box scaled for a Sprite2D standing on the footprint at `tile_size`
## world units per tile -- the same width/height contract Illustrated
## StructureSprite.footprint_frame_texture keeps for a real sheet, which
## since BuildingCatalog.PLOT_MARGIN_SHARE means drawn INSIDE the plot
## rather than across the whole of it.
##
## Both paths read the same drawn_plot_width_tiles on purpose: a building with
## no art yet must stand in exactly as much of its plot as one with art,
## or dropping a sheet in would visibly move the house and a street of
## half-arted buildings would carry two different rhythms.
func footprint_texture(footprint: Vector2i, seed_value: int, tile_size: int) -> ImageTexture:
	var image := generate_image(footprint, seed_value)
	var scaled := image.duplicate() as Image
	var width := maxi(1, int(round(float(tile_size) * BuildingCatalog.drawn_plot_width_tiles(footprint.x))))
	var height := maxi(1, int(round(
		float(width) * float((maxi(footprint.y, 1) + 1) * tile_size)
		/ float(maxi(footprint.x, 1) * tile_size)
	)))
	scaled.resize(width, height, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(scaled)
