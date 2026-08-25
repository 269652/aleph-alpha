extends GutTest

## SettlementConstruction: ConstructionPriority.decide's first real, live
## caller (docs/concept/timber_construction.md's own Status note: "nothing
## calls ConstructionPriority.decide from a real settlement-decision system
## yet"). Given a settlement's real local stock (VillageMarket), its
## present structure ids, and a candidate recipe/blueprint to build next at
## a real site, calls the real ConstructionPriority.decide and acts on the
## result: READY starts a real ConstructionProject and draws down real
## material; BUILD_PRODUCER_FIRST surfaces/queues the missing producer
## ahead of the project that needed it; SHORTFALL leaves the existing
## regional-trade/shortfall path untouched.

const SettlementConstruction = preload("res://src/emergence/settlement_construction.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
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


# -- READY: starts a real project and draws down real stock ------------------

func test_ready_starts_a_project():
	market.add_stock("wood", 12.0)
	market.add_stock("plank", 4.0)

	var result := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "storage", "household:1", [], book
	)

	assert_eq(result["priority"], ConstructionPriority.Priority.READY)
	var project := projects.find_project(CHUNK, ORIGIN, "storage")
	assert_not_null(project)
	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS)


func test_ready_draws_down_the_recipes_real_material_from_local_stock():
	market.add_stock("wood", 12.0)
	market.add_stock("plank", 4.0)

	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "storage", "household:1", [], book)

	assert_almost_eq(market.stock.get("wood", 0.0), 0.0, 0.001)
	assert_almost_eq(market.stock.get("plank", 0.0), 0.0, 0.001)


func test_ready_records_the_drawn_down_material_as_reserved_on_the_project():
	market.add_stock("wood", 12.0)
	market.add_stock("plank", 4.0)

	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "storage", "household:1", [], book)

	var project := projects.find_project(CHUNK, ORIGIN, "storage")
	assert_almost_eq(project.reserved_material.get("wood", 0.0), 12.0, 0.001)
	assert_almost_eq(project.reserved_material.get("plank", 0.0), 4.0, 0.001)


## Only surplus above the recipe's own requirement is left behind -- a
## draw-down takes exactly what the recipe costs, not the whole stockpile.
func test_ready_leaves_surplus_stock_beyond_the_recipes_own_requirement():
	market.add_stock("wood", 20.0)
	market.add_stock("plank", 4.0)

	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "storage", "household:1", [], book)

	assert_almost_eq(market.stock.get("wood", 0.0), 8.0, 0.001)


## A second call for the same site+blueprint after the project is already
## IN_PROGRESS must not draw down material a second time -- material is
## only ever reserved once.
func test_ready_does_not_double_draw_down_an_already_in_progress_project():
	market.add_stock("wood", 24.0)
	market.add_stock("plank", 8.0)

	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "storage", "household:1", [], book)
	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "storage", "household:1", [], book)

	assert_almost_eq(market.stock.get("wood", 0.0), 12.0, 0.001)
	assert_almost_eq(market.stock.get("plank", 0.0), 4.0, 0.001)


## A real, live gap decide()'s own "already-stocked output" shortcut can
## produce: log_to_balken reports READY because "beam" is already fully
## stocked (see test_construction_priority.gd's own
## test_an_already_stocked_output_is_ready_even_with_no_input_material),
## even though the recipe's OWN direct input ("log") is completely absent.
## This function's own hysteresis gate (ConstructionStartHysteresis, not an
## eyeballed assumption) catches that: it does not draw down material that
## is not really there, and leaves the project PLANNED rather than falsely
## marking it IN_PROGRESS.
func test_ready_does_not_draw_down_material_the_recipe_does_not_actually_have():
	market.add_stock("beam", 4.0)  # output already stocked -- decide() is READY
	# no "log" in stock at all -- log_to_balken's own real input requirement

	var result := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "log_to_balken", "household:1", [], book
	)

	assert_eq(result["priority"], ConstructionPriority.Priority.READY)
	assert_eq(result["action"], "waiting_on_stock")
	var project := projects.find_project(CHUNK, ORIGIN, "log_to_balken")
	assert_eq(project.status, ConstructionProject.Status.PLANNED)
	assert_eq(project.reserved_material, {})


# -- BUILD_PRODUCER_FIRST: surfaces AND queues the missing producer ----------

func test_build_producer_first_surfaces_the_missing_structure():
	var result := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "log_to_balken", "household:1", [], book
	)
	assert_eq(result["priority"], ConstructionPriority.Priority.BUILD_PRODUCER_FIRST)
	assert_eq(result["missing_structure_id"], "sagewerk")


