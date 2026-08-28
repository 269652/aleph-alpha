extends Sprite2D

## A netted flyer bonded via Beastmaster's `menagerie` keystone (see
## docs/concept/taming.md's "A bond, not an order: the Kinship path" and
## pets.md's "Birds, butterflies, bees: decorative"). Deliberately NOT a
## CreatureMarker: no trust/order/struggle state, because a netted flyer
## never had an order AI to learn Follow/Stay in the first place -- it
## forages, courts and ages exactly as it did in the wild, and simply
## travels loosely with the player besides. It is also never tied to
## anything, since a bonded companion is never left behind the way a led
## animal can be.
##
## Movement reuses CreatureMovementGate -- the same "walk around a tree
## rather than through it" obstacle-avoidance a led animal already gets --
## rather than a naive straight-line follow, but with no rope/anchor/tie
## state: Player pushes a loose `follow_target` in every frame (see
## Player._step_bonded_companions), and this node's own _process steps
## toward it.

const CreatureMovementGate = preload("res://src/gameplay/creature_movement_gate.gd")

const GROUP_NAME := "bonded_companion"

## Which species this companion is (an AmbientFlyerRenderer species id, e.g.
## "sparrow" or "monarch" -- see CaptureTool.is_ambient_flyer_species). Purely
## descriptive here: this node has no anatomy/diet/behaviour of its own.
var species := "sparrow"
var wander_seed := 0
## Where the player wants this companion to be, pushed in every frame by the
## owner rather than held as a node reference -- the same "never outlives a
## dangling holder" reason CreatureMarker.follow_target/`_rope_anchor` are.
var follow_target := Vector2.ZERO

## How fast a bonded companion catches up to its follow target. Slower than
## Player.BASE_SPEED (80.0) -- see test_follow_speed_is_slower_than_the_
## players_own_pace -- a "loosely trails" companion (taming.md's own
## wording) that matched or exceeded the player's pace would instead read
## as glued to them.
const FOLLOW_SPEED := 60.0
## Once within this distance of its target, a companion stops rather than
## endlessly micro-adjusting -- the same idea as a led animal being held AT
## rope length rather than exactly on top of the anchor.
const ARRIVAL_RADIUS := 6.0
const MOVEMENT_LOOKAHEAD := 24.0
const SENSE_RADIUS := 48.0
const BLOCKER_SCAN_RADIUS := 96.0

## Duck-typed world (see CreatureMarker._blockers_near): the chunk manager,
## queried for solid_obstacles_near, or null for a worldless/stub setup, in
## which case this companion just walks straight at its target.
var _world = null
var _last_gated_heading := Vector2.ZERO


func setup(world, _tile_size: int) -> void:
	add_to_group(GROUP_NAME)
	_world = world


func _process(delta: float) -> void:
	step(delta)


## The actual follow logic, split out from _process so tests (which do not
## run a live SceneTree frame loop) can call it directly -- the same split
## test_player.gd's own `horse._process(delta)` calls already rely on.
func step(delta: float) -> void:
	var to_target := follow_target - position
	if to_target.length() <= ARRIVAL_RADIUS:
		return
	var desired := to_target.normalized()
	var blockers := _blockers_near(BLOCKER_SCAN_RADIUS)
	var heading := desired
	if not blockers.is_empty():
		heading = CreatureMovementGate.clear_direction(
			position, desired, MOVEMENT_LOOKAHEAD, blockers, [], SENSE_RADIUS,
			_last_gated_heading
		)
	_last_gated_heading = heading
	if heading == Vector2.ZERO:
		return
	position += heading * FOLLOW_SPEED * delta


## Nearby solid props as plain {position, radius} data for
## CreatureMovementGate -- mirrors CreatureMarker._blockers_near, minus its
## throttled-sensing-tick cache (a handful of capped companions makes a
## fresh query each frame cheap, unlike the whole creature population).
func _blockers_near(radius: float) -> Array:
	if _world != null and _world.has_method("solid_obstacles_near"):
		return _world.solid_obstacles_near(position, radius)
	return []
