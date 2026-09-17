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


## Where the square actually stands: centred on the street's middle by
## design, and slid along the street -- west and east alternately, nearest
## first -- to the first column where the WHOLE square is dry when it
## isn't. Reported in play, twice, with a screenshot: a riverside village
## with no square and no hall, because the square was pinned to the chunk's
## exact middle and a river ran through it. The square is 8 tiles wide in a
## 32-tile chunk; there is real room beside the water, and standing it
## there is more honest than standing nowhere.
##
## `is_dry` is deliberately a WATER test, not the general buildable/
## occupied pair every other function here takes. Every consumer of this
## square (the founding layout, the reload's re-paving, the civic plot, the
## growth ladder's own next plot) has to derive the SAME rectangle with
## nothing persisted, so the input must be the one thing that never changes
## once the world is seeded: trees get felled and ground gets built on,
## rivers do not move. An invalid/omitted Callable keeps the designed
## centre, which is also what happens when nowhere is dry -- layout() then
## finds the square unclear and honestly lays none.
static func plaza_x0_for(
	chunk_size: int, street_y: int, street_x0: int, street_x1: int, is_dry: Callable
) -> int:
	var centred: int = chunk_size / 2 - PLAZA_WIDTH_TILES / 2
	if not is_dry.is_valid():
		return centred
	# The chunk's own edge margin, and nothing else. This used to also
	# take street_x0 -- the spine's decorative SEED JITTER
	# (_EDGE_MARGIN_TILES + 0..2, so villages don't all start at the
	# identical column) -- and on chunk (661,139) near lat 49.8 lon 10.6
	# that vetoed the only dry square placements this village had, at x=1
	# and x=2, because its jitter happened to start the street at x=3.
	# Reported three times as "no plaza, no city hall". A decorative jitter
	# is not a reason a village cannot have a market square; skeleton()
	# starts the spine at whichever of the two is further west instead, so
	# the street always reaches its own square.
	var westmost: int = _EDGE_MARGIN_TILES
	var eastmost: int = mini(chunk_size - _EDGE_MARGIN_TILES, street_x1 + 1) - PLAZA_WIDTH_TILES
	for offset in range(0, chunk_size):
		for candidate in ([centred] if offset == 0 else [centred - offset, centred + offset]):
			if candidate < westmost or candidate > eastmost:
				continue
			if not _plaza_is_dry(candidate, street_y, is_dry):
				continue
			# This used to also demand a run wide enough for the square PLUS
			# a house beside it, on the reasoning that a square swallowing
			# its whole street leaves the village nowhere to live. Measured
			# on chunk (661,139) near lat 49.8 lon 10.6 -- reported three
			# times as "no plaza, no city hall" -- that trade is the wrong
			# way round: the dry pocket there is about nine tiles, the
			# square fits on it, and the rule made the village take three
			# houses and no square instead. A house does not have to stand
			# on the spine; a village that fills its spine opens a further
			# street and reaches it by the gate lane. A square can only ever
			# straddle a street.
			return candidate
	return centred


## Whether every cell of the square standing at `plaza_x0` is dry -- the
## same rectangle skeleton() builds (PLAZA_ROWS_NORTH above the street row
## through PLAZA_ROWS_SOUTH below it), asked of nothing but `is_dry`.
static func _plaza_is_dry(plaza_x0: int, street_y: int, is_dry: Callable) -> bool:
	for y in range(street_y - PLAZA_ROWS_NORTH, street_y + PLAZA_ROWS_SOUTH + 1):
		for x in range(plaza_x0, plaza_x0 + PLAZA_WIDTH_TILES):
			if not is_dry.call(Vector2i(x, y)):
				return false
	return true