## The real payoff this doc names directly: this does not silently no-op --
## it queues a real, tracked ConstructionProject for the missing PRODUCER
## itself, ahead of the project that needed it.
func test_build_producer_first_queues_a_real_project_for_the_missing_producer():
	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "log_to_balken", "household:1", [], book)

	var producer_project := projects.find_project(CHUNK, ORIGIN, "sagewerk")
	assert_not_null(producer_project)
	assert_eq(producer_project.status, ConstructionProject.Status.PLANNED)


## The ORIGINALLY requested blueprint does NOT get its own project started
## just because the block was named -- only the producer is queued.
func test_build_producer_first_does_not_start_the_originally_requested_blueprint():
	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "log_to_balken", "household:1", [], book)
	assert_null(projects.find_project(CHUNK, ORIGIN, "log_to_balken"))


## Idempotent: calling it again while the producer is still missing returns
## the SAME queued project, not a duplicate.
func test_build_producer_first_is_idempotent():
	var first := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "log_to_balken", "household:1", [], book
	)
	var second := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "log_to_balken", "household:1", [], book
	)
	assert_eq(first["project_id"], second["project_id"])


## A missing SKILL (not a structure) has nothing spatial to queue -- must
## still surface it plainly rather than throwing or silently no-op'ing.
func test_build_producer_first_surfaces_a_skill_gate_with_no_structure_to_queue():
	market.add_stock("log", 8.0)
	market.add_stock("wood", 4.0)
	var result := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "sagewerk", "household:1", [], book
	)
	assert_eq(result["priority"], ConstructionPriority.Priority.BUILD_PRODUCER_FIRST)
	assert_eq(result["missing_structure_id"], "")
	assert_eq(result["action"], "blocked_on_skill")


# -- SHORTFALL: leaves existing stock/shortfall state untouched --------------

func test_shortfall_creates_no_project_and_touches_no_stock():
	market.add_stock("wood", 1.0)

	var result := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "wooden_club", "household:1", [], book
	)

	assert_eq(result["priority"], ConstructionPriority.Priority.SHORTFALL)
	assert_null(projects.find_project(CHUNK, ORIGIN, "wooden_club"))
	assert_almost_eq(market.stock.get("wood", 0.0), 1.0, 0.001)


## A PLANNED project (materials not yet committed) sitting at this site
## survives a SHORTFALL call when stock only dipped JUST below the
## requirement -- the flicker case ConstructionStartHysteresis exists to
## prevent.
func test_shortfall_leaves_a_planned_project_alone_when_stock_only_dipped_slightly():
	var project := projects.start_project(CHUNK, ORIGIN, "wooden_club", "household:1")
	market.add_stock("wood", 2.9)  # just below the required 3, not well below

	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "wooden_club", "household:1", [], book)

	assert_eq(project.status, ConstructionProject.Status.PLANNED)


## The genuine abandon case: stock has crashed WELL below the requirement
## while the project was still merely PLANNED (materials never committed).
func test_shortfall_abandons_a_planned_project_when_stock_crashes_well_below_requirement():
	var project := projects.start_project(CHUNK, ORIGIN, "wooden_club", "household:1")
	# required is wood:3 -- well below ConstructionStartHysteresis.ABANDON_FRACTION * 3
	market.add_stock("wood", 0.5)

	var result := SettlementConstruction.advance(
		projects, market, CHUNK, ORIGIN, "wooden_club", "household:1", [], book
	)

	assert_eq(result["action"], "abandoned")
	assert_eq(project.status, ConstructionProject.Status.ABANDONED)


## Once a project is IN_PROGRESS its material is already reserved/removed
## from the shared pool -- a later SHORTFALL reading of the (now-reduced,
## by this project's OWN drawdown) shared stock must not retroactively
## abandon it. It already holds what it needs.
func test_shortfall_does_not_abandon_an_in_progress_project_whose_material_is_already_reserved():
	market.add_stock("wood", 3.0)
	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "wooden_club", "household:1", [], book)
	var project := projects.find_project(CHUNK, ORIGIN, "wooden_club")
	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS, "sanity check on the fixture")

	# Global wood stock is now 0 (this project's own drawdown) -- a second
	# call for the SAME site+blueprint reads SHORTFALL from the shared pool.
	SettlementConstruction.advance(projects, market, CHUNK, ORIGIN, "wooden_club", "household:1", [], book)

	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS)
