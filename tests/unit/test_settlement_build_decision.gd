extends GutTest

## SettlementBuildDecision: docs/concept/timber_construction.md's "Deciding
## what to build, and who builds it" section's own real decision function --
## the settlement's real decision of WHAT to build next (ranking real
## shortfalls worst-first, picking the first with a real structural fix, and
## finally supplying SettlementConstruction.advance's own still-missing
## candidate blueprint_id argument) composed with "double-fix cancellation"
## (a settlement's own redundant queued producer project is abandoned once
## the player independently supplies the real fix first).

const SettlementBuildDecision = preload("res://src/emergence/settlement_build_decision.gd")
const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionPriority = preload("res://src/gameplay/construction_priority.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var projects: ConstructionProjectStore
var market: VillageMarket
var book: CraftingRecipeBook

const CHUNK := Vector2i(3, -2)
const ORIGIN := Vector2i(1, 1)


func before_each():
	projects = ConstructionProjectStore.new()
	market = VillageMarket.new()
	book = CraftingRecipeBook.new()


## Builds the same shape production_shortfall_quests_for_settlement's own
## "missing" list carries: [{item_id, need}, ...].
func _missing(item_id: String, need: float) -> Dictionary:
	return {"item_id": item_id, "need": need}


func _shortfall(missing: Array) -> Dictionary:
	return {"settlement_id": "settlement:test", "household_id": "household:1", "missing": missing}


# -- zero spare capacity: distinguishable from "nothing needed" --------------

func test_zero_spare_capacity_starts_nothing_and_is_named_distinctly():
	var shortfalls := [_shortfall([_missing("beam", 5.0)])]
	market.add_stock("log", 8.0)
	market.add_stock("wood", 4.0)

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 0
	)

	assert_eq(result["action"], "no_spare_capacity")
	assert_null(projects.find_project(CHUNK, ORIGIN, "sagewerk"))


func test_no_shortfalls_at_all_is_a_distinct_outcome_from_zero_spare_capacity():
	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, [], 3
	)
	assert_eq(result["action"], "no_actionable_shortfall")


# -- ranking: worst shortfall WITH a real structural fix wins -----------------

## "meat" has no real recipe producing it (gathered, not crafted) -- a pure
## raw-material issue with no structural fix, left to the existing shortfall
## path per this section's own framing. "beam" (log_to_balken) DOES have one
## (requires_structure "sagewerk", not present) -- even though its own need
## is smaller, it is the one this function acts on.
##
## Real log/wood stock and real allocated_nodes (the same carpentry_1 +
## carpentry_2 fixture test_construction_priority.gd's own skill-gate test
## already uses) are supplied so the recursive check on "sagewerk" ITSELF
## (SettlementConstruction.advance's own internal decide() call, checking
## whether building a Sägewerk is itself READY) clears rather than tripping
## the SAME real Carpentry gate one level deeper -- this test is about the
## ranking/selection logic, not a second exercise of the skill-gate
## limitation (see test_a_carpentry_gated_recipe_is_never_queued_even_as_
## the_only_shortfall below for that).
func test_picks_the_worst_shortfall_that_has_a_real_structural_fix_skipping_a_worse_one_that_does_not():
	var shortfalls := [
		_shortfall([_missing("meat", 50.0)]),   # worse need, no structural fix
		_shortfall([_missing("beam", 5.0)]),    # lesser need, HAS a structural fix
	]
	market.add_stock("log", 8.0)
	market.add_stock("wood", 4.0)
	var allocated_nodes := {"carpentry_1": true, "carpentry_2": true}

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3, allocated_nodes
	)

	assert_eq(result["priority"], ConstructionPriority.Priority.READY)
	assert_eq(result["item_id"], "beam")
	var producer_project := projects.find_project(CHUNK, ORIGIN, "sagewerk")
	assert_not_null(producer_project)
	assert_eq(producer_project.status, ConstructionProject.Status.IN_PROGRESS)


## Flattened across quests too -- a settlement's real shortfalls come as one
## quest per producing household, each carrying its own "missing" list; the
## ranking must consider every entry across every quest, not just the first
## quest's own list. Same real log/wood stock + allocated_nodes as the test
## above, for the same reason (clears the recursive Carpentry check on
## "sagewerk" itself so this test isolates ranking, not the skill gate).
func test_ranks_across_multiple_shortfall_quests_not_just_within_one():
	var shortfalls := [
		_shortfall([_missing("meat", 3.0)]),
		_shortfall([_missing("beam", 100.0)]),
	]
	market.add_stock("log", 8.0)
	market.add_stock("wood", 4.0)
	var allocated_nodes := {"carpentry_1": true, "carpentry_2": true}

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3, allocated_nodes
	)

	assert_eq(result["item_id"], "beam")
	assert_not_null(projects.find_project(CHUNK, ORIGIN, "sagewerk"))


