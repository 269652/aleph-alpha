extends GutTest

## World's click-to-target and Escape-clear dispatch (docs/concept/
## spell_runtime.md, "Explicit target selection"). The pool/cycle/toggle
## logic is tested directly on Player (test_player_spell_targeting.gd) and
## the priority ladder directly on EscapeAction (test_escape_action.gd) --
## this covers the thin, testable half of World's own wiring:
## _dispatch_creature_click and _apply_escape_action's CLEAR_TARGET branch,
## both of which take `local_player` as an explicit parameter rather than
## resolving it themselves.
##
## That split is deliberate, not incidental. World normally resolves "which
## Player is local" via multiplayer.get_unique_id() (~30 call sites in this
## file do this; _on_world_clicked/_handle_escape are two more), which
## requires a live SceneTree -- a bare World.new() (used here, like
## test_world_house_panel_wiring.gd, specifically to dodge World._ready()'s
## license-gate check and asset-warming cost) has no `multiplayer` property
## at all. Confirmed directly: calling _on_world_clicked with `_players` set
## crashes on exactly that line ("Cannot call method 'get_unique_id' on a
## null value"), and _handle_escape unconditionally ends in
## get_viewport().set_input_as_handled(), which crashes the same way -- so
## neither entry point itself is driveable here. None of the other ~30
## lookups are unit-tested anywhere either, for the same reason; this file
## only reaches past that limitation for the two pieces that are actually
## new, by giving each its own `local_player`-as-parameter seam.

const World = preload("res://scenes/world.gd")
const CraftingWindow = preload("res://scenes/crafting_window.gd")
const QuestLogWindow = preload("res://scenes/quest_log_window.gd")
const ConversationWindow = preload("res://scenes/conversation_window.gd")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const HousePanel = preload("res://scenes/house_panel.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const PlayerScene = preload("res://scenes/player.tscn")
const Player = preload("res://scenes/player.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const EscapeAction = preload("res://src/ui/escape_action.gd")

var world: World
var panel: HousePanel
var chunk_manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var player: Player


func before_each():
	world = World.new()
	panel = HousePanel.new()
	add_child_autofree(panel)
	world._house_panel = panel

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child_autofree(tile_map_layer)
	add_child_autofree(entities_parent)
	add_child_autofree(creatures_parent)
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))
	world._chunk_manager = chunk_manager

	# _any_gameplay_window_open reads all five modal windows, so a bare
	# World.new() needs them to exist before any click is routed at all (see
	# test_world_house_panel_wiring.gd).
	world._inventory_window = PanelContainer.new()
	world._crafting_window = CraftingWindow.new()
	world._quest_log_window = QuestLogWindow.new()
	world._conversation_window = ConversationWindow.new()
	world._skill_window = SkillTreeWindow.new()
	for window in [
		world._inventory_window, world._crafting_window, world._quest_log_window,
		world._conversation_window, world._skill_window,
	]:
		window.visible = false
		add_child_autofree(window)

	player = PlayerScene.instantiate()
	add_child_autofree(player)
	player.setup(chunk_manager, TerrainRenderer.TILE_SIZE)


func after_each():
	world.free()


func _creature_at(species: String, offset: Vector2) -> CreatureMarker:
	var marker := CreatureMarker.new()
	marker.info = CreatureInfo.new(species, 1)
	marker.wander_seed = 9
	add_child_autofree(marker)
	marker.setup(chunk_manager, TerrainRenderer.TILE_SIZE)
	marker.position = player.position + offset
	return marker


# -- _dispatch_creature_click: the creature half of _on_world_clicked -------

func test_dispatch_creature_click_targets_a_hostile_creature_and_reports_handled():
	var wolf := _creature_at("wolf", Vector2(20, 0))

	assert_true(world._dispatch_creature_click(wolf.position, player))
	assert_eq(player.explicit_target(), wolf)


func test_dispatch_creature_click_toggles_off_on_a_second_click_and_still_reports_handled():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	world._dispatch_creature_click(wolf.position, player)

	assert_true(world._dispatch_creature_click(wolf.position, player))

	assert_null(player.explicit_target())


func test_dispatch_creature_click_on_empty_ground_reports_unhandled():
	assert_false(world._dispatch_creature_click(Vector2(999999, 999999), player))
	assert_null(player.explicit_target())


## _on_world_clicked's own guard: no local player resolved (a World not
## fully wired, or genuinely nobody playing) is simply unhandled, never a
## crash.
func test_dispatch_creature_click_with_no_local_player_reports_unhandled():
	assert_false(world._dispatch_creature_click(Vector2.ZERO, null))


## Without a live local-player registry at all (e.g. a World not yet fully
## wired -- the exact state test_world_house_panel_wiring.gd's own
## before_each leaves `_players` in), a real click through the actual entry
## point must fall through without crashing. This goes through
## _on_world_clicked itself (not _dispatch_creature_click) because `_players
## == null` is caught before multiplayer.get_unique_id() is ever reached.
func test_a_click_with_no_players_registry_does_not_crash():
	world._players = null

	world._on_world_clicked(Vector2(0, 0))
	# No assertion beyond "did not crash" -- GUT fails the test on any
	# unhandled engine error regardless.


# -- _apply_escape_action(CLEAR_TARGET): the new half of _handle_escape -----

func test_apply_escape_action_clear_target_clears_the_players_target():
	var wolf := _creature_at("wolf", Vector2(20, 0))
	player.toggle_explicit_target(wolf)

	world._apply_escape_action(EscapeAction.CLEAR_TARGET, player)

	assert_null(player.explicit_target())


## The pre-existing branches beside it are untouched by this change --
## pinned here once, directly, now that _apply_escape_action exists as its
## own callable unit (CLOSE_SETTINGS/OPEN_SETTINGS still reach
## _toggle_settings_menu's get_tree().paused write, so stay untestable here).
func test_apply_escape_action_close_windows_still_closes_them():
	world._inventory_window.visible = true

	world._apply_escape_action(EscapeAction.CLOSE_WINDOWS, player)

	assert_false(world._inventory_window.visible)
