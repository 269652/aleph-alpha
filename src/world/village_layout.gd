extends RefCounted

## An Anno-style road-frontage village layout (docs/concept/building.md
## "Buildings are entities; interiors are scenes", pillar 5: "Villages are
## laid out, not scattered") -- replaces the old ring
## (SettlementGenerator._house_position/VillageRenderer._fit_house): a
## spine street through the chunk's own middle with a paved PLAZA at its
## centre (the civic plot where the town hall rises over time -- see
## docs/concept/civic_construction.md -- with the well and the stall on
## it) and a gate where the street enters the village; buildings on the
## street's NORTH side with their doors facing SOUTH onto it -- the
## doorstep IS a road cell, which is what makes a plot actually front the
## street rather than merely stand near it -- separated by a real one-tile
## gap. A street that fills up opens a further one south of it at a fixed
## pitch, tied back to the plaza by two side streets, rather than crowding
## or overlapping.
##
## Pure and seeded: `is_buildable`/`is_occupied` are Callables (the real
## ones are EarthChunkManager.is_buildable_terrain_at/a modification_at_
## global-backed check; VillageRenderer supplies them), so this is fully
## testable with a stub predicate and touches no world state itself.
## `building_ids` is placed in order, already CHOSEN by the caller (see
## BuildingCatalog.choose_house_id) -- this module only decides WHERE, the
## same division SettlementGenerator/VillageRenderer already drew for the
## old ring (SettlementGenerator decided who, VillageRenderer decided
## where). A building that fits nowhere on any street is simply absent
## from the result -- the same honest "a villager can be left without a
## house" outcome the old ring's own fallback ladder could still reach,
## not a new failure mode.
##
## skeleton() is the part that depends on nothing but the chunk and its
## seed -- street row, plaza, civic plot, landmarks -- so an older
## village's plaza can be re-derived on reload without persisting anything
## (VillageRenderer._recover_existing_village) and the civic build
## decision can find the hall's reserved site the same way.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Real gap between two adjacent plots on the same street.
const PLOT_GAP_TILES := 1
## Real gap between one street's own row of buildings and the next one
## south of it, on top of the deepest building in the catalog -- the pitch
## between two streets is fixed (STREET_PITCH_TILES) so side streets know
## where the next street row is before anything is placed on it.
const STREET_GAP_TILES := 2
## Deepest catalog footprint (house_large / the town hall, 3) plus the gap:
## the fixed row distance between one street and the next. Pinned by
## test_village_layout.gd against the catalog itself.
const STREET_PITCH_TILES := 3 + STREET_GAP_TILES
## Kept off the chunk's own edge -- a plot flush against the border risks
## its footprint or doorstep spilling into the next chunk once translated
## to global coordinates (the same chunk-edge caution the old ring layout
## already needed -- see VillageRenderer's own "a house must stand
## entirely inside its own chunk" doc comment).
const _EDGE_MARGIN_TILES := 2
## How far a street's own starting x may be seed-jittered within its
## margin, so every village's street doesn't begin at the identical
## column -- real, seeded variety, the same "small jitter, not fully
## random" convention SettlementGenerator's own old ring anchors used.
const _START_JITTER_TILES := 3

## The plaza: PLAZA_WIDTH_TILES wide, centred on the street's middle,
## reaching PLAZA_ROWS_NORTH rows above the street (where the civic plot
## sits, its door on the street) and PLAZA_ROWS_SOUTH rows below it (the
## well and the stall). Wide enough for the town hall (4) plus a paved
## margin either side; the north rows are exactly the hall's depth.
const PLAZA_WIDTH_TILES := 8
const PLAZA_ROWS_NORTH := 3
const PLAZA_ROWS_SOUTH := 2
const CIVIC_BUILDING_ID := "city_hall"
## The first house stands this many cells east of the gate, so no doorstep
## ever lands on the gate cell itself and the entrance reads as an entrance.
const _GATE_CLEARANCE_TILES := 2

## How many consecutive x positions one building may fail at before this
## module gives up on it and moves to the next -- generous (several times
## any real footprint+gap in this catalog) without being "the whole
## street": a building that is structurally impossible everywhere (an
## occupancy pattern no width of its own can ever clear) must not consume
## the ENTIRE remaining street width failing forever, which would leave
## no room left to even TRY any later, possibly perfectly placeable,
## building on the same street.
const _MAX_ATTEMPTS_PER_BUILDING := 12


## The one layout seed per chunk -- the exact formula VillageRenderer used
## to compute inline, moved here so every consumer (renderer, recover path,
## civic build decision) derives the same skeleton for the same chunk.
static func seed_for(chunk_coord: Vector2i) -> int:
	return hash("%d_%d_village_layout" % [chunk_coord.x, chunk_coord.y])


