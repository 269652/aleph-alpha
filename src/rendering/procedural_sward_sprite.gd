extends RefCounted

## Deterministic offline pixel-art for one plant of the sward -- the low
## rosette layer between the tussocks (see docs/concept/ground_cover.md).
##
## Deliberately NOT the shared blade technique ProceduralGrassSprite,
## ProceduralScrubSprite and ProceduralLichenSprite all lean on. Those paint
## 1px columns rising from the BOTTOM edge of the canvas, because a tuft stands
## up out of the ground. A rosette radiates from its own CENTRE and lies flat
## on it, which is both what these plants actually look like and what the
## renderer needs: the MultiMesh centres its quad on the point the simulation
## placed the plant, so art that hugged the bottom edge would draw every plant
## visibly below where the sim says it is.
##
## Four species, each with its own silhouette rather than its own colour on one
## shape -- four species that painted the same outline would be one species
## wearing four names, and the point of a sward is that it reads as mixed.
##
## `seed_value` (from the plant's own cell and index) varies leaf count, angle
## and length so neighbouring plants are not pixel-identical clones.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const GroundCover = preload("res://src/world/ground_cover.gd")

## DETAIL_MULTIPLIER times the world footprint (see
## docs/concept/art_resolution.md) -- painted oversized so it gains pixel
## detail without growing in the world.
const SIZE := Vector2i(32, 32)

## One per GroundCover.SPECIES, in the same order. Different greens on purpose:
## a clover leaf really is a deeper blue-green than a yarrow frond, and four
## identical greens would read as one plant drawn at four sizes.
##
## Every one is DARKER and at least as SATURATED as the grassland tile they are
## drawn against. That is not a style preference, it is what the first pass got
## wrong: reported live from a real screenshot, the original grey-green plantain
## and pale sage yarrow read as white STARS scattered over the meadow rather
## than as plants growing in it. Luminance alone did not explain it -- they were
## already darker than the grass -- it was saturation. A washed-out green
## against a vivid one reads as grey however dark it is. Pinned by
## test_no_sward_species_is_washed_out_against_the_grass and
## test_every_sward_species_is_darker_than_the_grass.
const LEAF_COLORS := [
	Color(0.16, 0.40, 0.13),  # clover -- deep, slightly blue-green
	Color(0.22, 0.47, 0.15),  # ribwort plantain -- darker olive-green
	Color(0.19, 0.52, 0.17),  # daisy -- mid green
	Color(0.30, 0.50, 0.22),  # yarrow -- sage, but still a real green
]

## How saturated a leaf must be relative to the grass it grows in. See
## LEAF_COLORS: the whole "pale star" bug lived in this ratio, and nothing was
## measuring it.
const MIN_SATURATION_OF_GRASS := 0.7

## How much lighter the sunlit half of a leaf is. A rosette lies flat, so it is
## lit from above along its whole length rather than shaded by depth the way a
## standing blade is -- but only just: a bright midrib on a radially symmetric
## rosette is exactly what made the first pass read as snowflakes.
const HIGHLIGHT_LIGHTEN := 0.09

## How far a leaf may swing off its evenly-spaced slot, in radians. See the
## comment at its use site: this is the other half of the snowflake fix.
const ANGLE_JITTER := 0.9

## Per-species leaf counts. Ribwort throws more leaves than a clover does.
const LEAF_COUNT_MIN := [3, 5, 6, 3]
const LEAF_COUNT_MAX := [4, 7, 8, 5]


## Finished plants, keyed by species and seed. A plant's seed comes from its
## own cell and index, so this is naturally bounded by how many distinct plants
## have ever been drawn, and a chunk that unloads and reloads (chunks are not
## persisted -- see EarthChunkManager's own doc comment) asks for the exact same
## texture back instead of a fresh repaint. Mirrors ProceduralScrubSprite's own
## cache.
static var _sward_texture_cache := {}


func generate_texture(species_index: int, seed_value: int) -> ImageTexture:
	var key := "%d_%d" % [species_index, seed_value]
	if _sward_texture_cache.has(key):
		return _sward_texture_cache[key]
	var texture := ImageTexture.create_from_image(generate_image(species_index, seed_value))
	_sward_texture_cache[key] = texture
	return texture


