extends RefCounted

## Real curated discharge and real channel width for the rivers in
## RiverCatalog -- the "how much water" half of the hydraulics model, where
## RiverCatalog supplies the "where" half. See docs/concept/rivers.md.
##
## Curated, not derived-from-terrain, for the same reason the river courses
## themselves are (rivers.md pillar 1): a river's discharge is set by its
## whole upstream catchment -- the Rhine at Cologne drains ~185,000 km2,
## thousands of chunks, none of them loaded. On a chunk-streamed world there
## is no way to integrate that locally, so a "computed" volume would be a
## lie dressed as physics. Real published gauge figures are both cheaper and
## more honest.
##
## Source throughout: German Wikipedia's structured `Abfluss` infobox
## blocks, which carry the named gauging station (Pegel), catchment area
## (AEo), the gauge's distance above the mouth, and the measurement period.
## They are consistently better sourced than the English infoboxes' single
## bare numbers.

const RiverCatalog = preload("res://src/world/river_catalog.gd")

## Real mean discharge (MQ) at each river's MOUTH, in m3/s.
##
## The Dreisam is the small-river calibration anchor: 10.86 m3/s where it
## joins the Elz (5.56 at Pegel Ebnet, 24.3 km upstream, at the eastern
## edge of Freiburg -- which is the reach this game's own spawn point sits
## on). Everything about how a small river should feel is calibrated against
## it, and its ~600x span down from the Danube is what makes the roster a
## real test of the model rather than a single-scale one.
const MEAN_DISCHARGE_M3_S := {
	"Danube": 6452.0,   # mouth/delta, 1931-2020, AEo ~817,000 km2
	"Rhine": 2900.0,    # mouth, summed delta arms, AEo 218,300 km2 (incl. Meuse)
	"Elbe": 861.0,      # mouth, AEo 148,268 km2
	"Oder": 574.0,      # mouth into the Stettiner Haff, AEo 118,890 km2
	"Weser": 383.0,     # mouth, AEo 45,809 km2
	"Mosel": 320.0,     # mouth at Koblenz, AEo 28,153 km2
	"Main": 211.0,      # mouth, AEo 27,292 km2
	"Isar": 176.0,      # mouth, AEo 8,962 km2
	"Neckar": 145.0,    # Pegel Mannheim at the mouth, AEo 13,934 km2
	"Spree": 38.0,      # Pegel Sophienwerder, 600 m above the mouth, 1961-1999
	"Dreisam": 10.86,   # mouth into the Elz near Riegel, AEo 649 km2
}

## Real published mean channel width (m), for the rivers that actually have
## one. Most do not: German river articles almost never publish a mean width,
## and the figures that do get published are usually a single named spot (a
## bridge, a gorge) or an engineered navigation fairway -- a dredging
## guarantee, not the river's own geometry. Only genuinely reach-scale
## figures are curated here; everything else is derived (see derived_width_m).
##
## These double as the calibration set for that derivation -- pinned by
## test_the_derived_width_relation_reproduces_the_real_published_widths.
const CURATED_WIDTH_M := {
	"Danube": 950.0,  # lower course 900-1000; the only river with real mean width by reach
	"Rhine": 560.0,   # >400 at Emmerich-Kleve, up to 900 on the widest Upper Rhine reach
	"Elbe": 400.0,    # Unterelbe below the Geesthacht weir, 300-500
	"Main": 170.0,    # Schweinfurt
	"Isar": 150.0,    # the engineered Munich channel
}

## Fraction of its mouth discharge a river already carries at its SOURCE.
##
## Fitted to real multi-gauge data across the roster rather than picked: for
## each of 9 real gauging stations with both a known position along its
## river and a known mean discharge, the implied source fraction is
## (measured/mouth - position) / (1 - position). Those 9 values average
## ~0.27. The spread is genuinely wide (-0.39 to +0.81) because real
## catchment shape varies enormously -- a river fed by one big Alpine
## tributary near its mouth behaves nothing like one gathering evenly along
## its length -- so this is an honest central estimate of a scattered
## natural relationship, not a precise law. Pinned against all 9 real gauges
## by test_the_course_model_lands_near_real_gauge_readings, with a
## deliberately wide tolerance that states that scatter rather than hiding it.
const SOURCE_DISCHARGE_FRACTION := 0.27