## Everything about a village's shape that depends only on the chunk and
## its seed, before any building is placed: the main street row and its
## x-span, the plaza rectangle, the civic plot (origin/doorstep of the town
## hall's reserved site) and the three landmark cells (well, stall, gate).
## Pure: two calls with the same inputs are equal, so a reload re-derives
## exactly the plaza it laid at founding.
static func skeleton(chunk_size: int, seed_value: int) -> Dictionary:
	var street_y := chunk_size / 2
	var street_x0 := _EDGE_MARGIN_TILES + PixelNoise.range_index(seed_value, 0, 0, _START_JITTER_TILES)
	var street_x1 := chunk_size - _EDGE_MARGIN_TILES - 1
	var plaza_x0 := chunk_size / 2 - PLAZA_WIDTH_TILES / 2
	var plaza := Rect2i(
		plaza_x0, street_y - PLAZA_ROWS_NORTH,
		PLAZA_WIDTH_TILES, PLAZA_ROWS_NORTH + 1 + PLAZA_ROWS_SOUTH
	)
	var civic_footprint := BuildingCatalog.footprint_of(CIVIC_BUILDING_ID)
	# The hall is centred on the plaza's own width, its bottom row directly
	# north of the street so its door (south edge, middle) opens onto it.
	var civic_origin := Vector2i(plaza_x0 + (PLAZA_WIDTH_TILES - civic_footprint.x) / 2, street_y - civic_footprint.y)
	var civic_plot := {
		"origin": civic_origin, "building_id": CIVIC_BUILDING_ID,
		"doorstep": civic_origin + BuildingCatalog.doorstep_of(CIVIC_BUILDING_ID),
	}
	# Well and stall on the plaza's south half, clear of the street row (so
	# they never block the hall's door) and of each other.
	var landmarks := {
		"well": Vector2i(plaza_x0 + 2, street_y + 1),
		"stall": Vector2i(plaza.end.x - 3, street_y + PLAZA_ROWS_SOUTH),
		"gate": Vector2i(street_x0, street_y),
	}
	return {
		"street_y": street_y, "street_x0": street_x0, "street_x1": street_x1,
		"plaza": plaza, "civic_plot": civic_plot, "landmarks": landmarks,
	}


