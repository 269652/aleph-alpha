extends GutTest

## TEMPORARY real-world probe (see METHODOLOGY) -- NOT a permanent test.
## Deleted before this task finishes. Real Player, real EarthChunkManager,
## real LiftableStone, real CollapsedPassage, run through the ACTUAL
## production code paths (Player._pickup_step / _kick_step), printing the
## real measured momentum numbers from the SAME production functions the
## game itself calls (Throwable.impact_knockback, Kick.KICK_MOMENTUM_KG_M_S,
## ImpactResolver.resolve_impact) -- not hand-traced arithmetic.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const HeldItemThrow = preload("res://src/gameplay/held_item_throw.gd")
const Throwable = preload("res://src/gameplay/throwable.gd")
const CollapsedPassage = preload("res://src/rendering/collapsed_passage.gd")
const ImpactResolver = preload("res://src/gameplay/impact_resolver.gd")
const ChargeMeter = preload("res://src/gameplay/charge_meter.gd")

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
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	Input.action_release("pickup")
	Input.action_release("kick")


func test_probe_light_pebble_thrown_at_minimum_charge_stays_blocked():
	var diameter_cm := 2.0
	var charge_elapsed := 0.0
	var throwable := Throwable.new()
	var resolver := ImpactResolver.new()

	var stone := LiftableStone.new()
	stone.diameter_cm = diameter_cm
	stone.position = player.position + Vector2(5, 0)
	entities_parent.add_child(stone)
	chunk_manager._loaded_stones[Vector2i(0, 0)] = [stone]

	var power := HeldItemThrow.release_speed_mps(ChargeMeter.fraction_at(charge_elapsed))
	var mass_kg := StoneSize.mass_kg_for(diameter_cm)
	var real_momentum: float = throwable.impact_knockback(mass_kg, power)
	var throw_distance := HeldItemThrow.throw_distance_px(ChargeMeter.fraction_at(charge_elapsed))
	var real_outcome: String = resolver.resolve_impact(real_momentum, "blunt", "stone")

	var obstacle := CollapsedPassage.new()
	obstacle.position = player.position + Vector2.DOWN * throw_distance
	add_child_autofree(obstacle)

	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)
	Input.action_press("pickup")
	player._pickup_step(0.016)
	player._hand_charge_elapsed = charge_elapsed
	Input.action_release("pickup")
	player._pickup_step(0.016)

	gut.p("=== PROBE: light pebble thrown at minimum charge ===")
	gut.p("  diameter: %.1f cm, mass: %.4f kg, release speed: %.2f m/s" % [diameter_cm, mass_kg, power])
	gut.p("  MEASURED momentum (Throwable.impact_knockback): %.4f kg*m/s" % real_momentum)
	gut.p("  ImpactResolver.resolve_impact -> %s" % real_outcome)
	gut.p("  obstacle.is_cleared(): %s   is_queued_for_deletion(): %s" % [obstacle.is_cleared(), obstacle.is_queued_for_deletion()])

	assert_false(obstacle.is_cleared(), "expected the light throw to leave the obstacle blocked")


func test_probe_heavy_cobble_thrown_at_full_charge_clears():
	var diameter_cm := 15.0
	var charge_elapsed := 0.45
	var throwable := Throwable.new()
	var resolver := ImpactResolver.new()

	var stone := LiftableStone.new()
	stone.diameter_cm = diameter_cm
	stone.position = player.position + Vector2(5, 0)
	entities_parent.add_child(stone)
	chunk_manager._loaded_stones[Vector2i(0, 0)] = [stone]

	var power := HeldItemThrow.release_speed_mps(ChargeMeter.fraction_at(charge_elapsed))
	var mass_kg := StoneSize.mass_kg_for(diameter_cm)
	var real_momentum: float = throwable.impact_knockback(mass_kg, power)
	var throw_distance := HeldItemThrow.throw_distance_px(ChargeMeter.fraction_at(charge_elapsed))
	var real_outcome: String = resolver.resolve_impact(real_momentum, "blunt", "stone")

	var obstacle := CollapsedPassage.new()
	obstacle.position = player.position + Vector2.DOWN * throw_distance
	add_child_autofree(obstacle)

	Input.action_press("pickup")
	player._pickup_step(0.016)
	Input.action_release("pickup")
	player._pickup_step(0.016)
	Input.action_press("pickup")
	player._pickup_step(0.016)
	player._hand_charge_elapsed = charge_elapsed
	Input.action_release("pickup")
	player._pickup_step(0.016)

	gut.p("=== PROBE: heavy cobble thrown at full charge ===")
	gut.p("  diameter: %.1f cm, mass: %.4f kg, release speed: %.2f m/s" % [diameter_cm, mass_kg, power])
	gut.p("  MEASURED momentum (Throwable.impact_knockback): %.4f kg*m/s" % real_momentum)
	gut.p("  ImpactResolver.resolve_impact -> %s" % real_outcome)
	gut.p("  obstacle.is_cleared(): %s   is_queued_for_deletion(): %s" % [obstacle.is_cleared(), obstacle.is_queued_for_deletion()])

	assert_true(obstacle.is_cleared(), "expected the heavy throw to clear the obstacle")


func test_probe_kicked_pebble_clears():
	var stone := LiftableStone.new()
	stone.diameter_cm = 3.0
	stone.position = player.position + Vector2(5, 0)
	entities_parent.add_child(stone)
	chunk_manager._loaded_stones[Vector2i(0, 0)] = [stone]

	var mass := StoneSize.mass_kg_for(3.0)
	var landing := Kick.landing_position(player.position, stone.position, mass)

	var obstacle := CollapsedPassage.new()
	obstacle.position = landing
	add_child_autofree(obstacle)

	Input.action_press("kick")
	player._kick_step()
	Input.action_release("kick")
	player._kick_step()

	gut.p("=== PROBE: kicked pebble ===")
	gut.p("  pebble diameter: 3.0 cm, mass: %.4f kg" % mass)
	gut.p("  MEASURED kick momentum (Kick.KICK_MOMENTUM_KG_M_S): %.4f kg*m/s" % Kick.KICK_MOMENTUM_KG_M_S)
	gut.p("  obstacle.is_cleared(): %s" % obstacle.is_cleared())

	assert_true(obstacle.is_cleared(), "expected the kicked pebble to clear the obstacle")
