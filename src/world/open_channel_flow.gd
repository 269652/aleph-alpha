extends RefCounted

## Real open-channel hydraulics: the actual formulas civil engineers and
## hydrologists use, in SI, for turning a river's discharge and its channel
## geometry into a self-consistent depth, current speed, and pressure.
## See docs/concept/rivers.md's "Real hydraulics" section.
##
## Pure functions, no state, no world knowledge -- this file answers "given
## this much water in a channel this shape, how fast and how deep is it",
## and never "where is there a river". That split matches BiomeClassifier
## (pure classification) vs EarthChunkGenerator (world knowledge).
##
## Every constant here is cited to a real engineering source. Nothing is
## eyeballed, per this project's own no-manually-tuned-values rule.

## Water density (kg/m3) and standard gravity (m/s2) -- the two constants
## every pressure/force term below is built on.
const WATER_DENSITY_KG_M3 := 1000.0
const GRAVITY_M_S2 := 9.81

# -- Manning roughness ------------------------------------------------------
#
# THE correction that matters most here, and the one a naive implementation
# gets wrong: standard Manning n tables (Chow 1959; Arcement & Schneider
# 1989) are measured on LOW-gradient channels and badly underestimate
# resistance in steep ones. Yochum et al. 2012 (J. Hydrology 424-425:84-98)
# measured average n = 0.18 across 15 Colorado reaches at 1.5-20% slope --
# 3-20x the textbook "mountain stream" value -- and say plainly that using
# table n there yields "substantially overestimated flow velocities".
#
# So this module uses a table value only on genuinely gentle ground, and
# Jarrett's (1984) measured steep-channel relation above that.

## Manning n for an ordinary lowland natural channel -- "clean, winding,
## some pools and shoals" sits around 0.033-0.040 in Chow's table; 0.035 is
## the standard mid value for a natural stream and what USGS WSP 1849's own
## gauged reaches cluster near.
##
## Units are m^(-1/3)*s, NOT dimensionless -- but the NUMBER is identical in
## SI and English (the English form's 1.486 factor absorbs the conversion),
## so a tabulated n is used directly and must never be unit-converted.
const LOWLAND_MANNING_N := 0.035

## Slope at/above which Jarrett's steep-channel relation replaces the table
## value. Jarrett's own validity band is 0.002-0.034 (0.2-3.4%); below
## 0.002 the table value is the better-supported one.
const STEEP_SLOPE_THRESHOLD := 0.002

## Jarrett (1984), SI form: n = 0.32 * S^0.38 * R^(-0.16), fitted to 75
## measurements across 21 Colorado sites (slope 0.2-3.4%, n 0.028-0.16,
## velocity 0.27-2.6 m/s). Printed in SI in Yochum et al. 2012 Table 1; the
## English form (0.39) in the HEC-RAS reference manual is the same relation
## (0.39 * 0.3048^0.16 = 0.3225).
const JARRETT_COEFFICIENT := 0.32
const JARRETT_SLOPE_EXPONENT := 0.38
const JARRETT_RADIUS_EXPONENT := -0.16

## Broad-crested weir discharge coefficient (Zachoval et al. 2014, J.
## Hydrol. Hydromech. 62(2):145-149, eq. 4a) -- a dry-stacked stone dam
## crest is broad, not a sharp plate. Collapsed with the weir equation's own
## (2/3)*sqrt(2g) into WEIR_FLOW_COEFFICIENT below.
const WEIR_DISCHARGE_COEFFICIENT := 0.845

## Q = C_d * (2/3) * sqrt(2g) * b * h^1.5, with the constants folded:
## 0.845 * (2/3) * sqrt(2*9.81) = 1.4407. A sharp-crested plate (C_D 0.62)
## would give 1.831 instead -- i.e. a sharp weir passes ~27% more water at
## the same head, which is the entire sharp-vs-broad distinction.
const WEIR_FLOW_COEFFICIENT := 1.4407

## Below this head the weir equation stops being valid: surface tension
## dominates and the discharge coefficient is no longer constant. Both
## Zachoval and ISO 3846 give the same ~0.06 m floor. Overtopping below it
## is reported as zero rather than as a fictitious trickle.
const MIN_WEIR_HEAD_M := 0.06


## Hydraulic radius R = A/P for a rectangular channel: R = bh/(b+2h).
##
## The wide-channel shortcut R ~ h costs real accuracy -- at b/h = 10 it
## overestimates velocity by 11%, at b/h = 2 by 37% -- and the exact form is
## one extra divide, so this uses the exact form. (b/h ratios: 100 -> R/h
## 0.980, 50 -> 0.962, 20 -> 0.909, 10 -> 0.833, 5 -> 0.714, 2 -> 0.500.)
static func hydraulic_radius(depth_m: float, width_m: float) -> float:
	if depth_m <= 0.0 or width_m <= 0.0:
		return 0.0
	return (width_m * depth_m) / (width_m + 2.0 * depth_m)


