extends CharacterBody2D
class_name InteriorAvatar

## The player's own local, non-networked stand-in while indoors (see
## HouseInteriorView's own doc comment, World._build_interior_view). The
## real Player node never moves or renders while indoors -- it stays
## parked outdoors at the real doorstep the whole visit, keeping chunk
## streaming/NPC schedules anchored exactly where they already were (see
## docs/concept/building.md "Entering"). This is what actually walks
## around inside the isolated interior SubViewport, colliding with
## HouseInteriorView's own real wall/furniture/threshold bodies on
## INTERIOR_COLLISION_LAYER. Reads input directly rather than going
## through Player's whole authority/proxy/RPC machinery: it only ever
## exists locally, for the one person currently standing in their own
## house, so none of that applies.
##
## Renders the player's REAL CharacterView -- the same rig, dressed with
## the same appearance, worn armor and held weapon (see dress) -- fed as
## plain data from Player._interior_outfit, so it is the same person and
## not a re-roll (reported live: "it's just a square"). Drives that view
## from its own movement exactly the way Player._update_character_view
## does outdoors, minus water (no water inside a house).

const HouseInteriorView = preload("res://src/rendering/house_interior_view.gd")
const CharacterViewScene = preload("res://scenes/character_view.tscn")
const TileTargeting = preload("res://src/gameplay/tile_targeting.gd")

const RADIUS := 6.0

## The last direction actually walked (never zeroed at rest -- Player.
## _last_facing_direction's own rule), what facing_cell reads. Down to
## start: a freshly entered avatar stands just inside the door facing into
## the room.
var last_facing_direction := Vector2.DOWN
var _tile_targeting := TileTargeting.new()

## Player.BASE_SPEED is the outdoor walking speed -- reused rather than a
## second, separately-tuned number, so indoor movement doesn't feel like a
## different game. Player is a global class_name (scenes/player.gd), so
## this reads it directly rather than preloading that script by path --
## Player itself references InteriorAvatar the same way, and an explicit
## two-way preload between the two would be a real circular-preload risk.
const SPEED := Player.BASE_SPEED

var _character_view: CharacterView
## What dress() was handed before this node entered the tree, applied in
## _ready -- CharacterView.equip_weapon/equip_armor_slot write straight to
## @onready slots (see character_preview_diorama.gd's _equip_starting_
## weapon doc comment on the crash that causes), so an outfit handed over
## early has to wait for the rig to be ready. Null once applied.
var _pending_outfit: Dictionary = {}


func _ready() -> void:
	collision_layer = 0
	collision_mask = HouseInteriorView.INTERIOR_COLLISION_LAYER

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

	# The same rig at the same local origin scenes/player.tscn itself uses
	# (its CharacterView sits at (0,0) under the body), so the character
	# stands on the collision circle exactly as outdoors.
	_character_view = CharacterViewScene.instantiate()
	_character_view.z_index = HouseInteriorView.INTERIOR_OCCUPANT_Z_INDEX
	add_child(_character_view)

	if not _pending_outfit.is_empty():
		_apply_outfit(_pending_outfit)
		_pending_outfit = {}


func character_view() -> CharacterView:
	return _character_view


## Dresses the avatar as a real character: `appearance` is a CharacterView
## appearance dict (Player.appearance / HeroAppearance.appearance_for),
## `armor_textures` maps a worn slot name ("head"/"chest"/"legs"/"feet",
## Equipment.SLOTS minus "weapon") to its item texture -- only the slots
## actually worn, a bare slot is simply absent -- and `weapon_texture` is
## the held weapon's texture or null for empty hands. Pure data, no Player
## dependency, so a test can dress one without a Player at all. Safe to
## call before add_child: applied once _ready has built the rig.
func dress(appearance: Dictionary, armor_textures: Dictionary, weapon_texture: Texture2D) -> void:
	var outfit := {
		"appearance": appearance, "armor_textures": armor_textures, "weapon_texture": weapon_texture,
	}
	if _character_view == null:
		_pending_outfit = outfit
		return
	_apply_outfit(outfit)


func _apply_outfit(outfit: Dictionary) -> void:
	# An empty appearance (a Player that never had apply_class run, e.g. a
	# bare test fixture) keeps the rig's own default look -- exactly what
	# the outdoor rig shows in that same state -- rather than crashing
	# inside CharacterView._apply_head on a missing key.
	var appearance: Dictionary = outfit["appearance"]
	if not appearance.is_empty():
		_character_view.apply_appearance(appearance)
	var armor_textures: Dictionary = outfit["armor_textures"]
	for slot in armor_textures:
		_character_view.equip_armor_slot(slot, armor_textures[slot])
	var weapon_texture: Texture2D = outfit["weapon_texture"]
	if weapon_texture != null:
		_character_view.equip_weapon(weapon_texture)


func _physics_process(_delta: float) -> void:
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_direction * SPEED
	move_and_slide()

	# Player._update_character_view's own rules, minus water: set_facing
	# keeps the last facing on idle by itself.
	_character_view.set_facing(input_direction)
	var moving := input_direction.length() > 0.01
	if moving:
		last_facing_direction = input_direction
	_character_view.is_moving = moving
	_character_view.set_movement_state(
		CharacterView.MovementState.WALKING if moving else CharacterView.MovementState.IDLE
	)


## The interior cell a decorate verb targets (docs/concept/housing.md
## "Decorating an entered interior"): one cell from the avatar's own cell
## along the dominant axis of last_facing_direction -- TileTargeting's
## rule, the same one the outdoor build/destroy verbs use, in the room's
## own local cells.
func facing_cell(tile_size: int) -> Vector2i:
	var cell := Vector2i(floori(position.x / tile_size), floori(position.y / tile_size))
	return _tile_targeting.facing_tile(cell, last_facing_direction)
