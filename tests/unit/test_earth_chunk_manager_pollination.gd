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
func _tree_at(position: Vector2) -> ChoppableTree:
	var tree := ChoppableTree.new()
	tree.position = position
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
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
