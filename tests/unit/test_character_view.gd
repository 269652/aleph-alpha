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


## arm_stroke_offset now also drives a small hand SWAY while walking, not
## swimming alone (reported live: "hands should also slightly sway when
## walking") -- hero_composite.png's arms weren't visible outside swimming
## until this same pass (see CharacterView._process's own doc comment on
## why), so a standing-still hand had never needed to look alive before.
## Idle stays the true "not moving at all" zero case.
func test_arm_stroke_is_zero_while_idle():
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.1)
	assert_eq(view.arm_stroke_offset, 0.0)


func test_arm_stroke_is_nonzero_partway_through_a_walk_cycle():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_ne(view.arm_stroke_offset, 0.0)


## Real gait swings an arm opposite the leg on its OWN side (contralateral
## coordination: left arm forward with right leg forward) -- checked by
## sign, not exact magnitude, since ARM_SWAY_AMPLITUDE and
## LEG_SWING_AMPLITUDE are free to differ.
func test_arm_sway_is_contralateral_to_leg_swing_while_walking():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	assert_ne(signf(view.arm_stroke_offset), signf(view.leg_swing_offset))


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


## Arms used to be visible ONLY while swimming -- a leftover from when the
## flat procedural torso rectangle was wide enough to visually stand in for
## a whole upper body, arms included, and separate Arm sprites existed only
## for the swimming stroke animation. hero_composite.png's illustrated torso
## stops at the shoulder (see docs/concept/character_art_brief.md's own
## proportions note), so that assumption no longer holds -- reported live:
## "no hands are visible" while standing/walking. Arms now stay visible in
## every movement state; only the STROKE animation itself stays gated to
## swimming (see arm_stroke_offset's own handling in _process).
func test_arms_are_visible_while_idle():
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.1)
	var arm_left: Sprite2D = view.get_node("ArmLeft")
	var arm_right: Sprite2D = view.get_node("ArmRight")
	assert_true(arm_left.visible)
	assert_true(arm_right.visible)


func test_arms_are_visible_while_walking():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	var arm_left: Sprite2D = view.get_node("ArmLeft")
	assert_true(arm_left.visible)


func test_arms_are_visible_while_swimming():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	var arm_left: Sprite2D = view.get_node("ArmLeft")
	assert_true(arm_left.visible)


# -- illustrated legs: worn as one fused pair, not two independent sprites --
#
# leg.png draws both legs together (see IllustratedCharacterSprite's own doc
# comment) -- CharacterView wears it as one sprite covering both world slots
# rather than splitting it, so LegRight stays hidden and LegLeft does not
# swing independently (see _apply_legs/_process).

func test_legs_are_fused_now_that_illustrated_leg_art_is_registered():
	assert_true(view.legs_are_fused())


func test_fused_legs_hide_the_right_leg_node_regardless_of_movement():
	for state in [view.MovementState.IDLE, view.MovementState.WALKING]:
		view.set_movement_state(state)
		view._process(0.1)
		var leg_right: Sprite2D = view.get_node("LegRight")
		assert_false(leg_right.visible, str(state))


func test_fused_legs_still_hide_entirely_for_swimming():
	view.set_movement_state(view.MovementState.SWIMMING)
	view._process(0.1)
	assert_false(view.legs_visible())


## No per-leg swing art exists for the fused pair, so a whole-pair bob
## substitutes for it (reported: "the legs aren't animated") -- must still
## move, just not by splitting into two offset copies of one sprite.
func test_fused_legs_bob_while_walking():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.3)
	var leg_left: Sprite2D = view.get_node("LegLeft")
	assert_ne(leg_left.position.y, view._leg_fused_rest_position.y)


func test_fused_legs_stay_put_while_idle():
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.3)
	var leg_left: Sprite2D = view.get_node("LegLeft")
	assert_almost_eq(leg_left.position.y, view._leg_fused_rest_position.y, 0.001)


