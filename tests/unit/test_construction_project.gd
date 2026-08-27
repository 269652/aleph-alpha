extends GutTest

## ConstructionProject: a single settlement building project in progress
## (see docs/concept/timber_construction.md's "Settlement construction
## ledger" section). Mirrors Household's own shape (household.gd) --
## deterministic id, no allocated counter -- keyed off a real, already-
## known site (chunk_coord + footprint origin) and blueprint id rather than
## a founder id.

const ConstructionProject = preload("res://src/emergence/construction_project.gd")


func test_a_fresh_project_at_a_site_is_planned():
	var project := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	assert_eq(project.status, ConstructionProject.Status.PLANNED)


func test_a_fresh_project_has_no_labor_hours_or_reserved_material_yet():
	var project := ConstructionProject.for_site(Vector2i(0, 0), Vector2i(0, 0), "storage", "household:1")
	assert_eq(project.labor_hours_accumulated, 0.0)
	assert_eq(project.reserved_material, {})


func test_a_project_records_its_own_site_blueprint_and_household():
	var project := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	assert_eq(project.chunk_coord, Vector2i(3, -2))
	assert_eq(project.origin, Vector2i(1, 1))
	assert_eq(project.blueprint_id, "storage")
	assert_eq(project.household_id, "household:1")


## Deterministic id, the same "deterministic key, not an allocated ID"
## idiom EntityRef itself already uses -- two calls describing the exact
## same site + blueprint must resolve to the exact same id, with no
## counter to protect from collision.
func test_the_project_id_is_deterministic_from_its_site_and_blueprint():
	var first := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var second := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:2")
	assert_eq(first.id, second.id, "same site+blueprint must derive the same id regardless of who's assigned")


func test_a_different_origin_derives_a_different_id():
	var a := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var b := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(2, 1), "storage", "household:1")
	assert_ne(a.id, b.id)


func test_a_different_blueprint_at_the_same_site_derives_a_different_id():
	var a := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	var b := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "sagewerk", "household:1")
	assert_ne(a.id, b.id)


## id_for_site is what ConstructionProjectStore.find_project/start_project
## key off without needing a full ConstructionProject constructed first.
func test_id_for_site_matches_a_constructed_projects_own_id():
	var project := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	assert_eq(ConstructionProject.id_for_site(Vector2i(3, -2), Vector2i(1, 1), "storage"), project.id)


## This doc's own literal "house_<chunk>_<origin>" naming
## (docs/concept/timber_construction.md's "Ownership" section), via the
## SAME EntityRef.for_kind("house", ...) idiom
## EarthChunkManager.record_settlement_founded_if_new already uses for a
## villager's own house id -- completed ledger houses share the identical
## id shape, not a second naming scheme.
func test_property_id_matches_the_docs_own_house_chunk_origin_naming():
	const EntityRef = preload("res://src/emergence/entity_ref.gd")
	var project := ConstructionProject.for_site(Vector2i(3, -2), Vector2i(1, 1), "storage", "household:1")
	assert_eq(project.property_id(), EntityRef.for_kind("house", "3_-2_1_1"))
