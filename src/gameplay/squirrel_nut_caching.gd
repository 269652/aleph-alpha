extends RefCounted

## Squirrel scatter-hoarding of fallen tree NUTS (see
## docs/concept/flora.md's disperser-vs-predator tension).
##
## Mirrors SeedCaching's mouse scatter-hoarding SHAPE exactly (find a fallen
## item nearby, carry it a short GROUND distance on foot while going about
## its business, resolve once it has actually travelled that distance) but
## is its own module, deliberately not folded into SeedCaching:
##   - src/gameplay/seed_caching.gd (mouse grass-seed scatter-hoarding):
##     same on-foot short-carry shape, but that module has no "eaten instead
##     of cached" branch at all -- grass seed is always re-cached, never
##     destroyed -- and it reads/writes TallGrass's own ground-seed system,
##     not fallen tree nuts.
##   - src/gameplay/seed_endozoochory.gd (bird fruit/ground-seed
##     swallowing): a fleshy fruit is a real mutualism (the seed inside
##     always survives digestion); GRANIVORY_CONSUMED_CHANCE's predation
##     roll only ever applies to bare GROUND seed, never to the fruit/nut a
##     bird swallows whole. A squirrel cracking a NUT is the missing mirror
##     case this module exists for: an animal that reaches fallen fruit/nut
##     and sometimes actually destroys the seed instead of dispersing it --
##     see docs/concept/flora.md's "Still open for FRUIT/nut seed
##     specifically" note, which this module closes.
##
## Pure functions and constants, no RandomNumberGenerator and no node
## access -- the caller (EarthChunkManager, via CreatureMarker's own
## carried-state fields) owns "is this squirrel currently carrying a nut"
## and just asks these questions, exactly like SeedCaching/SeedEndozoochory.
## All randomness is derived from the carrier's own seed via PixelNoise, so
## a reloaded chunk reproduces the same caching.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
static var _fitness := AnimalFitness.new()

## How far a squirrel carries a cached nut before resolving it (eaten or
## cached), in tiles. Real squirrels have a much bigger home range and are
## far more mobile than a mouse -- scatter-hoarding studies routinely record
## cache distances well beyond a mouse's few-metre range -- so this sits
## ABOVE SeedCaching.CARRY_MAX_TILES (6.0). But a squirrel still moves on
## foot (hopping/climbing), not airborne, so it stays well below a bird's
## gut-passage flight range (SeedEndozoochory.CARRY_MIN_TILES, 10.0) -- see
## test_squirrel_carries_a_nut_farther_than_a_mouse_carries_grass_seed /
## test_squirrel_carry_range_is_shorter_than_bird_endozoochory for the pinned
## three-tier ordering.
const CARRY_MIN_TILES := 2.0
const CARRY_MAX_TILES := 9.0

## How close a squirrel must be to a fallen nut to notice and grab it while
## foraging, in tiles. A touch wider than SeedCaching.PICKUP_RADIUS_TILES
## (3.0, a mouse's own tight working patch): a squirrel is bigger, more
## visually alert, and covers more ground while foraging than a mouse does.
const PICKUP_RADIUS_TILES := 3.5

## Fraction of a picked-up NUT that a squirrel eats outright rather than
## caching -- see the file-level doc comment for why this is its own
## constant rather than a reuse of SeedEndozoochory.GRANIVORY_CONSUMED_CHANCE
## (0.8). Real scatter-hoarding studies on grey squirrels/chipmunks find
## caching is the MINORITY outcome for a handled nut -- most are eaten
## immediately, with caching becoming common mainly once immediate hunger is
## satisfied or a mast glut exceeds what can be eaten right away. 0.7 sits
## comfortably in that "clear majority eaten, real minority cached" range:
## high enough that eating-outright reads as the ordinary case, but
## deliberately LOWER than the bird's 0.8 (a squirrel actively investing
## effort in burying a valuable nut is a stronger, more deliberate dispersal
## force than a sparrow's incidental gut-passage survival of a tiny bare
## seed) -- see test_squirrels_cache_a_bigger_share_than_a_sparrows_
## incidental_survival for the pinned ordering.
const NUT_CONSUMED_CHANCE := 0.7

