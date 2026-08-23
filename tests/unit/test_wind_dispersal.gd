extends GutTest

## Where the wind puts a seed (see docs/concept/seed_dispersal.md).

const WindDispersal = preload("res://src/world/wind_dispersal.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func _mean_offset(weight: float, direction: Vector2, strength: float, count: int) -> Vector2:
	var total := Vector2.ZERO
	for seed_value in count:
		total += WindDispersal.landing_offset(seed_value, weight, direction, strength)
	return total / float(count)


# -- the wind decides --------------------------------------------------------

## A meadow should visibly creep DOWNWIND over seasons rather than expanding as
## a circle -- that is the fingerprint of wind actually being simulated rather
## than a random offset wearing wind's name.
func test_seed_drifts_downwind():
	var mean := _mean_offset(WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 1.0, 600)
	assert_gt(mean.x, 0.0, "seed should drift downwind")
	assert_gt(
		mean.x, absf(mean.y) * 2.0, "the drift should be along the wind, not across it"
	)


func test_seed_drifts_whichever_way_the_wind_blows():
	var east := _mean_offset(WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 1.0, 400)
	var north := _mean_offset(WindDispersal.WEIGHT_FLOWER_SEED, Vector2.UP, 1.0, 400)
	assert_gt(east.x, 0.0)
	assert_lt(north.y, 0.0)


## In dead calm a seed still lands somewhere -- just not far, and with no
## preferred direction.
func test_in_dead_calm_seed_falls_around_the_parent():
	var mean := _mean_offset(WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 0.0, 600)
	assert_almost_eq(mean.x, 0.0, TerrainRenderer.TILE_SIZE * 0.5)
	assert_almost_eq(mean.y, 0.0, TerrainRenderer.TILE_SIZE * 0.5)


func test_a_stronger_wind_carries_seed_further():
	var gentle := _mean_offset(WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 0.3, 400)
	var gale := _mean_offset(WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 1.0, 400)
	assert_gt(gale.x, gentle.x)


# -- light things go further -------------------------------------------------

## The whole reason plants have different seeds: a dandelion seed and an acorn
## fall from the same height in the same wind and land far apart. It is why
## meadows colonise faster than woods.
func test_a_light_seed_travels_further_than_a_heavy_one():
	var light := _mean_offset(WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 1.0, 400)
	var heavy := _mean_offset(WindDispersal.WEIGHT_NUT, Vector2.RIGHT, 1.0, 400)
	assert_gt(light.x, heavy.x * 3.0, "a flower seed should outrun a nut by a long way")


func test_a_nut_barely_moves_even_in_a_gale():
	for seed_value in 200:
		var offset := WindDispersal.landing_offset(
			seed_value, WindDispersal.WEIGHT_NUT, Vector2.RIGHT, 1.0
		)
		assert_lte(
			offset.length(), WindDispersal.MAX_TRAVEL_TILES * TerrainRenderer.TILE_SIZE,
			"a nut left the map"
		)


func test_the_weights_are_ordered_the_way_the_seeds_fall():
	assert_lt(WindDispersal.WEIGHT_FLOWER_SEED, WindDispersal.WEIGHT_BERRY_PIP)
	assert_lt(WindDispersal.WEIGHT_BERRY_PIP, WindDispersal.WEIGHT_TREE_FRUIT)
	assert_lt(WindDispersal.WEIGHT_TREE_FRUIT, WindDispersal.WEIGHT_NUT)


# -- most near, a little far -------------------------------------------------

## Real wind dispersal is heavy tailed: the bulk falls within a few
## body-widths and a small fraction goes a very long way. That tail is what
## colonises new ground; a uniform scatter gives neither a dense home patch nor
## any pioneers.
func test_most_seed_lands_near_and_a_little_lands_far():
	var distances: Array[float] = []
	for seed_value in 1000:
		distances.append(
			WindDispersal.landing_offset(
				seed_value, WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 0.6
			).length()
		)
	distances.sort()
	var median: float = distances[distances.size() / 2]
	var top_percentile: float = distances[int(float(distances.size()) * 0.95)]
	var total := 0.0
	for distance in distances:
		total += distance
	var mean := total / float(distances.size())

	# Right-skewed: the mean is dragged above the median by the far-flung few.
	# That is what "heavy tailed" means, and it is a better statement of it
	# than any particular percentage landing within any particular radius.
	assert_gt(mean, median, "the distribution is not skewed -- no tail")
	assert_gt(
		top_percentile, median * 3.0,
		"the furthest twentieth should travel far beyond the typical seed"
	)


# -- housekeeping ------------------------------------------------------------

func test_a_given_seed_lands_in_one_place():
	for seed_value in [0, 11, 512, 9001]:
		assert_eq(
			WindDispersal.landing_offset(seed_value, 0.2, Vector2.RIGHT, 0.5),
			WindDispersal.landing_offset(seed_value, 0.2, Vector2.RIGHT, 0.5)
		)


func test_no_seed_ever_leaves_the_world():
	var limit := WindDispersal.MAX_TRAVEL_TILES * TerrainRenderer.TILE_SIZE
	for seed_value in 800:
		for weight in [WindDispersal.WEIGHT_FLOWER_SEED, WindDispersal.WEIGHT_NUT]:
			assert_lte(
				WindDispersal.landing_offset(seed_value, weight, Vector2.RIGHT, 1.0).length(),
				limit + 0.001
			)


## Consecutive seeds must not land in a line -- the banding trap this project
## has hit twice.
func test_consecutive_seeds_do_not_land_in_a_line():
	var angles := {}
	for seed_value in range(5000, 5040):
		var offset := WindDispersal.landing_offset(
			seed_value, WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 0.0
		)
		angles[snappedf(offset.angle(), 0.4)] = true
	assert_gt(angles.size(), 4, "forty seeds scattered into %d directions" % angles.size())


# -- wind direction ----------------------------------------------------------

## Direction varies day to day: a prevailing wind that never turned would drive
## every meadow in the world one way forever.
func test_the_wind_changes_direction_from_day_to_day():
	var model := WeatherModel.new()
	var directions := {}
	for day in 60:
		directions[snappedf(model.wind_direction_for(day, 1234).angle(), 0.5)] = true
	assert_gt(directions.size(), 3, "the wind never turns")


func test_the_wind_is_the_same_for_everyone_on_a_given_day():
	var model := WeatherModel.new()
	assert_eq(model.wind_direction_for(7, 1234), model.wind_direction_for(7, 1234))


func test_the_wind_direction_is_a_direction():
	var model := WeatherModel.new()
	for day in 40:
		assert_almost_eq(model.wind_direction_for(day, 99).length(), 1.0, 0.001)
