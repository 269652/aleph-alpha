extends RefCounted

## City Hall's own real "compute demands" step (see docs/concept/
## npc_role_consensus.md's "City Hall" section, pillar 4): reuses
## ConstructionPriority/NeedResolver's existing recipe-graph walk -- no new
## needs computation. Scans EVERY real recipe in the book that names a
## `requires_structure` (via CraftingRecipeBook.recipe_requires_structure)
## and reports the ones currently blocked on that missing structure
## (ConstructionPriority.Priority.BUILD_PRODUCER_FIRST) as the settlement's
## real, current demands. A pure material shortfall (a structure IS
## present but stock is short) is deliberately excluded -- that stays the
## existing shortfall/regional-trade path's own job, per pillar 4's "do not
## invent a second, parallel needs computation" framing.
##
## Where a recipe's own gate is an abstract multi-structure category (e.g.
## "heat_source", satisfied by either a campfire or a furnace) rather than
## one concrete buildable id, the reported missing_structure_id is that
## same abstract name -- an honest, already-documented limitation of
## ConstructionPriority.missing_structure_id itself (see its own doc
## comment), not something this wrapper resolves or hides.
##
## Wired to a real live caller: EarthChunkManager.city_hall_demands_near
## gates this behind a real "city_hall" structure standing nearby (see
## docs/concept/npc_role_consensus.md's own Status).

const ConstructionPriority = preload("res://src/gameplay/construction_priority.gd")

static var _priority := ConstructionPriority.new()


## Every real structure-gated recipe currently blocked on its own missing
## structure, given `local_stock` (item_id -> count), `present_structure_
## ids`, `recipe_book`, and `allocated_nodes` (SkillTree allocated-node
## shape, default empty -- the same defaults ConstructionPriority.decide
## itself already uses). Returns `[{"recipe_id": String, "output_item_id":
## String, "missing_structure_id": String}, ...]`, one entry per
## structure-gated recipe reporting BUILD_PRODUCER_FIRST, in the recipe
## book's own iteration order. Never includes a recipe that's READY (its
## structure is present) or a pure material SHORTFALL.
static func demands_for(
	local_stock: Dictionary, present_structure_ids: Array, recipe_book, allocated_nodes: Dictionary = {}
) -> Array:
	var demands: Array = []
	for recipe_id in recipe_book.recipe_ids():
		if recipe_book.recipe_requires_structure(recipe_id) == "":
			continue
		var priority_result: int = _priority.decide(
			recipe_id, local_stock, present_structure_ids, recipe_book, allocated_nodes
		)
		if priority_result != ConstructionPriority.Priority.BUILD_PRODUCER_FIRST:
			continue
		var missing := _priority.missing_structure_id(
			recipe_id, local_stock, present_structure_ids, recipe_book, allocated_nodes
		)
		demands.append({
			"recipe_id": recipe_id,
			"output_item_id": recipe_book.recipe_output(recipe_id)["item_id"],
			"missing_structure_id": missing,
		})
	return demands
