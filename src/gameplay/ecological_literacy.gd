extends RefCounted

## XP-award arithmetic for "ecological literacy" (docs/concept/progression.md
## "Ecological literacy: XP from reading the world, not just fighting it"):
## real bonus XP for skillfully engaging a real simulation system, instead of
## a flat per-action grind. Pure functions only -- the real triggers
## themselves (was the fruit at genuine peak ripeness, was the village
## genuinely hungry) are read from FruitingModel/VillageMarket's own real
## state by the callers (EarthChunkManager.harvest_peak_fruit_near,
## Player.sell_food_to_village); this class only turns that real boolean into
## an XP amount, fed into Player.gain_experience/ExperienceTrack exactly like
## combat XP already is.

## Off-peak harvest / a sale to an already-well-stocked village: a modest
## baseline for engaging the system at all -- not zero (foraging/trading are
## real actions worth something) but well under the skillful case.
const HARVEST_XP_BASE := 2
const VILLAGE_SALE_XP_BASE := 2

## On top of the base, for correctly reading a real signal: harvesting at
## genuine peak ripeness (FruitingModel.is_peak_ripe), or selling into a
## village that was genuinely hungry (VillageMarket.can_buy_meal() read false
## right before the sale). Sized so each skillful total (base + bonus) equals
## Player.XP_PER_KILL (6) exactly -- there is no independent real-world
## anchor for a game-balance XP number (the same category as XP_PER_KILL/
## HEALTH_PER_LEVEL themselves), so the deliberate anchor here is internal
## consistency with the existing XP economy: reading the world well is worth
## about as much as one level-1 kill, not a throwaway fraction of it. Pinned
## by test_skillful_totals_match_the_existing_kill_xp_scale.
const HARVEST_XP_PEAK_BONUS := 4
const VILLAGE_FEEDING_XP_BONUS := 4


## XP for a direct-from-the-tree fruit/nut harvest (see
## EarthChunkManager.harvest_peak_fruit_near) -- more when `is_peak` is true.
func harvest_xp(is_peak: bool) -> int:
	return HARVEST_XP_BASE + (HARVEST_XP_PEAK_BONUS if is_peak else 0)


## XP for selling real gathered food into a village's VillageMarket (see
## Player.sell_food_to_village) -- more when `was_hungry` is true.
func village_sale_xp(was_hungry: bool) -> int:
	return VILLAGE_SALE_XP_BASE + (VILLAGE_FEEDING_XP_BONUS if was_hungry else 0)
