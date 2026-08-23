extends RefCounted

## Where the wind puts a seed (see docs/concept/seed_dispersal.md).
##
## Pure and engine-free: this answers "how far and which way", and the caller
## decides whether anything can actually grow where it lands.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## ## Weight classes
##
## Weight is the single property that decides how far a seed travels, and it is
## the whole reason plants have different seeds: a dandelion seed and an acorn
## fall from the same height in the same wind and land a hundred metres apart.
## That difference is why meadows colonise faster than woods.
##
## Expressed as a terminal-velocity analogue -- lower is lighter and drifts
## further -- in the order the real seeds fall.
const WEIGHT_FLOWER_SEED := 0.08  # plumed or dust-fine, built for wind
const WEIGHT_BERRY_PIP := 0.3  # small, but no plume
const WEIGHT_TREE_FRUIT := 0.7  # carried by animals, not air
const WEIGHT_NUT := 1.0  # drops within a crown-width, always

## How far the wind can carry the lightest seed at full strength, in tiles.
const MAX_DRIFT_TILES := 14.0

## How far a seed scatters with NO wind at all -- it still has to land
## somewhere, it just does not go far. Independent of the wind so a dead calm
## does not stack every seed on the parent.
const CALM_SCATTER_TILES := 1.2

## Nothing travels further than this, whatever the wind. A bound rather than a
## behaviour: the tail of a heavy-tailed distribution has no natural end, and a
## seed that leaves the loaded world is a seed that quietly vanishes.
const MAX_TRAVEL_TILES := MAX_DRIFT_TILES + CALM_SCATTER_TILES

## How heavy the tail is.
##
## Real wind dispersal is heavy tailed: the bulk of a plant's seed falls within
## a few body-widths and a small fraction goes a very long way. That tail is
## what actually colonises new ground -- a uniform scatter gives neither a
## dense home patch nor any pioneers. Raising this concentrates seed closer in
## and makes the far-flung ones rarer.
const TAIL_POWER := 3.0


## Where this seed lands, relative to the plant that shed it.
##
## `weight` is one of the WEIGHT_ constants, `direction` the day's wind (a unit
## vector) and `strength` its force, 0 calm to 1 gale.
static func landing_offset(
	seed_value: int, weight: float, direction: Vector2, strength: float
) -> Vector2:
	var lightness := clampf(1.0 - clampf(weight, 0.0, 1.0), 0.0, 1.0)
	var force := clampf(strength, 0.0, 1.0)

	# Heavy-tailed distance: a uniform roll raised to a power spends most of
	# its range near zero, so most seed lands close and a little goes far.
	var roll := float(PixelNoise.range_index(seed_value, 71, 0, 1000)) / 999.0
	var reach := pow(roll, TAIL_POWER)

	# Downwind: along the day's wind, scaled by how hard it blows and how
	# little the seed weighs. A nut in a gale barely moves; a plumed seed in
	# the same gale crosses the meadow.
	var downwind := direction.normalized() * reach * force * lightness * MAX_DRIFT_TILES

	# Scatter: where it would have gone with no wind at all. Independent of
	# the wind, so a dead calm still spreads seed around the parent.
	var angle := float(PixelNoise.range_index(seed_value, 73, 0, 360)) * PI / 180.0
	var spread := sqrt(float(PixelNoise.range_index(seed_value, 79, 0, 1000)) / 999.0)
	var scatter := Vector2(cos(angle), sin(angle)) * spread * CALM_SCATTER_TILES

	var offset := (downwind + scatter) * TerrainRenderer.TILE_SIZE
	var limit := MAX_TRAVEL_TILES * TerrainRenderer.TILE_SIZE
	return offset.limit_length(limit)
