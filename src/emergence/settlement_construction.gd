extends RefCounted

## THE live integration point for docs/concept/timber_construction.md's
## "Settlement construction ledger" section: ConstructionPriority.decide's
## first real, live caller (that doc's own Status note this closes:
## "nothing calls ConstructionPriority.decide from a real settlement-
## decision system yet").
##
## Given a settlement's real local stock (VillageMarket), its present
## structure ids, and a candidate blueprint (a real CraftingRecipeBook
## recipe id) to build next at a specific site, `advance` decides what
## actually happens:
## - READY: starts a real ConstructionProject (gated by
##   ConstructionStartHysteresis, not an eyeballed assumption that decide()
##   ==READY always implies the recipe's own direct inputs are covered --
##   see test_ready_does_not_draw_down_material_the_recipe_does_not_
##   actually_have for the real edge case this guards) and draws down its
##   real material from `market`, recording it as the project's own
##   reserved_material.
## - BUILD_PRODUCER_FIRST: production_chains.md's own "a resolver, not a
##   solver" pillar's actual payoff -- NeedResolver only NAMES the blocker
##   (via ConstructionPriority.missing_structure_id), this is the first
##   real caller that turns it into an action: a real PLANNED
##   ConstructionProject queued for the missing PRODUCER structure itself,
##   ahead of the project that needed it. A missing SKILL (not a structure)
##   has nothing spatial to queue -- surfaced plainly instead.
## - SHORTFALL: the existing regional-trade/shortfall path already covers a
##   pure materials gap (this doc's own framing) -- no new mechanism here.
##   `market` is never mutated on this branch. The one thing this branch
##   does do: a project at this site that is still merely PLANNED (material
##   not yet committed/drawn down) is retired via
##   ConstructionStartHysteresis.should_abandon if local stock has
##   genuinely collapsed well below the recipe's own requirement -- a
##   project already IN_PROGRESS has already reserved what it needs and is
##   left alone regardless (see test_shortfall_does_not_abandon_an_in_
##   progress_project_whose_material_is_already_reserved).
##
## Static-function module, the same shape Quest.gd's own production_
## shortfall_quests_for/deeper_need_for already use: explicit dependencies
## passed in, no stored state of its own -- ConstructionProjectStore/
## VillageMarket/HouseholdStore stay the real state, this is pure decision
## logic layered over them, callable by a future settlement-decision system
## (per this doc's own framing) without that system needing to re-derive
## any of this reasoning itself.

const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionStartHysteresis = preload("res://src/emergence/construction_start_hysteresis.gd")
const ConstructionPriority = preload("res://src/gameplay/construction_priority.gd")


## `project_store`: ConstructionProjectStore. `market`: VillageMarket (its
## real `.stock` is read, and on READY, drawn down via `remove_stock`).
## `recipe_book`: CraftingRecipeBook. See this file's own header for the
## full branch-by-branch contract; the returned Dictionary always carries
## "priority" (a ConstructionPriority.Priority value) plus branch-specific
## keys ("action", and "project_id"/"missing_structure_id" where real).
static func advance(
	project_store,
	market,
	chunk_coord: Vector2i,
	origin: Vector2i,
	blueprint_id: String,
	household_id: String,
	present_structure_ids: Array,
	recipe_book,
	allocated_nodes: Dictionary = {}
) -> Dictionary:
	var priority: int = ConstructionPriority.new().decide(
		blueprint_id, market.stock, present_structure_ids, recipe_book, allocated_nodes
	)

	if priority == ConstructionPriority.Priority.BUILD_PRODUCER_FIRST:
		return _handle_build_producer_first(
			project_store, market, chunk_coord, origin, blueprint_id, household_id,
			present_structure_ids, recipe_book, allocated_nodes
		)
	if priority == ConstructionPriority.Priority.SHORTFALL:
		return _handle_shortfall(project_store, market, chunk_coord, origin, blueprint_id, recipe_book)
	return _handle_ready(project_store, market, chunk_coord, origin, blueprint_id, household_id, recipe_book)


