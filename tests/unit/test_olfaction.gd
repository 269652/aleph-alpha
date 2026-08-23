extends GutTest

## Smell as molecules and receptors (see docs/concept/olfaction.md).
##
## Nothing in the world is inherently attractive or repellent: a boar and a fly
## meet the same rotting apple and disagree, because they carry different
## receptors and weigh them differently.

const Olfaction = preload("res://src/gameplay/olfaction.gd")


# -- what a thing smells of --------------------------------------------------

## A ripe apple and a rotten one are the same fruit emitting different
## proportions of the same molecules -- not two entries in a table of scents.
func test_ripe_fruit_smells_of_sugar():
	var mixture := Olfaction.fruit_mixture("apple", 1.0)
	assert_gt(mixture.get(Olfaction.SUGAR, 0.0), mixture.get(Olfaction.DECAY, 0.0))


func test_rotten_fruit_smells_of_decay():
	var mixture := Olfaction.fruit_mixture("apple", 0.0)
	assert_gt(mixture.get(Olfaction.DECAY, 0.0), mixture.get(Olfaction.SUGAR, 0.0))


## It shifts GRADUALLY as the fruit goes over, so its audience changes across
## its life rather than at a threshold.
func test_fruit_shifts_from_sugar_to_decay_as_it_spoils():
	var previous_sugar := 999.0
	var previous_decay := -1.0
	for step in 12:
		var freshness := 1.0 - float(step) / 11.0
		var mixture := Olfaction.fruit_mixture("apple", freshness)
		var sugar: float = mixture.get(Olfaction.SUGAR, 0.0)
		var decay: float = mixture.get(Olfaction.DECAY, 0.0)
		assert_lte(sugar, previous_sugar + 0.001, "sugar should fall as it spoils")
		assert_gte(decay, previous_decay - 0.001, "decay should rise as it spoils")
		previous_sugar = sugar
		previous_decay = decay


## Every molecule in a mixture is one the model knows.
func test_a_mixture_only_contains_real_molecules():
	for freshness in [0.0, 0.5, 1.0]:
		for molecule in Olfaction.fruit_mixture("cherry", freshness):
			assert_true(Olfaction.MOLECULES.has(molecule), "unknown molecule %s" % molecule)


# -- who cares ---------------------------------------------------------------

## The pillar: the same rotting fruit, two animals, opposite verdicts.
func test_a_fly_and_a_boar_disagree_about_a_rotten_fruit():
	var rotten := Olfaction.fruit_mixture("apple", 0.0)
	assert_gt(Olfaction.attraction_to("fly", rotten, 0.0), 0.0, "a fly should want it")
	assert_lt(Olfaction.attraction_to("deer", rotten, 0.0), 0.0, "a deer should not")


func test_everything_likes_ripe_fruit():
	var ripe := Olfaction.fruit_mixture("apple", 1.0)
	for species in ["boar", "deer", "robin"]:
		assert_gt(Olfaction.attraction_to(species, ripe, 0.0), 0.0, species)


## Sensitivity and response are SEPARATE: an animal can be keenly aware of
## something it wants nothing to do with, which is what makes a repellent work.
func test_an_animal_can_notice_strongly_what_it_dislikes():
	var rotten := Olfaction.fruit_mixture("apple", 0.0)
	assert_gt(
		Olfaction.perceived_strength("deer", rotten, 0.0), 0.0,
		"a deer should still SMELL a rotting fruit"
	)
	assert_lt(
		Olfaction.attraction_to("deer", rotten, 0.0), 0.0,
		"...and still want nothing to do with it"
	)


func test_an_unknown_species_smells_nothing_and_wants_nothing():
	var ripe := Olfaction.fruit_mixture("apple", 1.0)
	assert_eq(Olfaction.perceived_strength("nonesuch", ripe, 0.0), 0.0)
	assert_eq(Olfaction.attraction_to("nonesuch", ripe, 0.0), 0.0)


# -- distance dilutes --------------------------------------------------------

## An animal follows a GRADIENT rather than teleporting to a known point. That
## gradient is the thing the player watches.
func test_smell_fades_with_distance():
	var ripe := Olfaction.fruit_mixture("apple", 1.0)
	var near := Olfaction.perceived_strength("boar", ripe, 1.0)
	var far := Olfaction.perceived_strength("boar", ripe, 12.0)
	assert_gt(near, far, "smell should fade with range")
	assert_gt(far, 0.0, "...but still carry")


func test_beyond_range_nothing_carries():
	var ripe := Olfaction.fruit_mixture("apple", 1.0)
	assert_eq(
		Olfaction.perceived_strength("boar", ripe, Olfaction.MAX_RANGE_TILES * 2.0), 0.0
	)


## Dilution never flips the verdict: distance makes a thing fainter, not
## friendlier.
func test_distance_never_turns_repulsion_into_attraction():
	var rotten := Olfaction.fruit_mixture("apple", 0.0)
	for step in 20:
		var distance := float(step) / 19.0 * Olfaction.MAX_RANGE_TILES
		assert_lte(Olfaction.attraction_to("deer", rotten, distance), 0.0)


# -- the roster --------------------------------------------------------------

## Every animal with receptors has a sensitivity for every molecule, so a new
## molecule cannot silently be invisible to half the roster.
func test_every_receptor_set_covers_every_molecule():
	for species in Olfaction.RECEPTORS:
		for molecule in Olfaction.MOLECULES:
			assert_true(
				Olfaction.RECEPTORS[species]["sensitivity"].has(molecule),
				"%s has no receptor for %s" % [species, molecule]
			)
			assert_true(
				Olfaction.RECEPTORS[species]["response"].has(molecule),
				"%s has no response to %s" % [species, molecule]
			)
