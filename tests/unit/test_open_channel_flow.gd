extends GutTest

## Real open-channel hydraulics -- see open_channel_flow.gd and
## docs/concept/rivers.md. Every formula here is the real one civil
## engineers use; these tests check it against REAL measured river data
## (USGS Water-Supply Paper 1849 verified reaches) rather than against
## numbers invented to match the implementation.

const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")


# -- hydraulic radius -------------------------------------------------------

func test_hydraulic_radius_of_a_wide_channel_approaches_its_depth():
	# b/h = 100 -> R/h = 0.980 (see the research table in the module doc).
	assert_almost_eq(OpenChannelFlow.hydraulic_radius(1.0, 100.0), 0.980, 0.001)


func test_hydraulic_radius_of_a_square_channel_is_well_below_its_depth():
	# b/h = 2 -> R/h = 0.500 exactly: R = bh/(b+2h) = 2/(2+2) = 0.5.
	assert_almost_eq(OpenChannelFlow.hydraulic_radius(1.0, 2.0), 0.5, 0.0001)


func test_hydraulic_radius_matches_the_closed_form():
	for depth in [0.2, 1.0, 3.7]:
		for width in [5.0, 40.0, 300.0]:
			assert_almost_eq(
				OpenChannelFlow.hydraulic_radius(depth, width),
				(width * depth) / (width + 2.0 * depth), 0.0001
			)


func test_hydraulic_radius_is_never_negative_or_nan_at_zero_depth():
	assert_eq(OpenChannelFlow.hydraulic_radius(0.0, 10.0), 0.0)


# -- Manning roughness ------------------------------------------------------
#
# The single most important correction the research turned up: standard
# table n values (Chow 1959 etc.) are measured on LOW-gradient channels and
# badly underestimate resistance in steep ones. Yochum et al. 2012
# (J. Hydrology 424-425:84-98) measured average n = 0.18 across 15 Colorado
# reaches at 1.5-20% slope -- 3-20x the textbook "mountain stream" value --
# and state plainly that using table n there means "substantially
# overestimated flow velocities". Jarrett (1984) is the standard
# steep-channel correction and is what this module uses above the threshold.

func test_a_gentle_channel_uses_the_lowland_table_roughness():
	assert_almost_eq(
		OpenChannelFlow.manning_n(0.0005, 2.0), OpenChannelFlow.LOWLAND_MANNING_N, 0.0001
	)


func test_a_steep_channel_is_much_rougher_than_the_lowland_table_value():
	# 3% slope -- squarely inside Jarrett's measured 0.2-3.4% range.
	var steep := OpenChannelFlow.manning_n(0.03, 0.5)
	assert_gt(steep, OpenChannelFlow.LOWLAND_MANNING_N * 2.0,
		"a steep mountain reach must not use a lowland table roughness")


func test_roughness_increases_with_slope():
	var previous := 0.0
	for slope in [0.001, 0.005, 0.01, 0.02, 0.05]:
		var n := OpenChannelFlow.manning_n(slope, 1.0)
		assert_gte(n, previous, "roughness must not fall as the channel steepens")
		previous = n


## Jarrett's own measured range was n = 0.028-0.16. Anything wildly outside
## that for a slope inside his validity band means the formula is wrong.
func test_steep_roughness_stays_within_jarretts_measured_range():
	for slope in [0.002, 0.01, 0.034]:
		var n := OpenChannelFlow.manning_n(slope, 1.0)
		assert_between(n, 0.02, 0.40, "n=%f at slope %f is outside any measured range" % [n, slope])


# -- Manning velocity -------------------------------------------------------

func test_velocity_is_zero_on_perfectly_flat_ground():
	assert_eq(OpenChannelFlow.velocity(1.0, 0.0, 0.03), 0.0)


func test_velocity_rises_with_slope_and_depth():
	assert_gt(
		OpenChannelFlow.velocity(2.0, 0.001, 0.03), OpenChannelFlow.velocity(1.0, 0.001, 0.03)
	)
	assert_gt(
		OpenChannelFlow.velocity(1.0, 0.004, 0.03), OpenChannelFlow.velocity(1.0, 0.001, 0.03)
	)


func test_velocity_falls_as_the_bed_gets_rougher():
	assert_lt(
		OpenChannelFlow.velocity(1.0, 0.001, 0.06), OpenChannelFlow.velocity(1.0, 0.001, 0.03)
	)


## REAL measured reach, USGS WSP 1849 (Barnes 1967): Columbia River at
## Vernita, WA -- n = 0.024, R = 7.97 m, S = 0.000192, measured mean
## velocity 2.49-2.64 m/s. Manning's must reproduce a real gauged river.
func test_manning_reproduces_the_measured_columbia_river_velocity():
	var v := OpenChannelFlow.velocity_from_radius(7.97, 0.000192, 0.024)
	assert_between(v, 2.2, 3.0, "Manning gave %f m/s where the USGS measured 2.49-2.64" % v)


## Second REAL measured reach from the same source, an order of magnitude
## smaller and 12x steeper: Beaver Kill at Cooks Falls, NY -- n = 0.033,
## R = 2.09 m, S = 0.00233-0.00442, measured 2.78-2.96 m/s.
func test_manning_reproduces_the_measured_beaver_kill_velocity():
	var v := OpenChannelFlow.velocity_from_radius(2.09, 0.00233, 0.033)
	assert_between(v, 2.0, 3.5, "Manning gave %f m/s where the USGS measured 2.78-2.96" % v)


