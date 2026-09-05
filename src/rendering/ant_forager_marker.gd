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
## Uses IllustratedDecomposerSprite's real "ant" art where it exists
## (checked first, same has_X()-gated fallback convention every optional
## illustrated-art seam in this codebase uses), falling back to
## ProceduralDecomposerSprite's silhouette otherwise -- either way, the
## same tiny ant every decomposer draws, not a new, separate design: a
## colony's own forager is exactly the same kind of animal DecomposerMarker
## already renders, just walking a deliberate path instead of ambient
## wander. A single held pose per leg, not an animated walk cycle -- this
## marker is short-lived and purely decorative (see the class doc comment),
## so DecomposerMarker is where the walk cycle's frame-stepping actually
## earns its keep.

const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const IllustratedDecomposerSprite = preload("res://src/rendering/illustrated_decomposer_sprite.gd")
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
var _sprite: Sprite2D
## Which leg the sprite is currently drawn for -- so _update_sprite only
## touches the texture/scale when the leg actually changes, not every
## frame (the frame array lookups are cheap/cached, but there's no reason
## to redo them 60 times a second for a value that only ever changes once
## per forager's whole lifetime).
var _carrying := false

static var _procedural_generator := ProceduralDecomposerSprite.new()
static var _illustrated_generator := IllustratedDecomposerSprite.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_update_sprite()


## Empty-handed (walking to the pickup) before waypoint 1 is reached,
## carrying (walking to the cache) after -- see the class doc comment on
## ant.png's own carry row existing exactly for this leg.
func _update_sprite() -> void:
	var carrying := _waypoint_index >= 2
	if carrying == _carrying and _sprite.texture != null:
		return
	_carrying = carrying
	var action := "carry" if carrying else "walk"
	if _illustrated_generator.has_action("ant", action):
		_sprite.texture = _illustrated_generator.generate_textures("ant", action)[0]
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale("ant", action)
		# Both sheets face left (IllustratedDecomposerSprite.faces_left) --
		# this marker walks purely along the path's own geometry with no
		# other facing logic, so mirror only when actually heading right.
		if _waypoint_index < path.size():
			var to_target: Vector2 = path[_waypoint_index] - position
			if absf(to_target.x) > 0.01:
				_sprite.flip_h = to_target.x > 0.0
	else:
		_sprite.texture = _procedural_generator.generate_texture("ant")
		_sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
		_sprite.flip_h = false


func _process(delta: float) -> void:
	if _waypoint_index >= path.size():
		queue_free()
		return
	var target: Vector2 = path[_waypoint_index]
	if position.distance_to(target) <= ARRIVE_DISTANCE_PX:
		_waypoint_index += 1
		_update_sprite()
		if _waypoint_index >= path.size():
			queue_free()
		return
	# move_toward, not += direction * speed * delta -- the exact
	# overshoot-and-orbit-forever bug DecomposerMarker._step_approaching hit
	# this same session (a short leg + one big step overshoots past the
	# waypoint, then overshoots back, forever), avoided here from the start
	# rather than re-earned the same way.
	position = position.move_toward(target, WALK_SPEED * delta)
