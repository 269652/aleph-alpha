extends Node2D

## The visible, static marker over one AntColony mound cell (see
## ProceduralAntMoundSprite, docs/concept/soil_fauna.md). Deliberately
## inert -- a mound does not move, flee, or need per-frame behaviour of its
## own (see AntColony's own doc comment on why a mound is a background
## population effect, not an individually-simulated creature): this is
## purely "stand here and be visible", the rendering-only counterpart to a
## data-only AntColony mound cell. AntForagerMarker is the thing that
## actually animates, spawned separately per successful forage.

const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")

const GROUP_NAME := "ant_mound"

static var _sprite_generator := ProceduralAntMoundSprite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = _sprite_generator.generate_texture()
	sprite.scale = Vector2.ONE * ProceduralAntMoundSprite.MOUND_WORLD_SCALE
	add_child(sprite)
