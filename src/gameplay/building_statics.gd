extends RefCounted

## Real (simplified) structural statics over a piece grid (see
## docs/concept/timber_construction.md#real-statics-a-support-graph-over-the-
## piece-grid). Reuses RoomDetector's grid-over-local-cells shape and
## 4-neighbor flood-fill approach as its model (see room_detector.gd), but
## the traversal answers a different question: not "is this cell enclosed"
## but "does this load-bearing cell have a path of adjacent load-bearing
## cells back to a grounded cell within a maximum unsupported run" -- the
## doc's own beam-span reasoning turned into a graph distance cap: "a beam
## spanning between two posts... the further it spans unsupported, the less
## load it can carry before it sags and fails."
##
## Pure logic over a grid + an explicit grounded-cell set, like RoomDetector
## and BuildingPlacement -- the caller (EarthChunkManager) decides what
## "grounded" means for its own world (today: bare terrain bordering the
## structure; a future foundation piece could mark itself grounded too,
## since `grounded` may contain piece cells as well as terrain cells).
##
## No engine dependency beyond Godot's own Vector2i/Dictionary value types,
## so this runs and tests exactly like RoomDetector does, with no autoloads.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

const _NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

## How many further load-bearing cells a support chain may cross beyond a
## directly-grounded one before the far end is unsupported -- the game
## version of a beam's span limit. Real half-timbered (Fachwerk) framing
## commonly spaces its principal posts/bays roughly 3-5 units apart at this
## game's ~1-tile-per-post scale; 4 sits centrally in that real range.
## Pinned by test_max_unsupported_run_is_pinned rather than left as an
## eyeballed comment (this project's no-manual-tuning rule). Ships as one
## fixed span for every material tier this pass -- BuildingPiece.
## support_capacity_of exists and is real/tested, but isn't consumed here
## yet; deriving span capacity from a piece's real material properties is
## the named future upgrade (see docs/concept/timber_construction.md's
## "Interaction with other docs" section on materials.md).
const MAX_UNSUPPORTED_RUN := 4

## How far a non-load-bearing piece (floor/roof/door/window) may sit from
## the nearest SUPPORTED load-bearing cell -- shorter than
## MAX_UNSUPPORTED_RUN per the doc's own framing ("its own, shorter
## cantilever limit"): a plank floor/deck has no structural continuity of
## its own the way a chained post-to-post wall run does, so it can only
## reach as far as a real floor joist's own unsupported end -- typical
## residential joists span roughly 3-6m between bearing walls, so a single
## joist's own reach from ONE end, before an intermediate support is
## needed, is a few tile-widths at this game's per-tile scale. Manhattan
## distance (orthogonal steps), matching RoomDetector's own 4-neighbor
## convention.
##
## 3, not smaller: test_house_blueprint.gd's own
## test_every_blueprint_is_fully_statically_supported is the real
## calibration guard here, not just the number in isolation -- it builds
## every real HouseBlueprint (up to a 7x6 manor) across 30 seeds and
## asserts nothing comes back unsupported. A tighter limit (1, this doc's
## own Worked Example B language taken completely literally) actually
## flags real, already-shipped village houses' own dead-center floor
## tiles as permanently unsupported -- a real regression that test caught.
## Pinned by test_cantilever_limit_is_pinned_and_shorter_than_the_wall_span.
const CANTILEVER_LIMIT := 3

## How many real seconds a piece may sit unsupported before it actually
## collapses (see docs/concept/materials.md's "Topple / collapse" verb,
## reused rather than a bespoke "building HP" system, per pillar 2: "it
## eventually falls"). Short enough to stay "a piece doesn't just sit
## there," long enough to be a legible warning rather than an instant
## surprise -- 6 real seconds is a few heartbeats of "this is creaking,"
## not a blink-and-you-missed-it snap. Pinned by
## test_grace_seconds_is_pinned.
const GRACE_SECONDS := 6.0


## Which cells in `grid` (Vector2i local cell -> piece_id) are currently
## unsupported: a load-bearing piece (see BuildingPiece.is_load_bearing) with
## no path of adjacent load-bearing cells reaching a grounded cell within
## MAX_UNSUPPORTED_RUN steps, or a non-load-bearing piece with no SUPPORTED
## load-bearing cell within CANTILEVER_LIMIT. `grounded` is the set of local
## cells (Vector2i keys, values ignored) that terminate a support chain --
## bare terrain or a foundation piece, decided entirely by the caller, the
## same way RoomDetector leaves "what encloses" to BuildingPiece rather than
## deciding it itself.
##
## Returns a stable-sorted Array[Vector2i], the same determinism convention
## RoomDetector.find_rooms uses, so callers/tests get the same answer every
## time.
func unsupported_cells(grid: Dictionary, grounded: Dictionary) -> Array:
	var support_distance := _load_bearing_support_distance(grid, grounded)
	var unsupported: Array[Vector2i] = []
	for cell in grid:
		var piece_id: String = grid[cell]
		if BuildingPiece.is_load_bearing(piece_id):
			if not support_distance.has(cell):
				unsupported.append(cell)
		elif not _within_cantilever(cell, support_distance):
			unsupported.append(cell)
	unsupported.sort_custom(_cell_before)
	return unsupported


