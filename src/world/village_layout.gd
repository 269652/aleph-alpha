extends RefCounted

## An Anno-style road-frontage village layout (docs/concept/building.md
## "Buildings are entities; interiors are scenes", pillar 5: "Villages are
## laid out, not scattered") -- replaces the old ring
## (SettlementGenerator._house_position/VillageRenderer._fit_house): a
## spine street through the chunk's own middle, buildings on its NORTH
## side with their doors facing SOUTH onto it -- the doorstep IS a road
## cell, which is what makes a plot actually front the street rather than
## merely stand near it -- separated by a real one-tile gap. A street that
## fills up opens a further one south of it, rather than crowding or
## overlapping.
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

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Real gap between two adjacent plots on the same street.
const PLOT_GAP_TILES := 1
## Real gap between one street's own row of buildings and the next one
## south of it, on top of the deepest building placed on the first.
const STREET_GAP_TILES := 2
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

## How many consecutive x positions one building may fail at before this
## module gives up on it and moves to the next -- generous (several times
## any real footprint+gap in this catalog) without being "the whole
## street": a building that is structurally impossible everywhere (an
## occupancy pattern no width of its own can ever clear) must not consume
## the ENTIRE remaining street width failing forever, which would leave
## no room left to even TRY any later, possibly perfectly placeable,
## building on the same street.
const _MAX_ATTEMPTS_PER_BUILDING := 12


func layout(
	building_ids: Array, chunk_size: int, seed_value: int, is_buildable: Callable, is_occupied: Callable
) -> Dictionary:
	var plots: Array = []
	var road_cells: Dictionary = {}  # Vector2i -> true, de-duplicated
	# This village's OWN placements so far -- is_occupied only reflects the
	# world as it stood before this layout call began, so a plot must never
	# be allowed to claim a cell a PRIOR plot in this same layout already
	# took.
	var claimed: Dictionary = {}

	var start_jitter := PixelNoise.range_index(seed_value, 0, 0, _START_JITTER_TILES)
	var index := 0
	var street_y := chunk_size / 2

	while index < building_ids.size() and street_y < chunk_size - _EDGE_MARGIN_TILES:
		var progressed_this_street := false
		var x := _EDGE_MARGIN_TILES + start_jitter
		var street_end := chunk_size - _EDGE_MARGIN_TILES
		var street_doorstep_xs: Array = []
		var deepest_footprint_y := 1
		var attempts_for_current_index := 0
		while x < street_end and index < building_ids.size():
			var building_id: String = building_ids[index]
			var footprint := BuildingCatalog.footprint_of(building_id)
			if footprint == Vector2i.ZERO:
				index += 1  # an unknown id -- skip it, never stall the street on a typo
				attempts_for_current_index = 0
				continue
			var origin := Vector2i(x, street_y - footprint.y)
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
				deepest_footprint_y = maxi(deepest_footprint_y, footprint.y)
				x += footprint.x + PLOT_GAP_TILES
				index += 1
				progressed_this_street = true
				attempts_for_current_index = 0
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
		# Connects this street's own frontage -- the span BETWEEN its own
		# placed doorsteps, not the whole street width past the last house.
		if street_doorstep_xs.size() > 1:
			street_doorstep_xs.sort()
			for rx in range(street_doorstep_xs[0], street_doorstep_xs[street_doorstep_xs.size() - 1] + 1):
				road_cells[Vector2i(rx, street_y)] = true
		if not progressed_this_street:
			break  # this street placed nothing at all -- a further one south won't fare any better
		street_y += deepest_footprint_y + STREET_GAP_TILES

	var road_array: Array[Vector2i] = []
	road_array.assign(road_cells.keys())
	return {"plots": plots, "road_cells": road_array}


## Every footprint cell AND the doorstep (the road cell the door opens
## onto -- a door opening onto unbuildable ground is a house nobody can
## reach, the exact bug the old ring layout's own probe found) must be
## inside the chunk, buildable, not already occupied by the WORLD, and not
## already claimed by an earlier plot in this SAME layout call.
func _fits(
	building_id: String, origin: Vector2i, chunk_size: int,
	is_buildable: Callable, is_occupied: Callable, claimed: Dictionary
) -> bool:
	var required: Array = BuildingCatalog.footprint_cells(building_id, origin)
	required.append(origin + BuildingCatalog.doorstep_of(building_id))
	for cell in required:
		if cell.x < 0 or cell.y < 0 or cell.x >= chunk_size or cell.y >= chunk_size:
			return false
		if claimed.has(cell):
			return false
		if not is_buildable.call(cell):
			return false
		if is_occupied.call(cell):
			return false
	return true
