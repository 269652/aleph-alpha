extends GutTest

const CharacterViewScene = preload("res://scenes/character_view.tscn")

var view: Node2D


func before_each():
	view = CharacterViewScene.instantiate()
	add_child(view)


func after_each():
	remove_child(view)
	view.free()


func test_starts_facing_down_and_idle():
	assert_eq(view.facing, view.Facing.DOWN)
	assert_eq(view.movement_state, view.MovementState.IDLE)


func test_set_facing_updates_facing_for_a_clear_direction():
	view.set_facing(Vector2(1, 0))
	assert_eq(view.facing, view.Facing.RIGHT)

	view.set_facing(Vector2(-1, 0))
	assert_eq(view.facing, view.Facing.LEFT)

	view.set_facing(Vector2(0, 1))
	assert_eq(view.facing, view.Facing.DOWN)

	view.set_facing(Vector2(0, -1))
	assert_eq(view.facing, view.Facing.UP)


func test_set_facing_keeps_the_previous_facing_when_idle():
	view.set_facing(Vector2(1, 0))
	view.set_facing(Vector2.ZERO)
	assert_eq(view.facing, view.Facing.RIGHT)


func test_set_movement_state_updates_the_state():
	view.set_movement_state(view.MovementState.WALKING)
	assert_eq(view.movement_state, view.MovementState.WALKING)
	view.set_movement_state(view.MovementState.SWIMMING)
	assert_eq(view.movement_state, view.MovementState.SWIMMING)
	view.set_movement_state(view.MovementState.IDLE)
	assert_eq(view.movement_state, view.MovementState.IDLE)


func test_leg_swing_is_zero_while_idle():
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.1)
	assert_eq(view.leg_swing_offset, 0.0)


func test_leg_swing_is_nonzero_partway_through_a_walk_cycle():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_ne(view.leg_swing_offset, 0.0)


func test_leg_swing_resets_once_walking_stops():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.1)
	assert_eq(view.leg_swing_offset, 0.0)


func test_arm_stroke_is_zero_while_not_swimming():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_eq(view.arm_stroke_offset, 0.0)


func test_arm_stroke_is_nonzero_partway_through_a_swim_cycle():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	assert_ne(view.arm_stroke_offset, 0.0)


func test_arm_stroke_resets_once_swimming_stops():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.1)
	assert_eq(view.arm_stroke_offset, 0.0)


func test_legs_are_hidden_while_swimming():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	assert_false(view.legs_visible())


func test_legs_are_visible_while_walking_or_idle():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_true(view.legs_visible())


func test_equip_slot_marks_the_slot_as_equipped():
	assert_false(view.is_slot_equipped("head"))
	view.equip_slot("head", Color.RED)
	assert_true(view.is_slot_equipped("head"))


func test_unequip_slot_marks_the_slot_as_not_equipped():
	view.equip_slot("head", Color.RED)
	view.unequip_slot("head")
	assert_false(view.is_slot_equipped("head"))


func test_equip_slot_on_an_unknown_slot_name_does_nothing_harmful():
	view.equip_slot("nonexistent", Color.RED)
	assert_false(view.is_slot_equipped("nonexistent"))


# -- weapon rendering + attack swing animation --------------------------------

func test_equip_weapon_sets_the_tool_slot_texture_and_marks_it_equipped():
	var texture := ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
	view.equip_weapon(texture)
	assert_eq(view.tool_slot_texture(), texture)
	assert_true(view.is_slot_equipped("tool"))


func test_equip_weapon_pivots_rotation_at_the_grip_not_the_sprite_center():
	# Weapon art (see ProceduralItemSprite) draws the grip at the bottom edge
	# of the image; rotating around the sprite's own center just spins it in
	# place, so the pivot must be shifted there instead, letting rotation
	# sweep the blade through a real arc.
	var texture := ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))
	view.equip_weapon(texture)
	assert_almost_eq(view.tool_slot_offset().y, -8.0, 0.01)


func test_tool_slot_rotation_is_zero_before_any_swing():
	assert_eq(view.tool_slot_rotation(), 0.0)


func test_play_attack_swing_rotates_the_tool_slot_partway_through():
	view.equip_weapon(ImageTexture.new())
	view.play_attack_swing("down", 0.2)
	view._process(0.1)  # halfway through a 0.2s swing
	assert_almost_eq(view.tool_slot_rotation(), PI / 2.0, 0.05)


func test_tool_slot_rotation_resets_to_zero_after_the_swing_ends():
	view.equip_weapon(ImageTexture.new())
	view.play_attack_swing("right", 0.1)
	view._process(0.2)  # past the swing's duration
	assert_almost_eq(view.tool_slot_rotation(), 0.0, 0.01)


# -- art resolution (docs/concept/art_resolution.md phase 2) -----------------
#
# The hero's parts are authored at ArtResolution.DETAIL_MULTIPLIER times
# their world size and drawn scaled back down, so the character gains real
# pixel detail without growing relative to the world or to the .tscn's
# part positions (which stay in world units).

const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const CharacterView = preload("res://scenes/character_view.gd")


func test_body_world_size_is_unchanged_by_the_art_resolution_pass():
	assert_eq(CharacterView.BODY_SIZE, Vector2i(13, 19))
	assert_eq(CharacterView.HEAD_SIZE, Vector2i(12, 12))


func test_part_art_sizes_are_the_world_sizes_times_the_detail_multiplier():
	assert_eq(CharacterView.ART_BODY_SIZE, ArtResolution.art_size(CharacterView.BODY_SIZE))
	assert_eq(CharacterView.ART_HEAD_SIZE, ArtResolution.art_size(CharacterView.HEAD_SIZE))
	assert_eq(CharacterView.ART_LEG_SIZE, ArtResolution.art_size(CharacterView.LEG_SIZE))
	assert_eq(CharacterView.ART_ARM_SIZE, ArtResolution.art_size(CharacterView.ARM_SIZE))


## Every part sprite must be scaled back down, or the oversized art would
## render a hero 4x their world footprint.
func test_every_part_sprite_is_scaled_back_to_its_world_footprint():
	for part_name in ["Body", "Head", "LegLeft", "LegRight", "ArmLeft", "ArmRight", "HeadSlot", "ToolSlot"]:
		var sprite: Sprite2D = view.get_node(part_name)
		assert_almost_eq(sprite.scale.x, ArtResolution.SPRITE_SCALE, 0.0001, part_name)
		assert_almost_eq(sprite.scale.y, ArtResolution.SPRITE_SCALE, 0.0001, part_name)


## The body's drawn size (art pixels x scale) must equal its world size --
## the invariant that keeps the hero matched to the world and to the
## .tscn's world-unit part positions.
func test_body_draws_at_its_world_size():
	var body: Sprite2D = view.get_node("Body")
	var drawn := Vector2(body.texture.get_size()) * body.scale
	assert_almost_eq(drawn.x, float(CharacterView.BODY_SIZE.x), 0.01)
	assert_almost_eq(drawn.y, float(CharacterView.BODY_SIZE.y), 0.01)
