extends GutTest

## Real curated river discharge + derived channel width -- see
## river_discharge.gd and docs/concept/rivers.md.

const RiverDischarge = preload("res://src/world/river_discharge.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")


# -- the curated roster -----------------------------------------------------

func test_every_curated_river_has_a_real_discharge_figure():
	for river_name in RiverCatalog.RIVERS:
		assert_true(
			RiverDischarge.MEAN_DISCHARGE_M3_S.has(river_name),
			"no discharge curated for %s" % river_name
		)
		assert_gt(RiverDischarge.MEAN_DISCHARGE_M3_S[river_name], 0.0)


## Real relative magnitudes, straight from the gauging data -- the Danube is
## the biggest, the Dreisam by far the smallest, and the ordering between
## them is real rather than invented.
func test_the_curated_discharges_have_the_real_relative_magnitudes():
	var d := RiverDischarge.MEAN_DISCHARGE_M3_S
	assert_gt(d["Danube"], d["Rhine"], "the Danube carries more than the Rhine")
	assert_gt(d["Rhine"], d["Elbe"])
	assert_gt(d["Elbe"], d["Oder"])
	assert_gt(d["Oder"], d["Weser"])
	assert_gt(d["Weser"], d["Mosel"])
	assert_gt(d["Mosel"], d["Main"])
	assert_gt(d["Main"], d["Isar"])
	assert_gt(d["Isar"], d["Neckar"])
	assert_gt(d["Neckar"], d["Spree"])
	assert_gt(d["Spree"], d["Dreisam"], "the Spree carries far more than the Dreisam")


## The small-river calibration anchor: the Dreisam at its mouth carries
## 10.86 m3/s (German Wikipedia, confluence with the Elz). Everything about
## how a small river should feel is calibrated against this number.
func test_the_dreisam_anchor_is_its_real_measured_discharge():
	assert_almost_eq(RiverDischarge.MEAN_DISCHARGE_M3_S["Dreisam"], 10.86, 0.01)


# -- discharge along a course -----------------------------------------------
#
# Real discharge GROWS from source to mouth as drainage area accumulates --
# the Dreisam carries 5.56 m3/s at Ebnet (24.3 km above its mouth) and
# 10.86 at the mouth itself. A model that used one number for a whole river
# would make a headwater stream as mighty as its own estuary.

func test_discharge_at_the_mouth_is_the_full_curated_figure():
	assert_almost_eq(
		RiverDischarge.discharge_at("Dreisam", 1.0),
		RiverDischarge.MEAN_DISCHARGE_M3_S["Dreisam"], 0.01
	)


func test_discharge_grows_monotonically_from_source_to_mouth():
	var previous := -1.0
	for step in 11:
		var q := RiverDischarge.discharge_at("Rhine", float(step) / 10.0)
		assert_gt(q, previous, "discharge must grow downstream")
		previous = q


func test_a_headwater_still_carries_real_water():
	# A source is a stream, not a dry bed -- but a small fraction of the mouth.
	var source := RiverDischarge.discharge_at("Rhine", 0.0)
	assert_gt(source, 0.0)
	assert_lt(source, RiverDischarge.MEAN_DISCHARGE_M3_S["Rhine"] * 0.5)


