extends GutTest

## CivicBuildDecision (docs/concept/civic_construction.md "Meeting Hall",
## building.md "City Hall over time"): whether a village raises its town
## hall on the plaza's reserved civic plot right now. Pure decision logic
## over the same real stores SettlementConstruction already uses -- the
## hall is one more ConstructionProject on the settlement ledger (spare
## hands + wood/stone drawn from the village market + labour hours), never
## an instant stamp. Branches, in order: already_standing (a hall is
## present), too_small (fewer than CITY_HALL_MIN_HOUSEHOLDS households --
## a hamlet has no need of a seat), no_spare_capacity (everyone works a
## survival job), else SettlementConstruction.try_start's own real
## hysteresis-gated start, owned by the settlement itself (a commons, not
## any one household).

const CivicBuildDecision = preload("res://src/emergence/civic_build_decision.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const ConstructionPriority = preload("res://src/gameplay/construction_priority.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")

var projects: ConstructionProjectStore
var market: VillageMarket
var book: CraftingRecipeBook

const CHUNK := Vector2i(3, -2)
const ORIGIN := Vector2i(14, 13)
var settlement_id := EntityRef.for_settlement(CHUNK)


func before_each():
	projects = ConstructionProjectStore.new()
	market = VillageMarket.new()
	book = CraftingRecipeBook.new()


func _stock_the_hall() -> void:
	market.add_stock("wood", 40.0)
	market.add_stock("stone", 20.0)


func _decide(households: int, spare: int, present: Array = []) -> Dictionary:
	return CivicBuildDecision.decide_and_advance(
		projects, market, CHUNK, ORIGIN, settlement_id, present, book, households, spare
	)


func test_the_household_threshold_is_pinned():
	assert_eq(CivicBuildDecision.CITY_HALL_MIN_HOUSEHOLDS, 3)


func test_a_standing_hall_means_nothing_to_do():
	_stock_the_hall()
	var result := _decide(5, 3, ["city_hall"])
	assert_eq(result["action"], "already_standing")
	assert_null(projects.find_project(CHUNK, ORIGIN, "city_hall"))
	assert_almost_eq(market.stock.get("wood", 0.0), 40.0, 0.001, "no stock drawn")


func test_a_hamlet_below_the_threshold_raises_no_hall():
	_stock_the_hall()
	var result := _decide(CivicBuildDecision.CITY_HALL_MIN_HOUSEHOLDS - 1, 3)
	assert_eq(result["action"], "too_small")
	assert_null(projects.find_project(CHUNK, ORIGIN, "city_hall"))


func test_no_spare_hands_means_no_hall_however_rich():
	_stock_the_hall()
	var result := _decide(5, 0)
	assert_eq(result["action"], "no_spare_capacity")
	assert_null(projects.find_project(CHUNK, ORIGIN, "city_hall"))


func test_a_big_enough_village_with_hands_and_stock_starts_the_hall():
	_stock_the_hall()

	var result := _decide(CivicBuildDecision.CITY_HALL_MIN_HOUSEHOLDS, 1)

	assert_eq(result["action"], "started")
	var project := projects.find_project(CHUNK, ORIGIN, "city_hall")
	assert_not_null(project)
	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS)
	assert_eq(project.household_id, settlement_id, "the hall is the settlement's own, a commons")


func test_starting_draws_the_halls_real_cost_from_the_market():
	_stock_the_hall()
	_decide(3, 1)
	assert_almost_eq(market.stock.get("wood", 0.0), 20.0, 0.001)
	assert_almost_eq(market.stock.get("stone", 0.0), 10.0, 0.001)
	var project := projects.find_project(CHUNK, ORIGIN, "city_hall")
	assert_almost_eq(project.reserved_material.get("wood", 0.0), 20.0, 0.001)
	assert_almost_eq(project.reserved_material.get("stone", 0.0), 10.0, 0.001)


## SettlementConstruction's own start gate (ConstructionStartHysteresis.
## should_start): every input must be fully in stock before anything is
## drawn -- one plank short and the plan waits, nothing spent.
func test_stock_short_of_the_cost_waits():
	market.add_stock("wood", 19.0)
	market.add_stock("stone", 10.0)

	var result := _decide(3, 1)

	assert_eq(result["action"], "waiting_on_stock")
	var project := projects.find_project(CHUNK, ORIGIN, "city_hall")
	assert_not_null(project, "the plan exists, waiting")
	assert_eq(project.status, ConstructionProject.Status.PLANNED)
	assert_almost_eq(market.stock.get("wood", 0.0), 19.0, 0.001, "nothing drawn while waiting")


func test_a_started_hall_is_never_started_twice():
	_stock_the_hall()
	_decide(3, 1)
	var result := _decide(3, 1)
	assert_eq(result["action"], "already_progressing")
	assert_almost_eq(market.stock.get("wood", 0.0), 20.0, 0.001, "drawn exactly once")


## Never SettlementConstruction._handle_shortfall's abandon: a waiting
## civic plan sits through a lean season rather than being retired.
func test_a_waiting_plan_survives_a_stock_crash():
	market.add_stock("wood", 19.0)
	market.add_stock("stone", 10.0)
	_decide(3, 1)
	market.remove_stock("wood", 18.0)

	var result := _decide(3, 1)

	assert_eq(result["action"], "waiting_on_stock")
	assert_eq(projects.find_project(CHUNK, ORIGIN, "city_hall").status, ConstructionProject.Status.PLANNED)


func test_completing_the_commons_project_grants_no_household_property_and_does_not_crash():
	_stock_the_hall()
	_decide(3, 1)
	var project := projects.find_project(CHUNK, ORIGIN, "city_hall")
	var households := HouseholdStore.new()
	assert_true(projects.complete_project(project.id, households))
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
