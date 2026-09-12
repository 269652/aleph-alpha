extends GutTest

## Where a fresh single-player game (and a fresh multiplayer host) starts
## when no random curated-river bank qualifies (see SpawnRiverPicker,
## docs/concept/rivers.md "Spawn: a random curated river") -- the FALLBACK
## point, not the common case.
##
## The Freiburg Gaskugel on the curated Dreisam (48.007669N, 7.805657E),
## RiverCatalog's own "this game's own spawn point" via-point. Reinstated
## 2026-09-12 ("also set the future spawn point to dreisam") as the
## fallback: a curated river with a real, named course beats an emergent
## hydrology channel with no name at all as the point a session falls
## back to when nothing else works out, and it's this project's own
## original, oldest-standing spawn. History: Berlin (52.52N, 13.405E,
## before 2026-08-29) -> Dreisam (2026-08-29) -> the Loire at Nantes, an
## emergent channel with no curated course near it (47.2031N, 1.5469W,
## 2026-09-03, chosen from tools/probe_hydrology.gd's own output as the
## strongest baked channel in western France) -> back to Dreisam
## (2026-09-12). Nothing else reads these two numbers except World.
## _compute_dry_land_spawn_tile(); the test files that hardcode the
## literal 52.52/13.405 (test_earth_chunk_manager.gd,
## test_world_ecology_batch_wild_crops.gd) use Berlin as a known-good
## REFERENCE chunk independent of the live spawn and are left alone.

const World = preload("res://scenes/world.gd")
const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const ClimateModel = preload("res://src/world/climate_model.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")


func test_spawn_fallback_is_the_dreisam_at_freiburg():
	assert_almost_eq(World.SPAWN_LATITUDE, 48.007669, 0.0001)
	assert_almost_eq(World.SPAWN_LONGITUDE, 7.805657, 0.0001)


