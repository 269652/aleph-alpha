extends Node2D

## A REAL forager (see docs/concept/soil_fauna.md "Real foraging: a round
## trip, not an instant resolve" and "Scouting: real search, not
## omniscient dispatch"): SCOUTS for a real food item (wandering, no known
## target -- see _step_scouting), commits and walks to it once its own
## local sensing finds one, takes it only on real arrival (re-checked then
## -- something else may have taken it first), walks back to the mound,
## and only THERE does the cache/consume roll resolve and the marker free
## itself. This used to be a purely decorative, one-shot walk along an
## already-resolved path; AntColony's own forage-and-cache resolution has
## moved out of EarthChunkManager's instant lookup and into the real
## moments this marker itself now causes (see AntForageBehavior).
##
## Reported live: "ants go straight to the next leaf when moving out the
## mound ... they should either explore randomly or follow pheromones",
## then, once a pheromone-biased OMNISCIENT candidate-list dispatch was
## built to answer that: "no omniscience please". This is the real
## answer: nothing here ever asks "what is the single/best food item
## anywhere within the mound's whole forage reach" from a stationary
## point any more. A dispatched scout starts with NO known target,
## wanders (AmbientFlyerMovement, home-anchored at the mound -- the same
## already-tested primitive DecomposerMarker's own ambient wander already
## uses), and at each step senses only within SENSE_RADIUS_TILES of its
## OWN current, moving position (see _sense_food_nearby) -- genuinely
## smaller than the mound's whole home range, so real wandering is
## required to cover it. A locally-sensed PheromoneField gradient (real
## chemotaxis: a concentration sensed exactly where the scout stands, not
## a list of known candidates compared from afar -- see AntScoutWander)
## biases which way it turns, the real recruitment effect, without ever
## needing to know where else a trail might lead.
##
## Uses IllustratedDecomposerSprite's real "ant" art where it exists
## (checked first, same has_X()-gated fallback convention every optional
## illustrated-art seam in this codebase uses), falling back to
## ProceduralDecomposerSprite's silhouette otherwise -- the same tiny ant
## every decomposer draws. A single held pose per leg, not an animated
## walk cycle -- this marker is short-lived, so DecomposerMarker is where
## the walk cycle's frame-stepping actually earns its keep.

