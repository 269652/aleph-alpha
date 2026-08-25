extends Node2D

## The Sägewerk's Lumberjack -- "an NPC moves in" per the user's own framing
## (see docs/concept/timber_construction.md). Deliberately NOT built on the
## full NpcMarker/CreatureMarker AI stack (daily schedules, roaming-wildlife
## sense/perceive/act), the same reasoning DecomposerMarker's own doc
## comment gives for the same choice: a tiny, narrow-behavior actor is the
## wrong shape for that machinery. One LumberjackMarker per placed Sägewerk
## (see EarthChunkManager's _sagewerk_lumberjacks wiring).
##
## SEEKING (find the nearest real standing ChoppableTree within reach) ->
## APPROACHING (walk to it) -> FELLING (the SAME ChoppableTree.take_damage
## loop Player._chop_step already uses -- "an NPC swinging an axe is not a
## separate mechanic, it is the same one with a different caller") ->
## CARRYING (walk the haul back to home) -> DEPOSIT (credit the Sägewerk's
## own log stock) -> back to SEEKING. LumberjackBehavior owns WHEN; this
## owns the actual world effect, mirroring DecomposerMarker's own split.
##
## Deliberately does NOT reuse Player's saw+Carpentry shortcut (saw_up) --
## the Lumberjack fells and buck-cuts into plain "log" items the ordinary
## way, then carries them, per this pass's brief.
##
## Out of scope for this pass (see docs/concept/timber_construction.md's
## Status): CARRY_MATERIAL/PLACE_PIECE -- the Lumberjack does not build
## houses itself.

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralLumberjackSprite = preload("res://src/rendering/procedural_lumberjack_sprite.gd")
const LumberjackBehavior = preload("res://src/gameplay/lumberjack_behavior.gd")
const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const FelledTree = preload("res://src/rendering/felled_tree.gd")
const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

const GROUP_NAME := "lumberjack"

## How far this Lumberjack ranges looking for a tree -- wider than
## DecomposerMarker.SEARCH_RADIUS_PX (an ant smelling carrion): a worker
## deliberately ranges out toward the treeline, not just its own doorstep.
const SEARCH_RADIUS_PX := 250.0
## How close counts as "arrived", at a tree or back home.
const ARRIVE_DISTANCE_PX := 4.0
## How far it wanders from home while no tree is in reach.
const WANDER_RADIUS_PX := 24.0
const WALK_SPEED := 28.0
## Ambient wander is slower than a committed walk to/from a tree -- mirrors
## DecomposerMarker.WANDER_SPEED_FRACTION's own reasoning.
const WANDER_SPEED_FRACTION := 0.35

## Felling damage per swing -- matches Player.BASE_CHOP_DAMAGE: an axe swing
## is an axe swing regardless of who swings it (this doc's own framing).
const FELL_DAMAGE := 5.0

## Where this Lumberjack's Sägewerk stands -- both its wander anchor and
## where it carries logs home to, and where finished beam/plank drop.
var home := Vector2.ZERO

var _behavior := LumberjackBehavior.new()
var _target: Node2D = null

## Local mirror of the tree's own canopy/cuts state (see _step_felling) --
## tracked here rather than read off ChoppableTree's private fields, since
## this Lumberjack is the sole caller driving every swing on its own
## target and already knows the exact sequence ChoppableTree.take_damage
## follows (canopy first, then CUTS_TO_CLEAR buck cuts).
var _canopy_removed_locally := false
var _cuts_left_locally := 0
var _target_growth_scale := 1.0
var _carried_log_count := 0

## The Sägewerk's own stock/shaping progress (see SagewerkProduction) --
## separate from this Lumberjack's own gathering state. Ticked every frame
## this marker exists: the marker's presence itself IS "staffed" (no
## separate hiring system -- see docs/concept/timber_construction.md's NPC
## section, and npc.md's own hiring section stays explicitly out of scope
## here).
var _production_state := {"log_stock": 0.0, "beam_progress": 0.0, "plank_progress": 0.0}
var _production := SagewerkProduction.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	var sprite := Sprite2D.new()
	sprite.texture = ProceduralLumberjackSprite.new().generate_texture()
	add_child(sprite)


## For World's mouse-hover tooltip (see HoverTargetFinder).
func get_display_name() -> String:
	return "Lumberjack"


## No player-facing interaction -- an autonomous worker, not something you
## click on to command (mirrors DecomposerMarker not offering any either).
func get_hover_actions() -> Array:
	return []


