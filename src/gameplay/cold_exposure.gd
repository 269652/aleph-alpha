extends RefCounted

## Prolonged cold as a real duration clock (docs/concept/survival.md, "The four
## triggers" -> "Prolonged cold, as a real duration clock").
##
## The warmth meter has tracked `is_cold()`/`is_freezing()` from real ambient
## temperature since it was written (`WeatherModel.warmth_factor` via
## `EarthChunkManager.ambient_warmth`), and cold has always accelerated fitness
## loss -- but nothing read that signal for SICKNESS. So exposure had no
## memory: warm up, and it was as though the afternoon in the sleet never
## happened. This is the missing piece, and memory is the whole difference
## between a debuff and a consequence.
##
## **Real grounding.** Clinical hypothermia is a duration effect and is STAGED,
## not a pass/fail temperature check -- which is exactly why real wind-chill
## charts post "time to hypothermia" in minutes rather than naming a
## temperature at which one is simply hypothermic. Frostbite is a separate,
## faster, extremity-specific mechanism and is deliberately not modelled here.
##
## Pure and stateless, like Sickness/DiseaseModel/DebuffStack: the caller
## (Player) owns the accumulated exposure and passes it through each call.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How long continuously cold before exposure is total.
##
## Measured in the WORLD'S OWN DAY, the clock every slow body clock in this
## project keeps (SurvivalMeters.SECONDS_TO_STARVE is one whole day, a
## kingfisher's appetite, a songbird's crop, fruit going over). Three in-game
## hours.
##
## Not eyeballed against "how long before this nags a player" -- that is the
## two-clocks mistake SurvivalMeters' own header documents. It is an ORDERING
## against the meter this game already measures neglect with: a person dies of
## cold in hours and of hunger in weeks, so full cold exposure has to arrive
## far inside a single day of hunger. Bracketed from both sides by
## test_cold_takes_you_long_before_hunger_does and
## test_prolonged_means_a_real_part_of_a_day -- long enough that this is
## weather you have to sit in rather than weather you walk through.
const SECONDS_TO_FULL_EXPOSURE := SeasonCycle.SECONDS_PER_DAY / 8.0

## How much faster FREEZING takes you down than merely being cold.
##
## Because hypothermia is staged rather than one rate: the difference between
## a cold day and a killing one is how fast the core loses heat, not whether
## it is losing it. Pinned as an ordering by
## test_freezing_takes_you_down_faster_than_merely_cold.
const FREEZING_MULTIPLIER := 3.0

## How fast a warm player sheds accumulated exposure, against the rate cold
## built it.
##
## Below 1.0 deliberately, and this is the constant that gives the mechanic its
## memory. Real grounding: rewarming a chilled body runs at roughly half the
## rate cold strips heat from it -- active rewarming raises core temperature by
## about a degree an hour, against the two-plus a body loses in genuinely cold
## conditions. Pinned as an ordering by
## test_you_do_not_come_back_the_moment_you_step_inside.
const RECOVERY_MULTIPLIER := 0.5

## Where on the clock being chilled turns into being in danger.
##
## Real hypothermia is STAGED: mild hypothermia is survivable and largely
## self-correcting -- you shiver, you warm up, that is the end of it -- while
## moderate hypothermia is the stage that becomes an illness needing
## treatment. This constant is that boundary, so the early part of the clock
## carries no risk at all (test_no_risk_at_all_while_merely_chilled) and the
## last stretch carries a rising one (test_risk_rises_with_time_endured).
##
## The exact fraction is a placeholder pending real playtesting -- the same
## honesty convention Taming.PREDATOR_BREAK_FREE_MULTIPLIER's own doc comment
## uses. What is NOT arbitrary, and what the tests pin, is that it leaves real
## headroom on both sides: risk-free chill first, then a ramp rather than a
## switch.
const RISK_THRESHOLD := 2.0 / 3.0

## How often the player rolls against the risk once the clock has run out.
## A cadence rather than a per-frame roll, the same way Player's own disease
## roll is one discrete event rather than a continuous probability -- sixty
## rolls a second would make any nonzero chance a certainty within moments.
const ROLL_INTERVAL_SECONDS := 10.0

## The sickness prolonged cold causes. A player sickness id (see
## Player.sickness_id), deliberately NOT one of DiseaseModel's wildlife SIRS
## archetypes: hypothermia is not transmissible and has no reservoir, it is
## the environment doing it to you.
const SICKNESS_ID := "hypothermia"

const _PER_SECOND := 1.0 / SECONDS_TO_FULL_EXPOSURE


## The accumulated exposure after `delta_seconds` of the given weather.
##
## Rises only while genuinely cold -- faster while freezing -- and falls while
## warm, more slowly than it rose.
static func advance(exposure: float, cold: bool, freezing: bool, delta_seconds: float) -> float:
	var rate := _PER_SECOND
	if freezing:
		rate *= FREEZING_MULTIPLIER
	elif not cold:
		rate = -_PER_SECOND * RECOVERY_MULTIPLIER
	return clampf(exposure + rate * delta_seconds, 0.0, 1.0)


## What to hand Sickness.infection_chance as its `exposure_level`.
##
## Zero through the mild stage, then ramping across the rest of the clock --
## so staying out in it is genuinely worse than having just crossed the line,
## and there is no single instant at which the player becomes at risk.
static func infection_exposure(exposure: float) -> float:
	if exposure < RISK_THRESHOLD:
		return 0.0
	return clampf(inverse_lerp(RISK_THRESHOLD, 1.0, exposure), 0.0, 1.0)
