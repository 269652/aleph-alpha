extends GutTest

## Direct-from-the-tree fruit harvest (docs/concept/progression.md
## "Ecological literacy"): pressing pickup (E) near a tree that still carries
## real hanging fruit (EarthChunkManager.harvest_peak_fruit_near) takes one
## into inventory and awards real XP -- more when the harvest lands at
## genuine peak ripeness (FruitingModel.is_peak_ripe) than off-peak. Mirrors
## test_player_held_item.gd's real-scene setup and
## test_earth_chunk_manager.gd's `_loaded_trees` injection convention. Only
## reachable when the ordinary ground-item sweep (pickup_nearby) finds
## nothing -- a fallen windfall item, by construction, can never itself be
## "at peak" (see fruiting_model.gd's is_peak_ripe doc comment), so this is
## the only path that can.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const EcologicalLiteracy = preload("res://src/gameplay/ecological_literacy.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player


func before_each():
	if not InputMap.has_action("pickup"):
		InputMap.add_action("pickup")

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.setup(chunk_manager, TILE_SIZE)


func after_each():
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	Input.action_release("pickup")


## Same brute-force-a-real-position idiom test_earth_chunk_manager.gd's own
## _position_for_species uses: an integer pixel position whose deterministic,
## position-keyed genome (ForageScheduler.genome_for) resolves to
## `species_id` with a real nonzero crop.
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
	return Vector2.ZERO


## Places a real tree exactly at player.position (well within PICKUP_RADIUS)
## and sets the world age to `elapsed_seconds`, returning the species' real
## FruitingModel window ({grow_end, fall_start, fall_end}, as year fractions)
## for the caller to compute peak/off-peak moments from.
func _place_tree_and_get_window(species_id: String) -> Dictionary:
	var tree := Node2D.new()
	tree.position = _position_for_species(species_id)
	entities_parent.add_child(tree)
	chunk_manager._loaded_trees[Vector2i(0, 0)] = [tree]
	player.position = tree.position

	var genome := ForageScheduler.new().genome_for(tree.position)
	var warmth: float = chunk_manager._warmth_at_pixel(tree.position)
	return FruitingModel.new()._window_for(genome, warmth)


func _tap_pickup() -> void:
	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)


func test_no_tree_nearby_pickup_grants_nothing():
	var before := player.experience.total_xp
	_tap_pickup()
	assert_eq(player.experience.total_xp, before)


func test_harvesting_hanging_fruit_adds_it_to_inventory_and_grants_xp():
	var species_id := "apple"
	var window := _place_tree_and_get_window(species_id)
	# Comfortably inside the plateau (a real "there is fruit to pick" moment).
	chunk_manager.set_world_age_seconds(
		(float(window.grow_end) + float(window.fall_start)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	)
	var before_count := player.inventory.count_of(species_id)
	var before_xp := player.experience.total_xp

	_tap_pickup()

	assert_eq(player.inventory.count_of(species_id), before_count + 1)
	assert_gt(player.experience.total_xp, before_xp, "expected real XP for a real harvest")


## The real, tested claim this feature exists for: a genuine peak-timed
## harvest of a tree awards MORE XP than an off-peak (but still hanging)
## harvest of the exact same tree/species.
func test_peak_timed_harvest_awards_more_xp_than_off_peak_harvest():
	var species_id := "apple"

	var window := _place_tree_and_get_window(species_id)
	chunk_manager.set_world_age_seconds(
		(float(window.grow_end) + float(window.fall_start)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	)
	var xp_before_peak := player.experience.total_xp
	_tap_pickup()
	var peak_xp_gained := player.experience.total_xp - xp_before_peak
	assert_eq(peak_xp_gained, EcologicalLiteracy.HARVEST_XP_BASE + EcologicalLiteracy.HARVEST_XP_PEAK_BONUS)

	# Same tree, moved to mid-abscission: still real hanging fruit (>0), but
	# no longer at peak.
	window = _place_tree_and_get_window(species_id)
	chunk_manager.set_world_age_seconds(
		(float(window.fall_start) + float(window.fall_end)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	)
	var xp_before_off_peak := player.experience.total_xp
	_tap_pickup()
	var off_peak_xp_gained := player.experience.total_xp - xp_before_off_peak
	assert_eq(off_peak_xp_gained, EcologicalLiteracy.HARVEST_XP_BASE)

	assert_gt(peak_xp_gained, off_peak_xp_gained, "a peak-timed harvest should earn more than an off-peak one")


func test_a_tree_with_nothing_ripe_yet_grants_no_harvest():
	var species_id := "apple"
	var window := _place_tree_and_get_window(species_id)
	chunk_manager.set_world_age_seconds(0.0)  # still growing, nothing hanging yet
	var before_count := player.inventory.count_of(species_id)

	_tap_pickup()

	assert_eq(player.inventory.count_of(species_id), before_count)
