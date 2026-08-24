extends GutTest

const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_COORD := Vector2i(2, 5)
const CHUNK_ORIGIN := Vector2i(64, 160)

var renderer: CreatureRenderer
var parent: Node2D


## Creatures cast contact shadows (see drop_shadow.gd), grounding them on the
## terrain instead of floating over it.
func test_spawned_creature_has_a_drop_shadow():
	var marker := renderer.spawn_single(parent, "boar", Vector2(10, 10))
	var shadow := marker.get_node_or_null("Shadow")
	assert_not_null(shadow, "creature should have a Shadow child")
	assert_true(shadow is Sprite2D and shadow.show_behind_parent)


## The shadow is a silhouette, not a fixed oval: the creature's own current
## texture, flipped upside down (see DropShadow.make_silhouette_shadow).
func test_creature_shadow_is_a_flipped_copy_of_its_own_sprite():
	var marker := renderer.spawn_single(parent, "boar", Vector2(10, 10))
	var shadow: Sprite2D = marker.get_node("Shadow")
	assert_true(shadow.flip_v, "a shadow is the creature's own shape flipped upside down")
	assert_eq(shadow.texture, marker.texture, "the shadow must be shaped like the actual creature casting it")


## Anchored where the species' own legs actually meet the ground (see
## AnimalAnatomy's body_y/body_height/leg_length), not a fixed half-height
## guess -- the generic guess put the shadow visibly below a boar's hooves
## (back when boar was still procedurally drawn -- see the illustrated-
## species version of this test below), reading as a floating creature
## (reported: "the shadow is a few pixel below sprite so it looks like it's
## floating"). Lynx here specifically because it has no illustrated art (see
## IllustratedAnimalSprite) and so still exercises this procedural formula.
func test_creature_shadow_is_anchored_at_the_species_own_feet_not_a_fixed_guess():
	const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
	const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
	var marker := renderer.spawn_single(parent, "lynx", Vector2(10, 10))
	var shadow: Sprite2D = marker.get_node("Shadow")
	var profile := AnimalAnatomy.profile_for("lynx")
	var h := float(ProceduralAnimalSprite.HEIGHT)
	var ground_y: float = h * (float(profile.body_y) + float(profile.body_height) * 0.5 + float(profile.leg_length))
	var expected_offset := ground_y - h * 0.5
	assert_almost_eq(shadow.position.y, expected_offset, 0.01)


## A species with real illustrated art (see IllustratedAnimalSprite) shares
## one fixed canvas/baseline convention instead of AnimalAnatomy's per-
## species canvas-fraction fields -- boar is illustrated now, so its shadow
## anchor must come from IllustratedAnimalSprite.ground_offset_y() instead
## of the procedural formula above.
func test_illustrated_species_shadow_uses_the_illustrated_ground_offset():
	const IllustratedAnimalSprite = preload("res://src/rendering/illustrated_animal_sprite.gd")
	var marker := renderer.spawn_single(parent, "boar", Vector2(10, 10))
	var shadow: Sprite2D = marker.get_node("Shadow")
	assert_almost_eq(shadow.position.y, IllustratedAnimalSprite.new().ground_offset_y(), 0.01)


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


## See docs/concept/disease.md's "Region pressure": a spawned marker carries
## its own region's RegionDifficulty tier forward (rather than the world
## re-deriving it later), reusing the SAME distance-from-spawn signal that
## already gates its species pool above, not a second one.
func test_spawned_markers_carry_the_regions_difficulty_tier_for_disease_pressure():
	var spawned := renderer.spawn_creatures(
		parent, CHUNK_COORD, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2.0, 0.0, null, "",
		RegionDifficulty.Tier.HARD
	)
	assert_eq(spawned[0].region_tier, RegionDifficulty.Tier.HARD)


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
		assert_true(
			species in ["herbivore", "boar", "mouse", "horse", "deer", "nonvenomous_snake", "sheep"],
			"unexpected herbivore-role species: %s" % species
		)
	assert_true(predator_species.has("predator"))
	assert_true(predator_species.has("lynx"))
	for species in predator_species:
		assert_true(species in ["predator", "lynx", "lion"], "unexpected predator-role species: %s" % species)