## Manning n for a channel of this slope and hydraulic radius -- the table
## value on gentle ground, Jarrett's measured steep-channel relation above
## STEEP_SLOPE_THRESHOLD (see this file's roughness note above for why that
## switch is not optional).
##
## Takes the maximum of the two at the boundary so roughness never DROPS as
## a channel steepens, which would be physically backwards.
static func manning_n(slope: float, hydraulic_radius_m: float) -> float:
	if slope < STEEP_SLOPE_THRESHOLD:
		return LOWLAND_MANNING_N
	var radius := maxf(hydraulic_radius_m, 0.05)  # Jarrett is undefined at R=0
	var jarrett := (
		JARRETT_COEFFICIENT
		* pow(slope, JARRETT_SLOPE_EXPONENT)
		* pow(radius, JARRETT_RADIUS_EXPONENT)
	)
	return maxf(jarrett, LOWLAND_MANNING_N)


## Manning's equation, SI form: V = (1/n) * R^(2/3) * S^(1/2).
##
## The SI coefficient is exactly 1.0 (USGS WSP 1849 p.7: "V = 1.486 R^2/3
## S^1/2 / n (English units) or V = R^2/3 S^1/2 / n (metric units)");
## variable units per FHWA HDS-4 Metric, eq. 13 (V m/s, R m, S m/m).
static func velocity_from_radius(hydraulic_radius_m: float, slope: float, n: float) -> float:
	if hydraulic_radius_m <= 0.0 or slope <= 0.0 or n <= 0.0:
		return 0.0
	return (1.0 / n) * pow(hydraulic_radius_m, 2.0 / 3.0) * sqrt(slope)


## Manning velocity for a WIDE channel, taking depth directly as the
## hydraulic radius. Used where the caller has a depth but no meaningful
## width (the normal-depth solve below is derived on the same wide-channel
## assumption, so the two stay consistent with each other).
static func velocity(depth_m: float, slope: float, n: float) -> float:
	return velocity_from_radius(depth_m, slope, n)


## Normal (uniform-flow) depth for a given discharge -- the closed-form
## wide-channel solution h = (n*q/sqrt(S))^(3/5), where q = Q/b is discharge
## per unit width (Apsley, Hydraulics 3, OCFBasics 1.2).
##
## Closed form matters: depth and velocity are NOT independently choosable
## (continuity Q = A*V binds them), and the naive way to satisfy both is to
## iterate to a fixed point. This solves it in one step instead -- which is
## what makes real hydraulics affordable per-tile on a chunk-streamed world.
static func normal_depth(discharge_m3_s: float, width_m: float, slope: float, n: float) -> float:
	if discharge_m3_s <= 0.0 or width_m <= 0.0 or slope <= 0.0 or n <= 0.0:
		return 0.0
	var unit_discharge := discharge_m3_s / width_m
	return pow(n * unit_discharge / sqrt(slope), 0.6)


## Gauge (above-atmospheric) hydrostatic pressure at a depth below the free
## surface: p = rho*g*h, in pascals. The classic check: 10 m of water is
## ~98.1 kPa, about one atmosphere.
static func hydrostatic_pressure_pa(depth_m: float) -> float:
	if depth_m <= 0.0:
		return 0.0
	return WATER_DENSITY_KG_M3 * GRAVITY_M_S2 * depth_m


## Total hydrostatic force on a vertical face (a dam) holding back water of
## this depth, across this width, in newtons: F = 0.5*rho*g*h^2*b.
##
## The 0.5 is because pressure grows linearly from 0 at the surface to
## rho*g*h at the bed, so the average over the face is half the maximum.
## The resultant acts at 1/3 of the depth up from the bed.
##
## Note the SQUARE: doubling the pooled depth QUADRUPLES the load. That is
## why a dry-stone dam that holds comfortably at one depth bursts at twice
## it, and it is the physical basis of the dam-failure mechanic rather than
## an invented threshold.
static func hydrostatic_force_newtons(depth_m: float, width_m: float) -> float:
	if depth_m <= 0.0 or width_m <= 0.0:
		return 0.0
	return 0.5 * WATER_DENSITY_KG_M3 * GRAVITY_M_S2 * depth_m * depth_m * width_m


## Discharge spilling over a dam crest, given the head of water standing
## ABOVE that crest and the crest's width: Q = 1.4407 * b * h^1.5 (broad-
## crested, see WEIR_FLOW_COEFFICIENT).
##
## Zero below MIN_WEIR_HEAD_M -- the equation genuinely stops holding for a
## trickle, so reporting a number there would be false precision.
static func weir_overflow_m3_s(head_above_crest_m: float, crest_width_m: float) -> float:
	if head_above_crest_m < MIN_WEIR_HEAD_M or crest_width_m <= 0.0:
		return 0.0
	return WEIR_FLOW_COEFFICIENT * crest_width_m * pow(head_above_crest_m, 1.5)


## The head that makes a crest of this width pass exactly `discharge_m3_s` --
## the inverse of weir_overflow_m3_s, and a dam's real steady state: the
## pool rises until what spills over equals what the river brings in.
static func equilibrium_weir_head_m(discharge_m3_s: float, crest_width_m: float) -> float:
	if discharge_m3_s <= 0.0 or crest_width_m <= 0.0:
		return 0.0
	return pow(discharge_m3_s / (WEIR_FLOW_COEFFICIENT * crest_width_m), 2.0 / 3.0)
