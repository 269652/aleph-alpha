extends RefCounted

## A small, roughly circular body of water's own shore-distance + alpha
## mask, for the character preview diorama's pond (see docs/concept/
## character_creator_preview_scene.md). `ProceduralShoreDistanceSprite`
## (see its own doc comment) is built around a SQUARE terrain TILE with
## land on specific cardinal SIDES, not an isolated round pond -- reusing
## it with an empty land_directions list gave a uniform "open ocean, no
## shore anywhere" texture with no alpha masking at all (a plain opaque
## square sprite, tinted flat by WaterShader since it had no shore
## gradient to shade against) -- reported live as the pond "seems tinted"
## rather than looking like real water, and not actually round.
##
## Generates the SAME shape of red-channel-encodes-shore-distance data
## WaterShader.gd already knows how to read (see that file's own doc
## comment: it just samples texture(TEXTURE, UV).r, with 0 = touching
## shore and 1 = deepest water, matching ProceduralShoreDistanceSprite's
## own convention exactly) -- measured radially from the image's own
## centre instead of from a tile's straight edges, plus a real circular
## ALPHA mask so the sprite's own silhouette is round, not square.

const SIZE := 32


## `SIZE`x`SIZE`: red channel is normalized distance FROM the rim TOWARD
## the centre (0 at the rim -- shore -- 1 at the very centre -- deep
## water), alpha is 1 inside the inscribed circle and 0 outside it.
static func generate_image() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE - 1, SIZE - 1) * 0.5
	# The INSCRIBED circle's radius (touching the middle of each edge, so
	# the corners crop away to transparent) -- not center.length() (the
	# CIRCUMSCRIBED radius, reaching the corners themselves), which would
	# make every pixel's own normalized distance top out at exactly 1.0
	# right at the corners and never actually exceed it, so nothing would
	# ever crop at all.
	var max_radius := center.x
	for y in SIZE:
		for x in SIZE:
			var offset := Vector2(x, y) - center
			var normalized := offset.length() / max_radius
			if normalized > 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var shore_distance := clampf(1.0 - normalized, 0.0, 1.0)
			image.set_pixel(x, y, Color(shore_distance, shore_distance, shore_distance, 1.0))
	return image


static func generate_texture() -> ImageTexture:
	return ImageTexture.create_from_image(generate_image())
