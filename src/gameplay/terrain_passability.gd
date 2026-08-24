extends RefCounted

## Whether/how fast the player can cross a given slope (see
## docs/concept/terrain_relief.md's "Passability: ask before you step").
## Pure function of a slope in real degrees (see terrain_relief.gd's
## slope_at) -- the same "one shared field, several consumers" relationship
## that doc's hillshading and mountain-ore sections also have to slope.
##
## Static, not instanced: no state, matching every other pure-formula module
## in this project (StoneSize, PebbleDispersion) that's called as a
## namespace rather than constructed.

## Below this, ordinary ground -- no speed penalty at all. Roughly where
## real hiking starts feeling like a genuine uphill effort rather than flat
## walking (see docs/concept/terrain_relief.md's real mountaineering slope
## bands).
const SOFT_THRESHOLD_DEG := 18.0

## At and beyond this, the slope is genuine scrambling/technical-climbing
## territory -- impassable on foot, per the same real mountaineering bands.
const HARD_THRESHOLD_DEG := 45.0

## What a climbing rope actually buys: real additional steepness, not
## infinite steepness. Beyond THIS, terrain is impassable even roped.
const HARD_THRESHOLD_WITH_ROPE_DEG := 65.0

## The slowest ordinary walking gets on the steepest ground it can still
## cross at all -- never zero, so the soft slowdown reads as "hard going"
## rather than "stuck," which is what the separate hard-refusal check is
## for.
const MIN_SPEED_MULTIPLIER := 0.3


## Movement-speed multiplier for a given real slope in degrees -- 1.0 (no
## penalty) at or below SOFT_THRESHOLD_DEG, linearly falling to
## MIN_SPEED_MULTIPLIER by HARD_THRESHOLD_DEG, and staying at that floor
## beyond it (a caller that got this far without being refused by
## is_passable is climbing with a rope, and still climbs slowly). The same
## "environment scales a movement multiplier" shape
## weather_model.gd's movement_speed_modifier already uses for rain/storm,
## just driven by slope instead of weather state.
static func speed_multiplier(slope_deg: float) -> float:
	if slope_deg <= SOFT_THRESHOLD_DEG:
		return 1.0
	var t := clampf(
		(slope_deg - SOFT_THRESHOLD_DEG) / (HARD_THRESHOLD_DEG - SOFT_THRESHOLD_DEG), 0.0, 1.0
	)
	return lerpf(1.0, MIN_SPEED_MULTIPLIER, t)


## Whether a slope this steep can be crossed at all. `has_climbing_gear`
## raises the threshold from HARD_THRESHOLD_DEG to
## HARD_THRESHOLD_WITH_ROPE_DEG -- real additional capability, not a
## bypass; genuinely vertical terrain stays impassable either way. No item/
## equipment concept currently sets this true anywhere in live gameplay
## (see docs/progress.md's Transportation section) -- the parameter exists
## now so this function is already correct and already tested for the day
## a real climbing rope exists, the same "plumbing ahead of the payoff"
## shape IllustratedStoneSprite's has_variants gate already used for art
## that didn't exist yet either.
static func is_passable(slope_deg: float, has_climbing_gear: bool = false) -> bool:
	var threshold := HARD_THRESHOLD_WITH_ROPE_DEG if has_climbing_gear else HARD_THRESHOLD_DEG
	return slope_deg < threshold
