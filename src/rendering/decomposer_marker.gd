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
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")

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

## Anthrax-like carry vector (docs/concept/disease.md's CARRION archetype):
## real blowflies/carrion beetles mechanically carry spores from an infected
## carcass to the next one they feed on -- this decomposer IS that insect
## (see carrion.md), so it carries the disease rather than a separate vector
## being invented. Picked up feeding on a Carcass whose `contaminated` is
## true (see _step_disease_carry); passed on to the next clean Carcass fed
## on afterward. CarcassGuts is not part of this loop -- disease.md scopes
## the anthrax archetype to carcasses/patches, not offal.
var carrying_disease := false
var _disease_model := DiseaseModel.new()
var _disease_roll_count := 0

var _behavior := CarrionForageBehavior.new()
var _target: Node2D = null


func _ready() -> void:
	add_to_group(GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = ProceduralDecomposerSprite.new().generate_texture(species)
	add_child(sprite)


var _lod_accumulated := 0.0

## Distance-based update rate (see SimulationLod) -- mirrors CreatureMarker/
## AmbientFlyerMarker's own _lod_step exactly. Without this, the SEEKING
## phase's _nearest_carrion group scan (see _step_seeking) ran completely
## unthrottled: every ant/bug in the loaded world re-scanned the whole
## Carcass/CarcassGuts groups every single frame, however far from the
## player it was and however long it had already been since anything nearby
## changed. Returns the time to advance by, or NEGATIVE when this frame
## should be skipped entirely.
##
## Negative rather than zero as the skip signal, because zero is a
## legitimate step -- see CreatureMarker._lod_step's own doc comment.
##
## The accumulated time is handed to the update when it does run, so a
## skipped frame is never LOST time -- a decomposer far from the player
## lives at exactly the same rate, it just does so in fewer, larger steps
## that nobody is close enough to see.
func _lod_step(delta: float) -> float:
	_lod_accumulated += delta
	var player = _nearest_player_position()
	if player == null:
		return _take_lod_step()  # nobody to be far from: always full rate
	var interval := SimulationLod.update_interval(position.distance_to(player))
	if _lod_accumulated < interval:
		return -1.0
	return _take_lod_step()


func _take_lod_step() -> float:
	var step := _lod_accumulated
	_lod_accumulated = 0.0
	return step


## Cheap: the player group holds one node in solo play. Cached per frame by
## the caller rather than scanned per creature would be better still, but
## this is already off the hot path for everything nearby.
func _nearest_player_position():
	# Not in the tree (a marker built standalone in a test) means there is no
	# player to measure against, so it runs at full rate.
	if not is_inside_tree():
		return null
	if _cached_player == null or not is_instance_valid(_cached_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return null
		_cached_player = players[0]
	return _cached_player.position


var _cached_player: Node = null


func _process(frame_delta: float) -> void:
	# Decomposers far from the player advance in fewer, larger steps (see
	# SimulationLod) -- same time passes, fewer scans to pay for.
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
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


## Nearest (by EFFECTIVE, not raw, distance) live Carcass or CarcassGuts
## within SEARCH_RADIUS_PX, or null. Both groups are checked indiscriminately
## -- a decomposer at a carcass doesn't care whether the offal is still
## attached or lying beside it. A carcass already carrying flies (see
## Carcass.fly_count) reads as closer than its real distance
## (CarrionForageBehavior.effective_distance) -- real scavengers cue off
## circling flies as a sign something worth investigating is there, so a
## fly-blown carcass can out-compete a nearer, fresh one, and can even be
## noticed a little past the ordinary search radius. CarcassGuts has no
## fly_count (disease.md/carrion.md both scope the fly loop to carcasses,
## not offal) and so is always scored at its real distance.
func _nearest_carrion() -> Node2D:
	var best: Node2D = null
	var best_effective_distance := SEARCH_RADIUS_PX
	for group_name in [Carcass.GROUP_NAME, CarcassGuts.GROUP_NAME]:
		for node in get_tree().get_nodes_in_group(group_name):
			var distance: float = position.distance_to(node.position)
			var fly_count: int = node.fly_count() if node.has_method("fly_count") else 0
			var effective := CarrionForageBehavior.effective_distance(distance, fly_count)
			if effective <= best_effective_distance:
				best = node
				best_effective_distance = effective
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
		_step_disease_carry()
		if not _target_still_here():
			_target = null
			_behavior.abort()


## One bite's worth of anthrax-like carry (see carrying_disease's own doc
## comment): a not-yet-carrying decomposer biting a contaminated Carcass may
## pick it up; an already-carrying decomposer biting a CLEAN Carcass may
## contaminate it in turn. Region pressure reads the CARCASS's own
## region_tier (see Carcass.region_tier) rather than adding a second copy of
## that field onto every decomposer -- the carcass being fed on is already
## the one real source of truth for "how dangerous is this spot".
func _step_disease_carry() -> void:
	if not (_target is Carcass):
		return
	var target_carcass: Carcass = _target
	_disease_roll_count += 1
	var seed_value := hash("%d_%d_decomposer_carry" % [wander_seed, _disease_roll_count])
	if target_carcass.contaminated and not carrying_disease:
		var chance := _disease_model.decomposer_carry_chance(target_carcass.region_tier)
		carrying_disease = _disease_model.attempt_transmit(chance, seed_value)
	elif carrying_disease and not target_carcass.contaminated:
		target_carcass.contaminated = true


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
