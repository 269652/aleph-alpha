extends RefCounted

## Walking up to a wireframe and raising it -- yourself, or by paying
## somebody who knows how. See docs/concept/planner_mode.md.
##
## This is where planner mode's pillar 1 finally pays out: planning charged
## nothing, and the real cost falls HERE, at the moment somebody actually
## builds. And per pillar 5, the two ways are the same construction paid
## for differently -- both name the same site and the same blueprint, and
## only who supplies the labour hours differs.
##
## Pure: positions, inventories, trust and wages are all passed in, so
## nothing here needs a Player, an NpcMarker or a loaded chunk.

const BuildPlan = preload("res://src/world/build_plan.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const HiringGate = preload("res://src/world/hiring_gate.gd")

## Who supplies the hours. The ONLY thing that differs between the two ways
## of raising a wireframe.
enum Labour { PLAYER, HIRED }

## How close, in tiles, you must be to a wireframe for it to offer itself.
##
## Generous enough to stand BESIDE one rather than inside its footprint:
## you cannot stand inside a finished house, and there is no reason a
## planned one should demand it. Three tiles is roughly the reach the rest
## of this game already uses for "the thing in front of you".
const REACH_TILES := 3


## The wireframe the player is close enough to raise, or null. The nearest
## one when several are in reach -- a player standing between two plans
## means the one they walked up to.
static func plan_within_reach(ledger, player_cell: Vector2i, chunk_size: int):
	var best = null
	var best_distance := INF
	for plan in ledger.plans():
		for cell in BuildPlan.footprint_cells(
			plan.blueprint_id, plan.chunk_coord * chunk_size + plan.origin
		):
			var distance := Vector2(cell - player_cell).length()
			if distance <= float(REACH_TILES) and distance < best_distance:
				best_distance = distance
				best = plan
	return best


## What you are short of, item id -> how many more. Empty when you can
## build it.
##
## Reads the building's OWN real catalog cost -- the same numbers a village
## pays to raise the same building -- rather than a second price list for
## the planner, so a player and a villager never disagree about what a
## sawmill costs.
static func missing_materials(blueprint_id: String, carried: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	for item_id in BuildingCatalog.cost_of(blueprint_id):
		var needed: int = int(BuildingCatalog.cost_of(blueprint_id)[item_id])
		var have: int = int(carried.get(item_id, 0))
		if have < needed:
			missing[item_id] = needed - have
	return missing


## Pavement has no catalog cost because it is not a BuildingCatalog entry
## -- and an empty cost must read as "layable by hand", exactly like the
## earth tile the player already places, rather than as "free but somehow
## unaffordable".
static func can_build_yourself(blueprint_id: String, carried: Dictionary) -> bool:
	return missing_materials(blueprint_id, carried).is_empty()


## Hiring somebody to build is an ongoing wage relationship like every
## other one in this game, so it goes through the SAME gate rather than a
## second, softer rule invented for construction (see
## docs/concept/npc_instructions.md's "Hiring is a separate gate").
static func can_hire_builder(trust: float, wage_offered: float, minimum_wage: float) -> bool:
	return HiringGate.can_hire(trust, wage_offered, minimum_wage)


## The site, the blueprint, and who is paying for the hours -- everything a
## caller needs to open a real ConstructionProject against this plan.
##
## Both ways of raising produce the SAME site and blueprint (pinned by
## test_both_ways_raise_the_same_site_and_blueprint); if they could differ,
## these would be two features that merely look alike rather than one
## construction paid for two ways.
static func raising_request(plan, labour: int) -> Dictionary:
	return {
		"chunk_coord": plan.chunk_coord,
		"origin": plan.origin,
		"blueprint_id": plan.blueprint_id,
		"labour": labour,
	}
