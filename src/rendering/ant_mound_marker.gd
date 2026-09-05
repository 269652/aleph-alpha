extends Node2D

## The visible, static marker over one AntColony mound cell (see
## ProceduralAntMoundSprite/IllustratedAntMoundSprite, docs/concept/
## soil_fauna.md). Deliberately inert -- a mound does not move, flee, or
## need per-frame behaviour of its own (see AntColony's own doc comment on
## why a mound is a background population effect, not an individually-
## simulated creature): this is purely "stand here and be visible", the
## rendering-only counterpart to a data-only AntColony mound cell.
## AntForagerMarker is the thing that actually animates, spawned separately
## per successful forage.

const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
const IllustratedAntMoundSprite = preload("res://src/rendering/illustrated_ant_mound_sprite.gd")

const GROUP_NAME := "ant_mound"

## Which of the illustrated sheet's variants this mound picks (see
## IllustratedAntMoundSprite.frame_for) -- ignored on the procedural
## fallback, which has no per-instance variation at all. Set before
## add_child, same convention as every other marker's per-instance fields
## (e.g. DecomposerMarker.wander_seed).
var mound_seed := 0

static var _procedural_generator := ProceduralAntMoundSprite.new()
static var _illustrated_generator := IllustratedAntMoundSprite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	if _illustrated_generator.has_variants():
		sprite.texture = _illustrated_generator.frame_for(mound_seed)
		sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale()
	else:
		sprite.texture = _procedural_generator.generate_texture()
		sprite.scale = Vector2.ONE * ProceduralAntMoundSprite.MOUND_WORLD_SCALE
	add_child(sprite)
