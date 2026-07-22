extends GutTest

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

var geo: GeoCoordinates


func before_each():
	geo = GeoCoordinates.new()


func test_top_row_is_the_north_pole():
	assert_almost_eq(geo.latitude_for_tile(0, 9), 90.0, 0.001)


func test_bottom_row_is_the_south_pole():
	assert_almost_eq(geo.latitude_for_tile(8, 9), -90.0, 0.001)


func test_middle_row_is_the_equator():
	assert_almost_eq(geo.latitude_for_tile(4, 9), 0.0, 0.001)


func test_left_edge_is_the_date_line():
	assert_almost_eq(geo.longitude_for_tile(0, 80), -180.0, 0.001)


func test_horizontal_center_is_the_prime_meridian():
	assert_almost_eq(geo.longitude_for_tile(40, 80), 0.0, 0.001)


func test_longitude_increases_moving_east():
	assert_lt(geo.longitude_for_tile(10, 80), geo.longitude_for_tile(50, 80))


func test_tile_for_latitude_is_the_inverse_of_latitude_for_tile():
	for tile_y in [0, 3, 4, 8]:
		var latitude := geo.latitude_for_tile(tile_y, 9)
		assert_eq(geo.tile_for_latitude(latitude, 9), tile_y)


func test_tile_for_longitude_is_the_inverse_of_longitude_for_tile():
	for tile_x in [0, 20, 40, 60, 79]:
		var longitude := geo.longitude_for_tile(tile_x, 80)
		assert_eq(geo.tile_for_longitude(longitude, 80), tile_x)
