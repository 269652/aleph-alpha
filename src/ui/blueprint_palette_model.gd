extends RefCounted

## What the build palette shows and says (see docs/concept/planner_mode.md,
## "The build palette"). Pure and static, so the menu's own content is
## testable without standing up a World -- the same "pure model, thin Node"
## split ViewMode already keeps for the mode itself.
##
## Asked directly, with a screenshot of ten identical text buttons in a
## row: *"Make the Planner / Building HUD more professional and more like
## Anno 1806. Add Icons not only text"*. Ten equal-weight words side by
## side is a list, not a build menu: it says nothing about what a thing
## looks like, what it costs or how much ground it takes. This module is
## the three of those that are words; BlueprintIcon is the picture.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")
const PlanRaising = preload("res://src/gameplay/plan_raising.gd")

const CATEGORY_ROADS := "roads"
const CATEGORY_HOMES := "homes"
const CATEGORY_PRODUCTION := "production"
const CATEGORY_CIVIC := "civic"

## What a blueprint that asks for no materials says. A blank cost line
## would read as "not known yet" rather than "free", and pavement really
## is free.
const FREE_TEXT := "No materials"

## PlanRaising.is_laid_by_hand's rule, said in the menu rather than
## discovered at the site: zero hours is not "0 hours", it is work that
## finishes the moment it is begun.
const LAID_BY_HAND_TEXT := "Laid by hand"

const HOURS_TEXT := "%s builder-hours"
const FOOTPRINT_TEXT := "%d x %d"


## The palette's tabs, in the order they are shown.
##
## Each one's blueprint list IS a BuildingCatalog list, read at runtime and
## never copied into a second grouping here -- BUILDING_IDS are homes,
## PRODUCTION_BUILDING_IDS are works, CIVIC_BUILDING_IDS are the commons,
## and each of those lists' own doc comment is what says so. A building
## added to the catalogue therefore lands in the right tab for free, and no
## tab here can drift out of step with what the catalogue says a building
## is.
##
## Pavement carries its own tab because it is not a BuildingCatalog entry
## at all (it is TerrainRenderer.ROAD_TILE_ID -- the same laid surface a
## village lays for its streets), and it comes first because it is the
## cheapest, most-used thing a player lays.
static func categories() -> Array:
	return [
		{
			"id": CATEGORY_ROADS, "label": "Roads",
			"blueprint_ids": [BuildPlan.PAVEMENT_BLUEPRINT_ID],
		},
		{
			"id": CATEGORY_HOMES, "label": "Homes",
			"blueprint_ids": BuildingCatalog.BUILDING_IDS,
		},
		{
			"id": CATEGORY_PRODUCTION, "label": "Production",
			"blueprint_ids": BuildingCatalog.PRODUCTION_BUILDING_IDS,
		},
		{
			"id": CATEGORY_CIVIC, "label": "Civic",
			"blueprint_ids": BuildingCatalog.CIVIC_BUILDING_IDS,
		},
	]


## Every blueprint the palette offers, tab order then within-tab order --
## what the old flat row of text buttons listed, in the same order.
static func blueprint_ids() -> Array:
	var ids: Array = []
	for category in categories():
		for blueprint_id in category["blueprint_ids"]:
			ids.append(blueprint_id)
	return ids


## What a slot is called -- BuildPlan's own name, so the menu, the planner
## message and the wireframe prompt all call a building the same thing.
static func slot_title(blueprint_id: String) -> String:
	return BuildPlan.display_name_of(blueprint_id)


## How much ground it takes, "" for something the game cannot build. The
## one fact a build menu must carry on the slot itself: a player choosing
## between a cottage and a manor is choosing between 2x2 and 3x3 of their
## own street.
static func slot_subtitle(blueprint_id: String) -> String:
	var footprint := footprint_of(blueprint_id)
	if footprint == Vector2i.ZERO:
		return ""
	return FOOTPRINT_TEXT % [footprint.x, footprint.y]


## Pavement is one cell at a time; everything else is the catalogue's own
## footprint; an unknown id is ZERO rather than a guessed 1x1, the same
## refusal BuildPlan.footprint_cells already makes.
static func footprint_of(blueprint_id: String) -> Vector2i:
	if blueprint_id == BuildPlan.PAVEMENT_BLUEPRINT_ID:
		return Vector2i.ONE
	return BuildingCatalog.footprint_of(blueprint_id)


## The material a build really consumes, as one line: "20 Wood, 4 Stone".
##
## Read from BuildingCatalog.cost_of and nowhere else -- the same rule
## PlanRaising keeps for the charge it actually makes, so what the menu
## promises and what raising it takes out of the player's inventory cannot
## disagree.
##
## `name_for_item` is the seam an ItemCatalog plugs into (the Callable
## shape BuildPlanLedger's own buildability check already established),
## since naming an item needs the crafted registry a pure module has no
## business holding. Without one the id is read as words, which is honest
## and never blank.
static func cost_text(blueprint_id: String, name_for_item := Callable()) -> String:
	if not BuildPlan.is_plannable(blueprint_id):
		return ""
	var cost := BuildingCatalog.cost_of(blueprint_id)
	if cost.is_empty():
		return FREE_TEXT
	var parts: Array = []
	for item_id in cost:
		var named := String(item_id).capitalize()
		if name_for_item.is_valid():
			named = String(name_for_item.call(item_id))
		parts.append("%d %s" % [int(cost[item_id]), named])
	return ", ".join(parts)


## How big the job is. `required_labor_hours` arrives from the caller
## rather than being derived here, so it is the SAME number the ledger
## finishes against (EarthChunkManager.build_labor_hours_for) -- the
## identical shape PlanRaising.is_laid_by_hand already takes, and for the
## identical reason.
static func labour_text(required_labor_hours: float) -> String:
	if PlanRaising.is_laid_by_hand(required_labor_hours):
		return LAID_BY_HAND_TEXT
	return HOURS_TEXT % String.num(required_labor_hours, 0)


## The whole card a hover reads: name, ground, materials, work. [] for
## something the game cannot build -- a guessed card for a typo would
## quote a price nobody can pay.
static func detail_lines(
	blueprint_id: String, required_labor_hours: float, name_for_item := Callable()
) -> Array:
	if not BuildPlan.is_plannable(blueprint_id):
		return []
	return [
		slot_title(blueprint_id),
		"%s tiles" % slot_subtitle(blueprint_id),
		cost_text(blueprint_id, name_for_item),
		labour_text(required_labor_hours),
	]
