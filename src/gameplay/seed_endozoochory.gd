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
