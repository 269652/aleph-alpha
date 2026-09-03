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
const AnimalActions = preload("res://src/gameplay/animal_actions.gd")
const GrazerForaging = preload("res://src/gameplay/grazer_foraging.gd")
const ScentForaging = preload("res://src/gameplay/scent_foraging.gd")
const FlightDistance = preload("res://src/gameplay/flight_distance.gd")
const Wariness = preload("res://src/gameplay/wariness.gd")
const WindScent = preload("res://src/world/wind_scent.gd")
const PredatorScent = preload("res://src/gameplay/predator_scent.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const CaptureTool = preload("res://src/gameplay/capture_tool.gd")
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
const Courtship = preload("res://src/gameplay/courtship.gd")
const MammalCourtship = preload("res://src/gameplay/mammal_courtship.gd")
const MammalGrowth = preload("res://src/gameplay/mammal_growth.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const SubmersionShader = preload("res://src/rendering/submersion_shader.gd")
const CreatureMovementGate = preload("res://src/gameplay/creature_movement_gate.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const DebuffStack = preload("res://src/gameplay/debuff_stack.gd")
const WoundModel = preload("res://src/gameplay/wound_model.gd")
const BloodTrail = preload("res://src/gameplay/blood_trail.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")

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

## Real prize/show animals are visibly judged by coat quality before anyone
## commits to keeping them (docs/concept/pets.md) -- a warm highlight on top
## of the creature's own normal art, scaling with coat_vibrancy (see
## AnimalFitness), so a player can size up a wild individual (most usefully a
## tameable one) before spending carrots on it. Applied to every creature
## with a wander_seed (see _ready) rather than a herbivore/tameable-only
## carve-out -- the same population AnimalFitness already covers elsewhere
## (MammalCourtship's mate-attractiveness, KeptAnimals' restore-by-seed), so
## there is exactly one population this tell can miss, not a second
## species/role list to keep in sync with CreatureInfo's own.
const COAT_TINT_MAX_BOOST := 0.35
static var _fitness := AnimalFitness.new()

## Deterministic, bounded coat-quality tint for `coat_vibrancy` in [0,1]:
## squared so an ordinary individual (low vibrancy) reads as visually
## unmodified while a truly vibrant one clearly stands out (see
## test_coat_tint_grows_faster_near_the_top_of_the_range_than_the_bottom) -- a
## plain linear ramp made even a common individual look faintly tinted, which
## read as an art/lighting bug rather than a deliberate tell. Warm (red/green
## boosted, blue pulled back slightly) rather than a flat brightness
## multiply, so it reads as a coat sheen rather than the whole creature
## glowing white.
static func coat_tint_for(coat_vibrancy: float) -> Color:
	var boost := COAT_TINT_MAX_BOOST * pow(clampf(coat_vibrancy, 0.0, 1.0), 2.0)
	return Color(1.0 + boost, 1.0 + boost * 0.6, 1.0 - boost * 0.3)

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

## How rattled THIS individual is, 0..1 (see Wariness, and
## docs/concept/animal_husbandry.md "The approach").
##
## Raised when the animal is made to run and while the player's scent is on it,
## decaying by absence. It widens this animal's own flight radius, so chasing
## an animal costs the player something and leaving it alone is a real verb.
var wariness := Wariness.INITIAL

## Whether the player's smell was reaching this animal at the last throttled
## check (see _step_wariness). Cached rather than recomputed per frame.
var _scent_alarm := false
var _scent_accumulator := 0.0
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
## The handler's `taming_affinity` at the moment this animal was caught (see
## Player.skill_bonus("taming_affinity") / Taming.break_free_chance), pushed
## in by restrain_to and read every struggle roll. Stored rather than a live
## reference back to the player for the same "never outlives a dangling
## holder" reason `_rope_anchor`/`follow_target` are.
var _capture_affinity := 0.0


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

## How old this creature is, in real seconds (see MammalGrowth). Mirrors
## AmbientFlyerMarker's own `age_seconds` exactly: spawned creatures (a
## chunk's initial population, or a reconciled shortfall) start already
## ADULT -- the world is not seeded with newborns -- while anything actually
## BORN in front of the player (World._resolve_courtship) starts at zero and
## has to grow up (see begin_life). Defaults to MammalGrowth.
## DEFAULT_ADULT_AGE_SECONDS rather than a species-specific threshold --
## `info` (and so this individual's species) isn't known yet at this point
## in construction, and that sentinel reads as mature for every species tier.
var age_seconds := MammalGrowth.DEFAULT_ADULT_AGE_SECONDS

## The species' own full-grown scale, captured once per action (see
## _apply_action_scale) or by begin_life() for a brand-new individual --
## what a still-growing juvenile's rendered `scale` is a fraction of (see
## MammalGrowth.size_scale_at).
var _base_scale := Vector2.ONE

## Courtship pairing (see MammalCourtship / World._pair_up_courtships): who
## this creature is currently paired with, if anyone. A plain instance id
## rather than a node reference, same reason AmbientFlyerMarker's
## `_courting_with` is -- a partner that despawns (eaten, chunk-unloaded)
## mid-courtship simply ends it rather than leaving a dangling reference.
## `_courtship_round` is bumped once per NEW pairing and salts Courtship.
## pair_seed, so a creature that courts (and fails to mate) more than once in
## its life gets a genuinely different outcome each time rather than
## replaying the same roll.
var _courting_partner_id := 0
var _courtship_elapsed := 0.0
var _courtship_round := 0
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

## Tree nut a SQUIRREL is currently caching, and where it was picked up (see
## EarthChunkManager._step_squirrel_nut_caching / SquirrelNutCaching) --
## the fruit/nut-side counterpart of carried_grass_seed above. Independent
## state for the same reason carried_grass_seed is independent of
## carried_seed_species: a squirrel is a distinct carrier from both the
## flower-epizoochory coat-rider and the mouse's grass cheek-pouch, able in
## principle to be doing any combination of the three at once. Unlike grass
## (which grows only one kind per chunk), a nut has a real species -- empty
## string means empty-handed, otherwise it names which tree to plant if the
## nut ends up cached rather than eaten.
var carried_nut_species := ""
var carried_nut_origin := Vector2.ZERO
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

	# The coat-quality tell (see COAT_TINT_MAX_BOOST doc comment above): also
	# keyed off wander_seed, so it's deterministic and reproducible from the
	# same individual across sessions, just like every other AnimalFitness
	# trait this seed already drives.
	modulate = coat_tint_for(_fitness.phenotype_for(wander_seed)["coat_vibrancy"])

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
	# Always ages, regardless of which branch below this creature takes --
	# a courting/restrained/tamed juvenile still grows up (see _step_growing).
	_step_growing(delta)
	# Runs unconditionally too, ahead of every early-return branch below (rope,
	# tame order, foraging, knockback) -- a sick animal keeps getting sicker
	# (and can still die) no matter what it's doing that frame, the same way
	# _needs.advance never pauses for those states either.
	_disease_step(delta)
	if is_queued_for_deletion():
		return  # died of disease this frame -- nothing below has a live marker to act on

	# Same "runs unconditionally, ahead of every early-return" reasoning as
	# disease above: an ignited/blighted creature keeps burning no matter
	# what it's doing this frame (see docs/concept/spell_runtime.md).
	_spell_status_step(delta)
	# Bleeding, clotting, and laying the trail (see step_wounds).
	step_wounds(delta)
	if is_queued_for_deletion():
		return  # an ignite/blight tick can kill too

	if _knockback_time_remaining > 0.0:
		var result := _knockback.step(_knockback_remaining, _knockback_time_remaining, delta)
		position += result.step
		_knockback_remaining = result.remaining
		_knockback_time_remaining = result.time_remaining
		_sync_grounded_children()
		return  # a shove overrides normal AI movement while it plays out

	if is_rooted():
		_sync_grounded_children()
		return  # frozen/rooted: no movement or AI decisions this frame, same precedence as a knockback

	if _world == null or info == null:
		_wander_step(delta)
		# Reported live, from the character-creator diorama's own ambient
		# boar (one real CreatureMarker with world left null on purpose,
		# per this fallback's own no-AI contract): "the boar doesn't have
		# walk animations". Every OTHER branch below calls this before
		# returning; this one didn't, so a world-less marker moved but its
		# texture stayed frozen on whatever idle frame it spawned with.
		# Already null-safe without a world (see _animation_step's own
		# doc comment: only its swim-detection is gated on _world != null).
		_animation_step()
		_sync_grounded_children()
		return

	_needs.advance(delta)
	# Body warmth against the LOCAL climate -- the same ambient figure the
	# player's own meter reads (see CreatureNeeds.warmth), so an animal and the
	# person beside it in the same storm agree about how cold it is. Guarded
	# because plenty of stub worlds in tests cannot answer.
	if _world.has_method("ambient_warmth"):
		_needs.regulate_temperature(_world.ambient_warmth(position), delta)
	if not _restrained:
		_struggle_fatigue = Taming.fatigue_after_rest(_struggle_fatigue, delta)
	energy = AnimalReproduction.decay(energy, delta)
	_seconds_since_birth += delta
	# Placed here, ABOVE the foraging/restraint/order early-returns below, so a
	# grazing animal still settles. Wariness decays by absence, and an animal
	# with its head down is the clearest case of nothing happening to it --
	# putting this after those returns would have left a spooked grazer
	# permanently jumpy for as long as it kept eating.
	_step_wariness(delta)
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
		#
		# The radius a PLAYER is sensed at is no longer the flat SENSE_RADIUS
		# every other threat uses -- it is this individual's own composed
		# flight distance (see _sensed_players, FlightDistance). Creature-vs-
		# creature sensing above is deliberately untouched: a wolf does not
		# care whether the deer trusts anyone.
		var sensed_players := _sensed_players(threat_radius) if fears_players() else []
		_cached_threats = sensed_players + _nearby_threat_creatures()
		_cached_caution_threats = (
			_nearby_in_group(PLAYER_GROUP, CAUTION_RADIUS) if fears_players() else []
		)
		# A predator that has the player's scent comes looking for them, from
		# well beyond what it can see (see smells_a_player_to_hunt). Predators
		# have never hunted the player at all: _nearby_prey_creatures only ever
		# returned other CREATURES, so the player was something a predator
		# bumped into rather than something it came for.
		_cached_prey = _players_stalked_by_scent() + _nearby_prey_creatures()
		_cached_blockers = _blockers_near(BLOCKER_SCAN_RADIUS)
		_cached_nearby_herbivores = _nearby_herbivore_creatures()
		_herd_disease_step()
		_carrion_disease_step()
		# Fresh senses: a creature standing because the gate found nowhere
		# to go re-evaluates now, not per frame (see _gate_standing).
		_gate_standing = false
		_cached_food_direction = _food_direction()
		_cached_water_direction = _water_direction()

	# Not throttled to the sensing interval like the group scans above: there
	# is nothing to SCAN here, just a specific known partner (or none) whose
	# live position is a single cheap instance_from_id lookup away -- reading
	# it fresh every frame is what makes the walk read as smooth rather than
	# stepping toward a stale point.
	var courting_partner := courtship_partner()
	var decision := _behavior.decide({
		"position": position,
		"temperament": _temperament_for_decision(),
		"is_predator": info.is_predator,
		"health_fraction": info.health / info.max_health,
		"hungry": _needs.is_hungry(),
		"thirsty": _needs.is_thirsty(),
		"threats": _positions_of(_cached_threats),
		"prey": _positions_of(_cached_prey),
		"food_direction": _cached_food_direction,
		"water_direction": _cached_water_direction,
		"is_courting": courting_partner != null,
		"partner_position": courting_partner.position if courting_partner != null else Vector2.ZERO,
		"is_mature": MammalGrowth.is_mature(age_seconds, info.species),
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


## ## The approach (see docs/concept/animal_husbandry.md)
##
## How close a player gets before THIS animal breaks. Composed per individual
## rather than read off one flat constant: its body size, how rattled it is,
## how much it trusts the player, and whether that player is crouching.
##
## `crouched` is asked of the player rather than assumed, so a stub player in a
## test (and the character-creator diorama's world-less marker) simply counts
## as standing.
func flight_radius(crouched: bool = false) -> float:
	var species := info.species if info != null else ""
	return FlightDistance.radius(species, wariness, trust, crouched)


## The players this animal can actually sense right now.
##
## `fallback_radius` is the Schmitt-widened radius the rest of the threat scan
## uses (FLEE_RELEASE_RADIUS while already fleeing, SENSE_RADIUS otherwise).
## While fleeing it is used AS the radius, unchanged, so the hysteresis that
## fixed the measured flee-dithering bug keeps working exactly as it did; only
## the ACQUIRE side becomes per-individual.
func _sensed_players(fallback_radius: float) -> Array:
	var widened := fallback_radius > SENSE_RADIUS
	var found: Array = []
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node == self:
			continue
		var radius := fallback_radius if widened else flight_radius(_is_crouching(node))
		if position.distance_to(node.position) <= radius:
			found.append(node)
	return found


## Whether this player node is crouching. Duck-typed like every other player
## query in this file: a stub without the method is simply standing.
static func _is_crouching(player: Node) -> bool:
	return player.has_method("is_crouching") and player.is_crouching()


## ## Wariness: what chasing an animal costs, and what leaving it alone buys
##
## Two inputs, both of them the player's doing:
##
##   Being MADE TO RUN is a sharp step up (`Wariness.after_spook`), applied on
##   the leading edge of a flee episode in _apply_decision so one long flee
##   costs one spook rather than one per frame.
##
##   The player's SCENT on the wind is a slow climb (`Wariness.after_scent`) --
##   a whiff does not make an animal bolt, it makes it jumpy. Routing the wind
##   through wariness rather than through a second flee trigger is what keeps
##   FlightDistance the single owner of "when does this animal run", and it is
##   the truer behaviour: a deer that catches your scent across a meadow does
##   not sprint, it stops trusting the meadow.
##
## Everything else is decay by ABSENCE. The input for that is nothing at all --
## the player leaves, and the animal gets over it.
func _step_wariness(delta: float) -> void:
	if not fears_players():
		wariness = Wariness.after_calm(wariness, delta)
		return
	# The scent verdict is THROTTLED on the same interval the group scans are,
	# and for the same reason: it walks the player group and does real vector
	# maths, and this runs for every creature every frame. Wariness is a ramp
	# with a multi-second half-life, so a quarter-second-stale verdict is
	# invisible. Deliberately its own accumulator rather than folded into the
	# sensing block below, because that block sits after the foraging/restraint
	# early-returns -- and an animal grazing with its head down is exactly the
	# one that should still be catching the player's scent.
	_scent_accumulator += delta
	if _scent_accumulator >= SENSE_INTERVAL:
		_scent_accumulator = 0.0
		_scent_alarm = _smells_a_player()
	if _scent_alarm:
		wariness = Wariness.after_scent(wariness, delta)
		return
	wariness = Wariness.after_calm(wariness, delta)


## Whether the player's own smell is reaching this animal right now, with the
## wind taken into account (see WindScent, Olfaction.PLAYER_MIXTURE).
##
## The world is asked for the wind rather than the weather: a stub world that
## cannot answer reports still air, which leaves the geometry alone and makes
## this exactly the still-air case every pre-existing test already assumes.
func _smells_a_player() -> bool:
	var species := info.species if info != null else ""
	if species.is_empty() or not Olfaction.has_nose(species):
		return false
	var wind_direction := Vector2.ZERO
	var wind_strength := 0.0
	if _world != null and _world.has_method("wind_direction"):
		wind_direction = _world.wind_direction()
	if _world != null and _world.has_method("wind_advection_strength"):
		wind_strength = _world.wind_advection_strength()
	var tile_size := float(maxi(_tile_size, 1))
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node == self:
			continue
		var tiles := WindScent.effective_distance_tiles(
			node.position, position, wind_direction, wind_strength, tile_size
		)
		# The Schmitt state is the alarm ITSELF, not the wariness it feeds: an
		# animal currently smelling the player keeps smelling them slightly
		# further out (MUSK_RELEASE_STRENGTH), which is what stops the verdict
		# flickering for one parked at exactly the alarm threshold. Keying it
		# off `wariness > 0.0` instead would have latched permanently, since an
		# exponential decay never quite reaches zero.
		if FlightDistance.smells_player(species, tiles, _scent_alarm):
			return true
	return false


## Whether this predator has the player's scent and is coming to look (see
## PredatorScent, docs/concept/olfaction.md's "The wind carries it").
##
## The other edge of the stalking mechanic. The wind already let the player
## approach a deer from downwind; this is what it costs them -- a wolf downwind
## of the player knows they are there from well beyond what it could see, so
## the wind is an exposure as well as an advantage.
##
## Reuses `_smells_a_player`'s exact wind plumbing rather than a second copy,
## so the two halves cannot disagree about which way the wind blows.
func smells_a_player_to_hunt() -> bool:
	if info == null or not info.is_predator:
		return false
	# A tamed predator does not stalk the person who tamed it -- the same
	# exemption fears_players makes on the prey side, for the same reason.
	if is_tame():
		return false
	if not PredatorScent.hunts_by_scent(info.species):
		return false
	return _nearest_player_scent_tiles() <= PredatorScent.HUNT_RANGE_TILES


## The wind-effective distance in tiles to the nearest player, or INF if there
## is none. Wind-effective rather than true: a player downwind is effectively
## closer, which is the whole mechanic.
func _nearest_player_scent_tiles() -> float:
	var wind_direction := Vector2.ZERO
	var wind_strength := 0.0
	if _world != null and _world.has_method("wind_direction"):
		wind_direction = _world.wind_direction()
	if _world != null and _world.has_method("wind_advection_strength"):
		wind_strength = _world.wind_advection_strength()
	var tile_size := float(maxi(_tile_size, 1))
	var nearest := INF
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node == self:
			continue
		nearest = minf(nearest, WindScent.effective_distance_tiles(
			node.position, position, wind_direction, wind_strength, tile_size
		))
	return nearest


## The players this predator is actively coming to look for, as prey. Empty
## unless it has actually caught the scent.
func _players_stalked_by_scent() -> Array:
	if not smells_a_player_to_hunt():
		return []
	var found: Array = []
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node != self:
			found.append(node)
	return found


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


## Everything about this animal a player is entitled to read, in one place.
##
## Reported live: "it's neither visible from the horses panel nor in hover or
## extra panel what the horses states are (hunger / cold / trust / thirst)".
## All four were already simulated and none was readable -- and hunger is the
## one that decides whether feeding does anything at all, since
## Taming.trust_after_feeding only counts a HUNGRY feed. A player working a
## tied horse could not see the single fact the whole loop turns on.
##
## One reporter rather than each surface reaching into private fields: the
## creature card, the hover tooltip and the rope banner all want the same
## facts, and three copies of `_needs.is_hungry()` would be three things to
## keep in step. Everything is a plain 0..1 fraction or a bool, so a caller can
## draw a bar without knowing this class.
func animal_state() -> Dictionary:
	return {
		"name": get_display_name(),
		"species": info.species if info != null else "",
		"level": info.level if info != null else 0,
		"health_fraction": (info.health / info.max_health) if info != null and info.max_health > 0.0 else 0.0,
		# EVERY fraction here reads the same way round: 1.0 is the animal being
		# fine, 0.0 is it being in trouble. CreatureNeeds stores hunger and
		# thirst as DEFICITS (1.0 = starving), which is right for the
		# simulation and a trap for a readout -- a bar drawn straight off
		# `hunger` would show full and green for a starving horse, pointing the
		# opposite way to the player's own Food bar on the same screen. Flipped
		# once here rather than in each of the three surfaces that draw it.
		"fullness": 1.0 - _needs.hunger,
		"hydration": 1.0 - _needs.thirst,
		"warmth": _needs.warmth,
		"hungry": _needs.is_hungry(),
		"thirsty": _needs.is_thirsty(),
		"cold": _needs.is_cold(),
		# How BADLY, not just whether -- AnimalActions scores feeding by
		# urgency, so a starving animal outranks a peckish one for the primary
		# slot. Deficit-shaped (1.0 = starving) on purpose: an urgency rises as
		# the animal gets worse, unlike the fullness/hydration fractions above
		# which read 1.0 = fine.
		"hunger_urgency": _needs.hunger,
		"thirst_urgency": _needs.thirst,
		"trust": trust,
		"tame": is_tame(),
		"restrained": _restrained,
		"tied": is_tied_up(),
		"sick": disease_state == DiseaseModel.State.INFECTED,
		"order": order,
		# Whether the player has a stake in this animal -- the same predicate
		# that decides what the aggregate model may cull. Readouts use it to
		# stay quiet about wildlife and detailed about your own stock.
		"invested": is_player_invested(),
	}


## What hovering this animal offers to do (see HoverTargetFinder, and
## AnimalActions for the ordering rule).
##
## CreatureMarker was in the hover group and had get_display_name(), but was
## one of only four hoverables that never implemented this -- so pointing at a
## horse named it and offered nothing, while pointing at a pebble offered
## "Pick Up (E)" and "Kick (K)".
##
## Answers for EMPTY HANDS: a marker cannot see what the player is holding, and
## the held item changes the answer (a carrot turns a tied hungry animal's
## primary action into Feed). World composes the held-item-aware version for
## the tooltip; this is the honest fallback for any caller without a player.
func get_hover_actions() -> Array:
	return AnimalActions.for_animal(animal_state(), "")


## Whether feeding this animal would actually earn any trust right now (see
## Taming.trust_after_feeding). Public because it is the question every taming
## surface asks, and the answer used to live behind a private field.
func is_hungry() -> bool:
	return _needs.is_hungry()


func is_thirsty() -> bool:
	return _needs.is_thirsty()


func is_cold() -> bool:
	return _needs.is_cold()


## Test seam: drives the need clock straight to a value, so a test can ask
## "what does a starving animal look like" without simulating the minutes it
## would really take to get there.
func set_needs_for_test(new_hunger: float, new_thirst: float, new_warmth: float = 1.0) -> void:
	_needs.hunger = clampf(new_hunger, 0.0, 1.0)
	_needs.thirst = clampf(new_thirst, 0.0, 1.0)
	_needs.warmth = clampf(new_warmth, 0.0, 1.0)


func is_tame() -> bool:
	return Taming.is_tame(trust)


## Catches this animal on whichever capture tool's other end is at `anchor`
## (see docs/concept/taming.md's "Any animal, the right tool"). Called again
## each frame by the holder to move the anchor (which is what "leading" is).
## Refused outright for anything `tool_id` is the wrong tool for -- see
## Taming.can_be_tamed, which now checks the ACTUAL tool used rather than
## just "is taming allowed at all" (a mouse offered a lasso must not be
## caught by it, even though a mouse offered a trap can be).
## `tied` distinguishes "the loose end is knotted to a tree" from "the player
## is holding it". Only a tied animal is somewhere the player deliberately
## LEFT it, which is what makes it worth keeping across a chunk unload even at
## zero trust (see KeptAnimals).
## `affinity` is the handler's Player.skill_bonus("taming_affinity") at the
## moment of the catch (0.0 for an uninvested character, byte-identical to
## the pre-affinity behaviour -- see Taming.break_free_chance), stored for
## every subsequent struggle roll in _step_restraint.
func restrain_to(
	anchor: Vector2, tied: bool = false, affinity: float = 0.0,
	tool_id: String = CaptureTool.LASSO
) -> bool:
	if info == null or not Taming.can_be_tamed(info.species, tool_id):
		return false
	if not _restrained:
		_restrained = true
		_struggle_elapsed = 0.0
	_rope_anchor = anchor
	_tied = tied
	_capture_affinity = affinity
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
	if roll < Taming.break_free_chance(condition, info.is_predator, _capture_affinity):
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
	# A newborn cannot pair off the moment it is born -- see MammalGrowth.
	# is_mature. A PRECONDITION added alongside the existing energy/health/
	# cooldown gate, not a replacement for it.
	if not MammalGrowth.is_mature(age_seconds, info.species):
		return false
	return AnimalReproduction.can_reproduce(energy, info.health / info.max_health, _seconds_since_birth)


## Called by World after this creature births an offspring: pays the energy
## cost (dropping it below the threshold) and restarts the birth cooldown, so
## it can't immediately breed again.
func on_reproduced() -> void:
	energy = AnimalReproduction.energy_after_birth(energy)
	_seconds_since_birth = 0.0


## Starts this creature at the beginning of its life rather than as an
## adult -- what separates an offspring actually BORN in front of the player
## (see World._resolve_courtship) from the population a chunk is populated
## with. Captures whatever `scale` CreatureRenderer._build_marker already
## set as this individual's own full-grown size (so a horse's newborn grows
## toward a horse's own adult size, not a shared assumption) and shrinks the
## rendered scale to a newborn's immediately -- mirrors AmbientFlyerMarker's
## set_adult_scale + begin_life pair, folded into one call since
## CreatureMarker has no separate scale-setter to call first.
func begin_life() -> void:
	_base_scale = scale
	age_seconds = 0.0
	var newborn_scale := _base_scale * MammalGrowth.size_scale_at(age_seconds, info.species)
	scale = newborn_scale
	_shadow_base_scale = newborn_scale


## Ages this creature (mirrors AmbientFlyerMarker._step_growing) -- called
## every frame regardless of which behaviour branch _process takes below, so
## a courting, restrained, or tamed juvenile still grows up (though it can
## never actually reach courting until it is mature -- see can_reproduce).
## The visible growth itself is applied lazily, in _apply_action_scale (see
## its own doc comment), which only runs once _animation_step does; this
## just advances the clock so that computation has a fresh age to read.
## Runs before this marker's own `info == null` guard elsewhere in _process
## (a bare marker still ages), so the species lookup falls back to an empty
## string -- MammalGrowth.mature_seconds_for's own generic fallback -- rather
## than assuming `info` is set.
func _step_growing(delta: float) -> void:
	var species := info.species if info != null else ""
	if age_seconds < MammalGrowth.mature_seconds_for(species):
		age_seconds += delta


## Whether this creature is currently paired for courtship (see
## MammalCourtship / World._pair_up_courtships). CreatureBehavior's decision
## tree only enters the "court" intent while this is true.
func is_courting() -> bool:
	return _courting_partner_id != 0


## This creature's current courtship partner, or null if it isn't courting
## or the partner is gone -- freeing (predation, despawn) is handled here
## rather than requiring every caller to check is_instance_valid itself, the
## same self-healing shape AmbientFlyerMarker._step_courtship uses for its
## own `_courting_with`.
func courtship_partner() -> Node:
	if _courting_partner_id == 0:
		return null
	var partner := instance_from_id(_courting_partner_id)
	if partner == null or not is_instance_valid(partner):
		end_courtship()
		return null
	return partner


## Starts (or restarts, for a creature courting again later in life) a real
## pairing with `partner`. Called on BOTH sides by World._pair_up_courtships
## so each creature independently knows who it is walking toward.
func begin_courtship(partner: Node) -> void:
	_courting_partner_id = partner.get_instance_id()
	_courtship_elapsed = 0.0
	_courtship_round += 1


## Ends the pairing, mated or not -- called once the courtship's duration is
## up (see World._resolve_courtship) or when the partner is found gone.
func end_courtship() -> void:
	_courting_partner_id = 0
	_courtship_elapsed = 0.0


## Advances this creature's own share of the pair's shared timer by `delta`
## and returns the new total. Both partners are advanced by the same amount
## every tick (see World._advance_courtships), so they stay in lockstep
## without messaging each other -- the same shape Courtship's pollinator
## dance uses for its own elapsed/leader-resolves split.
func advance_courtship(delta: float) -> float:
	_courtship_elapsed += delta
	return _courtship_elapsed


## Which pairing attempt this is, for salting Courtship.pair_seed -- see
## `_courtship_round`'s own doc comment.
func courtship_round() -> int:
	return _courtship_round


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
	# The BASE (fully-grown) scale only changes when the ACTION changes (each
	# action may come from its own differently-sized source file) -- the
	# expensive per-species/per-action lookup is skipped exactly as before
	# whenever the action hasn't changed. GROWTH (see MammalGrowth), unlike
	# the action, changes every frame while still immature, so it is always
	# re-applied on top of that cached base -- the `new_scale == scale` check
	# below is what keeps a fully-grown, action-unchanged creature just as
	# cheap as before (one multiply and one comparison, not a re-derivation).
	if action != _scaled_action:
		_scaled_action = action
		if uses_illustrated:
			# Per ACTION: an action may come from its own differently-sized
			# source file (see IllustratedAnimalSprite.marker_scale).
			_base_scale = Vector2.ONE * _illustrated.marker_scale(info.species, action)
		else:
			var species_scale: float = AnimalAnatomy.profile_for(info.species).world_scale
			_base_scale = Vector2.ONE * ArtResolution.SPRITE_SCALE * species_scale
	# A juvenile renders at its species' own normal size TIMES how grown it
	# currently is (see MammalGrowth.size_scale_at), converging to that
	# normal size once mature -- the mammal counterpart to
	# AmbientFlyerMarker._step_growing's own adult_scale * size_scale_at.
	var new_scale := _base_scale * MammalGrowth.size_scale_at(age_seconds, info.species)
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
## Soft terrain slowdown from real slope (see TerrainPassability.speed_
## multiplier and player.gd's own _terrain_speed_multiplier, which this
## mirrors) -- the same "environment scales a movement multiplier" shape the
## disease multiplier below already uses, driven by slope instead. 1.0 when
## the world doesn't offer slope data (StubWorld, or any other worldless/
## stub setup) -- the same has_method duck-typed fallback _blockers_near
## already uses for solid_obstacles_near.
func _terrain_speed_multiplier(tile: Vector2i) -> float:
	if _world == null or not _world.has_method("slope_at_global"):
		return 1.0
	return TerrainPassability.speed_multiplier(_world.slope_at_global(tile.x, tile.y))


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
	# Real slope underfoot slows a creature exactly the way it slows the
	# player (see _terrain_speed_multiplier above) -- one query for the tile
	# this creature is CURRENTLY standing on, not a scan over any area, so
	# this stays O(creatures) regardless of how many creatures are loaded.
	speed *= _terrain_speed_multiplier(_current_tile())
	# An open wound is a real performance cost long before it is fatal, which
	# is why a hunted animal is followed rather than outrun (see WoundModel).
	# Applied at the same single choke point the disease slow uses, so it
	# covers every intent rather than only fleeing.
	speed *= wound_speed_multiplier()
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
	var was_fleeing := _is_fleeing
	_is_fleeing = decision.intent == "flee"
	# The LEADING EDGE of a flee episode, not every frame of one: being made to
	# run once costs one spook, however long the run lasts (see Wariness,
	# _step_wariness). An animal you have flushed four times is warier than one
	# you startled once -- but it is the flushing that counts, not the running.
	if _is_fleeing and not was_fleeing:
		wariness = Wariness.after_spook(wariness)
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
		"court":
			_step_courtship_movement(decision.direction, delta)
		_:
			_wander_step(delta)


## Movement for the "court" intent: keep closing the distance to the partner
## (obstacle-gated the same way seek_water/seek_food are, but not threat-
## avoidant -- a courting pair is not fleeing anything) while it's still
## farther than MammalCourtship.LINGER_RADIUS_PX away, then simply stand
## once close enough rather than shoving into it (Vector2.ZERO through
## _advance is the same "stand still, not moving" no-op every other intent's
## overlap/arrival case already uses). A vanished partner (eaten, freed
## between decide() and here) just stands too -- the next sensing pass and
## next World tick both self-heal via courtship_partner()/is_courting().
func _step_courtship_movement(direction: Vector2, delta: float) -> void:
	var partner := courtship_partner()
	if partner == null:
		_advance(Vector2.ZERO, SEEK_SPEED, delta)
		return
	if MammalCourtship.should_approach(position.distance_to(partner.position)):
		_advance_gated(direction, SEEK_SPEED, delta, false)
	else:
		_advance(Vector2.ZERO, SEEK_SPEED, delta)


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


## Whether the tile a creature is about to step onto is too steep to enter at
## all (see TerrainPassability.is_passable and player.gd's own
## _terrain_blocks_movement, which this mirrors) -- a SEPARATE ask-before-you-
## step check layered on top of whatever heading obstacle/threat avoidance in
## _advance_gated below already settled on, the same way player.gd keeps its
## own terrain check independent of everything else that could refuse a
## step. `heading` is whatever _advance_gated is about to actually move
## along (a unit vector, or ZERO); the look-ahead reuses MOVEMENT_LOOKAHEAD
## rather than minting a second "roughly a tile ahead" distance -- both
## questions ("is this the tile I'm about to stand on") are the same
## question CreatureMovementGate's own obstacle check already asks at that
## same distance. Called at most ONCE per _advance_gated call (never per
## candidate direction clear_direction tries internally), so this is one
## slope query per creature per movement decision -- O(creatures), not
## O(creatures x terrain). No climbing-gear concept exists for creatures
## (player-only, see docs/progress.md's Transportation section), so this
## always checks the un-roped HARD_THRESHOLD_DEG.
func _terrain_blocks_movement(heading: Vector2) -> bool:
	if _world == null or not _world.has_method("slope_at_global") or heading.length() < 0.01:
		return false
	var look_ahead := position + heading.normalized() * MOVEMENT_LOOKAHEAD
	var tile := Vector2i(floori(look_ahead.x / _tile_size), floori(look_ahead.y / _tile_size))
	# Explicitly typed (not :=): _world is untyped/duck-typed (see setup's own
	# doc comment), so GDScript can't infer a type for its return value.
	var slope: float = _world.slope_at_global(tile.x, tile.y)
	return not TerrainPassability.is_passable(slope)


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
	var heading: Vector2
	if _cached_blockers.is_empty() and not has_threats:
		heading = desired
	else:
		var threats: Array = _positions_of(_cached_caution_threats) if avoid_threats else []
		var facing := 0.0 if _is_serpent() else facing_sign()
		heading = CreatureMovementGate.clear_direction(
			position, desired, MOVEMENT_LOOKAHEAD, _cached_blockers, threats, SENSE_RADIUS,
			_last_gated_heading, facing
		)
	# Terrain is a SEPARATE ask-before-you-step check, layered on top of
	# whatever heading obstacle/threat avoidance above already settled on --
	# see _terrain_blocks_movement's own doc comment for why this stays a
	# single slope query rather than one per candidate direction.
	if heading != Vector2.ZERO and _terrain_blocks_movement(heading):
		heading = Vector2.ZERO
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
	# _wander_radius() is a PER-CALL override (juvenile vs adult, see that
	# function's own doc comment) -- step_position itself takes no radius
	# argument, it reads the shared _wander instance's own wander_radius
	# property (see CreatureWander's "Per-instance override" doc comment),
	# so the override has to land there first.
	_wander.wander_radius = _wander_radius()
	var candidate := _wander.step_position(home, position, _elapsed_time, delta, wander_seed)
	_advance_avoided(candidate - position, CreatureWander.WANDER_SPEED, delta)


## A still-growing juvenile roams a tighter, home-anchored range than an
## adult, widening smoothly as it grows -- a real juvenile mammal stays close
## to its birth site rather than ranging as far as a full-grown adult. `home`
## on a courtship-born juvenile is already its actual birth position (see
## begin_life -- CreatureRenderer never moves it), so no separate tracking is
## needed. Scaled by MammalGrowth.size_scale_at, the same already-computed
## 0.4..1.0 growth fraction _apply_action_scale uses for the RENDERED size --
## reusing it here rather than inventing a second tunable means a newborn's
## wander range and its visible size grow in lockstep, and the range reaches
## exactly CreatureWander.WANDER_RADIUS at maturity (size_scale_at(mature) ==
## 1.0), so every existing adult's wander is completely unaffected. Can run
## with `info` still null (a bare marker's own wander step, called before
## the usual `info == null` guard elsewhere in _process) -- falls back to an
## empty species string, MammalGrowth.mature_seconds_for's own generic
## fallback, same as _step_growing.
func _wander_radius() -> float:
	var species := info.species if info != null else ""
	return CreatureWander.WANDER_RADIUS * MammalGrowth.size_scale_at(age_seconds, species)


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
	var sources: Array = _world.smells_near(position, Olfaction.MAX_RANGE_TILES)
	var target := ScentForaging.best_source(species, position, sources)
	if target.is_empty():
		return false
	_forage_target = target["position"]
	# An animal whose ordinary diet includes fruit takes what it smells AS
	# fruit, so the seed inside it still travels the way endozoochory expects
	# (see take_fruit_at, SeedEndozoochory). Everything else -- every plain
	# grazer, whose whole diet is FOOD_GRASS -- takes it as BAIT: a thing a
	# person put down, which it would never have foraged for and is crossing a
	# field for anyway. That distinction is the whole of what baiting is, and
	# without it nothing anyone put on the ground existed for a sheep.
	var forages_fruit := _forage_kinds().has(GrazerForaging.FOOD_FRUIT)
	_forage_kind = GrazerForaging.FOOD_FRUIT if forages_fruit else GrazerForaging.FOOD_BAIT
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
			# The sward it is standing on, and cropping it takes real leaf off
			# the ground (see EarthChunkManager.crop_sward_at,
			# docs/concept/ground_cover.md's "The grazing lawn is food").
			#
			# This used to read "it is standing in its food; there is nothing
			# to remove" -- the one bite in the game that could never fail. A
			# hungry animal on grassland was fed, the world lost nothing, and
			# a meadow therefore had no carrying capacity at all. Now ground
			# that has been eaten bare refuses the bite and the animal has to
			# move on, which is what makes a pasture something that can be
			# overstocked.
			got = _world.has_method("crop_sward_at") and _world.crop_sward_at(_forage_target)
		GrazerForaging.FOOD_GRASS:
			got = _world.has_method("graze_grass_at") and _world.graze_grass_at(_forage_target)
		GrazerForaging.FOOD_FRUIT:
			got = _world.has_method("take_fruit_at") and _world.take_fruit_at(_forage_target) != ""
		GrazerForaging.FOOD_SEED:
			got = _world.has_method("take_seed_at") and _world.take_seed_at(_forage_target) != ""
		GrazerForaging.FOOD_WORM:
			got = _world.has_method("take_worm_at") and _world.take_worm_at(_forage_target)
		GrazerForaging.FOOD_BAIT:
			got = _world.has_method("take_bait_at") and _world.take_bait_at(_forage_target) != ""
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


## Reduces info.health; on death, routes through the shared _die() path
## (leaves a real Carcass behind for a carcass-eligible species -- see
## docs/concept/carrion.md/LootTable -- and reports the death to the
## region's aggregate population, see EarthChunkManager.record_death_at /
## EcosystemSimulation.record_death, so a kill in front of the player does
## not vanish the moment the chunk unloads), then frees this marker.
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
	# A real blow opens a wound as well as taking health -- the slow threat
	# layered on the acute one (see WoundModel, and docs/concept/olfaction.md's
	# blood trail). Applied BEFORE the damage so a blow that kills outright
	# does not also leave a phantom wound on a corpse.
	if WoundModel.opens_a_wound(amount):
		_open_wound()
	info.health = _health.take_damage(info.health, amount)
	_update_health_bar()
	if _health.is_dead(info.health):
		_die()


# -- open wounds, and the trail they leave -----------------------------------
# See docs/concept/olfaction.md's "Blood: the trail a wounded animal leaves"
# and docs/concept/survival.md's open-wound trigger -- the SAME model from the
# animal's side, because a gash on a deer and a gash on the player are
# mechanically the same real thing.

## Open wounds, tracked in the generic DebuffStack exactly the way venom and
## spell statuses already are -- not a bespoke severity field. Empty means
## unwounded.
var active_wound_debuffs: Array = []
var _blood_trail := BloodTrail.new()


func _open_wound() -> void:
	active_wound_debuffs = _debuff_stack.apply(
		active_wound_debuffs, WoundModel.DEBUFF_ID, WoundModel.DURATION_SECONDS, WoundModel.MAX_STACKS
	)


func wound_stacks() -> int:
	return _debuff_stack.stacks_of(active_wound_debuffs, WoundModel.DEBUFF_ID)


## What this animal's wounds cost it in speed. The reason tracking a wounded
## animal is worth doing at all: the thing at the end of the trail is
## catchable.
func wound_speed_multiplier() -> float:
	return WoundModel.speed_multiplier(wound_stacks())


## Bleeds, clots, and lays the trail. Bleeding deliberately cannot finish the
## animal off by itself (it floors at a sliver of health): it is what lets you
## catch the animal, not what kills it for you -- the same "debuffs, not death"
## rule the player's own condition penalty follows.
func step_wounds(delta: float) -> void:
	var stacks := wound_stacks()
	if stacks > 0 and info != null:
		var bleed := WoundModel.damage_per_second(stacks) * delta
		info.health = maxf(info.health - bleed, WoundModel.BLEED_HEALTH_FLOOR)
		_update_health_bar()
	if _world != null and _world.has_method("drop_blood_at"):
		if _blood_trail.step(position, stacks, delta):
			_world.drop_blood_at(position)
	active_wound_debuffs = _debuff_stack.advance(active_wound_debuffs, delta)


## The `minor_heal`/`major_heal` atoms' shared target-side method (see
## docs/concept/spell_runtime.md) -- same duck-typed-across-target-types
## shape take_damage already is; Player.heal is the other half.
func heal(amount: float) -> void:
	if info == null:
		return
	info.health = minf(info.max_health, info.health + amount)


# -- spell-cast status effects: ignite/blight/freeze/root/slow/fear/calm/...
# (see docs/concept/spell_runtime.md). Mirrors Player's own DebuffStack-
# tracked shape exactly -- this class had no equivalent before (only Player
# could be poisoned/spell-debuffed at all).

var active_spell_debuffs: Array = []
var _debuff_stack := DebuffStack.new()
var _spell_status_effects := SpellStatusEffects.new()


func apply_spell_debuff(debuff_id: String, duration: float) -> void:
	active_spell_debuffs = _debuff_stack.apply(
		active_spell_debuffs, debuff_id, duration, SpellStatusEffects.MAX_STACKS
	)


func is_rooted() -> bool:
	return (
		_debuff_stack.stacks_of(active_spell_debuffs, SpellStatusEffects.FREEZE) > 0
		or _debuff_stack.stacks_of(active_spell_debuffs, SpellStatusEffects.ROOT) > 0
	)


## `fear`/`calm` don't touch creature_behavior.gd's own pure decide() at all
## -- they override the "temperament" value fed INTO it for their duration,
## additive at this one call site. An aggressive predator that would
## normally fight a nearby threat reads as non-aggressive instead (flees or
## stays passive, per CreatureBehavior's own rules), the same mechanical
## effect for both atoms today (see spell_runtime.md's honest note on this,
## the same "distinct atoms, identical mechanic for now" shape the four
## damage atoms already have).
func _temperament_for_decision() -> String:
	if info == null:
		return ""
	if (
		_debuff_stack.stacks_of(active_spell_debuffs, SpellStatusEffects.FEAR) > 0
		or _debuff_stack.stacks_of(active_spell_debuffs, SpellStatusEffects.CALM) > 0
	):
		return "calm"
	return info.temperament


## Authority-side per-frame tick: ignite/blight's real damage-over-time
## (mirrors Player._spell_status_step line for line), then advances every
## active spell debuff's remaining duration.
func _spell_status_step(delta: float) -> void:
	if info == null:
		return
	for debuff_id in [SpellStatusEffects.IGNITE, SpellStatusEffects.BLIGHT]:
		var stacks := _debuff_stack.stacks_of(active_spell_debuffs, debuff_id)
		if stacks > 0:
			take_damage(_spell_status_effects.damage_per_second(debuff_id, stacks) * delta)
	active_spell_debuffs = _debuff_stack.advance(active_spell_debuffs, delta)


func _update_health_bar() -> void:
	if info == null or _health_bar_fill == null:
		return
	_health_bar_fill.size.x = _health_bar.fill_width(info.health, info.max_health, HEALTH_BAR_WIDTH)


## Shared death path: a real Carcass (see docs/concept/carrion.md) for a
## carcass-eligible species (see LootTable), reports the death to the
## region's aggregate population (see EarthChunkManager.record_death_at /
## EcosystemSimulation.record_death -- a kill must not vanish the moment the
## chunk unloads, whether it came from combat or disease), then the marker
## frees itself. The ONE place a marker actually dies, whatever the cause --
## ordinary take_damage above, and a lethal disease death (_disease_step
## below) alike (docs/concept/disease.md "Feeds carrion": a disease-driven
## die-off must be a real source of carrion, not a silent despawn, so it has
## to go through this exact same path, not a parallel one).
func _die() -> void:
	# ONE booking, and it is the guarded one. Two sessions added this
	# independently and the merge left both calls here: every wild death was
	# counted twice, and a kept animal slipped past the exemption via the
	# unguarded call. _book_death_against_the_region is the version that skips
	# animals the player has a stake in -- carrying capacity governs WILD
	# animals, and KeptAnimals says so in its own doc comment.
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
