extends Node2D

## An ant or carrion bug -- the decomposer tier that finishes what a
## player's own butchering doesn't, and (see _nearest_food) an opportunistic
## forager of fallen fruit/nuts too, not a carrion specialist (see
## docs/concept/carrion.md). Deliberately NOT built on CreatureMarker/
## CreatureInfo -- that stack is a full roaming-wildlife AI (flee/fight/hunt/
## graze/mate/ecosystem population tracking), the wrong shape for a tiny
## insect whose entire behaviour is "find food, eat it, wander otherwise".
## Mirrors AmbientFlyerMarker instead (home-anchored ambient wander via the
## shared AmbientFlyerMovement algorithm, no ecosystem population math).
##
## Scans the Carcass/CarcassGuts/DroppedItem groups directly (the same
## get_tree().get_nodes_in_group shape Player's own melee-sweep steps
## already use) for MOST of its food -- there's nothing chunk-specific about
## "is there a carcass/dropped fruit nearby" the way there is for e.g. worms,
## which live in a per-chunk sim. Fallen-leaf litter is the one exception
## (see docs/concept/leaf_litter.md): it is chunk-specific data now (see
## LeafLitterField), so this marker takes an OPTIONAL injected `_world`
## reference just for that one case -- mirroring CreatureMarker's own
## identical `_world` pattern (defaults null, guarded everywhere it's used)
## -- narrowing, not breaking, this file's own "no chunk-specific
## dependency" principle the same way it already special-cases worms (a
## decomposer with no `_world` set simply never finds leaf litter, and keeps
## foraging carrion/fruit exactly as before).

## A never-added stand-in Node2D for "the fallen leaf currently being
## forages" (see _nearest_food's leaf-litter branch) -- litter has no real
## scene node of its own any more (see LeafLitterField/LeafLitterRenderer),
## so _step_feeding needs SOMETHING with a `position` to walk toward and
## arrive at. consume_leaf_litter() is the one action available on it,
## checked by _step_feeding the same way `.has_method("take_bite")` already
## distinguishes a Carcass/CarcassGuts target from a fallen-fruit DroppedItem.
class LeafForageHandle:
	extends Node2D
	var _world = null

	func consume_leaf_litter() -> void:
		if _world != null and _world.has_method("consume_leaf_litter_at"):
			_world.consume_leaf_litter_at(position)

