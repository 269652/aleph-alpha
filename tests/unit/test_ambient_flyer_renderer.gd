extends GutTest

## Chunk-based spawn/despawn of ambient wildlife (butterflies, songbirds) --
## same shape as FishRenderer/CreatureRenderer, but decorative/capped only,
## not population-simulated (see docs/concept/ecosystem_dynamics.md's
## Species roster).

const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")
const Chunk = preload("res://src/world/chunk.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_ORIGIN := Vector2i(64, 128)

var renderer: AmbientFlyerRenderer
var parent: Node2D


func before_each():
	renderer = AmbientFlyerRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_chunk(biome_name: String, size: int = CHUNK_SIZE) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.biome = PackedStringArray()
	for i in size * size:
		chunk.biome.append(biome_name)
	return chunk


func test_spawns_butterflies_and_birds_on_a_large_grassland_chunk():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	assert_gt(spawned.size(), 0)
	assert_eq(parent.get_child_count(), spawned.size())


## Spawn count is a guaranteed range (MIN..MAX), not an independent per-cell
## probability roll that could plausibly land on zero for some real-world
## coordinates -- every qualifying chunk gets at least the minimum, every
## time, the same reliability fix already applied to fish (see
## FishRenderer's target_count).
func test_every_qualifying_chunk_spawns_at_least_the_minimum_of_each():
	for coord_x in range(20):
		var chunk := _make_chunk("grassland")
		var origin := Vector2i(coord_x * CHUNK_SIZE, coord_x * 7)
		var spawned := renderer.spawn_ambient_flyers(parent, chunk, origin, TILE_SIZE, "grassland")
		var butterflies := 0
		var birds := 0
		for flyer in spawned:
			if AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL.has(flyer.species):
				butterflies += 1
			else:
				birds += 1
		assert_gte(
			butterflies, AmbientFlyerRenderer.MIN_BUTTERFLIES_PER_CHUNK,
			"chunk at x=%d should have at least the minimum butterflies" % coord_x
		)
		assert_gte(
			birds, AmbientFlyerRenderer.MIN_BIRDS_PER_CHUNK,
			"chunk at x=%d should have at least the minimum birds" % coord_x
		)


func test_spawns_nothing_on_desert():
	var chunk := _make_chunk("desert")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "desert")
	assert_eq(spawned.size(), 0)


func test_spawns_nothing_on_tundra():
	var chunk := _make_chunk("tundra")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "tundra")
	assert_eq(spawned.size(), 0)


func test_spawns_nothing_on_ocean():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "ocean")
	assert_eq(spawned.size(), 0)


func test_never_exceeds_the_combined_per_chunk_cap():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	assert_lte(
		spawned.size(),
		AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK + AmbientFlyerRenderer.MAX_BIRDS_PER_CHUNK
	)


func test_positions_are_deterministic_for_the_same_inputs():
	var chunk := _make_chunk("grassland")
	var first := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	var first_positions: Array[Vector2] = []
	for flyer in first:
		first_positions.append(flyer.position)

	var other_parent := Node2D.new()
	var second := renderer.spawn_ambient_flyers(other_parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	var second_positions: Array[Vector2] = []
	for flyer in second:
		second_positions.append(flyer.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


## Butterflies render at half size (a real-world scale difference from
## songbirds, and easier to read against tall grass/trees at this pixel
## density than the full 14x10 source art).
func test_butterflies_render_at_half_scale_but_birds_render_at_full_scale():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	assert_gt(spawned.size(), 0)
	for flyer in spawned:
		if AmbientFlyerRenderer.BUTTERFLY_SPECIES_POOL.has(flyer.species):
			assert_eq(flyer.scale, Vector2.ONE * AmbientFlyerRenderer.BUTTERFLY_SCALE, flyer.species)
		else:
			assert_eq(flyer.scale, Vector2.ONE, flyer.species)


func test_spawned_flyers_are_ambient_flyer_markers_with_a_texture():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_ambient_flyers(parent, chunk, CHUNK_ORIGIN, TILE_SIZE, "grassland")
	assert_gt(spawned.size(), 0)
	for flyer in spawned:
		assert_true(flyer is AmbientFlyerMarker)
		assert_not_null(flyer.texture)


# -- sized against a fish ---------------------------------------------------
#
# Flyer sizes are expressed as multiples of a fish, the nearest visible
# reference in the world: "butterflies should be half the size of a fish and
# a sparrow roughly the size of a fish... other birds may be bigger".

const FishRenderer = preload("res://src/rendering/fish_renderer.gd")


func test_a_sparrow_is_about_the_size_of_a_fish():
	assert_almost_eq(AmbientFlyerRenderer.FLYER_WORLD_SCALE["sparrow"], 1.0, 0.05)


func test_butterflies_are_about_half_a_fish():
	for species in ["monarch", "swallowtail", "blue_morpho"]:
		assert_between(AmbientFlyerRenderer.FLYER_WORLD_SCALE[species], 0.45, 0.65, species)


func test_the_larger_birds_outsize_a_sparrow():
	var sparrow: float = AmbientFlyerRenderer.FLYER_WORLD_SCALE["sparrow"]
	assert_gt(AmbientFlyerRenderer.FLYER_WORLD_SCALE["robin"], sparrow)
	assert_gt(AmbientFlyerRenderer.FLYER_WORLD_SCALE["kingfisher"], sparrow)


func test_every_butterfly_is_smaller_than_every_bird():
	for butterfly in ["monarch", "swallowtail", "blue_morpho"]:
		for bird in ["sparrow", "robin", "kingfisher"]:
			assert_lt(
				AmbientFlyerRenderer.FLYER_WORLD_SCALE[butterfly],
				AmbientFlyerRenderer.FLYER_WORLD_SCALE[bird],
				"%s should be smaller than %s" % [butterfly, bird]
			)


## "A robin should only be slightly bigger than a fish" -- the birds here
## are all SMALL birds, so the whole range stays narrow.
func test_a_robin_is_only_slightly_bigger_than_a_fish():
	assert_between(AmbientFlyerRenderer.FLYER_WORLD_SCALE["robin"], 1.0, 1.15)
