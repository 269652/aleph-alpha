extends GutTest

## SettlementReadout: the lines the settlement card shows (see
## docs/concept/hud.md "The settlement card").
##
## Pure: every fact is passed in rather than read from a live world, the
## same "pure model, thin Node" split AudioDiagnostics and HouseholdWellbeing
## already use -- so every branch, including the ones a player would have to
## found a city to reach, is testable headlessly.

const SettlementReadout = preload("res://src/ui/settlement_readout.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")


func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"tier": SettlementTier.TOWN,
		"households": 4,
		"housed": 3,
		"villagers": 5,
		"happiness": 0.68,
		"needs": {"food": 0.2, "shelter": 0.9, "work": 0.8, "income": 0.7, "community": 0.6},
		"gold": 12,
		"feeds": 6,
		"building": "house_small",
	}
	for key in overrides:
		state[key] = overrides[key]
	return state


func _line_starting(lines: Array, prefix: String) -> String:
	for line in lines:
		if String(line).begins_with(prefix):
			return String(line)
	return ""


# -- the title is the real tier, not the word "village" --------------------

func test_the_title_is_the_settlements_own_tier():
	for tier in SettlementTier.TIERS:
		assert_eq(
			SettlementReadout.title_for(_state({"tier": tier})), tier.capitalize(),
			"the card must say what the simulation classifies it as"
		)


func test_an_unknown_tier_still_titles_the_card():
	assert_ne(SettlementReadout.title_for(_state({"tier": ""})), "")


# -- the rows ---------------------------------------------------------------

func test_every_row_is_a_non_empty_line():
	for line in SettlementReadout.lines_for(_state()):
		assert_ne(String(line).strip_edges(), "", "a blank row would be a gap in the card")


func test_population_reports_households_and_how_many_are_housed():
	var line := _line_starting(SettlementReadout.lines_for(_state()), "Population")
	assert_string_contains(line, "4")
	assert_string_contains(line, "3", "the housed count belongs beside the population")


func test_happiness_is_a_percentage():
	var line := _line_starting(SettlementReadout.lines_for(_state({"happiness": 0.68})), "Happiness")
	assert_string_contains(line, "68")


func test_happiness_names_its_weakest_need_beside_it():
	# One blended percentage of five weighted needs tells a player nothing
	# about what to do; the per-need numbers are already computed to make
	# the blend, so naming the worst one costs nothing and turns a score
	# into a prompt.
	var line := _line_starting(SettlementReadout.lines_for(_state()), "Happiness")
	assert_string_contains(line, "food", "the weakest need was not named")


func test_the_weakest_need_really_is_the_lowest_one():
	var state := _state({
		"needs": {"food": 0.9, "shelter": 0.9, "work": 0.1, "income": 0.8, "community": 0.7}
	})
	var line := _line_starting(SettlementReadout.lines_for(state), "Happiness")
	assert_string_contains(line, "work")
	assert_false(line.contains("food"), "a need that is not the weakest was named")


func test_gold_is_reported():
	assert_string_contains(_line_starting(SettlementReadout.lines_for(_state()), "Gold"), "12")


func test_food_is_reported_as_how_many_households_it_can_feed():
	# SettlementFood.carrying_capacity is the real number the simulation
	# already assesses a settlement by -- how many households its food can
	# support. A raw stock figure would be a second, weaker number invented
	# for this card.
	var line := _line_starting(SettlementReadout.lines_for(_state({"feeds": 6, "households": 4})), "Food")
	assert_string_contains(line, "6")
	assert_string_contains(line, "4")


func test_food_that_cannot_feed_the_village_is_still_reported_plainly():
	var line := _line_starting(SettlementReadout.lines_for(_state({"feeds": 1, "households": 9})), "Food")
	assert_string_contains(line, "1")
	assert_string_contains(line, "9")


func test_what_is_being_built_is_reported():
	var line := _line_starting(SettlementReadout.lines_for(_state()), "Building")
	assert_ne(line, "")
	assert_string_contains(line.to_lower(), "cottage", "the row should name the building, not its id")


func test_building_nothing_says_so_rather_than_showing_an_empty_row():
	var line := _line_starting(SettlementReadout.lines_for(_state({"building": ""})), "Building")
	assert_ne(line.strip_edges(), "Building")


# -- unknown is not zero ----------------------------------------------------

func test_an_unassessed_settlement_reads_as_unknown_not_as_misery():
	# A village whose households have not been assessed yet is a real
	# state, and showing 0% happiness for it is a lie a player would act on.
	var line := _line_starting(SettlementReadout.lines_for(_state({"happiness": -1.0})), "Happiness")
	assert_false(line.contains("0%"), "an unassessed settlement was reported as 0%% happy")
	assert_string_contains(line.to_lower(), "—" if line.contains("—") else "unknown")


func test_the_needs_being_absent_does_not_break_the_happiness_row():
	var line := _line_starting(SettlementReadout.lines_for(_state({"needs": {}})), "Happiness")
	assert_ne(line.strip_edges(), "")


func test_the_model_is_pure():
	assert_eq(SettlementReadout.lines_for(_state()), SettlementReadout.lines_for(_state()))


func test_the_need_ids_are_the_wellbeing_models_own():
	# If HouseholdWellbeing grows a sixth need, this card must not quietly
	# keep reporting five.
	for need_id in HouseholdWellbeing.NEED_IDS:
		assert_true(
			SettlementReadout.NEED_LABELS.has(need_id),
			"need '%s' has no label, so it can never be named as the weakest" % need_id
		)


func test_the_row_count_matches_what_is_actually_produced():
	# The card builds ROW_COUNT labels once and never rebuilds them, so a
	# row added to lines_for without updating this would simply never be
	# drawn -- invisible, rather than broken.
	assert_eq(SettlementReadout.lines_for(_state()).size(), SettlementReadout.ROW_COUNT)
