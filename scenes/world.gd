extends Node2D

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const RenderResolution = preload("res://src/rendering/render_resolution.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")
const RainOverlay = preload("res://src/rendering/rain_overlay.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const ConsoleSpecies = preload("res://src/gameplay/console_species.gd")
const GroundTint = preload("res://src/rendering/ground_tint.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SolarPosition = preload("res://src/world/solar_position.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
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
const Keybindings = preload("res://src/gameplay/keybindings.gd")
const SettingsOverlay = preload("res://scenes/settings_overlay.gd")
const MainMenu = preload("res://scenes/main_menu.gd")
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
## Real seconds between creature-panel refreshes -- rebuilding a handful of
## panels a couple times a second is trivial, but this still avoids doing it
## every frame (same reasoning as the minimap/forage/spread throttling).
const CREATURE_PANELS_REFRESH_INTERVAL := 0.5
## Caps how many panels are shown at once (closest first) so a crowded area
## doesn't fill the whole screen with panels.
const MAX_CREATURE_PANELS := 6

## Berlin -- a real-world starting point (also handy given the user's timezone).
const SPAWN_LATITUDE := 52.52
const SPAWN_LONGITUDE := 13.405
const SPAWN_SEARCH_RADIUS := 5

const PORT := 8910
const MAX_CLIENTS := 32
const DEFAULT_HOST := "127.0.0.1"

## Debug/dev-console override for the always-day lighting default. Day is the
## DEFAULT in debug builds (see always_day_for) so development never waits on
## real-world night; set this env var to "0" to opt a debug build back into
## real UTC-driven day/night, or "1" to force day in an exported build.
const DEBUG_ALWAYS_DAY_ENV := "AA_DEBUG_ALWAYS_DAY"
## Sun directly overhead -- sin(90 deg) = 1.0, i.e. maximum sunlight_intensity.
const ALWAYS_DAY_ELEVATION := 90.0

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

@onready var _terrain: TileMapLayer = $Terrain
@onready var _water_fx: TileMapLayer = $WaterFx
@onready var _hillshade_fx: TileMapLayer = $HillshadeFx
## Snow lies here rather than as a tint on the ground, so footprints can be
## carved out of it (see SnowLayer).
@onready var _snow_fx: TileMapLayer = $SnowFx
@onready var _entities: Node2D = $Entities
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
var _main_menu: MainMenu
var _menu_backdrop: ColorRect
var _menu_background: TextureRect
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
var _talk_label: Label
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
var _fishing_label: Label
## Taming state banner (see docs/concept/taming.md) -- sits just under the
## fishing one, same shape.
var _lasso_label: Label
var _trade_label: Label
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


## Set true by the /day console command -- forces daytime lighting for the
## rest of the session, same effect as DEBUG_ALWAYS_DAY_ENV but toggled live
## rather than only at launch.
var _force_day := false


func _ready() -> void:
	# Area2D's input_event (used by DroppedItem's click-to-pick-up) never
	# fires unless the viewport's physics picking is explicitly enabled -- it
	# defaults to off.
	get_viewport().physics_object_picking = true

	_chunk_manager = EarthChunkManager.new(_terrain, _entities, _creatures)
	# World-space low-frequency color drift over the whole ground layer (see
	# GroundTint) -- soft lusher/drier patches spanning many tiles, so fields
	# read as organic ground instead of a uniform printed carpet.
	_terrain.material = GroundTint.new().shared_material()
	# GPU water: continuous noise-driven waves over every ocean cell,
	# translucent so shore foam and rain ripples show through (WaterShader).
	_chunk_manager.set_water_layer(_water_fx)
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
	_build_creature_panels_container()
	_build_hover_tooltip()
	_build_death_label()
	_build_survival_bar()
	_build_xp_bar()
	_build_fishing_label()
	_build_lasso_label()
	_build_trade_label()
	_build_talk_label()
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
	_wipe_persisted_world()
	if mode == "host":
		_start_server()
	_spawn_local_singleplayer()
	_dismiss_main_menu()


func _wipe_persisted_world() -> void:
	_world_reset.wipe_directory(EarthChunkManager.MODIFICATIONS_DIR)
	_world_reset.wipe_directory(EarthChunkManager.PLANTED_TREES_DIR)
	_world_reset.wipe_directory(EarthChunkManager.FISH_POPULATION_DIR)
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
	_spawn_local_singleplayer_from_save()
	_dismiss_main_menu()


func _on_menu_join_requested(address: String) -> void:
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


func _refresh_inventory_now(local_player: Player) -> void:
	_inventory_window.refresh(
		local_player.inventory.stacks(),
		_equipped_map(local_player),
		local_player.equipment.total_armor(),
		local_player.inventory.slot_count
	)


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
## toggled with toggle_skills (default K). Clicking an affordable node/keystone
## allocates it on the local player and refreshes.
func _build_skill_window() -> void:
	_skill_window = SkillTreeWindow.new()
	_skill_window.theme = _ui_theme
	_skill_window.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_skill_window.offset_left = 8.0
	_skill_window.offset_top = -150.0
	_skill_window.offset_right = 328.0
	_skill_window.offset_bottom = 150.0
	_ui.add_child(_skill_window)
	_skill_window.node_allocated.connect(_on_skill_node_allocated)
	_skill_window.keystone_unlocked.connect(_on_skill_keystone_unlocked)


func _on_skill_node_allocated(node_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null and local_player.allocate_skill(node_id):
		_refresh_skill_window(local_player)


func _on_skill_keystone_unlocked(keystone_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null and local_player.unlock_keystone(keystone_id):
		_refresh_skill_window(local_player)


func _refresh_skill_window(local_player: Player) -> void:
	if not _skill_window.visible:
		return
	_skill_window.refresh(
		local_player.experience.unspent_points,
		local_player.allocated_nodes,
		local_player.unlocked_keystones
	)


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


## A centered fishing prompt/result banner (hidden when there's nothing to say).
func _build_fishing_label() -> void:
	_fishing_label = Label.new()
	_fishing_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fishing_label.offset_top = 120.0
	_fishing_label.offset_left = -160.0
	_fishing_label.offset_right = 160.0
	_fishing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fishing_label.add_theme_font_size_override("font_size", 16)
	_ui.add_child(_fishing_label)


func _build_lasso_label() -> void:
	_lasso_label = Label.new()
	_lasso_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lasso_label.offset_top = 144.0
	_lasso_label.offset_left = -200.0
	_lasso_label.offset_right = 200.0
	_lasso_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lasso_label.add_theme_font_size_override("font_size", 16)
	_ui.add_child(_lasso_label)


func _update_lasso_label(local_player: Player) -> void:
	_lasso_label.text = local_player.lasso_message
	_lasso_label.visible = local_player.lasso_message != ""


func _update_fishing_label(local_player: Player) -> void:
	_fishing_label.text = local_player.fishing_message
	_fishing_label.visible = local_player.fishing_message != ""


## A centered shopping prompt/result banner (see Player._shop_step), same
## shape as the fishing banner just below it.
func _build_trade_label() -> void:
	_trade_label = Label.new()
	_trade_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_trade_label.offset_top = 144.0
	_trade_label.offset_left = -160.0
	_trade_label.offset_right = 160.0
	_trade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trade_label.add_theme_font_size_override("font_size", 16)
	_ui.add_child(_trade_label)


func _update_trade_label(local_player: Player) -> void:
	_trade_label.text = local_player.trade_message
	_trade_label.visible = local_player.trade_message != ""


## A centered talk-result banner (see Player._talk_step/NpcGreeting), same
## shape as the trade banner just above it.
func _build_talk_label() -> void:
	_talk_label = Label.new()
	_talk_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_talk_label.offset_top = 168.0
	_talk_label.offset_left = -220.0
	_talk_label.offset_right = 220.0
	_talk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_talk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talk_label.add_theme_font_size_override("font_size", 14)
	_ui.add_child(_talk_label)


func _update_talk_label(local_player: Player) -> void:
	_talk_label.text = local_player.talk_message
	_talk_label.visible = local_player.talk_message != ""


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
func _update_interaction_prompt(local_player: Player) -> void:
	if _chunk_manager == null:
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
	var mouse_world := get_global_mouse_position()
	# The finder only ever picks a target within HOVER_RADIUS_PX of the cursor,
	# so skip the expensive per-marker work (get_display_name/get_hover_actions
	# + dict alloc) for anything farther away -- turns an O(all loaded trees/
	# stones/creatures) scan into O(the handful under the cursor).
	var scan_radius_sq := HoverTargetFinder.HOVER_RADIUS_PX * HoverTargetFinder.HOVER_RADIUS_PX
	var candidates: Array = []
	for marker in get_tree().get_nodes_in_group(HoverTargetFinder.GROUP_NAME):
		if mouse_world.distance_squared_to(marker.position) > scan_radius_sq:
			continue
		var actions: Array = (
			marker.get_hover_actions() if marker.has_method("get_hover_actions") else []
		)
		candidates.append({"position": marker.position, "name": marker.get_display_name(), "actions": actions})

	var info := _hover_target_finder.info_under(mouse_world, candidates)
	var found_name: String = info.get("name", "")
	var found_actions: Array = info.get("actions", [])
	if found_name == "":
		var grass_growth := _chunk_manager.tall_grass_growth_at(mouse_world)
		if grass_growth >= 0.0:
			found_name = "Tall Grass"
			if grass_growth >= 1.0:
				found_actions = [{"verb": "Harvest", "action": "attack"}]

	_hover_tooltip.visible = found_name != ""
	if _hover_tooltip.visible:
		_hover_tooltip.text = _hover_tooltip_text(found_name, found_actions)
		_hover_tooltip.position = get_viewport().get_mouse_position() + Vector2(14, -8)


## Formats a hovered entity's name plus, on their own following lines, every
## action it offers with its LIVE keybinding (OS.get_keycode_string, so a
## rebind shows immediately -- the same pattern _show_interaction_prompt
## already uses for the proximity prompt). Multiple actions all show, e.g.
## a pebble reads "Pebble\nPick Up (E)\nKick (K)".
func _hover_tooltip_text(entity_name: String, actions: Array) -> String:
	var lines := [entity_name]
	for action in actions:
		lines.append(
			"%s (%s)" % [action["verb"], OS.get_keycode_string(_keybindings.keycode_for(action["action"]))]
		)
	return "\n".join(lines)


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
			nearby.append({"info": creature.info, "distance": distance})
	nearby.sort_custom(func(a, b): return a.distance < b.distance)

	for child in _creature_panels_container.get_children():
		child.free()

	for i in mini(nearby.size(), MAX_CREATURE_PANELS):
		var panel := CreaturePanel.new()
		_creature_panels_container.add_child(panel)
		panel.set_info(nearby[i].info)


func _unhandled_input(event: InputEvent) -> void:
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
func _step_ecology_fine(delta: float, focus_player: Player) -> void:
	# The clock first, and on EVERY slice: it is what seasons, ripening and
	# growth all read.
	_chunk_manager.advance_world_age(delta)
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
	_chunk_manager.step_flowers(delta)
	_chunk_manager.step_desert_scrub(delta)
	_chunk_manager.step_tundra_lichen(delta)
	# Every founded settlement is reassessed against its own food stock (see
	# EarthChunkManager.step_settlements/SettlementState) -- population
	# growth/decline pressure, throttled the same way tree spread is, so a
	# real session actually produces settlement_growing/settlement_declining
	# events without a console command.
	_chunk_manager.step_settlements(delta)
	_step_herbivore_food_consumption(delta)
	_step_reproduction(delta)


func _any_gameplay_window_open() -> bool:
	return _inventory_window.visible or _crafting_window.is_open() or _skill_window.is_open()


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
					"Commands: /day  /season [name]  /weather [state|off]"
					+ "  /ecotest [seconds_per_year|off]"
					+ "  /history <entity_id>  /why <event_id>  /remember <entity_id>"
					+ "  /household <entity_id>  /contract <entity_id>  /market <entity_id>"
					+ "  /institution <entity_id>  /settlement <entity_id>  /emergence"
					+ "  /spawn <species> [count]  /give <item_id> [count]"
					+ "  /craft <recipe_id>  /gold <amount>  /village  /species  /help"
				)
			)
		"species":
			# Discoverability: the roster is long enough now that /help
			# listing it inline would drown the other commands.
			_dev_console.log_line("Spawnable: %s" % ", ".join(ConsoleSpecies.spawnable()))
		"day":
			_force_day = true
			_dev_console.log_line("Time forced to day.")
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


## /settlement <settlement_id> -- food, capacity, households, and growth/
## decline status (see SettlementState).
func _handle_settlement_command(args: Array) -> void:
	if args.size() == 0:
		_dev_console.log_line("Usage: /settlement <settlement_id>  e.g. /settlement settlement:673_127")
		return
	var entity_id := str(args[0])
	var market := _chunk_manager.market_store().market_for(entity_id)
	var household_count := _chunk_manager.household_count_for_settlement(entity_id)
	for line in Why.explain_settlement(market, household_count, entity_id).split("
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
		_chunk_manager.clear_forced_weather()
		_dev_console.log_line("Weather back to its own devices.")
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
	# Reported as a TARGET, not a promise. The rate the world actually reaches
	# depends on how much ecology a frame can get through, which depends on the
	# machine and on how much is loaded: measured on this one, a year asked for
	# in 45 seconds arrives in about 90.
	_dev_console.log_line(
		(
			"Ecology target: a year every %.0fs (%.0fx). Actual depends on framerate."
			% [seconds_per_year, _ecology_time_scale]
		)
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


## Hunger/thirst bars fill up as satisfaction (1.0 - the meter, which itself
## rises toward 1.0 as hunger/thirst worsen) so a FULL bar reads as "doing
## fine", matching the health bar's full-is-good convention; the stamina bar
## just shows stamina directly (already 1.0 = full/good).
func _update_survival_bar(local_player: Player) -> void:
	var s := local_player.survival
	_hunger_fill.size.x = _health_bar.fill_width(1.0 - s.hunger, 1.0, SURVIVAL_BAR_WIDTH)
	_hunger_label.text = "Hunger %d%%" % int(s.hunger * 100)
	_thirst_fill.size.x = _health_bar.fill_width(1.0 - s.thirst, 1.0, SURVIVAL_BAR_WIDTH)
	_thirst_label.text = "Thirst %d%%" % int(s.thirst * 100)
	_stamina_fill.size.x = _health_bar.fill_width(s.stamina, 1.0, SURVIVAL_BAR_WIDTH)
	_stamina_label.text = "Stamina %d%%" % int(s.stamina * 100)
	_warmth_fill.size.x = _health_bar.fill_width(s.warmth, 1.0, SURVIVAL_BAR_WIDTH)
	var warmth_state := "Freezing" if s.is_freezing() else ("Cold" if s.is_cold() else "Warmth")
	_warmth_label.text = "%s %d%%" % [warmth_state, int(s.warmth * 100)]
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
			_hotbar_slots[i].texture = _item_sprite_generator.texture_for(item_id)
			_hotbar_counts[i].text = str(count) if count > 1 else ""
			_hotbar_slot_frames[i].tooltip_text = _hotbar_tooltip_text(item_id, count)
		else:
			_hotbar_slots[i].texture = null
			_hotbar_counts[i].text = ""
			_hotbar_slot_frames[i].tooltip_text = "Drag an item here to bind it"


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
	player.position = _spawn_position_for_tile(_compute_dry_land_spawn_tile())
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
	player.position = _spawn_position_for_tile(_compute_dry_land_spawn_tile())
	player.respawn_position = player.position
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
	_chunk_manager.update(_tile_for_position(saved_position))
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
	_chunk_manager.update(spawn_tile)
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


## TEMP LIVECHECK -- verifies Phases 4/5/6's gap-closing triggers
## (step_settlements' production/trade/institution-formation) fire
## automatically through the real _process/_step_ecology_batch chain, with
## zero manual coordinator calls. Gated behind --livecheck so an ordinary
## --solo run is unaffected. Removed before commit.
var _livecheck_ticks := 0
const _LIVECHECK_LOG := "user://livecheck_456.log"

func _livecheck_process() -> void:
	if not ("--livecheck" in OS.get_cmdline_user_args()):
		return
	_livecheck_ticks += 1
	if _livecheck_ticks == 2:
		var npc_identity_script = load("res://src/world/npc_identity.gd")
		var entity_ref_script = load("res://src/emergence/entity_ref.gd")
		var chunk_coord := Vector2i(900, 900)
		_chunk_manager.record_settlement_founded_if_new(
			chunk_coord, [npc_identity_script.new(5), npc_identity_script.new(1)]
		)
		var settlement_id: String = entity_ref_script.for_settlement(chunk_coord)
		_chunk_manager.market_store().market_for(settlement_id).add_stock("meat", 200)
		_handle_ecotest_command(["10"])
	if _livecheck_ticks % 30 == 0 or _livecheck_ticks == 900:
		var f := FileAccess.open(_LIVECHECK_LOG, FileAccess.WRITE)
		f.store_string(
			(
				"tick=%d production_succeeded=%d contract_proposed=%d contract_fulfilled=%d institution_formed=%d\n"
				% [
					_livecheck_ticks,
					_chunk_manager.event_store().events_of_type("production_succeeded").size(),
					_chunk_manager.event_store().events_of_type("contract_proposed").size(),
					_chunk_manager.event_store().events_of_type("contract_fulfilled").size(),
					_chunk_manager.event_store().events_of_type("institution_formed").size(),
				]
			)
		)
		f.close()
	if _livecheck_ticks >= 900:
		get_tree().quit()


func _process(delta: float) -> void:
	_livecheck_process()
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
		# Normally one slice carrying the frame's own delta; several when
		# /ecotest is running the year fast (see TimeLapse).
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

	for tile in _scarred_tiles.keys().duplicate():
		if not _path_scarring.is_worn(tile):
			_chunk_manager.destroy_at_global(tile.x, tile.y)
			_scarred_tiles.erase(tile)


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


## Condition-gated individual reproduction (see AnimalReproduction /
## ecosystem_dynamics.md): a healthy, well-fed creature past its birth cooldown
## spawns an offspring of the same species beside it. Suppressed once the scene
## is at MAX_LIVE_CREATURES (density dependence + safety bound). Offspring start
## with fresh moderate condition (via CreatureRenderer.spawn_single).
func _step_reproduction(delta: float) -> void:
	_reproduction_accumulator += delta
	if _reproduction_accumulator < REPRODUCTION_INTERVAL:
		return
	_reproduction_accumulator = 0.0

	var creatures := get_tree().get_nodes_in_group(CreatureMarker.GROUP_NAME)
	if creatures.size() >= MAX_LIVE_CREATURES:
		return

	var births := 0
	for creature in creatures:
		if creatures.size() + births >= MAX_LIVE_CREATURES:
			break
		if creature.info == null or not creature.has_method("can_reproduce") or not creature.can_reproduce():
			continue
		# Density dependence, not just a global node cap. The 60-creature cap
		# alone is a SAFETY bound, not an ecological one: it says nothing
		# about whether THIS clearing can feed another mouth, so well-fed
		# animals bred straight up to it and piled into one spot (reported
		# with a screenshot: "the fruit caused dozens of deer to spawn???").
		# Two checks, both local: how many of its own kind are already right
		# here, and whether the land itself can support another (the same
		# carrying capacity the unseen aggregate simulation obeys -- "two
		# fidelities, one truth", concept/ecosystem_dynamics.md).
		var crowd := _same_species_within(creature, NEIGHBOUR_RADIUS_PX)
		if crowd >= MAX_SAME_SPECIES_NEARBY:
			continue
		if not _chunk_manager.can_support_another_herbivore(creature.position, crowd):
			continue
		var offset := Vector2(
			_offset_hash(creature.position, 1), _offset_hash(creature.position, 2)
		) * OFFSPRING_SCATTER
		_creature_renderer.spawn_single(
			_creatures, creature.info.species, creature.position + offset, _chunk_manager
		)
		creature.on_reproduced()
		# The aggregate population owns the long-term picture, so an
		# individual birth in front of the player has to reach it -- otherwise
		# a herd the player watched grow evaporates on the next chunk reload,
		# and the off-screen model goes on breeding a range that is already
		# full (see EcosystemSimulation.record_birth).
		_chunk_manager.record_birth_at(creature.position)
		births += 1


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
## step_tree_spread never ran at all, and because step_tree_spread is what
## advances `_world_age_seconds`, the world clock was frozen at zero, so the
## season and weather never changed either. That is why nothing ever grew,
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
## UTC-driven solar elevation. Day is the DEFAULT during development: a debug
## build that happens to be run after sunset otherwise renders a dark world
## nothing can be evaluated in, and every dev launch would have to remember to
## set an env var. Exported builds still follow real time, so the shipped
## day/night cycle is unaffected. Precedence, highest first: the live console
## toggle (/day), the env var, then the build type. Pinned by
## test_world_daylight_default.gd.
static func always_day_for(force_day: bool, env_value: String, is_debug: bool) -> bool:
	if force_day:
		return true
	if env_value == "0":
		return false
	if env_value == "1":
		return true
	return is_debug


func _always_day() -> bool:
	return always_day_for(
		_force_day, OS.get_environment(DEBUG_ALWAYS_DAY_ENV), OS.is_debug_build()
	)


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
	_update_fishing_label(local_player)
	_update_lasso_label(local_player)
	_update_trade_label(local_player)
	_update_talk_label(local_player)
	_update_interaction_prompt(local_player)
	_update_charge_meter(local_player)
	_refresh_skill_window(local_player)
	_autosave_step(local_player, delta)
	var latitude := _geo_coordinates.latitude_for_tile(player_tile.y, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	var longitude := _geo_coordinates.longitude_for_tile(player_tile.x, EarthChunkGenerator.WORLD_WIDTH_TILES)

	# Real-world UTC time drives lighting directly: day/night always matches
	# what the sun is actually doing right now at the player's real-world
	# latitude/longitude, not an accelerated or arbitrary in-game clock --
	# unless overridden by DEBUG_ALWAYS_DAY_ENV for dev/testing.
	var utc := Time.get_datetime_dict_from_system(true)
	var day_of_year := _solar_position.day_of_year(utc.year, utc.month, utc.day)
	var utc_hour: float = utc.hour + utc.minute / 60.0 + utc.second / 3600.0

	var elevation := ALWAYS_DAY_ELEVATION if _always_day() else _solar_position.elevation_degrees(
		latitude, longitude, day_of_year, utc_hour
	)
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
	_day_night.color = Color(0.2 + sunlight * 0.8, 0.2 + sunlight * 0.8, 0.3 + sunlight * 0.7)
	# Drives every creature's silhouette shadow length (see DropShadow.
	# stretch_for_elevation / CreatureMarker.sun_elevation_deg) with the same
	# real sun position already computed for day/night lighting above.
	CreatureMarker.sun_elevation_deg = elevation

	var season := _chunk_manager.current_season().capitalize()
	var raw_weather := _chunk_manager.current_weather(local_player.position)
	# Water tiles react to the weather: raindrop ripples while raining,
	# windy chop otherwise, and the whole surface paces faster/slower with
	# how energetic the weather is (calm on a clear day, hectic in a storm).
	var raining := raw_weather == "rain" or raw_weather == "storm"
	_chunk_manager.set_rain(raining)
	# ... and the sky above them: rain you can actually see falling, heavier
	# in a storm than in ordinary rain (see RainOverlay).
	_rain_overlay.set_intensity(RAIN_INTENSITY_BY_WEATHER.get(raw_weather, 0.0))
	# Snow rather than rain when it is cold enough, and snow lying on the
	# ground afterwards (see Snowfall). Temperature decides, not the season
	# name -- a cold snap in autumn snows and a mild winter rains.
	var warmth := _chunk_manager.current_warmth()
	var snowing := Snowfall.falls_as_snow(raw_weather, warmth)
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
func _find_dry_land_spawn(candidate: Vector2i) -> Vector2i:
	for radius in range(SPAWN_SEARCH_RADIUS + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := candidate + Vector2i(dx, dy)
				if _chunk_manager.biome_at_global(tile.x, tile.y) != "ocean":
					return tile
	return candidate
