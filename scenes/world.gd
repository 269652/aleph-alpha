extends Node2D

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
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
const FoodConsumption = preload("res://src/gameplay/food_consumption.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")
const SettingsOverlay = preload("res://scenes/settings_overlay.gd")
const MainMenu = preload("res://scenes/main_menu.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const HOTBAR_SLOT_COUNT := 5
const SPELL_BAR_SLOT_COUNT := 4
const HUD_SLOT_SIZE := 32.0
const HUD_SLOT_BG_COLOR := Color(0.15, 0.15, 0.15, 0.85)
const HUD_SLOT_LOCKED_COLOR := Color(0.08, 0.08, 0.08, 0.6)

## Real seconds between minimap texture refreshes -- sampling thousands of
## tiles every frame would be wasteful; the player doesn't need pixel-perfect
## real-time minimap updates.
const MINIMAP_REFRESH_INTERVAL := 1.0

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

## Debug/dev-console override: when this env var is "1", lighting is forced
## to a fixed full-sun elevation instead of the real UTC-driven calculation --
## useful for testing without waiting on real-world day/night.
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

@onready var _terrain: TileMapLayer = $Terrain
@onready var _entities: Node2D = $Entities
@onready var _creatures: Node2D = $Creatures
@onready var _ground_items: Node2D = $GroundItems
@onready var _players: Node2D = $Players
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
var _is_dedicated_server := false
var _minimap_renderer := MinimapRenderer.new()
var _minimap_refresh_accumulator := MINIMAP_REFRESH_INTERVAL  # refresh immediately on first update
var _health_bar := HealthBar.new()
var _item_sprite_generator := ProceduralItemSprite.new()
var _hotbar_slots: Array[TextureRect] = []
var _hotbar_counts: Array[Label] = []
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
## Shared dark/rounded UI theme (see UiTheme), assigned to every window/menu so
## the whole UI reads as one styled system rather than raw grey boxes.
var _ui_theme := UiTheme.new().build_theme()
var _class_archetypes := ClassArchetype.new()
## Class chosen at the main menu, applied to the local player on spawn.
var _pending_class := "warrior"
var _keybindings := Keybindings.new()
var _graphics_fullscreen := false
var _graphics_vsync := true
var _death_label: Label
var _creature_panels_container: VBoxContainer
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
var _wallet_label: Label
var _creature_panels_accumulator := CREATURE_PANELS_REFRESH_INTERVAL  # refresh immediately
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
	_player_spawner.spawn_path = _players.get_path()
	_player_spawner.add_spawnable_scene(PlayerScene.resource_path)
	WorldItemBus.item_dropped.connect(_on_item_dropped)

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
	_build_death_label()
	_build_survival_bar()
	_build_xp_bar()
	_build_fishing_label()

	var args := OS.get_cmdline_user_args()
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


## Builds the start-up main menu (see MainMenu). The world is paused behind it
## (the menu itself keeps running via PROCESS_MODE_ALWAYS) until a choice is made.
func _show_main_menu() -> void:
	# A full-screen dim backdrop so the game world/HUD doesn't bleed through
	# behind the menu (it did before this pass).
	_menu_backdrop = ColorRect.new()
	_menu_backdrop.color = Color(0.04, 0.05, 0.07, 0.94)
	_menu_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(_menu_backdrop)

	_main_menu = MainMenu.new()
	_main_menu.theme = _ui_theme
	_main_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(_main_menu)
	_main_menu.start_requested.connect(_on_menu_start_requested)
	_main_menu.join_requested.connect(_on_menu_join_requested)
	get_tree().paused = true


func _on_menu_start_requested(mode: String, chosen_class: String) -> void:
	_pending_class = chosen_class
	if mode == "host":
		_start_server()
	_spawn_local_singleplayer()
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


## Clicking an inventory row activates that item (see Player.activate_item_id):
## weapons/tools get equipped, food/potions get used, raw materials do nothing.
func _on_inventory_item_clicked(item_id: String) -> void:
	var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
	if local_player != null:
		local_player.activate_item_id(item_id)
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
	_crafting_window.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_crafting_window.offset_left = -320.0
	_crafting_window.offset_top = -120.0
	_crafting_window.offset_right = -8.0
	_crafting_window.offset_bottom = 120.0
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
	_settings_overlay.setup(_keybindings, _graphics_fullscreen, _graphics_vsync)
	_settings_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_settings_overlay.offset_left = -210.0
	_settings_overlay.offset_top = -210.0
	_settings_overlay.offset_right = 210.0
	_settings_overlay.offset_bottom = 210.0
	_ui.add_child(_settings_overlay)
	_settings_overlay.binding_changed.connect(_on_binding_changed)
	_settings_overlay.reset_requested.connect(_on_bindings_reset)
	_settings_overlay.graphics_changed.connect(_on_graphics_changed)
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


## Graphics settings persist alongside key bindings in KEYBINDINGS_PATH (one
## small user config file). Applied at startup by _apply_graphics.
func _load_graphics() -> void:
	var config := ConfigFile.new()
	if config.load(KEYBINDINGS_PATH) != OK:
		return
	_graphics_fullscreen = config.get_value("graphics", "fullscreen", _graphics_fullscreen)
	_graphics_vsync = config.get_value("graphics", "vsync", _graphics_vsync)


func _apply_graphics() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if _graphics_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if _graphics_vsync else DisplayServer.VSYNC_DISABLED
	)


