extends GutTest

## Where /village really sends you (docs/concept/village_growth.md,
## Mechanism 6).
##
## Reported twice. First *"It teleports me to where no village is"*, which
## earned the layout pre-check `_village_would_settle`; then, with the
## console still on screen and nothing but grass around, *"/village
## teleports me to an empty field..."*.
##
## The pre-check is a PREDICTION -- it re-derives the roster and the layout
## and never looks at the ground, because it deliberately loads nothing. So
## the command checks the world: a chunk with no buildings standing in it is
## not a village, and the destination is a real building's doorstep rather
## than a planned well.
##
## Chunks are injected directly rather than generated -- the same cheap shape
## test_earth_chunk_manager_clear_vegetation.gd uses.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const Chunk = preload("res://src/world/chunk.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const CHUNK := Vector2i(3, 4)

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## A chunk with a real building record in it, the way a founded village's
## chunk looks once it has been loaded.
func _chunk_with_a_house() -> Chunk:
	var chunk := Chunk.new()
	var origin := Vector2i(6, 6)
	for local in BuildingCatalog.footprint_cells("house_small", origin):
		chunk.modifications[local] = (
			"house_small" if local == origin else BuildingCatalog.FOOTPRINT_TILE_ID
		)
	chunk.buildings[origin] = {
		"id": "house_small", "facing": Vector2i(0, 1), "seed": 1,
		"condition": 1.0, "progress": 1.0, "owner_household_id": "",
		"occupation": "", "resident_seed": 0,
	}
	return chunk


# -- a village is where buildings really stand ------------------------------

func test_a_loaded_chunk_with_a_building_reports_a_real_place_to_land():
	manager._loaded_chunks[CHUNK] = _chunk_with_a_house()

	var at = manager.standing_village_position(CHUNK)

	assert_not_null(at, "a chunk with a house standing in it is a village")


## And the place really is the house's own doorstep -- a cell a building has,
## not a cell a plan drew.
func test_where_it_lands_you_is_a_real_buildings_doorstep():
	manager._loaded_chunks[CHUNK] = _chunk_with_a_house()

	var at: Vector2 = manager.standing_village_position(CHUNK)
	var tile := Vector2i(
		floori(at.x / float(TerrainRenderer.TILE_SIZE)), floori(at.y / float(TerrainRenderer.TILE_SIZE))
	)
	var expected: Vector2i = (
		CHUNK * EarthChunkManager.CHUNK_SIZE + Vector2i(6, 6)
		+ BuildingCatalog.doorstep_of("house_small")
	)
	assert_eq(tile, expected, "you land at the door, not on the roof or on a plan")


## The whole point of the second report: a chunk the prediction liked, with
## nothing actually standing in it, is not a village.
func test_a_loaded_chunk_with_nothing_standing_is_not_a_village():
	manager._loaded_chunks[CHUNK] = Chunk.new()

	assert_null(
		manager.standing_village_position(CHUNK),
		"an empty field is an empty field, whatever the layout predicted"
	)


## A candidate that turns out not to be a village leaves nothing behind: a
## chunk this check loaded is unloaded again.
func test_a_rejected_candidate_is_not_left_loaded():
	assert_false(manager._loaded_chunks.has(CHUNK), "precondition: not loaded")

	manager.standing_village_position(CHUNK)

	assert_false(manager._loaded_chunks.has(CHUNK), "the search tidied up after itself")


## And a chunk that was ALREADY loaded is left loaded -- the check must not
## unload the chunk the player is standing in.
func test_a_chunk_that_was_already_loaded_stays_loaded():
	manager._loaded_chunks[CHUNK] = _chunk_with_a_house()

	manager.standing_village_position(CHUNK)

	assert_true(manager._loaded_chunks.has(CHUNK), "somebody else's chunk is not ours to unload")
