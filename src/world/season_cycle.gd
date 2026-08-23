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
## How long one in-game DAY lasts in real time.
##
## Four real hours, as specified directly. This is the clock the rest of the
## world's slow biology is measured against -- how often a kingfisher eats,
## how long a tree takes to come round to fruit again -- and it deliberately
## puts those on a scale a player experiences across sessions rather than
## within one. It sits alongside the life cycle's own real-day timings (see
## LifeCycle), which are wall-clock for the same reason.
##
## It was 25 seconds, implied by a 20-minute year: fast enough that a
## kingfisher eating "a couple of fish a day" still stripped a pond bare in
## minutes.
const SECONDS_PER_DAY := 4.0 * 60.0 * 60.0

## Days to a year -- the figure the weather model already assumed.
const DAYS_PER_YEAR := 48.0

## Derived, so the day and the calendar can never drift apart. Eight real days
## to a year, two to a season.
const SECONDS_PER_YEAR := SECONDS_PER_DAY * DAYS_PER_YEAR


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


## How far the world clock must move FORWARD to land at the start of `season`.
##
## Forward only, and that is the whole design. Season is a pure function of
## elapsed world time, so the obvious way to honour `/season winter` is to set
## the clock to winter -- but every other system measures itself against that
## same clock. A tree records the age it was `planted_at`; fruiting records the
## time it last ran. Winding the clock BACK gives a tree a negative age and
## hands `fallen_between` a span that runs backwards. Skipping forward is the
## only move that leaves every other clock consistent.
##
## Asking for the season you are already in therefore waits for it to come
## round again rather than doing nothing: you asked to watch it start.
## Unknown names move nothing.
func seconds_until_season(elapsed_seconds: float, season: String) -> float:
	var index := SEASONS.find(season)
	if index < 0:
		return 0.0
	var target := float(index) / float(SEASONS.size())
	var now := year_fraction(elapsed_seconds)
	var ahead := target - now
	if ahead <= 0.0:
		ahead += 1.0
	return ahead * SECONDS_PER_YEAR
