extends GutTest

const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_COORD := Vector2i(2, 5)
const CHUNK_ORIGIN := Vector2i(64, 160)

var renderer: CreatureRenderer
var parent: Node2D


func before_each():
	renderer = CreatureRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func test_spawns_one_marker_per_rounded_unit_of_herbivore_population():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 3.4, 0.0
	)
	assert_eq(spawned.size(), 3)


func test_spawns_markers_for_both_herbivores_and_predators():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2.0, 1.0
	)
	assert_eq(spawned.size(), 3)
	assert_eq(parent.get_child_count(), 3)


func test_spawns_nothing_for_zero_population():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 0.0, 0.0
	)
	assert_eq(spawned.size(), 0)


func test_caps_marker_count_for_a_very_large_population():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 500.0, 0.0
	)
	assert_lte(spawned.size(), CreatureRenderer.MAX_MARKERS_PER_SPECIES)
	assert_gt(spawned.size(), 0)


func test_markers_are_positioned_within_the_chunk_bounds():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 4.0, 2.0
	)
	assert_gt(spawned.size(), 0)
	for creature in spawned:
		var tile_x := int(creature.position.x / TILE_SIZE)
		var tile_y := int(creature.position.y / TILE_SIZE)
		assert_between(tile_x, CHUNK_ORIGIN.x, CHUNK_ORIGIN.x + CHUNK_SIZE - 1)
		assert_between(tile_y, CHUNK_ORIGIN.y, CHUNK_ORIGIN.y + CHUNK_SIZE - 1)


func test_positions_are_deterministic_for_the_same_inputs():
	var first := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 3.0, 1.0
	)
	var first_positions: Array[Vector2] = []
	for creature in first:
		first_positions.append(creature.position)

	var other_parent := Node2D.new()
	var second := renderer.spawn_creatures(
		other_parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 3.0, 1.0
	)
	var second_positions: Array[Vector2] = []
	for creature in second:
		second_positions.append(creature.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


func test_markers_carry_role_appropriate_info():
	# Species within a role can now vary (herbivore/boar, predator/lynx --
	# see the species-pool tests below), so this checks the role invariant
	# (is_predator) rather than an exact species string.
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1.0, 1.0
	)
	assert_eq(spawned.size(), 2)
	var herbivore_role_marker := spawned[0]
	var predator_role_marker := spawned[1]
	assert_false(herbivore_role_marker.info.is_predator)
	assert_true(predator_role_marker.info.is_predator)


func test_herbivore_role_population_sometimes_promotes_a_boar():
	var species_seen := {}
	for coord_x in range(30):
		var spawned := renderer.spawn_creatures(
			parent, Vector2i(coord_x, 0), CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1.0, 0.0
		)
		for creature in spawned:
			species_seen[creature.info.species] = true
			creature.free()
	assert_true(species_seen.has("boar"), "expected at least one boar across 30 sampled chunks")


func test_predator_role_population_sometimes_promotes_a_lynx():
	var species_seen := {}
	for coord_x in range(30):
		var spawned := renderer.spawn_creatures(
			parent, Vector2i(coord_x, 0), CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 0.0, 1.0
		)
		for creature in spawned:
			species_seen[creature.info.species] = true
			creature.free()
	assert_true(species_seen.has("lynx"), "expected at least one lynx across 30 sampled chunks")


func test_spawn_single_supports_boar_and_lynx_species():
	var boar := renderer.spawn_single(parent, "boar", Vector2(10, 10))
	var lynx := renderer.spawn_single(parent, "lynx", Vector2(20, 20))
	assert_eq(boar.info.species, "boar")
	assert_eq(lynx.info.species, "lynx")


func test_herbivore_and_predator_markers_use_different_textures():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1.0, 1.0
	)
	assert_eq(spawned.size(), 2)
	var herbivore_sprite := spawned[0] as Sprite2D
	var predator_sprite := spawned[1] as Sprite2D
	assert_ne(herbivore_sprite.texture, predator_sprite.texture)


func test_individual_creatures_get_visually_distinct_procedurally_generated_sprites():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2.0, 0.0
	)
	assert_eq(spawned.size(), 2)
	var first_image := (spawned[0] as Sprite2D).texture.get_image()
	var second_image := (spawned[1] as Sprite2D).texture.get_image()
	var any_pixel_differs := false
	for y in first_image.get_height():
		for x in first_image.get_width():
			if first_image.get_pixel(x, y) != second_image.get_pixel(x, y):
				any_pixel_differs = true
	assert_true(any_pixel_differs, "different individuals should look visually distinct")


func test_spawn_single_spawns_one_marker_of_the_given_species_at_the_given_position():
	var marker := renderer.spawn_single(parent, "predator", Vector2(100, 200))
	assert_eq(parent.get_child_count(), 1)
	assert_eq(marker.position, Vector2(100, 200))
	assert_eq(marker.info.species, "predator")


func test_spawn_single_gives_the_marker_a_real_procedural_texture():
	var marker := renderer.spawn_single(parent, "herbivore", Vector2.ZERO)
	assert_not_null((marker as Sprite2D).texture)
