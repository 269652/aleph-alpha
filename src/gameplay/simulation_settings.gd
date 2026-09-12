extends RefCounted

## The player's own simulation-density knobs (docs/concept/
## ecosystem_dynamics.md "Simulation density: the player's own knobs"):
## pure sanitising and cap scaling, the same shape AudioSettings gives the
## master volume. Each knob scales one design ceiling -- ant foragers per
## mound (AntColony.MAX_CONCURRENT_FORAGERS), bee foragers per hive
## (BeeColony.MAX_CONCURRENT_FORAGERS), pollinators per chunk
## (AmbientFlyerRenderer.MAX_BUTTERFLIES_PER_CHUNK) -- and only ever DOWN:
## 1.0 is exactly today's behaviour, 0.0 the floor each ceiling's own model
## allows (a colony still sends one scout; a chunk may have no butterflies).
## Persisted by World in the `[simulation]` section of the shared settings
## file, driven by the Settings overlay's "Simulation" sliders, consumed by
## EarthChunkManager (see its set_population_density).

const KNOB_ANT_FORAGERS := "ant_foragers"
const KNOB_BEE_FORAGERS := "bee_foragers"
const KNOB_POLLINATORS := "pollinators"
const KNOBS: Array[String] = [KNOB_ANT_FORAGERS, KNOB_BEE_FORAGERS, KNOB_POLLINATORS]

const DEFAULT_DENSITY := 1.0


## Every knob at full density -- today's behaviour, and what a missing or
## unreadable setting reads as.
static func default_densities() -> Dictionary:
	var out := {}
	for knob in KNOBS:
		out[knob] = DEFAULT_DENSITY
	return out


## A density is a fraction of a ceiling: NaN falls back to the default (the
## same fallback AudioSettings.sanitize_volume makes), anything else clamps
## into [0, 1] -- a knob only ever lowers a ceiling, never raises one past
## what the design already allows.
static func sanitize_density(value: float) -> float:
	if is_nan(value):
		return DEFAULT_DENSITY
	return clampf(value, 0.0, 1.0)


## Knob by knob: unknown keys dropped, missing knobs at the default, every
## value sanitised -- what a config file's `[simulation]` section becomes.
static func sanitize_densities(raw: Dictionary) -> Dictionary:
	var out := default_densities()
	for knob in KNOBS:
		if raw.has(knob):
			out[knob] = sanitize_density(float(raw[knob]))
	return out


## `cap` scaled by `density`, rounded, never below `floor` -- the colony
## models' own floor of one (an unfed colony still sends its first scout)
## or the pollinator budget's zero.
static func scaled_cap(cap: int, density: float, floor: int) -> int:
	return maxi(floor, roundi(float(cap) * sanitize_density(density)))
