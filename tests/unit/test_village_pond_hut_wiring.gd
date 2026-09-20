extends GutTest

## How a fisher's pond actually gets dug (docs/concept/village_ponds.md).
##
## Reported live, standing at the water: *"no Fisher Hut is near"*.
## Measured on three real streamed villages (tools/probe_village_geometry.gd):
## the village at chunk (696,128) had a pond with NO hut anywhere, and not
## by a near miss -- all 51 candidate origins within HUT_BANK_REACH_TILES
## of that water were refused, 19 by the village street, 21 by neighbouring
## houses, 5 by the pond's own fence rail and 6 by the water itself. The
## pond had been dug into the two-row strip between the street and the next
## house row, which is exactly wide enough for the water and nothing else.
##
## Two passes that never spoke: the dig took the best rectangle in reach,
## and the hut was sited afterwards on whatever bank that left. The rule
## itself is tested for real in test_village_pond.gd; this pins that the
## dig ASKS it, which is the part no model test can see.
##
## A source-contract test on the function body, the boundary this repo
## already draws for renderer wiring (see test_village_plaza_wiring.gd).

const VillagePond = preload("res://src/gameplay/village_pond.gd")


func _body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://src/rendering/village_renderer.gd")
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_the_dig_asks_whether_the_water_it_is_choosing_can_take_a_hut():
	var body := _body("_dig_fisher_ponds_if_missing")
	assert_true(
		body.contains("VillagePond.bank_takes_a_hut("),
		"the dig must ask the shared rule before it commits to a rectangle: %s" % body
	)


## ...and digs anyway when no bank anywhere can take one. A pond with no
## hut beats no pond at all: the fisher works the water, not the building.
func test_water_nowhere_can_be_built_beside_is_still_dug():
	var body := _body("_dig_fisher_ponds_if_missing")
	var asked := body.find("VillagePond.bank_takes_a_hut(")
	assert_gt(asked, -1, "the premise: the dig asks at all")
	var after := body.substr(asked)
	assert_true(
		after.contains("pond_cells(origin, building_id, is_free_for_house)"),
		"a second, unconditional search must stand behind the first: %s" % after
	)


## The rule it asks is a real one, not a name that happens to parse -- a
## source-contract test names a function in a string, and a string cannot
## be renamed by a refactor.
func test_the_rule_the_dig_asks_for_is_a_real_question_with_a_real_answer():
	var water: Array = []
	for y in range(8, 10):
		for x in range(8, 11):
			water.append(Vector2i(x, y))
	assert_true(
		VillagePond.bank_takes_a_hut(
			water, Vector2i(8, 12), "house_small", func(_cell: Vector2i) -> bool: return true
		),
		"open ground round a pond must take a hut"
	)
	assert_false(
		VillagePond.bank_takes_a_hut(
			water, Vector2i(8, 12), "house_small", func(_cell: Vector2i) -> bool: return false
		),
		"and ground nothing may be built on must not"
	)
