extends GutTest

## The mage guild as a real place in the world (docs/concept/mage_guild.md
## mechanisms 3 and 4): a guild ages, masters move in, and a player who
## walks inside can be taught by whoever is there.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const MageGuildRoster = preload("res://src/gameplay/mage_guild_roster.gd")
const MageMaster = preload("res://src/gameplay/mage_master.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE
const GUILD_ID := "mage_guild"

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var book := SpellBook.new()
## Everything this test placed, torn down in after_each: these are
## PERSISTED buildings in a real user:// dir shared with every other test
## in the run, and Berlin's chunk is where several of them go looking for
## clear ground.
var _placed: Array = []


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	chunk_manager.update(Vector2i(0, 0))


func after_each():
	for site in _placed:
		chunk_manager.remove_building(site["chunk_coord"], site["origin"])
	_placed.clear()
	chunk_manager.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## A real site for `building_id` on ground that is really dry, in BERLIN's
## chunk -- global tile (0, 0) is the Earth projection's corner and the
## whole origin neighbourhood is open ocean, so a site has to be found
## rather than assumed. Same move, same reason, as test_player.gd's own
## _a_dry_site_for.
func _a_dry_site_for(building_id: String) -> Dictionary:
	var footprint := BuildingCatalog.footprint_of(building_id)
	var geo := GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	var size := EarthChunkManager.CHUNK_SIZE
	var chunk_coord := Vector2i(floori(float(berlin.x) / size), floori(float(berlin.y) / size))
	chunk_manager._load_chunk(chunk_coord)
	for y in range(2, size - footprint.y - 2):
		for x in range(2, size - footprint.x - 2):
			var origin := Vector2i(x, y)
			var global_origin: Vector2i = chunk_coord * size + origin
			var cells: Array = BuildingCatalog.footprint_cells(building_id, global_origin)
			cells.append(global_origin + BuildingCatalog.doorstep_of(building_id))
			var clear := true
			for cell in cells:
				if (
					chunk_manager.is_water_at_global(cell.x, cell.y)
					or chunk_manager.modification_at_global(cell.x, cell.y) != ""
				):
					clear = false
					break
			if clear:
				return {"chunk_coord": chunk_coord, "origin": origin}
	return {}


## A real placed building of `building_id`, returned as its own record.
func _a_standing(building_id: String, seed_value: int) -> Dictionary:
	var site := _a_dry_site_for(building_id)
	assert_false(site.is_empty(), "no dry site for a %s in Berlin's chunk" % building_id)
	if site.is_empty():
		return {}
	assert_true(
		chunk_manager.place_building(
			site["chunk_coord"], site["origin"], building_id, Vector2i(0, 1), seed_value
		),
		"precondition: %s placed" % building_id
	)
	_placed.append(site)
	var record: Dictionary = chunk_manager.building_record_at(site["chunk_coord"], site["origin"])
	assert_false(record.is_empty(), "the %s that was just placed has no record" % building_id)
	return record


func _a_standing_guild() -> Dictionary:
	return _a_standing(GUILD_ID, 4242)


# -- a guild ages, and starts empty -----------------------------------------

func test_a_guild_raised_just_now_holds_nobody():
	var record := _a_standing_guild()
	assert_eq(chunk_manager.masters_in_guild(record), [])


func test_a_guild_that_has_stood_a_season_holds_a_master():
	var record := _a_standing_guild()
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER)
	var aged: Dictionary = chunk_manager.building_record_at(
		record["chunk_coord"], record["origin_local"]
	)
	assert_eq(chunk_manager.masters_in_guild(aged).size(), 1)


func test_a_guild_fills_to_capacity_and_no_further():
	var record := _a_standing_guild()
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER * 100.0)
	var aged: Dictionary = chunk_manager.building_record_at(
		record["chunk_coord"], record["origin_local"]
	)
	assert_eq(chunk_manager.masters_in_guild(aged).size(), MageGuildRoster.CAPACITY)


func test_the_guilds_own_seed_is_what_draws_its_masters():
	var record := _a_standing_guild()
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER * 3.0)
	var aged: Dictionary = chunk_manager.building_record_at(
		record["chunk_coord"], record["origin_local"]
	)
	assert_eq(
		chunk_manager.masters_in_guild(aged),
		MageGuildRoster.master_seeds(int(aged["seed"]), float(aged[EarthChunkManager.GUILD_DAYS_OPEN_KEY]))
	)


func test_a_building_that_is_not_a_guild_never_holds_masters():
	var record := _a_standing("city_hall", 7)
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER * 100.0)
	assert_eq(chunk_manager.masters_in_guild(record), [])


## The settlement step runs once per SETTLEMENT, so a guild aged from
## inside it must age once per step, not once per village in range --
## otherwise three villages nearby fill every guild three times too fast.
func test_ageing_one_chunk_does_not_age_a_guild_in_another():
	var record := _a_standing_guild()
	var elsewhere: Vector2i = Vector2i(record["chunk_coord"]) + Vector2i(1, 0)
	chunk_manager.age_mage_guilds_in(elsewhere, MageGuildRoster.DAYS_PER_MASTER * 100.0)
	var after: Dictionary = chunk_manager.building_record_at(
		record["chunk_coord"], record["origin_local"]
	)
	assert_eq(chunk_manager.masters_in_guild(after), [])


func test_ageing_never_runs_a_guild_backwards():
	var record := _a_standing_guild()
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER)
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER)
	var aged: Dictionary = chunk_manager.building_record_at(
		record["chunk_coord"], record["origin_local"]
	)
	assert_eq(chunk_manager.masters_in_guild(aged).size(), 2)


func test_a_guilds_age_survives_a_chunk_round_trip():
	# A permanent fact about a place -- it must not reset because the
	# player walked away and came back.
	var record := _a_standing_guild()
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER * 2.0)
	var chunk_coord: Vector2i = record["chunk_coord"]
	var origin: Vector2i = record["origin_local"]

	# Somewhere far enough to unload Berlin's chunk (which persists it),
	# then back.
	chunk_manager.update(chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(4000, 4000))
	chunk_manager._load_chunk(chunk_coord)

	var reloaded: Dictionary = chunk_manager.building_record_at(chunk_coord, origin)
	assert_false(reloaded.is_empty(), "the guild did not come back")
	assert_eq(chunk_manager.masters_in_guild(reloaded).size(), 2)


# -- what can be learned here -----------------------------------------------

func test_a_full_guild_really_offers_lessons():
	var record := _a_standing_guild()
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER * 100.0)
	var aged: Dictionary = chunk_manager.building_record_at(
		record["chunk_coord"], record["origin_local"]
	)
	var seeds: Array = chunk_manager.masters_in_guild(aged)
	assert_gt(MageGuildRoster.teachable_here(book, seeds).size(), 0,
		"a guild of %d masters teaches nothing at all" % seeds.size())


func test_every_master_in_a_guild_is_a_real_named_mage():
	var record := _a_standing_guild()
	chunk_manager.age_mage_guilds(MageGuildRoster.DAYS_PER_MASTER * 100.0)
	var aged: Dictionary = chunk_manager.building_record_at(
		record["chunk_coord"], record["origin_local"]
	)
	for seed_value in chunk_manager.masters_in_guild(aged):
		assert_eq(MageMaster.identity_for(seed_value).occupation, MageMaster.OCCUPATION)
		assert_ne(MageMaster.display_name_for(seed_value), "")