## The fallback spawn is on a CURATED river -- the Dreisam, by name, the
## exact via-point RiverCatalog's own doc comment already calls out as
## "this game's own spawn point" -- not an emergent hydrology channel with
## no name.
func test_spawn_fallback_is_on_the_curated_dreisam_by_name():
	var generator := EarthChunkGenerator.new()
	assert_true(generator.has_hydrology(), "the shipped bake must load")
	var geo := GeoCoordinates.new()
	var spawn_tile := geo.tile_for_coordinate(
		World.SPAWN_LATITUDE, World.SPAWN_LONGITUDE,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_true(generator.is_river_at_global(spawn_tile.x, spawn_tile.y))
	var nearest := generator.nearest_river_at(spawn_tile.x, spawn_tile.y)
	assert_eq(nearest.name, "Dreisam", "the fallback sits on the curated Dreisam, by name")
	assert_gt(generator.river_depth_meters_at_global(spawn_tile.x, spawn_tile.y), 0.0)


## A factual check against the real bundled elevation data (assets/data/
## world_elevation.png), not an eyeballed assumption -- the spawn must land
## somewhere `_find_dry_land_spawn` would actually accept (dry ground) and
## that BiomeClassifier would not read as a mountain peak.
func test_spawn_coordinates_are_dry_land_not_ocean_or_mountain():
	var elevation := EarthElevationSource.new().elevation_at(World.SPAWN_LATITUDE, World.SPAWN_LONGITUDE)
	assert_gt(elevation, EarthChunkGenerator.EARTH_SEA_LEVEL, "spawn must not be underwater")
	assert_lt(elevation, EarthChunkGenerator.EARTH_MOUNTAIN_LEVEL, "spawn must not be a mountain peak")


## The earlier Berlin spawn was calibrated (see EarthwormPatch.MILD_WARMTH's
## own doc comment and BERLIN_CLIMATE in test_earthworm_patch.gd) against a
## real measured climate temperature of ~0.413 -- low enough that the
## worm-surfacing mechanic almost shipped permanently gated off. The new
## spawn must not silently reintroduce that regression: its real climate
## must be at least as warm, so every threshold tuned against Berlin's
## number stays satisfied at the new spawn too.
##
## The exact figure Berlin itself computes to is 0.41228199135992 -- the
## doc comments elsewhere round it to "0.413", but that rounded value is
## fractionally ABOVE Berlin's own real number, so pinning against the
## rounded form would fail even for Berlin itself. Use the precise value.
func test_spawn_climate_is_at_least_as_warm_as_the_old_berlin_spawn():
	const OLD_BERLIN_CLIMATE := 0.41228199135992
	var elevation := EarthElevationSource.new().elevation_at(World.SPAWN_LATITUDE, World.SPAWN_LONGITUDE)
	var latitude_0to1 := absf(World.SPAWN_LATITUDE) / 90.0
	var height_above_sea_level := maxf(0.0, elevation - EarthChunkGenerator.EARTH_SEA_LEVEL)
	var temperature: float = ClimateModel.new().temperature_at(latitude_0to1, height_above_sea_level)
	assert_gt(temperature, OLD_BERLIN_CLIMATE)


## Real integration check (docs/concept/rivers.md, hydrology.md): the
## fallback spawn point sits ON the Dreisam's curated course -- the whole
## reason this location was picked. A dry-land search that didn't know
## about rivers would happily accept the literal spawn tile even though
## it's the middle of the river; _find_dry_land_spawn must search past it
## to real dry land instead.
##
## Not add_child()'d, same convention test_world_streaming_budget.gd/
## test_world_inventory_wiring.gd already use for a bare World.new() that
## only needs one plain (non-@onready) field poked directly. Needs one real
## EarthChunkManager.update() call (the cached biome_at_global/
## is_river_at_global read _find_dry_land_spawn relies on requires it), so
## kept in this small file rather than test_earth_chunk_manager.gd, which
## already takes ten-plus minutes on its own.
func test_find_dry_land_spawn_does_not_land_in_the_river_at_the_spawn_point():
	var world := World.new()
	var tile_map_layer := TileMapLayer.new()
	var entities_parent := Node2D.new()
	var creatures_parent := Node2D.new()
	var manager := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	world._chunk_manager = manager

	var geo := GeoCoordinates.new()
	var spawn_tile := geo.tile_for_coordinate(
		World.SPAWN_LATITUDE, World.SPAWN_LONGITUDE,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	manager.update(spawn_tile)

	# Sanity: the literal spawn tile really is on the Dreisam's curated
	# course (the whole premise of this test) -- if this ever stops being
	# true the test itself needs re-examining, not just the fix it's
	# checking.
	assert_true(
		manager.is_river_at_global(spawn_tile.x, spawn_tile.y),
		"expected the raw spawn tile to be on the Dreisam's curated course"
	)

	var result := world._find_dry_land_spawn(spawn_tile)
	assert_false(manager.is_river_at_global(result.x, result.y), "must not spawn inside the river")
	assert_ne(manager.biome_at_global(result.x, result.y), "ocean")

	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## A new game now starts on a random curated river (docs/concept/rivers.md
## "Spawn: a random curated river", src/world/spawn_river_picker.gd); the
## Dreisam pinned above is the FALLBACK when no river bank qualifies. A
## dev launch (--solo) fixes the seed so a measurement lands in the same
## place every run; --spawn-seed=N overrides either way.
func test_a_real_game_randomizes_its_spawn_and_a_dev_launch_fixes_it():
	assert_eq(World.spawn_seed_for(PackedStringArray([])), -1, "a real new game: randomize")
	assert_eq(World.spawn_seed_for(PackedStringArray(["--solo"])), 0, "a dev launch: the same river every time")
	assert_eq(World.spawn_seed_for(PackedStringArray(["--solo", "--spawn-seed=7"])), 7)
	assert_eq(World.spawn_seed_for(PackedStringArray(["--spawn-seed=3"])), 3, "an explicit seed wins for a real game too")


func test_the_climate_floor_is_the_old_berlin_spawn():
	assert_almost_eq(World.SPAWN_CLIMATE_FLOOR, 0.41228199135992, 0.000001)


func test_a_spawn_candidate_must_be_a_warm_river_tile_between_sea_and_mountain():
	var world := World.new()
	var tile_map_layer := TileMapLayer.new()
	var entities_parent := Node2D.new()
	var creatures_parent := Node2D.new()
	var manager := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	world._chunk_manager = manager
	var geo := GeoCoordinates.new()
	var width := EarthChunkGenerator.WORLD_WIDTH_TILES
	var height := EarthChunkGenerator.WORLD_HEIGHT_TILES
	# The smoothed Rhine course does not pass exactly through the city
	# centre (corners are cut, RiverCatalog._chaikin_smoothed), so take the
	# course point nearest Cologne -- a river tile by construction.
	var cologne_centre := geo.tile_for_coordinate(50.93639, 6.95278, width, height)
	var cologne := Vector2i.ZERO
	var nearest := INF
	for point in RiverCatalog.tile_polylines(width, height)["Rhine"]:
		var distance: float = Vector2(cologne_centre).distance_to(point)
		if distance < nearest:
			nearest = distance
			cologne = Vector2i(point)
	assert_true(manager.generator.is_river_at_global(cologne.x, cologne.y), "precondition: a point of the curated Rhine course is a river tile")
	assert_true(world._spawn_candidate_acceptable(cologne), "a warm river bank on land qualifies")
	var atlantic := geo.tile_for_coordinate(46.0, -8.0, width, height)
	assert_false(world._spawn_candidate_acceptable(atlantic), "open sea does not")
	var not_a_river := cologne + Vector2i(40, 40)
	if not manager.generator.is_river_at_global(not_a_river.x, not_a_river.y):
		assert_false(world._spawn_candidate_acceptable(not_a_river), "dry land off any river does not")
	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func test_the_spawn_is_picked_from_the_curated_rivers_and_falls_back_to_the_dreisam():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _compute_dry_land_spawn_tile(")
	assert_gt(start, -1, "the premise")
	var body := source.substr(start, source.find("\nfunc ", start + 1) - start)
	assert_true(body.contains("SpawnRiverPicker.pick("), "a random curated river")
	assert_true(body.contains("RiverCatalog.tile_polylines("), "drawn from the catalogue's real courses")
	assert_true(body.contains("_spawn_candidate_acceptable"), "filtered by the bank check")
	assert_true(body.contains("SPAWN_LATITUDE") and body.contains("SPAWN_LONGITUDE"), "the Dreisam remains the fallback")
	assert_true(body.contains("_session_spawn_picked"), "picked once per session, so every peer of a server shares it")
