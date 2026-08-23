extends GutTest

const TreeSpread = preload("res://src/gameplay/tree_spread.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var spread := TreeSpread.new()


func test_no_saplings_from_an_empty_tree_list():
	var saplings := spread.propose_saplings([], [], 1, 5)
	assert_eq(saplings.size(), 0)


func test_proposes_up_to_count_saplings():
	var trees := [Vector2(0, 0), Vector2(200, 200), Vector2(400, 0)]
	var saplings := spread.propose_saplings(trees, [], 1, 3)
	assert_lte(saplings.size(), 3)


## `spread_radius` is in TILES (see TreeGenome), and this compared it against a
## distance in PIXELS -- so it passed while seeds were landing a couple of
## pixels from the trunk, and would have failed the moment they started
## reaching the neighbouring tiles they are supposed to reach.
func test_each_sapling_lands_within_its_parent_trees_spread_radius():
	var trees := [Vector2(500, 500)]
	var saplings := spread.propose_saplings(trees, [], 1, 10)
	var genome := TreeGenome.new(hash("%d_%d" % [500, 500]))
	var reach: float = genome.spread_radius * TerrainRenderer.TILE_SIZE
	for sapling in saplings:
		assert_lte(trees[0].distance_to(sapling.position), reach)


func test_saplings_keep_minimum_spacing_from_existing_trees():
	var trees := [Vector2(500, 500)]
	var existing := [Vector2(502, 500)]  # right on top of a likely sapling spot
	var saplings := spread.propose_saplings(trees, existing, 1, 20)
	for sapling in saplings:
		for existing_position in existing:
			assert_gte(sapling.position.distance_to(existing_position), TreeSpread.MIN_TREE_SPACING)


func test_a_saplings_genome_is_a_mutated_child_of_its_parents_genome():
	var trees := [Vector2(500, 500)]
	var saplings := spread.propose_saplings(trees, [], 1, 10)
	var parent_genome := TreeGenome.new(hash("%d_%d" % [500, 500]))
	assert_gt(saplings.size(), 0)
	for sapling in saplings:
		assert_ne(sapling.genome_seed, parent_genome.seed_value)


func test_is_deterministic_for_the_same_tick():
	var trees := [Vector2(500, 500), Vector2(700, 300)]
	var a := spread.propose_saplings(trees, [], 5, 6)
	var b := spread.propose_saplings(trees, [], 5, 6)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].position, b[i].position)
		assert_eq(a[i].genome_seed, b[i].genome_seed)


# -- seeds have to reach the neighbours --------------------------------------

## `spread_radius` is in TILES, and has always said so -- but the spread code
## added it straight to a position measured in PIXELS. Seeds landed two to
## eight PIXELS from the parent, a fraction of one tile, so every seed a wood
## produced landed on a tile that already had a tree in it. That is the whole
## reason woods did not spread.
##
## The minimum-spacing rule was then tuned BELOW that wrong number so it would
## not reject everything, which is what hid it.
func test_a_seed_lands_tiles_away_not_pixels_away():
	var spread := TreeSpread.new()
	var parent := Vector2(1000.0, 1000.0)
	var reached := 0.0
	for tick in 200:
		for sapling in spread.propose_saplings([parent], [], tick, 3):
			reached = maxf(reached, parent.distance_to(sapling.position))
	assert_gt(
		reached, TerrainRenderer.TILE_SIZE,
		"no seed cleared its parent's own tile -- the wood cannot spread"
	)


## ...and stays within its parent's actual reach, in tiles.
func test_a_seed_stays_within_its_parents_reach():
	var spread := TreeSpread.new()
	var parent := Vector2(1000.0, 1000.0)
	var limit := TreeGenome.MAX_SPREAD_RADIUS * TerrainRenderer.TILE_SIZE
	for tick in 200:
		for sapling in spread.propose_saplings([parent], [], tick, 3):
			assert_lte(parent.distance_to(sapling.position), limit + 0.001)


# -- a tile holds three trees at most ----------------------------------------

## Nothing stopped a stack before: the spacing rule was a pixel and a half on a
## sixteen-pixel tile, so a tile could carry a hundred trunks. Three is a
## thicket you can walk into; more is a wall of overlapping sprites.
func test_a_tile_never_takes_more_than_three_trees():
	var spread := TreeSpread.new()
	var parent := Vector2(1000.0, 1000.0)
	var planted: Array = [parent]
	for tick in 400:
		for sapling in spread.propose_saplings([parent], planted, tick, 3):
			planted.append(sapling.position)
	var per_tile := {}
	for position in planted:
		var tile := Vector2i(
			int(floor(position.x / TerrainRenderer.TILE_SIZE)),
			int(floor(position.y / TerrainRenderer.TILE_SIZE))
		)
		per_tile[tile] = int(per_tile.get(tile, 0)) + 1
	for tile in per_tile:
		assert_lte(
			int(per_tile[tile]), TreeSpread.MAX_TREES_PER_TILE,
			"tile %s carries %d trees" % [tile, per_tile[tile]]
		)


## ...but a tile can still hold more than one, or a wood is a grid.
func test_a_tile_can_still_hold_more_than_one_tree():
	assert_gt(TreeSpread.MAX_TREES_PER_TILE, 1)


# -- a wood is not unbounded -------------------------------------------------

## Spread plants a few saplings per TICK, and the caller decides how often a
## tick happens. Under fast-forward the caller was firing one every frame, so
## the rate became frames-per-second rather than anything to do with world
## time: measured, about twenty-one saplings a second and two thousand trees
## inside a minute, which is what took the frame rate to seven.
##
## The ceiling is what makes that impossible rather than merely unlikely.
func test_a_wood_stops_spreading_once_it_is_full():
	var spread := TreeSpread.new()
	var parent := Vector2(1000.0, 1000.0)
	var planted: Array = []
	for index in TreeSpread.MAX_TREES_IN_WORLD:
		planted.append(parent + Vector2(float(index) * 40.0, 0.0))
	var proposed := spread.propose_saplings([parent], planted, 1, 3)
	assert_eq(proposed.size(), 0, "a full wood should propose nothing")


func test_a_wood_with_room_still_spreads():
	var spread := TreeSpread.new()
	var parent := Vector2(1000.0, 1000.0)
	var proposed := spread.propose_saplings([parent], [parent], 1, 3)
	assert_gt(proposed.size(), 0, "an empty wood should still spread")


## The ceiling is a runaway backstop, not a carrying capacity, so it has to sit
## well clear of what a real forest loads.
##
## A loaded forest around Berlin carries about 3,500 trees (measured in
## test_earth_chunk_manager). A first attempt put this at 900, which stopped
## ordinary spread dead in exactly that forest -- the ceiling has to be far
## enough above normal that reaching it means something is actually wrong.
const MEASURED_LOADED_FOREST := 3545


func test_the_ceiling_sits_well_clear_of_a_real_forest():
	assert_gt(TreeSpread.MAX_TREES_IN_WORLD, MEASURED_LOADED_FOREST * 4)
