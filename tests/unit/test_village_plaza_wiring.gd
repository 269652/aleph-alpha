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
