extends GutTest

## The build palette's own model (see docs/concept/planner_mode.md, "The
## build palette"). Pure, so what the menu says is testable without
## standing up a World -- the same split ViewMode already keeps for the
## mode itself.
##
## Asked directly, with a screenshot of ten identical text buttons in a
## row: "Make the Planner / Building HUD more professional and more like
## Anno 1806. Add Icons not only text".

const BlueprintPaletteModel = preload("res://src/ui/blueprint_palette_model.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")


## Typed Array[String] vs a plain Array compares element-wise either way,
## but the comparison is the point of several tests below, so it is made
## explicit rather than left to depend on that.
func _plain(values) -> Array:
	var out: Array = []
	for value in values:
		out.append(value)
	return out


func _flattened() -> Array:
	var out: Array = []
	for category in BlueprintPaletteModel.categories():
		out.append_array(_plain(category["blueprint_ids"]))
	return out


## The concept doc's rule: "the palette's categories ARE those lists, read
## at runtime. It does not keep a second grouping". Pinned per list, so a
## building added to BuildingCatalog lands in the right category for free.
func test_each_category_is_one_of_the_catalogues_own_lists():
	var by_id := {}
	for category in BlueprintPaletteModel.categories():
		by_id[String(category["id"])] = _plain(category["blueprint_ids"])
	assert_eq(
		by_id.get(BlueprintPaletteModel.CATEGORY_HOMES),
		_plain(BuildingCatalog.BUILDING_IDS),
		"the homes tab is BUILDING_IDS itself"
	)
	assert_eq(
		by_id.get(BlueprintPaletteModel.CATEGORY_PRODUCTION),
		_plain(BuildingCatalog.PRODUCTION_BUILDING_IDS),
		"the production tab is PRODUCTION_BUILDING_IDS itself"
	)
	assert_eq(
		by_id.get(BlueprintPaletteModel.CATEGORY_CIVIC),
		_plain(BuildingCatalog.CIVIC_BUILDING_IDS),
		"the civic tab is CIVIC_BUILDING_IDS itself"
	)
	assert_eq(
		by_id.get(BlueprintPaletteModel.CATEGORY_ROADS),
		[BuildPlan.PAVEMENT_BLUEPRINT_ID],
		"pavement is not a BuildingCatalog entry, so it carries its own tab"
	)


## A redesign that quietly drops a building is a building the player can no
## longer plan. The palette must still offer exactly what the flat row of
## text buttons offered -- pavement, then every real catalog list, in that
## order.
func test_the_palette_still_offers_exactly_what_it_offered_before():
	var expected: Array = [BuildPlan.PAVEMENT_BLUEPRINT_ID]
	expected.append_array(_plain(BuildingCatalog.BUILDING_IDS))
	expected.append_array(_plain(BuildingCatalog.PRODUCTION_BUILDING_IDS))
	expected.append_array(_plain(BuildingCatalog.CIVIC_BUILDING_IDS))
	assert_eq(_flattened(), expected, "nothing gained, nothing lost, same order")


func test_every_offered_blueprint_appears_in_exactly_one_category():
	assert_gt(_flattened().size(), 0, "the premise: the palette offers something")
	var seen := {}
	for blueprint_id in _flattened():
		assert_false(seen.has(blueprint_id), "%s is in two tabs" % blueprint_id)
		seen[blueprint_id] = true


func test_every_category_has_a_label_and_something_in_it():
	assert_gt(BlueprintPaletteModel.categories().size(), 0, "the premise: there are tabs")
	for category in BlueprintPaletteModel.categories():
		assert_ne(String(category["label"]), "", "a nameless tab is unclickable")
		assert_gt(
			_plain(category["blueprint_ids"]).size(), 0,
			"an empty tab is a tab that does nothing: %s" % category["id"]
		)


## Every blueprint the palette offers is one the ledger will really accept
## (pillar 2's one vocabulary) -- a tab offering something unplannable
## would be a button that always refuses.
func test_everything_offered_is_really_plannable():
	assert_gt(_flattened().size(), 0, "the premise: the palette offers something")
	for blueprint_id in _flattened():
		assert_true(
			BuildPlan.is_plannable(blueprint_id),
			"%s is offered but cannot be planned" % blueprint_id
		)


func test_a_slot_is_titled_with_the_name_the_rest_of_the_game_uses():
	assert_gt(_flattened().size(), 0, "the premise: the palette offers something")
	for blueprint_id in _flattened():
		assert_eq(
			BlueprintPaletteModel.slot_title(blueprint_id),
			BuildPlan.display_name_of(blueprint_id),
			"the menu and the message stack call a building the same thing"
		)


