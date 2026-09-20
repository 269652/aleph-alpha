extends RefCounted

## docs/concept/village_estates.md mechanism 3: the gated ladder, and the
## half docs/concept/village_growth.md never had.
##
## That system's population is a RATCHET. VillageImmigration only ever
## adds; there is no path by which a household loses standing, and none at
## all by which one leaves. So a village that stops supplying its people
## keeps them, and "growth" is a counter rather than a thing that can go
## either way.
##
## Here a household rises only where the CHARTER BUILDING for the next
## estate actually stands -- you cannot be a husbandman where there is no
## farm, a craftsman with no workshop to be apprenticed into, or a burgher
## with no civic seat to hold rights from. That is the whole of "gated
## growth": the gate is a real building on real ground, not a headcount.
## And it falls: subsistence short for a sustained run costs the household
## its standing, and at the bottom rung, where there is nowhere left to
## fall to, the household leaves the village.
##
## Pure and static. The dwell counters are RUN-LENGTHS the caller carries
## and this module advances (see advanced_runs) rather than state of its
## own -- the same derived-over-persisted discipline village_growth.md's
## pillar 5 holds. Every threshold is pinned by test_estate_ascension.gd
## against the behaviour or the real-world quantity it comes from, never
## asserted as a number somebody liked.

const VillageEstates = preload("res://src/emergence/village_estates.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const ASCEND := "ascend"
const HOLD := "hold"
const DESCEND := "descend"
const VERDICTS: Array[String] = [ASCEND, HOLD, DESCEND]

## What counts as a WHOLE ration. Not literally 1.0: satisfaction is a
## quotient of floats, so a village supplying exactly what it owes lands a
## few ulps under one, and a household would then never rise however well
## it was kept.
const FULL_SATISFACTION := 0.999

## How much of its own station a household must be holding to have a claim
## on the rung above. Below a full ration on purpose -- a household that
## has to be perfectly provisioned every single day to rise would never
## rise in a village with a real harvest cycle.
const STATION_THRESHOLD := 0.75

## Below this share of its subsistence, a household is going short in the
## sense that costs it something. Merely under a full ration is not:
## a village runs lean at the end of every winter and does not thereby
## unmake its craftsmen.
const SUBSISTENCE_FLOOR := 0.5

## One season of the real world clock: SeasonCycle's own year, divided by
## its own four seasons. The year is imported rather than typed so a change
## to it moves the dwell with it; the four is a literal only because
## SEASONS.size() is not a constant expression GDScript will fold, and
## test_the_ascent_dwell_is_one_real_season divides by the REAL list's size
## so a fifth season breaks loudly here rather than drifting quietly.
const SEASON_DAYS := SeasonCycle.DAYS_PER_YEAR / 4.0

## How long a household must hold its standard before it rises: one whole
## season. A single good week does not make a burgher, and the dwell is
## also what stops a village flapping between estates on every step.
const ASCENT_DWELL_DAYS := SEASON_DAYS

## How long subsistence must be short before the household loses standing:
## half a season. STRICTLY shorter than the ascent dwell, because a village
## unmakes itself faster than it makes itself -- which is what a famine is.
const DECLINE_DWELL_DAYS := SEASON_DAYS * 0.5

## What must be STANDING for a household of each estate to rise out of it.
## Any ONE of the listed buildings will do, which is why the value is a
## list: a village with a forge and no sawmill still has a trade to
## apprentice into.
##
## Every id here is a rung of VillageGrowth.LADDER_BUILDING_IDS, test-
## pinned: a gate on a building no village ever raises is a gate nothing
## ever passes. The top estate has no entry because there is nowhere above
## it.
const _CHARTERS_BY_ESTATE := {
	# You cannot be a husbandman where there is no plough-land worked.
	"kossaet": ["farmhouse"],
	# A trade to be apprenticed into -- either real workshop will do.
	"bauer": ["sawmill", "blacksmith"],
	# Civic rights are granted by a civic seat.
	"handwerker": ["city_hall"],
}


## What must stand for a household of `estate` to rise; `[]` at the top of
## the ladder and for an unknown estate.
static func charter_building_ids_for(estate: String) -> Array:
	return _CHARTERS_BY_ESTATE.get(estate, []).duplicate()


## Whether any one of this estate's charter buildings really stands.
static func has_charter(estate: String, present_building_ids: Array) -> bool:
	for charter in charter_building_ids_for(estate):
		if present_building_ids.has(charter):
			return true
	return false


## Whether a DESCEND verdict at this estate means the household leaves the
## settlement outright. True only at the bottom rung, which has nowhere
## left to fall to.
static func is_exodus(estate: String) -> bool:
	return VillageEstates.rank_of(estate) == 0


## ASCEND, HOLD or DESCEND for one household. `state` keys:
##   estate                its standing now
##   subsistence           [0,1], EstateConsumption.subsistence_satisfaction
##   station               [0,1], EstateConsumption.station_satisfaction
##   present_building_ids  what really stands in this village
##   good_run_days         consecutive days held at ascent-worthy provision
##   short_run_days        consecutive days held below SUBSISTENCE_FLOOR
##
## Starvation is checked FIRST and outranks every claim to rise: a
## household cannot be rising and falling at once, and which way it goes is
## never in doubt.
static func verdict(state: Dictionary) -> String:
	var estate := String(state.get("estate", ""))
	if VillageEstates.rank_of(estate) < 0:
		return HOLD

	var subsistence := clampf(float(state.get("subsistence", 0.0)), 0.0, 1.0)
	var short_run := float(state.get("short_run_days", 0.0))
	if subsistence < SUBSISTENCE_FLOOR and short_run >= DECLINE_DWELL_DAYS:
		return DESCEND

	if VillageEstates.next_estate(estate) == "":
		return HOLD
	if not has_charter(estate, state.get("present_building_ids", [])):
		return HOLD
	if float(state.get("good_run_days", 0.0)) < ASCENT_DWELL_DAYS:
		return HOLD
	if subsistence < FULL_SATISFACTION:
		return HOLD
	if clampf(float(state.get("station", 0.0)), 0.0, 1.0) < STATION_THRESHOLD:
		return HOLD
	return ASCEND


## The estate a household lands at after `a_verdict`. "" for an exodus --
## the caller reads that as the household leaving, not as a fifth rung.
static func resolve(estate: String, a_verdict: String) -> String:
	match a_verdict:
		ASCEND:
			var above := VillageEstates.next_estate(estate)
			return above if above != "" else estate
		DESCEND:
			return VillageEstates.previous_estate(estate)
		_:
			return estate


## The household's run-lengths after `days` at this provision.
## `{"good_run_days": float, "short_run_days": float}`.
##
## Three cases, and the third is the one worth naming: a household that is
## fed but below its station is in no danger AND has no claim, so BOTH runs
## clear. Only a household that is genuinely holding its standard banks
## time toward rising, and only one genuinely going short banks time toward
## falling.
##
## The top rung banks no good run at all: it has nowhere to spend one, and
## an ever-growing counter nothing reads is a number waiting to be
## mistaken for a fact.
static func advanced_runs(
	estate: String,
	subsistence: float,
	station: float,
	good_run_days: float,
	short_run_days: float,
	days: float
) -> Dictionary:
	var good := maxf(good_run_days, 0.0)
	var short := maxf(short_run_days, 0.0)
	if days <= 0.0:
		return {"good_run_days": good, "short_run_days": short}

	var fed := clampf(subsistence, 0.0, 1.0) >= FULL_SATISFACTION
	var stationed := clampf(station, 0.0, 1.0) >= STATION_THRESHOLD
	var can_rise := VillageEstates.next_estate(estate) != ""
	good = (good + days) if (fed and stationed and can_rise) else 0.0

	var starving := clampf(subsistence, 0.0, 1.0) < SUBSISTENCE_FLOOR
	short = (short + days) if starving else 0.0

	return {"good_run_days": good, "short_run_days": short}
