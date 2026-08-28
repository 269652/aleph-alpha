extends RefCounted

## Stylized procedural river fallback for everywhere RiverCatalog's curated
## rivers don't reach -- see docs/concept/rivers.md's "Procedural fallback"
## section for why this is a noise-contour proxy, not a flow-accumulation
## simulation (a real one is infeasible on a chunk-streamed ~40,000 x 20,000
## tile world with no point at which a global drainage pass could run).

## Fixed seed so the same real-world location always procedurally reads the
## same way across sessions/reloads -- the same determinism
## EarthChunkGenerator's own moisture noise (seed 424242) already commits
## to, just a different seed so the two fields don't correlate.
const NOISE_SEED := 918273

## Wavelength of roughly 1/NOISE_FREQUENCY tiles (~100 tiles, ~100km at this
## world's ~1km/tile scale) between contour crossings -- a plausible, but
## not real-data-derived, minor-waterway spacing.
const NOISE_FREQUENCY := 0.01

## How close to the iso-value 0.0 a noise sample must land to count as "on a
## contour line" -- narrow enough that contour lines read as winding threads
## rather than filling half the map (see test_is_river_candidate_is_not_true_everywhere).
const ISO_BAND := 0.02

## A procedural river only ever appears in the lower fraction of the real
## land elevation band between sea level and the mountain threshold -- real
## rivers run through lowlands, never along the foot of the highest peaks,
## even though placement itself isn't tracing real drainage.
const MAX_ELEVATION_FRACTION := 0.6

var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = NOISE_SEED
	_noise.frequency = NOISE_FREQUENCY


## Pure elevation gate: true only for real land strictly between sea_level
## and MAX_ELEVATION_FRACTION of the way up to mountain_level.
func passes_elevation_gate(elevation: float, sea_level: float, mountain_level: float) -> bool:
	if elevation < sea_level or elevation >= mountain_level:
		return false
	var elevation_fraction := (elevation - sea_level) / (mountain_level - sea_level)
	return elevation_fraction <= MAX_ELEVATION_FRACTION


## Pure contour test: true when a raw noise sample sits within ISO_BAND of
## the 0.0 iso-value.
func is_on_contour(noise_value: float) -> bool:
	return absf(noise_value) <= ISO_BAND


## The real per-tile query EarthChunkGenerator calls: the elevation gate
## AND a real seeded noise sample at (global_x, global_y) on a contour.
## elevation/sea_level/mountain_level are values the caller already computed
## for this cell -- no redundant elevation sampling here.
func is_river_candidate(
	global_x: int, global_y: int, elevation: float, sea_level: float, mountain_level: float
) -> bool:
	if not passes_elevation_gate(elevation, sea_level, mountain_level):
		return false
	return is_on_contour(_noise.get_noise_2d(global_x, global_y))
