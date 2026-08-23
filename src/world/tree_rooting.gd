extends RefCounted

## Where a tree can take root (see docs/concept/flora.md#where-a-forest-comes-
## from).
##
## Seeds only started travelling far enough for this to matter once the
## spread-radius unit bug was fixed: before that every seed landed on its
## parent's own tile, which was necessarily land, so nothing ever had to check.
## The first thing the fix produced was trees standing in a lake.

const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")

## How much vegetation a biome must be able to carry before it can carry a
## TREE.
##
## Derived from the vegetation model's own table rather than kept as a second
## list of biome names that could drift out of step with it. That table already
## answers "what grows here" -- ocean 0.0, mountain 0.12, desert 0.15, tundra
## 0.2, grassland 0.6, forest 0.85, rainforest 1.0 -- and a tree simply needs
## more than the sparse ground cover of the top three.
##
## Sitting between tundra's 0.2 and grassland's 0.6 puts the line where a real
## tree line is: woods in grassland, forest and rainforest; none in water, on
## bare rock, on sand, or above the tree line.
const MIN_CAPACITY_FOR_TREES := 0.3

static var _model := VegetationGrowthModel.new()


## Whether a tree can root in this biome. An unknown biome fails safe -- no
## tree -- which is the same convention the vegetation model uses for the same
## question.
static func can_root_in(biome_name: String) -> bool:
	return _model.carrying_capacity_for_biome(biome_name) >= MIN_CAPACITY_FOR_TREES
