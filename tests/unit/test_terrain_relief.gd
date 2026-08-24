extends GutTest

const TerrainRelief = preload("res://src/world/terrain_relief.gd")

var relief: TerrainRelief


func before_each():
	relief = TerrainRelief.new()


# -- elevation_meters: EarthElevationSource's normalized encoding -> real metres -

func test_elevation_meters_at_zero_is_the_deepest_trench():
	assert_almost_eq(relief.elevation_meters(0.0), -8000.0, 0.01)


func test_elevation_meters_at_one_is_the_highest_peak():
	assert_almost_eq(relief.elevation_meters(1.0), 6400.0, 0.01)


## EarthElevationSource's own doc comment: "sea level (0m) sits at ~0.5556".
func test_elevation_meters_near_the_documented_sea_level_normalized_value():
	assert_almost_eq(relief.elevation_meters(0.5556), 0.0, 5.0)


# -- meters_per_degree_longitude: real geodesy, shrinks toward the poles ---------

func test_meters_per_degree_longitude_at_the_equator_matches_latitude():
	assert_almost_eq(
		relief.meters_per_degree_longitude(0.0), TerrainRelief.METERS_PER_DEGREE_LATITUDE, 1.0
	)


func test_meters_per_degree_longitude_at_sixty_degrees_is_roughly_half():
	var at_sixty := relief.meters_per_degree_longitude(60.0)
	assert_almost_eq(at_sixty, TerrainRelief.METERS_PER_DEGREE_LATITUDE * 0.5, 5.0)


func test_meters_per_degree_longitude_at_the_pole_is_near_zero():
	assert_almost_eq(relief.meters_per_degree_longitude(90.0), 0.0, 1.0)


func test_meters_per_degree_longitude_is_symmetric_north_and_south():
	assert_almost_eq(
		relief.meters_per_degree_longitude(40.0), relief.meters_per_degree_longitude(-40.0), 0.01
	)


# -- slope_degrees_from_gradient: real central-difference slope magnitude -------

func test_flat_ground_has_zero_slope():
	assert_almost_eq(relief.slope_degrees_from_gradient(0.0, 0.0), 0.0, 0.001)


## A 1:1 rise:run gradient is exactly 45 degrees -- the textbook check.
func test_a_one_to_one_gradient_is_45_degrees():
	assert_almost_eq(relief.slope_degrees_from_gradient(1.0, 0.0), 45.0, 0.01)
	assert_almost_eq(relief.slope_degrees_from_gradient(0.0, 1.0), 45.0, 0.01)


func test_slope_combines_both_axes_by_magnitude_not_sum():
	# A 1:1 gradient on BOTH axes is steeper than either alone, but less than
	# their sum (Pythagorean magnitude, not linear addition).
	var combined := relief.slope_degrees_from_gradient(1.0, 1.0)
	assert_gt(combined, relief.slope_degrees_from_gradient(1.0, 0.0))
	assert_lt(combined, relief.slope_degrees_from_gradient(1.0, 0.0) * 2.0)


func test_slope_is_direction_agnostic():
	# Sign of the gradient doesn't change how STEEP it is, only which way it
	# faces (see aspect below) -- a slope down is exactly as steep as the
	# same slope up.
	assert_almost_eq(
		relief.slope_degrees_from_gradient(-1.0, 0.0), relief.slope_degrees_from_gradient(1.0, 0.0), 0.001
	)


func test_a_near_vertical_gradient_approaches_ninety_degrees():
	assert_gt(relief.slope_degrees_from_gradient(1000.0, 0.0), 89.0)


# -- aspect_degrees_from_gradient: real GIS convention, compass bearing downhill -

## GIS convention: aspect is the compass direction the slope FACES (the
## downhill direction), 0=north, 90=east, 180=south, 270=west.
func test_aspect_facing_due_south_when_ground_falls_toward_the_south():
	# East/west gradient flat, north/south gradient positive means north is
	# HIGHER than south -- so the slope faces (falls toward) south.
	var aspect := relief.aspect_degrees_from_gradient(0.0, 1.0)
	assert_almost_eq(aspect, 180.0, 0.5)


