extends GutTest

## docs/concept/village_ponds.md "A pond dug the day the fisher's house
## stands": a re-derivation of the village (EarthChunkManager
## ._respawn_village -- run on an arrival and on a completed building) keeps
## the village's LIVE market: the purse the cart fills and the wages come
## out of (NpcEconomy.PURSE_META) and the stall's own stock both live on
## that object, and a spawn that made a fresh one wiped both. Measured in
## play with the economy probe: the purse fell to 0 the moment a house
## completed, wages stopped, and the roster fell from ten to five.
##
## The first real settlement chunk near Berlin whose village spawns with a
## live market, loaded directly the way test_earth_chunk_manager_village_
## growth.gd does.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _generator := SettlementGenerator.new()
var _chunk_coord: Vector2i
var _settlement_id: String

static var _cached_chunk_coord: Vector2i
static var _cached_chunk_coord_found := false


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	if not _cached_chunk_coord_found:
		_cached_chunk_coord = _find_settlement_chunk_with_a_live_market()
		_cached_chunk_coord_found = true
	_chunk_coord = _cached_chunk_coord
	_settlement_id = EntityRef.for_settlement(_chunk_coord)
	_scrub()
	manager._load_chunk(_chunk_coord)


func _find_settlement_chunk_with_a_live_market() -> Vector2i:
	var geo := GeoCoordinates.new()
	var center := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	var loads := 0
	for dy in range(-15, 16):
		for dx in range(-15, 16):
			var coord := center + Vector2i(dx, dy)
			if not _generator.has_settlement_at(coord, "grassland"):
				continue
			loads += 1
			_chunk_coord = coord
			_scrub()
			manager._load_chunk(coord)
			var live: bool = manager.village_market_for_settlement(EntityRef.for_settlement(coord)) != null
			manager._unload_chunk(coord)
			_scrub()
			if live:
				return coord
			if loads >= 20:
				break
	fail_test("no real settlement chunk with a live village market found near Berlin")
	return Vector2i.ZERO


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _live_market():
	return manager.village_market_for_settlement(_settlement_id)


func test_the_premise_the_village_trades_in_a_live_market():
	assert_not_null(_live_market(), "Berlin's village is spawned with a market its villagers share")


func test_a_re_derivation_keeps_the_purse():
	var market = _live_market()
	assert_not_null(market)
	NpcEconomy.deposit_to_purse(market, 50.0)
	manager._respawn_village(_chunk_coord)
	var after = _live_market()
	assert_not_null(after, "the village stands again after the re-derivation")
	assert_eq(NpcEconomy.purse_of(after), 50.0, "the purse the cart filled is gone")


func test_a_re_derivation_keeps_the_stalls_stock():
	var market = _live_market()
	assert_not_null(market)
	market.add_stock("herb", 5.0)
	manager._respawn_village(_chunk_coord)
	var after = _live_market()
	assert_not_null(after)
	assert_eq(float(after.stock.get("herb", 0.0)), 5.0, "the stall's stock is gone")


func test_an_arrival_keeps_the_purse():
	var market = _live_market()
	assert_not_null(market)
	NpcEconomy.deposit_to_purse(market, 50.0)
	assert_ne(manager.admit_household(_chunk_coord), "", "precondition: a household arrived")
	assert_eq(NpcEconomy.purse_of(_live_market()), 50.0, "an arrival emptied the purse")
