extends Node2D
class_name CharacterView

const WeaponSwing = preload("res://src/gameplay/weapon_swing.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

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

var facing := Facing.DOWN
var movement_state := MovementState.IDLE
var leg_swing_offset := 0.0
var arm_stroke_offset := 0.0

var _cycle_time := 0.0
var _equipped_slots: Dictionary = {}  # slot_name (String) -> bool

var _weapon_swing := WeaponSwing.new()
var _character_sprite := ProceduralCharacterSprite.new()
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

	_arm_left.visible = false
	_arm_right.visible = false
	_head_slot.visible = false
	_tool_slot.visible = false


func _process(delta: float) -> void:
	match movement_state:
		MovementState.WALKING:
			_cycle_time += delta * WALK_CYCLE_SPEED
			leg_swing_offset = sin(_cycle_time) * LEG_SWING_AMPLITUDE
			arm_stroke_offset = 0.0
		MovementState.SWIMMING:
			_cycle_time += delta * SWIM_CYCLE_SPEED
			arm_stroke_offset = sin(_cycle_time) * ARM_STROKE_AMPLITUDE
			leg_swing_offset = 0.0
		_:
			_cycle_time = 0.0
			leg_swing_offset = 0.0
			arm_stroke_offset = 0.0

	_leg_left.visible = movement_state != MovementState.SWIMMING
	_leg_right.visible = movement_state != MovementState.SWIMMING
	_arm_left.visible = movement_state == MovementState.SWIMMING
	_arm_right.visible = movement_state == MovementState.SWIMMING

	_leg_left.position = _leg_left_base_position + Vector2(0, leg_swing_offset)
	_leg_right.position = _leg_right_base_position + Vector2(0, -leg_swing_offset)
	_arm_left.position = _arm_left_base_position + Vector2(0, arm_stroke_offset)
	_arm_right.position = _arm_right_base_position + Vector2(0, -arm_stroke_offset)

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
