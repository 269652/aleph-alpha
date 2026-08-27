extends RefCounted

## Pure decision logic for docs/concept/easter_eggs.md's Kraken -- the
## collection's one deliberately higher-stakes, CONDITION-triggered (not
## coordinate-triggered) entry. Every other cameo in this doc is pinned to
## one real-world lat/lon (see EasterEggSightings/EasterEggCreatures); the
## Kraken instead fires on a real CONDITION already computed live by this
## project's own weather/time systems -- open ocean, night, and an active
## storm (WeatherModel), all at once, anywhere on the map -- so there is no
## GeoCoordinates lookup here at all: there is no single point to be near.
##
## Every input below is a plain, already-computed primitive (a bool/String/
## float), never a live system/node reference -- the same "caller does the
## real-world computation, this module only decides" shape
## EasterEggSightings/EasterEggCreatures already use for `is_night` (see
## scenes/world.gd's `elevation <= 0.0`, built from SolarPosition), so this
## stays fully unit-testable without a node/scene/chunk manager in sight. A
## real caller (scenes/world.gd) would compute:
##   - is_night the exact same way every other Easter egg already does:
##     SolarPosition.elevation_degrees(...) <= 0.0 at the player's own
##     real-world lat/lon.
##   - weather from WeatherModel.weather_at(day, region_seed) at the
##     player's own chunk/region.
##   - depth_normalized from BiomeClassifier.depth_at(elevation) at the
##     player's own tile (EarthChunkManager.elevation_at_global) -- 0.0 at
##     sea level, 1.0 at the ocean floor. is_open_ocean below turns that
##     into the "open ocean, not a shallow coastal shelf" gate itself.
##
## Deliberately NOT wired into scenes/world.gd's live per-frame loop here
## (unlike EasterEggCreatures) -- a documented scope call, not an
## oversight; see docs/progress.md's Easter Eggs section for why an actual
## live spawn+combat encounter is left to a later integration pass.
##
## Aggro design (docs/concept/easter_eggs.md: "actually a real fight if it
## notices you" -- genuinely dangerous, but never a free ambush): this
## module answers ONLY "should the Kraken appear at all", never "does it
## attack" -- that's CreatureInfo.WORLD_BOSS_SPECIES/BossAggro's job, reused
## as-is for the Kraken (see creature_info.gd's own comment on this). The
## Kraken does not join worldbosses.md's regional-mythology roster --
## WORLD_BOSS_SPECIES gates a purely mechanical aggro/provocation rule, not
## membership in that system -- it just happens to want the exact same
## "doesn't proactively attack an unprovoked player, but fights for real
## once a real hit lands" behavior, so it reuses the same flag rather than
## inventing a second aggro-gate mechanism for one creature.

## How deep (BiomeClassifier.depth_at's normalized [0,1] scale, 0 = sea
## level, 1 = ocean floor) a tile must be before it counts as OPEN ocean
## rather than a shallow coastal shelf a wading player could stand on.
## Pinned as a named constant, not an eyeballed inline number, and
## exercised by is_open_ocean's own tests in test_kraken_trigger.gd: a
## first-pass midpoint (this project has no real playtesting data on where
## "open ocean" should start any more than it does for any other Easter-egg
## threshold -- same situation as BossAggro.MIN_DAMAGE_FRACTION_OF_MAX_
## HEALTH/EasterEggSightings' chance_per_check values), deliberately above
## the halfway point of the normalized range so "barely submerged past the
## shoreline" doesn't qualify.
const OPEN_OCEAN_MIN_DEPTH := 0.5

## Vanishingly rare -- the doc's own words -- and pinned as strictly rarer
## than every other coordinate-triggered cameo in the project by a wide
## margin (EasterEggCreatures.SIGHTINGS' squallmaw, this project's previous
## rarest entry at 0.0004 chance per check, itself already tuned "wildly
## lower than even the rarest ordinary predator"), enforced as a relative
## property test (test_kraken_trigger.gd) rather than an isolated eyeballed
## literal -- same "no eyeballed thresholds" discipline as every other
## chance_per_check constant in this project. The Kraken is also gated on
## three simultaneous real-world conditions that must ALL hold before this
## roll is even drawn (night AND storm AND open ocean), so its true overall
## rarity is far below this number alone.
const CHANCE_PER_CHECK := 0.00002


## True if depth_normalized is deep enough to count as open ocean rather
## than shallow coastal water.
func is_open_ocean(depth_normalized: float) -> bool:
	return depth_normalized >= OPEN_OCEAN_MIN_DEPTH


## All three real-world conditions the doc requires, at once: real night, an
## active storm, and open (not shallow/coastal) ocean. No roll yet -- a
## caller can check this cheaply before ever drawing a random number, the
## same is_in_range-vs-check_one split EasterEggCreatures already uses.
func is_eligible(is_night: bool, weather: String, depth_normalized: float) -> bool:
	return is_night and weather == "storm" and is_open_ocean(depth_normalized)


## One full check: true only if every condition holds AND `roll` (a
## caller-supplied [0, 1) draw -- pass randf() in real play, a fixed value
## in tests) clears CHANCE_PER_CHECK. False for anything short of all four
## conditions, including an otherwise-perfect roll on a calm sea.
func check(is_night: bool, weather: String, depth_normalized: float, roll: float) -> bool:
	if not is_eligible(is_night, weather, depth_normalized):
		return false
	return roll < CHANCE_PER_CHECK
