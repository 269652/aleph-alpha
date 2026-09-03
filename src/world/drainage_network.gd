extends RefCounted

## The static half of docs/concept/hydrology.md ("Layer 0: the drainage
## bake"): priority-flood depression filling, D8 flow direction, and flow
## accumulation over a height grid. Pure and engine-free -- packed arrays
## in, packed arrays out -- so the bake tool and the tests drive the same
## code over the real elevation asset and over a 5x5 synthetic bowl.
##
## Why priority-flood and not hydraulic_erosion.gd's droplet walk: the
## elevation asset is 8-bit, so every coastal plain reads as one flat
## plateau with no gradient at all, and a droplet stops dead on the first
## flat cell. Priority-flood (Barnes, Lehman & Mulla 2014) floods outward
## from the sea, raising each cell to at least its popper plus an epsilon,
## which gives every land cell a strictly descending path to the sea by
## construction -- across flats, and out of real closed basins, which it
## identifies (with their spill height) as a side effect.

## flow_direction value for a sea cell: it has no downstream.
const DIRECTION_SEA := 8
## depression_id value for a cell that is not in any depression.
const NO_DEPRESSION := -1

## The strictly-positive step the fill adds over a cell's popper. Small
## enough that a chain of thousands of plateau cells (one full asset row
## is 3840) accumulates far less than one 8-bit asset step (1/255), so an
## epsilon ramp can never be mistaken for a real depression; large enough
## to be exact in the float64 `filled` surface.
const FILL_EPSILON := 1e-7

## How far below its filled surface a cell must sit to count as being in a
## depression rather than on an epsilon-ramped flat. ~14m of the asset's
## 14,400m range: a quarter of one 8-bit step, so any real one-step basin
## qualifies and no epsilon chain can.
const DEFAULT_MIN_DEPRESSION_DEPTH := 0.001

## D8 neighbours, clockwise from north. Index is the direction code.
const NEIGHBOR_DX: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
const NEIGHBOR_DY: Array[int] = [-1, -1, 0, 1, 1, 1, 0, -1]
const NEIGHBOR_DISTANCE: Array[float] = [1.0, SQRT2, 1.0, SQRT2, 1.0, SQRT2, 1.0, SQRT2]

var width: int
var height: int
var wrap_x: bool
var sea_level: float

## The priority-flood surface: never below the input, raised inside
## depressions and by epsilon across flats. float64 so FILL_EPSILON is exact.
var filled: PackedFloat64Array
## Per cell: 0-7 (see NEIGHBOR_DX/DY), or DIRECTION_SEA.
var flow_direction: PackedByteArray
## Per cell: land cells draining through it, itself included; a sea cell
## counts only the land draining into it.
var accumulation: PackedInt32Array
## Per cell: index into `depressions`, or NO_DEPRESSION.
var depression_id: PackedInt32Array
## Each {id, cell_count, spill_elevation, spill_index, floor_elevation}.
var depressions: Array[Dictionary] = []

var _sea: PackedByteArray

# Binary min-heap keyed by (elevation, insertion sequence): the sequence
# tiebreak is what makes a flat flood out in a deterministic order.
var _heap_keys: PackedFloat64Array
var _heap_seq: PackedInt64Array
var _heap_items: PackedInt32Array
var _heap_size := 0
var _next_seq := 0


## Builds every field from `heights` (row-major, `a_width` x `a_height`,
## any scale as long as `a_sea_level` is on it). Cells below sea level are
## the sea; there must be at least one. `a_wrap_x` joins the east and west
## edges, as the real equirectangular asset requires. Returns self.
func build(
	heights: PackedFloat32Array,
	a_width: int,
	a_height: int,
	a_sea_level: float,
	a_wrap_x: bool = false,
	min_depression_depth: float = DEFAULT_MIN_DEPRESSION_DEPTH
) -> RefCounted:
	width = a_width
	height = a_height
	wrap_x = a_wrap_x
	sea_level = a_sea_level
	_fill(heights)
	_route()
	_accumulate()
	_label_depressions(heights, min_depression_depth)
	return self


func is_sea(index: int) -> bool:
	return _sea[index] == 1


## The cell `index` drains into, or -1 for a sea cell.
func downstream_index(index: int) -> int:
	var direction := flow_direction[index]
	if direction == DIRECTION_SEA:
		return -1
	return neighbor_index(index, direction)


## The cell one step in `direction` (0-7) from `index`, or -1 off the grid.
## Wraps east-west when wrap_x; never wraps north-south.
func neighbor_index(index: int, direction: int) -> int:
	var x := index % width
	@warning_ignore("integer_division")
	var y := index / width
	var nx := x + NEIGHBOR_DX[direction]
	var ny := y + NEIGHBOR_DY[direction]
	if ny < 0 or ny >= height:
		return -1
	if nx < 0 or nx >= width:
		if not wrap_x:
			return -1
		nx = posmod(nx, width)
	return ny * width + nx


func _fill(heights: PackedFloat32Array) -> void:
	var count := width * height
	filled.resize(count)
	_sea.resize(count)
	_sea.fill(0)
	var visited := PackedByteArray()
	visited.resize(count)
	visited.fill(0)
	_heap_size = 0
	_next_seq = 0

	for index in count:
		filled[index] = heights[index]
		if heights[index] < sea_level:
			_sea[index] = 1
			visited[index] = 1
			_heap_push(filled[index], index)
	if _heap_size == 0:
		push_error("DrainageNetwork.build: no sea cell to flood from")

	while _heap_size > 0:
		var current := _heap_pop()
		for direction in 8:
			var neighbor := neighbor_index(current, direction)
			if neighbor < 0 or visited[neighbor] == 1:
				continue
			visited[neighbor] = 1
			filled[neighbor] = maxf(float(heights[neighbor]), filled[current] + FILL_EPSILON)
			_heap_push(filled[neighbor], neighbor)


