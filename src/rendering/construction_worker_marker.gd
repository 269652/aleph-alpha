extends Node2D

## The builder you see on a construction site (docs/concept/building.md,
## "Somebody is working on it" and "And he carries the material"). Asked
## for directly, watching a village raise a cottage: *"the construction
## site should show a builder working on it"*, and then *"the builders
## should carry materials to the site"*.
##
## Deliberately NOT the NpcMarker schedule stack -- the same choice, for
## the same reason, FarmerMarker and LumberjackMarker make: a small,
## purpose-built walker whose whole job is one plot and the store it draws
## on. EarthChunkManager spawns exactly one per site that is really being
## worked and frees him with it (see _sync_construction_worker), so a
## worker can never outlive the thing he is working on.
##
## He is a face on a number, not decoration: a settlement spends real spare
## hands on its projects (SettlementSpareCapacity scaled by settlement_
## productivity, charged against the project's required hours by
## ConstructionCatchup), and a site accruing no labour has no worker
## standing over it. What he carries is a second real number -- the
## project's own `reserved_material`, already drawn out of VillageMarket
## when the project started, which used to travel from the store's number
## to the site by teleport.
##
## The round: out to the store, a spell loading, back to the plot, the load
## set down, a spell or two of work, and out again, until nothing is left
## to fetch -- after which he is a man working his plot, which is also what
## a project with no reservation and a village with no store get (see
## ConstructionHaul, and village_warehouse.md's own pillar-1 caveat).

