extends RefCounted

## Deterministic offline pixel-art for an ant mound, and for the worker specks
## that come and go on it (see docs/concept/soil_fauna.md's "What the player
## sees").
##
## `AntColony` has seeded roughly ten mounds per chunk since it was written and
## drawn none of them -- colonies quietly moving seed around ground that showed
## nothing at all, which is the same "the simulation is right and the world is
## not showing it" gap the earthworm/robin pair already went through once.
##
## What a mound in a meadow actually looks like from above, and what this
## paints: a low dome of fine excavated soil, a dark entrance hole a little off
## its peak, and an APRON of spoil thrown out to one side. The apron is why the
## silhouette is lopsided -- a symmetric dome reads as a pebble, and this world
## already has plenty of those.
##
## `seed_value` (hashed from the mound's cell) varies the dome's size, the
## entrance's offset and the spoil's bearing, so ten mounds in a chunk are not
## one stamp repeated.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- painted oversized so it gains pixel
## detail without growing in the world.
const SIZE := Vector2i(32, 32)

## Fine excavated subsoil: paler and warmer than TOPSOIL, because it is dug
## from below and dries out -- but well below the vivid grassland tile in value,
## which is what actually makes it read at a glance. What matters is the
## distance, not the direction: the sward pass learned the hard way that
## anything sitting at its background's own value simply is not there
## (test_a_mound_stands_out_against_the_grass).
const SOIL_COLOR := Color(0.52, 0.40, 0.26)
const SOIL_HIGHLIGHT := Color(0.63, 0.50, 0.34)
const SOIL_SHADE := Color(0.38, 0.28, 0.18)

## The hole. Dark enough to be unmistakably a hole rather than a shadow --
## it is the one detail that says "colony" instead of "pile of dirt".
const ENTRANCE_COLOR := Color(0.13, 0.09, 0.06)

## A worker: a dark speck, drawn on its own tiny canvas. At the game's zoom an
## ant is a couple of pixels, and anything with a drawn anatomy reads as a
## beetle.
const WORKER_SIZE := Vector2i(4, 4)
const WORKER_COLOR := Color(0.11, 0.08, 0.06)

## How wide a worker's whole canvas is in the world, in pixels -- one world
## pixel per texel, which is the floor for this art: a body drawn thinner than
## a world pixel does not become a smaller ant, it disappears. Found only from
## a screenshot of the running game
## (test_a_worker_body_is_at_least_two_world_pixels_across).
const WORKER_WORLD_WIDTH_PX := 4.0

## Dome radius, in canvas pixels. A mound is a real feature of the ground, not
## a crumb -- but the dome plus its apron stay inside the mound's own tile.
const DOME_MIN_RADIUS := 6.0
const DOME_MAX_RADIUS := 9.0

## The dome is wider than it is tall, because it is a low heap seen from above
## at this game's slight overhead lean.
const DOME_FLATTEN := 0.72

## How wide the whole feature is in the world, in tiles. A mound is a real
## bump in the ground rather than a crumb, but it stays inside its own tile.
##
## World size comes from THIS, never from the art canvas: raising SIZE for
## detail must not change how big a mound looks (a trap this project has hit
## twice -- see ProceduralWormSprite.world_scale).
const WORLD_WIDTH_TILES := 1.0

## How far off the dome's centre the entrance sits, as a fraction of the dome
## radius, on the side away from the spoil. Its own constant because the
## workers are placed against it: they come out of the drawn hole, not out of
## the middle of the tile (test_the_entrance_offset_lands_on_the_painted_hole).
const ENTRANCE_OFFSET_FRACTION := 0.28

## How far out the apron of diggings reaches, as a multiple of the dome radius.
const SPOIL_REACH := 1.6

## How wide the fan is, as the cosine of its half-angle: a colony throws its
## diggings over an arc, not in a ring. Wide -- the diggings skirt most of one
## side of the mound, which is what a spoil heap looks like; a narrow fan reads
## as a tail growing out of a pebble.
const SPOIL_ARC_COSINE := 0.05

