extends RefCounted

## Rodent scatter-hoarding of grass seed (see
## docs/concept/long_grass.md#reproduction-seed-and-how-a-field-colonises-
## ground-it-never-touches).
##
## Distinct from BOTH existing carriers, and deliberately so:
##   - src/world/seed_dispersal.gd (flower EPIzoochory): seed rides on a
##     grazer's COAT after brushing a bloom, dropped once it has wandered off.
##   - src/gameplay/seed_endozoochory.gd (bird endozoochory, tree/fruit AND
##     grass seed both route through this for the sparrow -- see
##     EarthChunkManager._step_grass_seed_caching's doc comment): the seed is
##     SWALLOWED and survives a real gut-passage-timed digestion in flight.
##
## A real scatter-hoarding rodent does neither: it does not fly, and it does
## not digest a whole seed in transit. It finds one, carries it a short
## distance on foot in its cheek pouch while it goes on foraging, and caches
## it nearby but not adjacent -- often forgetting a fraction of what it
## buried, which in reality is exactly how a lot of wild seed dispersal by
## rodents actually establishes new plants. That is a genuinely different
## mechanism, not just a shorter-range copy of either existing one, so it
## gets its own small module rather than reusing SeedEndozoochory's
## flight-time carry model with smaller numbers.
##
## Pure functions and constants, no RandomNumberGenerator and no node
## access -- the caller (EarthChunkManager, via CreatureMarker's own
## carried-state fields) owns "is this mouse currently carrying a seed" and
## just asks these questions, exactly like SeedDispersal/SeedEndozoochory.
## All randomness is derived from the carrier's own seed via PixelNoise, so a
## reloaded chunk reproduces the same caching.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## How far a mouse carries a cached seed before dropping it, in tiles. A
## small fraction of either existing carrier's range: real scatter-hoarding
## rodents cache within their own tiny home range, a few real-world metres
## from where they found the seed -- on foot and close by, not airborne and
## far. Deliberately below both SeedDispersal.CARRY_MIN_TILES (3.0, a
## grazer's coat-carried wander) and SeedEndozoochory.CARRY_MIN_TILES (10.0,
## a bird's gut-passage flight) rather than merely below their maximums --
## see test_rodent_carry_range_is_shorter_than_* for the pinned relationship.
const CARRY_MIN_TILES := 1.0
const CARRY_MAX_TILES := 6.0

## How close a mouse must be to a fallen grass seed to notice and grab it
## while foraging, in tiles. Tight, like SeedDispersal.PICKUP_RADIUS_TILES
## (1.5, "brushed against it") -- a mouse is a small animal working a small
## patch of ground, not scanning a whole meadow, but it is actively looking
## (unlike a grazer's passive coat-brushing), so the radius is a little wider
## than a literal brush.
const PICKUP_RADIUS_TILES := 3.0


func _init() -> void:
	pass


## How far this mouse carries a cached seed before dropping it, in tiles.
## Derived from the mouse's own seed so it is stable across a reload, and
## spread across CARRY_MIN_TILES..CARRY_MAX_TILES so different individuals
## cache at different ranges (see SeedDispersal.carry_distance_tiles, the
## same shape).
static func carry_distance_tiles(carrier_seed: int) -> float:
	var unit := PixelNoise.unit(carrier_seed, 0, 0)
	return CARRY_MIN_TILES + (CARRY_MAX_TILES - CARRY_MIN_TILES) * unit


## Which way this mouse moves off with its cached seed, as a unit vector.
## Sampled at a PixelNoise coordinate distinct from carry_distance_tiles's
## (0, 0) so heading and range vary independently -- the same
## independent-second-sample shape SeedEndozoochory.carry_direction/
## SeedDispersal.carry_direction already use.
##
## Needed for the same reason SeedDispersal's own carry_direction is:
## ordinary wander (CreatureWander.direction_at, shared by mice) is anchored
## to a home point within a fairly tight radius -- the SAME home-tethered
## containment shape AmbientFlyerMovement uses for birds -- so a mouse whose
## home never moves cannot reach this module's own CARRY_MIN_TILES..
## CARRY_MAX_TILES range by wander alone. Measured directly: a hard ~2.6-tile
## ceiling regardless of wander_seed, against a 1-6 tile intended range (see
## docs/progress.md); real hunger/foraging movement alone rescued most of the
## SHORT end of that range but not the top ~20%. Blended into ordinary wander
## by CreatureMarker._wander_step, not used to override it outright.
static func carry_direction(carrier_seed: int) -> Vector2:
	return Vector2.from_angle(PixelNoise.range_value(carrier_seed, 0, 1, 0.0, TAU))
