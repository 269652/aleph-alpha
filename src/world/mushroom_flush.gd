extends RefCounted

## Pure fungal fruiting-trigger model (see docs/concept/mushrooms.md's
## "Where and when a flush happens"). Same shape as EarthwormPatch.
## surface_drive: a real moisture term (rain wets the ground, the same
## wetness curve every soil-dwelling trigger in this project already uses)
## -- but SEASON-weighted rather than cold-gated. surface_drive's warmth
## term gates on cold (frozen ground stops a worm dead, otherwise wetness
## alone decides); real temperate fungal fruiting is instead heavily
## concentrated in one season specifically -- cooling temperatures plus
## autumn rain is the classic "mushroom season" -- so this reads the
## calendar season directly (SeasonCycle.season_at's own string) rather
## than a continuous warmth figure, the same discrete season-name gate
## leaf_litter.md's autumn leaf-fall trigger already uses.

## Real: fruiting is near-exclusively an autumn event. A small residual
## flush in spring/summer acknowledges real off-season fruitings exist
## without making the mechanic invisible outside autumn -- the same
## "named trickle, not zero" idiom leaf_litter.md's
## LEAF_SUMMER_TRICKLE_CHANCE uses. Winter ground is genuinely too cold for
## a fruiting body, so it is exactly zero, matching EarthwormPatch's own
## hard cold cutoff.
const SEASON_MULTIPLIER := {
	"spring": 0.05,
	"summer": 0.05,
	"autumn": 1.0,
	"winter": 0.0,
}

## An unrecognized season string is a defensive fallback, not a real
## calendar state -- reads like spring/summer's own small trickle, never
## like autumn's full flush and never like winter's hard zero.
const _DEFAULT_SEASON_MULTIPLIER := 0.05


## How hard real conditions are pushing a flush this step, [0,1]. `moisture`
## is how wet the ground is (see WeatherModel.soil_moisture) -- the exact
## real rain trigger EarthwormPatch.surface_drive already reads, unchanged
## here since wet ground is wet ground regardless of which organism
## responds to it. `season` is SeasonCycle.season_at's own string.
static func flush_drive(moisture: float, season: String) -> float:
	var season_term: float = SEASON_MULTIPLIER.get(season, _DEFAULT_SEASON_MULTIPLIER)
	return clampf(clampf(moisture, 0.0, 1.0) * season_term, 0.0, 1.0)
