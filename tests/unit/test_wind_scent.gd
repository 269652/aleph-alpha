extends GutTest

## Smell travels on the wind (see docs/concept/olfaction.md "The wind carries
## it").
##
## `Olfaction` dilutes a smell by the STRAIGHT-LINE distance between a source
## and a nose, which is the still-air case and is the case that never happens:
## `WeatherModel.wind_direction_for` has existed, tested, since the weather
## model was written and had **no production caller at all** -- the world has a
## wind direction that nothing in the running game ever asks for.
##
## This module is what asks. It converts a geometric distance into the distance
## the smell BEHAVES as if it had: shorter downwind, longer upwind. That single
## number is what makes stalking a decision -- come at an animal from downwind
## and you are quiet, come from upwind and you were announced two hundred
## pixels ago.

const WindScent = preload("res://src/world/wind_scent.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const EAST := Vector2.RIGHT
const TILE := float(TerrainRenderer.TILE_SIZE)


# -- which way the smell goes ------------------------------------------------


## The headline. Two animals the same distance from the player, one downwind
## and one upwind: only the downwind one is inside smelling range.
func test_a_smell_reaches_further_downwind_than_upwind():
	var source := Vector2.ZERO
	var downwind := Vector2(160.0, 0.0)
	var upwind := Vector2(-160.0, 0.0)
	var carried := WindScent.effective_distance_tiles(source, downwind, EAST, 1.0, TILE)
	var against := WindScent.effective_distance_tiles(source, upwind, EAST, 1.0, TILE)
	assert_lt(carried, against, "a downwind nose should be effectively closer")


## Across the wind is neither: it should land between the two, not at one end.
func test_crosswind_sits_between_downwind_and_upwind():
	var source := Vector2.ZERO
	var downwind := WindScent.effective_distance_tiles(source, Vector2(160, 0), EAST, 1.0, TILE)
	var across := WindScent.effective_distance_tiles(source, Vector2(0, 160), EAST, 1.0, TILE)
	var upwind := WindScent.effective_distance_tiles(source, Vector2(-160, 0), EAST, 1.0, TILE)
	assert_gt(across, downwind)
	assert_lt(across, upwind)


## In still air the wind must change nothing at all, so every existing
## still-air result -- and every test that assumes one -- is unaffected.
func test_still_air_leaves_the_geometry_alone():
	var source := Vector2.ZERO
	var nose := Vector2(160.0, 0.0)
	assert_almost_eq(
		WindScent.effective_distance_tiles(source, nose, EAST, 0.0, TILE), 160.0 / TILE, 0.0001
	)


func test_no_wind_direction_leaves_the_geometry_alone():
	assert_almost_eq(
		WindScent.effective_distance_tiles(
			Vector2.ZERO, Vector2(160.0, 0.0), Vector2.ZERO, 1.0, TILE
		),
		160.0 / TILE,
		0.0001
	)


## A stronger wind carries further: the same downwind nose is effectively
## nearer in a gale than in a breeze.
func test_a_stronger_wind_carries_a_smell_further():
	var source := Vector2.ZERO
	var nose := Vector2(160.0, 0.0)
	var breeze := WindScent.effective_distance_tiles(source, nose, EAST, 0.3, TILE)
	var gale := WindScent.effective_distance_tiles(source, nose, EAST, 1.0, TILE)
	assert_lt(gale, breeze)


## The wind never carries a smell to a nose standing on the source, and never
## produces a negative or zero distance that would divide by nothing further
## down the chain.
func test_the_effective_distance_is_never_negative():
	for degrees in 36:
		var angle := deg_to_rad(float(degrees) * 10.0)
		var nose := Vector2(cos(angle), sin(angle)) * 200.0
		for strength_step in 5:
			var strength := float(strength_step) / 4.0
			var tiles := WindScent.effective_distance_tiles(
				Vector2.ZERO, nose, EAST, strength, TILE
			)
			assert_gte(tiles, 0.0)


func test_a_nose_on_the_source_is_at_zero_whatever_the_wind():
	assert_eq(WindScent.effective_distance_tiles(Vector2.ZERO, Vector2.ZERO, EAST, 1.0, TILE), 0.0)


## Upwind never becomes free: a smell straight into the wind still reaches
## SOME distance, because a real plume is turbulent and not a laser.
func test_a_smell_still_reaches_a_little_way_upwind():
	var straight_upwind := WindScent.effective_distance_tiles(
		Vector2.ZERO, Vector2(-16.0, 0.0), EAST, 1.0, TILE
	)
	assert_lt(straight_upwind, INF)
	assert_gt(straight_upwind, 1.0, "one tile upwind should read as further than one tile")


# -- reading the real weather ------------------------------------------------


## The weather model's wind strength is not a 0..1 fraction -- it is a visual
## energy multiplier running from 1.0 (clear) to 1.8 (storm), which every
## wind-reactive VISUAL already consumes. Converting it here, once, is what
## stops every caller inventing its own normalisation.
func test_worse_weather_blows_harder():
	var weather := WeatherModel.new()
	var previous := -1.0
	for state in ["clear", "cloudy", "rain", "storm"]:
		var advection := WindScent.advection_strength(weather.wind_strength_for(state))
		assert_gt(advection, previous, "%s should blow harder than the state before it" % state)
		previous = advection


## Even a clear day has a real breeze in it: a scent mechanic that only existed
## in bad weather would be off for the majority of a session (clear is 50% of
## rolls, see WeatherModel.CLEAR_THRESHOLD).
func test_even_a_clear_day_carries_a_smell():
	var weather := WeatherModel.new()
	assert_gt(WindScent.advection_strength(weather.wind_strength_for("clear")), 0.0)


func test_advection_strength_stays_in_range():
	var weather := WeatherModel.new()
	for state in ["clear", "cloudy", "rain", "storm", "not_a_weather_state"]:
		var advection := WindScent.advection_strength(weather.wind_strength_for(state))
		assert_between(advection, 0.0, 1.0)


# -- what the player is told -------------------------------------------------


## The player cannot play around a wind they cannot read. `is_downwind_of`
## is what the HUD/weather glass asks -- "is this animal going to smell me?"
func test_an_animal_east_of_the_player_is_downwind_in_an_easterly_drift():
	assert_true(WindScent.is_downwind_of(Vector2.ZERO, Vector2(160.0, 0.0), EAST))
	assert_false(WindScent.is_downwind_of(Vector2.ZERO, Vector2(-160.0, 0.0), EAST))


## The wind's own name, for the weather glass. A wind is named for where it
## comes FROM -- an "easterly" blows out of the east, toward the west -- which
## is the one piece of real-world convention a player will bring with them.
func test_the_wind_is_named_for_where_it_comes_from():
	assert_eq(WindScent.wind_name(Vector2.RIGHT), "westerly")
	assert_eq(WindScent.wind_name(Vector2.LEFT), "easterly")
	assert_eq(WindScent.wind_name(Vector2.UP), "southerly")
	assert_eq(WindScent.wind_name(Vector2.DOWN), "northerly")


func test_every_direction_gets_a_name():
	for degrees in 72:
		var angle := deg_to_rad(float(degrees) * 5.0)
		var name := WindScent.wind_name(Vector2(cos(angle), sin(angle)))
		assert_false(name.is_empty(), "%d degrees has no name" % (degrees * 5))