func test_aspect_facing_due_north_when_ground_falls_toward_the_north():
	var aspect := relief.aspect_degrees_from_gradient(0.0, -1.0)
	assert_almost_eq(aspect, 0.0, 0.5)


func test_aspect_facing_due_east_when_ground_falls_toward_the_east():
	var aspect := relief.aspect_degrees_from_gradient(-1.0, 0.0)
	assert_almost_eq(aspect, 90.0, 0.5)


func test_aspect_wraps_into_zero_to_360_range():
	var aspect := relief.aspect_degrees_from_gradient(1.0, 0.0)
	assert_gte(aspect, 0.0)
	assert_lt(aspect, 360.0)


## Aspect is undefined on perfectly flat ground -- a real GIS edge case
## (there is no "downhill" with no slope at all). Reports -1 rather than an
## arbitrary angle, so a caller can tell "flat" apart from "faces north"
## instead of silently treating them the same.
func test_aspect_is_undefined_on_flat_ground():
	assert_eq(relief.aspect_degrees_from_gradient(0.0, 0.0), -1.0)


# -- slope_at / aspect_at: the real sampling wrapper, via a fake elevation source -

## Same has-a-real-dependency/fake-for-tests shape StoneRenderer already
## uses for IllustratedStoneSprite (see test_stone_renderer.gd's
## _FakeIllustratedStones) -- a fixed 4-neighbor reading with no PNG to load,
## so this stays a fast, isolated unit test rather than an integration one.
## Responds through the exact SAME `elevation_at(lat, lon)` call slope_at/
## aspect_at will actually make -- comparing the queried point against the
## known center tells north/south/east/west apart, rather than a second,
## made-up interface real EarthElevationSource doesn't have.
class _FakeElevationSource:
	var center_lat := 0.0
	var center_lon := 0.0
	var north := 0.5
	var south := 0.5
	var east := 0.5
	var west := 0.5

	func elevation_at(latitude_deg: float, longitude_deg: float) -> float:
		if latitude_deg > center_lat:
			return north
		if latitude_deg < center_lat:
			return south
		if longitude_deg > center_lon:
			return east
		if longitude_deg < center_lon:
			return west
		return 0.5


func _fake_at(center_lat: float, center_lon: float) -> _FakeElevationSource:
	var fake := _FakeElevationSource.new()
	fake.center_lat = center_lat
	fake.center_lon = center_lon
	fake.north = 0.5
	fake.south = 0.5
	fake.east = 0.5
	fake.west = 0.5
	return fake


func test_slope_at_is_zero_over_perfectly_flat_terrain():
	var fake := _fake_at(10.0, 20.0)
	var slope := relief.slope_at(fake, 10.0, 20.0)
	assert_almost_eq(slope, 0.0, 0.01)


func test_slope_at_is_nonzero_when_neighbors_differ_in_elevation():
	var fake := _fake_at(10.0, 20.0)
	fake.north = 0.6
	fake.south = 0.4
	var slope := relief.slope_at(fake, 10.0, 20.0)
	assert_gt(slope, 0.0)


func test_slope_at_is_steeper_with_a_bigger_elevation_difference():
	var gentle := _fake_at(10.0, 20.0)
	gentle.north = 0.52
	gentle.south = 0.48

	var steep := _fake_at(10.0, 20.0)
	steep.north = 0.9
	steep.south = 0.1

	assert_gt(relief.slope_at(steep, 10.0, 20.0), relief.slope_at(gentle, 10.0, 20.0))


func test_aspect_at_matches_the_gradient_direction():
	var fake := _fake_at(10.0, 20.0)
	# Higher to the north, lower to the south -> falls toward the south.
	fake.north = 0.7
	fake.south = 0.3
	var aspect := relief.aspect_at(fake, 10.0, 20.0)
	assert_almost_eq(aspect, 180.0, 1.0)
