extends GutTest

## Real weapon mass feeding a swing's knockback (see docs/concept/
## materials.md's momentum = mass * velocity model, Throwable.impact_
## knockback, ItemCatalog's weapon mass wiring). Calibrated so the EXISTING
## tuned KNOCKBACK_FORCE (60px) is exactly what an iron sword -- already this
## game's baseline melee weapon -- delivers, so wiring in real mass does not
## silently retune every existing attack: only a weapon lighter/heavier than
## an iron sword (or bare hands) diverges from that baseline.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Item = preload("res://src/gameplay/item.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player
var _item_catalog := ItemCatalog.new()


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.position = Vector2(4 * TILE_SIZE, 4 * TILE_SIZE)
	player.setup(chunk_manager, TILE_SIZE)


func after_each():
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func test_bare_handed_knockback_equals_the_original_tuned_constant():
	assert_almost_eq(player._knockback_force_for(null), player.KNOCKBACK_FORCE, 0.01)


## The reference weapon this scaling is calibrated against -- existing
## gameplay tuning must not silently shift now that real mass is wired in.
func test_iron_sword_knockback_equals_the_original_tuned_constant():
	var sword := _item_catalog.make("iron_sword")
	assert_almost_eq(player._knockback_force_for(sword), player.KNOCKBACK_FORCE, 0.5)


func test_a_lighter_weapon_knocks_back_less_than_an_iron_sword():
	var club := _item_catalog.make("wooden_club")
	var sword := _item_catalog.make("iron_sword")
	assert_lt(player._knockback_force_for(club), player._knockback_force_for(sword))


## Real momentum scaling, not just a fixed number: an absurdly heavy weapon
## (were one ever added) should knock back harder than the sword baseline.
func test_a_heavier_weapon_knocks_back_more_than_an_iron_sword():
	var heavy := Item.new("test_heavy_weapon", "Test Heavy Weapon", "weapon", 1, 10.0, "", 0.0, 100.0)
	var sword := _item_catalog.make("iron_sword")
	assert_gt(player._knockback_force_for(heavy), player._knockback_force_for(sword))


## A weapon item with no mass modeled yet (mass_kg 0.0, e.g. a tool with no
## MATERIAL_AND_VOLUME entry) must not divide by zero or otherwise error --
## it falls back to the same original constant as bare hands.
func test_a_weapon_with_no_mass_modeled_falls_back_to_the_original_constant():
	var massless := Item.new("test_massless_weapon", "Test Massless Weapon", "weapon", 1, 10.0)
	assert_almost_eq(player._knockback_force_for(massless), player.KNOCKBACK_FORCE, 0.01)
