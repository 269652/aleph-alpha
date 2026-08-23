extends GutTest

## Footprints in snow: walking displaces it, and fresh snow fills the tracks
## back in (see docs/concept/weather.md).
##
## The same shape as PathScarring, which already wears grass into dirt paths --
## walking marks a tile, and the world slowly undoes it. Snow differs in what
## undoes it: paths recover on their own, tracks are filled by more snow.

const SnowTrail = preload("res://src/world/snow_trail.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")


# -- walking displaces it ----------------------------------------------------

func test_walking_on_snow_leaves_a_track():
	var trail := SnowTrail.new()
	assert_eq(trail.tread_at(Vector2i(3, 4)), 0.0, "untrodden snow is untouched")
	trail.step_on(Vector2i(3, 4))
	assert_gt(trail.tread_at(Vector2i(3, 4)), 0.0)


func test_walking_the_same_line_deepens_the_track():
	var trail := SnowTrail.new()
	trail.step_on(Vector2i(1, 1))
	var once := trail.tread_at(Vector2i(1, 1))
	for step in 5:
		trail.step_on(Vector2i(1, 1))
	assert_gt(trail.tread_at(Vector2i(1, 1)), once)


## Snow only goes so flat: past a point it is trodden bare and further walking
## changes nothing.
func test_a_track_cannot_go_deeper_than_the_snow():
	var trail := SnowTrail.new()
	for step in 200:
		trail.step_on(Vector2i(0, 0))
	assert_lte(trail.tread_at(Vector2i(0, 0)), 1.0)


func test_untrodden_tiles_stay_untouched():
	var trail := SnowTrail.new()
	trail.step_on(Vector2i(5, 5))
	assert_eq(trail.tread_at(Vector2i(6, 5)), 0.0)


# -- snow fills the tracks in ------------------------------------------------

## What undoes a track is more SNOW, not time. A path through grass grows back
## on its own; footprints sit there until it snows again, which is why a trail
## across a field lasts through a clear cold day and is gone after a fall.
func test_fresh_snow_fills_the_tracks_in():
	var trail := SnowTrail.new()
	for step in 10:
		trail.step_on(Vector2i(2, 2))
	var deep := trail.tread_at(Vector2i(2, 2))
	trail.advance(SnowTrail.SECONDS_TO_FILL * 0.5, true)
	assert_lt(trail.tread_at(Vector2i(2, 2)), deep)


func test_tracks_do_not_fade_on_their_own():
	var trail := SnowTrail.new()
	trail.step_on(Vector2i(2, 2))
	var made := trail.tread_at(Vector2i(2, 2))
	trail.advance(SnowTrail.SECONDS_TO_FILL * 4.0, false)
	assert_almost_eq(
		trail.tread_at(Vector2i(2, 2)), made, 0.001,
		"a track should last until it snows again"
	)


## Tracks have to fill in WITHIN a snowfall.
##
## This was twelve real minutes against a weather spell of ten, so a snowfall
## always ended before it could fill anything and tracks cut on the first walk
## stayed for good (reported). A footprint is a shallow depression -- it drifts
## full faster than a whole field is buried.
func test_a_snowfall_fills_its_tracks_before_it_ends():
	assert_lt(
		SnowTrail.SECONDS_TO_FILL, WeatherModel.WEATHER_PERIOD_SECONDS,
		"a snowfall must be able to fill its tracks within one spell"
	)
	assert_lt(
		SnowTrail.SECONDS_TO_FILL, Snowfall.SECONDS_TO_COVER,
		"a footprint should drift full faster than a whole field is buried"
	)


## Walked once, then snowed on for a spell: the track is gone.
func test_a_spell_of_snow_erases_a_walked_trail():
	var trail := SnowTrail.new()
	for step in 4:
		trail.step_on(Vector2i(1, 1))
	var elapsed := 0.0
	while elapsed < WeatherModel.WEATHER_PERIOD_SECONDS:
		trail.advance(10.0, true)
		elapsed += 10.0
	assert_eq(trail.tread_at(Vector2i(1, 1)), 0.0, "a spell of snow should bury a trail")


func test_enough_snow_erases_a_track_completely():
	var trail := SnowTrail.new()
	for step in 20:
		trail.step_on(Vector2i(2, 2))
	trail.advance(SnowTrail.SECONDS_TO_FILL * 3.0, true)
	assert_eq(trail.tread_at(Vector2i(2, 2)), 0.0)


## A filled-in track is forgotten rather than kept at zero forever -- otherwise
## a long walk leaves the map remembering every tile ever stepped on.
func test_filled_tracks_are_forgotten():
	var trail := SnowTrail.new()
	for tile in 50:
		trail.step_on(Vector2i(tile, 0))
	assert_gt(trail.tracked_tile_count(), 0)
	trail.advance(SnowTrail.SECONDS_TO_FILL * 5.0, true)
	assert_eq(trail.tracked_tile_count(), 0, "the map should not remember erased tracks")


# -- what it is for ----------------------------------------------------------

## Tracks are visible: a footprint has to displace enough snow to be seen, or
## the whole feature is a number nobody can read.
func test_a_single_footprint_is_already_visible():
	var trail := SnowTrail.new()
	trail.step_on(Vector2i(0, 0))
	assert_gte(
		trail.tread_at(Vector2i(0, 0)), SnowTrail.VISIBLE_TREAD,
		"one step should already show"
	)
