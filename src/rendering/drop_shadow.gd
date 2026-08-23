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

## Vertical stretch bounds for silhouette shadows (see stretch_for_elevation):
## never fully collapse under a noon sun, never run off toward infinity at
## the horizon.
const MIN_STRETCH := 0.3
const MAX_STRETCH := 3.5

## Elevations at/below this are treated as MAX_STRETCH -- 1/tan blows up
## approaching 0 deg, and night (elevation <= 0) has no direct sun to cast a
## directional shadow at all; the caller decides whether to even show one.
const MIN_ELEVATION_FOR_STRETCH := 5.0

var _texture_cache: Dictionary = {}  # width (int) -> ImageTexture


## A ready-to-add Sprite2D: flattened translucent ellipse `width_px` wide,
## offset `foot_offset_y` px below the parent's origin (its feet/base), drawn
## behind the parent.
## `height_ratio` lets a caller match the shadow to the BODY it belongs to:
## the default is a generic oval, but a long low animal (a snake) needs a
## much flatter one or it sits on an egg (see CreatureRenderer).
func make_shadow(width_px: int, foot_offset_y: float, height_ratio: float = HEIGHT_RATIO) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Shadow"
	sprite.texture = _texture_for(width_px, height_ratio)
	sprite.position = Vector2(0, foot_offset_y)
	sprite.show_behind_parent = true
	return sprite


## How long a real shadow falls for a given sun elevation: length is
## proportional to 1/tan(elevation) -- overhead sun (90 deg) casts almost
## nothing, a low sun drags it out long. Clamped to [MIN_STRETCH, MAX_STRETCH]
## so noon doesn't collapse a shadow to a hairline and dawn/dusk doesn't
## stretch it toward infinity.
static func stretch_for_elevation(elevation_deg: float) -> float:
	var clamped_elevation := maxf(elevation_deg, MIN_ELEVATION_FOR_STRETCH)
	var stretch := 1.0 / tan(deg_to_rad(clamped_elevation))
	return clampf(stretch, MIN_STRETCH, MAX_STRETCH)


## A ready-to-add Sprite2D: the creature's own texture, flipped upside down
## and anchored at its feet -- a proper contact shadow shaped like what's
## actually casting it, instead of one fixed oval every species shared. Drawn
## behind the parent, darkened translucent via modulate rather than baking a
## black copy (so it stays a cheap live view of whatever texture/flip the
## caller assigns later, e.g. as a creature's walk cycle animates).
##
## `centered = false` with a top-anchored offset (rather than the default
## centered sprite): scaling scale.y to stretch the shadow (see
## stretch_for_elevation) must grow it AWAY from the foot anchor and into the
## ground, not split the growth evenly around a centre the way a centered
## sprite would -- that would push the shadow's "feet" up off the ground as
## it lengthened.
func make_silhouette_shadow(texture: Texture2D, foot_offset_y: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Shadow"
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = Vector2(-texture.get_width() / 2.0, 0.0)
	sprite.flip_v = true
	sprite.modulate = Color(0, 0, 0, SHADOW_ALPHA)
	sprite.position = Vector2(0, foot_offset_y)
	sprite.show_behind_parent = true
	return sprite


func _texture_for(width_px: int, height_ratio: float) -> ImageTexture:
	# Keyed on BOTH dimensions -- caching on width alone would hand a snake
	# whatever shape the first same-width caller happened to build.
	var key := "%d_%.3f" % [width_px, height_ratio]
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(_ellipse_image(width_px, height_ratio))
	return _texture_cache[key]


## A soft-edged dark ellipse: full SHADOW_ALPHA in the core, fading toward
## the rim so the shadow melts into the ground instead of ending in a ring.
func _ellipse_image(width_px: int, height_ratio: float = HEIGHT_RATIO) -> Image:
	var height_px := maxi(3, int(width_px * height_ratio))
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
