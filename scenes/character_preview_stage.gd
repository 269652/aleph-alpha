extends Node2D
class_name CharacterPreviewStage

## The character creator's live preview: the SAME CharacterView the player
## and every NPC use (see VillageRenderer's own doc comment on why -- one
## rig, not a second one that can silently drift out of sync), walking back
## and forth through a small grass patch, swinging its sword, and picking up
## a pebble to throw or kick away -- replacing the old static portrait
## (ProceduralCharacterSprite.generate_hero_portrait_texture) in
## scenes/main_menu.gd. All the actual choreography is pure/tested (see
## CharacterPreviewChoreographer); this script is just per-frame glue that
## reads its state and applies it to real nodes.

const CharacterViewScene = preload("res://scenes/character_view.tscn")
const CharacterView = preload("res://scenes/character_view.gd")
const CharacterPreviewChoreographer = preload("res://src/rendering/character_preview_choreographer.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## The ground line every part of the stage sits on -- CharacterView's own
## origin is already its FEET (see test_the_characters_feet_sit_at_its_own_
## origin in test_character_view.gd), so placing it directly on this line
## needs no extra foot-offset math.
const GROUND_Y := 0.0

## A grass backdrop wide/deep enough to comfortably cover the choreography's
## own WALK_RANGE/PEBBLE_X span (see CharacterPreviewChoreographer) with
## visible margin on every side -- purely a framing choice for this
## decorative stage, not a gameplay-tuned value.
const _GRASS_COLUMNS := 5
const _GRASS_ROWS := 3
## A fixed, arbitrary seed -- deterministic so the preview looks the same
## every time the creator opens, matching every other seeded generator in
## this game (same seed always produces the same result).
const _GRASS_SEED := 4021
const _PEBBLE_SEED := 917

var _choreographer := CharacterPreviewChoreographer.new()
var _character_view: CharacterView
var _pebble: Node2D
var _total_elapsed := 0.0

## A look/weapon requested before this stage entered the tree -- mirrors
## CharacterView's own _pending_appearance pattern exactly (see its _ready).
## main_menu.gd builds the whole create-screen subtree (including this
## stage) detached and attaches it afterward, so apply_appearance/
## equip_weapon can be called before _ready has populated _character_view.
var _pending_appearance: Dictionary = {}
var _pending_weapon_texture: Texture2D = null

## Follows the character horizontally (see _apply_state) rather than holding
## a wide fixed shot -- the choreography's own walk range/pebble trip covers
## more world-space than a small UI preview panel can show at a flattering
## zoom, so the camera tracks the character and the grass scrolls behind it
## instead, the same "diorama with the subject always in frame" treatment a
## small preview needs.
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	_build_grass_backdrop()
	_character_view = CharacterViewScene.instantiate()
	add_child(_character_view)
	_character_view.z_index = 1  # stand in front of the grass tiles

	_pebble = StoneRenderer.new().build_liftable_stone_node(
		_PEBBLE_SEED, CharacterPreviewChoreographer.PEBBLE_DIAMETER_CM
	)
	add_child(_pebble)
	_pebble.z_index = 1

	# Apply the initial pose immediately so the very first rendered frame
	# already shows the character somewhere on the walk cycle, not a default
	# T-pose before _process first runs.
	_apply_state(_choreographer.state_at(0.0, 0))

	# Now that _character_view exists, apply whatever was requested early.
	if not _pending_appearance.is_empty():
		apply_appearance(_pending_appearance)
	if _pending_weapon_texture != null:
		equip_weapon(_pending_weapon_texture)


func _process(delta: float) -> void:
	var prev_elapsed := _total_elapsed
	_total_elapsed += delta
	var loop_duration: float = CharacterPreviewChoreographer.LOOP_DURATION
	var prev_loop := int(prev_elapsed / loop_duration)
	var now_loop := int(_total_elapsed / loop_duration)
	var prev_t := fmod(prev_elapsed, loop_duration)
	var now_t := fmod(_total_elapsed, loop_duration)

	var event: String
	if now_loop != prev_loop:
		# Crossed into a new loop this frame -- check the tail of the old
		# loop and the head of the new one separately so a boundary right at
		# the seam is never missed or double-fired.
		event = _choreographer.event_at(prev_t, loop_duration, prev_loop)
		if event == "":
			event = _choreographer.event_at(0.0, now_t, now_loop)
	else:
		event = _choreographer.event_at(prev_t, now_t, now_loop)

	_apply_state(_choreographer.state_at(now_t, now_loop))
	_handle_event(event)


func _apply_state(state: Dictionary) -> void:
	_character_view.position = Vector2(state.character_x, GROUND_Y)
	_character_view.set_facing(state.facing)
	_character_view.set_movement_state(state.movement_state)
	_character_view.is_moving = state.movement_state == CharacterView.MovementState.WALKING
	_pebble.position = Vector2(state.pebble_position.x, GROUND_Y + state.pebble_position.y)
	_pebble.visible = state.pebble_visible
	_camera.position.x = state.character_x


func _handle_event(event: String) -> void:
	match event:
		"swing":
			# Reuses the choreographer's own SWING phase duration as the
			# swing animation's duration, rather than a second invented
			# number -- the blade's actual swing exactly fills the time the
			# timeline allotted for it.
			_character_view.play_attack_swing(
				_facing_string(_character_view.facing), CharacterPreviewChoreographer.SWING_DURATION
			)
		_:
			pass


## CharacterView.Facing (an enum) -> the facing string play_attack_swing/
## WeaponSwing expect -- mirrors Player._facing_string's own dominant-axis
## mapping (see scenes/player.gd), just off the enum instead of a raw
## direction vector since CharacterView.set_facing has already resolved one.
func _facing_string(facing: int) -> String:
	match facing:
		CharacterView.Facing.RIGHT:
			return "right"
		CharacterView.Facing.LEFT:
			return "left"
		CharacterView.Facing.UP:
			return "up"
		_:
			return "down"


## Dresses the inner CharacterView -- passthrough so main_menu.gd can drive
## this stage exactly like it drove the old static portrait. Callers may
## call this before the stage has entered the tree (see _pending_appearance).
func apply_appearance(appearance: Dictionary) -> void:
	if _character_view == null:
		_pending_appearance = appearance
		return
	_character_view.apply_appearance(appearance)


## Equips the sword shown mid-swing -- passthrough, see apply_appearance.
func equip_weapon(texture: Texture2D) -> void:
	if _character_view == null:
		_pending_weapon_texture = texture
		return
	_character_view.equip_weapon(texture)


func _build_grass_backdrop() -> void:
	var terrain := ProceduralTerrainSprite.new()
	var tile_world_size: float = float(ProceduralTerrainSprite.SIZE) * ArtResolution.SPRITE_SCALE
	var left := -float(_GRASS_COLUMNS) / 2.0 * tile_world_size
	var top := GROUND_Y - float(_GRASS_ROWS - 1) * tile_world_size
	for row in _GRASS_ROWS:
		for col in _GRASS_COLUMNS:
			var tile := Sprite2D.new()
			var variant_seed := _GRASS_SEED + row * _GRASS_COLUMNS + col
			tile.texture = terrain.generate_texture("grassland", variant_seed)
			tile.centered = false
			tile.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
			tile.position = Vector2(left + col * tile_world_size, top + row * tile_world_size)
			tile.z_index = 0
			add_child(tile)
