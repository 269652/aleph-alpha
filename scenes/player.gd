extends CharacterBody2D
class_name Player

const Keybindings = preload("res://src/gameplay/keybindings.gd")
const AnimalActions = preload("res://src/gameplay/animal_actions.gd")
const EquipmentMaterial = preload("res://src/gameplay/equipment_material.gd")
const WetnessTracker = preload("res://src/gameplay/wetness_tracker.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")
const Health = preload("res://src/gameplay/health.gd")
const MeleeAttack = preload("res://src/gameplay/melee_attack.gd")
const TileTargeting = preload("res://src/gameplay/tile_targeting.gd")
const Item = preload("res://src/gameplay/item.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const ConditionPenalty = preload("res://src/gameplay/condition_penalty.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ExperienceTrack = preload("res://src/gameplay/experience_track.gd")
const SkillTree = preload("res://src/gameplay/skill_tree.gd")
const KeystonePassive = preload("res://src/gameplay/keystone_passive.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const GenomeSkillNet = preload("res://src/gameplay/genome_skill_net.gd")
const HeroDna = preload("res://src/gameplay/hero_dna.gd")
const EcologicalLiteracy = preload("res://src/gameplay/ecological_literacy.gd")
const Equipment = preload("res://src/gameplay/equipment.gd")
const FishingSession = preload("res://src/gameplay/fishing_session.gd")
const MaterialDamage = preload("res://src/gameplay/material_damage.gd")
const Block = preload("res://src/gameplay/block.gd")
const ItemWear = preload("res://src/gameplay/item_wear.gd")
const HotbarAction = preload("res://src/gameplay/hotbar_action.gd")
const CampfireCooking = preload("res://src/gameplay/campfire_cooking.gd")
const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")
const VenomModel = preload("res://src/gameplay/venom_model.gd")
const DebuffStack = preload("res://src/gameplay/debuff_stack.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")
const Sickness = preload("res://src/gameplay/sickness.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const NpcGreeting = preload("res://src/world/npc_greeting.gd")
const Hotbar = preload("res://src/gameplay/hotbar.gd")
const FishingCast = preload("res://src/gameplay/fishing_cast.gd")
const ProceduralBobberSprite = preload("res://src/rendering/procedural_bobber_sprite.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CraftedItemRegistry = preload("res://src/gameplay/crafted_item_registry.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const DropShadow = preload("res://src/rendering/drop_shadow.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const WildCropMarker = preload("res://src/rendering/wild_crop_marker.gd")
const Carcass = preload("res://src/rendering/carcass.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const Taming = preload("res://src/gameplay/taming.gd")
const CaptureTool = preload("res://src/gameplay/capture_tool.gd")
const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const BondedCompanionMarker = preload("res://src/rendering/bonded_companion_marker.gd")
const CaptureBook = preload("res://src/gameplay/capture_book.gd")
const CaptureExecutor = preload("res://src/gameplay/capture_executor.gd")
const CaptureAtomEffects = preload("res://src/gameplay/capture_atom_effects.gd")
const BodyDimensions = preload("res://src/gameplay/body_dimensions.gd")
const FishMarker = preload("res://src/rendering/fish_marker.gd")
const CaptureItemActions = preload("res://src/gameplay/capture_item_actions.gd")
const FlyerPersonality = preload("res://src/gameplay/flyer_personality.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const WorldCoordinates = preload("res://src/world/world_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const InputLatch = preload("res://src/gameplay/input_latch.gd")
const Throwable = preload("res://src/gameplay/throwable.gd")
const ChargeMeter = preload("res://src/gameplay/charge_meter.gd")
const HeldItemThrow = preload("res://src/gameplay/held_item_throw.gd")
const ImpactResolver = preload("res://src/gameplay/impact_resolver.gd")
const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const CollapsedPassage = preload("res://src/rendering/collapsed_passage.gd")

const BASE_SPEED := 80.0
const PLAYER_SIZE := 12

## Taming reach (see docs/concept/taming.md). The throw is deliberately short:
## having to close with a wary animal first is the part that makes stalking a
## horse feel like something. Feeding is closer still -- an arm's length, since
## the animal has to take it from your hand -- and tying off needs the tree
## within reach of where you are standing.
const LASSO_RANGE := 72.0
const FEED_RANGE := 28.0
const TIE_RANGE := 40.0
const TAMING_TREAT_ID := "carrot"
## Every item id that is a capture tool (see docs/concept/taming.md's "Any
## animal, the right tool") -- what `_held_capture_tool_id` checks
## `equipped_item.id` against, generalized from the single hardcoded "lasso"
## string check this used to be.
const CAPTURE_TOOL_IDS := {
	CaptureTool.LASSO: true,
	CaptureTool.SNARE: true,
	CaptureTool.NET: true,
	CaptureTool.TRAP: true,
	CaptureTool.REINFORCED_ROPE: true,
}
## How far a bonded companion loosely trails the player, spread around them
## rather than stacking on one point. Reuses TIE_RANGE rather than inventing
## a second "how far a kept creature sits from the player" number.
const BONDED_COMPANION_TRAIL_RADIUS := TIE_RANGE
## How big one world tile should read on screen once camera-zoomed, in
## pixels -- the actual tuned/eyeballed value (CLAUDE.md: tuned constants
## must be pinned, not eyeballed comments). CAMERA_ZOOM below is DERIVED
## from this divided by TerrainRenderer.TILE_SIZE rather than a bare zoom
## number, so the framing is stated as an intent ("a tile should read this
## big") that stays correct on its own terms.
##
## The art-resolution pass (docs/concept/art_resolution.md) deliberately
## does NOT change this: it raises how many art PIXELS are painted per tile
## (TerrainRenderer.ART_TILE_SIZE), not how much WORLD a tile covers
## (TerrainRenderer.TILE_SIZE). Conflating those two -- the pass's first
## attempt bumped TILE_SIZE itself -- made every tile occupy 4x the world
## footprint, reported as "water squares are gigantic compared to the
## player".
const TARGET_TILE_SCREEN_PX := 64.0
## Applied in _ready() rather than left as a bare number in player.tscn, so
## it's a tested constant (see test_player_camera.gd) rather than an
## eyeballed scene property.
const CAMERA_ZOOM := Vector2.ONE * (TARGET_TILE_SCREEN_PX / TerrainRenderer.TILE_SIZE)
## How far (in pixels) position must change between frames for a non-authority
## proxy to consider itself "moving" for animation purposes, vs. jitter.
const PROXY_MOVEMENT_EPSILON := 0.5

## A melee swing: an AOE hit around the player (not aimed/single-target),
## with damage and knockback -- the "tactical mechanic beyond plain damage
## trading" Phase 3's definition of done asks for. Damage comes from the
## equipped weapon (UNARMED_DAMAGE if empty-handed).
const ATTACK_RANGE := 20.0
const UNARMED_DAMAGE := 5.0
const ATTACK_COOLDOWN := 0.5
const KNOCKBACK_FORCE := 60.0

## A moderate, controlled swing's contact speed -- not a blade-TIP speed
## measurement (which runs much higher), but the speed at the point of
## impact a real swing delivers, the same grounding shape as
## Kick.KICK_SPEED_MPS. Feeds real weapon mass into knockback (see
## _knockback_force_for) through the SAME momentum model
## Throwable.impact_knockback already uses for thrown items
## (docs/concept/materials.md).
const SWING_IMPACT_SPEED_MPS := 5.0
## Base per-swing damage against wood before the material model's weapon-kind
## multiplier (see MaterialDamage/_chop_step): an axe lands 3x this (15.0, the
## historical AXE_DAMAGE tuning), a sword 0.5x, bare hands 0.25x.
const BASE_CHOP_DAMAGE := 5.0
## Mining power of a stone pickaxe -- feeds OreYield's ore-count scaling (see
## _pickaxe_power / MinableOre.mine).
const PICKAXE_POWER := 1.0
## Radius (px) within which the pickup action (default E) sweeps up ground
## items -- roughly two tiles, so you grab a small pile around you at once.
const PICKUP_RADIUS := 34.0
## How long the weapon's swing animation plays, in seconds -- shorter than
## ATTACK_COOLDOWN so the blade snaps back to rest before the next swing can
## start, rather than looking like it's still mid-swing when idle.
const SWING_DURATION := 0.2
const INVENTORY_SLOTS := 12

## How close (in tiles, Chebyshev/square distance -- see
## EarthChunkManager.has_structure_near) the player must stand to a placed
## campfire/furnace to cook or smelt: "standing near the fire" range, not
## room-scale -- a few tiles so you don't have to be pixel-perfect on top of
## it, but you can't use one clear across a base either.
const HEAT_SOURCE_RADIUS_TILES := 3

## Same "standing near it" proximity range as HEAT_SOURCE_RADIUS_TILES,
## named separately for the Sägewerk collection action (see _collect_step)
## rather than repurposing a heat-source-specific constant name for an
## unrelated structure -- same real tuned value, not a second invented
## number.
const SAGEWERK_COLLECT_RADIUS_TILES := HEAT_SOURCE_RADIUS_TILES

## How much a single eaten food item relieves hunger by (see eat_food()).
const EAT_HUNGER_RELIEF := 0.4
## Thirst relief per second while standing in deep-enough water to be
## "swimming" (see current_mode) -- reuses the existing swim-state check
## rather than a separate water-source concept.
const DRINK_RATE_PER_SECOND := 0.1

## Emitted whenever the inventory or equipped weapon changes, for the HUD.
signal inventory_changed

## Exposed so the demo scene can be tweaked in the editor to test different
## swim/drown scenarios without a full inventory system yet.
@export var body_weight := 10.0
@export var max_swimmable_weight := 50.0
@export var worn_material: EquipmentMaterial

var wetness := 0.0
var current_mode := "walking"
var current_speed_multiplier := 1.0
## Real, continuous water depth in meters (maxf of ocean/river/lake --
## see _resolve_water_state), set alongside current_mode every step. Used
## to be computed and discarded the moment it was collapsed into current_
## mode's coarse walking/wading/swimming/drowning string; this is the
## channel _update_character_view feeds to CharacterView.
## set_submersion_depth so wading has a real visual signature instead of
## none at all until the exact swim threshold.
var current_water_depth := 0.0

## Aggressive/healthy predators and boars attack the player back (see
## CreatureMarker._try_attack), so take_damage() has a live caller. Reaching
## 0 health sets is_dead and freezes the player in place (see
## _authority_step) for RESPAWN_DELAY seconds, then respawns at
## respawn_position (set by World when this Player is first spawned) with
## full health -- no graveyard/corpse-recovery system yet (see
## docs/progress.md), just a straight reset.
@export var max_health := 100.0
var health := max_health

## A resource for spellcasting, deliberately separate from `SurvivalMeters.
## stamina` -- docs/concept/survival.md's "Stamina scope" section decided,
## on purpose, that stamina is traversal-only and combat stays off it (so
## the two systems don't fight over the same tension); casting a spell is
## combat. See docs/concept/spell_runtime.md. Unlike health, 0 is a valid,
## meaningful rest state (a non-caster class), so there's no floor above 0.
var max_mana := 0.0
var mana := 0.0
## Chosen so a mage can recast a cheap single-atom spell (Fire Bolt, ~3 mana
## -- see SpellBook/test_spell_book.gd) roughly every couple of seconds of
## not casting, rather than it being effectively free (instant regen) or
## requiring a long wait -- pinned by
## test_mana_regen_lets_a_mage_recast_fire_bolt_within_a_few_seconds.
const MANA_REGEN_PER_SECOND := 2.0
var is_dead := false
const DEAD_MODULATE := Color(0.35, 0.35, 0.35, 1.0)

## Where this player respawns -- set by World right after its initial spawn
## placement, so death always returns to known-good (dry land) ground.
var respawn_position := Vector2.ZERO
const RESPAWN_DELAY := 3.0
var _respawn_accumulator := 0.0

## How often actively swimming spawns a water-ripple disturbance (see
## EarthChunkManager.record_water_disturbance) -- once per stroke, not every
## frame; the ring itself takes a couple of seconds to fade, so anything
## faster would just stack redundant rings at the same spot.
const WATER_RIPPLE_INTERVAL := 0.4
var _water_ripple_accumulator := 0.0

var inventory := Inventory.new(INVENTORY_SLOTS)
## The single item currently in hand. It alone decides attack damage (if it's
## a weapon), tree-felling speed (fast for an axe, slow for a sword, slowest
## bare-handed), and mining power (only a pickaxe mines ore). Swapped by
## equip_item (from the hotbar or inventory). Null == bare hands.
var equipped_item: Item
## The placeable structure (campfire/furnace) armed for the next build-input
## press (see activate_hotbar_slot/activate_item_id dispatching HotbarAction.
## PLACE to _arm_placeable, and _build_step). Independent of equipped_item --
## arming a structure doesn't change what's drawn in hand. Persists until a
## different placeable is armed (mirrors equipped_item's own persist-until-
## switched behavior); it does NOT auto-clear when the stack runs out, see
## _build_step's doc comment. Null == nothing armed, i.e. build does today's
## plain bare-earth terraforming.
var _selected_placeable_item: Item
var survival := SurvivalMeters.new()
## Active timed buffs from eating rare/legendary fish (see
## FoodConsumption.FISH_BUFFS) -- category-slotted, ticked down in
## _food_buff_step. Empty means no active buff in any category.
var active_food_buffs: Array = []
## Active venom stacks from a venomous snake's bite (see VenomModel,
## CreatureMarker._try_attack) -- DebuffStack-shaped, ticked down and
## dealing damage in _venom_step. Empty means not currently poisoned.
var active_venom_debuffs: Array = []
## Player-side disease spillover (docs/concept/disease.md "Player
## spillover"): routed through the existing Sickness pure model (see
## src/gameplay/sickness.gd) EXACTLY the way survival.md's own sickness
## already works -- deliberately NOT a new VenomModel/DebuffStack-style
## module. "" sickness_id means not currently sick. Ticked in
## _sickness_step; set by apply_disease_bite (an infected predator's
## zoonotic bite, or careless butchering of a contaminated carcass).
var sickness_severity := 0.0
var sickness_id := ""
var sickness_diagnosed := false
var wallet := Wallet.new()
## How many number-key hotbar slots exist. World derives its HUD row's slot
## count from this (see World.HOTBAR_SLOT_COUNT), so the two can't drift.
const HOTBAR_SLOT_COUNT := 5
## How many bonded companions (see the taming Kinship path) a player may keep
## at once. Derived from the hotbar's own slot count -- a real existing
## anchor for "how many small extra things can the player keep readily at
## hand" -- rather than an invented number. Explicitly a placeholder pending
## real playtesting (same honesty convention Taming.PREDATOR_BREAK_FREE_
## MULTIPLIER's own doc comment uses for a derived-but-unplaytested figure).
const BONDED_COMPANION_CAP := HOTBAR_SLOT_COUNT
## Which item id sits on each hotbar key (see Hotbar). Explicitly assignable
## by dragging an item onto a slot, with empty slots auto-filled from the
## inventory -- so an item buried past the first few stacks can still be put
## on a key, which the old mirror-the-first-5-stacks hotbar made impossible.
var hotbar := Hotbar.new(HOTBAR_SLOT_COUNT)
var experience := ExperienceTrack.new()
## Kept although allocation now runs on skill_web below: SkillTree remains the
## OWNER of the twelve original nodes' stat/bonus/cost numbers, which the web
## reads out of it rather than restating (see SkillWeb's wedge table). Nothing
## on Player calls it directly any more.
var skill_tree := SkillTree.new()
var keystones := KeystonePassive.new()
## The PoE-style passive WEB (docs/concept/skills.md) -- the graph allocation
## actually runs on. Per character, not shared: apply_dna_seed grafts this
## character's own generated genome net into THIS instance.
var skill_web := SkillWeb.new()
## The DNA roll this character came out of (see HeroDna). `dna_resonance` is the
## per-archetype 0..1 affinity that sets the web's exchange rate; `dna_seed` also
## resolves DNA-flavoured node variants. Empty/0 means "no genome rolled", which
## the web reads as neutral -- a dedicated-server or test spawn is not penalised
## for not having been through the character creator.
var dna_seed := 0
var dna_resonance: Dictionary = {}
## This character's unique grafted cluster (see GenomeSkillNet). Derived from
## dna_seed, so only the seed is persisted.
var genome_net: Dictionary = {}
## XP-award arithmetic for non-combat "ecological literacy" sources (see
## harvest_fruit_from_tree/sell_food_to_village, docs/concept/progression.md).
var _ecological_literacy := EcologicalLiteracy.new()
## Worn armor (see Equipment): reduces incoming damage by its total armor.
var equipment := Equipment.new()
## node_id/keystone_id -> true for every allocated skill (see SkillTree /
## concept/progression.md). Skill bonuses fold into derived stats.
var allocated_nodes: Dictionary = {}
var unlocked_keystones: Dictionary = {}
## node_id -> the points that node ACTUALLY cost when it was taken. Refunds pay
## back this, not a recomputed price: free respec (concept/classes.md) has to be
## exactly free, and a recomputed cost would quietly differ if anything about
## the character's exchange rate ever moved between taking and refunding.
var _skill_points_paid: Dictionary = {}
## Skill-tree attack bonus, kept as a cached sum applied in _perform_attack.
var _skill_attack_bonus := 0.0
## Points a keystone costs to unlock (on top of its node-count gate).
const KEYSTONE_POINT_COST := 2
## Chosen class name (see ClassArchetype) and the attack bonus its stat lens
## grants -- applied by apply_class at character creation.
var character_class := "warrior"
var class_attack_bonus := 0.0
## The authored look from the character creator (see HeroAppearance), kept
## around (not just applied-and-forgotten) so a save can restore the same
## face/hair/outfit instead of re-rolling one from the peer id -- see
## to_save_dict/apply_save_dict and docs/concept/persistence.md.
var appearance: Dictionary = {}
## Health gained per level (see ExperienceTrack / concept/progression.md).
const HEALTH_PER_LEVEL := 8.0
## XP awarded per level of a defeated creature.
const XP_PER_KILL := 6
## A hit always lands at least this much even against heavy armor -- armor
## mitigates, it doesn't make you invulnerable.
const MIN_ARMORED_DAMAGE := 1.0
var _crafting_recipe_book := CraftingRecipeBook.new()
var _fishing := FishingSession.new()
## Taming (see docs/concept/taming.md): the animal currently on the end of
## this player's lasso, and the point the rope's loose end is tied to (a tree)
## if it has been. A tied animal is held by the anchor rather than by the
## player, which is what lets them walk away.
var _lassoed: Node = null
var _tie_anchor = null  # Vector2 once tied, null while led by hand
## The tamed animal currently being ridden (see docs/concept/taming.md).
## Riding moves the player at the mount's pace and carries the animal along
## with them, rather than swapping which node the camera follows -- the rider
## stays the thing the player controls, which keeps every other system
## (inventory, combat, survival) working unchanged while mounted.
var _mount: Node = null
## Derives a mounted animal's own speed from its individual fitness (see
## current_speed/Taming.mounted_speed_for) -- one shared instance since
## AnimalFitness holds no per-call state, matching MammalCourtship's own
## `_fitness` static instance.
var _fitness := AnimalFitness.new()
var _last_mount_input := false
var _pending_mount_pressed := false
var _last_lasso_input := false
var _pending_lasso_pressed := false
var lasso_message := ""
## A net's catch attempt resolves in one frame (see _attempt_net_catch), so
## its result -- "Bonded with the sparrow." / "Caught! Net is full." /
## "Missed!" -- has to OUTLIVE the same-frame call to _update_lasso_message
## that would otherwise immediately overwrite it back to "Net ready...". Same
## result-message-plus-timer shape _fishing_result_message/
## _fishing_result_timer already use for exactly this reason.
var _capture_result_message := ""
var _capture_result_timer := 0.0
## Bonded companions (see docs/concept/taming.md's "A bond, not an order:
## the Kinship path" and pets.md's "Birds, butterflies, bees: decorative"):
## a netted flyer kept as a real companion once `menagerie` is unlocked,
## rather than a one-off curiosity item. Persisted as plain {species} dicts
## on the player -- deliberately NOT a KeptAnimals-scale subsystem, which is
## explicitly out of scope for this pass.
var bonded_companions: Array[Dictionary] = []
## Live BondedCompanionMarker nodes mirroring bonded_companions 1:1, rebuilt
## from it after a load. Never itself persisted -- position/wander_seed are
## runtime-only, the same split _lassoed/_tie_anchor keep from `trust`.
var _bonded_markers: Array = []

## The capture DSL (docs/concept/capture_dsl.md): pure modules, instantiated
## once and reused across every catch attempt, the same shape _spell_book/
## _spell_executor already use for magic.
var _capture_book := CaptureBook.new()
var _capture_executor := CaptureExecutor.new()
var _capture_atom_effects := CaptureAtomEffects.new()
## Salts the hash-derived catch roll so repeated attempts against the SAME
## still-alive flyer don't collide on the identical outcome forever (a bare
## flyer.wander_seed roll would make a first miss permanently unwinnable) --
## the same role _struggle_count plays for CreatureMarker's own hash roll.
var _capture_attempt_count := 0

var _last_fish_input := false
var _pending_fish_pressed := false
var _fishing_cast_count := 0
var _fishing_result_message := ""
var _fishing_result_timer := 0.0
## The current fishing prompt/result, read by the HUD ("" == nothing to show).
var fishing_message := ""
## How long a caught/missed message lingers on the HUD.
const FISH_MESSAGE_DURATION := 2.5
## How long a net's catch result shows (see _capture_result_message).
## Reuses FISH_MESSAGE_DURATION rather than inventing a second "how long a
## result banner shows" number -- both are "a one-shot catch result banner".
const CAPTURE_RESULT_MESSAGE_DURATION := FISH_MESSAGE_DURATION
## Fish granted per catch, scaled by the rolled rarity (see FishingMinigame).
const FISH_REWARD_BY_RARITY := {"common": 1, "uncommon": 1, "rare": 2, "legendary": 3}
## Which catalog item a catch's rarity becomes -- rare/legendary get their own
## buff-granting item (see FoodConsumption.FISH_BUFFS); common/uncommon stay
## the plain "fish" everyone already knows.
const FISH_ITEM_ID_BY_RARITY := {"rare": "rare_fish", "legendary": "legendary_fish"}
## How far a real, visible FishMarker (see FishRenderer) can be from the
## player and still be the one that "was" caught -- generous enough to cover
## a pond fish a few tiles out while standing at the shore.
const FISH_CATCH_RADIUS := 64.0

## -- Fishing visuals: a real cast, a bobber, and nearby fish reacting --
## Previously casting was invisible (no rod-throw motion, no landing point
## shown, no reaction from nearby fish, no signal when a bite starts) --
## reported as "no animation of the rod being thrown into water and also
## doesn't attract near fish and also no animation when fish bites".
## Ground-contact shadow (see DropShadow) -- every creature already gets one,
## silhouette-shaped and stretched by the real sun's elevation
## (CreatureMarker._sync_grounded_children); reported directly that the
## player was the one thing in the world standing on nothing: "the player has
## no silhouette shadow which should stretch with sun's elevation". A plain
## flattened oval rather than a silhouette (DropShadow.make_silhouette_shadow
## needs ONE flat texture to flip upside down -- CharacterView is a composite
## rig of several parts, body/head/arms/legs, with no single texture to hand
## it), the same shape trees/stones/villages already use
## (TreeRenderer/StoneRenderer/VillageRenderer's own `_drop_shadow`). A plain
## child, not top_level like a creature's: unlike CreatureMarker, Player's own
## node never rotates or scales, so it has none of the reasons a creature's
## shadow needs manual position/rotation syncing every frame -- ordinary
## parent-child transform inheritance is already correct.
var _shadow: Sprite2D
var _fishing_cast := FishingCast.new()
var _bobber: Sprite2D
## Where the line landed for the current cast -- fixed at cast time, not
## re-derived from a possibly-changed facing while the line is out.
var _bobber_target := Vector2.ZERO
## How far around the bobber fish start steering toward it (see
## EarthChunkManager.set_attraction_point).
const ATTRACTION_RADIUS := 48.0
## The bobber's dip while a fish is biting -- the visible "something's
## pulling on the line" cue, on top of the HUD text prompt.
const BITE_BOB_AMPLITUDE_PX := 2.5
const BITE_BOB_SPEED := 14.0

## -- Shopping at a merchant villager (see VillageRenderer, Shop) --
## Phase 1 simplification: press the trade key near any merchant NPC to buy
## one item, cycling through Shop.CATALOG so repeated presses don't just buy
## the same cheapest thing forever -- no dedicated shop UI yet (that, and
## selling the player's own goods, are open follow-ups; see
## docs/progress.md's NPC section).
var _shop := Shop.new()
var _last_trade_input := false
var _last_sell_input := false
var _last_slot_input := [false, false]
var _pending_trade_pressed := false
var _pending_sell_pressed := false
var _trade_attempt_count := 0
var _trade_result_message := ""
var _trade_result_timer := 0.0
## The current shopping prompt/result, read by the HUD ("" == nothing to show).
var trade_message := ""
const TRADE_MESSAGE_DURATION := 2.5
## How close a merchant villager must be to trade with.
const TRADE_RADIUS := 48.0
var _item_catalog := ItemCatalog.new()

# -- casting a spell (see docs/concept/spell_runtime.md) ---------------------
# Simpler than trade/fishing's own result-message pattern on purpose: cast_
# spell() sets `cast_message` directly (no separate _cast_result_message
# indirection), since it's the action itself, not a per-frame poll -- only
# the auto-clear-after-a-few-seconds decay needs a per-frame tick, and that
# tick deliberately never reads Input at all (kept separate from _cast_step,
# so it stays testable without a real registered InputMap action).

const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const SpellAtomEffects = preload("res://src/gameplay/spell_atom_effects.gd")
const SpellTargeting = preload("res://src/gameplay/spell_targeting.gd")

var _spell_book := SpellBook.new()
var _spell_executor := SpellExecutor.new()
var _spell_atom_effects := SpellAtomEffects.new()
var _spell_targeting := SpellTargeting.new()

## The current cast result banner ("" == nothing to show), read by the HUD --
## same shape as trade_message/fishing_message.
var cast_message := ""
var _cast_message_timer := 0.0
const CAST_MESSAGE_DURATION := 2.5

## Structures for the emergent, content-addressed items this player is carrying
## (see docs/concept/item_identity.md). Handed to _item_catalog so the ONE place
## that decides whether a saved item survives a load -- apply_save_dict's
## `if _item_catalog.has(entry.id)` below -- can answer for a crafted id at all.
## Without it every crafted item is silently dropped on load, which is the bug
## this exists to close.
var crafted_items := CraftedItemRegistry.new()

## -- Talking to any villager (see NpcGreeting, EarthChunkManager.
## nearest_npc_near) -- a minimal stand-in for the real Live Dialogue System
## (docs/concept/npc.md's "Minimal talk interaction"): press the talk key
## near any villager to hear one deterministic, personality/need-flavored
## greeting line. No branching, no memory, no quest hooks -- see the concept
## doc for why that's an honest placeholder rather than a cut-down feature.
var _npc_greeting := NpcGreeting.new()
var _last_talk_input := false
var _pending_talk_pressed := false
var _talk_result_message := ""
var _talk_result_timer := 0.0
## The current talk prompt/result, read by the HUD ("" == nothing to show).
var talk_message := ""
const TALK_MESSAGE_DURATION := 3.0
## How close a villager must be to talk to -- same reach as trading.
const TALK_RADIUS := 48.0

var _chunk_manager: EarthChunkManager
var _tile_size: int
var _wetness_tracker := WetnessTracker.new()
var _water_movement_model := WaterMovementModel.new()
var _biome_classifier := BiomeClassifier.new()
var _world_coordinates := WorldCoordinates.new()
var _health := Health.new()
var _melee_attack := MeleeAttack.new()
var _throwable := Throwable.new()
var _impact_resolver := ImpactResolver.new()
var _stone_renderer := StoneRenderer.new()

## The held-item concept (see docs/concept/stone.md): distinct from both
## inventory and Equipment's worn "weapon" slot -- a small object carried
## loose in hand, picked up from and thrown back into the world rather than
## stacked or equipped. -1.0 means empty-handed; a real value is the held
## stone's diameter_cm (its mass, for the throw's momentum, is derived from
## THAT the same way every other stone's mass is -- see StoneSize.mass_kg_for).
var _hand_stone_diameter_cm := -1.0

## The held-item concept, generalized beyond stones (reported live: "pick up
## should put it in the hand first instead of the inventory" -- see
## docs/concept/wild_crops.md's "a real physical entity, not just an
## inventory grant"). null means nothing generic is held; a real ItemStack
## is whatever's currently in hand. Mutually exclusive with
## _hand_stone_diameter_cm -- only one thing occupies the hand at a time
## (see is_holding_anything).
var _hand_item_stack = null

## How long the pickup input has been continuously held THIS charge (reset
## on a fresh press while already holding something -- see _pickup_step).
## Fed to ChargeMeter.fraction_at every frame while charging.
var _hand_charge_elapsed := 0.0

## Whether the CURRENT press-and-hold is a genuine charge cycle rather than
## the initial press that grabbed the stone into hand -- distinguishes "the
## pickup press's own release" (nothing happens, still holding) from "a
## later press-and-hold's release" (throws). Without this, releasing the
## very same E press that just picked the stone up would immediately throw
## it again.
var _charging := false
var _material_damage := MaterialDamage.new()
var _block := Block.new()
var _item_wear := ItemWear.new()
var _hotbar_action := HotbarAction.new()
var _campfire_cooking := CampfireCooking.new()
var _item_sprite_generator := ProceduralItemSprite.new()
var _tile_targeting := TileTargeting.new()
var _attack_cooldown_remaining := 0.0
var _last_attack_input_state := false
var _last_cast_input_state := false
var _last_build_input_state := false
var _last_destroy_input_state := false
var _last_pickup_input_state := false
var _last_kick_input_state := false
var _last_stash_input_state := false
var _last_plant_input_state := false

## The rising-edge ("tap") actions: one discrete thing per press, so losing
## the press loses the whole action. These are the ones latched on the input
## EVENT (see _unhandled_input / InputLatch), because a tap shorter than one
## rendered frame is never visible to a poll of Input.is_action_pressed at
## all -- reported live at 6-8 FPS, a 140ms tap silently swallowed.
##
## Deliberately NOT in here: block, pickup, fish, lasso and mount. Those are
## read as a held LEVEL -- guard up, the pickup charge meter, the cast and
## reel, the rope -- and latching a level would turn a hold into one tap.
const MOMENTARY_ACTIONS := [
	"attack", "build", "destroy", "kick", "stash", "talk", "trade", "cast", "sell",
	"primary_action", "secondary_action", "plant"
]

## Rising edges seen by the input event but not yet acted on by the physics
## step (see _unhandled_input and _rising_edge). Local-input side only: the
## authority's view of a REMOTE client's actions still arrives as the
## replicated _pending_*_pressed levels below.
var _input_latch := InputLatch.new()

## Authority-side: last input direction received from the owning client (or
## read directly from Input, in the no-networking singleplayer fallback).
var _pending_input_direction := Vector2.ZERO
var _pending_attack_pressed := false
var _pending_cast_pressed := false
var _pending_block_pressed := false
var _pending_build_pressed := false
var _pending_destroy_pressed := false
var _pending_pickup_pressed := false
var _pending_kick_pressed := false
var _pending_stash_pressed := false
var _pending_plant_pressed := false
## Non-authority proxy side: for inferring facing/animation from replicated
## position deltas, since only position itself is replicated.
var _last_position := Vector2.ZERO
var _last_facing_direction := Vector2.DOWN

@onready var _character_view: CharacterView = $CharacterView
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _camera: Camera2D = $Camera2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_last_position = position
	_camera.zoom = CAMERA_ZOOM
	# So an item crafted DURING this session resolves too, not only one restored
	# from a save (apply_save_dict re-attaches whatever it loads).
	_item_catalog.use_crafted_registry(crafted_items)
	# So creature AI (CreatureMarker) can sense the player as a threat/target.
	add_to_group("player")
	_setup_replication()

	if _is_local_player_instance():
		_bind_wasd_movement()

	if worn_material == null:
		worn_material = EquipmentMaterial.new()
		worn_material.weight = 2.0
		worn_material.water_weight = 8.0
		worn_material.absorption_rate = 0.15
		worn_material.dry_rate = 0.05

	var shape := RectangleShape2D.new()
	shape.size = Vector2(PLAYER_SIZE, PLAYER_SIZE)
	_collision_shape.shape = shape

	_build_rope_line()

	# The fishing bobber (see _fishing_step) -- hidden until a line is cast.
	_bobber = Sprite2D.new()
	_bobber.texture = ProceduralBobberSprite.new().generate_texture()
	# Oversized art scaled back to its world size (see
	# docs/concept/art_resolution.md).
	_bobber.scale = Vector2.ONE * ArtResolution.SPRITE_SCALE
	_bobber.visible = false
	_bobber.top_level = true  # world position, independent of the player's own transform
	add_child(_bobber)

	# Shadow width comes from PLAYER_SIZE -- the player's own real collision
	# footprint -- rather than an eyeballed pixel count, the same "derive it,
	# don't invent it" discipline the rest of this project holds itself to.
	# Foot offset 0: record_water_disturbance(position)/_spawn_thrown_item's
	# own "the player's own feet" already treat plain `position` as the
	# ground-contact point, so the shadow needs no offset to match it.
	_shadow = DropShadow.new().make_shadow(PLAYER_SIZE, 0.0)
	add_child(_shadow)

	# Keep the hotbar reconciled with what's actually carried (see
	# sync_hotbar) from one place, rather than at every inventory mutation.
	inventory_changed.connect(sync_hotbar)

	# No starting grant here any more -- a NEW game's kit is now the
	# player's own choice (see grant_starter_items/docs/concept/
	# starting_kit.md), called explicitly by World AFTER this node is in
	# the tree (so inventory_changed above is already wired). A LOADED
	# game's inventory comes from apply_save_dict instead, same as before.
	# (The butterfly-net/glass-bottle capture-DSL discoverability that
	# briefly lived in this unconditional grant is still covered: both are
	# real StarterKit.POOL members now, so a player picks them on purpose
	# instead of receiving them regardless of choice.)


## Server-authoritative movement: this node's authority is always the server
## (peer 1, the default -- never reassigned to the connecting client), so a
## client's own avatar is still just a non-authority proxy locally. Only
## `position` is replicated; everything else visual is inferred locally (see
## _proxy_step) so no extra network traffic is needed for it.
func _setup_replication() -> void:
	var sync := MultiplayerSynchronizer.new()
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.property_set_replication_mode(NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	add_child(sync)


func _is_local_player_instance() -> bool:
	return not multiplayer.has_multiplayer_peer() or name.to_int() == multiplayer.get_unique_id()


## Whether this player should read the keyboard directly (rather than from a
## client's replicated RPC input). True in single-player and for a listen
## server's own avatar; false on a dedicated server simulating a remote
## client's avatar. NOTE: `multiplayer.has_multiplayer_peer()` is true even in
## single-player, so we key off local-instance identity, not peer presence --
## the earlier `not has_multiplayer_peer()` check silently disabled all
## keyboard input in single-player.
## Also false while DevConsole holds keyboard focus: movement/attack/build/
## destroy all poll Input.is_action_pressed/get_vector directly, which (unlike
## Godot's Control focus system) isn't suppressed just because a LineEdit has
## focus -- typing "d" into the console would otherwise also walk the player
## east.
func _controlled_locally() -> bool:
	return _is_local_player_instance() and is_multiplayer_authority() and not ConsoleFocus.is_open


## Momentary actions latch on the input EVENT, not on a poll of the level.
##
## Godot delivers accumulated input once per rendered frame. At 6-8 FPS the
## gap between two flushes is 125-165ms, so a tap shorter than that has its
## press AND its release delivered in the same flush: every physics tick that
## polls Input.is_action_pressed sees false, and the press is not delayed, it
## is ERASED. Reported live during a playtest: a 140ms tap silently
## swallowed. Making the game faster narrows that window but never closes it,
## which is why this is an input bug in its own right and not a symptom of
## the frame rate.
##
## The EVENTS still arrive, whatever the frame rate. So the rising edge is
## recorded here and consumed by the physics step (see _rising_edge), which
## makes the poll rate irrelevant.
##
## _unhandled_input rather than _input on purpose: an event a focused Control
## has already used -- typing into the dev console, driving a menu -- never
## reaches here at all, which is the behaviour the polled path could only
## approximate with the ConsoleFocus flag (checked below as well, since the
## polled half still needs it).
##
## Gated on _is_local_player_instance, not _controlled_locally: a non-
## authority client's own avatar reads the keyboard too (it forwards the
## result to the server, see _physics_process), and it needs the same latch
## or the tap is erased one hop earlier instead.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player_instance() or ConsoleFocus.is_open:
		return
	for action in MOMENTARY_ACTIONS:
		# has_action guard: there is no static [input] section in
		# project.godot (World._apply_keybindings registers the map at
		# runtime), so an isolated Player may legitimately be running before
		# every action exists.
		if InputMap.has_action(action) and event.is_action_pressed(action):
			_input_latch.press(action)


## True on the rising edge of a momentary action, from EITHER source: a press
## the input event latched, or the polled level going false->true.
##
## Both halves are kept deliberately. The latch is the only thing that sees a
## tap shorter than one rendered frame (see _unhandled_input). The poll is
## still what fires for a key genuinely held down across a tick, what fires
## when the event was consumed elsewhere before reaching _unhandled_input,
## and what the authority uses for a REMOTE client, whose actions arrive as
## the replicated _pending_*_pressed level rather than as local events.
##
## The two cannot double-fire: a real press latches once and the latch is
## cleared by the consume here, while the level half only fires on the tick
## the level itself changes.
##
## The consume is UNCONDITIONAL, and only acting on it is gated on
## _controlled_locally. A latch that is looked at but not cleared banks the
## press indefinitely -- and "remembered forever" is a failure mode the
## polled read never had. Concretely: press T, the dev console takes focus
## before this tick, the press is not acted on (correctly), and then thirty
## seconds later the console closes and the player greets an NPC out of
## nowhere. Taking it and discarding it means a press the world never got to
## act on is DROPPED, which is what letting go of focus should mean.
## (On the authority simulating a REMOTE player this consume is a no-op:
## _unhandled_input only latches for the local instance, so that node's latch
## is always empty and its actions arrive as _pending_*_pressed instead.)
func _rising_edge(action: String, pressed_now: bool, pressed_last_tick: bool) -> bool:
	var latched := _input_latch.consume(action)
	return (latched and _controlled_locally()) or (pressed_now and not pressed_last_tick)


## What a non-authority client reports to the server for a momentary action
## this tick (see _physics_process's _submit_* rpcs): the polled level OR a
## press the event latch caught. Without the latch half, a tap that never
## shows up in the level is never sent at all, so the server's own
## rising-edge detector cannot see it either -- the same erased tap, one hop
## further away.
##
## Console focus is checked here for the same reason _controlled_locally
## checks it on the authority side: this poll reads Input directly, which
## Godot's Control focus system does not suppress, so a client typing "b"
## into the dev console was otherwise forwarding a build to the server on
## every keystroke. Like _rising_edge, the latch is still consumed first --
## a press the console interrupted is dropped, never banked for later.
func _local_momentary_input(action: String) -> bool:
	var latched := _input_latch.consume(action)
	if ConsoleFocus.is_open:
		return false
	return latched or Input.is_action_pressed(action)


## Registers WASD movement actions at runtime rather than hand-editing
## project.godot's input map (a hand-typed InputEventKey resource literal
## there is an easy way to silently corrupt the whole project file).
func _bind_wasd_movement() -> void:
	_bind_key_action("move_left", KEY_A)
	_bind_key_action("move_right", KEY_D)
	_bind_key_action("move_up", KEY_W)
	_bind_key_action("move_down", KEY_S)
	_bind_key_action("attack", KEY_SPACE)
	_bind_key_action("block", KEY_SHIFT)
	_bind_key_action("pickup", KEY_E)
	_bind_key_action("fish", KEY_F)
	_bind_key_action("lasso", KEY_R)
	_bind_key_action("mount", KEY_V)
	_bind_key_action("trade", KEY_T)
	_bind_key_action("talk", KEY_G)
	_bind_key_action("build", KEY_B)
	_bind_key_action("destroy", KEY_Q)
	_bind_key_action("plant", KEY_P)


func _bind_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if not InputMap.action_get_events(action_name).is_empty():
		return  # already bound (e.g. a second Player instance in the same run)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)


## Must be called before the first _physics_process, to give this player
## access to the streamed world it's walking (or, for a non-authority proxy,
## rendering) on.
func setup(chunk_manager: EarthChunkManager, tile_size: int) -> void:
	_chunk_manager = chunk_manager
	_tile_size = tile_size


## No-op once already dead: freezes health at 0 and, since there's no
## respawn system yet (a separate, larger, not-yet-scoped feature -- see
## docs/progress.md), leaves the player in a visibly-dead but otherwise
## inert state (see _authority_step's early-out) rather than continuing to
## process hits against a corpse.
func take_damage(amount: float) -> void:
	if is_dead:
		return
	if is_blocking():
		if amount > 0.0:
			_wear_equipped_item()  # a real hit was actually absorbed, see docs/concept/item_durability.md
		amount = _block.blocked_damage(amount, _held_kind())
	# The `shield` spell atom (see docs/concept/spell_runtime.md): a flat
	# absorb pool consumed before armor, on top of whatever block already
	# stopped -- unlike armor's floor below, a shield CAN reduce a hit to
	# exactly zero (that's the point of spending mana on one).
	if _shield_absorb_remaining > 0.0 and amount > 0.0:
		var absorbed := minf(_shield_absorb_remaining, amount)
		_shield_absorb_remaining -= absorbed
		amount -= absorbed
	# Worn armor soaks a flat chunk of any real hit (see Equipment), but never
	# reduces a hit to nothing -- at least MIN_ARMORED_DAMAGE always lands.
	if amount > 0.0:
		amount = maxf(MIN_ARMORED_DAMAGE, amount - equipment.total_armor())
	health = _health.take_damage(health, amount)
	if _health.is_dead(health):
		is_dead = true
		modulate = DEAD_MODULATE


## Spends `amount` mana, all-or-nothing -- mirrors Wallet.spend's own "never
## mutated on failed spends" contract exactly, so a spell that can't afford
## its cost changes nothing rather than driving mana negative.
func spend_mana(amount: float) -> bool:
	if amount > mana:
		return false
	mana -= amount
	return true


## Passive regen, ticked every physics frame from _authority_step with the
## real delta -- exposed (not private-only-by-convention) the same way
## _venom_step and every other per-tick Player helper already is, so a test
## can drive it directly with a synthetic delta instead of waiting real time.
func _regen_mana(delta: float) -> void:
	mana = clampf(mana + MANA_REGEN_PER_SECOND * delta, 0.0, max_mana)


## Full reset back to respawn_position after RESPAWN_DELAY seconds dead (see
## _authority_step) -- no inventory/item loss, no corpse to recover, just a
## clean restart, consistent with this project's honest "no death-stakes
## system yet" scope.
func _respawn() -> void:
	is_dead = false
	health = max_health
	modulate = Color.WHITE
	_respawn_accumulator = 0.0
	position = respawn_position
	# Nothing pressed while dead should replay on the first live tick: the
	# simulation steps that would have consumed those presses never ran (see
	# _authority_step's early-out), so the latch would otherwise be holding
	# them. The polled half has the same property for free -- it only ever
	# reads the CURRENT level.
	_input_latch.clear()


func is_set_up() -> bool:
	return _chunk_manager != null


## Applies a class archetype's stat lens at character creation (see
## ClassArchetype / concept/progression.md): a max-health offset (bumping the
## bar) and an attack-damage bonus. A starting bias, not a lock.
## `appearance` is the look authored in the character creator (see MainMenu /
## HeroAppearance). Empty (the default) rolls one from the player's stable
## node name -- the multiplayer peer id -- as a stand-in dna seed, which is
## what non-interactive spawns (dedicated server, --connect) and tests get.
func apply_class(class_name_value: String, stats: Dictionary, chosen_appearance: Dictionary = {}) -> void:
	character_class = class_name_value
	max_health = maxf(20.0, 100.0 + float(stats.get("max_health", 0.0)))
	health = max_health
	max_mana = maxf(0.0, float(stats.get("max_mana", 0.0)))
	mana = max_mana
	class_attack_bonus = float(stats.get("attack_damage", 0.0))
	var look := chosen_appearance
	if look.is_empty():
		look = HeroAppearance.new().appearance_for(class_name_value, name.hash())
	appearance = look
	if _character_view != null:
		_character_view.apply_appearance(look)
	_grant_class_start_node()


## Your class's own start node on the web comes free, the way Path of Exile
## hands you the one you begin on: paying a level-up point for "you are a mage"
## would be a tax on existing, and without it a level-1 character owns nothing
## and so can path nowhere.
##
## Called only from apply_class, which has just RESET max_health to its class
## base -- so the bonus is applied unconditionally (it is part of the lens that
## reset was rebuilding) while the allocation itself stays idempotent. A start
## node from a previously chosen class is deliberately left allocated: owning
## another wedge's start is a legal, pathable state, not a leftover.
func _grant_class_start_node() -> void:
	var start := skill_web.start_node_for(character_class)
	if start == "":
		return
	allocated_nodes[start] = true
	_skill_points_paid[start] = 0
	_apply_web_node(start)


## Snapshots exactly the state docs/concept/persistence.md defines as worth
## remembering across a restart -- see that doc for the full field-by-field
## rationale of what's included/excluded. Plain-Variant-only (Vector2/String/
## int/float/Dictionary/Array), so PlayerSave can store_var it as-is; PlayerSave
## itself is pure I/O with no knowledge of what these keys mean.
func to_save_dict() -> Dictionary:
	var inventory_data := []
	for stack in inventory.stacks():
		inventory_data.append({"id": stack.item.id, "count": stack.count})

	var equipment_data := {}
	for slot in Equipment.SLOTS:
		var worn = equipment.equipped_in(slot)
		if worn != null:
			equipment_data[slot] = worn.id

	var hotbar_data := []
	for i in range(hotbar.slot_count):
		hotbar_data.append(hotbar.item_id_at(i))

	return {
		"position": position,
		"respawn_position": respawn_position,
		"character_class": character_class,
		"appearance": appearance,
		"health": health,
		"max_health": max_health,
		"class_attack_bonus": class_attack_bonus,
		"skill_attack_bonus": _skill_attack_bonus,
		"wallet_balance": wallet.balance,
		"experience_total_xp": experience.total_xp,
		"experience_level": experience.level,
		"experience_unspent_points": experience.unspent_points,
		"allocated_nodes": allocated_nodes.duplicate(),
		"unlocked_keystones": unlocked_keystones.duplicate(),
		# Only the SEED, never the generated net: the net is derived from it, so
		# storing both would be two copies of one fact that could disagree.
		"dna_seed": dna_seed,
		"skill_points_paid": _skill_points_paid.duplicate(),
		# Real foraging knowledge earned through direct field experience (see
		# docs/concept/mushrooms.md's "Identification") -- must not evaporate
		# on reload, the same as any other permanent progression fact.
		"mushrooms_eaten": mushrooms_eaten,
		"inventory": inventory_data,
		"equipment": equipment_data,
		# Alongside the inventory rather than inside it: an inventory entry is
		# {id, count}, so a structure blob inlined there would be written once
		# per stack and could come back as two different objects for one item.
		# id -> structure is normalized, and the entry's id is the foreign key.
		"crafted_items": crafted_items.to_dicts(),
		"hotbar": hotbar_data,
		# Bonded companions (docs/concept/taming.md's Kinship path): plain
		# {species} dicts, not the live BondedCompanionMarker nodes -- see
		# apply_save_dict, which respawns a marker per entry on load.
		"bonded_companions": bonded_companions.duplicate(true),
	}


## Restores state saved by to_save_dict onto this (already-_ready, already-
## setup) player, overwriting whatever apply_class/_ready's starter grants
## put there. Deliberately NOT part of apply_class -- apply_class always
## fully heals (health = max_health), correct for a brand new character but
## wrong for a loaded one, so callers must run this AFTER apply_class/_ready
## rather than folding it in (see World's load-game spawn path).
func apply_save_dict(data: Dictionary) -> void:
	position = data.get("position", position)
	respawn_position = data.get("respawn_position", respawn_position)
	character_class = data.get("character_class", character_class)
	appearance = data.get("appearance", appearance)
	health = data.get("health", health)
	max_health = data.get("max_health", max_health)
	class_attack_bonus = data.get("class_attack_bonus", class_attack_bonus)
	_skill_attack_bonus = data.get("skill_attack_bonus", _skill_attack_bonus)
	wallet.balance = data.get("wallet_balance", wallet.balance)
	experience.total_xp = data.get("experience_total_xp", experience.total_xp)
	experience.level = data.get("experience_level", experience.level)
	experience.unspent_points = data.get("experience_unspent_points", experience.unspent_points)
	allocated_nodes = (data.get("allocated_nodes", allocated_nodes) as Dictionary).duplicate()
	unlocked_keystones = (data.get("unlocked_keystones", unlocked_keystones) as Dictionary).duplicate()
	_skill_points_paid = (data.get("skill_points_paid", _skill_points_paid) as Dictionary).duplicate()
	mushrooms_eaten = data.get("mushrooms_eaten", mushrooms_eaten)
	# Rebuilds the genome net from the seed BEFORE anything reads the web, so a
	# reloaded character's own unique nodes are grafted again rather than
	# silently missing from a save that still lists them as allocated. A save
	# written before DNA was persisted has no seed and simply stays neutral.
	if int(data.get("dna_seed", 0)) != 0:
		apply_dna_seed(int(data["dna_seed"]))
	# A keystone unlocked before keystones lived on the web was only ever
	# recorded in unlocked_keystones; the web needs it in allocated_nodes too or
	# a reloaded build has a hole in the middle of its own path. Guarded on the
	# web actually knowing the id -- a save must never be able to inject a node
	# the graph has no place for.
	for keystone_id in unlocked_keystones:
		if unlocked_keystones[keystone_id] and skill_web.has(keystone_id):
			allocated_nodes[keystone_id] = true

	# BEFORE the inventory/equipment loops below, which is the whole point: both
	# gate on `_item_catalog.has(...)` and silently skip anything it does not
	# know, so the catalog has to be able to answer for this save's crafted ids
	# before it is asked. A save written before crafted items existed has no
	# such key and loads to an empty registry, exactly as it did.
	crafted_items = CraftedItemRegistry.from_dicts(data.get("crafted_items", {}))
	_item_catalog.use_crafted_registry(crafted_items)

	inventory = Inventory.new(inventory.slot_count)
	for entry in data.get("inventory", []):
		if _item_catalog.has(entry.id):
			inventory.add(_item_catalog.make(entry.id), entry.count)

	equipment = Equipment.new()
	equipped_item = null
	for slot in data.get("equipment", {}):
		var item_id: String = data["equipment"][slot]
		if not _item_catalog.has(item_id):
			continue
		var item := _item_catalog.make(item_id)
		if slot == "weapon":
			equip_item(item)
		else:
			equipment.equip(item)

	var hotbar_data: Array = data.get("hotbar", [])
	for i in range(hotbar_data.size()):
		hotbar.assign(i, hotbar_data[i])

	# Bonded companions (docs/concept/taming.md's Kinship path): re-spawn one
	# live BondedCompanionMarker per saved entry. Any markers from BEFORE
	# this load (there should be none on a freshly-spawned player, but this
	# guards a re-applied save the same way the equipment/inventory resets
	# above do) are cleared first so a load never doubles them up.
	for marker in _bonded_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_bonded_markers.clear()
	bonded_companions.assign(data.get("bonded_companions", []))
	for entry in bonded_companions:
		_spawn_bonded_marker(entry)

	inventory_changed.emit()


## Awards XP (see ExperienceTrack); each level gained bumps max health and heals
## to full (a durable level-up payoff). Returns the number of levels gained.
func gain_experience(amount: int) -> int:
	var levels := experience.add_xp(amount)
	if levels > 0:
		max_health += HEALTH_PER_LEVEL * levels
		health = max_health
	return levels


## What `node_id` costs THIS character: the web's base price at this genome's
## resonance exchange rate (see SkillWeb.point_cost / concept/skills.md).
func skill_point_cost(node_id: String) -> int:
	return skill_web.point_cost(node_id, dna_resonance)


## Total allocated bonus for `stat_name` at this character's exchange rate, with
## DNA-flavoured nodes resolved. The single reader for every stat the web grants
## but Player does not cache (meat_yield, carpentry_level, ...) -- always in sync
## with allocated_nodes, no second accumulator to drift.
func skill_bonus(stat_name: String) -> float:
	return skill_web.total_bonus(stat_name, allocated_nodes, dna_resonance, dna_seed)


## Takes a node on the passive web: it must be REACHABLE (your class's own start
## node, or next to something you already own -- concept/skills.md's pathing
## rule) and affordable at this genome's price. Returns true on success.
func allocate_skill(node_id: String) -> bool:
	if not skill_web.can_allocate(node_id, allocated_nodes, experience.unspent_points,
			character_class, dna_resonance):
		return false
	var cost := skill_point_cost(node_id)
	if not experience.spend_points(cost):
		return false
	allocated_nodes = skill_web.allocate(node_id, allocated_nodes)
	_skill_points_paid[node_id] = cost
	_apply_web_node(node_id)
	return true


## Keystones are ordinary web nodes with an extra floor: KeystonePassive's own
## required_node_count, kept as a second, legible statement of "a keystone is the
## end of a real investment" on top of the path you had to walk to reach it.
## Also recorded in `unlocked_keystones`, which persistence and the land_sense
## HUD readout both still read.
func unlock_keystone(keystone_id: String) -> bool:
	if unlocked_keystones.get(keystone_id, false):
		return false
	if not keystones.can_unlock(keystone_id, allocated_nodes.size()):
		return false
	if not allocate_skill(keystone_id):
		return false
	unlocked_keystones[keystone_id] = true
	return true


## Free respec (concept/classes.md): hands back exactly what the node cost and
## removes its bonus. Refused when it would ORPHAN the rest of the build -- you
## cannot keep a keystone while refunding the road you walked to reach it -- and
## for the class start node, which is not something you bought.
func refund_skill(node_id: String) -> bool:
	if not allocated_nodes.get(node_id, false):
		return false
	if node_id == skill_web.start_node_for(character_class):
		return false
	if not skill_web.can_refund(node_id, allocated_nodes, character_class):
		return false
	_apply_web_node(node_id, -1.0)
	allocated_nodes = skill_web.refund(node_id, allocated_nodes)
	unlocked_keystones.erase(node_id)
	experience.unspent_points += int(_skill_points_paid.get(node_id, skill_point_cost(node_id)))
	_skill_points_paid.erase(node_id)
	return true


## Applies (sign +1) or removes (sign -1) one web node's live stat effect, with
## its DNA-flavoured variant resolved and this genome's gain multiplier applied.
func _apply_web_node(node_id: String, sign_multiplier: float = 1.0) -> void:
	var variant := skill_web.flavored_variant(node_id, dna_seed)
	_apply_skill_stat(String(variant["stat_name"]),
		skill_web.effective_bonus(node_id, dna_resonance) * sign_multiplier)


## Rolls this character's genome from `seed_value` (see HeroDna), adopts the
## resonance it rolled as the web's exchange rate, and grafts the unique skill
## net that genome generates (see GenomeSkillNet / concept/skills.md). Only the
## SEED is persisted -- everything here is derived from it, so a reload rebuilds
## the identical net. Idempotent.
func apply_dna_seed(seed_value: int) -> void:
	dna_seed = seed_value
	var genome := HeroDna.new().roll(seed_value)
	dna_resonance = genome["resonance"]
	genome_net = GenomeSkillNet.new().generate(genome)
	skill_web.graft(genome_net)


## Applies a skill/keystone stat bonus to the live character. max_health also
## heals the gained amount; attack_damage accrues into the swing bonus. Other
## stats (stamina_regen) are recorded via the allocation but not yet fed back
## into their meters (a known gap noted in concept/progression.md).
func _apply_skill_stat(stat_name: String, amount: float) -> void:
	if stat_name == "max_health":
		max_health += amount
		health += amount
	elif stat_name == "attack_damage":
		_skill_attack_bonus += amount


## Activates hotbar slot `index` (0-based) against whatever item id is
## assigned to it (see Hotbar) -- weapons/tools get equipped, food/potions get
## used, raw materials do nothing (see HotbarAction). Returns true if
## something happened; false for an empty slot or an item no longer held.
## Called from World on a number-key press or a hotbar click.
func activate_hotbar_slot(index: int) -> bool:
	var item_id := hotbar.item_id_at(index)
	if item_id == "":
		return false
	return activate_item_id(item_id)


## Puts `item_id` on hotbar slot `index` -- what dropping an inventory item
## onto a hotbar slot does (see InventoryWindow/World's drag-and-drop).
func assign_hotbar_slot(index: int, item_id: String) -> void:
	hotbar.assign(index, item_id)


## Reconciles the hotbar against what's actually held: drops slots for items
## no longer carried, then auto-fills empty slots from the inventory (never
## overwriting an explicit assignment). Called whenever the inventory changes.
func sync_hotbar() -> void:
	var held_ids: Array = []
	for stack in inventory.stacks():
		held_ids.append(stack.item.id)
	hotbar.prune_missing(held_ids)
	hotbar.auto_fill(held_ids)


## Activates the held item with this id (see HotbarAction) -- used by the
## inventory window's click-to-use. Returns true if something happened.
func activate_item_id(item_id: String) -> bool:
	for stack in inventory.stacks():
		if stack.item.id == item_id:
			match _hotbar_action.action_for(stack.item.kind):
				HotbarAction.EQUIP:
					if stack.item.kind == "armor":
						return equip_armor(stack.item)
					return equip_item(stack.item)
				HotbarAction.USE:
					return _use_food(stack.item.id)
				HotbarAction.PLACE:
					return _arm_placeable(stack.item)
				_:
					return false
	return false


## Arms `item` (a "placeable" kind -- campfire/furnace) so the next
## build-input press places it into the world instead of doing plain
## bare-earth terraforming (see _build_step). Always succeeds for a placeable
## item -- HotbarAction.action_for already gated the caller to only reach here
## for kind "placeable".
func _arm_placeable(item) -> bool:
	_selected_placeable_item = item
	return true


## Equips an armor piece from the inventory into its slot (see Equipment):
## removes it from the inventory, and returns any displaced piece to the
## inventory. Returns true on success.
func equip_armor(item) -> bool:
	if not item.is_equippable():
		return false
	inventory.remove(item.id, 1)
	var displaced = equipment.equip(item)
	if displaced != null:
		inventory.add(displaced, 1)
	# Real worn-armor visuals (see docs/concept/item_illustrations.md) --
	# previously this method was purely numeric (Equipment.total_armor()),
	# with no call into _character_view at all, so nothing ever appeared on
	# the rig no matter what was worn.
	_character_view.equip_armor_slot(
		item.equip_slot_name(), _item_sprite_generator.generate_texture(item.sprite_id)
	)
	inventory_changed.emit()
	return true


## Removes the armor worn in `slot` back into the inventory (see the inventory
## paperdoll). Returns true if something was unequipped.
func unequip_slot(slot: String) -> bool:
	var item = equipment.unequip(slot)
	if item == null:
		return false
	inventory.add(item, 1)
	_character_view.unequip_slot(slot)
	inventory_changed.emit()
	return true


## Using a food item: if it's a raw item that can be cooked and the player is
## standing near a placed campfire (their heat source), cook it instead of
## eating it raw (see CampfireCooking) -- otherwise just eat it. So clicking
## raw meat next to a built campfire turns it into cooked meat.
func _use_food(item_id: String) -> bool:
	if cook(item_id):
		return true
	return eat_food(item_id)


## Cooks one unit of a raw food item into its cooked form (see CampfireCooking)
## if the player is near a placed campfire. Returns false (no-op) if the item
## can't be cooked or there's no campfire nearby.
func cook(item_id: String) -> bool:
	if not _campfire_cooking.can_cook(item_id, _has_campfire()):
		return false
	var cooked := _campfire_cooking.cooked_output(item_id)
	if cooked == "" or not _item_catalog.has(cooked):
		return false
	if inventory.remove(item_id, 1) <= 0:
		return false
	inventory.add(_item_catalog.make(cooked), 1)
	return true


## True while a placed campfire (see EarthChunkManager.has_structure_near) is
## within HEAT_SOURCE_RADIUS_TILES of the player's current tile -- a real
## world-proximity check, not an inventory count: carrying an unplaced
## campfire in your pack no longer counts.
func _has_campfire() -> bool:
	return _has_structure_near_player("campfire")


## A heat source for smelting/cooking: a placed campfire or the sturdier
## placed furnace (see concept/smelting.md), within HEAT_SOURCE_RADIUS_TILES
## of the player.
func _has_heat_source() -> bool:
	return _has_structure_near_player("campfire") or _has_structure_near_player("furnace")


## How much faster stamina regenerates each second while a "sustenance"
## category buff (rare fish -- see FoodConsumption.FISH_BUFFS) is active, on
## top of SurvivalMeters.advance's own passive regen.
const STAMINA_BUFF_REGEN_PER_SECOND := 0.1
## Melee damage multiplier while a "combat" category buff (legendary fish) is
## active.
const DAMAGE_BOOST_MULTIPLIER := 1.3


## Authority-only: ticks down active_food_buffs and applies whatever ongoing
## effect the currently-active buffs grant (currently: extra stamina regen
## while a "sustenance" buff is up). The "combat" damage-boost buff instead
## reads live at attack time -- see _damage_buff_multiplier.
func _food_buff_step(delta: float) -> void:
	active_food_buffs = FoodConsumption.advance_food_buffs(active_food_buffs, delta)
	var sustenance := FoodConsumption.buff_in_category(active_food_buffs, "sustenance")
	if sustenance.buff == "stamina_regen":
		survival.rest(STAMINA_BUFF_REGEN_PER_SECOND * delta)


var _debuff_stack := DebuffStack.new()
var _venom_model := VenomModel.new()


## Called by a venomous snake's bite (see CreatureMarker._try_attack):
## refreshes the venom debuff's duration and adds a stack (capped at
## VenomModel.MAX_STACKS) -- repeated bites hurt more, not just longer.
func apply_venom() -> void:
	active_venom_debuffs = _debuff_stack.apply(
		active_venom_debuffs, VenomModel.DEBUFF_ID, VenomModel.DURATION_SECONDS, VenomModel.MAX_STACKS
	)


## Authority-only: deals venom's real damage-over-time (see
## VenomModel.damage_per_second) for however many stacks are active, then
## ticks the debuff's remaining duration down (expiring it once it runs out).
func _venom_step(delta: float) -> void:
	var stacks := _debuff_stack.stacks_of(active_venom_debuffs, VenomModel.DEBUFF_ID)
	if stacks > 0:
		take_damage(_venom_model.damage_per_second(stacks) * delta)
	active_venom_debuffs = _debuff_stack.advance(active_venom_debuffs, delta)


# -- wild mushrooms: real poisoning, per-species severity, and
# identification learned by real experience (see docs/concept/mushrooms.md's
# "Eating one" and "Identification") -- mirrors venom's own DebuffStack
# shape, plus a permanent, persisted encounter counter venom needed no
# equivalent of.

var mushrooms_eaten := 0
var active_mushroom_toxin_debuffs: Array = []

var _mushroom_toxin := MushroomToxin.new()
## Which species is currently poisoning the player -- read by
## _mushroom_toxin_step to look up the right severity. Named simplification
## (see docs/concept/mushrooms.md): eating a second toxic species while
## still poisoned from a first overwrites this, so the whole active stack
## ticks at whichever species was eaten last, not a per-bite blend.
var _mushroom_toxin_species := ""


## Called from eat_food whenever ANY mushroom (edible or toxic) is eaten --
## every real encounter counts toward identification (see
## knows_mushrooms), and a toxic species additionally applies a real
## poisoning debuff.
func _eat_mushroom(species_id: String) -> void:
	mushrooms_eaten += 1
	if MushroomSpecies.is_toxic(species_id):
		apply_mushroom_toxin(species_id)


## Refreshes the mushroom-toxin debuff's duration and adds a stack (capped
## at MushroomToxin.MAX_STACKS), mirroring apply_venom exactly.
func apply_mushroom_toxin(species_id: String) -> void:
	_mushroom_toxin_species = species_id
	active_mushroom_toxin_debuffs = _debuff_stack.apply(
		active_mushroom_toxin_debuffs, MushroomToxin.DEBUFF_ID,
		MushroomToxin.DURATION_SECONDS, MushroomToxin.MAX_STACKS
	)


## Authority-only: mirrors _venom_step exactly, reading MushroomToxin's real
## PER-SPECIES damage-over-time (see MushroomToxin.severity_for) for
## however many stacks are active.
func _mushroom_toxin_step(delta: float) -> void:
	var stacks := _debuff_stack.stacks_of(active_mushroom_toxin_debuffs, MushroomToxin.DEBUFF_ID)
	if stacks > 0:
		take_damage(_mushroom_toxin.damage_per_second(stacks, _mushroom_toxin_species) * delta)
	active_mushroom_toxin_debuffs = _debuff_stack.advance(active_mushroom_toxin_debuffs, delta)


## Whether the player has learned to identify mushrooms on sight (see
## MushroomMarker's identification gate) -- real foraging knowledge earned
## through direct field experience (mushrooms_eaten), not a purchased skill
## point (see docs/concept/mushrooms.md's "Identification" for why this
## isn't a skill_web.gd node).
func knows_mushrooms() -> bool:
	return mushrooms_eaten >= MushroomSpecies.MUSHROOMS_TO_LEARN_IDENTIFICATION


# -- spell-cast status effects: ignite/blight/freeze/root/slow (see
# docs/concept/spell_runtime.md) -- the same DebuffStack-tracked, once-per-
# authority-frame shape as venom above, generalized via SpellStatusEffects
# instead of one bespoke model file per atom. --------------------------------

var active_spell_debuffs: Array = []
var _spell_status_effects := SpellStatusEffects.new()


## Applies a timed spell-status debuff to the player -- called by whatever
## resolves a spell atom's effect against this player as its target. Mirrors
## apply_venom's own refresh-duration-and-stack shape exactly.
func apply_spell_debuff(debuff_id: String, duration: float) -> void:
	active_spell_debuffs = _debuff_stack.apply(
		active_spell_debuffs, debuff_id, duration, SpellStatusEffects.MAX_STACKS
	)


## True while frozen or rooted (the `freeze`/`root` atoms) -- both mean
## "can't move for a duration" and are mechanically identical, staying
## distinct atoms only for their cost/tier/visual (see spell_runtime.md).
func is_rooted() -> bool:
	return (
		_debuff_stack.stacks_of(active_spell_debuffs, SpellStatusEffects.FREEZE) > 0
		or _debuff_stack.stacks_of(active_spell_debuffs, SpellStatusEffects.ROOT) > 0
	)


## The movement-speed multiplier active spell debuffs impose right now (1.0
## = no effect) -- one more term in _authority_step's existing
## current_speed_multiplier product chain, same shape as
## ConditionPenalty.speed_multiplier(survival.fitness) already is.
func _spell_speed_multiplier() -> float:
	if _debuff_stack.stacks_of(active_spell_debuffs, SpellStatusEffects.SLOW) > 0:
		return SpellStatusEffects.SLOW_SPEED_MULTIPLIER
	return 1.0


## Authority-only: deals ignite/blight's real damage-over-time (mirrors
## _venom_step line for line), then advances every active spell debuff's
## remaining duration, expiring whichever run out.
func _spell_status_step(delta: float) -> void:
	for debuff_id in [SpellStatusEffects.IGNITE, SpellStatusEffects.BLIGHT]:
		var stacks := _debuff_stack.stacks_of(active_spell_debuffs, debuff_id)
		if stacks > 0:
			take_damage(_spell_status_effects.damage_per_second(debuff_id, stacks) * delta)
	active_spell_debuffs = _debuff_stack.advance(active_spell_debuffs, delta)


# -- the `shield` atom: a simple bespoke absorb pool, not DebuffStack -- it
# needs to carry a depleting AMOUNT, not just a stack count. Mirrors Block's
# own "bespoke field, not a generic system" precedent. -----------------------

var _shield_absorb_remaining := 0.0
var _shield_time_remaining := 0.0


## Grants (or refreshes -- a re-cast replaces rather than adds) a temporary
## damage-absorbing shield.
func apply_shield(absorb_amount: float, duration: float) -> void:
	_shield_absorb_remaining = absorb_amount
	_shield_time_remaining = duration


func _shield_step(delta: float) -> void:
	_shield_time_remaining = maxf(0.0, _shield_time_remaining - delta)
	if _shield_time_remaining <= 0.0:
		_shield_absorb_remaining = 0.0


## The `minor_heal`/`major_heal` atoms' shared target-side method -- the same
## duck-typed-across-both-target-types shape take_damage already is
## (CreatureMarker gets its own heal() to match). A dead player has no
## health to restore -- healing does not resurrect (see take_damage's own
## symmetric is_dead guard).
func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)


## The `push`/`pull` spell atoms (see docs/concept/spell_runtime.md) --
## nothing in this game has ever knocked the player back before (only
## CreatureMarker had a sink). Mirrors CreatureMarker.apply_knockback/
## Knockback.step's own shape exactly: a short ease-out shove converted to a
## velocity so move_and_slide still resolves collision during it, rather
## than a raw position jump.
const Knockback = preload("res://src/gameplay/knockback.gd")
const KNOCKBACK_DURATION := 0.15
var _knockback := Knockback.new()
var _knockback_remaining := Vector2.ZERO
var _knockback_time_remaining := 0.0


func apply_knockback(force: Vector2) -> void:
	_knockback_remaining = force
	_knockback_time_remaining = KNOCKBACK_DURATION


## The velocity _authority_step should actually use this frame: a spell
## knockback overrides normal input-driven movement while it plays out (the
## same "shove wins over AI/input" precedence CreatureMarker.apply_knockback
## already establishes), converted from a raw displacement to a velocity so
## move_and_slide still resolves collision against walls during it.
## `fallback_velocity` (the normal input-driven one) passes through
## unchanged once no knockback is active. Factored out from _authority_step
## so it's directly testable, the same boundary _venom_step/
## _spell_status_step already keep.
func _knockback_velocity(fallback_velocity: Vector2, delta: float) -> Vector2:
	if _knockback_time_remaining <= 0.0:
		return fallback_velocity
	var result := _knockback.step(_knockback_remaining, _knockback_time_remaining, delta)
	_knockback_remaining = result.remaining
	_knockback_time_remaining = result.time_remaining
	return result.step / delta if delta > 0.0 else Vector2.ZERO


# -- disease spillover: Sickness, not a new debuff module (see
# docs/concept/disease.md "Player spillover") --------------------------------

## A well-fed, healthy player resists infection somewhat better -- real-
## world-grounded (malnourishment measurably weakens immune response), a
## modest term off current health fraction rather than a new stat.
const DISEASE_RESISTANCE_FROM_HEALTH := 0.3
## Sickness while untreated is "not fatal outright, a real tax" (see the
## doc): drains stamina proportional to severity rather than dealing direct
## damage -- the same lever _food_buff_step's "sustenance" buff already
## pulls, just in reverse.
const SICKNESS_STAMINA_DRAIN_PER_SECOND := 0.03

var _sickness := Sickness.new()
## Counts this player's disease exposure rolls, so each one draws a
## different, still-deterministic seed -- mirrors CreatureMarker's own
## _disease_roll_count.
var _disease_roll_count := 0


## Called by an infected predator's bite (see CreatureMarker._try_attack /
## _try_transmit_predator_disease -- the doc's zoonotic spillover path) or a
## careless butchering of a contaminated carcass (see _butcher_step -- the
## anthrax spillover path). Rolls real infection odds through
## Sickness.infection_chance/attempt_infect, the SAME mechanism survival.md's
## own sickness already uses -- not a bespoke debuff. No-op while already
## sick: a second exposure mid-recovery isn't modeled (mirrors Sickness's
## own single-instance scope).
func apply_disease_bite(new_disease_id: String, exposure_level: float = 1.0) -> void:
	if sickness_id != "":
		return
	_disease_roll_count += 1
	var chance := _sickness.infection_chance(exposure_level, _disease_resistance())
	var seed_value := hash("%d_%s_player_disease" % [_disease_roll_count, new_disease_id])
	if _sickness.attempt_infect(chance, seed_value):
		sickness_id = new_disease_id
		sickness_severity = 0.01  # just infected -- _sickness_step ramps it from here
		sickness_diagnosed = false


func _disease_resistance() -> float:
	return clampf(health / max_health, 0.0, 1.0) * DISEASE_RESISTANCE_FROM_HEALTH


## Authority-only: ticks sickness_severity via Sickness.progress (always
## untreated for now -- no cure/treatment tool exists yet, see disease.md's
## own explicitly-deferred "management tools" scope) and taxes stamina while
## sick, a real ongoing cost rather than a fatal one.
func _sickness_step(delta: float) -> void:
	if sickness_id == "":
		return
	sickness_severity = _sickness.progress(sickness_severity, delta, false)
	survival.spend_stamina(SICKNESS_STAMINA_DRAIN_PER_SECOND * sickness_severity * delta)


## Melee damage multiplier from an active "combat" category food buff (see
## FoodConsumption.FISH_BUFFS's legendary_fish entry) -- 1.0 (no change) when
## none is active.
func _damage_buff_multiplier() -> float:
	var combat := FoodConsumption.buff_in_category(active_food_buffs, "combat")
	return DAMAGE_BOOST_MULTIPLIER if combat.buff == "damage_boost" else 1.0


func _has_structure_near_player(structure_id: String) -> bool:
	if _chunk_manager == null:
		return false
	var tile := current_tile()
	return _chunk_manager.has_structure_near(tile.x, tile.y, structure_id, HEAT_SOURCE_RADIUS_TILES)


## Generic requires_structure gate (see docs/concept/production_chains.md,
## and CraftingRecipeBook.recipe_requires_structure) -- true if recipe_id
## has no structure gate at all (the common case). "heat_source" is the one
## abstract category value: EITHER a campfire OR a furnace nearby satisfies
## it, exactly as _has_heat_source already accepted for every smelt before
## this generalization (see concept/smelting.md). Every other value names
## one real, specific structure id, checked directly via
## _has_structure_near_player -- e.g. the Sägewerk's own log_to_balken/
## log_to_planke recipes require "sagewerk" nearby, no separate mechanism.
func _meets_requires_structure(recipe_id: String) -> bool:
	var structure_id := _crafting_recipe_book.recipe_requires_structure(recipe_id)
	if structure_id == "":
		return true
	if structure_id == "heat_source":
		return _has_heat_source()
	return _has_structure_near_player(structure_id)


## Generic required_skill gate (see docs/concept/production_chains.md, and
## CraftingRecipeBook.recipe_required_skill) -- true if recipe_id has no
## skill gate at all (the common case). Reads the live allocated-skill total
## via SkillTree.total_bonus, the exact same pattern
## Player._chop_step's own CARPENTRY_LEVEL_FOR_SAWING check already uses --
## this is what makes a recipe's required_skill field actually refuse the
## craft in practice, not just exist as unread data.
func _meets_required_skill(recipe_id: String) -> bool:
	var requirement := _crafting_recipe_book.recipe_required_skill(recipe_id)
	if requirement.is_empty():
		return true
	var have_level := skill_bonus(String(requirement["stat_name"]))
	return have_level >= requirement["level"]


## Equips a weapon or tool as the single held item (drawn in hand, and the
## sole driver of attack/chop/mine effectiveness). The item stays in the
## inventory -- equipping just makes it active and updates the drawn sprite,
## so switching from sword to axe visibly puts the axe in hand and makes trees
## fell fast. Also updates the paperdoll's "weapon" slot (see equipment,
## Item.equip_slot_name) so the inventory window's Character screen actually
## shows what's equipped instead of staying permanently empty for
## weapons/tools (only equip_armor used to touch `equipment`). Non-equippable
## kinds (materials/food) are a no-op.
func equip_item(item) -> bool:
	if item.kind != "weapon" and item.kind != "tool":
		return false
	equipped_item = item
	equipment.equip(item)
	_character_view.equip_weapon(_item_sprite_generator.generate_texture(item.sprite_id))
	inventory_changed.emit()
	return true


## Populates a brand-new character's inventory from the player's chosen
## starter items (see docs/concept/starting_kit.md), replacing what used to
## be a hardcoded, identical-for-everyone grant in _ready(). Called by World
## AFTER this node is already in the tree (see World._spawn_local_singleplayer)
## so inventory_changed's sync_hotbar connection (wired in _ready()) is
## already live when the emit below fires. Uses this node's own
## _item_catalog, like every other item-granting method here (cooking,
## foraging, trading, crafting) -- no reason for this one to take a second,
## separately-supplied catalog when the rest of the file never does.
##
## Mirrors the established /give pattern (World._handle_give_command)
## exactly: has() -> make() -> inventory.add() -- an unknown id is skipped
## rather than crashing, since a stale/hand-edited selection is a normal
## condition to degrade from, not an error worth taking the game down over.
##
## Auto-equips the first WEAPON-kind choice; if none was chosen, the first
## TOOL-kind choice instead (equip_item already accepts either kind) -- so a
## {pickaxe, compass, lasso} pick starts holding the pickaxe, not bare-handed
## just because nothing is literally a weapon. Bare-handed only when neither
## kind was chosen at all: a real, intended consequence of replacing the old
## fixed kit outright rather than adding to it.
func grant_starter_items(item_ids: Array) -> void:
	var first_weapon: Item = null
	var first_tool: Item = null
	for item_id in item_ids:
		if not _item_catalog.has(item_id):
			continue
		var item := _item_catalog.make(item_id)
		inventory.add(item, 1)
		if first_weapon == null and item.is_weapon():
			first_weapon = item
		elif first_tool == null and item.kind == "tool":
			first_tool = item
	var to_equip := first_weapon if first_weapon != null else first_tool
	if to_equip != null:
		equip_item(to_equip)
	inventory_changed.emit()


## Consumes one unit of a "food"-kind item from the inventory to relieve
## hunger (see SurvivalMeters.eat) -- called from World when the player
## clicks a food row in the inventory window. Returns false (no-op) if the
## player doesn't actually hold a food item with this id.
func eat_food(item_id: String) -> bool:
	for stack in inventory.stacks():
		if stack.item.id == item_id and stack.item.kind == "food":
			inventory.remove(item_id, 1)
			survival.eat(EAT_HUNGER_RELIEF)
			# Rare/legendary catches (see FoodConsumption.FISH_BUFFS) grant a
			# timed buff directly on eating -- no cooking/recipe required.
			if FoodConsumption.FISH_BUFFS.has(item_id):
				active_food_buffs = FoodConsumption.apply_food_buff(
					active_food_buffs, FoodConsumption.FISH_BUFFS[item_id]
				)
			# Wild mushrooms (see docs/concept/mushrooms.md's "Eating one" +
			# "Identification") -- a real hazard for a toxic species, and real
			# field experience toward identifying the whole roster either way.
			if MushroomSpecies.IDS.has(item_id):
				_eat_mushroom(item_id)
			return true
	return false


## item_id -> total count held across every stack, for CraftingRecipeBook's
## pure can_craft()/craft() (which only knows about counts, not Inventory's
## multi-stack storage) and the crafting UI's affordability display.
func inventory_counts() -> Dictionary:
	return _inventory_counts()


func _inventory_counts() -> Dictionary:
	var counts := {}
	for stack in inventory.stacks():
		counts[stack.item.id] = counts.get(stack.item.id, 0) + stack.count
	return counts


## Crafts recipe_id (see CraftingRecipeBook) if the inventory holds enough
## inputs: removes exactly the consumed amount of each input (the delta
## between the pre-craft count and CraftingRecipeBook's reported remaining
## count) and adds the output via ItemCatalog. Returns false (no-op, nothing
## removed or added) if the recipe is unknown, its requires_structure/
## required_skill gate (see docs/concept/production_chains.md) isn't met, or
## inputs are insufficient.
func craft(recipe_id: String) -> bool:
	if not _meets_requires_structure(recipe_id) or not _meets_required_skill(recipe_id):
		return false
	var counts := _inventory_counts()
	var result := _crafting_recipe_book.craft(recipe_id, counts)
	if not result.success:
		return false

	for item_id in counts:
		var consumed: int = counts[item_id] - int(result.remaining_counts.get(item_id, 0))
		if consumed > 0:
			inventory.remove(item_id, consumed)

	if _item_catalog.has(result.output_item_id):
		var output_item := _item_catalog.make(result.output_item_id)
		var overflow: int = inventory.add(output_item, result.output_count)
		if overflow > 0:
			# A full inventory must never silently eat the crafted item (the
			# consumed inputs rarely free a whole slot) -- drop what didn't
			# fit at the player's feet as a pick-up-able ground item instead.
			WorldItemBus.item_dropped.emit(ItemStack.new(output_item, overflow), position)
	inventory_changed.emit()
	return true


## Converts _last_facing_direction into the 4-way string WeaponSwing/
## CharacterView.play_attack_swing expect, mirroring CharacterView.set_facing's
## own dominant-axis logic.
func _facing_string() -> String:
	if absf(_last_facing_direction.x) > absf(_last_facing_direction.y):
		return "right" if _last_facing_direction.x > 0.0 else "left"
	return "down" if _last_facing_direction.y > 0.0 else "up"


func current_tile() -> Vector2i:
	var raw := Vector2i(floori(position.x / _tile_size), floori(position.y / _tile_size))
	var world_size := Vector2i(EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	return _world_coordinates.wrap(raw, world_size)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_authority_step(delta)
	else:
		_proxy_step()

	if _is_local_player_instance() and not is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_submit_input.rpc_id(1, _read_local_input())
		_submit_attack.rpc_id(1, _local_momentary_input("attack"))
		_submit_cast.rpc_id(1, _local_momentary_input("cast"))
		_submit_build.rpc_id(1, _local_momentary_input("build"))
		_submit_destroy.rpc_id(1, _local_momentary_input("destroy"))
		_submit_plant.rpc_id(1, _local_momentary_input("plant"))


## Runs only on the authority (the server, or this same instance in the
## no-networking singleplayer fallback): the real simulation -- water
## depth/wetness/movement resolution and actual collision via move_and_slide.
func _authority_step(delta: float) -> void:
	if _chunk_manager == null:
		return
	if is_dead:
		_respawn_accumulator += delta
		if _respawn_accumulator >= RESPAWN_DELAY:
			_respawn()
		return  # frozen in place until the respawn timer above fires

	var tile := current_tile()
	var water_result := _resolve_water_state(tile, delta)
	current_mode = water_result.mode
	current_water_depth = water_result.water_depth
	# Overall condition (SurvivalMeters.fitness, driven by starving/
	# dehydrated/cold) is a real movement debuff, not a dead meter -- see
	# ConditionPenalty and docs/concept/survival.md's "Debuffs, not death".
	current_speed_multiplier = (
		water_result.speed_multiplier
		* _weather_speed_multiplier()
		* _terrain_speed_multiplier(tile)
		* ConditionPenalty.speed_multiplier(survival.fitness)
		* _spell_speed_multiplier()
	)

	var input_direction := _read_local_input() if _controlled_locally() else _pending_input_direction
	var desired_velocity := input_direction * current_speed() * current_speed_multiplier
	if _terrain_blocks_movement(input_direction) or is_rooted():
		desired_velocity = Vector2.ZERO
	velocity = _knockback_velocity(desired_velocity, delta)
	move_and_slide()
	_wrap_position()

	_last_facing_direction = input_direction if input_direction.length() > 0.01 else _last_facing_direction
	_update_character_view(input_direction)
	_step_water_ripples(delta, input_direction)

	survival.advance(delta)
	_regen_mana(delta)
	_spell_status_step(delta)
	_shield_step(delta)
	_cast_message_step(delta)
	# Standing in any water (wading in the shallows or swimming) lets you drink
	# from it -- the "drink from water tiles" option. Wading is the easy way to
	# quench thirst without getting fully soaked.
	if current_mode == "swimming" or current_mode == "wading":
		survival.drink(DRINK_RATE_PER_SECOND * delta)
	if _chunk_manager != null:
		survival.regulate_temperature(_chunk_manager.ambient_warmth(position), wetness, delta)

	_attack_step(delta)
	_cast_step()
	_pickup_step(delta)
	_kick_step()
	_stash_step()
	_build_step()
	_destroy_step()
	_plant_step()
	_fishing_step(delta)
	_lasso_step(delta)
	_food_buff_step(delta)
	_venom_step(delta)
	_mushroom_toxin_step(delta)
	_sickness_step(delta)
	_shop_step(delta)
	_action_slots_step()
	_talk_step(delta)


## Combined weather + exposure movement penalty (see WeatherModel /
## SurvivalMeters): rain and storm slow you, and being freezing slows you
## further (stiff, sluggish). 1.0 when the world isn't wired (isolated tests).
##
## The freezing magnitude is defined once, in ConditionPenalty, and shared:
## the continuous condition slow deliberately reuses this already-committed
## number rather than inventing a second one (see condition_penalty.gd).
const FREEZING_SPEED_PENALTY := ConditionPenalty.WORST_SPEED_MULTIPLIER
func _weather_speed_multiplier() -> float:
	var m := 1.0
	if _chunk_manager != null:
		m *= _chunk_manager.weather_speed_modifier(position)
	if survival.is_freezing():
		m *= FREEZING_SPEED_PENALTY
	return m


## Soft terrain slowdown from real slope (see docs/concept/terrain_relief.md,
## TerrainPassability.speed_multiplier) -- the same "environment scales a
## movement multiplier" shape _weather_speed_multiplier above already uses,
## driven by slope instead of weather. 1.0 when the world isn't wired
## (isolated tests), matching that function's own fallback.
func _terrain_speed_multiplier(tile: Vector2i) -> float:
	if _chunk_manager == null:
		return 1.0
	return TerrainPassability.speed_multiplier(_chunk_manager.slope_at_global(tile.x, tile.y))


## How far ahead (world pixels) to check terrain slope before committing to
## a step -- the same "ask before you step, don't correct after" principle
## CreatureMovementGate already established for creatures walking into
## trees, applied here to the player walking into a mountainside. Half a
## tile: far enough to be a real look-ahead, not so far that the player is
## refused entry to a tile before they're anywhere near its edge.
const TERRAIN_CHECK_DISTANCE_PX := 8.0

## Whether the tile the player is currently heading toward is too steep to
## enter at all (see TerrainPassability.is_passable). Checked BEFORE the
## step, not corrected after -- a refused step simply never becomes
## velocity, rather than the player being placed on impassable terrain and
## then pushed back out of it.
func _terrain_blocks_movement(input_direction: Vector2) -> bool:
	if _chunk_manager == null or input_direction.length() < 0.01:
		return false
	var look_ahead := position + input_direction.normalized() * TERRAIN_CHECK_DISTANCE_PX
	var raw := Vector2i(floori(look_ahead.x / _tile_size), floori(look_ahead.y / _tile_size))
	var world_size := Vector2i(EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var ahead_tile := _world_coordinates.wrap(raw, world_size)
	var slope := _chunk_manager.slope_at_global(ahead_tile.x, ahead_tile.y)
	return not TerrainPassability.is_passable(slope, _has_climbing_gear())


## Whether the player is CARRYING a real climbing rope (docs/concept/
## transportation.md, item_catalog.gd's "climbing_rope") -- terrain_relief.md's
## own "unless the player is carrying a climbing rope" framing, so this is a
## raw inventory count like _has_fishing_rod(), not an equipped/wielding
## check. Raises TerrainPassability's hard-impassable slope threshold from
## HARD_THRESHOLD_DEG to HARD_THRESHOLD_WITH_ROPE_DEG via
## _terrain_blocks_movement's call above.
func _has_climbing_gear() -> bool:
	return _inventory_counts().get("climbing_rope", 0) > 0


## Authority-only: resolves a melee swing on the rising edge of the attack
## input (not held-repeat), gated by ATTACK_COOLDOWN.
func _attack_step(delta: float) -> void:
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	var attack_pressed := (
		Input.is_action_pressed("attack") if _controlled_locally() else _pending_attack_pressed
	)
	var just_pressed := _rising_edge("attack", attack_pressed, _last_attack_input_state)
	_last_attack_input_state = attack_pressed

	# No swinging while swimming -- the weapon is stowed in the water (see
	# CharacterView.set_movement_state's visual stowing).
	if just_pressed and _attack_cooldown_remaining <= 0.0 and current_mode != "swimming":
		_perform_attack()


## Casts, on the rising edge, whichever spell the "cast" key is bound to.
## No spell-selection UI exists yet (see docs/concept/spell_runtime.md's
## fixed-spellbook scope), so this always casts the same one -- a real,
## honestly-scoped placeholder for "which spell", not a limitation of
## cast_spell itself, which already accepts any known spell id.
const DEFAULT_CAST_SPELL_ID := "fire_bolt"


func _cast_step() -> void:
	var cast_pressed := (
		Input.is_action_pressed("cast") if _controlled_locally() else _pending_cast_pressed
	)
	var just_pressed := _rising_edge("cast", cast_pressed, _last_cast_input_state)
	_last_cast_input_state = cast_pressed

	if just_pressed:
		cast_spell(DEFAULT_CAST_SPELL_ID)


func _perform_attack() -> void:
	_attack_cooldown_remaining = ATTACK_COOLDOWN
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)

	var creatures := get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)
	var positions: Array = []
	for creature in creatures:
		positions.append(creature.position)

	var base_damage := _melee_attack.attack_damage(_held_weapon(), UNARMED_DAMAGE) + class_attack_bonus + _skill_attack_bonus
	var damage := _material_damage.effective_damage(base_damage, _held_kind(), "flesh") * _damage_buff_multiplier()
	var hit_indices := _melee_attack.targets_in_range(position, positions, ATTACK_RANGE)
	for index in hit_indices:
		var creature: CreatureMarker = creatures[index]
		var knockback := _melee_attack.knockback_vector(
			position, creature.position, _knockback_force_for(_held_weapon())
		)
		creature.apply_knockback(knockback)
		creature.take_damage(damage)
		_wear_equipped_item()  # a real connecting hit, see docs/concept/item_durability.md
		# A hit that kills the creature awards XP scaled by its level (see
		# ExperienceTrack / concept/progression.md).
		if creature.is_queued_for_deletion() and creature.info != null:
			gain_experience(XP_PER_KILL * creature.info.level)

	_chop_step()
	_smash_step()
	_harvest_grass_step()
	_pull_wild_crop_step()
	_butcher_step()
	_collect_step()
	_harvest_farm_plot_step()


## Resolves a cast of `spell_id` from the fixed SpellBook (see
## docs/concept/spell_runtime.md's full resolution order): affordability
## (mana, plus any explicit guard the spell text writes), then the pipeline's
## real per-atom effects in delivery-method order. Returns false (spending
## nothing) for an unknown spell id or a refused cast -- true for a spell
## that actually resolved, even if delivery found nothing to hit ("even an
## affordable spell still has to land", magic.md).
func cast_spell(spell_id: String) -> bool:
	var ast = _spell_book.ast_for(spell_id)
	if ast == null:
		return false
	var rule = _spell_executor.cast_rule(ast)
	if rule == null:
		return false

	var context := {"wielder": {"mana": mana, "health": health}}
	if not _spell_executor.can_cast(rule, mana, context):
		cast_message = "Not enough mana."
		_cast_message_timer = CAST_MESSAGE_DURATION
		return false

	spend_mana(_spell_executor.cost_for(rule))
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)

	var delivery := _spell_executor.delivery_for(rule)
	for step in rule.get("pipeline", []):
		_apply_cast_step(step, delivery)
	return true


## One pipeline step's real effect. accelerate_growth/reveal target the
## WORLD (a plant, a chunk), not a creature/player, so they're resolved
## directly here against _chunk_manager rather than through
## SpellAtomEffects; portal/induce_mutation are deferred entirely (cost and
## visual only, see spell_runtime.md). Everything else routes through
## SpellAtomEffects against whatever SpellTargeting resolves for the rule's
## delivery method.
func _apply_cast_step(step: Dictionary, delivery: String) -> void:
	var atom_id: String = step.get("atom", "")
	var params: Dictionary = step.get("params", {})

	if atom_id == "accelerate_growth":
		_cast_accelerate_growth(params)
		return
	if atom_id == "reveal":
		_cast_reveal(params)
		return
	if atom_id == "portal" or atom_id == "induce_mutation":
		return

	var target = _resolve_cast_target(delivery)
	if target is Array:
		for one in target:
			if _spell_atom_effects.apply_to_target(atom_id, params, one, position, _last_facing_direction):
				_spawn_spell_effect(atom_id, one.position)
	else:
		if _spell_atom_effects.apply_to_target(atom_id, params, target, position, _last_facing_direction):
			_spawn_spell_effect(atom_id, target.position if target != null else position)


## The procedural VFX (see docs/concept/magic.md's atom-effects section) --
## only spawned when the atom actually landed (apply_to_target returned
## true), so a whiffed cast doesn't flash an effect over nothing.
const SpellEffectMarker = preload("res://src/rendering/spell_effect_marker.gd")


func _spawn_spell_effect(atom_id: String, at_position: Vector2) -> void:
	if get_parent() == null:
		return
	var marker := SpellEffectMarker.new()
	marker.position = at_position
	get_parent().add_child(marker)
	marker.play(atom_id)


## The creature/player group is scanned the same way _perform_attack already
## does (get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)) -- PvP
## spell targeting is out of scope, matching melee's own scope.
func _resolve_cast_target(delivery: String):
	if delivery == "self":
		return self
	var candidates := get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)
	var positions: Array = []
	for candidate in candidates:
		positions.append(candidate.position)

	match delivery:
		"area":
			var center := _spell_targeting.area_center(position, _last_facing_direction)
			var hit_indices := _spell_targeting.in_area(center, positions)
			var targets: Array = []
			for index in hit_indices:
				targets.append(candidates[index])
			return targets
		"projectile":
			var index := _spell_targeting.nearest_in_facing(position, _last_facing_direction, positions)
			return candidates[index] if index >= 0 else null
		_:  # touch
			var index := _spell_targeting.nearest_touch(position, positions)
			return candidates[index] if index >= 0 else null


## `accelerate_growth` targets the wild crop patch(es) in the caster's
## current chunk -- chunk-wide, not single-plant (see
## EarthChunkManager.accelerate_wild_crop_growth's own honest note; the same
## magnitude/duration convention every other atom reads its params with).
func _cast_accelerate_growth(params: Dictionary) -> void:
	if _chunk_manager == null:
		return
	var seconds := float(params.get("magnitude", 5.0))
	_chunk_manager.accelerate_wild_crop_growth(current_tile(), seconds)


## `reveal` marks every chunk within `radius` chunks of the caster explored
## (EarthChunkManager.mark_chunk_explored -- the real, live ExploredTiles
## wrapper, see spell_runtime.md). CHUNK_SIZE is EarthChunkManager's own
## public constant; the chunk-coord formula matches every test file's own
## _chunk_coord_for_tile helper exactly, since there's no public accessor
## for it on EarthChunkManager itself (a private implementation detail this
## doesn't need to reach into).
func _cast_reveal(params: Dictionary) -> void:
	if _chunk_manager == null:
		return
	var radius := int(params.get("radius", 1))
	var tile := current_tile()
	var chunk_size := EarthChunkManager.CHUNK_SIZE
	var center_chunk := Vector2i(floori(float(tile.x) / chunk_size), floori(float(tile.y) / chunk_size))
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			_chunk_manager.mark_chunk_explored(center_chunk + Vector2i(dx, dy))


## Per-frame decay of the cast result banner -- deliberately separate from
## _cast_step (the input-polling wrapper) and never reads Input at all, so
## it stays directly testable and so a cast's message shows immediately
## (cast_spell sets `cast_message` itself) rather than waiting for a
## propagation tick the way trade_message's own indirection needs.
func _cast_message_step(delta: float) -> void:
	_cast_message_timer = maxf(0.0, _cast_message_timer - delta)
	if _cast_message_timer <= 0.0:
		cast_message = ""


## Smashing/mining: a swing that reaches a rock node (shared "stone" group)
## does one of two things. An ore-bearing node (MinableOre, has mine()) is
## mined -- with a pickaxe equipped it yields ore + stone, bare-handed only
## stone (see OreYield). A plain boulder (SmashableStone, has smash()) always
## yields a rock; carrying another rock knaps sharp shards off it with a tested
## probability (see Knapping) -- rock-on-rock, the first tool technology.
func _smash_step() -> void:
	var stones := get_tree().get_nodes_in_group(SmashableStone.GROUP_NAME)
	var positions: Array = []
	for stone in stones:
		positions.append(stone.position)

	var carrying_rock: bool = _inventory_counts().get("rock", 0) > 0
	var pickaxe_power := _pickaxe_power()
	for index in _melee_attack.targets_in_range(position, positions, ATTACK_RANGE):
		var node = stones[index]
		if node.has_method("mine"):
			node.mine(pickaxe_power)
		elif node.has_method("smash"):
			node.smash(carrying_rock)


## Mining power of the currently-equipped tool: a pickaxe mines ore, anything
## else (or nothing) has zero mining power (bare-handed).
func _pickaxe_power() -> float:
	if equipped_item != null and equipped_item.is_pickaxe():
		return PICKAXE_POWER
	return 0.0


## Harvesting: a swing over a mature tall-grass patch tears it up for plant
## fibre (see EarthChunkManager.harvest_grass_near) -- the lashing material in
## the stick+shard+fibre crude-blade recipe.
func _harvest_grass_step() -> void:
	if _chunk_manager != null:
		_chunk_manager.harvest_grass_near(position)


## Pulling: a swing over a mature wild carrot/potato patch pulls it out of
## the ground (see WildCropMarker.begin_pull, docs/concept/wild_crops.md) --
## same shared "stone"/"tree" group-scan + range-sweep shape as
## _smash_step/_chop_step, just targeting WildCropMarker.GROUP_NAME. The
## pull itself is animated over CropPull.DURATION_SECONDS and only drops the
## actual item once that finishes -- this swing just STARTS it.
func _pull_wild_crop_step() -> void:
	var crops := get_tree().get_nodes_in_group(WildCropMarker.GROUP_NAME)
	var positions: Array = []
	for crop in crops:
		positions.append(crop.position)

	for index in _melee_attack.targets_in_range(position, positions, ATTACK_RANGE):
		crops[index].begin_pull()


## Butchering: a swing over a nearby carcass (see Carcass.butcher,
## docs/concept/carrion.md) takes its next remaining part -- same shared
## group-scan + range-sweep shape as every other harvest step above. Meat
## yield reads the player's allocated butchering skill live (SkillTree's
## meat_yield stat, see Butchering.meat_count) rather than caching it --
## always in sync with allocated_nodes, no separate accumulator to drift.
func _butcher_step() -> void:
	var carcasses := get_tree().get_nodes_in_group(Carcass.GROUP_NAME)
	var positions: Array = []
	for carcass in carcasses:
		positions.append(carcass.position)

	if positions.is_empty():
		return
	var meat_yield_bonus := skill_bonus("meat_yield")
	for index in _melee_attack.targets_in_range(position, positions, ATTACK_RANGE):
		carcasses[index].butcher(meat_yield_bonus)
		# Anthrax-like spillover (docs/concept/disease.md): butchering a
		# contaminated carcass without care carries real infection risk --
		# the "careless butchering" consequence the doc names directly, a
		# real tax on skipping caution rather than a hidden gotcha.
		if carcasses[index].contaminated:
			apply_disease_bite(DiseaseModel.CARRION)


## Collecting: a swing near a real, nearby Sägewerk (see
## EarthChunkManager.has_structure_near) withdraws whatever real beam/plank
## stock it has piled up (StructureStock, credited by LumberjackMarker's own
## production step -- see docs/concept/timber_construction.md's "Storage,
## logistics, and the autonomous dependency chain" section) straight into
## the player's own inventory. A direct pickup, not a ground find, since the
## player is standing right at the source performing the collection
## themselves -- the real stand-in for a player with no Storage/Logistics
## built yet (see that section's own "What's honestly still a stand-in
## here" gap note this closes). No-ops with nothing built up yet, or no
## Sägewerk within reach -- same shared group-scan/proximity shape every
## other harvest step above uses, just against a placed structure instead
## of a creature/tree/plant.
func _collect_step() -> void:
	if _chunk_manager == null:
		return
	var tile := current_tile()
	if not _chunk_manager.has_structure_near(tile.x, tile.y, "sagewerk", SAGEWERK_COLLECT_RADIUS_TILES):
		return
	var sagewerk_pixel = _chunk_manager.nearest_structure_position(
		position, "sagewerk", float(SAGEWERK_COLLECT_RADIUS_TILES) * TerrainRenderer.TILE_SIZE
	)
	if sagewerk_pixel == null:
		return
	var sagewerk_tile := Vector2i(
		floori(sagewerk_pixel.x / TerrainRenderer.TILE_SIZE), floori(sagewerk_pixel.y / TerrainRenderer.TILE_SIZE)
	)
	for item_id in ["beam", "plank"]:
		var available: int = _chunk_manager.structure_stock_at(sagewerk_tile.x, sagewerk_tile.y, item_id)
		if available <= 0:
			continue
		_chunk_manager.withdraw_from_structure_at(sagewerk_tile.x, sagewerk_tile.y, item_id, available)
		inventory.add(_item_catalog.make(item_id), available)


## Harvesting: on an attack swing, if the tile the player is FACING carries
## a ready farm plot (see EarthChunkManager.harvest_farm_plot_at_global,
## docs/concept/farming.md), grants its real crop yield straight to
## inventory -- the same direct-grant shape _collect_step just above
## already uses (no ground-drop/pull animation for this slice, a
## documented simplification -- see docs/progress.md's Farming entry).
## Tile-targeted rather than a group-scan like the harvest steps above: a
## farm plot isn't a free-floating Node2D the player walks up to, it's
## anchored to a specific tile, the same way build/destroy target a tile
## instead of scanning nearby nodes.
func _harvest_farm_plot_step() -> void:
	if _chunk_manager == null:
		return
	var target := _tile_targeting.facing_tile(current_tile(), _last_facing_direction)
	var result: Dictionary = _chunk_manager.harvest_farm_plot_at_global(target.x, target.y)
	var count: int = result.get("count", 0)
	if count <= 0:
		return
	inventory.add(_item_catalog.make(result["crop_id"]), count)


## The held item's material-model kind (see MaterialDamage/Block), used for
## attacks, blocking, AND chopping -- so what's in hand is the single thing
## that matters: an axe chops wood fast (and blocks/cuts like an axe), a sword
## chops slowly but blocks best, bare hands (or a non-weapon tool like a
## pickaxe) are weakest at both.
## "unarmed" for bare hands AND for an item broken from accumulated combat
## fatigue (see docs/concept/item_durability.md) -- a broken sword blocks/
## attacks exactly like empty hands, not like a still-functional sword.
func _held_kind() -> String:
	if equipped_item == null or _equipped_item_is_broken():
		return "unarmed"
	if equipped_item.is_axe():
		return "axe"
	return "sword" if equipped_item.is_weapon() else "unarmed"


## The held item as an attack weapon, or null if it isn't one (bare-hands /
## holding a tool) OR it's broken from fatigue (see docs/concept/
## item_durability.md) -- feeds MeleeAttack.attack_damage, which already
## falls back to UNARMED_DAMAGE for null, so a broken weapon needs no
## separate damage path of its own.
func _held_weapon():
	if equipped_item == null or not equipped_item.is_weapon():
		return null
	return null if _equipped_item_is_broken() else equipped_item


func _equipped_item_is_broken() -> bool:
	return _item_wear.is_broken(equipped_item.wear, _item_catalog.material_of(equipped_item.id))


## Adds one use's worth of combat wear to the currently equipped item, if it
## has a real modeled material (see docs/concept/item_durability.md) --
## items with none (item_catalog.gd's own "not guessed at here" convention,
## the same one mass_kg already follows) never accrue wear and so can never
## break from it. Called once per connecting attack target and once per
## block that actually absorbs a real hit.
func _wear_equipped_item() -> void:
	if equipped_item == null:
		return
	if _item_catalog.material_of(equipped_item.id) == "":
		return
	equipped_item.wear += ItemWear.WEAR_PER_USE


## A swing's knockback force, fed by the held weapon's REAL mass through the
## same momentum model Throwable.impact_knockback already uses for thrown
## items (mass * velocity, docs/concept/materials.md), rather than the flat
## KNOCKBACK_FORCE every weapon used to deal identically regardless of what
## it actually was.
##
## Calibrated against an iron sword (this game's baseline melee weapon) so
## the EXISTING tuned KNOCKBACK_FORCE (60px) is exactly what an iron sword
## already delivers -- wiring in real mass does not silently retune every
## already-tuned attack, only weapons lighter/heavier than an iron sword
## diverge from that baseline. Bare hands, or a weapon with no mass modeled
## yet (mass_kg 0.0), fall back to the original constant untouched -- there
## is no invented "fist mass" standing in for a real one.
func _knockback_force_for(weapon) -> float:
	if weapon == null or weapon.mass_kg <= 0.0:
		return KNOCKBACK_FORCE
	var momentum := _throwable.impact_knockback(weapon.mass_kg, SWING_IMPACT_SPEED_MPS)
	return _knockback_force_for_momentum(momentum)


## Converts a real momentum value (kg * m/s) into the game's existing
## knockback-force scale (world pixels of displacement, see Knockback.step),
## calibrated so an iron sword's own momentum reproduces the original tuned
## KNOCKBACK_FORCE exactly (see _knockback_force_for's own doc comment).
## Shared by weapon swings (_knockback_force_for) and the held-item throw
## (_resolve_thrown_stone_impact) so both real-momentum sources land on the
## same pixel scale rather than each inventing their own conversion.
func _knockback_force_for_momentum(momentum: float) -> float:
	var reference_mass_kg: float = _item_catalog.make("iron_sword").mass_kg
	var reference_momentum := _throwable.impact_knockback(reference_mass_kg, SWING_IMPACT_SPEED_MPS)
	return KNOCKBACK_FORCE * (momentum / reference_momentum)


## True while the block input is held (and the player is alive): incoming
## damage is reduced weapon-dependently (see Block); blocking, like attacking,
## costs no stamina -- combat stays purely cooldown-based (see
## concept/survival.md's "Stamina scope: movement only, not combat").
func is_blocking() -> bool:
	if is_dead:
		return false
	return Input.is_action_pressed("block") if _controlled_locally() else _pending_block_pressed


## How much Carpentry (SkillTree's carpentry_1/2 nodes, summed via
## total_bonus) it takes to saw a bare trunk into beam/plank instead of
## bucking it into raw logs -- see docs/concept/woodworking.md. Requires
## BOTH nodes allocated, genuine investment rather than a single point.
const CARPENTRY_LEVEL_FOR_SAWING := 2.0

## Felling: any swing damages ChoppableTrees in range through the material
## damage model (see MaterialDamage), scaled by the HELD item -- an axe chops
## at full efficiency (3x wood multiplier), a sword hacks weakly (0.5x, so a
## tree takes many more swings), bare hands barely scratch bark (0.25x). Same
## AOE range/targeting math as creature hits (reuses MeleeAttack.targets_in_range).
##
## A saw + enough Carpentry tries ChoppableTree.saw_up first, on a bare
## trunk, turning the whole remaining trunk into beam+plank in one action
## instead of the ordinary one-log-per-swing chop -- saw_up itself is the
## authority on whether that's actually possible right now (is the trunk
## even bare yet?), so a swing that doesn't qualify just falls through to
## the normal take_damage() unchanged.
func _chop_step() -> void:
	var damage := _material_damage.effective_damage(BASE_CHOP_DAMAGE, _held_kind(), "wood")
	if damage <= 0.0:
		return

	var trees := get_tree().get_nodes_in_group(ChoppableTree.GROUP_NAME)
	var positions: Array = []
	for tree in trees:
		positions.append(tree.position)

	var has_saw: bool = equipped_item != null and equipped_item.is_saw()
	var carpentry_level := skill_bonus("carpentry_level")
	var can_saw := has_saw and carpentry_level >= CARPENTRY_LEVEL_FOR_SAWING

	var hit_indices := _melee_attack.targets_in_range(position, positions, ATTACK_RANGE)
	for index in hit_indices:
		var tree: ChoppableTree = trees[index]
		if can_saw and tree.saw_up():
			continue
		tree.take_damage(damage)


## Authority-only: E (pickup) is now CONTEXTUAL (see docs/concept/stone.md,
## generalized in docs/concept/wild_crops.md to any real physical object):
## empty-handed near a liftable stone, E picks it into the HAND instead of
## straight to inventory (_try_pick_stone_into_hand); failing that, empty-
## handed near a dropped item with a real, kickable-grade mass, E picks
## THAT into the hand instead (_try_pick_item_into_hand); empty-handed with
## neither nearby, E still does the ordinary ground-item sweep unchanged
## (pickup_nearby) -- so an item with no modeled mass (most food/material
## drops today) keeps going straight to inventory exactly as before. With
## something already in hand, a NEW press starts a charge (ChargeMeter
## bounces while held -- see hand_charge_fraction), and releasing throws it
## (_throw_held_stone or _throw_held_item, whichever is actually held).
## Rising-edge detection throughout so holding E doesn't repeat the initial
## action every frame.
func _pickup_step(delta: float) -> void:
	var pickup_pressed := (
		Input.is_action_pressed("pickup") if _controlled_locally() else _pending_pickup_pressed
	)
	var just_pressed := pickup_pressed and not _last_pickup_input_state
	var just_released := _last_pickup_input_state and not pickup_pressed
	_last_pickup_input_state = pickup_pressed

	if not is_holding_anything():
		if just_pressed and not _try_pick_stone_into_hand() and not _try_pick_item_into_hand():
			# A direct-from-the-tree harvest (see _try_harvest_peak_fruit) only
			# runs when the ordinary ground-item sweep found nothing -- one E
			# press does one thing, and a windfall already underfoot takes
			# priority over reaching for the branch.
			if pickup_nearby() == 0:
				_try_harvest_peak_fruit()
		return

	if just_pressed:
		# A NEW press while already holding something starts a real charge
		# cycle -- distinct from the press that grabbed the stone into hand
		# in the first place (see _charging's own doc comment).
		_charging = true
		_hand_charge_elapsed = 0.0
	elif _charging and pickup_pressed:
		_hand_charge_elapsed += delta

	if just_released and _charging:
		_charging = false
		if is_holding_stone():
			_throw_held_stone()
		else:
			_throw_held_item()


## Whether a stone is currently held in hand (see _hand_stone_diameter_cm's
## own doc comment) -- distinct from both inventory and Equipment's worn
## weapon slot.
func is_holding_stone() -> bool:
	return _hand_stone_diameter_cm >= 0.0


## Whether a general dropped item (not a stone) is currently held in hand
## (see _hand_item_stack's own doc comment).
func is_holding_item() -> bool:
	return _hand_item_stack != null


## Whether ANYTHING is currently held in hand -- a stone or a general item.
## Read wherever code previously asked is_holding_stone() to gate "is the
## hand occupied at all" (e.g. the E-pickup dispatch above, the interaction
## prompt) now that the hand can hold either kind of object.
func is_holding_anything() -> bool:
	return is_holding_stone() or is_holding_item()


## The charge meter's current reading in [0, 1] (see ChargeMeter) -- 0.0
## whenever nothing is in hand, or the pickup input isn't currently held.
## Read by World for the strengthometer UI.
func hand_charge_fraction() -> float:
	if not is_holding_anything() or not _charging:
		return 0.0
	return ChargeMeter.fraction_at(_hand_charge_elapsed)


## Takes the nearest liftable stone in reach (same nearby-target-finding
## convention as pickup_nearby/Kick -- EarthChunkManager.
## nearest_liftable_stone_near, PICKUP_RADIUS) into the HAND rather than
## straight to inventory. Returns whether anything was actually picked up,
## so the caller can fall back to the ordinary sweep when there's no stone
## nearby.
func _try_pick_stone_into_hand() -> bool:
	if _chunk_manager == null:
		return false
	var stone: Node2D = _chunk_manager.nearest_liftable_stone_near(position, PICKUP_RADIUS)
	if stone == null:
		return false
	_hand_stone_diameter_cm = stone.diameter_cm
	_hand_charge_elapsed = 0.0
	_charging = false
	stone.queue_free()
	return true


## Takes the nearest dropped item with a real, kickable-grade mass (the
## SAME "physical object" set Kick already recognizes -- see
## nearest_kickable_dropped_item_near) into the HAND, mirroring
## _try_pick_stone_into_hand exactly. An item with no modeled mass (most
## food/material drops today) is NOT a hand object -- it is deliberately
## left for the caller to fall back to the ordinary pickup_nearby() sweep,
## unchanged from before this existed.
func _try_pick_item_into_hand() -> bool:
	var dropped_item := nearest_kickable_dropped_item_near(position, PICKUP_RADIUS)
	if dropped_item == null:
		return false
	_hand_item_stack = dropped_item.item_stack
	_hand_charge_elapsed = 0.0
	_charging = false
	dropped_item.queue_free()
	return true


## Throws whatever is in hand: release power (wherever the ChargeMeter was
## at release) sets a real throw speed (HeldItemThrow.release_speed_mps),
## which feeds the SAME momentum model (Throwable.impact_knockback,
## docs/concept/materials.md) as every other hit in this game -- not a
## separate new physics path. The stone reappears in the world at its
## landing spot (see _spawn_thrown_stone) whether or not it struck anything
## on the way.
func _throw_held_stone() -> void:
	var diameter_cm := _hand_stone_diameter_cm
	_hand_stone_diameter_cm = -1.0

	var power := ChargeMeter.fraction_at(_hand_charge_elapsed)
	var release_speed := HeldItemThrow.release_speed_mps(power)
	var mass_kg := StoneSize.mass_kg_for(diameter_cm)
	var momentum := _throwable.impact_knockback(mass_kg, release_speed)
	var distance := HeldItemThrow.throw_distance_px(power)
	var direction := _last_facing_direction if _last_facing_direction.length() > 0.01 else Vector2.DOWN
	var landing_position := position + direction.normalized() * distance

	_resolve_thrown_stone_impact(landing_position, momentum)
	_resolve_stone_impact_on_obstacles(landing_position, momentum)
	_spawn_thrown_stone(landing_position, diameter_cm)


## Throws whatever generic item is in hand -- the SAME release-power ->
## real-momentum pipeline _throw_held_stone uses, just reading the item's
## own real mass (Item.mass_kg) instead of deriving one from a stone
## diameter, and spawning a plain DroppedItem at the landing spot instead
## of rebuilding a LiftableStone.
func _throw_held_item() -> void:
	var item_stack = _hand_item_stack
	_hand_item_stack = null

	var power := ChargeMeter.fraction_at(_hand_charge_elapsed)
	var release_speed := HeldItemThrow.release_speed_mps(power)
	var mass_kg: float = item_stack.item.mass_kg
	var momentum := _throwable.impact_knockback(mass_kg, release_speed)
	var distance := HeldItemThrow.throw_distance_px(power)
	var direction := _last_facing_direction if _last_facing_direction.length() > 0.01 else Vector2.DOWN
	var landing_position := position + direction.normalized() * distance

	_resolve_thrown_stone_impact(landing_position, momentum)
	_resolve_stone_impact_on_obstacles(landing_position, momentum)
	_spawn_thrown_item(landing_position, item_stack)


## How close a thrown stone's landing spot must be to a creature to count as
## a hit -- the same order of magnitude as ATTACK_RANGE, since both are
## "close enough to actually connect".
const THROWN_STONE_IMPACT_RADIUS_PX := 20.0

## Flat damage a thrown stone deals on a real (non-"bounce") impact.
## Simplification, documented rather than guessed at silently:
## ImpactResolver's outcome is read as a simple hit/no-hit here rather than
## mapped to a full per-outcome damage table -- docs/concept/materials.md
## itself lists per-outcome damage tuning as an open, project-wide design
## question, not something to invent unilaterally for this one feature.
const THROWN_STONE_BASE_DAMAGE := 4.0

## A thrown stone's impact against any creature at the landing spot --
## resolved through the SAME shared momentum model
## (ImpactResolver.resolve_impact, MeleeAttack.knockback_vector) every other
## hit in this game already uses.
func _resolve_thrown_stone_impact(landing_position: Vector2, momentum: float) -> void:
	var creatures := get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)
	var positions: Array = []
	for creature in creatures:
		positions.append(creature.position)
	var hit_indices := _melee_attack.targets_in_range(landing_position, positions, THROWN_STONE_IMPACT_RADIUS_PX)
	for index in hit_indices:
		var creature: CreatureMarker = creatures[index]
		var outcome := _impact_resolver.resolve_impact(momentum, "blunt", "flesh")
		if outcome == "bounce":
			continue
		var knockback := _melee_attack.knockback_vector(
			landing_position, creature.position, _knockback_force_for_momentum(momentum)
		)
		creature.apply_knockback(knockback)
		creature.take_damage(THROWN_STONE_BASE_DAMAGE)


## Delivers `momentum` to any CollapsedPassage obstacle (docs/concept/
## exploration.md's "collapsed passage" momentum obstacle) within
## THROWN_STONE_IMPACT_RADIUS_PX of `landing_position` -- the SAME nearby-
## target proximity check (_melee_attack.targets_in_range) and the SAME
## momentum value _resolve_thrown_stone_impact already resolves against
## creatures above, just checked against the OTHER kind of thing a real
## delivered momentum can act on in this world. The obstacle itself decides
## clear-vs-stays-blocked via ImpactResolver (see CollapsedPassage.
## receive_impact) -- no second hit-detection system, no bespoke obstacle
## event.
func _resolve_stone_impact_on_obstacles(landing_position: Vector2, momentum: float) -> void:
	var obstacles := get_tree().get_nodes_in_group(CollapsedPassage.GROUP_NAME)
	var positions: Array = []
	for obstacle in obstacles:
		positions.append(obstacle.position)
	var hit_indices := _melee_attack.targets_in_range(landing_position, positions, THROWN_STONE_IMPACT_RADIUS_PX)
	for index in hit_indices:
		obstacles[index].receive_impact(momentum)


## Materializes a real, correctly-rendered liftable stone (see
## StoneRenderer.build_liftable_stone_node) at the throw's landing spot --
## whether or not it struck anything on the way, a thrown stone still ends
## up lying on the ground afterward, exactly like any other loose stone.
func _spawn_thrown_stone(landing_position: Vector2, diameter_cm: float) -> void:
	var stone := _stone_renderer.build_liftable_stone_node(randi(), diameter_cm)
	stone.position = landing_position
	get_parent().add_child(stone)


## Materializes a real DroppedItem at `landing_position` -- the generic-item
## counterpart of _spawn_thrown_stone, and also reused by _stash_step to
## drop whatever doesn't fit in a full inventory rather than losing it.
func _spawn_thrown_item(landing_position: Vector2, item_stack) -> void:
	var dropped := DroppedItem.new()
	dropped.item_stack = item_stack
	dropped.position = landing_position
	get_parent().add_child(dropped)


## Picks up every ground item within PICKUP_RADIUS. Returns the number of item
## nodes fully collected.
func pickup_nearby() -> int:
	var collected := 0
	for item in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		if item.is_queued_for_deletion():
			continue
		if position.distance_to(item.position) <= PICKUP_RADIUS and item.pick_up(self):
			collected += 1
	return collected


## Fallback for the pickup key when the ordinary ground sweep found nothing:
## takes real hanging fruit straight from the nearest tree in reach (see
## EarthChunkManager.harvest_peak_fruit_near, PICKUP_RADIUS) into inventory
## and awards real XP (see EcologicalLiteracy.harvest_xp) -- more when the
## harvest lands at genuine peak ripeness than off-peak (docs/concept/
## progression.md "Ecological literacy"). Returns whether anything was
## harvested. This is the only harvest path that can ever land AT peak: a
## windfall item on the ground (pickup_nearby above) has, by construction,
## already left that window (see fruiting_model.gd's is_peak_ripe).
func _try_harvest_peak_fruit() -> bool:
	if _chunk_manager == null:
		return false
	var found := _chunk_manager.harvest_peak_fruit_near(position, PICKUP_RADIUS)
	if found.is_empty():
		return false
	var species_id: String = found["species_id"]
	inventory.add(_item_catalog.make(species_id), 1)
	inventory_changed.emit()
	gain_experience(_ecological_literacy.harvest_xp(found.get("is_peak", false)))
	return true


## Authority-only: on the rising edge of the kick input (default K -- see
## Keybindings), delivers a real one-time momentum (Kick.KICK_MOMENTUM_KG_M_S)
## to the nearest kickable PHYSICAL OBJECT in reach -- a liftable stone
## (docs/concept/stone.md) OR a dropped item with a real, modeled mass (e.g.
## a pulled wild carrot/potato, docs/concept/wild_crops.md's "a real physical
## entity, not just an inventory grant"), whichever is genuinely closer.
## Reuses PICKUP_RADIUS and EarthChunkManager.nearest_liftable_stone_near --
## the SAME nearby-target-finding convention pickup/dispersion already use --
## rather than a new proximity query for the stone half. An object at or
## above leg mass (Kick.is_kickable) is too heavy for a kick to move at all;
## a lighter one flies a distance that scales with the delivered momentum
## vs. its own mass, exactly Throwable.impact_knockback's reasoning.
func _kick_step() -> void:
	var kick_pressed := (
		Input.is_action_pressed("kick") if _controlled_locally() else _pending_kick_pressed
	)
	var just_pressed := _rising_edge("kick", kick_pressed, _last_kick_input_state)
	_last_kick_input_state = kick_pressed
	if not just_pressed or _chunk_manager == null:
		return

	var stone: Node2D = _chunk_manager.nearest_liftable_stone_near(position, PICKUP_RADIUS)
	var stone_mass := StoneSize.mass_kg_for(stone.diameter_cm) if stone != null else 0.0
	var stone_kickable := stone != null and Kick.is_kickable(stone_mass)
	var stone_distance := position.distance_to(stone.position) if stone_kickable else INF

	var dropped_item := nearest_kickable_dropped_item_near(position, PICKUP_RADIUS)
	var dropped_distance := position.distance_to(dropped_item.position) if dropped_item != null else INF

	if not stone_kickable and dropped_item == null:
		return

	# The leg's momentum is conserved into the kicked object (see kick.gd's
	# own doc comment: exit velocity = KICK_MOMENTUM_KG_M_S / its own mass, so
	# its own momentum at landing is exactly KICK_MOMENTUM_KG_M_S again) --
	# the same real momentum a thrown stone delivers via
	# _resolve_stone_impact_on_obstacles above, just from a kick instead of
	# a throw. Whichever candidate is genuinely nearer wins -- a farther
	# stone should not always take priority over a nearer dropped item just
	# because stones were the first kickable thing this game had.
	if stone_kickable and stone_distance <= dropped_distance:
		var landing_position := Kick.landing_position(position, stone.position, stone_mass)
		_resolve_stone_impact_on_obstacles(landing_position, Kick.KICK_MOMENTUM_KG_M_S)
		stone.position = landing_position
	else:
		var mass: float = dropped_item.item_stack.item.mass_kg
		var landing_position := Kick.landing_position(position, dropped_item.position, mass)
		_resolve_stone_impact_on_obstacles(landing_position, Kick.KICK_MOMENTUM_KG_M_S)
		dropped_item.position = landing_position


## Nearest DroppedItem within `radius` whose real item mass (Item.mass_kg) is
## light enough for Kick.is_kickable -- an item with no modeled mass yet
## (0.0, item.gd's own "not modeled" convention, still most food/material
## items) is deliberately excluded, the same as a stone at/above leg mass:
## kicking something with no real mass would be meaningless under the shared
## momentum model (docs/concept/materials.md).
func nearest_kickable_dropped_item_near(from: Vector2, radius: float) -> DroppedItem:
	var nearest: DroppedItem = null
	var nearest_distance := radius
	for item in get_tree().get_nodes_in_group(DroppedItem.GROUP_NAME):
		# Not every member of this group is a DroppedItem: LiftableStone and
		# PickableSeed deliberately join it so the pickup sweep collects them
		# with no special case of their own (see their own doc comments), and
		# neither carries an item_stack -- reading one threw a runtime error
		# per stone per frame and aborted this whole scan, so K silently
		# stopped kicking dropped items whenever a pebble or seed was loaded.
		# Gated by what a member actually answers to, the same way
		# EarthChunkManager.step_ground_food gates this very group and
		# nearest_liftable_stone_near gates the stone one.
		if not is_instance_valid(item) or not ("item_stack" in item):
			continue
		if item.is_queued_for_deletion() or item.item_stack == null:
			continue
		var mass: float = item.item_stack.item.mass_kg
		if mass <= 0.0 or not Kick.is_kickable(mass):
			continue
		var distance := from.distance_to(item.position)
		if distance <= nearest_distance:
			nearest = item
			nearest_distance = distance
	return nearest


## Authority-only: on the rising edge of the stash input (default H -- see
## Keybindings), puts whatever is currently held in the HAND away into the
## inventory -- the deliberate "put this down" complement to E's "pick this
## up into hand" (docs/concept/stone.md's held-item concept, generalized in
## docs/concept/wild_crops.md to any real physical object). A no-op with
## nothing in hand. Whatever doesn't fit is dropped as a real ground item at
## the player's own feet (_spawn_thrown_item) rather than lost -- stashing
## never silently discards anything, unlike LiftableStone.pick_up's own
## existing "partial overflow is silently dropped" ground-pickup behavior,
## which this deliberately does NOT copy: that shortcut is tolerable for an
## incidental walk-up pickup, not for a player's own deliberate stash.
func _stash_step() -> void:
	var stash_pressed := (
		Input.is_action_pressed("stash") if _controlled_locally() else _pending_stash_pressed
	)
	var just_pressed := _rising_edge("stash", stash_pressed, _last_stash_input_state)
	_last_stash_input_state = stash_pressed
	if not just_pressed or not is_holding_anything() or inventory == null:
		return

	if is_holding_stone():
		var diameter_cm := _hand_stone_diameter_cm
		_hand_stone_diameter_cm = -1.0
		var count := StoneSize.rock_yield(diameter_cm)
		var rock_item := Item.new("rock", "Rock", "material", 20)
		var overflow: int = inventory.add(rock_item, count)
		if overflow > 0:
			_spawn_thrown_item(position, ItemStack.new(rock_item, overflow))
	else:
		var item_stack = _hand_item_stack
		_hand_item_stack = null
		var overflow: int = inventory.add(item_stack.item, item_stack.count)
		if overflow > 0:
			_spawn_thrown_item(position, ItemStack.new(item_stack.item, overflow))


## Authority-only: the fishing minigame (see FishingSession / concept/fishing.md).
## Press the fish key next to water with a rod to cast -- a visible rod-throw
## swing and a bobber landing at the cast point (see FishingCast), drawing
## nearby fish toward it (EarthChunkManager.set_attraction_point). Wait for a
## bite (the bobber dips), then press the fish key again within the reaction
## window to land it (rarer catches yield more). Reeling too early or too
## late loses it. The HUD reads fishing_message.
func _fishing_step(delta: float) -> void:
	_fishing.advance(delta)
	if _fishing.phase() == FishingSession.CAUGHT:
		var rarity := _fishing.rarity()
		var count: int = FISH_REWARD_BY_RARITY.get(rarity, 1)
		# Rare/legendary catches become their own buff-granting item (see
		# FoodConsumption.FISH_BUFFS) so the rarity survives into the
		# inventory instead of being lost the moment the reward is granted.
		var fish_item_id: String = FISH_ITEM_ID_BY_RARITY.get(rarity, "fish")
		inventory.add(_item_catalog.make(fish_item_id), count)
		inventory_changed.emit()
		# If a real, visible fish (see FishRenderer) happens to be nearby,
		# make it disappear and name its species -- purely cosmetic, doesn't
		# change what's rewarded (still the rarity-scaled item/count above).
		var species := ""
		if _chunk_manager != null:
			species = _chunk_manager.catch_nearest_fish(position, FISH_CATCH_RADIUS)
		if species != "":
			_fishing_result_message = "Caught a %s %s! (x%d)" % [rarity, species, count]
		else:
			_fishing_result_message = "Caught a %s fish! (x%d)" % [rarity, count]
		_fishing_result_timer = FISH_MESSAGE_DURATION
		_fishing = FishingSession.new()
		_end_cast_visuals()
	elif _fishing.phase() == FishingSession.MISSED:
		_fishing_result_message = "The fish got away…"
		_fishing_result_timer = FISH_MESSAGE_DURATION
		_fishing = FishingSession.new()
		_end_cast_visuals()

	var fish_pressed := (
		Input.is_action_pressed("fish") if _controlled_locally() else _pending_fish_pressed
	)
	var just_pressed := fish_pressed and not _last_fish_input
	_last_fish_input = fish_pressed
	if just_pressed:
		if _fishing.is_active():
			_fishing.react()
		elif _has_fishing_rod() and _near_water():
			_fishing_cast_count += 1
			_fishing.cast(
				hash("%d_%d_%d" % [int(position.x), int(position.y), _fishing_cast_count]), 0.0
			)
			_start_cast_visuals()

	if _fishing.is_active() and _bobber != null:
		# A visible dip while a fish is on the line, on top of the HUD text.
		var bob := sin(_fishing.phase_elapsed_seconds() * BITE_BOB_SPEED) * BITE_BOB_AMPLITUDE_PX \
			if _fishing.phase() == FishingSession.BITING else 0.0
		_bobber.global_position = _bobber_target + Vector2(0, bob)
		if _chunk_manager != null:
			_chunk_manager.set_attraction_point(_bobber_target, ATTRACTION_RADIUS)

	_fishing_result_timer = maxf(0.0, _fishing_result_timer - delta)
	if _fishing.phase() == FishingSession.BITING:
		fishing_message = "! BITE — press the fish key!"
	elif _fishing.is_active():
		fishing_message = "Casting… wait for a bite."
	elif _fishing_result_timer > 0.0:
		fishing_message = _fishing_result_message
	else:
		fishing_message = ""


## Casting: a quick rod-throw swing (reusing the same swing animation as a
## melee attack) and the bobber landing at the cast point, drawing nearby
## fish in.
func _start_cast_visuals() -> void:
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)
	_bobber_target = _fishing_cast.cast_point(position, _last_facing_direction)
	if _bobber != null:
		_bobber.global_position = _bobber_target
		_bobber.visible = true
	if _chunk_manager != null:
		_chunk_manager.set_attraction_point(_bobber_target, ATTRACTION_RADIUS)


func _end_cast_visuals() -> void:
	if _bobber != null:
		_bobber.visible = false
	if _chunk_manager != null:
		_chunk_manager.clear_attraction_point()


## Taming: throw the lasso, lead what it caught, tie it off, and feed it (see
## docs/concept/taming.md). One key does the lot, because what it means is
## unambiguous from what the player is currently holding:
##
##   nothing caught  -> throw at the nearest catchable animal in range
##   caught, near a tree -> tie the loose end off there
##   caught, tied    -> untie and take the rope back in hand
##   caught, in hand -> let it go
##
## Feeding is separate and automatic on contact, since walking a carrot up to
## a horse's mouth IS the interaction.
func _lasso_step(delta: float) -> void:
	if _lassoed != null and (not is_instance_valid(_lassoed) or not _lassoed.is_restrained()):
		# It broke the rope, died, or its chunk unloaded.
		_lassoed = null
		_tie_anchor = null

	var pressed := (
		Input.is_action_pressed("lasso") if _controlled_locally() else _pending_lasso_pressed
	)
	var just_pressed := pressed and not _last_lasso_input
	_last_lasso_input = pressed

	if just_pressed and _held_capture_tool_id() != "":
		perform_rope_verb()

	_capture_result_timer = maxf(0.0, _capture_result_timer - delta)
	_hold_the_rope(delta)
	_draw_rope()
	_mount_input_step()
	_step_mount_and_orders()
	_step_bonded_companions(delta)
	_update_lasso_message()


## Keeps the rope attached: the anchor is pushed to the animal every frame, so
## "leading" is nothing more than an anchor that walks with the player.
func _hold_the_rope(_delta: float) -> void:
	if _lassoed == null or not is_instance_valid(_lassoed):
		return
	# Tied vs led: a tied animal is one the player deliberately left somewhere,
	# and is kept across a chunk unload on that basis (see KeptAnimals).
	_lassoed.restrain_to(
		_tie_anchor if _tie_anchor != null else position, _tie_anchor != null
	)


## What the rope key does right now: cycle a tamed animal's orders, throw,
## tie, untie, or let go -- whichever the current situation means.
##
## Extracted from _lasso_step so the ACTION SLOTS can reach the same verb.
## They used to call _lasso_step itself, which re-reads the lasso key: the slot
## press found that key not held, did nothing, and the prompt went on
## advertising a verb that never happened. A second way to reach an action must
## not be a second copy of it.
func perform_rope_verb() -> void:
	if _lassoed == null and _nearest_tamed(LASSO_RANGE) != null:
		# Already tamed: the rope has nothing left to do, so the key means
		# "change your mind about what you're doing" instead.
		_cycle_order()
	elif _lassoed == null:
		_throw_capture_tool()
	elif _tie_anchor != null:
		_tie_anchor = null
	else:
		var tree = _nearest_tie_point()
		if tree != null:
			_tie_anchor = tree
		else:
			_lassoed.release()
			_lassoed = null


## Offers the treat in hand to `animal`.
##
## A GESTURE, not a proximity effect. This used to fire from _lasso_step every
## frame whenever a carrot sat in the bag and the animal was in range -- so the
## relationship the whole mechanic rests on reduced, in play, to standing still
## next to a horse (see docs/concept/taming.md, "feeding as an offer that can
## be refused"). Now the player holds the food out and presses.
##
## Consumed only when it counts (see CreatureMarker.feed_treat, which refuses a
## feed the animal is not hungry for), so a full animal never eats the stock.
## Returns whether anything was actually taken.
func offer_treat_to(animal) -> bool:
	if animal == null:
		return false
	if position.distance_to(animal.position) > FEED_RANGE:
		return false

	# The HAND first, then the bag -- and "the hand" itself checks BOTH hand
	# concepts (see _held_out_item_id's own doc comment for why there are two).
	#
	# Reported, twice. First: "Carrots never end up in the inventory with a
	# carrot in hand" -- fixed by spending equipped_item first instead of only
	# ever draining the bag. Then again, live, after that fix had shipped:
	# "carrots or potatoes... never make it into the inventory to feed horse" --
	# because a pulled carrot never actually reaches equipped_item at all
	# (equip_item() refuses food-kind items outright, see its own kind gate);
	# it reaches _hand_item_stack via _try_pick_item_into_hand, a field the
	# first fix never checked. Every existing test simulated "a carrot in hand"
	# by poking equipped_item directly, which is not a place a real pickup can
	# ever put a carrot, so the gap shipped invisibly.
	#
	# Hand before bag because a player holding a carrot out is offering THAT
	# carrot -- draining the bag instead would leave the held one sitting there.
	var holding_in_hand_stack: bool = (
		_hand_item_stack != null and _hand_item_stack.item.id == TAMING_TREAT_ID
	)
	var holding_equipped: bool = (
		not holding_in_hand_stack
		and equipped_item != null
		and equipped_item.id == TAMING_TREAT_ID
	)
	var holding_treat := holding_in_hand_stack or holding_equipped
	if not holding_treat and inventory != null and inventory.count_of(TAMING_TREAT_ID) > 0:
		pass
	elif not holding_treat:
		return false

	# Ask BEFORE spending: feed_treat refuses an animal that is not hungry (see
	# CreatureMarker.feed_treat / Taming.trust_after_feeding), and a refused
	# offer must cost nothing.
	if not animal.feed_treat():
		return false

	if holding_in_hand_stack:
		_hand_item_stack.count -= 1
		if _hand_item_stack.count <= 0:
			_hand_item_stack = null
	elif holding_equipped:
		equipped_item = null
		inventory_changed.emit()
	else:
		inventory.remove(TAMING_TREAT_ID, 1)
	return true


## The item id the player is effectively "holding out" for an animal-facing
## gesture like Feed -- read by both animal_actions_for and offer_treat_to,
## which each used to ask `equipped_item` alone.
##
## Two different fields can each be "the hand", depending on how the item got
## there: `equipped_item` (Player.equip_item() -- a weapon/tool activated
## from the hotbar/inventory, drawn as the wielded item) or `_hand_item_stack`
## (Player._try_pick_item_into_hand() -- the contextual E-pickup hand a
## dropped object with real mass goes into, see docs/concept/wild_crops.md).
## A carrot/potato can only ever reach the second: equip_item() explicitly
## refuses anything that isn't a weapon/tool, so "food in equipped_item" is
## structurally impossible through ordinary play -- yet a pulled wild carrot
## ALWAYS goes through the hand-item path now that it has a real mass
## (ItemCatalog._PRODUCE_MASS_KG). Reported live: "carrots or potatoes...
## never make it into the inventory to feed horse" -- traced to exactly this:
## the two hand concepts were never unified, so the one a real carrot pickup
## actually populates was never checked. Hand-item wins when both happen to
## be set, matching offer_treat_to's own "hand before bag" priority -- a
## player who just picked something up to offer it is not also coincidentally
## offering a drawn weapon instead.
func _held_out_item_id() -> String:
	if _hand_item_stack != null:
		return _hand_item_stack.item.id
	if equipped_item != null:
		return equipped_item.id
	return ""


## The ordered actions this player can take on `animal` right now -- index 0 is
## the primary, 1 the secondary (see AnimalActions.for_animal). Public so the
## HUD and the tests can ask the same question the input router answers.
func animal_actions_for(animal) -> Array:
	if animal == null or not animal.has_method("animal_state"):
		return []
	return AnimalActions.for_animal(animal.animal_state(), _held_out_item_id())


## Carries out whichever slot the player pressed on `animal`.
##
## Routes into the SAME handlers the dedicated keys use rather than
## reimplementing any verb -- the slot is a second way to reach an action, not
## a second copy of it, so the two can never drift into doing different things.
func _perform_animal_action(animal, slot: int) -> void:
	var actions := animal_actions_for(animal)
	if slot < 0 or slot >= actions.size():
		return
	match actions[slot]["verb"]:
		"Feed":
			offer_treat_to(animal)
		"Ride":
			_try_mount()
		"Order":
			_cycle_order()
		"Release", "Lasso":
			perform_rope_verb()


## The animal the action slots act on: whatever is already on the rope, else
## the nearest one in reach. The rope wins because an animal you are HOLDING is
## unambiguously the one you meant, even when a curious sheep wanders closer.
func _action_target():
	if _lassoed != null and is_instance_valid(_lassoed):
		return _lassoed
	var best: Node = null
	var best_distance := LASSO_RANGE
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info == null:
			continue
		var distance := position.distance_to(creature.position)
		if distance <= best_distance:
			best = creature
			best_distance = distance
	return best


## The two context slots (see Keybindings' primary_action/secondary_action).
func _action_slots_step() -> void:
	for slot in AnimalActions.MAX_SLOTS:
		var action_name: String = AnimalActions.SLOT_ACTIONS[slot]
		var pressed := (
			_controlled_locally()
			and InputMap.has_action(action_name)
			and Input.is_action_pressed(action_name)
		)
		var was_pressed: bool = _last_slot_input[slot]
		if _rising_edge(action_name, pressed, was_pressed):
			_perform_context_action(slot, action_name)
		_last_slot_input[slot] = pressed


## Whichever action `slot` currently offers: the hover-verb path
## (AnimalActions, on whatever is under the player -- Feed/Ride/Order/
## Release) if it has something to say for this slot, else the held tool's
## own self-action (CaptureItemActions -- e.g. "Put into bottle", which
## needs no hover target at all) as a fallback (docs/concept/capture_dsl.md).
## The hover path always wins when it offers anything, so this never changes
## Feed/Ride/Order/Release's existing behavior.
func _perform_context_action(slot: int, action_name: String) -> void:
	var animal = _action_target()
	if slot < animal_actions_for(animal).size():
		_perform_animal_action(animal, slot)
		return
	# An EMPTY bottle: one already holding a creature is not somewhere to put
	# a second one (see _bottle_captive).
	var has_bottle := inventory != null and inventory.has("glass_bottle", "")
	var tool_action := CaptureItemActions.for_tool(equipped_item, has_bottle)
	if tool_action.get("action", "") == action_name:
		_bottle_captive()


## Throws whichever capture tool is held (see docs/concept/taming.md's "Any
## animal, the right tool"). Branches because a butterfly net scans a wholly
## different node group and resolves instantly rather than starting a
## struggle -- see _throw_net's own doc comment.
func _throw_capture_tool() -> void:
	var tool_id := _held_capture_tool_id()
	if tool_id == "":
		return
	if tool_id == CaptureTool.NET:
		if equipped_item != null and equipped_item.is_holding_captive():
			_release_net()
		else:
			_throw_net()
	else:
		_throw_rope_tool(tool_id)


## Lasso/snare/trap: the original struggle-and-lead loop, generalized to
## whichever of those three is actually held rather than a hardcoded lasso.
func _throw_rope_tool(tool_id: String) -> void:
	var best: Node = null
	var best_distance := LASSO_RANGE
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info == null or creature.is_restrained():
			continue
		if not Taming.can_be_tamed(creature.info.species, tool_id):
			continue
		var distance := position.distance_to(creature.position)
		if distance <= best_distance:
			best = creature
			best_distance = distance
	if best == null:
		return
	# The throw itself reuses the melee swing, the same way casting a rod does.
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)
	if best.restrain_to(position, false, skill_bonus("taming_affinity"), tool_id):
		_lassoed = best


## How close to a netted fish's own position catch_nearest_fish looks for
## the marker to take out of the water: the target is AT that position, so
## this only has to be wider than floating-point noise, never wide enough to
## take a neighbour instead.
const NET_FISH_TAKE_RADIUS := 1.0


## Netting is a real probability roll, not a struggle and not a guarantee
## (docs/concept/capture_dsl.md: nothing in AmbientFlyerMarker models a
## butterfly fighting a restraint the way a horse does, so there is no
## multi-bout contest -- but a swing can still miss). A landed throw goes for
## the NEAREST net target: an ambient flyer (a wholly separate node group
## from CreatureMarker.GROUP_NAME) or, since 2026-09-05, a fish in the
## shallows -- found through the same nearest-fish lookup a hunting
## kingfisher uses -- and resolves through _attempt_net_catch. Which of them
## the net can actually HOLD is the net's own mesh physics, not this
## function's business.
func _throw_net() -> void:
	var best: Node = null
	var best_distance := LASSO_RANGE
	for flyer in get_tree().get_nodes_in_group(AmbientFlyerMarker.FLOCK_GROUP):
		if not is_instance_valid(flyer) or flyer.is_queued_for_deletion():
			continue
		var distance := position.distance_to(flyer.position)
		if distance <= best_distance:
			best = flyer
			best_distance = distance
	if _chunk_manager != null:
		var fish = _chunk_manager.nearest_fish_position(position, best_distance)
		if fish != null and is_instance_valid(fish) and not fish.is_queued_for_deletion():
			best = fish
	if best == null:
		return
	_character_view.play_attack_swing(_facing_string(), SWING_DURATION)
	_attempt_net_catch(best)


## Resolves a landed net throw against `target` -- a flyer or a fish --
## through the net's own device text (docs/concept/capture_dsl.md):
## `mesh_holds(mesh: bag)` first, which reads the bag's real 10 mm mesh and
## 30 cm mouth off the net's part facts and the subject's measured body
## extents (BodyDimensions) and refuses WITH A REASON a bee that slips
## through or a koi that does not fit; then `catch_roll` (base 0.65, nudged
## by a flyer's own real, DNA-inherited FlyerPersonality.boldness_of -- a
## bolder flyer is easier to net; a fish has no personality and rolls at
## the middling default); then `confine(in: bag)`.
##
## The roll is salted with _capture_attempt_count, not just the target's
## wander_seed alone -- a bare-seed roll would make every retry against the
## same still-alive target land on the identical outcome forever, silently
## making one miss unwinnable.
##
## A mesh refusal shows its reason ("The bee slips through the 10 mm
## mesh."); a lost roll shows "Missed!"; either way nothing changes -- a
## flyer's own existing flee/dance reaction (FlyerPersonality.player_
## response) keeps running untouched. On a catch: see docs/concept/
## taming.md's "A bond, not an order: the Kinship path" -- an ambient flyer
## with `menagerie` unlocked (and room under the cap) becomes a real bonded
## companion instantly, exactly as before; a fish never bonds (nothing that
## lives in water follows you across a meadow); otherwise the net itself
## goes LOADED (Item.captive_species) and the player chooses Release or
## (with a glass bottle) Put into bottle. The subject leaves the world
## either way: a flyer is freed, a fish is taken through the rod's own
## catch_nearest_fish so its pond's real population records the harvest.
func _attempt_net_catch(target: Node) -> void:
	var species: String = target.species
	# By class, not by group: a marker joins its group in _ready, which a
	# node outside the tree never runs, and "is this a fish" must not depend
	# on where the node happens to sit.
	var is_fish: bool = target is FishMarker
	var traits = target.get("traits")
	var boldness: float = FlyerPersonality.MIDDLING_BOLDNESS
	if traits is Dictionary:
		boldness = FlyerPersonality.boldness_of(traits)
	var rule: Variant = _capture_executor.capture_rule(_capture_book.ast_for(CaptureTool.NET))
	_capture_attempt_count += 1
	var roll := float(absi(hash("%d_%d_catch" % [target.wander_seed, _capture_attempt_count])) % 10000) / 10000.0
	var context := {"target": {
		"species": species,
		"boldness": boldness,
		"extents_mm": BodyDimensions.extents_mm(species),
	}}
	context.merge(_capture_book.facts_for(CaptureTool.NET))
	var result := _capture_executor.resolve_catch(rule, context, roll)
	if not result["caught"]:
		var reason: String = result["reason"]
		_capture_result_message = "Missed!" if reason == "" else _as_sentence(reason)
		_capture_result_timer = CAPTURE_RESULT_MESSAGE_DURATION
		return
	if not is_fish and _has_menagerie() and _bond_companion(species):
		_capture_result_message = "Bonded with the %s." % species.capitalize()
	else:
		for effect in result["effects"]:
			_capture_atom_effects.apply_to_target(effect["atom"], effect["params"], equipped_item, context)
		_capture_result_message = "Caught! Net is full."
	_capture_result_timer = CAPTURE_RESULT_MESSAGE_DURATION
	if is_fish:
		_chunk_manager.catch_nearest_fish(target.position, NET_FISH_TAKE_RADIUS)
	else:
		target.queue_free()


## "the bee slips through the 10 mm mesh" -> "The bee slips through the 10 mm
## mesh." -- a reason is prose the executor phrased around its subject; the
## HUD just capitalises and closes it.
func _as_sentence(reason: String) -> String:
	if reason == "":
		return ""
	return reason[0].to_upper() + reason.substr(1) + "."


## Empties a loaded net, letting its catch go (docs/concept/capture_dsl.md's
## "on release" -- free(from: bag)). Deliberately does not respawn a live
## creature back into the world -- a documented, honest gap, not attempted
## here (see capture_dsl.md's Open questions).
func _release_net() -> void:
	if equipped_item == null or not equipped_item.is_holding_captive():
		return
	var species := equipped_item.captive_species
	var rule: Variant = _capture_executor.release_rule(_capture_book.ast_for(CaptureTool.NET))
	var result := _capture_executor.resolve_release(rule, {})
	if not result["released"]:
		return
	for effect in result["effects"]:
		_capture_atom_effects.apply_to_target(effect["atom"], effect["params"], equipped_item, {})
	_capture_result_message = "Released the %s." % species.capitalize()
	_capture_result_timer = CAPTURE_RESULT_MESSAGE_DURATION


## "Put into bottle" (docs/concept/capture_dsl.md's "on transfer(glass_bottle)"
## -- move_captive): consumes one EMPTY glass_bottle and relocates a loaded
## net's catch onto a freshly-loaded one (Item.captive_species), the same
## way _attempt_net_catch's confine loads the net in the first place --
## not a generic curiosity item, because the species has to survive the move
## for the bottle to be rendered as the specific creature it holds. See
## CaptureItemActions for when this is even offered -- it never fires unless
## a loaded net AND a glass_bottle are both on hand.
func _bottle_captive() -> void:
	if equipped_item == null or not equipped_item.is_holding_captive():
		return
	if inventory == null or not inventory.has("glass_bottle", ""):
		return
	var rule: Variant = _capture_executor.transfer_rule(_capture_book.ast_for(CaptureTool.NET), "glass_bottle")
	var result := _capture_executor.resolve_transfer(rule, {})
	if not result["transferred"]:
		return
	var species := ""
	for effect in result["effects"]:
		var outcome = _capture_atom_effects.apply_to_target(effect["atom"], effect["params"], equipped_item, {})
		if outcome is String and outcome != "":
			species = outcome
	if species == "":
		return
	# Spend an EMPTY bottle, never a loaded one -- with a loaded bottle and
	# an empty one both in the pack, an unfiltered remove could take the
	# loaded one and set its creature loose to make room for this one.
	inventory.remove("glass_bottle", 1, "")
	var loaded_bottle: Item = _item_catalog.make("glass_bottle")
	loaded_bottle.captive_species = species
	inventory.add(loaded_bottle, 1)
	_capture_result_message = "Bottled the %s." % species.capitalize()
	_capture_result_timer = CAPTURE_RESULT_MESSAGE_DURATION


## Beastmaster's `menagerie` keystone (docs/concept/taming.md's Kinship path
## / skills.md). Checked against BOTH unlocked_keystones (the shape land_
## sense/berserkers_fury/etc. use, via unlock_keystone -> KeystonePassive)
## and allocated_nodes (the shape `menagerie` actually lives in TODAY:
## skill_web.gd's beastmaster wedge already grants it a real taming_affinity
## bonus directly via ordinary allocate_skill, and it is not currently
## registered in KeystonePassive._KEYSTONES the way the other four keystones
## are -- see this lane's own HANDOFF note on the divergence). Reading both
## keeps this correct regardless of which mechanism ends up hosting
## menagerie's capability grant.
func _has_menagerie() -> bool:
	return unlocked_keystones.get("menagerie", false) or allocated_nodes.get("menagerie", false)


## Adds a new bonded companion for `species` if there is room (see
## BONDED_COMPANION_CAP), spawning its live marker immediately. Returns
## false, doing nothing, once the cap is reached -- _attempt_net_catch then
## falls back to loading the net instead of silently discarding the catch.
func _bond_companion(species: String) -> bool:
	if bonded_companions.size() >= BONDED_COMPANION_CAP:
		return false
	var entry := {"species": species}
	bonded_companions.append(entry)
	_spawn_bonded_marker(entry)
	return true


## A bonded companion's live node (see BondedCompanionMarker) -- a lightweight
## Node2D, NOT a CreatureMarker: no trust/order/struggle state, since a
## netted flyer never had an order AI to learn Follow/Stay in the first
## place. `top_level` so it renders/moves in world space rather than
## inheriting the player's own transform, the same reason the rope Line2D is.
func _spawn_bonded_marker(entry: Dictionary) -> void:
	var marker := BondedCompanionMarker.new()
	marker.species = entry.get("species", "")
	marker.wander_seed = hash(str(entry.get("species", "")) + str(_bonded_markers.size()))
	marker.top_level = true
	marker.position = position
	add_child(marker)
	marker.setup(_chunk_manager, _tile_size)
	_bonded_markers.append(marker)


## Pushes each bonded companion a spot to loosely trail toward, spread
## around the player rather than stacking on one point -- fixed offsets
## rather than a physically-simulated flock, which is plenty for a
## decorative presence (see docs/concept/pets.md). The actual gated
## movement happens in the marker's own _process, the same split
## _step_mount_and_orders uses for a tamed animal's follow_target.
func _step_bonded_companions(_delta: float) -> void:
	for i in range(_bonded_markers.size()):
		var marker = _bonded_markers[i]
		if not is_instance_valid(marker):
			continue
		var angle := float(i) * TAU / float(BONDED_COMPANION_CAP)
		marker.follow_target = (
			position + Vector2(cos(angle), sin(angle)) * BONDED_COMPANION_TRAIL_RADIUS
		)


## The nearest tree trunk worth tying off to. Trees are already solid bodies
## in the world (ChoppableTree), so "tie it to that one" needs no new entity.
func _nearest_tie_point():
	if _chunk_manager == null or not _chunk_manager.has_method("solid_obstacles_near"):
		return null
	var nearest = null
	var best := TIE_RANGE
	for obstacle in _chunk_manager.solid_obstacles_near(position, TIE_RANGE):
		var distance := position.distance_to(obstacle.position)
		if distance <= best:
			nearest = obstacle.position
			best = distance
	return nearest


## The banner line for whatever the rope is currently doing.
##
## Every branch names the KEY it wants pressed rather than the action's name.
## The old first line read "press the lasso key", which is not a key any
## keyboard has -- reported live, and the player had to go and find it in the
## settings screen to use the verb the game was telling them to use. Read off
## the live InputMap (Keybindings.display_key_for) so a rebind shows at once.
##
## Each line also says what the animal NEEDS, because that is the thing that
## decides what the player should do next and it was previously invisible: a
## tied animal that is not hungry cannot be fed toward trust at all (see
## Taming.trust_after_feeding), so "wait until it is hungry" is real, useful
## information rather than flavour.
func _update_lasso_message() -> void:
	var tool_id := _held_capture_tool_id()
	if tool_id == "":
		lasso_message = ""
		return
	var lasso_key := Keybindings.display_key_for("lasso")
	if tool_id == CaptureTool.NET:
		# A net has nothing to hold or lead -- a catch/release/bottle attempt
		# resolves in one frame (see _attempt_net_catch/_release_net/
		# _bottle_captive), so the result banner it set outlives this
		# same-frame call via _capture_result_timer rather than being
		# stomped straight back to the ready prompt.
		if _capture_result_timer > 0.0:
			lasso_message = _capture_result_message
		else:
			lasso_message = "Net ready — press %s near a flyer." % lasso_key
		return
	if _lassoed == null:
		var tool_name: String = _item_catalog.make(tool_id).display_name
		lasso_message = "%s ready — press %s near an animal." % [tool_name, lasso_key]
		return

	var name_text: String = _lassoed.info.display_name if _lassoed.info != null else "Animal"
	if _lassoed.is_tame():
		var orders := []
		if Taming.can_be_mounted(_lassoed.info.species if _lassoed.info != null else ""):
			orders.append("%s to ride" % Keybindings.display_key_for("mount"))
		orders.append("%s to change its orders" % lasso_key)
		lasso_message = "%s is tame — %s." % [name_text, ", ".join(orders)]
		return

	var trust_text := "trust %d%%" % int(_lassoed.trust * 100.0)
	var need_text := (
		"hungry, feed it" if _lassoed.is_hungry() else "not hungry yet — feeding won't help"
	)
	if _tie_anchor != null:
		lasso_message = "%s tied up — %s, %s (%s to untie)" % [
			name_text, trust_text, need_text, lasso_key
		]
	else:
		lasso_message = "Leading %s — %s, %s (%s to tie it to a tree)" % [
			name_text, trust_text, need_text, lasso_key
		]


## The rope, drawn between whatever holds it and the animal. Without it,
## "this animal is on a line" is something the player has to infer from
## behaviour -- and flora.md's rule that what is visible must be what is real
## cuts both ways: a real constraint should be visible.
##
## Deliberately `top_level`, so the line is drawn in world coordinates rather
## than inheriting the player's own transform (the same reason the creature
## health bars are).
const ROPE_COLOR := Color(0.78, 0.68, 0.42)
const ROPE_WIDTH := 1.5
var _rope_line: Line2D


func _build_rope_line() -> void:
	_rope_line = Line2D.new()
	_rope_line.top_level = true
	_rope_line.width = ROPE_WIDTH
	_rope_line.default_color = ROPE_COLOR
	_rope_line.visible = false
	_rope_line.z_index = 1
	add_child(_rope_line)


func _draw_rope() -> void:
	if _rope_line == null:
		return
	if _lassoed == null or not is_instance_valid(_lassoed):
		_rope_line.visible = false
		return
	var held_end: Vector2 = _tie_anchor if _tie_anchor != null else global_position
	_rope_line.visible = true
	_rope_line.points = PackedVector2Array([held_end, _lassoed.global_position])


# -- orders and riding --------------------------------------------------------

## How fast the player is moving right now: their own legs, or the mount's --
## and the mount's own individual fitness (see Taming.mounted_speed_for),
## not one flat speed shared by every horse regardless of which one is
## actually under the saddle.
func current_speed() -> float:
	return Taming.mounted_speed_for(_mount_fitness_score()) if is_mounted() else BASE_SPEED


## The current mount's fitness_score (see AnimalFitness), read from its own
## wander_seed so the exact same individual always rides at the exact same
## speed. Falls back to the population median (0.5, i.e. the flat
## Taming.MOUNTED_SPEED baseline) if somehow mounted on something with no
## wander_seed of its own -- current_speed() is called every physics frame
## and must never fail outright over a missing field on an unusual mount.
func _mount_fitness_score() -> float:
	if _mount == null or not ("wander_seed" in _mount):
		return 0.5
	return _fitness.fitness_score(_fitness.phenotype_for(_mount.wander_seed))


func is_mounted() -> bool:
	return _mount != null and is_instance_valid(_mount)


## Cycles the nearest tamed animal between following and staying put. A wild
## animal ignores it (see CreatureMarker.set_order).
func _cycle_order() -> void:
	var animal = _nearest_tamed(LASSO_RANGE)
	if animal == null:
		return
	animal.set_order(Taming.next_order(animal.order))


func _try_mount() -> bool:
	if is_mounted():
		return false
	var animal = _nearest_tamed(LASSO_RANGE)
	if animal == null or animal.info == null:
		return false
	if not Taming.is_mountable(animal.info.species, animal.trust):
		return false
	_mount = animal
	return true


func _dismount() -> void:
	_mount = null


## The nearest fully tamed animal within `reach`. Tamed only: orders and
## riding are things a tamed animal accepts, and a wild horse standing nearby
## must not silently absorb the key press meant for the tamed one.
func _nearest_tamed(reach: float):
	var best = null
	var best_distance := reach
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info == null or not creature.is_tame():
			continue
		var distance := position.distance_to(creature.position)
		if distance <= best_distance:
			best = creature
			best_distance = distance
	return best


## Keeps a mount under its rider, and tells a following animal where its owner
## is. Both are "push the owner's position in each frame" rather than the
## animal holding a reference back to the player, matching how the rope anchor
## works.
func _step_mount_and_orders() -> void:
	if is_mounted():
		_mount.position = position
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info != null and creature.is_tame():
			creature.follow_target = position


func _mount_input_step() -> void:
	var pressed := (
		Input.is_action_pressed("mount") if _controlled_locally() else _pending_mount_pressed
	)
	var just_pressed := pressed and not _last_mount_input
	_last_mount_input = pressed
	if not just_pressed:
		return
	if is_mounted():
		_dismount()
	else:
		_try_mount()


## Which capture tool (see docs/concept/taming.md's "Any animal, the right
## tool") is currently held, or "" if the equipped item isn't one. The
## generalization of what used to be a single hardcoded "== lasso" check.
func _held_capture_tool_id() -> String:
	if equipped_item != null and CAPTURE_TOOL_IDS.has(equipped_item.id):
		return equipped_item.id
	return ""


func _has_fishing_rod() -> bool:
	return _inventory_counts().get("fishing_rod", 0) > 0


## True if any cardinal neighbor tile is open water (ocean) -- you fish from the
## shore, not from on top of the water.
func _near_water() -> bool:
	if _chunk_manager == null:
		return false
	var tile := current_tile()
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _chunk_manager.biome_at_global(tile.x + offset.x, tile.y + offset.y) == "ocean":
			return true
	return false


## Authority-only: press the trade key next to a merchant villager (see
## EarthChunkManager.has_merchant_near) to buy one item from Shop.CATALOG,
## cycling through it each successful purchase so repeated presses don't just
## buy the same cheapest thing forever. The HUD reads trade_message.
func _shop_step(delta: float) -> void:
	var trade_pressed := (
		Input.is_action_pressed("trade") if _controlled_locally() else _pending_trade_pressed
	)
	# has_action guard, the same one _unhandled_input carries and for the same
	# reason: there is no static [input] section in project.godot (World
	# registers the map at runtime), so a Player stepped in isolation can
	# legitimately be running before every action exists. Reading an
	# unregistered action is an engine error per frame, not a false.
	var sell_pressed := (
		(_controlled_locally() and InputMap.has_action("sell") and Input.is_action_pressed("sell"))
		if _controlled_locally()
		else _pending_sell_pressed
	)
	if _rising_edge("sell", sell_pressed, _last_sell_input):
		_last_sell_input = sell_pressed
		if _chunk_manager != null and _chunk_manager.has_merchant_near(position, TRADE_RADIUS):
			_attempt_a_sale()
		else:
			_trade_result_message = "No merchant nearby to sell to."
		_trade_result_timer = TRADE_MESSAGE_DURATION
	_last_sell_input = sell_pressed

	var just_pressed := _rising_edge("trade", trade_pressed, _last_trade_input)
	_last_trade_input = trade_pressed
	if just_pressed:
		if _chunk_manager != null and _chunk_manager.has_merchant_near(position, TRADE_RADIUS):
			_attempt_a_purchase()
		else:
			# No merchant in reach -- fall back to selling real gathered food
			# into a nearby villager's own VillageMarket (see
			# _attempt_village_food_sale), rather than the flat "No merchant
			# nearby." this branch used to be unconditionally.
			_attempt_village_food_sale()
		_trade_result_timer = TRADE_MESSAGE_DURATION

	_trade_result_timer = maxf(0.0, _trade_result_timer - delta)
	trade_message = _trade_result_message if _trade_result_timer > 0.0 else ""


## Tries each item in Shop.CATALOG in turn, starting from _trade_attempt_count
## (so repeated purchases cycle through the catalog rather than always
## re-buying the first affordable item), and buys the first one the wallet
## can afford.
func _attempt_a_purchase() -> void:
	# The price is the LOCAL price, from the real market of the settlement this
	# merchant belongs to (see EarthChunkManager.merchant_market_near and
	# Shop.market_price_of) -- a shortage here costs more here, and buying
	# draws the item out of that village's own stock. Null when the merchant
	# has no settlement behind them, which falls back to the flat catalog.
	var market = _chunk_manager.merchant_market_near(position, TRADE_RADIUS) \
		if _chunk_manager != null else null
	var item_ids := _shop.known_item_ids()
	for offset in item_ids.size():
		var item_id: String = item_ids[(_trade_attempt_count + offset) % item_ids.size()]
		# Read the price BEFORE buying: the purchase itself moves the stock,
		# and therefore the price, so asking afterwards would report the next
		# customer's price rather than the one just paid.
		var paid := _shop.market_price_of(item_id, market)
		if _shop.buy(wallet, inventory, _item_catalog, item_id, market):
			_trade_attempt_count += 1
			inventory_changed.emit()
			_trade_result_message = "Bought %s for %d gold." % [
				_item_catalog.make(item_id).display_name, paid
			]
			return
	_trade_result_message = "Not enough gold."


## Sells one unit of the first thing in the player's bag this merchant
## actually deals in, at the local price (see Shop.sell_price_of).
##
## The other half of concept/economy.md's "Selling to the market" faucet, and
## the point at which what the player produces becomes a strategy rather than
## a number: the sale goes into the same real market buying draws from, so it
## pushes that village's stock UP and what it will pay for the next one DOWN.
## Carrying a glut somewhere short of it is the play.
##
## A merchant only buys what they deal in — `Item` carries no value field, so
## `Shop.CATALOG` is the only place an item has a price at all (see
## Shop.sell_price_of).
func _attempt_a_sale() -> void:
	var market = _chunk_manager.merchant_market_near(position, TRADE_RADIUS) \
		if _chunk_manager != null else null
	for item_id in _shop.known_item_ids():
		if not inventory.has(item_id):
			continue
		# Read the price BEFORE selling: the sale itself adds stock, and
		# therefore lowers the price, so asking afterwards would report the
		# next seller's price rather than the one just paid.
		var paid := _shop.sell_price_of(item_id, market)
		if _shop.sell(wallet, inventory, item_id, market):
			inventory_changed.emit()
			_trade_result_message = "Sold %s for %d gold." % [
				_item_catalog.make(item_id).display_name, paid
			]
			return
	_trade_result_message = "Nothing here they want to buy."


## Fallback for the trade key when no merchant is near: sells one unit of the
## player's own gathered food into the nearest real villager's own
## VillageMarket (see sell_food_to_village, docs/concept/npc.md "Local trade
## is NPC-to-NPC, not just player-to-shop" -- extended here to cover a
## player-initiated sale) -- a real XP bonus if that village was genuinely
## hungry (see EcologicalLiteracy, docs/concept/progression.md "Ecological
## literacy"). Unchanged fallback message when there is truly nobody nearby
## at all (no merchant AND no villager), matching this branch's original
## behaviour before this feature existed.
func _attempt_village_food_sale() -> void:
	var npc = _chunk_manager.nearest_npc_near(position, TRADE_RADIUS) if _chunk_manager != null else null
	if npc == null or npc.economy == null:
		_trade_result_message = "No merchant nearby."
		return
	var item_id := _first_food_item_id()
	if item_id == "":
		_trade_result_message = "No food to sell."
		return
	sell_food_to_village(npc.economy.market, item_id, 1)
	_trade_result_message = "Sold %s to the village." % _item_catalog.make(item_id).display_name


## The first food item id the player is carrying (by inventory_counts()
## iteration order), or "" if none -- what _attempt_village_food_sale sells
## when the player doesn't name a specific item.
func _first_food_item_id() -> String:
	for item_id in inventory_counts():
		if _item_catalog.kind_of(item_id) == "food":
			return item_id
	return ""


## Sells `amount` of `item_id` from inventory into `market`'s real per-
## village food stock (see VillageMarket). Real XP bonus (see
## EcologicalLiteracy) only when the market was GENUINELY hungry right
## before the sale -- VillageMarket.can_buy_meal() already means exactly
## that ("could a hungry villager buy a meal from this stock right now"), so
## "hungry" reuses that real boolean rather than an invented stock
## threshold. No gold changes hands: VillageMarket has no village-side
## wallet to pay from (see its own doc comment -- it's fed by NPC
## production, not player commerce), and the reward for feeding a real
## hungry settlement is the XP itself, not a shop transaction. Returns
## false (no-op) if the player doesn't actually carry `amount` of the item.
func sell_food_to_village(market, item_id: String, amount: int) -> bool:
	if amount <= 0 or inventory.count_of(item_id) < amount:
		return false
	var was_hungry: bool = not market.can_buy_meal()
	inventory.remove(item_id, amount)
	inventory_changed.emit()
	market.add_stock(item_id, float(amount))
	gain_experience(_ecological_literacy.village_sale_xp(was_hungry))
	return true


## Authority-only: press the talk key next to any villager (see
## EarthChunkManager.nearest_npc_near) to hear that NPC's own deterministic
## greeting line (see NpcGreeting) -- the minimal talk-interaction stand-in,
## not the real Live Dialogue System. The HUD reads talk_message.
func _talk_step(delta: float) -> void:
	var talk_pressed := (
		Input.is_action_pressed("talk") if _controlled_locally() else _pending_talk_pressed
	)
	var just_pressed := _rising_edge("talk", talk_pressed, _last_talk_input)
	_last_talk_input = talk_pressed
	if just_pressed:
		var npc = _chunk_manager.nearest_npc_near(position, TALK_RADIUS) if _chunk_manager != null else null
		_talk_result_message = (
			_npc_greeting.greeting_for(npc.identity) if npc != null else "No one to talk to nearby."
		)
		_talk_result_timer = TALK_MESSAGE_DURATION

	_talk_result_timer = maxf(0.0, _talk_result_timer - delta)
	talk_message = _talk_result_message if _talk_result_timer > 0.0 else ""


## Authority-only: on the rising edge of the build input, either places the
## armed placeable structure (see _arm_placeable) or -- when nothing is armed
## -- turns the tile the player is facing into bare earth (see
## TerrainRenderer.EARTH_TILE_ID), exactly as before this structure-placement
## feature existed: intentional (Terraria-style terraforming), not a bug,
## build always replaces whatever biome tile is there, grass included.
func _build_step() -> void:
	var build_pressed := (
		Input.is_action_pressed("build") if _controlled_locally() else _pending_build_pressed
	)
	var just_pressed := _rising_edge("build", build_pressed, _last_build_input_state)
	_last_build_input_state = build_pressed

	if not just_pressed or _chunk_manager == null:
		return

	var target := _tile_targeting.facing_tile(current_tile(), _last_facing_direction)

	if _selected_placeable_item != null:
		# A placeable is armed: place it instead of doing bare-earth
		# terraforming -- but only while the player still actually holds one.
		# Running out doesn't silently fall back to terraforming (that would
		# be a surprising bait-and-switch mid-build); it just does nothing
		# until the player restocks or arms something else.
		if _inventory_counts().get(_selected_placeable_item.id, 0) <= 0:
			return
		if _chunk_manager.build_at_global(target.x, target.y, _selected_placeable_item.id):
			# Only consume on a successful placement -- build_at_global
			# returns false if the target chunk isn't loaded or the tile is
			# already occupied by another modification.
			inventory.remove(_selected_placeable_item.id, 1)
			inventory_changed.emit()
		return

	_chunk_manager.build_at_global(target.x, target.y, TerrainRenderer.EARTH_TILE_ID)


## Authority-only: removes a modification from the tile the player is facing,
## on the rising edge of the destroy input. If that modification was a known
## placeable structure (campfire/furnace -- see item_catalog.gd), one unit of
## it is returned to the inventory -- the player is standing right there
## breaking it, no need for a ground-drop node. Destroying plain bare earth
## (today's existing behavior) stays exactly as-is: there's no "earth" item,
## so nothing is given back.
func _destroy_step() -> void:
	var destroy_pressed := (
		Input.is_action_pressed("destroy") if _controlled_locally() else _pending_destroy_pressed
	)
	var just_pressed := _rising_edge("destroy", destroy_pressed, _last_destroy_input_state)
	_last_destroy_input_state = destroy_pressed

	if not just_pressed or _chunk_manager == null:
		return

	var target := _tile_targeting.facing_tile(current_tile(), _last_facing_direction)
	var tile_id := _chunk_manager.modification_at_global(target.x, target.y)
	if not _chunk_manager.destroy_at_global(target.x, target.y):
		return

	if tile_id != "" and _item_catalog.has(tile_id):
		var removed_item := _item_catalog.make(tile_id)
		if removed_item.kind == "placeable":
			inventory.add(removed_item, 1)
			inventory_changed.emit()


## The farming loop's own crop for this slice (docs/concept/farming.md) --
## no seed item/selection UI exists yet (the concept doc's own open
## questions are about cross-breeding UI, not basic seed choice), so
## _plant_step always plants this one crop. Matches an existing catalog
## food item (see item_catalog.gd's "carrot", also grown wild -- farmed and
## wild share one art/DNA model per the concept doc's "Resolved" section).
const FARM_CROP_ID := "carrot"


## Authority-only: the farming loop's contextual till/plant/tend key
## (docs/concept/farming.md's "farming loop") -- same
## one-key-does-the-obvious-thing shape _build_step already uses for its
## own two behaviors. On the rising edge of the plant input: tends (waters)
## the faced tile's plot if a crop is already growing there, otherwise
## tills and plants a fresh one (a no-op if a crop there is already
## "ready" -- see EarthChunkManager.till_and_plant_farm_plot_at_global --
## an unharvested crop is never silently replaced). Harvesting a READY plot
## is deliberately NOT this key -- see _harvest_farm_plot_step, which
## reuses the attack key instead, the same way every other harvest-shaped
## verb (chop/smash/pull/butcher/collect) already does.
func _plant_step() -> void:
	var plant_pressed := (
		Input.is_action_pressed("plant") if _controlled_locally() else _pending_plant_pressed
	)
	var just_pressed := _rising_edge("plant", plant_pressed, _last_plant_input_state)
	_last_plant_input_state = plant_pressed

	if not just_pressed or _chunk_manager == null:
		return

	var target := _tile_targeting.facing_tile(current_tile(), _last_facing_direction)
	if _chunk_manager.water_farm_plot_at_global(target.x, target.y):
		return  # a live crop was already growing there -- tended, not replanted
	_chunk_manager.till_and_plant_farm_plot_at_global(target.x, target.y, FARM_CROP_ID)


## Runs on every non-authority peer's copy of a player (including a client's
## copy of its own avatar): position comes from replication, not local
## simulation. Facing/animation are inferred from how the replicated position
## is actually moving; swim-vs-walk visuals reuse a local, deterministic
## water-depth lookup (safe -- it's not exploitable state) if a chunk manager
## is available, defaulting to a plain walk otherwise.
func _proxy_step() -> void:
	var movement := position - _last_position
	_last_position = position

	if _chunk_manager != null and is_set_up():
		var water_result := _resolve_water_state(current_tile(), get_physics_process_delta_time())
		current_mode = water_result.mode
		current_speed_multiplier = water_result.speed_multiplier
		current_water_depth = water_result.water_depth

	var facing_direction := _last_facing_direction
	if movement.length() > PROXY_MOVEMENT_EPSILON:
		facing_direction = movement.normalized()
	_last_facing_direction = facing_direction

	var display_direction := facing_direction if movement.length() > PROXY_MOVEMENT_EPSILON else Vector2.ZERO
	_update_character_view(display_direction)


func _read_local_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(direction: Vector2) -> void:
	if not is_multiplayer_authority():
		return
	_pending_input_direction = direction


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_attack(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_attack_pressed = pressed


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_cast(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_cast_pressed = pressed


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_build(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_build_pressed = pressed


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_destroy(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_destroy_pressed = pressed


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_plant(pressed: bool) -> void:
	if not is_multiplayer_authority():
		return
	_pending_plant_pressed = pressed


func _resolve_water_state(tile: Vector2i, delta: float) -> Dictionary:
	var elevation := _chunk_manager.elevation_at_global(tile.x, tile.y)
	var ocean_depth := _biome_classifier.depth_meters_at(
		elevation, EarthChunkGenerator.EARTH_SEA_LEVEL, EarthChunkGenerator.EARTH_OCEAN_DEPTH_RANGE_METERS
	)
	# A river never changes elevation/biome_at_global's own result (see
	# docs/concept/rivers.md's "Rendering" section), so ocean_depth above is
	# always 0.0 there -- river_depth_meters_at_global is asked separately,
	# the same way is_river_at_global already is for the dry-land spawn
	# search (World._find_dry_land_spawn).
	var river_depth := _chunk_manager.river_depth_meters_at_global(tile.x, tile.y)
	# Lakes are the third kind of water, asked the same way (see
	# docs/concept/hydrology.md): standing water over untouched land biome.
	var lake_depth := _chunk_manager.lake_depth_meters_at_global(tile.x, tile.y)
	var water_depth := maxf(maxf(ocean_depth, river_depth), lake_depth)

	var submerged := water_depth > 0.0
	wetness = _wetness_tracker.update(wetness, worn_material, submerged, delta)
	var total_weight := body_weight + worn_material.effective_weight(wetness)

	var result := _water_movement_model.resolve(water_depth, total_weight, max_swimmable_weight)
	# The raw depth CharacterView.set_submersion_depth needs -- resolve()'s
	# own mode/speed_multiplier are derived FROM this, but neither carries
	# it back out (mode collapses it to 4 strings, and speed_multiplier's
	# own formula switches to weight-driven once swimming, so depth isn't
	# recoverable from it at all in that regime).
	result["water_depth"] = water_depth
	return result


## Modes in which the player is standing in enough water to disturb it (see
## WaterMovementModel) -- wading counts, not just swimming: sloshing through
## the shallows should ripple exactly as much as a stroke does.
const WATER_RIPPLE_MODES := ["swimming", "wading"]


## Records a water disturbance (see EarthChunkManager.record_water_disturbance)
## while actually moving through water -- water ripples are caused by things
## moving through it, not by wind, so an idle float shouldn't ripple, only
## movement. Throttled to WATER_RIPPLE_INTERVAL rather than every physics tick.
func _step_water_ripples(delta: float, input_direction: Vector2) -> void:
	if not WATER_RIPPLE_MODES.has(current_mode) or input_direction.length() <= 0.01:
		_water_ripple_accumulator = 0.0
		return
	_water_ripple_accumulator += delta
	if _water_ripple_accumulator < WATER_RIPPLE_INTERVAL:
		return
	_water_ripple_accumulator = 0.0
	_chunk_manager.record_water_disturbance(position)


func _update_character_view(input_direction: Vector2) -> void:
	_character_view.set_facing(input_direction)
	_character_view.is_moving = input_direction.length() > 0.01
	_character_view.set_submersion_depth(current_water_depth)
	if current_mode == "swimming":
		_character_view.set_movement_state(CharacterView.MovementState.SWIMMING)
	elif input_direction.length() > 0.01 and current_mode != "drowning":
		_character_view.set_movement_state(CharacterView.MovementState.WALKING)
	else:
		_character_view.set_movement_state(CharacterView.MovementState.IDLE)
	# The same real sun position already driving every creature's silhouette
	# shadow (World sets CreatureMarker.sun_elevation_deg once per frame from
	# it) -- reused rather than a second static/signal just for the player.
	if _shadow != null:
		_shadow.scale.y = DropShadow.stretch_for_elevation(CreatureMarker.sun_elevation_deg)


## Toroidal wrap: walking off any edge of the (finite, real-Earth-sized) world lands on the opposite side.
func _wrap_position() -> void:
	var world_pixel_size := Vector2(
		EarthChunkGenerator.WORLD_WIDTH_TILES * _tile_size, EarthChunkGenerator.WORLD_HEIGHT_TILES * _tile_size
	)
	position.x = fposmod(position.x, world_pixel_size.x)
	position.y = fposmod(position.y, world_pixel_size.y)
