extends GutTest

## How an aggregate population becomes a number of animals you can actually
## meet (docs/concept/ecosystem_dynamics.md).
##
## Measured in a real `--solo` launch, after the report that there was
## nothing to fight. Around a fresh spawn, across the 25 chunks the streamer
## holds:
##
##   herbivores  0.40 .. 1.26 per chunk   -> 24 animals drawn
##   predators   0.03 .. 0.10 per chunk   ->  0 animals drawn
##
## The predator populations sum to **1.66 animals** in the neighbourhood --
## a real, non-zero population the simulation is tracking and stepping --
## and `roundi` turned every one of them into nothing, because each chunk
## on its own rounds below a half. So the world near spawn was a petting
## zoo: boar, sheep, mouse, deer, squirrel, horse, alpaca, and not one thing
## that hunts. The trophic pyramid (`PredatorPopulationModel.
## PREDATORS_PER_PREY_UNIT` = 0.08) is ecologically right; rounding it away
## per chunk is not.
##
## The fix is the standard one for turning a density into discrete
## individuals: keep the fraction as a CHANCE, seeded per chunk so it stays
## deterministic like every other seeded pick in this codebase.

const PopulationMarkers = preload("res://src/world/population_markers.gd")

## The real per-chunk predator figures measured above.
const MEASURED_PREDATOR_POPULATIONS := [
	0.06, 0.06, 0.06, 0.07, 0.07, 0.05, 0.09, 0.08, 0.07, 0.07, 0.07, 0.07, 0.07,
	0.08, 0.10, 0.09, 0.06, 0.06, 0.06, 0.06, 0.03, 0.04, 0.07, 0.05, 0.06,
]

const CAP := 8


# -- the whole point: a real population is not rounded away ---------------

## The assertion the petting zoo was: 1.66 predators across 25 chunks must
## produce animals, not nothing.
func test_the_measured_predator_population_really_produces_predators():
	var total := 0
	for index in MEASURED_PREDATOR_POPULATIONS.size():
		total += PopulationMarkers.count_for(
			MEASURED_PREDATOR_POPULATIONS[index], index, CAP
		)
	assert_gt(total, 0, "1.66 real predators must not render as zero predators")


## And not wildly more than there really are, either -- the ecology is right
## and must be represented, not amplified.
func test_it_does_not_invent_a_pack_out_of_a_fraction():
	var expected := 0.0
	for value in MEASURED_PREDATOR_POPULATIONS:
		expected += value
	var total := 0
	for index in MEASURED_PREDATOR_POPULATIONS.size():
		total += PopulationMarkers.count_for(
			MEASURED_PREDATOR_POPULATIONS[index], index, CAP
		)
	assert_lt(
		float(total), expected * 4.0 + 2.0,
		"a 1.66-animal population must not draw as a horde"
	)


# -- unbiased ------------------------------------------------------------

## The property that makes this honest rather than a fudge: across many
## chunks, the animals drawn total what the ecology says is there.
func test_the_count_is_unbiased_across_many_chunks():
	for population in [0.08, 0.3, 0.5, 0.76, 1.4, 2.5]:
		var samples := 4000
		var total := 0
		for seed_value in samples:
			total += PopulationMarkers.count_for(population, seed_value, 99)
		var mean := float(total) / float(samples)
		assert_almost_eq(
			mean, population, 0.06,
			"a population of %.2f must draw as %.2f animals on average" % [population, population]
		)


## An exact whole number is not a coin flip -- two deer are two deer.
func test_a_whole_population_is_drawn_exactly():
	for population in [0.0, 1.0, 2.0, 7.0]:
		for seed_value in 50:
			assert_eq(
				PopulationMarkers.count_for(population, seed_value, 99), int(population),
				"%0.1f is not a chance, it is a count" % population
			)


func test_no_population_is_a_negative_number_of_animals():
	for population in [-1.0, -0.5, 0.0]:
		assert_eq(PopulationMarkers.count_for(population, 7, CAP), 0)


# -- deterministic -------------------------------------------------------

## Every pick in this codebase is seeded and reproducible; this one too, or
## a chunk would grow and lose a wolf each time it streamed back in.
func test_the_same_chunk_always_gets_the_same_answer():
	for seed_value in 200:
		var first := PopulationMarkers.count_for(0.37, seed_value, CAP)
		assert_eq(
			PopulationMarkers.count_for(0.37, seed_value, CAP), first,
			"seed %d changed its mind" % seed_value
		)


## Different chunks must not all answer alike, or the fraction is just a
## global on/off switch.
func test_different_chunks_do_not_all_answer_the_same():
	var answers := {}
	for seed_value in 200:
		answers[PopulationMarkers.count_for(0.5, seed_value, CAP)] = true
	assert_gt(answers.size(), 1, "half an animal must be one animal SOMETIMES")


# -- and it still protects the frame rate --------------------------------

func test_the_cap_still_holds():
	for seed_value in 50:
		assert_lte(PopulationMarkers.count_for(1000.0, seed_value, CAP), CAP)


func test_a_cap_of_zero_draws_nothing():
	assert_eq(PopulationMarkers.count_for(5.0, 3, 0), 0)


# -- the spawn pass and the reconcile pass must agree ---------------------
#
# CreatureRenderer.marker_count_for is called from TWO places: the spawn
# itself and EarthChunkManager._reconcile_chunk_creatures. They have to use
# the same chunk and the same species salt, or a chunk would gain an animal
# on spawn and lose it on the next reconcile, for ever.

const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")

## The salts spawn_creatures itself passes: herbivores 1, predators 2.
const HERBIVORE_SALT := 1
const PREDATOR_SALT := 2


func test_the_same_chunk_and_salt_give_the_same_count():
	var renderer := CreatureRenderer.new()
	for x in 20:
		var chunk := Vector2i(x, -x)
		assert_eq(
			renderer.marker_count_for(0.37, chunk, PREDATOR_SALT),
			renderer.marker_count_for(0.37, chunk, PREDATOR_SALT),
			"chunk %s changed its mind between the spawn and the reconcile" % chunk
		)


## And the two species must roll independently, or a chunk with a deer in it
## would always have a wolf in it too.
func test_herbivores_and_predators_roll_independently():
	var renderer := CreatureRenderer.new()
	var agreements := 0
	var chunks := 200
	for x in chunks:
		var chunk := Vector2i(x, 0)
		if (
			renderer.marker_count_for(0.5, chunk, HERBIVORE_SALT)
			== renderer.marker_count_for(0.5, chunk, PREDATOR_SALT)
		):
			agreements += 1
	assert_lt(
		agreements, chunks, "the two salts are producing one shared coin flip"
	)


## The real measured densities, through the REAL renderer, over the real
## 25-chunk neighbourhood: predators must appear.
func test_the_real_neighbourhood_really_gets_predators():
	var renderer := CreatureRenderer.new()
	var total := 0
	var index := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			total += renderer.marker_count_for(
				MEASURED_PREDATOR_POPULATIONS[index], Vector2i(dx, dy), PREDATOR_SALT
			)
			index += 1
	assert_gt(total, 0, "a fresh spawn must have something that hunts within reach")