## The timed step: given the grid/grounded state, the PRIOR accumulated
## instability (Vector2i cell -> seconds continuously unsupported, from the
## last call), and how many real seconds just elapsed, advances instability
## for every currently-unsupported cell, forgets it for any cell that
## regained support, and collapses (removes from the returned grid, drops
## from instability, and lists in `collapsed`) any cell whose accumulated
## instability has now reached GRACE_SECONDS.
##
## A single unsupported_cells() pass already finds the COMPLETE unsupported
## set in one shot, cascade included: a piece can only ever appear in
## someone else's support_distance path by itself already being supported,
## so a wall with no path to the ground was never a valid stepping stone for
## the roof cantilevered off it either -- both are already flagged together,
## which is what makes Worked Example D's cascade ("the roof section it was
## holding up now unsupported, comes down in turn") resolve within this ONE
## call when `elapsed_seconds` alone is enough to cross both their grace
## periods, with no second manual trigger required.
##
## Pure: does not mutate `grid`, `grounded`, or `instability`. Returns
## {grid: Dictionary, instability: Dictionary, collapsed: Array[Vector2i]}.
func resolve(grid: Dictionary, grounded: Dictionary, instability: Dictionary, elapsed_seconds: float) -> Dictionary:
	var unsupported := unsupported_cells(grid, grounded)
	var unsupported_set := {}
	var working_instability: Dictionary = instability.duplicate()
	for cell in unsupported:
		unsupported_set[cell] = true
		working_instability[cell] = float(working_instability.get(cell, 0.0)) + elapsed_seconds
	for cell in instability.keys():
		if not unsupported_set.has(cell):
			working_instability.erase(cell)

	var working_grid: Dictionary = grid.duplicate()
	var collapsed: Array[Vector2i] = []
	for cell in unsupported:
		if working_instability[cell] >= GRACE_SECONDS:
			collapsed.append(cell)
			working_grid.erase(cell)
			working_instability.erase(cell)

	return {"grid": working_grid, "instability": working_instability, "collapsed": collapsed}


## BFS from every load-bearing cell that directly touches a grounded cell,
## over the load-bearing subgraph only (floors/roofs/doors/windows never
## relay support -- only a wall can), capped at MAX_UNSUPPORTED_RUN edges.
## Returns Vector2i cell -> int distance for every load-bearing cell
## reachable within the cap; a load-bearing cell absent from this map is
## unsupported.
func _load_bearing_support_distance(grid: Dictionary, grounded: Dictionary) -> Dictionary:
	var distance := {}
	var queue: Array[Vector2i] = []
	for cell in grid:
		if not BuildingPiece.is_load_bearing(grid[cell]):
			continue
		if _touches_grounded(cell, grounded):
			distance[cell] = 0
			queue.append(cell)

	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var current_distance: int = distance[current]
		if current_distance >= MAX_UNSUPPORTED_RUN:
			continue
		for offset in _NEIGHBORS:
			var next: Vector2i = current + offset
			if distance.has(next):
				continue
			if not grid.has(next) or not BuildingPiece.is_load_bearing(grid[next]):
				continue
			distance[next] = current_distance + 1
			queue.append(next)
	return distance


func _touches_grounded(cell: Vector2i, grounded: Dictionary) -> bool:
	if grounded.has(cell):
		return true
	for offset in _NEIGHBORS:
		if grounded.has(cell + offset):
			return true
	return false


## Is any SUPPORTED load-bearing cell within CANTILEVER_LIMIT orthogonal
## steps of `cell`? Walks the diamond of Manhattan distance <=
## CANTILEVER_LIMIT rather than a Chebyshev box, matching _NEIGHBORS'
## orthogonal-step convention.
func _within_cantilever(cell: Vector2i, support_distance: Dictionary) -> bool:
	for dx in range(-CANTILEVER_LIMIT, CANTILEVER_LIMIT + 1):
		var remaining := CANTILEVER_LIMIT - absi(dx)
		for dy in range(-remaining, remaining + 1):
			if dx == 0 and dy == 0:
				continue
			if support_distance.has(cell + Vector2i(dx, dy)):
				return true
	return false


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
