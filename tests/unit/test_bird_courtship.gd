extends GutTest

const BirdCourtship = preload("res://src/gameplay/bird_courtship.gd")


func test_the_three_ambient_songbirds_dance():
	for species in ["sparrow", "robin", "blackbird"]:
		assert_true(BirdCourtship.dances(species), species)


## Kingfisher has real `court` art too (IllustratedBirdSprite covers all
## four species) but is a PiscivoreBirdMarker, not an AmbientFlyerMarker --
## it never runs the interaction loop this gate controls, so it must stay
## OUT of it structurally, the same way Courtship.DANCING_SPECIES excludes
## every non-pollinator.
func test_kingfisher_does_not_dance_here_it_is_a_different_marker_class():
	assert_false(BirdCourtship.dances("kingfisher"))


## The butterfly dance stays pollinator-only -- this is a SEPARATE
## mechanism, not a widening of Courtship.DANCING_SPECIES (see
## docs/concept/animal_genetics.md's explicit "do not widen" note).
func test_pollinators_do_not_do_the_bird_display():
	assert_false(BirdCourtship.dances("monarch"))
	assert_false(BirdCourtship.dances("bee"))


func test_only_the_same_species_courts():
	assert_true(BirdCourtship.can_court("robin", "robin"))
	assert_false(BirdCourtship.can_court("robin", "sparrow"))
	assert_false(BirdCourtship.can_court("", ""))


func test_mates_produces_young_a_minority_of_the_time():
	var yes := 0
	var total := 4000
	for i in total:
		if BirdCourtship.mates(i):
			yes += 1
	var fraction := float(yes) / float(total)
	assert_between(fraction, 0.20, 0.30, "roughly MATING_CHANCE")


func test_mates_is_deterministic_for_the_same_seed():
	var seed_value := BirdCourtship.pair_seed(5, 9, 0)
	assert_eq(BirdCourtship.mates(seed_value), BirdCourtship.mates(seed_value))


func test_pair_seed_is_symmetric():
	assert_eq(BirdCourtship.pair_seed(5, 9, 0), BirdCourtship.pair_seed(9, 5, 0))


func test_pair_seed_changes_with_the_round():
	assert_ne(BirdCourtship.pair_seed(5, 9, 0), BirdCourtship.pair_seed(5, 9, 1))


func test_hold_offset_starts_exactly_where_the_bird_actually_was():
	var start := Vector2(20, -5)
	var target := Vector2(9, 0)
	assert_eq(BirdCourtship.hold_offset(0.0, start, target, 1.5), start)


func test_hold_offset_reaches_the_target_and_stays_there():
	var start := Vector2(20, -5)
	var target := Vector2(9, 0)
	assert_eq(BirdCourtship.hold_offset(1.5, start, target, 1.5), target)
	assert_eq(BirdCourtship.hold_offset(3.0, start, target, 1.5), target, "holds, does not overshoot or orbit")


func test_hold_offset_eases_monotonically_toward_the_target():
	var start := Vector2(20, 0)
	var target := Vector2(0, 0)
	var previous_distance := start.distance_to(target)
	for i in range(1, 16):
		var t := float(i) / 15.0 * 1.5
		var here := BirdCourtship.hold_offset(t, start, target, 1.5)
		var distance := here.distance_to(target)
		assert_lte(distance, previous_distance + 0.0001, "must close in, never move further from the target")
		previous_distance = distance
