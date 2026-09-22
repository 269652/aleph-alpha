extends RefCounted
## The hour a brand-new character opens their eyes (docs/concept/arrival.md).
##
## This world's sky is the real sky: World._process reads the system UTC
## clock and drives SolarPosition.elevation_degrees from it at the spawn's
## real latitude and longitude. That is the right decision for a game set on
## the real Earth, and it is also why a game shown to a friend on a September
## evening began in darkness, in the cold, with nothing said.
##
## The clause does not move the sun. It moves WHICH REAL HOUR a new
## character's clock starts on -- to first light -- and then gives that hour
## back, smoothly and exactly, within a few in-game days. After
## CONVERGENCE_DAYS this module is the identity function and changes nothing
## about this world ever again.
##
## Pure: a RefCounted of static functions, no scene tree, no world, no file
## access, in the spirit of spell_cost.gd and journey_ring.gd. The caller
## hands in two numbers and gets an hour back.

## Civil dawn: the sun's centre 6 degrees below the horizon. The real
## astronomical definition of first light -- the point at which the horizon
## is distinguishable and work outdoors is possible without a lamp -- and
## therefore the hour a person who slept outside actually opens their eyes.
const CIVIL_TWILIGHT_DEGREES := -6.0

## Earth's own rotation: 360 degrees in 24 hours. The same factor
## SolarPosition already multiplies hour angles by (its `15.0 * (local_hour
## - 12.0)`), restated here rather than preloaded for the reason JourneyRing
## gives for restating KM_PER_TILE -- a small pure module should not pull in
## the astronomy layer to divide by 15 -- and pinned against a full rotation
## by test_first_light_is_derived_from_the_suns_own_rate_of_climb.
const DEGREES_PER_HOUR := 15.0

## Sunrise on an equinox, local solar time, at EVERY latitude on Earth: with
## declination at zero the sunrise hour angle is exactly -90 degrees, i.e.
## six hours before solar noon, wherever you stand. The one sunrise hour the
## whole planet agrees on, and the only defensible anchor for a constant that
## cannot know the player's latitude. Checked against this repo's own
## SolarPosition across a latitude sweep rather than asserted here.
const EQUINOX_SUNRISE_HOUR := 6.0

## 05:36 local solar time. Six degrees of climb at fifteen degrees an hour is
## 24 minutes -- the length of civil twilight at the equator, and the
## shortest it is anywhere, so this is first light at its earliest honest
## reading rather than a number that flatters the demo.
const FIRST_LIGHT_HOUR := EQUINOX_SUNRISE_HOUR + CIVIL_TWILIGHT_DEGREES / DEGREES_PER_HOUR

const HOURS_PER_DAY := 24.0

## The farthest any hour can be from first light once you go the short way
## round a clock face. Half a day, by construction, and the worst case every
## bound below is derived from.
const MAX_OFFSET_HOURS := HOURS_PER_DAY / 2.0

## One in-game day is four real hours (SeasonCycle.SECONDS_PER_DAY), so
## in-game days elapsed times this figure IS real hours elapsed. That
## coupling is what lets the two-argument signature recover the hour the
## character arrived at, and it is pinned against SeasonCycle itself by
## test_an_in_game_day_is_the_season_cycles_own_day rather than trusted.
const REAL_HOURS_PER_IN_GAME_DAY := 4.0

## Where the clock would STOP. Converging the worst possible offset over this
## many in-game days makes the catch-up rate exactly zero: a sun nailed to
## the horizon for twelve real hours, which is a worse first impression than
## the darkness this module exists to fix.
const STALL_DAYS := MAX_OFFSET_HOURS / REAL_HOURS_PER_IN_GAME_DAY

## The smallest whole day past the stall -- four in-game days, sixteen real
## hours of play. Derived, not chosen; see MIN_CLOCK_RATE for what it buys.
const CONVERGENCE_DAYS := STALL_DAYS + 1.0

## The slowest the in-game clock ever runs while it converges: quarter speed,
## in the worst case (an arrival almost exactly twelve hours from first
## light). The sky still climbs, the day still ends, and nothing in the world
## ever waits on a frozen sun. Approached arbitrarily closely as the arrival
## hour nears the antipode of first light, which is exactly what
## test_the_slowest_the_clock_ever_runs_is_the_pinned_floor measures.
const MIN_CLOCK_RATE := (
	1.0 - MAX_OFFSET_HOURS / (REAL_HOURS_PER_IN_GAME_DAY * CONVERGENCE_DAYS)
)

