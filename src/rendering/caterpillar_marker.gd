extends Node2D

## A caterpillar -- requested live: "wire caterpillars which live on trees
## and on the ground around them; they should also do groundforaging and
## eat green leaves (spring, summer only)". Mirrors DecomposerMarker's own
## shape closely: deliberately NOT built on CreatureMarker/CreatureInfo --
## that stack is a full roaming-wildlife AI, the wrong shape for a tiny
## insect whose entire behaviour is "find food, eat it, wander otherwise".
## Ambient wander reuses the same shared, already-tested AmbientFlyerMovement
## algorithm DecomposerMarker/AmbientFlyerMarker both already use.
##
## Two real food sources, picked between by whichever is nearer, exactly the
## way AmbientFlyerMarker's own bird picks between worm/fruit/seed:
##   - real, in-season (GREEN) fallen leaf litter on the ground -- an old
##     brown, still-decaying autumn leaf (LeafLitterField's own 270-day
##     lifespan means one absolutely can still be lying around come spring/
##     summer) is not what this eats, only a leaf whose OWN recorded season
##     is spring or summer.
##   - a real nearby tree (EarthChunkManager.trees_near, the same query
##     AmbientFlyerMarker's bird idle-rest already perches on) -- climbed,
##     not walked to, and never removed or depleted: unlike a leaf, which is
##     a one-visit consumable, a tree is a place to visit repeatedly. Its
##     own EATING phase therefore has to end on a clock rather than run
##     "until it's gone" -- see CaterpillarForageBehavior.EAT_SECONDS's own
##     doc comment for why, and why that is also what makes "groundforaging"
##     something this creature is ever actually seen doing at all.
##
## Season gating (spring/summer only) lives entirely at the SPAWN decision
## (see CaterpillarRenderer), not here -- the same accepted approximation
## every other ambient decoration in this codebase already has (nothing
## re-validates a spawned flyer's own season/biome eligibility continuously
## either). Only the per-leaf green/brown filter above is checked at
## runtime, since that is real data already carried on each leaf record,
## not something that needs its own season query.
##
## Neither target needs a live Node2D reference the way DecomposerMarker's
## carcass/fruit/leaf-handle targets do: a leaf is re-verified (and
## consumed) in one call at the moment of the bite (EarthChunkManager.
## consume_leaf_litter_at's own best-effort contract already reports
## whether anything was really there), and a tree is never removed at all
## -- so a plain position + a "which kind" flag is everything _step_
## approaching/_step_eating need, mirroring AmbientFlyerMarker's own
## _worm_target: Vector2 (not a node) exactly.

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const IllustratedCaterpillarSprite = preload("res://src/rendering/illustrated_caterpillar_sprite.gd")
const CaterpillarForageBehavior = preload("res://src/gameplay/caterpillar_forage_behavior.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const SquashCrushEffect = preload("res://src/rendering/squash_crush_effect.gd")
const Metabolism = preload("res://src/gameplay/metabolism.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")

const GROUP_NAME := "caterpillar"

## How far this caterpillar can notice food -- short, a slow ground crawler
## doesn't range far. Same order of magnitude as DecomposerMarker.
## SEARCH_RADIUS_PX (60.0), the closest sibling creature's own tuning.
const SEARCH_RADIUS_PX := 50.0
const TILE_SIZE := 16.0
const SEARCH_TILES := int(SEARCH_RADIUS_PX / TILE_SIZE)

## How close counts as "arrived", at either a leaf or a tree.
const ARRIVE_DISTANCE_PX := 4.0

## How far it wanders from home while nothing is around to eat.
const WANDER_RADIUS_PX := 24.0
## Requested directly: "they should be 66% slower", clarified immediately
## after as "1/3 of the speed" -- an exact fraction of the original 14.0,
## not a rounded approximation of "66% slower". WANDER_SPEED_FRACTION and
## WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS below both derive FROM this
## rather than duplicating it, so ambient wander slows down in the same
## proportion automatically.
const WALK_SPEED := 14.0 / 3.0
## Ambient wander is slower than a committed approach -- a hurrying
## caterpillar reads as one that has actually found something, same
## reasoning as DecomposerMarker.WANDER_SPEED_FRACTION.
const WANDER_SPEED_FRACTION := 0.35

## How high, in pixels, a caterpillar visually climbs while targeting a
## tree (see _step_climb) -- one tile's worth up the trunk, not into the
## canopy proper: a real caterpillar grazes low branches and the trunk
## itself at least as often as the crown, and a modest climb reads clearly
## without this class needing to know anything about ProceduralTreeSprite's
## own canopy dimensions, a dependency it has deliberately never had (see
## the class doc comment's "duck-typed" framing for trees_near itself).
const CLIMB_HEIGHT_PX := TILE_SIZE

## How long the illustrated crawl/climb/eat cycle holds each frame -- a flat
## elapsed-time cadence, same shape as DecomposerMarker.WALK_FRAME_DURATION_
## SECONDS. A caterpillar is a slower, chunkier gait than an ant's tiny fast
## legs, so this is longer.
const FRAME_DURATION_SECONDS := 0.16

## How much horizontal movement in one step counts as a real leftward/
## rightward heading worth flipping the sprite for -- mirrors
## DecomposerMarker.FACING_DEADZONE_PX exactly.
const FACING_DEADZONE_PX := 0.05

## Derived, not eyeballed -- how long a wandering caterpillar holds one
## exploring heading before AmbientFlyerMovement picks a new one, in
## seconds, from its own wander geometry (how long it would take to cross
## the whole wander radius at wander speed). Mirrors DecomposerMarker.
## WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS's identical derivation exactly,
## so a future change to WANDER_RADIUS_PX/WALK_SPEED/WANDER_SPEED_FRACTION
## keeps this in proportion automatically.
const WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS := (
	WANDER_RADIUS_PX / (WALK_SPEED * WANDER_SPEED_FRACTION)
)

var home := Vector2.ZERO
var wander_seed := 0

## This caterpillar's own real, live, unified body mass -- see
## docs/concept/metabolism.md. Lazily seeded (see current_mass_kg) from
## CreatureMass.mass_kg_for("caterpillar") the first time anything asks.
var _metabolism: Metabolism = null

var _behavior := CaterpillarForageBehavior.new()

## Where the current food target is, and which kind -- see the class doc
## comment for why this is a plain position rather than a live node
## reference. Null (_target_position) means "not currently pursuing
## anything", the same contract AmbientFlyerMarker's own _worm_target uses.
var _target_position = null  # Vector2, or null
var _target_is_tree := false

## How far up the trunk this caterpillar has visually climbed right now --
## purely a SPRITE offset (see _step_climb), never this node's own
## `position`: _step_approaching's arrival check, _nearest_food's distance
## comparisons, and anything that might Y-sort a caterpillar in the future
## all keep reading the real ground tile it is logically standing on. A
## caterpillar visually several pixels up a trunk is still, as far as
## every other system in this game is concerned, standing exactly where it
## always was -- the same "a plain position is everything approach/eat
## need" reasoning the class doc comment already draws for why a tree
## target needs no live node reference at all.
var _climb_height_px := 0.0

## Idle-wander motion -- reuses this one already-tested, home-anchored roam
## algorithm instead of a second, near-duplicate one. Built in _ready()
## rather than injected: a caterpillar's wander is always the same fixed
## geometry regardless of spawn site, so there is nothing for a caller to
## configure (same reasoning DecomposerMarker's own _movement field gives).
var _movement: AmbientFlyerMovement
var _elapsed_time := 0.0

var _sprite: Sprite2D
static var _illustrated_generator := IllustratedCaterpillarSprite.new()

## The owning EarthChunkManager, duck-typed for trees_near/
## nearest_leaf_litter_near/consume_leaf_litter_at -- optional, mirroring
## DecomposerMarker.setup's identical "narrows, doesn't break, a caterpillar
## built standalone" contract. Without it, this caterpillar simply never
## finds food and only ever wanders.
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
	return "Caterpillar"


## This caterpillar's own real, live, current body mass -- see
## docs/concept/metabolism.md.
func current_mass_kg() -> float:
	return _ensure_metabolism().current_mass_kg


func _ensure_metabolism() -> Metabolism:
	if _metabolism == null:
		_metabolism = Metabolism.new(CreatureMass.mass_kg_for("caterpillar"))
	return _metabolism


## Maps CaterpillarForageBehavior's own real Phase to Metabolism's small
## closed activity vocabulary (see docs/concept/metabolism.md's
## activity-tier table): actually eating is FEEDING, seeking/approaching
## (crawling or climbing toward food) is ordinary ambulatory MOVING.
func _current_metabolic_activity() -> String:
	if _behavior.phase == CaterpillarForageBehavior.Phase.EATING:
		return Metabolism.ACTIVITY_FEEDING
	return Metabolism.ACTIVITY_MOVING


## Set by crush() -- once true, _process skips every forage/wander/climb
## step entirely and only ticks the linger clock before freeing.
var _dying := false
var _dying_elapsed := 0.0


## Called by EarthChunkManager.crush_caterpillars_near (via
## _crush_markers_near) in place of an instant queue_free() -- see
## docs/concept/soil_fauna.md's own "No corpse state, no splat VFX" scope
## cut, now closed. Unlike MillipedeMarker.crush() there is no dedicated
## crushed row to play (caterpillar.png's four rows are crawl/climb/eat/rest
## -- no "crushed" pose was ever delivered, see IllustratedCaterpillarSprite's
## own doc comment), so this reuses SquashCrushEffect's shared procedural
## fallback instead, applied directly to whatever frame the caterpillar
## happened to be showing at the moment it died. Idempotent: a second crush
## call before the linger clock runs out does nothing further (in
## particular, never pushes _dying_elapsed back to 0).
func crush() -> void:
	if _dying:
		return
	_dying = true
	SquashCrushEffect.apply(_sprite)


## crawl: ambient wander, or approaching/eating ground litter -- level
## ground the whole time. climb: approaching OR eating at a tree -- the
## "eat" row's own head-down grazing pose reads fine questing partway up a
## trunk too, so only the APPROACH leg needs its own distinct pose; "rest"
## has no trigger wired in this first pass (named explicitly, not silently
## assumed -- see docs/concept/soil_fauna.md).
func _current_action() -> String:
	if _behavior.phase == CaterpillarForageBehavior.Phase.EATING:
		return "eat"
	if _behavior.phase == CaterpillarForageBehavior.Phase.APPROACHING and _target_is_tree:
		return "climb"
	return "crawl"


func _update_sprite(moved: Vector2) -> void:
	var action := _current_action()
	var frames := _illustrated_generator.generate_textures(action)
	_sprite.texture = frames[int(_elapsed_time / FRAME_DURATION_SECONDS) % frames.size()]
	_sprite.scale = Vector2.ONE * _illustrated_generator.world_scale()
	if absf(moved.x) > FACING_DEADZONE_PX:
		_sprite.flip_h = moved.x > 0.0


var _lod_accumulated := 0.0


## Distance-based update rate -- mirrors DecomposerMarker/CreatureMarker/
## AmbientFlyerMarker's own _lod_step exactly.
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


var _cached_player: Node = null


func _process(frame_delta: float) -> void:
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	if _dying:
		_dying_elapsed += delta
		if _dying_elapsed >= SquashCrushEffect.LINGER_SECONDS:
			queue_free()
		return
	_elapsed_time += delta
	# Real calorie burn (see docs/concept/metabolism.md): Kleiber's-law BMR
	# at this caterpillar's OWN current mass, scaled by its real
	# CaterpillarForageBehavior phase.
	_ensure_metabolism().advance(delta, _current_metabolic_activity())
	var position_before := position
	match _behavior.phase:
		CaterpillarForageBehavior.Phase.SEEKING:
			_step_seeking(delta)
		CaterpillarForageBehavior.Phase.APPROACHING:
			_step_approaching(delta)
		CaterpillarForageBehavior.Phase.EATING:
			_step_eating(delta)
	_step_climb(delta)
	_update_sprite(position - position_before)


## Requested directly: "caterpillars should crawl up trees" -- rises toward
## CLIMB_HEIGHT_PX at the same WALK_SPEED pace ground movement uses, for as
## long as a tree is the current target and the phase isn't SEEKING (i.e.
## rising through the walk there -- the same phase the "climb" sprite pose
## is already shown for, see _current_action -- and holding through
## EATING), then settling back to ground level once the phase returns to
## SEEKING. A leaf-litter visit never climbs at all: _target_is_tree stays
## false the whole time, so the target height is always 0.
func _step_climb(delta: float) -> void:
	var target_height := 0.0
	if _target_is_tree and _behavior.phase != CaterpillarForageBehavior.Phase.SEEKING:
		target_height = CLIMB_HEIGHT_PX
	_climb_height_px = move_toward(_climb_height_px, target_height, WALK_SPEED * delta)
	_sprite.position.y = -_climb_height_px


func _step_seeking(delta: float) -> void:
	position = _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	_behavior.advance(delta)  # no-op outside EATING, just ticks the rehunt clock
	if _behavior.can_commit():
		var found = _nearest_food()
		if found != null:
			_target_position = found["position"]
			_target_is_tree = found["is_tree"]
			_behavior.begin_approach()


## Nearest (by real distance) real food within SEARCH_RADIUS_PX -- a green
## fallen leaf, or a real tree -- as {position, is_tree}, or null. Both
## world queries are optional/duck-typed (see _world's own doc comment): a
## caterpillar with no world set, or a world missing one of the two
## methods, simply never finds that half of its diet.
func _nearest_food() -> Variant:
	if _world == null:
		return null
	var best_position = null
	var best_is_tree := false
	var best_distance := SEARCH_RADIUS_PX
	if _world.has_method("nearest_leaf_litter_near"):
		var leaf: Dictionary = _world.nearest_leaf_litter_near(position, best_distance)
		if not leaf.is_empty() and _is_green(String(leaf.get("season", ""))):
			var distance: float = position.distance_to(leaf["position"])
			if distance <= best_distance:
				best_position = leaf["position"]
				best_is_tree = false
				best_distance = distance
	if _world.has_method("trees_near"):
		for tree in _world.trees_near(position, SEARCH_TILES):
			var distance: float = position.distance_to(tree["position"])
			if distance <= best_distance:
				best_position = tree["position"]
				best_is_tree = true
				best_distance = distance
	if best_position == null:
		return null
	return {"position": best_position, "is_tree": best_is_tree}


## A leaf this caterpillar will actually eat: fallen in spring or summer,
## same "eats green, not brown" distinction docs/concept/leaf_litter.md
## itself draws between the small green spring/summer trickle and the
## large autumn fall. Mirrors FlowerSpecies.is_in_bloom's own
## season-membership shape.
static func _is_green(season: String) -> bool:
	return ["spring", "summer"].has(season)


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
	# DecomposerMarker._step_approaching already uses for the identical
	# reason.
	position = position.move_toward(_target_position, WALK_SPEED * delta)


func _step_eating(delta: float) -> void:
	if _target_position == null:
		_behavior.abort()
		return
	if _behavior.advance(delta):
		# A real intake event for this caterpillar's own unified mass (see
		# docs/concept/metabolism.md) -- no composition data exists for
		# green leaf litter or tree foliage, so (mirroring DecomposerMarker's
		# identical fallback) one landed bite is treated as one whole
		# meal's worth. Applies to BOTH real food sources (leaf or tree) --
		# a tree bite is a real bite too, even though the tree itself is
		# never removed (see below).
		_ensure_metabolism().feed_hunger_relief(1.0)
		if not _target_is_tree:
			# A leaf is a one-visit consumable (see the class doc comment) --
			# removed on the bite that lands, exactly like DecomposerMarker's
			# own leaf-litter case. Best-effort: if it's already gone (eaten by
			# something else between being spotted and this caterpillar
			# arriving), this simply does nothing further -- the phase still
			# closes out normally on CaterpillarForageBehavior's own EAT_
			# SECONDS clock either way.
			if _world != null and _world.has_method("consume_leaf_litter_at"):
				_world.consume_leaf_litter_at(_target_position)
	# A tree is never removed (see the class doc comment) -- nothing to do
	# on a bite there beyond the animation itself, which _update_sprite
	# already draws from _behavior.phase/_target_is_tree.
	if _behavior.phase != CaterpillarForageBehavior.Phase.EATING:
		# CaterpillarForageBehavior.advance closed the phase out itself
		# (EAT_SECONDS elapsed) -- clear the target so the next SEEKING
		# tick starts genuinely fresh rather than re-offering a stale
		# position to _nearest_food's own distance comparisons.
		_target_position = null
