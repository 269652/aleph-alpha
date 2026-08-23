extends GutTest

## Kick (see docs/concept/stone.md, Kick, Keybindings' "kick" action -> K):
## a real player, a real EarthChunkManager, a real injected LiftableStone --
## pressing kick sends a nearby light stone flying away from the player, and
## leaves a too-heavy stone (at/above leg mass) untouched. Mirrors
## test_player.gd's real-scene setup and test_earth_chunk_manager.gd's
## `_loaded_stones` injection convention for nearest_liftable_stone_near.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const Kick = preload("res://src/gameplay/kick.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player


func before_each():
	# World._apply_keybindings normally registers every Keybindings action
	# onto the InputMap at runtime (there is no static [input] section in
	# project.godot) -- this test instantiates Player directly, without a
	# World, so it registers the one action it needs itself.
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
	Input.action_release("kick")


func _add_stone(diameter_cm: float, offset: Vector2) -> LiftableStone:
	var stone := LiftableStone.new()
	stone.diameter_cm = diameter_cm
	stone.position = player.position + offset
	entities_parent.add_child(stone)
	chunk_manager._loaded_stones[Vector2i(0, 0)] = [stone]
	return stone


func _tap_kick() -> void:
	Input.action_press("kick")
	player._kick_step()
	Input.action_release("kick")
	player._kick_step()


func test_kick_sends_a_light_pebble_flying_away_from_the_player():
	var stone := _add_stone(3.0, Vector2(5, 0))
	var original_position := stone.position
	_tap_kick()
	assert_ne(stone.position, original_position, "a kicked pebble should have moved")
	assert_gt(stone.position.x, original_position.x, "the pebble should fly further AWAY from the player")
	stone.free()


## The user's explicit design: a stone at or above leg mass is too heavy to
## kick at all.
func test_kick_does_not_move_a_stone_at_or_above_leg_mass():
	# COBBLE_MAX_CM is already heavier than LEG_MASS_KG (see Kick's own class
	# doc comment) -- the largest cobble is a real, in-range example of a
	# too-heavy-to-kick stone.
	var stone := _add_stone(StoneSize.COBBLE_MAX_CM, Vector2(5, 0))
	assert_false(Kick.is_kickable(StoneSize.mass_kg_for(StoneSize.COBBLE_MAX_CM)))
	var original_position := stone.position
	_tap_kick()
	assert_eq(stone.position, original_position, "a too-heavy stone should not move at all")
	stone.free()


func test_kick_does_nothing_when_no_stone_is_in_reach():
	# No stone injected at all -- kicking thin air should not error.
	_tap_kick()
	assert_true(true, "kick with nothing nearby should be a harmless no-op")


## Rising-edge only: holding the key down should not repeatedly re-kick an
## already-moved stone every frame.
func test_kick_only_fires_once_per_press():
	var stone := _add_stone(3.0, Vector2(5, 0))
	Input.action_press("kick")
	player._kick_step()
	var after_first := stone.position
	player._kick_step()  # still held -- must not kick again
	assert_eq(stone.position, after_first, "kick should only fire on the rising edge, not every frame held")
	Input.action_release("kick")
	stone.free()