const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const IllustratedDecomposerSprite = preload("res://src/rendering/illustrated_decomposer_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const AntForageBehavior = preload("res://src/gameplay/ant_forage_behavior.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const LeafLitterAtlas = preload("res://src/rendering/leaf_litter_atlas.gd")
const LeafLitterRenderer = preload("res://src/rendering/leaf_litter_renderer.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const AntScoutWander = preload("res://src/gameplay/ant_scout_wander.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const SquashCrushEffect = preload("res://src/rendering/squash_crush_effect.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")

const GROUP_NAME := "ant_forager"

## Originally the same walking speed as every other decomposer (24.0, see
## DecomposerMarker.WALK_SPEED), on the reasoning that a colony's own
## forager is the identical animal, not a faster/slower special case.
## Reported directly ("half ants speed") and halved -- now a deliberately
## independent, slower value; DecomposerMarker's own ambient ants/bugs are
## untouched. Pinned by test_walk_speed_is_pinned_to_half_its_original_value.
const WALK_SPEED := 12.0
## How close counts as "arrived at this leg's target" -- mirrors
## DecomposerMarker.ARRIVE_DISTANCE_PX exactly, the same tiny-insect arrival
## tolerance.
const ARRIVE_DISTANCE_PX := 4.0

## How often a SCOUTING forager actually re-senses its surroundings (see
## _sense_food_nearby), independent of the SimulationLod throttle below --
## even a full-rate (near-player) scout doesn't need to re-run three
## separate world-area scans every single frame: at its own walking speed
## (WALK_SPEED * SCOUT_SPEED_FRACTION ~= 4.2px/s) it barely moves between
## one check and the next, so real food nearby is not about to be missed
## by checking 5 times a second instead of 60. Reported live, real
## measured cost via a --solo perf investigation session: this was the
## round-3 FPS regression's dominant cause -- FPS collapsed to 3-5, with
## ~1000-1300ms of CPU spent per 3-second window inside
## _sense_food_nearby alone, across roughly 1000 concurrently-scouting
## foragers (three deliberate tuning passes in the prior ~24h had raised
## both the realistic population and each forager's own scouting lifetime
## several-fold on top of a class that never got SimulationLod's
## treatment at all -- see docs/concept/soil_fauna.md's own "Generalized...
## FPS regression round 3" section). The FIRST scouting step always senses
## immediately regardless (see _sense_accumulator's own default) -- only
## repeated re-checks are throttled.
const SENSE_INTERVAL_SECONDS := 0.2

## Ambient wander is slower than a committed approach -- mirrors
## DecomposerMarker.WANDER_SPEED_FRACTION's own reasoning exactly: a
## hurrying insect reads as one that has actually found something, so
## SCOUTING (nothing found yet) stays visibly slower than APPROACHING
## (something real just got sensed) even though both use the same
## underlying WALK_SPEED.
const SCOUT_SPEED_FRACTION := 0.35

## How many times over a scout could cross its OWN whole wander disc
## (2 * AntColony.FORAGE_RADIUS_TILES, the home-anchor diameter
## AmbientFlyerMovement roams within) before giving up empty-handed --
## a real, if inherently judgment-called, design knob (see
## AntColony.FORAGE_RADIUS_TILES's own doc comment for precedent: "a real
## design knob, not itself test-locked"), chosen generously enough that a
## scout gets several genuine sweeps of its small home range rather than
## bailing after barely crossing it once. MAX_SCOUT_SECONDS below is
## DERIVED from this, not a second, independently-eyeballed number.
const MAX_SCOUT_CROSSINGS := 3.0

## Derived, not eyeballed (see MAX_SCOUT_CROSSINGS's own doc comment):
## real seconds to cross the scout's whole wander disc at scouting speed,
## times MAX_SCOUT_CROSSINGS. Pinned by test_max_scout_seconds_is_derived_
## not_eyeballed.
const MAX_SCOUT_SECONDS := (
	(2.0 * AntColony.FORAGE_RADIUS_TILES * TerrainRenderer.TILE_SIZE)
	/ (WALK_SPEED * SCOUT_SPEED_FRACTION) * MAX_SCOUT_CROSSINGS
)

## Where the real food is. Unset (Vector2.ZERO) until a scout commits to
## something it has actually sensed nearby (see _sense_food_nearby) --
## real production dispatch no longer sets this before add_child the way
## it used to; a direct construction (e.g. a test exercising the
## APPROACHING/RETURNING legs in isolation) still can.
var target_position: Vector2 = Vector2.ZERO
## Where this forager returns to once its trip resolves either way. Also
## this scout's own home anchor while SCOUTING (see AmbientFlyerMovement).
var mound_position: Vector2 = Vector2.ZERO
## "seed" (grass seed -- always survives to be planted), "windfall"
## (fallen fruit/nut -- resolves through AntColony.windfall_is_consumed
## first), "leaf" (real detritus, never re-cached), or "corpse" (a
## settled, dead ant -- see EarthChunkManager.ant_corpses_near/
## take_ant_corpse_near -- real food/detritus like a leaf, never
## re-cached either). Decides which of the world's take/plant APIs this
## trip actually calls. A scout decides this ITSELF, the moment it senses
## something real nearby (see _sense_food_nearby) -- no longer decided by
## the dispatcher in advance.
var forage_kind := "seed"

## Opts into scouting (see this file's own top doc comment and
## AntForageBehavior.begin_scouting) instead of the original
## already-know-the-target contract. Set before add_child by real
## dispatch (see EarthChunkManager._dispatch_ant_forager); left false (the
## default) keeps every existing direct-construction caller (chiefly
## tests exercising APPROACHING/RETURNING in isolation) completely
## unaffected.
var scout := false

## Dispatched specifically to FOLLOW a known trail (see
## EarthChunkManager's own scout-vs-resolver dispatch choice, gated on
## AntColony.has_active_pheromone_trail) rather than explore blind --
## reported live: "when the scouts return the mound dispatches more ants
## which follow / resolve the pheromone trails". Shares the exact same
## SCOUTING phase/sensing/commit contract `scout` does (see _step_
## scouting) -- the only real difference is that a resolver PRIORITIZES
## PheromoneField.nearest_trail_near over ambient wander, while a plain
## scout only ever gets the softer gradient_direction bias. Mutually
## exclusive with `scout` in practice (real dispatch sets exactly one),
## but nothing enforces that structurally -- both are plain opt-in flags,
## same as `scout` always has been.
var resolver := false

## This scout's own dispatch-time assigned sector (see EarthChunkManager's
## own scout-wave dispatch, which spreads several scouts' assigned
## directions evenly around a circle) -- Vector2.ZERO (the default) for a
## resolver, or a scout dispatched alone, in which case AntScoutWander.
## spread_heading leaves wander completely unbiased. Reported live: "the
## mound should send out multiple scouts in random directs" -- this is
## the concrete fix for several scouts dispatched together otherwise
## reading as one wandering ant with others following in a line.
var assigned_heading_bias := Vector2.ZERO

## This forager's own per-instance identity for AmbientFlyerMovement's
## roam (see that class's own direction_at: "deterministic" there means
## stable WITHIN one forager's own lifetime, not reproducible across runs
## -- the same contract every other wander_seed in this codebase already
## has). Rolled once at _ready() for a scouting forager (see that
## function) purely so several scouts out at once don't all wander in
## lockstep -- unlike a squirrel/bird's carry direction, a scout's own
## wander shape has nothing else it needs to agree with, so an injected,
## save-restorable seed (the shape every OTHER wander_seed in this
## codebase uses, for creatures that persist across saves) buys nothing
## here: an ant forager is one-shot-per-trip and is never itself saved.
var wander_seed := 0
var _elapsed_time := 0.0
## Starts already at (not past) SENSE_INTERVAL_SECONDS -- see that
## constant's own doc comment: the very first scouting step always senses
## immediately, and this field only gates REPEATED re-checks after that.
var _sense_accumulator := SENSE_INTERVAL_SECONDS
var _lod_accumulated := 0.0
var _cached_player: Node = null
## Built only for a scouting forager (see _ready) -- home-anchored at
## mound_position, radius AntColony.FORAGE_RADIUS_TILES: the mound's own
## forage reach doubles as this scout's own wander disc, so it never
## needs a second, independently-tuned range.
var _movement: AmbientFlyerMovement

## Which leaf this trip is carrying, if `forage_kind == "leaf"` -- set at
## dispatch time (see EarthChunkManager._dispatch_ant_forager's own doc
## comment) from the SAME nearest_leaf_litter_near lookup that found
## target_position in the first place, so this marker never has to ask the
## world a second time just to know what the leaf it is about to carry
## home actually looks like. Left "" (the default) for seed/windfall trips,
## which have no such visual (see _update_carried_leaf).
var carried_leaf_species := ""
var carried_leaf_season := ""

## Whether the food this trip committed to (see _sense_food_nearby) was
## sensed alongside AntColony.CLUSTER_THRESHOLD or more of its own kind --
## a real recruitment-worthy find, not something one ant quietly cleans up
## alone. Only a cluster find ever lays a trail on the way home (see
## _process's RETURNING branch) -- reported live: "these scouts should
## only lay out pheromones after they discovered a cluster for which
## multiple ants are needed".
var _is_cluster_find := false
## How many were sensed together at commit time (see _sense_food_nearby) --
## encoded into the trail as its own "amount" (see PheromoneField.
## deposit_trail) so a resolver reading it has some idea how much is
## really out there, not just that something is.
var _cluster_size := 0
## Set once this specific ant has determined the cluster is spent (took
## the last real item, or arrived to find it already empty -- see
## _resolve_arrival_at_food) so the walk home never lays a fresh trail
## for something that no longer exists.
var _trail_invalidated := false
## Throttles trail deposits to once per NEW tile crossed on the way home
## (see _maybe_deposit_trail_tile), not every single frame -- a real ant
## does not re-mark ground it is still standing on.
var _last_trail_tile := Vector2i.ZERO
var _has_deposited_trail_tile := false

var _behavior := AntForageBehavior.new()
## The species this trip is carrying, if any (windfall only -- a grass
## seed has no species to remember, TallGrass.plant_grass_at needs none).
var _carried_species := ""

## The mound's own owning colony -- for the deterministic per-(cell, step)
## carrier seed/windfall roll, the recent-forage-success record, and this
## mound's own pheromone trail (see setup()). Left null (default) is the
## same isolated-test fallback every other optional-world marker in this
## codebase uses: movement still works, the real world effects just
## no-op.
var _colony: AntColony = null
var _mound_cell := Vector2i.ZERO
## Duck-typed: take_grass_seed_at/plant_grass_at/take_fruit_at/
## try_plant_seed_at (see EarthChunkManager) -- the same optional-world
## contract FishMarker/PiscivoreBirdMarker already use, so this marker's
## real behaviour is testable without a real chunk manager.
var _world = null

var _sprite: Sprite2D
## Whether the sprite is CURRENTLY drawn in the carry pose -- reflects
## what is actually being carried, not just which leg of the trip this is:
## an empty-handed return (the food was already gone on arrival) must
## still show the plain walk cycle, never carry.
var _carrying := false

## The real, visible leaf riding home with this ant (see _update_carried_
## leaf) -- a SECOND child, added after _sprite so the ant's own body draws
## on top of it (the same "carrying something held against the body"
## read the ant's own carry POSE already establishes), never the only
## visual standing in for "carrying". Hidden by default: only forage_kind
## == "leaf" trips that actually found something ever show it.
var _leaf_sprite: Sprite2D

## The real, visible corpse riding home with this ant (see
## _update_carried_corpse) -- reported live: "instead dead ants should be
## foraged by other ants so they get visibly dragged into the mound". A
## THIRD child, same "drawn under the ant's own body, trailing behind it"
## shape _leaf_sprite already establishes. Hidden by default: only
## forage_kind == "corpse" trips that actually found something ever show
## it.
var _corpse_sprite: Sprite2D

static var _procedural_generator := ProceduralDecomposerSprite.new()
static var _illustrated_generator := IllustratedDecomposerSprite.new()
static var _leaf_atlas := LeafLitterAtlas.new()


## `world` (duck-typed, see _world's own doc comment), `colony` (the real
## AntColony this forager's mound belongs to), and `mound_cell` (which
## mound within it) -- all three needed before this forager can do
## anything beyond walk. Mirrors FishMarker.setup's own shape.
func setup(world, colony: AntColony, mound_cell: Vector2i) -> void:
	_world = world
	_colony = colony
	_mound_cell = mound_cell


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_ensure_initialized()


## Real Godot _ready() timing depends on this whole node's own branch
## actually being attached to a live SceneTree -- true for every real
## dispatch, but NOT guaranteed for a synthetic test double parent (see
## EarthChunkManager's own test suite, whose _entities_parent is never
## itself added to a tree) that still calls _process() directly. Splitting
## setup out of _ready() into this idempotent helper -- called from BOTH
## _ready() (the normal path) and defensively at the top of _process()
## (see that function) -- means scouting activates correctly either way,
## rather than silently depending on Godot's own tree-attachment timing
## for correctness.
func _ensure_initialized() -> void:
	if _sprite != null:
		return
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_leaf_sprite = Sprite2D.new()
	_leaf_sprite.visible = false
	add_child(_leaf_sprite)
	_corpse_sprite = Sprite2D.new()
	_corpse_sprite.visible = false
	add_child(_corpse_sprite)
	if scout or resolver:
		wander_seed = randi()
		_movement = AmbientFlyerMovement.new(
			WALK_SPEED * SCOUT_SPEED_FRACTION,
			AntColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE),
			_scout_direction_change_interval()
		)
		_behavior.begin_scouting()
	_update_sprite()


## Derived, not eyeballed -- how long it would take to cross the scout's
## OWN wander disc at scouting speed, mirroring DecomposerMarker.WANDER_
## DIRECTION_CHANGE_INTERVAL_SECONDS's own identical derivation exactly
## (see that constant's own doc comment for why: keeps this in proportion
## automatically if FORAGE_RADIUS_TILES/WALK_SPEED/SCOUT_SPEED_FRACTION
## are ever retuned, instead of silently drifting out of sync with them).
## A function, not a top-level const, since AntColony.FORAGE_RADIUS_TILES
## is itself a real value at load time, not a compile-time constant this
## file could fold in directly.
func _scout_direction_change_interval() -> float:
	return (
		(AntColony.FORAGE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE))
		/ (WALK_SPEED * SCOUT_SPEED_FRACTION)
	)


