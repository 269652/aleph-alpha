extends GutTest

## Where the wind puts a seed (see docs/concept/seed_dispersal.md).

const WindDispersal = preload("res://src/world/wind_dispersal.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const FlowerEstablishment = preload("res://src/world/flower_establishment.gd")


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


# -- the prevailing wind -----------------------------------------------------
#
# The day's wind walks; the PREVAILING wind is the long-run one a region's
# landscape was shaped by. Worldgen needs it: a baked meadow has to be what the
# wind already did (see concept/flora.md#the-meadow-you-arrive-to-is-what-the-
# wind-already-did), and "what the wind already did" is not one particular
# day's weather.

func test_the_prevailing_wind_is_a_direction():
	var model := WeatherModel.new()
	for region_seed in [0, 17, 4242, -99]:
		assert_almost_eq(model.prevailing_wind_direction(region_seed).length(), 1.0, 0.001)


func test_the_prevailing_wind_is_the_same_every_time_you_ask():
	var model := WeatherModel.new()
	assert_eq(
		model.prevailing_wind_direction(1234), model.prevailing_wind_direction(1234)
	)


## Every region gets its own, or every meadow in the world leans the same way
## -- which is the thing a prevailing wind is supposed to avoid being.
func test_each_region_has_its_own_prevailing_wind():
	var model := WeatherModel.new()
	var directions := {}
	for region_seed in 40:
		directions[snappedf(model.prevailing_wind_direction(region_seed * 977).angle(), 0.5)] = true
	assert_gt(directions.size(), 4, "the whole world shares one wind (%d directions)" % directions.size())


## The day's wind is a walk AROUND the region's prevailing wind, not a walk
## from an arbitrary shared zero. Pinned at day one, before the walk has had
## anywhere to go.
func test_the_days_wind_starts_from_the_regions_prevailing_wind():
	var model := WeatherModel.new()
	for region_seed in [7, 555, 90210]:
		var swing: float = absf(
			model.wind_direction_for(0, region_seed).angle_to(
				model.prevailing_wind_direction(region_seed)
			)
		)
		assert_lte(
			swing, WeatherModel.WIND_TURN_PER_DAY + 0.001,
			"day one blew further from the prevailing wind than a day's turn allows"
		)


## The bug that made this necessary: the walk used to start at angle 0 for
## EVERY region, so on day one the wind blew east across the entire world.
func test_regions_do_not_all_share_the_same_wind_on_day_one():
	var model := WeatherModel.new()
	var directions := {}
	for region_seed in 40:
		directions[snappedf(model.wind_direction_for(0, region_seed * 977).angle(), 0.5)] = true
	assert_gt(directions.size(), 4, "day one blew the same way everywhere (%d directions)" % directions.size())


## Some ground is windier than other ground, but nowhere is a permanent dead
## calm (which would mean a meadow there could never lean anywhere) and
## nowhere is a permanent gale.
func test_a_regions_prevailing_wind_is_a_real_wind_everywhere():
	var model := WeatherModel.new()
	var strengths := {}
	for region_seed in 40:
		var strength: float = model.prevailing_wind_strength(region_seed * 977)
		assert_gt(strength, 0.0, "a region with no wind at all")
		assert_lte(strength, 1.0, "a region blowing harder than a gale")
		strengths[snappedf(strength, 0.05)] = true
	assert_gt(strengths.size(), 3, "every region is exactly as windy as every other")


# -- how hard it blows, for a seed -------------------------------------------
#
# wind_strength_for is a SHADER pace multiplier (1.0 baseline, up to 1.8) --
# WindDispersal wants 0 calm to 1 gale. Two readings of the same sky, kept
# ordered together so they cannot drift into disagreeing about which day is
# windier.

func test_dispersal_strength_is_calm_to_gale():
	var model := WeatherModel.new()
	for state in WeatherModel.STATES:
		var strength: float = model.dispersal_strength_for(state)
		assert_gte(strength, 0.0, "%s blew backwards" % state)
		assert_lte(strength, 1.0, "%s blew harder than a gale" % state)


func test_dispersal_strength_ranks_the_sky_the_same_way_the_shader_does():
	var model := WeatherModel.new()
	for i in WeatherModel.STATES.size() - 1:
		var calmer: String = WeatherModel.STATES[i]
		var rougher: String = WeatherModel.STATES[i + 1]
		assert_eq(
			model.dispersal_strength_for(calmer) < model.dispersal_strength_for(rougher),
			model.wind_strength_for(calmer) < model.wind_strength_for(rougher),
			"the two readings disagree about whether %s is windier than %s" % [rougher, calmer]
		)


## A clear day is half of all weather (see CLEAR_THRESHOLD). If it disperses
## nothing, then for half the world's time the downwind term is multiplied by
## zero and every meadow spreads as a circle -- which is the isotropic
## behaviour the whole wind model exists to replace.
func test_even_a_clear_day_carries_seed_somewhere():
	var model := WeatherModel.new()
	assert_gt(model.dispersal_strength_for("clear"), 0.0)


func test_an_unknown_sky_still_answers_with_a_real_wind():
	var model := WeatherModel.new()
	var fallback: float = model.dispersal_strength_for("not_a_sky")
	assert_gte(fallback, 0.0)
	assert_lte(fallback, 1.0)


# -- a plume drifts in still air; an acorn does not --------------------------
#
# Reported live: seed "should be carried a bit further by the wind and birds so
# it leaves more space between individual flowers". The downwind term already
# scaled with the seed's lightness; the calm scatter did not, so on a still day
# a plumed seed and an acorn fell into the same little circle. That is the case
# a meadow is actually generated under -- a prevailing wind is a breeze, not a
# gale -- so it was the term deciding how far apart flowers ended up standing.

func _mean_distance(weight: float, strength: float, count: int) -> float:
	var total := 0.0
	for seed_value in count:
		total += WindDispersal.landing_offset(
			seed_value, weight, Vector2.RIGHT, strength
		).length()
	return total / float(count) / float(TerrainRenderer.TILE_SIZE)


## Still air is not still: a plumed seed goes somewhere on the faintest
## movement of it, which is what the plume is FOR.
func test_in_still_air_a_plumed_seed_drifts_further_than_an_acorn():
	var plume := _mean_distance(WindDispersal.WEIGHT_FLOWER_SEED, 0.0, 500)
	var acorn := _mean_distance(WindDispersal.WEIGHT_NUT, 0.0, 500)
	assert_gt(plume, acorn * 1.5, "a dandelion seed and an acorn fell alike (%.2f vs %.2f tiles)" % [plume, acorn])


## And the other side of it, unchanged: an acorn drops within a crown-width
## whatever the weather. This is the behaviour the calm scatter always had for
## a nut, pinned so making the plume drift further cannot quietly drag the nut
## along with it.
func test_an_acorn_still_drops_within_a_crown_width_in_still_air():
	for seed_value in 300:
		var drop := WindDispersal.landing_offset(
			seed_value, WindDispersal.WEIGHT_NUT, Vector2.RIGHT, 0.0
		).length() / float(TerrainRenderer.TILE_SIZE)
		assert_lte(drop, 1.25, "an acorn rolled %.2f tiles in dead calm" % drop)


## Far enough to matter: on a still day a flower seed has to clear the
## establishment gate's own spacing reasonably often, or a lineage simply
## piles up on its parent and one plant is all that ever grows there. Ties the
## two constants together rather than leaving each eyeballed on its own.
func test_still_air_carries_flower_seed_clear_of_its_parent_often_enough():
	var cleared := 0
	var total := 400
	for seed_value in total:
		var drift := WindDispersal.landing_offset(
			seed_value, WindDispersal.WEIGHT_FLOWER_SEED, Vector2.RIGHT, 0.0
		).length() / float(TerrainRenderer.TILE_SIZE)
		if drift >= FlowerEstablishment.MIN_SPACING_TILES:
			cleared += 1
	assert_gt(
		float(cleared) / float(total), 0.35,
		"only %d of %d seeds cleared the parent in still air" % [cleared, total]
	)
