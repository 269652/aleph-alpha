extends Sprite2D

## A single creature: senses its surroundings each frame and acts on them via
## the pure decision modules (CreatureNeeds/CreaturePerception/CreatureBehavior),
## and is damageable. Draws a tiny always-on health sliver above its sprite
## (see _health_bar_*); its name/level/full HP readout lives in a HUD panel
## instead (see CreaturePanel/World._update_creature_panels), not floating
## text attached to the creature in world-space.
##
## Behavior summary: herbivores (calm) graze food terrain, drink at water, and
## flee predators and the player; predators (aggressive) hunt and eat
## herbivores when hungry, attack the player when strong, and flee it when
## weakened. Until setup() is called with a world, a marker just idle-wanders
## (harmless fallback used by tests/tools that don't need full AI).
##
## Known simplifications (see docs/progress.md): sensing is O(nearby creatures)
## per frame with no spatial index; killing prey/being killed doesn't decrement
## the region's aggregate EcosystemSimulation population (it reseeds on the
## next chunk reload); creatures aren't replicated to multiplayer clients.

const CreatureWander = preload("res://src/rendering/creature_wander.gd")
const ThreatAvoidantWander = preload("res://src/gameplay/threat_avoidant_wander.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const CreatureNeeds = preload("res://src/gameplay/creature_needs.gd")
const GrazerForaging = preload("res://src/gameplay/grazer_foraging.gd")
const ScentForaging = preload("res://src/gameplay/scent_foraging.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const RopeTether = preload("res://src/gameplay/rope_tether.gd")
const CreaturePerception = preload("res://src/gameplay/creature_perception.gd")
const CreatureBehavior = preload("res://src/gameplay/creature_behavior.gd")
const Health = preload("res://src/gameplay/health.gd")
const BossAggro = preload("res://src/gameplay/boss_aggro.gd")
const LootTable = preload("res://src/gameplay/loot_table.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const Knockback = preload("res://src/gameplay/knockback.gd")
const HealthBar = preload("res://src/gameplay/health_bar.gd")
const AnimalReproduction = preload("res://src/gameplay/animal_reproduction.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const SubmersionShader = preload("res://src/rendering/submersion_shader.gd")
const CreatureMovementGate = preload("res://src/gameplay/creature_movement_gate.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

## Sun elevation in degrees, shared by every creature's shadow -- set once
## per frame by World from its real sun-position calculation (see
## SolarPosition) rather than threaded individually through every marker.
## Static because it's one world-wide value, not per-creature state.
const DEFAULT_SUN_ELEVATION_DEG := 45.0
static var sun_elevation_deg := DEFAULT_SUN_ELEVATION_DEG

## Small always-visible health bar above the sprite.
const HEALTH_BAR_WIDTH := 14.0
## Taming readouts sit just above the health bar. The trust bar is the same
## width so the two read as one stack rather than two unrelated widgets, and
## the hunger pip is a small mark beside it rather than a third bar -- hunger
## is a yes/no cue ("feed me now"), not a quantity the player acts on.
const TRUST_BAR_COLOR := Color(0.45, 0.75, 0.95)
const TRUST_BAR_OFFSET_Y := -16.0
const HUNGER_PIP_COLOR := Color(0.95, 0.72, 0.2)
const HUNGER_PIP_SIZE := 3.0
## A third pip beside hunger, shown only on a tamed/kept animal (see
## docs/concept/taming.md's own hunger/trust readouts and disease.md's
## "third pip added the same way") -- a sickly yellow-green distinct from
## both the blue trust bar and the amber hunger pip.
const SICK_PIP_COLOR := Color(0.55, 0.75, 0.25)
const SICK_PIP_SIZE := 3.0
## Visible symptom for EVERY infected creature, tamed or wild (docs/concept/
## disease.md "What you see is what's real" -- a sick animal visibly reads
## as sick without a new animation system): reuses Sprite2D's own built-in
## `modulate`, a duller, sicklier cast of the sprite's normal color.
const SICK_MODULATE_COLOR := Color(0.72, 0.8, 0.55)
const HEALTHY_MODULATE_COLOR := Color.WHITE
const HEALTH_BAR_HEIGHT := 2.0
const HEALTH_BAR_OFFSET_Y := -12.0
const HEALTH_BAR_BG_COLOR := Color(0.1, 0.1, 0.1, 0.85)
const HEALTH_BAR_FILL_COLOR := Color(0.8, 0.15, 0.15)

## Godot group names for spatial queries.
const GROUP_NAME := "creature"
const PLAYER_GROUP := "player"

## Solid world props a creature must walk around rather than through (see
## ChoppableTree/SmashableStone/MinableOre, which join these). Only the
## TRUNK of a tree is solid, not its canopy -- see TreeRenderer.
const TREE_GROUP := "tree"
const STONE_GROUP := "stone"

## How far out obstacles are gathered, in pixels. Only needs to comfortably
## exceed the movement lookahead below, since anything further away cannot
## block this step; kept small because this scan runs on the throttled
## sensing tick over two whole node groups.
const BLOCKER_SCAN_RADIUS := 64.0

## How far ahead a creature checks for obstacles before committing to a
## step. A single frame's travel (well under a pixel) is far too short to
## anticipate anything, so the check looks a fixed distance ahead instead --
## roughly a tile, so a creature starts going around a trunk before it is
## standing on it.
const MOVEMENT_LOOKAHEAD := 14.0

## Fallback half-extent for an obstacle with no CollisionShape2D of its own
## to measure (test doubles, or any prop that carries no shape) -- see
## _blocker_radius.
const DEFAULT_BLOCKER_RADIUS := 8.0

## Every hoverable entity -- this marker plus FishMarker/AmbientFlyerMarker/
## PiscivoreBirdMarker/DroppedItem/LiftableStone/SmashableStone/MinableOre/
## ChoppableTree -- joins HoverTargetFinder.GROUP_NAME, so World's hover
## tooltip can scan one group regardless of entity type.

## How far (pixels) a creature can sense other creatures/players, and how far
## (tiles) it scans terrain for food/water.
const SENSE_RADIUS := 80.0

## Wider than SENSE_RADIUS on purpose, and checked SEPARATELY from it (see
## _cached_caution_threats). SENSE_RADIUS gates when a creature actively
## flees; using that same boundary for "should I even consider walking
## toward the player" left no buffer zone -- the instant the player stepped
## outside 80px, the avoidance bias in _wander_step had nothing to avoid and
## wandered straight back toward them, re-entering flee range and fleeing
## again, forever. Reported as "moving back and forth ... just outside the
## flee radius". This radius is checked directly before a wander step is
## taken, not after, so the animal never even considers a direction that
## approaches the player while inside it.
const CAUTION_RADIUS := 160.0
const SENSE_RADIUS_TILES := 6

## How far a threat must get before an ALREADY-FLEEING creature stops
## sensing it. Fleeing is entered at SENSE_RADIUS but only released out
## here -- a Schmitt trigger, not one shared threshold. With a single
## threshold, a player parked right at SENSE_RADIUS made the creature dither
## in and out of fleeing every couple of seconds: cross the line, flee
## outward, drop straight back to wander, drift back in, flee again
## (measured 16-23 facing flips per 30 simulated seconds at 60-90px, versus
## 2 when well clear). Sits comfortably inside CAUTION_RADIUS so a creature
## that has just stopped fleeing is still avoiding, not obliviously
## wandering back in (see _caution_biased_step).
const FLEE_RELEASE_RADIUS := 120.0

## Movement speeds (px/s) for each intent -- fleeing/hunting are urgent and
## faster than a leisurely graze or idle wander (see CreatureWander).
const FLEE_SPEED := 40.0
const HUNT_SPEED := 36.0
const SEEK_SPEED := 28.0

## The expensive part of the AI -- scanning nearby nodes and terrain tiles --
## runs at most this often (seconds), cached in between, rather than every
## frame. Movement is still applied every frame off the cached senses, so it
## stays smooth while keeping per-frame cost low with many creatures loaded.
const SENSE_INTERVAL := 0.25

## Predator melee against the player: reach, damage, and cooldown between hits.
const ATTACK_RANGE := 16.0
const ATTACK_DAMAGE := 6.0
const ATTACK_COOLDOWN := 0.8

## How close a predator must get to a herbivore to catch and eat it, and the
## (one-shot-lethal) damage it deals on catching.
const PREDATION_RANGE := 12.0
const PREDATION_DAMAGE := 1000.0

## How long a knockback shove plays out over, in seconds (Hammerwatch-style
## slide, not an instant teleport -- see Knockback.step).
const KNOCKBACK_DURATION := 0.15

## Bioenergetic condition gained per feeding event (see AnimalReproduction).
## Two-to-three good meals lift a creature over the reproduction threshold.
const FEED_ENERGY := 0.25

## Seconds per animation frame (all actions have 2 frames, see
## ProceduralAnimalAnimation.FRAME_COUNTS).
const ANIMATION_FRAME_DURATION := 0.3

## How much GROUND a creature covers per gait frame -- the walk/swim cycles
## are paced by distance actually travelled, not wall-clock time, so stride
## frequency scales with speed the way a real gait does (reported: "adapt
## the horse animation to be faster when it moves faster"). Derived, not
## eyeballed: at CreatureWander.WANDER_SPEED this works out to exactly
## ANIMATION_FRAME_DURATION per frame, so an ambling creature's cadence is
## unchanged from the old time-based cycle and everything faster speeds up
## proportionally (pinned by
## test_gait_stride_per_frame_matches_the_old_cadence_at_wander_speed).
const GAIT_STRIDE_PER_FRAME := CreatureWander.WANDER_SPEED * ANIMATION_FRAME_DURATION

var home := Vector2.ZERO
var wander_seed := 0
var info: CreatureInfo

## Per-action generated frame textures, filled lazily on first use of each
## action (see _animation_step) -- a marker typically only ever plays 2-3 of
## the 5 actions, so generating all upfront would be wasted work.
var _animation_frames: Dictionary = {}  # action String -> Array[ImageTexture]
var _animation := preload("res://src/rendering/procedural_animal_animation.gd").new()
## Real hand/AI-illustrated art for species that have it (horse/deer/boar --
## see IllustratedAnimalSprite) instead of ProceduralAnimalSprite's
## primitive-shape generation. Checked first in _animation_step; every
## species/action it doesn't cover falls back to _animation as before.
var _illustrated := preload("res://src/rendering/illustrated_animal_sprite.gd").new()
var _current_action := "walk"

var _wander := CreatureWander.new()
## Seeded from wander_seed in _ready so a herd doesn't cross into hunger in
## lockstep -- see CreatureNeeds.START_STAGGER.
var _needs := CreatureNeeds.new()

## Disease (see docs/concept/disease.md / DiseaseModel): which of the three
## real archetypes (if any) this individual carries, and where it is in the
## SIRS cycle. "" disease_id / State.SUSCEPTIBLE means healthy. region_tier
## is set once at spawn (see CreatureRenderer.spawn_creatures) from the SAME
## RegionDifficulty tier that already gates this individual's species pool,
## so disease pressure scales with the one distance-from-spawn signal this
## project already computes rather than a second one.
var disease_state: int = DiseaseModel.State.SUSCEPTIBLE
var disease_id := ""
var disease_severity := 0.0
var _disease_state_seconds := 0.0
var region_tier: int = RegionDifficulty.Tier.EASY
var _disease_model := DiseaseModel.new()
## Counts this individual's disease rolls, so each one draws a different,
## still-deterministic seed from wander_seed -- the same salted-hash pattern
## _struggle_count already uses for _step_restraint's own rolls.
var _disease_roll_count := 0

## Taming (see docs/concept/taming.md). `_rope_anchor` is whatever holds the
## other end of the lasso -- the player leading it, or the point it is tied to
## -- and is pushed in each frame by the holder rather than stored as a node
## reference, so a marker never outlives a dangling holder.
var trust := 0.0
## What a tamed animal has been told to do, and where the thing it is
## following currently is. `follow_target` is pushed in by the owner each
## frame rather than held as a node reference, the same way the rope anchor
## is, so a marker never outlives a dangling owner.
var order := Taming.ORDER_FOLLOW
var follow_target := Vector2.ZERO
var _stay_anchor := Vector2.ZERO
var _restrained := false
var _rope_anchor := Vector2.ZERO
## True when the rope's loose end is tied to a fixed point rather than held by
## the player -- the difference between "being led" and "left here".
var _tied := false
var _struggle_elapsed := 0.0
## How winded this animal is from fighting the rope. Recovers when it is not
## struggling, so an animal that got away is not permanently broken.
var _struggle_fatigue := 0.0
## Counts this individual's struggles, so each roll is a different draw
## without holding an RNG on every creature in the world.
var _struggle_count := 0


## Active foraging (see GrazerForaging): the phase machine, the bite this
## animal has committed to walking to, and what kind of food that bite is.
var _forage := GrazerForaging.new()
var _forage_target := Vector2.ZERO
var _forage_kind := ""
var _has_forage_target := false
## Bioenergetic condition (see AnimalReproduction / ecosystem_dynamics.md):
## rises when the creature eats, decays over time, and gates reproduction
## together with health and a birth cooldown. Starts moderate so a fresh herd
## doesn't instantly breed.
var energy := 0.5
var _seconds_since_birth := 0.0
var _perception := CreaturePerception.new()
var _behavior := CreatureBehavior.new()
var _health := Health.new()
var _boss_aggro := BossAggro.new()
var _loot_table := LootTable.new()
var _knockback := Knockback.new()
var _health_bar := HealthBar.new()
var _health_bar_bg: ColorRect
var _health_bar_fill: ColorRect
## Taming readouts (see docs/concept/taming.md): how far along winning this
## animal over is, and whether it wants feeding right now.
var _trust_bar: ColorRect
var _hunger_pip: ColorRect
## Third readout beside hunger, tamed/kept animals only -- see disease.md.
var _sick_pip: ColorRect
## The ground-contact shadow CreatureRenderer adds as a child (see
## set_shadow) -- null until it does, since bare test markers never get one.
var _shadow: Node2D = null
var _shadow_offset := Vector2.ZERO
## The shadow's own resting scale before the sun-elevation stretch is
## multiplied into its Y (see set_shadow) -- a silhouette shadow is drawn
## top_level, so it doesn't inherit the marker's own scale (species size,
## art-resolution downscale) the way a plain child would, and needs it
## re-applied explicitly.
var _shadow_base_scale := Vector2.ONE
var _elapsed_time := 0.0
var _attack_cooldown_remaining := 0.0

## How often an actively-swimming creature spawns a water-ripple disturbance
## (see EarthChunkManager.record_water_disturbance) -- mirrors
## player.gd's WATER_RIPPLE_INTERVAL.
const WATER_RIPPLE_INTERVAL := 0.4
var _water_ripple_accumulator := 0.0

## Flower seed this animal is currently carrying, and where it picked it up
## (see EarthChunkManager._step_seed_dispersal / SeedDispersal). Empty string
## means empty-handed. State lives on the marker rather than in the chunk
## manager so it travels with the animal across chunk boundaries.
var carried_seed_species := ""
var carried_seed_origin := Vector2.ZERO

## Grass seed a MOUSE is currently caching, and where it picked it up (see
## EarthChunkManager._step_grass_seed_caching / SeedCaching). Separate from
## carried_seed_species/_origin above rather than reusing them: those track a
## FLOWER seed riding on ANY non-predator creature's coat, and a mouse can in
## principle be doing both at once (brushing a bloom while also caching a
## grass seed it actively picked up), so the two carriers need independent
## state. No species field -- a chunk grows only one kind of grass.
var carried_grass_seed := false
var carried_grass_seed_origin := Vector2.ZERO
var _world = null
var _tile_size := 16

var _knockback_remaining := Vector2.ZERO
var _knockback_time_remaining := 0.0

## Throttled-sensing cache (see SENSE_INTERVAL). Starts "due" so the very first
## _process senses immediately rather than idling for a quarter second.
var _sense_accumulator := SENSE_INTERVAL
var _cached_threats: Array = []
## Nearby solid props to walk around, refreshed with the rest of the
## throttled sensing (see _blockers_near). Array of {position, radius}.
var _cached_blockers: Array = []

## The heading this creature last actually advanced along, fed back into
## CreatureMovementGate as its sticky detour (see clear_direction's
## previous_heading doc comment). ZERO whenever it last stood still.
var _last_gated_heading := Vector2.ZERO

## Total ground this creature has actually covered -- the walk/swim gait
## phase (see GAIT_STRIDE_PER_FRAME). Accumulated in _advance from the REAL
## position delta, so a blocked creature's legs freeze automatically and a
## fast one's cycle speeds up in proportion.
var _gait_distance := 0.0

## Wider-radius awareness for wander avoidance ONLY -- see CAUTION_RADIUS.
## Kept separate from _cached_threats (which drives actual fleeing) so the
## two radii can never collapse back into the same boundary.
var _cached_caution_threats: Array = []
var _cached_prey: Array = []
## Nearby herbivore-role creatures, for herd (foot-and-mouth-like) disease
## transmission (see _herd_disease_step) -- separate from _cached_prey,
## which only ever populates for a predator (see _nearby_prey_creatures).
var _cached_nearby_herbivores: Array = []

## Consolidated per-tick classification of the "creature" group (see
## _scan_nearby_creatures): every other creature within the tick's threat
## radius that is a predator, and every other creature within SENSE_RADIUS
## that is not. _nearby_threat_creatures/_nearby_prey_creatures/
## _nearby_herbivore_creatures all read these instead of independently
## rescanning get_tree().get_nodes_in_group(GROUP_NAME).
var _scan_threat_candidates: Array = []
var _scan_nonpredator_candidates: Array = []
## Increments once per real get_tree().get_nodes_in_group(GROUP_NAME) scan
## (see _scan_nearby_creatures) -- exists so a test can prove a whole
## sensing tick performs exactly one such scan, not one per bucket accessor.
var _creature_scan_count := 0
var _cached_food_direction := Vector2.ZERO
var _cached_water_direction := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)
	# By now CreatureRenderer has assigned this individual's wander_seed, so
	# its needs can start somewhere of its own in the cycle rather than at
	# exactly empty like every other animal in the herd.
	_needs = CreatureNeeds.new(wander_seed)

	_health_bar_bg = ColorRect.new()
	_health_bar_bg.color = HEALTH_BAR_BG_COLOR
	_health_bar_bg.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	# `top_level`: a plain child inherits the marker's own rotation, which
	# would tilt the health bar right along with a turning serpent's body
	# (reported: "the health bar and shadow of creatures should NOT rotate
	# together with the animal"). top_level ignores the parent's transform
	# entirely, so its position is re-synced manually every frame instead
	# (see _sync_grounded_children) -- translation only, never rotation.
	_health_bar_bg.top_level = true
	add_child(_health_bar_bg)

	# Taming state, drawn above the health bar (see docs/concept/taming.md).
	# Both are top_level for the same reason the health bar is: they must not
	# tilt with a turning body, so their positions are re-synced each frame.
	_trust_bar = ColorRect.new()
	_trust_bar.color = TRUST_BAR_COLOR
	_trust_bar.size = Vector2(0.0, HEALTH_BAR_HEIGHT)
	_trust_bar.top_level = true
	_trust_bar.visible = false
	add_child(_trust_bar)

	_hunger_pip = ColorRect.new()
	_hunger_pip.color = HUNGER_PIP_COLOR
	_hunger_pip.size = Vector2(HUNGER_PIP_SIZE, HUNGER_PIP_SIZE)
	_hunger_pip.top_level = true
	_hunger_pip.visible = false
	add_child(_hunger_pip)

	_sick_pip = ColorRect.new()
	_sick_pip.color = SICK_PIP_COLOR
	_sick_pip.size = Vector2(SICK_PIP_SIZE, SICK_PIP_SIZE)
	_sick_pip.top_level = true
	_sick_pip.visible = false
	add_child(_sick_pip)

	_health_bar_fill = ColorRect.new()
	_health_bar_fill.color = HEALTH_BAR_FILL_COLOR
	_health_bar_fill.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_fill.top_level = true
	add_child(_health_bar_fill)

	_sync_grounded_children()
	_update_health_bar()


## Gives the creature the world it senses (duck-typed biome_at_global) and the
## tile size, enabling full AI. Without it, _process falls back to wander.
func setup(world, tile_size: int) -> void:
	_world = world
	_tile_size = tile_size


## Registers this marker's ground-contact shadow (a plain Sprite2D child
## added by CreatureRenderer -- see DropShadow.make_silhouette_shadow). Made
## `top_level` for the same reason the health bar is: a plain child's
## POSITION would be relative to the marker's own transform, which breaks
## once the marker itself starts moving via non-translation paths (knockback,
## etc.) -- position is instead re-synced manually every frame (see
## _sync_grounded_children). Rotation is handled differently per shadow kind:
## the health bar always stays upright regardless of a turning serpent's
## body, but a Sprite2D silhouette shadow DOES now track the marker's
## rotation there, since it has to actually match the rotated body casting it
## to look physically accurate (see _sync_grounded_children). Its foot offset
## is captured once here (before top_level changes what `position` means);
## actually syncing its global position happens later, in _process/_ready's
## own _sync_grounded_children calls -- CreatureRenderer calls this BEFORE
## adding the marker to the scene tree, so `global_position` isn't meaningful
## yet and the health bar nodes _sync_grounded_children also touches don't
## exist until _ready runs.
func set_shadow(shadow: Node2D, base_scale: Vector2 = Vector2.ONE) -> void:
	_shadow = shadow
	_shadow_offset = shadow.position
	_shadow_base_scale = base_scale
	shadow.top_level = true


## Keeps the health bar and shadow (both `top_level`, so they no longer
## inherit ANY of the marker's transform) tracking this marker's POSITION
## only -- called every frame regardless of which _process path ran, so they
## never lag or freeze mid-knockback.
func _sync_grounded_children() -> void:
	var health_bar_offset := Vector2(-HEALTH_BAR_WIDTH / 2.0, HEALTH_BAR_OFFSET_Y)
	_health_bar_bg.global_position = global_position + health_bar_offset
	_health_bar_fill.global_position = global_position + health_bar_offset
	if _trust_bar != null:
		var trust_offset := Vector2(-HEALTH_BAR_WIDTH / 2.0, TRUST_BAR_OFFSET_Y)
		_trust_bar.global_position = global_position + trust_offset
		_hunger_pip.global_position = (
			global_position + trust_offset + Vector2(HEALTH_BAR_WIDTH + 2.0, 0.0)
		)
		# Sick pip sits on the OTHER side of the trust bar from hunger, so a
		# tamed animal that is both hungry AND sick shows both cues at once
		# instead of one overwriting the other's spot.
		_sick_pip.global_position = (
			global_position + trust_offset + Vector2(-SICK_PIP_SIZE - 2.0, 0.0)
		)
		_update_taming_readouts()
	if _shadow != null:
		# _shadow_offset was captured in the marker's own UNSCALED texture
		# pixel space, but the marker itself is drawn at `scale` (species
		# size x the shared art-resolution downscale -- see
		# art_resolution.md), so its feet appear on screen at
		# _shadow_offset * scale, not the raw pixel count. Reported directly:
		# "the shadow is a few pixel below sprite so it looks like it's
		# floating" -- for any species whose scale isn't exactly 1.0, the
		# unscaled offset overshot past the creature's actual feet.
		# The anchor offset itself deliberately does NOT rotate with the
		# body -- a rotating/flipping serpent still needs its shadow to stay
		# on the GROUND below it, not swing out to the side or, worse, up
		# above it past 90 degrees (see the sprite's own flip_v line in
		# _advance). Two earlier attempts at rotating this offset to "match
		# the body" both put the shadow in the wrong place at some rotation
		# (reported, repeatedly: "the snake is the axis .. it should render
		# below the snake not above ... the shadow should always render on
		# the bottom of a creature regardless if it's rotated by 180deg") --
		# straight down, always, is simply correct, the same as every other
		# creature's shadow. _shadow_offset was captured in the marker's own
		# UNSCALED texture pixel space, but the marker itself is drawn at
		# `scale` (species size x the shared art-resolution downscale -- see
		# art_resolution.md), so its feet appear on screen at
		# _shadow_offset * scale, not the raw pixel count (reported
		# separately: "the shadow is a few pixel below sprite so it looks
		# like it's floating" -- for any species whose scale isn't exactly
		# 1.0, the unscaled offset overshot past the creature's actual feet).
		var offset := _shadow_offset * scale
		_shadow.global_position = global_position + offset
		# The SPRITE's rotation still matches the body, though -- a real
		# silhouette shadow (see DropShadow.make_silhouette_shadow) is a
		# live copy of whatever the marker itself currently looks like, and
		# a serpent's own sprite DOES rotate to face its heading (_advance),
		# so its flattened SHAPE has to rotate to match or it reads as a
		# blob that stopped turning with the body (reported: "The shadow for
		# snakes is not rotating properly. Its shadow should render
		# physically accurate when the snake is rotated"). Bare Node2D
		# shadows (fallback/test doubles) and the health bar are left alone.
		# A no-op for legged animals, whose own sprite rotation is always 0.
		if _shadow is Sprite2D:
			var sprite := _shadow as Sprite2D
			sprite.texture = texture
			sprite.flip_h = flip_h
			# The shadow's own baked-in flip_v (see make_silhouette_shadow)
			# makes it read as "the body, upside down" relative to whatever
			# the body currently shows -- when the body itself is ALSO
			# flip_v'd, that has to cancel out, or the shadow doubly flips
			# back to matching the (already-mirrored) body instead of
			# staying upside-down relative to it.
			sprite.flip_v = not flip_v
			sprite.rotation = rotation
			sprite.scale = Vector2(
				_shadow_base_scale.x, _shadow_base_scale.y * DropShadow.stretch_for_elevation(sun_elevation_deg)
			)


## For World's mouse-hover animal-name tooltip.
func get_display_name() -> String:
	return info.display_name if info != null else ""


var _lod_accumulated := 0.0

## Distance-based update rate (see SimulationLod). Returns the time to advance
## by, or NEGATIVE when this frame should be skipped entirely.
##
## Negative rather than zero as the skip signal, because zero is a legitimate
## step: a zero-delta frame still has to run the body (a caller passing 0.0
## expects state to settle, not to be ignored -- see
## test_processing_a_zero_delta_frame_leaves_is_moving_false).
##
## The accumulated time is handed to the update when it does run, so a skipped
## frame is never LOST time -- a creature far from the player lives at exactly
## the same rate, it just does so in fewer, larger steps that nobody is close
## enough to see.
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
## the caller rather than scanned per creature would be better still, but this
## is already off the hot path for everything nearby.
func _nearest_player_position():
	# Not in the tree (a marker built standalone in a test) means there is no
	# player to measure against, so it runs at full rate.
	if not is_inside_tree():
		return null
	# Cache the player node so this LOD-distance check (run every frame for
	# every creature) doesn't re-query the whole "player" group each time --
	# just re-look-up when the cached ref is gone (player despawn/respawn).
	if _cached_player == null or not is_instance_valid(_cached_player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return null
		_cached_player = players[0]
	return _cached_player.position


var _cached_player: Node = null


func _process(frame_delta: float) -> void:
	# Animals far from the player advance in fewer, larger steps (see
	# SimulationLod) -- same time passes, fewer updates to pay for.
	var delta := _lod_step(frame_delta)
	if delta < 0.0:
		return
	_elapsed_time += delta
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	# Runs unconditionally, ahead of every early-return branch below (rope,
	# tame order, foraging, knockback) -- a sick animal keeps getting sicker
	# (and can still die) no matter what it's doing that frame, the same way
	# _needs.advance never pauses for those states either.
	_disease_step(delta)
	if is_queued_for_deletion():
		return  # died of disease this frame -- nothing below has a live marker to act on

	if _knockback_time_remaining > 0.0:
		var result := _knockback.step(_knockback_remaining, _knockback_time_remaining, delta)
		position += result.step
		_knockback_remaining = result.remaining
		_knockback_time_remaining = result.time_remaining
		_sync_grounded_children()
		return  # a shove overrides normal AI movement while it plays out

	if _world == null or info == null:
		_wander_step(delta)
		_sync_grounded_children()
		return

	_needs.advance(delta)
	if not _restrained:
		_struggle_fatigue = Taming.fatigue_after_rest(_struggle_fatigue, delta)
	energy = AnimalReproduction.decay(energy, delta)
	_seconds_since_birth += delta
	_current_action = "walk"  # overridden below by whatever the AI actually does

	# Active foraging comes BEFORE _satisfy_needs_in_place, which is now the
	# fallback rather than the main event: an animal that can see something
	# to eat walks to it and eats that, and only an animal with nothing in
	# reach falls back to cropping whatever biome it happens to stand on.
	# A caught animal stops making its own decisions about where to go: it
	# fights the rope on its own clock and is towed along by it. Fleeing in
	# particular must not run -- the whole point of the rope is that it
	# cannot leave (see docs/concept/taming.md).
	if _restrained:
		_step_restraint(delta)
	if _restrained:
		_step_led_movement(delta)
		_animation_step()
		_step_water_ripple(delta)
		_sync_grounded_children()
		return

	# A tamed animal that isn't on a rope is carrying out its last order
	# rather than living its own life. It still eats -- foraging runs first,
	# below -- but where it stands is the player's call now.
	if is_tame() and not _restrained and not _needs.is_hungry():
		_step_order(delta)
		_animation_step()
		_step_water_ripple(delta)
		_sync_grounded_children()
		return

	if _step_foraging(delta):
		_animation_step()
		_step_water_ripple(delta)
		_sync_grounded_children()
		return  # head down: a grazing animal is planted, it does not move

	_satisfy_needs_in_place()

	# Expensive sensing (node-group scans + terrain tile scans) is throttled and
	# cached; cheap behavior + movement still run every frame off the cache.
	_sense_accumulator += delta
	if _sense_accumulator >= SENSE_INTERVAL:
		_sense_accumulator = 0.0
		# Widened while already fleeing so the creature can't straddle one
		# threshold and dither in and out of it -- see FLEE_RELEASE_RADIUS.
		var threat_radius := FLEE_RELEASE_RADIUS if _is_fleeing else SENSE_RADIUS
		# One consolidated pass over the "creature" group per tick (see
		# _scan_nearby_creatures) instead of every bucket accessor below
		# independently rescanning it.
		_scan_nearby_creatures(threat_radius)
		# A tamed animal is not afraid of people any more (see fears_players):
		# players are sensed as threats, so leaving this alone would have a
		# horse the player just tamed spend the rest of its life fleeing them.
		var sensed_players := _nearby_in_group(PLAYER_GROUP, threat_radius) if fears_players() else []
		_cached_threats = sensed_players + _nearby_threat_creatures()
		_cached_caution_threats = (
			_nearby_in_group(PLAYER_GROUP, CAUTION_RADIUS) if fears_players() else []
		)
		_cached_prey = _nearby_prey_creatures()
		_cached_blockers = _blockers_near(BLOCKER_SCAN_RADIUS)
		_cached_nearby_herbivores = _nearby_herbivore_creatures()
		_herd_disease_step()
		_carrion_disease_step()
		# Fresh senses: a creature standing because the gate found nowhere
		# to go re-evaluates now, not per frame (see _gate_standing).
		_gate_standing = false
		_cached_food_direction = _food_direction()
		_cached_water_direction = _water_direction()

	var decision := _behavior.decide({
		"position": position,
		"temperament": info.temperament,
		"is_predator": info.is_predator,
		"health_fraction": info.health / info.max_health,
		"hungry": _needs.is_hungry(),
		"thirsty": _needs.is_thirsty(),
		"threats": _positions_of(_cached_threats),
		"prey": _positions_of(_cached_prey),
		"food_direction": _cached_food_direction,
		"water_direction": _cached_water_direction,
		"is_world_boss": info.is_world_boss,
		"is_aggroed": info.is_aggroed,
	})

	_apply_decision(decision, _cached_threats, _cached_prey, delta)
	_animation_step()
	_step_water_ripple(delta)
	_sync_grounded_children()


# -- taming: caught, held, fed (see docs/concept/taming.md) -------------------

## How often a restrained animal tries to break the rope. Long enough that a
## catch is a held moment the player watches rather than a coin flip resolved
## instantly, short enough that a healthy animal is usually gone before you
## have walked it anywhere.
const STRUGGLE_INTERVAL := 1.2


## Shows taming state only once the animal is actually in the taming loop --
## caught, or already tame. A horse standing in a field is not a project, and
## putting a progress bar over every animal in the world would say otherwise.
func _update_taming_readouts() -> void:
	var in_the_loop := _restrained or trust > 0.0
	_trust_bar.visible = in_the_loop
	_trust_bar.size.x = HEALTH_BAR_WIDTH * clampf(trust / Taming.TAME_TRUST, 0.0, 1.0)
	# The cue to act: shown when feeding would actually do something.
	_hunger_pip.visible = in_the_loop and not is_tame() and _needs.is_hungry()
	# Third readout (docs/concept/disease.md): a tamed/kept animal you've
	# invested trust in reads as sick the instant it happens, the same shape
	# hunger already uses -- not shown on every animal in the world, only one
	# already "in the loop" with the player.
	_sick_pip.visible = in_the_loop and disease_state == DiseaseModel.State.INFECTED


## How far a tamed animal told to STAY will drift from the spot it was left,
## and how close one told to FOLLOW comes before it stops walking.
##
## Following stops SHORT rather than at zero: a horse walks up to you and then
## stands there, and a target of zero distance would have it shoving into the
## player forever, never satisfied.
const STAY_RADIUS := 32.0
const FOLLOW_DISTANCE := 28.0


## Gives a tamed animal an order. Refused by anything that isn't tame -- a
## wild horse is nobody's to command (see Taming.accepts_orders).
func set_order(new_order: int) -> bool:
	if not Taming.accepts_orders(trust):
		return false
	order = new_order
	_stay_anchor = position
	return true


## Whether this animal still treats players as something to run from.
##
## A tamed animal does not: players are sensed as THREATS (see the
## _cached_threats scan), so without this a horse the player spent five
## carrots taming would spend the rest of its life fleeing from them.
func fears_players() -> bool:
	return not is_tame()


## Movement for a tamed, un-roped animal carrying out its order.
func _step_order(delta: float) -> void:
	if order == Taming.ORDER_STAY:
		# Milling about where it was left: the stay anchor plays the part the
		# rope anchor does for a tied animal, so this reuses the same "walk
		# back when you have drifted too far" shape rather than a second one.
		var pull := RopeTether.pull_direction(position, _stay_anchor, STAY_RADIUS)
		if pull != Vector2.ZERO:
			_advance_gated(pull, CreatureWander.WANDER_SPEED, delta, false)
		else:
			_wander_step(delta)
		return

	var to_owner := follow_target - position
	if to_owner.length() <= FOLLOW_DISTANCE:
		_wander_step(delta)  # arrived: stand around near them
		return
	_advance_gated(to_owner.normalized(), SEEK_SPEED, delta, false)


## Whether this animal is tied to a fixed point rather than being led.
##
## A tied animal is one the player deliberately left somewhere, so it is kept
## across a chunk unload even at zero trust (see KeptAnimals) -- finding it
## gone would be the world losing something you put down.
func is_tied_up() -> bool:
	return _restrained and _tied

func tie_anchor() -> Vector2:
	return _rope_anchor


## Puts a saved animal back the way the player left it (see KeptAnimals).
## Restores the rope directly rather than going through restrain_to, because
## re-catching it would restart the struggle it already gave up on.
func restore_taming(saved_trust: float, saved_order: int, was_tied: bool, anchor_point: Vector2) -> void:
	trust = saved_trust
	order = saved_order
	if was_tied:
		_restrained = true
		_tied = true
		_rope_anchor = anchor_point
		# It was already broken to the rope before it was saved; making it
		# fight again on load would be the world forgetting.
		_struggle_fatigue = 1.0
	_stay_anchor = position


func is_restrained() -> bool:
	return _restrained


## Whether the player has a stake in this animal -- tamed, part-way tamed, or
## on the end of a rope right now.
##
## This is the line between "an animal the land supports" and "an animal the
## player is looking after", and it decides what the AGGREGATE model is allowed
## to do. EarthChunkManager._thin_creatures already refuses to cull an invested
## animal to make room for wild ones, and _die() refuses to book one against
## the region's population for the same reason: carrying capacity governs wild
## animals, and the player's stock is deliberately extra (see KeptAnimals).
##
## Deliberately BROADER than KeptAnimals.is_worth_keeping, which asks a
## different question -- what survives a chunk unload, where a merely-led
## animal is with the player anyway and needs no saving. Here the question is
## whose books the animal is on, and a horse on a rope is already off the
## wild ones.
func is_player_invested() -> bool:
	return trust > 0.0 or _restrained


func is_tame() -> bool:
	return Taming.is_tame(trust)


## Catches this animal on a lasso whose other end is at `anchor`. Called again
## each frame by the holder to move the anchor (which is what "leading" is).
## Refused outright for anything a rope and a carrot are the wrong tools for --
## see Taming.can_be_tamed.
## `tied` distinguishes "the loose end is knotted to a tree" from "the player
## is holding it". Only a tied animal is somewhere the player deliberately
## LEFT it, which is what makes it worth keeping across a chunk unload even at
## zero trust (see KeptAnimals).
func restrain_to(anchor: Vector2, tied: bool = false) -> bool:
	if info == null or not Taming.can_be_tamed(info.species, info.is_predator):
		return false
	if not _restrained:
		_restrained = true
		_struggle_elapsed = 0.0
	_rope_anchor = anchor
	_tied = tied
	return true


## Lets the animal go. Trust it has already earned is deliberately KEPT: the
## rope is only what stops it leaving, and losing the feeding progress every
## time the rope came off would make feeding pointless.
func release() -> void:
	_restrained = false
	_tied = false


## Feeds the animal a treat, returning whether it actually learned anything.
## Only counts while it is hungry -- the rule the whole system rests on, so
## taming is paced by the animal's own hunger clock rather than by how fast
## the player can click (see Taming.trust_after_feeding).
func feed_treat() -> bool:
	if info == null:
		return false
	var was := trust
	trust = Taming.trust_after_feeding(trust, _needs.is_hungry())
	if trust == was:
		return false
	_needs.feed()
	_gain_energy()
	_current_action = "eat"
	return true


## One frame of being on the end of a rope. Returns true while the animal is
## still held, false on the frame it breaks free.
##
## Fighting the rope costs it condition, so a long hold is winnable -- and the
## damage is real damage, which is what makes wearing an animal down a
## strategy with a cost rather than a free timer.
func _step_restraint(delta: float) -> void:
	_struggle_elapsed += delta
	if _struggle_elapsed < STRUGGLE_INTERVAL:
		return
	_struggle_elapsed = 0.0

	# A tamed animal has no reason to fight the rope any more, and an animal
	# that has fought itself to a standstill has no fight left (see
	# Taming.has_given_up -- without it, a tied horse eventually always
	# escapes and taming can never be finished).
	if is_tame() or Taming.has_given_up(_struggle_fatigue):
		return

	_struggle_count += 1
	var health_fraction := info.health / info.max_health if info.max_health > 0.0 else 0.0
	var condition := Taming.effective_condition(health_fraction, _struggle_fatigue)
	var roll := float(absi(hash("%d_%d_struggle" % [wander_seed, _struggle_count])) % 10000) / 10000.0
	if roll < Taming.break_free_chance(condition):
		release()
		# It has learned what the rope means: bolt.
		_flee_direction = (position - _rope_anchor).normalized()
		_flee_commit_remaining = FLEE_COMMIT_SECONDS
		return
	# Fighting the rope TIRES the animal rather than wounding it -- a caught
	# horse should be exhausted, not nearly dead (see Taming.STRUGGLE_FATIGUE).
	_struggle_fatigue = Taming.fatigue_after_struggle(_struggle_fatigue)


## Where a restrained animal is allowed to be, applied AFTER its own movement:
## a rope is a rope, so whatever the AI did this frame it cannot end up
## further out than the rope is long (see RopeTether).
func _apply_rope_limit() -> void:
	position = RopeTether.clamped_position(position, _rope_anchor, RopeTether.ROPE_LENGTH)


## Movement while on the end of a rope: the animal walks itself back when the
## rope goes taut and mills about on its own while it is slack, then is held
## at rope length regardless.
##
## The walk still goes through the ordinary gated step, so a led horse walks
## AROUND a tree rather than being dragged through it, and still turns to face
## where it is going rather than moonwalking after the player.
func _step_led_movement(delta: float) -> void:
	var pull := RopeTether.pull_direction(position, _rope_anchor, RopeTether.ROPE_LENGTH)
	if pull != Vector2.ZERO:
		_advance_gated(pull, SEEK_SPEED, delta, false)
	else:
		_wander_step(delta)
	_apply_rope_limit()


## Grazing/drinking happen wherever the creature already stands on the right
## terrain -- herbivores eat food biomes, everyone drinks at water. (Predators
## don't graze; they feed by catching prey, handled in _apply_decision.)
func _satisfy_needs_in_place() -> void:
	var tile := _current_tile()
	if _needs.is_thirsty() and _perception.is_on(_world, tile, "water"):
		_needs.drink()
		_current_action = "drink"
	# Grazing deliberately does NOT happen here any more. Feeding off the
	# biome underfoot the moment an animal got hungry meant a horse on
	# grassland was never hungry for longer than one frame, so it never had a
	# reason to walk anywhere and nothing about eating was ever visible. It
	# now runs as a head-down bout through the forage cycle (see
	# GrazerForaging.FOOD_UNDERFOOT), which is also what keeps an animal fed
	# where there are no tufts, fruit or worms to be seen.
	if _needs.is_hungry() and not info.is_predator and _forage_kinds().is_empty():
		# A herbivore with no forage diet at all still eats the old way,
		# rather than being left with no way to feed itself.
		if _perception.is_on(_world, tile, "food"):
			_needs.feed()
			_gain_energy()
			_current_action = "eat"


## Eating raises bioenergetic condition (see AnimalReproduction) -- called
## wherever the creature actually feeds (grazing, dropped fruit, or predation).
func _gain_energy() -> void:
	energy = AnimalReproduction.feed(energy, FEED_ENERGY)


## Whether this creature is in condition to reproduce right now: well-fed,
## healthy, and past its birth cooldown (see AnimalReproduction / the
## bioenergetics section of concept/ecosystem_dynamics.md). World checks this
## for near creatures and spawns an offspring when true.
func can_reproduce() -> bool:
	if info == null or info.max_health <= 0.0:
		return false
	return AnimalReproduction.can_reproduce(energy, info.health / info.max_health, _seconds_since_birth)


## Called by World after this creature births an offspring: pays the energy
## cost (dropping it below the threshold) and restarts the birth cooldown, so
## it can't immediately breed again.
func on_reproduced() -> void:
	energy = AnimalReproduction.energy_after_birth(energy)
	_seconds_since_birth = 0.0


## Called by the world loop when this creature consumes a dropped food ground
## item (see World._step_herbivore_food_consumption) -- trees feed animals.
func on_ate_food() -> void:
	_needs.feed()
	_gain_energy()
	_current_action = "eat"


## Records a water disturbance (see EarthChunkManager.record_water_disturbance)
## while this creature is actively swimming -- mirrors player.gd's own
## ripple step. `_world` is the owning EarthChunkManager (see
## creature_renderer.gd's spawn_creature_marker); duck-typed since this
## marker deliberately stays untyped against it elsewhere too.
func _step_water_ripple(delta: float) -> void:
	if _current_action != "swim" or _world == null:
		_water_ripple_accumulator = 0.0
		return
	_water_ripple_accumulator += delta
	if _water_ripple_accumulator < WATER_RIPPLE_INTERVAL:
		return
	_water_ripple_accumulator = 0.0
	if _world.has_method("record_water_disturbance"):
		_world.record_water_disturbance(position)


## Swaps the sprite among this action's generated frames (see
## ProceduralAnimalAnimation): walking legs alternate, attacks lunge, eating/
## drinking dips the head, swimming bobs half-submerged. The action itself is
## set as a side effect of what the AI actually did this frame (_apply_decision/
## _satisfy_needs_in_place), with an on-water check overriding to "swim".
##
## "walk" specifically is gated on _is_moving: the gait cycle used to play off
## elapsed time alone, so legs kept swinging through a stride even while the
## creature genuinely wasn't advancing (reported: "their legs are animated
## even when they stand still"). Not moving falls back to ProceduralAnimal-
## Animation's "idle" action -- a single static neutral pose -- instead.
func _animation_step() -> void:
	if info == null:
		return
	if _world != null and _perception.is_on(_world, _current_tile(), "water"):
		_current_action = "swim"

	var action := _current_action
	if action == "walk" and not _is_moving:
		action = "idle"

	var uses_illustrated := _illustrated.has_action(info.species, action)
	if not _animation_frames.has(action):
		if uses_illustrated:
			_animation_frames[action] = _illustrated.generate_textures(info.species, action)
		else:
			# textures_for, NOT generate_textures: frame sets are shared
			# between animals of the same look instead of drawn fresh per
			# individual (see ProceduralAnimalAnimation.LOOK_VARIANTS -- a
			# herd all reaching a new action together cost 1.18 seconds of
			# drawing inside one 5-second window).
			_animation_frames[action] = _animation.textures_for(info.species, action, wander_seed)
	# Which way the frames now showing are drawn -- the procedural generator
	# always faces right, an illustrated sheet may not (see _art_faces_left).
	# When that convention CHANGES (an illustrated species falling back to
	# procedural art for eat/attack, or back again), flip_h has to flip with
	# it: flip_h means "mirrored from the source art", so leaving it alone
	# while the source art's own facing flips would spin the creature around
	# on screen for exactly the frames around the swap -- caught by
	# test_a_wandering_creature_never_translates_against_its_own_facing.
	var art_faces_left := uses_illustrated and _illustrated.faces_left(info.species)
	if art_faces_left != _art_faces_left:
		flip_h = not flip_h
		_art_faces_left = art_faces_left

	var frames: Array = _animation_frames[action]
	if action == "walk" or action == "swim":
		# Gait cycles are paced by ground actually covered, not wall-clock
		# time (see GAIT_STRIDE_PER_FRAME) -- legs cycle faster the faster
		# the creature really moves, and freeze the moment it stops.
		texture = frames[int(_gait_distance / GAIT_STRIDE_PER_FRAME) % frames.size()]
	else:
		texture = frames[int(_elapsed_time / ANIMATION_FRAME_DURATION) % frames.size()]
	_apply_action_scale(uses_illustrated, action)
	_apply_submersion(action, uses_illustrated)


## Tints whatever part of the body is below the waterline while swimming
## (see SubmersionShader, the same effect the player already uses -- world-
## space Y so it reads as one shared phenomenon rather than a per-creature
## invention).
##
## ONLY for illustrated species: their swim frames are just the walk cycle
## reused (see IllustratedAnimalSprite.has_action), so without this a
## swimming horse simply walks across the surface, fully dry (reported: "it
## doesn't have a swim animation instead it walks on the water... sprite
## should be submerged and tinted like the others"). A PROCEDURAL species'
## swim frames already have the water painted into the pixels
## (ProceduralAnimalAnimation._swim_frame), so shading them again would tint
## them twice.
##
## Each creature owns its own SubmersionShader instance, so
## `shared_material()` here means "shared across this creature's frames",
## not across creatures -- the waterline is a WORLD Y, and two creatures
## swimming at different depths on screen need different ones (the player
## sets its own on its own instance for exactly the same reason).
func _apply_submersion(action: String, uses_illustrated: bool) -> void:
	if action != "swim" or not uses_illustrated:
		# Guarded: unconditionally clearing wrote a shader uniform every
		# frame for every creature that had EVER swum, forever after.
		if _submersion != null and _waterline_active:
			_submersion.clear_waterline()
			_waterline_active = false
		return
	if _submersion == null:
		_submersion = SubmersionShader.new()
		material = _submersion.shared_material()
	_submersion.set_waterline(to_global(Vector2(0.0, _illustrated.waterline_offset_y(info.species))).y)
	_waterline_active = true


## `scale` used to be set ONCE at spawn time (see CreatureRenderer.
## _build_marker), calibrated for whichever canvas that species' INITIAL
## texture used -- an illustrated species' idle frame. Switching to an
## action illustrated art doesn't cover (swim/drink/attack, or eat for
## horse specifically) swaps to a MUCH smaller procedural canvas (48x32,
## see ProceduralAnimalSprite.WIDTH/HEIGHT) without ever revisiting scale,
## rendering the creature far too small (reported: "when the horse enters
## the water it becomes tiny"). Recomputed every animation step instead --
## mirrors _build_marker's own two formulas exactly, so the on-screen size
## never jumps at the moment CreatureRenderer's spawn-time value gets
## superseded. The shadow's own base scale (see set_shadow/
## _sync_grounded_children) is kept in lockstep, or it would visibly
## mismatch the body's new size.
func _apply_action_scale(uses_illustrated: bool, action: String = "walk") -> void:
	# Scale only ever changes when the ACTION changes (each action may come
	# from its own differently-sized source file). Re-deriving it every frame
	# for every creature was pure waste -- see marker_scale's own note on the
	# per-frame cost this used to carry.
	if action == _scaled_action:
		return
	_scaled_action = action
	var new_scale: Vector2
	if uses_illustrated:
		# Per ACTION: an action may come from its own differently-sized
		# source file (see IllustratedAnimalSprite.marker_scale).
		new_scale = Vector2.ONE * _illustrated.marker_scale(info.species, action)
	else:
		var species_scale: float = AnimalAnatomy.profile_for(info.species).world_scale
		new_scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * species_scale
	if new_scale == scale:
		return
	scale = new_scale
	_shadow_base_scale = new_scale


## How fast a serpent can swing its heading, in radians/sec. A snake is a
## long rigid body: it cannot translate sideways or reverse the way a
## four-legged animal can shuffle.
const SERPENT_TURN_RATE := 2.4

## Deadzone on the requested direction's own x component (a roughly
## unit-length vector, not a raw pixel delta) before flipping which way a
## legged creature faces. Without one, near-vertical movement flickers the
## flip every frame as x crosses zero -- the same doubled-image artifact the
## birds shipped with before their own FACING_DEADZONE was added. This is
## the ONLY debounce a legged animal's facing gets -- see _advance's doc
## comment for why a DISTANCE-based commit used to also gate it, and why
## that was removed.
const FACING_DEADZONE := 0.15

## A serpent's actual heading, turned toward smoothly rather than snapped to
## (see _advance) -- a long thin body genuinely reads fine rotated to any
## angle, so a snake turns first and then rotates its whole sprite to match.
## UNUSED by legged animals: see _advance's doc comment for why they get a
## different treatment entirely (two attempts at unifying the two failed).
var _heading := Vector2.RIGHT

## Whether this creature actually advanced last time _advance ran (see
## _animation_step): the walk-gait animation plays only while this is true,
## instead of cycling off elapsed time regardless of whether the creature was
## really moving (reported: "their legs are animated even when they stand
## still").
var _is_moving := false

## Per-creature submersion tint while swimming, created lazily the first
## time this creature actually enters water (see _apply_submersion) -- most
## creatures never swim, and a ShaderMaterial per marker is not free.
var _submersion: SubmersionShader = null
## Whether the waterline uniform is currently set -- see _apply_submersion.
var _waterline_active := false

## The action `scale` was last computed for -- see _apply_action_scale.
var _scaled_action := ""

## How long a fleeing animal holds its escape heading before re-aiming.
const FLEE_COMMIT_SECONDS := 1.1
var _flee_direction := Vector2.ZERO
var _flee_commit_remaining := 0.0

## Whether this creature is currently in a flee episode -- the state half of
## the flee Schmitt trigger (see FLEE_RELEASE_RADIUS): it widens its own
## threat-sensing radius while true, so a threat sitting right on
## SENSE_RADIUS can't be repeatedly acquired and dropped.
var _is_fleeing := false

## A facing change is COMMITTED for this long: a reversal request inside the
## window is refused outright -- the creature stands still that frame rather
## than either flipping again (erratic) or moving backward against its
## facing (moonwalking, the failure mode that killed the old distance-based
## commit; refusing to MOVE is what makes a time-based commit safe).
## Reported, explicitly: "if it gets blocked by a tree and changes direction
## it should not be allowed to instantly flip again". Real animals do
## exactly this: stop, then turn.
const FACING_COMMIT_SECONDS := 0.8
var _facing_commit_remaining := 0.0

## True after the movement gate reported NOWHERE to go -- held until the
## next sensing tick rather than re-derived per frame. Re-scanning all of
## the gate's candidate turns against every nearby blocker EVERY frame for
## a creature that is just standing there was the per-frame cost that
## tipped the game over its frame budget (reported: "the lag is... sth that
## recently changed with horse movement. Rain just puts enough load that it
## becomes noticable" -- a wedged creature, e.g. the spawn horse against a
## tree, paid the gate's full worst case every single frame). The world
## cannot have changed between sensing ticks anyway: blockers are only
## refreshed then (see _cached_blockers).
var _gate_standing := false


## Whether the art CURRENTLY on this sprite is drawn facing left (see
## IllustratedAnimalSprite.faces_left). Not a fixed per-species fact: an
## illustrated species falls back to the procedural generator for the
## actions its own sheet doesn't cover (eat/attack -- see _animation_step),
## and the procedural generator always draws facing RIGHT, so a single
## creature's art convention genuinely changes with its action. Refreshed
## by _animation_step, which is the one place that knows which generator
## actually produced the frames now showing.
var _art_faces_left := false


## Which way this creature VISUALLY faces on screen right now: +1 for right,
## -1 for left. `flip_h` alone can't answer that -- it means "mirrored from
## whatever the source art happens to be", and the source art doesn't face a
## consistent direction (see _art_faces_left). Conflating the two is exactly
## what made the horse walk backwards in every direction: its sheet is drawn
## facing LEFT, so `flip_h = desired.x < 0` (correct only for right-facing
## art) mirrored it precisely the wrong way round every single frame, while
## the tests -- which asserted on `flip_h` under the same wrong assumption --
## happily passed.
func facing_sign() -> float:
	return 1.0 if flip_h == _art_faces_left else -1.0


## True for the legless body plans (see AnimalAnatomy.SERPENT_SPECIES).
func _is_serpent() -> bool:
	return info != null and AnimalAnatomy.SERPENT_SPECIES.has(info.species)


## Moves toward `desired`. Two genuinely different treatments by body plan --
## tried unifying them (twice) and both failed for the same underlying
## reason: a legged animal's art is a strict left/right side-view silhouette
## with legs baked pointing toward the ground.
##
## - A SERPENT turns its heading toward `desired` first and advances only
##   along the heading actually reached (never straight toward the raw
##   requested direction -- that's what read as sliding sideways or snapping
##   backwards without turning), then rotates its whole sprite to match. A
##   long thin body genuinely reads fine at any angle.
## - A LEGGED animal just advances straight toward `desired` -- sideways,
##   diagonal, whatever; there's no heading to turn, and no rotation. Forcing
##   it through the serpent's turn-before-advance made it turn toward
##   directions it could never actually draw (still just two facings either
##   way), and rotating the whole sprite to the heading is worse: the instant
##   the heading isn't near-horizontal the legs rotate away from the ground
##   with it (a horse "facing up" ends up lying on its side -- reported
##   directly: "that literally rotates the horse so that it's legs are
##   upside down... legs obviously at the bottom / floor"). It only ever
##   flips to keep its drawn facing matching which way it's actually
##   currently walking, off the requested direction itself, IMMEDIATELY --
##   on the very same frame the direction's sign disagrees with the current
##   facing -- rather than off a lagging position delta, so it can never
##   appear to walk backwards relative to its own facing (reported
##   requirement: "make it move sideways but not backwards, if wants to walk
##   backwards flip it to orient"). This used to be gated behind a DISTANCE-
##   based commit (must travel 3 tiles before flipping again, to stop rapid
##   direction noise from flickering the facing) -- removed after it
##   overcorrected: a creature given a genuinely SUSTAINED new direction (not
##   noise) still held its stale old facing until it had physically covered
##   3 tiles, which IS real backward/sideways-backward translation the whole
##   time it hadn't caught up (reported again, worse: "the horse walks
##   backwards or diagonally backwards sometimes... looks like it's
##   moonwalking"). Unlike a serpent, whose travel direction and visual
##   heading can never disagree by construction (it always moves along its
##   own gradually-turning `_heading`, never straight toward the raw
##   `desired`), a legged animal's binary either-way facing has no way to
##   represent "still catching up" -- any frame spent facing the wrong way
##   IS a frame of visible backward sliding, so there's no safe amount of
##   delay to add. The instability the distance commit was originally
##   compensating for is fixed further upstream now instead: flee commits to
##   one heading for FLEE_COMMIT_SECONDS (see _apply_decision) and wander/
##   search only re-derive a new heading once per CreatureWander.
##   DIRECTION_CHANGE_INTERVAL, so `desired` itself is no longer noisy
##   frame-to-frame the way it was when ThreatAvoidantWander's bias was
##   recomputed fresh off a raw, ever-changing angle every single tick.
##   FACING_DEADZONE is the only debounce left, and it's a different,
##   narrower one: it only suppresses a genuinely near-vertical `desired`
##   (an ambiguous x-sign) from flipping at all, not a real reversal.
func _advance(desired: Vector2, speed: float, delta: float) -> void:
	if desired.length() < 0.001:
		_is_moving = false
		return
	# Herd (foot-and-mouth-like) disease's real secondary effect (docs/
	# concept/disease.md): it doesn't damage directly, it makes the carrier
	# measurably easier prey by slowing it down (see DiseaseModel.
	# movement_speed_multiplier). The single choke point every intent's
	# movement (wander/flee/seek/hunt/attack) already funnels through, via
	# _advance_gated/_advance_avoided calling this -- so one multiplier here
	# covers all of them.
	if disease_id == DiseaseModel.HERD and disease_state == DiseaseModel.State.INFECTED:
		speed *= _disease_model.movement_speed_multiplier(disease_severity)
	_facing_commit_remaining = maxf(0.0, _facing_commit_remaining - delta)
	var position_before := position
	if not _is_serpent():
		var motion := desired
		if absf(desired.x) >= FACING_DEADZONE:
			if signf(desired.x) != facing_sign():
				# A genuine reversal. Inside the commit window it is refused
				# outright -- stand this frame rather than flip again or
				# moonwalk (see FACING_COMMIT_SECONDS). Outside it, mirror
				# so the creature VISUALLY faces the way it's travelling --
				# which way that is depends on which way the source art
				# already faces, see facing_sign/_art_faces_left.
				if _facing_commit_remaining > 0.0:
					_is_moving = false
					return
				flip_h = (desired.x < 0.0) != _art_faces_left
				_facing_commit_remaining = FACING_COMMIT_SECONDS
		else:
			# Near-vertical: too ambiguous an x sign to justify flipping (that
			# would flicker on ordinary noise), but applying its small
			# backward component anyway is exactly the residual moonwalking
			# left over once immediate flipping fixed the big reversals.
			# Drop it and travel purely sideways instead -- "quadrupeds should
			# only be allowed to move forward and sideways".
			if motion.x * facing_sign() < 0.0:
				motion.x = 0.0
		position += motion * speed * delta
	else:
		_heading = Vector2.from_angle(
			lerp_angle(_heading.angle(), desired.angle(), clampf(SERPENT_TURN_RATE * delta, 0.0, 1.0))
		)
		position += _heading * speed * delta
		rotation = _heading.angle()
		# Rotating past vertical would leave it belly-up, so mirror across the
		# body's long axis instead of letting it invert.
		flip_v = absf(_heading.angle()) > PI * 0.5
		flip_h = false
	# Whether a requested direction actually translated into real movement --
	# NOT just whether one was requested (see _is_moving's own doc comment):
	# a creature whose position doesn't actually change despite wanting to
	# move (blocked by an obstacle, once that lands, or speed/delta reducing
	# the step to nothing) should read as standing still, not walking in
	# place (reported: "should only render walk animation when moving, not
	# when stuck against a tree or standing still").
	var travelled := position.distance_to(position_before)
	_is_moving = travelled >= 0.001
	_gait_distance += travelled


func _apply_decision(decision: Dictionary, threats: Array, prey: Array, delta: float) -> void:
	_is_fleeing = decision.intent == "flee"
	if not _is_fleeing:
		# A flee episode's committed heading/timer must not leak into a
		# LATER, separate flee episode -- _flee_commit_remaining only ever
		# decremented while actively fleeing, so a flee that ended early
		# (escaped SENSE_RADIUS before its own commit window expired) left
		# both frozen at their stale values instead of resetting. The next
		# time a threat was sensed, that stale heading got reused verbatim
		# (see the "flee" branch below) even if the new threat was
		# somewhere else entirely -- which could point the creature TOWARD
		# it instead of away (reported again: "the horse still has flee
		# hystery and tries to walk into the players flee radius"). This
		# only runs on a frame that ISN'T fleeing, so one continuous flee
		# streak still holds its heading across its own frames exactly as
		# before -- only a genuine gap between two separate episodes clears it.
		_flee_direction = Vector2.ZERO
		_flee_commit_remaining = 0.0
	match decision.intent:
		"flee":
			# Commit to a flee heading for a beat instead of re-deriving it
			# from the threat's CURRENT position every tick. Re-deriving made
			# a fleeing animal reverse each time the pursuer moved past it,
			# which read as jittering back and forth rather than escaping --
			# the same re-target-every-tick mistake as the pollinators.
			_flee_commit_remaining -= delta
			if _flee_commit_remaining <= 0.0 or _flee_direction == Vector2.ZERO:
				_flee_direction = decision.direction
				_flee_commit_remaining = FLEE_COMMIT_SECONDS
			# Obstacle-gated but NOT threat-gated: a fleeing creature still
			# has to go around a tree, but must not be talked out of running
			# by the very thing it is running from.
			_advance_gated(_flee_direction, FLEE_SPEED, delta, false)
		"attack":
			_advance(decision.direction, HUNT_SPEED, delta)
			_try_attack(_nearest_node(threats))
			_current_action = "attack"
		"hunt":
			_advance(decision.direction, HUNT_SPEED, delta)
			_try_eat(_nearest_node(prey))
			_current_action = "attack"
		"seek_water":
			_advance_gated(decision.direction, SEEK_SPEED, delta, false)
		"seek_food":
			_advance_gated(decision.direction, SEEK_SPEED, delta, false)
		"search_water", "search_food":
			# Need exists but the resource isn't in sight -- range outward to
			# look for it, rather than orbiting home like idle wander. Still
			# caution-biased away from a nearby threat the same as ordinary
			# wander (see _caution_biased_step) -- this used to advance
			# straight off the raw roam heading, so a thirsty/hungry
			# creature would range straight toward a nearby player while
			# searching, cross into flee range, resume searching the
			# instant it was safely back outside it (still thirsty/hungry),
			# and range right back toward them -- forever (reported again:
			# "the horse and other animals... same flee hysteria the snake
			# had at the beginning").
			_advance_avoided(_wander.roam_direction(_elapsed_time, wander_seed), SEEK_SPEED, delta)
		_:
			_wander_step(delta)


## Species that inject venom on a successful bite (see VenomModel,
## docs/concept/ecosystem_dynamics.md's Species roster) -- a real mechanical
## difference from every other predator, not just a color/flavor one.
const VENOMOUS_SPECIES := {"venomous_snake": true}


func _try_attack(target: Node) -> void:
	if target == null or _attack_cooldown_remaining > 0.0:
		return
	if position.distance_to(target.position) > ATTACK_RANGE:
		return
	if target.has_method("take_damage"):
		target.take_damage(ATTACK_DAMAGE)
		if VENOMOUS_SPECIES.has(info.species) and target.has_method("apply_venom"):
			target.apply_venom()
		_try_transmit_predator_disease(target)
		_attack_cooldown_remaining = ATTACK_COOLDOWN


## Predator (rabies-like) disease transmission: rides this SAME bite,
## rolled only when the attacker itself is currently INFECTED with the
## PREDATOR archetype (docs/concept/disease.md "rides the existing attack-
## resolution path"). Works identically whether `target` is another
## creature or the player (see Player.apply_disease_bite) -- the doc's
## zoonotic spillover path is just this same duck-typed call landing on a
## Player instead of a CreatureMarker, no separate code path needed.
func _try_transmit_predator_disease(target: Node) -> void:
	if disease_state != DiseaseModel.State.INFECTED or disease_id != DiseaseModel.PREDATOR:
		return
	if not target.has_method("apply_disease_bite"):
		return
	_disease_roll_count += 1
	var chance := _disease_model.predator_bite_transmission_chance(region_tier)
	if _disease_model.attempt_infect(
		chance, hash("%d_%d_predator_disease" % [wander_seed, _disease_roll_count])
	):
		target.apply_disease_bite(DiseaseModel.PREDATOR)


func _try_eat(target: Node) -> void:
	if target == null:
		return
	if position.distance_to(target.position) > PREDATION_RANGE:
		return
	if target.has_method("take_damage"):
		target.take_damage(PREDATION_DAMAGE)
	_needs.feed()
	_gain_energy()


## Strips any component of `step` that points toward the nearest CAUTION_
## RADIUS-sensed threat (see ThreatAvoidantWander), leaving it untouched if
## none is nearby. CAUTION_RADIUS awareness, not SENSE_RADIUS: this runs
## BEFORE a step is taken, so a direction facing the player is never chosen
## in the first place while inside the wider radius -- rather than fleeing
## fast, overshooting SENSE_RADIUS, and only THEN discovering (with no
## awareness left) that moving freely walked straight back in. Shared by
## every non-urgent roaming movement -- ordinary idle wander (_wander_step)
## and searching for a sensed-nowhere resource (_apply_decision's
## "search_water"/"search_food") alike -- since both are "no specific
## reason to approach the player" movement the same way.
func _caution_biased_step(step: Vector2) -> Vector2:
	var nearest := _nearest_node(_cached_caution_threats)
	if nearest == null:
		return step
	var to_threat: Vector2 = nearest.position - position
	var distance := to_threat.length()
	if distance < 0.001:
		return step
	# Ramped 0 at CAUTION_RADIUS to full at SENSE_RADIUS rather than applied
	# at full strength anywhere inside CAUTION_RADIUS and not at all outside
	# it. That hard switch was its own limit cycle: avoidance shoved the
	# creature just past 160px, avoidance vanished, the home anchor pulled it
	# straight back inside, avoidance shoved it out again -- measured
	# oscillating between 155.0 and 160.6px from the player on a 16-frame
	# period, reversing its facing each time. Every boundary in this system
	# that switched hard has produced exactly this shape of bug (see also
	# CreatureWander.direction_at and FLEE_RELEASE_RADIUS); ramps do not.
	var strength := clampf((CAUTION_RADIUS - distance) / (CAUTION_RADIUS - SENSE_RADIUS), 0.0, 1.0)
	var toward := to_threat / distance
	var inward := maxf(0.0, step.dot(toward))
	return step - toward * inward * strength


## Nearby solid props (trees, stones, ore) as plain {position, radius} data
## for CreatureMovementGate. Gathered on the throttled sensing tick, not per
## frame. Asks the world when it offers a bounded lookup (EarthChunkManager.
## solid_obstacles_near -- O(nearby), from its per-chunk bookkeeping); the
## group scan below is only the fallback for worldless/stub setups, since
## scanning the ENTIRE tree/stone groups per creature per tick was O(every
## prop in every loaded chunk) and visibly lagged the game once creatures
## did it (reported: "since the last change the game is laggy").
func _blockers_near(radius: float) -> Array:
	if _world != null and _world.has_method("solid_obstacles_near"):
		return _world.solid_obstacles_near(position, radius)
	var result: Array = []
	for group in [TREE_GROUP, STONE_GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			if position.distance_to(node.position) > radius:
				continue
			result.append({"position": node.position, "radius": _blocker_radius(node)})
	return result


## An obstacle's blocking radius, measured from its OWN collision shape
## rather than guessed per group: a tree's solid part is just its trunk (see
## TreeRenderer, which deliberately sizes the box to the trunk so you can
## walk under a canopy), and stones vary in size. Falls back to
## DEFAULT_BLOCKER_RADIUS for anything carrying no shape.
func _blocker_radius(node: Node) -> float:
	for child in node.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var extents: Vector2 = (child.shape as RectangleShape2D).size * 0.5
			return maxf(extents.x, extents.y)
	return DEFAULT_BLOCKER_RADIUS


## Moves along `desired` only if the step is actually clear (see
## CreatureMovementGate) -- steering around a tree/stone when one is in the
## way, and standing still when nothing is open at all, rather than moving
## into it and re-deciding next frame.
##
## `avoid_threats` is false for fleeing: a fleeing creature still dodges
## trees, but must not be talked out of running by the very thing it's
## running from.
func _advance_gated(desired: Vector2, speed: float, delta: float, avoid_threats: bool) -> void:
	if _gate_standing:
		# The gate already said "nowhere to go" this sensing window -- hold
		# idle until fresh senses instead of re-scanning every candidate
		# turn against every blocker per frame (see _gate_standing).
		_is_moving = false
		return
	# Nothing to avoid: skip the gate entirely. Most creatures, most of the
	# time, are in open ground with no tree, stone or threat in reach, and
	# running the full candidate search (plus allocating a threat-position
	# array) for them every frame was pure overhead -- measured at ~6us per
	# creature per frame, which at a few dozen loaded creatures is a
	# meaningful slice of the frame budget for no behavioural gain.
	var has_threats := avoid_threats and not _cached_caution_threats.is_empty()
	if _cached_blockers.is_empty() and not has_threats:
		_last_gated_heading = desired
		_advance(desired, speed, delta)
		return

	var threats: Array = _positions_of(_cached_caution_threats) if avoid_threats else []
	var facing := 0.0 if _is_serpent() else facing_sign()
	var heading := CreatureMovementGate.clear_direction(
		position, desired, MOVEMENT_LOOKAHEAD, _cached_blockers, threats, SENSE_RADIUS,
		_last_gated_heading, facing
	)
	_last_gated_heading = heading
	if heading == Vector2.ZERO:
		# Nowhere to go: stand still. Deliberately NOT a fallback move in some
		# other direction -- picking one anyway, every frame, is precisely
		# what produced the erratic flipping when wedged between the player
		# and a tree.
		_gate_standing = true
		_is_moving = false
		return
	_advance(heading, speed, delta)


## Moves along `raw` with avoidance applied, WITHOUT renormalizing away how
## much of it avoidance actually removed. Renormalizing is what turned a
## near-fully-cancelled step (a creature whose only way home is straight
## through the player) into a full-speed lurch in an ill-conditioned
## direction that reversed every single frame -- measured as a creature
## pinned 127px from the player with its distance-to-home flickering
## 54.0<->54.2 (reported: "it should not constantly flip when at the
## border"). Keeping the magnitude means a cornered creature simply slows
## to a stop facing away, which is both stable and what a real animal does.
func _advance_avoided(raw: Vector2, speed: float, delta: float) -> void:
	var step := _caution_biased_step(raw)
	if step.length() < 0.001:
		_is_moving = false
		return
	var surviving := clampf(step.length() / maxf(raw.length(), 0.0001), 0.0, 1.0)
	_advance_gated(step.normalized(), speed * surviving, delta, true)


func _wander_step(delta: float) -> void:
	# Grazing pause: some wander intervals are deliberate stands (see
	# CreatureWander.is_pausing) -- continuous never-resting drift read as
	# mechanical ("it doesn't look like natural wandering or foraging").
	# Only ordinary wander pauses; searching/seeking/fleeing never do.
	if _wander.is_pausing(_elapsed_time, wander_seed):
		_is_moving = false
		return
	# Routed through _advance (via _advance_avoided) rather than "position +=
	# step" directly, which is what this did until now. For every other
	# intent (flee/attack/hunt/seek) movement already went through _advance,
	# so it turned before moving in all of them -- but wandering is a
	# creature's DEFAULT state (caution-radius avoidance runs here, not in
	# flee), so bypassing _advance meant the one path most likely to be
	# active near a player never got the turn-first treatment, and still
	# translated straight toward whatever direction CreatureWander/the bias
	# picked -- sideways or backwards, from the sprite's own point of view,
	# whenever that direction opposed its current heading.
	var candidate := _wander.step_position(home, position, _elapsed_time, delta, wander_seed)
	_advance_avoided(candidate - position, CreatureWander.WANDER_SPEED, delta)


func _current_tile() -> Vector2i:
	return Vector2i(floori(position.x / _tile_size), floori(position.y / _tile_size))


func _food_direction() -> Vector2:
	if not _needs.is_hungry() or info.is_predator:
		return Vector2.ZERO
	# A committed bite outranks the biome: "walk toward greener tiles" is
	# what an animal does when it can see nothing specific to eat.
	if _has_forage_target:
		var to_bite := _forage_target - position
		if to_bite.length() > 0.001:
			return to_bite.normalized()
	return _perception.nearest_direction(_current_tile(), _world, SENSE_RADIUS_TILES, "food")


## Which food kinds this animal actually walks to. Empty for predators and
## anything else with no forage diet, which skips the whole cycle.
func _forage_kinds() -> Array:
	if info == null or info.is_predator:
		return []
	return GrazerForaging.forage_kinds(info.species, info.diet)


## Advances the graze cycle. Returns true while the animal is head-down, which
## the caller treats as "planted": no AI movement this frame.
##
## Sensing for a bite is deliberately NOT per-frame -- it rides the same
## SENSE_INTERVAL throttle the rest of the expensive senses do (see
## _sense_accumulator), since scanning the world's grass/fruit/seed/worm
## layers is exactly the kind of work that was measured as lag before.
func _step_foraging(delta: float) -> bool:
	if _forage_kinds().is_empty():
		return false

	# Hunger is what starts a bout; a fed animal lets the cycle idle so it
	# isn't holding a target it has no reason to walk to.
	if not _needs.is_hungry():
		_drop_forage_target()
		_forage.advance(delta)
		return false

	# A threat outranks a meal outright -- an animal being stalked lifts its
	# head and goes, it does not finish the mouthful.
	if not _cached_threats.is_empty():
		_drop_forage_target()
		_forage.abort()
		return false

	var swallowed := _forage.advance(delta)

	if _forage.phase == GrazerForaging.Phase.GRAZING:
		if swallowed:
			_take_forage_bite()
		_current_action = "eat"
		return true

	if _has_forage_target:
		if position.distance_to(_forage_target) <= GrazerForaging.ARRIVAL_DISTANCE:
			_forage.arrive()
			_current_action = "eat"
			return true
		if _forage.phase != GrazerForaging.Phase.APPROACHING:
			_drop_forage_target()  # the approach timed out under us
		return false

	if _forage.can_commit():
		_look_for_a_bite()
	return false


## Picks the next bite from whatever this animal's diet lets it see. Kinds are
## tried in diet order, so a boar prefers mast over grass without needing a
## weighting scheme.
func _look_for_a_bite() -> void:
	# Smell first, and much further than sight.
	#
	# An animal that only eats what it walks into is not foraging, it is
	# colliding with food -- which is why no boar was ever seen at a windfall
	# even when one was lying there. Sight reaches GrazerForaging.SEARCH_TILES;
	# a nose reaches Olfaction.MAX_RANGE_TILES, and tells the animal whether
	# the thing is worth crossing a field for at all.
	if _seek_by_smell():
		return
	for kind in _forage_kinds():
		var candidates := _visible_food(kind)
		if candidates.is_empty():
			continue
		var bite := GrazerForaging.choose_bite(position, candidates, wander_seed)
		if bite.is_empty():
			continue
		_forage_target = bite["position"]
		_forage_kind = kind
		_has_forage_target = true
		_forage.begin_approach()
		return

	# Nothing in sight to walk to. An animal standing on living ground crops
	# what is under it rather than starving -- the old biome grazing, except
	# it now costs a head-down bout like any other bite instead of zeroing
	# hunger the instant a hungry animal touched a green tile.
	if _perception.is_on(_world, _current_tile(), "food"):
		_forage_target = position
		_forage_kind = GrazerForaging.FOOD_UNDERFOOT
		_has_forage_target = true
		_forage.begin_approach()


## Heads for the best-smelling food in range, if this animal has a nose and
## anything out there appeals to it. Returns whether a target was taken.
func _seek_by_smell() -> bool:
	if _world == null or not _world.has_method("smells_near"):
		return false
	var species := info.species if info != null else ""
	if not ScentForaging.forages_by_smell(species):
		return false
	if not _forage_kinds().has(GrazerForaging.FOOD_FRUIT):
		return false
	var sources: Array = _world.smells_near(position, Olfaction.MAX_RANGE_TILES)
	var target := ScentForaging.best_source(species, position, sources)
	if target.is_empty():
		return false
	_forage_target = target["position"]
	_forage_kind = GrazerForaging.FOOD_FRUIT
	_has_forage_target = true
	_forage.begin_approach()
	return true


func _visible_food(kind: String) -> Array:
	var radius := int(GrazerForaging.SEARCH_TILES)
	match kind:
		GrazerForaging.FOOD_GRASS:
			if _world.has_method("grass_near"):
				return _world.grass_near(position, radius)
		GrazerForaging.FOOD_FRUIT:
			if _world.has_method("fruit_near"):
				return _world.fruit_near(position, radius)
		GrazerForaging.FOOD_SEED:
			if _world.has_method("seeds_near"):
				return _world.seeds_near(position, radius)
		GrazerForaging.FOOD_WORM:
			if _world.has_method("worms_near"):
				return _world.worms_near(position, radius)
	return []


## Removes the committed bite from the world and feeds on it. A bite that has
## gone (another animal got there first) simply feeds nothing -- the bout
## still plays out, which reads as the animal finding the patch already
## cropped rather than teleporting to another one.
func _take_forage_bite() -> void:
	if not _has_forage_target:
		return
	var got := false
	match _forage_kind:
		GrazerForaging.FOOD_UNDERFOOT:
			got = true  # it is standing in its food; there is nothing to remove
		GrazerForaging.FOOD_GRASS:
			got = _world.has_method("graze_grass_at") and _world.graze_grass_at(_forage_target)
		GrazerForaging.FOOD_FRUIT:
			got = _world.has_method("take_fruit_at") and _world.take_fruit_at(_forage_target) != ""
		GrazerForaging.FOOD_SEED:
			got = _world.has_method("take_seed_at") and _world.take_seed_at(_forage_target) != ""
		GrazerForaging.FOOD_WORM:
			got = _world.has_method("take_worm_at") and _world.take_worm_at(_forage_target)
	if got:
		_needs.feed()
		_gain_energy()
	_drop_forage_target()


func _drop_forage_target() -> void:
	_has_forage_target = false
	_forage_kind = ""


func _water_direction() -> Vector2:
	if not _needs.is_thirsty():
		return Vector2.ZERO
	return _perception.nearest_direction(_current_tile(), _world, SENSE_RADIUS_TILES, "water")


func _nearby_in_group(group: String, radius: float = SENSE_RADIUS) -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group(group):
		if node == self:
			continue
		if position.distance_to(node.position) <= radius:
			result.append(node)
	return result


## Single per-tick scan of the "creature" group (see SENSE_INTERVAL),
## classifying every other creature into the two buckets
## _nearby_threat_creatures/_nearby_prey_creatures/_nearby_herbivore_creatures
## need -- predators within this tick's threat_radius, and non-predators
## within SENSE_RADIUS -- in one pass instead of each accessor independently
## calling get_tree().get_nodes_in_group(GROUP_NAME) and re-filtering the
## whole population (previously up to 2x per tick for a herbivore marker,
## across however many creature markers are loaded that's O(n^2)).
func _scan_nearby_creatures(threat_radius: float) -> void:
	_creature_scan_count += 1
	var threats: Array = []
	var nonpredators: Array = []
	for node in get_tree().get_nodes_in_group(GROUP_NAME):
		if node == self or node.info == null:
			continue
		var distance := position.distance_to(node.position)
		if node.info.is_predator:
			if distance <= threat_radius:
				threats.append(node)
		elif distance <= SENSE_RADIUS:
			nonpredators.append(node)
	_scan_threat_candidates = threats
	_scan_nonpredator_candidates = nonpredators


## Other creatures within sense range that are predators to me (a herbivore's
## threats). Predators aren't threatened by other creatures, only by the player.
## Reads the current tick's _scan_nearby_creatures classification.
func _nearby_threat_creatures() -> Array:
	if info.is_predator:
		return []
	return _scan_threat_candidates


## Herbivores within sense range that a predator can hunt. Reads the current
## tick's _scan_nearby_creatures classification.
func _nearby_prey_creatures() -> Array:
	if not info.is_predator:
		return []
	return _scan_nonpredator_candidates


## Other herbivore-role creatures within sense range -- for herd disease
## transmission (see _herd_disease_step), NOT hunting: unlike
## _nearby_prey_creatures (predator-only), this only ever populates for a
## herbivore-role individual, since herd disease spreads herbivore to
## herbivore, never through a predator. Reads the current tick's
## _scan_nearby_creatures classification (the same bucket _nearby_prey_creatures
## reads -- the two never populate for the same individual, since one requires
## being a predator and the other requires not being one).
func _nearby_herbivore_creatures() -> Array:
	if info.is_predator:
		return []
	return _scan_nonpredator_candidates


## Cached node lists can span several frames (see SENSE_INTERVAL); a cached
## target may have been freed (eaten/killed) since -- skip invalid instances.
func _positions_of(nodes: Array) -> Array:
	var positions: Array = []
	for node in nodes:
		if is_instance_valid(node):
			positions.append(node.position)
	return positions


func _nearest_node(nodes: Array) -> Node:
	var best: Node = null
	var best_distance := -1.0
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var distance := position.distance_squared_to(node.position)
		if best == null or distance < best_distance:
			best = node
			best_distance = distance
	return best


## Reduces info.health; on death, leaves a real Carcass behind (see
## docs/concept/carrion.md) for a carcass-eligible species (see LootTable --
## the same species that used to get an instant loot spray now get a real
## carcass instead) and frees this marker. A species with nothing to yield
## (no LootTable entry) still just despawns, exactly like before.
##
## A world boss (see BossAggro, docs/concept/worldbosses.md) filters this
## FIRST, before any of the above: while not yet aggroed, a hit that
## doesn't clear BossAggro's real-damage threshold bounces off entirely --
## no health lost, no aggro gained, nothing else in this function runs.
## Once aggroed, or for any non-boss species, damage always applies exactly
## as before this feature existed.
func take_damage(amount: float) -> void:
	if info == null:
		return
	if info.is_world_boss and not info.is_aggroed:
		if not _boss_aggro.deals_real_damage(amount, info.max_health):
			return
		info.is_aggroed = true
	info.health = _health.take_damage(info.health, amount)
	_update_health_bar()
	if _health.is_dead(info.health):
		_die()


func _update_health_bar() -> void:
	if info == null or _health_bar_fill == null:
		return
	_health_bar_fill.size.x = _health_bar.fill_width(info.health, info.max_health, HEALTH_BAR_WIDTH)


## Shared death path: a real Carcass (see docs/concept/carrion.md) for a
## carcass-eligible species (see LootTable), then the marker frees itself.
## The ONE place a marker actually dies, whatever the cause -- ordinary
## take_damage above, and a lethal disease death (_disease_step below) alike
## (docs/concept/disease.md "Feeds carrion": a disease-driven die-off must
## be a real source of carrion, not a silent despawn, so it has to go
## through this exact same path, not a parallel one).
func _die() -> void:
	_book_death_against_the_region()
	_spawn_carcass_if_eligible()
	queue_free()


## Tells the region's aggregate that one of its animals is gone (see
## EcosystemSimulation.record_death).
##
## _die() is the single choke point EVERY death goes through -- combat,
## disease, a predator's kill -- which is exactly why the call belongs here
## rather than at each of those call sites. Until this existed the individual
## and aggregate halves of the simulation disagreed about mortality in one
## direction only: births were reported and deaths were not, so
## _reconcile_chunk_creatures restocked whatever the player had just hunted.
##
## Two guards, both deliberate. An animal the player has a stake in is not on
## the wild books at all (see is_player_invested). And the world is only asked
## if it can answer -- CreatureMarker runs against several stub and
## partially-built worlds, and a death is not worth a crash.
func _book_death_against_the_region() -> void:
	if _world == null or info == null or is_player_invested():
		return
	if not _world.has_method("record_death_at"):
		return
	_world.record_death_at(position, info.is_predator)


func _spawn_carcass_if_eligible() -> void:
	if _loot_table.drops_for(info.species).is_empty():
		return
	var carcass := Carcass.new()
	carcass.species = info.species
	carcass.position = position
	carcass.region_tier = region_tier
	get_parent().add_child(carcass)


# -- disease (see docs/concept/disease.md / DiseaseModel) ---------------------

## Called by an infected predator's bite (see _try_attack, the PREDATOR
## archetype's "rides the existing attack-resolution path") or a herd-
## disease proximity check (_herd_disease_step) -- infects this creature if
## it is currently SUSCEPTIBLE. A creature already INFECTED or RECOVERED
## (immune) can't be re-infected mid-cycle -- the real epidemiological
## constraint the SIRS states exist to express, not an oversight.
func apply_disease_bite(new_disease_id: String) -> void:
	if disease_state != DiseaseModel.State.SUSCEPTIBLE:
		return
	disease_state = DiseaseModel.State.INFECTED
	disease_id = new_disease_id
	disease_severity = 0.0
	_disease_state_seconds = 0.0
	_update_disease_tint()


## Authority-only: advances this creature's own SIRS cycle one tick (see
## DiseaseModel.advance_state) and routes a disease death through _die() --
## the exact same carcass path a predation kill already uses.
func _disease_step(delta: float) -> void:
	if disease_state == DiseaseModel.State.SUSCEPTIBLE:
		return
	_disease_roll_count += 1
	var result: Dictionary = _disease_model.advance_state(
		disease_state,
		disease_id,
		disease_severity,
		_disease_state_seconds,
		delta,
		hash("%d_%d_disease_progress" % [wander_seed, _disease_roll_count])
	)
	disease_state = result["state"]
	disease_severity = result["severity"]
	_disease_state_seconds = result["state_seconds"]
	if disease_state == DiseaseModel.State.SUSCEPTIBLE:
		disease_id = ""  # immunity waned -- healthy and vulnerable again
	_update_disease_tint()
	if result["died"]:
		_die()


## Visible symptom (docs/concept/disease.md "What you see is what's real"):
## reuses Sprite2D's own `modulate` rather than a new rendering system --
## same reasoning as the taming sick pip, but shown on EVERY infected
## creature, tamed or wild, not just ones the player has a stake in.
func _update_disease_tint() -> void:
	modulate = (
		SICK_MODULATE_COLOR if disease_state == DiseaseModel.State.INFECTED else HEALTHY_MODULATE_COLOR
	)


## Herd (foot-and-mouth-like) proximity transmission: an infected herbivore
## can pass it to a nearby SUSCEPTIBLE herbivore, density-weighted against
## this region's real herbivore population vs. carrying capacity (see
## DiseaseModel.herd_transmission_chance) -- the same real distance check
## GrazerForaging/courtship already resolve off, reused rather than adding a
## second spatial system. Called once per sensing tick (see _process), not
## every frame, matching every other proximity check's own cadence.
func _herd_disease_step() -> void:
	if info == null or info.is_predator:
		return
	if disease_state != DiseaseModel.State.INFECTED or disease_id != DiseaseModel.HERD:
		return
	if _world == null or not _world.has_method("herbivore_population_near"):
		return
	var target: Node = _nearest_node(_cached_nearby_herbivores)
	if target == null or target.disease_state != DiseaseModel.State.SUSCEPTIBLE:
		return
	var local_population: float = _world.herbivore_population_near(position)
	var capacity: float = _world.herbivore_capacity_near(position)
	var chance := _disease_model.herd_transmission_chance(local_population, capacity, region_tier)
	_disease_roll_count += 1
	if _disease_model.attempt_infect(
		chance, hash("%d_%d_herd_disease" % [wander_seed, _disease_roll_count])
	):
		target.apply_disease_bite(DiseaseModel.HERD)


## Carrion (anthrax-like) graze exposure: real blowflies/carrion beetles
## mechanically carry anthrax spores from an infected carcass to nearby
## vegetation, which grazing herbivores then ingest (docs/concept/
## disease.md). Simplified to direct proximity to the contaminated Carcass
## itself, rather than a separately-tracked "contaminated patch of grass"
## object -- this project has no such object today, and the carcass IS the
## real, already-visible source the player can see and avoid. Scans the
## SAME Carcass.GROUP_NAME group Player's own butcher step already scans.
## Called once per sensing tick, matching every other proximity check here.
func _carrion_disease_step() -> void:
	if info == null or info.is_predator or disease_state != DiseaseModel.State.SUSCEPTIBLE:
		return
	var nearest := _nearest_contaminated_carcass()
	if nearest == null:
		return
	_disease_roll_count += 1
	var chance := _disease_model.carrion_graze_transmission_chance(region_tier)
	if _disease_model.attempt_infect(
		chance, hash("%d_%d_carrion_graze" % [wander_seed, _disease_roll_count])
	):
		apply_disease_bite(DiseaseModel.CARRION)


func _nearest_contaminated_carcass() -> Node:
	var best: Node = null
	var best_distance := SENSE_RADIUS
	for node in get_tree().get_nodes_in_group(Carcass.GROUP_NAME):
		if not node.contaminated:
			continue
		var distance := position.distance_to(node.position)
		if distance <= best_distance:
			best = node
			best_distance = distance
	return best


## Starts a shove of `force` total displacement, played out smoothly over
## KNOCKBACK_DURATION (see _process/Knockback.step) rather than teleporting
## instantly. A knockback already in progress is replaced by the new one.
func apply_knockback(force: Vector2) -> void:
	_knockback_remaining = force
	_knockback_time_remaining = KNOCKBACK_DURATION
