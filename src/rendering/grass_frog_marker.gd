extends Node2D

## A grass frog -- part of the seasonal-behavior epic's phase 10
## (docs/concept/seasonal_behavior.md): brand new to the game, built from
## art that had zero code references before this. Mirrors CaterpillarMarker's
## own shape closely: deliberately NOT built on CreatureMarker/CreatureInfo
## -- that stack is a full roaming-wildlife AI, the wrong shape for a small
## decorative-but-real pond-side presence whose entire behaviour is "sit,
## occasionally hop, occasionally croak".
##
## Real frog locomotion is a genuinely DISCRETE gait -- long still periods
## between short hop bursts -- not the continuous smooth roam
## AmbientFlyerMovement.step_position drives every other ambient creature
## with (a butterfly/bird/caterpillar is always drifting; a frog mostly
## isn't). This still reuses AmbientFlyerMovement, but only its direction_at
## heading-picker (home-anchored, already-tested containment math), called
## once at the START of each hop rather than every frame -- the actual
## per-frame stepping is a small bespoke hop-burst state machine below.
## This also makes the idle/hop animation choice a REAL discrete state
## (mid-hop-burst or not) rather than a proxy read off continuous movement
## magnitude, which a continuously-drifting creature's own tiny per-frame
## delta would make meaningless here.
##
## Deliberately lighter than CaterpillarMarker: no forage-and-eat state
## machine. A real frog snapping up a passing insect has no real economy to
## consume here -- the "insects" this game's own ambient flyers represent
## (butterflies) are themselves a decorative flat-cap presence with no
## population count to decrement (see AmbientFlyerRenderer's own doc
## comment), so wiring a fake "eats a real butterfly" interaction would
## still be decorative underneath, not an actual mechanism. IllustratedGrass
## FrogSprite's "eat" row is therefore left unwired in this pass, an honest,
## named scope cut rather than a reskin pretending to be a real mechanism
## (see docs/concept/seasonal_behavior.md's phase 10 write-up).
##
## "croak" plays as real (if decorative) frog behaviour on its own
## periodic, per-instance-jittered timer while idle -- real frogs call
## while stationary; this doesn't attract or repel anything, so it costs
## nothing to be honest about being flavour rather than a load-bearing
## signal.
##
## Season gating (spring/summer/autumn only, brumates through winter) lives
## entirely at the SPAWN decision (see GrassFrogRenderer), not here -- the
## same accepted approximation every other ambient decoration in this
## codebase already has (nothing re-validates a spawned flyer's own season/
## biome eligibility continuously either).

const IllustratedGrassFrogSprite = preload("res://src/rendering/illustrated_grass_frog_sprite.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")

const GROUP_NAME := "grass_frog"

## How far this frog ranges from its home spot across many hops -- short: a
## real grass frog stays close to its patch of damp ground/pond edge.
## Same order of magnitude as CaterpillarMarker.WANDER_RADIUS_PX.
const WANDER_RADIUS_PX := 20.0

## One real hop's distance -- a modest fraction of the whole home range, so
## it takes several hops to cross it (matching real frog locomotion: a
## sequence of short hops, not one leap spanning its whole territory).
const HOP_DISTANCE_PX := 10.0

## How long one hop burst's animation/movement actually takes.
const HOP_DURATION_SECONDS := 0.4

## How often, on average, an idle frog hops again -- real frogs sit still
## far longer than they move. Per-instance jittered via wander_seed (see
## _ready) so a pond full of frogs doesn't hop in unison.
const HOP_INTERVAL_SECONDS := 3.0

## How often, on average, an idle frog plays a real croak -- a real frog
## calls occasionally while stationary, not continuously and not on a
## rigid metronome. Per-instance jittered via wander_seed so a pond full of
## frogs doesn't call in unison.
const CROAK_INTERVAL_SECONDS := 6.0
const CROAK_DURATION_SECONDS := 1.2

## How long the illustrated idle/hop/croak cycle holds each frame -- mirrors
## CaterpillarMarker.FRAME_DURATION_SECONDS' order of magnitude.
const FRAME_DURATION_SECONDS := 0.16

## How much horizontal movement in one hop step counts as a real leftward/
## rightward heading worth flipping the sprite for -- mirrors
## CaterpillarMarker/DecomposerMarker.FACING_DEADZONE_PX exactly.
const FACING_DEADZONE_PX := 0.05

## grass_frog.png's "idle" row (see IllustratedGrassFrogSprite) is drawn
## facing right (measured directly from the sliced pixels via a temporary
## probe script) -- the opposite default from caterpillar's left-facing
## sheet, so the flip_h sense below is inverted from CaterpillarMarker's.
const _DRAWN_FACING_RIGHT := true

var home := Vector2.ZERO
var wander_seed := 0

