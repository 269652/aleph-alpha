extends GutTest

## Snow as a per-tile overlay, so footprints can be carved out of it (see
## docs/concept/weather.md).
##
## Snow started as a tint on the whole ground layer, which cannot express "this
## tile is trodden and that one is not" -- the tint is one number for the world.
## Making it a layer of tiles is what lets a trail through a field exist at all.

const SnowLayer = preload("res://src/rendering/snow_layer.gd")
const SnowTrail = preload("res://src/world/snow_trail.gd")

var layer: SnowLayer


func before_each():
	layer = SnowLayer.new()


# -- the art -----------------------------------------------------------------

## One tile per depth band, so ground goes from bare through a dusting to full
## cover rather than snapping between two states.
func test_there_is_a_tile_for_every_depth_band():
	var tile_set := layer.build_tile_set()
	assert_not_null(tile_set)
	assert_gte(SnowLayer.DEPTH_BANDS, 3, "bare, a dusting and cover at the very least")


## Deeper snow is whiter: the bands have to actually differ, or the gradation
## is a number nobody can see.
func test_deeper_snow_is_whiter():
	var previous := -1.0
	for band in SnowLayer.DEPTH_BANDS:
		var whiteness := _whiteness(layer.build_band_image(band))
		assert_gt(whiteness, previous, "band %d is no whiter than the one below" % band)
		previous = whiteness


## Snow is not a flat white rectangle -- it has grain, or a covered field reads
## as a hole in the world.
func test_snow_has_some_texture():
	var image := layer.build_band_image(SnowLayer.DEPTH_BANDS - 1)
	var shades := {}
	for y in image.get_height():
		for x in image.get_width():
			shades[snappedf(image.get_pixel(x, y).v, 0.02)] = true
	assert_gt(shades.size(), 1, "flat white is not snow")


# -- which band a tile gets --------------------------------------------------

func test_bare_ground_gets_no_snow():
	assert_eq(layer.band_for(0.0, 0.0), -1, "no snow means no tile at all")


func test_deep_snow_gets_the_deepest_band():
	assert_eq(layer.band_for(1.0, 0.0), SnowLayer.DEPTH_BANDS - 1)


func test_more_snow_never_gets_a_shallower_band():
	var previous := -2
	for step in 20:
		var band := layer.band_for(float(step) / 19.0, 0.0)
		assert_gte(band, previous)
		previous = band


# -- footprints carve it out -------------------------------------------------

## The whole point: a trodden tile shows less snow than the field around it.
func test_a_trodden_tile_shows_less_snow():
	var untrodden := layer.band_for(1.0, 0.0)
	var trodden := layer.band_for(1.0, 1.0)
	assert_lt(trodden, untrodden, "a footprint should displace the snow in it")


## Walking through deep snow does not clear it to bare earth -- it packs it
## down. A trail should read as tracks, not as a dug trench.
func test_a_single_pass_does_not_clear_deep_snow():
	assert_gte(
		layer.band_for(1.0, SnowTrail.TREAD_PER_STEP), 0,
		"one step through deep snow should pack it, not clear it"
	)


## In a thin dusting, though, a footprint does show the ground.
func test_a_footprint_in_a_dusting_shows_the_ground():
	assert_eq(layer.band_for(0.25, 1.0), -1, "a boot through a dusting reaches the ground")


func test_treading_never_deepens_the_snow():
	for step in 10:
		var tread := float(step) / 9.0
		assert_lte(layer.band_for(0.8, tread), layer.band_for(0.8, 0.0))


func _whiteness(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			total += pixel.v * pixel.a
			count += 1
	return total / float(maxi(count, 1))
