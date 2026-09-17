extends RefCounted

## Every blueprint currently laid out but not yet built -- the standing
## wireframes of docs/concept/planner_mode.md.
##
## Pure logic over cells. Ground buildability arrives as a `Callable`
## rather than being read from a chunk, exactly as `BuildingPlacement`
## already takes it and for its own stated reason: water and cliff rules
## belong to the world, not to the rules of construction. That is also
## what makes the whole ledger testable with no chunk loaded.
##
## Holds no materials and starts nothing: a plan is an intention, and the
## real cost falls when somebody raises it (planner_mode.md's pillar 1).

const BuildPlan = preload("res://src/world/build_plan.gd")

var _plans: Dictionary = {}


## Lays a blueprint down, or returns "" and changes nothing if it may not
## go there. The id is `BuildPlan.plan_id`'s deterministic one, so planning
## the same thing on the same site twice is idempotent rather than a
## duplicate.
func plan(
	chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String, now: float,
	buildable_ground: Callable
) -> String:
	if not refusal_reason(chunk_coord, origin, blueprint_id, buildable_ground).is_empty():
		return ""
	var record := BuildPlan.new(chunk_coord, origin, blueprint_id, now)
	_plans[record.id] = record
	return record.id


## Why a plan is refused, or "" when it may go there.
##
## A reason rather than a bare bool, mirroring `BuildingPlacement.
## refusal_reason`'s own rule: the build cursor should explain itself
## rather than silently doing nothing.
func refusal_reason(
	chunk_coord: Vector2i, origin: Vector2i, blueprint_id: String, buildable_ground: Callable
) -> String:
	if not BuildPlan.is_plannable(blueprint_id):
		return "There is no blueprint called \"%s\"." % blueprint_id
	var cells: Array = BuildPlan.footprint_cells(blueprint_id, origin)
	for cell in cells:
		if not bool(buildable_ground.call(cell)):
			return "The ground at %d,%d cannot be built on." % [cell.x, cell.y]
	for existing in _plans.values():
		if existing.chunk_coord != chunk_coord:
			continue
		# Same chunk only: an identical local origin in a different chunk is
		# another place entirely, not an overlap.
		for occupied in BuildPlan.footprint_cells(existing.blueprint_id, existing.origin):
			if cells.has(occupied):
				return "%s is already planned here." % BuildPlan.display_name_of(existing.blueprint_id)
	return ""


func plans() -> Array:
	return _plans.values()


## One chunk's own plans, for a renderer that draws only what is loaded.
func plans_in(chunk_coord: Vector2i) -> Array:
	var found: Array = []
	for record in _plans.values():
		if record.chunk_coord == chunk_coord:
			found.append(record)
	return found


## Whatever is planned over this cell, or null. This is what a player
## walking up to a wireframe is standing in front of.
func plan_at(chunk_coord: Vector2i, cell: Vector2i):
	for record in _plans.values():
		if record.chunk_coord != chunk_coord:
			continue
		if BuildPlan.footprint_cells(record.blueprint_id, record.origin).has(cell):
			return record
	return null


## Tears a wireframe down. Costs nothing, because planning cost nothing
## (planner_mode.md's pillar 1). False for an id that was never planned --
## the same "narrows, never crashes" contract the rest of this codebase
## follows.
func cancel(plan_id: String) -> bool:
	return _plans.erase(plan_id)


func count() -> int:
	return _plans.size()