const ProceduralBuilderSprite = preload("res://src/rendering/procedural_builder_sprite.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ConstructionHaul = preload("res://src/gameplay/construction_haul.gd")
const WalkGate = preload("res://src/gameplay/walk_gate.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const TileRouter = preload("res://src/gameplay/tile_router.gd")
const AgentPassability = preload("res://src/gameplay/agent_passability.gd")

const GROUP_NAME := "construction_worker"

## How long he works one spot before moving to the next. Long enough to
## read as working rather than pacing: a builder crossing a 2x2 plot at
## WALK_SPEED takes about two seconds, so a dwell of the same order means
## roughly half his time is spent with the mallet down.
const WORK_SECONDS := 2.0

## World units per second ON THE PLOT. A working pace on a building site,
## well under the villagers' own walking speed -- he is carrying something
## heavy and has nowhere to be.
const WALK_SPEED := 9.0

## And world units per second on the ROAD, where he is crossing a village
## rather than stepping between two corners of one footprint. The village
## porter's own pace, pinned to it by
## test_a_builder_on_the_road_walks_at_the_porters_pace: two men carrying
## goods across the same square at visibly different speeds is a thing the
## eye catches immediately, and there is no reason for them to differ.
const HAUL_SPEED := 28.0

## Near enough to a store or a stockpile to be there. The porter's own
## arrival distance, and for the same reason: a walker that demands to
## land exactly on a point never gets there.
const ARRIVE_DISTANCE_PX := 4.0

## A spell spent loading at the store, the same length as a spell spent
## working on the plot -- lifting a load onto your shoulder is work, and
## measuring it differently would be inventing a second number.
const LOAD_SECONDS := WORK_SECONDS

## How much A* one builder may spend on one leg of his round, and the
## smallest gap between two recomputes -- the same terms every villager
## routes on (docs/concept/navigation.md), pinned to NpcMarker's own by
## test_a_builder_routes_on_the_same_terms_a_villager_does rather than
## preloading that whole marker for two numbers. Two walkers searching the
## same village to different depths is a difference nobody can justify.
const ROUTE_NODE_BUDGET := 1500
const ROUTE_RECOMPUTE_SECONDS := 0.5

## How long he waits before asking again for a route that could not be
## found AT ALL. A failed search is the expensive one -- it spends the
## whole node budget before giving up -- and a site ringed by buildings
## would otherwise pay that twice a second for as long as it stands.
## Longer than the ordinary throttle, and only for the failing case: a
## route he simply walked to the end of is recomputed at once, because a
## leg that ends short of its goal is the stall this seam exists to
## prevent. Pinned by test_a_builder_who_cannot_reach_the_store_does_not_
## search_for_ever.
const ROUTE_RETRY_SECONDS := 5.0

## How many spells of work one delivered load is worth before he goes back
## for the next. One would mean a man who walks far more than he builds;
## the site would read as a road. Pinned by
## test_he_works_the_plot_between_loads_rather_than_only_hauling, which
## fails at either degenerate end.
const WORK_SPELLS_PER_LOAD := 2

## Where he is in the round. WORKING is the whole of the old builder, and
## is where he stays when there is nothing to fetch.
enum Phase { WORKING, FETCHING, LOADING, HAULING }

## The plot he works, in world space -- the site's own footprint rect. An
## empty one means no site was given to him, and he simply stands.
var plot: Rect2 = Rect2()

## Which spots on that plot he picks, and in which order -- the site's own
## seed, so one builder works one site the same way on every reload.
var seed_value: int = 0

## Where the material is: the village store's pixel position, or null when
## no store is in reach. Injected by the caller, the same idiom
## LogisticsMarker's own preferred_storage_position already uses, so a
## builder does not re-discover a store his spawner has already found.
var depot = null

## The project's own reservation (item_id -> float), already drawn out of
## VillageMarket.stock when the project started. Empty means nothing to
## carry, which is a real answer rather than a missing one.
var reserved_material: Dictionary = {}

## How much of it he has carried in so far. Deliberately the WORKER's own
## tally rather than the ledger's: nothing in the ledger depends on it, and
## a chunk that unloads takes the man and his count with it, so a reloaded
## site starts its round over. Making it durable would mean persisting a
## second material ledger to change nothing about what gets built.
var delivered: Dictionary = {}

## What is in his arms right now, "" / 0.0 when his hands are free.
var carried_item_id := ""
var carried_count := 0.0

## Late-bound world reference for WalkGate and for routing, the same
## pattern the other walking markers use -- set by whatever spawns this
## marker, null in a test, which the gate itself answers by letting every
## step through. Assigning it binds the two passability questions once
## (NpcMarker.setup's own shape) rather than building a fresh lambda per
## frame.
var earth = null:
	set(value):
		earth = value
		_wall_tiles = AgentPassability.blocked_predicate_for(value)
		_route_cost = AgentPassability.cost_scale_for(value)

var _phase := Phase.WORKING
var _target := Vector2.ZERO
var _working := 0.0
var _picks := 0
## Starts full, so the first thing a builder does on a bare site is go and
## fetch something rather than mime work over an empty plot.
var _spells_since_load := WORK_SPELLS_PER_LOAD
var _sprite: Sprite2D

## Which tiles he may not step into, and how much longer each takes to
## cross than open ground -- invalid until `earth` is set, which both the
## gate and the router read as "nothing is solid", the same fail-open
## every mover in this project keeps.
var _wall_tiles := Callable()
var _route_cost := Callable()

## The tiles left to walk on this leg, the goal they were computed for, and
## the time since. An empty route means "no detour needed, or none found"
## -- either way he walks straight at it and the gate keeps him out of
## walls. Starts stale on purpose, so the first leg of a round routes on
## its first frame rather than half a second into a wall.
var _route: Array = []
var _route_goal_tile := Vector2i(2147483647, 2147483647)
var _route_age := ROUTE_RECOMPUTE_SECONDS
## Whether the last search came back with nothing, and how many searches
## this builder has run at all -- the second is what pins the back-off
## above, since "how often does it search" is otherwise unobservable.
var _route_search_failed := false
var _route_searches := 0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_sprite = Sprite2D.new()
	_sprite.texture = ProceduralBuilderSprite.new().generate_texture(carried_count > 0.0)
	add_child(_sprite)
	_target = _pick_spot()


func _process(delta: float) -> void:
	if plot.size == Vector2.ZERO:
		return
	match _phase:
		Phase.WORKING:
			_step_working(delta)
		Phase.FETCHING:
			_step_fetching(delta)
		Phase.LOADING:
			_step_loading(delta)
		Phase.HAULING:
			_step_hauling(delta)


## Paces the plot and works: walk to a spot, put the mallet down for
## WORK_SECONDS, pick the next. Leaves for the store once he has worked
## what one load is worth and there is another load waiting for him.
##
## Ungated on purpose -- he never crosses a tile boundary that WalkGate
## could refuse here, and a builder frozen against his own site by a gate
## would be strictly worse than one walking over its bare ground.
func _step_working(delta: float) -> void:
	if _spells_since_load >= WORK_SPELLS_PER_LOAD and not _next_load().is_empty():
		_phase = Phase.FETCHING
		return
	if _working > 0.0:
		_working -= delta
		if _working <= 0.0:
			_spells_since_load += 1
		return
	var toward := _target - position
	var step := WALK_SPEED * delta
	if toward.length() <= step:
		position = _target
		_working = WORK_SECONDS
		_target = _pick_spot()
		return
	position += toward.normalized() * step


func _step_fetching(delta: float) -> void:
	if depot == null:
		_phase = Phase.WORKING
		return
	if _walk_the_road_to(depot, delta):
		_working = LOAD_SECONDS
		_phase = Phase.LOADING


func _step_loading(delta: float) -> void:
	_working -= delta
	if _working > 0.0:
		return
	var load_out := _next_load()
	if load_out.is_empty():
		# Somebody else finished the pile while he walked: no load, no trip
		# back with empty arms pretending to deliver.
		_spells_since_load = 0
		_phase = Phase.WORKING
		return
	carried_item_id = String(load_out["item_id"])
	carried_count = float(load_out["count"])
	_draw_as_loaded(true)
	_phase = Phase.HAULING


## Back to the site with it, and the load is set down ON the plot -- the
## stockpile is its middle, which is where a site's material really goes:
## in reach of all of it.
func _step_hauling(delta: float) -> void:
	if not _walk_the_road_to(plot.get_center(), delta):
		return
	delivered[carried_item_id] = float(delivered.get(carried_item_id, 0.0)) + carried_count
	carried_item_id = ""
	carried_count = 0.0
	_draw_as_loaded(false)
	_spells_since_load = 0
	_working = 0.0
	_target = _pick_spot()
	_phase = Phase.WORKING


## One step of a road leg: toward the next waypoint of a real route when
## one is needed, through the shared gate (see WalkGate). A worker is a
## Sprite2D assigning position, so no StaticBody2D in the world has ever
## stopped one -- reported live, "Creatures and NPCs also walk through
## houses". A builder who never left his footprint could not walk through a
## wall; one crossing the square to the store can. True once he is there.
func _walk_the_road_to(goal: Vector2, delta: float) -> bool:
	var toward := goal - position
	var step := HAUL_SPEED * delta
	if toward.length() <= maxf(step, ARRIVE_DISTANCE_PX):
		_route.clear()
		_route_goal_tile = Vector2i(2147483647, 2147483647)
		return true
	var toward_waypoint := _steer_toward(goal, delta) - position
	if toward_waypoint.length() <= 0.0001:
		return false
	position = WalkGate.slide(
		earth, position, position + toward_waypoint.normalized() * step,
		float(TerrainRenderer.TILE_SIZE)
	)
	return false


## Where to actually aim this frame: the next waypoint of a real route when
## one is needed, or the goal itself when the way is clear, no route was
## found, or he has no world to ask. The villagers' own steering
## (NpcMarker._steer_toward, docs/concept/navigation.md), because the
## problem is the villagers' own.
##
## Measured on a real village (tools/probe_construction_haul.gd) before
## this: given the straight line and the wall slide alone, a builder walked
## 68 px toward the store's door, pressed into the corner of a building
## 25 px short of it, and stood there for the remaining 230 simulated
## seconds. Sliding is a local reflex for a wall you brush; getting AROUND
## one needs a plan.
##
## Recomputed when the goal moves, and also when the route has run out
## while he is still not there -- a leg that ends short is exactly the
## stall above, and one search every half second for the one builder on a
## site is cheap enough to spend on never seeing it again.
func _steer_toward(target: Vector2, delta: float) -> Vector2:
	_route_age += delta
	if not _wall_tiles.is_valid():
		return target
	var here := _tile_of(position)
	var goal := _tile_of(target)
	if here == goal:
		return target  # final approach, inside the destination tile
	var wait := ROUTE_RETRY_SECONDS if _route_search_failed else ROUTE_RECOMPUTE_SECONDS
	if (goal != _route_goal_tile or _route.is_empty()) and _route_age >= wait:
		_route_goal_tile = goal
		_route_age = 0.0
		_route_searches += 1
		_route = TileRouter.route(here, goal, _wall_tiles, ROUTE_NODE_BUDGET, _route_cost)
		_route_search_failed = _route.is_empty()
	# Drop whatever has already been walked.
	while not _route.is_empty() and _tile_of(position) == _route[0]:
		_route.remove_at(0)
	if _route.is_empty():
		return target
	return _tile_centre(_route[0])


func _tile_of(point: Vector2) -> Vector2i:
	var tile_size := float(TerrainRenderer.TILE_SIZE)
	return Vector2i(floori(point.x / tile_size), floori(point.y / tile_size))


func _tile_centre(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2.ONE * 0.5) * float(TerrainRenderer.TILE_SIZE)


## Which leg of the round he is drawn on: mallet up going out, a load on
## the shoulder coming back (ProceduralBuilderSprite). Redrawn only when
## his hands actually change, not every frame -- the image is generated
## pixel by pixel, and a walker regenerating it sixty times a second would
## be paying for a picture that has not changed.
func _draw_as_loaded(loaded: bool) -> void:
	if _sprite == null:
		return
	_sprite.texture = ProceduralBuilderSprite.new().generate_texture(loaded)


func _next_load() -> Dictionary:
	if depot == null:
		return {}
	return ConstructionHaul.next_load(reserved_material, delivered)


## The next spot on the plot he works, drawn from the site's own seed
## through two independent salts -- one index split across both axes walks
## a diagonal of the plot instead of covering it, the same trap
## BuildingCatalog.variant_cell_for names.
func _pick_spot() -> Vector2:
	if plot.size == Vector2.ZERO:
		return position
	_picks += 1
	var across := float(PixelNoise.range_index(seed_value, _picks, 11, 1000)) / 999.0
	var down := float(PixelNoise.range_index(seed_value, _picks, 29, 1000)) / 999.0
	return plot.position + Vector2(plot.size.x * across, plot.size.y * down)
