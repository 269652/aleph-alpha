extends GutTest

const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")


## A tree of an illustrated species, which is what the branch-by-branch growth
## applies to. TreeSpecies keys off a bias FLOAT rather than an id, so a test
## that wants a particular species has to search for a bias that lands on it.
func _tree() -> ChoppableTree:
	var grown := ChoppableTree.new()
	for step in 201:
		var bias := float(step) / 200.0
		if TreeSpecies.species_for_bias(bias) == "cherry":
			grown.species_bias = bias
			break
	add_child_autofree(grown)
	# The canopy sprite is TreeRenderer's in the real world; a test that wants
	# to see what was drawn has to supply one.
	var canopy := Sprite2D.new()
	grown.add_child(canopy)
	grown.bind_canopy(canopy)
	return grown

var tree: ChoppableTree


func before_each():
	tree = ChoppableTree.new()
	tree.position = Vector2(50, 50)
	add_child(tree)


func after_each():
	if is_instance_valid(tree):
		remove_child(tree)
		tree.free()


func test_is_added_to_the_tree_group():
	assert_true(tree.is_in_group(ChoppableTree.GROUP_NAME))


func test_take_damage_reduces_health():
	var before := tree.health
	tree.take_damage(5.0)
	assert_eq(tree.health, before - 5.0)


## Felling is now the FIRST half of the job: the tree goes over and lies there,
## still holding its wood. Working it up is what drops anything.
##
## Both of these asserted the old behaviour -- that a killing blow sprayed
## items and deleted the node -- which is the tree evaporating rather than
## being cut down (reported). The drop itself is tested in
## test_felled_tree.gd, against the fallen trunk that now produces it.
func test_felling_does_not_drop_anything_yet():
	watch_signals(WorldItemBus)
	tree.take_damage(tree.health)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)


func test_felling_leaves_the_trunk_lying_there():
	tree.take_damage(tree.health)
	assert_false(tree.is_queued_for_deletion(), "a felled tree should still be there")
	assert_true(tree.is_felled())


func test_a_non_lethal_hit_does_not_drop_wood_or_free_the_tree():
	watch_signals(WorldItemBus)
	tree.take_damage(1.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)
	assert_false(tree.is_queued_for_deletion())


# -- hover tooltip: name + available actions ---------------------------------

func test_a_standing_trees_display_name_and_action():
	assert_eq(tree.get_display_name(), "Tree")
	var actions: Array = tree.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["verb"], "Chop")
	assert_eq(actions[0]["action"], "attack")


## A felled trunk is still choppable (see _cut_up), so its hover name should
## say so rather than keep calling it a standing tree.
func test_a_felled_trees_display_name_changes():
	tree.take_damage(tree.health)
	assert_eq(tree.get_display_name(), "Fallen Tree")


# -- a sapling has to actually grow ------------------------------------------

## A planted sapling grew only when its chunk was unloaded and reloaded.
##
## `growth_scale` was set once, at spawn, from the tree's age at that moment,
## and nothing ever touched it again -- so a sapling you watched stayed a
## seedling forever, and the only way to see a tree mature was to walk away and
## come back. Reported as newborn trees not maturing properly.
func test_a_sapling_grows_as_it_ages():
	var tree := ChoppableTree.new()
	add_child_autofree(tree)
	tree.planted_at = 0.0
	tree.set_age(0.0)
	var seedling := tree.growth_scale
	tree.set_age(TreeGrowth.MATURITY_SECONDS)
	assert_gt(tree.growth_scale, seedling, "the sapling never grew")


func test_a_grown_tree_stops_growing():
	var tree := ChoppableTree.new()
	add_child_autofree(tree)
	tree.set_age(TreeGrowth.MATURITY_SECONDS)
	var grown := tree.growth_scale
	tree.set_age(TreeGrowth.MATURITY_SECONDS * 10.0)
	assert_almost_eq(tree.growth_scale, grown, 0.001)


## Growth is monotonic -- a tree never shrinks.
func test_a_tree_never_shrinks():
	var tree := ChoppableTree.new()
	add_child_autofree(tree)
	var previous := 0.0
	for step in 20:
		tree.set_age(float(step) / 19.0 * TreeGrowth.MATURITY_SECONDS)
		assert_gte(tree.growth_scale, previous)
		previous = tree.growth_scale


# -- a growing tree redraws its branches -------------------------------------

## A young tree has FEWER BRANCHES, not a smaller picture. The node scale alone
## drew a sapling as a full-grown tree in miniature -- every bough and twig, just
## small -- which is what looked wrong. Growth now reaches the CANOPY as well, so
## the crown fills in branch by branch as the tree ages.
func test_ageing_a_tree_redraws_its_canopy():
	var tree := _tree()
	tree.set_age(0.0)
	tree.set_ripe_fruit(0, "summer")
	var sapling: Texture2D = tree._canopy_sprite.texture
	tree.set_age(TreeGrowth.MATURITY_SECONDS * 2.0)
	assert_ne(
		tree._canopy_sprite.texture.get_image().get_data(),
		sapling.get_image().get_data(),
		"a grown tree should not carry a sapling's canopy"
	)