## An interim stride cue for the fused pair, on top of the existing vertical
## bob -- real per-leg knee art doesn't exist yet (see docs/concept/
## character_art_brief.md's own "Four bugs" section on why the fused
## drawing can't split into independently-swinging legs at all), but a
## small hip-pivot rock reads as more of a stride than the bob alone
## (reported live: asked for real knee-jointed per-leg animation; a whole-
## pair rotational rock is the closest this session can build without new
## art -- see FUSED_LEG_ROCK_AMPLITUDE's own doc comment). Once per full
## stride (sin, not the bob's absf(sin)) -- a real gait leans one way then
## the other over a whole stride, not twice per stride the way footfalls
## land.
func test_fused_legs_rock_side_to_side_while_walking():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.3)
	var leg_left: Sprite2D = view.get_node("LegLeft")
	assert_ne(leg_left.rotation, 0.0)


func test_fused_legs_rock_resets_to_upright_while_idle():
	view.set_movement_state(view.MovementState.IDLE)
	view._process(0.3)
	var leg_left: Sprite2D = view.get_node("LegLeft")
	assert_almost_eq(leg_left.rotation, 0.0, 0.001)


# -- illustrated arms: two independent poses, not one frame worn twice ------

func test_arm_left_and_arm_right_use_different_source_frames():
	var arm_left: Sprite2D = view.get_node("ArmLeft")
	var arm_right: Sprite2D = view.get_node("ArmRight")
	assert_ne(arm_left.texture, arm_right.texture)


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


## Reported live: "the sword should be held by the actual hand" -- ToolSlot
## used to sit at a fixed torso-side position (_tool_slot_base_position),
## independent of the arm entirely. It now tracks ArmRight's own current
## position every frame instead, so a held weapon inherits the hand's own
## sway (see ARM_SWAY_AMPLITUDE) rather than floating at a static point.
func test_tool_slot_tracks_arm_rights_current_position():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	var arm_right: Sprite2D = view.get_node("ArmRight")
	var tool_slot: Sprite2D = view.get_node("ToolSlot")
	var expected := arm_right.position + Vector2(0, CharacterView.GRIP_OFFSET_Y)
	assert_almost_eq(tool_slot.position.x, expected.x, 0.01)
	assert_almost_eq(tool_slot.position.y, expected.y, 0.01)


## The tracked position must actually move as the arm sways, not just agree
## with it at one single frame by coincidence.
func test_tool_slot_moves_with_the_arms_walk_sway():
	view.set_movement_state(view.MovementState.WALKING)
	view._process(0.1)
	var tool_slot: Sprite2D = view.get_node("ToolSlot")
	var first: Vector2 = tool_slot.position
	view._process(0.4)
	var second: Vector2 = tool_slot.position
	assert_ne(first, second)


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
	# BODY_SIZE.x widened 13 -> 26 to match hero_composite.png's own torso
	# proportions -- see BODY_SIZE's own doc comment.
	assert_eq(CharacterView.BODY_SIZE, Vector2i(26, 19))
	assert_eq(CharacterView.HEAD_SIZE, Vector2i(12, 12))


func test_part_art_sizes_are_the_world_sizes_times_the_detail_multiplier():
	assert_eq(CharacterView.ART_BODY_SIZE, ArtResolution.art_size(CharacterView.BODY_SIZE))
	assert_eq(CharacterView.ART_HEAD_SIZE, ArtResolution.art_size(CharacterView.HEAD_SIZE))
	assert_eq(CharacterView.ART_LEG_SIZE, ArtResolution.art_size(CharacterView.LEG_SIZE))
	assert_eq(CharacterView.ART_ARM_SIZE, ArtResolution.art_size(CharacterView.ARM_SIZE))


## HeadSlot/ToolSlot are equipment, never routed through the illustrated
## pipeline (see equip_slot/equip_weapon) -- they always share the flat
## ArtResolution.SPRITE_SCALE. Head/Body/Leg*/Arm* now go through
## IllustratedCharacterSprite by default (see below): each is normalized onto
## ONE shared working canvas, not sized per part, so they carry their OWN
## measured scale instead of this flat constant -- see
## test_illustrated_parts_are_each_scaled_to_their_own_world_size.
func test_equipment_slots_share_the_flat_art_resolution_scale():
	for part_name in ["HeadSlot", "ToolSlot"]:
		var sprite: Sprite2D = view.get_node(part_name)
		assert_almost_eq(sprite.scale.x, ArtResolution.SPRITE_SCALE, 0.0001, part_name)
		assert_almost_eq(sprite.scale.y, ArtResolution.SPRITE_SCALE, 0.0001, part_name)


