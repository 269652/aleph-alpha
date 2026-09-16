extends Node2D

## The house's own villager, standing in their room while they are home
## (docs/concept/building.md "Residents inside") -- built fresh per visit
## by HouseInteriorView.place_resident (never the outdoor NpcMarker
## reparented: that node stays where the schedules, economy and every
## outdoor scan expect it), dressed exactly the way VillageRenderer
## dresses them outdoors (HeroAppearance for their occupation + identity
## seed, so it IS the same person), facing the door, idle, and solid on
## the room's collision layer so the player walks around them rather than
## through. No preload of HouseInteriorView here on purpose: the view
## preloads this script, and a preload back would be a cycle (the same
## reason InteriorAvatar is referenced bare as a global class, never
## preloaded) -- so the layer is handed in by the room instead.

const CharacterViewScene = preload("res://scenes/character_view.tscn")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

## Same order as InteriorAvatar.RADIUS -- the two occupants of a room are
## the same size, so neither can slip through the other.
const RADIUS := 6.0

var identity: NpcIdentity
var _character_view: CharacterView


## Dresses and stands the villager -- call after add_child (CharacterView's
## parts are @onready, the same ordering VillageRenderer._build_npc keeps).
## `collision_layer_bits`: the room's own layer (HouseInteriorView.
## INTERIOR_COLLISION_LAYER), the one the interior avatar's mask reads.
func present(npc_identity: NpcIdentity, collision_layer_bits: int) -> void:
	identity = npc_identity
	_character_view = CharacterViewScene.instantiate()
	add_child(_character_view)
	_character_view.apply_appearance(HeroAppearance.new().appearance_for(identity.occupation, identity.seed_value))
	_character_view.set_facing(Vector2.DOWN)
	_character_view.is_moving = false
	_character_view.set_movement_state(CharacterView.MovementState.IDLE)

	var body := StaticBody2D.new()
	body.collision_layer = collision_layer_bits
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	body.add_child(shape)
	add_child(body)


func character_view() -> CharacterView:
	return _character_view