func _save_graphics() -> void:
	var config := ConfigFile.new()
	config.load(KEYBINDINGS_PATH)  # preserve the [bindings] section
	config.set_value("graphics", "fullscreen", _graphics_fullscreen)
	config.set_value("graphics", "vsync", _graphics_vsync)
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


func _update_fishing_label(local_player: Player) -> void:
	_fishing_label.text = local_player.fishing_message
	_fishing_label.visible = local_player.fishing_message != ""


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
		_toggle_settings_menu()
	else:
		_handle_hotbar_hotkeys(event)


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
					"Commands: /day  /spawn <herbivore|boar|predator|lynx> [count]  /give <item_id> [count]"
					+ "  /craft <recipe_id>  /gold <amount>  /help"
				)
			)
		"day":
			_force_day = true
			_dev_console.log_line("Time forced to day.")
		"spawn":
			_handle_spawn_command(args, local_player)
		"give":
			_handle_give_command(args, local_player)
		"craft":
			_handle_craft_command(args, local_player)
		"gold":
			_handle_gold_command(args, local_player)
		_:
			_dev_console.log_line("Unknown command: /%s (try /help)" % command)


func _handle_spawn_command(args: Array, local_player: Player) -> void:
	if local_player == null:
		_dev_console.log_line("No local player to spawn near.")
		return

	var species := "herbivore"
	if args.size() >= 1:
		species = String(args[0]).to_lower()
	if not CreatureRenderer.SPECIES_COLORS.has(species):
		_dev_console.log_line(
			"Unknown species '%s' (try %s)." % [species, ", ".join(CreatureRenderer.SPECIES_COLORS.keys())]
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


## Spawns a clickable ground item where a creature died or a tree dropped
## forage. Only the simulation-owning side (server/singleplayer) holds the
## authoritative item layer for now -- ground items aren't replicated yet.
func _on_item_dropped(item_stack, world_position: Vector2) -> void:
	if _ground_items.get_child_count() >= MAX_GROUND_ITEMS:
		_ground_items.get_child(0).queue_free()  # drop the oldest to stay bounded
	var dropped := DroppedItem.new()
	dropped.item_stack = item_stack
	dropped.position = world_position
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
		var slot := _make_hud_slot(HUD_SLOT_BG_COLOR)
		# Clicking a slot activates it, same as its number hotkey.
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_hotbar_slot_gui_input.bind(i))

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


## A left-click on hotbar slot `index` activates it (equip/use), same as its
## number hotkey.
func _on_hotbar_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		if local_player != null:
			local_player.activate_hotbar_slot(index)


## A fixed row of locked placeholder slots for future abilities -- there is no
## spell/ability system yet (see docs/progress.md), so these are an honest
## stub, not fake functionality.
func _build_spell_bar() -> void:
	for i in SPELL_BAR_SLOT_COUNT:
		_spell_bar.add_child(_make_hud_slot(HUD_SLOT_LOCKED_COLOR))


