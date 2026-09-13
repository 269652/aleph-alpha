extends RefCounted

## A settlement's spare hands gather building material into its own
## persisted Market over time (docs/concept/milling_and_baking.md, "Where
## the wood and stone come from") -- the construction analogue of
## SettlementGranary's food gathering, and the reason a village can raise a
## Farm at all: nothing else ever puts wood, stone or plant fibre into the
## emergence Market in live play (Shop stocking, the granary, regional trade
## and occupation production all deal in other goods), so before this every
## autonomous construction decision could only ever end in SHORTFALL.
##
## Real-world grounding: a village has always cut its own timber, picked
## its own fieldstone and pulled its own binding fibre -- the unglamorous
## work of whoever is not busy with a survival occupation, which is exactly
## what SettlementSpareCapacity already measures (households beyond farmer/
## hunter/fisher). Wood is the most plentiful (firewood and poles are split
## by the armful), stone the slowest (picked one at a time), fibre in
## between -- pinned by test_settlement_gathering.gd rather than left as a
## comment, per this project's no-manual-tuning rule.
##
## Pure, static-function module, the same shape SettlementGranary uses: a
## rate per spare household per day, a sub-unit carry between steps so
## short steps lose nothing, whole units out. Illustrative pacing: with
## ConstructionCatchup.SECONDS_PER_DAY's one-hour day and three spare
## households, a Farm's own 6 wood + 4 fibre are on hand in ~10-15 minutes.

const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")

const WOOD_PER_SPARE_HOUSEHOLD_PER_DAY := 12.0
const STONE_PER_SPARE_HOUSEHOLD_PER_DAY := 6.0
const PLANT_FIBRE_PER_SPARE_HOUSEHOLD_PER_DAY := 6.0

const _RATE_BY_ITEM := {
	"wood": WOOD_PER_SPARE_HOUSEHOLD_PER_DAY,
	"stone": STONE_PER_SPARE_HOUSEHOLD_PER_DAY,
	"plant_fibre": PLANT_FIBRE_PER_SPARE_HOUSEHOLD_PER_DAY,
}


## What `spare_capacity` households gather over `seconds`, on top of the
## sub-unit `carry` left from the previous step: {"stock_delta": {item_id ->
## whole units to add now}, "carry": {item_id -> the fraction still owed}}.
## Never mutates `carry`; a zero spare capacity gathers nothing (the carry
## is kept, not lost).
static func material_delta(spare_capacity: int, seconds: float, carry: Dictionary) -> Dictionary:
	var stock_delta := {}
	var next_carry := carry.duplicate()
	if spare_capacity <= 0 or seconds <= 0.0:
		return {"stock_delta": stock_delta, "carry": next_carry}
	var days := seconds / ConstructionCatchup.SECONDS_PER_DAY
	for item_id in _RATE_BY_ITEM:
		var gathered: float = float(next_carry.get(item_id, 0.0)) + _RATE_BY_ITEM[item_id] * float(spare_capacity) * days
		var whole := int(floor(gathered + 0.000001))
		if whole > 0:
			stock_delta[item_id] = whole
		next_carry[item_id] = gathered - float(whole)
	return {"stock_delta": stock_delta, "carry": next_carry}
