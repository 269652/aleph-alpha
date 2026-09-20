extends GutTest

## A village pond is REAL water (docs/concept/village_ponds.md). Asked for
## directly: "filled with water and a pond with river water physics".
##
## Two world queries are the whole of it. Everything else in the game that
## cares about water already asks one of them, so a pond needs no case of its
## own anywhere else: creatures refuse it, the surface paints it, and what
## floats in it drifts.
##
## Uses _load_chunk directly rather than the slow real update(), the same way
## test_earth_chunk_manager_bees.gd and its siblings do.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const VillagePond = preload("res://src/gameplay/village_pond.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var _tile: Vector2i


## Removes the REAL persisted modifications for the Berlin chunk this whole
## file anchors on. Narrow on purpose (never the shared directory), and
## mirrors test_earth_chunk_manager_structure_art.gd's identically-named
## helper.
##
## Not optional here: one test unloads a chunk, _unload_chunk PERSISTS that
## chunk's modifications to user://, and user:// is keyed only by the
## project name -- so a dug pond leaked into every later test in this file
## AND into the next run of it, in a different worktree, as ground that was
## already water. It cost three failures that read like real bugs before
## being recognised as the hazard that file's own header documents.
func _forget_persisted_chunk() -> void:
	var chunk_coord := Vector2i(
		floori(float(_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)
	for dir in [
		EarthChunkManager.MODIFICATIONS_DIR,
		EarthChunkManager.ROOF_MODIFICATIONS_DIR,
		EarthChunkManager.PLANTED_TREES_DIR,
		EarthChunkManager.POND_FISH_DIR,
	]:
		var path := "%s/%d_%d.bin" % [dir, chunk_coord.x, chunk_coord.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo := GeoCoordinates.new()
	# Deliberately inland: a tile that is already river or ocean could not
	# tell a pond's own answer from the ground's.
	_tile = Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_forget_persisted_chunk()
	manager.update(_tile)


func after_each():
	_forget_persisted_chunk()
	remove_child(entities_parent)
	entities_parent.free()
	creatures_parent.free()
	tile_map_layer.free()


func test_dry_ground_is_not_water_before_anybody_digs():
	assert_false(manager.is_water_at_global(_tile.x, _tile.y), "precondition: dry inland ground")
	assert_false(manager.is_river_at_global(_tile.x, _tile.y))


func test_a_dug_pond_cell_reads_as_real_water():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	assert_true(
		manager.is_water_at_global(_tile.x, _tile.y),
		"a pond nothing reads as water is a brown square with fish drawn on it"
	)


## "River water physics": the flow overlay and FishMarker's own current both
## key on is_river_at_global, so a pond that answers it moves what floats in
## it without either of them learning about ponds.
func test_a_dug_pond_carries_river_flow():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	assert_true(manager.is_river_at_global(_tile.x, _tile.y))


## Filling one in gives the ground back -- a pond is a thing somebody dug,
## not a permanent change to the world.
func test_filling_a_pond_in_leaves_dry_ground_again():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	manager.destroy_at_global(_tile.x, _tile.y)
	assert_false(manager.is_water_at_global(_tile.x, _tile.y))
	assert_false(manager.is_river_at_global(_tile.x, _tile.y))


## And nothing ELSE built becomes water by accident.
func test_no_other_built_tile_reads_as_water():
	manager.build_at_global(_tile.x, _tile.y, VillageFarm.fence_tile_for("north"))
	assert_false(manager.is_water_at_global(_tile.x, _tile.y))
	assert_false(manager.is_river_at_global(_tile.x, _tile.y))


## Nobody may build on open water, so nobody may build on a pond either --
## otherwise a village would site a house in the fisher's own water.
func test_a_pond_is_not_ground_anybody_may_build_on():
	manager.build_at_global(_tile.x, _tile.y, VillagePond.POND_TILE_ID)
	assert_false(manager.is_buildable_ground_at(_tile.x, _tile.y))


# -- fish that live there and breed ----------------------------------------
#
# "...and fish swimming in it which reproduce". A pond holds its own small
# stock, grown on the world's own ecology tick toward what its water can
# feed (docs/concept/village_ponds.md).


func _dig_pond(cells: Array) -> void:
	for cell in cells:
		manager.build_at_global((cell as Vector2i).x, (cell as Vector2i).y, VillagePond.POND_TILE_ID)


func _a_pond() -> Array:
	var cells: Array = []
	for y in 2:
		for x in 3:
			cells.append(_tile + Vector2i(x, y))
	return cells


func test_water_nobody_stocked_holds_no_fish():
	var cells := _a_pond()
	_dig_pond(cells)
	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), 0.0, 0.0001)


func test_stocking_a_pond_puts_real_fish_in_it():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_almost_eq(
		manager.pond_fish_at(_tile.x, _tile.y), float(VillagePond.STOCKING_FISH), 0.0001
	)


## Every cell of the same water is the same stock -- a pond is one body of
## water, not six buckets.
func test_every_cell_of_one_pond_reports_the_same_stock():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	for cell in cells:
		assert_almost_eq(
			manager.pond_fish_at((cell as Vector2i).x, (cell as Vector2i).y),
			float(VillagePond.STOCKING_FISH), 0.0001, str(cell)
		)


func test_a_stocked_pond_breeds_on_the_worlds_own_tick():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	var before: float = manager.pond_fish_at(_tile.x, _tile.y)

	for _day in 30:
		manager.step_ponds(3600.0)  # ChunkEcologyCatchup.SECONDS_PER_DAY

	var after: float = manager.pond_fish_at(_tile.x, _tile.y)
	assert_gt(after, before, "the stock never bred")
	assert_lte(
		after, VillagePond.carrying_capacity(cells.size(), 0.55) + 1.0,
		"a pond fed more fish than its water can"
	)


## Stocking is not spontaneous, and neither is breeding from nothing.
func test_an_unstocked_pond_stays_empty_however_long_it_ticks():
	_dig_pond(_a_pond())
	for _day in 30:
		manager.step_ponds(3600.0)
	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), 0.0, 0.0001)


