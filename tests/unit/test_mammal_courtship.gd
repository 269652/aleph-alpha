extends GutTest

## Land-mammal courtship: the walking-quadruped counterpart to Courtship
## (pollinators-only, a synchronized flutter no grounded animal can perform).
## Pure and engine-free like Courtship itself, so the whole approach-then-
## linger cycle is testable headlessly. See docs/concept/ecosystem_dynamics.md
## and World._pair_up_courtships / _advance_courtships / _resolve_courtship.

const MammalCourtship = preload("res://src/gameplay/mammal_courtship.gd")
const World = preload("res://scenes/world.gd")


# -- closing distance, then lingering ----------------------------------------

func test_a_far_apart_pair_should_keep_approaching():
	assert_true(MammalCourtship.should_approach(MammalCourtship.LINGER_RADIUS_PX + 1.0))


func test_a_pair_within_the_linger_radius_stops_approaching():
	assert_false(MammalCourtship.should_approach(MammalCourtship.LINGER_RADIUS_PX - 1.0))


func test_linger_radius_is_comfortably_inside_the_neighbour_radius():
	# The pair has to visibly CLOSE distance -- if lingering triggered at or
	# beyond the radius that found them each other in the first place, they
	# would already read as "arrived" the instant courtship began.
	assert_lt(MammalCourtship.LINGER_RADIUS_PX, World.NEIGHBOUR_RADIUS_PX)


# -- how long they have to linger before it resolves -------------------------

func test_courtship_is_not_complete_before_its_duration():
	assert_false(MammalCourtship.courtship_complete(MammalCourtship.COURTSHIP_SECONDS - 0.1))


func test_courtship_completes_once_the_duration_has_elapsed():
	assert_true(MammalCourtship.courtship_complete(MammalCourtship.COURTSHIP_SECONDS))


## Long enough to actually watch (several World.REPRODUCTION_INTERVAL ticks,
## not one), short enough it doesn't stall a whole reproduction cycle for a
## day -- courtship itself is meant to be common and watchable, unlike the
## real-world-day REPRO_COOLDOWN gate that makes a creature eligible again.
func test_courtship_duration_spans_several_reproduction_ticks():
	assert_gt(MammalCourtship.COURTSHIP_SECONDS, World.REPRODUCTION_INTERVAL * 2.0)


# -- finding the nearest eligible partner (mirrors FoodConsumption.nearest_food_index) --

func test_nearest_partner_index_picks_the_closest_candidate():
	var position := Vector2.ZERO
	var candidates := [Vector2(100, 0), Vector2(20, 0), Vector2(50, 0)]
	assert_eq(MammalCourtship.nearest_partner_index(position, candidates, 160.0), 1)


func test_nearest_partner_index_ignores_candidates_outside_the_radius():
	var position := Vector2.ZERO
	var candidates := [Vector2(200, 0)]
	assert_eq(MammalCourtship.nearest_partner_index(position, candidates, 160.0), -1)


func test_nearest_partner_index_is_minus_one_with_no_candidates():
	assert_eq(MammalCourtship.nearest_partner_index(Vector2.ZERO, [], 160.0), -1)


func test_nearest_partner_index_accepts_a_candidate_exactly_at_the_radius():
	var candidates := [Vector2(160.0, 0)]
	assert_eq(MammalCourtship.nearest_partner_index(Vector2.ZERO, candidates, 160.0), 0)


# -- fitness-preferring partner choice (AnimalFitness's first real caller) --
#
# Distance still gates who is even a CANDIDATE (an attractive mate three
# chunks away is not reachable) -- see most_attractive_partner_index's own
# doc comment for why that has to come first, not the other way round.
# Among whatever is actually in range, the creature ranks candidates by
# AnimalFitness.mate_attractiveness against its OWN phenotype rather than
# just taking whichever happens to be closest.

func test_most_attractive_partner_index_prefers_higher_attractiveness_when_equidistant():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	var own_phenotype: Dictionary = fitness.phenotype_for(1)
	# Two candidates at the exact same distance -- only attractiveness can
	# break the tie, so if it picks the closer-looking-but-actually-equidistant
	# candidate that isn't the more attractive one, the fitness ranking isn't
	# doing anything.
	var less_attractive := {"strength": 0.1, "agility": 0.1, "coat_vibrancy": 0.1}
	var more_attractive: Dictionary = fitness.phenotype_for(1)  # identical to self: max similarity + own fitness
	var position := Vector2.ZERO
	var candidate_positions := [Vector2(50, 0), Vector2(0, 50)]
	var candidate_phenotypes := [less_attractive, more_attractive]
	assert_eq(
		MammalCourtship.most_attractive_partner_index(
			own_phenotype, position, candidate_positions, candidate_phenotypes, 160.0
		),
		1
	)


func test_most_attractive_partner_index_ignores_candidates_outside_the_radius():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	var own_phenotype: Dictionary = fitness.phenotype_for(1)
	var candidate_positions := [Vector2(200, 0)]
	var candidate_phenotypes := [fitness.phenotype_for(1)]
	assert_eq(
		MammalCourtship.most_attractive_partner_index(
			own_phenotype, Vector2.ZERO, candidate_positions, candidate_phenotypes, 160.0
		),
		-1
	)


func test_most_attractive_partner_index_is_minus_one_with_no_candidates():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	var own_phenotype: Dictionary = fitness.phenotype_for(1)
	assert_eq(
		MammalCourtship.most_attractive_partner_index(own_phenotype, Vector2.ZERO, [], [], 160.0),
		-1
	)


## A far, more attractive candidate still loses to a nearer, less attractive
## one that's outside the far candidate's own reach -- the radius restricts
## the candidate POOL before ranking ever runs, so attractiveness can never
## reach past the distance an animal can actually perceive/travel.
func test_most_attractive_partner_index_never_reaches_beyond_the_radius():
	var AnimalFitness = preload("res://src/world/animal_fitness.gd")
	var fitness := AnimalFitness.new()
	var own_phenotype: Dictionary = fitness.phenotype_for(1)
	var candidate_positions := [Vector2(50, 0), Vector2(500, 0)]
	var candidate_phenotypes := [
		{"strength": 0.1, "agility": 0.1, "coat_vibrancy": 0.1},
		{"strength": 1.0, "agility": 1.0, "coat_vibrancy": 1.0},
	]
	assert_eq(
		MammalCourtship.most_attractive_partner_index(
			own_phenotype, Vector2.ZERO, candidate_positions, candidate_phenotypes, 160.0
		),
		0
	)
