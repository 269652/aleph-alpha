extends Node2D

## A REAL forager for a BeeColony hive (see docs/concept/bees.md
## "Foraging") -- the direct flying sibling of AntForagerMarker: SCOUTS
## for a real flower with real nectar (wandering, no known target -- see
## _step_scouting), commits and flies to it once its own local sensing
## finds one, drinks it only on real arrival (re-checked then --
## something else may have drained it first), flies back to the hive,
## and only there does the honey deposit resolve and the marker free
## itself.
##
## Deliberately trimmed relative to AntForagerMarker (see bees.md's own
## "What's reused verbatim, what's a deliberate new duplicate, and why"):
## no pheromone trail/resolver role (real honeybee recruitment is the
## waggle dance, a genuinely different signal -- out of scope this
## pass), no carried-item visual (a drop of nectar has no equivalent
## "visibly carried leaf" moment), no crush/corpse lifecycle (never
## reported or asked for bees, unlike ants' own separately-requested
## corpse-foraging feature).
##
## Flies via AmbientFlyerMovement -- the same already-tested wander
## primitive AntForagerMarker's own SCOUT phase already uses for its
## ground wander, and every ambient flyer in this codebase uses for real
## flight -- rather than the walking gait a ground forager uses: a bee
## is a flying insect, not a walking one.
##
## Reuses ProceduralButterflySprite's existing "bee" art directly (a
## compact amber silhouette) rather than inventing a new generator: the
## shape/colour were already right for a bee, it is only the SPAWN/
## lifecycle half of the old decorative pollinator that this feature
## retires (see AmbientFlyerRenderer), never the art itself.
##
## ONE marker class serves BOTH a honeybee hive's own worker AND a
## solitary WildBeePatch resident's own foraging trip -- see `_colony`'s
## own doc comment for why this is a deliberate duck-typed reuse (both
## objects share the identical record_forage_result(cell, succeeded)
## call) rather than a near-duplicate WildBeeForagerMarker.

const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const BeeForageBehavior = preload("res://src/gameplay/bee_forage_behavior.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")

const GROUP_NAME := "bee_forager"

## Real honeybees are considerably faster fliers than an ant's own
## walking pace (AntForagerMarker.WALK_SPEED, 12.0) -- flight, not a
## crawl.
const FLY_SPEED := 40.0
const ARRIVE_DISTANCE_PX := 4.0

## Mirrors AntForagerMarker.SENSE_INTERVAL_SECONDS's own reasoning and
## FPS-regression history exactly (see that constant's own doc comment:
## "FPS regression round 3" -- a real, hard-learned lesson this class
## applies from the start rather than waiting to hit the identical bug
## a second time): a scout barely moves between one sense check and the
## next at its own scouting speed, so checking several times a second
## rather than every frame costs nothing real.
const SENSE_INTERVAL_SECONDS := 0.2

## Mirrors AntForagerMarker.SCOUT_SPEED_FRACTION's own reasoning: ambient
## wander (nothing found yet) stays visibly slower than a committed
## approach (something real just got sensed).
const SCOUT_SPEED_FRACTION := 0.6

## Mirrors AntForagerMarker.MAX_SCOUT_CROSSINGS's own reasoning: a real
## design knob, not itself test-locked, chosen generously enough for
## several genuine sweeps of the hive's own home range before giving up.
const MAX_SCOUT_CROSSINGS := 3.0

## Derived, not eyeballed -- mirrors AntForagerMarker.MAX_SCOUT_SECONDS's
## own derivation exactly, against BeeColony.FORAGE_RADIUS_TILES instead
## of AntColony's.
const MAX_SCOUT_SECONDS := (
	(2.0 * BeeColony.FORAGE_RADIUS_TILES * TerrainRenderer.TILE_SIZE)
	/ (FLY_SPEED * SCOUT_SPEED_FRACTION) * MAX_SCOUT_CROSSINGS
)

