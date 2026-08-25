extends RefCounted

## The collection of ConstructionProjects (see docs/concept/
## timber_construction.md's "Settlement construction ledger" section).
##
## Same shape as HouseholdStore: a plain RefCounted collection, no engine
## dependency, its own to_dicts/from_dicts for a future persistence wrapper
## to wield (mirroring HouseholdStorePersistence's own split) -- and the
## same idempotent-creation contract start_project/form_household both
## carry: asking twice for the same real-world key returns the SAME entry,
## never a duplicate.

const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")

var _projects: Dictionary = {}   # id -> ConstructionProject


## A project at (chunk_coord, origin) for blueprint_id, assigned to
## household_id -- forming a fresh PLANNED one if this exact site+blueprint
## hasn't been asked about before, idempotent, so calling this twice does
## not reset an already-progressing project's own accumulated state (the
## same reasoning HouseholdStore.form_household's own doc comment gives).
func start_project(
	chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String, household_id: String
) -> ConstructionProject:
	var id := ConstructionProject.id_for_site(chunk_coord, origin, blueprint_id)
	if _projects.has(id):
		return _projects[id]
	var project: ConstructionProject = ConstructionProject.for_site(chunk_coord, origin, blueprint_id, household_id)
	_projects[id] = project
	return project


## Looks a project up by its OWN id -- the same "get_X by X's own id"
## accessor HouseholdStore.get_household already provides.
func get_project(project_id: String) -> ConstructionProject:
	return _projects.get(project_id)


## Looks a project up by the SAME (chunk_coord, origin, blueprint_id) key
## start_project derives its id from, without the caller needing to already
## hold the id string.
func find_project(chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String) -> ConstructionProject:
	return _projects.get(ConstructionProject.id_for_site(chunk_coord, origin, blueprint_id))


## Marks a project COMPLETE and grants its property to its assigned
## household -- HouseholdStore.grant_property(household_id,
## "house_<chunk>_<origin>"), already correct as-is (this doc's own
## "Ownership" section). False, no mutation, for an unknown project_id.
func complete_project(project_id: String, household_store) -> bool:
	var project: ConstructionProject = _projects.get(project_id)
	if project == null:
		return false
	project.status = ConstructionProject.Status.COMPLETE
	household_store.grant_property(project.household_id, project.property_id())
	return true


## The real caller for docs/concept/timber_construction.md's "Unloaded /
## offscreen fidelity" subsection: advances one project's real labor-hours
## by `elapsed_seconds` of `capacity` (builder_count) via
## construction_catchup.advance, and -- once the returned accumulated hours
## reach the project's own real labor_hours_required (derived from its
## recipe via ConstructionLabor, since there is no HouseBlueprint.
## total_labor_hours field) -- completes it through the ALREADY-CORRECT
## complete_project above rather than reimplementing what it already does
## (marking COMPLETE and granting household_store the property).
##
## No-ops (returns {"action": "no_op"}, no mutation) for an unknown
## project_id or any project not currently IN_PROGRESS -- PLANNED/COMPLETE/
## ABANDONED all mean either nothing has actually started being built yet or
## there is nothing left to advance; only a project with material already
## reserved (IN_PROGRESS) is actually being built. `recipe_book`: a
## CraftingRecipeBook (for ConstructionLabor's own real requirement lookup).
## `household_store`: passed straight through to complete_project on
## completion.
func advance_project_labor(
	project_id: String, elapsed_seconds: float, capacity: Dictionary, recipe_book, household_store
) -> Dictionary:
	var project: ConstructionProject = _projects.get(project_id)
	if project == null or project.status != ConstructionProject.Status.IN_PROGRESS:
		return {"action": "no_op"}

	var required := ConstructionLabor.labor_hours_required(project.blueprint_id, recipe_book)
	var caught_up := ConstructionCatchup.new().advance(
		{"labor_hours_accumulated": project.labor_hours_accumulated, "labor_hours_required": required},
		elapsed_seconds,
		capacity
	)
	project.labor_hours_accumulated = caught_up["labor_hours_accumulated"]

	if project.labor_hours_accumulated >= required and required > 0.0:
		complete_project(project_id, household_store)
		return {"action": "completed", "project_id": project_id}
	return {"action": "advanced", "project_id": project_id}


## For a future ConstructionProjectStorePersistence -- pure serialization,
## no FileAccess (same split EventStore/HouseholdStore already use).
func to_dicts() -> Array:
	var out: Array = []
	for id in _projects:
		var project: ConstructionProject = _projects[id]
		out.append({
			"id": project.id,
			"chunk_coord": [project.chunk_coord.x, project.chunk_coord.y],
			"origin": [project.origin.x, project.origin.y],
			"blueprint_id": project.blueprint_id,
			"household_id": project.household_id,
			"status": project.status,
			"labor_hours_accumulated": project.labor_hours_accumulated,
			"reserved_material": project.reserved_material,
		})
	return out


static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	for d in dicts:
		var project: ConstructionProject = ConstructionProject.new()
		project.id = d.get("id", "")
		var chunk: Array = d.get("chunk_coord", [0, 0])
		project.chunk_coord = Vector2i(int(chunk[0]), int(chunk[1]))
		var origin_arr: Array = d.get("origin", [0, 0])
		project.origin = Vector2i(int(origin_arr[0]), int(origin_arr[1]))
		project.blueprint_id = d.get("blueprint_id", "")
		project.household_id = d.get("household_id", "")
		project.status = int(d.get("status", ConstructionProject.Status.PLANNED))
		project.labor_hours_accumulated = float(d.get("labor_hours_accumulated", 0.0))
		var restored_material: Dictionary = d.get("reserved_material", {})
		for item_id in restored_material:
			project.reserved_material[str(item_id)] = float(restored_material[item_id])

		store._projects[project.id] = project
	return store
