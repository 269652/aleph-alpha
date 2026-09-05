extends GutTest

## Player-facing farming loop wiring (docs/concept/farming.md's "farming
## loop"): the "plant" action tills+plants (or tends, if a live crop is
## already growing there) the tile the player faces, and harvesting reuses
## the SAME attack key every other harvest-shaped verb already does (see
## Player._pull_wild_crop_step/_harvest_grass_step/_collect_step, all fired
## from _perform_attack) -- a ready plot's yield lands in real inventory.
## Mirrors test_player_fruit_harvest.gd's real-scene setup.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const TileTargeting = preload("res://src/gameplay/tile_targeting.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player
var _tile_targeting := TileTargeting.new()
var _keybindings := Keybindings.new()


func before_each():
	# No static [input] section in project.godot -- World._apply_keybindings
	# registers the InputMap at runtime. This test instantiates Player
	# without a World, so it registers whatever is missing itself, the same
	# way test_player_fruit_harvest.gd/test_player_input_latch.gd already do.
	for action in ["plant", "attack"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			var default_event := InputEventKey.new()
			default_event.physical_keycode = _keybindings.default_keycode_for(action)
			InputMap.action_add_event(action, default_event)

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.setup(chunk_manager, TILE_SIZE)
	# Loads real chunks around the player -- covers the faced tile too
	# (one tile away, well within LOAD_RADIUS).
	chunk_manager.update(player.current_tile())


func after_each():
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	Input.action_release("plant")
	Input.action_release("attack")


func _target_tile() -> Vector2i:
	return _tile_targeting.facing_tile(player.current_tile(), player._last_facing_direction)


func _tap_plant() -> void:
	Input.action_press("plant")
	player._plant_step()
	Input.action_release("plant")
	player._plant_step()


func _tap_attack() -> void:
	Input.action_press("attack")
	player._attack_step(0.016)
	Input.action_release("attack")
	player._attack_step(0.016)


func test_plant_action_tills_and_plants_the_faced_tile():
	var target := _target_tile()

	_tap_plant()

	var marker = chunk_manager._farm_plots.get(target)
	assert_not_null(marker, "expected a farm plot at the faced tile")
	assert_eq(marker.plot.state, "growing")


func test_plant_action_on_an_already_growing_plot_tends_it_instead_of_replanting():
	var target := _target_tile()
	_tap_plant()
	var plot: FarmPlot = chunk_manager._farm_plots[target].plot
	chunk_manager.step_farm_plots(plot.growth_time * FarmPlot.WATER_GRACE_FRACTION - 0.1)

	_tap_plant()

	assert_eq(plot.time_since_watered, 0.0, "a second plant-key press should tend, not replant")
	assert_eq(plot.state, "growing")


func test_harvest_via_attack_adds_the_yield_to_inventory_and_clears_the_plot():
	var target := _target_tile()
	chunk_manager.till_and_plant_farm_plot_at_global(target.x, target.y, "carrot")
	var marker = chunk_manager._farm_plots[target]
	var step: float = marker.plot.growth_time / 10.0
	for i in 12:
		chunk_manager.water_farm_plot_at_global(target.x, target.y)
		chunk_manager.step_farm_plots(step)
	assert_eq(marker.plot.state, "ready", "precondition: plot must be ready before this proves anything")
	var before_count := player.inventory.count_of("carrot")

	_tap_attack()

	assert_gt(player.inventory.count_of("carrot"), before_count)
	assert_eq(marker.plot.state, "empty")


func test_harvest_via_attack_on_a_growing_plot_grants_nothing():
	var target := _target_tile()
	chunk_manager.till_and_plant_farm_plot_at_global(target.x, target.y, "carrot")
	var before_count := player.inventory.count_of("carrot")

	_tap_attack()

	assert_eq(player.inventory.count_of("carrot"), before_count)