## Stocking twice does not double the stock -- a fisher stocks a pond, they
## do not keep stocking it.
func test_stocking_an_already_stocked_pond_changes_nothing():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_almost_eq(
		manager.pond_fish_at(_tile.x, _tile.y), float(VillagePond.STOCKING_FISH), 0.0001
	)


func test_dry_ground_can_neither_be_stocked_nor_report_fish():
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), 0.0, 0.0001)


# -- fish you can actually see ---------------------------------------------
#
# "...and fish swimming in it". A stock that only exists as a number is a
# spreadsheet. The markers are the fish: real FishMarkers standing on the
# pond's own water, kept in step with the population that breeds.


func test_water_nobody_stocked_shows_no_fish():
	_dig_pond(_a_pond())
	assert_eq(manager.pond_fish_marker_count_at(_tile.x, _tile.y), 0)


func test_stocking_a_pond_puts_visible_fish_in_it():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_eq(
		manager.pond_fish_marker_count_at(_tile.x, _tile.y), VillagePond.STOCKING_FISH,
		"the stock is a number with nothing swimming in it"
	)


func test_every_fish_stands_on_the_ponds_own_water():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	var markers: Array = manager.pond_fish_markers_at(_tile.x, _tile.y)
	assert_gt(markers.size(), 0, "precondition: fish were put in")
	for fish in markers:
		var tile := Vector2i(
			floori((fish as Node2D).position.x / 16.0), floori((fish as Node2D).position.y / 16.0)
		)
		assert_true(cells.has(tile), "a fish is standing at %s, which is not the pond" % str(tile))


## As the stock breeds, more of it is visible.
func test_a_breeding_pond_shows_more_fish_over_time():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	var before: int = manager.pond_fish_marker_count_at(_tile.x, _tile.y)
	for _day in 30:
		manager.step_ponds(3600.0)
	assert_gt(
		manager.pond_fish_marker_count_at(_tile.x, _tile.y), before,
		"the stock bred but the water still shows the same fish"
	)


## One fish per cell at most: six tiles of water is a pond, not a shoal.
func test_a_pond_never_shows_more_fish_than_it_has_water():
	var cells := _a_pond()
	_dig_pond(cells)
	manager.stock_pond_at(_tile.x, _tile.y)
	for _day in 200:
		manager.step_ponds(3600.0)
	assert_lte(manager.pond_fish_marker_count_at(_tile.x, _tile.y), cells.size())


## And they go away with the chunk, like every other loaded thing.
func test_unloading_a_chunk_takes_its_pond_fish_with_it():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	assert_gt(manager.pond_fish_marker_count_at(_tile.x, _tile.y), 0)
	manager._unload_chunk(manager._chunk_coord_for_tile(_tile))
	assert_eq(manager.pond_fish_markers_at(_tile.x, _tile.y).size(), 0)


