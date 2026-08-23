extends GutTest

## A flower's own life through its season: opening, full, then withering (see
## docs/concept/flora.md).
##
## Distinct from NECTAR, which is a bloom's current contents and refills in
## about a minute. A drained flower is a full flower that has just been
## visited; a withered one is a flower at the end of its life. Treating the
## first as the second stopped pollinators revisiting the plants they had
## drained -- which is most of what a local pollinator does.

const FlowerBloom = preload("res://src/world/flower_bloom.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- in season and out -------------------------------------------------------

func test_a_flower_out_of_its_season_has_no_bloom_at_all():
	# Lavender blooms in summer; midwinter is not its season.
	assert_lt(FlowerBloom.phase_at("lavender", 0.85), 0.0)


func test_a_flower_in_its_season_has_a_phase():
	var cycle := SeasonCycle.new()
	var found := false
	for step in 200:
		var year_fraction := float(step) / 199.0
		if not FlowerSpecies.is_in_bloom("lavender", cycle.season_at(year_fraction * SeasonCycle.SECONDS_PER_YEAR)):
			continue
		found = true
		assert_between(FlowerBloom.phase_at("lavender", year_fraction), 0.0, 1.0)
	assert_true(found, "lavender never blooms at all")


## Every species opens and withers somewhere -- a species that is never in
## bloom, or never withers, is not modelled.
func test_every_species_opens_and_withers():
	for species in FlowerSpecies.IDS:
		var opened := false
		var withered := false
		for step in 400:
			var year_fraction := float(step) / 399.0
			var phase := FlowerBloom.phase_at(species, year_fraction)
			if phase < 0.0:
				continue
			opened = true
			if FlowerBloom.is_withered(species, year_fraction):
				withered = true
		assert_true(opened, "%s never opens" % species)
		assert_true(withered, "%s never withers" % species)


# -- withering comes at the END ----------------------------------------------

## "Spent" means withered, as in late in the flower's own season -- and WHICH
## part of the year that is depends on the flower. A crocus is over before a
## rose has opened.
func test_a_flower_withers_at_the_end_of_its_own_season():
	for species in FlowerSpecies.IDS:
		var first_withered := 2.0
		var last_fresh := -1.0
		for step in 400:
			var year_fraction := float(step) / 399.0
			var phase := FlowerBloom.phase_at(species, year_fraction)
			if phase < 0.0:
				continue
			if FlowerBloom.is_withered(species, year_fraction):
				first_withered = minf(first_withered, phase)
			else:
				last_fresh = maxf(last_fresh, phase)
		assert_gt(first_withered, 0.5, "%s withers before its season is half done" % species)
		assert_gt(last_fresh, 0.0, "%s is withered its whole life" % species)


func test_a_newly_opened_flower_is_not_withered():
	for species in FlowerSpecies.IDS:
		assert_false(FlowerBloom.is_withered_at_phase(0.0), species)


func test_the_wither_point_leaves_most_of_the_season_fresh():
	assert_gt(FlowerBloom.WITHER_PHASE, 0.5)
	assert_lt(FlowerBloom.WITHER_PHASE, 1.0)


# -- species differ ----------------------------------------------------------

## Different flowers are over at different times, which is the whole reason
## a meadow looks different in May and September.
func test_different_species_wither_at_different_times():
	var wither_points := {}
	for species in FlowerSpecies.IDS:
		for step in 400:
			var year_fraction := float(step) / 399.0
			if FlowerBloom.phase_at(species, year_fraction) < 0.0:
				continue
			if FlowerBloom.is_withered(species, year_fraction):
				wither_points[species] = snappedf(year_fraction, 0.05)
				break
	var distinct := {}
	for species in wither_points:
		distinct[wither_points[species]] = true
	assert_gt(distinct.size(), 1, "every flower in the world withers on the same day")
