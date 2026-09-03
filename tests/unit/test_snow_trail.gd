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


# -- the GPU trail mask -------------------------------------------------------
#
# SnowBombShader.set_trail_mask wants a real R8 Texture2D window in WORLD
# pixels, not the tile->float dictionary above -- see docs/concept/
# snow_cover.md's "Footprints" section. build_mask_texture is the bridge: a
# small window centered on the player's own tile, read back as an Image so
# these tests can assert real pixel values rather than trust the GPU.

func test_mask_texture_is_the_requested_size():
	var trail := SnowTrail.new()
	var texture := trail.build_mask_texture(Vector2i(0, 0), 8)
	assert_eq(texture.get_width(), 8)
	assert_eq(texture.get_height(), 8)


func test_an_untrodden_window_is_all_zero():
	var trail := SnowTrail.new()
	var image := trail.build_mask_texture(Vector2i(0, 0), 8).get_image()
	for y in 8:
		for x in 8:
			assert_eq(image.get_pixel(x, y).r, 0.0, "untrodden ground should read as untrodden")


## The window is centered ON the given tile -- so treading the centre tile
## itself must land on the image's own centre pixel.
func test_the_window_is_centred_on_the_given_tile():
	var trail := SnowTrail.new()
	trail.step_on(Vector2i(10, 10))
	var image := trail.build_mask_texture(Vector2i(10, 10), 8).get_image()
	assert_almost_eq(
		image.get_pixel(4, 4).r, trail.tread_at(Vector2i(10, 10)), 1.0 / 255.0,
		"the centre tile should land on the window's own centre pixel"
	)


## A trodden tile off-centre still lands at its own real offset, not just
## the centre -- otherwise every footprint would draw in the same place.
func test_a_trodden_tile_lands_at_its_real_offset():
	var trail := SnowTrail.new()
	trail.step_on(Vector2i(3, 5))  # centre (0,0) + offset (3,5)
	var image := trail.build_mask_texture(Vector2i(0, 0), 16).get_image()
	assert_almost_eq(
		image.get_pixel(8 + 3, 8 + 5).r, trail.tread_at(Vector2i(3, 5)), 1.0 / 255.0
	)


## A tile outside the window must not crash and must not bleed onto a
## neighbouring in-window pixel via wraparound indexing.
func test_a_tile_outside_the_window_does_not_appear_or_crash():
	var trail := SnowTrail.new()
	trail.step_on(Vector2i(1000, 1000))
	var image := trail.build_mask_texture(Vector2i(0, 0), 8).get_image()
	for y in 8:
		for x in 8:
			assert_eq(image.get_pixel(x, y).r, 0.0, "a far-off tread should not appear in this window")


## Real displacement values must survive being packed into an 8-bit channel
## and read back, within one texel step -- not just "something nonzero".
func test_mask_values_track_the_real_tread_value_not_just_presence():
	var trail := SnowTrail.new()
	for step in 2:  # 2 * TREAD_PER_STEP (0.34) = 0.68, short of MAX_TREAD on purpose
		trail.step_on(Vector2i(0, 0))
	var real_tread := trail.tread_at(Vector2i(0, 0))
	assert_gt(real_tread, 0.0)
	assert_lt(real_tread, 1.0, "pick a tread value that is not already saturated, or this proves nothing")
	var image := trail.build_mask_texture(Vector2i(0, 0), 4).get_image()
	assert_almost_eq(image.get_pixel(2, 2).r, real_tread, 1.0 / 255.0)
