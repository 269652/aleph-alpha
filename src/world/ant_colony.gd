extends RefCounted

## Per-chunk ant colony population -- the myrmecochory (seed-harvesting)
## soil-invertebrate tier named in docs/concept/soil_fauna.md's "other soil
## fauna" open item, now closed for ants.
##
## Deliberately shaped like EarthwormPatch/FlowerPatch/TallGrass/DesertScrub/
## TundraLichen -- deterministic PixelNoise-seeded placement, a hard
## per-chunk cap, advance(delta) -- rather than sharing a base class with
## them (see DesertScrub's doc comment on why three similar things beats a
## premature abstraction).
##
## What is genuinely different from EarthwormPatch: a mound is a whole
## COLONY, not a single animal, and this pass gives it no rendered or eaten
## state at all (see "explicitly out of scope" in the soil_fauna.md doc) --
## only a place, and a small deterministic per-step chance that the colony
## sends a forager out to check the ground near its mound for a fallen grass
## seed (grassland) or a fallen windfall fruit/nut (forest/rainforest, see
## WINDFALL_CONSUMED_CHANCE below). There is no surfacing/weather machinery:
## ants are not driven by soil moisture the way earthworms are, and giving
## them one here would be unjustified plumbing for a behaviour this pass
## doesn't need.
##
## No RandomNumberGenerator, and no Godot string hash either for anything
## PER-CELL: all placement and per-step rolls are derived from the chunk seed
## via PixelNoise, which (unlike `hash`) decorrelates neighbouring cells and
## neighbouring steps -- the clustering bug this project has hit five times.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Biomes with real organic soil an ant can excavate -- the same set
## EarthwormPatch uses, and for the same reasons (ocean has no soil, desert
## soil is too loose and dry, tundra is permafrost). Ants are NOT restricted
## to grassland in the real world (leafcutter and army ants are a defining
## feature of rainforest, for instance), so mounds are seeded across all
## three. What USED TO BE scoped to grassland alone was what a mound could
## actually forage: TallGrass, the only source of ground SEED in this game,
## only grows in grassland (see TallGrass._seed_initial_patches). A forest/
## rainforest mound now has a second forage target instead of sitting idle:
## a nearby fallen windfall fruit/nut ground item (the same
## EarthChunkManager.fruit_near/take_fruit_at API SquirrelNutCaching already
## uses), gated to real NUTS (TreeSpecies.is_nut) the same way
## SquirrelNutCaching gates its own pickup. See WINDFALL_CONSUMED_CHANCE's
## own doc comment for why this is a far more consumption-dominant case than
## the grass-seed myrmecochory above -- a single forager ant cannot carry off
## an intact nut/dried-fruit propagule the way a squirrel or bird can.
const SOIL_BIOMES := {"grassland": true, "forest": true, "rainforest": true}

## Chance a given soil cell holds a mound. Real ant nest density per unit
## area is typically HIGHER than earthworm burrow density in the same soil
## (a hectare of temperate grassland commonly holds many dozens of nests
## across several species, against a much sparser scatter of worm burrows),
## so this sits above EarthwormPatch.SEED_CHANCE -- pinned as an ordering by
## test_mounds_are_denser_than_earthworm_burrows, not just asserted here.
## Still far under TallGrass.SEED_CHANCE: a mound is a whole colony's single
## entrance, not a blade of grass.
const MOUND_CHANCE := 0.05

## Hard cap per chunk. Deliberately LOWER than EarthwormPatch.MAX_WORMS (24)
## despite the higher per-cell chance above: one mound represents an entire
## colony ranging out over many tiles, not one individual the way a single
## worm is one worm, so far fewer of them are needed to represent a chunk's
## ground as "actively foraged." Above the ~50 a full soil chunk seeds at
## MOUND_CHANCE, so in practice it is what actually governs the count.
const MAX_MOUNDS := 10

## Chance, per call to advance(), that a given mound's colony sends a
## forager out to check the ground near it this step. A caller (see
## EarthChunkManager.step_ants) is expected to call advance() many times a
## second under normal play, the same cadence step_worms runs at -- so
## anything close to 1.0 would empty every seed within the first second of a
## chunk loading. Kept small so foraging reads as ongoing background
## activity, the same reasoning EarthwormPatch's SURFACE_RATE/BURROW_RATE
## comments give for why THEIR numbers are small. Pinned in range by
## test_forage_chance_is_small, and its actual foraging-in-the-flesh effect
## (a seed gets taken eventually, not every single call) is pinned by
## test_forage_roll_spreads_across_true_and_false.
const FORAGE_CHANCE := 0.05

