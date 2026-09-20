extends GutTest

## CaveNetwork: which cells of a cave-bearing layer are natural void (see
## docs/concept/underground.md "The cave network and Strata.KIND_VOID").
##
## The porosities are DERIVED from real cave surveys -- a pattern's
## measured passage density times its real mean passage width -- not
## tuned. The generator's own thresholds are then calibrated to reproduce
## them, which is what test_measured_void_fraction_matches_the_derived_
## porosity checks: the real number is the spec, the threshold is just how
## the field is made to hit it.

const CaveNetwork = preload("res://src/world/cave_network.gd")
const CavePattern = preload("res://src/world/cave_pattern.gd")

## Big enough that a spatially-correlated field still averages out; a
## smooth noise field has far higher sampling variance than independent
## draws, which is why the tolerances below are relative and generous.
const SAMPLE_SPAN := 160

var network: CaveNetwork


func before_each():
	network = CaveNetwork.new()


func _void_cells(pattern: String, origin: Vector2i, span: int) -> Dictionary:
	var cells := {}
	for y in span:
		for x in span:
			if network.is_void_at(pattern, origin.x + x, origin.y + y):
				cells[Vector2i(x, y)] = true
	return cells


## Share of a region's void cells that sit in its single largest
## 8-connected component -- the real "is this one cave or a scatter of
## unconnected pockets" question.
##
## Eight-connected, not four, and that is load-bearing rather than a
## convenience. A real 3m conduit at this world's 1.426 m/tile comes out
## one to two tiles wide, and a sinuous passage that narrow steps
## diagonally all the time. The player moves diagonally too, so a
## diagonal step is genuinely traversable -- judging these passages by
## 4-connectivity measured the grid's axis alignment, not whether the
## cave joins up, and reported a perfectly continuous conduit as 16%
## connected.
func _largest_component_share(pattern: String, origin: Vector2i, span: int) -> float:
	var cells := _void_cells(pattern, origin, span)
	if cells.is_empty():
		return 0.0
	var unvisited := cells.duplicate()
	var largest := 0
	while not unvisited.is_empty():
		var start: Vector2i = unvisited.keys()[0]
		var stack: Array[Vector2i] = [start]
		unvisited.erase(start)
		var size := 0
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			size += 1
			for step in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
			]:
				var neighbour: Vector2i = cell + step
				if unvisited.has(neighbour):
					unvisited.erase(neighbour)
					stack.append(neighbour)
		largest = maxi(largest, size)
	return float(largest) / float(cells.size())


# -- porosity is derived from real surveys, not tuned ----------------------

func test_porosity_is_derived_from_a_real_passage_density_and_width():
	for pattern in CaveNetwork.CAVE_PATTERNS:
		var density: float = CaveNetwork.PASSAGE_DENSITY_KM_PER_KM2[pattern]
		var width_m: float = CaveNetwork.MEAN_PASSAGE_WIDTH_M[pattern]
		# km of passage per km^2, times metres of width, over 1000 m/km.
		assert_almost_eq(
			network.porosity_of(pattern), density * width_m / 1000.0, 0.0001,
			"%s porosity must follow from its own survey numbers" % pattern
		)


func test_a_maze_is_vastly_more_open_than_a_branchwork():
	# Optymistychna packs ~257km of passage into ~2km^2; Mammoth Cave
	# spreads ~676km across ~150km^2. That contrast is the whole reason
	# the two patterns play differently.
	assert_gt(
		network.porosity_of(CavePattern.PATTERN_NETWORK_MAZE),
		network.porosity_of(CavePattern.PATTERN_BRANCHWORK) * 10.0
	)


func test_a_cave_is_still_mostly_rock():
	for pattern in CaveNetwork.CAVE_PATTERNS:
		assert_lt(
			network.porosity_of(pattern), 0.5,
			"%s would be open space, not a cave in rock" % pattern
		)
		assert_gt(network.porosity_of(pattern), 0.0)


func test_a_pattern_with_no_cave_has_no_porosity():
	assert_eq(network.porosity_of(CavePattern.PATTERN_NONE), 0.0)
	assert_eq(network.porosity_of("not_a_real_pattern"), 0.0)


# -- the generated field actually reproduces those porosities --------------

