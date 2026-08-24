extends Node2D

## Offal spilled from a butchered carcass -- see docs/concept/carrion.md. A
## real world entity, deliberately NOT an inventory item: a player doesn't
## carry or eat guts, but a scavenger/decomposer does (see take_bite, the
## same contract Carcass itself exposes so a decomposer doesn't need to
## distinguish "carcass" from "guts", only "something here is carrion").

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralGutsSprite = preload("res://src/rendering/procedural_guts_sprite.gd")

const GROUP_NAME := "carcass_guts"

## Real offal spoils within about a day even in cool conditions -- much
## faster than a carcass's own hide/bones. Kept on the same "observable
## within an ordinary play session" timescale as Carcass.ROT_SECONDS (see
## that constant's own doc comment for why this deliberately does NOT
## follow FruitSpoilage's real-day compression), just shorter again --
## guts are the first thing to go on a real kill.
const ROT_SECONDS := 60.0

## How much decomposer "bite" it takes to fully consume a guts pile.
const CONSUME_HEALTH := 10.0

var _age := 0.0
var _health := CONSUME_HEALTH


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = ProceduralGutsSprite.new().generate_texture()
	add_child(sprite)


func _process(delta: float) -> void:
	_age += delta
	if _age >= ROT_SECONDS:
		queue_free()


## A decomposer's bite. Unlike Carcass.take_bite, guts are always
## immediately edible -- exposed viscera don't need time to become
## accessible the way a hide-and-bone carcass does. Always returns true.
func take_bite(amount: float) -> bool:
	_health = maxf(0.0, _health - amount)
	if _health <= 0.0:
		queue_free()
	return true


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	return "Guts"


## For World's mouse-hover tooltip (see HoverTargetFinder). Nothing for the
## PLAYER to do with guts directly -- scavenger food only.
func get_hover_actions() -> Array:
	return []
