extends Node2D

## A REAL forager (see docs/concept/soil_fauna.md "Real foraging: a round
## trip, not an instant resolve"): walks to a known food position, takes
## the food only on real arrival (re-checked then -- something else may
## have taken it first), walks back to the mound, and only THERE does the
## cache/consume roll resolve and the marker free itself. This used to be
## a purely decorative, one-shot walk along an already-resolved path;
## AntColony's own forage-and-cache resolution has moved out of
## EarthChunkManager's instant lookup and into the two real moments this
## marker itself now causes (see AntForageBehavior).
##
## Deliberately no SEEKING phase: the colony already found this real,
## reachable target before dispatching a forager at all (see
## EarthChunkManager._forage_seed_near_mound/_forage_windfall_near_mound,
## and PheromoneField.best_candidate_index for how that target is chosen
## when more than one candidate is in reach) -- this marker owns the walk
## and the two real world effects at each end, not target discovery.
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

## Where the real food is. Set before add_child, same convention as every
## other marker's per-instance fields.
var target_position: Vector2 = Vector2.ZERO
## Where this forager returns to once its trip resolves either way.
var mound_position: Vector2 = Vector2.ZERO
## "seed" (grass seed -- always survives to be planted) or "windfall"
## (fallen fruit/nut -- resolves through AntColony.windfall_is_consumed
## first, same as before). Decides which of the world's take/plant APIs
## this trip actually calls.
var forage_kind := "seed"

## Which leaf this trip is carrying, if `forage_kind == "leaf"` -- set at
## dispatch time (see EarthChunkManager._dispatch_ant_forager's own doc
## comment) from the SAME nearest_leaf_litter_near lookup that found
## target_position in the first place, so this marker never has to ask the
## world a second time just to know what the leaf it is about to carry
## home actually looks like. Left "" (the default) for seed/windfall trips,
## which have no such visual (see _update_carried_leaf).
var carried_leaf_species := ""
var carried_leaf_season := ""

## Whether this trip is a SCOUTING trip (see docs/concept/soil_fauna.md
## "Scouts mark leaf clusters, workers collect from marks") -- set at
## dispatch time by EarthChunkManager._scout_for_leaf_cluster_near_mound,
## which has already confirmed a real cluster exists at/near
## target_position before ever creating this marker. A scout walks, takes,
## and returns exactly like any other leaf trip (see _process/
## _resolve_arrival_at_mound, both untouched) -- the ONLY difference is
## that a successful arrival at the food ALSO marks the cluster (see
## _resolve_arrival_at_food), the same "on the way back" moment
## _deposit_pheromone_at already marks a single tile at.
var is_scout := false

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
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_leaf_sprite = Sprite2D.new()
	_leaf_sprite.visible = false
	add_child(_leaf_sprite)
	_update_sprite()


## For World's mouse-hover tooltip (see docs/concept/soil_fauna.md "Ants at
## half their old size, and finally hoverable"). No get_hover_actions() --
## an autonomous colony worker, not something a player commands, the same
## name-only-hoverable shape LumberjackMarker/DecomposerMarker's own
## non-interactive workers already use.
func get_display_name() -> String:
	return "Ant"


## Which leg of the round trip this forager is currently walking.
func _current_leg_target() -> Vector2:
	if _behavior.phase == AntForageBehavior.Phase.APPROACHING:
		return target_position
	return mound_position


func _process(delta: float) -> void:
	var leg_target := _current_leg_target()
	if position.distance_to(leg_target) > ARRIVE_DISTANCE_PX:
		# move_toward, not += direction * speed * delta -- the exact
		# overshoot-and-orbit-forever bug DecomposerMarker._step_approaching
		# once hit (a short leg + one big step overshoots past the target,
		# then overshoots back, forever), avoided here from the start.
		position = position.move_toward(leg_target, WALK_SPEED * delta)
		return
	match _behavior.phase:
		AntForageBehavior.Phase.APPROACHING:
			_resolve_arrival_at_food()
			_update_sprite()
			_update_carried_leaf()
		AntForageBehavior.Phase.RETURNING:
			_resolve_arrival_at_mound()
			queue_free()


## Real arrival at the food's own position: take it for real (re-checked
## HERE, not guaranteed by having been dispatched at all -- something else
## may have taken it first) and, on success, mark the spot with this
## mound's own trail pheromone so the NEXT dispatched forager can be drawn
## back to a known-good source (see PheromoneField). A scouting trip
## (is_scout) additionally marks the whole CLUSTER it was sent to confirm
## (see docs/concept/soil_fauna.md "Scouts mark leaf clusters, workers
## collect from marks") -- the dispatcher (EarthChunkManager._scout_for_
## leaf_cluster_near_mound) already verified one exists at target_position
## before creating this marker at all, so a successful pickup here is
## enough to commit it to this mound's own memory.
func _resolve_arrival_at_food() -> void:
	var succeeded := false
	if _world != null:
		if forage_kind == "windfall":
			_carried_species = _world.take_fruit_at(target_position)
			succeeded = _carried_species != ""
		elif forage_kind == "leaf":
			succeeded = _world.consume_leaf_litter_at(target_position)
		else:
			succeeded = _world.take_grass_seed_at(target_position)
	_behavior.arrive_at_food(succeeded)
	if succeeded and _colony != null:
		_deposit_pheromone_at(target_position)
		if is_scout and forage_kind == "leaf":
			_colony.mark_cluster(_mound_cell, target_position)


func _deposit_pheromone_at(pixel_position: Vector2) -> void:
	var tile_size := float(TerrainRenderer.TILE_SIZE)
	var tile := Vector2i(floori(pixel_position.x / tile_size), floori(pixel_position.y / tile_size))
	_colony.deposit_pheromone(_mound_cell, tile)


## Real arrival back at the mound: tells the colony (and through it, the
## queen -- see AntColony.record_forage_result) whether this trip actually
## fed anyone, and, if it did, resolves the cache/consume roll exactly
## where a real ant would leave its find: at the mound, not out in the
## field where it was picked up (see docs/concept/soil_fauna.md's geometry
## note on this).
func _resolve_arrival_at_mound() -> void:
	if _colony != null:
		_colony.record_forage_result(_mound_cell, _behavior.found_food)
	if not _behavior.found_food or _world == null or _colony == null:
		return
	if forage_kind == "windfall" and AntColony.windfall_is_consumed(_colony.windfall_carrier_seed_for(_mound_cell)):
		return  # eaten on the spot at the mound -- no cache leg
	if forage_kind == "leaf":
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
		# Both sheets face left (IllustratedDecomposerSprite.faces_left) --
		# this marker walks purely along its own current leg's geometry
		# with no other facing logic, so mirror only when actually heading
		# right.
		var to_target := _current_leg_target() - position
		if absf(to_target.x) > 0.01:
			_sprite.flip_h = to_target.x > 0.0
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
