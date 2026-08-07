extends RefCounted

## Shared soft-ellipse contact shadows for world entities (trees, creatures,
## stones, the player). Without a shadow every sprite floats on the ground
## plane; a translucent flattened ellipse at the feet is the cheapest, most
## effective grounding cue in top-down pixel art. Textures are cached per
## width (a handful of sizes serve thousands of nodes), and the returned
## sprite draws behind its parent so it never covers the entity itself.

## Peak opacity at the shadow's center -- a soft hint, not a black hole.
## Pinned by test_shadow_pixels_are_translucent_dark_not_opaque_black.
const SHADOW_ALPHA := 0.26

## Height as a fraction of width: ground shadows are flattened ellipses.
const HEIGHT_RATIO := 0.4

var _texture_cache: Dictionary = {}  # width (int) -> ImageTexture


## A ready-to-add Sprite2D: flattened translucent ellipse `width_px` wide,
## offset `foot_offset_y` px below the parent's origin (its feet/base), drawn
## behind the parent.
func make_shadow(width_px: int, foot_offset_y: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Shadow"
	sprite.texture = _texture_for(width_px)
	sprite.position = Vector2(0, foot_offset_y)
	sprite.show_behind_parent = true
	return sprite


func _texture_for(width_px: int) -> ImageTexture:
	if not _texture_cache.has(width_px):
		_texture_cache[width_px] = ImageTexture.create_from_image(_ellipse_image(width_px))
	return _texture_cache[width_px]


## A soft-edged dark ellipse: full SHADOW_ALPHA in the core, fading toward
## the rim so the shadow melts into the ground instead of ending in a ring.
func _ellipse_image(width_px: int) -> Image:
	var height_px := maxi(3, int(width_px * HEIGHT_RATIO))
	var image := Image.create(width_px, height_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(width_px / 2.0, height_px / 2.0)
	for y in height_px:
		for x in width_px:
			var dx := (x + 0.5 - center.x) / (width_px / 2.0)
			var dy := (y + 0.5 - center.y) / (height_px / 2.0)
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var alpha := SHADOW_ALPHA * (1.0 if d < 0.55 else 0.5)
			image.set_pixel(x, y, Color(0, 0, 0, alpha))
	return image
