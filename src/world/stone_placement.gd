extends RefCounted

## Deterministic, per-tile stone/boulder placement on grassland and forest
## cells. Same coordinate-hash approach as TreePlacement (see that file for
## why a hash beats sampling noise at integer lattice points), but much
## sparser -- boulders are scattered landmarks, not ground cover. In forest,
## a cell that already carries a tree never also carries a stone.

const TreePlacement = preload("res://src/world/tree_placement.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

const STONE_BIOMES: Array[String] = ["grassland", "forest"]
## What the density was when every stone cell was a boulder. Kept so the
## change can be pinned rather than described: adding pebbles must not have
## made boulders rarer as a side effect (see
## test_adding_pebbles_did_not_make_boulders_rarer).
const BOULDERS_PER_TILE_BEFORE_PEBBLES := 0.012

## How much loose stone lies on the ground.
##
## Raised from 0.012 when pebbles arrived. Every stone cell used to be a
## boulder; now most roll small (see StoneSize), so at the old density
## boulders would have become two-thirds rarer purely as a side effect of
## adding small stone. This is set so a boulder still turns up about as often
## as it always did, and the pebbles are genuinely additional.
##
## The cost is real and worth stating: this is roughly three times as many
## stone nodes per chunk. They are cheap ones -- a liftable stone is a
## Sprite2D with no collision body and no script running per frame -- but it
## is not free.
const STONE_DENSITY := 0.04

var _tree_placement := TreePlacement.new()


## Whether a boulder sits at this global tile, given its biome.
func has_stone_at(global_x: int, global_y: int, biome_name: String) -> bool:
	if not STONE_BIOMES.has(biome_name):
		return false
	if _tree_placement.has_tree_at(global_x, global_y, biome_name):
		return false
	var value := float(absi(hash("%d_%d_stone" % [global_x, global_y])) % 10000) / 10000.0
	return value < STONE_DENSITY


## Local cell positions (within a `width` x `height` chunk biome grid at
## `chunk_origin_tiles`) that carry a stone. `biome` is the chunk's flat
## row-major biome-name array, same layout as Chunk.biome.
func stones_in_chunk(
	chunk_origin_tiles: Vector2i, biome: Array, width: int, height: int
) -> Array[Vector2i]:
	var stones: Array[Vector2i] = []
	for y in height:
		for x in width:
			var biome_name: String = biome[y * width + x]
			if has_stone_at(chunk_origin_tiles.x + x, chunk_origin_tiles.y + y, biome_name):
				stones.append(Vector2i(x, y))
	return stones


## Deterministic per-tile seed for this stone's sprite variation.
func seed_at(global_x: int, global_y: int) -> int:
	return hash("%d_%d_stone_seed" % [global_x, global_y])


# -- pebble flocks (see docs/concept/stone.md) -------------------------------
#
# Small stone is everywhere, and not every pebble should be a single lone
# rock: a pebble-class cell sometimes turns out to be a FLOCK of several
# pebbles clustered together instead of one. This decides WHETHER a cell
# flocks and HOW MANY members it has -- pure per-cell data, same as every
# other placement decision in this file; StoneRenderer decides how to draw
# and position what this returns.
#
# Cobbles and boulders never flock: a boulder is explicitly a scattered
# landmark (see the class doc comment above), and a cobble is already a
# large enough visual event on its own -- clustering several together at
# their bigger drawn size read as clutter rather than as scree, where the
# same clustering at pebble scale reads as a natural scatter of gravel.

## Chance that an eligible (pebble-class) cell becomes a FLOCK instead of one
## lone stone. Picked from the middle of the plausible range: low enough that
## a lone pebble is still the commoner sight (a flock is a moment, not the
## default), high enough that a flock is a genuinely regular occurrence
## rather than an easter egg. Pinned from both sides by
## test_flocks_are_common_but_not_universal.
const PEBBLE_FLOCK_CHANCE := 0.4

## How many pebbles a flock has, once it happens. The low end is still
## recognisably a pair rather than a lone stone; the high end is picked
## against EarthChunkManager's load volume (CHUNK_SIZE=32, LOAD_RADIUS=2,
## STONE_DENSITY=0.04 -- on the order of ~1000 loaded stone cells worst
## case) so a flock multiplies visible pebble nodes by a bounded, deliberate
## amount rather than an arbitrary big one.
const FLOCK_MIN_MEMBERS := 2
const FLOCK_MAX_MEMBERS := 5

## Offsets each flock member's own seed, the same reasoning as
## ProceduralFlowerSprite.BUSH_STEM_SEED_STRIDE: without this every member
## would share the base cell's seed and come out as the same pebble drawn
## several times. A large prime spreads member seeds well apart from each
## other and from the base seed's own derived values.
const FLOCK_MEMBER_SEED_STRIDE := 104729


## How many pebbles make up the stone at this cell -- 1 for a lone stone,
## FLOCK_MIN_MEMBERS..FLOCK_MAX_MEMBERS for a flock. Both rolls read the
## SAME per-cell seed seed_at already derives everything else about this
## stone from, on noise channels (10/1 and 11/1) distinct from diameter_for's
## own (3, 0) so the flock decision doesn't just track the diameter roll.
func flock_size_at(global_x: int, global_y: int) -> int:
	var base_seed := seed_at(global_x, global_y)
	var stone_class := StoneSize.class_for(StoneSize.diameter_for(base_seed))
	if stone_class != StoneSize.CLASS_PEBBLE:
		return 1
	if PixelNoise.unit(base_seed, 10, 1) >= PEBBLE_FLOCK_CHANCE:
		return 1
	return FLOCK_MIN_MEMBERS + PixelNoise.range_index(
		base_seed, 11, 1, FLOCK_MAX_MEMBERS - FLOCK_MIN_MEMBERS + 1
	)


## The seed for one member of a flock, offset from the cell's own base seed
## so members vary independently instead of being the same pebble repeated
## (see FLOCK_MEMBER_SEED_STRIDE).
func flock_member_seed(base_seed: int, member_index: int) -> int:
	return base_seed + member_index * FLOCK_MEMBER_SEED_STRIDE
