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


# -- per-biome species pools ---------------------------------------------------


func _species_seen_across_chunks(
	herbivore_population: float, predator_population: float, biome_name: String, chunk_count: int = 30
) -> Dictionary:
	var species_seen := {}
	for coord_x in range(chunk_count):
		var spawned := renderer.spawn_creatures(
			parent, Vector2i(coord_x, 0), CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE,
			herbivore_population, predator_population, null, biome_name
		)
		for creature in spawned:
			species_seen[creature.info.species] = true
			creature.free()
	return species_seen


func test_spawn_creatures_still_compiles_and_works_without_a_biome_argument():
	# The default empty biome_name must keep every pre-existing call site
	# (which never passes a biome) compiling and behaving exactly as before.
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2.0, 1.0
	)
	assert_eq(spawned.size(), 3)


func test_empty_biome_name_falls_back_to_the_generic_species_pools():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "")
	for species in herbivore_species:
		assert_true(species in ["herbivore", "boar"], "unexpected herbivore-role species: %s" % species)
	for species in predator_species:
		assert_true(species in ["predator", "lynx"], "unexpected predator-role species: %s" % species)


func test_unmapped_biome_name_falls_back_to_the_generic_species_pools():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "ocean")
	for species in herbivore_species:
		assert_true(species in ["herbivore", "boar"], "unexpected herbivore-role species: %s" % species)


func test_grassland_biome_matches_the_original_generic_pool_identity():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "grassland")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "grassland")
	assert_true(herbivore_species.has("herbivore"))
	assert_true(herbivore_species.has("boar"))
	for species in herbivore_species:
		assert_true(species in ["herbivore", "boar"], "unexpected herbivore-role species: %s" % species)
	assert_true(predator_species.has("predator"))
	assert_true(predator_species.has("lynx"))
	for species in predator_species:
		assert_true(species in ["predator", "lynx"], "unexpected predator-role species: %s" % species)


func test_forest_biome_is_boar_and_lynx_dominant():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "forest")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "forest")
	assert_true(herbivore_species.has("boar"), "forest should promote boars")
	for species in herbivore_species:
		assert_true(species in ["herbivore", "boar"], "unexpected herbivore-role species: %s" % species)
	assert_true(predator_species.has("lynx"), "forest should promote lynx")
	for species in predator_species:
		assert_true(species in ["predator", "lynx"], "unexpected predator-role species: %s" % species)


func test_desert_biome_promotes_camels_and_jackals():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "desert")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "desert")
	assert_true(herbivore_species.has("camel"), "desert should promote camels")
	for species in herbivore_species:
		assert_true(species in ["herbivore", "camel"], "unexpected herbivore-role species: %s" % species)
	assert_true(predator_species.has("jackal"), "desert should promote jackals")
	for species in predator_species:
		assert_true(species in ["predator", "jackal"], "unexpected predator-role species: %s" % species)


func test_tundra_biome_promotes_reindeer_and_arctic_foxes():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "tundra")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "tundra")
	assert_true(herbivore_species.has("reindeer"), "tundra should promote reindeer")
	for species in herbivore_species:
		assert_true(species in ["herbivore", "reindeer"], "unexpected herbivore-role species: %s" % species)
	assert_true(predator_species.has("arctic_fox"), "tundra should promote arctic foxes")
	for species in predator_species:
		assert_true(species in ["predator", "arctic_fox"], "unexpected predator-role species: %s" % species)


func test_rainforest_biome_promotes_tapirs_and_jaguars():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "rainforest")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "rainforest")
	assert_true(herbivore_species.has("tapir"), "rainforest should promote tapirs")
	for species in herbivore_species:
		assert_true(species in ["herbivore", "tapir"], "unexpected herbivore-role species: %s" % species)
	assert_true(predator_species.has("jaguar"), "rainforest should promote jaguars")
	for species in predator_species:
		assert_true(species in ["predator", "jaguar"], "unexpected predator-role species: %s" % species)


func test_mountain_biome_promotes_goats_and_mountain_lions():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "mountain")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "mountain")
	assert_true(herbivore_species.has("goat"), "mountain should promote goats")
	for species in herbivore_species:
		assert_true(species in ["herbivore", "goat"], "unexpected herbivore-role species: %s" % species)
	assert_true(predator_species.has("mountain_lion"), "mountain should promote mountain lions")
	for species in predator_species:
		assert_true(species in ["predator", "mountain_lion"], "unexpected predator-role species: %s" % species)