## Every illustrated part sprite must be scaled back down to its OWN real
## world footprint (see IllustratedCharacterSprite.part_scale_for/
## head_scale_for) -- measured from the part's own drawn content, since a
## flat shared scale would render some parts oversized and others
## undersized the instant their content doesn't fill the shared working
## canvas identically (which normalize_frames' own aspect-preserving fit
## means it usually doesn't).
## Body is checked with an upper bound, not assert_almost_eq like the rest --
## see BODY_SIZE's own doc comment: it only renders at EXACTLY BODY_SIZE.y
## for an outfit row whose aspect matches the box BODY_SIZE.x was measured
## from, and other rows legitimately render shorter once
## _width_bounded_scale's own width clamp binds instead. Never taller,
## always the real invariant to pin.
func test_illustrated_parts_are_each_scaled_to_their_own_world_size():
	var expected_world_height := {
		"Head": CharacterView.HEAD_SIZE.y,
		"LegLeft": CharacterView.LEG_SIZE.y,
		"ArmLeft": CharacterView.ARM_SIZE.y,
		"ArmRight": CharacterView.ARM_SIZE.y,
	}
	for part_name in expected_world_height:
		var sprite: Sprite2D = view.get_node(part_name)
		var content_height := _opaque_content_height(sprite.texture.get_image())
		assert_almost_eq(
			content_height * sprite.scale.y, float(expected_world_height[part_name]), 0.5, part_name
		)
	var body: Sprite2D = view.get_node("Body")
	var body_height := _opaque_content_height(body.texture.get_image()) * body.scale.y
	assert_true(body_height <= float(CharacterView.BODY_SIZE.y) + 0.5, "Body: rendered %.2f" % body_height)


## The body's drawn CONTENT (art pixels x scale, trimmed to what is actually
## opaque -- illustrated art is normalized onto a padded shared canvas, see
## IllustratedCharacterSprite.CANVAS_SIZE, so the raw texture size alone
## overstates it) must never EXCEED its world size -- see BODY_SIZE's own
## doc comment on why "at most", not "exactly", is the real invariant now.
func test_body_draws_at_most_its_world_size():
	var body: Sprite2D = view.get_node("Body")
	var content_height := _opaque_content_height(body.texture.get_image())
	assert_true(content_height * body.scale.y <= float(CharacterView.BODY_SIZE.y) + 0.5)


func _opaque_content_height(image: Image) -> float:
	var min_y := image.get_height()
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	return float(max_y - min_y + 1)


func _opaque_content_width(image: Image) -> float:
	var min_x := image.get_width()
	var max_x := -1
	for x in image.get_width():
		for y in image.get_height():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	return float(max_x - min_x + 1)


