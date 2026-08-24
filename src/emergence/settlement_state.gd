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

## How much food one household draws down per assessment. Tested against the
## GROWING/STABLE/DECLINING classification it produces, not any specific
## "correct" number -- there is no real economy data yet to derive one from.
const FOOD_PER_HOUSEHOLD := 4

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