## Where the real flower is. Unset (Vector2.ZERO) until a scout commits
## to something it has actually sensed nearby -- mirrors
## AntForagerMarker.target_position's own backward-compatible contract
## (a direct construction can still set this before add_child).
var target_position: Vector2 = Vector2.ZERO
## Where this forager returns to once its trip resolves either way. Also
## this scout's own home anchor while SCOUTING.
var hive_position: Vector2 = Vector2.ZERO

## Opts into scouting (see AntForagerMarker.scout's own doc comment for
## the identical reasoning) instead of the already-know-the-target
## contract. Set before add_child by real dispatch.
var scout := false

var wander_seed := 0
var _elapsed_time := 0.0
var _sense_accumulator := SENSE_INTERVAL_SECONDS
var _lod_accumulated := 0.0
var _cached_player: Node = null
var _movement: AmbientFlyerMovement

var _behavior := BeeForageBehavior.new()

## The hive's own owning colony -- for record_forage_result (see
## setup()). Deliberately UNTYPED, not `: BeeColony` -- this same
## marker also serves a WildBeePatch's own solitary resident (see
## docs/concept/bees.md's "Foraging"/"Wild bee nests": a lone female's
## round trip to a real flower is the identical mechanism, just homed
## on a nest hole instead of a hive), and WildBeePatch.
## record_forage_result(cell, succeeded) already shares BeeColony's own
## exact signature -- one marker, two duck-typed "home" kinds, rather
## than a near-duplicate WildBeeForagerMarker for a difference that is
## purely which object receives the SAME call. Left null (default) is
## the same isolated-test fallback every other optional-world marker in
## this codebase uses: movement still works, the real world effects
## just no-op.
var _colony = null
var _hive_cell := Vector2i.ZERO
## Duck-typed: flowers_near/drink_nectar_at (see EarthChunkManager) --
## the same optional-world contract AntForagerMarker's own `_world`
## already uses, so this marker's real behaviour is testable without a
## real chunk manager.
var _world = null

var _sprite: Sprite2D

static var _generator := ProceduralButterflySprite.new()


## `world` (duck-typed, see _world's own doc comment), `colony` (the real
## BeeColony this forager's hive belongs to, or null in isolated tests),
## and `hive_cell` (which hive within it). Mirrors
## AntForagerMarker.setup's own shape exactly.
func setup(world, colony, hive_cell: Vector2i) -> void:
	_world = world
	_colony = colony
	_hive_cell = hive_cell


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_ensure_initialized()


## Mirrors AntForagerMarker._ensure_initialized's own idempotent,
## dual-call-site (real _ready() AND defensively at the top of
## _process()) shape exactly -- see that function's own doc comment for
## why: a synthetic test-double parent may call _process() directly
## without this node ever actually joining a live SceneTree.
func _ensure_initialized() -> void:
	if _sprite != null:
		return
	_sprite = Sprite2D.new()
	add_child(_sprite)
	if scout:
		wander_seed = randi()
		_movement = AmbientFlyerMovement.new(
			FLY_SPEED * SCOUT_SPEED_FRACTION,
			BeeColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE),
			_scout_direction_change_interval()
		)
		_behavior.begin_scouting()
	_sprite.texture = _generator.generate_texture("bee", wander_seed)


func _scout_direction_change_interval() -> float:
	return (
		(BeeColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE))
		/ (FLY_SPEED * SCOUT_SPEED_FRACTION)
	)


func get_display_name() -> String:
	return "Bee"


func _current_leg_target() -> Vector2:
	if _behavior.phase == BeeForageBehavior.Phase.APPROACHING:
		return target_position
	return hive_position


## Mirrors AntForagerMarker._lod_step/_take_lod_step/_nearest_player_
## position exactly -- see that class's own doc comment: a real, hard-
## learned FPS-regression lesson (round 3) applied here from the start
## rather than retrofitted after the fact a second time.
func _lod_step(delta: float) -> float:
	_lod_accumulated += delta
	var player = _nearest_player_position()
	if player == null:
		return _take_lod_step()
	var interval := SimulationLod.update_interval(position.distance_to(player))
	if _lod_accumulated < interval:
		return -1.0
	return _take_lod_step()


