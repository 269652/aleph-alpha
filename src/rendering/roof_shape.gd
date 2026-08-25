extends RefCounted

## Turns a building's flat SET of roof cells into a pitched roof (see
## docs/concept/building.md "How a house reads from above").
##
## Reported directly: village houses "don't resemble houses at all... just
## some randomly placed stones and wood panels". A roof drawn as one flat
## shingle texture tiled across a rectangle is, seen from above, a brick
## patio -- what reads as a ROOF is the PITCH: a ridge along the top with
## two slopes falling away from it, one catching the light and one in
## shade. That is per-cell CONTEXT rather than per-cell art, so it is
## derived here the same way TerrainRenderer.dominant_blend_for/
## corner_direction_for derive biome blends from neighbours: a pure
## classifier over the cell set, feeding a bounded atlas family.
##
## Pure and static throughout -- no atlas, no Image, no TileMapLayer -- so
## the geometry is testable without baking anything (a full atlas bake is
## minutes; see test_terrain_renderer.gd).

## Which of a cell's four cardinal sides face OUT of its own building.
##
## The reported "randomly placed panels" look came from every piece tile
## drawing its own bright/dark rim, so twenty wall tiles in a ring drew
## twenty individually-outlined boxes -- an internal grid over the whole
## building. A rim belongs on the STRUCTURE's outer boundary only, which is
## exactly this mask: a bit is set only where the neighbouring cell is not
## part of the same roof.
const EDGE_NORTH := 1
const EDGE_EAST := 2
const EDGE_SOUTH := 4
const EDGE_WEST := 8

## How many brightness steps one slope is quantized into, and the total
## across both slopes (lit occupies [0, SHADE_BANDS_PER_SLOPE), shaded the
## rest). Quantized rather than a continuous ramp so this stays a bounded
## atlas family like every other one in TerrainRenderer -- 4 steps is
## enough for a pitch to read across the 2-4 tile slopes this project's
## house footprints actually produce (see HouseBlueprint's catalog), and
## few enough that the family stays small.
const SHADE_BANDS_PER_SLOPE := 4
const TOTAL_SHADE_BANDS := SHADE_BANDS_PER_SLOPE * 2

## Lower band index means brighter, so the lit slope's own darkest step is
## still brighter than the shaded slope's brightest -- see classify_all.
const FIRST_SHADED_BAND := SHADE_BANDS_PER_SLOPE

const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

## The 8 cells surrounding one cell -- diagonals included, unlike the
## cardinal-only _NEIGHBOR_OFFSETS, because a room's corner walls touch it
## only diagonally (see revealed_cells).
const _RING_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]

const _NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
const _NEIGHBOR_EDGE_BITS: Array[int] = [EDGE_NORTH, EDGE_EAST, EDGE_SOUTH, EDGE_WEST]


## Whether this cell set's ridge runs left-right (true) rather than up-down.
##
## Real rafters span the SHORTER direction and lean against a ridge beam
## running along the longer one, so a wide house gets a horizontal ridge
## and a tall one a vertical ridge. A perfect square has no longer axis and
## deliberately falls to horizontal rather than picking arbitrarily -- a
## stable answer matters more than a "correct" one that could flicker
## between two equally-valid orientations on a repaint.
static func ridge_is_horizontal(cells: Dictionary) -> bool:
	if cells.is_empty():
		return true
	var bounds := _bounds(cells.keys())
	var extent: Vector2i = bounds.max - bounds.min
	return extent.x >= extent.y


