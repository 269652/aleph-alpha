extends GutTest

## BuildingStatics: a support graph over the piece grid (see
## docs/concept/timber_construction.md#real-statics-a-support-graph-over-the-
## piece-grid). Reuses RoomDetector's grid-over-local-cells shape and
## flood-fill approach as its model, but the traversal answers a different
## question: not "is this cell enclosed" but "does this load-bearing cell
## have a path of adjacent load-bearing cells back to a grounded cell within
## a maximum unsupported run" -- the game version of a beam's span limit
## ("a beam spanning between two posts... the further it spans unsupported,
## the less load it can carry before it sags and fails").

const BuildingStatics = preload("res://src/gameplay/building_statics.gd")

var statics: BuildingStatics


func before_each():
	statics = BuildingStatics.new()


## A single wall cell touching a grounded cell needs no chain at all.
func test_a_wall_directly_on_grounded_terrain_is_supported():
	var grid := {Vector2i(0, 0): "wood_wall"}
	var grounded := {Vector2i(0, -1): true}
	assert_eq(statics.unsupported_cells(grid, grounded), [])


## A wall with NO grounded cell anywhere nearby, and no load-bearing chain
## reaching one, is unsupported -- floating in the air is not a real
## structure.
func test_a_wall_with_no_grounding_anywhere_is_unsupported():
	var grid := {Vector2i(0, 0): "wood_wall"}
	var grounded := {}
	assert_eq(statics.unsupported_cells(grid, grounded), [Vector2i(0, 0)])


## A simple supported structure: a straight run of walls up to
## MAX_UNSUPPORTED_RUN cells long, one end touching grounded terrain, plus a
## floor and a roof each within CANTILEVER_LIMIT of a wall. Nothing here
## should report unsupported -- mirrors Worked Example A, "the statics graph
## accepts it because every wall segment sits within its span limit of a
## corner post."
func test_a_simple_supported_structure_reports_nothing_unsupported():
	var grid := {}
	for i in range(BuildingStatics.MAX_UNSUPPORTED_RUN + 1):
		grid[Vector2i(i, 0)] = "wood_wall"
	grid[Vector2i(0, 1)] = "wood_floor"  # within CANTILEVER_LIMIT of wall (0,0)
	grid[Vector2i(1, 1)] = "wood_roof"  # within CANTILEVER_LIMIT of wall (1,0)
	var grounded := {Vector2i(-1, 0): true}
	assert_eq(statics.unsupported_cells(grid, grounded), [])


## A load-bearing chain longer than MAX_UNSUPPORTED_RUN cells past the
## grounded end leaves its far cells unsupported -- the game version of a
## beam sagging past its real span limit.
func test_a_wall_chain_beyond_the_max_unsupported_run_is_unsupported():
	var grid := {}
	var chain_length := BuildingStatics.MAX_UNSUPPORTED_RUN + 3
	for i in range(chain_length):
		grid[Vector2i(i, 0)] = "wood_wall"
	var grounded := {Vector2i(-1, 0): true}
	var unsupported := statics.unsupported_cells(grid, grounded)
	# Cells 0..MAX_UNSUPPORTED_RUN are within the span limit (distance
	# 0..MAX_UNSUPPORTED_RUN from the grounded end); anything past that is not.
	for i in range(BuildingStatics.MAX_UNSUPPORTED_RUN + 1, chain_length):
		assert_true(unsupported.has(Vector2i(i, 0)), "cell %d should be unsupported" % i)
	for i in range(0, BuildingStatics.MAX_UNSUPPORTED_RUN + 1):
		assert_false(unsupported.has(Vector2i(i, 0)), "cell %d should still be supported" % i)


## The defining case this module exists for: sever a support path by
## removing the piece that used to connect a cell back to the ground, and
## that cell (and anything past it) must now be detected unsupported --
## without the grid changing anywhere else.
func test_severing_a_support_path_is_detected_as_unsupported():
	var grid := {
		Vector2i(0, 0): "wood_wall", Vector2i(1, 0): "wood_wall", Vector2i(2, 0): "wood_wall",
	}
	var grounded := {Vector2i(-1, 0): true}
	# Fully connected: nothing unsupported.
	assert_eq(statics.unsupported_cells(grid, grounded), [])

	# Sever the middle link.
	grid.erase(Vector2i(1, 0))
	var unsupported := statics.unsupported_cells(grid, grounded)
	assert_eq(unsupported, [Vector2i(2, 0)], "the far wall lost its only path back to the ground")


