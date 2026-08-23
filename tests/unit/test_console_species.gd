extends GutTest

## /spawn's species roster (see ConsoleSpecies).

const ConsoleSpecies = preload("res://src/gameplay/console_species.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")


## The reported gap: snakes existed in the world but could not be spawned to
## look at, because the console validated against a four-entry colour table
## rather than the actual species roster.
func test_every_species_with_an_anatomy_can_be_spawned():
	for species in AnimalAnatomy.SPECIES:
		assert_eq(ConsoleSpecies.resolve(species), species, "%s should be spawnable" % species)


## "/spawn snake" must work -- guessing "nonvenomous_snake" is the friction a
## debug console exists to remove.
func test_friendly_aliases_resolve_to_real_species():
	assert_eq(ConsoleSpecies.resolve("snake"), "nonvenomous_snake")
	assert_eq(ConsoleSpecies.resolve("viper"), "venomous_snake")


func test_lookup_ignores_case_and_padding():
	assert_eq(ConsoleSpecies.resolve("  SNAKE "), "nonvenomous_snake")


func test_an_unknown_species_resolves_to_nothing():
	assert_eq(ConsoleSpecies.resolve("dragon"), "")
	assert_eq(ConsoleSpecies.resolve(""), "")


## Every alias must point at something real, or /help advertises a command
## that fails.
func test_no_alias_points_at_a_missing_species():
	for alias in ConsoleSpecies.ALIASES:
		assert_true(
			AnimalAnatomy.SPECIES.has(ConsoleSpecies.ALIASES[alias]),
			"alias '%s' targets a species that does not exist" % alias
		)


func test_the_advertised_list_is_actually_spawnable():
	for name in ConsoleSpecies.spawnable():
		assert_ne(ConsoleSpecies.resolve(name), "", "/help lists '%s' but it cannot spawn" % name)
