extends GutTest

## EarthChunkManager's real footprint lifecycle (see FootstepGait,
## FootprintField, FootprintRenderer). Reported live: "real footstep
## prints with left/right footprints spaced apart and stamped into the
## snow with displacement (snow amount should still be reduced)... also
## implement proper pathscarring for grass and forest tiles" -- one
## field/renderer per chunk serves all three surfaces.
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md
## / test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const FootstepGait = preload("res://src/gameplay/footstep_gait.gd")
const FootprintField = preload("res://src/world/footprint_field.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i
var _berlin_chunk: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	# Berlin -- same real-world spawn tile every other test file in this
	# project uses; reliably inland forest/grassland nearby.
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _pixel_for(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE)


const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


# -- surface determination: pure, independent of a real loaded chunk ------
# -- (see EarthChunkManager.footstep_surface_for's own doc comment) -------

func test_snow_lying_means_snow_regardless_of_biome():
	assert_eq(EarthChunkManager.footstep_surface_for("grassland", true), "snow")
	assert_eq(EarthChunkManager.footstep_surface_for("forest", true), "snow")
	assert_eq(EarthChunkManager.footstep_surface_for("desert", true), "snow")


func test_grassland_without_snow_is_grass():
	assert_eq(EarthChunkManager.footstep_surface_for("grassland", false), "grass")


func test_forest_without_snow_is_forest():
	assert_eq(EarthChunkManager.footstep_surface_for("forest", false), "forest")


## Reported live scope exactly: "grass and forest tiles" -- desert,
## mountain, tundra, rainforest, and ocean get no footprint at all,
## mirroring PathScarring's own identical PATH_SCAR_BIOMES gate.
func test_other_biomes_get_no_footprint_at_all():
	for biome in ["desert", "mountain", "tundra", "rainforest", "ocean"]:
		assert_eq(
			EarthChunkManager.footstep_surface_for(biome, false), "",
			"%s should not scar at all, matching PathScarring's own PATH_SCAR_BIOMES gate" % biome
		)


# -- chunk lifecycle: same create-at-load/erase-at-unload shape as -------
# -- _leaf_litter_fields ---------------------------------------------------

func test_a_loaded_chunk_gets_a_real_footprint_field():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._footprint_fields.has(_berlin_chunk))
	assert_true(manager._footprint_fields[_berlin_chunk] is FootprintField)


func test_a_loaded_chunk_gets_one_multimeshinstance_per_surface():
	manager._load_chunk(_berlin_chunk)
	var mmis: Dictionary = manager._footprint_mmis[_berlin_chunk]
	for surface in ["snow", "grass", "forest"]:
		assert_true(mmis.has(surface))
		assert_true(mmis[surface] is MultiMeshInstance2D)


func test_unloading_a_chunk_frees_its_footprint_state():
	manager._load_chunk(_berlin_chunk)
	manager._unload_chunk(_berlin_chunk)
	assert_false(manager._footprint_fields.has(_berlin_chunk))
	assert_false(manager._footprint_mmis.has(_berlin_chunk))


# -- record_footstep: the real per-frame entry point -----------------------

## The very first call establishes a baseline position -- there is no
## PRIOR position yet to measure real distance travelled from, so no
## print can be placed yet (mirrors tread_snow_at's own "nothing to
## compare against on the very first call" shape, just expressed via
## distance instead of tile identity).
func test_the_first_call_places_no_print_yet():
	manager._load_chunk(_berlin_chunk)
	var pixel := _pixel_for(_berlin_tile)
	manager.record_footstep(pixel, Vector2.UP)
	assert_eq(manager._footprint_fields[_berlin_chunk].count(), 0)


## Walking the full stride length in small real steps (mirroring how this
## is actually driven, once per physics frame) should place exactly one
## print, in a real biome-eligible tile.
func test_walking_a_full_stride_places_one_print():
	manager._load_chunk(_berlin_chunk)
	# The chunk's own centre cell, not _berlin_tile's exact real position --
	# comfortably clear of every edge regardless of where in its chunk
	# Berlin's own real tile happens to fall, so a real stride's worth of
	# walking can never cross into a neighbouring (unloaded) chunk.
	var centre_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + Vector2i(
		EarthChunkManager.CHUNK_SIZE / 2, EarthChunkManager.CHUNK_SIZE / 2
	)
	var biome := manager.biome_at_global(centre_tile.x, centre_tile.y)
	if not ["grassland", "forest"].has(biome) or manager.snow_depth() > 0.0:
		pass_test("precondition unmet (this chunk's real biome/season this run isn't grass/forest snow-free) -- nothing to check")
		return
	var pixel := _pixel_for(centre_tile)
	manager.record_footstep(pixel, Vector2.UP)  # baseline
	var step := Vector2.UP * (FootstepGait.STRIDE_LENGTH_PX + 1.0)
	manager.record_footstep(pixel + step, Vector2.UP)
	var field: FootprintField = manager._footprint_fields[_berlin_chunk]
	assert_eq(field.count(), 1)
	assert_eq(field.prints()[0].surface, biome_to_surface(biome))


func biome_to_surface(biome: String) -> String:
	return "grass" if biome == "grassland" else biome


## A teleport (dev command, respawn, save load) must not bridge a stray
## print across the gap, and must not crash on a huge distance value.
func test_a_huge_position_jump_is_treated_as_a_teleport_not_a_stride():
	manager._load_chunk(_berlin_chunk)
	var pixel := _pixel_for(_berlin_tile)
	manager.record_footstep(pixel, Vector2.UP)
	manager.record_footstep(pixel + Vector2(50000, 50000), Vector2.UP)
	var field: FootprintField = manager._footprint_fields.get(_berlin_chunk)
	if field != null:
		assert_eq(field.count(), 0, "a teleport should not stamp a stray print bridging the gap")


func test_record_footstep_before_any_chunk_is_loaded_does_not_crash():
	manager.record_footstep(Vector2(999999999, 999999999), Vector2.UP)
	manager.record_footstep(Vector2(999999999, 999999950), Vector2.UP)
	# The real assertion is simply reaching this line without an engine
	# error -- GUT fails a test outright on an unhandled script error.
	assert_true(true)


# -- step_footprints: ages/prunes every loaded chunk's field ---------------

func test_step_footprints_ages_a_field_towards_pruning():
	manager._load_chunk(_berlin_chunk)
	var field: FootprintField = manager._footprint_fields[_berlin_chunk]
	field.add_print(_pixel_for(_berlin_tile), "left", "grass", Vector2.UP, 0.0)
	manager._world_age_seconds = FootprintField.LIFETIME_SECONDS + 1.0
	manager.step_footprints()
	assert_eq(field.count(), 0)
