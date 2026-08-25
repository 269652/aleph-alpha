extends GutTest

## ConstructionProjectStore: the collection of ConstructionProjects (see
## docs/concept/timber_construction.md's "Settlement construction ledger"
## section). Mirrors HouseholdStore's own to_dicts/from_dicts/idempotent-
## creation shape exactly.

const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")

var store: ConstructionProjectStore


func before_each():
	store = ConstructionProjectStore.new()


# -- starting projects --------------------------------------------------------

func test_starting_a_project_returns_a_planned_project():
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	assert_eq(project.status, ConstructionProject.Status.PLANNED)
	assert_eq(project.blueprint_id, "storage")


## Idempotent -- asking twice for the same site+blueprint returns the SAME
## project, not a duplicate, mirroring form_household's own dedupe.
func test_starting_a_project_twice_for_the_same_site_returns_the_same_one():
	var first := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var second := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	assert_eq(first.id, second.id)


## Idempotent creation does not reset progress -- mutating the first
## project's own state and "starting" it again must not wipe that state.
func test_starting_a_project_twice_does_not_reset_its_progress():
	var first := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	first.labor_hours_accumulated = 4.0
	first.status = ConstructionProject.Status.IN_PROGRESS

	var second := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	assert_eq(second.labor_hours_accumulated, 4.0)
	assert_eq(second.status, ConstructionProject.Status.IN_PROGRESS)


func test_a_different_site_is_a_different_project():
	var a := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var b := store.start_project(Vector2i(3, -2), Vector2i(2, 1), "storage", "household:1")
	assert_ne(a.id, b.id)


# -- lookups ------------------------------------------------------------------

func test_get_project_finds_it_by_its_own_id():
	var started := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var found: ConstructionProject = store.get_project(started.id)
	assert_not_null(found)
	assert_eq(found.id, started.id)


func test_get_project_for_an_unknown_id_is_null():
	assert_null(store.get_project("construction_project:unknown"))


func test_find_project_looks_it_up_by_site_and_blueprint():
	var started := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var found: ConstructionProject = store.find_project(Vector2i(3, -2), Vector2i(1, 1), "storage")
	assert_not_null(found)
	assert_eq(found.id, started.id)


func test_find_project_for_a_site_with_no_project_is_null():
	assert_null(store.find_project(Vector2i(3, -2), Vector2i(1, 1), "storage"))


# -- completion + ownership ----------------------------------------------------

## HouseholdStore.grant_property(household_id, "house_<chunk>_<origin>") is
## already correct, per this doc's own "Ownership" section -- this just has
## to call it correctly on completion.
func test_completing_a_project_marks_it_complete_and_grants_its_property():
	var households := HouseholdStore.new()
	var household := households.form_household("npc:1")
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", household.id)

	var completed := store.complete_project(project.id, households)

	assert_true(completed)
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
	assert_eq(households.owner_of(project.property_id()), household.id)
	assert_eq(households.household_for("npc:1").property, [project.property_id()])


func test_completing_an_unknown_project_fails_without_touching_households():
	var households := HouseholdStore.new()
	var completed := store.complete_project("construction_project:unknown", households)
	assert_false(completed)


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dicts_and_from_dicts_round_trip_a_whole_store():
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	project.labor_hours_accumulated = 6.5
	project.reserved_material = {"wood": 12.0, "plank": 4.0}
	project.status = ConstructionProject.Status.IN_PROGRESS

	var restored := ConstructionProjectStore.from_dicts(store.to_dicts())
	var found: ConstructionProject = restored.get_project(project.id)

	assert_not_null(found)
	assert_eq(found.chunk_coord, Vector2i(3, -2))
	assert_eq(found.origin, Vector2i(1, 1))
	assert_eq(found.blueprint_id, "storage")
	assert_eq(found.household_id, "household:1")
	assert_eq(found.status, ConstructionProject.Status.IN_PROGRESS)
	assert_eq(found.labor_hours_accumulated, 6.5)
	assert_eq(found.reserved_material, {"wood": 12.0, "plank": 4.0})


func test_find_project_still_works_after_a_round_trip():
	store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var restored := ConstructionProjectStore.from_dicts(store.to_dicts())
	assert_not_null(restored.find_project(Vector2i(3, -2), Vector2i(1, 1), "storage"))