## How much of the apron's depth is SOLID soil before it starts to stipple out.
## Seen in a real render with no solid band at all: a wholly stippled apron
## grows radial one-pixel spikes, and the mound reads as something with LEGS.
const SPOIL_SOLID_FRACTION := 0.55

## How much of the apron survives at the FAR edge of the fan compared to
## straight down its bearing. Keeps the fan a fan rather than a rectangle.
const SPOIL_EDGE_DENSITY := 0.35

## How much of the dome is loose grain catching the light.
const GRAIN_DENSITY := 0.18

## Independent noise streams, so the grain, the apron's extent and its tone are
## not the same roll wearing three hats.
const _GRAIN_SALT := 8191
const _APRON_SALT := 12289
const _APRON_TONE_SALT := 24593


## Finished mounds, keyed by seed. A mound's seed comes from its cell, so this
## is naturally bounded by how many distinct mounds have ever been drawn, and a
## chunk that unloads and reloads (chunks are not persisted -- see
## EarthChunkManager's own doc comment) asks for the same texture back instead
## of a fresh repaint. Mirrors ProceduralScrubSprite's own cache.
static var _mound_texture_cache := {}
static var _worker_texture: ImageTexture = null


## What a Sprite2D showing this art must be scaled by so a mound comes out
## WORLD_WIDTH_TILES wide, whatever the canvas resolution is.
static func world_scale() -> float:
	return (WORLD_WIDTH_TILES * float(TerrainRenderer.TILE_SIZE)) / float(SIZE.x)


## What a quad showing the worker art must be sized to so a worker comes out
## WORKER_WORLD_WIDTH_PX across, whatever the canvas resolution is. The same
## world-space-constant rule world_scale() follows, for the same reason.
static func worker_world_scale() -> float:
	return WORKER_WORLD_WIDTH_PX / float(WORKER_SIZE.x)


## Which way this colony throws its diggings. Everything asymmetric about the
## mound hangs off this one bearing, so the fan and the entrance agree about
## where the low side is.
static func spoil_direction(seed_value: int) -> Vector2:
	var bearing := PixelNoise.unit(seed_value, 1, 0) * TAU
	return Vector2(cos(bearing), sin(bearing))


## The dome's radius in canvas pixels.
static func dome_radius(seed_value: int) -> float:
	return lerpf(DOME_MIN_RADIUS, DOME_MAX_RADIUS, PixelNoise.unit(seed_value, 0, 0))


## Where the entrance hole sits, in canvas pixels from the canvas centre.
##
## Public because the workers are placed against it rather than against the
## tile centre: soil_fauna.md's second honesty rule is that every trip starts
## and ends at the entrance, and the player can see where the entrance is.
static func entrance_offset(seed_value: int) -> Vector2:
	return -spoil_direction(seed_value) * dome_radius(seed_value) * ENTRANCE_OFFSET_FRACTION


func generate_texture(seed_value: int) -> ImageTexture:
	if _mound_texture_cache.has(seed_value):
		return _mound_texture_cache[seed_value]
	var texture := ImageTexture.create_from_image(generate_image(seed_value))
	_mound_texture_cache[seed_value] = texture
	return texture


## One shared worker texture: every ant looks the same, and a full decoration
## radius carries a few hundred of them, so there is nothing to vary and
## everything to gain from one texture they all bind.
func worker_texture() -> ImageTexture:
	if _worker_texture == null:
		_worker_texture = ImageTexture.create_from_image(generate_worker_image())
	return _worker_texture


func generate_image(seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE) * 0.5
	var radius := dome_radius(seed_value)
	var bearing := spoil_direction(seed_value)

	_paint_spoil_apron(image, centre, radius, bearing, seed_value)
	_paint_dome(image, centre, radius, seed_value)
	_paint_entrance(image, centre, seed_value)
	_keep_largest_blob(image)
	return image


