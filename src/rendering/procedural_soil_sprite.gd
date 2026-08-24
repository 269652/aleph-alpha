extends RefCounted

## A small mound of tilled soil under a wild crop patch (see WildCropMarker,
## docs/concept/wild_crops.md) -- shared across every crop, exactly
## ai_sprite_prompts.md's 2b spec (dirt looks the same regardless of what's
## growing in it). No AI-illustrated soil art exists yet, so this is a
## hand-drawn procedural fallback in the same offline-art style as
## ProceduralBobberSprite and friends -- swappable for real art later with no
## sim/marker changes needed, the same has_variants()-gated layering every
## other optional illustrated-art seam in this codebase already uses.
##
## Two states, both deterministic and drawn once (see fill_band's
## "generate once, reuse everywhere" precedent): UNDISTURBED (a neat round
## mound, something is planted in it) and DISTURBED (the same footprint
## hollowed into a shallow, darker crater -- what's left once a root has
## been pulled straight up out of the center).

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

## DETAIL_MULTIPLIER-scale canvas (see docs/concept/art_resolution.md) --
## drawn at ArtResolution.SPRITE_SCALE so it gains pixel detail without
## growing the mound's actual world footprint.
const SIZE := 24

## How wide the mound should read ON THE GROUND, in world pixels. Reported
## live: rendering at the raw SIZE=24 texture with no scale applied at all
## looked roughly 1.5 tiles wide next to a 16px tile -- the same "gigantic"
## class of bug ProceduralItemSprite's WORLD_WIDTH_BY_ID already fixed once
## for tree fruit. A follow-up live report ("huge potato crops above soil",
## reported twice) caught the leaves/root themselves ALSO reading too large
## (see IllustratedCropSprite.LEAF_WORLD_SIZE/ROOT_WORLD_SIZE, re-tuned to a
## measured scale in the same pass) -- this is sized to roughly match that
## smaller plant footprint: big enough to plausibly cover a planted root
## sitting at the same origin, without itself dominating the tile.
const SOIL_WORLD_WIDTH := 10.0
## The scale factor a marker applies to a SIZE-authored soil sprite to make
## it actually read at SOIL_WORLD_WIDTH on screen.
const SOIL_WORLD_SCALE := SOIL_WORLD_WIDTH / float(SIZE)

const SOIL_COLOR := Color(0.36, 0.24, 0.14)
## The crater floor reads darker than the undisturbed mound's own shadow
## band -- a hollow, not just a re-tinted mound.
const CRATER_COLOR := Color(0.22, 0.14, 0.08)
## Small scattered crumbs just outside the crater's rim (see
## ai_sprite_prompts.md 2b: "a few small clods and crumbs scattered just
## outside its rim").
const CRUMB_COLOR := Color(0.42, 0.29, 0.18)

var _palette := PixelPalette.new()


func generate_texture(disturbed: bool) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(disturbed))


func generate_image(disturbed: bool) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var radius := SIZE / 2.0

	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var d := point.distance_to(center)
			if d > radius:
				if disturbed:
					_maybe_draw_crumb(image, x, y, point, center, radius)
				continue
			image.set_pixel(x, y, _color_at(point, center, radius, d, disturbed))
	return image


func _color_at(point: Vector2, center: Vector2, radius: float, d: float, disturbed: bool) -> Color:
	if d > radius - 1.0:
		return _palette.outline_color()

	if disturbed:
		# A shallow crater: darkest at the very center (where the root came
		# out), lightening back toward the undisturbed rim.
		var depth := 1.0 - clampf(d / radius, 0.0, 1.0)
		return CRATER_COLOR.lerp(SOIL_COLOR, 1.0 - depth)

	# Undisturbed: a smooth mound, posterized light/shadow banding from the
	# upper-left (matches the shared style preamble's single light source).
	var to_point := point - center
	var lit := to_point.x < 0 and to_point.y < 0
	return _palette.highlight(SOIL_COLOR) if lit else _palette.shade(SOIL_COLOR)


## A few deterministic crumb specks just outside the crater's rim -- purely
## decorative, so a handful of fixed hashed positions is enough; no need for
## a caller-supplied seed since this is one shared, non-per-instance sprite.
func _maybe_draw_crumb(image: Image, x: int, y: int, point: Vector2, center: Vector2, radius: float) -> void:
	var d := point.distance_to(center)
	if d > radius + 3.0:
		return
	var h := absi(hash("%d_%d_soil_crumb" % [x, y]))
	if h % 7 == 0:
		image.set_pixel(x, y, CRUMB_COLOR)
