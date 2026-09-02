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


# -- bait: what a PARTICULAR food smells of ----------------------------------
#
# See docs/concept/animal_husbandry.md "The approach". fruit_mixture ignores
# its item id, so every food on the ground emitted the same mixture and a
# carrot was no better a lure for a horse than a walnut was -- which makes
# baiting meaningless as a verb.


## The whole point of a bait table: two different foods are two different
## smells, so WHAT you put down decides WHO comes.
func test_a_carrot_and_an_apple_do_not_smell_the_same():
	var carrot := Olfaction.bait_mixture("carrot", 1.0)
	var apple := Olfaction.bait_mixture("apple", 1.0)
	assert_ne(carrot, apple, "a carrot and an apple must not emit the same mixture")


## A food nobody gave a mixture is a food no animal can ever smell -- a silent
## dead bait. Iterating the catalog means one added later cannot be scentless.
func test_every_food_item_in_the_catalog_has_a_mixture():
	var catalog = load("res://src/gameplay/item_catalog.gd").new()
	for item_id in catalog.known_ids():
		if catalog.kind_of(item_id) != "food":
			continue
		var mixture := Olfaction.bait_mixture(item_id, 1.0)
		assert_false(mixture.is_empty(), "%s emits nothing at all" % item_id)


## Bait keeps fruit's ripe-to-rotten interpolation: a food still goes over, and
## its audience still changes as it does.
func test_bait_still_shifts_toward_decay_as_it_spoils():
	var fresh := Olfaction.bait_mixture("carrot", 1.0)
	var spoiled := Olfaction.bait_mixture("carrot", 0.0)
	assert_gt(
		spoiled.get(Olfaction.DECAY, 0.0),
		fresh.get(Olfaction.DECAY, 0.0),
		"a carrot left out should smell more of decay, not less"
	)


## The reason a carrot is the taming treat: a grazer wants a root over a nut.
## An ordering, not a weight -- the mixtures can be retuned as long as the
## grazer still prefers the thing a grazer prefers.
func test_a_grazer_prefers_a_carrot_to_a_walnut():
	var carrot := Olfaction.bait_mixture("carrot", 1.0)
	var walnut := Olfaction.bait_mixture("walnut", 1.0)
	assert_gt(
		Olfaction.attraction_to("horse", carrot, 1.0),
		Olfaction.attraction_to("horse", walnut, 1.0)
	)


## And the converse, so the table is a real disagreement between animals
## rather than one food that is simply better than another for everyone.
func test_a_squirrel_prefers_a_walnut_to_a_carrot():
	var carrot := Olfaction.bait_mixture("carrot", 1.0)
	var walnut := Olfaction.bait_mixture("walnut", 1.0)
	assert_gt(
		Olfaction.attraction_to("squirrel", walnut, 1.0),
		Olfaction.attraction_to("squirrel", carrot, 1.0)
	)


# -- the roster, widened -----------------------------------------------------


## Sheep, goat, camel, reindeer and tapir had no receptors at all, so nothing
## a player put on the ground existed for them. Iterating the real anatomy
## roster means a species added later cannot be born noseless.
func test_every_keepable_species_has_a_nose():
	var anatomy = load("res://src/rendering/animal_anatomy.gd")
	for species in anatomy.SPECIES:
		assert_true(Olfaction.has_nose(species), "%s cannot smell anything" % species)


## Same invariant as test_every_receptor_set_covers_every_molecule, but over
## every nose the game can actually hand out (derived ones included) rather
## than only the hand-authored table.
func test_every_derived_nose_covers_every_molecule():
	var anatomy = load("res://src/rendering/animal_anatomy.gd")
	for species in anatomy.SPECIES:
		var receptors := Olfaction.receptors_for(species)
		for molecule in Olfaction.MOLECULES:
			assert_true(
				receptors["sensitivity"].has(molecule),
				"%s has no receptor for %s" % [species, molecule]
			)
			assert_true(
				receptors["response"].has(molecule), "%s has no response to %s" % [species, molecule]
			)


## The five hand-tuned profiles are not lost when the derived ones arrive:
## receptors_for still hands back the authored entry for a species that has
## one, so the boar/deer/horse/robin/fly tuning keeps its meaning.
func test_a_hand_authored_nose_wins_over_its_diet_default():
	assert_eq(Olfaction.receptors_for("boar"), Olfaction.RECEPTORS["boar"])


# -- the player has a smell --------------------------------------------------


## A human is an animal, and animals smell of musk. This is what makes wind
## direction matter at all (see WindScent): without a player emission there is
## nothing for the wind to carry toward the animal.
func test_the_player_smells_of_musk():
	var mixture := Olfaction.player_mixture()
	assert_gt(mixture.get(Olfaction.MUSK, 0.0), 0.0)


## And every prey animal is driven off by it rather than drawn in, which is the
## whole reason a stalk has to be downwind.
func test_a_grazer_is_repelled_by_the_players_smell():
	assert_lt(Olfaction.attraction_to("sheep", Olfaction.player_mixture(), 1.0), 0.0)