## Branchwork conduits sit ~220m apart in a real system, which is ~156
## tiles -- so a contiguous 160-tile block contains barely one conduit and
## says nothing about the field's average. Sampling with a stride across a
## far wider area decorrelates the samples and spans many wavelengths,
## which is what makes the measured fraction mean anything.
const POROSITY_SAMPLE_STRIDE := 13
const POROSITY_SAMPLE_STEPS := 220

func _measured_porosity(pattern: String) -> float:
	var void_count := 0
	for iy in POROSITY_SAMPLE_STEPS:
		for ix in POROSITY_SAMPLE_STEPS:
			if network.is_void_at(
				pattern, 4096 + ix * POROSITY_SAMPLE_STRIDE, -2048 + iy * POROSITY_SAMPLE_STRIDE
			):
				void_count += 1
	return float(void_count) / float(POROSITY_SAMPLE_STEPS * POROSITY_SAMPLE_STEPS)


func test_measured_void_fraction_matches_the_derived_porosity():
	for pattern in CaveNetwork.CAVE_PATTERNS:
		var measured := _measured_porosity(pattern)
		var target: float = network.porosity_of(pattern)
		assert_almost_eq(
			measured, target, target * 0.4,
			"%s: generated %.2f%% void against a surveyed %.2f%%" % [
				pattern, measured * 100.0, target * 100.0
			]
		)


# -- determinism -----------------------------------------------------------

func test_the_void_field_is_deterministic():
	for i in 200:
		var x := 900 + i * 7
		var y := -300 - i * 3
		assert_eq(
			network.is_void_at(CavePattern.PATTERN_BRANCHWORK, x, y),
			network.is_void_at(CavePattern.PATTERN_BRANCHWORK, x, y)
		)


func test_two_instances_agree():
	var other := CaveNetwork.new()
	for i in 200:
		var x := 1500 + i * 11
		assert_eq(
			network.is_void_at(CavePattern.PATTERN_NETWORK_MAZE, x, 77),
			other.is_void_at(CavePattern.PATTERN_NETWORK_MAZE, x, 77)
		)


func test_rock_with_no_cave_pattern_is_never_void():
	for i in 500:
		assert_false(network.is_void_at(CavePattern.PATTERN_NONE, i * 13, i * 29))
		assert_false(network.is_void_at("not_a_real_pattern", i * 13, i * 29))


# -- the patterns are structurally what Palmer says they are ---------------

## A conduit system is ONE cave: its passages join. A scatter of
## unconnected pockets at the same porosity would be a different thing
## entirely, and is what a naive per-cell density roll produces.
const CONNECTED_SHARE := 0.5

## Largest-component share of a pure per-cell density roll at the same
## porosity -- the naive generator this whole file exists to not be. Well
## below the percolation threshold it is a dust of one- and two-cell
## specks, so this is near zero.
func _scatter_largest_component_share(porosity: float, span: int) -> float:
	var cells := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	for y in span:
		for x in span:
			if rng.randf() < porosity:
				cells[Vector2i(x, y)] = true
	if cells.is_empty():
		return 0.0
	var unvisited := cells.duplicate()
	var largest := 0
	while not unvisited.is_empty():
		var start: Vector2i = unvisited.keys()[0]
		var stack: Array[Vector2i] = [start]
		unvisited.erase(start)
		var size := 0
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			size += 1
			for step in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
			]:
				var neighbour: Vector2i = cell + step
				if unvisited.has(neighbour):
					unvisited.erase(neighbour)
					stack.append(neighbour)
		largest = maxi(largest, size)
	return float(largest) / float(cells.size())


## How many times more integrated than a scatter a real conduit system has
## to be. Deliberately a RATIO against a same-porosity control rather than
## an absolute share: several separate contour arcs crossing one sampling
## window are several real conduits that may only join outside it, so an
## absolute "most cells in one component" bound would be measuring the
## window, not the cave. Mammoth Cave's own region holds several distinct
## systems too.
const SCATTER_INTEGRATION_FACTOR := 5.0

