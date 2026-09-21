extends RefCounted
## What THIS moment teaches (docs/concept/spell_weaving.md's acquisition
## table, as a rule rather than as a table).
##
## Measured before this module existed: the doc had specified seven
## phenomena and their real sources since the Weave shipped, and its own
## status list said four of them were "specified and tabled but have no call
## site yet". Only `froze`, `warmed_at_a_fire` and `envenomated` were ever
## raised, so four of the twenty-five atoms -- `shock_damage`, `illuminate`,
## `slow` and `fear` -- could not be come by in ordinary play at all. A
## player could see the Weave, own three motes, and never be able to reach
## the rest of the catalogue.
##
## One decision, from facts the player's own step already has, so there is a
## single place that answers "what does this moment teach" instead of a
## table in a doc and a scatter of `if`s in a 5000-line scene script.
##
## Every threshold is READ from the module that owns it -- the weather
## model's own storm state, the HUD's own civil twilight, the terrain's own
## soft slope threshold -- so none of them is a second opinion, and a retune
## anywhere moves this with it.
##
## Pure: RefCounted, static functions, no player, no world, no scene tree.

const SpellMote = preload("res://src/gameplay/spell_mote.gd")
const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")

## The weather this teaches from. `WeatherModel.STATES`' own entry, held to
## it by test -- a state the weather can never actually be in would teach
## nothing for ever, silently.
const STORM_STATE := "storm"

## When it is dark: the sun below civil twilight. The same astronomical
## definition docs/concept/arrival.md already derived `FIRST_LIGHT_HOUR`
## from (the sun's centre 6 degrees below the horizon, the point at which
## the horizon stops being distinguishable), and the same figure the HUD
## already calls night -- `HudReadouts.CIVIL_TWILIGHT_DEGREES`, restated
## rather than preloading a UI module into a gameplay rule, and pinned to it
## by test.
const DARK_BELOW_SUN_ELEVATION_DEG := -6.0

## Ground that "fought back" is ground the WORLD itself slows you on:
## `TerrainPassability.SOFT_THRESHOLD_DEG`, the slope at which its speed
## multiplier first bites. Read from that module rather than restated, since
## a pure gameplay rule may preload another pure gameplay rule.
const HARD_GROUND_ABOVE_SLOPE_DEG := TerrainPassability.SOFT_THRESHOLD_DEG

## Every phenomenon that is a CONDITION of a moment, in the fixed order
## `taught_by` reports them.
##
## `envenomated` is deliberately absent: it is an EVENT, raised where the
## bite lands (`Player.apply_venom`). A poisoned character stays poisoned
## for seconds, and a condition-shaped venom would ask the same question on
## every one of those frames.
const CONDITION_PHENOMENA: Array[String] = [
	SpellMote.PHENOMENON_FROZE,
	SpellMote.PHENOMENON_WARMED_AT_A_FIRE,
	SpellMote.PHENOMENON_CAUGHT_IN_A_STORM,
	SpellMote.PHENOMENON_HUNGRY_IN_THE_DARK,
	SpellMote.PHENOMENON_CLIMBED_HARD_GROUND,
	SpellMote.PHENOMENON_HUNTED,
]


## Which phenomena this moment teaches, from plain facts.
##
## `facts` is what the caller already knows: `freezing` and `starving` from
## `SurvivalMeters`, `at_a_fire` from the real campfire scan, `weather` from
## `EarthChunkManager.current_weather`, `sun_elevation_deg` from the sky the
## world is already drawing, `slope_deg` from the ground underfoot, and
## `moving` / `hunted` from the character's own step.
##
## A missing fact is a fact that is not true: a caller with no world wired
## (an isolated test, a headless probe) teaches nothing rather than crashing
## or inventing a storm.
static func taught_by(facts: Dictionary) -> Array[String]:
	var taught: Array[String] = []

	if bool(facts.get("freezing", false)):
		taught.append(SpellMote.PHENOMENON_FROZE)

	if bool(facts.get("at_a_fire", false)):
		taught.append(SpellMote.PHENOMENON_WARMED_AT_A_FIRE)

	if String(facts.get("weather", "")) == STORM_STATE:
		taught.append(SpellMote.PHENOMENON_CAUGHT_IN_A_STORM)

	# Either alone is an ordinary hardship; together they are the thing that
	# teaches a character to want light (the doc's own source, "is_starving
	# after is_night").
	if (
		bool(facts.get("starving", false))
		and float(facts.get("sun_elevation_deg", 90.0)) < DARK_BELOW_SUN_ELEVATION_DEG
	):
		taught.append(SpellMote.PHENOMENON_HUNGRY_IN_THE_DARK)

	# Standing on a cliff is not climbing it -- you have to be going
	# somewhere for the ground to have fought you.
	if (
		bool(facts.get("moving", false))
		and float(facts.get("slope_deg", 0.0)) > HARD_GROUND_ABOVE_SLOPE_DEG
	):
		taught.append(SpellMote.PHENOMENON_CLIMBED_HARD_GROUND)

	if bool(facts.get("hunted", false)):
		taught.append(SpellMote.PHENOMENON_HUNTED)

	return taught
