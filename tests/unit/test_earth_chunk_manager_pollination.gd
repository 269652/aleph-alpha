extends GutTest

## EarthChunkManager's pollination-gated fruiting and reproduction (see
## docs/concept/flora.md's "Pollination feedback" and "Where a forest comes
## from"). Mirrors test_earth_chunk_manager_bees.gd's own dedicated-file
## shape -- direct `_loaded_trees` injection, never the slow real `update()`
## (see CONTRIBUTING.md / test_earth_chunk_manager.gd's own known-slow-file
## note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Same brute-force-a-real-instance idiom as test_earth_chunk_manager.gd's
## own `_position_for_species` -- position-keyed, since a tree's genome (and
## therefore its species) is always derived from its own position, never
## stored per-tree.
func _position_for_species(species_id: String) -> Vector2:
	var scheduler := ForageScheduler.new()
	for step in 4000:
		var position := Vector2(step * 37, step * 53)
		var genome := scheduler.genome_for(position)
		if TreeSpecies.species_for_bias(genome.species_bias) != species_id:
			continue
		if FruitingModel.new().crop_potential(genome) <= 0:
			continue
		return position
	fail_test("no position in range resolved to %s with a nonzero crop" % species_id)
	return Vector2.ZERO


## A real ChoppableTree (not a bare Node2D) -- this file's own tests need
## the real record_pollination_visit/pollination_visits_in_cycle methods,
## unlike test_earth_chunk_manager.gd's own bare-Node2D harvest_peak_fruit_
## near fixtures, which predate this feature and never touch pollination.
##
## Sets the node's own species_bias from the SAME position-derived genome
## _position_for_species already used to choose this position -- a fresh
## ChoppableTree defaults species_bias to 0.5 (walnut), and functions that
## read the node's species directly (blossoms_near,
## _pollination_eligible_tree_positions) would otherwise silently disagree
## with the species this position was actually chosen for.
##
## APPENDS to Vector2i(0, 0)'s own bucket rather than replacing it, so
## several calls in the same test (see the mixed-list tests below) each add
## a real, independently-findable tree instead of the later call silently
## overwriting the earlier one.
func _tree_at(position: Vector2) -> ChoppableTree:
	var tree := ChoppableTree.new()
	tree.position = position
	tree.species_bias = ForageScheduler.new().genome_for(position).species_bias
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	var bucket: Array = manager._loaded_trees.get(Vector2i(0, 0), [])
	bucket.append(tree)
	manager._loaded_trees[Vector2i(0, 0)] = bucket
	return tree


