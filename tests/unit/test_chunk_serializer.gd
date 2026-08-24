extends GutTest

const Chunk = preload("res://src/world/chunk.gd")
const ChunkSerializer = preload("res://src/world/chunk_serializer.gd")

const TEST_PATH := "user://test_chunk.bin"

var serializer: ChunkSerializer


func before_each():
	serializer = ChunkSerializer.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _make_chunk() -> Chunk:
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.1, 0.2, 0.3, 0.4])
	chunk.biome = PackedStringArray(["ocean", "grassland", "desert", "forest"])
	chunk.modifications = {Vector2i(1, 1): "built_wall"}
	return chunk


func test_save_then_load_round_trips_dimensions_and_terrain_data():
	var chunk := _make_chunk()
	serializer.save_chunk(chunk, TEST_PATH)
	var loaded: Chunk = serializer.load_chunk(TEST_PATH)
	assert_eq(loaded.width, 2)
	assert_eq(loaded.height, 2)
	assert_eq(loaded.elevation, chunk.elevation)
	assert_eq(loaded.biome, chunk.biome)


func test_save_then_load_round_trips_player_modifications():
	var chunk := _make_chunk()
	serializer.save_chunk(chunk, TEST_PATH)
	var loaded: Chunk = serializer.load_chunk(TEST_PATH)
	assert_eq(loaded.modifications, {Vector2i(1, 1): "built_wall"})


func test_loading_a_missing_chunk_file_returns_null():
	assert_eq(serializer.load_chunk("user://does_not_exist.bin"), null)


func test_save_then_load_modifications_round_trips():
	var modifications := {Vector2i(3, 4): "wall"}
	serializer.save_modifications(modifications, TEST_PATH)
	assert_eq(serializer.load_modifications(TEST_PATH), modifications)


func test_loading_missing_modifications_returns_an_empty_dictionary():
	assert_eq(serializer.load_modifications("user://does_not_exist.bin"), {})


func test_save_then_load_planted_trees_round_trips():
	var planted_trees := [
		{"position": Vector2(120.0, 340.0), "planted_at": 12.5},
		{"position": Vector2(140.0, 340.0), "planted_at": 40.0},
	]
	serializer.save_planted_trees(planted_trees, TEST_PATH)
	assert_eq(serializer.load_planted_trees(TEST_PATH), planted_trees)


func test_loading_missing_planted_trees_returns_an_empty_array():
	assert_eq(serializer.load_planted_trees("user://does_not_exist.bin"), [])


## See docs/concept/fishing.md#persistence-a-gap-shared-with-land-ecology-worth-closing-here-first.
## One file per chunk (like modifications/planted_trees) holding a single
## scalar -- there's only ever one aggregate fish population per chunk, no
## natural sub-key the way a chunk's many modifications/trees have.

func test_save_then_load_fish_population_round_trips():
	serializer.save_fish_population(4.5, TEST_PATH)
	assert_almost_eq(serializer.load_fish_population(TEST_PATH), 4.5, 0.0001)


func test_save_then_load_fish_population_round_trips_a_fished_out_zero():
	# 0.0 is a legitimate persisted state (a fished-out chunk), distinct from
	# "never persisted" -- callers must check file existence themselves
	# (see EarthChunkManager) rather than treating this 0.0 default as
	# "nothing to load".
	serializer.save_fish_population(0.0, TEST_PATH)
	assert_almost_eq(serializer.load_fish_population(TEST_PATH), 0.0, 0.0001)


func test_loading_missing_fish_population_returns_zero():
	assert_eq(serializer.load_fish_population("user://does_not_exist.bin"), 0.0)


# -- land ecology survives a restart -----------------------------------------
#
# Fish already persisted; herbivores, predators and vegetation lived only in
# EarthChunkManager's in-memory record, so quitting reset every region to a
# freshly-seeded population at full capacity. A herd the player hunted down,
# or watched grow, was back to default next launch.

func test_land_ecology_round_trips_through_a_file():
	var path := "user://test_ecology.bin"
	var state := {
		"herbivores": 3.25, "predators": 0.5, "vegetation": 0.75,
		"saved_at_unix": 1700000000.0,
	}
	serializer.save_ecology(state, path)
	var loaded := serializer.load_ecology(path)
	assert_almost_eq(float(loaded["herbivores"]), 3.25, 0.001)
	assert_almost_eq(float(loaded["predators"]), 0.5, 0.001)
	assert_almost_eq(float(loaded["vegetation"]), 0.75, 0.001)
	DirAccess.remove_absolute(path)


## Wall-clock, and to full precision: the whole point is knowing how long the
## player was away, and a float32 second-count near the current unix epoch
## loses minutes to rounding.
func test_the_saved_timestamp_keeps_its_precision():
	var path := "user://test_ecology_time.bin"
	var now := 1767225600.0  # a plausible present-day unix time
	serializer.save_ecology({"saved_at_unix": now}, path)
	assert_almost_eq(float(serializer.load_ecology(path)["saved_at_unix"]), now, 1.0)
	DirAccess.remove_absolute(path)


## "Never persisted" and "persisted as empty" are different facts: a region
## really can be hunted down to nothing, and re-seeding it would quietly undo
## the player's effect on the world.
func test_a_region_that_was_never_saved_is_distinguishable_from_an_empty_one():
	assert_true(serializer.load_ecology("user://nothing_here_at_all.bin").is_empty())
	var path := "user://test_ecology_empty.bin"
	serializer.save_ecology({"herbivores": 0.0, "predators": 0.0, "vegetation": 0.0}, path)
	var loaded := serializer.load_ecology(path)
	assert_false(loaded.is_empty(), "a hunted-out region is a real, saved state")
	assert_almost_eq(float(loaded["herbivores"]), 0.0, 0.001)
	DirAccess.remove_absolute(path)


# -- land health survives a real restart too (docs/concept/world.md "Land
# health: overharvesting leaves a lasting mark, not just a slower respawn")
#
# Land health is exactly the kind of lasting change the concept doc calls
# for -- it must NOT silently reset on reload the way the vegetation/fruit
# patch-sims that predate this feature are documented as not persisting.

func test_land_health_round_trips_through_the_ecology_file():
	var path := "user://test_ecology_land_health.bin"
	var state := {
		"herbivores": 1.0, "predators": 0.0, "vegetation": 0.5,
		"saved_at_unix": 1700000000.0, "land_health": 0.35,
	}
	serializer.save_ecology(state, path)
	var loaded := serializer.load_ecology(path)
	assert_almost_eq(float(loaded["land_health"]), 0.35, 0.001)
	DirAccess.remove_absolute(path)


## Backward compatibility: an ecology file written BEFORE land health existed
## (the original 4-field format -- herbivores/predators/vegetation/
## saved_at_unix, nothing more) must still load cleanly, defaulting land
## health to 1.0 (pristine) rather than reading past end-of-file. An old save
## genuinely has no history of degradation to report, which IS the correct
## fact -- not a crash, and not a fabricated degraded value.
func test_an_old_ecology_file_without_land_health_defaults_it_to_pristine():
	var path := "user://test_ecology_old_format.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_float(2.0)  # herbivores
	file.store_float(1.0)  # predators
	file.store_float(0.6)  # vegetation
	file.store_double(1700000000.0)  # saved_at_unix
	file.close()

	var loaded := serializer.load_ecology(path)

	assert_almost_eq(float(loaded["herbivores"]), 2.0, 0.001)
	assert_almost_eq(float(loaded["land_health"]), 1.0, 0.001)
	DirAccess.remove_absolute(path)
