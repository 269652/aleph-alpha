extends Node2D

## A purely decorative, one-shot visual: an ant walking a fixed path (mound
## -> harvested item's last position -> cache/plant target), spawned right
## after AntColony's own instant, data-level forage-and-cache resolution
## already happened (see EarthChunkManager._forage_seed_near_mound/
## _forage_windfall_near_mound) -- so the actual game-state effect (a real
## grass seed taken and re-planted, or a real fallen nut eaten) is already
## correct and already fully tested independently of this marker. This
## exists ONLY so a player can actually SEE that happen, instead of it
## resolving invisibly in the background the way it always has (see
## AntColony's own doc comment on why the underlying resolution is
## deliberately instant, not something this marker changes or depends on).
##
## Reuses ProceduralDecomposerSprite's "ant" silhouette -- the same tiny ant
## every decomposer already draws -- rather than a new, separate design: a
## colony's own forager is exactly the same kind of animal DecomposerMarker
## already renders, just walking a deliberate path instead of ambient
## wander.

const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

const GROUP_NAME := "ant_forager"

## Same walking speed as every other decomposer -- a colony's own forager is
## the identical animal, not a faster/slower special case.
const WALK_SPEED := 24.0
## How close counts as "arrived at this waypoint" -- mirrors
## DecomposerMarker.ARRIVE_DISTANCE_PX exactly, the same tiny-insect arrival
## tolerance.
const ARRIVE_DISTANCE_PX := 4.0

## mound position -> harvested item's position -> cache/plant target, in
## that order (index 0 is where this marker is spawned, already equal to
## `position`; walking starts toward index 1). Set before add_child, same
## convention as every other marker's per-instance fields.
var path: Array = []

var _waypoint_index := 1

static var _sprite_generator := ProceduralDecomposerSprite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = _sprite_generator.generate_texture("ant")
	sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	add_child(sprite)


func _process(delta: float) -> void:
	if _waypoint_index >= path.size():
		queue_free()
		return
	var target: Vector2 = path[_waypoint_index]
	if position.distance_to(target) <= ARRIVE_DISTANCE_PX:
		_waypoint_index += 1
		if _waypoint_index >= path.size():
			queue_free()
		return
	# move_toward, not += direction * speed * delta -- the exact
	# overshoot-and-orbit-forever bug DecomposerMarker._step_approaching hit
	# this same session (a short leg + one big step overshoots past the
	# waypoint, then overshoots back, forever), avoided here from the start
	# rather than re-earned the same way.
	position = position.move_toward(target, WALK_SPEED * delta)
