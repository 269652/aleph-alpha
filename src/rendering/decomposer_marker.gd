extends Node2D

## An ant or carrion bug -- the decomposer tier that finishes what a
## player's own butchering doesn't (see docs/concept/carrion.md). Deliberately
## NOT built on CreatureMarker/CreatureInfo -- that stack is a full roaming-
## wildlife AI (flee/fight/hunt/graze/mate/ecosystem population tracking),
## the wrong shape for a tiny insect whose entire behaviour is "find carrion,
## eat it, wander otherwise". Mirrors AmbientFlyerMarker instead
## (home-anchored ambient wander, no ecosystem population math).
##
## Scans the Carcass/CarcassGuts groups directly (the same
## get_tree().get_nodes_in_group shape Player's own melee-sweep steps
## already use) rather than needing an injected "world" -- there's nothing
## chunk-specific about "is there carrion nearby" the way there is for
## e.g. worms, which live in a per-chunk sim.

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const CarrionForageBehavior = preload("res://src/gameplay/carrion_forage_behavior.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const CarcassGuts = preload("res://src/rendering/carcass_guts.gd")

const GROUP_NAME := "decomposer"

## How far this decomposer can notice carrion -- short, an ant doesn't smell
## a carcass across the whole chunk.
const SEARCH_RADIUS_PX := 60.0
## How close counts as "arrived".
const ARRIVE_DISTANCE_PX := 4.0
## How far it wanders from home while nothing is around to eat.
const WANDER_RADIUS_PX := 24.0
const WALK_SPEED := 24.0
## Ambient wander is slower than a committed approach -- a hurrying insect
## reads as one that has actually found something.
const WANDER_SPEED_FRACTION := 0.35
## How much decompose/consume health one bite removes -- see
## Carcass.DECOMPOSE_HEALTH / CarcassGuts.CONSUME_HEALTH.
const BITE_AMOUNT := 1.0

## "ant" or "bug" -- which sprite/silhouette this decomposer draws (see
## ProceduralDecomposerSprite). Set before add_child, same convention as
## every other marker in this codebase.
var species := "ant"
var home := Vector2.ZERO
var wander_seed := 0

var _behavior := CarrionForageBehavior.new()
var _target: Node2D = null


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = ProceduralDecomposerSprite.new().generate_texture(species)
	add_child(sprite)


func _process(delta: float) -> void:
	match _behavior.phase:
		CarrionForageBehavior.Phase.SEEKING:
			_step_seeking(delta)
		CarrionForageBehavior.Phase.APPROACHING:
			_step_approaching(delta)
		CarrionForageBehavior.Phase.FEEDING:
			_step_feeding(delta)


func _step_seeking(delta: float) -> void:
	var to_home := home - position
	if to_home.length() > WANDER_RADIUS_PX:
		position += to_home.normalized() * WALK_SPEED * WANDER_SPEED_FRACTION * delta
	_behavior.advance(delta)  # no-op outside FEEDING, just ticks the rehunt clock
	if _behavior.can_commit():
		var found := _nearest_carrion()
		if found != null:
			_target = found
			_behavior.begin_approach()


## Nearest live Carcass or CarcassGuts within SEARCH_RADIUS_PX, or null.
## Both groups are checked indiscriminately -- a decomposer at a carcass
## doesn't care whether the offal is still attached or lying beside it.
func _nearest_carrion() -> Node2D:
	var best: Node2D = null
	var best_distance := SEARCH_RADIUS_PX
	for group_name in [Carcass.GROUP_NAME, CarcassGuts.GROUP_NAME]:
		for node in get_tree().get_nodes_in_group(group_name):
			var distance: float = position.distance_to(node.position)
			if distance <= best_distance:
				best = node
				best_distance = distance
	return best


func _step_approaching(delta: float) -> void:
	if not _target_still_here():
		_target = null
		_behavior.abort()
		return
	var to_target: Vector2 = _target.position - position
	if to_target.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive()
		return
	position += to_target.normalized() * WALK_SPEED * delta


func _step_feeding(delta: float) -> void:
	if not _target_still_here():
		_target = null
		_behavior.abort()
		return
	if _behavior.advance(delta):
		_target.take_bite(BITE_AMOUNT)
		if not _target_still_here():
			_target = null
			_behavior.abort()


## Whether _target is a real, not-yet-consumed thing still worth working --
## queue_free()'d nodes stay "valid" until the next frame boundary, so
## is_queued_for_deletion() is checked directly rather than relying on
## is_instance_valid() alone to catch a target consumed this same tick.
func _target_still_here() -> bool:
	return (
		_target != null
		and is_instance_valid(_target)
		and not _target.is_queued_for_deletion()
	)
