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
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

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


# -- a dropped item (docs/concept/wild_crops.md's "physical entity, not -----
# -- just an inventory grant") is kickable the same way a stone is, when ----
# -- no stone is closer -------------------------------------------------------

func _add_dropped_carrot(offset: Vector2) -> DroppedItem:
	var dropped := DroppedItem.new()
	dropped.item_stack = ItemStack.new(Item.new("carrot", "Carrot", "food", 20, 0.0, "", 0.0, 0.07), 1)
	dropped.position = player.position + offset
	# Unlike _add_stone (found via chunk_manager._loaded_stones, a direct
	# dict injection that doesn't need real tree membership), a DroppedItem
	# is found via its own scene-tree group (see Player.
	# _nearest_kickable_dropped_item_near / pickup_nearby) -- it has to
	# actually be IN the live tree for _ready() to join it, so it's parented
	# under `self` (already in the tree) rather than the disconnected
	# entities_parent this test file never mounts.
	add_child(dropped)
	return dropped


func test_kick_sends_a_dropped_carrot_flying_away_from_the_player():
	var dropped := _add_dropped_carrot(Vector2(5, 0))
	var original_position := dropped.position
	_tap_kick()
	assert_ne(dropped.position, original_position, "a kicked dropped item should have moved")
	assert_gt(dropped.position.x, original_position.x, "should fly further AWAY from the player")
	dropped.free()


func test_kick_prefers_a_nearer_stone_over_a_farther_dropped_item():
	var dropped := _add_dropped_carrot(Vector2(50, 0))  # far
	var stone := _add_stone(3.0, Vector2(5, 0))  # near
	_tap_kick()
	assert_eq(dropped.position, player.position + Vector2(50, 0), "the far dropped item should be untouched")
	assert_ne(stone.position, player.position + Vector2(5, 0), "the nearer stone should be the one kicked")
	dropped.free()
	stone.free()


func test_kick_prefers_a_nearer_dropped_item_over_a_farther_stone():
	var dropped := _add_dropped_carrot(Vector2(5, 0))  # near
	var stone := _add_stone(3.0, Vector2(50, 0))  # far
	_tap_kick()
	assert_eq(stone.position, player.position + Vector2(50, 0), "the far stone should be untouched")
	assert_ne(dropped.position, player.position + Vector2(5, 0), "the nearer dropped item should be the one kicked")
	dropped.free()
	stone.free()
