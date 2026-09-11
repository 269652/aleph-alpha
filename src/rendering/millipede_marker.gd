extends Node2D

## A millipede -- see docs/concept/soil_fauna.md "Millipedes: a dedicated
## autumn leaf-litter decomposer", requested live after a screenshot of an
## autumn floor carpeted in leaves: "what else decomposes leaves I could
## add into the ecosystem to increase decomposition rate?" Mirrors
## CaterpillarMarker's own shape closely -- deliberately NOT built on
## CreatureMarker/CreatureInfo, the wrong shape for a tiny detritivore whose
## entire behaviour is "find food, eat it, wander otherwise" -- but smaller:
## a millipede has exactly ONE food source (real fallen leaf litter, see
## _nearest_food), never climbs a tree the way a caterpillar does, so there
## is no second target kind, no climb animation, no climb-height offset.
##
## Reuses CaterpillarForageBehavior directly rather than a near-duplicate
## state machine (see docs/concept/soil_fauna.md): that class's own
## SEEKING -> APPROACHING -> EATING -> SEEKING cycle is already fully
## generic -- nothing tree-specific lives in the behavior itself, only in
## how CaterpillarMarker interprets its own _target_is_tree flag, which
## this class has no equivalent of at all.
##
## The OPPOSITE diet restriction from a caterpillar: real millipedes are
## near-exclusively saprophagous (dead plant matter, not carrion, not fresh
## fruit, not live foliage) and have no reason to prefer green leaves over
## brown ones -- an old, decaying leaf is exactly what a real millipede
## eats, so unlike CaterpillarMarker._is_green, this class applies NO
## season filter at all: any real leaf, any recorded season, is food. This
## is the entire reason this creature exists -- a caterpillar structurally
## cannot touch the autumn pile the request was actually about.

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const IllustratedMillipedeSprite = preload("res://src/rendering/illustrated_millipede_sprite.gd")
const CaterpillarForageBehavior = preload("res://src/gameplay/caterpillar_forage_behavior.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const SimulationLodClock = preload("res://src/gameplay/simulation_lod_clock.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")

const GROUP_NAME := "millipede"

## How far this millipede can notice a leaf -- short, a slow ground crawler
## doesn't range far. Same order of magnitude as CaterpillarMarker.
## SEARCH_RADIUS_PX (50.0), the closest sibling creature's own tuning.
const SEARCH_RADIUS_PX := 50.0

## How close counts as "arrived".
const ARRIVE_DISTANCE_PX := 4.0

## How far it wanders from home while nothing is around to eat.
const WANDER_RADIUS_PX := 24.0
## No specific speed request exists for this creature (unlike
## CaterpillarMarker's own explicit "1/3 of the speed" ask) -- reuses
## DecomposerMarker.WALK_SPEED, the nearest architecturally-equivalent
## sibling's own default ground-forager pace, rather than inventing an
## unrequested third number.
const WALK_SPEED := 24.0
## Ambient wander is slower than a committed approach -- a hurrying
## millipede reads as one that has actually found something, same
## reasoning as CaterpillarMarker/DecomposerMarker's own
## WANDER_SPEED_FRACTION.
const WANDER_SPEED_FRACTION := 0.35

## How long the illustrated crawl/alert cycle holds each frame -- mirrors
## CaterpillarMarker.FRAME_DURATION_SECONDS: a similarly slow, chunky,
## many-legged gait reads fine at the same cadence.
const FRAME_DURATION_SECONDS := 0.16

## How much horizontal movement in one step counts as a real leftward/
## rightward heading worth flipping the sprite for -- mirrors
## CaterpillarMarker.FACING_DEADZONE_PX exactly.
const FACING_DEADZONE_PX := 0.05

## Derived, not eyeballed -- how long a wandering millipede holds one
## exploring heading before AmbientFlyerMovement picks a new one, in
## seconds, from its own wander geometry. Mirrors CaterpillarMarker.
## WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS's identical derivation exactly.
const WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS := (
	WANDER_RADIUS_PX / (WALK_SPEED * WANDER_SPEED_FRACTION)
)

var home := Vector2.ZERO
var wander_seed := 0

var _behavior := CaterpillarForageBehavior.new()

## Where the current leaf target is, or null (not currently pursuing
## anything) -- a plain position, not a live node reference, the same
## contract CaterpillarMarker._target_position uses: a leaf is re-verified
## (and consumed) in one call at the moment of the bite, via the injected
## _world's own best-effort consume_leaf_litter_at.
var _target_position = null  # Vector2, or null

var _movement: AmbientFlyerMovement
var _elapsed_time := 0.0

var _sprite: Sprite2D
static var _illustrated_generator := IllustratedMillipedeSprite.new()

## The owning EarthChunkManager, duck-typed for nearest_leaf_litter_near/
## consume_leaf_litter_at -- optional, mirroring CaterpillarMarker.setup's
## identical "narrows, doesn't break, a millipede built standalone" contract.
## Without it, this millipede simply never finds food and only ever wanders.
var _world = null


func setup(world) -> void:
	_world = world


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_movement = AmbientFlyerMovement.new(
		WALK_SPEED * WANDER_SPEED_FRACTION, WANDER_RADIUS_PX, WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS
	)
	_update_sprite(Vector2.ZERO)


func get_display_name() -> String:
	return "Millipede"


## crawl: ambient wander, or approaching a leaf. alert: EATING -- a
## millipede pausing to feed (see IllustratedMillipedeSprite's own row
## doc comment). crushed: dying (see crush()) -- closes the gap
## docs/concept/soil_fauna.md's own "What this does NOT include" named
## explicitly ("the `crushed` row exists and is real ... not yet wired to
## a real trigger"). curl alone remains genuinely unwired (no threat-sense
## exists to trigger it).
func _current_action() -> String:
	if _dying:
		return "crushed"
	if _behavior.phase == CaterpillarForageBehavior.Phase.EATING:
		return "alert"
	return "crawl"


## Set by crush() (see its own doc comment) -- once true, _process skips
## every forage/wander step entirely and only ticks the death animation.
var _dying := false


## Called by EarthChunkManager.crush_millipedes_near (via _crush_markers_near)
## in place of an instant queue_free() -- see docs/concept/soil_fauna.md's
## own "No timed death animation" scope-cut, now closed: real "crushed" art
## already existed (IllustratedMillipedeSprite's row 4), delivered but never
## wired to any trigger; this is that trigger. Restarts _elapsed_time from
## 0.0 so the crushed row plays from its own first frame regardless of
## whatever the crawl/alert cycle's counter happened to read at the moment
## of death, then holds on the LAST crushed frame (see _update_sprite's own
## clamped-vs-wrapped indexing) for one more full frame's worth of time
## before _process actually frees the marker -- long enough to read as a
## real death, not an instant swap. Idempotent: crushing an already-dying
## millipede a second time (e.g. a second heavy footstep landing before the
## animation finishes) does nothing further.
func crush() -> void:
	if _dying:
		return
	_dying = true
	_elapsed_time = 0.0
	_update_sprite(Vector2.ZERO)


## How long the crushed row plays before the marker actually frees itself --
## derived from the row's own real frame count (25, per
## IllustratedMillipedeSprite.EXPECTED_FRAME_COUNT) times the same
## FRAME_DURATION_SECONDS every other action already animates at, not a
## second, independently-eyeballed duration.
func _crushed_duration() -> float:
	return float(_illustrated_generator.generate_textures("crushed").size()) * FRAME_DURATION_SECONDS


func _update_sprite(moved: Vector2) -> void:
	var action := _current_action()
	var frames := _illustrated_generator.generate_textures(action)
	var index := int(_elapsed_time / FRAME_DURATION_SECONDS)
	# Dying holds its LAST frame once fully played (a flattened corpse
	# should stay flattened, not loop back to crawling) -- every other
	# action still wraps forever via modulo, exactly as before.
	_sprite.texture = frames[clampi(index, 0, frames.size() - 1)] if _dying else frames[index % frames.size()]
	_sprite.scale = Vector2.ONE * _illustrated_generator.world_scale()
	if absf(moved.x) > FACING_DEADZONE_PX:
		_sprite.flip_h = moved.x > 0.0


var _lod_clock := SimulationLodClock.new()


## Distance-based update rate -- mirrors CaterpillarMarker/DecomposerMarker/
## CreatureMarker's own _lod_step exactly.
func _lod_step(delta: float) -> float:
	if not _lod_clock.tick(delta):
		return -1.0
	var player = _nearest_player_position()
	if player == null:
		return _lod_clock.take_full_rate_step()
	return _lod_clock.take_step(position.distance_to(player))


func _nearest_player_position():
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
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	_elapsed_time += delta
	if _dying:
		_update_sprite(Vector2.ZERO)
		if _elapsed_time >= _crushed_duration():
			queue_free()
		return
	var position_before := position
	match _behavior.phase:
		CaterpillarForageBehavior.Phase.SEEKING:
			_step_seeking(delta)
		CaterpillarForageBehavior.Phase.APPROACHING:
			_step_approaching(delta)
		CaterpillarForageBehavior.Phase.EATING:
			_step_eating(delta)
	_update_sprite(position - position_before)


func _step_seeking(delta: float) -> void:
	position = _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	_behavior.advance(delta)  # no-op outside EATING, just ticks the rehunt clock
	if _behavior.can_commit():
		var found = _nearest_food()
		if found != null:
			_target_position = found
			_behavior.begin_approach()


## Nearest (by real distance) real leaf litter within SEARCH_RADIUS_PX, of
## ANY recorded season (see the class doc comment for why this has no
## green/brown filter the way CaterpillarMarker._is_green does), or null.
## Optional/duck-typed (see _world's own doc comment): a millipede with no
## world set simply never finds anything.
func _nearest_food() -> Variant:
	if _world == null or not _world.has_method("nearest_leaf_litter_near"):
		return null
	var leaf: Dictionary = _world.nearest_leaf_litter_near(position, SEARCH_RADIUS_PX)
	if leaf.is_empty():
		return null
	return leaf["position"]


func _step_approaching(delta: float) -> void:
	if _target_position == null:
		_behavior.abort()
		return
	var to_target: Vector2 = _target_position - position
	if to_target.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive()
		return
	# move_toward, not += direction * speed * delta: a target committed to
	# while ambient wander is active can already be closer than one whole
	# step, and unclamped movement overshoots straight past it -- then
	# overshoots back next step, forever. Same clamped-arrival shape
	# CaterpillarMarker._step_approaching already uses for the identical
	# reason.
	position = position.move_toward(_target_position, WALK_SPEED * delta)


func _step_eating(delta: float) -> void:
	if _target_position == null:
		_behavior.abort()
		return
	if _behavior.advance(delta):
		# A leaf is a one-visit consumable, removed on the bite that lands --
		# best-effort: if it's already gone (eaten by something else between
		# being spotted and this millipede arriving), this simply does
		# nothing further, same as CaterpillarMarker._step_eating's
		# identical ground-litter case.
		if _world != null and _world.has_method("consume_leaf_litter_at"):
			_world.consume_leaf_litter_at(_target_position)
	if _behavior.phase != CaterpillarForageBehavior.Phase.EATING:
		# CaterpillarForageBehavior.advance closed the phase out itself
		# (EAT_SECONDS elapsed) -- clear the target so the next SEEKING
		# tick starts genuinely fresh.
		_target_position = null
