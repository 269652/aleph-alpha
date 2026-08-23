extends RefCounted

## Where a fruit lands when it falls (see docs/concept/flora.md#where-a-forest-
## comes-from).
##
## Fruit falls uniformly across the parent's own tile and the eight around it
## -- the three-by-three block a real canopy overhangs.
##
## This exists because fruit used to land on the tree's exact position, which
## meant every seed a wood produced landed on a tile that already had a tree in
## it. A fruit that always lands on the trunk can never found a tree.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How far from the trunk fruit can land, in tiles, along each axis.
##
## One and a half tiles reaches the far edge of the eight neighbours and no
## further: the canopy block, and nothing outside it. Fruit thrown further than
## the crown that grew it would not be falling, it would be scattering.
const SPREAD_TILES := 1.5


## Where this fruit lands, relative to the tree that dropped it.
##
## Uniform in both axes, so the nine tiles share the crop evenly rather than
## the wood creeping in whichever direction the noise happens to lean.
##
## PixelNoise rather than Godot's string hash: the hash is near-linear across
## inputs that differ only in a trailing number, and this project has been
## bitten by that twice -- diagonal banding in terrain, and then a whole crop
## of cherries landing within a tenth of a pixel of each other.
static func fall_offset(seed_value: int) -> Vector2:
	return Vector2(
		_axis(seed_value, 61), _axis(seed_value, 67)
	) * SPREAD_TILES * TerrainRenderer.TILE_SIZE


## One axis, in [-1, 1] and strictly INSIDE it.
##
## Half-open on purpose: an offset of exactly 1.5 tiles rounds into the TENTH
## tile, one step outside the block, and a nine-tile spread that occasionally
## produces ten is not the shape it claims to be. Sampling cell centres keeps
## it symmetric and strictly interior.
const _STEPS := 2000


static func _axis(seed_value: int, salt: int) -> float:
	var step := PixelNoise.range_index(seed_value, salt, 0, _STEPS)
	return (float(step) + 0.5) / float(_STEPS) * 2.0 - 1.0
