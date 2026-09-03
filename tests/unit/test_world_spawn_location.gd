extends GutTest

## Where a fresh single-player game (and a fresh multiplayer host) starts.
##
## The Loire at Nantes (47.2031N, 1.5469W): an EMERGENT river -- a channel
## of the baked drainage network (docs/concept/hydrology.md), not a curated
## RiverCatalog course. Chosen from tools/probe_hydrology.gd's output on
## 2026-09-03: the strongest baked channel in western France more than 400
## tiles from every curated river, at the asset cell whose centre the
## channel's centreline passes through. Previously the Freiburg Gaskugel
## on the curated Dreisam (48.007669N, 7.805657E, 2026-08-29) and before
## that Berlin (52.52N, 13.405E). Nothing else reads these two numbers
## except World._compute_dry_land_spawn_tile(); the test files that
## hardcode the literal 52.52/13.405 (test_earth_chunk_manager.gd,
## test_world_ecology_batch_wild_crops.gd) use Berlin as a known-good
## REFERENCE chunk independent of the live spawn and are left alone.

const World = preload("res://scenes/world.gd")
const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const ClimateModel = preload("res://src/world/climate_model.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")


func test_spawn_is_the_loire_at_nantes():
	assert_almost_eq(World.SPAWN_LATITUDE, 47.2031, 0.0001)
	assert_almost_eq(World.SPAWN_LONGITUDE, -1.5469, 0.0001)


## The spawn is on an EMERGENT river: a baked hydrology channel, which the
## generator reports as a river with an empty name (no curated course
## anywhere near it), fed by the shipped bake in assets/data/hydrology.
func test_spawn_is_on_an_emergent_river_not_a_curated_one():
	var generator := EarthChunkGenerator.new()
	assert_true(generator.has_hydrology(), "the shipped bake must load")
	var geo := GeoCoordinates.new()
	var spawn_tile := geo.tile_for_coordinate(
		World.SPAWN_LATITUDE, World.SPAWN_LONGITUDE,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_true(generator.is_river_at_global(spawn_tile.x, spawn_tile.y))
	var nearest := generator.nearest_river_at(spawn_tile.x, spawn_tile.y)
	assert_eq(nearest.name, "", "no curated river reaches Nantes")
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


## Real integration check (docs/concept/rivers.md, hydrology.md): the spawn
## point sits ON the Loire's baked channel -- the whole reason this location
## was picked. A dry-land search that didn't know about rivers would happily
## accept the literal spawn tile even though it's the middle of the river;
## _find_dry_land_spawn must search past it to real dry land instead.
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

	# Sanity: the literal spawn tile really is on the Loire's baked channel
	# (the whole premise of this test) -- if this ever stops being true the
	# test itself needs re-examining, not just the fix it's checking.
	assert_true(
		manager.is_river_at_global(spawn_tile.x, spawn_tile.y),
		"expected the raw spawn tile to be on the Loire's emergent channel"
	)

	var result := world._find_dry_land_spawn(spawn_tile)
	assert_false(manager.is_river_at_global(result.x, result.y), "must not spawn inside the river")
	assert_ne(manager.biome_at_global(result.x, result.y), "ocean")

	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
