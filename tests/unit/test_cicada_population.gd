extends GutTest

## Pure logic deciding which of a chunk's real trees host a calling cicada
## (see docs/concept/creature_and_footstep_audio.md's "Cicadas" section).
## Reported live: "you can hear cicadas in the environment which don't
## exist... add them please as real ecosystem member." No growth/
## starvation/persistence economy the way ant/bee colonies get -- a real
## adult cicada's whole calling window is short (a few summer weeks) and
## this game's own chunk load/unload cycle is frequent enough that a fresh
## roll per load is an honest simplification of that same short-windowed
## presence, not a missing feature.

const CicadaPopulation = preload("res://src/world/cicada_population.gd")


func test_active_only_in_summer():
	assert_true(CicadaPopulation.is_active_in("summer"))
	for season in ["spring", "autumn", "winter"]:
		assert_false(CicadaPopulation.is_active_in(season), season)


## Outside summer, no tree hosts a cicada regardless of how favorable the
## rolls are -- the season gate is checked before any roll is spent.
func test_no_trees_qualify_outside_summer_even_with_guaranteed_rolls():
	var rolls: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	assert_eq(CicadaPopulation.cicada_tree_indices(5, "spring", rolls), [])


## A guaranteed-hit roll (0.0) for every tree, in summer, must qualify
## every single tree -- proves the density check is a real, working
## threshold compare, not silently always-false.
func test_every_tree_qualifies_in_summer_with_guaranteed_rolls():
	var rolls: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	assert_eq(CicadaPopulation.cicada_tree_indices(5, "summer", rolls), [0, 1, 2, 3, 4])


## A guaranteed-miss roll (1.0) for every tree, in summer, must qualify
## none -- the opposite edge, so the threshold compare isn't silently
## always-true either.
func test_no_trees_qualify_in_summer_with_guaranteed_miss_rolls():
	var rolls: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
	assert_eq(CicadaPopulation.cicada_tree_indices(5, "summer", rolls), [])


## Only trees whose OWN roll clears the threshold qualify -- proves this is
## a genuine per-tree decision, not "any qualifying roll anywhere makes
## every tree qualify" or vice versa.
func test_only_the_trees_whose_own_roll_clears_the_threshold_qualify():
	var rolls: Array[float] = [0.0, 0.99, 0.0, 0.99]
	assert_eq(CicadaPopulation.cicada_tree_indices(4, "summer", rolls), [0, 2])


## Deliberately sparse -- a chorus of dozens of trees calling at once would
## be a wall of noise, not the real "your ear picks out an individual
## cicada or two nearby" experience. A real, named, tested constant, not an
## eyeballed inline number (see CLAUDE.md).
func test_tree_density_is_a_real_sparse_fraction_not_eyeballed():
	assert_true(CicadaPopulation.TREE_DENSITY > 0.0)
	assert_true(CicadaPopulation.TREE_DENSITY < 0.5)