## Growing must not be mistaken for "nothing changed" by the redraw guard --
## the guard compares crop and season, and age is neither.
func test_growing_beats_the_redraw_guard():
	var tree := _tree()
	tree.set_ripe_fruit(0, "summer")
	tree.set_age(0.0)
	var sapling: Texture2D = tree._canopy_sprite.texture
	tree.set_age(TreeGrowth.MATURITY_SECONDS * 2.0)
	tree.set_ripe_fruit(0, "summer")
	assert_ne(
		tree._canopy_sprite.texture.get_image().get_data(),
		sapling.get_image().get_data()
	)


## The node still shrinks -- a young tree really is shorter, and the trunk has
## to come up with it. Fewer branches is IN ADDITION to that, not instead.
func test_a_sapling_is_still_a_smaller_node():
	var tree := _tree()
	tree.set_age(0.0)
	assert_lt(tree.scale.x, 1.0)
	tree.set_age(TreeGrowth.MATURITY_SECONDS * 2.0)
	assert_almost_eq(tree.scale.x, 1.0, 0.01)


# -- pollination visits (see docs/concept/flora.md / FruitingModel.pollination_factor) --
#
# A bee's visit has to survive somewhere: crop_potential is a pure function of
## the genome and time, with no persisted per-tree state anywhere -- so
## "visits accumulate and boost yield" needs a real place to live, and this is
## the same tier ChoppableTree's other per-tree state (growth, ripe count)
## already lives at. Deliberately scoped to survive only while the chunk is
## loaded (see the module doc comment on ChoppableTree) -- not persisted
## across a save/reload in this pass.

const BEARING_CYCLE_SECONDS := 100.0  # a stand-in cycle length, not the real year


func test_a_visit_is_recorded():
	var t := ChoppableTree.new()
	add_child_autofree(t)
	assert_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, 0.0), 0.0)
	t.record_pollination_visit(BEARING_CYCLE_SECONDS, 0.0)
	assert_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, 0.0), 1.0)


func test_visits_accumulate_within_the_same_cycle():
	var t := ChoppableTree.new()
	add_child_autofree(t)
	for i in 5:
		t.record_pollination_visit(BEARING_CYCLE_SECONDS, float(i))
	assert_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, 5.0), 5.0)


## The whole reason this is windowed to ONE cycle: a bee visit last year must
## not go on boosting this year's crop forever, or "pollination feedback"
## degenerates into a one-time permanent buff.
func test_visits_reset_once_a_new_bearing_cycle_begins():
	var t := ChoppableTree.new()
	add_child_autofree(t)
	t.record_pollination_visit(BEARING_CYCLE_SECONDS, 10.0)  # cycle 0
	assert_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, 10.0), 1.0)
	# Now well into the NEXT cycle, with no visit yet this time round.
	assert_eq(
		t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, BEARING_CYCLE_SECONDS + 10.0), 0.0,
		"last cycle's visit should not still be boosting this cycle"
	)


func test_a_visit_in_the_new_cycle_starts_a_fresh_count():
	var t := ChoppableTree.new()
	add_child_autofree(t)
	t.record_pollination_visit(BEARING_CYCLE_SECONDS, 10.0)  # cycle 0
	t.record_pollination_visit(BEARING_CYCLE_SECONDS, BEARING_CYCLE_SECONDS + 5.0)  # cycle 1
	assert_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, BEARING_CYCLE_SECONDS + 5.0), 1.0)


func test_a_freshly_built_tree_has_no_visits_yet():
	var t := ChoppableTree.new()
	add_child_autofree(t)
	assert_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, 12345.0), 0.0)


## A fitter bee's visit should bank more than a flat 1 (see
## FruitingModel.visit_weight_for_fitness) -- record_pollination_visit takes
## an optional weight, defaulting to 1.0 so every call above this line is
## unaffected.
func test_a_visit_can_be_weighted_above_the_default():
	var t := ChoppableTree.new()
	add_child_autofree(t)
	t.record_pollination_visit(BEARING_CYCLE_SECONDS, 0.0, 1.15)
	assert_almost_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, 0.0), 1.15, 0.001)


func test_weighted_visits_accumulate_within_the_same_cycle():
	var t := ChoppableTree.new()
	add_child_autofree(t)
	t.record_pollination_visit(BEARING_CYCLE_SECONDS, 0.0, 0.85)
	t.record_pollination_visit(BEARING_CYCLE_SECONDS, 1.0, 1.15)
	assert_almost_eq(t.pollination_visits_in_cycle(BEARING_CYCLE_SECONDS, 1.0), 2.0, 0.001)