## Validation against REAL gauge readings, not against the implementation.
## Each pair is a real gauging station: its real position along the river
## (as a course fraction) and the real mean discharge measured there, as a
## fraction of that river's own mouth discharge. The model is a broad
## approximation of a genuinely scattered natural relationship (catchment
## shape varies hugely), so the tolerance is wide and honest -- but it must
## land in the right region, not merely be self-consistent.
func test_the_course_model_lands_near_real_gauge_readings():
	# [river, course fraction of the gauge, real measured fraction of mouth Q]
	var gauges := [
		["Elbe", 0.825, 0.827],    # Neu Darchau, 191.33 km above mouth
		["Mosel", 0.905, 0.978],   # Cochem, 51.6 km
		["Isar", 0.969, 0.994],    # Plattling, 9.1 km
		["Neckar", 0.832, 0.938],  # Rockenau, 60.7 km
		["Oder", 0.877, 0.941],    # Widuchowa, 105 km
		["Weser", 0.734, 0.838],   # Intschede, 120.1 km
		["Main", 0.929, 0.915],    # Frankfurt-Osthafen, 37.6 km
		["Rhine", 0.841, 0.779],   # Rees, 196 km
		["Dreisam", 0.180, 0.512], # Ebnet, 24.3 km
	]
	for gauge in gauges:
		var river_name: String = gauge[0]
		var predicted: float = (
			RiverDischarge.discharge_at(river_name, gauge[1])
			/ RiverDischarge.MEAN_DISCHARGE_M3_S[river_name]
		)
		assert_almost_eq(
			predicted, gauge[2], 0.30,
			"%s at course %f: model %f vs real gauge %f" % [river_name, gauge[1], predicted, gauge[2]]
		)


# -- channel width ----------------------------------------------------------
#
# THE trap this module exists to avoid: RiverCatalog.RIVER_HALF_WIDTH_TILES
# renders a river 4 tiles wide, and at this world's ~1 km/tile that is a
# 4 km-wide Dreisam. Deriving velocity from the RENDERED width would put
# current speed off by ~3 orders of magnitude. Real channel width is
# separate curated/derived data and must never be read off the render.

func test_real_channel_width_is_nothing_like_the_rendered_tile_width():
	# The rendered Dreisam is 4 tiles = ~4000 m across. The real one is tens
	# of metres. If these ever converge, something is badly wrong.
	assert_lt(
		RiverDischarge.channel_width_m("Dreisam", 1.0), 100.0,
		"a real small river is tens of metres wide, not kilometres"
	)


func test_curated_widths_are_used_where_real_data_exists():
	# The Danube is the one river with genuinely published mean width by
	# reach (~900 m on its lower course).
	assert_almost_eq(
		RiverDischarge.channel_width_m("Danube", 1.0),
		RiverDischarge.CURATED_WIDTH_M["Danube"], 0.01
	)


## Where no real width was published (most of them), width is DERIVED from
## discharge by hydraulic geometry rather than hand-entered -- and the
## relation's coefficient is calibrated against the rivers that DO have real
## published widths. This checks the derivation reproduces those real
## widths, which is what makes the coefficient a fitted constant rather than
## an eyeballed one.
func test_the_derived_width_relation_reproduces_the_real_published_widths():
	for river_name in RiverDischarge.CURATED_WIDTH_M:
		var real_width: float = RiverDischarge.CURATED_WIDTH_M[river_name]
		var derived := RiverDischarge.derived_width_m(
			RiverDischarge.MEAN_DISCHARGE_M3_S[river_name]
		)
		assert_almost_eq(
			derived / real_width, 1.0, 0.5,
			"%s: derived %f m vs real %f m" % [river_name, derived, real_width]
		)


func test_width_grows_with_discharge():
	assert_gt(RiverDischarge.derived_width_m(2900.0), RiverDischarge.derived_width_m(10.0))


func test_width_is_never_zero_even_for_a_trickle():
	assert_gt(RiverDischarge.derived_width_m(0.001), 0.0)


func test_a_river_narrows_toward_its_source():
	assert_lt(
		RiverDischarge.channel_width_m("Rhine", 0.0), RiverDischarge.channel_width_m("Rhine", 1.0)
	)


# -- unknown rivers ---------------------------------------------------------

func test_an_unknown_river_reports_no_discharge_rather_than_crashing():
	assert_eq(RiverDischarge.discharge_at("Amazon", 0.5), 0.0)


func test_an_unknown_river_reports_no_width_rather_than_crashing():
	assert_eq(RiverDischarge.channel_width_m("Amazon", 0.5), 0.0)
