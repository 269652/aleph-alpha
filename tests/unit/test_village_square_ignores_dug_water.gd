extends GutTest

## The square's own rectangle must be derived from water that NEVER MOVES.
##
## VillageLayout.plaza_x0_for and EarthChunkManager._is_dry_local both say
## so in as many words -- *"water is the one input that never changes once
## the world is seeded: trees get felled and ground gets built on, rivers do
## not move"* -- because every consumer of the square (the founding layout,
## the reload's re-paving, the civic plot, the growth ladder's next plot,
## the well/stall/gate) has to re-derive the SAME rectangle with nothing
## persisted.
##
## It stopped being true when ponds became real water. A fisher digs a 3x2
## pond beside their own door (docs/concept/village_ponds.md) and writes
## `pond_water` into chunk.modifications; is_water_at_global answers the dug
## pond FIRST, before anything the generator knows. So the square's siting
## predicate started reading BUILT water, and the square moved under its own
## village.
##
## Measured on the reported village, chunk (676,148) at lat 47.2 lon 15.1,
## across two runs of the same seed (tools/probe_village_hall.gd): the
## square sat at x0=7 in one and x0=12 in the other, purely because the
## village laid out differently and its pond landed somewhere else. A square
## that moves leaves its own paving behind: the well, the stall, the market
## stands and the civic plot all point at ground nobody paved.
##
## Berlin's real chunk loaded directly via _load_chunk, the same shape
## test_earth_chunk_manager_water_reclaims.gd uses, with its persisted files
## scrubbed before and after -- tests share one real user:// dir.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_chunk_coord = Vector2i(
		floori(float(berlin.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(berlin.y) / EarthChunkManager.CHUNK_SIZE)
	)
	_scrub()
	manager._load_chunk(_chunk_coord)


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	var path: String = manager._modifications_path(_chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## A dry cell of this chunk, as a LOCAL cell.
func _dry_local():
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var local := Vector2i(x, y)
			var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + local
			if manager.is_buildable_terrain_at(g.x, g.y):
				return local
	return null


func _dig_pond_at(local: Vector2i) -> void:
	var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + local
	manager.build_at_global(g.x, g.y, VillagePond.POND_TILE_ID)


## The generated world's own water, with nothing anybody dug in it.
func test_generated_water_ignores_a_dug_pond():
	var local = _dry_local()
	assert_not_null(local, "precondition: this chunk has dry ground")
	var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + local
	_dig_pond_at(local)
	assert_true(
		manager.is_water_at_global(g.x, g.y),
		"a dug pond is still real water to everything that asks about water"
	)
	assert_false(
		manager.is_generated_water_at_global(g.x, g.y),
		"...but it is not water the GENERATOR ever put there"
	)


## The square's own predicate reads the generated world, so a pond dug
## beside a fisher's door cannot move the village's centre.
func test_the_squares_predicate_does_not_see_a_dug_pond():
	var local = _dry_local()
	assert_not_null(local, "precondition: this chunk has dry ground")
	_dig_pond_at(local)
	var is_dry: Callable = manager._is_dry_local(_chunk_coord)
	assert_true(is_dry.call(local), "the square's siting read a dug pond as water")


## ...and so the rectangle itself is the same before and after the dig.
func test_the_square_does_not_move_when_a_pond_is_dug_on_it():
	var before: Rect2i = VillageLayout.skeleton(
		EarthChunkManager.CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord),
		manager._is_dry_local(_chunk_coord)
	)["plaza"]
	# Dig right through the square's own middle row -- the worst case there
	# is, and exactly where a fisher's pond may land.
	for x in range(before.position.x, before.end.x):
		_dig_pond_at(Vector2i(x, before.position.y))
	var after: Rect2i = VillageLayout.skeleton(
		EarthChunkManager.CHUNK_SIZE, VillageLayout.seed_for(_chunk_coord),
		manager._is_dry_local(_chunk_coord)
	)["plaza"]
	assert_eq(after, before, "the square moved out from under its own village")
