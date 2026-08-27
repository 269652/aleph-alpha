extends GutTest

## What World actually hands the inventory window when it refreshes it.
##
## Both of these are features that were built and tested elsewhere but could
## not be SEEN in the running game, because the one call site that feeds them
## lives here: per-item food freshness needs the world's current season, and
## the paperdoll needs the player's authored appearance or it draws
## CharacterView's default warrior for everyone. A feature that is green in
## its own unit test and invisible on screen is not done -- so the wiring
## itself gets a test, rather than being filed under "World is untested glue"
## (docs/concept/persistence.md).

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const PlayerScene = preload("res://scenes/player.tscn")


## Stands in for the real InventoryWindow and records what it was handed.
## World declares `_inventory_window` as a plain PanelContainer, so a
## recorder drops straight in without building the real window's node tree.
## The signature matches InventoryWindow.refresh exactly, defaults included,
## so a call that omits the season still lands here rather than erroring.
class RecordingInventoryWindow extends PanelContainer:
	var refresh_calls: Array = []
	var applied_appearance = null

	func refresh(
		stacks: Array, equipped: Dictionary, total_armor: float, slot_count: int = 12,
		season: String = ""
	) -> void:
		refresh_calls.append({
			"stacks": stacks,
			"equipped": equipped,
			"total_armor": total_armor,
			"slot_count": slot_count,
			"season": season,
		})

	func apply_appearance(appearance: Dictionary) -> void:
		applied_appearance = appearance


var world: World
var window: RecordingInventoryWindow
var player: Node
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	# Not add_child()'d: _refresh_inventory_now touches only plain
	# (non-@onready) fields, the same way test_world_persistence builds World.
	world = World.new()
	window = RecordingInventoryWindow.new()
	world._inventory_window = window

	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	world._chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)

	player = PlayerScene.instantiate()
	player.appearance = {"skin": Color(0.9, 0.7, 0.5), "hair": Color(0.2, 0.1, 0.05)}


func after_each():
	player.free()
	window.free()
	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Food's shelf life is seasonal (see InventoryWindow's freshness line), and
## the window cannot know the season by itself -- the world clock lives on
## EarthChunkManager. Without this argument the freshness/shelf-life line
## silently never appears, which is exactly how it shipped: implemented,
## unit-tested, and invisible.
func test_the_inventory_refresh_carries_the_worlds_current_season():
	world._refresh_inventory_now(player)

	assert_eq(window.refresh_calls.size(), 1)
	var season: String = window.refresh_calls[0]["season"]
	assert_ne(season, "", "the window was told nothing about the season")
	assert_eq(season, world._chunk_manager.current_season())


## The paperdoll must show the character the player authored in the creator,
## not CharacterView's default warrior -- every player looked identical in
## their own inventory otherwise.
func test_the_inventory_paperdoll_shows_the_players_own_character():
	world._refresh_inventory_now(player)

	assert_eq(window.applied_appearance, player.appearance)


## The season lookup has to survive a refresh that happens before the chunk
## manager exists (World builds its UI before it builds the world) -- an
## empty season is the window's own documented default, a crash is not.
func test_a_refresh_before_the_world_exists_does_not_crash():
	world._chunk_manager = null

	world._refresh_inventory_now(player)

	assert_eq(window.refresh_calls.size(), 1)
	assert_eq(window.refresh_calls[0]["season"], "")
