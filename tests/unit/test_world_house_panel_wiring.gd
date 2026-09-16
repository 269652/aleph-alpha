extends GutTest

## What World actually does with a left-click in the world
## (docs/concept/village_growth.md mechanism 5).
##
## The readout is built and tested on its own (test_house_panel.gd) and its
## data is built and tested on its own (test_earth_chunk_manager_village_
## growth.gd) -- but a feature that is green in both and never opens on
## screen is not done, so the one call site that joins them gets a test of
## its own rather than being filed under "World is untested glue" (the same
## reasoning test_world_inventory_wiring.gd's own header gives).

const World = preload("res://scenes/world.gd")
const CraftingWindow = preload("res://scenes/crafting_window.gd")
const QuestLogWindow = preload("res://scenes/quest_log_window.gd")
const ConversationWindow = preload("res://scenes/conversation_window.gd")
const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")
const HousePanel = preload("res://scenes/house_panel.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const _HOUSE_TILE := Vector2i(12, 7)


## A real EarthChunkManager with household_report_at overridden to answer
## from a fixed, test-controlled map -- World declares `_chunk_manager`
## with that exact type, and World only ever asks it this one question
## here, so nothing has to be generated and no chunk has to be loaded.
class StubChunkManager extends EarthChunkManager:
	var reports: Dictionary = {}  # Vector2i tile -> report
	var asked: Array = []

	func household_report_at(global_x: int, global_y: int) -> Dictionary:
		asked.append(Vector2i(global_x, global_y))
		return reports.get(Vector2i(global_x, global_y), {})


var world: World
var panel: HousePanel
var chunk_manager: StubChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


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
	chunk_manager = StubChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	# _any_gameplay_window_open reads all five modal windows, so a bare
	# World.new() needs them to exist before any click is routed at all.
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
	chunk_manager.reports[_HOUSE_TILE] = {
		"building_id": "house_small", "capacity": 1, "is_home": true,
		"household_id": "household:npc:3", "resident_name": "Ilsa Rook",
		"resident_occupation": "farmer", "wallet_balance": 6,
		"needs": {"food": 0.8, "shelter": 1.0, "income": 0.3, "community": 0.2},
		"happiness": 0.6, "productivity": 0.5, "settlement_productivity": 0.6,
	}
	world._chunk_manager = chunk_manager


func after_each():
	world.free()


## World resolves a world position to a tile before asking, so a click at
## the tile's own pixel centre must land on exactly that tile -- the same
## `(cell + 0.5) * TILE_SIZE` convention every placed entity uses.
func _click_tile(tile: Vector2i) -> void:
	world._on_world_clicked((Vector2(tile) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE)


func test_clicking_a_house_opens_the_readout_on_it():
	_click_tile(_HOUSE_TILE)
	assert_true(panel.is_open(), "a click on a building opens its readout")
	assert_true(panel.subtitle_text().contains("Ilsa Rook"))


func test_the_world_asks_the_chunk_manager_about_the_tile_that_was_clicked():
	_click_tile(_HOUSE_TILE)
	assert_eq(chunk_manager.asked, [_HOUSE_TILE], "the tile under the cursor, not some other one")


func test_clicking_bare_ground_closes_a_readout_that_was_open():
	_click_tile(_HOUSE_TILE)
	assert_true(panel.is_open(), "precondition")
	_click_tile(Vector2i(40, 40))
	assert_false(panel.is_open(), "clicking elsewhere is a real answer, not a stale panel")


## Every other world-space affordance in World is suppressed while a modal
## is open; the readout is no exception, and must not steal a click aimed
## at the window on top of it.
func test_a_click_is_ignored_while_a_gameplay_window_is_open():
	world._inventory_window.visible = true

	_click_tile(_HOUSE_TILE)

	assert_false(panel.is_open())
	assert_true(chunk_manager.asked.is_empty(), "the world was never even asked")


func test_escape_closing_the_gameplay_windows_closes_the_readout_too():
	_click_tile(_HOUSE_TILE)
	assert_true(panel.is_open(), "precondition")

	world._close_gameplay_windows()

	assert_false(panel.is_open())