func test_conduit_patterns_are_far_more_integrated_than_a_scatter():
	for pattern in [
		CavePattern.PATTERN_BRANCHWORK,
		CavePattern.PATTERN_ANASTOMOTIC,
		CavePattern.PATTERN_NETWORK_MAZE,
	]:
		var share := _largest_component_share(pattern, Vector2i(-512, 1024), SAMPLE_SPAN)
		var scatter := _scatter_largest_component_share(network.porosity_of(pattern), SAMPLE_SPAN)
		assert_gt(
			share, scatter * SCATTER_INTEGRATION_FACTOR,
			(
				"%s: largest component holds %.1f%% of void cells, a same-porosity "
				+ "scatter manages %.1f%% -- this is not a passage system"
			) % [pattern, share * 100.0, scatter * 100.0]
		)


func test_a_dense_maze_is_one_single_system():
	# At its surveyed porosity a maze is far above the percolation
	# threshold, so unlike a sparse conduit it really should come out as
	# one cave with almost nothing stranded.
	var share := _largest_component_share(
		CavePattern.PATTERN_NETWORK_MAZE, Vector2i(-512, 1024), SAMPLE_SPAN
	)
	assert_gt(share, CONNECTED_SHARE, "a maze at 38% porosity must be one connected system")


func test_a_conduit_comes_out_as_wide_as_the_surveyed_passage():
	# The threshold is calibrated against the surveyed POROSITY and knows
	# nothing about passage width. If the width it independently produces
	# lands on the surveyed mean width, two unrelated survey numbers have
	# agreed -- which is a real check on the model, not a restatement of
	# its input.
	var expected_half_width: float = (
		CaveNetwork.MEAN_PASSAGE_WIDTH_M[CavePattern.PATTERN_BRANCHWORK]
		/ 2.0 / CaveNetwork.METRES_PER_TILE
	)
	assert_gt(expected_half_width, 0.0)
	var produced: float = network.conduit_half_width_tiles(CavePattern.PATTERN_BRANCHWORK)
	var anastomotic: float = network.conduit_half_width_tiles(CavePattern.PATTERN_ANASTOMOTIC)
	assert_almost_eq(
		anastomotic, expected_half_width, expected_half_width * 0.25,
		"an anastomotic tube came out %.2f tiles half-wide against a surveyed %.2f" % [
			anastomotic, expected_half_width
		]
	)
	# A quarter of the surveyed width. The first version of this test
	# allowed a full 100% relative tolerance, which let a conduit 2.5x too
	# narrow pass as agreement -- a loose bound is not a weak test, it is
	# a test of nothing.
	assert_almost_eq(
		produced, expected_half_width, expected_half_width * 0.25,
		(
			"a branchwork conduit came out %.2f tiles half-wide against a surveyed "
			+ "%.2f (%.1fm passage at %.3f m/tile)"
		) % [
			produced, expected_half_width,
			CaveNetwork.MEAN_PASSAGE_WIDTH_M[CavePattern.PATTERN_BRANCHWORK],
			CaveNetwork.METRES_PER_TILE,
		]
	)


func test_spongework_has_no_through_route():
	# Palmer's spongework is irregular interconnected CAVITIES -- the
	# defining property is that it does not carry a through-route, unlike
	# every conduit pattern above.
	var sponge := _largest_component_share(
		CavePattern.PATTERN_SPONGEWORK, Vector2i(-512, 1024), SAMPLE_SPAN
	)
	var branchwork := _largest_component_share(
		CavePattern.PATTERN_BRANCHWORK, Vector2i(-512, 1024), SAMPLE_SPAN
	)
	assert_lt(sponge, CONNECTED_SHARE, "spongework must not form one through-going system")
	assert_lt(sponge, branchwork, "spongework must be less integrated than a conduit system")


func test_a_ramiform_cave_is_room_dominated():
	# Hypogenic caves are rooms, not conduits -- Carlsbad's Big Room is
	# 190m across. Its mean passage width is correspondingly far above a
	# stream conduit's.
	assert_gt(
		CaveNetwork.MEAN_PASSAGE_WIDTH_M[CavePattern.PATTERN_RAMIFORM],
		CaveNetwork.MEAN_PASSAGE_WIDTH_M[CavePattern.PATTERN_BRANCHWORK]
	)


func test_every_cave_bearing_pattern_is_covered():
	# Every CavePattern except NONE must have a void field, or a region
	# would classify as cave-bearing and then generate solid rock.
	for pattern in CavePattern.PATTERNS:
		if pattern == CavePattern.PATTERN_NONE:
			continue
		assert_true(
			CaveNetwork.CAVE_PATTERNS.has(pattern), "pattern '%s' has no void field" % pattern
		)