## A catch takes a real fish out of the water: one off the stock, and one
## fewer swimming. Empty water yields nothing -- a pond you have fished out
## is fished out until it breeds back.
func test_catching_takes_a_fish_out_of_the_pond():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	var before: float = manager.pond_fish_at(_tile.x, _tile.y)
	var fish_before: int = manager.pond_fish_marker_count_at(_tile.x, _tile.y)

	assert_true(manager.catch_pond_fish_at(_tile.x, _tile.y), "there were fish to catch")

	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), before - 1.0, 0.0001)
	assert_eq(manager.pond_fish_marker_count_at(_tile.x, _tile.y), fish_before - 1)


func test_an_empty_pond_yields_no_catch():
	_dig_pond(_a_pond())
	assert_false(manager.catch_pond_fish_at(_tile.x, _tile.y), "water nobody stocked gave a fish")


func test_dry_ground_yields_no_catch():
	assert_false(manager.catch_pond_fish_at(_tile.x, _tile.y))


## A pond fished down to less than one whole fish has none to give, and
## breeds back from what is left rather than from nothing.
func test_a_pond_cannot_be_fished_below_nothing():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	for _attempt in 20:
		manager.catch_pond_fish_at(_tile.x, _tile.y)
	assert_gte(manager.pond_fish_at(_tile.x, _tile.y), 0.0, "a pond went into debt")
	assert_false(manager.catch_pond_fish_at(_tile.x, _tile.y))


# -- the water you can SEE, on the visit that digs it ----------------------
#
# Reported live with a screenshot: "The built pond renders as earth instead
# of water" -- a fenced rectangle of flat brown with the pond's own fish
# swimming on it, which is this file's own opening line made real ("a pond
# nothing reads as water is a brown square with fish drawn on it").
#
# Every query already answered correctly; what was missing was the PAINT.
# Water rides one overlay (docs/concept/hydrology.md, "ONE WATER SURFACE"),
# and _paint_river_flow_overlay runs once per chunk load -- while the
# village that digs the pond runs LATER in that same load. So the overlay
# pass had already been and gone, and build_at_global never repainted it.
# What was left is the bare pond_water modification, which the painter has
# no tile of its own for and falls through to flat earth.


## A loaded cell this chunk's own water surface does not reach: dry ground,
## far enough from the Spree that the flow overlay has erased it outright.
## Dug there, a pond's water can only be water the DIG painted.
func _a_dry_cell_with_no_water_surface(flow_layer: TileMapLayer) -> Vector2i:
	var origin := Vector2i(
		floori(float(_tile.x) / EarthChunkManager.CHUNK_SIZE) * EarthChunkManager.CHUNK_SIZE,
		floori(float(_tile.y) / EarthChunkManager.CHUNK_SIZE) * EarthChunkManager.CHUNK_SIZE
	)
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell := origin + Vector2i(x, y)
			if flow_layer.get_cell_source_id(cell) != -1:
				continue
			if manager.is_water_at_global(cell.x, cell.y):
				continue
			if manager.modification_at_global(cell.x, cell.y) != "":
				continue
			return cell
	fail_test("no dry cell clear of the water surface in this chunk")
	return _tile


func test_a_pond_dug_now_shows_its_water_now():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	var cell := _a_dry_cell_with_no_water_surface(flow_layer)

	manager.build_at_global(cell.x, cell.y, VillagePond.POND_TILE_ID)

	assert_ne(
		flow_layer.get_cell_source_id(cell), -1,
		"a pond dug this session must be water on screen now, not after the next reload"
	)
	flow_layer.free()


