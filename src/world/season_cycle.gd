extends RefCounted

## A deterministic calendar season cycle (see concept/seasons.md): elapsed
## game-time -> spring/summer/autumn/winter plus smooth warmth and growth
## modifiers that other systems (fruit phenology, vegetation growth, weather,
## survival exposure) read instead of a flat constant. Pure -- season is a
## function of time only, so every reader agrees.

## Seasons in order from the start of a year.
const SEASONS := ["spring", "summer", "autumn", "winter"]

## Real seconds per in-game year, compressed so a single play session spans
## multiple seasons. Tuned constant, exercised by the season-cycle tests.
const SECONDS_PER_YEAR := 1200.0


## Fraction [0,1) through the current year.
func year_fraction(elapsed_seconds: float) -> float:
	return fposmod(elapsed_seconds, SECONDS_PER_YEAR) / SECONDS_PER_YEAR


## The discrete season label. The year is four equal quarters starting at
## spring (year_fraction 0).
func season_at(elapsed_seconds: float) -> String:
	var index := int(year_fraction(elapsed_seconds) * SEASONS.size())
	return SEASONS[clampi(index, 0, SEASONS.size() - 1)]


## Seasonal warmth [0,1]: a smooth cosine peaking mid-summer (~3/8 of the year,
## the middle of the summer quarter) and troughing mid-winter (~7/8). Stands in
## for the seasonal temperature/photoperiod swing driving fruit ripening.
func warmth_modifier(elapsed_seconds: float) -> float:
	# Shift the phase so the peak lands mid-summer rather than at year start.
	var phase := (year_fraction(elapsed_seconds) - 0.375) * TAU
	return 0.5 + 0.5 * cos(phase)


## How vigorously vegetation grows this season [0,1]: warm-season high, cold-
## season low. Same curve as warmth but with a raised floor so plants never
## fully stop growing (dormancy, not death).
func growth_modifier(elapsed_seconds: float) -> float:
	return 0.2 + 0.8 * warmth_modifier(elapsed_seconds)
