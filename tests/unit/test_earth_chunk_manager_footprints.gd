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


# -- underwater: a river/lake crossing grass/forest ground (rivers/lakes ---
# -- never change biome_at_global's own result -- see docs/concept/
# -- rivers.md) -- asked directly: "underwater footprints should be
# -- tinted". A pure override on top of whatever biome would otherwise
# -- give a real footprint -- it does NOT invent a footprint anywhere a
# -- dry biome wouldn't already have one (a true "ocean" biome tile still
# -- gets none at all, unaffected by this flag).

func test_underwater_overrides_grass_and_forest():
	assert_eq(EarthChunkManager.footstep_surface_for("grassland", false, true), "underwater")
	assert_eq(EarthChunkManager.footstep_surface_for("forest", false, true), "underwater")


func test_underwater_has_no_effect_on_biomes_with_no_footprint_at_all():
	for biome in ["desert", "mountain", "tundra", "rainforest", "ocean"]:
		assert_eq(
			EarthChunkManager.footstep_surface_for(biome, false, true), "",
			"%s should still get no footprint at all, underwater or not" % biome
		)


## Snow lying on top means the surface is frozen, not open water -- the
## same priority order the function already had (snow checked first),
## just confirmed to still hold now that a second override exists.
func test_snow_still_wins_over_underwater():
	assert_eq(EarthChunkManager.footstep_surface_for("grassland", true, true), "snow")
	assert_eq(EarthChunkManager.footstep_surface_for("forest", true, true), "snow")


## The default (no third argument) must keep matching dry land exactly --
## every pre-existing 2-arg call site across the whole project is
## unaffected by this feature.
func test_underwater_defaults_to_false_for_every_pre_existing_caller():
	assert_eq(EarthChunkManager.footstep_surface_for("grassland", false), "grass")
	assert_eq(EarthChunkManager.footstep_surface_for("forest", false), "forest")


# -- chunk lifecycle: same create-at-load/erase-at-unload shape as -------
# -- _leaf_litter_fields ---------------------------------------------------

func test_a_loaded_chunk_gets_a_real_footprint_field():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._footprint_fields.has(_berlin_chunk))
	assert_true(manager._footprint_fields[_berlin_chunk] is FootprintField)


func test_a_loaded_chunk_gets_one_multimeshinstance_per_surface():
	manager._load_chunk(_berlin_chunk)
	var mmis: Dictionary = manager._footprint_mmis[_berlin_chunk]
	for surface in ["snow", "grass", "forest", "underwater"]:
		assert_true(mmis.has(surface))
		assert_true(mmis[surface] is MultiMeshInstance2D)


func test_unloading_a_chunk_frees_its_footprint_state():
	manager._load_chunk(_berlin_chunk)
	manager._unload_chunk(_berlin_chunk)
	assert_false(manager._footprint_fields.has(_berlin_chunk))
	assert_false(manager._footprint_mmis.has(_berlin_chunk))


# -- record_footstep threads real river/lake presence through -------------
# -- (see footstep_surface_for's own "underwater" tests above) -- a
# -- source-contract test on the function body, the same shape and
# -- reasoning test_world_crush_wiring.gd/test_world_footstep_wiring.gd
# -- already use: a real river/lake at this specific test's fixed Berlin
# -- tile is not guaranteed, so this proves the WIRING rather than
# -- depending on world generation landing a river there.

func _record_footstep_body() -> String:
	var source := FileAccess.get_file_as_string("res://src/world/earth_chunk_manager.gd")
	var start := source.find("func record_footstep")
	assert_gt(start, -1, "the premise: this function must still exist and be named that")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_record_footstep_checks_for_a_real_river_or_lake():
	var body := _record_footstep_body()
	assert_true(body.contains("is_river_at_global("), "must check for a real river at the footstep tile")
	assert_true(body.contains("is_lake_at_global("), "must check for a real lake at the footstep tile too")


## Structural, not name-coupled: proves a THIRD argument was actually
## added to the real call (not just that the river/lake check exists
## somewhere unused in the function) without depending on whatever local
## variable name holds it. To end of statement (a newline), not the first
## ")" -- biome_at_global(tile.x, tile.y) has its own closing paren
## nested inside, which a naive first-")" search stops at before reaching
## the real one (the exact gotcha test_world_footstep_wiring.gd's own
## "players_own_position_and_facing" test already documents avoiding).
## Expects 3 commas, not 2: biome_at_global(tile.x, tile.y)'s own nested
## call contributes one, on top of the two top-level argument separators.
func test_record_footstep_passes_a_third_argument_to_footstep_surface_for():
	var body := _record_footstep_body()
	var call_index := body.find("footstep_surface_for(")
	assert_gt(call_index, -1, "must still call footstep_surface_for at all")
	var call_end := body.find("\n", call_index)
	var call_text := body.substr(call_index, call_end - call_index)
	assert_eq(
		call_text.count(","), 3,
		"must pass a third argument (the underwater check) alongside biome and snow_lying: %s" % call_text
	)


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