# -- normal depth (the closed-form solve) -----------------------------------
#
# h_n = (n*q/sqrt(S))^(3/5), q = Q/b -- the wide-channel normal-depth
# solution (Apsley, Hydraulics 3, OCFBasics 1.2). Closed form, so no
# fixed-point iteration is needed to get a self-consistent (depth, velocity)
# pair from (Q, width, slope, roughness).

func test_normal_depth_is_zero_with_no_discharge():
	assert_eq(OpenChannelFlow.normal_depth(0.0, 20.0, 0.001, 0.03), 0.0)


func test_normal_depth_grows_with_discharge():
	assert_gt(
		OpenChannelFlow.normal_depth(200.0, 50.0, 0.001, 0.03),
		OpenChannelFlow.normal_depth(20.0, 50.0, 0.001, 0.03)
	)


func test_normal_depth_falls_as_the_channel_steepens():
	assert_lt(
		OpenChannelFlow.normal_depth(100.0, 50.0, 0.01, 0.03),
		OpenChannelFlow.normal_depth(100.0, 50.0, 0.0005, 0.03)
	)


func test_normal_depth_falls_as_the_channel_widens():
	assert_lt(
		OpenChannelFlow.normal_depth(100.0, 200.0, 0.001, 0.03),
		OpenChannelFlow.normal_depth(100.0, 20.0, 0.001, 0.03)
	)


## The real consistency requirement: depth and velocity are NOT independent.
## Whatever depth the solve returns must, run back through Manning and
## continuity, reproduce the discharge it was given.
func test_depth_and_velocity_together_conserve_the_given_discharge():
	for discharge in [5.56, 145.0, 2900.0]:
		for width in [15.0, 90.0, 400.0]:
			var slope := 0.0008
			var n := 0.035
			var depth: float = OpenChannelFlow.normal_depth(discharge, width, slope, n)
			var v: float = OpenChannelFlow.velocity(depth, slope, n)
			var reconstructed: float = depth * width * v
			assert_almost_eq(
				reconstructed / discharge, 1.0, 0.12,
				"Q=%f w=%f gave depth %f, velocity %f -> Q=%f" % [discharge, width, depth, v, reconstructed]
			)


# -- hydrostatic pressure ---------------------------------------------------

func test_pressure_is_zero_at_the_surface():
	assert_eq(OpenChannelFlow.hydrostatic_pressure_pa(0.0), 0.0)


## p = rho*g*h. At 10 m the textbook answer is ~98.1 kPa -- about one
## atmosphere, the classic "10 m of water = 1 bar" sanity check.
func test_pressure_at_ten_metres_is_about_one_atmosphere():
	assert_almost_eq(OpenChannelFlow.hydrostatic_pressure_pa(10.0), 98100.0, 500.0)


func test_pressure_rises_linearly_with_depth():
	var shallow := OpenChannelFlow.hydrostatic_pressure_pa(1.0)
	var deep := OpenChannelFlow.hydrostatic_pressure_pa(3.0)
	assert_almost_eq(deep / shallow, 3.0, 0.0001)


# -- force on a dam face ----------------------------------------------------

func test_no_force_on_a_dry_dam():
	assert_eq(OpenChannelFlow.hydrostatic_force_newtons(0.0, 5.0), 0.0)


## F = 0.5 * rho * g * h^2 * width. For h = 2 m, w = 5 m:
## 0.5 * 1000 * 9.81 * 4 * 5 = 98,100 N.
func test_force_on_a_dam_face_matches_the_closed_form():
	assert_almost_eq(OpenChannelFlow.hydrostatic_force_newtons(2.0, 5.0), 98100.0, 1.0)


## Force goes as depth SQUARED -- doubling the pooled depth quadruples the
## load. This is why a dam that holds fine at 1 m bursts at 2 m, and it's
## the whole physical basis of the failure mechanic.
func test_force_grows_with_the_square_of_depth():
	var single := OpenChannelFlow.hydrostatic_force_newtons(1.0, 3.0)
	var double := OpenChannelFlow.hydrostatic_force_newtons(2.0, 3.0)
	assert_almost_eq(double / single, 4.0, 0.0001)


# -- weir overtopping -------------------------------------------------------
#
# Broad-crested stone weir, C_d = 0.845 (Zachoval et al. 2014, J. Hydrol.
# Hydromech. 62(2):145-149) -> Q = 1.441 * b * h^1.5.

func test_no_overtopping_below_the_crest():
	assert_eq(OpenChannelFlow.weir_overflow_m3_s(0.0, 4.0), 0.0)
	assert_eq(OpenChannelFlow.weir_overflow_m3_s(-0.5, 4.0), 0.0)


func test_overtopping_matches_the_broad_crested_weir_equation():
	# 0.5 m of head over a 4 m crest: 1.441 * 4 * 0.5^1.5 = 2.038 m3/s.
	assert_almost_eq(OpenChannelFlow.weir_overflow_m3_s(0.5, 4.0), 2.038, 0.01)


func test_overtopping_grows_faster_than_linearly_with_head():
	# h^1.5: doubling head multiplies flow by 2^1.5 = 2.83.
	var single := OpenChannelFlow.weir_overflow_m3_s(0.4, 3.0)
	var double := OpenChannelFlow.weir_overflow_m3_s(0.8, 3.0)
	assert_almost_eq(double / single, pow(2.0, 1.5), 0.001)


## The head at which a weir of a given width passes exactly the river's
## discharge -- the dam's real steady state, and the inverse of the equation
## above. Must round-trip.
func test_equilibrium_head_round_trips_through_the_weir_equation():
	for discharge in [0.5, 5.56, 60.0]:
		var head := OpenChannelFlow.equilibrium_weir_head_m(discharge, 4.0)
		assert_almost_eq(OpenChannelFlow.weir_overflow_m3_s(head, 4.0), discharge, 0.01)
