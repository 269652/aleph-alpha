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
## Draws real illustrated art (IllustratedBeeSprite -- honeybee.png for a
## real hive worker, bee.png for a WildBeePatch resident, see
## `is_wild_bee`'s own doc comment) at a real, measured world scale.
## Previously drew EITHER species via ProceduralButterflySprite's own
## generic "bee" silhouette with NO scale applied to the sprite at all --
## reported live: "bees are drawn gigantic" -- this codebase's own
## recurring "gigantic X" failure mode (see ProceduralDecomposerSprite's
## own doc comment for the identical precedent already hit for ants).
##
## ONE marker class serves BOTH a honeybee hive's own worker AND a
## solitary WildBeePatch resident's own foraging trip -- see `_colony`'s
## own doc comment for why this is a deliberate duck-typed reuse (both
## objects share the identical record_forage_result(cell, succeeded)
## call) rather than a near-duplicate WildBeeForagerMarker.

const ProceduralButterflySprite = preload("res://src/rendering/procedural_butterfly_sprite.gd")
const IllustratedBeeSprite = preload("res://src/rendering/illustrated_bee_sprite.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const BeeForageBehavior = preload("res://src/gameplay/bee_forage_behavior.gd")
const BeeColony = preload("res://src/world/bee_colony.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const ScentField = preload("res://src/world/scent_field.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

const GROUP_NAME := "bee_forager"

## Flying things draw above ground scenery -- mirrors AmbientFlyerMarker.
## AIRBORNE_Z_INDEX exactly, and for the identical reason (see that
## constant's own doc comment): every hive is required to sit within a
## couple of tiles of a real tree (see EarthChunkManager.
## _has_real_hive_anchor), and a bee is Y-sorted as a plain sibling of
## that tree under the same Entities node. A tree's OWN sort position is
## where it is ROOTED, not how tall its canopy draws; a bee flying at a
## screen position Y-sorting places "behind" that root gets hidden under
## the whole canopy sprite, then pops into view the instant it crosses
## the sort boundary -- reading as a bee materializing mid-air, not the
## continuous flight it actually is (reported live: "streams of bees...
## flying in that appear out of nowhere"). AmbientFlyerMarker already
## hit and fixed this exact bug for butterflies hovering at a flower;
## bees never inherited the fix because they are not built on
## AmbientFlyerMarker at all.
const AIRBORNE_Z_INDEX := 1

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

## How far a scout can detect (and commit to) a real flower or blossom by
## scent alone, once nothing is within the tighter BeeColony.
## SENSE_RADIUS_TILES that already guarantees a successful approach -- see
## _sense_distant_food, docs/concept/flora.md#tree-blossoms-emit-real-
## scent-too.
##
## NOT ScentField.gradient_direction/RADIUS_TILES (6 tiles): that models a
## real physical scent PLUME and is deliberately short-ranged, but
## SENSE_RADIUS_TILES (9) already exceeds it -- a gradient computed from
## the scout's own position could never contribute anything, since
## anything close enough to register on it would already have been close
## enough to commit to directly. This is the same real limitation
## AmbientFlyerMarker's own "KNOWN DIVERGENCE" comment documents for
## butterflies (targeting reaches further than scent literally carries);
## the honest fix here is a wider DETECTION range, not a gradient lean
## that can never fire. Real honeybees do detect and orient toward a food
## source well beyond the range at which a plume alone would resolve a
## direction, using memory and landmarks alongside scent -- this is that,
## simplified to "detectable across the whole home range."
const DISTANT_SENSE_RADIUS_TILES := BeeColony.FORAGE_RADIUS_TILES

## Where the real flower is. Unset (Vector2.ZERO) until a scout commits
## to something it has actually sensed nearby -- mirrors
## AntForagerMarker.target_position's own backward-compatible contract
## (a direct construction can still set this before add_child).
var target_position: Vector2 = Vector2.ZERO
## Which kind of target this trip committed to (see _sense_food_nearby):
## "flower" (drunk via _world.drink_nectar_at) or "blossom" (a real,
## pollinator-needing, blossoming fruit tree, pollinated via
## _world.record_pollination_visit_at) -- real honeybees, and real
## solitary bees, are genuine fruit-tree pollinators too, not just
## flower-nectar feeders. This is deliberately the ONE live path either
## kind of bee actually visits a tree: the retired decorative ambient
## "bee" (see AmbientFlyerRenderer/docs/concept/bees.md) was the only
## previous path via its own TREE_POLLINATING_SPECIES, and this feature
## replaces it rather than silently dropping tree pollination along
## with the decorative species it retires.
var _target_kind := "flower"
## Where this forager returns to once its trip resolves either way. Also
## this scout's own home anchor while SCOUTING.
var hive_position: Vector2 = Vector2.ZERO

## Opts into scouting (see AntForagerMarker.scout's own doc comment for
## the identical reasoning) instead of the already-know-the-target
## contract. Set before add_child by real dispatch.
var scout := false

## Which real sheet to draw (see IllustratedBeeSprite's own doc comment):
## false (the default) is a honeybee.png hive worker, dispatched by
## EarthChunkManager._dispatch_bee_forager; true is a bee.png WildBeePatch
## resident, dispatched by _dispatch_wild_bee_forager. A plain bool rather
## than reading `_colony`'s own runtime type: `_colony` is deliberately
## untyped/duck-typed (see its own doc comment) specifically so this class
## never has to care which kind of home it has for behaviour -- only the
## ART differs by species, so that is the one place this class asks at
## all, and it asks via an explicit flag set at dispatch time rather than
## an is-a check on a value that is deliberately untyped everywhere else.
var is_wild_bee := false

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

## How much horizontal movement in one step counts as a real leftward/
## rightward heading worth flipping the sprite for -- mirrors
## DecomposerMarker.FACING_DEADZONE_PX exactly.
const FACING_DEADZONE_PX := 0.05

var _sprite: Sprite2D

static var _generator := ProceduralButterflySprite.new()
static var _illustrated_generator := IllustratedBeeSprite.new()


func _species() -> String:
	return "wild_bee" if is_wild_bee else "honeybee"


## `world` (duck-typed, see _world's own doc comment), `colony` (the real
## BeeColony this forager's hive belongs to, or null in isolated tests),
## and `hive_cell` (which hive within it). Mirrors
## AntForagerMarker.setup's own shape exactly.
func setup(world, colony, hive_cell: Vector2i) -> void:
	_world = world
	_colony = colony
	_hive_cell = hive_cell


## Redirects this ALREADY-DISPATCHED forager to a hive that just relocated
## out from under it (absconding, or a harvest hand-off -- see docs/concept/
## bees.md's "Absconding") -- called by EarthChunkManager, never by this
## marker itself. hive_position/_hive_cell are otherwise set exactly once,
## at dispatch time in setup()/by the caller directly (see hive_position's
## own doc comment); this is the ONE place either is allowed to change
## mid-trip. Both _step_scouting's own home-anchor wander and
## _current_leg_target's RETURNING-leg branch read hive_position fresh
## every step (never a cached snapshot taken at dispatch time), and
## _resolve_arrival_at_hive reads _hive_cell fresh on arrival -- so simply
## reassigning both here is sufficient to redirect a forager wherever it
## currently is in its own trip (SCOUTING, APPROACHING, or RETURNING):
## without this, a forager already in flight kept flying toward the OLD
## site's now-torn-down marker forever, and its eventual arrival would
## have credited the colony's own now-gone `_hive_cell` instead of the
## real, current one.
func retarget_hive(new_hive_position: Vector2, new_hive_cell: Vector2i) -> void:
	hive_position = new_hive_position
	_hive_cell = new_hive_cell


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	z_index = AIRBORNE_Z_INDEX
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
	_update_sprite(Vector2.ZERO)


## Real illustrated fly-cycle art where IllustratedBeeSprite has it for
## this species (checked first, same has_X()-gated fallback convention
## every other optional illustrated-art seam in this codebase uses),
## ProceduralButterflySprite's own single static silhouette otherwise.
## `moved` is how far position actually changed this step -- see
## FACING_DEADZONE_PX's own doc comment for why only a real horizontal
## step flips the sprite.
func _update_sprite(moved: Vector2) -> void:
	var species := _species()
	if _illustrated_generator.has_species(species):
		var frames := _illustrated_generator.generate_textures(species)
		var index := int(_elapsed_time / IllustratedBeeSprite.FRAME_DURATION_SECONDS) % frames.size()
		_sprite.texture = frames[index]
		_sprite.scale = Vector2.ONE * _illustrated_generator.world_scale(species)
		if absf(moved.x) > FACING_DEADZONE_PX:
			_sprite.flip_h = moved.x > 0.0
	else:
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
	var position_before := position
	if _behavior.phase == BeeForageBehavior.Phase.SCOUTING:
		_step_scouting(delta)
		_update_sprite(position - position_before)
		return
	var leg_target := _current_leg_target()
	if position.distance_to(leg_target) > ARRIVE_DISTANCE_PX:
		position = position.move_toward(leg_target, FLY_SPEED * delta)
		_update_sprite(position - position_before)
		return
	match _behavior.phase:
		BeeForageBehavior.Phase.APPROACHING:
			_resolve_arrival_at_food()
		BeeForageBehavior.Phase.RETURNING:
			_resolve_arrival_at_hive()
			queue_free()
			return
	_update_sprite(position - position_before)


## No known target: wander (home-anchored at the hive), sensing its own
## immediate vicinity for real nectar as it goes (see _sense_food_nearby)
## -- no pheromone-TRAIL bias at all, i.e. no bee-to-bee recruitment
## signal (see this file's own header doc comment), unlike AntForagerMarker's
## own gradient-biased equivalent. It DOES also check its whole home range
## for something merely detectable rather than guaranteed-reachable (see
## _sense_distant_food/DISTANT_SENSE_RADIUS_TILES) -- real scent from the
## flowers/blossoms themselves, a genuinely different mechanism from a laid
## trail between bees -- and commits straight to that if nothing closer
## turned up. Gives up past MAX_SCOUT_SECONDS of fruitless wandering, same
## "still flies home, just empty-handed" contract an unsuccessful
## APPROACHING trip already has.
func _step_scouting(delta: float) -> void:
	if _elapsed_time >= MAX_SCOUT_SECONDS:
		_behavior.give_up_scouting()
		return
	_sense_accumulator += delta
	var found := {}
	if _sense_accumulator >= SENSE_INTERVAL_SECONDS:
		_sense_accumulator = 0.0
		found = _sense_food_nearby()
		if found.is_empty():
			found = _sense_distant_food()
	if not found.is_empty():
		target_position = found.position
		_target_kind = found.get("kind", "flower")
		_behavior.commit_to_food()
		return
	var heading := _movement.direction_at(hive_position, position, _elapsed_time, wander_seed)
	position += heading * (FLY_SPEED * SCOUT_SPEED_FRACTION) * delta


## Real, LOCAL sensing -- ONLY within BeeColony.SENSE_RADIUS_TILES of
## this scout's OWN current position, never the hive's whole forage
## reach -- mirrors AntForagerMarker._sense_food_nearby's own real,
## non-omniscient shape exactly. Two real food kinds, checked in order:
## a flower first (the everyday case), then -- only if none is near --
## a real blossoming, pollinator-needing fruit tree (see
## _target_kind's own doc comment on why this exists at all: the real
## LIVE replacement for the retired decorative bee's tree-pollination
## path, not a new mechanic invented here). Both share the identical
## {"position", "nectar"} real-world shape (see EarthChunkManager.
## blossoms_near's own doc comment), so this is a straightforward
## second check, not a parallel targeting system.
func _sense_food_nearby() -> Dictionary:
	if _world == null:
		return {}
	var sense_radius_px := BeeColony.SENSE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	var sense_radius_tiles := int(ceil(BeeColony.SENSE_RADIUS_TILES))
	var flowers: Array = _world.flowers_near(position, sense_radius_tiles)
	flowers = flowers.filter(func(f): return position.distance_to(f["position"]) <= sense_radius_px)
	flowers = flowers.filter(func(f): return float(f.get("nectar", 0.0)) > 0.0)
	if not flowers.is_empty():
		return {"position": flowers[0]["position"], "kind": "flower", "cluster_size": flowers.size()}
	if _world.has_method("blossoms_near"):
		var blossoms: Array = _world.blossoms_near(position, sense_radius_tiles)
		blossoms = blossoms.filter(func(b): return position.distance_to(b["position"]) <= sense_radius_px)
		if not blossoms.is_empty():
			return {"position": blossoms[0]["position"], "kind": "blossom", "cluster_size": blossoms.size()}
	return {}


## Real flower/blossom detection across this scout's WHOLE home range
## (DISTANT_SENSE_RADIUS_TILES), well beyond the tight commit-radius
## _sense_food_nearby uses -- this is what lets a real orchard or meadow
## draw a bee before it happens to wander into guaranteed sensing range by
## chance (see docs/concept/flora.md#tree-blossoms-emit-real-scent-too).
##
## Only ever consulted when _sense_food_nearby found nothing (see
## _step_scouting) -- a bee always prefers something guaranteed-reachable
## over something merely detected further off.
##
## Ranks candidates by ScentField.concentration_at (real superposition:
## several blooms clustered together outscore one lone bloom of the same
## individual strength, and a stronger-scented species like apple outranks
## a fainter one like cherry at equal distance -- see TreeSpecies.
## blossom_scent_for) rather than picking the nearest or the first found,
## so a real meadow or orchard genuinely pulls harder than a single flower,
## the same design point ScentField's own docstring makes for spawn rate
## and butterfly steering. A blossom's species is a TreeSpecies id, which
## ScentField's own FlowerSpecies-keyed lookup has never heard of --
## scent_strength overrides that lookup (see ScentField.concentration_at),
## same as EarthChunkManager.blossoms_near already sets it for its own
## callers; set here too rather than relied upon, since a stub/minimal
## world's blossoms_near is not guaranteed to carry it.
##
## has_method("current_season") is defensive the same way _sense_food_
## nearby already is on "blossoms_near": a world that predates/doesn't
## offer season reporting still gets a real (if not season-exact) answer
## rather than crashing or refusing to find anything at all.
func _sense_distant_food() -> Dictionary:
	if _world == null:
		return {}
	var wide_radius_px := DISTANT_SENSE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	var wide_radius_tiles := int(ceil(DISTANT_SENSE_RADIUS_TILES))
	var candidates: Array = []
	for f in _world.flowers_near(position, wide_radius_tiles):
		if position.distance_to(f["position"]) > wide_radius_px:
			continue
		if float(f.get("nectar", 0.0)) <= 0.0:
			continue
		var entry: Dictionary = f.duplicate()
		entry["kind"] = "flower"
		candidates.append(entry)
	if _world.has_method("blossoms_near"):
		for b in _world.blossoms_near(position, wide_radius_tiles):
			if position.distance_to(b["position"]) > wide_radius_px:
				continue
			var entry: Dictionary = b.duplicate()
			entry["kind"] = "blossom"
			entry["scent_strength"] = TreeSpecies.blossom_scent_for(String(b.get("species", "")))
			candidates.append(entry)
	if candidates.is_empty():
		return {}
	var season := "spring"
	if _world.has_method("current_season"):
		season = _world.current_season()
	var best: Dictionary = candidates[0]
	var best_score := -1.0
	for candidate in candidates:
		var score: float = ScentField.concentration_at(
			candidate["position"], candidates, season, float(TerrainRenderer.TILE_SIZE)
		)
		if score > best_score:
			best_score = score
			best = candidate
	return {"position": best["position"], "kind": best["kind"]}


## Re-checks the real world on genuine arrival -- something else may
## have drained the bloom (or, for a blossom, simply nothing is wrong at
## all: pollination is not a depleting resource, see blossoms_near's own
## doc comment -- record_pollination_visit_at can still fail if the
## tree itself is no longer there) in the time this bee spent flying
## over (see AntForagerMarker._resolve_arrival_at_food's own identical
## reasoning). A blossom target is pollinated, never drunk from -- the
## two real methods are not interchangeable.
func _resolve_arrival_at_food() -> void:
	var succeeded := false
	if _world != null:
		if _target_kind == "blossom":
			succeeded = _world.record_pollination_visit_at(target_position)
		else:
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
