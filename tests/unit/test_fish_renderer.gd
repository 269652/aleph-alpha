extends GutTest

## FishRenderer: chunk-based spawn/despawn of visible, catchable fish on
## ocean cells -- same "one node per qualifying tile, deterministic per
## global coordinate, capped so a huge water body doesn't spawn hundreds of
## nodes" shape as TreeRenderer/CreatureRenderer.

const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const FishMarker = preload("res://src/rendering/fish_marker.gd")
const Chunk = preload("res://src/world/chunk.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_ORIGIN := Vector2i(64, 128)

var renderer: FishRenderer
var parent: Node2D


func before_each():
	renderer = FishRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_chunk(biome_name: String, size: int = CHUNK_SIZE) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(size * size)
	chunk.biome = PackedStringArray()
	for i in size * size:
		chunk.biome.append(biome_name)
	return chunk


func test_spawns_nothing_on_a_chunk_with_no_ocean():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), 0)


# -- spawn_fish_at: one real fish outside the chunk system entirely --------
#
# For the character preview diorama's own small standalone pond (see
# character_preview_diorama.gd) -- not ocean-tile spawning, no Chunk
# involved at all.

func test_spawn_fish_at_places_a_real_fish_at_the_given_position():
	var fish := renderer.spawn_fish_at(parent, "koi", Vector2(40, 60), 7)
	assert_not_null(fish.texture)
	assert_eq(fish.position, Vector2(40, 60))
	assert_eq(fish.get_parent(), parent)


func test_spawn_fish_at_processes_a_frame_without_a_world_without_crashing():
	add_child(parent)
	var fish := renderer.spawn_fish_at(parent, "goldfish", Vector2.ZERO, 1)
	# FishMarker.setup's own doc comment says a null world means the fish
	# swims unconfined rather than checking water-tile boundaries -- a real
	# crash trying to duck-type against that null world would only show up
	# once _process actually runs, not at construction time.
	fish._process(0.1)
	assert_true(true)
	remove_child(parent)


func test_spawns_some_fish_on_a_large_ocean_chunk():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	assert_eq(parent.get_child_count(), spawned.size())


func test_never_exceeds_the_per_chunk_fish_cap():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_lte(spawned.size(), FishRenderer.MAX_FISH_PER_CHUNK)


func test_fish_are_positioned_within_the_chunk_bounds():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(2, 3), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for fish in spawned:
		var tile_x := int(fish.position.x / TILE_SIZE)
		var tile_y := int(fish.position.y / TILE_SIZE)
		assert_between(tile_x, CHUNK_ORIGIN.x, CHUNK_ORIGIN.x + CHUNK_SIZE - 1)
		assert_between(tile_y, CHUNK_ORIGIN.y, CHUNK_ORIGIN.y + CHUNK_SIZE - 1)


func test_positions_are_deterministic_for_the_same_inputs():
	var chunk := _make_chunk("ocean")
	var first := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	var first_positions: Array[Vector2] = []
	for fish in first:
		first_positions.append(fish.position)

	var other_parent := Node2D.new()
	var second := renderer.spawn_fish(other_parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	var second_positions: Array[Vector2] = []
	for fish in second:
		second_positions.append(fish.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


func test_spawned_fish_are_fish_markers_with_a_texture():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for fish in spawned:
		assert_true(fish is FishMarker)
		assert_not_null(fish.texture)


## The stranding fix's spawn half: fish must only spawn on INTERIOR water
## cells (all four cardinal neighbors also water), never on a cell touching
## the shore -- a shore-adjacent spawn starts life half-beached and, with the
## clearance rule (see FishMarker.CLEARANCE_PX), barely able to move.
func test_fish_never_spawn_on_water_cells_touching_land():
	var chunk := _make_chunk("ocean")
	# Carve a land column through the middle -- its water neighbors become
	# shore cells no fish may spawn on.
	var land_x := CHUNK_SIZE / 2
	for y in CHUNK_SIZE:
		chunk.biome[y * CHUNK_SIZE + land_x] = "grassland"

	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	for fish in spawned:
		var tile_x := int(fish.position.x / TILE_SIZE) - CHUNK_ORIGIN.x
		assert_ne(tile_x, land_x - 1, "fish spawned on the shore cell west of the land column")
		assert_ne(tile_x, land_x + 1, "fish spawned on the shore cell east of the land column")
		assert_ne(tile_x, land_x, "fish spawned on land itself")


func test_fish_never_spawn_on_the_chunks_edge_cells():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for fish in spawned:
		var tile := Vector2i(int(fish.position.x / TILE_SIZE), int(fish.position.y / TILE_SIZE)) - CHUNK_ORIGIN
		assert_gt(tile.x, 0)
		assert_gt(tile.y, 0)
		assert_lt(tile.x, CHUNK_SIZE - 1)
		assert_lt(tile.y, CHUNK_SIZE - 1)


## Colorful and multiple varieties, in practice: across a large enough ocean
## chunk, more than one species should show up.
func test_a_large_ocean_chunk_spawns_a_mix_of_species():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(4, 4), chunk, CHUNK_ORIGIN, TILE_SIZE)
	var species_seen := {}
	for fish in spawned:
		species_seen[fish.species] = true
	assert_gt(species_seen.size(), 1, "expected more than one species across a large ocean chunk")


# -- population-driven spawn count (see docs/concept/fishing.md#individual-fidelity-promotion) --
#
# target_count defaults to -1 (every test above), which keeps the legacy
# per-cell SPAWN_CHANCE roll unchanged -- every pre-existing call site (and
# test) keeps compiling and behaving exactly as before, same convention as
# CreatureRenderer's biome_name parameter.

func test_target_count_spawns_exactly_that_many_when_water_area_allows():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 4)
	assert_eq(spawned.size(), 4)