## A floor/roof/door/window is never itself load-bearing, but needs a real
## load-bearing neighbor within CANTILEVER_LIMIT -- cantilevering a plank
## floor further than that past the last supporting post must be refused,
## per Worked Example B.
func test_a_floor_too_far_from_any_wall_is_unsupported():
	var grid := {
		Vector2i(0, 0): "wood_wall",
	}
	var far_offset := BuildingStatics.CANTILEVER_LIMIT + 1
	grid[Vector2i(far_offset, 0)] = "wood_floor"
	var grounded := {Vector2i(-1, 0): true}
	var unsupported := statics.unsupported_cells(grid, grounded)
	assert_true(unsupported.has(Vector2i(far_offset, 0)))


func test_a_floor_within_the_cantilever_limit_is_supported():
	var grid := {Vector2i(0, 0): "wood_wall"}
	grid[Vector2i(BuildingStatics.CANTILEVER_LIMIT, 0)] = "wood_floor"
	var grounded := {Vector2i(-1, 0): true}
	assert_eq(statics.unsupported_cells(grid, grounded), [])


## A door/window follows the exact same non-load-bearing rule as a floor --
## the doc groups CATEGORY_FLOOR/ROOF/DOOR/WINDOW together explicitly.
func test_a_door_far_from_any_wall_is_unsupported():
	var grid := {Vector2i(0, 0): "wood_wall"}
	var far_offset := BuildingStatics.CANTILEVER_LIMIT + 1
	grid[Vector2i(far_offset, 0)] = "wood_door"
	var grounded := {Vector2i(-1, 0): true}
	assert_true(statics.unsupported_cells(grid, grounded).has(Vector2i(far_offset, 0)))


# -- resolve(): grace threshold + collapse (see docs/concept/materials.md's
# "Topple / collapse" verb) --------------------------------------------------
#
# A piece that loses its support path does not vanish instantly: it
# accumulates instability and, past a short grace threshold, collapses.
# resolve() is the pure, timed step: given the grid/grounded/prior-
# instability state and how many real seconds just elapsed, it returns the
# advanced instability plus whichever cells crossed the grace threshold and
# should collapse this pass.

func test_a_newly_unsupported_cell_does_not_collapse_before_the_grace_period():
	var grid := {Vector2i(0, 0): "wood_wall"}
	var grounded := {}  # ungrounded -- unsupported from the start
	var result := statics.resolve(grid, grounded, {}, BuildingStatics.GRACE_SECONDS * 0.5)
	assert_eq(result["collapsed"], [], "half the grace period should not be enough to collapse yet")
	assert_gt(
		float(result["instability"].get(Vector2i(0, 0), 0.0)), 0.0,
		"it should still be accumulating instability"
	)


## The timing test: instability accrues across successive resolve() calls
## (the real, event-driven recompute happening again later) exactly like a
## caller feeding its own previous result back in, and the cell collapses
## only once the ACCUMULATED time crosses GRACE_SECONDS, not before.
func test_grace_threshold_timing_before_collapse_actually_triggers():
	var grid := {Vector2i(0, 0): "wood_wall"}
	var grounded := {}
	var step := BuildingStatics.GRACE_SECONDS / 3.0
	var instability := {}

	var first := statics.resolve(grid, grounded, instability, step)
	assert_eq(first["collapsed"], [], "1/3 of the grace period: not yet")
	instability = first["instability"]

	var second := statics.resolve(grid, grounded, instability, step)
	assert_eq(second["collapsed"], [], "2/3 of the grace period: still not yet")
	instability = second["instability"]

	var third := statics.resolve(grid, grounded, instability, step * 1.1)
	assert_eq(third["collapsed"], [Vector2i(0, 0)], "just past the full grace period: now it collapses")