## Wolves are forest's own named apex predator (see
## docs/concept/ecosystem_dynamics.md's Species roster section) and sheep is
## their (and deer's) forest prey -- both additive to the existing boar/lynx
## dominance this test's name pins, not a replacement of it.
func test_forest_biome_is_boar_and_lynx_dominant():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "forest")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "forest")
	assert_true(herbivore_species.has("boar"), "forest should promote boars")
	for species in herbivore_species:
		assert_true(
			species in ["herbivore", "boar", "mouse", "deer", "sheep", "nonvenomous_snake"],
			"unexpected herbivore-role species: %s" % species
		)
	assert_true(predator_species.has("lynx"), "forest should promote lynx")
	for species in predator_species:
		assert_true(
			species in ["predator", "lynx", "wolf", "bear"], "unexpected predator-role species: %s" % species
		)


## Wolves eat sheep and deer and live in forests (see
## docs/concept/ecosystem_dynamics.md's Species roster section) -- both real
## prey species must actually be promotable alongside them in the SAME
## biome for that predation to be anything other than a name. Wolves are
## forest-exclusive, unlike the ordinary ungated roster additions (deer,
## nonvenomous_snake) that join multiple biomes.
func test_forest_promotes_wolves_alongside_their_sheep_and_deer_prey():
	# Sample counts raised above the default 30 (see mice/horse/deer/
	# nonvenomous_snake's own tests just below) -- sheep and deer are both
	# single, non-dominant entries in forest's 9-entry herbivore pool, so a
	# low sample count under-covers their real, lower hit rate per chunk.
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "forest", 200)
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "forest", 200)
	assert_true(predator_species.has("wolf"), "forest should promote wolves")
	assert_true(herbivore_species.has("sheep"), "forest should promote sheep, wolf prey")
	assert_true(herbivore_species.has("deer"), "forest should promote deer, wolf prey")
	for biome_name in ["grassland", "desert", "tundra", "rainforest", "mountain"]:
		var other_predators := _species_seen_across_chunks(0.0, 1.0, biome_name, 200)
		assert_false(other_predators.has("wolf"), "%s should not promote wolves" % biome_name)


func test_desert_biome_promotes_camels_and_jackals():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "desert")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "desert")
	assert_true(herbivore_species.has("camel"), "desert should promote camels")
	for species in herbivore_species:
		assert_true(
			species in ["herbivore", "camel", "mouse", "horse", "nonvenomous_snake"],
			"unexpected herbivore-role species: %s" % species
		)
	assert_true(predator_species.has("jackal"), "desert should promote jackals")
	for species in predator_species:
		assert_true(
			species in ["predator", "jackal", "lion", "venomous_snake"],
			"unexpected predator-role species: %s" % species
		)


func test_tundra_biome_promotes_reindeer_and_arctic_foxes():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "tundra")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "tundra")
	assert_true(herbivore_species.has("reindeer"), "tundra should promote reindeer")
	for species in herbivore_species:
		assert_true(
			species in ["herbivore", "reindeer", "mouse", "deer"], "unexpected herbivore-role species: %s" % species
		)
	assert_true(predator_species.has("arctic_fox"), "tundra should promote arctic foxes")
	for species in predator_species:
		assert_true(
			species in ["predator", "arctic_fox", "bear"], "unexpected predator-role species: %s" % species
		)


func test_rainforest_biome_promotes_tapirs_and_jaguars():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "rainforest")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "rainforest")
	assert_true(herbivore_species.has("tapir"), "rainforest should promote tapirs")
	for species in herbivore_species:
		assert_true(
			species in ["herbivore", "tapir", "mouse", "nonvenomous_snake"],
			"unexpected herbivore-role species: %s" % species
		)
	assert_true(predator_species.has("jaguar"), "rainforest should promote jaguars")
	for species in predator_species:
		assert_true(
			species in ["predator", "jaguar", "venomous_snake"], "unexpected predator-role species: %s" % species
		)


func test_mountain_biome_promotes_goats_and_mountain_lions():
	var herbivore_species := _species_seen_across_chunks(1.0, 0.0, "mountain")
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "mountain")
	assert_true(herbivore_species.has("goat"), "mountain should promote goats")
	for species in herbivore_species:
		assert_true(
			species in ["herbivore", "goat", "mouse", "sheep"], "unexpected herbivore-role species: %s" % species
		)
	assert_true(predator_species.has("mountain_lion"), "mountain should promote mountain lions")
	for species in predator_species:
		assert_true(species in ["predator", "mountain_lion"], "unexpected predator-role species: %s" % species)


# -- mice and horses (see docs/concept/ecosystem_dynamics.md's Species roster) --
#
# Real mice are near-ubiquitous generalists -- every non-ocean biome's pool
# gets them, unlike the biome-exclusive specialists above. Horses are a real
# grassland/dry-steppe grazer -- grassland and desert only, not the other
# four. Sample counts raised above the default 30: each pool now has more
# entries, so any one species' hit rate per chunk is lower.

