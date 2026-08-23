extends GutTest

## Pollen moving from one plant to another, and seed only being set when it
## arrives (see docs/concept/flora.md).
##
## A plant that sets seed on its own is not being pollinated -- it is just
## reproducing, with the pollinator as decoration. Requiring pollen makes the
## bees load-bearing: no bees, no seed, and a meadow that loses its pollinators
## stops renewing itself.

const Pollination = preload("res://src/gameplay/pollination.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")


# -- plants have a sex -------------------------------------------------------

func test_a_plant_is_male_or_female():
	for seed_value in 100:
		var sex := Pollination.sex_of(seed_value)
		assert_true(
			sex == Pollination.MALE or sex == Pollination.FEMALE, "got %s" % sex
		)


func test_a_given_plant_keeps_its_sex():
	for seed_value in [0, 13, 707, 5000]:
		assert_eq(Pollination.sex_of(seed_value), Pollination.sex_of(seed_value))


## Roughly even, or one sex is a rarity and the meadow barely sets seed.
func test_both_sexes_are_about_as_common():
	var males := 0
	for seed_value in 1000:
		if Pollination.sex_of(seed_value) == Pollination.MALE:
			males += 1
	assert_between(float(males) / 1000.0, 0.35, 0.65)


# -- pollen moves one way ----------------------------------------------------

func test_only_a_male_flower_gives_pollen():
	assert_true(Pollination.gives_pollen(Pollination.MALE))
	assert_false(Pollination.gives_pollen(Pollination.FEMALE))


func test_only_a_female_flower_can_set_seed():
	assert_true(Pollination.can_set_seed(Pollination.FEMALE, "crocus"))
	assert_false(Pollination.can_set_seed(Pollination.MALE, "crocus"))


## Pollen is species-specific: a bee carrying crocus pollen does nothing for a
## rose. That is what stops a meadow of mixed flowers cross-breeding into one.
func test_pollen_only_works_on_its_own_species():
	assert_true(Pollination.pollinates("crocus", "crocus"))
	assert_false(Pollination.pollinates("crocus", "rose"))


func test_carrying_nothing_pollinates_nothing():
	assert_false(Pollination.pollinates("", "crocus"))


# -- the whole trip ----------------------------------------------------------

## A bee that has visited a male flower carries its pollen to the next one.
func test_visiting_a_male_flower_loads_pollen():
	assert_eq(
		Pollination.pollen_after_visit("", "crocus", Pollination.MALE), "crocus"
	)


## Visiting a female flower does not strip what it is carrying -- one load of
## pollen can fertilise more than one plant, which is why a single bee is worth
## anything at all.
func test_visiting_a_female_flower_keeps_the_pollen():
	assert_eq(
		Pollination.pollen_after_visit("crocus", "crocus", Pollination.FEMALE), "crocus"
	)


## ...but a later male flower replaces it: a bee carries what it touched last.
func test_a_later_male_flower_replaces_the_load():
	assert_eq(
		Pollination.pollen_after_visit("crocus", "rose", Pollination.MALE), "rose"
	)


## The case the whole system exists for: seed is set only when a carrier
## arrives at a female flower of the matching species.
func test_seed_is_set_only_when_matching_pollen_arrives():
	assert_true(Pollination.sets_seed("crocus", "crocus", Pollination.FEMALE))
	assert_false(Pollination.sets_seed("rose", "crocus", Pollination.FEMALE))
	assert_false(Pollination.sets_seed("crocus", "crocus", Pollination.MALE))
	assert_false(Pollination.sets_seed("", "crocus", Pollination.FEMALE))


## Every species can actually be pollinated -- a species that can never set
## seed would quietly die out of the world.
func test_every_species_can_be_pollinated():
	for species in FlowerSpecies.IDS:
		assert_true(Pollination.sets_seed(species, species, Pollination.FEMALE), species)
