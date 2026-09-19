extends GutTest

## CrushMechanic: the shared momentum-based "crushed underfoot" physics
## check every soft-bodied creature small enough to be at risk uses --
## today, EarthwormPatch.crush (worms) and EarthChunkManager.
## crush_caterpillars_near (caterpillars) both resolve through this same
## class, rather than each owning an independent copy of the threshold
## (see docs/concept/soil_fauna.md's "Generalized to caterpillars too").
## These are the same is_crushed_by cases that used to live directly on
## EarthwormPatch, moved here unchanged in substance -- testing the class
## that actually owns the physics rule now, not the worm specifically.

const CrushMechanic = preload("res://src/world/crush_mechanic.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")


## The real, tested boundary this whole mechanic exists to draw: a mouse's
## own momentum must fall under the threshold, and a horse's/player's own
## must clear it -- computed from the SAME real numbers the live game
## actually uses, not invented test-only figures.
func test_is_crushed_by_spares_a_mouses_own_real_momentum():
	var mouse_momentum: float = CreatureMass.mass_kg_for("mouse") * PebbleDispersion.FOOTSTEP_SPEED_MPS
	assert_false(CrushMechanic.is_crushed_by(mouse_momentum))


func test_is_crushed_by_kills_under_a_horses_own_real_momentum():
	var horse_momentum: float = CreatureMass.mass_kg_for("horse") * PebbleDispersion.FOOTSTEP_SPEED_MPS
	assert_true(CrushMechanic.is_crushed_by(horse_momentum))


## The calibration example given directly, back when the worm mechanic
## first shipped: a light creature's step spares something this small, a
## heavy one's kills it. No frog exists in this game -- mouse/squirrel
## stand in for it here, same as they always have.
func test_is_crushed_by_spares_small_creatures_and_kills_under_large_ones():
	for species in ["mouse", "squirrel"]:
		var momentum: float = CreatureMass.mass_kg_for(species) * PebbleDispersion.FOOTSTEP_SPEED_MPS
		assert_false(CrushMechanic.is_crushed_by(momentum), "%s should spare something this small" % species)
	for species in ["horse", "boar", "deer", "bear"]:
		var momentum: float = CreatureMass.mass_kg_for(species) * PebbleDispersion.FOOTSTEP_SPEED_MPS
		assert_true(CrushMechanic.is_crushed_by(momentum), "%s should crush something this small" % species)


func test_is_crushed_by_is_never_true_at_zero_momentum():
	assert_false(CrushMechanic.is_crushed_by(0.0))


func test_the_threshold_is_the_pinned_tuned_constant():
	assert_eq(CrushMechanic.CRUSH_MOMENTUM_THRESHOLD_KG_M_S, 5.0)


# -- crushing a real ANIMAL underfoot ---------------------------------------
#
# Reported in play: "Stepping on a frog doesn't kill it? Shouldn't this work
# out of the box for ANY animal when enough pressure is put on it? A boar
# walking over a frog should kill it as well" (see docs/concept/soil_fauna.md
# "Generalized to ANY animal").
#
# is_crushed_by alone cannot answer this. It asks only "is the stepper heavy
# enough to crush anything at all", which is the whole question for a worm --
# anything over that threshold flattens a worm -- and the wrong question on
# its own for an animal: a boar clears it, a deer is also an animal, and a
# boar does not crush a deer by stepping on it. So the victim needs a second
# term, and that term is DERIVED rather than picked: PebbleDispersion.
# FOOT_MASS_FRACTION is already a cited anatomical figure (one foot is 1.4%
# of body mass), which gives the boundary for free --
#
#   an animal is crushed underfoot when it weighs less than the foot landing
#   on it
#
# -- with no new tuned number invented anywhere.


func test_one_foot_is_the_anatomical_fraction_of_the_stepper_it_belongs_to():
	assert_almost_eq(CrushMechanic.foot_mass_kg(70.0), 70.0 * PebbleDispersion.FOOT_MASS_FRACTION, 0.0001)
	assert_almost_eq(CrushMechanic.foot_mass_kg(CreatureMass.mass_kg_for("horse")), 7.0, 0.0001)
	assert_eq(CrushMechanic.foot_mass_kg(0.0), 0.0, "nothing has no foot")