## Every cell's {"band": int, "mask": int}, keyed by cell.
##
## `cells` is a whole CHUNK's roof cells (see EarthChunkManager's
## Chunk.roof_modifications), which routinely holds several unrelated
## houses at once -- so the pitch is computed per orthogonally-connected
## COMPONENT, not over the whole set's bounding box. Sharing one bounding
## box across two neighbouring houses would run a single ridge across the
## gap between them, tilting both roofs the wrong way.
##
## The edge mask, unlike the band, is computed against the whole set: two
## roof cells that touch orthogonally ARE one building by definition (same
## 4-connectivity the component grouping itself uses), so there is nothing
## for a per-component pass to answer differently.
static func classify_all(cells: Dictionary) -> Dictionary:
	var classified := {}
	for component in _components(cells):
		var bounds := _bounds(component)
		var lowest: Vector2i = bounds.min
		var highest: Vector2i = bounds.max
		var extent: Vector2i = highest - lowest
		var horizontal: bool = extent.x >= extent.y
		# The pitch runs ACROSS the ridge: a horizontal ridge is climbed by
		# moving in y, a vertical one by moving in x.
		var span_min: int = lowest.y if horizontal else lowest.x
		var span_max: int = highest.y if horizontal else highest.x
		var ridge_center := (float(span_min) + float(span_max)) * 0.5
		for cell in component:
			var coord: int = cell.y if horizontal else cell.x
			var offset := float(coord) - ridge_center
			# Counted in TILES from the ridge, not as a fraction of the roof's
			# own depth. A real pitched roof is two FLAT planes: brightness is
			# a property of which slope you are on, with a local darkening at
			# the eave, not something that stretches to fit the building.
			# Normalizing instead made a shallow roof use only the extreme
			# bands -- a 3x3 hut, whose two roof rows are both maximally far
			# from their own ridge, came out uniformly dark with no lit side
			# at all -- while a deep roof spread the ramp into visible stripes.
			# floor() rather than round() so the half-tile offsets a
			# two-row pitch produces (+-0.5) land on the ridge band instead of
			# one step down it.
			var step := clampi(floori(absf(offset)), 0, SHADE_BANDS_PER_SLOPE - 1)
			# Light comes from the upper-left across this whole project (see
			# ProceduralBuildingPieceSprite's rim convention and docs/art/
			# ai_sprite_prompts.md's shared style preamble), so the slope
			# facing up/left catches it and the opposite one is in shade.
			var band := step if offset <= 0.0 else FIRST_SHADED_BAND + step
			classified[cell] = {"band": band, "mask": _edge_mask(cells, cell)}
	return classified


## Which sides of `cell` border something that is not roof at all.
static func _edge_mask(cells: Dictionary, cell: Vector2i) -> int:
	var mask := 0
	for i in _NEIGHBOR_OFFSETS.size():
		if not cells.has(cell + _NEIGHBOR_OFFSETS[i]):
			mask |= _NEIGHBOR_EDGE_BITS[i]
	return mask


## The cell set split into orthogonally-connected groups -- one per
## building. Plain iterative flood fill (no recursion: a large chunk's roof
## set can be thousands of cells), mirroring RoomDetector's own
## 4-connectivity so "one building" means the same thing in both places.
static func _components(cells: Dictionary) -> Array:
	var seen := {}
	var components: Array = []
	for start in cells:
		if seen.has(start):
			continue
		var component: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [start]
		seen[start] = true
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			component.append(cell)
			for offset in _NEIGHBOR_OFFSETS:
				var neighbor: Vector2i = cell + offset
				if cells.has(neighbor) and not seen.has(neighbor):
					seen[neighbor] = true
					frontier.append(neighbor)
		components.append(component)
	return components


## Inclusive min/max corners of `cell_list`.
static func _bounds(cell_list: Array) -> Dictionary:
	var minimum: Vector2i = cell_list[0]
	var maximum: Vector2i = cell_list[0]
	for cell in cell_list:
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	return {"min": minimum, "max": maximum}


## The cells whose roof must lift when the player steps into `room_cells`.
##
## Roofs cover a building's whole footprint, WALLS INCLUDED (see
## docs/concept/building.md "How a house reads from above" -- roofing only
## the interior is what made a house read inside-out from outside). So
## hiding just the room's own floor cells would leave the roof still
## capping the walls around it: standing inside, the player would see a
## floor bounded by roof, never the room's own walls or the windows in
## them. Revealing the enclosing ring as well makes stepping inside a real
## cutaway -- floor, walls and windows, with the roof lifted off exactly
## the room being occupied and left intact everywhere else.
##
## `structure` is the chunk's modification map (cell -> piece id). Only
## cells holding a real BuildingPiece are added, so a campfire, a worn
## earth path, or a neighbouring building's roof can never be revealed by
## standing next to it. Diagonals are included so a room's CORNER cells --
## which touch the room only diagonally -- come off with the rest of the
## ring instead of being left as four stray roof pixels at the corners.
static func revealed_cells(room_cells: Array, structure: Dictionary) -> Dictionary:
	var revealed := {}
	for cell in room_cells:
		revealed[cell] = true
	for cell in room_cells:
		for offset in _RING_OFFSETS:
			var neighbor: Vector2i = cell + offset
			if revealed.has(neighbor):
				continue
			if BuildingPiece.has_piece(structure.get(neighbor, "")):
				revealed[neighbor] = true
	return revealed