## The footprint is the one thing a build menu must say before a click, and
## it is read from the catalogue rather than restated.
func test_the_footprint_line_is_the_catalogues_own_footprint():
	assert_eq(BlueprintPaletteModel.slot_subtitle("house_small"), "2 x 2")
	assert_eq(BlueprintPaletteModel.slot_subtitle("house_large"), "3 x 3")
	assert_eq(BlueprintPaletteModel.slot_subtitle("city_hall"), "4 x 3")
	assert_eq(
		BlueprintPaletteModel.slot_subtitle(BuildPlan.PAVEMENT_BLUEPRINT_ID), "1 x 1",
		"pavement is one cell at a time"
	)


## Never a second price list -- the rule PlanRaising already keeps, applied
## to the menu, so what the card promises and what raising it charges
## cannot disagree. Pinned exactly rather than by "the number appears
## somewhere", which a footprint or an hour count could satisfy by
## accident.
func test_the_cost_text_is_the_catalogues_own_cost_exactly():
	assert_eq(BlueprintPaletteModel.cost_text("house_small"), "12 Wood")
	assert_eq(BlueprintPaletteModel.cost_text("house_medium"), "20 Wood, 4 Stone")
	assert_eq(
		BlueprintPaletteModel.cost_text("farmhouse"), "14 Wood, 4 Stone, 6 Plant Fibre",
		"an id with an underscore is still read as words"
	)


## The pin that keeps the three above honest as the catalogue is tuned:
## every count in the text really is the catalogue's own, for every
## building the palette offers.
func test_every_offered_buildings_cost_text_is_built_from_its_own_cost():
	assert_gt(_flattened().size(), 0, "the premise: the palette offers something")
	for blueprint_id in _flattened():
		var cost: Dictionary = BuildingCatalog.cost_of(blueprint_id)
		var text := BlueprintPaletteModel.cost_text(blueprint_id)
		if cost.is_empty():
			assert_eq(text, BlueprintPaletteModel.FREE_TEXT, blueprint_id)
			continue
		var parts := text.split(", ")
		assert_eq(parts.size(), cost.size(), "one part per material: %s" % text)
		var index := 0
		for item_id in cost:
			assert_eq(
				String(parts[index]).split(" ")[0], str(int(cost[item_id])),
				"%s's %s count" % [blueprint_id, item_id]
			)
			index += 1


func test_the_cost_names_items_through_the_catalogue_when_one_is_given():
	var naming := func(item_id: String) -> String:
		return "Timber" if item_id == "wood" else item_id.capitalize()
	assert_eq(BlueprintPaletteModel.cost_text("house_medium", naming), "20 Timber, 4 Stone")


func test_a_blueprint_that_costs_no_materials_says_so_rather_than_nothing():
	assert_eq(
		BlueprintPaletteModel.cost_text(BuildPlan.PAVEMENT_BLUEPRINT_ID),
		BlueprintPaletteModel.FREE_TEXT
	)


func test_the_cost_of_an_unknown_blueprint_is_blank_rather_than_free():
	assert_eq(BlueprintPaletteModel.cost_text("not_a_building"), "")


func test_the_card_carries_the_cost_text_itself():
	var text := "\n".join(BlueprintPaletteModel.detail_lines("house_medium", 10.0))
	assert_true(
		text.contains(BlueprintPaletteModel.cost_text("house_medium")),
		"the card shows the same cost the cost text says: %s" % text
	)


## PlanRaising.is_laid_by_hand's rule, said in the menu instead of
## discovered at the site: work that costs no hours is laid at once, and
## reads that way rather than as "0 hours".
func test_work_that_costs_no_hours_reads_as_laid_by_hand():
	var text := "\n".join(
		BlueprintPaletteModel.detail_lines(BuildPlan.PAVEMENT_BLUEPRINT_ID, 0.0)
	)
	assert_true(text.contains(BlueprintPaletteModel.LAID_BY_HAND_TEXT), text)
	assert_false(text.contains("0"), "nothing on the card reads as a zero: %s" % text)


func test_a_build_that_really_takes_hours_says_how_many():
	var text := "\n".join(BlueprintPaletteModel.detail_lines("house_small", 6.0))
	assert_true(text.contains("6"), "the real requirement is on the card: %s" % text)
	assert_false(text.contains(BlueprintPaletteModel.LAID_BY_HAND_TEXT), text)


func test_the_detail_opens_with_the_buildings_own_name():
	var lines := BlueprintPaletteModel.detail_lines("brewery", 57.0)
	assert_gt(lines.size(), 0, "a known building has a card")
	assert_eq(String(lines[0]), BuildPlan.display_name_of("brewery"))


## An unknown id gets nothing rather than a guessed card -- the same
## refusal BuildPlan.footprint_cells already makes for the same reason.
func test_an_unknown_blueprint_gets_no_card_rather_than_a_guessed_one():
	assert_eq(BlueprintPaletteModel.detail_lines("not_a_building", 3.0), [])
	assert_eq(BlueprintPaletteModel.slot_subtitle("not_a_building"), "")
