extends Node2D
class_name CharacterView

const WeaponSwing = preload("res://src/gameplay/weapon_swing.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const SubmersionShader = preload("res://src/rendering/submersion_shader.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")

## Reusable placeholder character rendering: a body/head/legs/arms made of
## flat colored shapes, a directional facing, walk and swim animations, and a
## small set of equipment slots (visual only -- not tied to gameplay
## inventory yet). Meant for both the player and, later, NPCs; swap the
## placeholder textures for real art without touching the API.

enum Facing { DOWN, UP, LEFT, RIGHT }
enum MovementState { IDLE, WALKING, SWIMMING }

const WALK_CYCLE_SPEED := 10.0
const LEG_SWING_AMPLITUDE := 3.0
const SWIM_CYCLE_SPEED := 6.0
const ARM_STROKE_AMPLITUDE := 4.0
## The walking arm counter-swing's amplitude -- reuses LEG_SWING_AMPLITUDE
## rather than a fresh eyeballed number: a natural gait swings each arm
## opposite its same-side leg by an equal amount, so "equal and opposite to
## the leg" is the derived, defensible choice, not an invented one (see
## CLAUDE.md: tuned values must be derived/pinned, not eyeballed).
const ARM_SWING_AMPLITUDE := LEG_SWING_AMPLITUDE
const TOOL_SLOT_SIDE_OFFSET := 8.0

## Bumped from the original 10x14/8x8 (see the character sprite engine's
## hero head/tunic detail -- hairstyles, brows, eyes, belt/collar trim): at
## the old resolution none of that detail had enough pixels to read at all,
## just a flat colored blob under a smaller blob (reported "the in game char
## looks horrible"). These proportions match the tscn's part positions below.
const BODY_SIZE := Vector2i(13, 19)
const HEAD_SIZE := Vector2i(12, 12)
const LEG_SIZE := Vector2i(5, 8)
const ARM_SIZE := Vector2i(4, 9)
const SLOT_SIZE := Vector2i(7, 7)
const EYE_COLOR := Color(0.1, 0.1, 0.1)

## The ART canvases each part is actually painted on: DETAIL_MULTIPLIER
## times the world sizes above (see docs/concept/art_resolution.md). Every
## part sprite is drawn at ArtResolution.SPRITE_SCALE, so the hero gains
## real pixel detail -- a face with actual features rather than a few
## suggestive pixels -- while staying exactly the same size in the world
## and keeping character_view.tscn's part positions (which are in world
## units) valid unchanged.
const ART_BODY_SIZE := Vector2i(26, 38)
const ART_HEAD_SIZE := Vector2i(24, 24)
const ART_LEG_SIZE := Vector2i(10, 16)
const ART_ARM_SIZE := Vector2i(8, 18)
const ART_SLOT_SIZE := Vector2i(14, 14)

## The character's own origin sits at its feet (y=0, see the feet-anchoring
## tests in test_character_view.gd) -- this is the top of the HEAD relative
## to that, i.e. the character's own total height. Mirrors
## character_view.tscn's Head position (-27) minus half HEAD_SIZE.y (6);
## pinned against the live scene by test_head_top_y_matches_the_actual_head_
## nodes_top_edge so a .tscn layout change can't silently drift out of sync
## with the scale computed from it below.
const HEAD_TOP_Y := -33.0

## The character (and every NPC, who shares this same scene -- see
## VillageRenderer) reads at this fraction of a full-grown tree's height,
## rather than looming as tall as (or taller than) the trees around it
## (reported: "shrink the character and npcs so they are 2/3 the height of
## a tree").
const TARGET_HEIGHT_FRACTION_OF_TREE := 2.0 / 3.0

## Computed, not eyeballed (see CLAUDE.md): the character's own total
## on-screen height (feet to head-top, -HEAD_TOP_Y) times this scale must
## equal TARGET_HEIGHT_FRACTION_OF_TREE of a tree's real WORLD height
## (already resolution-corrected -- see TreeRenderer.TREE_SIZE, itself
## just ProceduralTreeSprite.WORLD_SIZE). Pinned by
## test_scaled_character_height_is_two_thirds_a_trees_world_height.
const SCALE := (
	TARGET_HEIGHT_FRACTION_OF_TREE * float(ProceduralTreeSprite.WORLD_SIZE.y) / -HEAD_TOP_Y
)

var facing := Facing.DOWN
var movement_state := MovementState.IDLE
## Whether the character is actually being driven right now (nonzero input),
## as opposed to just being in water. SWIMMING used to stroke the arms
## unconditionally off a free-running clock, so treading water in place
## looked identical to actually swimming (reported: "the arms should only
## animate when moving not when standing"). Legs/arm visibility and tool
## stowing stay keyed off movement_state alone -- you're still submerged
## while treading water -- only the STROKE ANIMATION additionally checks
## this.
var is_moving := false
var leg_swing_offset := 0.0
var arm_stroke_offset := 0.0
## Walking's counter-swing offset -- kept separate from arm_stroke_offset
## (swimming's own animation) rather than overloaded onto it, so each stays
## a single state's animation and existing swim-stroke assertions don't have
## to account for a second animation sharing the field.
var arm_swing_offset := 0.0

var _cycle_time := 0.0
var _equipped_slots: Dictionary = {}  # slot_name (String) -> bool

var _weapon_swing := WeaponSwing.new()
var _character_sprite := ProceduralCharacterSprite.new()
var _submersion := SubmersionShader.new()
var _swing_time_remaining := 0.0
var _swing_duration := 0.0
var _swing_facing := "down"
## A look requested before this view entered the tree (see
## apply_appearance), applied in _ready.
var _pending_appearance: Dictionary = {}

@onready var _body: Sprite2D = $Body
@onready var _head: Sprite2D = $Head
@onready var _leg_left: Sprite2D = $LegLeft
@onready var _leg_right: Sprite2D = $LegRight
@onready var _arm_left: Sprite2D = $ArmLeft
@onready var _arm_right: Sprite2D = $ArmRight
@onready var _head_slot: Sprite2D = $HeadSlot
@onready var _tool_slot: Sprite2D = $ToolSlot

var _leg_left_base_position: Vector2
var _leg_right_base_position: Vector2
var _arm_left_base_position: Vector2
var _arm_right_base_position: Vector2
var _tool_slot_base_position: Vector2


func _ready() -> void:
	# Every part's art is authored DETAIL_MULTIPLIER times oversized for
	# pixel detail; scaling the sprites back down is what keeps the hero at
	# their world size and keeps this scene's part positions (in world
	# units) correct (see docs/concept/art_resolution.md).
	for part in [_body, _head, _leg_left, _leg_right, _arm_left, _arm_right, _head_slot, _tool_slot]:
		part.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE

	# Shrinks the whole rig (this node, not the individual parts above) down
	# to SCALE's fraction of a tree's height -- see SCALE's own doc comment.
	# Applied on the CharacterView node itself so it scales every part AND
	# their .tscn positions uniformly, rather than needing every offset
	# constant in this file re-tuned by hand.
	scale = Vector2.ONE * SCALE

	# Torso submersion (see SubmersionShader) -- the player used to have NO
	# visual for being partway underwater at all: legs simply vanished and
	# the torso rendered exactly as it does on dry land (reported: "half the
	# torso should be under water"). Only the torso, not every part: that is
	# what "half" means here, and it is what the ask specifically named.
	_body.material = _submersion.shared_material()

	_leg_left_base_position = _leg_left.position
	_leg_right_base_position = _leg_right.position
	_arm_left_base_position = _arm_left.position
	_arm_right_base_position = _arm_right.position
	_tool_slot_base_position = _tool_slot.position

	# A look requested before this view was in the tree wins; otherwise a
	# default identity, so an unconfigured view still reads as a person
	# (see apply_appearance / HeroAppearance).
	if _pending_appearance.is_empty():
		apply_appearance(HeroAppearance.new().appearance_for("warrior", 0))
	else:
		apply_appearance(_pending_appearance)

	# Arms stay visible from the start now (see _process's own comment) --
	# only the equipment slots default to hidden until something's equipped.
	_head_slot.visible = false
	_tool_slot.visible = false


func _process(delta: float) -> void:
	match movement_state:
		MovementState.WALKING:
			_cycle_time += delta * WALK_CYCLE_SPEED
			leg_swing_offset = sin(_cycle_time) * LEG_SWING_AMPLITUDE
			arm_stroke_offset = 0.0
			# Opposite the legs -- see ARM_SWING_AMPLITUDE's own doc comment.
			arm_swing_offset = -sin(_cycle_time) * ARM_SWING_AMPLITUDE
		MovementState.SWIMMING:
			leg_swing_offset = 0.0
			arm_swing_offset = 0.0
			if is_moving:
				_cycle_time += delta * SWIM_CYCLE_SPEED
				arm_stroke_offset = sin(_cycle_time) * ARM_STROKE_AMPLITUDE
			else:
				# Treading water: submerged, arms out, but not stroking.
				arm_stroke_offset = 0.0
		_:
			_cycle_time = 0.0
			leg_swing_offset = 0.0
			arm_stroke_offset = 0.0
			arm_swing_offset = 0.0

	_leg_left.visible = movement_state != MovementState.SWIMMING
	_leg_right.visible = movement_state != MovementState.SWIMMING
	# Arms are visible in every state now -- see arms_visible's own doc
	# comment for why they used to be swim-only.
	_arm_left.visible = true
	_arm_right.visible = true

	_leg_left.position = _leg_left_base_position + Vector2(0, leg_swing_offset)
	_leg_right.position = _leg_right_base_position + Vector2(0, -leg_swing_offset)
	# arm_stroke_offset (swim) and arm_swing_offset (walk) are never nonzero
	# at the same time -- only one state drives either -- so summing them is
	# safe and avoids a branch here duplicating the match above.
	var arm_offset := arm_stroke_offset + arm_swing_offset
	_arm_left.position = _arm_left_base_position + Vector2(0, arm_offset)
	_arm_right.position = _arm_right_base_position + Vector2(0, -arm_offset)

	# The waterline sits at the torso's own vertical CENTER -- _body.position
	# is already that centre (Sprite2D draws centred on its own position by
	# default, and Body carries no extra offset), so "half the torso
	# submerged" falls straight out of that existing constant rather than
	# needing a new hand-tuned fraction.
	if movement_state == MovementState.SWIMMING:
		_submersion.set_waterline(global_position.y + _body.position.y)
	else:
		_submersion.clear_waterline()

	if _swing_time_remaining > 0.0:
		_swing_time_remaining = maxf(0.0, _swing_time_remaining - delta)
		if _swing_time_remaining <= 0.0:
			_tool_slot.rotation = 0.0  # swing just finished -- rest, not frozen at full extension
		else:
			var progress := 1.0 - _swing_time_remaining / _swing_duration
			_tool_slot.rotation = _weapon_swing.rotation_at(progress, _swing_facing)
	else:
		_tool_slot.rotation = 0.0


## Updates facing from a movement direction; a near-zero direction (idle)
## leaves the previous facing unchanged rather than snapping to a default.
func set_facing(direction: Vector2) -> void:
	if direction.length() < 0.01:
		return

	if absf(direction.x) > absf(direction.y):
		facing = Facing.RIGHT if direction.x > 0 else Facing.LEFT
	else:
		facing = Facing.DOWN if direction.y > 0 else Facing.UP

	var tool_side := 0.0
	if facing == Facing.RIGHT:
		tool_side = 1.0
	elif facing == Facing.LEFT:
		tool_side = -1.0
	_tool_slot.position = _tool_slot_base_position + Vector2(tool_side * TOOL_SLOT_SIDE_OFFSET, 0.0)
	_tool_slot.z_index = -1 if facing == Facing.UP else 1


## Dresses this character as the given hero (see HeroAppearance): class-
## colored tunic with trim, DNA-picked skin/hair on the head, class leg
## colors, skin-toned arms. Call any time -- textures regenerate in place.
func apply_appearance(appearance: Dictionary) -> void:
	# Callers can dress a view before it has entered the scene tree (a
	# villager is built and dressed by VillageRenderer, whose parent node
	# may not itself be in the tree yet). @onready part refs are null until
	# then, so remember the look and apply it once _ready runs.
	if _body == null:
		_pending_appearance = appearance
		return
	_body.texture = _character_sprite.generate_hero_tunic_texture(ART_BODY_SIZE, appearance)
	_head.texture = _character_sprite.generate_hero_head_texture(ART_HEAD_SIZE, appearance)
	_leg_left.texture = _character_sprite.generate_body_part_texture(ART_LEG_SIZE, appearance.legs)
	_leg_right.texture = _character_sprite.generate_body_part_texture(ART_LEG_SIZE, appearance.legs)
	_arm_left.texture = _character_sprite.generate_body_part_texture(ART_ARM_SIZE, appearance.skin)
	_arm_right.texture = _character_sprite.generate_body_part_texture(ART_ARM_SIZE, appearance.skin)


func set_movement_state(state: MovementState) -> void:
	movement_state = state
	# You can't swing a sword while swimming: the weapon is stowed (hidden)
	# in the water and re-drawn when back on land. _equipped_slots still
	# remembers it's equipped -- this is purely visual stowing.
	if _tool_slot != null and _equipped_slots.get("tool", false):
		_tool_slot.visible = state != MovementState.SWIMMING


func legs_visible() -> bool:
	return _leg_left.visible


## Arms used to only ever be shown while swimming -- see _process's own
## comment. Exposed the same way legs_visible() already is.
func arms_visible() -> bool:
	return _arm_left.visible


func equip_slot(slot_name: String, color: Color) -> void:
	var node := _slot_node(slot_name)
	if node == null:
		return
	_set_solid_texture(node, ART_SLOT_SIZE, color)
	node.visible = true
	_equipped_slots[slot_name] = true


func unequip_slot(slot_name: String) -> void:
	var node := _slot_node(slot_name)
	if node == null:
		return
	node.visible = false
	_equipped_slots.erase(slot_name)


func is_slot_equipped(slot_name: String) -> bool:
	return _equipped_slots.get(slot_name, false)


## Shows the weapon's actual sprite in the tool slot (real item art, not the
## flat-color placeholder equip_slot() uses). Shifts the sprite's rotation
## pivot to the grip -- the bottom edge of the image, per ProceduralItemSprite's
## convention for sword/axe art -- so play_attack_swing's rotation sweeps the
## blade through an arc instead of spinning it in place around its own center.
func equip_weapon(texture: Texture2D) -> void:
	_tool_slot.texture = texture
	_tool_slot.offset = Vector2(0, -texture.get_height() / 2.0)
	_tool_slot.visible = true
	_equipped_slots["tool"] = true


## Starts a swing animation of the equipped weapon: a pendulum arc (see
## WeaponSwing) oriented horizontally for left/right facing or vertically for
## up/down, played out over `duration` seconds and reset to idle afterward.
func play_attack_swing(facing: String, duration: float) -> void:
	_swing_facing = facing
	_swing_duration = duration
	_swing_time_remaining = duration


func tool_slot_rotation() -> float:
	return _tool_slot.rotation


func tool_slot_texture() -> Texture2D:
	return _tool_slot.texture


func tool_slot_offset() -> Vector2:
	return _tool_slot.offset


func _slot_node(slot_name: String) -> Sprite2D:
	match slot_name:
		"head":
			return _head_slot
		"tool":
			return _tool_slot
		_:
			return null


func _set_solid_texture(sprite: Sprite2D, size: Vector2i, color: Color) -> void:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	sprite.texture = ImageTexture.create_from_image(image)
