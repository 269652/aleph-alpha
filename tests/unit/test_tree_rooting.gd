extends GutTest

## Where a tree can take root (see docs/concept/flora.md#where-a-forest-comes-
## from).
##
## Seeds only started travelling far enough to matter once the spread-radius
## unit bug was fixed -- before that every seed landed on its parent's own
## tile, which was necessarily land, so nothing ever checked. The first thing
## the fix produced was trees standing in a lake.

const TreeRooting = preload("res://src/world/tree_rooting.gd")
const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")


func test_a_tree_cannot_root_in_water():
	assert_false(TreeRooting.can_root_in("ocean"), "trees should not grow in water")


func test_a_tree_roots_where_woods_actually_grow():
	for biome in ["grassland", "forest", "rainforest"]:
		assert_true(TreeRooting.can_root_in(biome), biome)


## Above the tree line and out on the sand, ground cover is not a wood. These
## biomes sustain sparse vegetation -- they are not zero -- but a tree needs
## more than sparse.
func test_a_tree_does_not_root_above_the_tree_line_or_on_sand():
	for biome in ["mountain", "tundra", "desert"]:
		assert_false(TreeRooting.can_root_in(biome), biome)


## An unknown biome fails SAFE -- no tree -- matching the convention the
## vegetation model already uses for the same question.
func test_an_unknown_biome_grows_nothing():
	assert_false(TreeRooting.can_root_in("nonesuch"))
	assert_false(TreeRooting.can_root_in(""))


## The threshold is derived from the vegetation model's own table rather than
## being a second, parallel list of biome names that could drift out of step
## with it: it sits between the sparse biomes and the ones that carry woods.
func test_the_threshold_sits_between_sparse_cover_and_real_woods():
	var model := VegetationGrowthModel.new()
	var sparsest_wood := 999.0
	var richest_bare := 0.0
	for biome in ["grassland", "forest", "rainforest"]:
		sparsest_wood = minf(sparsest_wood, model.carrying_capacity_for_biome(biome))
	for biome in ["ocean", "mountain", "tundra", "desert"]:
		richest_bare = maxf(richest_bare, model.carrying_capacity_for_biome(biome))
	assert_gt(TreeRooting.MIN_CAPACITY_FOR_TREES, richest_bare)
	assert_lte(TreeRooting.MIN_CAPACITY_FOR_TREES, sparsest_wood)
