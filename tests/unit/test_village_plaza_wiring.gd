extends GutTest

## How the square actually gets laid (docs/concept/village_market_square.md,
## docs/concept/village_farms.md).
##
## Reported: *"There are still villages without plaza."* Measured on two
## genuine villages (tools/probe_village_supply.gd): chunk (682,132) had 8
## of its 48 plaza cells paved -- exactly the single street row crossing it
## -- with a `farm_fence_east` at (15,13) and a `warehouse` at (20,13)
## standing inside the square.
##
## Two separate faults, and both had to go:
##
## 1. The paving pass walked the rect and RETURNED on the first cell it
##    could not take, so one fence cancelled the whole square.
## 2. It skipped the whole pass whenever the civic doorstep was already a
##    road tile -- and the street crossing the square paves exactly that.
##    So a village that lost its square once could never gain it back, on
##    any later visit.
##
## A source-contract test on the function body, the boundary this repo
## already draws for renderer wiring; the rule itself is tested for real in
## test_village_layout.gd.

const VillageLayout = preload("res://src/world/village_layout.gd")


func _body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://src/rendering/village_renderer.gd")
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_the_square_is_laid_around_what_stands_in_it_rather_than_abandoned():
	var body := _body("_lay_plaza_if_missing")
	assert_true(
		body.contains("VillageLayout.plaza_is_worth_laying("),
		"it asks the shared rule how much of a square is enough: %s" % body
	)
	assert_true(
		body.contains("continue"),
		"a cell it cannot take is stepped over, not a reason to stop"
	)


## The one thing that must NOT come back: a bare `return` inside the cell
## walk is exactly the fault, whatever it is guarded by.
func test_one_blocked_cell_can_never_cancel_the_whole_square_again():
	var body := _body("_lay_plaza_if_missing")
	var walk_start := body.find("for y in range(")
	assert_gt(walk_start, -1, "the premise: it still walks the rect")
	var walk_end := body.find("VillageLayout.plaza_is_worth_laying(")
	assert_gt(walk_end, walk_start, "the premise: the share is judged after the walk")
	var walk := body.substr(walk_start, walk_end - walk_start)
	assert_false(
		walk.contains("return"),
		"nothing inside the cell walk may abandon the square: %s" % walk
	)


## Self-healing, the shape this file already uses elsewhere: the pass runs
## on every visit and re-derives what is missing, so a village whose square
## was abandoned before gains it on the next load. The doorstep short-circuit
## made that impossible, because the street crossing the square paves the
## doorstep itself.
func test_a_village_that_lost_its_square_can_gain_it_back():
	var body := _body("_lay_plaza_if_missing")
	assert_false(
		body.contains('["civic_plot"]'),
		"the civic plot's own cell is never read as a short-circuit: %s" % body
	)


# -- the square is sited by water that never moves --------------------------
#
# VillageLayout.plaza_x0_for and EarthChunkManager._is_dry_local both say it
# outright: every consumer of the square has to re-derive the SAME rectangle
# with nothing persisted, so its input must be the one thing that never
# changes once the world is seeded. Ponds broke that -- a fisher digs one
# beside their door (docs/concept/village_ponds.md) and it is a chunk
# MODIFICATION, which is_water_at_global answers first. Measured: digging a
# row of pond through a square moved it from x0=12 to x0=4
# (test_village_square_ignores_dug_water.gd).
#
# The renderer derives the square in five places and founds a village in a
# sixth. All six must ask the generated world.


func test_every_square_the_renderer_derives_is_sited_by_water_that_never_moves():
	var source := FileAccess.get_file_as_string("res://src/rendering/village_renderer.gd")
	var at := source.find("VillageLayout.skeleton(")
	var seen := 0
	while at > -1:
		seen += 1
		var call_text := source.substr(at, 200)
		assert_true(
			call_text.contains("_is_dry_local("),
			"a square sited by ground that MOVES: %s" % call_text
		)
		at = source.find("VillageLayout.skeleton(", at + 1)
	assert_gt(seen, 0, "the premise: the renderer still derives squares")


## ...and the founding layout, which derives its own square inside
## VillageLayout, is handed the same rule rather than its buildability test.
func test_the_founding_layout_is_handed_the_same_water_rule():
	var body := _body("_place_new_village")
	assert_true(
		body.contains("_is_dry_local("),
		"founding sites its square by whatever it can BUILD on: %s" % body
	)


## The well, the stall and the gate are the square's own props: they are
## derived from the same rectangle, so they must be derived from the same
## water. Handing this one _is_buildable_local would put the props on one
## square and the paving on another the moment a fisher digs.
func test_the_squares_props_are_sited_by_the_same_water_rule():
	var source := FileAccess.get_file_as_string("res://src/rendering/village_renderer.gd")
	var at := source.find("_settlement_generator.generate_settlement(")
	assert_gt(at, -1, "the premise: the renderer still generates settlements")
	var call_text := source.substr(at, 700)
	assert_false(
		call_text.contains("_is_buildable_local("),
		"the square's props are sited by ground that MOVES: %s" % call_text
	)


## Both memos are per-village scratch (the square does not move while one is
## being founded). A memo that outlives its clear hands the NEXT village the
## previous one's ground.
func test_every_per_village_memo_is_cleared_together():
	var source := FileAccess.get_file_as_string("res://src/rendering/village_renderer.gd")
	for memo in ["_buildable_memo", "_dry_memo", "_skeleton_memo"]:
		assert_true(
			source.contains("%s.clear()" % memo),
			"%s is never cleared, so it leaks across villages" % memo
		)