const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const IllustratedDecomposerSprite = preload("res://src/rendering/illustrated_decomposer_sprite.gd")
const CarrionForageBehavior = preload("res://src/gameplay/carrion_forage_behavior.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const CarcassGuts = preload("res://src/rendering/carcass_guts.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const SimulationLodClock = preload("res://src/gameplay/simulation_lod_clock.gd")
const SimulationScheduler = preload("res://src/gameplay/simulation_scheduler.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const AmbientFlyerMovement = preload("res://src/rendering/ambient_flyer_movement.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const SquashCrushEffect = preload("res://src/rendering/squash_crush_effect.gd")
const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const MushroomEffect = preload("res://src/gameplay/mushroom_effect.gd")
const DebuffStack = preload("res://src/gameplay/debuff_stack.gd")
const Metabolism = preload("res://src/gameplay/metabolism.gd")
const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")

const GROUP_NAME := "decomposer"

## How far this decomposer can notice carrion -- short, an ant doesn't smell
## a carcass across the whole chunk.
const SEARCH_RADIUS_PX := 60.0
## How close counts as "arrived".
const ARRIVE_DISTANCE_PX := 4.0
## How far it wanders from home while nothing is around to eat.
const WANDER_RADIUS_PX := 24.0
const WALK_SPEED := 24.0
## Ambient wander is slower than a committed approach -- a hurrying insect
## reads as one that has actually found something.
const WANDER_SPEED_FRACTION := 0.35
## How much decompose/consume health one bite removes -- see
## Carcass.DECOMPOSE_HEALTH / CarcassGuts.CONSUME_HEALTH.
const BITE_AMOUNT := 1.0

## How much residual walking activity a decomposer keeps at the coldest
## real soil reading (see docs/concept/seasonal_behavior.md, "Decomposer
## 'bug' cold-slowdown") -- a real ground beetle shelters and slows
## drastically in cold soil, it does not vanish. Deliberately matches
## AntColony/BeeColony/WildBeePatch's own DORMANCY_FLOOR value exactly,
## the same "never literally zero" reasoning, not a coincidence -- this
## marker has no aggregate economy for a shared base class to hang a real
## constant off of (see this file's own class doc comment on why it is
## deliberately not built on that stack), so the value is restated here
## rather than imported from an unrelated colony class.
const DORMANCY_FLOOR := 0.2

## [DORMANCY_FLOOR, 1.0]: how much of full wander/approach speed this
## decomposer keeps at the given real soil/air warmth reading. Reuses
## EarthwormPatch's own COLD_CUTOFF/MILD_WARMTH ramp exactly -- same soil,
## same real signal every other cold-weather mechanism in this game
## already reads (AntColony/BeeColony.dormancy_multiplier_at,
## EarthwormPatch.surface_drive).
static func activity_multiplier_for(warmth: float) -> float:
	var cold_gate := clampf(
		(warmth - EarthwormPatch.COLD_CUTOFF) / (EarthwormPatch.MILD_WARMTH - EarthwormPatch.COLD_CUTOFF),
		0.0, 1.0
	)
	return DORMANCY_FLOOR + (1.0 - DORMANCY_FLOOR) * cold_gate

## How long the illustrated walk/idle cycle holds each frame -- a flat
## elapsed-time cadence (mirrors CreatureMarker._animation_step's own
## non-gait fallback), not stride-distance-based: an ant's real per-frame
## leg travel is tiny enough that the difference is not worth a second
## distance-tracking field on top of _elapsed_time, which this marker
## already keeps for its wander heading. Faster than
## CreatureMarker.ANIMATION_FRAME_DURATION (0.3) -- carrion.md's own "small,
## fast" framing for an ant calls for snappier legs than a grazing
## quadruped's gait.
const WALK_FRAME_DURATION_SECONDS := 0.12
## How much horizontal movement in one step counts as a real leftward/
## rightward heading worth flipping the sprite for -- below this, a step
## that is mostly vertical (or FEEDING's own zero movement) leaves facing
## exactly as it was rather than flickering on near-zero noise.
const FACING_DEADZONE_PX := 0.05

## How long a wandering decomposer holds one exploring heading before
## AmbientFlyerMovement picks a new one, in seconds. Derived from the
## decomposer's own wander geometry -- how long it would take to cross the
## whole wander radius at wander speed -- rather than an eyeballed guess, so
## a change to WANDER_RADIUS_PX/WALK_SPEED/WANDER_SPEED_FRACTION keeps this
## in proportion automatically instead of silently drifting out of sync with
## them. Pinned by test_wander_direction_change_interval_is_derived_not_
## eyeballed.
const WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS := (
	WANDER_RADIUS_PX / (WALK_SPEED * WANDER_SPEED_FRACTION)
)

## "ant" or "bug" -- which sprite/silhouette this decomposer draws (see
## ProceduralDecomposerSprite). Set before add_child, same convention as
## every other marker in this codebase.
var species := "ant"
var home := Vector2.ZERO
var wander_seed := 0

## This decomposer's own real, live, unified body mass -- see
## docs/concept/metabolism.md. Lazily seeded (see current_mass_kg) from
## CreatureMass.mass_kg_for(species) the first time anything asks.
var _metabolism: Metabolism = null

## Anthrax-like carry vector (docs/concept/disease.md's CARRION archetype):
## real blowflies/carrion beetles mechanically carry spores from an infected
## carcass to the next one they feed on -- this decomposer IS that insect
## (see carrion.md), so it carries the disease rather than a separate vector
## being invented. Picked up feeding on a Carcass whose `contaminated` is
## true (see _step_disease_carry); passed on to the next clean Carcass fed
## on afterward. CarcassGuts is not part of this loop -- disease.md scopes
## the anthrax archetype to carcasses/patches, not offal.
var carrying_disease := false
var _disease_model := DiseaseModel.new()
var _disease_roll_count := 0

## Real seconds left before this decomposer will consider a mushroom bite
## again, set from MushroomBiting.satiation_seconds_for(this decomposer's
## own real mass) on a successful bite (see _step_feeding) -- the report's
## own "a small bug... is satisfied for a few hours" (docs/concept/
## soil_fauna.md's "Progressive, mass-scaled bites, and real toxic
## effects"). Deliberately narrow: gates ONLY the mushroom branch of
## _nearest_food, not carrion/fruit/leaf-litter foraging, which this
## marker has no general hunger concept for at all and this pass does not
## add one.
var _mushroom_satiation_remaining := 0.0

## Toxic mushroom effects (docs/concept/mushrooms.md's "Toxic effects:
## disorientation and illness", docs/concept/soil_fauna.md's "Progressive,
## mass-scaled bites, and real toxic effects", MushroomEffect) -- the
## exact real, reported case: "i just saw a bug eat a psylo and it didn't
## do anything to it." Mirrors CreatureMarker's own active_spell_debuffs/
## active_mushroom_debuffs shape exactly (a DebuffStack-tracked array),
## extended to a decomposer for the first time -- this marker had no
## timed-effect concept at all before this.
var active_mushroom_debuffs: Array = []
var _debuff_stack := DebuffStack.new()
## Which real species most recently caused the CURRENT effect -- see
## CreatureMarker._mushroom_effect_species' own doc comment for why this
## single field (not per-stack) is an accepted, documented simplification.
var _mushroom_effect_species := ""

var _behavior := CarrionForageBehavior.new()
var _target: Node2D = null

## Idle-wander motion (see AmbientFlyerMarker's identical use) -- reuses this
## one already-tested, home-anchored roam algorithm instead of a second,
## near-duplicate one, per its own doc comment's stated purpose. Built in
## _ready() rather than injected: unlike a flyer's per-species tuning, a
## decomposer's wander is always the same fixed WANDER_RADIUS_PX/WALK_SPEED
## regardless of species/spawn site, so there is nothing for a caller to
## configure.
var _movement: AmbientFlyerMovement
var _elapsed_time := 0.0

var _sprite: Sprite2D
static var _procedural_generator := ProceduralDecomposerSprite.new()
static var _illustrated_generator := IllustratedDecomposerSprite.new()

## The owning EarthChunkManager, for leaf-litter foraging ONLY (see
## _nearest_food's own leaf-litter branch) -- optional and duck-typed, the
## same `_world`/setup shape CreatureMarker already uses. A decomposer built
## standalone (most of this file's own tests) simply never finds leaf
## litter and keeps foraging carrion/fruit exactly as it always has.
var _world = null


## Gives this decomposer the world it can query for chunk-specific leaf
## litter (see _world's own doc comment). Without it, _nearest_food falls
## back to carrion/fruit foraging only, exactly as before this feature.
func setup(world) -> void:
	_world = world


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_update_sprite(Vector2.ZERO)
	_movement = AmbientFlyerMovement.new(
		WALK_SPEED * WANDER_SPEED_FRACTION, WANDER_RADIUS_PX, WANDER_DIRECTION_CHANGE_INTERVAL_SECONDS
	)


## For World's mouse-hover tooltip. HoverTargetFinder was already preloaded
## here (see the const above) but never actually wired up -- see
## docs/concept/soil_fauna.md "Ants at half their old size, and finally
## hoverable". No get_hover_actions() -- an autonomous forager, not
## something a player commands, mirroring LumberjackMarker's own
## name-only-hoverable shape for the identical reason.
func get_display_name() -> String:
	return species.capitalize()


## This decomposer's own real, live, current body mass -- see
## docs/concept/metabolism.md. The ONE thing a real consumer (mushroom
## bite-count/satiation scaling) should read instead of the flat
## CreatureMass.mass_kg_for(species) table.
func current_mass_kg() -> float:
	return _ensure_metabolism().current_mass_kg


func _ensure_metabolism() -> Metabolism:
	if _metabolism == null:
		_metabolism = Metabolism.new(CreatureMass.mass_kg_for(species))
	return _metabolism


## Maps CarrionForageBehavior's own real Phase to Metabolism's small closed
## activity vocabulary (see docs/concept/metabolism.md's activity-tier
## table): actually feeding is FEEDING, seeking/approaching is ordinary
## ambulatory MOVING.
func _current_metabolic_activity() -> String:
	if _behavior.phase == CarrionForageBehavior.Phase.FEEDING:
		return Metabolism.ACTIVITY_FEEDING
	return Metabolism.ACTIVITY_MOVING


## Set by crush() -- once true, _process skips every forage/wander step
## entirely and only ticks the linger clock before freeing.
var _dying := false
var _dying_elapsed := 0.0


## Called by EarthChunkManager.crush_decomposers_near (via
## _crush_markers_near) in place of an instant queue_free() -- see
## docs/concept/soil_fauna.md's own "no corpse/recovery state" scope cut,
## now closed. Neither the "ant" nor "bug" sheet has a dedicated crushed
## pose, so this reuses SquashCrushEffect's shared procedural fallback,
## applied to whichever species/action frame this decomposer happened to be
## showing at the moment it died. Idempotent, same contract as
## CaterpillarMarker.crush()/AntForagerMarker.crush().
func crush() -> void:
	if _dying:
		return
	_dying = true
	SquashCrushEffect.apply(_sprite)


## FEEDING (biting in place) shows the idle cycle (legs gathered) -- a
## stationary decomposer with animated walking legs would read as sliding
## in place. Every other phase (ambient wander, committed approach) shows
## the walk cycle.
func _current_action() -> String:
	if _behavior.phase == CarrionForageBehavior.Phase.FEEDING:
		return "idle"
	return "walk"


## Rebuilds the sprite for however this decomposer is behaving right now:
## real illustrated art where IllustratedDecomposerSprite has it for this
## species/action (checked first, same has_X()-gated fallback convention
## every other optional illustrated-art seam in this codebase uses),
## ProceduralDecomposerSprite's single static silhouette otherwise. `moved`
## is how far position actually changed this step (Vector2.ZERO for
## FEEDING, which never moves) -- see FACING_DEADZONE_PX's own doc comment
## for why only a real horizontal step flips the sprite.
func _update_sprite(moved: Vector2) -> void:
	var action := _current_action()
	if _illustrated_generator.has_action(species, action):
		var frames := _illustrated_generator.generate_textures(species, action)
		_sprite.texture = frames[int(_elapsed_time / WALK_FRAME_DURATION_SECONDS) % frames.size()]
		_sprite.scale = Vector2.ONE * _illustrated_generator.marker_scale(species, action)
		# Both registered sheets face left (IllustratedDecomposerSprite.
		# faces_left) -- mirror only for a real rightward step, matching
		# CreatureMarker.facing_sign's own "flip_h means mirrored from the
		# source art" convention, simplified: an ant has no commit-window/
		# moonwalk guard, it is small and fast enough that an occasional
		# flip on ambiguous near-vertical noise is not worth the extra
		# state.
		if absf(moved.x) > FACING_DEADZONE_PX:
			_sprite.flip_h = moved.x > 0.0
	else:
		_sprite.texture = _procedural_generator.generate_texture(species)
		# ProceduralDecomposerSprite's art canvas is authored at
		# ArtResolution.DETAIL_MULTIPLIER, the same oversample-then-scale-
		# down convention every other sprite generator in this codebase
		# follows (see art_resolution.md) -- this was the one generator
		# that never actually applied SPRITE_SCALE, so it rendered at its
		# raw art-canvas size instead of its intended tiny insect world
		# size (reported: "gigantic ant blobs"; direct precedent for the
		# same failure mode: ProceduralItemSprite's own doc comment
		# records a fallen cherry once being "as wide as the tile it lay
		# on" for the identical missing-scale reason).
		_sprite.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
		_sprite.flip_h = false


var _lod_clock := SimulationLodClock.new()

## Distance-based update rate (see SimulationLod) -- mirrors CreatureMarker/
## AmbientFlyerMarker's own _lod_step exactly. Without this, the SEEKING
## phase's _nearest_food group scan (see _step_seeking) ran completely
## unthrottled: every ant/bug in the loaded world re-scanned the whole
## Carcass/CarcassGuts groups every single frame, however far from the
## player it was and however long it had already been since anything nearby
## changed. Returns the time to advance by, or NEGATIVE when this frame
## should be skipped entirely.
##
## Negative rather than zero as the skip signal, because zero is a
## legitimate step -- see CreatureMarker._lod_step's own doc comment.
##
## The accumulated time is handed to the update when it does run, so a
## skipped frame is never LOST time -- a decomposer far from the player
## lives at exactly the same rate, it just does so in fewer, larger steps
## that nobody is close enough to see.
func _lod_step(delta: float) -> float:
	if not _lod_clock.tick(delta):
		return -1.0
	var player = _nearest_player_position()
	if player == null:
		return _lod_clock.take_full_rate_step()  # nobody to be far from: always full rate
	var step := _lod_clock.take_step(position.distance_to(player))
	# A distant creature skips its next frames anyway -- park it so those
	# frames cost it nothing at all (FPS regression round 11, see
	# SimulationScheduler). A no-op when no scheduler is current.
	if step >= 0.0:
		SimulationScheduler.park_if_far(self, _lod_clock)
	return step


## Applies the real effect `species_id` causes (see MushroomEffect.
## effect_kind_for) -- a no-op for a non-toxic species. Called from
## _step_feeding once a bite lands on a real toxic mushroom species.
func apply_mushroom_effect(species_id: String) -> void:
	var kind := MushroomEffect.effect_kind_for(species_id)
	if kind == "":
		return
	_mushroom_effect_species = species_id
	active_mushroom_debuffs = _debuff_stack.apply(
		active_mushroom_debuffs, kind, MushroomEffect.duration_for(species_id), MushroomEffect.MAX_STACKS
	)


## Advances every active mushroom debuff's remaining duration. Deliberately
## does NOT roll a death chance the way CreatureMarker._mushroom_effect_step
## does -- see MushroomEffect.is_lethal_capable's own doc comment: real
## insects are documented as considerably more amatoxin-tolerant than
## mammals (fungus gnat larvae famously develop IN death cap fruiting
## bodies), so a decomposer gets the real Weakened slowdown below but never
## risks dying from it.
func _mushroom_effect_step(delta: float) -> void:
	active_mushroom_debuffs = _debuff_stack.advance(active_mushroom_debuffs, delta)


## Applies this decomposer's own active mushroom effects to one step's
## worth of movement, `delta_vec` -- the actual position change
## _step_seeking/_step_approaching already computed. Disoriented (a real
## psychoactive species) wobbles the heading -- the report's own "how they
## walk" ask -- rather than touching AmbientFlyerMovement itself (a
## shared, carefully-tuned algorithm this file's own git history shows is
## fragile to exactly this kind of change). Weakened (Death Cap) applies a
## real, flat speed penalty, the identical mechanical shape
## CreatureMarker's own _advance uses.
func _mushroom_affected_delta(delta_vec: Vector2) -> Vector2:
	if _debuff_stack.stacks_of(active_mushroom_debuffs, MushroomEffect.DISORIENTED_ID) > 0:
		delta_vec = MushroomEffect.wobble_direction(
			delta_vec, MushroomEffect.wobble_radians_for(_mushroom_effect_species), wander_seed, _elapsed_time
		)
	if _debuff_stack.stacks_of(active_mushroom_debuffs, MushroomEffect.WEAKENED_ID) > 0:
		delta_vec *= MushroomEffect.weakened_speed_multiplier_for(_mushroom_effect_species)
	return delta_vec


## Real soil/air warmth at this decomposer's own position, the same signal
## CreatureMarker._process already reads for body-temperature regulation
## (see World.ambient_warmth) -- reused directly rather than a second,
## independent reading of the identical world. A decomposer with no
## `_world` set (most of this file's own tests, and every caller that
## predates this feature) reads full warmth and so keeps its ordinary
## undiminished speed, the same "no world means no chunk-specific data"
## convention _nearest_food's own leaf-litter branch already uses.
func _current_activity_multiplier() -> float:
	if _world == null or not _world.has_method("ambient_warmth"):
		return 1.0
	return activity_multiplier_for(_world.ambient_warmth(position))


## Cheap: the player group holds one node in solo play. Cached per frame by
## the caller rather than scanned per creature would be better still, but
## this is already off the hot path for everything nearby.
func _nearest_player_position():
	# Not in the tree (a marker built standalone in a test) means there is no
	# player to measure against, so it runs at full rate.
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
	# Decomposers far from the player advance in fewer, larger steps (see
	# SimulationLod) -- same time passes, fewer scans to pay for.
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	if _dying:
		_dying_elapsed += delta
		if _dying_elapsed >= SquashCrushEffect.LINGER_SECONDS:
			queue_free()
		return
	# Advanced by the same (possibly LOD-coalesced) delta everything else in
	# this function uses, so a decomposer far from the player keeps the same
	# wander-heading cadence relative to its OWN simulated time -- not real
	# wall-clock frames it may be skipping most of.
	_elapsed_time += delta
	# Real calorie burn (see docs/concept/metabolism.md): Kleiber's-law BMR
	# at this decomposer's OWN current mass, scaled by its real
	# CarrionForageBehavior phase.
	_ensure_metabolism().advance(delta, _current_metabolic_activity())
	_mushroom_satiation_remaining = maxf(0.0, _mushroom_satiation_remaining - delta)
	_mushroom_effect_step(delta)
	var position_before := position
	match _behavior.phase:
		CarrionForageBehavior.Phase.SEEKING:
			_step_seeking(delta)
		CarrionForageBehavior.Phase.APPROACHING:
			_step_approaching(delta)
		CarrionForageBehavior.Phase.FEEDING:
			_step_feeding(delta)
	_update_sprite(position - position_before)


## Bug report: "gigantic ant blobs... but they don't move". This used to only
## ever pull the decomposer BACK toward home once it had drifted past
## WANDER_RADIUS_PX -- nothing ever sent it wandering away from home in the
## first place, so an idle decomposer with nothing nearby to eat sat frozen
## on exactly one position forever. Real ambient wander now, via the same
## home-anchored AmbientFlyerMovement algorithm AmbientFlyerMarker already
## uses (see _movement's own doc comment).
func _step_seeking(delta: float) -> void:
	var position_before_wander := position
	var stepped := _movement.step_position(home, position, _elapsed_time, delta, wander_seed)
	# Toxic mushroom effects (see _mushroom_affected_delta's own doc
	# comment) wobble/slow the actual step, rather than touching
	# AmbientFlyerMovement itself. Cold soil (see _current_activity_
	# multiplier) scales the resulting distance the same post-hoc way,
	# for the identical "don't touch the shared movement algorithm"
	# reason.
	var wander_delta := _mushroom_affected_delta(stepped - position_before_wander)
	position = position_before_wander + wander_delta * _current_activity_multiplier()
	_behavior.advance(delta)  # no-op outside FEEDING, just ticks the rehunt clock
	if _behavior.can_commit():
		var found := _nearest_food()
		if found != null:
			_target = found
			# Relocates the wander anchor to wherever real food actually is,
			# exactly like AmbientFlyerMarker already does at every one of its
			# own commit sites (e.g. "if _worm_target.distance_to(home) >
			# _movement.radius: home = _worm_target"). Without this, a
			# decomposer that walks beyond its own tiny WANDER_RADIUS_PX to
			# reach a real target -- entirely possible, since SEARCH_RADIUS_PX
			# is more than double it -- returns to SEEKING still anchored on
			# the stale point it started from, and the home-anchored wander's
			# containment pull (see AmbientFlyerMovement.direction_at) drags
			# it straight back there before it can settle near wherever it
			# just ate. Reported live: "bugs run to a new leaf instantly then
			# walk back a bit then speed to the next leaf" -- the "walk back"
			# was this exact pull, and relocating home here is what lets a
			# decomposer keep wandering naturally around a real food patch
			# instead of yo-yoing to and from an arbitrary spawn point.
			if found.position.distance_to(home) > _movement.radius:
				home = found.position
			_behavior.begin_approach()


## Nearest (by EFFECTIVE, not raw, distance) live Carcass, CarcassGuts, or
## fallen fruit/nut within SEARCH_RADIUS_PX, or null. An ant/carrion bug is
## an opportunistic omnivore, not a carrion specialist (see
## docs/concept/carrion.md, AntColony's own already-real windfall foraging)
## -- a decomposer with no carrion around should still notice food lying at
## its feet rather than starve next to it.
##
## Carcass/CarcassGuts are checked indiscriminately -- a decomposer at a
## carcass doesn't care whether the offal is still attached or lying beside
## it. A carcass already carrying flies (see Carcass.fly_count) reads as
## closer than its real distance (CarrionForageBehavior.effective_distance)
## -- real scavengers cue off circling flies as a sign something worth
## investigating is there, so a fly-blown carcass can out-compete a nearer,
## fresh one, and can even be noticed a little past the ordinary search
## radius. CarcassGuts has no fly_count (disease.md/carrion.md both scope
## the fly loop to carcasses, not offal) and so is always scored at its real
## distance -- and so is fallen fruit, which has no fly-attraction mechanic
## of its own either.
##
## Fallen fruit/nuts are real DroppedItem ground items, scanned via
## DroppedItem.FORAGEABLE_GROUP_NAME rather than the shared, catch-all
## DroppedItem.GROUP_NAME (see that constant's own doc comment). Bug
## report: "game now has only 4-5 fps". GROUP_NAME is shared by every
## ground-pickable thing this game has -- LiftableStone and PickableSeed
## deliberately join it too, for the player's own pickup sweep, and stones
## in particular are extremely dense -- so scanning it globally, for every
## ant, on every SEEKING check, was a real O(decomposers x every dropped
## thing in the loaded world) cost, not just the earlier `.item_stack`
## crash on non-DroppedItem members (see git history: that crash was fixed
## first and measurably helped, but did not fully explain the reported
## collapse on its own -- this scan-scope fix is the rest of it).
## FORAGEABLE_GROUP_NAME is joined by a DroppedItem actually holding a
## TreeSpecies.IDS species at creation time (real fallen windfall, never a
## dropped tool, ore chunk, or the far larger set of stones lying around),
## and -- since this pass -- by MushroomMarker too (real fungivory, see
## docs/concept/soil_fauna.md's fungivory follow-up): a mushroom joined
## this exact group from the moment it was first built (see that class's
## own doc comment), but this loop's `not (node is DroppedItem)` guard
## silently excluded it again right afterward, so a decomposer could never
## actually reach one at all until this fix. Reported live: "when a bug
## takes a bite."
## Shared across every decomposer -- see this class doc comment history:
## round 4 (docs/concept/soil_fauna.md) found and fixed two "one marker
## scans the whole world instead of a scoped neighbourhood" bugs
## (AmbientFlyerMarker._scan_for_partners, EarthChunkManager.
## crush_ants_near) but missed this third instance of the identical
## shape: CarrionForageBehavior.can_commit() stays true on EVERY frame
## once past REHUNT_SECONDS, not just once, so _nearest_food's own
## Carcass/CarcassGuts/FORAGEABLE_GROUP_NAME group walk ran once PER
## DECOMPOSER PER FRAME for as long as it kept searching -- with live
## population in the hundreds (confirmed: 645-900 on the user's own
## real save), this reproduced the exact anti-pattern those two fixes
## had already closed elsewhere. Reported live, again: "still at 4-10
## fps" after both of those had already shipped.
##
## The underlying data ("where is food in the world right now") is
## identical for every decomposer, so there is no reason each of
## potentially hundreds of them independently re-fetches the SAME
## whole-world group lists every frame. Refreshed at most once per
## FOOD_GROUP_REFRESH_SECONDS of real (wall-clock, Time.get_ticks_msec)
## time -- deliberately NOT a per-instance throttle mirroring
## AmbientFlyerMarker.WORM_SNIFF_INTERVAL, which was considered and
## rejected: at the very low frame rates this was actually reported at,
## one single frame's own delta can already exceed a half-second
## interval, so a per-INSTANCE cooldown checked once per frame barely
## suppresses anything in exactly the condition that matters most.
## Sharing the fetch across every instance is what actually bounds the
## cost regardless of frame rate: one refresh serves every decomposer
## that asks during its window, however many (or however few) real
## frames that window happens to span.
##
## Deliberately NOT full per-chunk spatial bucketing either -- the shape
## round 4's own flyers_near/leaf_litter_near/trees_near all use: those
## all reuse an EXISTING per-chunk registry EarthChunkManager already
## maintained for spawn/despawn tracking. Carcass/CarcassGuts/
## DroppedItem(fruit)/MushroomMarker have no such registry to reuse --
## they spawn from five separate, scattered call sites (creature death,
## player drops, world events, the mushroom renderer's own per-chunk
## spawn) with no existing per-chunk bucket, so building one from
## scratch here would be a materially larger, riskier change than this
## fix. Named explicitly as the smaller-scoped fix, not silently passed
## off as the full round-4-style treatment -- a real follow-up, not
## invented here.
const FOOD_GROUP_REFRESH_SECONDS := 0.5
static var _food_group_refresh_at_msec: int = -1000000
static var _cached_carcasses: Array = []
static var _cached_carcass_guts: Array = []
static var _cached_forageables: Array = []


## Refetches the three shared group lists from `tree` if the cache has
## gone stale. `now_msec` is INJECTED (not read directly via Time.get_
## ticks_msec here) so this stays testable with a fake clock and a
## counting tree double, the same call-observing idiom round 4's own
## tests already use. `tree` is duck-typed (only needs get_nodes_in_
## group), matching every other 'world' port in this codebase.
static func _refresh_food_groups_if_stale(tree, now_msec: int) -> void:
	if now_msec - _food_group_refresh_at_msec < int(FOOD_GROUP_REFRESH_SECONDS * 1000.0):
		return
	_food_group_refresh_at_msec = now_msec
	_cached_carcasses = tree.get_nodes_in_group(Carcass.GROUP_NAME)
	_cached_carcass_guts = tree.get_nodes_in_group(CarcassGuts.GROUP_NAME)
	_cached_forageables = tree.get_nodes_in_group(DroppedItem.FORAGEABLE_GROUP_NAME)


func _nearest_food() -> Node2D:
	if is_inside_tree():
		_refresh_food_groups_if_stale(get_tree(), Time.get_ticks_msec())
	var best: Node2D = null
	var best_effective_distance := SEARCH_RADIUS_PX
	for group in [_cached_carcasses, _cached_carcass_guts]:
		for node in group:
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			var distance: float = position.distance_to(node.position)
			var fly_count: int = node.fly_count() if node.has_method("fly_count") else 0
			var effective := CarrionForageBehavior.effective_distance(distance, fly_count)
			if effective <= best_effective_distance:
				best = node
				best_effective_distance = effective
	for node in _cached_forageables:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		# FORAGEABLE_GROUP_NAME is joined by a real DroppedItem holding a
		# real fruit/nut (see DroppedItem._ready()) OR a MushroomMarker with
		# something left to bite (see MushroomMarker._ready(), take_
		# mushroom_bite -- real fungivory, docs/concept/mushrooms.md). The
		# `is DroppedItem`/`item_stack` half is defensive, not load-bearing
		# for correctness -- kept so a future bug in that join can never
		# reintroduce the exact "invalid access to item_stack" crash this
		# whole investigation started from. A FULLY eaten mushroom (see
		# MushroomMarker.can_be_bitten, docs/concept/soil_fauna.md's
		# "Progressive, mass-scaled bites") has nothing left to offer, so
		# it is excluded here rather than costing a decomposer a wasted
		# trip only to find take_mushroom_bite() a no-op on arrival -- a
		# PARTIALLY bitten one (some real capacity still left) stays a
		# real target, so a second bug can take a second bite.
		var is_real_fruit: bool = node is DroppedItem and node.item_stack != null
		# Satiated (see _mushroom_satiation_remaining's own doc comment):
		# recently ate a mushroom, not hungry enough to seek another one
		# yet -- the report's own "is satisfied for a few hours". Gates
		# ONLY this branch, not fruit/carrion above.
		var is_biteable_mushroom: bool = (
			_mushroom_satiation_remaining <= 0.0
			and node.has_method("take_mushroom_bite")
			and node.can_be_bitten()
		)
		if not is_real_fruit and not is_biteable_mushroom:
			continue
		var distance: float = position.distance_to(node.position)
		if distance <= best_effective_distance:
			best = node
			best_effective_distance = distance

	# Fallen-leaf litter (see docs/concept/leaf_litter.md) -- the one
	# chunk-specific case this marker needs an injected _world for at all
	# (see that field's own doc comment). Scored at its real distance, the
	# same as fallen fruit/nuts just above: a leaf has no fly-attraction
	# mechanic of its own either.
	if _world != null and _world.has_method("nearest_leaf_litter_near"):
		var leaf_found: Dictionary = _world.nearest_leaf_litter_near(position, best_effective_distance)
		if not leaf_found.is_empty():
			var leaf_distance: float = position.distance_to(leaf_found.position)
			if leaf_distance <= best_effective_distance:
				var handle := LeafForageHandle.new()
				handle.position = leaf_found.position
				handle._world = _world
				best = handle
				best_effective_distance = leaf_distance
	return best


func _step_approaching(delta: float) -> void:
	if not _target_still_here():
		_target = null
		_behavior.abort()
		return
	var to_target: Vector2 = _target.position - position
	if to_target.length() <= ARRIVE_DISTANCE_PX:
		_behavior.arrive()
		return
	# move_toward, not += direction * speed * delta: a target committed to
	# WHILE ambient wander is active (see _step_seeking) can already be
	# closer than one whole step (WALK_SPEED * delta) once approach begins,
	# and unclamped movement overshoots straight past it -- then overshoots
	# back on the next step, forever, an orbiting decomposer that commits to
	# a real target and then never actually arrives. Latent since this
	# marker was first built (a frozen, never-wandering SEEKING phase always
	# started APPROACHING already within ARRIVE_DISTANCE_PX of a target
	# right beside home, so the overshoot case could never trigger); exposed
	# by giving SEEKING a real wander distance to close. Same clamped-arrival
	# shape NpcMarker._process already uses to walk toward its own target.
	# Toxic mushroom effects (see _mushroom_affected_delta's own doc
	# comment) wobble/slow this step too -- a disoriented decomposer
	# stumbles toward its target rather than beelining for it, re-aiming
	# fresh from wherever it actually ends up each frame (move_toward
	# recomputes to_target live), so it still eventually arrives. Cold
	# soil (see _current_activity_multiplier) slows the approach the same
	# way it slows ambient wander -- a real committed trip still takes
	# longer in winter, not just the undirected searching.
	var approach_step := (
		position.move_toward(_target.position, WALK_SPEED * delta * _current_activity_multiplier())
		- position
	)
	position += _mushroom_affected_delta(approach_step)


func _step_feeding(delta: float) -> void:
	if not _target_still_here():
		_target = null
		_behavior.abort()
		return
	if _behavior.advance(delta):
		if _target.has_method("take_bite"):
			# Carcass/CarcassGuts: a real health pool whittled down over
			# several visits, same as always.
			_target.take_bite(BITE_AMOUNT)
			_step_disease_carry()
			# A real intake event for this decomposer's own unified mass
			# (docs/concept/metabolism.md) -- no composition data exists
			# for carrion (see NutrientRelease's own doc comment), so this
			# treats one landed bite as one whole meal's worth, the same
			# fallback granularity CreatureMarker's own uncomposed forage
			# kinds already use.
			_ensure_metabolism().feed_hunger_relief(1.0)
		elif _target.has_method("take_mushroom_bite"):
			# A mushroom (see MushroomMarker.take_mushroom_bite): unlike a
			# carcass's whittled-down health pool or a fallen fruit eaten
			# whole in one visit, a bite advances a real per-mushroom stage
			# count and stays present, in the world and later in an
			# inventory, just diminished (see MushroomBiting.gd), rather
			# than removed outright. How many stages -- and how long this
			# decomposer stays satisfied afterward -- both scale with its
			# own real mass (docs/concept/soil_fauna.md's "Progressive,
			# mass-scaled bites, and real toxic effects"): a bug/ant-scale
			# decomposer takes exactly one small nibble and won't seek
			# another mushroom for a real while (see
			# _mushroom_satiation_remaining). This decomposer is done here
			# regardless of what take_mushroom_bite() itself returns --
			# even a refused bite (already fully eaten by the time it
			# arrived) means there is nothing left to gain from trying
			# again immediately (see WildMushroomPatch.bite).
			var mass_kg := current_mass_kg()
			var species_id: String = _target.species_id
			if _target.take_mushroom_bite(MushroomBiting.bites_per_visit_for(mass_kg)):
				_mushroom_satiation_remaining = MushroomBiting.satiation_seconds_for(mass_kg)
				# Corrected 2026-09-07 -- the exact reported case: "i just
				# saw a bug eat a psylo and it didn't do anything to it"
				# (see docs/concept/mushrooms.md's "Toxic effects:
				# disorientation and illness"). A no-op for a non-toxic
				# species (see MushroomEffect.effect_kind_for).
				apply_mushroom_effect(species_id)
				# A real intake event for this decomposer's own unified
				# mass (docs/concept/metabolism.md) -- only on an actually
				# landed bite (take_mushroom_bite can refuse near the real
				# per-mushroom cap).
				_ensure_metabolism().feed_hunger_relief(1.0)
			_target = null
			_behavior.abort()
			return
		elif _target.has_method("consume_leaf_litter"):
			# Fallen-leaf litter (see _nearest_food's own leaf-litter
			# branch): the handle itself has no health pool either -- one
			# visit removes the real record from its LeafLitterField (see
			# LeafForageHandle.consume_leaf_litter). free(), not queue_free():
			# this handle was never added to the tree in the first place, so
			# there is no same-frame-iteration hazard to defer around.
			_target.consume_leaf_litter()
			_target.free()
			_ensure_metabolism().feed_hunger_relief(1.0)
		else:
			# Fallen fruit/nut (see _nearest_food): a dropped cherry is not a
			# boar carcass -- there is no health pool to whittle down, a
			# decomposer finishing one just eats the whole thing in this one
			# visit.
			_target.queue_free()
			_ensure_metabolism().feed_hunger_relief(1.0)
		if not _target_still_here():
			_target = null
			_behavior.abort()


## One bite's worth of anthrax-like carry (see carrying_disease's own doc
## comment): a not-yet-carrying decomposer biting a contaminated Carcass may
## pick it up; an already-carrying decomposer biting a CLEAN Carcass may
## contaminate it in turn. Region pressure reads the CARCASS's own
## region_tier (see Carcass.region_tier) rather than adding a second copy of
## that field onto every decomposer -- the carcass being fed on is already
## the one real source of truth for "how dangerous is this spot".
func _step_disease_carry() -> void:
	if not (_target is Carcass):
		return
	var target_carcass: Carcass = _target
	_disease_roll_count += 1
	var seed_value := hash("%d_%d_decomposer_carry" % [wander_seed, _disease_roll_count])
	if target_carcass.contaminated and not carrying_disease:
		var chance := _disease_model.decomposer_carry_chance(target_carcass.region_tier)
		carrying_disease = _disease_model.attempt_transmit(chance, seed_value)
	elif carrying_disease and not target_carcass.contaminated:
		target_carcass.contaminated = true


## Whether _target is a real, not-yet-consumed thing still worth working --
## queue_free()'d nodes stay "valid" until the next frame boundary, so
## is_queued_for_deletion() is checked directly rather than relying on
## is_instance_valid() alone to catch a target consumed this same tick.
func _target_still_here() -> bool:
	return (
		_target != null
		and is_instance_valid(_target)
		and not _target.is_queued_for_deletion()
	)