## For World's mouse-hover tooltip (see docs/concept/soil_fauna.md "Ants at
## half their old size, and finally hoverable"). No get_hover_actions() --
## an autonomous colony worker, not something a player commands, the same
## name-only-hoverable shape LumberjackMarker/DecomposerMarker's own
## non-interactive workers already use.
func get_display_name() -> String:
	return "Ant"


## Set by crush() -- once true, _process skips its whole round-trip walk and
## only ticks the linger clock, then (see is_corpse()) the corpse-decompose
## clock, before freeing.
var _dying := false
var _dying_elapsed := 0.0

## How long a settled corpse persists before decomposing on its own if
## nothing ever forages it (see is_corpse() and EarthChunkManager.
## take_ant_corpse_near) -- reused directly from EarthwormPatch's own
## corpse/recovery window (docs/concept/soil_fauna.md "A corpse is new
## ground") rather than a second, independently-eyeballed lifetime: both
## are "how long should a small creature's corpse realistically linger
## before something has found it, or it has rotted away" the same
## real-world question, so there is no reason for the two to differ.
const CORPSE_MAX_AGE_SECONDS := EarthwormPatch.RECOVERY_SECONDS


## Whether this dead forager has finished its brief death animation and
## settled into a real, discoverable corpse -- see docs/concept/
## soil_fauna.md "Ant corpses: foraged home, not left to vanish". A
## computed property of the existing _dying/_dying_elapsed state (no
## separate stored flag needed): still mid-SquashCrushEffect-linger reads
## false (matching the shared TINT-and-hold every crushed creature plays
## through first), true from the moment that linger completes until this
## marker actually frees itself (either foraged -- see
## EarthChunkManager.take_ant_corpse_near -- or, failing that, once it
## decomposes on its own past CORPSE_MAX_AGE_SECONDS, see _process below).
func is_corpse() -> bool:
	return _dying and _dying_elapsed >= SquashCrushEffect.LINGER_SECONDS


