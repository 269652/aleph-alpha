extends RefCounted

## The lines the settlement card shows (see docs/concept/hud.md "The
## settlement card").
##
## Asked for directly: a context-dependent Village/City panel showing
## population, happiness, gold "and so". Every row here is a READ of state
## the simulation already keeps -- households, HouseholdWellbeing, the
## guild chest, the village market, the growth ladder -- so nothing is
## tracked for this card's benefit and nothing it shows can drift from
## what the village is actually doing.
##
## Pure: facts in, strings out, no nodes and no world. The same "pure
## model, thin Node" split AudioDiagnostics and HouseholdWellbeing already
## keep, which is what makes a city's rows testable without founding one.

const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

## What a happiness of "not assessed yet" looks like coming in. A village
## whose households have not been assessed is a real state, and reporting
## it as 0% would be a lie a player would act on.
## How many rows lines_for produces. The card builds this many labels ONCE,
## so the row count is fixed and the card never resizes under the player's
## eye as a village grows -- the same contract the world-clock card keeps.
## Pinned against the real output by test_the_row_count_matches_what_is_
## actually_produced, so a new row cannot be added here and silently go
## undrawn.
const ROW_COUNT := 5

const UNKNOWN := -1.0
const UNKNOWN_TEXT := "—"

## Player-facing names for HouseholdWellbeing's own five needs. Pinned
## against NEED_IDS by test_the_need_ids_are_the_wellbeing_models_own, so a
## sixth need cannot be added to the model while this card keeps quietly
## reporting five.
const NEED_LABELS := {
	"food": "food",
	"shelter": "housing",
	"work": "work",
	"income": "income",
	"community": "company",
}


## The card's title: whatever tier the simulation currently computes, not
## a fixed word. Watching this change from Hamlet to Town is watching
## SettlementTier's three dimensions cross together.
static func title_for(state: Dictionary) -> String:
	var tier := String(state.get("tier", ""))
	if tier.is_empty():
		return "Settlement"
	return tier.capitalize()


## One line per row, in reading order.
static func lines_for(state: Dictionary) -> Array:
	return [
		"Population  %d  (%d housed)" % [
			int(state.get("households", 0)), int(state.get("housed", 0))
		],
		_happiness_line(state),
		"Gold  %d" % int(state.get("gold", 0)),
		"Food  %s" % _food_text(state),
		"Building  %s" % _building_text(state),
	]


## Happiness with its weakest need beside it. The blend alone is nearly
## useless to a player -- it is a weighted mix of five needs, so "68%" says
## nothing about what to do -- and the per-need numbers are already
## computed to produce it, so naming the worst costs nothing.
static func _happiness_line(state: Dictionary) -> String:
	var happiness := float(state.get("happiness", UNKNOWN))
	if happiness < 0.0:
		return "Happiness  %s" % UNKNOWN_TEXT
	var worst := _weakest_need(state.get("needs", {}))
	if worst.is_empty():
		return "Happiness  %d%%" % roundi(happiness * 100.0)
	return "Happiness  %d%%  (worst: %s)" % [roundi(happiness * 100.0), worst]


## The lowest-scoring of the real needs, by its player-facing name, or ""
## when nothing was assessed. Ties resolve by NEED_IDS order so the answer
## is stable rather than dictionary-order dependent.
static func _weakest_need(needs: Dictionary) -> String:
	var worst_id := ""
	var worst_score := INF
	for need_id in HouseholdWellbeing.NEED_IDS:
		if not needs.has(need_id):
			continue
		var score := float(needs[need_id])
		if score < worst_score:
			worst_score = score
			worst_id = need_id
	return String(NEED_LABELS.get(worst_id, worst_id))


## How many households the settlement's food can actually support, against
## how many it has. SettlementFood.carrying_capacity is the number the
## simulation ALREADY assesses a settlement by (it is what decides
## GROWING/STABLE/DECLINING), so the card reports that rather than
## inventing a second, weaker stock figure for itself.
static func _food_text(state: Dictionary) -> String:
	if not state.has("feeds"):
		return UNKNOWN_TEXT
	return "feeds %d of %d" % [int(state["feeds"]), int(state.get("households", 0))]


## The building's own display name rather than its catalog id -- "Cottage",
## not "house_small". An empty ladder says so in words; a blank row would
## read as a bug.
static func _building_text(state: Dictionary) -> String:
	var building_id := String(state.get("building", ""))
	if building_id.is_empty():
		return "nothing"
	var name := BuildingCatalog.display_name_of(building_id)
	return building_id if name.is_empty() else name
