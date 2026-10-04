extends Node2D

## A real, homing projectile (docs/concept/spell_runtime.md, "Projectile
## flight: a cast that truly homes"). Unlike SpellEffectMarker (purely
## cosmetic grow/hold/fade glue over a cast that has already resolved), this
## node drives real gameplay resolution: WHO a projectile-delivery cast's
## effect lands on is decided HERE, on arrival, not at cast time. Player
## spawns one per pipeline atom, points it at a target (or a fixed aim
## point, for a cast that already missed at launch), and hands it a
## callback to run once it actually gets there.

const SpellProjectileFlight = preload("res://src/gameplay/spell_projectile_flight.gd")

## Shared across every bolt, the same reasoning SpellEffectMarker's own
## static generators use: the flight math is a pure function of its inputs.
static var _flight := SpellProjectileFlight.new()

## The instance id of the creature/player this bolt is homing on, or 0 for
## one aimed at a fixed point. Re-validated via instance_from_id/
## is_instance_valid every frame rather than held as a direct reference --
## the exact pattern CreatureMarker._windup_target_id already establishes
## for "a target can legitimately be freed before the thing committed to it
## resolves."
var _target_id := 0

## Where this bolt is actually headed this frame: the target's live
## position while it is still valid, frozen at its last known position the
## instant validity is lost. A dead/despawned target is a miss at wherever
## it last really was, never a retarget (see the concept doc).
var _aim_point: Vector2

var _delay_remaining := 0.0
var _resolved := false
var _on_arrival: Callable


## Homes on `target`'s live position every frame until it arrives.
func aim_at_target(target: Node2D) -> void:
	_target_id = target.get_instance_id()
	_aim_point = target.position


## Flies straight at a fixed point -- a cast that had nothing to target
## still throws something, per the concept doc's "a miss still flies" rule.
func aim_at_point(point: Vector2) -> void:
	_target_id = 0
	_aim_point = point


## `start_delay` mirrors `_spawn_spell_effect`'s own chain-stagger: a
## multi-atom pipeline's later bolts leave a beat after the earlier ones
## rather than every atom launching in the same frame.
func launch(on_arrival: Callable, start_delay: float = 0.0) -> void:
	_delay_remaining = start_delay
	_on_arrival = on_arrival


func is_in_flight() -> bool:
	return not _resolved


func _process(delta: float) -> void:
	if _resolved:
		return
	if _delay_remaining > 0.0:
		_delay_remaining -= delta
		return
	var live_target := _live_target()
	if live_target != null:
		_aim_point = live_target.position
	position = _flight.position_after(position, _aim_point, delta)
	if _flight.has_arrived(position, _aim_point):
		_resolve(live_target)


func _live_target() -> Node:
	if _target_id == 0:
		return null
	var node := instance_from_id(_target_id)
	if node == null or not is_instance_valid(node):
		return null
	return node


func _resolve(live_target: Node) -> void:
	_resolved = true
	if _on_arrival.is_valid():
		_on_arrival.call(live_target, position)
	queue_free()
