extends Node2D

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const RenderResolution = preload("res://src/rendering/render_resolution.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")
const RainOverlay = preload("res://src/rendering/rain_overlay.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const ConsoleSpecies = preload("res://src/gameplay/console_species.gd")
const EasterEggSightings = preload("res://src/gameplay/easter_egg_sightings.gd")
const EasterEggCreatures = preload("res://src/gameplay/easter_egg_creatures.gd")
const WarGamesResponse = preload("res://src/gameplay/wargames_response.gd")
const BackToTheFutureDay = preload("res://src/gameplay/back_to_the_future_day.gd")
const RushAmbientCue = preload("res://src/gameplay/rush_ambient_cue.gd")
const SecretD20 = preload("res://src/gameplay/secret_d20.gd")
const AncientTerminal = preload("res://src/gameplay/ancient_terminal.gd")
const SignedSecretRoom = preload("res://src/gameplay/signed_secret_room.gd")
const BridgekeeperEncounter = preload("res://src/gameplay/bridgekeeper_encounter.gd")
const ThreeFragmentsHunt = preload("res://src/gameplay/three_fragments_hunt.gd")
const SeaCaveGuardian = preload("res://src/gameplay/sea_cave_guardian.gd")
const JoustMatchView = preload("res://src/rendering/joust_match_view.gd")
const RetroHandheld = preload("res://src/gameplay/retro_handheld.gd")
const HandheldBattleView = preload("res://src/rendering/handheld_battle_view.gd")
const GroundTint = preload("res://src/rendering/ground_tint.gd")
const SeasonalFoliage = preload("res://src/rendering/seasonal_foliage.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SolarPosition = preload("res://src/world/solar_position.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const AnimalActions = preload("res://src/gameplay/animal_actions.gd")
const MinimapRenderer = preload("res://src/rendering/minimap_renderer.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const HealthBar = preload("res://src/gameplay/health_bar.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const DevConsole = preload("res://scenes/dev_console.gd")
const InventoryWindow = preload("res://scenes/inventory_window.gd")
const CraftingWindow = preload("res://scenes/crafting_window.gd")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const CreaturePanel = preload("res://scenes/creature_panel.gd")
const PathScarring = preload("res://src/world/path_scarring.gd")
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")
const Courtship = preload("res://src/gameplay/courtship.gd")
const MammalCourtship = preload("res://src/gameplay/mammal_courtship.gd")
const AnimalFitness = preload("res://src/world/animal_fitness.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")
const SettingsOverlay = preload("res://scenes/settings_overlay.gd")
const LicenseGateOverlay = preload("res://scenes/license_gate_overlay.gd")
const LicenseStore = preload("res://src/licensing/license_store.gd")
const GithubVerifyOverlay = preload("res://scenes/github_verify_overlay.gd")
const GithubDeviceAuth = preload("res://src/licensing/github_device_auth.gd")
const GithubDeviceFlow = preload("res://src/licensing/github_device_flow.gd")
const GithubTokenStore = preload("res://src/licensing/github_token_store.gd")
const MainMenu = preload("res://scenes/main_menu.gd")
const LoadingOverlay = preload("res://scenes/loading_overlay.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const Why = preload("res://src/emergence/why.gd")
const SimulationMetrics = preload("res://src/emergence/simulation_metrics.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const DragSlot = preload("res://src/ui/drag_slot.gd")
const TimeLapse = preload("res://src/gameplay/time_lapse.gd")
const FruitSpoilage = preload("res://src/gameplay/fruit_spoilage.gd")
const EscapeAction = preload("res://src/ui/escape_action.gd")
const PlayerSave = preload("res://src/gameplay/player_save.gd")
const WorldReset = preload("res://src/world/world_reset.gd")
const WorldCoordinates = preload("res://src/world/world_coordinates.gd")
const Compass = preload("res://src/gameplay/compass.gd")
const MapProjection = preload("res://src/world/map_projection.gd")
const Spyglass = preload("res://src/gameplay/spyglass.gd")
const WeatherForecast = preload("res://src/gameplay/weather_forecast.gd")
const SeasonAlmanac = preload("res://src/world/season_almanac.gd")
const FieldJournal = preload("res://src/emergence/field_journal.gd")
const RegionalTrade = preload("res://src/emergence/regional_trade.gd")
const Taming = preload("res://src/gameplay/taming.gd")

## How many hotbar slots the HUD row draws. Derived from Player's own
## hotbar size (see Player.HOTBAR_SLOT_COUNT / Hotbar) rather than duplicated,
## so the drawn row can never silently disagree with the bindable slots.
const HOTBAR_SLOT_COUNT := Player.HOTBAR_SLOT_COUNT
const SPELL_BAR_SLOT_COUNT := 4
const HUD_SLOT_SIZE := 32.0
const HUD_SLOT_BG_COLOR := Color(0.15, 0.15, 0.15, 0.85)
const HUD_SLOT_LOCKED_COLOR := Color(0.08, 0.08, 0.08, 0.6)

## Real seconds between minimap texture refreshes -- sampling thousands of
## tiles every frame would be wasteful; the player doesn't need pixel-perfect
## real-time minimap updates.
const MINIMAP_REFRESH_INTERVAL := 1.0
## Hover tooltip recompute cadence (~30 Hz) -- imperceptible for a tooltip,
## and keeps the (throttled + radius-filtered) hoverable scan off the critical
## per-frame path.
const HOVER_REFRESH_INTERVAL := 0.033
var _hover_accumulator := 0.0

## Interaction-prompt ("Talk"/"Pick") recompute cadence (~13 Hz) -- same
## reasoning and shape as HOVER_REFRESH_INTERVAL just above: this scan chains
## through up to three unbounded linear scans (EarthChunkManager.
## nearest_npc_near, .nearest_liftable_stone_near, Player.
## nearest_kickable_dropped_item_near, see _update_interaction_prompt) every
## time the player isn't already near an NPC or holding something -- the
## common case -- and used to run that chain on literally every frame with no
## throttle at all. A proximity prompt needs nowhere near 60 Hz freshness;
## pinned within the 10-15 Hz band by test_world_interaction_prompt_throttle.gd
## rather than left an eyeballed comment-only value (see CLAUDE.md).
const INTERACTION_PROMPT_REFRESH_INTERVAL := 0.075
var _interaction_prompt_accumulator := 0.0

## Real seconds between Easter-egg sighting checks (docs/concept/
## easter_eggs.md's Mothman/Jersey Devil/Roswell/Area 51 cameos) -- these
## are meant to be rare, atmospheric glimpses, not a per-frame lottery, so
## chance_per_check in EasterEggSightings is calibrated against "a check
## roughly every few seconds while in range", not against frame rate.
const EASTER_EGG_CHECK_INTERVAL := 4.0
## How long a triggered sighting message stays on screen before clearing --
## long enough to read a short line, short enough that it's clearly a
## glimpse, not a persistent HUD element.
const EASTER_EGG_MESSAGE_DURATION := 6.0
## A sighting's ink: cooler and slightly dimmer than UiTheme.TEXT, so an
## ambient glimpse reads as something the WORLD said rather than a result of
## something the player just did. The only per-banner difference in the
## shared message stack (see _build_message_stack).
const EASTER_EGG_MESSAGE_COLOR := Color(0.85, 0.85, 0.95)
var _easter_egg_check_accumulator := 0.0
var _easter_egg_message_timer := 0.0

## How far (px) a triggered creature cameo (Squallmaw/Coilnecca/Champ, see
## EasterEggCreatures) spawns from the player, rather than on top of them --
## first-pass placeholder, same discipline as EASTER_EGG_CHECK_INTERVAL:
## outside melee/interaction range (see CREATURE_PANELS_RADIUS, 220.0 --
## "wider than melee range, meant to cover what's visibly on screen") so it
## reads as spotted at a distance rather than materializing at the player's
## feet, closer than SENSE_RADIUS's release range so it can still be walked
## toward and reacted to like an ordinary creature.
const EASTER_EGG_CREATURE_SPAWN_DISTANCE := 220.0

## How long the ancient-terminal sequence (multiple prose lines joined into
## one banner, see _check_ancient_terminal) stays on screen -- longer than
## EASTER_EGG_MESSAGE_DURATION's single-line glimpses since there is
## genuinely more text to read here.
const ANCIENT_TERMINAL_MESSAGE_DURATION := 12.0
## Same reasoning as ANCIENT_TERMINAL_MESSAGE_DURATION -- the secret room's
## credit line gets its own brief but slightly longer read time than an
## ordinary one-line cameo.
const SIGNED_SECRET_ROOM_MESSAGE_DURATION := 8.0
## docs/concept/easter_eggs.md's "Three Fragments" bonus discovery -- the
## same "slightly longer than a one-line glimpse" reasoning as
## SIGNED_SECRET_ROOM_MESSAGE_DURATION, since ThreeFragmentsHunt.
## BONUS_MESSAGE is a similarly-sized short passage, not a single line.
const THREE_FRAGMENTS_BONUS_MESSAGE_DURATION := 8.0
## The sea cave guardian's challenge + transform lines (docs/concept/
## easter_eggs.md's "hidden sea cave... dueling-birds cabinet" entry) are
## two short passages joined together -- same "genuinely more text to
## read" reasoning as ANCIENT_TERMINAL_MESSAGE_DURATION, and it fires right
## as JoustMatchView's own transform beat begins, so it needs to outlast
## that beat comfortably.
const SEA_CAVE_GUARDIAN_MESSAGE_DURATION := 12.0
## The retro handheld's own found/reopened flavor line (docs/concept/
## easter_eggs.md's "hidden retro handheld" entry) -- a single short line,
## same duration as every other one-line cameo cue.
const RETRO_HANDHELD_MESSAGE_DURATION := EASTER_EGG_MESSAGE_DURATION

## Real seconds between player-state autosaves (see docs/concept/
## persistence.md) -- mirrors the world's own "persist eagerly, not on an
## explicit save action" philosophy (EarthChunkManager saves on chunk
## unload). Frequent enough that a crash never costs more than a short
## interval of progress; infrequent enough that writing a whole save
## Dictionary to disk every frame would be wasteful (same reasoning as
## MINIMAP_REFRESH_INTERVAL above).
const AUTOSAVE_INTERVAL := 60.0

## How far (px) a creature counts as "nearby" for its own HUD panel -- wider
## than melee range, meant to cover what's visibly on screen around the
## player.
const CREATURE_PANELS_RADIUS := 220.0
## Where the shared message stack starts (px from the top of the screen), and
## how wide a banner card may get.
##
## ONE stack, ONE x/y: the taming and trade banners used to be pinned to the
## same hand-picked offset_top of 144 and drew straight through each other.
## The top is the highest of the five old offsets (the fishing banner's 120),
## so nothing moved further down the screen than it already was; the width is
## the widest of them (the Easter-egg banner's 520) rounded down to leave a
## margin at 720p. See _build_message_stack.
const MESSAGE_STACK_TOP := 120.0
const MESSAGE_STACK_WIDTH := 460.0
## Real seconds between creature-panel refreshes -- rebuilding a handful of
## panels a couple times a second is trivial, but this still avoids doing it
## every frame (same reasoning as the minimap/forage/spread throttling).
const CREATURE_PANELS_REFRESH_INTERVAL := 0.5
## Caps how many panels are shown at once (closest first) so a crowded area
## doesn't fill the whole screen with panels.
const MAX_CREATURE_PANELS := 6

## Freiburg im Breisgau -- the Gaskugel landmark on the Dreisam, in the
## Betzenhausen district (48.007669N, 7.805657E per Wikimedia Commons' geo
## tag and OpenStreetMap/Nominatim, which agree to within a few metres).
## Previously Berlin (52.52N, 13.405E); moved 2026-08-29. See
## test_world_spawn_location.gd, including its real-elevation-data check
## that the new point is dry, non-mountain land at least as climate-warm as
## the old Berlin spawn (so mechanics tuned against Berlin's real measured
## climate, e.g. EarthwormPatch.MILD_WARMTH, are not silently re-broken).
const SPAWN_LATITUDE := 48.007669
const SPAWN_LONGITUDE := 7.805657
const SPAWN_SEARCH_RADIUS := 5

const PORT := 8910
const MAX_CLIENTS := 32
const DEFAULT_HOST := "127.0.0.1"

## Launch-time override that pins lighting to full day for a whole session,
## in ANY build: set it to "1" (see always_day_for). There is no longer a
## build-type default for it to opt out of -- debug builds run the same real
## UTC day/night cycle the shipped game does -- so "0" now means what leaving
## it unset means. For pinning a sky while the game is already running, use
## the /day, /night and /time console commands instead.
const DEBUG_ALWAYS_DAY_ENV := "AA_DEBUG_ALWAYS_DAY"
## Sun directly overhead -- sin(90 deg) = 1.0, i.e. maximum sunlight_intensity.
const ALWAYS_DAY_ELEVATION := 90.0
## Sun directly underfoot -- sin(-90 deg) = -1.0, which
## SolarPosition.sunlight_intensity clamps to no light at all. The mirror of
## ALWAYS_DAY_ELEVATION, for /night.
const ALWAYS_NIGHT_ELEVATION := -90.0
## No /time pin in force -- the clock and the sun follow real UTC. Outside
## the [0,24) range any real clock hour lives in, so it can never collide
## with one (see clock_hour_for_console_argument).
const NO_FORCED_HOUR := -1.0

const CONSOLE_TOGGLE_ACTION := "toggle_console"
const INVENTORY_TOGGLE_ACTION := "toggle_inventory"
const CRAFTING_TOGGLE_ACTION := "toggle_crafting"
const SKILLS_TOGGLE_ACTION := "toggle_skills"
const SETTINGS_TOGGLE_ACTION := "toggle_settings"

## Where the player's key-binding overrides persist between sessions. Only
## overrides are stored (see Keybindings.to_dict); defaults live in code.
const KEYBINDINGS_PATH := "user://keybindings.cfg"
## /spawn caps how many creatures one command can add, and scatters them a
## little around the player rather than stacking exactly on top of each
## other or one another.
const MAX_SPAWN_COUNT := 10
const SPAWN_SCATTER := 20.0
## /give caps how many of an item one command can hand out.
const MAX_GIVE_COUNT := 99
## /gold caps how much one dev-console command can add to the wallet.
const MAX_GOLD_COUNT := 9999

const SURVIVAL_BAR_WIDTH := 150.0
const SURVIVAL_BAR_HEIGHT := 14.0

## How heavy the visible falling rain is per weather state (see
## RainOverlay.set_intensity). A storm is a downpour; ordinary rain is
## steady but lighter; everything else is dry. Anything not listed falls
## back to 0.0, so a new weather state can never accidentally rain.
const RAIN_INTENSITY_BY_WEATHER := {
	"rain": 0.55,
	"storm": 1.0,
}

var _rain_overlay := RainOverlay.new()

## Held only to avoid allocating one per frame -- the material it pushes to is
## static and shared (see GroundTint._shared_material, pinned by
## test_ground_tint.gd::test_the_shared_material_is_the_same_one_for_every_instance),
## so which instance does the pushing is irrelevant.
var _ground_tint := GroundTint.new()

@onready var _terrain: TileMapLayer = $Terrain
@onready var _water_fx: TileMapLayer = $WaterFx
@onready var _river_flow_fx: TileMapLayer = $RiverFlowFx
@onready var _hillshade_fx: TileMapLayer = $HillshadeFx
## Snow lies here rather than as a tint on the ground, so footprints can be
## carved out of it (see SnowBombShader) -- the cells carry only land
## presence now, the actual coverage is read per pixel by the shader.
@onready var _snow_fx: TileMapLayer = $SnowFx
@onready var _entities: Node2D = $Entities
## Ground-flush decoration (flowers, worms, desert scrub, tundra lichen) --
## not y_sort_enabled, and drawn behind Entities via z_index instead, the
## same "ground effects tier" WaterFx/SnowFx/HillshadeFx already use. This
## decor sits flush with the floor and never needed per-sprite Y-order
## interleaving with trees/creatures/the player in the first place; forcing
## it into Entities' own y_sort_enabled=true interleaving is what broke
## draw-call batching for the whole group under the gl_compatibility
## renderer (see EarthChunkManager._ground_decor_parent's own doc comment).
@onready var _ground_decor: Node2D = $GroundDecor
@onready var _creatures: Node2D = $Creatures
@onready var _ground_items: Node2D = $GroundItems
@onready var _roof: TileMapLayer = $Roof
## Players are spawned directly into $Entities (not a separate sibling
## container) so they Y-sort against trees/grass/stones -- tall grass or a
## tree in front of the player must be able to draw over them, which two
## independently-sorted containers can never do (each only sorts its own
## direct children; reported as grass/trees "rendering one square too high"
## while never actually occluding the player from the front). The
## get_children() loops below already filter with `as Player`, so mixing in
## non-player siblings is harmless.
@onready var _players: Node2D = $Entities
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _day_night: CanvasModulate = $DayNightTint
@onready var _ui: CanvasLayer = $UI
@onready var _debug_label: Label = $UI/DebugLabel
@onready var _minimap: TextureRect = $UI/Minimap
@onready var _player_health_bg: ColorRect = $UI/PlayerHealthBar/Background
@onready var _player_health_fill: ColorRect = $UI/PlayerHealthBar/Fill
@onready var _player_health_label: Label = $UI/PlayerHealthBar/Label
@onready var _hotbar: HBoxContainer = $UI/Hotbar
@onready var _spell_bar: HBoxContainer = $UI/SpellBar

var _chunk_manager: EarthChunkManager
var _path_scarring := PathScarring.new()
var _scarred_tiles: Dictionary = {}  # Vector2i global tile -> true, tiles we've painted as trampled earth
## Sentinel far outside any reachable tile, so the first real tile always
## counts as "newly stepped on".
var _last_scar_step_tile := Vector2i(-2147483648, -2147483648)
var _scar_refresh_accumulator := 0.0
var _geo_coordinates := GeoCoordinates.new()
var _solar_position := SolarPosition.new()
var _easter_egg_sightings := EasterEggSightings.new()
var _easter_egg_creatures := EasterEggCreatures.new()
var _wargames_response := WarGamesResponse.new()
var _back_to_the_future_day := BackToTheFutureDay.new()
## Once-per-session flag (see BackToTheFutureDay's own doc comment for why
## this is enough): the cameo is only eligible one real calendar day a year,
## so "once per session" and "once per day" are indistinguishable in
## practice.
var _bttf_cameo_shown_this_session := false
var _rush_ambient_cue := RushAmbientCue.new()
## Once-per-approach flag (see RushAmbientCue's own doc comment for the
## same low-risk "no de-duplication guard" scope call EasterEggCreatures
## already makes) -- fires the cue once per session rather than replaying
## it on every check while the player lingers nearby.
var _rush_ambient_cue_played := false
var _secret_d20 := SecretD20.new()
## Dedicated to SecretD20 alone -- see that module's own doc comment on why
## this is a separate, narrowly-named RandomNumberGenerator instance rather
## than the ambient randf() the cameo-rarity checks elsewhere in this file
## already use: nothing else in this project should ever draw from this.
var _secret_d20_rng := RandomNumberGenerator.new()
var _ancient_terminal := AncientTerminal.new()
var _signed_secret_room := SignedSecretRoom.new()
## Rolling buffer of the last few "stash"/"lasso"/"fish"/"mount" just-pressed
## action names (see SignedSecretRoom.ACTION_SEQUENCE/matches_sequence's own
## doc comment) -- capped to ACTION_SEQUENCE's own length so it never grows
## unbounded; only these four action names are ever pushed onto it, nothing
## else the player presses touches this buffer at all.
var _signed_secret_room_recent_actions: Array[String] = []
var _bridgekeeper := BridgekeeperEncounter.new()
## Session state for an in-progress riddle exchange (see
## _check_bridgekeeper_encounter/_handle_bridgekeeper_answer_command): -1
## means no encounter is active. Reused across encounters -- "rarely
## encountered wandering NPC" per the doc implies this can happen more than
## once a session, unlike the once-per-session cameos above.
var _bridgekeeper_riddle_index := -1
var _bridgekeeper_correct_count := 0
## docs/concept/easter_eggs.md's "Three Fragments" hunt -- pure aggregation
## logic over the three source eggs' own has_been_found() signals (see
## ThreeFragmentsHunt's own doc comment). Granting each fragment item is
## handled inline in _check_ancient_terminal/_check_signed_secret_room/the
## /globalthermonuclearwar command handler, each gated on "was this egg NOT
## already found before this call" so a fragment is only ever granted once
## per source egg, no matter how many times a re-triggerable egg (the
## terminal, the secret room) fires again later.
var _three_fragments_hunt := ThreeFragmentsHunt.new()
## docs/concept/easter_eggs.md's "hidden sea cave... dueling-birds cabinet"
## entry -- SeaCaveGuardian is the pure location/challenge-state module;
## _joust_view is the node/rendering adapter that actually plays the match
## (built in _build_joust_view, shown/hidden by _check_sea_cave_guardian/
## _on_joust_match_finished below). Not part of "Three Fragments" -- that
## hunt only ever named the terminal/secret room/WarGames eggs.
var _sea_cave_guardian := SeaCaveGuardian.new()
var _joust_view: JoustMatchView
## The hidden retro handheld (docs/concept/easter_eggs.md's "hidden retro
## handheld" entry) -- RetroHandheld is the pure location/interaction-state
## module (mirrors AncientTerminal's real-coordinate shape but, like
## SeaCaveGuardian, is repeatable rather than a one-shot has_been_found()
## gate on re-entry); HandheldBattleView is the actual playable battle +
## dex screen (built in _build_handheld_view, opened/closed by
## _check_retro_handheld/_on_handheld_closed below).
var _retro_handheld := RetroHandheld.new()
var _handheld_view: HandheldBattleView
var _weather_model := WeatherModel.new()
var _is_dedicated_server := false
var _minimap_renderer := MinimapRenderer.new()
var _minimap_refresh_accumulator := MINIMAP_REFRESH_INTERVAL  # refresh immediately on first update
var _autosave_accumulator := 0.0
var _health_bar := HealthBar.new()
var _item_sprite_generator := ProceduralItemSprite.new()
var _hotbar_slots: Array[TextureRect] = []
var _hotbar_counts: Array[Label] = []
## The slot frames themselves (icon/count's parent) -- kept separately so
## _update_hotbar can set each slot's tooltip to what's actually bound there
## (see _hotbar_tooltip_text), matching InventoryWindow's item tooltips.
var _hotbar_slot_frames: Array[Control] = []
## Last-rendered "item_id:count" per hotbar slot, so _update_hotbar can skip
## slots that didn't change (avoids per-frame texture rebuilds). Sized when the
## slots are built; a sentinel forces the first real refresh.
var _hotbar_slot_state: Array[String] = []
var _creature_renderer := CreatureRenderer.new()
var _item_catalog := ItemCatalog.new()
var _crafting_recipe_book := CraftingRecipeBook.new()
var _dev_console: PanelContainer
var _inventory_window: PanelContainer
var _crafting_window: CraftingWindow
var _skill_window: SkillTreeWindow
var _settings_overlay: SettingsOverlay
var _license_gate_overlay: LicenseGateOverlay
var _github_verify_overlay: GithubVerifyOverlay
## True only once _ready() has actually built the world (chunk manager,
## menus, etc.) -- false for the entire time a license-gate/GitHub-verify
## overlay is showing instead. _process()/_unhandled_input() guard on
## this so they don't run against not-yet-built state (see _ready()'s
## own doc comment on the line that sets this true).
var _world_ready := false
var _main_menu: MainMenu
var _menu_backdrop: ColorRect
var _menu_background: TextureRect
var _loading_overlay: LoadingOverlay
## One-shot guard around the joining-client version of the loading stall (see
## _run_initial_client_chunk_load) -- true once that async chunk-load task has
## actually been kicked off, so the per-frame _client_process never starts a
## second overlapping one; _done flips true once it actually finishes, which
## is when _client_process resumes its own plain per-frame update() calls.
var _initial_client_chunk_load_task_running := false
var _initial_client_chunk_load_done := false
## Shared dark/rounded UI theme (see UiTheme), assigned to every window/menu so
## the whole UI reads as one styled system rather than raw grey boxes.
var _ui_theme := UiTheme.new().build_theme()
var _class_archetypes := ClassArchetype.new()
## Class chosen at the main menu, applied to the local player on spawn.
var _pending_class := "warrior"
## The look authored in the character creator (see MainMenu), applied to the
## spawned player. Empty for non-interactive launches (dedicated server,
## --connect), which fall back to a seed-rolled appearance.
var _pending_appearance: Dictionary = {}
## The rolled DNA genome's stat swing (see HeroDna/MainMenu.current_dna),
## added on top of the chosen class's own base stats before spawning. Empty
## (no-op) for non-interactive launches, same as _pending_appearance.
var _pending_dna_stat_modifiers: Dictionary = {}
## The seed of the SAME roll _pending_dna_stat_modifiers came out of (see
## HeroDna/MainMenu.current_dna). It drives the passive web's resonance exchange
## rate and the character's own grafted genome net (see Player.apply_dna_seed /
## docs/concept/skills.md); 0 means no creator ran, which the web reads as a
## neutral genome rather than as a penalty.
var _pending_dna_seed := 0
## Player-state persistence (see docs/concept/persistence.md) -- PlayerSave
## is pure I/O, WorldReset wipes EarthChunkManager's own persistence dirs.
var _player_save := PlayerSave.new()
var _world_reset := WorldReset.new()
var _world_coordinates := WorldCoordinates.new()
var _keybindings := Keybindings.new()
var _graphics_fullscreen := false
## Default VSync OFF so the frame rate can exceed the monitor refresh toward
## 120+ FPS (VSync hard-caps to refresh). Re-enable it in Settings > Graphics
## for a tear-free image on a high-refresh display.
var _graphics_vsync := false
## Render resolution (see RenderResolution): how many pixels the world is
## drawn into before being scaled to the window. The one graphics lever that
## scales the entire frame cost at once.
var _graphics_resolution := RenderResolution.default_option()
var _death_label: Label
var _creature_panels_container: VBoxContainer
var _hover_tooltip: Label
var _hover_target_finder := HoverTargetFinder.new()
## Floating "Talk (<key>)" prompt shown above the nearest in-range villager
## (see Player.TALK_RADIUS, EarthChunkManager.nearest_npc_near) -- the
## available-interaction hint requested alongside the talk feature itself.
var _interaction_prompt: Label

## The "strengthometer" for the held-item charge/release throw (see
## docs/concept/stone.md, ChargeMeter, Player.hand_charge_fraction) -- a
## floating bar shown above the player's head only while holding + charging
## something, same Background/Fill ColorRect shape as _player_health_fill,
## positioned every frame the same world-to-screen way _interaction_prompt
## is (see _build_charge_meter/_update_charge_meter).
var _charge_meter: Control
var _charge_meter_bg: ColorRect
var _charge_meter_fill: ColorRect

var _hunger_fill: ColorRect
var _hunger_label: Label
var _thirst_fill: ColorRect
var _thirst_label: Label
var _stamina_fill: ColorRect
var _stamina_label: Label
var _warmth_fill: ColorRect
var _warmth_label: Label
var _xp_fill: ColorRect
var _xp_label: Label
## Naturalist "land_sense" keystone reveal (docs/concept/progression.md
## "Ecological literacy"): real land-health/vegetation numbers near the
## player, visible only once that keystone is unlocked -- see
## _update_land_sense_label.
var _land_sense_label: Label
## The one top-centre stack every transient world message is shown in, and
## the themed cards inside it -- see _build_message_stack for why there is
## one stack rather than five hand-positioned, background-less Labels. The
## taming banner (docs/concept/taming.md) sits just under the fishing one, as
## it always did; it just cannot land ON it any more.
var _message_stack: VBoxContainer
var _fishing_banner: PanelContainer
var _lasso_banner: PanelContainer
var _trade_banner: PanelContainer
var _talk_banner: PanelContainer
var _easter_egg_banner: PanelContainer
var _cast_banner: PanelContainer
var _wallet_label: Label
var _creature_panels_accumulator := CREATURE_PANELS_REFRESH_INTERVAL  # refresh immediately
## How much faster than real time the ECOLOGY runs, set by /ecotest.
##
## One means normal, and is the ordinary game: at that value the ecology takes
## the frame's own delta through exactly the path it always did. Anything
## higher hands it the same time in slices (see TimeLapse) so a year can be
## watched in a minute -- seasons turning, canopies going bare and back into
## leaf, fruit ripening and falling, saplings coming up.
##
## Deliberately only the ecology: the player still moves at normal speed, so
## you can walk around and look at things while the year runs past.
var _ecology_time_scale := 1.0


## Pure command parsing so `/ecotest off` remains testable and independent
## from any diagnostic display code.
static func ecology_scale_for_console_argument(current_scale: float, argument: String) -> float:
	if argument.to_lower() == "off":
		return 1.0
	var asked := argument.to_float()
	return TimeLapse.scale_for(asked) if asked > 0.0 else current_scale


## Which sky the console has pinned for the rest of the session: "" (the real
## cycle), "day" (/day) or "night" (/night). Same effect as
## DEBUG_ALWAYS_DAY_ENV but toggled live rather than only at launch.
var _forced_sky := ""
## Local clock hour pinned by /time <hh:mm>, or NO_FORCED_HOUR for the real
## one (see clock_hour_for_console_argument).
var _forced_local_hour := NO_FORCED_HOUR


## How fast the streaming budget below assumes the player is travelling, in
## TILES per second. Not the walking pace: the fastest the player can
## actually move under their own power is a mount (Taming.MOUNTED_SPEED
## world units per second, over TerrainRenderer.TILE_SIZE units per tile), so
## that is what the streaming edge has to stay ahead of.
const STREAMING_BUDGET_TILES_PER_SECOND := Taming.MOUNTED_SPEED / float(TerrainRenderer.TILE_SIZE)

## ...and how many update() calls per second that pace gets, i.e. the frame
## rate. This is deliberately the WORST rate the playtest measured -- 6 FPS,
## the floor of the 6-8 FPS dip at a chunk boundary that this budget exists
## to remove -- rather than the 20-26 FPS of smooth walking. Fewer frames per
## second means fewer update() calls to spread the pending chunks over, so
## the derivation has to allow MORE chunks per call: assuming the dip is the
## conservative direction, and guarantees the budget itself can never be the
## reason a chunk arrives late.
##
## Neither constant is a knife edge -- chunks_per_update_for returns 1 across
## the whole 6-144 FPS band at both the walking and the mounted pace
## (test_the_budget_is_one_across_the_whole_measured_frame_rate_band).
const STREAMING_BUDGET_FRAMES_PER_SECOND := 6.0


## Caps how many chunks ONE update() call may generate, so crossing a chunk
## boundary no longer generates a whole LOAD_RADIUS column inside a single
## frame (the measured walking stall: 20-26 FPS falling to 6-8). The manager
## defaults to 0 == unbudgeted, which is what every test and the cold load
## want, so this one call is what makes the budget real in the running game.
##
## The value is DERIVED, never picked: EarthChunkManager.chunks_per_update_for
## is a pure, separately-tested function of pace and frame rate over the real
## streaming geometry (see its own doc comment and
## CHUNK_BUDGET_SAFETY_FACTOR). The cold initial load is untouched -- it goes
## through update_with_progress' coroutine, which is the right tool there.
func _apply_streaming_budget(manager: EarthChunkManager) -> void:
	manager.max_chunk_loads_per_update = EarthChunkManager.chunks_per_update_for(
		STREAMING_BUDGET_TILES_PER_SECOND, STREAMING_BUDGET_FRAMES_PER_SECOND
	)


func _ready() -> void:
	# Second, independent integrity + license check (see docs/licensing.md,
	# src/licensing/self_integrity.gd, src/licensing/license_gate.gd) --
	# the SelfIntegrity/LicenseGate autoloads already check at boot, before
	# this scene even loads; these re-verify from scratch rather than
	# trusting that already ran, so bypassing the game requires patching
	# more than one call site, not just one `if`. Integrity failures still
	# hard-quit (a tampered install isn't something an in-game screen can
	# fix) -- only the license check gets a recoverable in-game path,
	# since the fix there really is just "type/paste a valid key".
	#
	# SelfIntegrity keeps its own OS.has_feature("editor") bypass -- a
	# SEPARATE, still-valid concern: there's no exported .pck to hash while
	# running raw project files this way, so it can never pass in this
	# launch mode regardless of any real key, and forcing it would just
	# always hard-quit every dev/editor launch, not usefully test anything.
	#
	# The LICENSE check's own editor bypass is gone (see license_gate.gd's
	# _boot(), removed by request): LicenseGate.check_licensed() now runs
	# unconditionally here too, the same as an exported build, so an
	# invalid/missing key shows the real in-game "enter your key" gate
	# during editor Play-button runs as well. The `--force-license-check`
	# arg this used to read is gone with it -- the check it opted back
	# into is now simply always on.
	if not OS.has_feature("editor"):
		SelfIntegrity.require_verified()
	var license_result: Dictionary = LicenseGate.check_licensed()
	if not license_result.licensed:
		_show_license_gate()
		return
	# Personal/GitHub-bound key (docs/licensing.md's "Personal / GitHub-
	# bound keys"): structurally valid (signature checks out, not
	# expired) isn't the same as identity-verified yet -- await the real
	# check before letting boot continue. _ready() awaiting mid-function
	# is a normal, supported GDScript pattern; the node is still
	# considered ready while this is pending.
	if license_result.github_user_id != 0:
		var identity_ok: bool = await _verify_github_identity(license_result.github_user_id)
		if not identity_ok:
			return

	# Real bug found live: _process()/_unhandled_input() run every frame
	# regardless of whether _ready() returned early above -- before this
	# flag existed, an unlicensed/unverified boot's early return still
	# left the license/GitHub-verify overlay's screen crashing every
	# frame on _chunk_manager (built further below) being null, via
	# _process()'s step_water_disturbances() call. Both callbacks below
	# now no-op until this is true, set only once everything they touch
	# has actually been built.
	_world_ready = true

	# Seeds SecretD20's OWN dedicated RandomNumberGenerator -- see that
	# module's own doc comment for why this instance is never shared with
	# anything else in the project.
	_secret_d20_rng.randomize()

	# Area2D's input_event (used by DroppedItem's click-to-pick-up) never
	# fires unless the viewport's physics picking is explicitly enabled -- it
	# defaults to off.
	get_viewport().physics_object_picking = true

	_chunk_manager = EarthChunkManager.new(_terrain, _entities, _creatures, _ground_decor)
	# Streams at most one chunk per frame from here on, so stepping over a
	# chunk boundary stops generating a whole column inside one frame (see
	# _apply_streaming_budget). The cold initial load below still runs
	# through update_with_progress' coroutine and is unaffected.
	_apply_streaming_budget(_chunk_manager)
	# World-space low-frequency color drift over the whole ground layer (see
	# GroundTint) -- soft lusher/drier patches spanning many tiles, so fields
	# read as organic ground instead of a uniform printed carpet.
	_terrain.material = GroundTint.new().shared_material()
	# GPU water: continuous noise-driven waves over every ocean cell,
	# translucent so shore foam and rain ripples show through (WaterShader).
	_chunk_manager.set_water_layer(_water_fx)
	# Directional current over river cells only, on top of the still-water
	# base above (see RiverFlowShader, docs/concept/rivers.md -- rivers
	# previously looked exactly like still ocean water).
	_chunk_manager.set_river_flow_layer(_river_flow_fx)
	_chunk_manager.set_snow_layer(_snow_fx)
	# GPU relief shading: real slope/aspect data shaded by the real, live sun
	# position (see HillshadeShader, docs/concept/terrain_relief.md).
	_chunk_manager.set_hillshade_layer(_hillshade_fx)
	# Roof pieces (see docs/concept/building.md#what-enterable-means-in-a-top-down-game):
	# a separate layer above the player/entities so a house reads as a real
	# building from outside, hidden per-room while the player is inside it.
	_chunk_manager.set_roof_layer(_roof)
	# Lets fruit-eating birds (see AmbientFlyerMarker.fruit_world /
	# docs/concept/flora.md#bird-endozoochory) see and eat the same real,
	# already-rendered fallen-fruit ground items the player can click on --
	# EarthChunkManager.fruit_near/take_fruit_at read this directly rather
	# than needing a second, parallel ground-item model.
	_chunk_manager.set_ground_items(_ground_items)
	_player_spawner.spawn_path = _players.get_path()
	_player_spawner.add_spawnable_scene(PlayerScene.resource_path)
	WorldItemBus.item_dropped.connect(_on_item_dropped)

	# Visible falling rain (see RainOverlay). Mounted once, always present,
	# and invisible until the weather model turns it on -- the water was
	# already rippling from rain that never appeared to be falling.
	add_child(_rain_overlay.build_overlay())

	# Bind every action to the InputMap up front (loading any saved overrides
	# first), before Player spawns and starts polling -- Player's own
	# bind-if-empty calls then become harmless no-ops (see _apply_keybindings).
	_load_keybindings()
	_apply_keybindings()
	_load_graphics()
	_apply_graphics()

	_build_hotbar_slots()
	_build_spell_bar()
	_build_dev_console()
	_build_inventory_window()
	_build_crafting_window()
	_build_skill_window()
	_build_settings_overlay()
	_build_loading_overlay()
	_build_creature_panels_container()
	_build_hover_tooltip()
	_build_death_label()
	_build_survival_bar()
	_build_xp_bar()
	_build_land_sense_label()
	_build_message_stack()
	_build_joust_view()
	_build_handheld_view()
	_build_interaction_prompt()
	_build_charge_meter()

	var args := OS.get_cmdline_user_args()
	if "--solo" in args:
		# Dev/instrumentation launch: skip the menu and drop straight into a
		# solo session. The project's standard way of finding a bug that
		# every unit test structurally cannot see is to instrument
		# _process, launch the game, and read the log (see
		# docs/progress.md) -- which needs the world actually RUNNING, and
		# the menu holds it paused until someone clicks. Deliberately does
		# NOT wipe the save the way New Game does.
		_spawn_local_singleplayer()
		return
	if "--server" in args:
		_is_dedicated_server = true
		_start_server()
	elif _has_network_arg(args):
		_start_client(args)
	else:
		# Interactive launch: show the main menu (New Game / Host / Join /
		# class pick) and hold the world paused until the player chooses, rather
		# than dropping straight into a default single-player game.
		_show_main_menu()


## Path to the menu's painted backdrop (see concept art prompt in the commit
## this was added in). Optional -- MENU_BACKGROUND_PATH missing just means
## the plain dim ColorRect (below) is all that shows, so dropping the asset
## in later works with no code change.
const MENU_BACKGROUND_PATH := "res://assets/backgrounds/main.png"


## Builds the start-up main menu (see MainMenu). The world is paused behind it
## (the menu itself keeps running via PROCESS_MODE_ALWAYS) until a choice is made.
func _show_main_menu() -> void:
	# The painted backdrop, if present -- covers the full screen, cropped
	# (not stretched/squashed) to whatever aspect ratio the viewport is.
	if ResourceLoader.exists(MENU_BACKGROUND_PATH):
		_menu_background = TextureRect.new()
		_menu_background.texture = load(MENU_BACKGROUND_PATH)
		_menu_background.set_anchors_preset(Control.PRESET_FULL_RECT)
		_menu_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_menu_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_menu_background.process_mode = Node.PROCESS_MODE_ALWAYS
		_ui.add_child(_menu_background)

	# A dim overlay so the game world/HUD doesn't bleed through behind the
	# menu (it did before this pass) and the panel stays readable over the
	# backdrop art -- much lighter than before now there's real art to show
	# through it; falls back to a near-opaque dim on its own if the art is
	# missing.
	_menu_backdrop = ColorRect.new()
	_menu_backdrop.color = (
		Color(0.02, 0.02, 0.04, 0.45) if _menu_background != null else Color(0.04, 0.05, 0.07, 0.94)
	)
	_menu_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(_menu_backdrop)

	_main_menu = MainMenu.new()
	_main_menu.theme = _ui_theme
	_main_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(_main_menu)
	_main_menu.start_requested.connect(_on_menu_start_requested)
	_main_menu.join_requested.connect(_on_menu_join_requested)
	_main_menu.load_requested.connect(_on_menu_load_requested)
	get_tree().paused = true


## New Game and Host Game both author a brand new character via the creator
## -- neither is "load", so both wipe any previous run's persisted world and
## player save first (see docs/concept/persistence.md: "New Game means new").
## Safe to wipe unconditionally here: EarthChunkManager hasn't loaded any
## chunks yet at this point (chunk loading is lazy, first triggered by
## spawn), so every chunk simply finds nothing left to layer on top of its
## deterministic base.
func _on_menu_start_requested(
	mode: String, chosen_class: String, appearance: Dictionary, dna_stat_modifiers: Dictionary
) -> void:
	_pending_class = chosen_class
	_pending_appearance = appearance
	_pending_dna_stat_modifiers = dna_stat_modifiers
	# Read straight off the menu rather than carried on start_requested: the
	# signal already carries this genome's stat modifiers, and the seed is the
	# same roll's other half (see MainMenu.current_dna).
	_pending_dna_seed = int(_main_menu.current_dna().get("seed_value", 0))
	# Shown and PAINTED before any of the real, synchronous world-setup work
	# below starts (see _show_loading_overlay) -- that work is what was
	# reported as the game appearing to hang (see docs/progress.md's Loading
	# screens entry for the real measured cost).
	await _show_loading_overlay("Preparing a new world...")
	_wipe_persisted_world()
	if mode == "host":
		_start_server()
	await _spawn_local_singleplayer()
	_dismiss_main_menu()


## Every user:// DIRECTORY New Game destroys -- listed here so the backup
## below and the wipe underneath it can never disagree about what a world is
## (pinned against the wipe's own source by test_world_backup_paths.gd).
static func backed_up_directories() -> PackedStringArray:
	return PackedStringArray([
		EarthChunkManager.MODIFICATIONS_DIR,
		EarthChunkManager.PLANTED_TREES_DIR,
		EarthChunkManager.FISH_POPULATION_DIR,
		EarthChunkManager.ROOF_MODIFICATIONS_DIR,
		EarthChunkManager.ECOLOGY_DIR,
		EarthChunkManager.KEPT_ANIMALS_DIR,
	])


## Every single-FILE store New Game destroys, in the order the wipe removes
## them. Each path is read from the persistence class that owns it rather
## than restated as a literal, so moving a store's file moves its backup too.
static func backed_up_files() -> PackedStringArray:
	return PackedStringArray([
		EarthChunkManager.EventStorePersistence.SAVE_PATH,
		EarthChunkManager.MemoryStorePersistence.SAVE_PATH,
		EarthChunkManager.HouseholdStorePersistence.SAVE_PATH,
		EarthChunkManager.ContractStorePersistence.SAVE_PATH,
		EarthChunkManager.MarketStorePersistence.SAVE_PATH,
		EarthChunkManager.InstitutionStorePersistence.SAVE_PATH,
		EarthChunkManager.WorldBossStorePersistence.SAVE_PATH,
		EarthChunkManager.WorldClockPersistence.SAVE_PATH,
		PlayerSave.SAVE_PATH,
	])


## Copies everything the wipe below is about to destroy to `<path>.bak`
## first (see WorldReset.backup_file/backup_directory).
##
## New Game is the only irreversible action in the game, and until this ran
## it had no undo whatsoever: one click removed a whole world's chunk
## modifications, its planted trees, its fish populations, its event, memory,
## household, contract, market, institution and world-boss stores, its clock
## and the player's own save -- and the 60-second autosave then wrote the new
## character over player_save.bin, closing even the undelete window. Every
## emergent thing a save accumulates lived in exactly those files.
##
## ONE generation, overwritten by the next New Game: enough to undo a
## mis-click, not an archive. It roughly doubles the on-disk world for as
## long as the backup sits there, which is a cheap price for an undo.
func _backup_persisted_world() -> void:
	for dir_path in backed_up_directories():
		_world_reset.backup_directory(dir_path)
	for path in backed_up_files():
		_world_reset.backup_file(path)


func _wipe_persisted_world() -> void:
	_backup_persisted_world()
	_world_reset.wipe_directory(EarthChunkManager.MODIFICATIONS_DIR)
	_world_reset.wipe_directory(EarthChunkManager.PLANTED_TREES_DIR)
	_world_reset.wipe_directory(EarthChunkManager.FISH_POPULATION_DIR)
	# Roofs are chunk modifications like any other (the same per-chunk
	# <x>_<y>.bin shape as MODIFICATIONS_DIR, written by the same building
	# code) -- they were just added later than the three lines above and
	# never joined the wipe, so a new world loaded the PREVIOUS world's
	# roofs hanging over ground whose walls and floors had gone.
	_world_reset.wipe_directory(EarthChunkManager.ROOF_MODIFICATIONS_DIR)
	# A region's land health and populations, and the animals the player tamed,
	# are world state exactly like the four above -- a grazed-down meadow and a
	# horse won over across an evening both belong to ONE world. Both were added
	# to the manager after this function was written and never joined it, and
	# the stale files are READ BACK on the next chunk load: _apply_persisted_
	# ecology seeds the old world's herbivore, predator and land-health numbers,
	# and _restore_kept_animals spawns the old world's tamed horses. Neither
	# record carries a world identity, so nothing downstream can tell a previous
	# world's file from its own -- a new world inherited the last player's
	# overgrazed pasture and their livestock.
	_world_reset.wipe_directory(EarthChunkManager.ECOLOGY_DIR)
	_world_reset.wipe_directory(EarthChunkManager.KEPT_ANIMALS_DIR)
	_player_save.wipe()
	# The event store and memory store are two more pieces of world-scoped
	# state that must not survive "New Game" -- the same "New Game means new"
	# pillar as the three lines above (see docs/concept/persistence.md,
	# EventStorePersistence/MemoryStorePersistence).
	_chunk_manager.wipe_event_store()
	_chunk_manager.wipe_memory_store()
	_chunk_manager.wipe_household_store()
	_chunk_manager.wipe_contract_store()
	_chunk_manager.wipe_market_store()
	_chunk_manager.wipe_institution_store()
	_chunk_manager.wipe_world_boss_store()
	# And a brand new world clock: any previous run's persisted clock must not
	# leak into this one either, then a fresh random starting point is rolled
	# for THIS world (see EarthChunkManager.randomize_world_age/
	# docs/concept/seasons.md) -- every save used to start at world-age 0
	# exactly, which reliably began mid-winter-adjacent and snowed within
	# minutes of every single new game (reported: "it starts to snow
	# deterministically").
	_chunk_manager.wipe_world_clock()
	_chunk_manager.randomize_world_age()


## Restores a previously saved character exactly where they left off (see
## docs/concept/persistence.md) -- bypasses the character creator entirely,
## unlike _on_menu_start_requested. Deliberately does NOT wipe anything.
func _on_menu_load_requested() -> void:
	await _show_loading_overlay("Loading your world...")
	await _spawn_local_singleplayer_from_save()
	_dismiss_main_menu()


## A joining client's own version of the same stall (see _client_process,
## which is where its first real EarthChunkManager.update() call actually
## happens -- there is no single call here to wrap the way the two entry
## points above wrap _spawn_local_singleplayer[_from_save], since a joining
## client's player node only exists once the server's own spawn has
## replicated in). Shown here so it's up immediately on click rather than
## leaving a blank/frozen-looking screen for however long the connection
## handshake plus that later freeze take; _client_process hides it once that
## first update() call actually completes.
func _on_menu_join_requested(address: String) -> void:
	await _show_loading_overlay("Connecting to host...")
	_start_client_to(address)
	_dismiss_main_menu()


func _dismiss_main_menu() -> void:
	get_tree().paused = false
	if _main_menu != null:
		_main_menu.queue_free()
		_main_menu = null
	if _menu_backdrop != null:
		_menu_backdrop.queue_free()
		_menu_backdrop = null
	if _menu_background != null:
		_menu_background.queue_free()
		_menu_background = null


## Builds the loading overlay (see LoadingOverlay) once, hidden, ready to be
## shown/hidden repeatedly by _show_loading_overlay/_client_process. Built
## alongside the other menu-era overlays (_build_settings_overlay) rather than
## lazily, so it's already in the tree -- and can be moved to the front of
## `_ui` -- the first time New Game/Load Game/Join needs it.
func _build_loading_overlay() -> void:
	_loading_overlay = LoadingOverlay.new()
	_loading_overlay.theme = _ui_theme
	# Must keep animating/painting while the world is paused (see
	# _show_main_menu/_toggle_settings_menu -- every other paused-but-live
	# overlay in this file uses the same PROCESS_MODE_ALWAYS).
	_loading_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(_loading_overlay)


## Shows the loading overlay with `text` and waits for it to actually be
## PAINTED before returning, so callers can safely follow this with a long
## synchronous call without leaving a blank/frozen-looking frame on screen
## first. Two frames, not one: adding a Control and making it visible in the
## same frame queues a draw that a single `await process_frame` isn't
## guaranteed to have been presented by (Godot can defer that first draw one
## frame further) -- verified against a real running instance, see
## docs/progress.md's Loading screens entry.
func _show_loading_overlay(text: String) -> void:
	_loading_overlay.show_with_text(text)
	await get_tree().process_frame
	await get_tree().process_frame


## Passed as the on_progress Callable to every EarthChunkManager.
## update_with_progress call site (New Game/Load Game/Join) so the overlay's
## status line shows the same real "N / M chunks" progress regardless of
## which entry point is loading (see LoadingOverlay.set_progress).
func _on_chunk_load_progress(loaded: int, total: int) -> void:
	_loading_overlay.set_progress(loaded, total)


## The joining-client (and New Game/Load Game's own second, now-cheap) chunk
## load, run from _client_process -- see its own call site's doc comment for
## why this is a separate fire-and-forget function rather than an inline
## await. Hides the overlay itself once done, the same single hide point the
## old code had, still idempotent (a no-op if already hidden).
func _run_initial_client_chunk_load(player_tile: Vector2i) -> void:
	await _chunk_manager.update_with_progress(player_tile, _on_chunk_load_progress)
	_initial_client_chunk_load_done = true
	if _loading_overlay.visible:
		_loading_overlay.hide_overlay()


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		push_error("Failed to start server on port %d: %s" % [PORT, error])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[server] listening on port %d" % PORT)


func _has_network_arg(args: PackedStringArray) -> bool:
	for arg in args:
		if arg.begins_with("--connect"):
			return true
	return false


func _start_client(args: PackedStringArray) -> void:
	var host := DEFAULT_HOST
	for arg in args:
		if arg.begins_with("--connect="):
			host = arg.trim_prefix("--connect=")

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host, PORT)
	if error != OK:
		push_error("Failed to connect to %s:%d: %s" % [host, PORT, error])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	print("[client] connecting to %s:%d" % [host, PORT])


func _on_connection_failed() -> void:
	print("[client] connection FAILED")


## Builds the dev/debug console (see DevConsole) centered on screen, hidden
## until toggled (backtick by default, rebindable; see _unhandled_input).
func _build_dev_console() -> void:
	_dev_console = DevConsole.new()
	_dev_console.theme = _ui_theme
	_dev_console.set_anchors_preset(Control.PRESET_CENTER)
	_dev_console.offset_left = -210.0
	_dev_console.offset_top = -80.0
	_dev_console.offset_right = 210.0
	_dev_console.offset_bottom = 80.0
	_ui.add_child(_dev_console)
	_dev_console.command_submitted.connect(_on_console_command)


## Builds the real inventory window (see InventoryWindow), hidden until
## toggled with the toggle_inventory action (default I, rebindable in the
## settings overlay). The action itself is bound centrally in
## _apply_keybindings, not here.
func _build_inventory_window() -> void:
	_inventory_window = InventoryWindow.new()
	_inventory_window.theme = _ui_theme
	# Centered, and sized to match InventoryWindow's own custom_minimum_size
	# (600x460) exactly -- the previous TOP_RIGHT box (300x200) was smaller
	# than the window's real minimum size, pushing it off the 960x540
	# viewport. Matches this file's other popup windows (dev console,
	# settings overlay), which already anchor to PRESET_CENTER. Keep this in
	# sync with InventoryWindow._ready()'s custom_minimum_size if that ever
	# changes (e.g. SLOT_SIZE/ICON_SIZE tuning) -- undersizing this box
	# reintroduces the off-screen bug.
	_inventory_window.set_anchors_preset(Control.PRESET_CENTER)
	_inventory_window.offset_left = -300.0
	_inventory_window.offset_top = -230.0
	_inventory_window.offset_right = 300.0
	_inventory_window.offset_bottom = 230.0
	_ui.add_child(_inventory_window)
	_inventory_window.item_clicked.connect(_on_inventory_item_clicked)
	_inventory_window.unequip_requested.connect(_on_inventory_unequip_requested)
	_inventory_window.items_reordered.connect(_on_inventory_items_reordered)


## Clicking an inventory row activates that item (see Player.activate_item_id):
## weapons/tools get equipped, food/potions get used, raw materials do nothing.
func _on_inventory_item_clicked(item_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null:
		local_player.activate_item_id(item_id)
		_refresh_inventory_now(local_player)


## Dragging one inventory item onto another slot reorders it (see
## Inventory.swap_slots / move_to_end). A drop past the last occupied stack
## moves the item to the end rather than swapping with nothing.
func _on_inventory_items_reordered(from_index: int, to_index: int) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player == null:
		return
	var used := local_player.inventory.used_slots()
	if to_index >= used:
		local_player.inventory.move_to_end(from_index)
	else:
		local_player.inventory.swap_slots(from_index, to_index)
	_refresh_inventory_now(local_player)


## Clicking a worn paperdoll slot unequips it back into the inventory.
func _on_inventory_unequip_requested(slot: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null:
		local_player.unequip_slot(slot)
		_refresh_inventory_now(local_player)


## Hands the window everything it cannot work out for itself.
##
## The SEASON is the world clock's, and only EarthChunkManager has it -- food
## shelf life is seasonal, so without it the window's per-item freshness line
## silently never appears at all. Guarded for null because the UI is built
## before the world is (see _refresh_inventory_now's own test).
##
## The APPEARANCE is the look the player authored in the creator; without it
## the paperdoll falls back to CharacterView's default warrior, so every
## character looked identical in their own inventory.
func _refresh_inventory_now(local_player: Player) -> void:
	_inventory_window.refresh(
		local_player.inventory.stacks(),
		_equipped_map(local_player),
		local_player.equipment.total_armor(),
		local_player.inventory.slot_count,
		_chunk_manager.current_season() if _chunk_manager != null else ""
	)
	_inventory_window.apply_appearance(local_player.appearance)


## slot -> worn Item for the paperdoll (see Equipment).
func _equipped_map(local_player: Player) -> Dictionary:
	var map := {}
	for slot in local_player.equipment.SLOTS:
		var item = local_player.equipment.equipped_in(slot)
		if item != null:
			map[slot] = item
	return map


## Builds the crafting menu (see CraftingWindow), hidden until toggled with
## toggle_crafting (default C). Clicking an affordable recipe crafts it via the
## local player and refreshes.
func _build_crafting_window() -> void:
	_crafting_window = CraftingWindow.new()
	_crafting_window.theme = _ui_theme
	# Centered, like every other full menu (inventory, settings) -- it used to
	# be pinned to the right edge as a narrow strip, which read as a
	# secondary sidebar rather than the actual crafting screen.
	_crafting_window.set_anchors_preset(Control.PRESET_CENTER)
	# Keep in sync with CraftingWindow's own WORLD_ANCHOR_BOX test constant
	# (600x520 window minimum + margin) -- test_crafting_window.gd pins that
	# the window's real minimum size fits inside this box.
	_crafting_window.offset_left = -320.0
	_crafting_window.offset_top = -280.0
	_crafting_window.offset_right = 320.0
	_crafting_window.offset_bottom = 280.0
	_ui.add_child(_crafting_window)
	_crafting_window.craft_requested.connect(_on_craft_requested)


func _on_craft_requested(recipe_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null and local_player.craft(recipe_id):
		_crafting_window.refresh(local_player.inventory_counts())


## Builds the skill-tree spend window (see SkillTreeWindow), hidden until
## toggled with toggle_skills (default L). Clicking an affordable node/keystone
## allocates it on the local player and refreshes.
func _build_skill_window() -> void:
	_skill_window = SkillTreeWindow.new()
	_skill_window.theme = _ui_theme
	# CENTRED, not pinned to the left edge as it was while this window held only
	# a narrow list: the web (docs/concept/skills.md) needs the whole viewport
	# less a margin to read as a map. SkillTreeWindow.WORLD_AVAILABLE_BOX is the
	# single statement of the room these offsets leave it.
	_skill_window.set_anchors_preset(Control.PRESET_CENTER)
	_skill_window.offset_left = -SkillTreeWindow.WINDOW_SIZE.x * 0.5
	_skill_window.offset_top = -SkillTreeWindow.WINDOW_SIZE.y * 0.5
	_skill_window.offset_right = SkillTreeWindow.WINDOW_SIZE.x * 0.5
	_skill_window.offset_bottom = SkillTreeWindow.WINDOW_SIZE.y * 0.5
	_ui.add_child(_skill_window)
	_skill_window.node_allocated.connect(_on_skill_node_allocated)
	_skill_window.keystone_unlocked.connect(_on_skill_keystone_unlocked)
	_skill_window.node_refunded.connect(_on_skill_node_refunded)


func _on_skill_node_allocated(node_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null and local_player.allocate_skill(node_id):
		_refresh_skill_window(local_player)


func _on_skill_keystone_unlocked(keystone_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null and local_player.unlock_keystone(keystone_id):
		_refresh_skill_window(local_player)


## Free respec (docs/concept/classes.md): right-clicking an owned node on the
## web hands its points back, unless doing so would orphan the rest of the build
## (see Player.refund_skill).
func _on_skill_node_refunded(node_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null and local_player.refund_skill(node_id):
		_refresh_skill_window(local_player)


func _refresh_skill_window(local_player: Player) -> void:
	if not _skill_window.visible:
		return
	# Re-pointed every refresh rather than once at build time: the window is
	# built before any player exists, and the character (class, genome, grafted
	# net) is what the view has to be showing.
	_skill_window.configure_web(
		local_player.skill_web,
		local_player.character_class,
		local_player.dna_resonance,
		local_player.dna_seed
	)
	_skill_window.refresh(
		local_player.experience.unspent_points,
		local_player.allocated_nodes,
		local_player.unlocked_keystones
	)


## Shown INSTEAD OF building the rest of the world when LicenseGate finds no
## valid key (see _ready(), docs/licensing.md's "In-game license entry").
## Deliberately built standalone here rather than depending on anything the
## skipped rest of _ready() would have set up -- _ui and _ui_theme are the
## only things this needs, and both are already valid this early (_ui via
## @onready, _ui_theme via its own field initializer -- see their
## declarations above).
func _show_license_gate() -> void:
	_license_gate_overlay = LicenseGateOverlay.new()
	_license_gate_overlay.theme = _ui_theme
	_license_gate_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_license_gate_overlay.offset_left = -260.0
	_license_gate_overlay.offset_top = -170.0
	_license_gate_overlay.offset_right = 260.0
	_license_gate_overlay.offset_bottom = 170.0
	_ui.add_child(_license_gate_overlay)
	_license_gate_overlay.verify_requested.connect(_on_license_gate_verify_requested)
	_license_gate_overlay.quit_requested.connect(func(): get_tree().quit())


## A valid key gets saved to every real candidate path (see LicenseStore.
## write_code()'s own doc comment for why "every", not just the first) and
## the scene reloads fresh -- _ready() runs again, LicenseGate.check_licensed()
## re-reads the now-valid file, and this time the real world builds normally.
## An invalid key just reports back; the player can try again without losing
## anything (nothing else in the world has been built yet at this point).
##
## Real bug found live: this used to set the status label text and call
## reload_current_scene() in the very same frame -- reported back as
## "hangs a lot after verify and save ... appears stuck", because the
## confirmation text was queued to draw but reload_current_scene()'s real
## synchronous work started before the engine ever presented that frame,
## so nothing was ever visibly shown before the freeze. Same root cause
## and same fix _show_loading_overlay's own doc comment already documents
## for every OTHER long synchronous call in this file: await two frames
## (not one -- see that doc comment for why one isn't reliably enough)
## after showing something, before starting the long call. This does NOT
## make the reload itself faster or animate through it -- reload_current_scene()
## is one opaque synchronous call with no incremental unit to await
## mid-way through, so the loading screen still freezes on this one frame
## for the reload's real duration, the same documented limitation
## LoadingOverlay's own doc comment accepts for chunk-loading before
## update_with_progress existed. What this fixes is the confirmation
## never painting AT ALL first, not the freeze itself.
func _on_license_gate_verify_requested(code: String) -> void:
	var result := LicenseGate.check_licensed(code)
	if not result.licensed:
		_license_gate_overlay.show_status("That key isn't valid. Check for typos and try again.")
		return
	LicenseStore.write_code(LicenseStore.default_candidate_paths(), code)
	var loading := LoadingOverlay.new()
	loading.theme = _ui_theme
	_ui.add_child(loading)
	loading.show_with_text("Valid! Restarting the game...")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().reload_current_scene()


## The identity-verification half of a personal/GitHub-bound key (see
## _ready(), docs/licensing.md's "Personal / GitHub-bound keys"). Shows
## GithubVerifyOverlay for the duration, tries a cached token first (no
## interactive step at all if it still checks out -- this is what makes
## it a genuine per-launch identity check rather than a one-time flag,
## without forcing a browser round-trip on every single launch), and
## falls back to a fresh interactive device flow otherwise. A token
## GitHub itself rejects gets cleared and the flow retries once from
## scratch. Returns true only once GET /user's real id matches the bound
## one; the overlay is left showing a terminal message on any failure
## (mismatched identity, denied, expired, no network) rather than
## auto-retrying forever.
func _verify_github_identity(bound_user_id: int) -> bool:
	_github_verify_overlay = GithubVerifyOverlay.new()
	_github_verify_overlay.theme = _ui_theme
	_github_verify_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_github_verify_overlay.offset_left = -240.0
	_github_verify_overlay.offset_top = -150.0
	_github_verify_overlay.offset_right = 240.0
	_github_verify_overlay.offset_bottom = 150.0
	_ui.add_child(_github_verify_overlay)

	var auth := GithubDeviceAuth.new()
	add_child(auth)
	auth.user_code_ready.connect(func(user_code: String, verification_uri: String):
		_github_verify_overlay.show_device_code(user_code, verification_uri)
		_github_verify_overlay.show_status("Waiting for you to approve in your browser...")
	)

	var token_path := GithubTokenStore.default_path()
	var token := GithubTokenStore.read_token(token_path)
	# At most two passes: one retry if a cached token turns out to be
	# stale, then a fresh interactive flow -- never an unbounded loop.
	for attempt in 2:
		if token.is_empty():
			_github_verify_overlay.show_status("Starting GitHub sign-in...")
			var flow_result: Dictionary = await auth.run_device_flow()
			if not flow_result.ok:
				push_error("GitHub device flow failed: %s" % flow_result.reason)
				_github_verify_overlay.show_status("Could not verify your GitHub identity. Please restart to try again.")
				auth.queue_free()
				return false
			token = flow_result.access_token
			GithubTokenStore.write_token(token_path, token)

		_github_verify_overlay.show_status("Confirming your identity...")
		var user_result: Dictionary = await auth.run_fetch_user_id(token)
		if not user_result.ok:
			GithubTokenStore.clear_token(token_path)
			token = ""
			continue

		auth.queue_free()
		if GithubDeviceFlow.identity_satisfies_binding(bound_user_id, user_result.user_id):
			_github_verify_overlay.queue_free()
			return true
		_github_verify_overlay.show_status("This key is registered to a different GitHub account.")
		return false

	_github_verify_overlay.show_status("Could not verify your GitHub identity. Please restart to try again.")
	auth.queue_free()
	return false


## The already-in-game "change your license key" path (SettingsOverlay's
## License tab), distinct from _on_license_gate_verify_requested() above --
## that one blocks all of play with no valid key yet; this one is only
## reachable once already playing. Saves to disk either way, but doesn't
## reload the scene on success (nothing here needs the world rebuilt) --
## just reports honestly that a restart is needed for it to take effect,
## since no gameplay code today re-reads product_mask mid-session.
func _on_settings_license_code_submitted(code: String) -> void:
	var result := LicenseGate.check_licensed(code)
	if result.licensed:
		LicenseStore.write_code(LicenseStore.default_candidate_paths(), code)
		_settings_overlay.show_license_status("Saved. Restart the game for it to take effect.")
	else:
		_settings_overlay.show_license_status("That key isn't valid. Check for typos and try again.")


## Builds the key-binding settings overlay (see SettingsOverlay), hidden until
## toggled with toggle_settings (default Escape). Rebinding an action re-applies
## the InputMap immediately and persists the override to disk.
func _build_settings_overlay() -> void:
	_settings_overlay = SettingsOverlay.new()
	_settings_overlay.theme = _ui_theme
	# The menu must keep processing input while the game is paused (opening it
	# pauses the world, see _toggle_settings_menu).
	_settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_overlay.setup(
		_keybindings, _graphics_fullscreen, _graphics_vsync, _graphics_resolution
	)
	_settings_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_settings_overlay.offset_left = -210.0
	_settings_overlay.offset_top = -210.0
	_settings_overlay.offset_right = 210.0
	_settings_overlay.offset_bottom = 210.0
	_ui.add_child(_settings_overlay)
	_settings_overlay.binding_changed.connect(_on_binding_changed)
	_settings_overlay.reset_requested.connect(_on_bindings_reset)
	_settings_overlay.graphics_changed.connect(_on_graphics_changed)
	_settings_overlay.graphics_option_changed.connect(_on_graphics_option_changed)
	_settings_overlay.resume_requested.connect(_toggle_settings_menu)
	_settings_overlay.license_code_submitted.connect(_on_settings_license_code_submitted)


## Opens/closes the pause menu, pausing the world while it's open so it acts
## like a real pause screen (the menu itself keeps running via PROCESS_MODE_ALWAYS).
func _toggle_settings_menu() -> void:
	_settings_overlay.toggle()
	get_tree().paused = _settings_overlay.is_open()


func _on_graphics_changed(setting: String, enabled: bool) -> void:
	if setting == "fullscreen":
		_graphics_fullscreen = enabled
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
		)
	elif setting == "vsync":
		_graphics_vsync = enabled
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
		)
	_save_graphics()


## A graphics setting that is a CHOICE rather than on/off.
func _on_graphics_option_changed(setting: String, value: String) -> void:
	if setting == "render_resolution":
		_graphics_resolution = RenderResolution.sanitize(value)
		_apply_render_resolution()
	_save_graphics()


## Applies the render resolution by switching how the window scales its
## content (see RenderResolution).
##
## NATIVE uses CANVAS_ITEMS: the world and HUD rasterise at the window's true
## size, which is what makes text sharp. Anything else uses VIEWPORT: the
## world is drawn into a smaller framebuffer and scaled up, which costs that
## sharpness back but scales the whole frame's pixel cost with it. The design
## size stays the layout reference either way, so the player never sees more
## or less of the world for changing this.
func _apply_render_resolution() -> void:
	var window := get_window()
	if window == null:
		return
	if RenderResolution.is_native(_graphics_resolution):
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_size = Vector2i.ZERO
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = RenderResolution.render_size(
		_graphics_resolution, window.size
	)


## Graphics settings persist alongside key bindings in KEYBINDINGS_PATH (one
## small user config file). Applied at startup by _apply_graphics.
func _load_graphics() -> void:
	var config := ConfigFile.new()
	if config.load(KEYBINDINGS_PATH) != OK:
		return
	_graphics_fullscreen = config.get_value("graphics", "fullscreen", _graphics_fullscreen)
	_graphics_vsync = config.get_value("graphics", "vsync", _graphics_vsync)
	_graphics_resolution = RenderResolution.sanitize(
		str(config.get_value("graphics", "render_resolution", _graphics_resolution))
	)


func _apply_graphics() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if _graphics_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if _graphics_vsync else DisplayServer.VSYNC_DISABLED
	)
	_apply_render_resolution()


func _save_graphics() -> void:
	var config := ConfigFile.new()
	config.load(KEYBINDINGS_PATH)  # preserve the [bindings] section
	config.set_value("graphics", "fullscreen", _graphics_fullscreen)
	config.set_value("graphics", "vsync", _graphics_vsync)
	config.set_value("graphics", "render_resolution", _graphics_resolution)
	config.save(KEYBINDINGS_PATH)


func _on_binding_changed(action_name: String, keycode: int) -> void:
	_keybindings.set_keycode(action_name, keycode)
	_apply_keybindings()
	_save_keybindings()


func _on_bindings_reset() -> void:
	_keybindings.reset()
	_apply_keybindings()
	_save_keybindings()


## (Re)binds every rebindable action (see Keybindings) onto the InputMap from
## the current keycodes -- clearing existing events first so a rebind actually
## replaces the old key rather than adding a second one. Runs at startup and
## after every settings change.
func _apply_keybindings() -> void:
	for action in _keybindings.action_names():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = _keybindings.keycode_for(action)
		InputMap.action_add_event(action, event)


func _load_keybindings() -> void:
	var config := ConfigFile.new()
	if config.load(KEYBINDINGS_PATH) != OK:
		return  # no saved overrides yet -- defaults stand
	var saved := {}
	if config.has_section("bindings"):
		for action in config.get_section_keys("bindings"):
			saved[action] = config.get_value("bindings", action)
	_keybindings.apply_dict(saved)


func _save_keybindings() -> void:
	var config := ConfigFile.new()
	var overrides := _keybindings.to_dict()
	for action in overrides:
		config.set_value("bindings", action, overrides[action])
	config.save(KEYBINDINGS_PATH)


## Hunger/Thirst/Stamina mini-bars + a gold readout, bottom-left corner --
## deliberately NOT the left column below the health bar, since
## _creature_panels_container lives there and can grow tall/unpredictably.
func _build_survival_bar() -> void:
	# A themed panel groups the meters into one HUD card in the corner instead
	# of loose floating bars.
	var panel := PanelContainer.new()
	panel.theme = _ui_theme
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 8.0
	panel.offset_top = -132.0
	panel.offset_right = 176.0
	panel.offset_bottom = -8.0
	_ui.add_child(panel)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	panel.add_child(container)

	var hunger := _make_survival_meter_row(container, Color(0.75, 0.55, 0.15))
	_hunger_fill = hunger["fill"]
	_hunger_label = hunger["label"]
	var thirst := _make_survival_meter_row(container, Color(0.2, 0.5, 0.85))
	_thirst_fill = thirst["fill"]
	_thirst_label = thirst["label"]
	var stamina := _make_survival_meter_row(container, Color(0.85, 0.75, 0.15))
	_stamina_fill = stamina["fill"]
	_stamina_label = stamina["label"]
	var warmth := _make_survival_meter_row(container, Color(0.9, 0.45, 0.2))
	_warmth_fill = warmth["fill"]
	_warmth_label = warmth["label"]

	_wallet_label = Label.new()
	_wallet_label.add_theme_font_size_override("font_size", 12)
	container.add_child(_wallet_label)


## One mini bar (bg + fill + centered label), same shaded-rect pattern as
## PlayerHealthBar/CreaturePanel, just smaller.
## A slim XP bar with a level readout, just under the player health bar
## (top-left). Full = about to level up (see ExperienceTrack).
func _build_xp_bar() -> void:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bar.position = Vector2(8, 74)
	_ui.add_child(bar)

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12, 0.85)
	bg.size = Vector2(SURVIVAL_BAR_WIDTH, 10)
	bar.add_child(bg)

	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(0.5, 0.35, 0.85)
	_xp_fill.size = Vector2(0, 10)
	bar.add_child(_xp_fill)

	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 10)
	_xp_label.position = Vector2(2, -2)
	bar.add_child(_xp_label)


## Naturalist "land_sense" keystone reveal (docs/concept/progression.md
## "Ecological literacy"): real EarthChunkManager.land_health_near/
## vegetation_density_near numbers near the player, just under the XP bar.
## Hidden until the keystone is unlocked -- see _update_land_sense_label.
## This keystone's whole payoff IS this reveal, not a stat bump (see
## SkillTreeWindow's own special-cased row rendering for the same keystone).
func _build_land_sense_label() -> void:
	_land_sense_label = Label.new()
	_land_sense_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_land_sense_label.position = Vector2(8, 88)
	_land_sense_label.add_theme_font_size_override("font_size", 10)
	_land_sense_label.visible = false
	_ui.add_child(_land_sense_label)


## Every transient message the world shows the player -- fishing, taming,
## trade, talk, Easter-egg sightings -- in ONE themed, top-centre stack.
##
## They used to be five independent, absolutely-positioned, background-less
## Labels at hand-picked y offsets: unreadable over snow (reported), washed
## out over sand, and two of them (taming and trade) pinned to the SAME
## offset_top of 144, so a trade message and a taming message drew straight
## through each other. A VBoxContainer makes that overlap structurally
## impossible -- a hidden banner takes no room, so whatever is showing simply
## stacks -- and the shared `_ui_theme` PanelContainer card (the same opaque,
## bordered card _build_survival_bar and CreaturePanel already use) makes each
## one legible over any terrain.
##
## Each _update_*_label body keeps its name and its caller; what changed is
## that it now sets its banner's CARD (see _set_message_banner) rather than a
## loose Label's text and visibility.
func _build_message_stack() -> void:
	_message_stack = VBoxContainer.new()
	_message_stack.theme = _ui_theme
	_message_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_stack.offset_top = MESSAGE_STACK_TOP
	_message_stack.offset_left = -MESSAGE_STACK_WIDTH / 2.0
	_message_stack.offset_right = MESSAGE_STACK_WIDTH / 2.0
	_message_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_message_stack.add_theme_constant_override("separation", 4)
	_message_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_message_stack)

	# Fixed top-to-bottom order -- the same order message_banner_lines pins.
	_fishing_banner = _make_message_banner(16)
	_lasso_banner = _make_message_banner(16)
	_trade_banner = _make_message_banner(16)
	_talk_banner = _make_message_banner(14)
	_easter_egg_banner = _make_message_banner(14)
	_cast_banner = _make_message_banner(16)
	# A sighting is an ambient world event rather than something the player
	# did, and reads in its own cooler ink -- the one per-banner difference.
	(_easter_egg_banner.get_child(0) as Label).add_theme_color_override(
		"font_color", EASTER_EGG_MESSAGE_COLOR
	)


## One message banner: a themed card (UiTheme.panel_stylebox via _ui_theme --
## the same opaque, bordered card the survival panel and CreaturePanel use)
## wrapping a centred, wrapping Label. Hidden until it has something to say.
func _make_message_banner(font_size: int) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	banner.add_child(label)
	_message_stack.add_child(banner)
	return banner


## Sets one banner's text, hiding the whole CARD (not just blanking its text)
## when there is nothing to say -- a hidden VBox child takes no room, so the
## banners below it move up instead of a blank gap opening.
func _set_message_banner(banner: PanelContainer, message: String) -> void:
	(banner.get_child(0) as Label).text = message
	banner.visible = message != ""


## The banners on screen, top to bottom -- the fixed order the stack shows
## them in, with empty ones dropped entirely, so two messages can never land
## on the same line the way the taming and trade banners did (both were
## pinned at offset_top 144). Pinned by test_world_hud.gd.
static func message_banner_lines(
	fishing: String, lasso: String, trade: String, talk: String, easter_egg: String, cast: String
) -> PackedStringArray:
	var lines := PackedStringArray()
	for message in [fishing, lasso, trade, talk, easter_egg, cast]:
		if message != "":
			lines.append(message)
	return lines


func _update_lasso_label(local_player: Player) -> void:
	_set_message_banner(_lasso_banner, local_player.lasso_message)


func _update_fishing_label(local_player: Player) -> void:
	_set_message_banner(_fishing_banner, local_player.fishing_message)


## A shopping prompt/result banner (see Player._shop_step).
func _update_trade_label(local_player: Player) -> void:
	_set_message_banner(_trade_banner, local_player.trade_message)


## A cast result banner (see docs/concept/spell_runtime.md and
## Player.cast_spell) -- same shared-stack shape as every other banner here.
func _update_cast_label(local_player: Player) -> void:
	_set_message_banner(_cast_banner, local_player.cast_message)


## A talk-result banner (see Player._talk_step/NpcGreeting).
func _update_talk_label(local_player: Player) -> void:
	_set_message_banner(_talk_banner, local_player.talk_message)


## The joust arcade-cabinet overlay (see JoustMatchView's own doc comment)
## -- built hidden, parented under _ui like every other overlay in this
## file, and wired to pause/unpause the world for the duration of a match
## (see _on_joust_match_finished and _check_sea_cave_guardian below), the
## same "acts like a real pause screen" pattern _toggle_settings_menu
## already uses for SettingsOverlay.
func _build_joust_view() -> void:
	_joust_view = JoustMatchView.new()
	_joust_view.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(_joust_view)
	_joust_view.match_finished.connect(_on_joust_match_finished)


## The hidden retro handheld's battle + dex screen (see HandheldBattleView's
## own doc comment) -- same "built hidden, parented under _ui, pause/unpause
## for the duration" shape as _build_joust_view just above.
func _build_handheld_view() -> void:
	_handheld_view = HandheldBattleView.new()
	_handheld_view.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(_handheld_view)
	_handheld_view.closed.connect(_on_handheld_closed)


## Undocumented on purpose (docs/concept/easter_eggs.md pillar 3 -- no
## quest marker, no hint pointing here): once every EASTER_EGG_CHECK_
## INTERVAL seconds, rolls each registered sighting against the player's
## current real-world tile. The first that clears both its radius and its
## own rarity roll shows as a brief on-screen line, same shape as the talk/
## trade/fishing banners, then clears itself after EASTER_EGG_MESSAGE_
## DURATION -- there is nothing left to walk up to afterward (see
## EasterEggSightings' own doc comment: no persistent sighting object).
func _check_easter_egg_sightings(player_tile: Vector2i, is_night: bool) -> void:
	for id in _easter_egg_sightings.sighting_ids():
		var message := _easter_egg_sightings.check_one(
			id,
			player_tile.x,
			player_tile.y,
			EarthChunkGenerator.WORLD_WIDTH_TILES,
			EarthChunkGenerator.WORLD_HEIGHT_TILES,
			randf(),
			is_night
		)
		if message != "":
			_set_message_banner(_easter_egg_banner, message)
			_easter_egg_message_timer = EASTER_EGG_MESSAGE_DURATION
			return


## Squallmaw/Coilnecca/Champ (docs/concept/easter_eggs.md) -- unlike
## _check_easter_egg_sightings above, a hit here is a REAL creature: rolls
## each registered id against the player's current tile via
## EasterEggCreatures (same reverse-geo + radius + per-check-roll shape as
## the sightings above), and on a hit, spawns that species a short distance
## from the player with CreatureRenderer.spawn_single -- the exact same API
## the debug /spawn command uses (see _handle_spawn_command). Once spawned
## it's an ordinary CreatureMarker: no despawn timer, no special
## persistence, so "fight, flee, be tamed" is true by construction, same as
## every other creature in the world.
func _check_easter_egg_creature_spawns(player_tile: Vector2i, local_player: Player) -> void:
	if local_player == null:
		return
	for id in _easter_egg_creatures.sighting_ids():
		var species := _easter_egg_creatures.check_one(
			id, player_tile.x, player_tile.y,
			EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES, randf()
		)
		if species != "":
			var offset := Vector2.RIGHT.rotated(randf() * TAU) * EASTER_EGG_CREATURE_SPAWN_DISTANCE
			_creature_renderer.spawn_single(
				_creatures, species, local_player.position + offset, _chunk_manager, TerrainRenderer.TILE_SIZE
			)
			return


## Back to the Future Day (docs/concept/easter_eggs.md) -- gated on the
## REAL system calendar date (utc.month/utc.day, NOT SeasonCycle -- see
## BackToTheFutureDay's own doc comment), not a rarity roll: on the one
## real day a year this is eligible, it fires once per session via the
## same on-screen banner (_easter_egg_label) the sightings cameos already
## use, since there is no real car sprite/art to spawn instead.
func _check_back_to_the_future_day(month: int, day: int) -> void:
	if _bttf_cameo_shown_this_session:
		return
	if not _back_to_the_future_day.is_today(month, day):
		return
	_bttf_cameo_shown_this_session = true
	_set_message_banner(_easter_egg_banner, _back_to_the_future_day.cameo_message())
	_easter_egg_message_timer = EASTER_EGG_MESSAGE_DURATION


## Rush ambient nod (docs/concept/easter_eggs.md) -- LOCATION alone is the
## trigger (see RushAmbientCue's own doc comment: no rarity roll, unlike
## every other coordinate-triggered cameo above), fired once per session on
## approach via the same on-screen banner the other cameos use.
func _check_rush_ambient_cue(player_tile: Vector2i) -> void:
	if _rush_ambient_cue_played:
		return
	if not _rush_ambient_cue.is_in_range(
		player_tile.x, player_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	):
		return
	_rush_ambient_cue_played = true
	_set_message_banner(_easter_egg_banner, _rush_ambient_cue.cameo_message())
	_easter_egg_message_timer = EASTER_EGG_MESSAGE_DURATION
	# TODO(easter-eggs): once a real short original ambient instrumental cue
	# exists (.ogg), attach it here via an AudioStreamPlayer2D at the
	# player's position -- no audio-generation tool was available to this
	# stage, so this cameo is text-only for now; see docs/progress.md.


## The Zork-homage ancient terminal (docs/concept/easter_eggs.md, see
## AncientTerminal's own doc comment) -- called every frame (unlike the
## throttled _check_easter_egg_sightings/_check_rush_ambient_cue above)
## because this needs to catch the single frame Input.is_action_just_
## pressed("talk") is true; throttling to EASTER_EGG_CHECK_INTERVAL would
## silently drop most real key presses. Deliberately re-triggerable (no
## once-per-session guard) -- a terminal you can walk up to and "read"
## again is more in the spirit of a found prop than a one-time cutscene;
## only has_been_found's own latch is permanent.
func _check_ancient_terminal(player_tile: Vector2i, local_player: Player) -> void:
	if not Input.is_action_just_pressed("talk"):
		return
	if not _ancient_terminal.is_in_range(
		player_tile.x, player_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	):
		return
	var already_found := _ancient_terminal.has_been_found()
	_ancient_terminal.mark_found()
	_set_message_banner(
		_easter_egg_banner, "\n".join(_ancient_terminal.terminal_lines())
	)
	_easter_egg_message_timer = ANCIENT_TERMINAL_MESSAGE_DURATION
	# "Three Fragments" hunt (docs/concept/easter_eggs.md) -- quietly leaves
	# behind one small, unremarkable fragment item the FIRST time the
	# terminal is found; re-reading it later (this egg is deliberately
	# re-triggerable, see this function's own doc comment above) does not
	# grant a second copy.
	if not already_found:
		_grant_fragment_and_check_three_fragments_hunt(
			local_player, ThreeFragmentsHunt.TERMINAL_FRAGMENT_ITEM_ID
		)


## The signed secret room (docs/concept/easter_eggs.md, see
## SignedSecretRoom's own doc comment) -- called every frame for the same
## just-pressed reason _check_ancient_terminal is. Watches only the four
## action names SignedSecretRoom.ACTION_SEQUENCE actually needs, appends
## each to a small rolling buffer capped at the sequence's own length, and
## reveals the credit the moment that buffer's tail matches AND the player
## is standing at the room's own location.
func _check_signed_secret_room(player_tile: Vector2i, local_player: Player) -> void:
	for action_name in SignedSecretRoom.ACTION_SEQUENCE:
		if not Input.is_action_just_pressed(action_name):
			continue
		_signed_secret_room_recent_actions.append(action_name)
		var overflow := (
			_signed_secret_room_recent_actions.size() - SignedSecretRoom.ACTION_SEQUENCE.size()
		)
		if overflow > 0:
			_signed_secret_room_recent_actions = _signed_secret_room_recent_actions.slice(overflow)

	if not _signed_secret_room.matches_sequence(_signed_secret_room_recent_actions):
		return
	if not _signed_secret_room.is_in_range(
		player_tile.x, player_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	):
		return
	var already_found := _signed_secret_room.has_been_found()
	_signed_secret_room.mark_found()
	_set_message_banner(_easter_egg_banner, _signed_secret_room.credit_text())
	_easter_egg_message_timer = SIGNED_SECRET_ROOM_MESSAGE_DURATION
	# "Three Fragments" hunt (docs/concept/easter_eggs.md) -- same grant-once
	# shape as _check_ancient_terminal above.
	if not already_found:
		_grant_fragment_and_check_three_fragments_hunt(
			local_player, ThreeFragmentsHunt.SECRET_ROOM_FRAGMENT_ITEM_ID
		)


## The hidden sea cave's guardian (docs/concept/easter_eggs.md's "hidden
## sea cave... dueling-birds cabinet" entry, see SeaCaveGuardian's own doc
## comment) -- called every frame for the same just-pressed reason
## _check_ancient_terminal is. A successful "talk" press in range shows the
## challenge + transform banner text, starts the actual joust
## (_joust_view.start_match), and pauses the world for the duration --
## _on_joust_match_finished unpauses it and reports the outcome once
## JoustMatchView's own match_finished signal fires.
func _check_sea_cave_guardian(player_tile: Vector2i) -> void:
	if not Input.is_action_just_pressed("talk"):
		return
	if not _sea_cave_guardian.can_begin_challenge(
		player_tile.x, player_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	):
		return
	_sea_cave_guardian.begin_challenge()
	_set_message_banner(
		_easter_egg_banner,
		_sea_cave_guardian.challenge_line() + "\n\n" + _sea_cave_guardian.transform_line()
	)
	_easter_egg_message_timer = SEA_CAVE_GUARDIAN_MESSAGE_DURATION
	_joust_view.start_match()
	get_tree().paused = true


## JoustMatchView.match_finished's handler -- unpauses the world (mirroring
## _toggle_settings_menu's own pause/unpause symmetry), frees the guardian
## to be re-challenged (SeaCaveGuardian is deliberately repeatable, see its
## own doc comment), and shows the guardian's own win/lose flavor line
## through the shared Easter-egg banner.
func _on_joust_match_finished(winner: String) -> void:
	get_tree().paused = false
	_sea_cave_guardian.end_challenge()
	_set_message_banner(_easter_egg_banner, _sea_cave_guardian.outcome_line(winner))
	_easter_egg_message_timer = EASTER_EGG_MESSAGE_DURATION


## The hidden retro handheld (docs/concept/easter_eggs.md's "hidden retro
## handheld" entry, see RetroHandheld's own doc comment) -- called every
## frame for the same just-pressed reason _check_ancient_terminal is. A
## successful "talk" press in range shows the found/reopened flavor line,
## opens the actual battle+dex screen (_handheld_view.open), and pauses the
## world for the duration -- _on_handheld_closed unpauses it once the
## player puts the handheld away (HandheldBattleView's own closed signal).
func _check_retro_handheld(player_tile: Vector2i) -> void:
	if not Input.is_action_just_pressed("talk"):
		return
	if not _retro_handheld.can_open(
		player_tile.x, player_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	):
		return
	var already_found := _retro_handheld.has_been_found()
	_retro_handheld.mark_found()
	_retro_handheld.open()
	_set_message_banner(_easter_egg_banner, _retro_handheld.flavor_line(already_found))
	_easter_egg_message_timer = RETRO_HANDHELD_MESSAGE_DURATION
	_handheld_view.open()
	get_tree().paused = true


## HandheldBattleView.closed's handler -- unpauses the world (mirroring
## _on_joust_match_finished's identical pause/unpause symmetry) and frees
## the prop to be reopened (RetroHandheld is deliberately repeatable, see
## its own doc comment).
func _on_handheld_closed() -> void:
	get_tree().paused = false
	_retro_handheld.close()


## Monty Python's Bridgekeeper (docs/concept/easter_eggs.md, see
## BridgekeeperEncounter's own doc comment) -- rolled on the same throttled
## cadence as _check_easter_egg_sightings above (a rarity roll, not a
## per-frame check). Only rolls for a NEW encounter while none is already
## active (_bridgekeeper_riddle_index == -1); the player answers via the
## /answer console command (_handle_bridgekeeper_answer_command).
func _check_bridgekeeper_encounter(player_tile: Vector2i) -> void:
	if _bridgekeeper_riddle_index != -1:
		return
	if not _bridgekeeper.check(
		player_tile.x, player_tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES, randf()
	):
		return
	_bridgekeeper_riddle_index = 0
	_bridgekeeper_correct_count = 0
	_dev_console.log_line("A robed figure blocks the narrow crossing. \"None shall pass unanswered.\"")
	_dev_console.log_line(_bridgekeeper.riddle_text(0))
	_dev_console.log_line("(Reply with /answer <your answer>)")


## /answer <text> (docs/concept/easter_eggs.md's Bridgekeeper egg) --
## deliberately never listed in /help (pillar 3), and a no-op when no
## encounter is active (typing it on a whim outside an encounter does
## nothing, rather than erroring). Advances the riddle index each call;
## once all three are answered, prints passage_message and clears the
## active-encounter state so a later roll can start a fresh one.
func _handle_bridgekeeper_answer_command(args: Array) -> void:
	if _bridgekeeper_riddle_index == -1:
		_dev_console.log_line("There is no one here to answer.")
		return
	var answer := " ".join(args)
	if _bridgekeeper.is_correct_answer(_bridgekeeper_riddle_index, answer):
		_bridgekeeper_correct_count += 1
		_dev_console.log_line("\"...Correct.\" The figure seems faintly surprised.")
	else:
		_dev_console.log_line("\"...Incorrect.\" The figure sighs, unbothered.")
	_bridgekeeper_riddle_index += 1
	if _bridgekeeper_riddle_index >= _bridgekeeper.riddle_count():
		_dev_console.log_line(_bridgekeeper.passage_message(_bridgekeeper_correct_count))
		_bridgekeeper_riddle_index = -1
		return
	_dev_console.log_line(_bridgekeeper.riddle_text(_bridgekeeper_riddle_index))


## Forwarding getter: the clean, testable "was this found" signal a later
## system (docs/concept/easter_eggs.md's "Three Fragments" hunt) can check
## against, without reaching into _ancient_terminal directly.
func has_found_ancient_terminal() -> bool:
	return _ancient_terminal.has_been_found()


## Forwarding getter: same purpose as has_found_ancient_terminal above, for
## the signed secret room.
func has_found_signed_secret_room() -> bool:
	return _signed_secret_room.has_been_found()


## Forwarding getter: same purpose as has_found_ancient_terminal above, for
## the WarGames egg.
func has_found_wargames_egg() -> bool:
	return _wargames_response.has_been_found()


## Forwarding getter: ThreeFragmentsHunt's own has_triggered() latch -- true
## once the "Three Fragments" bonus discovery has fired.
func has_triggered_three_fragments_bonus() -> bool:
	return _three_fragments_hunt.has_triggered()


## Forwarding getter: SeaCaveGuardian's own is_challenge_active() -- lets a
## future system check "is a joust currently in progress" without reaching
## into World's private field directly, the same shape as has_found_
## ancient_terminal/has_found_signed_secret_room above. Not part of "Three
## Fragments" (SeaCaveGuardian was never one of that hunt's three eggs).
func is_sea_cave_challenge_active() -> bool:
	return _sea_cave_guardian.is_challenge_active()


## Forwarding getter: RetroHandheld's own is_open() -- the same shape as
## is_sea_cave_challenge_active above. Not part of "Three Fragments" (the
## handheld was never one of that hunt's three eggs).
func is_handheld_open() -> bool:
	return _retro_handheld.is_open()


## Grants one fragment item of docs/concept/easter_eggs.md's "Three
## Fragments" hunt to local_player, then checks whether the player now holds
## all three -- called from each of the three source eggs' own find sites
## (the ancient terminal, the signed secret room, the /globalthermonuclearwar
## command), each already gated by its own caller on "this egg was NOT
## already found before this call" so a fragment is only ever granted once
## per source egg no matter how many times a re-triggerable egg fires again
## later. A no-op with no local player to give it to (matches _handle_give_
## command's own "no local player" guard).
func _grant_fragment_and_check_three_fragments_hunt(
	local_player: Player, fragment_item_id: String
) -> void:
	if local_player == null:
		return
	local_player.inventory.add(_item_catalog.make(fragment_item_id), 1)
	_check_three_fragments_hunt(local_player)


## docs/concept/easter_eggs.md's "Three Fragments" bonus discovery -- fires
## the moment local_player is found to be holding all three fragment items at
## once (ThreeFragmentsHunt.should_trigger latches permanently via
## mark_triggered, so this can only ever actually fire once per session,
## even though it's re-checked every time a fragment is granted). Reuses the
## same on-screen banner every other cameo in this file uses, and grants
## ThreeFragmentsHunt.BONUS_ITEM_ID -- see that module's own doc comment for
## why this specific payoff was chosen.
func _check_three_fragments_hunt(local_player: Player) -> void:
	if local_player == null:
		return
	var has_terminal := local_player.inventory.has(ThreeFragmentsHunt.TERMINAL_FRAGMENT_ITEM_ID)
	var has_secret_room := local_player.inventory.has(ThreeFragmentsHunt.SECRET_ROOM_FRAGMENT_ITEM_ID)
	var has_wargames := local_player.inventory.has(ThreeFragmentsHunt.WARGAMES_FRAGMENT_ITEM_ID)
	if not _three_fragments_hunt.should_trigger(has_terminal, has_secret_room, has_wargames):
		return
	_three_fragments_hunt.mark_triggered()
	local_player.inventory.add(_item_catalog.make(ThreeFragmentsHunt.BONUS_ITEM_ID), 1)
	_set_message_banner(_easter_egg_banner, _three_fragments_hunt.bonus_message())
	_easter_egg_message_timer = THREE_FRAGMENTS_BONUS_MESSAGE_DURATION


func _update_easter_egg_label(delta: float) -> void:
	if _easter_egg_message_timer <= 0.0:
		return
	_easter_egg_message_timer -= delta
	if _easter_egg_message_timer <= 0.0:
		_set_message_banner(_easter_egg_banner, "")


## The floating "Talk (<key>)" prompt (see _interaction_prompt's own doc
## comment) -- a plain Label parented under _ui like every other HUD text
## (see _hover_tooltip), so its display position needs a manual world-to-
## screen projection via the viewport's canvas transform (the inverse of
## what get_global_mouse_position() does for the hover tooltip's screen-space
## mouse position).
func _build_interaction_prompt() -> void:
	_interaction_prompt = Label.new()
	_interaction_prompt.add_theme_font_size_override("font_size", 12)
	_interaction_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_interaction_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_interaction_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_interaction_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction_prompt.visible = false
	_ui.add_child(_interaction_prompt)


## How wide/tall the charge meter bar reads on screen -- small, since it
## floats above the player's own head rather than sitting in a HUD corner
## like PlayerHealthBar.
const CHARGE_METER_SIZE := Vector2(40.0, 6.0)

## The held-item charge "strengthometer" (see docs/concept/stone.md,
## ChargeMeter, Player.hand_charge_fraction): same Background/Fill
## ColorRect shape as PlayerHealthBar, built dynamically and positioned
## every frame the same world-to-screen way _interaction_prompt is (it
## floats above whichever player is charging, not a fixed HUD corner).
func _build_charge_meter() -> void:
	_charge_meter = Control.new()
	_charge_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_meter.visible = false
	_charge_meter.size = CHARGE_METER_SIZE

	_charge_meter_bg = ColorRect.new()
	_charge_meter_bg.color = Color(0.1, 0.1, 0.1, 0.85)
	_charge_meter_bg.size = CHARGE_METER_SIZE
	_charge_meter.add_child(_charge_meter_bg)

	_charge_meter_fill = ColorRect.new()
	_charge_meter_fill.color = Color(0.85, 0.65, 0.15, 1.0)
	_charge_meter_fill.size = CHARGE_METER_SIZE
	_charge_meter.add_child(_charge_meter_fill)

	_ui.add_child(_charge_meter)


## Every frame: visible only while the local player is actively charging a
## held stone (Player.hand_charge_fraction is 0.0 whenever nothing is in
## hand or the charge input isn't currently held), reusing the SAME
## HealthBar.fill_width pure-logic every other bar in this HUD already
## shares, just fed a [0,1] fraction against a max of 1.0 instead of
## health/max_health.
func _update_charge_meter(local_player: Player) -> void:
	var fraction := local_player.hand_charge_fraction()
	_charge_meter.visible = fraction > 0.0
	if not _charge_meter.visible:
		return
	_charge_meter_fill.size.x = _health_bar.fill_width(fraction, 1.0, CHARGE_METER_SIZE.x)
	var screen_position: Vector2 = (
		get_viewport().get_canvas_transform() * (local_player.position + Vector2(0, -40))
	)
	_charge_meter.position = screen_position - Vector2(CHARGE_METER_SIZE.x / 2.0, 0)


## Every frame: finds the nearest villager within talk range of the local
## player (see EarthChunkManager.nearest_npc_near, Player.TALK_RADIUS) and
## shows/hides+positions "Talk (<key>)" just above their head accordingly.
## Failing that, finds the nearest liftable stone within pickup range (see
## EarthChunkManager.nearest_liftable_stone_near, Player.PICKUP_RADIUS) and
## shows "Pick (<key>)" instead -- a boulder never qualifies (see
## StoneSize.is_liftable), only something the pickup key would actually
## collect. Failing THAT, the same for the nearest dropped item with a
## real, kickable-grade mass (Player.nearest_kickable_dropped_item_near) --
## the generic-item counterpart of the stone case (docs/concept/
## wild_crops.md's "a real physical entity" now also picks into the hand).
## An NPC to talk to takes precedence over anything to pick up when both
## are in range at once: talking is the rarer, more deliberate action, and
## a pebble underfoot isn't going anywhere. All bound keys are read live
## from _keybindings so a rebind is reflected immediately, never a stale
## hardcoded letter.
##
## Throttled to INTERACTION_PROMPT_REFRESH_INTERVAL by the caller (see
## _maybe_update_interaction_prompt) rather than run here every frame -- call
## that wrapper from _client_process, not this directly.
func _update_interaction_prompt(local_player: Player) -> void:
	if not world_hint_visible_for(_chunk_manager != null, _any_gameplay_window_open()):
		_interaction_prompt.visible = false
		return

	var npc = _chunk_manager.nearest_npc_near(local_player.position, Player.TALK_RADIUS)
	if npc != null:
		_show_interaction_prompt("Talk (%s)" % OS.get_keycode_string(_keybindings.keycode_for("talk")), npc.position)
		return

	# Something already in hand: E is now dedicated to charge/release (see
	# Player._pickup_step, the charge meter above the player's own head
	# handles that hint) -- "Pick" would be misleading since pressing the
	# key no longer sweeps a new stone/item into inventory while the hand
	# is full.
	if local_player.is_holding_anything():
		_interaction_prompt.visible = false
		return

	var stone := _chunk_manager.nearest_liftable_stone_near(local_player.position, Player.PICKUP_RADIUS)
	if stone != null:
		_show_interaction_prompt("Pick (%s)" % OS.get_keycode_string(_keybindings.keycode_for("pickup")), stone.position)
		return

	var dropped_item := local_player.nearest_kickable_dropped_item_near(local_player.position, Player.PICKUP_RADIUS)
	if dropped_item != null:
		_show_interaction_prompt(
			"Pick (%s)" % OS.get_keycode_string(_keybindings.keycode_for("pickup")), dropped_item.position
		)
		return

	_interaction_prompt.visible = false


## Gates _update_interaction_prompt behind INTERACTION_PROMPT_REFRESH_INTERVAL
## -- the exact same accumulator shape _client_process already uses inline
## for _hover_accumulator/_update_hover_tooltip, just pulled into its own
## function here so the throttle itself is directly callable (and testable)
## without also invoking the rest of _client_process's per-frame work. Skips
## the real scan on a throttled call and leaves _interaction_prompt exactly
## as the last real scan left it -- Control properties persist on their own,
## so nothing needs to be cached separately for that.
func _maybe_update_interaction_prompt(local_player: Player, delta: float) -> void:
	_interaction_prompt_accumulator += delta
	if _interaction_prompt_accumulator < INTERACTION_PROMPT_REFRESH_INTERVAL:
		return
	_interaction_prompt_accumulator = 0.0
	_update_interaction_prompt(local_player)


## Shows the interaction prompt with `text`, positioned just above
## `world_position` -- shared by the "Talk"/"Pick" cases above so the
## world-to-screen projection math lives in exactly one place.
func _show_interaction_prompt(text: String, world_position: Vector2) -> void:
	_interaction_prompt.visible = true
	_interaction_prompt.text = text
	var screen_position: Vector2 = get_viewport().get_canvas_transform() * (world_position + Vector2(0, -28))
	_interaction_prompt.position = screen_position - Vector2(_interaction_prompt.size.x / 2.0, 0)


func _update_xp_bar(local_player: Player) -> void:
	var xp := local_player.experience
	_xp_fill.size.x = xp.progress_fraction() * SURVIVAL_BAR_WIDTH
	var points := "  (%d pts)" % xp.unspent_points if xp.unspent_points > 0 else ""
	_xp_label.text = "Lv %d — %s%s" % [xp.level, local_player.character_class.capitalize(), points]


## Every frame: hidden unless the local player has unlocked the Naturalist
## "land_sense" keystone; otherwise reads REAL EarthChunkManager.
## land_health_near/vegetation_density_near at the player's own position --
## the exact same numbers the simulation itself runs on (see
## VegetationGrowthModel.effective_capacity/step_land_health), not a
## separate display-only stat. This is the keystone's actual payoff (see
## KeystonePassive._KEYSTONES's own doc comment on why land_sense carries no
## stat bonus).
func _update_land_sense_label(local_player: Player) -> void:
	var unlocked: bool = local_player.unlocked_keystones.get("land_sense", false)
	_land_sense_label.visible = unlocked and _chunk_manager != null
	if not _land_sense_label.visible:
		return
	var land_health := _chunk_manager.land_health_near(local_player.position)
	var vegetation := _chunk_manager.vegetation_density_near(local_player.position)
	_land_sense_label.text = "Land health %d%%  ·  Vegetation %d%%" % [
		int(round(land_health * 100.0)), int(round(vegetation * 100.0))
	]


func _make_survival_meter_row(parent: Control, fill_color: Color) -> Dictionary:
	var row := Control.new()
	row.custom_minimum_size = Vector2(SURVIVAL_BAR_WIDTH, SURVIVAL_BAR_HEIGHT)
	parent.add_child(row)

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.85)
	bg.size = Vector2(SURVIVAL_BAR_WIDTH, SURVIVAL_BAR_HEIGHT)
	row.add_child(bg)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.size = Vector2(SURVIVAL_BAR_WIDTH, SURVIVAL_BAR_HEIGHT)
	row.add_child(fill)

	var label := Label.new()
	label.size = Vector2(SURVIVAL_BAR_WIDTH, SURVIVAL_BAR_HEIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	row.add_child(label)

	return {"fill": fill, "label": label}


## A plain vertical stack of CreaturePanels, left side of the screen below
## the player health bar -- populated/refreshed by _update_creature_panels.
func _build_creature_panels_container() -> void:
	_creature_panels_container = VBoxContainer.new()
	_creature_panels_container.theme = _ui_theme
	_creature_panels_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_creature_panels_container.offset_left = 8.0
	# Below the health bar (top) and the XP bar (y~74), so they don't overlap.
	_creature_panels_container.offset_top = 96.0
	_creature_panels_container.add_theme_constant_override("separation", 4)
	_ui.add_child(_creature_panels_container)


## A small floating label that follows the mouse cursor, showing whichever
## hoverable entity (creature, fish, ambient/piscivore flyer, tree, stone,
## ore, or dropped item -- every type that joins HoverTargetFinder.
## GROUP_NAME) is nearest the cursor, or hidden if nothing is close enough.
func _build_hover_tooltip() -> void:
	_hover_tooltip = Label.new()
	_hover_tooltip.add_theme_font_size_override("font_size", 12)
	_hover_tooltip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hover_tooltip.add_theme_constant_override("shadow_offset_x", 1)
	_hover_tooltip.add_theme_constant_override("shadow_offset_y", 1)
	_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tooltip.visible = false
	_ui.add_child(_hover_tooltip)


## Every frame: finds whichever hoverable entity (creature, fish, ambient/
## piscivore flyer, tree, stone, ore, or dropped item) is nearest the mouse
## cursor (world-space, so it tracks correctly regardless of camera zoom/pan)
## and shows/hides+positions the tooltip label near the cursor accordingly.
## The tooltip shows the entity's name and, for anything with an action
## (pick up, chop, mine, smash, kick...), that action's verb and its live
## keybinding -- ALL of them, if more than one applies (e.g. a pebble reads
## both "Pick Up (E)" and "Kick (K)"). Grass is the one exception: it has no
## per-tuft Node2D to join HoverTargetFinder's group (see
## EarthChunkManager._sync_grass_sprites), so it is checked separately, only
## once nothing else claimed the cursor.
func _update_hover_tooltip() -> void:
	# A tooltip about whatever is behind an open window is noise -- and worse,
	# it draws ON TOP of that window (see world_hint_visible_for). Skipping
	# the scan entirely also saves the per-marker work while a modal is up.
	if not world_hint_visible_for(true, _any_gameplay_window_open()):
		_hover_tooltip.visible = false
		return
	var mouse_world := get_global_mouse_position()
	# The finder only ever picks a target within HOVER_RADIUS_PX of the cursor
	# (relaxed by Spyglass.effective_hover_radius when a Spyglass is equipped
	# -- docs/concept/wayfinding.md's Spyglass item, no new "detection" stat,
	# just the existing hover system resolving from further away), so skip
	# the expensive per-marker work (get_display_name/get_hover_actions +
	# dict alloc) for anything farther away -- turns an O(all loaded trees/
	# stones/creatures) scan into O(the handful under the cursor).
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	var has_spyglass: bool = (
		local_player != null
		and local_player.equipped_item != null
		and local_player.equipped_item.id == "spyglass"
	)
	var scan_radius := Spyglass.effective_hover_radius(HoverTargetFinder.HOVER_RADIUS_PX, has_spyglass)
	var scan_radius_sq := scan_radius * scan_radius
	var candidates: Array = []
	for marker in get_tree().get_nodes_in_group(HoverTargetFinder.GROUP_NAME):
		if mouse_world.distance_squared_to(marker.position) > scan_radius_sq:
			continue
		var actions: Array = (
			marker.get_hover_actions() if marker.has_method("get_hover_actions") else []
		)
		# An animal's actions depend on what the player is HOLDING -- a carrot
		# turns a tied, hungry horse's primary action into Feed -- and a marker
		# cannot see the player's hands, so it answers for empty ones. Only
		# animals care, so only animals are re-asked here.
		var detail := ""
		if marker.has_method("animal_state"):
			var state: Dictionary = marker.animal_state()
			var held := (
				local_player.equipped_item.id
				if local_player != null and local_player.equipped_item != null
				else ""
			)
			actions = AnimalActions.for_animal(state, held)
			detail = _animal_detail_line(state)
		candidates.append({
			"position": marker.position,
			"name": marker.get_display_name(),
			"actions": actions,
			"detail": detail,
		})

	var info := _hover_target_finder.info_under(mouse_world, candidates, scan_radius)
	var found_name: String = info.get("name", "")
	var found_actions: Array = info.get("actions", [])
	var found_detail: String = info.get("detail", "")
	if found_name == "":
		var grass_growth := _chunk_manager.tall_grass_growth_at(mouse_world)
		if grass_growth >= 0.0:
			found_name = "Tall Grass"
			if grass_growth >= 1.0:
				found_actions = [{"verb": "Harvest", "action": "attack"}]

	_hover_tooltip.visible = found_name != ""
	if _hover_tooltip.visible:
		_hover_tooltip.text = _hover_tooltip_text(found_name, found_actions, found_detail)
		_hover_tooltip.position = get_viewport().get_mouse_position() + Vector2(14, -8)


## Formats a hovered entity's name plus, on their own following lines, every
## action it offers with its LIVE keybinding (OS.get_keycode_string, so a
## rebind shows immediately -- the same pattern _show_interaction_prompt
## already uses for the proximity prompt). Multiple actions all show, e.g.
## a pebble reads "Pebble\nPick Up (E)\nKick (K)".
func _hover_tooltip_text(entity_name: String, actions: Array, detail: String = "") -> String:
	var lines := [entity_name]
	if detail != "":
		lines.append(detail)
	for action in actions:
		lines.append(
			"%s (%s)" % [action["verb"], OS.get_keycode_string(_keybindings.keycode_for(action["action"]))]
		)
	return "\n".join(lines)


## One line of an animal's condition for the hover tooltip.
##
## Reported live: hovering an animal named it and said nothing else, while its
## hunger -- the single fact deciding whether feeding it would do anything at
## all -- was simulated the whole time and shown nowhere.
##
## Terse on purpose: a tooltip follows the cursor and is read in a glance, so
## this is the SHORT form (what is wrong, and how tame it is). The full
## percentages live on the creature card, which sits still and can be studied.
func _animal_detail_line(state: Dictionary) -> String:
	var parts := []
	if bool(state.get("tame", false)):
		parts.append("tame")
	elif float(state.get("trust", 0.0)) > 0.0:
		parts.append("trust %d%%" % int(round(float(state["trust"]) * 100.0)))
	if bool(state.get("tied", false)):
		parts.append("tied")
	elif bool(state.get("restrained", false)):
		parts.append("on the rope")
	for flag in ["hungry", "thirsty", "cold", "sick"]:
		if bool(state.get(flag, false)):
			parts.append(flag)
	return ", ".join(parts)


## Big centered "You Died / Respawning in N..." text, hidden until the local
## player's is_dead flag flips (see _update_player_health_bar) -- the actual
## countdown/respawn happens on Player itself (see Player.RESPAWN_DELAY),
## this just displays it.
func _build_death_label() -> void:
	_death_label = Label.new()
	_death_label.text = "You Died"
	_death_label.visible = false
	_death_label.add_theme_font_size_override("font_size", 28)
	_death_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.offset_left = -120.0
	_death_label.offset_top = -60.0
	_death_label.offset_right = 120.0
	_death_label.offset_bottom = 10.0
	_ui.add_child(_death_label)


## Throttled (see CREATURE_PANELS_REFRESH_INTERVAL) rebuild of one HUD panel
## per creature within CREATURE_PANELS_RADIUS of the player, closest first
## and capped at MAX_CREATURE_PANELS -- these are separate HUD widgets (see
## CreaturePanel), not text/labels attached to the creature's world-space
## sprite, so they stay upright and readable regardless of where the
## creature wanders.
func _update_creature_panels(local_player: Player, delta: float) -> void:
	_creature_panels_accumulator += delta
	if _creature_panels_accumulator < CREATURE_PANELS_REFRESH_INTERVAL:
		return
	_creature_panels_accumulator = 0.0

	var nearby: Array = []
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		var distance := local_player.position.distance_to(creature.position)
		if distance <= CREATURE_PANELS_RADIUS:
			nearby.append({"state": creature.animal_state(), "distance": distance})
	nearby.sort_custom(func(a, b): return a.distance < b.distance)

	for child in _creature_panels_container.get_children():
		child.free()

	for i in mini(nearby.size(), MAX_CREATURE_PANELS):
		var panel := CreaturePanel.new()
		_creature_panels_container.add_child(panel)
		panel.set_state(nearby[i].state)


func _unhandled_input(event: InputEvent) -> void:
	if not _world_ready:
		return
	if event.is_action_pressed(CONSOLE_TOGGLE_ACTION):
		_dev_console.toggle()
	elif event.is_action_pressed(INVENTORY_TOGGLE_ACTION):
		_inventory_window.toggle()
	elif event.is_action_pressed(CRAFTING_TOGGLE_ACTION):
		_crafting_window.toggle()
	elif event.is_action_pressed(SKILLS_TOGGLE_ACTION):
		_skill_window.toggle()
		var lp := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		if lp != null:
			_refresh_skill_window(lp)
	elif event.is_action_pressed(SETTINGS_TOGGLE_ACTION):
		_handle_escape()
	else:
		_handle_hotbar_hotkeys(event)


## Escape closes whatever is open, innermost first, and only opens the
## pause/settings menu when the screen is clear (see EscapeAction for the
## priority order). Marks the event handled so one press can't both close a
## surface AND re-open settings -- Escape fires both Godot's built-in
## `ui_cancel` and this project's runtime-bound `toggle_settings`.
func _handle_escape() -> void:
	var action := EscapeAction.action_for(
		_dev_console.visible, _any_gameplay_window_open(), _settings_overlay.is_open()
	)
	match action:
		EscapeAction.CLOSE_CONSOLE:
			# Via toggle(), never `visible = false` -- it also clears
			# ConsoleFocus/keyboard focus, which Player reads to suppress WASD.
			_dev_console.toggle()
		EscapeAction.CLOSE_WINDOWS:
			_close_gameplay_windows()
		EscapeAction.CLOSE_SETTINGS, EscapeAction.OPEN_SETTINGS:
			# Via the wrapper, which also syncs the paused state.
			_toggle_settings_menu()
	get_viewport().set_input_as_handled()


## ## The ecology runs at two cadences
##
## Measured, not assumed. With the world running fast, one frame's worth of
## ecology broke down like this per 30-second slice:
##
##     ecosystem 500ms   flowers 20ms   grass 9ms   worms 2ms   fruiting 4ms
##
## The cheap ones are exactly the ones worth running often -- fruit ripening
## and falling, worms surfacing -- and the expensive ones are periodic batch
## jobs that reconcile or ADD world content: populations, spread, forage
## drops, the vegetation layers. Those are written to run once every minute or
## so of world time, which is invisible at normal speed and ruinous when a
## frame contains several minutes.
##
## So the fine group runs per slice, and the batch group runs once a frame with
## the WHOLE frame's simulated time -- which is what its accumulators want
## anyway: one call that crosses the interval, rather than several that each
## cross it.
##
## This is the same principle as before, sharpened by measurement: a lapse
## accelerates phenology, not population.


## Per slice: cheap, and the things the lapse exists to show.
##
## The world CLOCK is deliberately not advanced here any more. It used to be,
## once per slice, which tied the calendar to the per-FRAME slice budget --
## and a lapse runs at a few frames a second, so the year came out several
## times slower than the rate asked for. The clock now runs at the rate asked
## for, once a frame, independently of how many slices a frame can afford
## (see TimeLapse.calendar_seconds and _process).
func _step_ecology_fine(delta: float, focus_player: Player) -> void:
	_chunk_manager.step_worms(delta)
	if focus_player != null:
		_chunk_manager.step_fruiting(delta, focus_player.position)


## Once a frame, carrying the whole frame's simulated time: the heavy periodic
## work, and everything that adds to the world.
func _step_ecology_batch(delta: float, _focus_player: Player) -> void:
	_chunk_manager.step_ecosystem(delta)
	_chunk_manager.step_forage(delta)
	_chunk_manager.step_tree_spread(delta)
	# Saplings age in place (see EarthChunkManager.step_tree_growth).
	_chunk_manager.step_tree_growth()
	# Ground food rots on world time (see EarthChunkManager.step_ground_food).
	_chunk_manager.step_ground_food(delta)
	# Flies breeding on whatever has gone over (see FlyColony).
	_chunk_manager.step_flies(delta)
	# Food goes off in the pack too, on the same clock (see ItemStack.age).
	_chunk_manager.step_carried_food(delta)
	_chunk_manager.step_tall_grass(delta)
	# Wild carrot/potato growth + spread (see EarthChunkManager.step_wild_crops,
	# docs/concept/wild_crops.md) -- mirrors step_tall_grass's own throttled
	# cadence immediately above. This line was simply missing: the step
	# existed, its own unit tests called it directly and passed, and nothing
	# in a real session ever did -- so a wild crop patch only ever showed the
	# maturity _seed_initial_patches handed it at chunk creation (1.0, mature)
	# and spread never fired once. Same trap the ownership gate fell into (see
	# test_world_simulation_ownership.gd's header), one call level further
	# out. Independently found and fixed on both this branch and main.
	_chunk_manager.step_wild_crops(delta)
	# Player-tilled farm plots (see EarthChunkManager.step_farm_plots,
	# docs/concept/farming.md) -- same tick this crop's wild cousin grows on
	# just above.
	_chunk_manager.step_farm_plots(delta)
	# Ant mounds foraging (see AntColony, myrmecochory) -- fallen grass seed
	# in grassland, or windfall fruit/nut in forest/rainforest where grass
	# doesn't grow -- a background per-chunk population effect, batched here
	# alongside the other content-adding steps rather than the cheap fine
	# group, since it reads grass_seeds_near/fruit_near and plants new
	# grass/saplings the same way the mouse's/squirrel's own scatter-hoarding
	# does.
	_chunk_manager.step_ants(delta)
	_chunk_manager.step_flowers(delta)
	_chunk_manager.step_desert_scrub(delta)
	_chunk_manager.step_tundra_lichen(delta)
	# Every founded settlement is reassessed against its own food stock (see
	# EarthChunkManager.step_settlements/SettlementState) -- population
	# growth/decline pressure, throttled the same way tree spread is, so a
	# real session actually produces settlement_growing/settlement_declining
	# events without a console command.
	_chunk_manager.step_settlements(delta)
	# NPCs sharing a real landmark on their real daily schedule exchange
	# memories automatically (see EarthChunkManager.step_npc_encounters,
	# docs/concept/npc.md "Memory, beliefs, and rumor propagation") -- the
	# one gap that section itself named, now closed the same way
	# step_settlements already is.
	_chunk_manager.step_npc_encounters(delta)
	# A settlement's own real production shortfall (see
	# EarthChunkManager.production_shortfall_quests_for_settlement, Phase
	# 12) can be resupplied by the nearest other real settlement's genuine
	# surplus (see step_regional_trade, docs/concept/regional_trade.md) --
	# the region's own most basic trade network, running automatically.
	# Dispatch is throttled by REGIONAL_TRADE_INTERVAL internally, same
	# accumulator shape as step_settlements above; delivery is now a real
	# caravan trip (see step_caravans, docs/concept/trade.md), not an
	# instant credit.
	_chunk_manager.step_regional_trade(delta)
	_step_herbivore_food_consumption(delta)
	_step_reproduction(delta)


func _any_gameplay_window_open() -> bool:
	return _inventory_window.visible or _crafting_window.is_open() or _skill_window.is_open()


## Whether a WORLD-SPACE floating hint -- the "Talk (G)"/"Pick (E)" prompt,
## the hover tooltip, the message stack -- may be drawn right now.
##
## Every HUD node in this file is a child of the same `_ui` CanvasLayer, so
## draw order is sibling order -- and the floaters are built AFTER the
## inventory/crafting/skill windows in _ready(), which put "Talk (G)" and a
## tooltip about a tree BEHIND the modal on top of the open modal (reported).
## Hiding them is the fix rather than reordering the layers: a hint about the
## world behind a window is noise even in the corners it does not overlap.
##
## `window_open` is _any_gameplay_window_open(), the same predicate
## EscapeAction.action_for already treats as "a modal is open". Deliberately
## NOT widened to the settings overlay (which pauses the tree, so
## _client_process stops running and the floaters freeze rather than update)
## or the dev console (a small bottom strip that overlaps nothing) -- and
## widening it would change what EscapeAction means. Pinned by
## test_world_hud.gd.
static func world_hint_visible_for(can_show: bool, window_open: bool) -> bool:
	return can_show and not window_open


## Closes every open gameplay window at once -- Escape clears the screen
## rather than needing one press per open window.
func _close_gameplay_windows() -> void:
	_inventory_window.visible = false
	_crafting_window.visible = false
	_skill_window.visible = false


## Number keys 1..HOTBAR_SLOT_COUNT (rebindable hotbar_N actions) activate the
## corresponding hotbar slot on the local player -- equipping weapons/tools or
## using consumables (see Player.activate_hotbar_slot).
func _handle_hotbar_hotkeys(event: InputEvent) -> void:
	for i in HOTBAR_SLOT_COUNT:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
			if local_player != null:
				local_player.activate_hotbar_slot(i)
			return


## Dispatches a parsed console command (see ConsoleCommandParser via
## DevConsole) against live game state -- the one place that actually knows
## about the chunk manager, local player, etc.
func _on_console_command(command: String, args: Array) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player

	match command:
		"help":
			_dev_console.log_line(
				(
					"Commands: /day [off]  /night [off]  /time <hh:mm>|off"
					+ "  /season [name]  /weather [state|off]"
					+ "  /ecotest [seconds_per_year|off]"
					+ "  /history <entity_id>  /why <event_id>  /remember <entity_id>"
					+ "  /household <entity_id>  /contract <entity_id>  /market <entity_id>"
					+ "  /institution <entity_id>  /settlement <entity_id>  /boss <entity_id>"
					+ "  /quests <entity_id>  /emergence"
					+ "  /spawn <species> [count]  /give <item_id> [count]"
					+ "  /craft <recipe_id>  /gold <amount>  /village  /species  /help"
					+ "  /compass  /map  /weatherglass  /almanac  /deed"
					+ "  /ledger propose|accept|fulfill|breach ...  /charter found <type> <counterparty_id>"
					+ "  /journal <entity_id>"
				)
			)
		"species":
			# Discoverability: the roster is long enough now that /help
			# listing it inline would drown the other commands.
			_dev_console.log_line("Spawnable: %s" % ", ".join(ConsoleSpecies.spawnable()))
		"day":
			_handle_sky_command("day", args)
		"night":
			_handle_sky_command("night", args)
		"time":
			_handle_time_command(args)
		"history":
			_handle_history_command(args)
		"why":
			_handle_why_command(args)
		"remember":
			_handle_remember_command(args)
		"household":
			_handle_household_command(args)
		"contract":
			_handle_contract_command(args)
		"market":
			_handle_market_command(args)
		"institution":
			_handle_institution_command(args)
		"settlement":
			_handle_settlement_command(args)
		"boss":
			_handle_world_boss_command(args)
		"quests":
			_handle_quests_command(args)
		"emergence":
			_handle_emergence_command()
		"season":
			_handle_season_command(args)
		"weather":
			_handle_weather_command(args)
		"ecotest":
			_handle_ecotest_command(args)
		"spawn":
			_handle_spawn_command(args, local_player)
		"give":
			_handle_give_command(args, local_player)
		"craft":
			_handle_craft_command(args, local_player)
		"gold":
			_handle_gold_command(args, local_player)
		"village":
			_handle_village_command(local_player)
		"compass":
			_handle_compass_command(local_player)
		"map":
			_handle_map_command(local_player)
		"weatherglass":
			_handle_weatherglass_command(local_player)
		"almanac":
			_handle_almanac_command(local_player)
		"deed":
			_handle_deed_command(local_player)
		"ledger":
			_handle_ledger_command(args, local_player)
		"charter":
			_handle_charter_command(args, local_player)
		"journal":
			_handle_journal_command(args, local_player)
		"globalthermonuclearwar":
			# docs/concept/easter_eggs.md's WarGames Easter egg -- deliberately
			# NOT listed in /help's output above (pillar 3, undocumented on
			# purpose): a hidden command prints one original, deadpan homage
			# line (WarGamesResponse) and does nothing else at all -- zero
			# mechanical weight, same as every other cameo in this doc.
			var wargames_already_found := _wargames_response.has_been_found()
			_wargames_response.mark_found()
			_dev_console.log_line(_wargames_response.response_line())
			# "Three Fragments" hunt (docs/concept/easter_eggs.md) -- quietly
			# leaves behind one small, unremarkable fragment item the first
			# time this command is ever run, same "no fanfare" grant-once
			# shape _check_ancient_terminal/_check_signed_secret_room use.
			if not wargames_already_found:
				_grant_fragment_and_check_three_fragments_hunt(
					local_player, ThreeFragmentsHunt.WARGAMES_FRAGMENT_ITEM_ID
				)
		"rolld20":
			# docs/concept/easter_eggs.md's d20 Easter egg -- also never
			# listed in /help (pillar 3): the ONE genuinely-random moment in
			# this entire deterministic-by-design game, deliberately drawn
			# from SecretD20's own dedicated RNG, never the ambient randf()
			# the cameo-rarity checks elsewhere in this file use. Harmless
			# and silly on a natural 20; a complete no-op otherwise.
			_handle_d20_command()
		"answer":
			# docs/concept/easter_eggs.md's Bridgekeeper egg -- also never
			# listed in /help (pillar 3): the reply channel for an in-
			# progress riddle exchange started by _check_bridgekeeper_
			# encounter's own rare roll. A no-op line outside an active
			# encounter, never an error.
			_handle_bridgekeeper_answer_command(args)
		_:
			_dev_console.log_line("Unknown command: /%s (try /help)" % command)


## /history <entity_id> -- an entity's whole recorded history (see
## docs/emergence, EntityRef for the "<kind>:<key>" id shape -- e.g.
## "settlement:3_-7", "npc:483920").
func _handle_history_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /history <entity_id>  e.g. /history settlement:3_-7")
		return
	var entity_id := str(args[0])
	for line in Why.explain_entity(_chunk_manager.event_store(), entity_id).split("
"):
		_dev_console.log_line(line)


## /why <event_id> -- an event's cause-chain provenance trace. Event ids are
## printed by /history (they look like "evt_0_settlement_founded").
func _handle_why_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /why <event_id>  e.g. /why evt_0_settlement_founded")
		return
	var event_id := str(args[0])
	for line in Why.explain_event(_chunk_manager.event_store(), event_id).split("
"):
		_dev_console.log_line(line)


## /remember <entity_id> -- what this entity itself recalls (see MemoryRecord):
## source type and confidence per memory, distinct from /history's
## authoritative record of what it was part of.
func _handle_remember_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /remember <entity_id>  e.g. /remember npc:483920")
		return
	var entity_id := str(args[0])
	for line in Why.explain_memories(_chunk_manager.memory_store(), entity_id).split("
"):
		_dev_console.log_line(line)


## /household <entity_id> -- what household this entity belongs to and what
## it owns (see Household/HouseholdStore).
func _handle_household_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /household <entity_id>  e.g. /household npc:483920")
		return
	var entity_id := str(args[0])
	for line in Why.explain_household(_chunk_manager.household_store(), entity_id).split("
"):
		_dev_console.log_line(line)


## /contract <entity_id> -- every contract this entity is a party to (see
## Contract/ContractStore).
func _handle_contract_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /contract <entity_id>  e.g. /contract household:483920")
		return
	var entity_id := str(args[0])
	for line in Why.explain_contracts(_chunk_manager.contract_store(), entity_id).split("
"):
		_dev_console.log_line(line)


## /market <settlement_id> -- stock and price for a settlement's market (see
## Market/MarketStore).
func _handle_market_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /market <settlement_id>  e.g. /market settlement:673_127")
		return
	var entity_id := str(args[0])
	var market := _chunk_manager.market_store().market_for(entity_id)
	for line in Why.explain_market(market, entity_id).split("
"):
		_dev_console.log_line(line)


## /institution <entity_id> -- every institution this entity has ever
## belonged to, active or dissolved (see Institution/InstitutionStore).
func _handle_institution_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /institution <entity_id>  e.g. /institution household:483920")
		return
	var entity_id := str(args[0])
	for line in Why.explain_institutions(_chunk_manager.institution_store(), entity_id).split("
"):
		_dev_console.log_line(line)


## /settlement <settlement_id> -- food, capacity, households, growth/decline
## status (see SettlementState), town/city tier + specialization derived
## from real institution/production flows (see SettlementTier), and
## governance form + legitimacy derived from real institution history and
## food security (see Governance).
func _handle_settlement_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /settlement <settlement_id>  e.g. /settlement settlement:673_127")
		return
	var entity_id := str(args[0])
	var market := _chunk_manager.market_store().market_for(entity_id)
	var household_count := _chunk_manager.household_count_for_settlement(entity_id)
	var active_institutions := _chunk_manager.active_institution_count_for_settlement(entity_id)
	var production_counts := _chunk_manager.production_counts_for_settlement(entity_id)
	var institution_type_counts := _chunk_manager.institution_type_counts_for_settlement(entity_id)
	# The LIVE VillageMarket too, not just the persisted emergence Market: those
	# are two different things both called "the market", and step_settlements /
	# legitimacy_for_settlement classify a settlement off BOTH (see
	# SettlementFood). Reporting off only the emergence one had /settlement
	# printing "food: 0 (capacity 0) / declining" for a village visibly holding
	# food -- the console contradicting the simulation that had just
	# event-sourced it growing. Null for an unloaded chunk, which
	# explain_settlement handles.
	var village_market = _chunk_manager.village_market_for_settlement(entity_id)
	for line in Why.explain_settlement(
		market, household_count, entity_id, active_institutions, production_counts,
		institution_type_counts, village_market
	).split("
"):
		_dev_console.log_line(line)


## /boss <individual_id> -- every world-boss promotion a real individual has
## ever had (see WorldBossStore, docs/concept/worldbosses.md). No live
## gameplay trigger promotes anyone automatically yet (see
## EarthChunkManager.attempt_world_boss_promotion's own doc comment for
## why), so this will show nothing for an ordinary creature today -- the
## command exists for whenever a real caller starts promoting real
## individuals.
func _handle_world_boss_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /boss <individual_id>  e.g. /boss creature:12345")
		return
	var individual_id := str(args[0])
	for line in Why.explain_world_boss(_chunk_manager.world_boss_store(), individual_id).split("
"):
		_dev_console.log_line(line)


## /quests <settlement_id> -- real, currently-discoverable production
## shortfall quests (see Quest, docs/concept/quests.md "Supply and demand
## quests"). A live projection over real household/market state, not a
## stored list -- recomputed fresh every call.
func _handle_quests_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /quests <settlement_id>  e.g. /quests settlement:673_127")
		return
	var settlement_id := str(args[0])
	var quests := _chunk_manager.production_shortfall_quests_for_settlement(settlement_id)
	for line in Why.explain_quests(quests).split("
"):
		_dev_console.log_line(line)


## /emergence -- store-wide health check: how much has the event substrate
## actually recorded so far.
func _handle_emergence_command() -> void:
	for line in SimulationMetrics.format_report(_chunk_manager.event_store()).split("
"):
		_dev_console.log_line(line)


## /season [name] -- reports the season, or skips the world FORWARD to the
## start of the one you name.
##
## Forward only (see EarthChunkManager.jump_to_season): every other system
## measures itself against this clock, so winding it back would give a tree a
## negative age. Asking for the season you are already in therefore waits for
## it to come round again -- you asked to watch it start.
func _handle_season_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line(
			"Season: %s. Try: %s"
			% [_chunk_manager.current_season(), ", ".join(SeasonCycle.SEASONS)]
		)
		return

	var wanted := str(args[0]).to_lower()
	if not _chunk_manager.jump_to_season(wanted):
		_dev_console.log_line(
			"Unknown season '%s'. Try: %s" % [wanted, ", ".join(SeasonCycle.SEASONS)]
		)
		return
	_dev_console.log_line("Skipped forward to %s." % _chunk_manager.current_season())
	_dev_console.log_line(
		"The world aged to get here -- trees are older, but the fruit you skipped is gone."
	)


## /weather [state|off] -- reports the sky, or pins it.
##
## Weather is a deterministic roll on the day and region, which is right for the
## world and useless for looking at things: to watch snow settle you would
## otherwise wait for a rainy day to come round in winter. Pinned on the model
## itself so every reader agrees -- overlay, soil moisture, wind and snowfall
## all read through the same call.
func _handle_weather_command(args: Array) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	var here := (
		_chunk_manager.current_weather(local_player.position) if local_player != null else "?"
	)
	if args.size() == 0:
		var suffix := " (forced)" if _chunk_manager.is_weather_forced() else ""
		_dev_console.log_line(
			"Weather: %s%s. Try: %s, off"
			% [here, suffix, ", ".join(WeatherModel.STATES)]
		)
		return

	var wanted := str(args[0]).to_lower()
	if wanted == "off":
		# "off" releases a PIN; it does not stop the weather. Saying "back to
		# its own devices" when nothing was pinned reports a change that did
		# not happen, and reads as a broken command to anyone who expected
		# "off" to mean "clear skies" -- which is exactly how it was read
		# during a play session while real autumn rain carried on falling.
		var was_forced := _chunk_manager.is_weather_forced()
		_chunk_manager.clear_forced_weather()
		if was_forced:
			# Re-read AFTER clearing. `here` above was taken while the pin was
			# still in force, and current_weather returns the pinned state
			# first by design -- quoting it would announce the very state this
			# line just deleted ("back to its own devices: rain") while the
			# natural roll was something else entirely.
			var natural := (
				_chunk_manager.current_weather(local_player.position)
				if local_player != null
				else "?"
			)
			_dev_console.log_line("Weather back to its own devices: %s here now." % natural)
		else:
			_dev_console.log_line(
				"Weather was not pinned -- %s here is the real forecast. "
				% here
				+ "(/weather off releases a pin; it does not stop the weather.)"
			)
		return
	if not _chunk_manager.force_weather(wanted):
		_dev_console.log_line(
			"Unknown weather '%s'. Try: %s, off" % [wanted, ", ".join(WeatherModel.STATES)]
		)
		return
	_dev_console.log_line("Weather pinned to %s." % wanted)
	# Snow is rain that falls cold (see Snowfall), so there is no "snow" state
	# to ask for -- it is what rain IS in winter, and saying so here saves
	# hunting for a state that does not exist.
	if wanted == "rain" or wanted == "storm":
		_dev_console.log_line("In winter this falls as snow -- try /season winter with it.")


## /day [off] and /night [off] -- pin the sky for the rest of the session,
## whatever the real sun is doing at the character's real-world coordinates.
##
## These exist because debug builds no longer default to permanent noon (see
## always_day_for): rather than a build type silently deciding, whoever wants
## a particular sky asks for one, and can ask for NIGHT too -- which the old
## default made impossible to see without waiting for real nightfall.
func _handle_sky_command(sky: String, args: Array) -> void:
	_forced_sky = "" if is_off_argument(args) else sky
	if _forced_sky == "":
		_dev_console.log_line("Real day/night cycle restored.")
		return
	_dev_console.log_line(
		"Sky pinned to %s (/%s off to restore the real cycle)." % [sky, sky]
	)


## /time <hh:mm>|off -- pins the LOCAL clock at the character's own longitude
## (the same local-solar-time basis SolarPosition.local_hour already uses for
## the HUD readout), so the sun really is where that hour puts it rather than
## the readout drifting away from the sky. /time off returns to real UTC.
func _handle_time_command(args: Array) -> void:
	if is_off_argument(args):
		_forced_local_hour = NO_FORCED_HOUR
		_dev_console.log_line("Clock back on real time.")
		return
	if args.size() == 0:
		_dev_console.log_line("Usage: /time <hh:mm>  e.g. /time 22:30, or /time off")
		return
	var hour := clock_hour_for_console_argument(str(args[0]))
	if hour == NO_FORCED_HOUR:
		_dev_console.log_line("Not a time: '%s'. Try /time 22:30 or /time off." % str(args[0]))
		return
	_forced_local_hour = hour
	_dev_console.log_line(
		"Local clock pinned to %02d:%02d. /time off for real time."
		% [int(hour), int(round((hour - float(int(hour))) * 60.0))]
	)


## /ecotest [seconds_per_year|off] -- runs the ECOLOGY fast so a whole year
## can be watched: winter into spring into summer into autumn, canopies going
## bare and back into leaf, fruit ripening and falling, saplings coming up and
## growing.
##
## Only the ecology speeds up. The player still moves normally, so you can walk
## around and look at things while the year runs past.
func _handle_ecotest_command(args: Array) -> void:
	if args.size() > 0 and str(args[0]) == "off":
		_ecology_time_scale = ecology_scale_for_console_argument(_ecology_time_scale, "off")
		_dev_console.log_line("Ecology back to normal speed.")
		return

	var seconds_per_year := TimeLapse.DEFAULT_SECONDS_PER_YEAR
	if args.size() > 0:
		var asked := str(args[0]).to_float()
		if asked > 0.0:
			seconds_per_year = asked
	_ecology_time_scale = TimeLapse.scale_for(seconds_per_year)
	# The SEASON rate is now exact at any framerate: the calendar advances by
	# the full requested amount once a frame, while the ecology keeps its
	# measured per-frame slice budget (see TimeLapse.calendar_seconds). What
	# still depends on the machine is how much ecology each frame gets
	# through -- not when the year ends.
	_dev_console.log_line(
		(
			"Seasons now turn a year every %.0fs (%.0fx). How much ecology each"
			+ " frame gets through still depends on the framerate."
		)
		% [seconds_per_year, _ecology_time_scale]
	)
	_dev_console.log_line(
		"Watch the canopies -- a season should turn every half minute or so."
	)
	_dev_console.log_line("Fruit ripens and falls, saplings grow. /ecotest off to stop.")


func _handle_spawn_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to spawn near.")
		return

	var typed := String(args[0]) if args.size() >= 1 else "herbivore"
	# Resolved against the real anatomy roster (plus friendly aliases like
	# "snake"), not the four-entry colour table this used to check -- most
	# species existed in the world but could not be summoned to look at.
	var species := ConsoleSpecies.resolve(typed)
	if species == "":
		_dev_console.log_line(
			"Unknown species '%s'. Try: %s" % [typed, ", ".join(ConsoleSpecies.spawnable())]
		)
		return

	var count := 1
	if args.size() >= 2:
		count = clampi(int(args[1]), 1, MAX_SPAWN_COUNT)

	for i in count:
		var offset := Vector2(
			randf_range(-SPAWN_SCATTER, SPAWN_SCATTER), randf_range(-SPAWN_SCATTER, SPAWN_SCATTER)
		)
		_creature_renderer.spawn_single(
			_creatures, species, local_player.position + offset, _chunk_manager, TerrainRenderer.TILE_SIZE
		)
	_dev_console.log_line("Spawned %d %s." % [count, species])


func _handle_give_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to give items to.")
		return
	if args.is_empty():
		_dev_console.log_line("Usage: /give <item_id> [count]")
		return

	var item_id: String = args[0]
	if not _item_catalog.has(item_id):
		_dev_console.log_line(
			"Unknown item '%s'. Known: %s" % [item_id, ", ".join(_item_catalog.known_ids())]
		)
		return

	var count := 1
	if args.size() >= 2:
		count = clampi(int(args[1]), 1, MAX_GIVE_COUNT)

	local_player.inventory.add(_item_catalog.make(item_id), count)
	_dev_console.log_line("Gave %d x %s." % [count, item_id])


func _handle_craft_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to craft for.")
		return
	if args.is_empty():
		_dev_console.log_line(
			"Usage: /craft <recipe_id>. Known: %s" % ", ".join(_crafting_recipe_book.recipe_ids())
		)
		return

	var recipe_id: String = args[0]
	if local_player.craft(recipe_id):
		_dev_console.log_line("Crafted %s." % recipe_id)
	else:
		_dev_console.log_line(
			"Can't craft '%s' -- missing ingredients or unknown recipe. Known: %s"
			% [recipe_id, ", ".join(_crafting_recipe_book.recipe_ids())]
		)


func _handle_gold_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to give gold to.")
		return
	if args.is_empty():
		_dev_console.log_line("Usage: /gold <amount>")
		return

	var amount := clampi(int(args[0]), 1, MAX_GOLD_COUNT)
	local_player.wallet.add(amount)
	_dev_console.log_line("Gave %d gold." % amount)


## Teleports the local player to the nearest procedurally-placed settlement
## (see SettlementGenerator/VillageFinder), searching outward chunk-by-chunk
## from wherever they currently stand. Lands them at the village's well --
## every settlement always has one (its central landmark) -- rather than an
## arbitrary house edge.
func _handle_village_command(local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to teleport.")
		return

	var destination: Variant = _chunk_manager.find_nearest_village(local_player.current_tile())
	if destination == null:
		_dev_console.log_line("No village found nearby.")
		return

	local_player.position = destination
	_dev_console.log_line("Teleported to the nearest village.")


## /rolld20 (docs/concept/easter_eggs.md's d20 Easter egg, undocumented on
## purpose) -- draws one real roll from SecretD20's own dedicated RNG
## (never the ambient randf() the cameo-rarity checks elsewhere in this
## file already use) and prints the harmless, silly natural-20 payoff, or a
## flat "nothing happens" for every other result.
func _handle_d20_command() -> void:
	var value := _secret_d20.roll(_secret_d20_rng)
	var outcome := _secret_d20.outcome_message(value)
	if outcome == "":
		_dev_console.log_line("You roll a %d. Nothing happens." % value)
	else:
		_dev_console.log_line("You roll a %d! %s" % [value, outcome])


## /compass -- requires "rough_compass" or (fine) "compass" (docs/concept/
## wayfinding.md's Compass item). Bearing toward the world's own spawn point
## (EarthChunkManager.spawn_chunk_coord(), "point me home" -- this item's own
## natural default target before the player ever sets a waypoint). The
## chunk-coord -> pixel conversion reuses the exact same
## chunk_coord*CHUNK_SIZE + half-chunk-tile-offset pattern
## EarthChunkManager already uses elsewhere (e.g. its worm-patch climate
## sampling), fed through this file's own existing tile -> pixel-center
## helper (_spawn_position_for_tile) rather than a third formula.
func _handle_compass_command(local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to read a compass for.")
		return
	var has_fine: bool = local_player.inventory.has("compass")
	if not has_fine and not local_player.inventory.has("rough_compass"):
		_dev_console.log_line("You don't have a compass.")
		return

	var chunk_coord := _chunk_manager.spawn_chunk_coord()
	var centre_tile := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(
		EarthChunkManager.CHUNK_SIZE / 2, EarthChunkManager.CHUNK_SIZE / 2
	)
	var target_world_position := _spawn_position_for_tile(centre_tile)
	var bearing := Compass.bearing_degrees(local_player.position, target_world_position)
	var reading := Compass.reading_for(bearing, has_fine)
	_dev_console.log_line("Compass: %.1f degrees toward home." % reading)


## /map -- requires "map" (docs/concept/wayfinding.md's Map item). Visual map
## rendering is explicitly out of scope for this pass regardless -- a
## text-only report is the intended MVP: how many chunks have been explored,
## plus which real, already-founded settlements (EventStore's own
## "settlement_founded" events -- the same real source
## EarthChunkManager._known_settlement_ids reads internally, just read here
## through the already-public event_store() accessor, the same "/why"
## precedent every other command in this file follows) fall inside that
## explored set, via MapProjection.landmarks_visible_on_map.
func _handle_map_command(local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to read a map for.")
		return
	if not local_player.inventory.has("map"):
		_dev_console.log_line("You don't have a map.")
		return

	var explored: Array = _chunk_manager.explored_chunks()
	_dev_console.log_line("Map: %d chunk(s) explored." % explored.size())

	var known_landmarks: Array = []
	for event in _chunk_manager.event_store().events_of_type("settlement_founded"):
		if event.actors.is_empty():
			continue
		var settlement_id: String = event.actors[0]
		known_landmarks.append(
			{"chunk_coord": RegionalTrade.chunk_coord_of(settlement_id), "id": settlement_id}
		)

	var visible: Array = MapProjection.landmarks_visible_on_map(explored, known_landmarks)
	if visible.is_empty():
		_dev_console.log_line("No known settlements fall inside explored territory yet.")
		return
	var ids: Array = []
	for landmark in visible:
		ids.append(landmark.get("id"))
	_dev_console.log_line("Settlements visible: %s" % ", ".join(ids))


## /weatherglass -- requires "weather_glass" (docs/concept/wayfinding.md's
## Weather glass item). Current sky plus WeatherForecast's own
## instrument-grade-vague read of what's coming, never an exact-hour
## cheat-omniscient forecast.
func _handle_weatherglass_command(local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to read a weather glass for.")
		return
	if not local_player.inventory.has("weather_glass"):
		_dev_console.log_line("You don't have a weather glass.")
		return

	var current := _chunk_manager.current_weather(local_player.position)
	var upcoming := _chunk_manager.upcoming_weather(local_player.position)
	_dev_console.log_line(
		"Weather glass: %s now. %s." % [current, WeatherForecast.forecast_label(current, upcoming)]
	)


## /almanac -- requires "star_chart" (docs/concept/wayfinding.md's Star
## chart item). Current season, the next one, and real days remaining until
## it turns.
func _handle_almanac_command(local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to read a star chart for.")
		return
	if not local_player.inventory.has("star_chart"):
		_dev_console.log_line("You don't have a star chart.")
		return

	var current := _chunk_manager.current_season()
	var next_season := SeasonAlmanac.next_season(current)
	var days := SeasonAlmanac.days_until_next_season(_chunk_manager.world_age_seconds())
	_dev_console.log_line(
		"Almanac: %s now, %s next (%.1f days)." % [current, next_season, days]
	)


## /deed -- requires "deed" (docs/concept/player_citizenship.md's Deed
## item). Claims the plot the player currently stands on -- a marked,
## unbuilt plot is a valid Deed target per that doc's own Deed section,
## alongside an existing structure; no "nearest structure" query exists
## yet, a named, in-spec scoping choice for this pass, not a shortcut
## around the design. The tile -> chunk-coord conversion replicates
## EarthChunkManager._chunk_coord_for_tile's own real formula exactly
## (floori(tile / CHUNK_SIZE) per axis) rather than inventing a different one.
func _handle_deed_command(local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to claim property for.")
		return
	if not local_player.inventory.has("deed"):
		_dev_console.log_line("You don't have a deed.")
		return

	var tile := local_player.current_tile()
	var chunk := Vector2i(
		floori(float(tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	var property_id := EntityRef.for_kind("house", "player_claim_%d_%d" % [chunk.x, chunk.y])
	# Claiming land inside a settlement that already exists also makes the
	# player a MEMBER of it (see concept/player_citizenship.md's "Residency").
	# Named from the SAME chunk the property id is derived from, so a deed can
	# never claim land in one place and make you a citizen of another. Passed
	# unconditionally: the "is there actually a settlement here" guard lives in
	# record_player_settled_if_new, where the event graph is the authority --
	# gating the claim itself would break claiming land in open wilderness,
	# which is legitimate and should still make you a landowner.
	var settlement_id := EntityRef.for_settlement(chunk)
	var household := _chunk_manager.claim_property_with_deed(property_id, settlement_id)
	_dev_console.log_line("Claimed %s for household %s." % [property_id, household.id])


## /ledger propose <type> <counterparty_id> <consideration> <deadline_seconds>
## /ledger accept|fulfill|breach <contract_id>
## -- requires "ledger" (docs/concept/player_citizenship.md's Ledger item).
## Obligations authoring is out of scope for this pass -- propose always
## sends an empty obligations array, a named gap, not an oversight.
func _handle_ledger_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to use a ledger for.")
		return
	if not local_player.inventory.has("ledger"):
		_dev_console.log_line("You don't have a ledger.")
		return
	if args.is_empty():
		_dev_console.log_line(
			"Usage: /ledger propose <type> <counterparty_id> <consideration> <deadline_seconds>"
			+ "  |  /ledger accept|fulfill|breach <contract_id>"
		)
		return

	var sub: String = args[0]
	match sub:
		"propose":
			if args.size() < 5:
				_dev_console.log_line(
					"Usage: /ledger propose <type> <counterparty_id> <consideration> <deadline_seconds>"
				)
				return
			var type: String = args[1]
			var counterparty_id: String = args[2]
			var consideration: String = args[3]
			var deadline: float = str(args[4]).to_float()
			var contract := _chunk_manager.player_propose_contract(
				type, counterparty_id, [], consideration, deadline
			)
			_dev_console.log_line("Proposed contract %s." % contract.id)
		"accept":
			if args.size() < 2:
				_dev_console.log_line("Usage: /ledger accept <contract_id>")
				return
			var contract_id: String = args[1]
			_dev_console.log_line("Accepted: %s" % _chunk_manager.accept_contract(contract_id))
		"fulfill":
			if args.size() < 2:
				_dev_console.log_line("Usage: /ledger fulfill <contract_id>")
				return
			var contract_id: String = args[1]
			_dev_console.log_line("Fulfilled: %s" % _chunk_manager.fulfill_contract(contract_id))
		"breach":
			if args.size() < 2:
				_dev_console.log_line("Usage: /ledger breach <contract_id>")
				return
			var contract_id: String = args[1]
			_dev_console.log_line("Breached: %s" % _chunk_manager.breach_contract(contract_id))
		_:
			_dev_console.log_line(
				"Unknown /ledger action '%s'. Try: propose, accept, fulfill, breach" % sub
			)


## /charter found <type> <counterparty_id> -- requires "charter" (docs/
## concept/player_citizenship.md's Charter item). No craftable "charter"
## item id exists yet -- a named, pre-existing gap (none of the other 9
## wayfinding/citizenship items' registration pass covered this one, per
## docs/progress.md's own Player Citizenship entry) -- so this command is
## real and fully wired but currently unreachable by a player until that
## item is registered.
func _handle_charter_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to use a charter for.")
		return
	if not local_player.inventory.has("charter"):
		_dev_console.log_line("You don't have a charter.")
		return
	if args.size() < 3 or str(args[0]) != "found":
		_dev_console.log_line("Usage: /charter found <type> <counterparty_id>")
		return

	var type: String = args[1]
	var counterparty_id: String = args[2]
	var institution := _chunk_manager.player_attempt_institution_formation(type, counterparty_id)
	if institution == null:
		_dev_console.log_line("Not enough shared history yet.")
		return
	_dev_console.log_line("Founded institution %s." % institution.id)


## /journal <entity_id> -- requires "field_journal" (docs/concept/
## player_citizenship.md's Field Journal item). Builds the stores
## Dictionary FieldJournal.entry_for needs directly from _chunk_manager's
## own public store accessors (household_store()/institution_store()/
## world_boss_store()/event_store()) -- the exact same accessors /household,
## /institution, /boss, and /history already read directly in this file, so
## no new coordinator method was needed on EarthChunkManager.
func _handle_journal_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to read a field journal for.")
		return
	if not local_player.inventory.has("field_journal"):
		_dev_console.log_line("You don't have a field journal.")
		return
	if args.is_empty():
		_dev_console.log_line("Usage: /journal <entity_id>  e.g. /journal settlement:673_127")
		return

	var entity_id: String = args[0]
	var stores := {
		"household_store": _chunk_manager.household_store(),
		"institution_store": _chunk_manager.institution_store(),
		"world_boss_store": _chunk_manager.world_boss_store(),
		"event_store": _chunk_manager.event_store(),
	}
	for line in FieldJournal.entry_for(entity_id, stores).split("
"):
		_dev_console.log_line(line)


## Spawns a clickable ground item where a creature died or a tree dropped
## forage. Only the simulation-owning side (server/singleplayer) holds the
## authoritative item layer for now -- ground items aren't replicated yet.
func _on_item_dropped(item_stack, world_position: Vector2) -> void:
	if _ground_items.get_child_count() >= MAX_GROUND_ITEMS:
		_ground_items.get_child(0).queue_free()  # drop the oldest to stay bounded
	var dropped := DroppedItem.new()
	dropped.item_stack = item_stack
	dropped.position = world_position
	# Food rots on world time with a real shelf life; everything else keeps the
	# flat despawn, which is a tidiness rule rather than a spoilage one (see
	# FruitSpoilage and EarthChunkManager.step_ground_food).
	if item_stack != null and item_stack.item.kind == "food":
		dropped.ages_on_world_time = true
		dropped.spoil_seconds = FruitSpoilage.edible_seconds(
			item_stack.item.id, _chunk_manager.current_season()
		)
	_ground_items.add_child(dropped)


## Refreshes the real inventory window (see InventoryWindow) from the local
## player's stacks -- only while it's actually open, so a hidden window isn't
## rebuilding its item grid every frame for nothing. Note the inventory lives
## on the server-authoritative Player; a networked client sees its local
## proxy's copy, which isn't yet synced from the server (known gap).
func _update_inventory_window(local_player: Player) -> void:
	if not _inventory_window.visible:
		return
	_refresh_inventory_now(local_player)


## Refreshes the crafting menu's affordability while it's open (see
## CraftingWindow) -- same open-only guard as the inventory window.
func _update_crafting_window(local_player: Player) -> void:
	if not _crafting_window.visible:
		return
	_crafting_window.refresh(local_player.inventory_counts())


func _update_player_health_bar(local_player: Player) -> void:
	var width := _health_bar.fill_width(local_player.health, local_player.max_health, _player_health_bg.size.x)
	_player_health_fill.size.x = width
	_player_health_label.text = "HP %d / %d" % [int(local_player.health), int(local_player.max_health)]

	_death_label.visible = local_player.is_dead
	if local_player.is_dead:
		var remaining := Player.RESPAWN_DELAY - local_player._respawn_accumulator
		_death_label.text = "You Died\nRespawning in %d..." % ceili(maxf(remaining, 0.0))


## The reserve left of a meter SurvivalMeters stores as a DEFICIT.
##
## hunger and thirst rise toward 1.0 as they worsen (that is how the model
## integrates them); stamina and warmth are already stored the other way up.
## The HUD shows all four as reserves so that one panel never means two
## opposite things at once -- reported: "Hunger 100%" printed over an EMPTY
## bar, two rows above "Warmth 100%" over a full one. Pinned by
## test_world_hud.gd; see docs/concept/hud.md and docs/concept/survival.md.
static func reserve_for_deficit(deficit: float) -> float:
	return clampf(1.0 - deficit, 0.0, 1.0)


## One meter's label. Takes the SAME reserve fraction the bar beside it is
## filled with, so the number and the bar are the same value by construction
## rather than by two lines agreeing to stay in step.
static func meter_label_text(meter_name: String, reserve: float) -> String:
	return "%s %d%%" % [meter_name, int(round(clampf(reserve, 0.0, 1.0) * 100.0))]


## Every meter reads as a RESERVE: full is good, and the number always says
## the same thing as the bar under it -- the same convention the health bar
## has always used. Food and Water are named for what is LEFT rather than for
## what is missing (see reserve_for_deficit).
func _update_survival_bar(local_player: Player) -> void:
	var s := local_player.survival
	var food := reserve_for_deficit(s.hunger)
	_hunger_fill.size.x = _health_bar.fill_width(food, 1.0, SURVIVAL_BAR_WIDTH)
	_hunger_label.text = meter_label_text("Food", food)
	var water := reserve_for_deficit(s.thirst)
	_thirst_fill.size.x = _health_bar.fill_width(water, 1.0, SURVIVAL_BAR_WIDTH)
	_thirst_label.text = meter_label_text("Water", water)
	_stamina_fill.size.x = _health_bar.fill_width(s.stamina, 1.0, SURVIVAL_BAR_WIDTH)
	_stamina_label.text = meter_label_text("Stamina", s.stamina)
	_warmth_fill.size.x = _health_bar.fill_width(s.warmth, 1.0, SURVIVAL_BAR_WIDTH)
	var warmth_state := "Freezing" if s.is_freezing() else ("Cold" if s.is_cold() else "Warmth")
	_warmth_label.text = meter_label_text(warmth_state, s.warmth)
	_wallet_label.text = "Gold: %d" % local_player.wallet.balance


## Builds HOTBAR_SLOT_COUNT empty slot backgrounds once; _update_hotbar fills
## in icons/counts from the current inventory each frame.
func _build_hotbar_slots() -> void:
	for i in HOTBAR_SLOT_COUNT:
		var slot := _make_hud_slot(HUD_SLOT_BG_COLOR, true)
		# Left-click activates a slot, same as its number hotkey; right-click
		# clears its assignment (see _on_hotbar_slot_gui_input) -- previously
		# the only way to change a bound slot was to drag a different item
		# over it, with no way to just empty one out.
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_hotbar_slot_gui_input.bind(i))
		# A hover brighten, matching InventoryWindow's own item slots -- the
		# hotbar previously gave no feedback at all that a slot was
		# interactive under the cursor.
		slot.mouse_entered.connect(func(): slot.modulate = Color(1.15, 1.15, 1.15))
		slot.mouse_exited.connect(func(): slot.modulate = Color(1, 1, 1))
		# Dropping an inventory item here binds it to this number key (see
		# Hotbar / InventoryWindow's drag source).
		slot.can_accept = func(payload):
			return payload is Dictionary and payload.get("source", "") == InventoryWindow.DRAG_SOURCE_INVENTORY
		slot.dropped = func(payload): _on_hotbar_slot_dropped(i, payload)

		var index_label := Label.new()
		index_label.text = str(i + 1)
		index_label.add_theme_font_size_override("font_size", 9)
		index_label.modulate = Color(1, 1, 1, 0.5)
		index_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(index_label)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		var count_label := Label.new()
		count_label.name = "Count"
		count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count_label.add_theme_font_size_override("font_size", 10)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count_label)

		_hotbar.add_child(slot)
		_hotbar_slots.append(icon)
		_hotbar_counts.append(count_label)
		_hotbar_slot_frames.append(slot)
		_hotbar_slot_state.append("<unset>")  # sentinel: forces first real refresh


## A left-click on hotbar slot `index` activates it (equip/use), same as its
## number hotkey. A right-click instead CLEARS whatever's bound there --
## previously the only way to change a slot was to drag a different item
## over it, with no way to just empty one out (matching InventoryWindow's
## own left-drags/right-uses split, see that scene's doc comment).
func _on_hotbar_slot_gui_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player == null:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		local_player.activate_hotbar_slot(index)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		local_player.hotbar.clear_slot(index)


## Dropping an inventory item onto hotbar slot `index` binds that item to the
## slot's number key (see Player.assign_hotbar_slot / Hotbar).
func _on_hotbar_slot_dropped(index: int, payload: Dictionary) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null:
		local_player.assign_hotbar_slot(index, String(payload.get("item_id", "")))


## A fixed row of locked placeholder slots for future abilities -- there is no
## spell/ability system yet (see docs/progress.md), so these are an honest
## stub, not fake functionality.
func _build_spell_bar() -> void:
	for i in SPELL_BAR_SLOT_COUNT:
		_spell_bar.add_child(_make_hud_slot(HUD_SLOT_LOCKED_COLOR))


## A HUD slot frame. `droppable` makes it a DragSlot (see drag_slot.gd) so
## the caller can wire can_accept/dropped -- the hotbar accepts inventory
## drags, the spell-bar placeholders don't.
func _make_hud_slot(color: Color, droppable: bool = false) -> PanelContainer:
	var slot: PanelContainer = DragSlot.new() if droppable else PanelContainer.new()
	slot.custom_minimum_size = Vector2(HUD_SLOT_SIZE, HUD_SLOT_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.2)
	slot.add_theme_stylebox_override("panel", style)
	return slot


## Fills the hotbar's slot icons/counts from whatever item id each slot is
## bound to (see Player.hotbar / Hotbar) -- an explicit assignment made by
## dragging an item onto the slot, or an auto-filled one. Empty slots are
## left blank.
func _update_hotbar(local_player: Player) -> void:
	for i in HOTBAR_SLOT_COUNT:
		var item_id := local_player.hotbar.item_id_at(i)
		var count := local_player.inventory.count_of(item_id) if item_id != "" else 0
		# Skip slots whose (item, count) is unchanged since last frame: rebuilding
		# the icon/count every frame regenerated a GPU texture per slot per frame
		# (a real hitch source). Only touch a slot when it actually changed.
		var state := "%s:%d" % [item_id, count]
		if _hotbar_slot_state[i] == state:
			continue
		_hotbar_slot_state[i] = state
		if item_id != "" and count > 0:
			# texture_for() hits a shared static cache keyed by id (no per-frame
			# image build / GPU upload) -- item art is a pure function of the id.
			_hotbar_slots[i].texture = _item_sprite_generator.texture_for(_sprite_id_for_item(item_id))
			_hotbar_counts[i].text = str(count) if count > 1 else ""
			_hotbar_slot_frames[i].tooltip_text = _hotbar_tooltip_text(item_id, count)
		else:
			_hotbar_slots[i].texture = null
			_hotbar_counts[i].text = ""
			_hotbar_slot_frames[i].tooltip_text = "Drag an item here to bind it"


## The sprite_id to render for `item_id` (see docs/concept/item_illustrations.md):
## every renderer looks up its picture via an item's sprite_id, never its raw
## id, so a variant item can share a base item's art. Falls back to the raw id
## for one the catalog doesn't know -- ProceduralItemSprite's own generic
## fallback already handles an unrecognized id gracefully, same as
## _hotbar_tooltip_text's display-name fallback just below.
func _sprite_id_for_item(item_id: String) -> String:
	return _item_catalog.make(item_id).sprite_id if _item_catalog.has(item_id) else item_id


## "Iron Sword\nx3\nRight-click to clear" -- what's bound, how many, and how
## to unbind it, matching InventoryWindow's own item tooltips instead of the
## hotbar giving no hover feedback at all.
func _hotbar_tooltip_text(item_id: String, count: int) -> String:
	var lines := [_item_catalog.make(item_id).display_name if _item_catalog.has(item_id) else item_id]
	if count > 1:
		lines.append("x%d" % count)
	lines.append("Right-click to clear")
	return "\n".join(lines)


## The player is always the center sample of MinimapRenderer's image, so the
## static, screen-anchored PlayerDot child never needs to move -- only the
## terrain texture underneath it refreshes.
func _update_minimap(player_tile: Vector2i, delta: float) -> void:
	_minimap_refresh_accumulator += delta
	if _minimap_refresh_accumulator < MINIMAP_REFRESH_INTERVAL:
		return
	_minimap_refresh_accumulator = 0.0
	var image := _minimap_renderer.build_image(_chunk_manager, player_tile)
	_minimap.texture = ImageTexture.create_from_image(image)


## Server-only: called once per connecting peer. Computes a real spawn
## position (server-authoritative -- the client never picks its own spawn
## point) and spawns a Player under $Players named after the peer id (the
## standard Godot multiplayer node-name convention, so RPCs/replication route
## to the right instance on every peer). MultiplayerSpawner replicates this
## addition -- including the initial position -- to all clients automatically.
func _on_peer_connected(peer_id: int) -> void:
	var player := PlayerScene.instantiate()
	player.name = str(peer_id)
	player.position = _spawn_position_for_tile(await _compute_dry_land_spawn_tile())
	player.respawn_position = player.position
	_players.add_child(player)
	# So its pack ages and, once something in it turns, smells (see
	# EarthChunkManager.register_scent_carrier).
	_chunk_manager.register_scent_carrier(player)
	player.setup(_chunk_manager, TerrainRenderer.TILE_SIZE)
	print("[server] peer %d connected, spawned player" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	print("[server] peer %d disconnected" % peer_id)


func _on_connected_to_server() -> void:
	print("[client] connected, own peer id %d" % multiplayer.get_unique_id())


## Layers a rolled DNA genome's stat swing (see HeroDna) on top of a class's
## own base stats -- additive per key, never mutating `base` itself, so a
## rare/legendary roll's "excellent magic attack but no defense" actually
## shows up on the spawned character instead of being computed and dropped.
func _stats_with_dna(base: Dictionary, dna_stat_modifiers: Dictionary) -> Dictionary:
	var stats := base.duplicate()
	for key in dna_stat_modifiers:
		stats[key] = float(stats.get(key, 0.0)) + float(dna_stat_modifiers[key])
	return stats


## Only used when running with no networking at all (quick local playtesting).
func _spawn_local_singleplayer() -> void:
	var player := PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	player.position = _spawn_position_for_tile(await _compute_dry_land_spawn_tile())
	player.respawn_position = player.position
	# BEFORE apply_class: the class start node it grants is a real web node, and
	# what that node is worth to this character depends on the resonance the
	# genome rolls here (see Player._grant_class_start_node).
	if _pending_dna_seed != 0:
		player.apply_dna_seed(_pending_dna_seed)
	player.apply_class(
		_pending_class,
		_stats_with_dna(_class_archetypes.stats_for(_pending_class), _pending_dna_stat_modifiers),
		_pending_appearance
	)
	_players.add_child(player)
	# So its pack ages and, once something in it turns, smells (see
	# EarthChunkManager.register_scent_carrier).
	_chunk_manager.register_scent_carrier(player)
	player.setup(_chunk_manager, TerrainRenderer.TILE_SIZE)


## Restores a previously saved character (see docs/concept/persistence.md):
## spawns at the saved position instead of running the dry-land search (a
## saved position is already valid ground), applies the saved class/
## appearance via apply_class for the character-view wiring (setup below
## still runs after, mirroring _spawn_local_singleplayer's own ordering), then
## restores everything apply_class doesn't cover (health, inventory,
## equipment, wallet, hotbar, skill progress) via apply_save_dict LAST --
## apply_class alone always fully heals/starts with default gear, which is
## only correct for a genuinely new character.
func _spawn_local_singleplayer_from_save() -> void:
	var save_data := _player_save.load_data()
	var player := PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	var saved_position: Vector2 = save_data.get("position", Vector2.ZERO)
	player.position = saved_position
	player.respawn_position = save_data.get("respawn_position", saved_position)
	# Same ordering reason as _spawn_local_singleplayer, from the saved seed
	# instead of the creator's; apply_save_dict below re-applies it anyway, but
	# apply_class runs first and must already know this character's genome.
	if int(save_data.get("dna_seed", 0)) != 0:
		player.apply_dna_seed(int(save_data["dna_seed"]))
	player.apply_class(
		save_data.get("character_class", _pending_class),
		_class_archetypes.stats_for(save_data.get("character_class", _pending_class)),
		save_data.get("appearance", {})
	)
	_players.add_child(player)
	# So its pack ages and, once something in it turns, smells (see
	# EarthChunkManager.register_scent_carrier).
	_chunk_manager.register_scent_carrier(player)
	player.setup(_chunk_manager, TerrainRenderer.TILE_SIZE)
	# Resumes the world clock BEFORE the first update() -- update() loads
	# chunks, and chunk-loading reads _world_age_seconds itself (sapling ages,
	# ecology catchup), so this has to land before that or the loaded-in world
	# briefly sees the wrong clock (see EarthChunkManager.load_world_clock /
	# docs/concept/seasons.md: a resumed game must pick up exactly where its
	# own save left off, never re-roll a new random start the way New Game
	# does).
	_chunk_manager.load_world_clock()
	await _chunk_manager.update_with_progress(_tile_for_position(saved_position), _on_chunk_load_progress)
	player.apply_save_dict(save_data)
	# Restores whatever history and memory a prior session recorded -- the
	# same "Load Game means exactly where you left off" pillar the player
	# state above already follows (see docs/concept/persistence.md).
	_chunk_manager.load_event_store()
	_chunk_manager.load_memory_store()
	_chunk_manager.load_household_store()
	_chunk_manager.load_contract_store()
	_chunk_manager.load_market_store()
	_chunk_manager.load_institution_store()
	_chunk_manager.load_world_boss_store()


## The world position a player spawning on `tile` should take: the tile's
## CENTER, matching the `(cell + 0.5) * TILE_SIZE` convention every other
## placed entity uses (trees/creatures/structures -- see EarthChunkManager).
## Spawning at the tile's raw corner instead put the hero's sprite (drawn
## centered on its position) straddling four tiles -- reported as "the
## player is offset by half a tile".
func _spawn_position_for_tile(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE


## Same pixel-position -> wrapped-tile conversion Player.current_tile() uses,
## needed here before a Player exists yet to load chunks around a saved spot.
func _tile_for_position(pixel_position: Vector2) -> Vector2i:
	var raw := Vector2i(
		floori(pixel_position.x / TerrainRenderer.TILE_SIZE),
		floori(pixel_position.y / TerrainRenderer.TILE_SIZE)
	)
	var world_size := Vector2i(EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	return _world_coordinates.wrap(raw, world_size)


## Periodic player-state autosave (see docs/concept/persistence.md and
## AUTOSAVE_INTERVAL) -- mirrors the world's own eager-persistence
## philosophy so progress is never more than one short interval old. Only
## reached from _client_process, which already only runs for a real local
## client (not a dedicated server).
func _autosave_step(local_player: Player, delta: float) -> void:
	_autosave_accumulator += delta
	if _autosave_accumulator < AUTOSAVE_INTERVAL:
		return
	_autosave_accumulator = 0.0
	_save_local_player(local_player)


func _save_local_player(player: Player) -> void:
	_player_save.save(player.to_save_dict())
	# Persisted alongside the player on the same cadence -- world-scoped
	# state, so it belongs with the autosave/quit-save that already covers
	# the rest of what a session accumulates, not a separate schedule.
	_chunk_manager.save_event_store()
	_chunk_manager.save_memory_store()
	_chunk_manager.save_household_store()
	_chunk_manager.save_contract_store()
	_chunk_manager.save_market_store()
	_chunk_manager.save_institution_store()
	_chunk_manager.save_world_boss_store()
	# The world clock too -- without this, New Game's random starting point
	# (see EarthChunkManager.randomize_world_age) would never actually reach
	# disk, and a Load Game would fall back to the pre-persistence default of
	# world-age 0 instead of resuming where the session left off.
	_chunk_manager.save_world_clock()


## Also saves once right before the window actually closes (OS close button/
## Alt+F4), so quitting never loses the last AUTOSAVE_INTERVAL of progress.
## A no-op if no local player has spawned yet (e.g. quitting from the main
## menu) or on a dedicated server (no single "local" player to speak of).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null:
		_save_local_player(local_player)
	get_tree().quit()


## Connects to a host at an explicit address (from the Join menu), rather than
## from a --connect cmdline arg. Live connectivity on this dev machine is
## blocked by CrowdStrike (see progress.md Multiplayer notes); the flow is the
## standard Godot ENet client bootstrap.
func _start_client_to(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		push_error("Failed to connect to %s:%d: %s" % [address, PORT, error])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	print("[client] connecting to %s:%d" % [address, PORT])


func _compute_dry_land_spawn_tile() -> Vector2i:
	var spawn_tile := Vector2i(
		_geo_coordinates.tile_for_longitude(SPAWN_LONGITUDE, EarthChunkGenerator.WORLD_WIDTH_TILES),
		_geo_coordinates.tile_for_latitude(SPAWN_LATITUDE, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	await _chunk_manager.update_with_progress(spawn_tile, _on_chunk_load_progress)
	var dry_land_tile := _find_dry_land_spawn(spawn_tile)
	# The real dry-land spawn tile is also the center of the EASY-difficulty
	# region (see RegionDifficulty / docs/concept/ecosystem_dynamics.md's
	# Region difficulty section) -- dangerous species (bear/lion/venomous
	# snake) won't spawn near a fresh character.
	_chunk_manager.set_spawn_tile(dry_land_tile)
	return dry_land_tile


## Safety cap so ground items can't accumulate without bound (they'd leak CPU
## and memory over a long session). Oldest is removed when the cap is hit.
const MAX_GROUND_ITEMS := 80


func _process(delta: float) -> void:
	if not _world_ready:
		return
	# Ages every recorded water disturbance (fish/player/animal ripples) so
	# its ring actually expands and fades -- every frame, every client, not
	# gated behind _owns_ecosystem_simulation() like the simulation steps
	# below (a visual effect, not shared world state).
	_chunk_manager.step_water_disturbances(delta)
	var focus_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	# Grass parting under a walker is the SAME kind of purely-cosmetic,
	# per-client-only effect as the water disturbances above -- it was
	# previously gated behind _owns_ecosystem_simulation(), which is false for
	# every connected client except whichever peer hosts (see
	# owns_ecosystem_simulation_for below): a joining client's OWN local grass
	# never parted for them, only the host's did. Every client needs their own
	# nearby grass to part around their own view, not just the simulation
	# owner's.
	if focus_player != null:
		_chunk_manager.set_grass_walker_position(focus_player.position)
	if _owns_ecosystem_simulation():
		# The CALENDAR first, at the rate actually asked for: seasons, fruit
		# ripening and tree growth all read the clock, and they are what
		# /ecotest exists to let someone watch. At normal speed this is
		# exactly the frame's own delta, so nothing changes off the lapse.
		_chunk_manager.advance_world_age(
			TimeLapse.calendar_seconds(delta, _ecology_time_scale)
		)
		# Real in-flight regional-trade caravans (see docs/concept/trade.md)
		# read the clock rather than a delta, so they belong with the clock:
		# once, right after it moves. They used to run per slice, back when
		# each slice moved the clock -- now every slice within a frame would
		# see the same world age and redo identical work.
		_chunk_manager.step_caravans()
		# The STEPPING keeps its measured per-frame budget (see TimeLapse):
		# normally one slice carrying the frame's own delta, several when
		# /ecotest is running the year fast, never more than the frame can
		# get through.
		# Two groups, at two cadences -- see _step_ecology_fine and
		# _step_ecology_batch.
		var slices := TimeLapse.slices(delta, _ecology_time_scale)
		var simulated := 0.0
		for slice in slices:
			simulated += slice
			_step_ecology_fine(slice, focus_player)
		if simulated > 0.0:
			_step_ecology_batch(simulated, focus_player)
		_step_path_scarring(delta)
		if focus_player != null:
			_step_pebble_dispersion(focus_player)

	if _is_dedicated_server:
		_server_process()
	else:
		_client_process(delta)


## How often worn/recovered path tiles are diffed against the rendered
## trampled-earth modifications -- the wear model itself advances every frame.
const PATH_SCAR_REFRESH_INTERVAL := 2.0

## Which biomes a walked-over tile can wear down to a dirt path on -- water,
## desert sand, bare mountain etc. don't scar.
const PATH_SCAR_BIOMES := ["grassland", "forest"]


## Path scarring (see PathScarring): each new grass/forest tile the player
## walks onto accumulates wear; heavily-walked tiles render as trampled earth
## (reusing the build system's EARTH_TILE_ID modification), and unwalked ones
## slowly recover and revert. Modifications made here are indistinguishable
## from player-built earth once persisted -- an accepted overlap, both are
## "the ground got turned to dirt".
func _step_path_scarring(delta: float) -> void:
	_path_scarring.advance(delta)

	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null and not local_player.is_dead:
		var tile: Vector2i = local_player.current_tile()
		if tile != _last_scar_step_tile:
			_last_scar_step_tile = tile
			if PATH_SCAR_BIOMES.has(_chunk_manager.biome_at_global(tile.x, tile.y)):
				_path_scarring.step_on(tile)

	_scar_refresh_accumulator += delta
	if _scar_refresh_accumulator < PATH_SCAR_REFRESH_INTERVAL:
		return
	_scar_refresh_accumulator = 0.0

	for tile in _path_scarring.worn_tiles():
		if not _scarred_tiles.has(tile):
			if _chunk_manager.build_at_global(tile.x, tile.y, TerrainRenderer.EARTH_TILE_ID):
				_scarred_tiles[tile] = true
				# Emergence Phase 8 (see docs/concept/infrastructure.md,
				# EarthChunkManager.record_path_worn_if_new): the same real
				# state transition that renders a worn path also records it
				# as a real, /why-inspectable event -- "repeated movement
				# creates infrastructure" made concrete, not just a texture
				# change.
				_chunk_manager.record_path_worn_if_new(tile)

	for tile in _scarred_tiles.keys().duplicate():
		if not _path_scarring.is_worn(tile):
			_chunk_manager.destroy_at_global(tile.x, tile.y)
			_scarred_tiles.erase(tile)
			_chunk_manager.record_path_reclaimed(tile)


## Pebble dispersion (see PebbleDispersion, docs/concept/stone.md): walking
## close enough to a loose stone kicks it a small, one-time distance out of
## the way. PLAYER-ONLY for now -- the same scope PathScarring itself has
## above (player position only, no creature wiring) -- extending this to
## every creature too would mean an O(creatures x nearby stones) scan every
## frame, and nothing today needs it enough to justify that cost; a
## documented follow-up, not an oversight (see docs/progress.md).
func _step_pebble_dispersion(local_player: Player) -> void:
	if _chunk_manager == null or local_player.is_dead:
		return
	for stone in _chunk_manager.liftable_stones_near(local_player.position, PebbleDispersion.TRIGGER_RADIUS_PX):
		if stone.has_method("try_disperse"):
			stone.try_disperse(local_player.position)


## How often herbivores get a chance to eat dropped tree food -- cheap
## enough per tick, but there's no need to run the O(creatures x items)
## scan every frame.
const HERBIVORE_FOOD_INTERVAL := 2.0
var _herbivore_food_accumulator := 0.0


## Herbivore-role creatures eat dropped food ground items (the fruit/nuts
## trees forage-drop, see EarthChunkManager.step_forage) when standing close
## enough -- closing the trees-feed-animals loop. Uses the tested
## FoodConsumption.nearest_food_index; the item node is simply consumed
## (freed), and the creature's own hunger resets via its marker.
func _step_herbivore_food_consumption(delta: float) -> void:
	_herbivore_food_accumulator += delta
	if _herbivore_food_accumulator < HERBIVORE_FOOD_INTERVAL:
		return
	_herbivore_food_accumulator = 0.0

	var food_items: Array = []
	var food_positions: Array = []
	for item in _ground_items.get_children():
		if item.is_queued_for_deletion() or item.item_stack == null:
			continue
		if item.item_stack.item.kind == "food":
			food_items.append(item)
			food_positions.append(item.position)
	if food_items.is_empty():
		return

	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if creature.info == null or creature.info.is_predator:
			continue
		var index: int = FoodConsumption.nearest_food_index(
			creature.position, food_positions, FoodConsumption.EAT_RADIUS
		)
		if index < 0:
			continue
		var eaten: Node = food_items[index]
		if not eaten.is_queued_for_deletion():
			eaten.queue_free()
			if creature.has_method("on_ate_food"):
				creature.on_ate_food()


## How often creatures are checked for reproduction, and the hard cap on how
## many creature nodes may exist before births are suppressed -- density
## dependence at the individual scale (real populations stop growing as they
## crowd their range) and a safety bound so a fed herd can't spawn without limit.
const REPRODUCTION_INTERVAL := 3.0
const MAX_LIVE_CREATURES := 60

## How close counts as "right here" for density dependence, and how many of
## one species may share that space before they stop breeding. A herd is
## believable; a wall of deer in one clearing is not, and the global cap
## alone permitted exactly that (see _step_reproduction).
const NEIGHBOUR_RADIUS_PX := 160.0
const MAX_SAME_SPECIES_NEARBY := 4
const OFFSPRING_SCATTER := 14.0
var _reproduction_accumulator := 0.0

## Turns a creature's own wander_seed into its AnimalFitness phenotype for
## _find_courtship_partner's mate-attractiveness ranking (see
## MammalCourtship.most_attractive_partner_index). One shared instance --
## AnimalFitness is stateless, so there is nothing per-creature to keep.
var _animal_fitness := AnimalFitness.new()


## Condition-gated, PAIRED individual reproduction (see AnimalReproduction /
## MammalCourtship / ecosystem_dynamics.md's "Courtship, and where births come
## from"). AnimalReproduction.can_reproduce() (energy/health/birth cooldown)
## is a PRECONDITION, not the whole gate any more: an eligible creature with
## no eligible same-species neighbour nearby does not reproduce at all -- it
## has to find a partner (_pair_up_courtships), the pair has to actually walk
## together and linger for a real duration (CreatureBehavior's "court" intent
## drives that every frame; this only advances the shared timer -- see
## _advance_courtships), and only once that duration completes with the pair
## STILL viably together (_resolve_courtship) does an offspring appear.
## There is deliberately no solo path any more: a single eligible creature
## with nobody nearby to court just keeps wandering, exactly like the real
## thing (previously it spawned young by itself, unconditionally on hitting
## the gates below -- see docs/progress.md for the "no mate, no pairing" gap
## this replaces).
func _step_reproduction(delta: float) -> void:
	_reproduction_accumulator += delta
	if _reproduction_accumulator < REPRODUCTION_INTERVAL:
		return
	var interval := _reproduction_accumulator
	_reproduction_accumulator = 0.0

	var creatures := get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)
	_advance_courtships(creatures, interval)
	if get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME).size() >= MAX_LIVE_CREATURES:
		return
	_pair_up_courtships(creatures)


## Pairs up newly-eligible creatures that aren't already courting. Neither
## side spawns anything here -- this only starts the courtship STATE (see
## CreatureMarker.begin_courtship), which CreatureBehavior's "court" intent
## then walks toward completion frame by frame, and _advance_courtships
## finishes once its duration is up.
func _pair_up_courtships(creatures: Array) -> void:
	for creature in creatures:
		if creature.info == null or not creature.has_method("can_reproduce"):
			continue
		if creature.is_courting() or not creature.can_reproduce():
			continue
		var partner = _find_courtship_partner(creature, creatures)
		if partner == null:
			continue
		creature.begin_courtship(partner)
		partner.begin_courtship(creature)


## The most attractive eligible same-species partner for `creature` within
## NEIGHBOUR_RADIUS_PX -- the same "right here" locality _same_species_within
## already uses for density-dependent crowding. Eligible means: the same
## species, individually past AnimalReproduction's own gate, not already
## paired with someone else, and a genuinely different individual
## (Courtship.can_pair guards the self-pairing a scan of a group containing
## `creature` itself would otherwise allow -- reused as-is, it is already
## id-based and species-agnostic). No eligible neighbour in range returns
## null: there is no fallback, that IS the "no mate, no courtship" rule.
##
## Ranking is by AnimalFitness.mate_attractiveness against `creature`'s own
## phenotype (see MammalCourtship.most_attractive_partner_index), not simply
## the closest candidate -- but distance still gates who is even a candidate
## in the first place, unchanged: the radius filter runs first, exactly like
## the plain-nearest version this replaces, and attractiveness only ranks
## whoever survives it. Each creature's phenotype comes from its own
## wander_seed (already present on CreatureMarker, reproducible without
## storing anything new per-individual -- see AnimalFitness.phenotype_for).
func _find_courtship_partner(creature, creatures: Array):
	var candidate_positions: Array = []
	var candidate_phenotypes: Array = []
	var candidate_nodes: Array = []
	for other in creatures:
		if other.info == null or other.info.species != creature.info.species:
			continue
		if not Courtship.can_pair(creature.get_instance_id(), other.get_instance_id()):
			continue
		if other.is_courting() or not other.has_method("can_reproduce") or not other.can_reproduce():
			continue
		candidate_positions.append(other.position)
		candidate_phenotypes.append(_animal_fitness.phenotype_for(other.wander_seed))
		candidate_nodes.append(other)
	var own_phenotype: Dictionary = _animal_fitness.phenotype_for(creature.wander_seed)
	var index := MammalCourtship.most_attractive_partner_index(
		own_phenotype, creature.position, candidate_positions, candidate_phenotypes, NEIGHBOUR_RADIUS_PX
	)
	return candidate_nodes[index] if index >= 0 else null


## Advances every already-courting creature's own share of its pair's shared
## timer by `interval` (both partners get the same increment every tick, so
## they stay in lockstep without either one telling the other). Once a pair
## has lingered long enough (MammalCourtship.courtship_complete), exactly one
## side resolves it -- Courtship.leads decides which, the same "both sides
## compute independently, only the leader acts" shape the pollinator dance
## already uses, so a pair is never resolved twice regardless of which side
## this loop reaches first.
func _advance_courtships(creatures: Array, interval: float) -> void:
	for creature in creatures:
		if not creature.is_courting():
			continue
		var partner = creature.courtship_partner()
		if partner == null:
			continue  # courtship_partner() already ended it if the partner is gone
		var elapsed: float = creature.advance_courtship(interval)
		if not MammalCourtship.courtship_complete(elapsed):
			continue
		if not Courtship.leads(creature.get_instance_id(), partner.get_instance_id()):
			continue
		_resolve_courtship(creature, partner)


## A pair's courtship duration is up: ends the courtship STATE unconditionally
## (mate or not, the pairing is over either way -- see Courtship.COOLDOWN_
## SECONDS's own doc for why pollinators do the same), then re-checks
## viability at THIS moment rather than trusting the checks from when the
## pairing began -- crowding and carrying capacity can change during the
## linger window (see courtship_still_viable's own doc for the "dozens of
## deer" bug this specifically guards against), and either partner may have
## wandered off, died, or been eaten in the meantime. Only if the pair is
## still genuinely together and the land can still support another mouth
## does an offspring actually appear -- via the same CreatureRenderer.
## spawn_single/on_reproduced/record_birth_at calls the old solo path used.
func _resolve_courtship(a, b) -> void:
	var round_index: int = a.courtship_round()
	a.end_courtship()
	b.end_courtship()
	if not is_instance_valid(a) or not is_instance_valid(b) or a.info == null or b.info == null:
		return

	var a_position: Vector2 = a.position
	var b_position: Vector2 = b.position
	var distance := a_position.distance_to(b_position)
	var crowd := _same_species_within(a, NEIGHBOUR_RADIUS_PX)
	var capacity_ok: bool = _chunk_manager.can_support_another_herbivore(a_position, crowd)
	if not courtship_still_viable(distance, NEIGHBOUR_RADIUS_PX, crowd, MAX_SAME_SPECIES_NEARBY, capacity_ok):
		return
	if get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME).size() >= MAX_LIVE_CREATURES:
		return

	var seed_value := Courtship.pair_seed(a.get_instance_id(), b.get_instance_id(), round_index)
	if not Courtship.mates(seed_value):
		return

	var midpoint := (a_position + b_position) * 0.5
	var offset := Vector2(_offset_hash(midpoint, 1), _offset_hash(midpoint, 2)) * OFFSPRING_SCATTER
	var species: String = a.info.species
	var offspring := _creature_renderer.spawn_single(_creatures, species, midpoint + offset, _chunk_manager)
	# Born, not spawned already grown -- see MammalGrowth/CreatureMarker.
	# begin_life. Without this every mammal offspring would appear at full
	# adult size the instant courtship resolves.
	offspring.begin_life()
	a.on_reproduced()
	b.on_reproduced()
	# The aggregate population owns the long-term picture, so an
	# individual birth in front of the player has to reach it -- otherwise
	# a herd the player watched grow evaporates on the next chunk reload,
	# and the off-screen model goes on breeding a range that is already
	# full (see EcosystemSimulation.record_birth).
	_chunk_manager.record_birth_at(midpoint)


## Whether a pair whose courtship duration just completed may still actually
## reproduce, checked fresh at the moment it resolves rather than when it
## began: `distance` is how far apart the two partners currently are (must
## still be within `notice_radius`, the same locality that found them each
## other), `crowd`/`max_crowd` is the same density-dependence check
## _step_reproduction always applied, and `capacity_ok` is whether the land
## itself (EarthChunkManager.can_support_another_herbivore) can still feed
## another mouth. Pure and static so it's testable without a live scene tree
## (see test_world_courtship_pairing.gd) -- the same style as World's other
## static gates (always_day_for, ecology_scale_for_console_argument).
##
## This exists because a clearing can fill up WHILE a pair is lingering: two
## deer that started courting in an empty clearing must not still produce a
## fawn if three more deer wandered in and filled it during the wait --
## exactly the "the fruit caused dozens of deer to spawn" bug that motivated
## the crowding/capacity checks in the first place, just re-applied at the
## END of a courtship instead of only at its start.
static func courtship_still_viable(
		distance: float, notice_radius: float, crowd: int, max_crowd: int, capacity_ok: bool
) -> bool:
	return distance <= notice_radius and crowd < max_crowd and capacity_ok


## How many creatures of `creature`'s own species are within `radius` of it,
## excluding itself -- the local crowding that gates breeding.
func _same_species_within(creature, radius: float) -> int:
	var count := 0
	for other in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		if other == creature or other.info == null:
			continue
		if other.info.species != creature.info.species:
			continue
		if creature.position.distance_to(other.position) <= radius:
			count += 1
	return count


## A small deterministic-ish spread offset in [-1,1] for scattering offspring,
## salted so x and y differ.
func _offset_hash(position: Vector2, salt: int) -> float:
	var h := absi(hash("%d_%d_%d" % [int(position.x), int(position.y), salt]))
	return float(h % 2000) / 1000.0 - 1.0


## The living-ecosystem simulation (Phase 1) runs authoritatively on whichever
## side is the source of truth for the world: the dedicated server, or a
## singleplayer instance with no networking at all. A network CLIENT must not
## also simulate it locally -- that would silently diverge from the server's
## state. Known gap: creature markers aren't replicated to clients yet (see
## docs/progress.md), so a connected client currently sees no creatures at
## all rather than the server's authoritative ones.
## Whether THIS process is the authority that advances the shared world
## simulation (ecosystem, flowers, worms, fruiting, tree spread, and the
## world clock itself -- see _process).
##
## The peer-is-null case alone was not enough, and the omission switched the
## ENTIRE ecology off for the normal way the game is played: starting a world
## from the menu HOSTS it (see _start_server), so `multiplayer_peer` is set,
## `_is_dedicated_server` is false, and this returned false. Measured live:
## `owns=false`, `age=0` -- meaning step_flowers/step_worms/step_fruiting/
## step_tree_spread never ran at all, and because the world clock is advanced
## from inside this same `owns` branch (see _process), `_world_age_seconds`
## was frozen at zero, so the season and weather never changed either. That is why nothing ever grew,
## no worm ever surfaced ("no worms in rain" -- it had never actually
## rained), no fruit ever fell, and the robin had nothing to hunt. A player
## hosting their own world IS the authority for it.
static func owns_ecosystem_simulation_for(
	is_dedicated_server: bool, has_peer: bool, is_server: bool
) -> bool:
	if is_dedicated_server:
		return true
	if not has_peer:
		return true  # no networking at all: a plain solo session
	return is_server  # hosting: this process owns the world


func _owns_ecosystem_simulation() -> bool:
	return owns_ecosystem_simulation_for(
		_is_dedicated_server,
		multiplayer.multiplayer_peer != null,
		multiplayer.is_server()
	)


## Whether lighting should be pinned to full sun instead of following the real
## UTC-driven solar elevation. Precedence, highest first: the live console
## toggle (/day), then the env var.
##
## There is deliberately NO build-type default any more. This used to end in
## `return is_debug`, so every debug build was permanent noon -- sun elevation
## 90 at two in the morning -- and nobody developing the game ever saw the
## night the shipped build has; AA_DEBUG_ALWAYS_DAY=0 was the only escape and
## nobody set it. /day, /night and /time <hh:mm> put a chosen sky one
## keystroke away, which is what that default was really providing. Pinned by
## test_world_daylight_default.gd.
static func always_day_for(force_day: bool, env_value: String) -> bool:
	return force_day or env_value == "1"


## Night's tint floor and day's tint ceiling for DayNightTint (see
## day_night_tint_for below). Reported directly: "I can barely see at night" --
## the old inline floor (0.2, 0.2, 0.3) was too dark to read the scene by.
## Real-world grounding: even with the sun fully below the horizon, moonlight
## + starlight + skyglow give real usable outdoor vision -- night is dim and
## blue-shifted, never pitch black, the same "never fully black" floor most
## games deliberately keep for playability. Blue sits noticeably higher than
## red/green (a cool, moonlit cast), rather than a uniformly dimmed copy of
## daylight. DAY_TINT is unchanged from the previous formula's sunlight=1.0
## case (neutral, undimmed) -- only the night floor moved.
const NIGHT_TINT := Color(0.4, 0.4, 0.55)
const DAY_TINT := Color(1.0, 1.0, 1.0)


## The DayNightTint color for a given sunlight_intensity() value -- a plain
## linear interpolation between the pinned night floor and day ceiling.
## Extracted out of the per-frame lighting step (see _client_process) so the
## actual endpoint values are testable rather than an inline literal nobody
## could pin (see test_world_daylight_default.gd's own day/night tint
## section).
static func day_night_tint_for(sunlight: float) -> Color:
	return NIGHT_TINT.lerp(DAY_TINT, clampf(sunlight, 0.0, 1.0))


## The elevation to light the world by: whichever sky the console pinned,
## else the real one just computed. ONE place decides, so /day and /night can
## never disagree about which wins -- and a live /night beats a stale
## AA_DEBUG_ALWAYS_DAY=1 from launch, since whoever is typing now is more
## current than whoever set the variable.
static func forced_elevation_for(
	forced_sky: String, env_value: String, real_elevation: float
) -> float:
	if forced_sky == "night":
		return ALWAYS_NIGHT_ELEVATION
	if always_day_for(forced_sky == "day", env_value):
		return ALWAYS_DAY_ELEVATION
	return real_elevation


## Parses a /time argument -- "22:30", or a bare "22" -- into a local clock
## hour in [0,24), or NO_FORCED_HOUR when it is not a real time. Pure and
## separate from the live clock, the same way
## ecology_scale_for_console_argument already is for /ecotest.
static func clock_hour_for_console_argument(text: String) -> float:
	var parts := text.split(":")
	if parts.size() > 2 or not parts[0].is_valid_int():
		return NO_FORCED_HOUR
	var hours := int(parts[0])
	var minutes := 0
	if parts.size() == 2:
		if not parts[1].is_valid_int():
			return NO_FORCED_HOUR
		minutes = int(parts[1])
	if hours < 0 or hours > 23 or minutes < 0 or minutes > 59:
		return NO_FORCED_HOUR
	return float(hours) + float(minutes) / 60.0


## Whether a console command's arguments say "off" -- shared by /day, /night
## and /time so one word clears any of them.
static func is_off_argument(args: Array) -> bool:
	return args.size() > 0 and str(args[0]).to_lower() == "off"


## Every connected player gets a working chunk_manager reference so its
## simulation can run at all. Chunk streaming itself only follows one player
## at a time for now -- true multi-player streaming needs EarthChunkManager
## to union multiple interest points instead of a single center, which is a
## follow-up once more than one concurrent player is actually being tested.
func _server_process() -> void:
	var streamed := false
	for child in _players.get_children():
		var player := child as Player
		if player == null:
			continue
		if not player.is_set_up():
			player.setup(_chunk_manager, TerrainRenderer.TILE_SIZE)
		if not streamed:
			_chunk_manager.update(player.current_tile())
			streamed = true


func _client_process(delta: float) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player == null:
		return

	# Every locally-visible player (including remote players' proxies) needs a
	# chunk_manager reference so its own visual water-state lookup works.
	for child in _players.get_children():
		var player := child as Player
		if player != null and not player.is_set_up():
			player.setup(_chunk_manager, TerrainRenderer.TILE_SIZE)

	# Covers the joining-client version of the same New Game/Load Game
	# loading stall (see _on_menu_join_requested): unlike those two, a joining
	# client has no single call site to wrap -- its local player only exists
	# once the server's own spawn has replicated in, and its first real chunk
	# load happens on whichever _client_process frame that lands on. Run via
	# a separate fire-and-forget async task (_run_initial_client_chunk_load)
	# rather than awaiting right here -- _client_process itself stays a plain
	# synchronous per-frame function, so suspending across frames doesn't also
	# suspend every per-frame UI update below. While that task is in flight,
	# skip the plain update() below entirely: update_with_progress already
	# owns the manager's chunk state for this stretch, and calling update()
	# concurrently on the same EarthChunkManager instance would race it. Once
	# done, ordinary per-frame update() calls resume exactly as before --
	# this also correctly covers New Game/Load Game, whose local player
	# reaches here only after their own update_with_progress call already
	# finished, so this one-shot task just re-confirms nothing is pending and
	# completes without ever needing to await a frame.
	if not _initial_client_chunk_load_done:
		if not _initial_client_chunk_load_task_running:
			_initial_client_chunk_load_task_running = true
			_run_initial_client_chunk_load(local_player.current_tile())
	else:
		_chunk_manager.update(local_player.current_tile())

	var player_tile := local_player.current_tile()
	_update_minimap(player_tile, delta)
	_update_inventory_window(local_player)
	_update_crafting_window(local_player)
	_update_player_health_bar(local_player)
	_update_hotbar(local_player)
	_update_creature_panels(local_player, delta)
	# Hover tooltip is throttled (~30 Hz): recomputing which of potentially
	# thousands of hoverables is under the cursor every single frame was a top
	# CPU cost. 30 Hz is imperceptible for a tooltip.
	_hover_accumulator += delta
	if _hover_accumulator >= HOVER_REFRESH_INTERVAL:
		_hover_accumulator = 0.0
		_update_hover_tooltip()
	_update_survival_bar(local_player)
	_update_xp_bar(local_player)
	_update_land_sense_label(local_player)
	_update_fishing_label(local_player)
	_update_lasso_label(local_player)
	_update_trade_label(local_player)
	_update_talk_label(local_player)
	_update_cast_label(local_player)
	# The banners keep their own text; the whole stack steps aside while a
	# window is open (see world_hint_visible_for).
	_message_stack.visible = world_hint_visible_for(true, _any_gameplay_window_open())
	_maybe_update_interaction_prompt(local_player, delta)
	_update_charge_meter(local_player)
	_refresh_skill_window(local_player)
	_autosave_step(local_player, delta)
	var latitude := _geo_coordinates.latitude_for_tile(player_tile.y, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var longitude := _geo_coordinates.longitude_for_tile(player_tile.x, EarthChunkGenerator.WORLD_WIDTH_TILES)

	# Real-world UTC time drives lighting directly: day/night always matches
	# what the sun is actually doing right now at the player's real-world
	# latitude/longitude, not an accelerated or arbitrary in-game clock --
	# unless the console has pinned a sky (/day, /night) or a clock (/time),
	# or DEBUG_ALWAYS_DAY_ENV pinned day for the whole session at launch.
	var utc := Time.get_datetime_dict_from_system(true)
	var day_of_year := _solar_position.day_of_year(utc.year, utc.month, utc.day)
	var utc_hour: float = utc.hour + utc.minute / 60.0 + utc.second / 3600.0
	# /time <hh:mm> pins the LOCAL clock, converted back here to the UTC hour
	# that produces it (SolarPosition.utc_hour_for_local) -- so the displayed
	# clock, the sun's elevation and its azimuth/hillshading all move
	# together instead of the readout drifting away from the sky.
	if _forced_local_hour != NO_FORCED_HOUR:
		utc_hour = _solar_position.utc_hour_for_local(_forced_local_hour, longitude)

	var elevation := forced_elevation_for(
		_forced_sky,
		OS.get_environment(DEBUG_ALWAYS_DAY_ENV),
		_solar_position.elevation_degrees(latitude, longitude, day_of_year, utc_hour)
	)
	# Easter-egg sighting cameos (docs/concept/easter_eggs.md) -- gated on
	# the same real sun elevation day/night lighting already uses, so
	# "spookier at night" (the Jersey Devil) means the same thing here as it
	# does for the lights overhead.
	_easter_egg_check_accumulator += delta
	if _easter_egg_check_accumulator >= EASTER_EGG_CHECK_INTERVAL:
		_easter_egg_check_accumulator = 0.0
		_check_easter_egg_sightings(player_tile, elevation <= 0.0)
		# Squallmaw/Coilnecca/Champ -- real, rare, spawnable cameos, checked
		# on the same cadence/roll as the flavor-text-only sightings above
		# (see EasterEggCreatures' own doc comment for why this is a
		# separate module rather than folded into EasterEggSightings).
		_check_easter_egg_creature_spawns(player_tile, local_player)
		# Back to the Future Day -- gated on the REAL system calendar
		# date (utc.month/utc.day), not a rarity roll like every cameo
		# above; see _check_back_to_the_future_day's own doc comment.
		_check_back_to_the_future_day(utc.month, utc.day)
		# Rush ambient nod -- location alone triggers this one, no roll;
		# see _check_rush_ambient_cue's own doc comment.
		_check_rush_ambient_cue(player_tile)
		# Monty Python's Bridgekeeper -- a rare encounter roll, same cadence
		# as the sightings above; see _check_bridgekeeper_encounter's own
		# doc comment.
		_check_bridgekeeper_encounter(player_tile)
	# The Zork-homage terminal and the signed secret room both key off a
	# single-frame Input.is_action_just_pressed edge (see each function's own
	# doc comment for why they can't share the throttled block above --
	# throttling to EASTER_EGG_CHECK_INTERVAL would drop most real presses).
	_check_ancient_terminal(player_tile, local_player)
	_check_signed_secret_room(player_tile, local_player)
	_check_sea_cave_guardian(player_tile)
	_check_retro_handheld(player_tile)
	_update_easter_egg_label(delta)
	# Real sun compass bearing, for hillshading (see HillshadeShader,
	# docs/concept/terrain_relief.md) -- same real inputs as elevation just
	# above, so mountain shading is driven by the exact same sun as day/
	# night lighting rather than a second light source.
	var azimuth := _solar_position.azimuth_degrees(latitude, longitude, day_of_year, utc_hour)
	# The displayed clock reads LOCAL time at the character's own in-game
	# longitude, not raw UTC -- the same real-astronomy local-solar-time
	# basis elevation_degrees already uses for lighting (see
	# SolarPosition.local_hour's own doc comment). Reported: "if a player
	# from Japan has his character in Berlin, it's still GMT+2 for him" --
	# the clock used to ignore where the character actually stood entirely.
	var local_hour := _solar_position.local_hour(utc_hour, longitude)
	var local_hour_whole := int(local_hour)
	var local_minute := int((local_hour - float(local_hour_whole)) * 60.0)
	var sunlight := _solar_position.sunlight_intensity(elevation)
	_day_night.color = day_night_tint_for(sunlight)
	# The river strokes lift toward moonlight from the SAME sunlight -- the
	# CanvasModulate above multiplies every canvas pixel, and without the
	# lift the current marks fall below visibility exactly when the world
	# clock (which follows the real clock) holds evening players in
	# permanent night. Real rivers gleam after dark: they reflect the sky.
	_chunk_manager.set_river_flow_night_lift(sunlight)
	var wader_candidates: Array = [local_player.position]
	for creature in get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME):
		wader_candidates.append(creature.position)
	_chunk_manager.set_river_flow_waders(
		_chunk_manager.river_wader_positions(wader_candidates)
	)
	# Drives every creature's silhouette shadow length (see DropShadow.
	# stretch_for_elevation / CreatureMarker.sun_elevation_deg) with the same
	# real sun position already computed for day/night lighting above.
	CreatureMarker.sun_elevation_deg = elevation

	var season := _chunk_manager.current_season().capitalize()
	var raw_weather := _chunk_manager.current_weather(local_player.position)
	# Snow rather than rain when it is cold enough, and snow lying on the
	# ground afterwards (see Snowfall). Temperature decides, not the season
	# name -- a cold snap in autumn snows and a mild winter rains. Computed
	# BEFORE `raining` below, since raining now needs to know about it.
	var warmth := _chunk_manager.current_warmth()
	var snowing := Snowfall.falls_as_snow(raw_weather, warmth)
	# Water tiles react to the weather: raindrop ripples while raining (but
	# NOT while snowing -- falling snow doesn't splash water the way rain
	# does, RainOverlay below already shows flakes instead of drops once
	# snowing is true, and the raindrop shader term is real per-fragment GPU
	# cost across every visible water pixel: reported live, driving it
	# during snow too dropped fps from ~30 to ~6 for no visual payoff).
	# Windy chop otherwise, and the whole surface paces faster/slower with
	# how energetic the weather is (calm on a clear day, hectic in a storm).
	var raining := (raw_weather == "rain" or raw_weather == "storm") and not snowing
	_chunk_manager.set_rain(raining)
	# ... and the sky above them: rain you can actually see falling, heavier
	# in a storm than in ordinary rain (see RainOverlay).
	_rain_overlay.set_intensity(RAIN_INTENSITY_BY_WEATHER.get(raw_weather, 0.0))
	_rain_overlay.set_snowing(snowing)
	# Depth, tracks and repaint all live behind one call now, and it reads the
	# WORLD clock rather than this frame's delta -- see step_snow. Accumulating
	# here against `delta` put the snow on a different clock from the season, so
	# a jump to summer left it lying in the sunshine.
	_chunk_manager.step_snow(snowing, warmth)
	# Walking packs the snow down, which is what leaves a trail.
	_chunk_manager.tread_snow_at(local_player.position)
	_chunk_manager.set_wind_strength(_weather_model.wind_strength_for(raw_weather))
	# Real relief shading, lit by the exact same sun already computed above
	# for day/night (elevation) and now also its compass bearing (azimuth).
	_chunk_manager.set_sun_position(elevation, azimuth)
	# The GROUND carries the season too, not just the canopy above it (see
	# SeasonalFoliage / concept/seasons.md "The ground carries the season
	# too"). Forcing winter used to give bare trees standing on a bright
	# summer lawn, in lush grass, over green crop tops -- the season was
	# something that happened to IllustratedTree's four canopy frames and to
	# nothing else. Read off the same world clock every other season reader
	# uses, so the lawn and the canopy can never disagree about the month.
	# One shader-parameter write; invalidates no atlas (pinned by
	# test_a_season_turn_changes_the_material_and_not_one_pixel_of_the_atlas).
	var foliage_tint := SeasonalFoliage.tint_for_world_age(_chunk_manager.world_age_seconds())
	_ground_tint.set_season_tint(foliage_tint)
	_chunk_manager.set_season_tint(foliage_tint)
	# ...and the CANOPY above that ground, off the same clock, in the same
	# frame. This belongs here rather than in _process's ecology block because
	# a canopy is a rendering concern, not a simulation-ownership one: the
	# season used to reach the trees only through step_fruiting, which runs
	# behind _owns_ecosystem_simulation(), so a JOINED CLIENT -- which owns no
	# simulation -- kept a summer-green forest in every season for the whole
	# session, and even a host's first chunks loaded green before the first
	# tick corrected them. _client_process runs on every peer. Guarded to a
	# handful of canopy rebuilds per in-game year (see
	# EarthChunkManager.sync_tree_season); pinned by
	# tests/unit/test_world_season_fanout.gd.
	#
	# Passed local_player.position so that rare full-canopy rebuild also
	# respects FRUITING_DETAIL_RADIUS -- which already covers the whole
	# visible viewport, so nothing on screen goes undressed, while a tree far
	# outside it is left for step_fruiting (host) or a later, nearer sync
	# (any peer) instead of paying a redraw nobody can see.
	_chunk_manager.sync_tree_season(local_player.position)
	var weather := raw_weather.capitalize()
	_debug_label.text = (
		"FPS %d   Lat %.1f Lon %.1f   Local %02d:%02d   Sun elev %.1f°   %s · %s   Mode: %s   Speed: %d%%"
		% [
			Engine.get_frames_per_second(),
			latitude,
			longitude,
			local_hour_whole,
			local_minute,
			elevation,
			season,
			weather,
			local_player.current_mode,
			local_player.current_speed_multiplier * 100,
		]
	)


## Searches an expanding ring around a candidate spawn tile for dry land, in
## case the exact coordinate lands on a coastline pixel the source data
## rounds to ocean. Falls back to the candidate itself if nothing is found.
## Neither ocean nor a river (docs/concept/rivers.md) -- a river never
## changes biome_at_global's own result (it's a water-overlay concern, not
## an eighth biome), so it's asked separately here rather than folded into
## the biome check above.
func _find_dry_land_spawn(candidate: Vector2i) -> Vector2i:
	for radius in range(SPAWN_SEARCH_RADIUS + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := candidate + Vector2i(dx, dy)
				if (
					_chunk_manager.biome_at_global(tile.x, tile.y) != "ocean"
					and not _chunk_manager.is_river_at_global(tile.x, tile.y)
				):
					return tile
	return candidate