## Reported live: "we need footsteps" -- World needs to know a real step
## just landed to trigger a footstep SOUND at the exact same real per-step
## cadence the visual print already uses, without re-deriving FootstepGait's
## own accumulator a second time. record_footstep stayed `-> void` until
## now; every pre-existing caller/test above ignores its return value
## already (GDScript doesn't require using one), so this is a pure
## addition, not a behavior change.
##
## Returns the raw biome/snow/underwater facts, NOT an audio surface key --
## EarthChunkManager (world state) must not depend on FootstepSound (audio);
## that dependency runs the other way, same as NatureSoundscapePlayer
## already reads real world state rather than World reading audio state.
## The caller (World) feeds these into FootstepSound.surface_for itself.
## Deliberately independent of whether a VISUAL footprint was actually
## drawn (see the next test) -- FootstepSound's own surface coverage is
## wider than the footprint sprite's (see that file's own doc comment), so
## audio must not silently inherit the narrower visual gap.
func test_record_footstep_returns_the_real_facts_when_a_real_step_lands():
	manager._load_chunk(_berlin_chunk)
	var centre_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + Vector2i(
		EarthChunkManager.CHUNK_SIZE / 2, EarthChunkManager.CHUNK_SIZE / 2
	)
	var biome := manager.biome_at_global(centre_tile.x, centre_tile.y)
	var pixel := _pixel_for(centre_tile)
	manager.record_footstep(pixel, Vector2.UP)  # baseline
	var step := Vector2.UP * (FootstepGait.STRIDE_LENGTH_PX + 1.0)
	var result: Dictionary = manager.record_footstep(pixel + step, Vector2.UP)
	assert_eq(result.get("biome"), biome)
	assert_eq(result.get("snow_lying"), manager.snow_depth() > 0.0)
	assert_true(result.has("underwater"))
	# The baseline call never reaches step_if_due at all (it returns early
	# on the is_inf(...) first-ever-call check) -- this second call is the
	# actual FIRST real call into FootstepGait, which starts _next_is_left
	# true, so "left" is correct here, not an alternation off some prior
	# step that never really happened.
	assert_eq(result.get("side"), "left")


## A biome with no VISUAL footprint art (e.g. desert/tundra/mountain --
## see footstep_surface_for's own narrower _SURFACE_BY_FOOTSTEP_BIOME) must
## still report the real step facts, not an empty Dictionary -- a real
## step happened even though nothing got drawn, and FootstepSound's own
## wider coverage means it should still make SOME sound.
func test_record_footstep_returns_facts_even_when_the_biome_has_no_footprint_art():
	manager._load_chunk(_berlin_chunk)
	var centre_tile: Vector2i = _berlin_chunk * EarthChunkManager.CHUNK_SIZE + Vector2i(
		EarthChunkManager.CHUNK_SIZE / 2, EarthChunkManager.CHUNK_SIZE / 2
	)
	var biome := manager.biome_at_global(centre_tile.x, centre_tile.y)
	if ["grassland", "forest"].has(biome) and manager.snow_depth() == 0.0:
		pass_test("precondition unmet (this chunk's real biome/season this run DOES have footprint art) -- nothing to check")
		return
	var pixel := _pixel_for(centre_tile)
	manager.record_footstep(pixel, Vector2.UP)  # baseline
	var step := Vector2.UP * (FootstepGait.STRIDE_LENGTH_PX + 1.0)
	var result: Dictionary = manager.record_footstep(pixel + step, Vector2.UP)
	assert_eq(result.get("biome"), biome)


## The baseline call (no real step due yet) and a jump both leave nothing
## to react to -- an empty Dictionary, not a missing key crash, so a
## caller can safely do `result.get("biome", "")` unconditionally.
func test_record_footstep_returns_empty_when_no_step_is_due():
	manager._load_chunk(_berlin_chunk)
	var pixel := _pixel_for(_berlin_tile)
	var result: Dictionary = manager.record_footstep(pixel, Vector2.UP)
	assert_eq(result, {})


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
