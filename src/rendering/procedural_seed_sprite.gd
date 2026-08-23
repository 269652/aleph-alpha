extends RefCounted

## A few seeds lying in the grass, shed by a nearby flower (see
## FlowerPatch.shed_seed / docs/concept/flora.md).
##
## Deliberately tiny and dull next to a bloom: seed is what a meadow looks
## like AFTER flowering, and it has to read as "something small on the
## ground" rather than competing with the flowers themselves. Coloured from
## the parent species so a patch of shed seed still says which plant dropped
## it -- the same "the world shows what it is" rule the rest of the flora
## follows.
##
## Pure/deterministic like every other procedural sprite here: the same
## (species, seed) always paints the same scatter, so a reloaded chunk looks
## identical.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")

## Art canvas. Small even at the 4x art resolution -- these are seeds.
const SIZE := Vector2i(8, 8)

## How much of a tile a seed scatter spans, in tiles. Well under one so
## several can lie near each other without merging into a blanket.
const WORLD_SPAN_TILES := 0.34
const TILE_SIZE := 16.0

## How many grains are painted per scatter.
const GRAIN_COUNT := 4

## Seed is dried, not fresh: the parent bloom's colour pulled well down
## toward husk brown, so it reads as chaff rather than as a tiny flower.
const HUSK_COLOR := Color(0.62, 0.53, 0.34)
const HUSK_BLEND := 0.65


static func world_scale() -> float:
	return (WORLD_SPAN_TILES * TILE_SIZE) / float(SIZE.x)


static func generate_image(species_id: String, seed_value: int) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var base: Color = FlowerSpecies.color_for(species_id).lerp(HUSK_COLOR, HUSK_BLEND)
	for grain in GRAIN_COUNT:
		# Scattered, not gridded: a real spill of seed is irregular.
		var x := PixelNoise.range_index(seed_value + 131, grain, 0, SIZE.x)
		var y := PixelNoise.range_index(seed_value + 977, grain, 1, SIZE.y)
		# Each grain is two pixels tall so it survives the downscale to world
		# size instead of disappearing into a single sub-pixel speck.
		image.set_pixel(x, y, base)
		if y + 1 < SIZE.y:
			image.set_pixel(x, y + 1, base.darkened(0.25))
	return image


static func generate_texture(species_id: String, seed_value: int) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(species_id, seed_value))