func layout(
	building_ids: Array, chunk_size: int, seed_value: int, is_buildable: Callable, is_occupied: Callable
) -> Dictionary:
	if building_ids.is_empty():
		var no_roads: Array[Vector2i] = []
		return {"plots": [], "road_cells": no_roads, "plaza": Rect2i(), "civic_plot": {}, "landmarks": {}}

	var bones := skeleton(chunk_size, seed_value)
	var street_y: int = bones["street_y"]
	var street_x0: int = bones["street_x0"]
	var street_x1: int = bones["street_x1"]
	var plaza: Rect2i = bones["plaza"]

	var plots: Array = []
	var road_cells: Dictionary = {}  # Vector2i -> true, de-duplicated
	# This village's OWN placements so far -- is_occupied only reflects the
	# world as it stood before this layout call began, so a plot must never
	# be allowed to claim a cell a PRIOR plot in this same layout already
	# took (nor the plaza or a side street, claimed up front below).
	var claimed: Dictionary = {}

	# The plaza and its side streets are reserved FIRST, only when the whole
	# square can actually be paved -- a village whose centre is water or
	# forest gets no plaza (and so no hall), honestly, rather than a square
	# with a lake in it.
	var has_plaza := _every_cell_clear(_rect_cells(plaza), chunk_size, is_buildable, is_occupied)
	var side_street_cells: Array = []
	if has_plaza:
		for cell in _rect_cells(plaza):
			claimed[cell] = true
			road_cells[cell] = true
		var second_street_y := street_y + STREET_PITCH_TILES
		for x in [plaza.position.x, plaza.end.x - 1]:
			for y in range(plaza.end.y, second_street_y + 1):
				var cell := Vector2i(x, y)
				if _cell_clear(cell, chunk_size, is_buildable, is_occupied):
					side_street_cells.append(cell)
					claimed[cell] = true
	else:
		plaza = Rect2i()

	# The main street is paved along its whole buildable length -- a real
	# street, not just the run between two doorsteps.
	for x in range(street_x0, street_x1 + 1):
		var cell := Vector2i(x, street_y)
		if _cell_clear(cell, chunk_size, is_buildable, is_occupied):
			road_cells[cell] = true
			claimed[cell] = true

	var index := 0
	var current_street_y := street_y
	var second_street_got_a_plot := false
	while index < building_ids.size() and current_street_y < chunk_size - _EDGE_MARGIN_TILES:
		var progressed_this_street := false
		var x := street_x0 + _GATE_CLEARANCE_TILES
		var street_doorstep_xs: Array = []
		var attempts_for_current_index := 0
		while x < street_x1 and index < building_ids.size():
			var building_id: String = building_ids[index]
			var footprint := BuildingCatalog.footprint_of(building_id)
			if footprint == Vector2i.ZERO:
				index += 1  # an unknown id -- skip it, never stall the street on a typo
				attempts_for_current_index = 0
				continue
			# Never try to straddle the plaza: a plot whose footprint would
			# reach the square's western margin jumps to its eastern side
			# (one gap clear), so the square itself never burns attempts.
			if has_plaza and current_street_y == street_y:
				var plaza_west_margin := plaza.position.x - PLOT_GAP_TILES
				var plaza_east_resume := plaza.end.x + PLOT_GAP_TILES
				if x < plaza_east_resume and x + footprint.x > plaza_west_margin:
					x = plaza_east_resume
					continue
			var origin := Vector2i(x, current_street_y - footprint.y)
			if _fits(building_id, origin, chunk_size, is_buildable, is_occupied, claimed):
				var doorstep: Vector2i = origin + BuildingCatalog.doorstep_of(building_id)
				plots.append({
					"origin": origin, "building_id": building_id, "building_index": index,
					"facing": Vector2i(0, 1), "doorstep": doorstep,
				})
				for cell in BuildingCatalog.footprint_cells(building_id, origin):
					claimed[cell] = true
				road_cells[doorstep] = true
				street_doorstep_xs.append(doorstep.x)
				x += footprint.x + PLOT_GAP_TILES
				index += 1
				progressed_this_street = true
				attempts_for_current_index = 0
				if current_street_y != street_y:
					second_street_got_a_plot = true
			else:
				x += 1
				attempts_for_current_index += 1
				if attempts_for_current_index >= _MAX_ATTEMPTS_PER_BUILDING:
					# Given up on this one for GOOD (see _MAX_ATTEMPTS_PER_
					# BUILDING's own doc comment: the point is only that it
					# must not consume an entire street's width failing --
					# never retried on a later street either, so the cost of
					# one hopeless building stays bounded at exactly this
					# many wasted attempts, not "one street per hopeless
					# building" as more streets open for the ones behind it).
					index += 1
					attempts_for_current_index = 0
		# A further street connects its own frontage -- the span BETWEEN its
		# own placed doorsteps (the main street is paved end to end above).
		if current_street_y != street_y and street_doorstep_xs.size() > 1:
			street_doorstep_xs.sort()
			for rx in range(street_doorstep_xs[0], street_doorstep_xs[street_doorstep_xs.size() - 1] + 1):
				var cell := Vector2i(rx, current_street_y)
				if _cell_clear(cell, chunk_size, is_buildable, is_occupied) and not claimed.has(cell):
					road_cells[cell] = true
		if not progressed_this_street:
			break  # this street placed nothing at all -- a further one south won't fare any better
		current_street_y += STREET_PITCH_TILES

	# Side streets only exist to reach a second street -- a village that fit
	# on its main street keeps the ground south of the plaza open.
	if second_street_got_a_plot:
		for cell in side_street_cells:
			road_cells[cell] = true

	var road_array: Array[Vector2i] = []
	road_array.assign(road_cells.keys())
	return {
		"plots": plots, "road_cells": road_array, "plaza": plaza,
		"civic_plot": bones["civic_plot"] if has_plaza else {},
		"landmarks": bones["landmarks"] if has_plaza else {},
	}


## Every footprint cell AND the doorstep (the road cell the door opens
## onto -- a door opening onto unbuildable ground is a house nobody can
## reach, the exact bug the old ring layout's own probe found) must be
## inside the chunk, buildable, not already occupied by the WORLD, and not
## already claimed by an earlier plot (or the plaza/streets) in this SAME
## layout call. The doorstep may already be a claimed ROAD cell -- that is
## the whole point of fronting the street -- so it is checked against the
## world only, never against `claimed`.
func _fits(
	building_id: String, origin: Vector2i, chunk_size: int,
	is_buildable: Callable, is_occupied: Callable, claimed: Dictionary
) -> bool:
	for cell in BuildingCatalog.footprint_cells(building_id, origin):
		if claimed.has(cell) or not _cell_clear(cell, chunk_size, is_buildable, is_occupied):
			return false
	var doorstep: Vector2i = origin + BuildingCatalog.doorstep_of(building_id)
	return _cell_clear(doorstep, chunk_size, is_buildable, is_occupied)


static func _cell_clear(cell: Vector2i, chunk_size: int, is_buildable: Callable, is_occupied: Callable) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= chunk_size or cell.y >= chunk_size:
		return false
	if not is_buildable.call(cell):
		return false
	return not is_occupied.call(cell)


static func _every_cell_clear(cells: Array, chunk_size: int, is_buildable: Callable, is_occupied: Callable) -> bool:
	for cell in cells:
		if not _cell_clear(cell, chunk_size, is_buildable, is_occupied):
			return false
	return true


static func _rect_cells(rect: Rect2i) -> Array:
	var out: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out
