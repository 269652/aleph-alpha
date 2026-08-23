extends GutTest

## Flies: the creature that wants what everything else avoids (see
## docs/concept/olfaction.md).
##
## They exist to make rot MEAN something. Without them a rotting windfall is
## just food nobody wants, which is indistinguishable from no food at all --
## with them it is somebody's larder, and a cloud of flies is the player's
## visible cue that something has gone over.

const Flies = preload("res://src/gameplay/flies.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const ScentForaging = preload("res://src/gameplay/scent_foraging.gd")


# -- what brings them ---------------------------------------------------------

## The whole point: they come for what a deer walks away from.
func test_flies_gather_on_what_others_avoid():
	var rotten := Olfaction.fruit_mixture("apple", 0.0)
	assert_gt(Flies.swarm_size_for(rotten, 0.0), 0, "rot should draw flies")
	assert_lt(
		Olfaction.attraction_to("deer", rotten, 0.0), 0.0,
		"...the same rot a deer avoids"
	)


func test_fresh_fruit_draws_no_swarm():
	var ripe := Olfaction.fruit_mixture("apple", 1.0)
	assert_eq(Flies.swarm_size_for(ripe, 0.0), 0, "fresh fruit should not be blown")


## The swarm grows as the thing goes further over -- so the cloud is a reading
## of how rotten something is, not a switch.
func test_the_swarm_grows_as_the_fruit_goes_over():
	var previous := -1
	for step in 12:
		var freshness := 1.0 - float(step) / 11.0
		var size := Flies.swarm_size_for(Olfaction.fruit_mixture("apple", freshness), 0.0)
		assert_gte(size, previous, "the swarm shrank as the fruit got worse")
		previous = size


func test_a_swarm_is_bounded():
	for step in 20:
		var freshness := 1.0 - float(step) / 19.0
		assert_lte(
			Flies.swarm_size_for(Olfaction.fruit_mixture("apple", freshness), 0.0),
			Flies.MAX_SWARM
		)


## Distance thins them, like any other smell.
func test_fewer_flies_find_it_from_further_away():
	var rotten := Olfaction.fruit_mixture("apple", 0.0)
	assert_gt(
		Flies.swarm_size_for(rotten, 0.0),
		Flies.swarm_size_for(rotten, Olfaction.MAX_RANGE_TILES * 0.8)
	)


# -- they behave like a swarm -------------------------------------------------

## They orbit their source rather than flying to a point and stopping, which is
## what makes a cloud read as a cloud.
func test_a_fly_circles_its_source():
	var angles := {}
	for step in 12:
		var offset := Flies.swarm_offset(0, float(step) * 0.2)
		angles[snappedf(offset.angle(), 0.4)] = true
	assert_gt(angles.size(), 3, "the swarm should circle, not sit")


func test_the_swarm_stays_over_its_source():
	for index in Flies.MAX_SWARM:
		for step in 20:
			assert_lte(
				Flies.swarm_offset(index, float(step) * 0.3).length(),
				Flies.SWARM_RADIUS_PX + 0.01
			)


## Each fly in a swarm is somewhere different, or it reads as one fly.
func test_the_flies_in_a_swarm_are_spread_out():
	var places := {}
	for index in Flies.MAX_SWARM:
		places[snappedf(Flies.swarm_offset(index, 1.0).angle(), 0.3)] = true
	assert_gt(places.size(), 2, "the whole swarm is in one spot")


## Flies forage by smell like everything else with a nose -- they are not a
## special case bolted on.
func test_a_fly_uses_the_same_nose_as_everything_else():
	assert_true(ScentForaging.forages_by_smell("fly"))
