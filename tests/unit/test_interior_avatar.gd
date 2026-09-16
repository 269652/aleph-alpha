extends GutTest

## InteriorAvatar (see its own doc comment, house_interior_view.gd's):
## the local-only stand-in that actually walks around inside an entered
## house's isolated SubViewport, since the real (possibly networked)
## Player node stays parked outdoors for the whole visit. It renders the
## player's REAL CharacterView (appearance, worn armor, held weapon) --
## reported live: "the indoor scene doesn't use the real character, it's
## just a square". Collision itself (walls/furniture/the door threshold
## actually blocking movement) is standard Godot StaticBody2D/
## CharacterBody2D physics against bodies already covered by
## test_house_interior_view.gd's own collision tests -- not re-proven here
## to avoid a same-frame physics-registration flake; this covers the
## avatar's own setup, dressing, and how it turns input into motion and
## animation.

const HouseInteriorView = preload("res://src/rendering/house_interior_view.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")

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


func _a_texture(color: Color) -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _warrior_look() -> Dictionary:
	return HeroAppearance.new().appearance_for("warrior", 0)


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


# -- the real character, not a square ----------------------------------------

func test_the_visual_is_a_real_character_view_not_a_placeholder():
	assert_not_null(avatar.character_view(), "the avatar must carry a real CharacterView")
	assert_true(avatar.character_view() is CharacterView)
	for child in avatar.get_children():
		assert_false(child is ColorRect, "the old placeholder square must be gone")


func test_dress_applies_appearance_armor_and_weapon_once_in_the_tree():
	var chest := _a_texture(Color.RED)
	var sword := _a_texture(Color.BLUE)

	avatar.dress(_warrior_look(), {"chest": chest}, sword)

	var view: CharacterView = avatar.character_view()
	assert_true(view.is_slot_equipped("chest"), "worn armor must show on the avatar")
	assert_true(view.is_slot_equipped("tool"), "the held weapon must show on the avatar")
	assert_false(view.is_slot_equipped("head"), "a slot nothing was passed for stays bare")
	assert_eq(view.slot_texture("chest").get_image().get_data(), chest.get_image().get_data())


## The diorama's own hard-won lesson (character_preview_diorama.gd's
## _equip_starting_weapon doc comment): CharacterView.equip_* write straight
## to @onready slots, so dressing a view that is not in the tree yet used to
## crash. dress() must be safe to call before add_child and apply once ready.
func test_dress_before_entering_the_tree_is_applied_once_ready():
	var fresh := InteriorAvatar.new()
	fresh.dress(_warrior_look(), {"head": _a_texture(Color.GREEN)}, _a_texture(Color.BLUE))

	add_child(fresh)

	assert_true(fresh.character_view().is_slot_equipped("head"))
	assert_true(fresh.character_view().is_slot_equipped("tool"))
	fresh.free()


func test_dress_with_no_weapon_leaves_the_tool_slot_bare():
	avatar.dress(_warrior_look(), {}, null)
	assert_false(avatar.character_view().is_slot_equipped("tool"))


## A Player that never had apply_class run (a bare fixture) has an empty
## appearance dict; the outdoor rig then shows CharacterView's own default
## look, and the avatar must do the same rather than crash inside
## CharacterView._apply_head on a missing key (found red-first).
func test_dress_with_an_empty_appearance_keeps_the_rigs_default_look_without_crashing():
	avatar.dress({}, {"chest": _a_texture(Color.RED)}, null)
	assert_true(avatar.character_view().is_slot_equipped("chest"), "the rest of the outfit still applies")


# -- movement drives the view exactly like outdoors --------------------------

func test_no_input_produces_no_velocity_and_an_idle_view():
	_register_movement_keybindings()
	avatar._physics_process(0.1)
	assert_eq(avatar.velocity, Vector2.ZERO)
	assert_false(avatar.character_view().is_moving)
	assert_eq(avatar.character_view().movement_state, CharacterView.MovementState.IDLE)


func test_pressing_a_direction_moves_the_avatar_that_way_with_nothing_in_the_way():
	_register_movement_keybindings()
	var position_before := avatar.position

	Input.action_press("move_down")
	avatar._physics_process(0.1)
	Input.action_release("move_down")

	assert_gt(avatar.position.y, position_before.y, "pressing down must move the avatar down")
	assert_almost_eq(avatar.position.x, position_before.x, 0.01, "pressing down must not drift sideways")


func test_walking_faces_the_view_that_way_and_animates_it():
	_register_movement_keybindings()

	Input.action_press("move_left")
	avatar._physics_process(0.1)
	Input.action_release("move_left")

	var view: CharacterView = avatar.character_view()
	assert_eq(view.facing, CharacterView.Facing.LEFT)
	assert_true(view.is_moving)
	assert_eq(view.movement_state, CharacterView.MovementState.WALKING)


func test_stopping_keeps_the_last_facing_but_idles_the_view():
	_register_movement_keybindings()
	Input.action_press("move_right")
	avatar._physics_process(0.1)
	Input.action_release("move_right")

	avatar._physics_process(0.1)

	var view: CharacterView = avatar.character_view()
	assert_eq(view.facing, CharacterView.Facing.RIGHT, "idle never snaps facing back to a default")
	assert_false(view.is_moving)
	assert_eq(view.movement_state, CharacterView.MovementState.IDLE)


func test_movement_speed_matches_the_players_own_outdoor_walking_speed():
	assert_eq(InteriorAvatar.SPEED, Player.BASE_SPEED, "indoor movement should not feel like a different game")


# -- facing cell: which tile a decorate verb targets (docs/concept/ ----------
# -- housing.md "Decorating an entered interior") -- the same dominant-axis --
# -- TileTargeting rule the outdoor build/destroy verbs use, from the -------
# -- avatar's own cell and last facing. ------------------------------------

func test_facing_cell_starts_one_cell_south_facing_down_like_a_fresh_entry():
	avatar.position = Vector2(3.5, 2.5) * 16.0
	assert_eq(avatar.facing_cell(16), Vector2i(3, 3), "a freshly entered avatar faces the room (down)")


func test_facing_cell_follows_the_last_walked_direction_and_keeps_it_when_idle():
	_register_movement_keybindings()
	avatar.position = Vector2(3.5, 2.5) * 16.0

	Input.action_press("move_left")
	avatar._physics_process(0.0)
	Input.action_release("move_left")
	avatar._physics_process(0.0)

	assert_eq(avatar.last_facing_direction, Vector2.LEFT)
	assert_eq(avatar.facing_cell(16), Vector2i(2, 2))