func test_target_count_of_zero_spawns_nothing():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 0)
	assert_eq(spawned.size(), 0)


func test_target_count_is_capped_by_max_fish_per_chunk():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 999)
	assert_eq(spawned.size(), FishRenderer.MAX_FISH_PER_CHUNK)


func test_target_count_selection_is_deterministic():
	var chunk := _make_chunk("ocean")
	var first := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5)
	var first_positions: Array[Vector2] = []
	for fish in first:
		first_positions.append(fish.position)

	var other_parent := Node2D.new()
	var second := renderer.spawn_fish(other_parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5)
	var second_positions: Array[Vector2] = []
	for fish in second:
		second_positions.append(fish.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


func test_target_count_still_respects_interior_water_only():
	var chunk := _make_chunk("ocean")
	var land_x := CHUNK_SIZE / 2
	for y in CHUNK_SIZE:
		chunk.biome[y * CHUNK_SIZE + land_x] = "grassland"

	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 999)
	for fish in spawned:
		var tile_x := int(fish.position.x / TILE_SIZE) - CHUNK_ORIGIN.x
		assert_ne(tile_x, land_x, "fish spawned on land itself")


# -- texture reuse: fish share cached art instead of one unique image each --
#
# See ProceduralFishSprite's own cache tests for the generator-level detail;
# this proves it end-to-end through FishRenderer's actual spawn path -- with
# MAX_FISH_PER_CHUNK capping population per chunk but many water chunks
# potentially loaded at once, an uncached generate_texture meant every
# visible fish was both paying its own per-instance image-generation cost
# and permanently unbatchable with every other fish of the same species.

func test_two_fish_of_the_same_species_and_seed_share_one_texture():
	var a := renderer.spawn_fish_at(parent, "koi", Vector2(10, 10), 5)
	var b := renderer.spawn_fish_at(parent, "koi", Vector2(90, 40), 5)
	assert_same(a.texture, b.texture, "same species+seed fish should share one cached texture")


# -- fish DO live in rivers, and that is why the ripple fix matters --------
#
# Reported plainly, against a claim of mine that said otherwise: "the rivers
# are full of fish". The claim came from reading the spawn gate alone --
# is_interior_water requires the ocean BIOME -- and concluding that no
# curated river course could satisfy it. Measuring instead of reading is
# what corrected it: sweeping the apron band around every curated course,
# 64 cells qualify for fish and 53 of them are also painted by the river
# overlay.
#
# The reason is that the two decisions ask different questions. Fish spawn
# where the coarse world elevation dips below sea level, which happens along
# real reaches -- broad water, lakes a course runs through, river mouths.
# The river overlay paints purely by DISTANCE to a curated course, with no
# biome check at all (_paint_river_flow_overlay). So those reaches are ocean
# biome AND under the opaque river surface at once: fish swimming in water
# whose ripples that surface had no term to draw.
#
# Pinned here at one measured coordinate rather than by re-sweeping 10k
# cells, which is far too slow for the suite -- one real example is enough
# to keep the case from being "fixed" away as impossible again.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const WaterAreaSurvey = preload("res://src/world/water_area_survey.gd")

## On the Rhine, found by sweeping every curated course's apron band.
const FISH_UNDER_THE_RIVER_SURFACE := Vector2i(20542, 4242)

const _NEIGHBOR_STEPS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


func test_a_river_reach_can_be_both_fish_water_and_under_the_flow_overlay():
	var generator := EarthChunkGenerator.new()
	var tile := FISH_UNDER_THE_RIVER_SURFACE

	# The fish side: WaterAreaSurvey.is_interior_water's own rule, asked of
	# the generator directly rather than through a Chunk (the same question,
	# without building one).
	assert_eq(
		generator.biome_at_global(tile.x, tile.y), "ocean",
		"precondition: this reach is ocean biome, which is what spawns fish"
	)
	for step in _NEIGHBOR_STEPS:
		assert_eq(
			generator.biome_at_global(tile.x + step.x, tile.y + step.y), "ocean",
			"interior water needs every neighbour to be water too"
		)

	# The overlay side: _paint_river_flow_overlay's own gate -- distance to
	# the nearest curated course, and deliberately no biome check.
	var apron := RiverCatalog.RIVER_HALF_WIDTH_TILES + RiverCatalog.RIVER_BANK_APRON_TILES
	var nearest = generator.river_catalog().nearest_river_at(
		tile.x, tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	assert_lte(
		nearest.distance_tiles, apron,
		"this reach must be inside the painted apron, or it is not river surface"
	)
