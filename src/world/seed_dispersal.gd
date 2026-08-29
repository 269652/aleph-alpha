extends RefCounted

## Flowers spread because animals carry their seed (see
## docs/concept/flora.md#spread-by-animal-seed-dispersal).
##
## Deliberately NOT tile-adjacency spread like TallGrass uses: an animal
## grazing through a bloom picks seed up, carries it while it wanders, and
## drops it somewhere along its own path. That ties flower spread to the
## ecosystem's real movement corridors -- a region that loses its grazers
## slowly stops spreading flowers -- which is the same "ecology has
## consequences" thread as tree spread (see TreeSpread /
## ecosystem_dynamics.md).
##
## Pure functions, no RandomNumberGenerator and no node access: the caller
## owns the "who is carrying what" state and just asks these questions. All
## randomness is derived from the carrier's own seed via PixelNoise, so a
## reloaded chunk reproduces the same dispersal.

const FlowerSpecies = preload("res://src/world/flower_species.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## How close an animal must pass to a bloom to pick its seed up, in tiles.
## Roughly "brushed against it", not "was in the same meadow".
const PICKUP_RADIUS_TILES := 1.5

## How far seed rides before being dropped, in tiles. The spread MIN..MAX is
## what keeps spread from stamping a constant radius around every patch --
## a fixed distance reads as a pattern rather than as dispersal.
const CARRY_MIN_TILES := 3.0
const CARRY_MAX_TILES := 14.0

## Where a dropped seed can actually sprout. Flowers are meadow plants: they
## take in grassland, and a seed dropped in the sea or on bare rock is simply
## lost (which is itself a real check on spread).
const ROOTABLE_BIOMES: Array[String] = ["grassland"]


func _init() -> void:
	pass


## The species whose seed an animal at `position` picks up, or "" for none.
##
## Only BLOOMING flowers give seed -- a rose in winter is just a plant -- and
## only ones within PICKUP_RADIUS_TILES. When several are in reach the
## nearest wins, so an animal carries what it actually brushed against.
static func pickup_species(
	position: Vector2, flowers: Array, season: String, tile_size: float, _carrier_seed: int
) -> String:
	if tile_size <= 0.0:
		return ""
	var best_species := ""
	var best_distance := PICKUP_RADIUS_TILES
	for flower in flowers:
		var species := String(flower["species"])
		if FlowerSpecies.scent_strength(species, season) <= 0.0:
			continue  # present but not in bloom -- no seed on offer
		var distance_tiles: float = position.distance_to(flower["position"]) / tile_size
		if distance_tiles <= best_distance:
			best_distance = distance_tiles
			best_species = species
	return best_species


## How far this carrier takes seed before dropping it, in tiles. Derived from
## the carrier's own seed so it is stable across a reload, and spread across
## CARRY_MIN_TILES..CARRY_MAX_TILES so different animals plant at different
## ranges.
static func carry_distance_tiles(carrier_seed: int) -> float:
	var unit := PixelNoise.unit(carrier_seed, 0, 0)
	return CARRY_MIN_TILES + (CARRY_MAX_TILES - CARRY_MIN_TILES) * unit


## Which way this carrier moves off with its picked-up seed, as a unit
## vector. Sampled at a PixelNoise coordinate distinct from
## carry_distance_tiles's (0, 0) so heading and range vary independently for
## the same carrier -- the same independent-second-sample shape
## SeedEndozoochory.carry_direction/AntColony.carry_direction already use for
## their own carrier seeds.
##
## Needed for the same reason SeedEndozoochory needed one: ordinary wander
## (CreatureWander.direction_at) is anchored to a home point within a fairly
## tight radius -- the SAME home-tethered containment shape
## AmbientFlyerMovement uses for birds -- so a carrier whose home never moves
## cannot reach this module's own CARRY_MIN_TILES..CARRY_MAX_TILES range by
## wander alone. Measured directly, not assumed: a hard ~2.6-tile ceiling
## across 30 sampled wander_seeds regardless of what carry_distance_tiles
## actually intended, and real hunger/foraging movement alone rescued only
## 2 of those 30 within a 15-simulated-minute window (see docs/progress.md).
## Blended into ordinary wander by CreatureMarker._wander_step, not used to
## override it outright -- see that function's own doc comment.
static func carry_direction(carrier_seed: int) -> Vector2:
	return Vector2.from_angle(PixelNoise.range_value(carrier_seed, 0, 1, 0.0, TAU))


## Whether a seed dropped on `biome_name` can sprout there at all. Unknown
## biomes deliberately return false: a new biome should have to opt in to
## growing flowers rather than silently inheriting them.
static func can_root_in(biome_name: String) -> bool:
	return ROOTABLE_BIOMES.has(biome_name)