## Called by EarthChunkManager.crush_ants_near in place of an instant
## queue_free() -- see docs/concept/soil_fauna.md's own "no corpse/recovery
## state ... no timed death animation either" scope cut, now closed.
## IllustratedDecomposerSprite's "ant" art has no dedicated crushed pose at
## all, so this reuses SquashCrushEffect's shared TINT (the same "no
## longer alive" tell every other crushed creature shows), applied to
## whatever frame (walk or carry) this forager happened to be showing at
## the moment it died -- but deliberately WITHOUT SquashCrushEffect's own
## VERTICAL_SQUASH flatten. Reported live: "crushed ants should have the
## same size as normal ants... atm ants seem to disappear". An ant's own
## live marker_scale is already tiny (IllustratedDecomposerSprite.
## ANT_WORLD_WIDTH is 4.5px against a several-hundred-pixel source frame,
## scale.y measured around 0.013 in practice) -- even the RELATIVE squash
## VERTICAL_SQUASH already is (see that constant's own doc comment: fixed
## once already, from an absolute overwrite that made a crushed ant
## balloon up huge) still shrinks an already-near-invisible sprite by
## another 65%, down toward a fraction of a percent of its texture height
## -- effectively gone. Idempotent, same contract as CaterpillarMarker.
## crush()/DecomposerMarker.crush(), both of which keep the full
## SquashCrushEffect.apply() treatment unchanged -- neither was reported,
## and neither starts anywhere near this small.
func crush() -> void:
	if _dying:
		return
	_dying = true
	_sprite.modulate = SquashCrushEffect.TINT


## Which leg of the round trip this forager is currently walking.
func _current_leg_target() -> Vector2:
	if _behavior.phase == AntForageBehavior.Phase.APPROACHING:
		return target_position
	return mound_position