## The report itself, against the game's own real masses: a person and a
## boar both crush a frog.
func test_a_person_and_a_boar_both_crush_a_frog_underfoot():
	var frog: float = CreatureMass.mass_kg_for("grass_frog")
	assert_true(CrushMechanic.crushes_underfoot(CreatureMass.PLAYER_MASS_KG, frog), "player")
	assert_true(CrushMechanic.crushes_underfoot(CreatureMass.mass_kg_for("boar"), frog), "boar")


## And the reason the second term has to exist at all: momentum alone would
## have a boar flatten a deer, because a boar clears the momentum gate.
func test_an_animal_too_heavy_to_go_under_a_foot_is_not_crushed():
	var horse: float = CreatureMass.mass_kg_for("horse")
	assert_true(
		CrushMechanic.is_crushed_by(horse * PebbleDispersion.FOOTSTEP_SPEED_MPS),
		"the premise: a horse clears the momentum gate easily"
	)
	assert_false(
		CrushMechanic.crushes_underfoot(horse, CreatureMass.mass_kg_for("wolf")),
		"a horse does not flatten a wolf by putting a foot on it"
	)
	assert_false(
		CrushMechanic.crushes_underfoot(CreatureMass.mass_kg_for("deer"), CreatureMass.mass_kg_for("jackal")),
		"nor a deer a jackal"
	)
	assert_false(
		CrushMechanic.crushes_underfoot(CreatureMass.mass_kg_for("boar"), CreatureMass.mass_kg_for("deer")),
		"nor a boar a deer -- the case momentum alone gets wrong"
	)


## A horse's foot really is heavier than a whole snake, and that is the
## boundary: big enough steppers crush genuinely substantial animals.
func test_a_heavy_enough_stepper_crushes_a_genuinely_substantial_animal():
	assert_true(
		CrushMechanic.crushes_underfoot(CreatureMass.mass_kg_for("horse"), CreatureMass.mass_kg_for("venomous_snake"))
	)


## The first term is not redundant: a mouse's foot is lighter than an ant,
## but a mouse crushes nothing, because it never clears the momentum gate.
func test_a_stepper_too_light_to_crush_anything_crushes_nothing():
	var mouse: float = CreatureMass.mass_kg_for("mouse")
	assert_lt(
		CreatureMass.mass_kg_for("ant"), CrushMechanic.foot_mass_kg(mouse),
		"the premise: an ant really is lighter than a mouse's own foot"
	)
	assert_false(
		CrushMechanic.crushes_underfoot(mouse, CreatureMass.mass_kg_for("ant")),
		"a mouse still crushes nothing -- it fails the momentum gate first"
	)


## Both terms, stated as the rule rather than as examples: for every pair of
## the game's own real species, crushes_underfoot is exactly "the stepper
## clears the momentum gate AND the victim is no heavier than its foot".
func test_the_rule_is_exactly_its_two_terms_over_every_real_species_pair():
	var species := ["ant", "bug", "caterpillar", "grass_frog", "mouse", "squirrel", "jackal", "wolf", "deer", "boar", "horse"]
	for stepper in species:
		var stepper_mass: float = CreatureMass.mass_kg_for(stepper)
		for victim in species:
			var victim_mass: float = CreatureMass.mass_kg_for(victim)
			var expected := (
				CrushMechanic.is_crushed_by(stepper_mass * PebbleDispersion.FOOTSTEP_SPEED_MPS)
				and victim_mass <= CrushMechanic.foot_mass_kg(stepper_mass)
			)
			assert_eq(
				CrushMechanic.crushes_underfoot(stepper_mass, victim_mass), expected,
				"%s stepping on %s" % [stepper, victim]
			)


## Nothing crushes itself: a creature's own mass is always far more than
## its own foot, which is what stops a herd flattening itself.
func test_nothing_crushes_something_its_own_size():
	for species in ["mouse", "squirrel", "jackal", "wolf", "deer", "boar", "horse", "bear"]:
		var mass: float = CreatureMass.mass_kg_for(species)
		assert_false(CrushMechanic.crushes_underfoot(mass, mass), species)


## The frog the report is about is a real, tabulated animal mass like every
## other -- not a number invented for this rule.
func test_a_grass_frog_has_a_real_tabulated_mass():
	assert_almost_eq(CreatureMass.mass_kg_for("grass_frog"), 0.02, 0.0001)
