extends RefCounted
## Reads season_cycle.gd's real day/season clock forward -- docs/concept/
## wayfinding.md's Star chart / seasonal almanac item.
const SeasonCycle = preload("res://src/world/season_cycle.gd")


## The season after current_season in SeasonCycle.SEASONS, wrapping
## winter -> spring. Unrecognized names fall through to spring (index -1 +
## 1 wraps to 0 via the modulo below), the same "don't crash on an unknown
## input" convention as compass.gd/weather_model.gd's own match fallbacks.
static func next_season(current_season: String) -> String:
	var seasons := SeasonCycle.SEASONS
	var index := seasons.find(current_season)
	return seasons[(index + 1) % seasons.size()]


## Real days (not seconds) remaining until the season turns, derived from
## SeasonCycle's own real seconds_until_season/SECONDS_PER_DAY -- no
## invented constant.
static func days_until_next_season(elapsed_seconds: float) -> float:
	var cycle := SeasonCycle.new()
	var current := cycle.season_at(elapsed_seconds)
	var upcoming := next_season(current)
	var seconds := cycle.seconds_until_season(elapsed_seconds, upcoming)
	return seconds / SeasonCycle.SECONDS_PER_DAY
