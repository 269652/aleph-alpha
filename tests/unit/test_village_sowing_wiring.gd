extends GutTest

## Where the demand-driven crop choice actually reaches the ground
## (docs/concept/village_farms.md, "What a field sows follows the village's
## need").
##
## A source-contract test on the function bodies, the boundary this repo
## already draws for node wiring (see test_world_planner_mode_wiring.gd):
## what the choice IS is tested for real in test_village_crop_choice.gd;
## what is pinned here is that the sowing path really asks it.

const VillageCropChoice = preload("res://src/gameplay/village_crop_choice.gd")


func _body(path: String, function_name: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist in %s" % [function_name, path])
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


## The crop was decided once in setup_economy, from the occupation, and
## never revisited -- so a village's whole cropping plan was fixed the
## moment its villagers were built, before a single basket had been drawn.
func test_the_crop_is_decided_at_sowing_not_when_the_villager_was_built():
	var body := _body("res://src/rendering/npc_marker.gd", "_work_field_cell")
	assert_true(
		body.contains("_sow_choice_for("),
		"the sow asks for a choice rather than using the frozen field crop: %s" % body
	)
	assert_false(
		body.contains("till_and_plant_farm_plot_at_global(cell.x, cell.y, _field_crop)"),
		"the frozen crop no longer reaches the ground"
	)


## Fail-open, the same shape every other world hook in this file uses: a
## marker with no world to ask sows what it always did.
func test_a_marker_with_no_world_to_ask_keeps_its_traditional_crop():
	var body := _body("res://src/rendering/npc_marker.gd", "_sow_choice_for")
	assert_true(body.contains("_field_crop"), "it falls back to the occupation's own")
	assert_true(body.contains("has_method("), "and only asks a world that can answer")


## One rule, asked from the world rather than a second one written there.
func test_the_world_reads_the_shared_rule_rather_than_deciding_again():
	var body := _body("res://src/world/earth_chunk_manager.gd", "sow_choice_at")
	assert_true(body.contains("VillageCropChoice.choose("), body)
	assert_true(
		body.contains("VillageCropChoice.can_bake("),
		"including whether wheat is worth sowing here"
	)
	assert_true(
		body.contains("satisfaction"),
		"read off the same assembly state the needs panel shows"
	)


## A farmhouse now holds whatever its field was told to sow, which may not
## be the crop this villager was built with. Hauling one assumed id would
## quietly carry nothing.
func test_the_haul_carries_what_the_shelf_really_holds():
	var body := _body("res://src/rendering/npc_marker.gd", "haul_stock_to_village")
	assert_true(
		body.contains("structure_stock_contents_at("),
		"it reads the shelf rather than assuming one crop: %s" % body
	)