## Downstream hydraulic geometry: channel width grows as the square root of
## discharge (w = COEFFICIENT * sqrt(Q)). The 0.5 exponent is the classic
## downstream hydraulic-geometry value from real river surveys; the
## coefficient is fitted to this roster's own real published widths
## (Danube 950 m at 6452 m3/s -> 11.8; Elbe 400 at 861 -> 13.6; Main 170 at
## 211 -> 11.7; Isar 150 at 176 -> 11.3), which cluster tightly around 12.
##
## Honest limitation: every calibration point is a LARGE river. Extrapolating
## one power law down three orders of magnitude to a Dreisam-sized stream is
## not well supported by this data -- no width was published for any of the
## small rivers to check it against. Treat small-river widths as plausible,
## not verified. Stated in docs/concept/rivers.md's own gaps section too.
const WIDTH_COEFFICIENT := 12.1
const WIDTH_EXPONENT := 0.5

## Floor so a headwater trickle still has SOME channel to flow in -- a zero
## width would divide by zero in the continuity solve.
const MIN_CHANNEL_WIDTH_M := 1.0


## Real discharge (m3/s) at a point `course_fraction` along a river's
## course, 0.0 at the source and 1.0 at the mouth (see
## RiverCatalog.nearest_river_at, which produces exactly that fraction).
##
## Grows linearly from SOURCE_DISCHARGE_FRACTION of the mouth figure up to
## the full figure -- real discharge grows downstream as drainage area
## accumulates, so a single per-river number would make a headwater brook as
## mighty as its own estuary. 0.0 for a river with no curated figure.
static func discharge_at(river_name: String, course_fraction: float) -> float:
	if not MEAN_DISCHARGE_M3_S.has(river_name):
		return 0.0
	var fraction := clampf(course_fraction, 0.0, 1.0)
	var mouth: float = MEAN_DISCHARGE_M3_S[river_name]
	return mouth * (SOURCE_DISCHARGE_FRACTION + (1.0 - SOURCE_DISCHARGE_FRACTION) * fraction)


## Channel width (m) implied by a discharge, by downstream hydraulic
## geometry -- see WIDTH_COEFFICIENT for the fit and its honest limits.
static func derived_width_m(discharge_m3_s: float) -> float:
	if discharge_m3_s <= 0.0:
		return MIN_CHANNEL_WIDTH_M
	return maxf(WIDTH_COEFFICIENT * pow(discharge_m3_s, WIDTH_EXPONENT), MIN_CHANNEL_WIDTH_M)


## Real channel width (m) at a point along a river: the curated published
## width where one exists, scaled along the course by how much of the
## river's discharge has accumulated by then (a river really is narrower
## near its source), and derived from discharge everywhere else.
##
## NEVER the rendered tile width. RiverCatalog.RIVER_HALF_WIDTH_TILES draws
## a river 4 tiles across, which at this world's ~1 km/tile is a 4 km-wide
## Dreisam -- a deliberate visibility compression (rivers.md pillar 4).
## Feeding that into the continuity solve would put current speed out by
## ~3 orders of magnitude. Pinned by
## test_real_channel_width_is_nothing_like_the_rendered_tile_width.
static func channel_width_m(river_name: String, course_fraction: float) -> float:
	if not MEAN_DISCHARGE_M3_S.has(river_name):
		return 0.0
	var here := discharge_at(river_name, course_fraction)
	if CURATED_WIDTH_M.has(river_name):
		# Scale the real published (mouth-reach) width by how far the
		# discharge has grown, using the same sqrt relation -- so a curated
		# river still narrows upstream instead of running full width to its
		# spring.
		var mouth_discharge: float = MEAN_DISCHARGE_M3_S[river_name]
		var scale := pow(here / mouth_discharge, WIDTH_EXPONENT) if mouth_discharge > 0.0 else 1.0
		return maxf(CURATED_WIDTH_M[river_name] * scale, MIN_CHANNEL_WIDTH_M)
	return derived_width_m(here)
