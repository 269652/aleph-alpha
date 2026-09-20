extends GutTest

## CaveZonation: the four real cave zones by distance from an entrance,
## the light that reaches them, and the temperature they hold (see
## docs/concept/underground.md "The four cave zones, and why the deep one
## is a refuge").
##
## Speleobiology's standard zonation: entrance, twilight, transition, deep
## cave. Two consequences carry real gameplay weight -- below the twilight
## zone there is NO light at all (lighting.md's "dim, never pitch black"
## is justified by moonlight and skyglow, neither of which exists down
## here), and the deep zone sits at the locality's mean annual surface
## temperature whatever the weather is doing above it.

const CaveZonation = preload("res://src/world/cave_zonation.gd")
const CaveNetwork = preload("res://src/world/cave_network.gd")

var zonation: CaveZonation


func before_each():
	zonation = CaveZonation.new()


# -- the four zones ---------------------------------------------------------

func test_every_distance_lands_in_a_known_zone():
	for tiles in range(0, 400, 3):
		var zone: String = zonation.zone_at(float(tiles))
		assert_true(CaveZonation.ZONES.has(zone), "'%s' is not a known cave zone" % zone)


func test_the_zones_appear_in_depth_order():
	var order: Array[String] = []
	for tiles in range(0, 400):
		var zone: String = zonation.zone_at(float(tiles))
		if order.is_empty() or order[-1] != zone:
			order.append(zone)
	assert_eq(order, CaveZonation.ZONES, "zones must appear in order and never recur")


func test_the_mouth_is_the_entrance_zone():
	assert_eq(zonation.zone_at(0.0), CaveZonation.ZONE_ENTRANCE)


func test_a_negative_distance_clamps_to_the_entrance():
	assert_eq(zonation.zone_at(-50.0), CaveZonation.ZONE_ENTRANCE)


func test_the_twilight_zone_ends_within_tens_of_metres():
	# Usable daylight is gone within a few tens of metres of a cave mouth,
	# sooner in a sinuous passage -- not hundreds.
	var metres: float = CaveZonation.TWILIGHT_END_TILES * CaveZonation.METRES_PER_TILE
	assert_between(metres, 10.0, 60.0, "the twilight zone is tens of metres deep")


func test_the_deep_zone_begins_beyond_the_reach_of_surface_air():
	var metres: float = CaveZonation.TRANSITION_END_TILES * CaveZonation.METRES_PER_TILE
	assert_gt(metres, 100.0, "surface air exchange reaches well past the twilight zone")


# -- light: absolutely dark below the twilight zone -------------------------

func test_full_daylight_at_the_mouth():
	assert_almost_eq(zonation.daylight_fraction_at(0.0), 1.0, 0.001)


func test_daylight_never_increases_with_depth():
	var previous := 2.0
	for tiles in range(0, 200):
		var light: float = zonation.daylight_fraction_at(float(tiles))
		assert_between(light, 0.0, 1.0, "daylight fraction out of [0,1] at %d tiles" % tiles)
		assert_lte(light, previous, "daylight rose going deeper at %d tiles" % tiles)
		previous = light


func test_daylight_is_exactly_zero_below_the_twilight_zone():
	# Exactly zero, not asymptotically small. There is no moonlight, no
	# starlight and no skyglow underground, so lighting.md's floor does
	# not travel down here -- and a floor that never quite reaches zero
	# would quietly make a torch cosmetic.
	for tiles in [
		CaveZonation.TWILIGHT_END_TILES, CaveZonation.TWILIGHT_END_TILES + 1.0, 500.0
	]:
		assert_eq(
			zonation.daylight_fraction_at(tiles), 0.0,
			"daylight leaked into the dark zone at %.1f tiles" % tiles
		)


func test_absolute_darkness_is_exactly_the_transition_and_deep_zones():
	for zone in CaveZonation.ZONES:
		var dark: bool = zonation.is_absolutely_dark(zone)
		var expected: bool = zone in [CaveZonation.ZONE_TRANSITION, CaveZonation.ZONE_DEEP]
		assert_eq(dark, expected, "%s disagrees about being absolutely dark" % zone)


# -- temperature: the deep zone is a real refuge ----------------------------

func test_the_deep_zone_holds_the_mean_annual_surface_temperature():
	# The standard, well-established result: a cave's deep zone sits at
	# its locality's mean annual surface temperature. This is why people
	# have stored food in caves for as long as there have been both.
	for surface_now in [-25.0, 0.0, 18.0, 45.0]:
		assert_almost_eq(
			zonation.temperature_c_at(CaveZonation.ZONE_DEEP, 11.0, surface_now),
			11.0, 0.001,
			"a %.0fC day changed the deep zone's temperature" % surface_now
		)


func test_the_entrance_zone_tracks_the_weather_outside():
	assert_almost_eq(
		zonation.temperature_c_at(CaveZonation.ZONE_ENTRANCE, 11.0, 34.0), 34.0, 0.001
	)


func test_the_zones_between_are_between():
	var mean := 11.0
	var outside := 34.0
	var twilight: float = zonation.temperature_c_at(CaveZonation.ZONE_TWILIGHT, mean, outside)
	var transition: float = zonation.temperature_c_at(CaveZonation.ZONE_TRANSITION, mean, outside)
	assert_lt(twilight, outside)
	assert_lt(transition, twilight)
	assert_gt(transition, mean)


func test_a_cave_is_a_refuge_from_a_cold_snap_too():
	# The refuge works in both directions -- the deep zone is warmer than
	# a hard frost outside, not merely cooler than a hot day.
	assert_gt(
		zonation.temperature_c_at(CaveZonation.ZONE_DEEP, 11.0, -20.0),
		zonation.temperature_c_at(CaveZonation.ZONE_ENTRANCE, 11.0, -20.0)
	)


func test_an_unknown_zone_reports_the_surface():
	assert_almost_eq(zonation.temperature_c_at("not_a_zone", 11.0, 30.0), 30.0, 0.001)


func test_the_model_is_pure():
	assert_eq(zonation.zone_at(42.0), zonation.zone_at(42.0))
	assert_eq(zonation.daylight_fraction_at(7.0), zonation.daylight_fraction_at(7.0))


func test_metres_per_tile_agrees_with_the_cave_network():
	# Two files carry this play-scale constant rather than one preloading
	# the other; they must not drift apart.
	assert_almost_eq(
		CaveZonation.METRES_PER_TILE, CaveNetwork.METRES_PER_TILE, 0.0001
	)
