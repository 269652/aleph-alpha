extends RefCounted

## Quests as PROJECTIONS of real simulation state, never new authoritative
## content (docs/emergence/07-implementation-roadmap.md Phase 12: "Refactor
## quests into projections of household, institution, settlement, ecology,
## infrastructure, history, and economy problems. Disabling quests must not
## remove the underlying problem.") -- deliberately NOT a Store: a quest
## here is a pure, stateless VIEW over data that already exists elsewhere
## (Market/production, Phase 5), never persisted, never recorded as an
## event. Deleting every function in this file changes nothing about
## whether a settlement's market is actually short on stock -- it only
## removes the player-facing framing of that real shortage. This is also
## why a quest is always CURRENT: recomputed fresh every call, it can never
## go stale the way a recorded "quest offered" event could once the
## shortage it named is resolved.
##
## Deliberately narrow first slice, same discipline as every earlier phase:
## of docs/concept/quests.md's three need sources (safety, production,
## social), only PRODUCTION is grounded in real, already-tracked data
## (Phase 5's Market/CraftingRecipeBook). Safety needs
## docs/concept/worldbosses.md's threat detection (Phase 11, no live
## trigger yet) and NPC threat-memory thresholds (not built); social is
## explicitly deferred by quests.md itself ("lightest touch... deferred
## detailed design"). Quorum/promotion/representative-selection (needs
## factions.md's reputation score, not built) and resolution/consequences
## (needs a currency-to-NPC transaction, not built) are all out of scope
## for this slice too -- this is discovery only: can a real quest be
## derived from real state at all.

const OccupationProduction = preload("res://src/emergence/occupation_production.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const NeedResolver = preload("res://src/gameplay/need_resolver.gd")


## A settlement's own household needs a real recipe input its market
## doesn't have -- the literal docs/concept/quests.md "Production" need
## source: "A crafting or farming NPC short a recipe input they can't
## source themselves." One quest per household whose occupation-grounded
## recipe is currently blocked, naming the SPECIFIC missing item(s) and how
## many -- not just "production failed" (Phase 5's own event), which isn't
## actionable for a player deciding what to bring.
##
## `household_occupations`: Dictionary of household_id -> occupation
## (already-real data the caller reads from HouseholdStore/NpcIdentity).
static func production_shortfall_quests_for(
	settlement_id: String, household_occupations: Dictionary, market, recipe_book: CraftingRecipeBook
) -> Array:
	var quests: Array = []
	for household_id in household_occupations:
		var occupation: String = household_occupations[household_id]
		var recipe_id := OccupationProduction.recipe_for(occupation)
		if recipe_id == "":
			continue
		var missing := _missing_inputs(market, recipe_book, recipe_id)
		if missing.is_empty():
			continue
		quests.append({
			"settlement_id": settlement_id,
			"household_id": household_id,
			"recipe_id": recipe_id,
			"missing": missing,
		})
	return quests


## Every recipe input this market's CURRENT stock falls short of, and by
## how much -- reads the same real `Market.stock`/`CraftingRecipeBook.
## recipe_inputs` Phase 5's own `attempt_production`/`Market.produce`
## already use, no second stock/recipe model.
static func _missing_inputs(market, recipe_book: CraftingRecipeBook, recipe_id: String) -> Array:
	var missing: Array = []
	for input in recipe_book.recipe_inputs(recipe_id):
		var have: int = market.stock_of(input["item_id"])
		if have < input["count"]:
			missing.append({"item_id": input["item_id"], "need": input["count"] - have})
	return missing


## ADDITIVE capability (see docs/concept/production_chains.md): for ONE
## specific item named in a production_shortfall_quests_for "missing" list
## (or any other item id a caller wants the deeper picture on), resolves
## what actually producing more of it needs -- a missing skill, a missing
## structure, or deeper missing sub-materials, possibly several hops down
## -- via NeedResolver's real recursive walk over CraftingRecipeBook.
##
## Deliberately does NOT change production_shortfall_quests_for's own
## signature, behavior, or its one real call site
## (EarthChunkManager.production_shortfall_quests_for_settlement,
## earth_chunk_manager.gd:1329-1336) -- this is a separate, additive
## function a caller reaches for only when it wants MORE than "how many of
## item_id are missing," e.g. to explain to a player (or a settlement's own
## construction-ledger reasoning, per timber_construction.md) WHY an item
## is missing and what would actually resolve it.
static func deeper_need_for(
	item_id: String, stock: Dictionary, allocated_nodes: Dictionary, nearby_structures: Dictionary, recipe_book: CraftingRecipeBook
) -> Array:
	return NeedResolver.new(recipe_book).resolve(item_id, stock, allocated_nodes, nearby_structures)
