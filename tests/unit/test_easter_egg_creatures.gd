extends GutTest

## EasterEggCreatures (docs/concept/easter_eggs.md's Starter collection):
## Squallmaw (Bermuda Triangle), Coilnecca (Loch Ness), and Champ (Lake
## Champlain). Unlike EasterEggSightings (Mothman/Jersey Devil/Roswell/Area
## 51 -- flavor-text-only glimpses with no persistent object), these three
## are real, spawnable species (see CreatureInfo/AnimalAnatomy's squallmaw/
## coilnecca/champ entries) -- a hit here names which species scenes/
## world.gd should actually spawn into the world (via
## CreatureRenderer.spawn_single), not a line of text.
##
## Same reverse-geo-lookup + radius + per-check-roll shape as
## EasterEggSightings, reusing GeoCoordinates identically -- see that
## module's own doc comment for the shared design rationale (chance_per_check
## is per-CHECK, not per-second; roll is caller-supplied so this stays
## deterministic/testable).

const EasterEggCreatures = preload("res://src/gameplay/easter_egg_creatures.gd")
const EasterEggSightings = preload("res://src/gameplay/easter_egg_sightings.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")

var creatures: EasterEggCreatures
var world_width: int
var world_height: int


func before_each():
	creatures = EasterEggCreatures.new()
	world_width = EarthChunkGenerator.WORLD_WIDTH_TILES
	world_height = EarthChunkGenerator.WORLD_HEIGHT_TILES


func test_this_stages_three_creature_ids_are_registered():
	var ids := creatures.sighting_ids()
	for expected in ["squallmaw", "coilnecca", "champ"]:
		assert_true(ids.has(expected), "missing creature id: %s" % expected)


## Every registered id must be an actual spawnable species -- the whole
## point of this module is naming something CreatureRenderer.spawn_single
## can spawn, unlike EasterEggSightings' text-only ids.
func test_every_registered_id_is_a_real_spawnable_species():
	for id in creatures.sighting_ids():
		assert_true(AnimalAnatomy.SPECIES.has(id), "%s should have a real AnimalAnatomy profile" % id)


func _tile_at(id: String) -> Vector2i:
	return creatures.tile_for(id, world_width, world_height)


func test_is_in_range_true_at_the_creatures_own_tile():
	for id in creatures.sighting_ids():
		var tile := _tile_at(id)
		assert_true(
			creatures.is_in_range(id, tile.x, tile.y, world_width, world_height),
			"%s should be in range of its own coordinate" % id
		)


func test_is_in_range_false_far_from_every_creature():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	for id in creatures.sighting_ids():
		assert_false(
			creatures.is_in_range(id, far_tile.x, far_tile.y, world_width, world_height),
			"%s should not be in range of the far tile" % id
		)


func test_check_one_empty_when_out_of_range_even_with_a_guaranteed_roll():
	var far_tile := Vector2i(world_width / 2, world_height / 2)
	var species := creatures.check_one("squallmaw", far_tile.x, far_tile.y, world_width, world_height, 0.0)
	assert_eq(species, "")


func test_check_one_empty_when_roll_does_not_clear_the_chance_threshold():
	var tile := _tile_at("squallmaw")
	# A roll of exactly 1.0 clears no threshold in [0, 1).
	var species := creatures.check_one("squallmaw", tile.x, tile.y, world_width, world_height, 1.0)
	assert_eq(species, "")


## The "message" this module returns IS the species id itself -- what the
## caller passes straight to CreatureRenderer.spawn_single.
func test_check_one_returns_the_species_id_when_in_range_and_roll_clears_threshold():
	for id in creatures.sighting_ids():
		var tile := _tile_at(id)
		var species := creatures.check_one(id, tile.x, tile.y, world_width, world_height, 0.0)
		assert_eq(species, id)


func test_check_one_unknown_id_returns_empty_string_not_a_crash():
	var species := creatures.check_one("bigfoot", 0, 0, world_width, world_height, 0.0)
	assert_eq(species, "")


func test_a_creature_check_has_no_persistent_state():
	# Same "zero mechanical presence beyond the decision itself" shape as
	# EasterEggSightings -- calling check_one twice with the same inputs is
	# exactly as valid as calling it once.
	var tile := _tile_at("coilnecca")
	var first := creatures.check_one("coilnecca", tile.x, tile.y, world_width, world_height, 0.0)
	var second := creatures.check_one("coilnecca", tile.x, tile.y, world_width, world_height, 0.0)
	assert_eq(first, second)


## Doc: Squallmaw "spawns at a wildly lower rate than even the rarest
## ordinary predator" -- operationalized as "rarer than every other
## coordinate-triggered cameo in this project", both this stage's own
## Coilnecca/Champ and Stage A's EasterEggSightings roster, since those are
## the only other numbers in the same units (a per-EASTER_EGG_CHECK_
## INTERVAL-seconds roll) to compare against.
func test_squallmaw_is_far_rarer_than_every_other_easter_egg_cameo():
	var squallmaw_chance: float = EasterEggCreatures.SIGHTINGS["squallmaw"]["chance_per_check"]
	for id in ["coilnecca", "champ"]:
		var chance: float = EasterEggCreatures.SIGHTINGS[id]["chance_per_check"]
		assert_lt(squallmaw_chance * 5.0, chance, "squallmaw should be far rarer than %s" % id)
	for id in EasterEggSightings.SIGHTINGS:
		var chance: float = EasterEggSightings.SIGHTINGS[id]["chance_per_check"]
		assert_lt(
			squallmaw_chance * 5.0, chance,
			"squallmaw should be far rarer than every existing sighting cameo (%s)" % id
		)


## Coilnecca and Champ are cameos, not the collection's rarest entry --
## pinned as a relative property against Squallmaw rather than an
## independent literal, matching this project's own "no eyeballed
## thresholds" precedent (see EasterEggSightings' matching test).
func test_coilnecca_and_champ_are_tuned_independently_of_each_other():
	# Not a hard requirement that they match OR differ -- just that both are
	# real, positive, sane per-check probabilities.
	for id in ["coilnecca", "champ"]:
		var chance: float = EasterEggCreatures.SIGHTINGS[id]["chance_per_check"]
		assert_gt(chance, 0.0, id)
		assert_lt(chance, 1.0, id)