func _process(delta: float) -> void:
	_step_production(delta)
	match _behavior.phase:
		LumberjackBehavior.Phase.SEEKING:
			_step_seeking(delta)
		LumberjackBehavior.Phase.APPROACHING:
			_step_approaching(delta)
		LumberjackBehavior.Phase.FELLING:
			_step_felling(delta)
		LumberjackBehavior.Phase.CARRYING:
			_step_carrying(delta)
		LumberjackBehavior.Phase.DEPOSIT:
			_step_deposit(delta)


## The Sägewerk's own production, independent of what phase its Lumberjack
## is currently in -- a real mill keeps shaping stock it already has even
## while its worker is out felling the next tree.
func _step_production(delta: float) -> void:
	var result: Dictionary = _production.advance(_production_state, delta, true)
	_production_state = result
	var beam_output: int = result.get("beam_output", 0)
	var plank_output: int = result.get("plank_output", 0)
	if beam_output > 0:
		WorldItemBus.item_dropped.emit(
			ItemStack.new(Item.new("beam", "Beam", "material", 20), beam_output), home
		)
	if plank_output > 0:
		WorldItemBus.item_dropped.emit(
			ItemStack.new(Item.new("plank", "Plank", "material", 20), plank_output), home + Vector2(8, 4)
		)


func _step_seeking(delta: float) -> void:
	var to_home := home - position
	if to_home.length() > WANDER_RADIUS_PX:
		position += to_home.normalized() * WALK_SPEED * WANDER_SPEED_FRACTION * delta
	_behavior.advance(delta)  # no-op outside FELLING/DEPOSIT, just ticks the rehunt clock
	if _behavior.can_commit():
		var found := _nearest_standing_tree()
		if found != null:
			_target = found
			_canopy_removed_locally = false
			_cuts_left_locally = 0
			_carried_log_count = 0
			_behavior.begin_approach()


## Nearest live, still-standing ChoppableTree within SEARCH_RADIUS_PX, or
## null. Standing-only: a tree someone else already felled is that worker's
## to finish (multiple Lumberjacks competing for one trunk is an explicitly
## out-of-scope edge case for this single-worker-per-Sägewerk pass).
func _nearest_standing_tree() -> Node2D:
	var best: Node2D = null
	var best_distance := SEARCH_RADIUS_PX
	for node in get_tree().get_nodes_in_group(ChoppableTree.GROUP_NAME):
		if node.is_felled():
			continue
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
		_target_growth_scale = _target.growth_scale
		_behavior.arrive()
		return
	position += to_target.normalized() * WALK_SPEED * delta


## Swings at the tree exactly like Player._chop_step does -- the same
## take_damage() loop, staged the same way (fell, then canopy off, then
## CUTS_TO_CLEAR buck cuts). Tracks its own local canopy/cuts mirror (see
## the field doc comment above) to know when a swing bucks a real log off,
## crediting FelledTree.logs_per_cut for that cut, and to know when the
## trunk is fully worked up so it can start carrying the haul home.
func _step_felling(delta: float) -> void:
	if not _target_still_here():
		_target = null
		_behavior.abort()
		return
	if not _behavior.advance(delta):
		return  # swing not ready yet this tick

	if not _target.is_felled():
		_target.take_damage(FELL_DAMAGE)
		return

	if not _canopy_removed_locally:
		_canopy_removed_locally = true
		_cuts_left_locally = FelledTree.CUTS_TO_CLEAR
		_target.take_damage(FELL_DAMAGE)  # removes the canopy, no log yet
		return

	_carried_log_count += FelledTree.logs_per_cut(_target_growth_scale)
	_cuts_left_locally -= 1
	_target.take_damage(FELL_DAMAGE)  # bucks one length off the bare trunk
	if _cuts_left_locally <= 0:
		_target = null
		_behavior.start_carry()


func _step_carrying(delta: float) -> void:
	var to_home := home - position
	if to_home.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive_home()
		return
	position += to_home.normalized() * WALK_SPEED * delta


func _step_deposit(delta: float) -> void:
	if _behavior.advance_deposit(delta):
		var log_stock: float = _production_state.get("log_stock", 0.0)
		_production_state["log_stock"] = log_stock + float(_carried_log_count)
		_carried_log_count = 0
		_behavior.finish_deposit()


## Whether _target is a real, not-yet-consumed thing still worth working --
## queue_free()'d nodes stay "valid" until the next frame boundary (see
## DecomposerMarker's own identical doc comment), so is_queued_for_deletion
## is checked directly.
func _target_still_here() -> bool:
	return (
		_target != null
		and is_instance_valid(_target)
		and not _target.is_queued_for_deletion()
	)