## Sets world_age_seconds to genuine mid-plateau peak ripeness for the real
## tree at `position` -- mirrors test_earth_chunk_manager.gd's own
## test_harvest_peak_fruit_near_reports_the_real_peak_state setup exactly,
## since window boundaries don't depend on yield_multiplier/pollination_
## factor (see that test's own comment).
func _set_world_age_to_peak_for(position: Vector2) -> void:
	var scheduler := ForageScheduler.new()
	var genome := scheduler.genome_for(position)
	var model := FruitingModel.new()
	var warmth: float = manager._warmth_at_pixel(position)
	var window: Dictionary = model._window_for(genome, warmth)
	manager.set_world_age_seconds(
		(float(window.grow_end) + float(window.fall_start)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	)


# -- harvest_peak_fruit_near composes pollination_factor, same as step_fruiting -
#
# harvest_peak_fruit_near computed its own yield_multiplier without ever
# composing pollination_factor into it at all -- an inconsistency with
# step_fruiting, which already did. An unpollinated apple's canopy correctly
# showed no fruit, yet a player (or an NPC gather instruction, see
# NpcInstructionEffects, which reads this exact function) could still walk
# up and harvest one anyway.

func test_an_unpollinated_insect_pollinated_tree_has_nothing_to_harvest_even_at_peak():
	var position := _position_for_species("apple")
	_tree_at(position)  # never record_pollination_visit -- zero visits this cycle
	_set_world_age_to_peak_for(position)

	assert_true(
		manager.harvest_peak_fruit_near(position, 10.0).is_empty(),
		"an apple with zero real pollinator visits should have nothing to harvest"
	)


func test_a_pollinated_insect_pollinated_tree_can_still_be_harvested_at_peak():
	var position := _position_for_species("apple")
	var tree := _tree_at(position)
	tree.record_pollination_visit(
		FruitingModel.BEARING_CYCLE_SECONDS, 0.0, FruitingModel.POLLINATION_SATURATION_VISITS
	)
	_set_world_age_to_peak_for(position)

	var found := manager.harvest_peak_fruit_near(position, 10.0)
	assert_eq(found.get("species_id", ""), "apple")


## Wind-pollinated species (real catkins/cones) need no insect at all -- the
## fix must not gate a species TreeSpecies.needs_pollinators_for already
## says is exempt.
func test_a_wind_pollinated_tree_can_be_harvested_with_zero_pollinator_visits():
	var position := _position_for_species("walnut")
	_tree_at(position)  # never visited, and never needs to be
	_set_world_age_to_peak_for(position)

	var found := manager.harvest_peak_fruit_near(position, 10.0)
	assert_eq(found.get("species_id", ""), "walnut")


# -- blossoms_near attaches a real scent_strength (see docs/concept/flora.md
# -- #tree-blossoms-emit-real-scent-too) -------------------------------------
#
# Without this, a blossom entry fed into ScentField.concentration_at falls
# back to FlowerSpecies' own _FALLBACK profile (an unrelated 0.4, chosen for
# an unrecognized FLOWER id, not a real, deliberate blossom value) -- an
# accident this makes into a real, tested, species-specific number instead.

func test_a_blossoming_tree_carries_its_real_species_scent_strength():
	var position := _position_for_species("apple")
	_tree_at(position)
	manager.set_world_age_seconds(0.1 * SeasonCycle.SECONDS_PER_YEAR)  # spring
	assert_eq(manager.current_season(), "spring", "precondition: blossoms_near is spring-only")

	var blossoms := manager.blossoms_near(position, 10)
	assert_eq(blossoms.size(), 1, "precondition: the tree should be found in blossom")
	assert_almost_eq(
		float(blossoms[0]["scent_strength"]), TreeSpecies.blossom_scent_for("apple"), 0.001
	)


# -- _pollination_eligible_tree_positions gates TreeSpread's own dominant ----
# -- reproduction path (see docs/concept/flora.md#where-a-forest-comes-from) -
#
# TreeSpread.propose_saplings/TreeMaturity.mature_positions carry no species
# or pollination awareness at all -- bare Vector2 positions, by design (see
# tree_maturity.gd's own doc comment) -- so step_tree_spread filters the
# candidate seed-source list through this before ever calling
# propose_saplings, rather than changing either of those two pure, already-
# tested signatures.

func test_an_unpollinated_insect_pollinated_tree_is_not_a_seed_source():
	var position := _position_for_species("apple")
	_tree_at(position)  # never visited

	var eligible := manager._pollination_eligible_tree_positions([position])
	assert_eq(eligible, [], "an unvisited apple should not seed new trees")


func test_a_pollinated_insect_pollinated_tree_is_still_a_seed_source():
	var position := _position_for_species("apple")
	var tree := _tree_at(position)
	tree.record_pollination_visit(FruitingModel.BEARING_CYCLE_SECONDS, 0.0, 1.0)  # any real visit at all

	var eligible := manager._pollination_eligible_tree_positions([position])
	assert_eq(eligible, [position])


func test_a_wind_pollinated_tree_is_a_seed_source_with_zero_visits():
	var position := _position_for_species("walnut")
	_tree_at(position)  # never visited, and never needs to be

	var eligible := manager._pollination_eligible_tree_positions([position])
	assert_eq(eligible, [position], "a wind-pollinated tree needs no insect to spread")


## A position with no resolvable tree node fails OPEN (spreads) rather than
## being silently dropped for a data gap this filter has no way to judge --
## see this function's own doc comment.
func test_a_position_with_no_loaded_tree_fails_open():
	var eligible := manager._pollination_eligible_tree_positions([Vector2(12345, 67890)])
	assert_eq(eligible, [Vector2(12345, 67890)])


## A mixed list only drops the specific ineligible position, keeping every
## other candidate (of either kind) intact -- not an all-or-nothing gate.
func test_a_mixed_list_only_drops_the_ineligible_position():
	var unpollinated_apple := _position_for_species("apple")
	_tree_at(unpollinated_apple)
	var walnut := _position_for_species("walnut")
	_tree_at(walnut)

	var eligible := manager._pollination_eligible_tree_positions([unpollinated_apple, walnut])
	assert_eq(eligible, [walnut])
