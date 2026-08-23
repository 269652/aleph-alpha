extends GutTest

## Where a fruit lands when it falls (see docs/concept/flora.md#where-a-forest-
## comes-from).
##
## A fruit that always lands on the trunk is a fruit that can never found a
## tree, because the trunk's tile is already taken.

const FruitFall = preload("res://src/world/fruit_fall.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


# -- the three-by-three block ------------------------------------------------

## Fruit falls across the parent's own tile and the eight around it -- the
## block a real canopy overhangs.
func test_fruit_lands_within_the_canopy_block():
	for seed_value in 400:
		var offset := FruitFall.fall_offset(seed_value)
		assert_lte(
			absf(offset.x), FruitFall.SPREAD_TILES * TerrainRenderer.TILE_SIZE + 0.001
		)
		assert_lte(
			absf(offset.y), FruitFall.SPREAD_TILES * TerrainRenderer.TILE_SIZE + 0.001
		)


## Every one of the nine tiles actually receives fruit. A distribution that
## misses the corners is not the block it claims to be.
func test_every_tile_in_the_block_gets_fruit():
	var tiles := {}
	for seed_value in 900:
		tiles[_tile_of(FruitFall.fall_offset(seed_value))] = true
	assert_eq(tiles.size(), 9, "expected all nine tiles, got %d" % tiles.size())


## ...and roughly evenly. "Uniformly", as asked: no tile may take more than
## twice its fair share, or the wood still creeps in one direction.
func test_fruit_falls_roughly_evenly_across_the_block():
	var counts := {}
	var total := 1800
	for seed_value in total:
		var tile: Vector2i = _tile_of(FruitFall.fall_offset(seed_value))
		counts[tile] = int(counts.get(tile, 0)) + 1
	var fair := float(total) / 9.0
	for tile in counts:
		assert_between(
			float(counts[tile]), fair * 0.5, fair * 2.0,
			"tile %s took %d of %d, fair share is %.0f" % [tile, counts[tile], total, fair]
		)


## The parent's own tile is included -- fruit does drop straight down, it just
## must not ONLY drop straight down.
func test_the_parents_own_tile_still_gets_fruit():
	var own := 0
	for seed_value in 900:
		if _tile_of(FruitFall.fall_offset(seed_value)) == Vector2i.ZERO:
			own += 1
	assert_gt(own, 0, "fruit should still fall at the foot of its own tree")


## A given fruit falls where it falls: the same drop resolves the same way, so
## nothing depends on how many frames the player watched for.
func test_a_given_fruit_lands_in_one_place():
	for seed_value in [0, 7, 99, 4001]:
		assert_eq(FruitFall.fall_offset(seed_value), FruitFall.fall_offset(seed_value))


## Consecutive drops must not land in a line. Godot's string hash is near
## linear across inputs differing by a trailing number, which this project has
## been bitten by twice (terrain banding, then a whole crop landing on one
## pixel).
func test_consecutive_drops_do_not_land_in_a_line():
	var tiles := {}
	for seed_value in range(1000, 1040):
		tiles[_tile_of(FruitFall.fall_offset(seed_value))] = true
	assert_gt(tiles.size(), 3, "forty consecutive drops landed in %d tiles" % tiles.size())


func _tile_of(offset: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(offset.x / TerrainRenderer.TILE_SIZE + 0.5)),
		int(floor(offset.y / TerrainRenderer.TILE_SIZE + 0.5))
	)