## Passed as `arrival_real_hour` when the caller has not kept the hour the
## character arrived at and wants it recovered from the day count instead.
const AUTO_ARRIVAL := -1.0


## The real local hour a character who has been alive `in_game_days_elapsed`
## days must have arrived at, recovered from the world's own four-real-hours
## -per-in-game-day coupling.
##
## Exact within a continuous session, which is the whole of a first arrival.
## It is an approximation across a quit and a return: WorldClockPersistence
## stops the world clock when the game closes, and the wall clock does not
## stop with it. A caller that has persisted the real arrival hour should
## pass it to local_hour_for directly rather than rely on this.
static func arrival_hour_for(real_local_hour: float, in_game_days_elapsed: float) -> float:
	var real_hours_elapsed := in_game_days_elapsed * REAL_HOURS_PER_IN_GAME_DAY
	return fposmod(real_local_hour - real_hours_elapsed, HOURS_PER_DAY)


## How far the clock is shifted at the moment of arrival: the SHORT way
## round the clock face from the arrival hour to first light, so a 03:00
## arrival waits two and a half hours and a 20:00 arrival sleeps through to
## morning rather than being dragged backwards through the afternoon.
##
## Always in [-MAX_OFFSET_HOURS, +MAX_OFFSET_HOURS].
static func offset_at_arrival(arrival_real_hour: float) -> float:
	return wrapf(
		FIRST_LIGHT_HOUR - arrival_real_hour, -MAX_OFFSET_HOURS, MAX_OFFSET_HOURS
	)


## How much of the arrival offset is still being applied, [0, 1]: the whole
## of it at the moment of arrival, none of it from CONVERGENCE_DAYS onward,
## and a straight line between.
##
## Linear on purpose. A linear decay makes the catch-up rate CONSTANT (see
## clock_rate_for), so the in-game clock simply runs a little slow or a
## little fast for four days; any curve here would put an acceleration in
## the sky for no gain a player could name.
static func decay_fraction(in_game_days_elapsed: float) -> float:
	if in_game_days_elapsed <= 0.0:
		return 1.0
	if in_game_days_elapsed >= CONVERGENCE_DAYS:
		return 0.0
	return 1.0 - in_game_days_elapsed / CONVERGENCE_DAYS


## The offset still applied on a given day, hours. Monotone toward zero, and
## zero for ever after CONVERGENCE_DAYS.
static func offset_hours(arrival_real_hour: float, in_game_days_elapsed: float) -> float:
	return offset_at_arrival(arrival_real_hour) * decay_fraction(in_game_days_elapsed)


## How fast the shown clock runs against the real one while it converges --
## 1.0 once it has. Constant for a given arrival, by construction: the real
## hour advances at 1, and the decaying offset gives back its whole self over
## REAL_HOURS_PER_IN_GAME_DAY * CONVERGENCE_DAYS real hours.
##
## Never zero and never negative (see MIN_CLOCK_RATE): a clock that stalls or
## runs backwards is a visible lurch in the sky, and it is precisely what the
## obvious implementation -- re-deriving the offset from the hour it is NOW
## rather than from the hour of arrival -- does to every evening arrival.
static func clock_rate_for(arrival_real_hour: float) -> float:
	var window := REAL_HOURS_PER_IN_GAME_DAY * CONVERGENCE_DAYS
	return 1.0 - offset_at_arrival(arrival_real_hour) / window


## The local hour to show (and to drive the sun from, via
## SolarPosition.utc_hour_for_local -- the same door the /time command
## already uses, so the readout, the elevation and the hillshade move
## together).
##
## `real_local_hour` is what SolarPosition.local_hour says it really is here.
## `in_game_days_elapsed` is measured from CHARACTER CREATION, not from
## session start: a save made on day 9 loads on day 9, and this function is
## the identity for it. That is the whole of why a loaded save is untouched.
##
## `arrival_real_hour` is optional. Left at AUTO_ARRIVAL it is recovered by
## arrival_hour_for; a caller that persisted the real arrival hour should
## pass it, which is exact across a reload and also sidesteps the one knife
## edge in the recovery (an arrival within float noise of the antipode of
## first light, where the short way round flips sign).
static func local_hour_for(
	real_local_hour: float, in_game_days_elapsed: float, arrival_real_hour: float = AUTO_ARRIVAL
) -> float:
	var anchor := arrival_real_hour
	if anchor < 0.0:
		anchor = arrival_hour_for(real_local_hour, in_game_days_elapsed)
	return fposmod(
		real_local_hour + offset_hours(anchor, in_game_days_elapsed), HOURS_PER_DAY
	)