func test_no_actionable_shortfall_when_every_gap_is_a_pure_material_issue():
	var shortfalls := [_shortfall([_missing("meat", 10.0), _missing("stick", 4.0)])]

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3
	)

	assert_eq(result["action"], "no_actionable_shortfall")
	assert_null(projects.find_project(CHUNK, ORIGIN, "sagewerk"))


# -- the real, honest skill-gate limitation -----------------------------------
#
# ANY recipe gated by required_skill (e.g. "sagewerk" itself, Carpentry-2.0)
# always resolves as blocked-on-skill with no missing_structure_id to queue
# (missing_structure_id's own doc comment: "" for a skill-only gate) -- this
# decision function can never autonomously queue building a second Sägewerk
# today, only skill-ungated real structures. Confirmed as a real test, not
# just a comment.

func test_a_carpentry_gated_recipe_is_never_queued_even_as_the_only_shortfall():
	# "sagewerk" itself is the missing item (recipe_for_output("sagewerk") ==
	# "sagewerk") -- required_skill (Carpentry-2.0) blocks it with NO
	# missing_structure_id (a skill-only gate), so nothing gets queued.
	var shortfalls := [_shortfall([_missing("sagewerk", 1.0)])]
	market.add_stock("log", 8.0)
	market.add_stock("wood", 4.0)

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3
	)

	assert_eq(result["action"], "no_actionable_shortfall")
	assert_null(projects.find_project(CHUNK, ORIGIN, "sagewerk"))


# -- double-fix cancellation ---------------------------------------------------

## A settlement already building its own missing producer (a queued PLANNED
## "sagewerk" project) has that project abandoned once a REAL sagewerk
## already exists nearby (present_structure_ids) -- the player independently
## brought/built the same real fix first. No second Sägewerk silently
## appears because the player got there first.
func test_abandons_a_redundant_planned_producer_project_once_the_real_structure_exists():
	var redundant := projects.start_project(CHUNK, ORIGIN, "sagewerk", "household:1")

	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", ["sagewerk"], book, [], 3
	)

	assert_eq(redundant.status, ConstructionProject.Status.ABANDONED)


func test_abandons_a_redundant_in_progress_producer_project_too():
	var redundant := projects.start_project(CHUNK, ORIGIN, "sagewerk", "household:1")
	redundant.status = ConstructionProject.Status.IN_PROGRESS

	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", ["sagewerk"], book, [], 3
	)

	assert_eq(redundant.status, ConstructionProject.Status.ABANDONED)


## Without the real fix present, the queued producer project is left alone --
## cancellation only fires once the structure is genuinely there.
func test_does_not_abandon_a_producer_project_while_the_structure_is_still_genuinely_missing():
	var project := projects.start_project(CHUNK, ORIGIN, "sagewerk", "household:1")

	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, [], 0
	)

	assert_eq(project.status, ConstructionProject.Status.PLANNED)


## "storage" is never a requires_structure target for any real recipe --
## a project to build a (possibly second) Storage must NOT be swept up by
## double-fix cancellation just because a Storage happens to already exist
## nearby; multiple real Storages per settlement are a real, intended
## feature (see EarthChunkManager.nearby_structure_positions).
func test_does_not_abandon_a_storage_project_even_though_a_storage_already_exists_nearby():
	var storage_project := projects.start_project(CHUNK, ORIGIN, "storage", "household:1")

	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", ["storage"], book, [], 0
	)

	assert_eq(storage_project.status, ConstructionProject.Status.PLANNED)


## Cancellation runs even with zero spare capacity -- it retires wasted
## work, it does not need population headroom to do that.
func test_double_fix_cancellation_runs_even_with_zero_spare_capacity():
	var redundant := projects.start_project(CHUNK, ORIGIN, "sagewerk", "household:1")

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", ["sagewerk"], book, [], 0
	)

	assert_eq(redundant.status, ConstructionProject.Status.ABANDONED)
	assert_eq(result["action"], "no_spare_capacity")


## A project at a DIFFERENT site (different chunk) is never touched.
func test_cancellation_never_touches_a_different_chunks_project():
	var elsewhere := projects.start_project(Vector2i(9, 9), ORIGIN, "sagewerk", "household:1")

	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", ["sagewerk"], book, [], 0
	)

	assert_eq(elsewhere.status, ConstructionProject.Status.PLANNED)