## D8 steepest descent on the filled surface. Every land cell has a
## strictly lower neighbour there (the cell that flooded it), so the
## result is acyclic and always terminates at the sea.
func _route() -> void:
	var count := width * height
	flow_direction.resize(count)
	for index in count:
		if _sea[index] == 1:
			flow_direction[index] = DIRECTION_SEA
			continue
		var best_direction := DIRECTION_SEA
		var best_slope := 0.0
		for direction in 8:
			var neighbor := neighbor_index(index, direction)
			if neighbor < 0:
				continue
			var slope := (filled[index] - filled[neighbor]) / NEIGHBOR_DISTANCE[direction]
			if slope > best_slope:
				best_slope = slope
				best_direction = direction
		flow_direction[index] = best_direction


## Upstream-count accumulation in topological order (Kahn's algorithm over
## the flow graph): headwaters first, each cell handing its count to its
## downstream once every contributor has handed over. Linear, no sort.
func _accumulate() -> void:
	var count := width * height
	accumulation.resize(count)
	var indegree := PackedInt32Array()
	indegree.resize(count)
	indegree.fill(0)
	for index in count:
		accumulation[index] = 0 if _sea[index] == 1 else 1
		var downstream := downstream_index(index)
		if downstream >= 0:
			indegree[downstream] += 1

	var queue := PackedInt32Array()
	for index in count:
		if _sea[index] == 0 and indegree[index] == 0:
			queue.append(index)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var downstream := downstream_index(index)
		if downstream < 0:
			continue
		accumulation[downstream] += accumulation[index]
		if _sea[downstream] == 0:
			indegree[downstream] -= 1
			if indegree[downstream] == 0:
				queue.append(downstream)


## A depression is an 8-connected component of cells the fill raised by
## more than `min_depth`. Its spill is the component's lowest filled cell
## (the whole component sits at spill + a few epsilon), its floor the
## lowest original cell. Nested basins merge into one component here --
## the depression TREE hydrology.md describes is not built yet.
func _label_depressions(heights: PackedFloat32Array, min_depth: float) -> void:
	var count := width * height
	depression_id.resize(count)
	depression_id.fill(NO_DEPRESSION)
	depressions.clear()

	for start in count:
		if depression_id[start] != NO_DEPRESSION or not _is_raised(heights, start, min_depth):
			continue
		var id := depressions.size()
		var cell_count := 0
		var spill_elevation := filled[start]
		var spill_index := start
		var floor_elevation := float(heights[start])
		var stack := PackedInt32Array([start])
		depression_id[start] = id
		while stack.size() > 0:
			var index := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cell_count += 1
			if filled[index] < spill_elevation:
				spill_elevation = filled[index]
				spill_index = index
			floor_elevation = minf(floor_elevation, float(heights[index]))
			for direction in 8:
				var neighbor := neighbor_index(index, direction)
				if neighbor < 0 or depression_id[neighbor] != NO_DEPRESSION:
					continue
				if not _is_raised(heights, neighbor, min_depth):
					continue
				depression_id[neighbor] = id
				stack.append(neighbor)
		depressions.append({
			"id": id,
			"cell_count": cell_count,
			"spill_elevation": spill_elevation,
			"spill_index": spill_index,
			"floor_elevation": floor_elevation,
		})


func _is_raised(heights: PackedFloat32Array, index: int, min_depth: float) -> bool:
	return _sea[index] == 0 and filled[index] - float(heights[index]) > min_depth


# --- heap ---

func _heap_less(a: int, b: int) -> bool:
	if _heap_keys[a] != _heap_keys[b]:
		return _heap_keys[a] < _heap_keys[b]
	return _heap_seq[a] < _heap_seq[b]


func _heap_swap(a: int, b: int) -> void:
	var key := _heap_keys[a]
	_heap_keys[a] = _heap_keys[b]
	_heap_keys[b] = key
	var seq := _heap_seq[a]
	_heap_seq[a] = _heap_seq[b]
	_heap_seq[b] = seq
	var item := _heap_items[a]
	_heap_items[a] = _heap_items[b]
	_heap_items[b] = item


func _heap_push(key: float, item: int) -> void:
	if _heap_size == _heap_keys.size():
		_heap_keys.append(key)
		_heap_seq.append(_next_seq)
		_heap_items.append(item)
	else:
		_heap_keys[_heap_size] = key
		_heap_seq[_heap_size] = _next_seq
		_heap_items[_heap_size] = item
	_next_seq += 1
	var position := _heap_size
	_heap_size += 1
	while position > 0:
		@warning_ignore("integer_division")
		var parent := (position - 1) / 2
		if not _heap_less(position, parent):
			break
		_heap_swap(position, parent)
		position = parent


func _heap_pop() -> int:
	var top := _heap_items[0]
	_heap_size -= 1
	if _heap_size == 0:
		return top
	_heap_swap(0, _heap_size)
	var position := 0
	while true:
		var left := 2 * position + 1
		var right := left + 1
		var smallest := position
		if left < _heap_size and _heap_less(left, smallest):
			smallest = left
		if right < _heap_size and _heap_less(right, smallest):
			smallest = right
		if smallest == position:
			break
		_heap_swap(position, smallest)
		position = smallest
	return top
