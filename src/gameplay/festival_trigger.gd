extends RefCounted

## Emergent festival conditions (concept/festivals.md "Emergent Festival
## Trigger System"): festivals fire off real simulated state (crop yield,
## the season clock) rather than a fixed calendar the player can memorize.

## Day-of-year values for the four astronomical solstices/equinoxes, using
## commonly-cited approximate dates for a 365-day (non-leap) year: spring
## equinox ~Mar 21 (day 80), summer solstice ~Jun 21 (day 172), autumn
## equinox ~Sep 23 (day 266), winter solstice ~Dec 21 (day 355). These are
## the only days a seasonal festival is defined; every other day is "".
const SEASONAL_FESTIVAL_DAYS: Dictionary = {
	80: "Spring Equinox Festival",
	172: "Summer Solstice Festival",
	266: "Autumn Equinox Festival",
	355: "Winter Solstice Festival",
}


## A harvest festival can trigger once the season's total harvest yield
## reaches threshold; the boundary is inclusive (meeting the threshold
## exactly counts as eligible, not just exceeding it).
func harvest_festival_eligible(total_harvest_yield: float, threshold: float) -> bool:
	return total_harvest_yield >= threshold


## Festival name for a defined seasonal festival day, "" on every other day.
func seasonal_festival_for_day(day_of_year: int) -> String:
	if SEASONAL_FESTIVAL_DAYS.has(day_of_year):
		return SEASONAL_FESTIVAL_DAYS[day_of_year]
	return ""


## Days remaining until the next seasonal festival, 0 on a festival day
## itself. Wraps around year-end to the first festival of the following
## year (never negative) when no festival remains later this year.
func days_until_next_seasonal_festival(day_of_year: int) -> int:
	var festival_days: Array = SEASONAL_FESTIVAL_DAYS.keys()
	festival_days.sort()
	for festival_day: int in festival_days:
		if festival_day >= day_of_year:
			return festival_day - day_of_year
	var days_left_in_year := 365 - day_of_year
	return days_left_in_year + int(festival_days[0])
