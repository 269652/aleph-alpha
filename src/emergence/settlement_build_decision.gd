extends RefCounted

## docs/concept/timber_construction.md's "Deciding what to build, and who
## builds it" section: the settlement's own real decision of WHAT to build
## next, and whether it can act on it right now -- this is the still-missing
## candidate `blueprint_id` argument SettlementConstruction.advance's own doc
## comment names ("Given ... a candidate blueprint (a real CraftingRecipeBook
## recipe id) to build next at a specific site" -- this function is what
## finally SUPPLIES that candidate, closing the exact gap that module's own
## header already names). SettlementConstruction.advance itself is untouched.
##
## Two things happen every call, in this order:
##
## 1. **Double-fix cancellation** (this section's own "Two real needs
##    resolving each other" paragraph): every real PLANNED/IN_PROGRESS
##    ConstructionProject at this site whose blueprint_id names a real
##    structure-producing recipe is re-checked against the REAL, CURRENT
##    ConstructionPriority.missing_structure_id for whatever recipe in the
##    book actually depends on that structure (`recipe_requires_structure`) --
##    if the structure is no longer missing (the player independently
##    brought/built the real fix), the project is abandoned via
##    ConstructionProjectStore.abandon_project. Deliberately scoped to
##    structures that SOME real recipe actually gates on (`requires_structure`
##    names them) -- a structure nothing ever gates on (e.g. "storage", which
##    has no skill/structure prerequisite of its own) is never a
##    double-fix-cancellation target, since a settlement may legitimately
##    want a SECOND one (see EarthChunkManager.nearby_structure_positions --
##    multiple real Storages per settlement is an intended feature, not a
##    redundancy). Runs unconditionally, independent of spare capacity --
##    retiring wasted work needs no population headroom.
##
## 2. **What to build next**: `shortfalls` is the SAME shape
##    production_shortfall_quests_for_settlement already returns (one entry
##    per producing household, each carrying its own real "missing" list --
##    `[{item_id, need}, ...]`, `need` already a real magnitude, no new
##    number invented). Every missing item across every shortfall is ranked
##    worst-need-first; for each (worst first), `recipe_book.
##    recipe_for_output(item_id)` names the recipe that would actually
##    produce more of it (empty for a raw/gathered item with no recipe at
##    all -- a pure material issue with no possible structural fix, left to
##    the existing shortfall/regional-trade path unchanged, per this
##    section's own framing) -- the first shortfall (worst first) whose
##    recipe DOES resolve a real missing_structure_id is the one this
##    function acts on: if `spare_capacity > 0`, it calls the ALREADY-REAL
##    SettlementConstruction.advance with that missing structure's own
##    recipe id as the candidate blueprint_id. `spare_capacity <= 0` returns
##    a distinctly-named `{"action": "no_spare_capacity"}` BEFORE even
##    looking at shortfalls -- a settlement at subsistence does not build no
##    matter how bad its shortfall is, and that outcome must never read the
##    same as "nothing needed" (`{"action": "no_actionable_shortfall"}`,
##    returned when every real shortfall is either absent or a pure
##    material issue with no structural fix).
##
## **Named, honest limitation** (see this doc's own "Deciding what to build"
## section for the full account): SettlementConstruction.advance/
## ConstructionPriority.decide take an `allocated_nodes` SkillTree pool a
## settlement has no real source for -- this function passes decide's own
## existing empty-Dictionary default, so ANY recipe gated by `required_skill`
## (the real "sagewerk" recipe's own Carpentry-2.0 requirement) always
## resolves blocked-on-skill with NO missing_structure_id to queue (per
## missing_structure_id's own doc comment: "" for a skill-only gate) -- this
## function can never autonomously queue building a second Sägewerk today,
## only skill-ungated real structures (e.g. "storage"). A real, accepted gap
## -- no settlement-level skill/labor model exists -- not worked around here.
##
## Static-function module, the same explicit-dependencies-in shape
## SettlementConstruction/Quest.gd already use -- no stored state of its own.

const SettlementConstruction = preload("res://src/emergence/settlement_construction.gd")
const ConstructionPriority = preload("res://src/gameplay/construction_priority.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")


