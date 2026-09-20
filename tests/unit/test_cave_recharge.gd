extends GutTest

## CaveRecharge.mode_at: which of Palmer's five groundwater recharge modes
## governs a place (see docs/concept/underground.md "Palmer: how the water
## gets in decides what the cave looks like").
##
## Palmer 1991 (GSA Bulletin 103) found cave pattern is controlled
## primarily by the MODE OF RECHARGE -- not by rock type, depth or age --
## so this classifier is where the real causal work happens; CavePattern
## is only the lookup that follows from it.

const CaveRecharge = preload("res://src/world/cave_recharge.gd")

var recharge: CaveRecharge


func before_each():
	recharge = CaveRecharge.new()


# -- always a real answer, always the same answer --------------------------

func test_every_result_is_a_known_recharge_mode():
	for channel in [true, false]:
		for caprock in [true, false]:
			for seasonality in [0.0, 0.5, 1.0]:
				for hydrothermal in [0.0, 0.5, 1.0]:
					for coast_km in [0.0, 25.0, 1000.0]:
						var mode: String = recharge.mode_at(
							channel, caprock, seasonality, hydrothermal, coast_km
						)
						assert_true(
							CaveRecharge.MODES.has(mode), "'%s' is not a known recharge mode" % mode
						)


func test_the_classification_is_pure():
	var first: String = recharge.mode_at(true, false, 0.8, 0.1, 400.0)
	var second: String = recharge.mode_at(true, false, 0.8, 0.1, 400.0)
	assert_eq(first, second, "recharge mode must be a pure function of its inputs")


func test_bare_karst_concentrates_its_own_rain_into_point_recharge():
	# Bare karst with no sinking stream and no caprock still takes
	# autogenic recharge -- there is no "this limestone never sees water"
	# case. But its own EPIKARST concentrates that diffuse rain into
	# discrete inputs at shaft tops, so what reaches the cave is a point
	# input, not a diffuse one. This is why branchwork dominates Palmer's
	# survey: the commonest karst setting of all feeds it.
	var mode: String = recharge.mode_at(false, false, 0.0, 0.0, 9999.0)
	assert_eq(mode, CaveRecharge.MODE_SINKHOLE)


func test_the_permeable_caprock_is_what_makes_recharge_genuinely_diffuse():
	# Palmer's network mazes form where recharge percolates through an
	# insoluble but permeable cover -- sandstone over limestone, as in the
	# Black Hills maze caves and Mammoth Cave's own maze sections. Remove
	# the caprock and the epikarst concentrates the same rain instead.
	assert_eq(recharge.mode_at(false, true, 0.0, 0.0, 500.0), CaveRecharge.MODE_DIFFUSE)
	assert_eq(recharge.mode_at(false, false, 0.0, 0.0, 500.0), CaveRecharge.MODE_SINKHOLE)


# -- precedence: what dominates when several drivers apply at once ---------

func test_hypogenic_dominates_everything_else():
	# Rising sulfidic water dissolves independently of any surface
	# recharge -- Carlsbad and Lechuguilla have no feeding surface stream
	# at all -- so it wins even where a sinking channel and a coast exist.
	var mode: String = recharge.mode_at(true, true, 1.0, 1.0, 0.0)
	assert_eq(mode, CaveRecharge.MODE_HYPOGENIC)


func test_the_coastal_mixing_zone_beats_surface_recharge():
	var mode: String = recharge.mode_at(true, false, 1.0, 0.0, 0.0)
	assert_eq(mode, CaveRecharge.MODE_MIXING_ZONE)


func test_inland_of_the_mixing_zone_surface_recharge_takes_over():
	var mode: String = recharge.mode_at(true, false, 0.0, 0.0, CaveRecharge.MIXING_ZONE_COAST_KM * 10.0)
	assert_eq(mode, CaveRecharge.MODE_SINKHOLE)


# -- the surface-recharge pair: sinkhole vs floodwater ---------------------

func test_a_sinking_stream_in_a_steady_climate_is_sinkhole_recharge():
	assert_eq(
		recharge.mode_at(true, false, 0.0, 0.0, 500.0), CaveRecharge.MODE_SINKHOLE
	)


func test_a_sinking_stream_in_a_strongly_seasonal_climate_is_floodwater():
	assert_eq(
		recharge.mode_at(true, false, 1.0, 0.0, 500.0), CaveRecharge.MODE_FLOODWATER
	)


func test_floodwater_needs_a_sinking_stream_not_just_a_seasonal_climate():
	# Floodwater recharge is episodic injection of ALLOGENIC discharge --
	# a real surface stream in flood. Autogenic epikarst input never
	# reaches that energy however seasonal the climate is, and percolation
	# through a caprock is buffered by the cover itself.
	assert_eq(
		recharge.mode_at(false, false, 1.0, 0.0, 500.0), CaveRecharge.MODE_SINKHOLE
	)
	assert_eq(
		recharge.mode_at(false, true, 1.0, 0.0, 500.0), CaveRecharge.MODE_DIFFUSE
	)


func test_the_floodwater_threshold_is_a_real_wet_dry_contrast():
	assert_between(
		CaveRecharge.FLOODWATER_SEASONALITY_THRESHOLD, 0.0, 1.0,
		"seasonality is a [0,1] reading"
	)
	var just_under: String = recharge.mode_at(
		true, false, CaveRecharge.FLOODWATER_SEASONALITY_THRESHOLD - 0.01, 0.0, 500.0
	)
	var just_over: String = recharge.mode_at(
		true, false, CaveRecharge.FLOODWATER_SEASONALITY_THRESHOLD + 0.01, 0.0, 500.0
	)
	assert_eq(just_under, CaveRecharge.MODE_SINKHOLE)
	assert_eq(just_over, CaveRecharge.MODE_FLOODWATER)


# -- diffuse recharge ------------------------------------------------------

func test_a_permeable_caprock_with_no_sinking_stream_is_diffuse():
	assert_eq(
		recharge.mode_at(false, true, 0.2, 0.0, 500.0), CaveRecharge.MODE_DIFFUSE
	)


func test_a_sinking_stream_beats_a_caprock_above_it():
	# A real allogenic stream sinking through the cover is a point input
	# regardless of what it sank through on the way.
	assert_eq(
		recharge.mode_at(true, true, 0.0, 0.0, 500.0), CaveRecharge.MODE_SINKHOLE
	)


# -- the thresholds themselves are real distances, not tuning knobs --------

func test_the_mixing_zone_is_a_real_coastal_width():
	# Real flank-margin and coastal carbonate cave systems (Yucatan's Ox
	# Bel Ha / Sac Actun) develop within roughly ten kilometres of the
	# coast, not hundreds.
	assert_between(
		CaveRecharge.MIXING_ZONE_COAST_KM, 1.0, 50.0,
		"the fresh/salt mixing zone is a coastal band, not a continental one"
	)


func test_hypogenic_needs_real_proximity_to_rising_fluids():
	assert_between(CaveRecharge.HYPOGENIC_PROXIMITY_THRESHOLD, 0.0, 1.0)
	var far: String = recharge.mode_at(
		false, false, 0.0, CaveRecharge.HYPOGENIC_PROXIMITY_THRESHOLD - 0.01, 500.0
	)
	var near: String = recharge.mode_at(
		false, false, 0.0, CaveRecharge.HYPOGENIC_PROXIMITY_THRESHOLD + 0.01, 500.0
	)
	assert_ne(far, CaveRecharge.MODE_HYPOGENIC)
	assert_eq(near, CaveRecharge.MODE_HYPOGENIC)