static func _handle_build_producer_first(
	project_store, market, chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String,
	household_id: String, present_structure_ids: Array, recipe_book, allocated_nodes: Dictionary
) -> Dictionary:
	var missing_structure_id: String = ConstructionPriority.new().missing_structure_id(
		blueprint_id, market.stock, present_structure_ids, recipe_book, allocated_nodes
	)
	if missing_structure_id == "":
		return {
			"priority": ConstructionPriority.Priority.BUILD_PRODUCER_FIRST,
			"action": "blocked_on_skill",
			"missing_structure_id": "",
		}

	# Queued at the SAME site as the project that needed it -- this pass
	# does not build a real siting/placement algorithm for where a
	# producer structure should actually go (out of scope, see this doc's
	# own "do NOT touch VillageRenderer._stamp_house or ... PLACE_PIECE"
	# instruction); the origin here is bookkeeping for a future
	# settlement-decision caller, not a claim about real footprint
	# collision-checking. A distinct blueprint_id keeps its own project id
	# distinct from the one that needed it either way (see
	# ConstructionProject.id_for_site).
	var producer_project: ConstructionProject = project_store.start_project(
		chunk_coord, origin, missing_structure_id, household_id
	)
	return {
		"priority": ConstructionPriority.Priority.BUILD_PRODUCER_FIRST,
		"action": "queued_producer_first",
		"missing_structure_id": missing_structure_id,
		"project_id": producer_project.id,
	}


static func _handle_shortfall(
	project_store, market, chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String, recipe_book
) -> Dictionary:
	var project: ConstructionProject = project_store.find_project(chunk_coord, origin, blueprint_id)
	if project == null or project.status != ConstructionProject.Status.PLANNED:
		return {"priority": ConstructionPriority.Priority.SHORTFALL, "action": "left_to_shortfall_path"}

	if _any_input_crashed(market, recipe_book, blueprint_id):
		project.status = ConstructionProject.Status.ABANDONED
		return {
			"priority": ConstructionPriority.Priority.SHORTFALL,
			"action": "abandoned",
			"project_id": project.id,
		}
	return {
		"priority": ConstructionPriority.Priority.SHORTFALL,
		"action": "left_to_shortfall_path",
		"project_id": project.id,
	}


static func _handle_ready(
	project_store, market, chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String,
	household_id: String, recipe_book
) -> Dictionary:
	var project: ConstructionProject = project_store.start_project(chunk_coord, origin, blueprint_id, household_id)
	if project.status != ConstructionProject.Status.PLANNED:
		return {
			"priority": ConstructionPriority.Priority.READY,
			"action": "already_progressing",
			"project_id": project.id,
		}

	var inputs: Array = recipe_book.recipe_inputs(blueprint_id)
	for input in inputs:
		var have: float = market.stock.get(input["item_id"], 0.0)
		if not ConstructionStartHysteresis.should_start(have, float(input["count"])):
			return {
				"priority": ConstructionPriority.Priority.READY,
				"action": "waiting_on_stock",
				"project_id": project.id,
			}

	for input in inputs:
		var item_id: String = input["item_id"]
		var count := float(input["count"])
		market.remove_stock(item_id, count)
		project.reserved_material[item_id] = project.reserved_material.get(item_id, 0.0) + count
	project.status = ConstructionProject.Status.IN_PROGRESS
	return {"priority": ConstructionPriority.Priority.READY, "action": "started", "project_id": project.id}


## Whether ANY of blueprint_id's real recipe inputs has crashed WELL below
## its own required count (ConstructionStartHysteresis.should_abandon) --
## a project can't proceed without every one of its inputs, so any single
## one collapsing is real grounds to abandon.
static func _any_input_crashed(market, recipe_book, blueprint_id: String) -> bool:
	for input in recipe_book.recipe_inputs(blueprint_id):
		var have: float = market.stock.get(input["item_id"], 0.0)
		if ConstructionStartHysteresis.should_abandon(have, float(input["count"])):
			return true
	return false