## `project_store`: ConstructionProjectStore. `market`: VillageMarket.
## `shortfalls`: production_shortfall_quests_for_settlement's own real
## return shape. `spare_capacity`: SettlementSpareCapacity.for_settlement's
## own real result. See this file's own header for the full contract.
static func decide_and_advance(
	project_store,
	market,
	chunk_coord: Vector2i,
	origin: Vector2i,
	household_id: String,
	present_structure_ids: Array,
	recipe_book,
	shortfalls: Array,
	spare_capacity: int,
	allocated_nodes: Dictionary = {}
) -> Dictionary:
	_cancel_redundant_producer_projects(project_store, market, chunk_coord, present_structure_ids, recipe_book, allocated_nodes)

	if spare_capacity <= 0:
		return {"action": "no_spare_capacity"}

	for item_id in _rank_shortfalls(shortfalls):
		var recipe_id: String = recipe_book.recipe_for_output(item_id)
		if recipe_id == "":
			continue  # a pure raw/gathered material -- no structural fix possible

		var priority: int = ConstructionPriority.new().decide(
			recipe_id, market.stock, present_structure_ids, recipe_book, allocated_nodes
		)
		if priority != ConstructionPriority.Priority.BUILD_PRODUCER_FIRST:
			continue

		var missing_structure_id: String = ConstructionPriority.new().missing_structure_id(
			recipe_id, market.stock, present_structure_ids, recipe_book, allocated_nodes
		)
		if missing_structure_id == "":
			continue  # a skill-only gate -- nothing spatial to queue (see this file's own header)

		var result: Dictionary = SettlementConstruction.advance(
			project_store, market, chunk_coord, origin, missing_structure_id, household_id,
			present_structure_ids, recipe_book, allocated_nodes
		)
		result["item_id"] = item_id
		return result

	return {"action": "no_actionable_shortfall"}


## Flattens every real shortfall quest's own "missing" list into one ranked
## Array of item_id, worst (largest need) first -- item_id itself as a
## deterministic tie-break, per this project's determinism discipline.
##
## Sorts via a `[-need, item_id]` key array rather than a custom comparator
## Callable: GDScript's default Array `<` already compares element-wise
## (float first, then String), so ascending-sorting `-need` puts the
## LARGEST real need first, with item_id as the automatic, deterministic
## tie-break -- no lambda/Callable needed for a two-key sort this simple.
static func _rank_shortfalls(shortfalls: Array) -> Array:
	var sort_keys: Array = []
	for shortfall in shortfalls:
		for missing in shortfall.get("missing", []):
			sort_keys.append([-float(missing["need"]), String(missing["item_id"])])
	sort_keys.sort()

	var ranked_item_ids: Array = []
	for key in sort_keys:
		ranked_item_ids.append(key[1])
	return ranked_item_ids


## Every real PLANNED/IN_PROGRESS project at this site whose blueprint_id
## names a real structure-producing recipe (its output is a real
## ItemCatalog "placeable") AND is a genuine producer-fix target (SOME real
## recipe in the book actually `requires_structure` it -- see this file's
## own header for why "storage" is deliberately excluded) is abandoned once
## that structure is no longer missing.
static func _cancel_redundant_producer_projects(
	project_store, market, chunk_coord: Vector2i, present_structure_ids: Array, recipe_book, allocated_nodes: Dictionary
) -> void:
	var catalog := ItemCatalog.new()
	for project in project_store.active_projects_in_chunk(chunk_coord):
		var output: Dictionary = recipe_book.recipe_output(project.blueprint_id)
		if output.is_empty():
			continue
		if catalog.kind_of(output["item_id"]) != "placeable":
			continue

		var dependent_recipe_id := _first_recipe_requiring_structure(project.blueprint_id, recipe_book)
		if dependent_recipe_id == "":
			continue  # nothing in the book ever gates on this structure -- not a producer-fix target

		var still_missing: String = ConstructionPriority.new().missing_structure_id(
			dependent_recipe_id, market.stock, present_structure_ids, recipe_book, allocated_nodes
		)
		if still_missing == "":
			project_store.abandon_project(project.id)


## The first real recipe (book iteration order -- deterministic, `_RECIPES`
## is a fixed Dictionary literal) whose `requires_structure` names
## `structure_id`, or "" if nothing in the book ever gates on it.
static func _first_recipe_requiring_structure(structure_id: String, recipe_book) -> String:
	for recipe_id in recipe_book.recipe_ids():
		if recipe_book.recipe_requires_structure(recipe_id) == structure_id:
			return recipe_id
	return ""
