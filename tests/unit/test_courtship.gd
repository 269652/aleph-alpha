extends GutTest

## Courtship: two animals of the same kind noticing each other, dancing, and
## sometimes mating (see docs/concept/ecosystem_dynamics.md).
##
## Pure and engine-free like the rest of the behaviour modules, so the whole
## meeting-to-mating cycle is testable headlessly.

const Courtship = preload("res://src/gameplay/courtship.gd")
const LifeCycle = preload("res://src/gameplay/life_cycle.gd")


# -- who will court whom -----------------------------------------------------

func test_two_of_the_same_kind_will_court():
	assert_true(Courtship.can_court("monarch", "monarch"))


func test_different_species_do_not_court():
	assert_false(Courtship.can_court("monarch", "swallowtail"))
	assert_false(Courtship.can_court("horse", "deer"))


## An animal cannot court itself -- the caller passes candidates from a group
## scan that includes itself, and a self-pairing would be a partner that is
## always available and always in range.
func test_an_animal_does_not_court_itself():
	assert_false(Courtship.can_pair(7, 7))
	assert_true(Courtship.can_pair(7, 8))


## Exactly one of a pair leads the dance, decided the same way by both, so two
## animals never both try to lead or both try to follow.
func test_a_pair_agrees_on_which_of_them_leads():
	assert_ne(Courtship.leads(3, 9), Courtship.leads(9, 3))
	assert_eq(Courtship.leads(3, 9), Courtship.leads(3, 9))


# -- the dance ---------------------------------------------------------------

func test_the_dance_is_a_circling_motion_around_the_partner():
	var offsets := []
	for step in 8:
		offsets.append(
			Courtship.dance_offset(float(step) * Courtship.DANCE_SECONDS / 8.0, 1, true)
		)
	var angles := {}
	for offset in offsets:
		angles[snappedf(offset.angle(), 0.2)] = true
	assert_gt(angles.size(), 4, "the pair should circle, not sit beside each other")


## Partners orbit opposite each other rather than on top of one another --
## that is what reads as two butterflies dancing rather than one sprite.
func test_partners_stay_on_opposite_sides_of_the_dance():
	var leader := Courtship.dance_offset(0.7, 1, true)
	var follower := Courtship.dance_offset(0.7, 1, false)
	assert_gt(leader.distance_to(follower), Courtship.DANCE_RADIUS_PX, "they should be apart")


func test_the_dance_stays_close_enough_to_read_as_one_pair():
	for step in 20:
		var offset := Courtship.dance_offset(float(step) * 0.13, 5, true)
		assert_lte(offset.length(), Courtship.DANCE_RADIUS_PX + 0.01)


# -- mating ------------------------------------------------------------------

## Occasionally, not every meeting: two butterflies crossing paths mostly just
## cross paths.
func test_only_some_dances_end_in_mating():
	var mated := 0
	for pair in 400:
		if Courtship.mates(pair * 31 + 7):
			mated += 1
	var rate := float(mated) / 400.0
	assert_gt(rate, 0.05, "mating has to actually happen sometimes")
	assert_lt(rate, 0.6, "...but a meeting is not a pregnancy")


func test_whether_a_given_pairing_mates_is_deterministic():
	assert_eq(Courtship.mates(12345), Courtship.mates(12345))


## A pair that has just courted does not court again for a REAL DAY.
##
## The cooldown was 40 seconds, which measured as a butterfly added every few
## seconds. The brief puts this on wall-clock time -- "1+ real day to mate" --
## so the dance stays a common sight and what follows it does not.
func test_courting_is_followed_by_a_cooldown():
	assert_gt(Courtship.COOLDOWN_SECONDS, Courtship.DANCE_SECONDS)
	assert_gte(
		Courtship.COOLDOWN_SECONDS, LifeCycle.MATE_SECONDS,
		"a pair must not court again inside a real day"
	)


## The dance itself is still seconds long: it is the thing the player is meant
## to SEE, and a courtship flight that took a day would never be witnessed.
func test_the_dance_itself_stays_watchable_even_though_breeding_does_not():
	assert_lt(Courtship.DANCE_SECONDS, 60.0)


func test_the_dance_lasts_long_enough_to_be_seen():
	assert_gt(Courtship.DANCE_SECONDS, 1.0, "a dance the player cannot notice is not a dance")
	assert_lt(Courtship.DANCE_SECONDS, 20.0, "...but they are not courting all day either")


## Only pollinators dance. A bird performing a butterfly's tight spiralling
## courtship flight reads as a bird glitching in place -- reported as birds
## stalling and jittering on the spot.
func test_birds_do_not_perform_the_butterfly_dance():
	assert_false(Courtship.can_court("sparrow", "sparrow"))
	assert_false(Courtship.can_court("robin", "robin"))
	assert_false(Courtship.dances("sparrow"))


func test_pollinators_still_dance():
	for species in ["monarch", "swallowtail", "blue_morpho", "bee"]:
		assert_true(Courtship.can_court(species, species), "%s should dance" % species)
