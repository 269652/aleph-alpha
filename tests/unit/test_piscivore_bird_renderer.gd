extends GutTest

## Chunk-based spawn/despawn of fish-eating birds (kingfishers) -- gated by
## water presence (not a land biome pool, unlike AmbientFlyerRenderer),
## since piscivores hunt over water specifically. See
## docs/concept/ecosystem_dynamics.md's "fish-eating birds".

const PiscivoreBirdRenderer = preload("res://src/rendering/piscivore_bird_renderer.gd")
const PiscivoreBirdMarker = preload("res://src/rendering/piscivore_bird_marker.gd")
const Chunk = preload("res://src/world/chunk.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_ORIGIN := Vector2i(64, 128)

var renderer: PiscivoreBirdRenderer
var parent: Node2D


func before_each():
	renderer = PiscivoreBirdRenderer.new()
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


func test_spawns_nothing_on_a_chunk_with_no_water():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	assert_eq(spawned.size(), 0)


func test_never_exceeds_max_per_chunk_on_a_large_ocean_chunk():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 500.0
	)
	assert_lte(spawned.size(), PiscivoreBirdRenderer.MAX_PER_CHUNK)


func test_positions_are_deterministic_for_the_same_inputs():
	var chunk := _make_chunk("ocean")
	var first := renderer.spawn_piscivore_birds(
		parent, Vector2i(2, 2), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)

	var other_parent := Node2D.new()
	var second := renderer.spawn_piscivore_birds(
		other_parent, Vector2i(2, 2), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)

	var first_positions: Array[Vector2] = []
	for bird in first:
		first_positions.append(bird.position)
	var second_positions: Array[Vector2] = []
	for bird in second:
		second_positions.append(bird.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


func test_spawned_bird_is_a_piscivore_bird_marker_with_a_texture():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	assert_eq(spawned.size(), 1)
	assert_true(spawned[0] is PiscivoreBirdMarker)
	assert_not_null(spawned[0].texture)


# -- promoted from the real aggregate kingfisher population, not a die roll --
#
# A kingfisher used to appear on a flat SPAWN_CHANCE roll regardless of
# whether the water it hunts had any fish at all. Presence is now driven by
# EcosystemSimulation.kingfisher_population -- itself derived from the
# EXISTING fish population (see KingfisherPopulationModel) -- mirroring
# CreatureRenderer's aggregate-population-to-marker-count promotion.

func test_spawns_nothing_without_a_kingfisher_population():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 0.0
	)
	assert_eq(spawned.size(), 0)


func test_spawns_a_kingfisher_once_population_reaches_one():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 0.6
	)
	assert_eq(spawned.size(), 1)


# -- the kingfisher flaps like every other bird ------------------------------
#
# The marker used to be built with its resting-pose texture and nothing else
# -- unlike AmbientFlyerRenderer._build_marker, which also wires flap_frames/
# perched_frame for sparrow and robin (see test_ambient_flyer_renderer.gd's
# own "same species+seed should reuse the cached flap-frame sequence"). A
# kingfisher never got either, so it flew, hovered and carried its catch off
# on one frozen frame (reported: "fix the kingfisher's wings").
# ProceduralBirdSprite already generates both for "kingfisher" (see
# test_procedural_bird_sprite.gd's test_flap_frames_are_deterministic) --
# this was a wiring gap here, not a missing painter.

func test_spawned_kingfisher_has_wing_beat_frames():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	assert_eq(spawned.size(), 1)
	assert_false(
		spawned[0].flap_frames.is_empty(), "a kingfisher should flap like every other flyer"
	)


func test_spawned_kingfisher_has_a_perched_frame():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	assert_not_null(spawned[0].perched_frame, "a perched kingfisher should hold a folded-wing pose")


func test_two_kingfishers_of_the_same_seed_share_flap_frames():
	var chunk := _make_chunk("ocean")
	var first := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	var other_parent := Node2D.new()
	var second := renderer.spawn_piscivore_birds(
		other_parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	# Read before freeing `other_parent` -- the marker is its child, so
	# freeing it frees the marker too (the array itself, once read into a
	# local, is its own refcounted value and outlives that).
	var second_flap_frames: Array = second[0].flap_frames
	other_parent.free()
	assert_same(
		first[0].flap_frames, second_flap_frames,
		"same chunk (same seed) should reuse the cached flap-frame sequence"
	)
