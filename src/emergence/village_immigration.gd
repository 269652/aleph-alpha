extends RefCounted

## docs/concept/village_growth.md mechanism 3: a village that is fed and has
## room attracts new households over time.
##
## This is what makes the growth ladder a ladder anything ever walks up.
## SettlementGenerator's own POPULATION is a fixed 5 -- deterministic per
## chunk, which is right for FOUNDING a village but means every village is
## frozen at its founding size forever. An arrival here is a real new
## household in the settlement (formed through HouseholdStore.form_household
## and recorded with the same `npc_settled` event
## record_settlement_founded_if_new already uses), so
## household_count_for_settlement, SettlementSpareCapacity, SettlementTier
## and VillageGrowth's ladder all see it with no new plumbing whatsoever.
##
## Two hard gates, either of which alone stops arrivals dead:
## - **Room.** No spare roof AND nowhere left to build ⇒ nobody moves in.
##   A village packed to its walls takes nobody, however rich.
## - **Food.** A larder below FED_THRESHOLD per household ⇒ nobody moves
##   in. A hungry village attracts nobody, however much room it has.
##
## Past both gates the draw is a rate per day, raised by how far the larder
## is above the threshold and by how much of the ladder actually stands --
## a village with a hall and a brewery draws people a bare hamlet does not.
##
## Same carry-the-fraction, whole-units-out shape SettlementGathering and
## SettlementGranary already use, so a short step loses nothing. Tuned
## values are pinned by test_village_immigration.gd against the behaviour
## they produce (a full larder draws faster than a barely-fed one; twenty
## short steps arrive at the same count as one long one), per this
## project's no-manual-tuning rule.

const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")

## Food units in the settlement's store per household, below which nobody
## moves in. Deliberately under HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_
## TARGET (what that model calls a FULL larder): a village has to be
## somewhat comfortable before it grows, not perfectly provisioned --
## test-pinned so the two can never invert.
const FED_THRESHOLD := 2.0

## Real seconds of elapsed play per simulated day -- mirrors
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY's own VALUE (60), restated
## here rather than imported for the reason AntColony.SECONDS_PER_SIMULATED_
## DAY's own doc comment gives (EarthChunkManager is an engine-dependent
## singleton a pure emergence module must not depend on). Cross-checked by
## test_village_immigration.gd so the two cannot silently drift.
##
## Arrivals used to be counted in ConstructionCatchup's day (3600) -- the
## deliberately conservative rate for integrating an UNLOADED chunk's
## vegetation and herds across an absence, and sixty times the day the
## player actually lives in. Measured: a bare just-fed village drew one
## household every 6 hours 40 minutes of real play, and a full larder under
## a full ladder still took 2 hours 13. Immigration only runs while the
## chunk is LOADED (see this file's own honest limitation below), so that
## was two hours of standing beside a village to watch one person move in --
## a village that grows by itself and can never be seen to.
const SECONDS_PER_SIMULATED_DAY := 60.0

## The draw of a bare, just-fed village with room: roughly one household a
## week of simulated days.
const BASE_ARRIVALS_PER_DAY := 0.15
## How much a full larder adds on top of the base draw, as a multiple.
const FOOD_SURPLUS_DRAW := 1.0
## How much a fully-built ladder adds on top of the base draw, as a
## multiple -- the same magnitude as food, because a place worth living in
## and a place with food to eat drew people about equally.
const LADDER_DRAW := 1.0
## How far above FED_THRESHOLD the larder has to run for the food draw to
## be fully open.
const FOOD_SURPLUS_FOR_FULL_DRAW := FED_THRESHOLD * 2.0


## `{"arrivals": whole households moving in now, "carry": the fraction
## still owed}`. `spare_house_capacity` is real unused capacity in houses
## that already stand; `has_room_to_build` is whether the village still has
## frontage for one more house (VillageLayout.next_street_plot).
##
## Arrivals are CAPPED at `spare_house_capacity + 1 if has_room_to_build`,
## and whatever the rate produced beyond that cap is simply LOST rather
## than banked -- households that found no room went somewhere else, which
## is both what really happened historically and what stops a long absence
## from dumping a whole town onto a village the moment a player walks back
## into it. The carry only ever holds a real sub-unit fraction.
static func arrivals(
	seconds: float,
	food_per_household: float,
	spare_house_capacity: int,
	has_room_to_build: bool,
	ladder_share: float,
	carry: float
) -> Dictionary:
	var room := maxi(spare_house_capacity, 0) + (1 if has_room_to_build else 0)
	if seconds <= 0.0 or room <= 0 or food_per_household < FED_THRESHOLD:
		return {"arrivals": 0, "carry": carry}

	var surplus := clampf(
		(food_per_household - FED_THRESHOLD) / FOOD_SURPLUS_FOR_FULL_DRAW, 0.0, 1.0
	)
	var draw := BASE_ARRIVALS_PER_DAY * (
		1.0 + FOOD_SURPLUS_DRAW * surplus + LADDER_DRAW * clampf(ladder_share, 0.0, 1.0)
	)
	var days := seconds / SECONDS_PER_SIMULATED_DAY
	var accrued := carry + draw * days
	var whole := int(floor(accrued + 0.000001))
	# maxf, because the +epsilon that stops a float 0.9999999 from losing a
	# whole household can also carry `accrued` just past `whole`, leaving a
	# carry of -3e-15. A negative carry is not a fraction still owed; it is
	# arithmetic noise, and it compounds.
	return {"arrivals": mini(whole, room), "carry": maxf(accrued - float(whole), 0.0)}
