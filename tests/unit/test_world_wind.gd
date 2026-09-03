extends GutTest

## The wind reaching the running game (see docs/concept/olfaction.md "The wind
## carries it").
##
## `WeatherModel.wind_direction_for` has been written, documented and tested
## since the weather model existed, and — verified by searching every `.gd` in
## `src/` and `scenes/` — had **no production caller at all**. Seeds dispersed,
## grass swayed and flowers advertised without anything ever asking which way
## the wind was blowing.
##
## These pin the glue that makes it a real quantity in the world: one place
## that knows the day and the region, one cached answer every creature can ask
## for, and the conversion from the weather model's visual energy multiplier
## into the 0..1 advection strength `WindScent` wants.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const WindScent = preload("res://src/world/wind_scent.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	add_child(creatures_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func after_each():
	tile_map_layer.queue_free()
	entities_parent.queue_free()
	creatures_parent.queue_free()


## Before anything tells it otherwise the world is in still air, which leaves
## every smell exactly where the geometry puts it — so a chunk manager that is
## never told about the weather behaves the way it always did.
func test_a_fresh_world_is_still():
	assert_eq(manager.wind_advection_strength(), 0.0)


func test_refreshing_the_wind_gives_it_a_real_direction():
	var weather := WeatherModel.new()
	manager.refresh_wind(Vector2.ZERO, weather.wind_strength_for("clear"))
	assert_almost_eq(manager.wind_direction().length(), 1.0, 0.001)


## The advection strength is the weather model's own energy multiplier put
## through the one conversion `WindScent` owns, rather than each caller
## normalising it its own way.
func test_the_advection_strength_is_the_weather_models_wind_converted_once():
	var weather := WeatherModel.new()
	for state in ["clear", "cloudy", "rain", "storm"]:
		var raw := weather.wind_strength_for(state)
		manager.refresh_wind(Vector2.ZERO, raw)
		assert_almost_eq(
			manager.wind_advection_strength(), WindScent.advection_strength(raw), 0.0001
		)


## `WeatherModel.wind_direction_for` walks the whole day history to get today's
## heading — it is a slow function called from a per-creature, per-frame path,
## so the answer has to be cached rather than recomputed. Same inputs, same
## answer, and no dependence on how many times it was asked.
func test_the_direction_is_stable_while_the_day_and_region_are():
	var weather := WeatherModel.new()
	manager.refresh_wind(Vector2.ZERO, weather.wind_strength_for("clear"))
	var first := manager.wind_direction()
	for repeat in 20:
		manager.refresh_wind(Vector2.ZERO, weather.wind_strength_for("storm"))
	assert_eq(manager.wind_direction(), first, "the wind must not spin because it was asked twice")


## ...but it does turn as the world ages, or it is a fixed prevailing wind and
## the whole point of `WIND_TURN_PER_DAY` is lost.
func test_the_wind_turns_as_the_world_ages():
	var weather := WeatherModel.new()
	manager.refresh_wind(Vector2.ZERO, weather.wind_strength_for("clear"))
	var early := manager.wind_direction()

	manager.advance_world_age(EarthChunkManager.WEATHER_PERIOD_SECONDS * 40.0)
	manager.refresh_wind(Vector2.ZERO, weather.wind_strength_for("clear"))

	assert_ne(manager.wind_direction(), early)
