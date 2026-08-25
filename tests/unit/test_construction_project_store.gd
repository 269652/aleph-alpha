extends GutTest

## ConstructionProjectStore: the collection of ConstructionProjects (see
## docs/concept/timber_construction.md's "Settlement construction ledger"
## section). Mirrors HouseholdStore's own to_dicts/from_dicts/idempotent-
## creation shape exactly.

const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")

var store: ConstructionProjectStore
var recipe_book: CraftingRecipeBook


func before_each():
	store = ConstructionProjectStore.new()
	recipe_book = CraftingRecipeBook.new()


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


# -- offscreen labor catch-up (construction_catchup.gd's real caller) --------
#
# advance_project_labor is docs/concept/timber_construction.md's "Unloaded /
# offscreen fidelity" subsection's real caller: it derives a project's real
# labor_hours_required from its own recipe (ConstructionLabor), calls
# construction_catchup.advance with its current labor_hours_accumulated, and
# -- once accumulated reaches required -- calls the ALREADY-CORRECT
# complete_project (see the "completion + ownership" section above) rather
# than reimplementing it.

func test_advancing_labor_on_an_in_progress_project_with_enough_time_and_builders_completes_it_and_grants_the_property():
	var households := HouseholdStore.new()
	var household := households.form_household("npc:1")
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", household.id)
	project.status = ConstructionProject.Status.IN_PROGRESS

	# storage's real labor requirement is comfortably cleared by 30 days of
	# 4 builders' worth of hours.
	var elapsed := ChunkEcologyCatchup.SECONDS_PER_DAY * 30.0
	var result := store.advance_project_labor(project.id, elapsed, {"builder_count": 4.0}, recipe_book, households)

	assert_eq(result["action"], "completed")
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
	assert_eq(households.owner_of(project.property_id()), household.id)
	assert_eq(households.household_for("npc:1").property, [project.property_id()])


func test_advancing_labor_caps_accumulated_at_the_real_requirement_on_completion():
	var households := HouseholdStore.new()
	var household := households.form_household("npc:1")
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", household.id)
	project.status = ConstructionProject.Status.IN_PROGRESS

	var elapsed := ChunkEcologyCatchup.SECONDS_PER_DAY * 365.0
	store.advance_project_labor(project.id, elapsed, {"builder_count": 4.0}, recipe_book, households)

	assert_almost_eq(
		project.labor_hours_accumulated, ConstructionLabor.labor_hours_required("storage", recipe_book), 0.001
	)


func test_advancing_labor_with_only_partial_time_accumulates_real_partial_progress_without_completing():
	var households := HouseholdStore.new()
	var household := households.form_household("npc:1")
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", household.id)
	project.status = ConstructionProject.Status.IN_PROGRESS

	# One builder, one day only accumulates a small fraction of storage's
	# real requirement -- real partial progress, not completion.
	var elapsed := ChunkEcologyCatchup.SECONDS_PER_DAY * 1.0
	var result := store.advance_project_labor(project.id, elapsed, {"builder_count": 1.0}, recipe_book, households)

	assert_eq(result["action"], "advanced")
	assert_eq(project.status, ConstructionProject.Status.IN_PROGRESS)
	assert_gt(project.labor_hours_accumulated, 0.0)
	assert_lt(project.labor_hours_accumulated, ConstructionLabor.labor_hours_required("storage", recipe_book))
	assert_eq(households.owner_of(project.property_id()), "")


func test_advancing_labor_on_a_planned_project_is_a_no_op():
	var households := HouseholdStore.new()
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	# Still PLANNED -- material not reserved yet, so nothing is really
	# being built.
	var result := store.advance_project_labor(project.id, 1.0e6, {"builder_count": 4.0}, recipe_book, households)

	assert_eq(result["action"], "no_op")
	assert_eq(project.status, ConstructionProject.Status.PLANNED)
	assert_almost_eq(project.labor_hours_accumulated, 0.0, 0.0001)


func test_advancing_labor_on_a_complete_project_is_a_no_op():
	var households := HouseholdStore.new()
	var household := households.form_household("npc:1")
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", household.id)
	store.complete_project(project.id, households)

	var result := store.advance_project_labor(project.id, 1.0e6, {"builder_count": 4.0}, recipe_book, households)

	assert_eq(result["action"], "no_op")
	assert_eq(project.status, ConstructionProject.Status.COMPLETE)


func test_advancing_labor_on_an_abandoned_project_is_a_no_op():
	var households := HouseholdStore.new()
	var project := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	project.status = ConstructionProject.Status.ABANDONED

	var result := store.advance_project_labor(project.id, 1.0e6, {"builder_count": 4.0}, recipe_book, households)

	assert_eq(result["action"], "no_op")
	assert_eq(project.status, ConstructionProject.Status.ABANDONED)
	assert_almost_eq(project.labor_hours_accumulated, 0.0, 0.0001)


func test_advancing_labor_for_an_unknown_project_id_is_a_no_op():
	var households := HouseholdStore.new()
	var result := store.advance_project_labor(
		"construction_project:unknown", 1.0e6, {"builder_count": 4.0}, recipe_book, households
	)
	assert_eq(result["action"], "no_op")


# -- in_progress_projects_in_chunk (EarthChunkManager's own real chunk-unload/
# reload catch-up caller needs this to enumerate what to advance) ------------
#
# Additive lookup, the same "look up by a real key" shape find_project/
# get_project already establish, but returning every match at a SITE's own
# chunk_coord rather than one exact (chunk_coord, origin, blueprint_id) key --
# EarthChunkManager only knows "this chunk just reloaded," not which specific
# projects live in it.

func test_in_progress_projects_in_chunk_returns_only_real_in_progress_projects_at_that_site():
	var a := store.start_project(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	a.status = ConstructionProject.Status.IN_PROGRESS
	var b := store.start_project(Vector2i(3, -2), Vector2i(2, 2), "sagewerk", "household:1")
	b.status = ConstructionProject.Status.IN_PROGRESS
	# Still PLANNED -- must not be returned (advance_project_labor's own
	# identical no-op filter for a non-IN_PROGRESS project).
	store.start_project(Vector2i(3, -2), Vector2i(3, 3), "log_to_balken", "household:1")
	var elsewhere := store.start_project(Vector2i(9, 9), Vector2i(1, 1), "storage", "household:1")
	elsewhere.status = ConstructionProject.Status.IN_PROGRESS

	var found: Array = store.in_progress_projects_in_chunk(Vector2i(3, -2))

	assert_eq(found.size(), 2)
	var ids: Array = []
	for project in found:
		ids.append(project.id)
	assert_true(ids.has(a.id))
	assert_true(ids.has(b.id))


func test_in_progress_projects_in_chunk_is_empty_for_a_chunk_with_no_real_projects():
	assert_eq(store.in_progress_projects_in_chunk(Vector2i(50, 50)), [])