## composite_part_scale_for matches CONTENT HEIGHT to a part's target world
## height alone, then CharacterView applies that SAME scale to width
## (Sprite2D.scale is one uniform Vector2.ONE * scale) -- correct only when
## the source art's own aspect ratio already matches the target box's own
## aspect, the assumption the old flat-rectangle procedural art satisfied by
## construction (drawn at EXACTLY that box, so matching height always meant
## matching width too). Scoped to BODY specifically, not every part: it is
## the one confirmed, visually dramatic case -- hero_composite.png's torso
## column measures noticeably WIDER relative to its own height than
## BODY_SIZE's own aspect (short sleeves drawn as part of the same
## silhouette), and height-matching alone rendered it roughly 2x BODY_SIZE.x
## wide (reported live: "proportions are awfully wrong"). Legs/arms/head
## were checked too and are NOT put through the same clamp -- their own
## aspect mismatches are real but small enough that forcing a width bound
## shrank their rendered HEIGHT well below target for no visible gain (see
## _width_bounded_scale's own doc comment); revisit per-part if one of them
## is ever reported looking wrong the way body was.
func test_body_never_renders_wider_than_its_own_world_width():
	var expected_world_width := {
		"Body": CharacterView.BODY_SIZE.x,
	}
	for part_name in expected_world_width:
		var sprite: Sprite2D = view.get_node(part_name)
		var content_width := _opaque_content_width(sprite.texture.get_image())
		var rendered_width: float = content_width * sprite.scale.x
		assert_true(
			rendered_width <= float(expected_world_width[part_name]) + 0.5,
			"%s: rendered %.2f, expected at most %s" % [part_name, rendered_width, expected_world_width[part_name]]
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


## Neither Head's nor Body's own art draws a neck, and both are positioned
## by their own measured content (varies per outfit row/head cell), so a
## fixed-size neck would only fit one combination -- reported live: "the
## head is floating" / "the neck should be rendered procedurally". Checks
## the real invariant (no visible gap once the neck is accounted for)
## rather than exact pixel positions, since which appearance the view's
## default seed happens to roll -- and therefore whether a gap exists at
## all for it -- isn't something this test controls.
func test_neck_bridges_any_gap_between_head_and_body():
	var neck: Sprite2D = view.get_node("Neck")
	var head: Sprite2D = view.get_node("Head")
	var body: Sprite2D = view.get_node("Body")
	var head_bottom: float = head.position.y + head.offset.y * head.scale.y + CharacterView.HEAD_SIZE.y * 0.5
	var body_top: float = (
		body.position.y + body.offset.y * body.scale.y - view._body_content_height_world() * 0.5
	)
	if not neck.visible:
		assert_true(body_top <= head_bottom + 0.5, "no neck shown, but a gap exists")
		return
	var neck_height: float = neck.texture.get_image().get_height() * neck.scale.y
	var neck_top: float = neck.position.y - neck_height * 0.5
	var neck_bottom: float = neck.position.y + neck_height * 0.5
	assert_true(neck_top <= head_bottom + 0.5, "neck should reach up to head's bottom edge")
	assert_true(neck_bottom >= body_top - 0.5, "neck should reach down to body's top edge")


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
func test_scaled_character_height_matches_its_target_fraction_of_a_trees_height():
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


# -- leg proportions: a real anthropometric leg-to-height fraction ----------
#
# Reported live: "the players walk animation and overall appearance looks
# like a dwarf" -- LEG_SIZE.y previously put legs at 12/33 (~36%) of the
# character's own total height, short of a real standing human's leg share.
# Winter's "Biomechanics and Motor Control of Human Movement" segment-length
# table (the same book stone_size.gd's LEG_MASS_FRACTION already cites, for
# a different table) gives thigh length as ~0.245x standing height and shank
# length as ~0.246x -- together ~49.1% of a person's real standing height is
# leg, hip joint to floor. See CharacterView.LEG_TO_HEIGHT_FRACTION.

func test_leg_size_matches_the_anthropometric_leg_to_height_fraction():
	var expected := roundi(CharacterView._anthropometric_leg_height(CharacterView.ABOVE_HIP_HEIGHT))
	assert_eq(CharacterView.LEG_SIZE.y, expected)


func test_the_resulting_leg_share_of_total_height_is_within_the_cited_anthropometric_range():
	var total := CharacterView.ABOVE_HIP_HEIGHT + float(CharacterView.LEG_SIZE.y)
	var fraction: float = float(CharacterView.LEG_SIZE.y) / total
	assert_true(fraction >= 0.45 and fraction <= 0.50, "leg fraction was %.3f" % fraction)


## HEAD_TOP_Y must grow by exactly however much the legs grew (see
## ABOVE_HIP_HEIGHT's own doc comment: everything above the hip line is held
## fixed while legs stretch) -- a literal Y-axis stretch that makes the
## character genuinely taller, not a bigger overall SCALE multiplier that
## would leave proportions (and the "dwarf" look) unchanged.
func test_head_top_y_equals_above_hip_height_plus_the_new_leg_height():
	assert_almost_eq(
		-CharacterView.HEAD_TOP_Y, CharacterView.ABOVE_HIP_HEIGHT + float(CharacterView.LEG_SIZE.y), 0.01
	)
