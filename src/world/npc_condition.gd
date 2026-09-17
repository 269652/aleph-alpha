extends RefCounted

## A villager's stamina and fitness (docs/concept/npc.md, "A hunter runs, and
## the run is paid for in stamina").
##
## Deliberately NOT a second stamina model. These are the player's own two
## meters in the player's own shape -- same range, same regen rate, same
## exhaustion line, same "fitness is the accumulator of neglect" rule -- with
## SurvivalMeters' constants reused by direct reference rather than restated,
## so a re-tune there cannot leave a villager running on numbers the player
## no longer uses. The one real difference is the one that was asked for:
## recovery is scaled by fitness (ConditionPenalty.stamina_regen_multiplier),
## which is survival.md's own long-specified "poor condition slows stamina
## regen" pillar effect finally having something that spends stamina to make
## it visible.
##
## What it deliberately does NOT do: rise on its own like a drive. Stamina is
## a resource you HAVE and spend, not a need that climbs until relieved,
## which is exactly why the shared Drives clock (hunger/thirst/fear, see
## ethogram.md) is the wrong shape for it and why SurvivalMeters keeps its
## own two meters outside that clock too.

const SurvivalMeters = preload("res://src/gameplay/survival_meters.gd")
const ConditionPenalty = preload("res://src/gameplay/condition_penalty.gd")
const Metabolism = preload("res://src/gameplay/metabolism.gd")

## What one second of running costs, as a fraction of the whole meter.
##
## Derived, not eyeballed: STAMINA_REGEN_PER_SECOND is the rate a body on
## its feet at the ordinary walking tier gets back, and Metabolism already
## owns this game's real MET-style activity tiers -- walking is
## ACTIVITY_MOVING, running is ACTIVITY_EXERTION -- so a run costs that same
## body the exertion tier's own multiple of a walk (5.0 / 1.75, about 2.9x).
##
## What that works out to, which is the number worth sanity-checking: a
## rested villager has about five and a half seconds of running in them
## before they hit the exhaustion line, which at NpcMarker.RUN_SPEED is
## roughly 220px -- most of HuntableQuarry.SEARCH_RADIUS_PX, so one full bar
## covers about one full-radius approach. Pinned by
## test_a_run_costs_what_this_games_own_activity_tiers_say_it_does and by
## test_a_full_bar_of_wind_covers_most_of_a_hunters_own_search_radius.
## A `static var`, not a `const`, for the same reason NpcNeeds' own derived
## rates are: the value comes from a function call, which a const initializer
## cannot make.
static var RUN_STAMINA_PER_SECOND: float = SurvivalMeters.STAMINA_REGEN_PER_SECOND * (
	Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_EXERTION)
	/ Metabolism.activity_multiplier_for(Metabolism.ACTIVITY_MOVING)
)

## Stamina in [0,1], 1 fully rested -- the player's own meter, same range.
var stamina := 1.0
## Overall condition in [0,1], the same accumulator of neglect
## SurvivalMeters.fitness is: it falls while this villager is starving and
## recovers otherwise, and what it costs them is how fast their wind comes
## back (see advance).
var fitness := 1.0

## Once blown, a villager walks until their wind is FULLY back, rather than
## breaking into a run again the instant one frame of recovery lifts them a
## hair over the exhaustion line -- which would alternate run/walk every
## frame for the whole chase. The same "come well back over it, not merely
## over it" asymmetry ConstructionStartHysteresis already uses for a
## village's own build decisions; pinned to full recovery so it costs no
## second tuned constant.
var _blown := false


## One frame of a villager's body. `hunger` is their own real hunger level
## (NpcNeeds.hunger, 0 fed .. 1 desperate) and `running` is whether they
## actually ran this frame.
##
## Stamina's recovery is paid at the condition the frame was LIVED in (the
## fitness this call began with), not the one it ends in -- the difference is
## a rounding error at any real delta, and it keeps "why did I get exactly
## this much back" answerable from state a caller can see.
func advance(delta_seconds: float, hunger: float, running: bool) -> void:
	var lived_in_fitness := fitness
	if hunger >= SurvivalMeters.STARVING_THRESHOLD:
		fitness = clampf(fitness - SurvivalMeters.FITNESS_DROP_PER_SECOND * delta_seconds, 0.0, 1.0)
	else:
		fitness = clampf(fitness + SurvivalMeters.FITNESS_RECOVER_PER_SECOND * delta_seconds, 0.0, 1.0)

	if running:
		stamina = clampf(stamina - RUN_STAMINA_PER_SECOND * delta_seconds, 0.0, 1.0)
	else:
		var regain := (
			SurvivalMeters.STAMINA_REGEN_PER_SECOND
			* ConditionPenalty.stamina_regen_multiplier(lived_in_fitness)
			* delta_seconds
		)
		stamina = clampf(stamina + regain, 0.0, 1.0)

	if stamina <= SurvivalMeters.EXHAUSTED_THRESHOLD:
		_blown = true
	elif stamina >= 1.0:
		_blown = false


## Whether there is a run left in them right now -- see _blown for why this
## is latched rather than a bare comparison against the exhaustion line.
func can_run() -> bool:
	return not _blown and stamina > SurvivalMeters.EXHAUSTED_THRESHOLD