## How far an individual forager's own AnimalFitness.fitness_score (0..1) can
## nudge its personal consumption chance away from NUT_CONSUMED_CHANCE --
## mirrors SeedEndozoochory.FITNESS_CHANCE_SWING exactly, same magnitude and
## same real-world grounding: a fitter, more efficient forager destroys
## slightly more of what it handles, but real individual variation in
## foraging efficiency is a matter of a few percentage points, not a
## dramatic swing. The full [0,1] fitness range maps to NUT_CONSUMED_CHANCE
## +/- 3 percentage points (0.67 to 0.73), comfortably inside the 0.5-1.0
## "clear majority, not certainty" band
## test_nut_consumed_chance_is_a_majority_but_not_a_certainty already pins,
## for every individual, not just on average (see
## test_nut_consumption_chance_stays_a_modest_nudge_around_the_base_chance).
const NUT_FITNESS_CHANCE_SWING := 0.06


func _init() -> void:
	pass


## How far this squirrel carries a nut before resolving it, in tiles.
## Derived from the squirrel's own seed so it is stable across a reload, and
## spread across CARRY_MIN_TILES..CARRY_MAX_TILES so different individuals
## cache at different ranges (see SeedCaching.carry_distance_tiles, the same
## shape).
static func carry_distance_tiles(carrier_seed: int) -> float:
	var unit := PixelNoise.unit(carrier_seed, 0, 0)
	return CARRY_MIN_TILES + (CARRY_MAX_TILES - CARRY_MIN_TILES) * unit


## Which way this squirrel moves off with its picked-up nut, as a unit
## vector. Sampled at PixelNoise coordinate (0, 2) -- distinct from BOTH
## carry_distance_tiles's (0, 0) and nut_is_consumed's (0, 1) -- so heading,
## range, and the eaten-vs-cached roll all vary independently. Same
## independent-second-sample shape SeedEndozoochory.carry_direction/
## SeedDispersal.carry_direction/SeedCaching.carry_direction already use.
##
## Needed for the same reason those siblings' own carry_direction is:
## ordinary wander (CreatureWander.direction_at, shared by squirrels) is
## anchored to a home point within a fairly tight radius -- the SAME
## home-tethered containment shape AmbientFlyerMovement uses for birds -- so
## a squirrel whose home never moves cannot reach this module's own
## CARRY_MIN_TILES..CARRY_MAX_TILES range by wander alone. Not separately
## measured the way SeedDispersal/SeedCaching were (see docs/progress.md) --
## fixed by analogy, since it shares the identical CreatureWander/
## CreatureMarker movement substrate and a similarly-out-of-reach range
## (2-9 tiles against the same measured ~2.6-tile ceiling) -- but IS covered
## by the same real-range regression test the other two carriers get.
static func carry_direction(carrier_seed: int) -> Vector2:
	return Vector2.from_angle(PixelNoise.range_value(carrier_seed, 0, 2, 0.0, TAU))


## This forager's own personal consumption chance: NUT_CONSUMED_CHANCE
## nudged by its AnimalFitness.fitness_score (see NUT_FITNESS_CHANCE_SWING).
## `forager_seed` is the squirrel's own per-individual identity seed (see
## CreatureMarker.wander_seed) -- fixed for that squirrel's whole life,
## unlike the per-pick `carrier_seed` nut_is_consumed itself rolls against.
## Mirrors SeedEndozoochory.consumption_chance_for exactly.
static func nut_consumption_chance_for(forager_seed: int) -> float:
	var fitness_score: float = _fitness.fitness_score(_fitness.phenotype_for(forager_seed))
	return NUT_CONSUMED_CHANCE + (fitness_score - 0.5) * NUT_FITNESS_CHANCE_SWING


## Whether THIS particular carried nut is eaten outright rather than
## surviving to be cached (see nut_consumption_chance_for). PixelNoise-seeded
## off the carrier -- never Godot's string hash() (see PixelNoise's own doc
## comment) -- sampled at a coordinate distinct from carry_distance_tiles's
## so the two rolls vary independently for the same carrier, exactly like
## SeedEndozoochory.seed_is_consumed vs. its own carry_distance_tiles.
##
## `forager_seed` (the eating squirrel's own identity seed, defaulting to
## `carrier_seed` for callers that don't distinguish the two) decides WHOSE
## fitness nudges the chance; `carrier_seed` decides the actual roll -- kept
## separate so the same squirrel rolls independently for each nut it handles
## while still using its own fixed fitness every time.
static func nut_is_consumed(carrier_seed: int, forager_seed: int = carrier_seed) -> bool:
	return PixelNoise.unit(carrier_seed, 0, 1) < nut_consumption_chance_for(forager_seed)