## The same cell, painted the same way a RELOAD would paint it -- which is
## what "it looked right the second time you walked past" actually means,
## and the only check that cannot be fooled by painting SOMETHING there.
func test_a_dug_ponds_water_is_the_water_a_reload_would_paint():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	var cell := _a_dry_cell_with_no_water_surface(flow_layer)
	manager.build_at_global(cell.x, cell.y, VillagePond.POND_TILE_ID)
	var dug := flow_layer.get_cell_atlas_coords(cell)

	var chunk_coord := Vector2i(
		floori(float(cell.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(cell.y) / EarthChunkManager.CHUNK_SIZE)
	)
	manager._unload_chunk(chunk_coord)
	manager._load_chunk(chunk_coord)

	assert_eq(dug, flow_layer.get_cell_atlas_coords(cell), "the dig must paint what the reload paints")
	flow_layer.free()


## And the other direction, for the same reason: water that was filled in
## must stop being painted as water without waiting for a reload either.
func test_filling_a_pond_in_takes_its_water_surface_with_it():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	var cell := _a_dry_cell_with_no_water_surface(flow_layer)
	manager.build_at_global(cell.x, cell.y, VillagePond.POND_TILE_ID)

	manager.destroy_at_global(cell.x, cell.y)

	assert_eq(
		flow_layer.get_cell_source_id(cell), -1,
		"filled-in ground must not go on being painted as water"
	)
	flow_layer.free()


# -- a pond keeps its fish when you walk away ------------------------------
#
# Reported live, with the pond in shot: *"no fish are in it"*. Measured on
# two real streamed villages before anything was changed: both held a dug,
# fenced pond and both reported stock=0.00, 0 markers
# (tools/probe_pond_and_farmhouse.gd).
#
# The water survives a reload because it is a persisted chunk modification.
# NOTHING ELSE about a pond was stored at all: the stock lived only in
# EarthChunkManager's own in-memory dictionary, and the village pass that
# stocks a pond only runs on the visit that DIGS one (VillageRenderer.
# _dig_fisher_ponds_if_missing returns early on a pond that is already
# there -- correctly, since "a fisher stocks a pond, they do not keep
# stocking it"). So a pond was a fishery on the one visit that founded it
# and a hole for the rest of the game.

func test_a_ponds_fish_are_still_swimming_when_the_chunk_comes_back():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	var before: float = manager.pond_fish_at(_tile.x, _tile.y)
	assert_gt(before, 0.0, "precondition: the pond was stocked")
	var chunk_coord := manager._chunk_coord_for_tile(_tile)

	manager._unload_chunk(chunk_coord)
	manager._load_chunk(chunk_coord)

	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), before, 0.0001,
		"the pond forgot its stock the moment the player walked away")
	assert_gt(manager.pond_fish_marker_count_at(_tile.x, _tile.y), 0,
		"the stock came back but nothing is swimming in it")


## And across a real restart, which is the case the report is actually
## about: a stocked pond persisted to disk is a stocked pond to a manager
## that has never seen it, exactly as a region's own fish population
## already is (FISH_POPULATION_DIR).
func test_a_ponds_fish_survive_a_manager_that_never_dug_it():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	var before: float = manager.pond_fish_at(_tile.x, _tile.y)
	var chunk_coord := manager._chunk_coord_for_tile(_tile)
	manager._unload_chunk(chunk_coord)

	var other_layer := TileMapLayer.new()
	var other_entities := Node2D.new()
	var other_creatures := Node2D.new()
	add_child(other_entities)
	var other := EarthChunkManager.new(other_layer, other_entities, other_creatures)
	other._load_chunk(chunk_coord)
	var after: float = other.pond_fish_at(_tile.x, _tile.y)
	var swimming: int = other.pond_fish_marker_count_at(_tile.x, _tile.y)
	remove_child(other_entities)
	other_entities.free()
	other_creatures.free()
	other_layer.free()

	assert_almost_eq(after, before, 0.0001,
		"a pond dug and stocked in an earlier session came back empty")
	assert_gt(swimming, 0, "a pond that kept its stock but shows no fish is a hole with a number on it")


## A pond fished flat and left flat stays flat -- the stock is real state,
## not a value that resets to its stocking every time the chunk is read.
## This is the whole reason the answer is PERSISTENCE and not "stock it
## again on reload".
func test_a_pond_fished_out_is_still_fished_out_after_a_reload():
	_dig_pond(_a_pond())
	manager.stock_pond_at(_tile.x, _tile.y)
	for _attempt in 20:
		manager.catch_pond_fish_at(_tile.x, _tile.y)
	var emptied: float = manager.pond_fish_at(_tile.x, _tile.y)
	assert_lt(emptied, 1.0, "precondition: the pond was fished below a whole fish")
	var chunk_coord := manager._chunk_coord_for_tile(_tile)

	manager._unload_chunk(chunk_coord)
	manager._load_chunk(chunk_coord)

	assert_almost_eq(manager.pond_fish_at(_tile.x, _tile.y), emptied, 0.0001,
		"a reload restocked a pond the village had already fished out")