func _make_hud_slot(color: Color) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(HUD_SLOT_SIZE, HUD_SLOT_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.2)
	slot.add_theme_stylebox_override("panel", style)
	return slot


## Fills the hotbar's slot icons/counts from the first HOTBAR_SLOT_COUNT
## inventory stacks; empty slots are left blank.
func _update_hotbar(local_player: Player) -> void:
	var stacks: Array = local_player.inventory.stacks()
	for i in HOTBAR_SLOT_COUNT:
		if i < stacks.size():
			var stack = stacks[i]
			_hotbar_slots[i].texture = _item_sprite_generator.generate_texture(stack.item.id)
			_hotbar_counts[i].text = str(stack.count) if stack.count > 1 else ""
		else:
			_hotbar_slots[i].texture = null
			_hotbar_counts[i].text = ""


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
	player.position = Vector2(_compute_dry_land_spawn_tile() * TerrainRenderer.TILE_SIZE)
	player.respawn_position = player.position
	_players.add_child(player)
	player.setup(_chunk_manager, TerrainRenderer.TILE_SIZE)
	print("[server] peer %d connected, spawned player" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	print("[server] peer %d disconnected" % peer_id)


func _on_connected_to_server() -> void:
	print("[client] connected, own peer id %d" % multiplayer.get_unique_id())


## Only used when running with no networking at all (quick local playtesting).
func _spawn_local_singleplayer() -> void:
	var player := PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	player.position = Vector2(_compute_dry_land_spawn_tile() * TerrainRenderer.TILE_SIZE)
	player.respawn_position = player.position
	player.apply_class(_pending_class, _class_archetypes.stats_for(_pending_class))
	_players.add_child(player)
	player.setup(_chunk_manager, TerrainRenderer.TILE_SIZE)


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
	return _find_dry_land_spawn(spawn_tile)


## Safety cap so ground items can't accumulate without bound (they'd leak CPU
## and memory over a long session). Oldest is removed when the cap is hit.
const MAX_GROUND_ITEMS := 80


func _process(delta: float) -> void:
	if _owns_ecosystem_simulation():
		_chunk_manager.step_ecosystem(delta)
		_chunk_manager.step_forage(delta)
		_chunk_manager.step_tree_spread(delta)
		_chunk_manager.step_tall_grass(delta)
		_chunk_manager.step_desert_scrub(delta)
		_chunk_manager.step_tundra_lichen(delta)
		var focus_player := _players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		if focus_player != null:
			_chunk_manager.step_fruiting(delta, focus_player.position)
		_step_path_scarring(delta)
		_step_herbivore_food_consumption(delta)
		_step_reproduction(delta)

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
		var offset := Vector2(
			_offset_hash(creature.position, 1), _offset_hash(creature.position, 2)
		) * OFFSPRING_SCATTER
		_creature_renderer.spawn_single(
			_creatures, creature.info.species, creature.position + offset, _chunk_manager
		)
		creature.on_reproduced()
		births += 1


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
func _owns_ecosystem_simulation() -> bool:
	return _is_dedicated_server or multiplayer.multiplayer_peer == null


func _always_day() -> bool:
	return _force_day or OS.get_environment(DEBUG_ALWAYS_DAY_ENV) == "1"


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
	_update_survival_bar(local_player)
	_update_xp_bar(local_player)
	_update_fishing_label(local_player)
	_refresh_skill_window(local_player)
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
	var sunlight := _solar_position.sunlight_intensity(elevation)
	_day_night.color = Color(0.2 + sunlight * 0.8, 0.2 + sunlight * 0.8, 0.3 + sunlight * 0.7)

	var season := _chunk_manager.current_season().capitalize()
	var raw_weather := _chunk_manager.current_weather(local_player.position)
	# Water tiles react to the weather: raindrop ripples while raining,
	# windy chop otherwise (repaints only on an actual transition).
	_chunk_manager.set_rain(raw_weather == "rain" or raw_weather == "storm")
	var weather := raw_weather.capitalize()
	_debug_label.text = (
		"Lat %.1f Lon %.1f   UTC %02d:%02d   Sun elev %.1f°   %s · %s   Mode: %s   Speed: %d%%"
		% [
			latitude,
			longitude,
			utc.hour,
			utc.minute,
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