## How close a fallen grass seed has to be to a mound for its colony to
## notice it, in tiles. SHORTER than SeedCaching.PICKUP_RADIUS_TILES (3.0,
## a foraging mouse's own noticing range): an ant's foraging range from its
## mound entrance is far smaller than a mouse's whole home range. Pinned by
## test_ant_forage_radius_is_shorter_than_rodent_pickup_radius.
const FORAGE_RADIUS_TILES := 1.0

## How far a mound caches a harvested seed before it counts as planted, in
## tiles. This is the shortest-range disperser of the game's whole carrier
## family, and deliberately so, in order:
##   1. SeedDispersal (grazer epizoochory, coat-carried): 3.0 .. 14.0 tiles.
##   2. SeedEndozoochory (bird gut-passage, carried in flight): 10 .. 40.
##   3. SeedCaching (mouse scatter-hoard, carried on foot): 1.0 .. 6.0.
##   4. This (ant myrmecochory, carried by a single worker): shortest of all.
## Real myrmecochory moves a seed only centimetres to a couple of metres --
## the shortest-range seed dispersal mechanism that exists in nature, well
## under even a mouse's tiny cache range. Pinned below SeedCaching's own
## CARRY_MIN_TILES (not just its max) by
## test_ant_carry_range_is_shorter_than_rodent_carry_range, mirroring how
## SeedCaching itself is pinned below SeedDispersal/SeedEndozoochory in
## test_seed_caching.gd.
const CARRY_MIN_TILES := 0.15
const CARRY_MAX_TILES := 0.9

## Salt for the per-step foraging roll and the carrier-seed sample, so
## "does this mound forage this step" and "where does it cache the seed" are
## independent draws -- the same independent-second-sample technique
## EarthwormPatch's _RELUCTANCE_SALT uses to keep placement and reluctance
## from correlating.
const _FORAGE_SALT := 419
const _CARRY_SALT := 6131

## Fraction of a windfall fruit/nut find a mound's forager consumes outright
## on the spot rather than surviving to be cached as a new sapling
## (see windfall_is_consumed). Its own constant, deliberately NOT a reuse of
## SquirrelNutCaching.NUT_CONSUMED_CHANCE (0.7) or SeedEndozoochory.
## GRANIVORY_CONSUMED_CHANCE (0.8): both of those model an animal that can
## physically carry the WHOLE propagule away intact (a squirrel in its
## mouth, a bird's whole gut) and only sometimes destroys it. A single
## forager ant cannot do that at all -- it cannot carry off an intact nut or
## dried fruit. Real ants interacting with fallen fruit/nut debris are
## documented almost entirely as scavengers/decomposers, stripping and
## consuming soft pulp/residue in place rather than dispersing the hard
## propagule itself; true myrmecochory in nature is specific to small,
## elaiosome-bearing seeds -- exactly the ground-seed case this file already
## models via FORAGE_CHANCE/CARRY_MIN_TILES/CARRY_MAX_TILES above. A fallen
## tree nut is a genuinely different, far more consumption-dominant case for
## this disperser, so this sits ABOVE both existing consumed-chance
## constants -- ants are the LEAST effective disperser of a large propagule
## of any forager in this game. Pinned by
## test_windfall_consumed_chance_is_higher_than_squirrel_and_sparrow. Never
## 1.0 though -- never say never, the same pattern every other
## consumed-vs-cached mechanic in this game follows -- a real, nonzero
## minority still gets carried the short CARRY_MIN_TILES..CARRY_MAX_TILES
## distance above and counts as planted, pinned by
## test_windfall_is_consumed_mostly_true_but_leaves_a_real_minority_cached.
const WINDFALL_CONSUMED_CHANCE := 0.93

## Salt for the windfall consumed-vs-cached roll (see windfall_carrier_seed_for/
## windfall_is_consumed), independent of both _FORAGE_SALT (does this mound
## forage this step) and _CARRY_SALT (where a harvested item gets cached) --
## the same independent-second-sample technique those two use to keep
## separate per-mound-per-step rolls from correlating with each other.
const _WINDFALL_SALT := 27457

var _width: int
var _height: int
var _biome: PackedStringArray
var _seed_value: int

## Vector2i cell -> true. The mounds a chunk seeds at construction; fixed for
## the chunk's whole life, exactly like EarthwormPatch's burrows.
var _mounds: Dictionary = {}