## Distance-based update rate -- mirrors DecomposerMarker/MillipedeMarker/
## CreatureMarker's own _lod_step exactly (see SENSE_INTERVAL_SECONDS' own
## doc comment for why this class needed it: it never had it before,
## despite every sibling creature marker in this codebase already using
## it). Returns the delta to advance by when this frame should actually
## process, or NEGATIVE when it should be skipped (accumulated, not lost --
## see _take_lod_step).
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
## this is already off the hot path for everything nearby (see
## DecomposerMarker's own identical helper and doc comment).
func _nearest_player_position():
	if not is_inside_tree():
		return null
	if _cached_player == null or not is_instance_valid(_cached_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return null
		_cached_player = players[0]
	return _cached_player.position


const PerfProbe = preload("res://src/rendering/perf_probe.gd")


func _process(frame_delta: float) -> void:
	PerfProbe.begin("ant_forager._process")
	PerfProbe.count_instance("ant_forager (live)")
	_process_impl(frame_delta)
	PerfProbe.end("ant_forager._process")


func _process_impl(frame_delta: float) -> void:
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	_ensure_initialized()
	if _dying:
		_dying_elapsed += delta
		# Past the death-animation linger AND the full corpse window with
		# nothing ever foraging it (see is_corpse()/CORPSE_MAX_AGE_SECONDS)
		# -- decomposes on its own, the same eventual fallback cleanup
		# EarthwormPatch's own corpse/recovery clock already has. A corpse
		# actually FOUND and foraged instead frees via EarthChunkManager.
		# take_ant_corpse_near calling queue_free() directly -- this branch
		# only ever fires for one nothing ever claimed.
		if _dying_elapsed >= SquashCrushEffect.LINGER_SECONDS + CORPSE_MAX_AGE_SECONDS:
			queue_free()
		return
	_elapsed_time += delta
	if _behavior.phase == AntForageBehavior.Phase.SCOUTING:
		_step_scouting(delta)
		return
	var leg_target := _current_leg_target()
	if position.distance_to(leg_target) > ARRIVE_DISTANCE_PX:
		# move_toward, not += direction * speed * delta -- the exact
		# overshoot-and-orbit-forever bug DecomposerMarker._step_approaching
		# once hit (a short leg + one big step overshoots past the target,
		# then overshoots back, forever), avoided here from the start.
		position = position.move_toward(leg_target, WALK_SPEED * delta)
		if (
			_behavior.phase == AntForageBehavior.Phase.RETURNING
			and _is_cluster_find and not _trail_invalidated
		):
			_maybe_deposit_trail_tile()
		return
	match _behavior.phase:
		AntForageBehavior.Phase.APPROACHING:
			_resolve_arrival_at_food()
			_update_sprite()
			_update_carried_leaf()
			_update_carried_corpse()
		AntForageBehavior.Phase.RETURNING:
			_resolve_arrival_at_mound()
			queue_free()


## No known target: wander (home-anchored at the mound, see _ready), local
## pheromone gradient biasing which way (real chemotaxis -- see
## AntScoutWander), sensing only its own immediate vicinity for real food
## (see _sense_food_nearby) as it goes. Gives up (see AntForageBehavior.
## give_up_scouting) past MAX_SCOUT_SECONDS of fruitless wandering, same
## "still walks home, just empty-handed" contract an unsuccessful
## APPROACHING trip already has.
func _step_scouting(delta: float) -> void:
	if _elapsed_time >= MAX_SCOUT_SECONDS:
		_behavior.give_up_scouting()
		_update_sprite()
		return
	# Throttled independent of SimulationLod above -- see
	# SENSE_INTERVAL_SECONDS' own doc comment: even a full-rate scout
	# doesn't need to re-run three world-area scans every single frame.
	_sense_accumulator += delta
	var found := {}
	if _sense_accumulator >= SENSE_INTERVAL_SECONDS:
		_sense_accumulator = 0.0
		found = _sense_food_nearby()
	if not found.is_empty():
		target_position = found.position
		forage_kind = found.kind
		carried_leaf_species = found.get("species", "")
		carried_leaf_season = found.get("season", "")
		_cluster_size = found.get("cluster_size", 1)
		_is_cluster_find = _cluster_size >= AntColony.CLUSTER_THRESHOLD
		_behavior.commit_to_food()
		_update_sprite()
		return
	# A resolver's whole job is to reliably reach a KNOWN cluster, not
	# explore -- if a real trail is sensed nearby, follow its own stored
	# direction exactly (no blending with ambient wander at all: unlike a
	# scout's own soft gradient_direction bias, this is a deliberate,
	# purposeful step, the same "follow / resolve the pheromone trails"
	# distinct role reported live). A scout never takes this branch at all
	# (dispatch only ever sends resolvers where a trail is already known
	# to exist -- see EarthChunkManager's own dispatch choice).
	if resolver and _colony != null:
		var trail := _colony.nearest_pheromone_trail_near(
			_mound_cell, position, float(TerrainRenderer.TILE_SIZE)
		)
		if not trail.is_empty():
			var trail_direction: Vector2 = trail.direction
			position += trail_direction * (WALK_SPEED * SCOUT_SPEED_FRACTION) * delta
			_face(trail_direction)
			return
	var wander_direction := _movement.direction_at(mound_position, position, _elapsed_time, wander_seed)
	var gradient := Vector2.ZERO
	if _colony != null:
		var field = _colony.pheromones_at(_mound_cell)
		if field != null:
			gradient = field.gradient_direction(position, float(TerrainRenderer.TILE_SIZE))
	var heading := AntScoutWander.biased_heading(wander_direction, gradient)
	heading = AntScoutWander.spread_heading(heading, assigned_heading_bias)
	position += heading * (WALK_SPEED * SCOUT_SPEED_FRACTION) * delta
	_face(heading)


## Real, LOCAL sensing -- ONLY within SENSE_RADIUS_TILES of this scout's
## OWN current position, never the mound's whole forage reach (see this
## file's own top doc comment: that wider, stationary-point query is
## exactly the omniscience being replaced). Leaf is checked first, same
## priority DecomposerMarker's own sensing already gives it, since it is
## not biome-gated at all -- then seed and windfall, both real, ordinary
## checks that simply come back empty wherever the world itself does not
## place that kind of food (grassland grows no fruiting trees; forest/
## rainforest grows no TallGrass), so no separate biome pre-filter is
## needed here the way the old per-mound dispatch required one. Returns
## {} if nothing real is close enough yet, or {"kind", "position",
## "species"?, "season"?} for whichever real thing was found.
func _sense_food_nearby() -> Dictionary:
	if _world == null:
		return {}
	var sense_radius_px := AntColony.SENSE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	var leaves: Array = _world.leaf_litter_near(position, sense_radius_px)
	if not leaves.is_empty():
		var leaf: Dictionary = leaves[0]
		return {
			"kind": "leaf", "position": leaf.position,
			"species": leaf.get("species", ""), "season": leaf.get("season", ""),
			"cluster_size": leaves.size(),
		}
	var sense_radius_tiles := int(ceil(AntColony.SENSE_RADIUS_TILES))
	var seeds: Array = _world.grass_seeds_near(position, sense_radius_tiles)
	seeds = seeds.filter(func(s): return position.distance_to(s["position"]) <= sense_radius_px)
	if not seeds.is_empty():
		return {"kind": "seed", "position": seeds[0]["position"], "cluster_size": seeds.size()}
	var fruit: Array = _world.fruit_near(position, sense_radius_tiles)
	fruit = fruit.filter(func(f): return position.distance_to(f["position"]) <= sense_radius_px)
	fruit = fruit.filter(func(f): return TreeSpecies.is_nut(String(f.get("species", ""))))
	if not fruit.is_empty():
		return {
			"kind": "windfall", "position": fruit[0]["position"],
			"species": fruit[0]["species"], "cluster_size": fruit.size(),
		}
	# Checked last -- an append-only addition, same priority every other
	# kind already has (see docs/concept/soil_fauna.md "Ant corpses:
	# foraged home, not left to vanish"). No biome gate needed, same
	# reason leaf litter has none: a dead ant can be lying anywhere any
	# mound's own scouts already range over.
	var corpses: Array = _world.ant_corpses_near(position, sense_radius_px)
	if not corpses.is_empty():
		return {"kind": "corpse", "position": corpses[0]["position"], "cluster_size": corpses.size()}
	return {}


## Shared by _update_sprite (which leg's geometry decides facing while
## APPROACHING/RETURNING) and _step_scouting (its own live wander heading
## decides facing instead, since there is no "leg" yet to read a direction
## from). Both sheets face left (IllustratedDecomposerSprite.faces_left)
## -- mirror only when actually heading right.
func _face(direction: Vector2) -> void:
	if absf(direction.x) > 0.01:
		_sprite.flip_h = direction.x > 0.0


## Real arrival at the food's own position: take it for real (re-checked
## HERE, not guaranteed by having been dispatched at all -- something else
## may have taken it first). Reported live: "these scouts should only lay
## out pheromones after they discovered a cluster... the last ant which
## takes home the last piece or one that encounters it empty invalidates
## the pheromone trail" -- a solo (non-cluster) find never touches the
## pheromone field at all any more, in either direction. A cluster find
## either keeps recruiting (something real is still left nearby -- the
## actual trail-laying happens progressively on the walk home, see
## _process's RETURNING branch) or gets invalidated immediately: on a
## failed take (something else already emptied it) or on a successful
## take that turns out to be the last one.
func _resolve_arrival_at_food() -> void:
	var succeeded := false
	if _world != null:
		if forage_kind == "windfall":
			_carried_species = _world.take_fruit_at(target_position)
			succeeded = _carried_species != ""
		elif forage_kind == "leaf":
			succeeded = _world.consume_leaf_litter_at(target_position)
		elif forage_kind == "corpse":
			succeeded = _world.take_ant_corpse_near(target_position)
		else:
			succeeded = _world.take_grass_seed_at(target_position)
	_behavior.arrive_at_food(succeeded)
	if not (_is_cluster_find or resolver):
		return
	if not succeeded:
		_invalidate_trail_near(target_position)  # arrived to find it already empty
		return
	if _remaining_same_kind_count() <= 0:
		_invalidate_trail_near(target_position)  # took the last real item


## Real, LOCAL re-check (mirrors _sense_food_nearby's own per-kind query,
## at the food's own position rather than this ant's current one -- by
## now they are the same spot) -- how many of forage_kind are still there
## after this ant's own take. Reads the REAL world state fresh rather than
## doing arithmetic on the cluster_size sensed at commit time: the take
## itself already mutated the real data (consume_leaf_litter_at/
## take_grass_seed_at/take_fruit_at), so a fresh query already reflects
## one fewer -- no separate "minus one" bookkeeping needed, and no risk of
## drifting out of sync with whatever else might also be consuming the
## same cluster concurrently.
func _remaining_same_kind_count() -> int:
	if _world == null:
		return 0
	var sense_radius_px := AntColony.SENSE_RADIUS_TILES * float(TerrainRenderer.TILE_SIZE)
	var sense_radius_tiles := int(ceil(AntColony.SENSE_RADIUS_TILES))
	match forage_kind:
		"leaf":
			return _world.leaf_litter_near(target_position, sense_radius_px).size()
		"seed":
			return _world.grass_seeds_near(target_position, sense_radius_tiles).size()
		"windfall":
			var fruit: Array = _world.fruit_near(target_position, sense_radius_tiles)
			return fruit.filter(func(f): return TreeSpecies.is_nut(String(f.get("species", "")))).size()
		"corpse":
			return _world.ant_corpses_near(target_position, sense_radius_px).size()
	return 0


## Masks the trail as spent (see PheromoneField.invalidate_near) and
## remembers it locally so this ant's own walk home never lays a fresh
## one for something that no longer exists (see _process's RETURNING
## branch). SENSE_RADIUS_TILES, the same local-vicinity scale this
## marker's own sensing already uses, rather than reaching into
## PheromoneField's own RADIUS_TILES constant for a second, unrelated
## notion of "nearby".
func _invalidate_trail_near(pixel_position: Vector2) -> void:
	_trail_invalidated = true
	if _colony == null:
		return
	_colony.invalidate_pheromone_near(
		_mound_cell, pixel_position, AntColony.SENSE_RADIUS_TILES, float(TerrainRenderer.TILE_SIZE)
	)


## Lays one real trail marker per NEW tile crossed on the way home (see
## _process's RETURNING branch, which calls this only for a cluster find
## not yet invalidated) -- direction computed exactly toward the food's
## own real position from wherever this tile is, never inferred, so a
## later ant reading it near the mound heads OUT rather than mistaking
## the trail's own origin for its destination (reported live: "he encodes
## direction and amount in the pheromones so other ants don't follow it
## back into the mound").
func _maybe_deposit_trail_tile() -> void:
	if _colony == null:
		return
	var tile_size := float(TerrainRenderer.TILE_SIZE)
	var tile := Vector2i(floori(position.x / tile_size), floori(position.y / tile_size))
	if _has_deposited_trail_tile and tile == _last_trail_tile:
		return
	_has_deposited_trail_tile = true
	_last_trail_tile = tile
	var to_food := target_position - position
	var direction := to_food.normalized() if to_food.length() > 0.01 else Vector2.ZERO
	_colony.deposit_pheromone_trail(_mound_cell, tile, direction, float(_cluster_size))


## Real arrival back at the mound: tells the colony (and through it, the
## queen -- see AntColony.record_forage_result) whether this trip actually
## fed anyone, and, if it did, resolves the cache/consume roll exactly
## where a real ant would leave its find: at the mound, not out in the
## field where it was picked up (see docs/concept/soil_fauna.md's geometry
## note on this).
##
## Re-checked here, not just at dispatch: _colony is a direct object
## reference set once, at dispatch (see setup()) -- this marker is
## parented on the persistent _entities_parent node, not chunk-scoped (see
## this file's own header doc comment), so it keeps walking its whole real
## round trip even after its own mound's chunk unloads out from under it.
## EarthChunkManager._unload_chunk erases the manager's OWN dictionary
## entry, but that alone cannot free an object this forager itself still
## references -- without is_retired(), a successful trip would silently
## resolve against that now-orphaned colony (both the record_forage_result
## deposit AND, below, the real seed/nut cached into the world) instead of
## whatever fresh one _load_chunk built if the player later returns (see
## docs/concept/soil_fauna.md's "In-flight foragers survive an unload;
## their trip's outcome does not", mirroring BeeForagerMarker.
## _resolve_arrival_at_hive's own identical guard). The whole function
## returns before either half runs -- not just the record_forage_result
## call -- so a retired colony's forager also never plants/caches what it
## was carrying: the honest "this trip's outcome is lost" consequence,
## same as bees, not a partial effect landing on a mound nobody can reach.
func _resolve_arrival_at_mound() -> void:
	if _colony == null or _colony.is_retired():
		return
	_colony.record_forage_result(_mound_cell, _behavior.found_food)
	if not _behavior.found_food or _world == null:
		return
	if forage_kind == "windfall" and AntColony.windfall_is_consumed(_colony.windfall_carrier_seed_for(_mound_cell)):
		return  # eaten on the spot at the mound -- no cache leg
	if forage_kind == "leaf" or forage_kind == "corpse":
		return  # real detritus/food, not a propagule -- consumed already, never re-cached
	var carrier_seed := _colony.carrier_seed_for(_mound_cell)
	var carry_tiles := AntColony.carry_distance_tiles(carrier_seed)
	var direction: Vector2 = AntColony.carry_direction(carrier_seed)
	var cache_target := mound_position + direction * carry_tiles * float(TerrainRenderer.TILE_SIZE)
	if forage_kind == "windfall":
		_world.try_plant_seed_at(cache_target, _carried_species)
	else:
		_world.plant_grass_at(cache_target)


## Empty-handed (walking to the pickup, or returning with nothing to show
## for it) shows the plain walk cycle; carrying real food back shows
## ant.png's own dedicated carry row.
func _update_sprite() -> void:
	var carrying := _behavior.phase == AntForageBehavior.Phase.RETURNING and _behavior.found_food
	if carrying == _carrying and _sprite.texture != null:
		return
	_carrying = carrying
	var action := "carry" if carrying else "walk"
	if _illustrated_generator.has_action("ant", action):
		_sprite.texture = _illustrated_generator.generate_textures("ant", action)[0]
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale("ant", action)
		_face(_current_leg_target() - position)
	else:
		_sprite.texture = _procedural_generator.generate_texture("ant")
		_sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
		_sprite.flip_h = false


## How far behind the ant's own centre the carried leaf sits, so it reads as
## dragged along the ground rather than perfectly overlapping the ant's own
## body -- half the leaf's own rendered size (LeafLitterRenderer.WORLD_SIZE),
## the same "proportional to the real thing being placed" grounding this
## codebase already uses elsewhere (e.g. AntColony's own carry_distance_tiles)
## rather than an eyeballed pixel count.
const _TRAIL_OFFSET_FRACTION := 0.5


## The real, visible leaf riding home with the ant (see docs/concept/
## soil_fauna.md's "Resolved" note on this bug) -- shown for the whole
## RETURNING leg of a successful leaf trip, never just a flash at pickup:
## unlike _update_sprite (which only ever needs to flip its OWN texture
## between two known frames), this sprite's texture/scale/position are only
## ever set ONCE, the same single moment _update_sprite is itself called
## (real arrival at the food -- see _process's APPROACHING branch), since
## nothing about a carried leaf changes for the rest of the straight-line
## walk home. Frees automatically (as a child) the instant the whole
## forager does, at real arrival at the mound -- see _resolve_arrival_at_
## mound/_process's RETURNING branch -- so "vanish only when it's in the
## mound" falls out of ordinary Godot node ownership, not extra bookkeeping
## here.
func _update_carried_leaf() -> void:
	var carrying_leaf := (
		forage_kind == "leaf"
		and _behavior.phase == AntForageBehavior.Phase.RETURNING
		and _behavior.found_food
	)
	_leaf_sprite.visible = carrying_leaf
	if not carrying_leaf:
		return
	_leaf_sprite.texture = _leaf_texture_for(carried_leaf_species, carried_leaf_season)
	_leaf_sprite.scale = Vector2.ONE * (LeafLitterRenderer.WORLD_SIZE / float(LeafLitterAtlas.STAMP_SIZE))
	var to_mound := mound_position - position
	var trail_direction := -to_mound.normalized() if to_mound.length() > 0.01 else Vector2.ZERO
	_leaf_sprite.position = trail_direction * LeafLitterRenderer.WORLD_SIZE * _TRAIL_OFFSET_FRACTION


## The real, visible corpse riding home with the ant (see docs/concept/
## soil_fauna.md "Ant corpses: foraged home, not left to vanish" --
## reported live: "they get visibly dragged into the mound") -- shown for
## the whole RETURNING leg of a successful corpse trip, same "set once at
## real arrival, never touched again for the rest of the straight-line
## walk home" shape _update_carried_leaf already establishes, same trailing-
## behind-the-body positioning (ANT_WORLD_WIDTH standing in for
## LeafLitterRenderer.WORLD_SIZE -- the real thing being dragged is
## another ant now, not a leaf, so its own real-world size is what "how
## far behind" should be proportional to). No dedicated corpse texture to
## crop (IllustratedDecomposerSprite's "ant" art has no crushed pose any
## more than a live one does -- see AntForagerMarker.crush()'s own doc
## comment): reuses the identical texture _update_sprite's own "walk" pose
## already draws, tinted with SquashCrushEffect.TINT on top -- the same
## "no longer alive" tell the corpse itself showed, in place, before this
## ant ever picked it up.
func _update_carried_corpse() -> void:
	var carrying_corpse := (
		forage_kind == "corpse"
		and _behavior.phase == AntForageBehavior.Phase.RETURNING
		and _behavior.found_food
	)
	_corpse_sprite.visible = carrying_corpse
	if not carrying_corpse:
		return
	if _illustrated_generator.has_action("ant", "walk"):
		_corpse_sprite.texture = _illustrated_generator.generate_textures("ant", "walk")[0]
		_corpse_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale("ant", "walk")
	else:
		_corpse_sprite.texture = _procedural_generator.generate_texture("ant")
		_corpse_sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	_corpse_sprite.modulate = SquashCrushEffect.TINT
	var to_mound := mound_position - position
	var trail_direction := -to_mound.normalized() if to_mound.length() > 0.01 else Vector2.ZERO
	_corpse_sprite.position = trail_direction * IllustratedDecomposerSprite.ANT_WORLD_WIDTH * _TRAIL_OFFSET_FRACTION


## Crops `species`/`season`'s own stamp out of the SAME shared atlas texture
## LeafLitterRenderer's ground-litter shader samples (see LeafLitterAtlas),
## via the exact same cell_index/CELL_SIZE/STAMP_PADDING/STAMP_SIZE pixel
## math that atlas already exposes -- so a carried leaf is genuinely the
## SAME art a ground-resting one of this species/season would show, not an
## independent lookalike. AtlasTexture (not a fresh cropped Image) so this
## costs no new texture upload: it shares the ground renderer's own already-
## built atlas_texture() outright.
static func _leaf_texture_for(species: String, season: String) -> AtlasTexture:
	var index := _leaf_atlas.cell_index(species, season)
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = _leaf_atlas.atlas_texture()
	atlas_tex.region = Rect2(
		index * LeafLitterAtlas.CELL_SIZE + LeafLitterAtlas.STAMP_PADDING, LeafLitterAtlas.STAMP_PADDING,
		LeafLitterAtlas.STAMP_SIZE, LeafLitterAtlas.STAMP_SIZE
	)
	return atlas_tex