## Where a pixel sits on the dome with respect to the light, 1 at the sunlit
## top edge and 0 at the shaded bottom edge. `dy` is its offset from the dome's
## centre in canvas pixels.
##
## Pulled out as a pure function rather than left inline because the spoil
## apron is thrown in a random direction and pollutes any average taken over
## the finished image -- so "lit from above" can only be pinned here
## (test_a_mound_is_lit_from_above).
static func dome_lighting(dy: float, radius: float) -> float:
	return clampf(0.5 - dy / maxf(radius * DOME_FLATTEN, 0.001) * 0.5, 0.0, 1.0)


## The three-tone banding a lit heap gets. Bands rather than a gradient: this
## is pixel art, and three flat tones read as a dome where a smooth ramp reads
## as a blur.
static func dome_colour(lighting: float) -> Color:
	if lighting > 0.66:
		return SOIL_HIGHLIGHT
	if lighting > 0.33:
		return SOIL_COLOR
	return SOIL_SHADE


## Whether the pixel at (`dx`, `dy`) from this mound's centre is a grain of
## loose spoil catching the light.
##
## Seeded from the MOUND, which the first version got wrong: it sampled at
## `int(centre.x) * 31`, and the centre is the middle of a fixed-size canvas,
## so that was the constant 16 for every mound ever drawn. Pinned by
## test_the_grain_pattern_differs_between_mounds.
static func is_loose_grain(seed_value: int, dx: int, dy: int) -> bool:
	return PixelNoise.unit(seed_value + _GRAIN_SALT, dx, dy) < GRAIN_DENSITY


## The heap: an ellipse, banded from the sunlit top edge to the shaded bottom
## one, with a grainy speckle so it reads as loose soil rather than a blob.
func _paint_dome(image: Image, centre: Vector2, radius: float, seed_value: int) -> void:
	var reach := int(ceilf(radius)) + 1
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var normalised := Vector2(float(dx), float(dy) / DOME_FLATTEN)
			if normalised.length() > radius:
				continue
			var colour := dome_colour(dome_lighting(float(dy), radius))
			# Height on the dome, 1 at the peak and 0 at the rim: only the
			# raised part of a heap has loose grain sitting proud on it.
			var height := 1.0 - normalised.length() / radius
			if height > 0.15 and is_loose_grain(seed_value, dx, dy):
				colour = colour.lightened(0.12)
			_paint_pixel(image, int(centre.x) + dx, int(centre.y) + dy, colour)


## The apron of diggings thrown out to one side: what gives the mound its
## lopsided silhouette, and the reason it does not read as a pebble.
##
## Painted as a CONTIGUOUS skirt off the rim, thinning outwards -- not as
## grains scattered at a distance. Seen in a real render of the scattered
## version: lone dark pixels floating in vivid green do not read as soil, they
## read as whiskers on the mound. Solid where it leaves the rim, stippling out
## to nothing at the edge of the fan.
func _paint_spoil_apron(
	image: Image, centre: Vector2, radius: float, direction: Vector2, seed_value: int
) -> void:
	var outer := radius * SPOIL_REACH
	var span := int(ceilf(outer)) + 1
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var offset := Vector2(float(dx), float(dy) / DOME_FLATTEN)
			var distance := offset.length()
			if distance <= radius or distance > outer:
				continue
			var alignment := offset.normalized().dot(direction)
			if alignment < SPOIL_ARC_COSINE:
				continue
			# 0 where the apron leaves the rim, 1 at its outer edge.
			var out := (distance - radius) / maxf(outer - radius, 0.001)
			# 0 at the edges of the fan, 1 straight down its bearing.
			var arc := (alignment - SPOIL_ARC_COSINE) / (1.0 - SPOIL_ARC_COSINE)
			# Solid against the rim, then a short stippled edge -- crumbly
			# rather than spiky. The arc factor thins the fan sideways, so it
			# tapers to its edges instead of ending in a straight cut.
			var radial := 1.0
			if out > SPOIL_SOLID_FRACTION:
				radial = 1.0 - (out - SPOIL_SOLID_FRACTION) / (1.0 - SPOIL_SOLID_FRACTION)
			var density := radial * lerpf(SPOIL_EDGE_DENSITY, 1.0, arc)
			if PixelNoise.unit(seed_value + _APRON_SALT, dx, dy) > density:
				continue
			var shaded := apron_is_shaded(seed_value, dx, dy, out)
			_paint_pixel(
				image, int(centre.x) + dx, int(centre.y) + dy, SOIL_SHADE if shaded else SOIL_COLOR
			)


