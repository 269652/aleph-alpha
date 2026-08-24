extends RefCounted

## "October 21 (Back to the Future Day, calendar-gated)"
## (docs/concept/easter_eggs.md): the real-world date fans famously marked
## as "the future" the trilogy travels to. On that one real calendar day
## each year, a silver, gull-winged car cameo (description only, no
## trademarked name -- pillar 4) appears briefly wherever the player is
## standing, then is gone.
##
## IMPORTANT: this is gated on the REAL SYSTEM calendar date (Time.
## get_datetime_dict_from_system(), the same real-world clock scenes/
## world.gd already reads for solar lighting), NOT this game's own
## fictional SeasonCycle -- those are two entirely different clocks. A real
## caller passes in utc.month/utc.day; is_today below never touches Time
## itself, so this stays a pure, deterministic function to test.
##
## Same "pure decision, caller supplies the real value and owns any session
## state" shape as KrakenTrigger/EasterEggSightings: is_today doesn't track
## whether the cameo has already fired today -- scenes/world.gd owns a
## simple once-per-session flag, the same low-risk "no de-duplication
## guard" scope call EasterEggCreatures' own doc comment already makes for
## its cameos (a whole calendar year between eligible days makes a
## once-per-session showing indistinguishable from once-per-day in
## practice).
##
## Deliberately reuses the SAME on-screen banner (_easter_egg_label/
## EASTER_EGG_MESSAGE_DURATION) EasterEggSightings' Mothman/Jersey Devil/
## Roswell/Area 51 cameos already use, rather than a new sprite -- the doc's
## own wording ("appears briefly... then is gone") is exactly what that
## existing banner already does, and no real car art exists to spawn
## instead (same "brief on-screen line, not a spawned prop" scope call
## EasterEggSightings' own doc comment already makes and sanctions).

const TARGET_MONTH := 10
const TARGET_DAY := 21

const CAMEO_MESSAGE := "A low silver shape streaks past in a blink -- gull-wing doors thrown open, no plates, already gone before you can look twice. Whatever that was, it was not going the speed limit."


## True only on the one real calendar date this cameo is gated on.
func is_today(month: int, day: int) -> bool:
	return month == TARGET_MONTH and day == TARGET_DAY


## The flavor line to show when a cameo fires -- caller decides WHEN (is_
## today AND not already shown this session).
func cameo_message() -> String:
	return CAMEO_MESSAGE
