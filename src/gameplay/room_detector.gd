extends RefCounted

## Which cells are enclosed by walls -- i.e. indoors (see
## docs/concept/building.md#what-enterable-means-in-a-top-down-game).
##
## This is the mechanism that makes a building a BUILDING rather than
## scenery. A 3D game gets enclosure for free from geometry; a top-down grid
## has to compute it. A region is INDOORS when it cannot reach the outside
## world by orthogonal steps through non-enclosing cells.
##
## Doors are the crux: they enclose (so a house with a door is still a
## house) while remaining walkable (so you can get in). That pair of
## properties, which BuildingPiece defines, is what this file relies on --
## and it is why "enterable" can be expressed at all on a flat grid.
##
## Pure logic over a grid, like BuildingPlacement, so the player's shelter
## check and the village generator's validation share one implementation.

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

const _NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


## Every enclosed room in `grid` (Vector2i cell -> piece_id), each as an
## Array of its interior cells. A room must contain at least one floor
## piece: a walled ring with nothing in it is a fence, not a house.
##
## Rooms are returned in a stable order (sorted by their top-left cell), so
## callers and tests get the same answer every time.
func find_rooms(grid: Dictionary) -> Array:
	if grid.is_empty():
		return []

	var bounds := _bounds(grid)
	var visited := {}
	var rooms := []

	for cell in grid:
		# Only interior-capable cells can start a region; an enclosing piece
		# is the boundary, never the inside.
		if visited.has(cell) or _encloses_at(grid, cell):
			continue
		var region := _flood(grid, cell, bounds, visited)
		if region.is_empty():
			continue  # escaped to the outside world
		if _has_floor(grid, region):
			region.sort()
			rooms.append(region)

	rooms.sort_custom(func(a, b): return _cell_before(a[0], b[0]))
	return rooms


## Is `cell` inside some enclosed room? Used for shelter effects and for
## hiding a roof while the player is under it.
func is_indoors(cell: Vector2i, grid: Dictionary) -> bool:
	return not room_containing(cell, grid).is_empty()


## The specific room containing `cell`, as its Array of interior cells -- the
## same room find_rooms would return, or an empty Array if `cell` isn't
## indoors at all. Useful when a caller needs to ACT on exactly the room a
## position is inside (e.g. hiding a roof over exactly the cells the player
## is standing under), not just get a yes/no answer.
func room_containing(cell: Vector2i, grid: Dictionary) -> Array:
	for room in find_rooms(grid):
		if room.has(cell):
			return room
	return []


## Flood outward from `start` through non-enclosing cells. Returns the
## region, or an empty Array if it reached beyond the structure's bounds --
## which means it escaped to the outside world and is therefore outdoors.
##
## Searching one cell PAST the bounding box is what makes "outside" well
## defined on an infinite grid: anything that gets that far is out.
func _flood(grid: Dictionary, start: Vector2i, bounds: Rect2i, visited: Dictionary) -> Array:
	var region := []
	var queue := [start]
	visited[start] = true
	var escaped := false

	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		region.append(cell)
		for offset in _NEIGHBORS:
			var next: Vector2i = cell + offset
			if visited.has(next):
				continue
			if not bounds.has_point(next):
				escaped = true  # stepped outside the structure entirely
				continue
			if _encloses_at(grid, next):
				continue  # a wall or a door stops the fill
			visited[next] = true
			queue.append(next)

	return [] if escaped else region


func _encloses_at(grid: Dictionary, cell: Vector2i) -> bool:
	return BuildingPiece.encloses(grid.get(cell, ""))


func _has_floor(grid: Dictionary, region: Array) -> bool:
	for cell in region:
		if BuildingPiece.category_of(grid.get(cell, "")) == BuildingPiece.CATEGORY_FLOOR:
			return true
	return false


## The structure's bounding box, grown by one cell so the flood has an
## "outside" to escape into.
func _bounds(grid: Dictionary) -> Rect2i:
	var min_cell := Vector2i(1 << 30, 1 << 30)
	var max_cell := Vector2i(-(1 << 30), -(1 << 30))
	for cell in grid:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
