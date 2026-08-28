extends RefCounted

## Bird endozoochory for fruit-tree seeds (see docs/concept/flora.md#bird-
## endozoochory and docs/concept/ecosystem_dynamics.md's frugivory section).
##
## Distinct from src/world/seed_dispersal.gd (flower EPIzoochory: a grazer
## brushes past a bloom and seed rides on its coat until it wanders off).
## Here the seed is SWALLOWED WHOLE along with the fruit and survives
## digestion -- deposited only once the bird has actually gone on its way,
## not picked up by proximity and not dropped after a ground-walked
## distance. Shares the pickup->carry->can-root-in->plant SHAPE
## SeedDispersal already established (the idiom this codebase uses for every
## animal-carried seed), but is its own module: a different disperser
## (birds, not grazers), a different distance range, and different rootable
## biomes (fruit TREES, not meadow flowers).
##
## Pure functions and constants, no RandomNumberGenerator and no node
## access: the caller (AmbientFlyerMarker) owns "is this bird currently
## carrying a seed" state and just asks these questions, exactly like
## SeedDispersal.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const TreeRooting = preload("res://src/world/tree_rooting.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
static var _fitness := AnimalFitness.new()

## How far a bird carries a swallowed seed before depositing it, in tiles.
## Deliberately further than SeedDispersal's ground-epizoochory range
## (3..14 tiles): a bird is airborne and gut passage takes real time (small
## birds: roughly 15-60 minutes for a fruit to pass), so by the time it
## deposits the seed it has typically covered much more ground than a
## grazer that merely carried seed on its coat until it happened to brush
## it off.
const CARRY_MIN_TILES := 10.0
const CARRY_MAX_TILES := 40.0

## Where a dispersed tree seed can actually take root. Trees, unlike meadow
## flowers, establish in forest/rainforest -- the same biomes the original
## map-generated forest already grows in (see TreePlacement.FOREST_BIOMES) --
## not grassland; a seed dropped mid-meadow, in the sea, or on bare rock is
## simply lost, the same honest "not every drop succeeds" SeedDispersal
## already models.


func _init() -> void:
	pass


## How far this bird carries seed before depositing it, in tiles. Derived
## from the bird's own seed (see PixelNoise) so it's stable and reproducible
## for a given bird, and spread across CARRY_MIN_TILES..CARRY_MAX_TILES so
## different birds plant at different ranges.
static func carry_distance_tiles(carrier_seed: int) -> float:
	return PixelNoise.range_value(carrier_seed, 0, 0, CARRY_MIN_TILES, CARRY_MAX_TILES)


## Which way this bird flies off with its swallowed seed, as a unit vector.
## Sampled at a PixelNoise coordinate distinct from carry_distance_tiles's
## (0,0) so heading and range vary independently for the same carrier -- a
## fast, far-flying bird is equally likely in any direction -- the same
## independent-second-sample shape AntColony.carry_direction/
## carry_distance_tiles already uses for its own carrier seed. Real
## dispersal direction is arbitrary (a bird takes off whichever way its next
## activity pulls it), so this is a uniform random heading, never biased
## toward or away from the parent plant.
##
## Distance alone turned out not to be enough to actually disperse a seed:
## AmbientFlyerMarker's ordinary wander is anchored to a home point within a
## fairly tight radius (measured at a hard ~2.5-tile ceiling for a sparrow,
## regardless of wander_seed or this module's own 10-40 tile range), so a
## carrying bird needs an actual heading to fly off in -- see
## AmbientFlyerMarker._step_seed_carrying's own doc comment for the full
## story, and docs/progress.md for the measurement.
static func carry_direction(carrier_seed: int) -> Vector2:
	return Vector2.from_angle(PixelNoise.range_value(carrier_seed, 0, 2, 0.0, TAU))


## Whether a tree seed dropped on `biome_name` can sprout there at all.
## Delegates to TreeRooting, which is the ONE answer to "can a tree stand
## here".
##
## This used to keep its own list -- forest and rainforest, where the
## map-generated forest already grows -- while ground spread had no check at
## all. Two rules for one question is how this project has repeatedly ended up
## with a rendered assumption and a simulated one drifting apart, and it also
## meant a bird could not seed a meadow, which is most of what birds are for.
static func can_root_in(biome_name: String) -> bool:
	return TreeRooting.can_root_in(biome_name)


