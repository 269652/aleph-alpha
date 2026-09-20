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


# -- the bread chain: raised from its root, but never from the farm ---------
#
## docs/concept/milling_and_baking.md: a settlement short of bread must raise
## the chain from its DEEPEST missing producer, never a bakery that would
## stand waiting on flour that never comes.
##
## That root is the farm, and a village does not build farms
## (SETTLEMENT_WILL_NOT_RAISE, and docs/concept/npc_farm_production.md's own
## reversal) -- so with nothing built the whole chain is declined. Once a
## farm really stands there, whoever put it down, the same shortfall raises
## the mill and then the bakery exactly as before: the rule is about who
## builds a farm, not about the chain above it.
##
## Real recipe book, real materials for every link, no skill gates anywhere
## on the chain.

func _bread_shortfall() -> Array:
	return [_shortfall([_missing("bread", 12.0)])]


func _stock_the_whole_chain() -> void:
	market.add_stock("wood", 40.0)
	market.add_stock("stone", 20.0)
	market.add_stock("plant_fibre", 10.0)


## Rewritten, not deleted: this used to assert the opposite -- that the same
## shortfall STARTS a farm -- and that is exactly the spawn reported live,
## *"it just should not spawn this weird looking npc with that 3 soil
## tiles"*. What it still guards is the half that never changed: a village
## short of bread must not raise some middle link whose inputs can never
## arrive.
func test_a_bread_shortfall_with_nothing_built_raises_nothing_at_all():
	_stock_the_whole_chain()
	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, _bread_shortfall(), 3
	)
	assert_eq(result["action"], "no_actionable_shortfall")
	assert_null(projects.find_project(CHUNK, ORIGIN, "farm"), "a village does not build farms")
	assert_null(projects.find_project(CHUNK, ORIGIN, "mill"), "nor the chain above one")
	assert_null(projects.find_project(CHUNK, ORIGIN, "bakery"), "never a bakery with no flour ever coming")


func test_with_the_farm_present_the_same_shortfall_starts_the_mill_then_the_bakery():
	_stock_the_whole_chain()
	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", ["farm"], book, _bread_shortfall(), 3
	)
	assert_not_null(projects.find_project(CHUNK, ORIGIN, "mill"))

	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK + Vector2i(1, 0), ORIGIN, "household:1", ["farm", "mill"], book, _bread_shortfall(), 3
	)
	assert_not_null(projects.find_project(CHUNK + Vector2i(1, 0), ORIGIN, "bakery"))


func test_with_the_whole_chain_built_a_bread_shortfall_is_not_actionable():
	_stock_the_whole_chain()
	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", ["farm", "mill", "bakery"], book, _bread_shortfall(), 3
	)
	assert_eq(result["action"], "no_actionable_shortfall", "the chain exists; bread is a matter of time, not construction")


# -- the Farm is a player's structure, never a village's --------------------
#
# Reported live with one standing in a field: *"it just should not spawn this
# weird looking npc with that 3 soil tiles"*.
#
# A DECLINING village short of bread used to raise farm -> mill -> bakery on
# its own (docs/concept/milling_and_baking.md), and `farm` is the ROOT of
# that chain. What that produced was the one-tile placeable dropped on the
# first clear cell spiralling out from the village centre, with its narrow
# FarmerMarker beside it and its three plots at fixed offsets -- a second,
# redundant wheat mechanism standing next to the real one, since
# village_farms.md already gives the farmer occupation a real 3x2 farmhouse
# and a real fenced field.
#
# The farm recipe is wood (6) + plant_fibre (4) and carries NO skill gate, so
# every test below stocks those: refusing a farm the village could not have
# afforded anyway would prove nothing.


## The reported spawn itself: a real bread shortfall, real spare hands, and
## every material the farm needs in the market -- and still no farm.
func test_a_village_short_of_bread_never_raises_the_farm_placeable():
	var shortfalls := [_shortfall([_missing("bread", 9.0)])]
	market.add_stock("wood", 6.0)
	market.add_stock("plant_fibre", 4.0)

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3
	)

	assert_null(projects.find_project(CHUNK, ORIGIN, "farm"), "no farm may be queued")
	assert_eq(result["action"], "no_actionable_shortfall")


## Refusing the ROOT refuses the whole chain, rather than leaving a bakery
## standing waiting on flour that can never come.
func test_refusing_the_farm_refuses_the_rest_of_the_bread_chain_too():
	var shortfalls := [_shortfall([_missing("bread", 9.0)])]
	market.add_stock("wood", 6.0)
	market.add_stock("plant_fibre", 4.0)

	SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3
	)

	for structure_id in ["farm", "mill", "bakery"]:
		assert_null(
			projects.find_project(CHUNK, ORIGIN, structure_id),
			"%s is part of the chain the village declines" % structure_id
		)


## Refusing the farm must not make the village passive about everything else:
## a timber shortfall still raises its own producer exactly as before. Same
## log/wood stock and allocated_nodes the ranking tests above use, for the
## same reason (clears the recursive Carpentry gate on "sagewerk" itself).
func test_declining_the_farm_leaves_every_other_producer_decision_alone():
	var shortfalls := [_shortfall([_missing("beam", 5.0)])]
	market.add_stock("log", 8.0)
	market.add_stock("wood", 4.0)
	var allocated_nodes := {"carpentry_1": true, "carpentry_2": true}

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3, allocated_nodes
	)

	assert_eq(result.get("item_id", ""), "beam")
	assert_not_null(projects.find_project(CHUNK, ORIGIN, "sagewerk"))


## A bread shortfall must not shadow a fixable one ranked below it: the farm
## is SKIPPED, not treated as "decided nothing, stop looking". Bread needs 40
## against beam's 5, so bread is ranked first and still must not win.
func test_a_refused_farm_does_not_hide_a_smaller_shortfall_it_can_still_fix():
	var shortfalls := [_shortfall([_missing("bread", 40.0), _missing("beam", 5.0)])]
	market.add_stock("log", 8.0)
	market.add_stock("wood", 10.0)
	market.add_stock("plant_fibre", 4.0)
	var allocated_nodes := {"carpentry_1": true, "carpentry_2": true}

	var result := SettlementBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, "household:1", [], book, shortfalls, 3, allocated_nodes
	)

	assert_eq(result.get("item_id", ""), "beam", "bread is worse, but its only fix is refused")
	assert_null(projects.find_project(CHUNK, ORIGIN, "farm"))
	assert_not_null(projects.find_project(CHUNK, ORIGIN, "sagewerk"))
