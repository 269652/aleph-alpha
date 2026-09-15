extends GutTest

## InteriorAvatar (see its own doc comment, house_interior_view.gd's):
## the local-only stand-in that actually walks around inside an entered
## house's isolated SubViewport, since the real (possibly networked)
## Player node stays parked outdoors for the whole visit. Collision
## itself (walls/furniture/the door threshold actually blocking movement)
## is standard Godot StaticBody2D/CharacterBody2D physics against bodies
## already covered by test_house_interior_view.gd's own collision tests --
## not re-proven here to avoid a same-frame physics-registration flake;
## this covers the avatar's own setup and how it turns input into motion.

const HouseInteriorView = preload("res://src/rendering/house_interior_view.gd")

var avatar: InteriorAvatar


func before_each():
	avatar = InteriorAvatar.new()
	add_child(avatar)


func after_each():
	avatar.free()
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")


func _register_movement_keybindings() -> void:
	for action_name in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)


func test_collides_only_against_the_interior_layer_never_visible_to_anything_else():
	assert_eq(avatar.collision_mask, HouseInteriorView.INTERIOR_COLLISION_LAYER)
	assert_eq(avatar.collision_layer, 0, "nothing needs to collide INTO the avatar itself")


func test_has_a_real_collision_shape():
	var shape: CollisionShape2D = null
	for child in avatar.get_children():
		if child is CollisionShape2D:
			shape = child
			break
	assert_not_null(shape, "InteriorAvatar must have a real CollisionShape2D child")
	assert_not_null(shape.shape, "the collision shape must actually be set")


func test_no_input_produces_no_velocity():
	_register_movement_keybindings()
	avatar._physics_process(0.1)
	assert_eq(avatar.velocity, Vector2.ZERO)


func test_pressing_a_direction_moves_the_avatar_that_way_with_nothing_in_the_way():
	_register_movement_keybindings()
	var position_before := avatar.position

	Input.action_press("move_down")
	avatar._physics_process(0.1)
	Input.action_release("move_down")

	assert_gt(avatar.position.y, position_before.y, "pressing down must move the avatar down")
	assert_almost_eq(avatar.position.x, position_before.x, 0.01, "pressing down must not drift sideways")


func test_movement_speed_matches_the_players_own_outdoor_walking_speed():
	assert_eq(InteriorAvatar.SPEED, Player.BASE_SPEED, "indoor movement should not feel like a different game")