var _elapsed_time := 0.0
var _sprite: Sprite2D
static var _illustrated_generator := IllustratedGrassFrogSprite.new()

## Heading-picker only (see the class doc comment) -- never stepped
## continuously.
var _movement: AmbientFlyerMovement

var _hop_target := Vector2.ZERO
var _hopping_until := -1.0
var _next_hop_at := 0.0
var _croaking_until := -1.0
var _next_croak_at := 0.0
var _last_moved := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_movement = AmbientFlyerMovement.new(HOP_DISTANCE_PX / HOP_DURATION_SECONDS, WANDER_RADIUS_PX, HOP_INTERVAL_SECONDS)
	# Per-instance jitter so a pond full of frogs doesn't hop/croak in
	# lockstep -- same "hash the seed" determinism AmbientFlyerMovement's
	# own _phase_offset uses.
	_next_hop_at = float(hash("%d_hop_phase" % wander_seed) % 10000) / 10000.0 * HOP_INTERVAL_SECONDS
	_next_croak_at = float(hash("%d_croak_phase" % wander_seed) % 10000) / 10000.0 * CROAK_INTERVAL_SECONDS
	_update_sprite()


func get_display_name() -> String:
	return "Grass Frog"


## A hop that just began still steps THIS SAME tick (not only from the next
## _process call onward): HOP_DURATION_SECONDS (0.4s) is deliberately
## shorter than an ordinary frame delta can be under this game's own
## distance-based LOD throttling (SimulationLod can space a distant
## marker's ticks seconds apart -- see DecomposerMarker/CaterpillarMarker's
## own _lod_step), so waiting for a follow-up call to actually move would
## let a slow-ticking frog schedule hop after hop while never once visibly
## moving, each one instantly stale before its next tick ever arrives.
func _process(delta: float) -> void:
	_elapsed_time += delta
	_last_moved = Vector2.ZERO
	if _is_hopping():
		_step_hop(delta)
	elif _is_croaking():
		pass  # a real frog call: stationary until it ends, see class doc comment
	elif _elapsed_time >= _next_hop_at:
		_begin_hop()
		_step_hop(delta)
	elif _elapsed_time >= _next_croak_at:
		_begin_croak()
	_update_sprite()


func _is_hopping() -> bool:
	return _elapsed_time < _hopping_until


func _is_croaking() -> bool:
	return _elapsed_time < _croaking_until


## Picks a real heading via AmbientFlyerMovement's already-tested,
## home-anchored containment math (so a long run of hops still keeps this
## frog within its territory, exactly like every other ambient creature's
## wander), then commits to one HOP_DISTANCE_PX hop in that direction over
## HOP_DURATION_SECONDS.
func _begin_hop() -> void:
	var direction := _movement.direction_at(home, position, _elapsed_time, wander_seed)
	_hop_target = position + direction * HOP_DISTANCE_PX
	_hopping_until = _elapsed_time + HOP_DURATION_SECONDS
	_next_hop_at = _elapsed_time + HOP_DURATION_SECONDS + _jittered_interval(HOP_INTERVAL_SECONDS, "hop")


func _step_hop(delta: float) -> void:
	var before := position
	position = position.move_toward(_hop_target, HOP_DISTANCE_PX / HOP_DURATION_SECONDS * delta)
	_last_moved = position - before


func _begin_croak() -> void:
	_croaking_until = _elapsed_time + CROAK_DURATION_SECONDS
	_next_croak_at = _elapsed_time + CROAK_DURATION_SECONDS + _jittered_interval(CROAK_INTERVAL_SECONDS, "croak")


## A fresh random-ish interval around `base_seconds`, reseeded from this
## frog's own wander_seed plus the current elapsed time so consecutive
## rolls don't repeat identically -- the interval only needs to avoid
## looking metronomic, not be cryptographically random.
func _jittered_interval(base_seconds: float, salt: String) -> float:
	var roll := float(hash("%d_%s_%d" % [wander_seed, salt, int(_elapsed_time * 1000.0)]) % 10000) / 10000.0
	return base_seconds * (0.75 + roll * 0.5)


func _current_action() -> String:
	if _is_hopping():
		return "hop"
	if _is_croaking():
		return "croak"
	return "idle"


func _update_sprite() -> void:
	var action := _current_action()
	var frames := _illustrated_generator.generate_textures(action)
	_sprite.texture = frames[int(_elapsed_time / FRAME_DURATION_SECONDS) % frames.size()]
	_sprite.scale = Vector2.ONE * _illustrated_generator.world_scale()
	if absf(_last_moved.x) > FACING_DEADZONE_PX:
		_sprite.flip_h = (_last_moved.x < 0.0) if _DRAWN_FACING_RIGHT else (_last_moved.x > 0.0)
