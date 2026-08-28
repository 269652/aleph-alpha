extends GutTest

## World's land-mammal courtship gates (see World._pair_up_courtships /
## _advance_courtships / _resolve_courtship, and MammalCourtship for the
## approach/linger/duration logic these build on).
##
## Only the PURE static gate is exercised here -- World itself is a live
## scene script wired to a chunk manager and creature renderer, so the actual
## node-scanning/pairing/spawning is exercised by hand-testing the running
## game (see docs/progress.md), the same way World's other static gates
## (always_day_for, ecology_scale_for_console_argument,
## owns_ecosystem_simulation_for) are unit-tested without instancing World.

const World = preload("res://scenes/world.gd")


## A pair that finished lingering still has to be checked AGAIN at the moment
## it resolves, not just when it started -- conditions (crowding, carrying
## capacity, whether the partner is even still nearby) can change during the
## courtship window.
func test_a_pair_still_together_and_under_every_cap_is_viable():
	assert_true(World.courtship_still_viable(10.0, 160.0, 1, 4, true))


func test_a_pair_that_has_drifted_apart_is_not_viable():
	assert_false(World.courtship_still_viable(200.0, 160.0, 1, 4, true))


## Exactly the bug this whole gate exists to prevent: "the fruit caused dozens
## of deer to spawn" -- a clearing that filled up WHILE a pair was courting
## must not still produce young just because they started before it was full.
func test_a_pair_in_a_since_overcrowded_clearing_is_not_viable():
	assert_false(World.courtship_still_viable(10.0, 160.0, 4, 4, true))


func test_a_pair_the_land_can_no_longer_support_is_not_viable():
	assert_false(World.courtship_still_viable(10.0, 160.0, 1, 4, false))


func test_viability_is_exact_at_the_neighbour_radius_boundary():
	assert_true(World.courtship_still_viable(160.0, 160.0, 1, 4, true))
