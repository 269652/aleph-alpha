extends RefCounted

## Carrying capacity and growth/decline status (see
## docs/emergence/04-settlements-cities-infrastructure.md "Carrying
## capacity": "Population capacity depends on food, water, housing, jobs,
## sanitation, security, transport, trade, climate, and disease. Population
## should move toward capacity rather than use arbitrary growth").
##
## Deliberately FOOD-only for this first slice (avoid premature complexity):
## food is the one input this project already has live, real data for (via
## Market, Phase 5) -- water/housing/job/sanitation simulation do not exist
## yet either, so deriving capacity from them would mean inventing the very
## systems this slice is trying to avoid inventing.

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

## How long one settlement assessment is, in world seconds.
##
## Declared here rather than imported from EarthChunkManager, which preloads
## this module -- the dependency can only run one way. Pinned against
## SETTLEMENT_STEP_INTERVAL by test_the_assessment_this_module_prices_is_
## the_one_the_world_runs, so the two cannot drift.
const ASSESSMENT_SECONDS := 30.0

## How much food one household draws down per assessment.
##
## MEASURED off the villagers' own hunger clock, not chosen. This used to be
## 4, with its own comment admitting "there is no real economy data yet to
## derive one from" -- and by the time there was, nobody went back. The data
## is `Ethogram.drive_profile("", "villager")`'s hunger entry:
##
##     rise_seconds 50.0, threshold 0.5, meal 1.0
##
## A villager's hunger rises from 0 to 1 over 50 world-seconds and reads as
## urgent at 0.5, so a fed villager is hungry again 25 seconds later, and one
## meal (VillageMarket.FOOD_UNITS_PER_MEAL, one whole unit) takes it back to
## zero. An assessment is 30 world-seconds. Run for 200 assessments against
## the real NpcNeeds clock: 240 meals, exactly 1.2 food units per household
## per assessment -- against the 4 this constant claimed, a 3.33x
## overstatement of what a village actually eats.
##
## A literal rather than a computed expression because GDScript cannot call
## into another script from a const initialiser (the same reason
## Ethogram's own DRIVE_COMPANY entry writes out the quarter-day it means);
## pinned to the real clock by test_a_households_draw_is_what_its_own_hunger
## _clock_really_eats, so the derivation is a test and not a comment.
##
## ONE HOUSEHOLD IS ONE VILLAGER today -- the founding roster gives each
## villager a house of their own (SettlementGenerator, VillageRenderer), so
## this is a per-villager draw wearing a per-household name. A house that
## really held two (BuildingCatalog.capacity_of allows up to three) would
## need this multiplied by its residents, and nothing does that yet.
const FOOD_PER_HOUSEHOLD := 1.2

const GROWING := "growing"
const STABLE := "stable"
const DECLINING := "declining"
const STATUSES := [GROWING, STABLE, DECLINING]

## How far a household count can sit above/below capacity and still read as
## merely STABLE -- a dead band so a settlement sitting almost exactly at
## capacity does not flicker between labels every time one unit of food
## changes hands (the same "prevent flicker" reasoning
## InstitutionFormation's hysteresis gap already applies, here as a band
## around one threshold rather than two separate ones).
const STABLE_BAND := 0.15


## Total food-typed stock in `market` -- reads real item categories from the
## existing ItemCatalog rather than a second, hand-maintained "which items
## are food" list that could drift from it.
static func food_stock(market, catalog = null) -> int:
	var item_catalog = catalog if catalog != null else ItemCatalog.new()
	var total := 0
	for item_id in market.stock:
		if item_catalog.has(item_id) and item_catalog.make(item_id).kind == "food":
			total += market.stock_of(item_id)
	return total


static func carrying_capacity(market, catalog = null) -> int:
	return int(food_stock(market, catalog) / float(FOOD_PER_HOUSEHOLD))


## GROWING (real headroom, capacity comfortably exceeds population),
## DECLINING (population comfortably exceeds capacity -- real pressure), or
## STABLE (roughly balanced, or nothing there yet to be under pressure).
static func status_for(household_count: int, capacity: int) -> String:
	if capacity <= 0:
		return DECLINING if household_count > 0 else STABLE
	var ratio := float(household_count) / float(capacity)
	if ratio > 1.0 + STABLE_BAND:
		return DECLINING
	if ratio < 1.0 - STABLE_BAND:
		return GROWING
	return STABLE
