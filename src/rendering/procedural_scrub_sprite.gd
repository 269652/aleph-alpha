extends RefCounted

## Deterministic offline pixel-art for a tuft of desert scrub -- same
## silhouette technique as ProceduralGrassSprite (a few 1px-wide blades rising
## from the bottom edge, shaded by distance from the tuft's horizontal
## center), reused deliberately rather than reinvented (see
## desert_scrub.gd's doc comment on why the simulation itself isn't shared,
## but the sprite geometry is fine to lean on). Colored dusty sage/olive
## instead of tall grass's lush saturated green, so scrub visibly reads as a
## dry desert plant rather than a lush meadow tuft.
## `seed_value` (typically hashed from the patch's cell) varies blade count,
## lean, and height so neighbouring tufts aren't pixel-identical clones.

## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- drawn at ArtResolution.SPRITE_SCALE
## so it gains pixel detail without growing in the world.
const SIZE := Vector2i(32, 32)
const BLADE_COUNT_MIN := 4
const BLADE_COUNT_MAX := 6
const BASE_COLOR := Color(0.5, 0.55, 0.35)
const SHADE_DARKEN := 0.25
const HIGHLIGHT_LIGHTEN := 0.25


## Finished tufts, keyed by seed_value alone -- a tuft's seed is hashed from
## its cell, so this is naturally bounded by how many distinct cells have ever
## drawn one, and a chunk that unloads and reloads (chunks are not persisted --
## see EarthChunkManager's own doc comment) asks for the exact same texture
## back instead of a fresh repaint. Mirrors ProceduralTreeSprite's own
## _tree_texture_cache.
static var _scrub_texture_cache := {}


func generate_texture(seed_value: int) -> ImageTexture:
	if _scrub_texture_cache.has(seed_value):
		return _scrub_texture_cache[seed_value]
	var texture := ImageTexture.create_from_image(generate_image(seed_value))
	_scrub_texture_cache[seed_value] = texture
	return texture


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var blade_count := BLADE_COUNT_MIN + absi(hash("%d_blade_count" % seed_value)) % (BLADE_COUNT_MAX - BLADE_COUNT_MIN + 1)
	for i in blade_count:
		_paint_blade(image, seed_value, i)
	return image


## One blade: a 1px-wide column rising from the bottom edge, leaning left or
## right as it climbs. Blades near the tuft's center get the highlight tint,
## outer blades the shade tint, so the tuft reads as lit from above.
func _paint_blade(image: Image, seed_value: int, index: int) -> void:
	var h := absi(hash("%d_blade_%d" % [seed_value, index]))
	var base_x := 3 + h % (SIZE.x - 6)
	var height := 6 + (h / 31) % 8  # 6..13 px tall
	var lean: int = [-1, 0, 1][(h / 977) % 3]

	var color := BASE_COLOR
	var center_distance := absf(base_x + 0.5 - SIZE.x / 2.0)
	if center_distance < 3.0:
		color = BASE_COLOR.lightened(HIGHLIGHT_LIGHTEN)
	elif center_distance > 5.0:
		color = BASE_COLOR.darkened(SHADE_DARKEN)

	for step in height:
		var y := SIZE.y - 1 - step
		var x: int = base_x + lean * step / 4  # gentle lean: 1px sideways per 4px up
		if x < 0 or x >= SIZE.x or y < 0:
			break
		# Tip pixel is slightly darker so blades end crisply instead of flat.
		image.set_pixel(x, y, color.darkened(SHADE_DARKEN) if step == height - 1 else color)
