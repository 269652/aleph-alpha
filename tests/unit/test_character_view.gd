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


## Stroking requires BOTH swimming and is_moving -- see is_moving's doc
## comment. Not just "swimming": that was the bug (treading water in place
## looked identical to actually swimming, reported: "the arms should only
## animate when moving not when standing").
func test_arm_stroke_is_nonzero_partway_through_a_swim_cycle_while_moving():
	view.set_movement_state(view.MovementState.SWIMMING)
	view.is_moving = true
	view._process(0.1)
	assert_ne(view.arm_stroke_offset, 0.0)


## THE regression this exists to catch: swimming alone must not stroke.
func test_arm_stroke_stays_zero_while_swimming_but_not_moving():
	view.set_movement_state(view.MovementState.SWIMMING)
	view.is_moving = false
	view._process(0.1)
	assert_eq(view.arm_stroke_offset, 0.0)


## Treading water is still submerged -- legs stay hidden even though the
## stroke has stopped. Only the ANIMATION should differ, not the pose.
func test_treading_water_keeps_legs_hidden():
	view.set_movement_state(view.MovementState.SWIMMING)
	view.is_moving = false
	view._process(0.1)
	assert_false(view.legs_visible())


func test_arm_stroke_resets_once_swimming_stops():
	view.set_movement_state(view.MovementState.SWIMMING)
	view.is_moving = true
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


## Arms used to only ever show up while swimming (see set_movement_state's
## visibility toggle before this fix) -- a normal walking/standing character
## rendered with a literally armless torso (reported, screenshotted: "no
## arms"). A person has arms all the time, not just mid-stroke.
func test_arms_are_visible_while_idle():
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.1)
	assert_true(view.arms_visible())


func test_arms_are_visible_while_walking():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_true(view.arms_visible())


func test_arms_are_visible_while_swimming():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	assert_true(view.arms_visible())


## Walking gets a counter-swing (opposite the legs), the same natural-gait
## treatment legs already had -- arms used to just hang rigid (invisible,
## even) through an entire walk cycle.
func test_arm_swing_is_nonzero_partway_through_a_walk_cycle():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_ne(view.arm_swing_offset, 0.0)


## Opposite the legs, not matching them -- a real gait swings the left arm
## forward with the RIGHT leg, not its own-side leg. Reuses
## LEG_SWING_AMPLITUDE (see ARM_SWING_AMPLITUDE's own doc comment) rather
## than a fresh eyeballed number, so the two swings are equal-and-opposite
## by construction.
func test_arm_swing_is_opposite_phase_to_the_leg_swing_while_walking():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_almost_eq(view.arm_swing_offset, -view.leg_swing_offset, 0.0001)


func test_arm_swing_resets_once_walking_stops():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.1)
	assert_eq(view.arm_swing_offset, 0.0)


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


## The tunic's hem used to flare to nearly full shoulder width and directly
## overlap the legs' own span below it -- for any class whose leg color sits
## close to its tunic/trim (e.g. "guard": tunic (0.28,0.34,0.46), legs
## (0.22,0.24,0.28)), the hem read as an undifferentiated second pair of
## legs sitting right on top of the real ones (reported, screenshotted:
## "double legs"). Measured from the ACTUAL generated art (not the
## _HEM_FRACTION constant directly), converted art->world px the same way
## every other part-size assertion in this file does, and compared against
## the real leg-pair span read from the live .tscn nodes -- so this stays
## correct even if LEG_SIZE or the legs' positions ever change.
func test_tunic_hem_does_not_read_as_a_second_pair_of_legs():
	var body: Sprite2D = view.get_node("Body")
	var image: Image = body.texture.get_image()
	var hem_row := image.get_height() - 1
	var min_x := image.get_width()
	var max_x := -1
	for x in image.get_width():
		if image.get_pixel(x, hem_row).a > 0.01:
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
	var hem_world_width: float = float(max_x - min_x + 1) * ArtResolution.SPRITE_SCALE

	var leg_left: Sprite2D = view.get_node("LegLeft")
	var leg_right: Sprite2D = view.get_node("LegRight")
	var legs_left_edge: float = leg_left.position.x - CharacterView.LEG_SIZE.x / 2.0
	var legs_right_edge: float = leg_right.position.x + CharacterView.LEG_SIZE.x / 2.0
	var legs_world_width: float = legs_right_edge - legs_left_edge

	# Clearly narrower, not a hairline margin -- 0.85 is this test's own
	# "meaningfully narrower" bar, not a production-tuned value.
	assert_lt(
		hem_world_width, legs_world_width * 0.85,
		"hem width %s vs leg-pair width %s -- hem must read clearly narrower or it looks like a second pair of legs" % [hem_world_width, legs_world_width]
	)


# -- the character must be anchored at its FEET, not its center --------------
#
# CharacterView's origin is what player.gd's CharacterBody2D collision sits
# at (see player.tscn: CollisionShape2D has no offset from the body). The
# parts were drawn centered on that same origin, at the character's
# midriff, so the collision box represented the character's WAIST while the
# head reached 19 world units above it and the feet only 14 below -- any
# solid object the player walked up against had the player's head visibly
# poking past it (reported repeatedly as trees/stones "rendering one square
# too high"/floating; see tree_renderer.gd's TRUNK_COLLISION_DEPTH history).
# Trees and stones are already foot-anchored the same way world.gd spawns
# characters -- the player's own art was the one part of this still
# center-anchored.