## Fraction of swallowed GROUND seed -- flower or grass seed picked up bare
## off the ground, see AmbientFlyerMarker._step_seed_carrying's flower/grass
## branches -- that a sparrow's gizzard simply grinds up rather than passing
## intact. Deliberately NOT applied to fruit-tree seed (the `elif
## fruit_world` branch of that same function): a fleshy fruit exists
## specifically so the seed riding inside it is swallowed whole and
## survives, a real mutualism, whereas a bare seed IS the meal for a true
## granivore.
##
## Real seed-predation studies on granivorous songbirds (sparrows, finches,
## and relatives cracking cereal/weed seed) consistently find the large
## majority of what is eaten destroyed in digestion, with only a minority
## surviving gut passage or scatter-caching to actually establish a new
## plant -- commonly cited figures cluster in the 70-90% consumed range. 80%
## sits in the middle of that range: high enough to read as real predation
## (not a coin flip), low enough that the disperser mechanic this module
## exists for still fires often enough to matter, rather than making
## bird-planted flowers/grass a near-impossibility despite the code path
## still being there. See test_granivory_consumed_chance_is_a_large_majority
## for the pinned bounds and test_seed_mostly_consumed_but_sometimes_survives
## for the resulting distribution.
const GRANIVORY_CONSUMED_CHANCE := 0.8

## How far an individual forager's own AnimalFitness.fitness_score (0..1) can
## nudge its personal consumption chance away from GRANIVORY_CONSUMED_CHANCE
## -- AnimalFitness's first real caller here. A fitter, more efficient
## forager destroys slightly more of what it eats, but real individual
## variation in foraging efficiency among granivorous songbirds is a matter
## of a few percentage points, not a dramatic swing: the full [0,1] fitness
## range maps to GRANIVORY_CONSUMED_CHANCE +/- 3 percentage points (0.77 to
## 0.83), comfortably inside the 0.5-1.0 "large majority, not certainty" band
## test_granivory_consumed_chance_is_a_large_majority already pins, for
## every individual, not just on average (see
## test_consumption_chance_stays_a_modest_nudge_around_the_base_chance).
const FITNESS_CHANCE_SWING := 0.06


## This forager's own personal consumption chance: GRANIVORY_CONSUMED_CHANCE
## nudged by its AnimalFitness.fitness_score (see FITNESS_CHANCE_SWING).
## `forager_seed` is the bird's own per-individual identity seed (see
## AmbientFlyerMarker.wander_seed) -- fixed for that bird's whole life, unlike
## the per-pick `carrier_seed` seed_is_consumed itself rolls against.
static func consumption_chance_for(forager_seed: int) -> float:
	var fitness_score: float = _fitness.fitness_score(_fitness.phenotype_for(forager_seed))
	return GRANIVORY_CONSUMED_CHANCE + (fitness_score - 0.5) * FITNESS_CHANCE_SWING


## Whether THIS particular swallowed ground seed is destroyed rather than
## surviving to be planted (see consumption_chance_for). PixelNoise-seeded
## off the carrier -- never Godot's string hash(), which has repeatedly
## clustered this project's seeded-index rolls onto a single bucket (see
## PixelNoise's own doc comment) -- sampled at a coordinate distinct from
## carry_distance_tiles's so the two rolls vary independently for the same
## carrier.
##
## `forager_seed` (the eating bird's own identity seed, defaulting to
## `carrier_seed` for callers that don't distinguish the two) decides WHOSE
## fitness nudges the chance; `carrier_seed` decides the actual roll -- kept
## separate so the same bird rolls independently for each seed it eats while
## still using its own fixed fitness every time.
static func seed_is_consumed(carrier_seed: int, forager_seed: int = carrier_seed) -> bool:
	return PixelNoise.unit(carrier_seed, 0, 1) < consumption_chance_for(forager_seed)
