extends RefCounted

## Deterministic, per-tile cave-mouth placement (see
## docs/concept/geology.md "Cave entrances"). Same coordinate-hash idiom as
## StonePlacement/OrePlacement, weighted per biome rather than gated to a
## fixed biome list -- real cave/adit mouths overwhelmingly occur where
## exposed rock already breaks the surface, so `mountain` gets by far the
## largest weight, other biomes a small non-zero chance (an outcrop can
## occur almost anywhere), and `ocean` none at all (nothing to dig into).

## Relative likelihood per biome that a cave entrance forms there, before
## the shared base density below. Mountain dominates -- real caves/adits
## overwhelmingly break the surface where rock is already exposed -- but a
## small chance elsewhere keeps the world from reading as "caves only ever
## happen in the mountains."
const BIOME_WEIGHTS := {
	"mountain": 1.0,
	"tundra": 0.25,
	"desert": 0.15,
	"grassland": 0.08,
	"forest": 0.08,
	"rainforest": 0.05,
}

## Base density (before biome weighting) an entrance rolls at in a
## weight-1.0 biome. Kept far sparser than StonePlacement.STONE_DENSITY --
## a cave mouth is a landmark, not ground cover, more like a boulder's
## own "scattered landmark" rarity than loose stone's.
const BASE_ENTRANCE_DENSITY := 0.002


## Whether a cave entrance sits at this global tile, given its biome.
func has_entrance_at(global_x: int, global_y: int, biome_name: String) -> bool:
	var weight: float = BIOME_WEIGHTS.get(biome_name, 0.0)
	if weight <= 0.0:
		return false
	var density := BASE_ENTRANCE_DENSITY * weight
	var value := float(absi(hash("%d_%d_cave_entrance" % [global_x, global_y])) % 10000) / 10000.0
	return value < density


## Deterministic per-tile seed for this entrance's sprite/marker variation.
func seed_at(global_x: int, global_y: int) -> int:
	return hash("%d_%d_cave_entrance_seed" % [global_x, global_y])