func test_the_characters_feet_sit_at_its_own_origin():
	var leg_left: Sprite2D = view.get_node("LegLeft")
	var feet_y: float = leg_left.position.y + CharacterView.LEG_SIZE.y / 2.0
	assert_almost_eq(feet_y, 0.0, 0.5, "the character's origin should sit at its feet, not its waist")


func test_no_part_hangs_below_the_characters_own_origin():
	for part_name in ["Body", "Head", "LegLeft", "LegRight", "ArmLeft", "ArmRight"]:
		var sprite: Sprite2D = view.get_node(part_name)
		var world_size: Vector2i = {
			"Body": CharacterView.BODY_SIZE, "Head": CharacterView.HEAD_SIZE,
			"LegLeft": CharacterView.LEG_SIZE, "LegRight": CharacterView.LEG_SIZE,
			"ArmLeft": CharacterView.ARM_SIZE, "ArmRight": CharacterView.ARM_SIZE,
		}[part_name]
		var bottom: float = sprite.position.y + world_size.y / 2.0
		assert_lte(bottom, 0.5, "%s should not extend below the character's feet" % part_name)


# -- torso submersion --------------------------------------------------------
#
# The player used to have NO visual for being partway underwater: legs just
# vanished and the torso rendered exactly as it does on dry land (reported:
# "half the torso should be under water"). The torso now carries a shared
# world-space tint material (see SubmersionShader) whose waterline is driven
# from movement_state.

const SubmersionShader = preload("res://src/rendering/submersion_shader.gd")


func test_the_torso_carries_the_shared_submersion_material():
	var body: Sprite2D = view.get_node("Body")
	assert_true(body.material is ShaderMaterial)
	assert_string_contains((body.material as ShaderMaterial).shader.code, "water_world_y")


func test_swimming_sets_the_waterline_at_the_torsos_own_centre():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	var body: Sprite2D = view.get_node("Body")
	var material := body.material as ShaderMaterial
	# _body.position.y IS the torso's own vertical centre (Sprite2D draws
	# centred on its own position, and Body carries no extra offset) -- so
	# "half the torso submerged" falls out of that existing constant.
	assert_almost_eq(
		float(material.get_shader_parameter("water_world_y")),
		view.position.y + body.position.y,
		0.01
	)


## Nothing should be tinted on dry land or mid-stride -- only while
## genuinely in the water.
func test_not_swimming_clears_the_waterline():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	var body: Sprite2D = view.get_node("Body")
	var material := body.material as ShaderMaterial
	assert_gt(float(material.get_shader_parameter("water_world_y")), 100000.0)


# -- sized relative to a tree (reported: "shrink the character and npcs so --
# -- they are 2/3 the height of a tree") -------------------------------------
#
# Trees used to tower unrealistically over the player (and every NPC, who
# shares this same scene -- see VillageRenderer) with no size relationship
# between them at all. The character is now scaled down so its own total
# on-screen height (feet at the origin, see the feet-anchoring tests above,
# to the top of the head) comes out to a fixed fraction of a tree's real
# WORLD height (already resolution-corrected, see TreeRenderer.TREE_SIZE).

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")


## HEAD_TOP_Y is a script constant mirroring the .tscn's Head layout (so the
## scale formula below doesn't need to inspect a live scene) -- pinned here
## against the ACTUAL instantiated Head node so the two can't silently drift
## apart.
func test_head_top_y_matches_the_actual_head_nodes_top_edge():
	var head: Sprite2D = view.get_node("Head")
	var actual_top: float = head.position.y - CharacterView.HEAD_SIZE.y / 2.0
	assert_almost_eq(CharacterView.HEAD_TOP_Y, actual_top, 0.01)


## The formula itself: scaling the character's own total height (feet to
## head-top) by CharacterView.SCALE must land it at exactly
## TARGET_HEIGHT_FRACTION_OF_TREE of a real tree's world height -- not an
## eyeballed constant.
func test_scaled_character_height_is_two_thirds_a_trees_world_height():
	var character_height := -CharacterView.HEAD_TOP_Y  # feet (y=0) to head-top
	var scaled_height := character_height * CharacterView.SCALE
	var expected := CharacterView.TARGET_HEIGHT_FRACTION_OF_TREE * ProceduralTreeSprite.WORLD_SIZE.y
	assert_almost_eq(scaled_height, expected, 0.01)


## The scale must actually be applied to the instantiated view, not just
## exist as an unused constant.
func test_the_instantiated_view_is_scaled_down():
	assert_almost_eq(view.scale.x, CharacterView.SCALE, 0.0001)
	assert_almost_eq(view.scale.y, CharacterView.SCALE, 0.0001)
	assert_lt(CharacterView.SCALE, 1.0, "the character should shrink, not grow, relative to its old size")