func test_mouse_appears_in_every_non_ocean_biomes_herbivore_pool():
	for biome_name in ["grassland", "forest", "desert", "tundra", "rainforest", "mountain"]:
		var herbivore_species := _species_seen_across_chunks(1.0, 0.0, biome_name, 200)
		assert_true(herbivore_species.has("mouse"), "%s should be able to promote mice" % biome_name)


func test_horse_appears_only_in_grassland_and_desert_herbivore_pools():
	for biome_name in ["grassland", "desert"]:
		var herbivore_species := _species_seen_across_chunks(1.0, 0.0, biome_name, 200)
		assert_true(herbivore_species.has("horse"), "%s should be able to promote horses" % biome_name)
	for biome_name in ["forest", "tundra", "rainforest", "mountain"]:
		var herbivore_species := _species_seen_across_chunks(1.0, 0.0, biome_name, 200)
		assert_false(herbivore_species.has("horse"), "%s should not promote horses" % biome_name)


# -- bear, deer, lion, and both snakes (see docs/concept/ecosystem_dynamics.md's
# Region difficulty section) -- difficulty_tier defaults to HARD (2, the most
# permissive) so every pre-existing call site above keeps compiling and
# behaving exactly as before.

const RegionDifficulty = preload("res://src/world/region_difficulty.gd")


func test_deer_appears_in_grassland_forest_and_tundra_herbivore_pools():
	for biome_name in ["grassland", "forest", "tundra"]:
		var herbivore_species := _species_seen_across_chunks(1.0, 0.0, biome_name, 200)
		assert_true(herbivore_species.has("deer"), "%s should be able to promote deer" % biome_name)


func test_nonvenomous_snake_appears_in_warm_and_temperate_herbivore_pools():
	for biome_name in ["grassland", "forest", "desert", "rainforest"]:
		var herbivore_species := _species_seen_across_chunks(1.0, 0.0, biome_name, 200)
		assert_true(
			herbivore_species.has("nonvenomous_snake"), "%s should be able to promote nonvenomous_snake" % biome_name
		)


## Deer/nonvenomous_snake are ordinary (ungated) roster additions -- they
## show up regardless of difficulty tier, unlike bear/lion/venomous_snake.
func test_deer_appears_even_at_the_easiest_difficulty_tier():
	var species_seen := {}
	for coord_x in range(80):
		var spawned := renderer.spawn_creatures(
			parent, Vector2i(coord_x, 0), CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1.0, 0.0, null, "grassland",
			RegionDifficulty.Tier.EASY
		)
		for creature in spawned:
			species_seen[creature.info.species] = true
			creature.free()
	assert_true(species_seen.has("deer"), "deer should appear at EASY difficulty")


func test_bear_lion_and_venomous_snake_never_appear_below_hard_difficulty():
	var dangerous := ["bear", "lion", "venomous_snake"]
	for tier in [RegionDifficulty.Tier.EASY, RegionDifficulty.Tier.MEDIUM]:
		for biome_name in ["grassland", "forest", "desert", "tundra", "rainforest"]:
			var herbivore_species := {}
			var predator_species := {}
			for coord_x in range(40):
				var spawned := renderer.spawn_creatures(
					parent, Vector2i(coord_x, 0), CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1.0, 1.0, null,
					biome_name, tier
				)
				for creature in spawned:
					if creature.info.is_predator:
						predator_species[creature.info.species] = true
					else:
						herbivore_species[creature.info.species] = true
					creature.free()
			for species in dangerous:
				assert_false(
					predator_species.has(species) or herbivore_species.has(species),
					"%s should not appear in %s at tier %s" % [species, biome_name, tier]
				)


func test_bear_appears_in_forest_at_hard_difficulty():
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "forest", 80)
	# _species_seen_across_chunks doesn't pass a tier -- default is HARD (2).
	assert_true(predator_species.has("bear"), "forest should promote bears at HARD difficulty")


func test_lion_appears_in_grassland_at_hard_difficulty():
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "grassland", 80)
	assert_true(predator_species.has("lion"), "grassland should promote lions at HARD difficulty")


func test_venomous_snake_appears_in_desert_at_hard_difficulty():
	var predator_species := _species_seen_across_chunks(0.0, 1.0, "desert", 80)
	assert_true(predator_species.has("venomous_snake"), "desert should promote venomous snakes at HARD difficulty")