## Everything about a village's shape that depends only on the chunk and
## its seed, before any building is placed: the main street row and its
## x-span, the plaza rectangle, the civic plot (origin/doorstep of the town
## hall's reserved site) and the three landmark cells (well, stall, gate).
## Pure: two calls with the same inputs are equal, so a reload re-derives
## exactly the plaza it laid at founding.
##
## `is_dry` (optional) is a WATER test only -- see plaza_x0_for. Omit it
## and the square stands at the chunk's exact middle, exactly as it always
## did; pass it and the square slides clear of water rather than not
## existing. Every caller that can answer it MUST pass the same one, or
## two of them derive two different squares for the same village.
static func skeleton(chunk_size: int, seed_value: int, is_dry := Callable()) -> Dictionary:
	var street_y := chunk_size / 2
	var street_x0 := _EDGE_MARGIN_TILES + PixelNoise.range_index(seed_value, 0, 0, _START_JITTER_TILES)
	var street_x1 := chunk_size - _EDGE_MARGIN_TILES - 1
	var plaza_x0 := plaza_x0_for(chunk_size, street_y, street_x0, street_x1, is_dry)
	# A square sited west of where the jitter put the spine's start pulls
	# that start west with it: a square the street stops short of is a
	# square nobody walks to.
	street_x0 = mini(street_x0, plaza_x0)
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

	# VillageRenderer's own is_buildable IS the water test (see
	# VillageRenderer._is_buildable_local: a village fells the trees it
	# needs, so water is the only ground it refuses), which is exactly what
	# the square's siting wants -- see plaza_x0_for.
	var bones := skeleton(chunk_size, seed_value, is_buildable)
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

	# The main street is paved along its whole buildable length -- but only
	# along ONE unbroken length of it. Reported in play: "Not all houses
	# are connected by streets". Ground that is fine on both sides of a
	# river and impassable across it used to be paved on both sides, which
	# is two villages with two islands of paving, and houses on the far
	# side whose doors opened onto pavement nobody could walk to from the
	# square. A village builds on the side it can actually reach.
	var run := _chosen_street_run(
		street_y, street_x0, street_x1, chunk_size, is_buildable, is_occupied,
		(plaza.position.x + plaza.size.x / 2) if has_plaza else -1
	)
	if run.y < run.x:
		# Not one buildable cell of street anywhere. Nothing is paved and
		# nothing is placed -- VillageRenderer reads an empty plot list as
		# "this is not a village" and founds nothing here.
		var no_street: Array[Vector2i] = []
		return {"plots": [], "road_cells": no_street, "plaza": Rect2i(), "civic_plot": {}, "landmarks": {}}
	# The gate clearance keeps a village off the CHUNK's edge, so it is
	# measured from the spine the skeleton drew, not from wherever this run
	# happens to start -- applying it again to a short run would eat the
	# whole run and leave a street with no houses on it.
	var spine_x0 := street_x0
	street_x0 = run.x
	street_x1 = run.y
	for x in range(street_x0, street_x1 + 1):
		var cell := Vector2i(x, street_y)
		if _cell_clear(cell, chunk_size, is_buildable, is_occupied):
			road_cells[cell] = true
			claimed[cell] = true

	var index := 0
	var current_street_y := street_y
	var second_street_got_a_plot := false
	# Cells of the gate lane reaching the street about to be laid, held
	# back until that street is actually built on -- the same "only pave a
	# tie-back that ties something back" rule side_street_cells follows.
	var pending_lane_cells: Array = []
	while index < building_ids.size() and current_street_y < chunk_size - _EDGE_MARGIN_TILES:
		var progressed_this_street := false
		var x := maxi(spine_x0 + _GATE_CLEARANCE_TILES, street_x0)
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
		if current_street_y != street_y and not street_doorstep_xs.is_empty():
			street_doorstep_xs.sort()
			# Reach both side streets, not merely the span between this
			# street's own doorsteps: the side streets beside the plaza are
			# the ONLY way a further street joins the spine, so a further
			# street that stops short of them is a row of houses nobody can
			# walk to (reported in play: "Not all houses are connected by
			# streets").
			# Whatever ties this street back to the spine -- the two side
			# streets beside the square, or the gate lane when there is no
			# square -- has to be REACHED by this street's own paving, or
			# the tie-back ends one cell short of the thing it ties.
			var tie_x0: int = mini(plaza.position.x, street_x0) if has_plaza else street_x0
			var tie_x1: int = (plaza.end.x - 1) if has_plaza else street_x0
			var from_x: int = mini(street_doorstep_xs[0], tie_x0)
			var to_x: int = maxi(street_doorstep_xs[street_doorstep_xs.size() - 1], tie_x1)
			for rx in range(from_x, to_x + 1):
				var cell := Vector2i(rx, current_street_y)
				if _cell_clear(cell, chunk_size, is_buildable, is_occupied) and not claimed.has(cell):
					road_cells[cell] = true
			for cell in pending_lane_cells:
				road_cells[cell] = true
			pending_lane_cells.clear()
		if not progressed_this_street:
			# A spine whose whole run is taken by the SQUARE placed nothing
			# for that reason, not because the village has nowhere to live:
			# its houses belong on the next street, reached by the gate lane
			# below. Measured on chunk (661,139) near lat 49.8 lon 10.6,
			# whose dry pocket is about nine tiles -- just the square and no
			# more -- where breaking here left a village with a market
			# square and not one house.
			#
			# Bounded, and deliberately: only the spine gets this, and only
			# while nothing at all has been placed. A further street that
			# places nothing still ends the village, so a chunk is never
			# walked to the bottom placing nothing.
			var blocked_by_the_square: bool = (
				has_plaza and current_street_y == street_y and plots.is_empty()
			)
			if not blocked_by_the_square:
				break
		var next_street_y := current_street_y + STREET_PITCH_TILES
		# EVERY further street is tied back by the gate lane, square or no
		# square. Without a square there is nothing else to hang one on --
		# reported in play, twice: a riverside village stuck at three
		# houses with five villagers, because a drowned square used to end
		# its growth outright rather than merely cost it a square. WITH a
		# square it is still needed past the second street, because the
		# side streets beside the square only reach that far: a third
		# street hung on nothing was a real disconnected row (caught by
		# test_a_river_across_the_street_never_leaves_a_house_stranded the
		# moment a village grew that big). The lane is claimed BEFORE
		# anything is placed on the street it reaches, so no plot can take
		# it.
		var lane := _gate_lane_cells(
			street_x0, current_street_y, next_street_y, chunk_size, is_buildable, is_occupied
		)
		if lane.is_empty():
			# Nothing clear to walk down: this village stays where it is
			# rather than grow a row nobody can reach.
			break
		for cell in lane:
			claimed[cell] = true
		pending_lane_cells.append_array(lane)
		current_street_y = next_street_y

	# Side streets only exist to reach a second street -- a village that fit
	# on its main street keeps the ground south of the plaza open.
	if second_street_got_a_plot:
		for cell in side_street_cells:
			road_cells[cell] = true

	var road_array: Array[Vector2i] = []
	road_array.assign(road_cells.keys())
	# The gate marks where the street begins, so it moves with it when the
	# street is a shorter run than the skeleton drew.
	var landmarks: Dictionary = bones["landmarks"] if has_plaza else {}
	if landmarks.has("gate"):
		landmarks = landmarks.duplicate()
		landmarks["gate"] = Vector2i(street_x0, street_y)
	return {
		"plots": plots, "road_cells": road_array, "plaza": plaza,
		"civic_plot": bones["civic_plot"] if has_plaza else {},
		"landmarks": landmarks,
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


# -- the industry plot: a sawmill at the forest ----------------------------
#
# docs/concept/village_growth.md mechanism 1. A sawmill stood at the timber,
# not on the village square, and a real track was laid to it -- the track is
# not decoration, it is what made the outlying works part of the village.
# Everything below is the same pure, seeded, predicate-driven shape the rest
# of this module keeps: no world state is touched, `is_forest` joins
# `is_buildable`/`is_occupied` as a third caller-supplied Callable (the real
# one is EarthChunkManager's own biome query).

## How far from the works' own footprint real forest must stand for the
## site to count as "at the timber". Two tiles: close enough that the log
## deck genuinely backs onto the trees, loose enough that the mill is not
## required to share a cell boundary with a biome edge that moves.
const INDUSTRY_FOREST_REACH_TILES := 2
## How far (Chebyshev, from the plaza's own centre) the works must stand to
## read as outlying rather than as one more plot on the square. Larger than
## the plaza's own half-width plus a street pitch, so a mill can never turn
## up in the middle of the village.
const INDUSTRY_MIN_PLAZA_DISTANCE_TILES := PLAZA_WIDTH_TILES / 2 + STREET_PITCH_TILES
## Kept off the chunk edge for the same reason every other plot is (see
## _EDGE_MARGIN_TILES) -- the spur needs room to turn, so one tile more.
const _INDUSTRY_EDGE_MARGIN_TILES := _EDGE_MARGIN_TILES + 1


## Where this village's `building_id` works stand, and the road spur that
## joins them to the main street: `{origin, building_id, doorstep,
## road_spur}`, or `{}` when no site qualifies.
##
## A site qualifies when its whole footprint and doorstep are inside the
## chunk, buildable, unoccupied and NOT themselves forest; real forest
## stands within INDUSTRY_FOREST_REACH_TILES of the footprint; the origin
## is at least INDUSTRY_MIN_PLAZA_DISTANCE_TILES from the plaza's centre;
## and -- the part that is not negotiable -- a real contiguous spur can
## actually be laid from the doorstep back to the main street. A mill the
## village cannot walk to is not a mill, so an unreachable site is refused
## outright rather than placed and left stranded.
##
## Of every qualifying site the NEAREST to the plaza wins (ties broken by
## y then x, deterministic like everything else here): the works go as
## close to the village as the timber allows, which is exactly how a real
## village sited its mill -- at the resource, but no further out than it
## had to be.
static func industry_plot(
	building_id: String, chunk_size: int, seed_value: int,
	is_buildable: Callable, is_forest: Callable, is_occupied: Callable,
	is_dry := Callable()
) -> Dictionary:
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO:
		return {}

	# `is_dry` only when the caller's own is_buildable is NOT the water
	# test -- the growth ladder's refuses forest too, and a square sited
	# against that would not be the square the village was founded with.
	var bones := skeleton(chunk_size, seed_value, is_dry if is_dry.is_valid() else is_buildable)
	var plaza: Rect2i = bones["plaza"]
	var plaza_centre: Vector2i = plaza.position + plaza.size / 2

	var qualifies := func(origin: Vector2i) -> bool:
		return _industry_site_qualifies(
			building_id, origin, chunk_size, is_buildable, is_forest, is_occupied
		)
	return _sited_plot(building_id, chunk_size, bones, is_buildable, is_occupied, qualifies)


## A plot on the village's OUTSKIRTS: anywhere clear in the chunk, clear of
## the square, with a real road spur back to the street -- the same siting
## the sawmill already gets, offered to any caller with its own condition
## about what makes a site good.
##
## Reported in play as "no farmers", and measured: on a village wedged
## against a river (chunk (661,139) near lat 49.8 lon 10.6) next_street_plot
## returns nothing at all for a 3x2 farmhouse, while SIXTY origins elsewhere
## in the same chunk fit one, every one with a full field ring. A farmstead
## does not need street frontage the way a house does -- it needs open
## ground and a path home, which is exactly what this gives it.
##
## `accepts_origin` is the caller's own extra condition (a farmhouse asks
## for room for its field); omitted, any clear site qualifies.
static func outskirt_plot(
	building_id: String, chunk_size: int, seed_value: int,
	is_buildable: Callable, is_occupied: Callable,
	accepts_origin := Callable(), is_dry := Callable()
) -> Dictionary:
	if BuildingCatalog.footprint_of(building_id) == Vector2i.ZERO:
		return {}
	var bones := skeleton(chunk_size, seed_value, is_dry if is_dry.is_valid() else is_buildable)
	var qualifies := func(origin: Vector2i) -> bool:
		for cell in (
			BuildingCatalog.footprint_cells(building_id, origin)
			+ [origin + BuildingCatalog.doorstep_of(building_id)]
		):
			if not _cell_clear(cell, chunk_size, is_buildable, is_occupied):
				return false
		return not accepts_origin.is_valid() or accepts_origin.call(origin)
	return _sited_plot(building_id, chunk_size, bones, is_buildable, is_occupied, qualifies)


## The scan both siting rules share: every origin inside the chunk's own
## margin and clear of the square, that `qualifies` accepts and that can
## really be reached by a road spur -- the NEAREST to the square winning
## (ties by y then x, deterministic like everything else here). The works,
## or the farmstead, goes as close to the village as its own condition
## allows, which is exactly how a real one was sited.
static func _sited_plot(
	building_id: String, chunk_size: int, bones: Dictionary,
	is_buildable: Callable, is_occupied: Callable, qualifies: Callable
) -> Dictionary:
	var footprint := BuildingCatalog.footprint_of(building_id)
	var plaza: Rect2i = bones["plaza"]
	var plaza_centre: Vector2i = plaza.position + plaza.size / 2
	var best: Dictionary = {}
	var best_key: Array = []
	var limit := chunk_size - _INDUSTRY_EDGE_MARGIN_TILES
	for y in range(_INDUSTRY_EDGE_MARGIN_TILES, limit):
		for x in range(_INDUSTRY_EDGE_MARGIN_TILES, limit):
			var origin := Vector2i(x, y)
			var offset: Vector2i = origin - plaza_centre
			if maxi(absi(offset.x), absi(offset.y)) < INDUSTRY_MIN_PLAZA_DISTANCE_TILES:
				continue
			if not qualifies.call(origin):
				continue
			var doorstep: Vector2i = origin + BuildingCatalog.doorstep_of(building_id)
			var spur = _industry_spur(
				origin, footprint, doorstep, bones, chunk_size, is_buildable, is_occupied
			)
			if spur == null:
				continue
			var key: Array = [offset.x * offset.x + offset.y * offset.y, origin.y, origin.x]
			if best.is_empty() or key < best_key:
				best_key = key
				best = {
					"origin": origin, "building_id": building_id,
					"doorstep": doorstep, "road_spur": spur,
				}
	return best


## Footprint + doorstep inside the chunk, buildable, unoccupied and not
## forest, with real forest within reach of the footprint. The "not forest"
## check is explicit rather than left to `is_buildable`: the two predicates
## are independent by contract (a test may stub either), and a works
## standing IN the wood it cuts is exactly what this is here to prevent.
static func _industry_site_qualifies(
	building_id: String, origin: Vector2i, chunk_size: int,
	is_buildable: Callable, is_forest: Callable, is_occupied: Callable
) -> bool:
	var cells: Array = BuildingCatalog.footprint_cells(building_id, origin)
	var doorstep: Vector2i = origin + BuildingCatalog.doorstep_of(building_id)
	for cell in cells + [doorstep]:
		if not _cell_clear(cell, chunk_size, is_buildable, is_occupied) or is_forest.call(cell):
			return false
	for cell in cells:
		for dy in range(-INDUSTRY_FOREST_REACH_TILES, INDUSTRY_FOREST_REACH_TILES + 1):
			for dx in range(-INDUSTRY_FOREST_REACH_TILES, INDUSTRY_FOREST_REACH_TILES + 1):
				if is_forest.call(cell + Vector2i(dx, dy)):
					return true
	return false


## The spur: an L from the doorstep to the main street -- along the
## doorstep's own row to a column, then along that column to the street.
## `null` when no column works.
##
## Three columns are tried, in order: the doorstep's own (a straight run,
## the ordinary case for works standing north of the street), then just
## east and just west of the footprint. Those two exist because a works
## standing SOUTH of the street has its own building sitting between its
## south-facing door and the street -- the leg has to route around it, and
## a spur laid through the mill it serves would be no spur at all.
##
## The street row itself is deliberately NOT part of the spur: the main
## street is already paved end to end by layout() (and re-paved on every
## reload), so the spur's job is only to reach it.
static func _industry_spur(
	origin: Vector2i, footprint: Vector2i, doorstep: Vector2i, bones: Dictionary,
	chunk_size: int, is_buildable: Callable, is_occupied: Callable
):
	var street_y: int = bones["street_y"]
	var street_x0: int = bones["street_x0"]
	var street_x1: int = bones["street_x1"]
	var footprint_cells := {}
	for y in footprint.y:
		for x in footprint.x:
			footprint_cells[origin + Vector2i(x, y)] = true

	for column in [doorstep.x, origin.x + footprint.x, origin.x - 1]:
		if column < street_x0 or column > street_x1:
			continue
		var cells = _spur_cells(doorstep, column, street_y, footprint_cells, chunk_size, is_buildable, is_occupied)
		if cells != null:
			return cells
	return null


## One candidate L, or null if any cell of it is unusable. Every cell is
## checked against the world EXCEPT the doorstep, which the caller has
## already cleared -- and the street row is excluded entirely (see
## _industry_spur).
static func _spur_cells(
	doorstep: Vector2i, column: int, street_y: int, footprint_cells: Dictionary,
	chunk_size: int, is_buildable: Callable, is_occupied: Callable
):
	var cells: Array[Vector2i] = [doorstep]
	var step_x := 1 if column >= doorstep.x else -1
	var x := doorstep.x
	while x != column:
		x += step_x
		cells.append(Vector2i(x, doorstep.y))
	var step_y := 1 if street_y >= doorstep.y else -1
	var y := doorstep.y
	while y + step_y != street_y and y != street_y:
		y += step_y
		cells.append(Vector2i(column, y))

	for cell in cells:
		if footprint_cells.has(cell):
			return null
		if cell != doorstep and not _cell_clear(cell, chunk_size, is_buildable, is_occupied):
			return null
	return cells


# -- the next free street plot: where a growth building goes ---------------

## The FIRST plot `building_id` fits on, walking this village's own streets
## in exactly the order layout() walks them -- what a village reaches for
## when it owes itself one more house (an arriving household) or the next
## rung of docs/concept/village_growth.md's ladder. `{}` when the village
## has no frontage left.
##
## Unlike layout(), the plaza is reserved UNCONDITIONALLY rather than only
## when its whole square happens to be clear. That difference is the whole
## reason this is its own function and not a one-building layout() call: a
## plaza that has already been paved reads as OCCUPIED to `is_occupied`,
## layout() would conclude there is no plaza at all, and the guard that
## stops a plot straddling the square would quietly switch itself off --
## putting the village's next warehouse in the middle of its own market
## square.
static func next_street_plot(
	building_id: String, chunk_size: int, seed_value: int, is_buildable: Callable,
	is_occupied: Callable, is_dry := Callable(), accepts_origin := Callable()
) -> Dictionary:
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO:
		return {}

	# See industry_plot: the square's own siting wants the water test, not
	# whatever wider ground rule this caller happens to build against.
	var bones := skeleton(chunk_size, seed_value, is_dry if is_dry.is_valid() else is_buildable)
	var street_y: int = bones["street_y"]
	var street_x0: int = bones["street_x0"]
	var street_x1: int = bones["street_x1"]
	var plaza: Rect2i = bones["plaza"]

	var street := street_y
	while street < chunk_size - _EDGE_MARGIN_TILES:
		var x := street_x0 + _GATE_CLEARANCE_TILES
		while x + footprint.x <= street_x1:
			var origin := Vector2i(x, street - footprint.y)
			# The square is never frontage, paved or not (see this
			# function's own doc comment).
			var plaza_west_margin := plaza.position.x - PLOT_GAP_TILES
			var plaza_east_resume := plaza.end.x + PLOT_GAP_TILES
			if x < plaza_east_resume and x + footprint.x > plaza_west_margin and _rect_overlaps_rows(plaza, origin, footprint):
				x = plaza_east_resume
				continue
			if (
				_street_plot_fits(building_id, origin, plaza, chunk_size, is_buildable, is_occupied)
				# A caller may have a further condition of its own about the
				# GROUND AROUND a plot rather than the plot itself -- a
				# farmhouse needs room for its field (docs/concept/
				# village_farms.md), and a farmhouse with nowhere to farm is
				# a farmhouse that should not have been raised. A rejected
				# origin simply keeps the walk going, so the village finds
				# the next frontage that does work.
				and (not accepts_origin.is_valid() or accepts_origin.call(origin))
			):
				return {
					"origin": origin, "building_id": building_id, "facing": Vector2i(0, 1),
					"doorstep": origin + BuildingCatalog.doorstep_of(building_id),
				}
			x += 1
		street += STREET_PITCH_TILES
	return {}


## Whether the plaza's own rows overlap the rows a plot at `origin` would
## occupy -- a further street south of the square is genuinely clear of it,
## so the square must not push plots aside there.
static func _rect_overlaps_rows(plaza: Rect2i, origin: Vector2i, footprint: Vector2i) -> bool:
	return origin.y < plaza.end.y and origin.y + footprint.y > plaza.position.y


## Every footprint cell clear and off the square; the doorstep clear of the
## square too, but allowed to be an ALREADY-PAVED road cell -- fronting the
## street is the point, and the street is already paved by the time any
## growth building is ever sited.
static func _street_plot_fits(
	building_id: String, origin: Vector2i, plaza: Rect2i, chunk_size: int,
	is_buildable: Callable, is_occupied: Callable
) -> bool:
	for cell in BuildingCatalog.footprint_cells(building_id, origin):
		if plaza.has_area() and plaza.has_point(cell):
			return false
		if not _cell_clear(cell, chunk_size, is_buildable, is_occupied):
			return false
	var doorstep: Vector2i = origin + BuildingCatalog.doorstep_of(building_id)
	if plaza.has_area() and plaza.has_point(doorstep):
		return false
	if doorstep.x < 0 or doorstep.y < 0 or doorstep.x >= chunk_size or doorstep.y >= chunk_size:
		return false
	return is_buildable.call(doorstep)


## The lane a village with no square walks down to reach a further street:
## one column at the spine run's own start, from just below `from_y` to
## `to_y` inclusive. Empty when any cell of it is blocked -- a lane with a
## hole in it is not a lane. Chosen at the run's start because that column
## is the one place no plot can ever want: every street's own plots begin
## at least _GATE_CLEARANCE_TILES east of the spine's start, and the lane
## is claimed before the street it reaches is laid out regardless.
static func _gate_lane_cells(
	lane_x: int, from_y: int, to_y: int, chunk_size: int,
	is_buildable: Callable, is_occupied: Callable
) -> Array:
	var cells: Array = []
	for y in range(from_y + 1, to_y + 1):
		var cell := Vector2i(lane_x, y)
		if not _cell_clear(cell, chunk_size, is_buildable, is_occupied):
			return []
		cells.append(cell)
	return cells


## Every unbroken run of buildable street on the spine row, as (x0, x1)
## pairs. A river crossing the chunk shows up here as two runs.
static func _street_runs(
	street_y: int, street_x0: int, street_x1: int, chunk_size: int,
	is_buildable: Callable, is_occupied: Callable
) -> Array:
	var runs: Array = []
	var start := -1
	for x in range(street_x0, street_x1 + 2):
		var clear := (
			x <= street_x1 and _cell_clear(Vector2i(x, street_y), chunk_size, is_buildable, is_occupied)
		)
		if clear:
			if start < 0:
				start = x
		elif start >= 0:
			runs.append(Vector2i(start, x - 1))
			start = -1
	return runs


## Which run the village builds on: the one holding its square if it has
## one (the plaza is already proven clear, so it is always inside a run),
## otherwise the longest -- the most houses that can stand together and
## reach each other. Ties go to the westernmost, so the answer stays
## deterministic for a given chunk. Returns (0, -1) when no street exists
## at all.
static func _chosen_street_run(
	street_y: int, street_x0: int, street_x1: int, chunk_size: int,
	is_buildable: Callable, is_occupied: Callable, anchor_x: int
) -> Vector2i:
	var runs := _street_runs(street_y, street_x0, street_x1, chunk_size, is_buildable, is_occupied)
	var best := Vector2i(0, -1)
	for run in runs:
		var r: Vector2i = run
		if anchor_x >= 0 and r.x <= anchor_x and anchor_x <= r.y:
			return r
		if r.y - r.x > best.y - best.x:
			best = r
	return best
