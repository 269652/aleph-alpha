extends GutTest

## What it takes for a seed lying on the ground to become a sapling (see
## docs/concept/seed_dispersal.md).

const SeedGermination = preload("res://src/world/seed_germination.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")


# -- a seed needs earth ------------------------------------------------------

## Rain alone roots nothing: the seed has to be lying on ground that can
## actually take it.
func test_a_seed_needs_earth_under_it():
	assert_false(SeedGermination.can_germinate("ocean", 0.0))
	assert_false(SeedGermination.can_germinate("mountain", 0.0))
	assert_true(SeedGermination.can_germinate("grassland", 0.0))


func test_water_is_never_a_seedbed_however_bare():
	for bareness in [0.0, 0.5, 1.0]:
		assert_false(SeedGermination.can_germinate("ocean", bareness))


# -- bare earth beats turf ---------------------------------------------------

## True, and the reason disturbance drives succession: a seed that lands in
## thick grass mostly fails, and the same seed on scraped ground mostly takes.
## It is what makes clearing a patch the way a player deliberately starts a
## wood.
func test_bare_earth_is_a_far_better_seedbed_than_turf():
	var bare := SeedGermination.germination_chance("grassland", 1.0)
	var turf := SeedGermination.germination_chance("grassland", 0.0)
	assert_gt(bare, turf, "bare ground should still be the better seedbed")


## Grass is a perfectly good seedbed, both its shades -- the light and dark
## speckle is one tile, not two kinds of ground. Seed takes in a meadow all the
## time, which is how meadows exist.
##
## An earlier pass had turf at 0.08 against bare earth's 0.75, which made grass
## a near-failure and would have meant nothing ever seeded except on a path.
func test_grass_is_a_perfectly_good_seedbed():
	var turf := SeedGermination.germination_chance("grassland", 0.0)
	var bare := SeedGermination.germination_chance("grassland", 1.0)
	assert_gt(turf, 0.0, "a meadow that can never seed itself never changes")
	assert_gte(
		turf, bare * 0.5,
		"grass should be a workable seedbed, not a near-failure next to bare earth"
	)


func test_more_bare_ground_is_always_at_least_as_good():
	var previous := -1.0
	for step in 20:
		var chance := SeedGermination.germination_chance("grassland", float(step) / 19.0)
		assert_gte(chance, previous)
		previous = chance


func test_ground_that_cannot_take_a_seed_gives_no_chance_at_all():
	for biome in ["ocean", "mountain", "desert", "tundra"]:
		assert_eq(SeedGermination.germination_chance(biome, 1.0), 0.0, biome)


func test_a_chance_is_always_a_chance():
	for biome in ["grassland", "forest", "rainforest", "ocean"]:
		for step in 10:
			var chance := SeedGermination.germination_chance(biome, float(step) / 9.0)
			assert_between(chance, 0.0, 1.0)


# -- rain is the trigger -----------------------------------------------------

## A seed lies there until it is watered. That is what makes rain a thing the
## player waits for rather than a weather texture.
func test_rain_is_what_starts_a_seed_rooting():
	var model := WeatherModel.new()
	assert_true(SeedGermination.is_rooting_weather(model.soil_moisture("rain")))
	assert_false(SeedGermination.is_rooting_weather(model.soil_moisture("clear")))


## The threshold IS what rain delivers, not a hair above it. Set higher, only
## storms root anything and ordinary rain falls on seed that never takes --
## which is what happened the first time.
func test_the_rooting_threshold_is_exactly_what_rain_delivers():
	var model := WeatherModel.new()
	assert_eq(SeedGermination.ROOTING_MOISTURE, model.soil_moisture("rain"))


## A storm roots seed too -- it is wetter than rain, not drier.
func test_a_storm_roots_seed_as_well():
	var model := WeatherModel.new()
	assert_true(SeedGermination.is_rooting_weather(model.soil_moisture("storm")))


## ...and merely overcast does not.
func test_cloudy_weather_does_not_root_seed():
	var model := WeatherModel.new()
	assert_false(SeedGermination.is_rooting_weather(model.soil_moisture("cloudy")))


func test_drier_ground_than_the_threshold_never_roots():
	assert_false(SeedGermination.is_rooting_weather(SeedGermination.ROOTING_MOISTURE - 0.01))
	assert_true(SeedGermination.is_rooting_weather(SeedGermination.ROOTING_MOISTURE))


# -- a sapling is not a seed --------------------------------------------------

## Once it has rooted it is not food any more, so a bird that would have eaten
## the seed leaves the seedling alone.
func test_a_rooted_seed_is_no_longer_edible():
	assert_true(SeedGermination.is_edible_seed(false))
	assert_false(SeedGermination.is_edible_seed(true))
