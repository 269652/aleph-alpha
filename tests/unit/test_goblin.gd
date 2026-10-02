extends GutTest

## docs/concept/monsters.md, entry 10: the Goblin -- the roster's first
## humanoid Tier A hostile fauna, placed in the same dense herbivore-role
## pool boar already established (ecosystem_dynamics.md's "Steady combat
## near spawn") so a player meets one often, asked directly: "you should
## not have to walk far." What is asserted here is that it exists as a REAL
## SPECIES: every table a species needs, a real niche in a real biome's
## pool, its own bite, and that its one behaviour (never breaks off) really
## holds -- so that nothing about it is a special case bolted onto the side
## of the roster.

const CreatureInfo = preload("res://src/world/creature_info.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")
const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const ConsoleSpecies = preload("res://src/gameplay/console_species.gd")
const SpeciesBite = preload("res://src/gameplay/species_bite.gd")

const GOBLIN := "goblin"
## boar is the existing fight-capable herbivore-role filler grassland/
## forest already use (ecosystem_dynamics.md's "Steady combat near spawn")
## -- the natural creature to hold a second one against.
const REFERENCE := "boar"


# -- it is a real species, not a special case -----------------------------

## Every table the reference species appears in, the newcomer appears in
## too. Two-way rather than a hand-listed set, so a table added later cannot
## silently leave this species half-defined.
func test_it_is_defined_everywhere_an_ordinary_species_is():
	var tables := {
		"MAX_HEALTH_BY_SPECIES": CreatureInfo.MAX_HEALTH_BY_SPECIES,
		"MAX_STAMINA_BY_SPECIES": CreatureInfo.MAX_STAMINA_BY_SPECIES,
		"MAX_MANA_BY_SPECIES": CreatureInfo.MAX_MANA_BY_SPECIES,
		"DIET_BY_SPECIES": CreatureInfo.DIET_BY_SPECIES,
		"TEMPERAMENT_BY_SPECIES": CreatureInfo.TEMPERAMENT_BY_SPECIES,
	}
	for name in tables:
		var table: Dictionary = tables[name]
		assert_true(table.has(REFERENCE), "precondition: %s knows the reference" % name)
		assert_true(table.has(GOBLIN), "%s has no entry for the goblin" % name)


## Herbivore-role like boar (is_predator false): the dense population pool,
## not the sparse real-predator one -- see ecosystem_dynamics.md's new
## spawn safe-zone section on why density is raised this way, not by
## touching PREDATORS_PER_PREY_UNIT.
func test_it_fights_but_is_not_a_predator():
	assert_false(bool(CreatureInfo.PREDATOR_SPECIES.get(GOBLIN, false)))
	assert_eq(CreatureInfo.TEMPERAMENT_BY_SPECIES[GOBLIN], CreatureInfo.AGGRESSIVE)


func test_it_has_a_body_the_renderer_can_draw():
	assert_true(AnimalAnatomy.has_profile(GOBLIN), "no anatomy profile")
	assert_true(AnimalAnatomy.profile_for(GOBLIN).get("biped", false), "should use the biped body plan")
	assert_true(ProceduralAnimalSprite.SPECIES_BASE_COLORS.has(GOBLIN), "no colour")
	assert_true(CreatureMass.knows(GOBLIN), "no mass -- the loot table would silently drop nothing for it")


func test_it_can_be_summoned_by_name():
	assert_eq(ConsoleSpecies.resolve(GOBLIN), GOBLIN, "/spawn and /arena must find it")


# -- it lives in the two biomes a real spawn can land in ---------------------

func test_it_lives_in_grassland_and_forest_and_nowhere_else():
	for biome in CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME:
		var pool: Array = CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME[biome]
		if biome in CreatureRenderer.SPAWN_REACHABLE_BIOMES:
			assert_true(pool.has(GOBLIN), "%s is spawn-reachable and should be able to produce a goblin" % biome)
		else:
			assert_false(pool.has(GOBLIN), "%s is not spawn-reachable; a goblin there could never be met" % biome)


# -- it bites like itself, and it never lets go ------------------------------

func test_it_has_its_own_bite_rather_than_the_fallback():
	assert_true(SpeciesBite.has_profile(GOBLIN), "a named monster with a generic bite is a reskin")


## The roster's line about it: it never breaks off. Every other creature in
## the game flees at SOME health fraction (SpeciesBite.flees_at); a
## goblin's tenacity is exactly 0.0, so nothing above zero health ever
## triggers it.
func test_it_never_breaks_off_however_low_its_health():
	assert_eq(float(SpeciesBite.profile_for(GOBLIN)["tenacity"]), 0.0)
	for health_fraction in [1.0, 0.5, 0.1, 0.01, 0.001]:
		assert_false(
			SpeciesBite.flees_at(GOBLIN, health_fraction),
			"a goblin at %.3f health should not break off" % health_fraction
		)


func test_it_is_more_committed_than_the_biomes_ordinary_fighter():
	assert_lt(
		float(SpeciesBite.profile_for(GOBLIN)["tenacity"]),
		float(SpeciesBite.profile_for(REFERENCE)["tenacity"]),
		"a goblin must hold on past the health an ordinary fighter would quit at"
	)