func _take_lod_step() -> float:
	var step := _lod_accumulated
	_lod_accumulated = 0.0
	return step


func _nearest_player_position():
	if not is_inside_tree():
		return null
	if _cached_player == null or not is_instance_valid(_cached_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return null
		_cached_player = players[0]
	return _cached_player.position


func _process(frame_delta: float) -> void:
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	_ensure_initialized()
	_elapsed_time += delta
	if _behavior.phase == BeeForageBehavior.Phase.SCOUTING:
		_step_scouting(delta)
		return
	var leg_target := _current_leg_target()
	if position.distance_to(leg_target) > ARRIVE_DISTANCE_PX:
		position = position.move_toward(leg_target, FLY_SPEED * delta)
		return
	match _behavior.phase:
		BeeForageBehavior.Phase.APPROACHING:
			_resolve_arrival_at_food()
		BeeForageBehavior.Phase.RETURNING:
			_resolve_arrival_at_hive()
			queue_free()


## No known target: wander (home-anchored at the hive), sensing only its
## own immediate vicinity for real nectar as it goes (see
## _sense_food_nearby) -- no pheromone/trail bias at all (see this
## file's own header doc comment), unlike AntForagerMarker's own
## gradient-biased equivalent. Gives up past MAX_SCOUT_SECONDS of
## fruitless wandering, same "still flies home, just empty-handed"
## contract an unsuccessful APPROACHING trip already has.
func _step_scouting(delta: float) -> void:
	if _elapsed_time >= MAX_SCOUT_SECONDS:
		_behavior.give_up_scouting()
		return
	_sense_accumulator += delta
	var found := {}
	if _sense_accumulator >= SENSE_INTERVAL_SECONDS:
		_sense_accumulator = 0.0
		found = _sense_food_nearby()
	if not found.is_empty():
		target_position = found.position
		_behavior.commit_to_food()
		return
	var heading := _movement.direction_at(hive_position, position, _elapsed_time, wander_seed)
	position += heading * (FLY_SPEED * SCOUT_SPEED_FRACTION) * delta


## Real, LOCAL sensing -- ONLY within BeeColony.SENSE_RADIUS_TILES of
## this scout's OWN current position, never the hive's whole forage
## reach -- mirrors AntForagerMarker._sense_food_nearby's own real,
## non-omniscient shape exactly, trimmed to the one food kind a bee
## actually looks for.
func _sense_food_nearby() -> Dictionary:
	if _world == null:
		return {}
	var sense_radius_px := BeeColony.SENSE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	var sense_radius_tiles := int(ceil(BeeColony.SENSE_RADIUS_TILES))
	var flowers: Array = _world.flowers_near(position, sense_radius_tiles)
	flowers = flowers.filter(func(f): return position.distance_to(f["position"]) <= sense_radius_px)
	flowers = flowers.filter(func(f): return float(f.get("nectar", 0.0)) > 0.0)
	if flowers.is_empty():
		return {}
	return {"position": flowers[0]["position"], "cluster_size": flowers.size()}


## Re-checks the real world on genuine arrival -- something else may
## have drained the bloom in the time this bee spent flying over (see
## AntForagerMarker._resolve_arrival_at_food's own identical reasoning).
func _resolve_arrival_at_food() -> void:
	var succeeded := false
	if _world != null:
		succeeded = _world.drink_nectar_at(target_position)
	_behavior.arrive_at_food(succeeded)


## Deposits into the hive's real honey reserve on a successful trip --
## mirrors AntForagerMarker._resolve_arrival_at_mound's own
## record_forage_result call exactly (which itself handles the deposit,
## see BeeColony.record_forage_result); an empty-handed trip still
## records the failure (feeds the recent-success EMA) but deposits
## nothing.
func _resolve_arrival_at_hive() -> void:
	if _colony == null:
		return
	_colony.record_forage_result(_hive_cell, _behavior.found_food)
