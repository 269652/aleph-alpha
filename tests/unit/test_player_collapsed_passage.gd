extends GutTest

## Real Player + a real thrown or kicked stone + a real CollapsedPassage
## obstacle in the world (docs/concept/exploration.md's "collapsed passage"
## momentum obstacle): momentum delivered by the SAME two sources this
## session already built -- HeldItemThrow/Throwable for a thrown stone,
## Kick for a kicked one -- is what clears, or fails to clear, the
## obstacle, routed through the exact same "find nearby target, resolve via
## ImpactResolver" delivery Player._resolve_thrown_stone_impact already
## uses for a thrown stone striking a creature (see
## Player._resolve_stone_impact_on_obstacles). Mirrors
## test_player_held_item.gd/test_player_kick.gd's real-scene setup.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const HeldItemThrow = preload("res://src/gameplay/held_item_throw.gd")
const CollapsedPassage = preload("res://src/rendering/collapsed_passage.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player


func before_each():
	if not InputMap.has_action("pickup"):
		InputMap.add_action("pickup")
	if not InputMap.has_action("kick"):
		InputMap.add_action("kick")

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	player.setup(chunk_manager, TILE_SIZE)


func after_each():
	# A thrown stone (see Player._spawn_thrown_stone) is added directly under
	# the player's own parent -- this test node -- so clean those up too.
	for node in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if is_instance_valid(node) and node.get_parent() == self:
			remove_child(node)
			node.free()
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	Input.action_release("pickup")
	Input.action_release("kick")


func _add_stone(diameter_cm: float, offset: Vector2) -> LiftableStone:
	var stone := LiftableStone.new()
	stone.diameter_cm = diameter_cm
	stone.position = player.position + offset
	entities_parent.add_child(stone)
	chunk_manager._loaded_stones[Vector2i(0, 0)] = [stone]
	return stone


func _add_obstacle(at_position: Vector2) -> CollapsedPassage:
	var obstacle := CollapsedPassage.new()
	obstacle.position = at_position
	add_child_autofree(obstacle)
	return obstacle


## Charges to an EXACT ChargeMeter elapsed reading, then releases --
## deterministic power (0.45s == the triangle wave's peak, fraction 1.0;
## 0.0s == the trough, fraction 0.0) rather than depending on incidental
## frame timing.
func _pick_and_throw_at(charge_elapsed: float) -> void:
	Input.action_press("pickup")
	player._pickup_step(0.016)  # pick into hand
	Input.action_release("pickup")
	player._pickup_step(0.016)  # release: no-op, was the pickup press

	Input.action_press("pickup")
	player._pickup_step(0.016)  # new press: starts charging
	player._hand_charge_elapsed = charge_elapsed
	Input.action_release("pickup")
	player._pickup_step(0.016)  # release -> throws at exactly this charge


func _tap_kick() -> void:
	Input.action_press("kick")
	player._kick_step()
	Input.action_release("kick")
	player._kick_step()


# -- thrown stone --------------------------------------------------------------

## A large stone thrown at full charge: mass_kg_for(15cm) * MAX_THROW_SPEED_MPS
## is well above ImpactResolver.T_CRUSH -- the obstacle should clear.
func test_a_heavy_stone_thrown_at_full_power_clears_the_obstacle():
	_add_stone(15.0, Vector2(5, 0))
	var throw_distance := HeldItemThrow.throw_distance_px(1.0)
	var obstacle := _add_obstacle(player.position + Vector2.DOWN * throw_distance)

	_pick_and_throw_at(0.45)  # triangle-wave peak -> full power

	assert_true(obstacle.is_cleared())
	assert_true(obstacle.is_queued_for_deletion())


## A tiny stone thrown at minimum charge: mass_kg_for(2cm) * MIN_THROW_SPEED_MPS
## is well below ImpactResolver.BOUNCE_MOMENTUM_THRESHOLD -- the obstacle
## should stay exactly where it was.
func test_a_light_stone_thrown_at_minimum_power_does_not_clear_the_obstacle():
	_add_stone(2.0, Vector2(5, 0))
	var throw_distance := HeldItemThrow.throw_distance_px(0.0)
	var obstacle := _add_obstacle(player.position + Vector2.DOWN * throw_distance)

	_pick_and_throw_at(0.0)  # triangle-wave trough -> minimum power

	assert_false(obstacle.is_cleared())
	assert_false(obstacle.is_queued_for_deletion())


# -- kicked stone ---------------------------------------------------------------

## A kicked pebble delivers Kick.KICK_MOMENTUM_KG_M_S regardless of its own
## mass (momentum is conserved leg -> stone, see kick.gd's own doc comment),
## which is well above T_CRUSH -- the obstacle should clear. There is no
## real "kick doesn't clear" case to pin here: kick always delivers this
## same fixed momentum to whatever it hits (that's real, tuned, and shared
## with Kick's existing distance model, not invented for this test).
func test_a_kicked_pebble_clears_the_obstacle():
	var stone := _add_stone(3.0, Vector2(5, 0))
	var mass := StoneSize.mass_kg_for(3.0)
	var landing := Kick.landing_position(player.position, stone.position, mass)
	var obstacle := _add_obstacle(landing)

	_tap_kick()

	assert_true(obstacle.is_cleared())