## Regaining support (e.g. a neighboring recompute reconnects the chain)
## forgets any instability that had built up -- a piece that was briefly at
## risk and then got re-supported should not carry a grudge.
func test_regaining_support_resets_accumulated_instability():
	var grid := {Vector2i(0, 0): "wood_wall"}
	var ungrounded := {}
	var grounded := {Vector2i(-1, 0): true}

	var at_risk := statics.resolve(grid, ungrounded, {}, BuildingStatics.GRACE_SECONDS * 0.9)
	assert_gt(float(at_risk["instability"].get(Vector2i(0, 0), 0.0)), 0.0, "precondition: accumulating")

	var supported := statics.resolve(grid, grounded, at_risk["instability"], 0.0)
	assert_false(supported["instability"].has(Vector2i(0, 0)), "support regained -- instability forgotten")


## The cascade: a collapse can bring down whatever it was holding up, all
## within ONE resolve() call -- not requiring the caller to invoke it a
## second time. Mirrors Worked Example D: "the statics recompute this
## triggers finds the roof section it was holding up now unsupported, which
## comes down in turn." A grounded post holds up a wall which holds up a
## roof; the post is already gone from the grid (as if it had just
## collapsed), so BOTH the now-unsupported wall AND the roof it was in turn
## holding up must collapse together when enough time is given in one call.
func test_a_collapse_cascades_to_dependents_within_one_resolve_call():
	var grid := {
		Vector2i(1, 0): "wood_wall",  # depended on the now-missing post at (0,0)
		Vector2i(1, 1): "wood_roof",  # cantilevers off the wall at (1,0)
	}
	var grounded := {}  # nothing grounds this chain any more -- the post is gone
	var result := statics.resolve(grid, grounded, {}, BuildingStatics.GRACE_SECONDS)

	assert_true(result["collapsed"].has(Vector2i(1, 0)), "the orphaned wall should collapse")
	assert_true(
		result["collapsed"].has(Vector2i(1, 1)),
		"the roof it was holding up should come down in the SAME call, in turn"
	)
	assert_eq(result["collapsed"].size(), 2, "no other cell should be affected")


## A generously-supported structure never accumulates any instability at
## all, no matter how much time passes -- resolve() must be a true no-op for
## a healthy building.
func test_resolve_is_a_no_op_for_a_fully_supported_structure():
	var grid := {Vector2i(0, 0): "wood_wall", Vector2i(1, 0): "wood_floor"}
	var grounded := {Vector2i(-1, 0): true}
	var result := statics.resolve(grid, grounded, {}, 1000.0)
	assert_eq(result["collapsed"], [])
	assert_eq(result["instability"], {})


func test_resolve_does_not_mutate_its_inputs():
	var grid := {Vector2i(0, 0): "wood_wall"}
	var grounded := {}
	var instability := {}
	statics.resolve(grid, grounded, instability, BuildingStatics.GRACE_SECONDS)
	assert_eq(grid, {Vector2i(0, 0): "wood_wall"}, "grid must be untouched")
	assert_eq(instability, {}, "the instability dict passed in must be untouched")


# -- calibration: tuned constants are pinned, not eyeballed comments --------

func test_max_unsupported_run_is_pinned():
	assert_eq(BuildingStatics.MAX_UNSUPPORTED_RUN, 4)


func test_cantilever_limit_is_pinned_and_shorter_than_the_wall_span():
	assert_eq(BuildingStatics.CANTILEVER_LIMIT, 3)
	assert_lt(BuildingStatics.CANTILEVER_LIMIT, BuildingStatics.MAX_UNSUPPORTED_RUN)


func test_grace_seconds_is_pinned():
	assert_eq(BuildingStatics.GRACE_SECONDS, 6.0)


func test_results_are_deterministic():
	var grid := {
		Vector2i(0, 0): "wood_wall", Vector2i(1, 0): "wood_wall", Vector2i(2, 0): "wood_floor",
	}
	var grounded := {Vector2i(-1, 0): true}
	assert_eq(statics.unsupported_cells(grid, grounded), statics.unsupported_cells(grid, grounded))