## Whether a pixel of the apron sits in the dome's shadow, at depth `out`
## through the apron (0 against the rim, 1 at its outer edge).
##
## Dithered rather than banded, so the apron reads as thinning cover rather
## than as a second ring around the mound -- and concentrated AT THE RIM,
## because the dome shades its own base. Inverted, the far crumbs are the dark
## ones and the fringe reads as hairs on the mound (test_the_apron_is_shaded_
## against_the_rim).
static func apron_is_shaded(seed_value: int, dx: int, dy: int, out: float) -> bool:
	return PixelNoise.unit(seed_value + _APRON_TONE_SALT, dx, dy) > out


## The hole, set a little off the peak and on the side away from the spoil --
## a colony does not throw its diggings back down its own entrance.
func _paint_entrance(image: Image, centre: Vector2, seed_value: int) -> void:
	var hole := centre + entrance_offset(seed_value)
	var hole_radius := 1.4 + PixelNoise.unit(seed_value + 41, 0, 0) * 0.9
	var reach := int(ceilf(hole_radius))
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if Vector2(dx, dy).length() > hole_radius:
				continue
			_paint_pixel(image, int(hole.x) + dx, int(hole.y) + dy, ENTRANCE_COLOR)


## A worker, at the only size an ant reads at: a solid two-by-two body with a
## head pixel off one corner, which at this zoom is all a moving dot needs to
## be an animal.
##
## Solid rather than an L of three: the L had a one-texel waist, and a texel is
## one world pixel here -- so half the ant was sub-pixel and it read as a
## smudge rather than as a body.
func generate_worker_image() -> Image:
	var image := Image.create(WORKER_SIZE.x, WORKER_SIZE.y, false, Image.FORMAT_RGBA8)
	for y in [1, 2]:
		for x in [1, 2]:
			image.set_pixel(x, y, WORKER_COLOR)
	image.set_pixel(2, 0, WORKER_COLOR)
	return image


## A mound is ONE feature, so anything the stipple left stranded in the grass
## is erased. At this resolution a lone dark pixel on vivid grassland does not
## read as a grain of soil -- it reads as a dead pixel. Pinned by
## test_a_mound_is_one_connected_feature.
##
## Cheap: the canvas is 32x32 and this runs once per distinct mound, behind the
## texture cache.
func _keep_largest_blob(image: Image) -> void:
	var unvisited := {}
	for y in SIZE.y:
		for x in SIZE.x:
			if image.get_pixel(x, y).a > 0.0:
				unvisited[Vector2i(x, y)] = true
	var largest: Array[Vector2i] = []
	while not unvisited.is_empty():
		var start: Vector2i = unvisited.keys()[0]
		unvisited.erase(start)
		var frontier: Array[Vector2i] = [start]
		var blob: Array[Vector2i] = []
		while not frontier.is_empty():
			var here: Vector2i = frontier.pop_back()
			blob.append(here)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var neighbour := here + Vector2i(dx, dy)
					if unvisited.has(neighbour):
						unvisited.erase(neighbour)
						frontier.append(neighbour)
		if blob.size() > largest.size():
			for pixel in largest:
				image.set_pixel(pixel.x, pixel.y, Color(0.0, 0.0, 0.0, 0.0))
			largest = blob
		else:
			for pixel in blob:
				image.set_pixel(pixel.x, pixel.y, Color(0.0, 0.0, 0.0, 0.0))


func _paint_pixel(image: Image, x: int, y: int, colour: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE.x or y >= SIZE.y:
		return
	image.set_pixel(x, y, colour)