func generate_image(species_index: int, seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	# An unknown index paints an ordinary plant rather than an empty square,
	# which would read as a hole in the meadow. Same never-crash-on-an-odd-id
	# convention as AnimalAnatomy.profile_for.
	var species := posmod(species_index, GroundCover.SPECIES.size())
	var colour: Color = LEAF_COLORS[species]
	var spread: int = LEAF_COUNT_MAX[species] - LEAF_COUNT_MIN[species]
	var leaf_count: int = LEAF_COUNT_MIN[species] + int(
		PixelNoise.value(seed_value, species, 0) % (spread + 1)
	)
	# A whole-plant angular offset, so two rosettes side by side are turned
	# differently even before per-leaf jitter.
	var base_angle := PixelNoise.unit(seed_value, species, 1) * TAU
	for index in leaf_count:
		var angle := base_angle + TAU * float(index) / float(leaf_count)
		# Wide enough that leaves genuinely crowd and gap rather than sitting on
		# a perfect star. A real rosette is lopsided; an evenly spaced one reads
		# as a snowflake, which is what the first pass looked like on screen.
		angle += (PixelNoise.unit(seed_value, species, 2 + index) - 0.5) * ANGLE_JITTER
		match species:
			0:
				_paint_trefoil_leaflet(image, angle, colour, seed_value, index)
			1:
				_paint_lance_leaf(image, angle, colour, seed_value, index)
			2:
				_paint_spoon_leaf(image, angle, colour, seed_value, index)
			_:
				_paint_feathered_frond(image, angle, colour, seed_value, index)
	return image


## Clover: a rounded leaflet held out on a short stalk. Three of them make the
## trefoil everyone can recognise from a lawn.
func _paint_trefoil_leaflet(
	image: Image, angle: float, colour: Color, seed_value: int, index: int
) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var stalk := 4.0 + PixelNoise.unit(seed_value, 11, index) * 2.0
	var radius := 3.0 + PixelNoise.unit(seed_value, 12, index) * 1.5
	var centre := _canvas_centre() + direction * (stalk + radius * 0.6)
	_paint_line(image, _canvas_centre(), centre, colour.darkened(0.15), 1)
	_paint_disc(image, centre, radius, colour)
	# The pale chevron a clover leaflet carries across its middle.
	_paint_disc(image, centre - direction * radius * 0.35, radius * 0.35, colour.lightened(HIGHLIGHT_LIGHTEN))


## Ribwort plantain: long narrow lance leaves lying flat, with a lighter
## midrib. The most grazing-tolerant thing in a pasture, and it looks it.
func _paint_lance_leaf(
	image: Image, angle: float, colour: Color, seed_value: int, index: int
) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var length := 6.0 + PixelNoise.unit(seed_value, 21, index) * 5.0
	var tip := _canvas_centre() + direction * length
	_paint_line(image, _canvas_centre(), tip, colour, 2)
	_paint_line(image, _canvas_centre(), _canvas_centre() + direction * length * 0.8, colour.lightened(HIGHLIGHT_LIGHTEN), 1)


## Daisy: a tight low rosette of short blunt spoon leaves, pressed flat enough
## to survive being trodden on -- which is exactly why it is on every lawn.
func _paint_spoon_leaf(
	image: Image, angle: float, colour: Color, seed_value: int, index: int
) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var length := 5.0 + PixelNoise.unit(seed_value, 31, index) * 2.5
	var tip := _canvas_centre() + direction * length
	_paint_line(image, _canvas_centre(), tip, colour, 2)
	_paint_disc(image, tip, 1.6, colour.lightened(HIGHLIGHT_LIGHTEN * 0.5))


## Yarrow: a fine feathery frond -- a thin rachis with tiny leaflets down both
## sides. Deep-rooted, and what holds a sward together through a dry spell.
func _paint_feathered_frond(
	image: Image, angle: float, colour: Color, seed_value: int, index: int
) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var perpendicular := Vector2(-direction.y, direction.x)
	var length := 5.0 + PixelNoise.unit(seed_value, 41, index) * 5.5
	_paint_line(image, _canvas_centre(), _canvas_centre() + direction * length, colour, 1)
	var step := 2.0
	var along := step
	while along < length:
		var spine := _canvas_centre() + direction * along
		var tick := 1.0 + PixelNoise.unit(seed_value, 42, index * 8 + int(along)) * 1.5
		_paint_line(image, spine, spine + perpendicular * tick, colour, 1)
		_paint_line(image, spine, spine - perpendicular * tick, colour, 1)
		along += step


func _canvas_centre() -> Vector2:
	return Vector2(SIZE) * 0.5


## A filled disc, clipped to the canvas.
func _paint_disc(image: Image, centre: Vector2, radius: float, colour: Color) -> void:
	var r := int(ceilf(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() > radius:
				continue
			_paint_pixel(image, int(centre.x) + dx, int(centre.y) + dy, colour)


## A straight line of the given pixel width, walked at half-pixel steps so a
## steep line has no gaps in it.
func _paint_line(image: Image, from: Vector2, to: Vector2, colour: Color, width: int) -> void:
	var span := to - from
	var steps := int(ceilf(span.length() * 2.0))
	if steps <= 0:
		return
	var half := int(floorf(float(width) / 2.0))
	for step in steps + 1:
		var point := from + span * (float(step) / float(steps))
		for oy in range(-half, half + 1):
			for ox in range(-half, half + 1):
				_paint_pixel(image, int(point.x) + ox, int(point.y) + oy, colour)


func _paint_pixel(image: Image, x: int, y: int, colour: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE.x or y >= SIZE.y:
		return
	image.set_pixel(x, y, colour)