## How many times advance() has been called. The only per-tick state a
## mound needs this pass -- there is no surfacing value to animate and
## nothing here changes over real seconds, so a discrete step counter (not
## elapsed_seconds) is genuinely all that drives the per-step foraging roll
## and the carrier-seed sample below.
var _step_count: int = 0


func _init(seed_value: int, width: int, height: int, biome: PackedStringArray) -> void:
	_seed_value = seed_value
	_width = width
	_height = height
	_biome = biome
	_seed_initial_mounds()


func mound_cells() -> Array:
	return _mounds.keys()


func has_mound(cell: Vector2i) -> bool:
	return _mounds.has(cell)


## Advances the colony's own step count. Accepts `delta` to match the shared
## patch-sim advance(delta) shape every other per-chunk sim in this project
## uses, but does not need it: ants have no EarthwormPatch-style surfacing
## value to animate over real seconds, only a discrete "which step is this"
## counter that the foraging roll and carrier seed are sampled against.
func advance(_delta: float) -> void:
	_step_count += 1


## Whether this mound's colony sends a forager out to check for a nearby
## seed THIS step. A pure, PixelNoise-seeded roll against the mound's own
## position and the colony's current step -- never Godot's string hash,
## which correlates neighbouring inputs instead of spreading them.
func should_forage(cell: Vector2i) -> bool:
	return PixelNoise.unit(
		_seed_value + _step_count + _FORAGE_SALT, cell.x, cell.y
	) < FORAGE_CHANCE


## A deterministic seed for "the carry this mound's forager makes right now",
## derived from the mound's own position and the colony's current step so a
## reloaded chunk at the same step caches identically, and different mounds
## (or the same mound at a different step) don't collide on the same offset.
## Feed this into carry_distance_tiles/carry_direction to place the cache.
func carrier_seed_for(cell: Vector2i) -> int:
	return PixelNoise.value(_seed_value + _step_count + _CARRY_SALT, cell.x, cell.y)


## A deterministic seed for "is the windfall fruit/nut THIS mound's forager
## just grabbed consumed outright or actually cached", derived from the
## mound's own position and the colony's current step via its own salt
## (_WINDFALL_SALT) so it never correlates with should_forage's or
## carrier_seed_for's own rolls for the same (cell, step) -- the same
## independent-second-sample technique those two already use between each
## other. Feed this into windfall_is_consumed.
func windfall_carrier_seed_for(cell: Vector2i) -> int:
	return PixelNoise.value(_seed_value + _step_count + _WINDFALL_SALT, cell.x, cell.y)


## How far this carry travels before the seed counts as cached, in tiles.
## Spread across CARRY_MIN_TILES..CARRY_MAX_TILES the same shape as
## SeedCaching.carry_distance_tiles/SeedDispersal.carry_distance_tiles, so
## different carries range differently rather than all landing at once
## distance.
static func carry_distance_tiles(carrier_seed: int) -> float:
	var unit := PixelNoise.unit(carrier_seed, 0, 0)
	return CARRY_MIN_TILES + (CARRY_MAX_TILES - CARRY_MIN_TILES) * unit


## Which way this carry heads, as a unit vector. Sampled independently of
## the distance above (different PixelNoise inputs) so direction and range
## don't correlate, the same independent-second-sample technique the class
## doc comment describes for _FORAGE_SALT/_CARRY_SALT.
static func carry_direction(carrier_seed: int) -> Vector2:
	var angle := PixelNoise.unit(carrier_seed, 1, 0) * TAU
	return Vector2(cos(angle), sin(angle))


## Whether a windfall fruit/nut find is consumed outright rather than
## surviving to be cached (see WINDFALL_CONSUMED_CHANCE). PixelNoise-seeded
## off `windfall_seed` (see windfall_carrier_seed_for) -- never Godot's
## string hash(), which correlates neighbouring inputs instead of spreading
## them.
static func windfall_is_consumed(windfall_seed: int) -> bool:
	return PixelNoise.unit(windfall_seed, 0, 0) < WINDFALL_CONSUMED_CHANCE


func _seed_initial_mounds() -> void:
	for y in _height:
		for x in _width:
			if _mounds.size() >= MAX_MOUNDS:
				return
			if not SOIL_BIOMES.has(_biome[y * _width + x]):
				continue
			if PixelNoise.unit(_seed_value, x, y) >= MOUND_CHANCE:
				continue
			_mounds[Vector2i(x, y)] = true
