extends GutTest

## The house readout says what STANDING the household holds and which way
## it is going (docs/concept/village_estates.md mechanisms 1 and 3).
##
## This is the Anno-shaped surface of the whole overhaul: a player looks at
## a house and sees what it is, what it is short of, and whether it is
## about to rise. Everything on it is derived at the moment it is asked
## for, from state the simulation already keeps -- the readout is a
## consumer, never a driver, exactly as village_growth.md's pillar 6 says.

const HousePanel = preload("res://scenes/house_panel.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const EstateAscension = preload("res://src/emergence/estate_ascension.gd")

var panel: HousePanel


func before_each():
	panel = HousePanel.new()
	add_child(panel)


func after_each():
	panel.free()


func _home(overrides: Dictionary) -> Dictionary:
	var report := {
		"is_home": true,
		"display_name": "Cottage",
		"resident_name": "Bren",
		"resident_occupation": "hunter",
		"estate": "kossaet",
		"estate_verdict": EstateAscension.HOLD,
		"needs": {},
		"happiness": 0.5,
		"productivity": 0.5,
		"wallet_balance": 3,
	}
	report.merge(overrides, true)
	return report


# -- every estate has a name a player can read ----------------------------

func test_every_estate_has_a_readable_english_name():
	for estate in VillageEstates.ESTATE_IDS:
		var name: String = VillageEstates.display_name_of(estate)
		assert_ne(name, "", "%s has no name a player could read" % estate)
		assert_ne(name, estate, "%s is shown to players by its own id" % estate)


func test_an_unknown_estate_has_no_name_rather_than_a_made_up_one():
	assert_eq(VillageEstates.display_name_of("emperor"), "")


# -- the subtitle carries the standing ------------------------------------

func test_a_home_shows_its_households_standing_beside_its_resident():
	panel.show_report(_home({}))
	assert_string_contains(panel.subtitle_text(), VillageEstates.display_name_of("kossaet"))
	assert_string_contains(panel.subtitle_text(), "Bren")


func test_a_home_whose_standing_is_unknown_still_shows_its_resident():
	panel.show_report(_home({"estate": ""}))
	assert_string_contains(panel.subtitle_text(), "Bren")


## A commons has no household and therefore no standing to show.
func test_a_commons_shows_no_standing():
	panel.show_report({"is_home": false, "display_name": "Sawmill", "settlement_productivity": 0.8})
	for estate in VillageEstates.ESTATE_IDS:
		assert_false(
			panel.subtitle_text().contains(VillageEstates.display_name_of(estate)),
			"a works was given a social standing"
		)


# -- and which way it is going --------------------------------------------

## The line a player actually watches: a house that is about to rise says
## so, and says what it is rising to.
func test_a_rising_household_says_what_it_is_rising_to():
	panel.show_report(_home({"estate_verdict": EstateAscension.ASCEND}))
	assert_string_contains(panel.standing_text(), VillageEstates.display_name_of("bauer"))


func test_a_falling_household_says_what_it_is_falling_to():
	panel.show_report(_home({"estate": "handwerker", "estate_verdict": EstateAscension.DESCEND}))
	assert_string_contains(panel.standing_text(), VillageEstates.display_name_of("bauer"))


## The bottom rung has nowhere to fall to, so it is leaving -- and the
## readout must say THAT rather than naming an estate that does not exist.
func test_a_cottager_that_is_falling_is_leaving_the_village():
	panel.show_report(_home({"estate": "kossaet", "estate_verdict": EstateAscension.DESCEND}))
	assert_string_contains(panel.standing_text().to_lower(), "leaving")
	for estate in VillageEstates.ESTATE_IDS:
		assert_false(
			panel.standing_text().contains(VillageEstates.display_name_of(estate)),
			"a departing cottager was told which estate it was falling into"
		)


func test_a_settled_household_says_nothing_dramatic():
	panel.show_report(_home({"estate_verdict": EstateAscension.HOLD}))
	assert_false(panel.standing_text().to_lower().contains("leaving"))
	assert_ne(panel.standing_text(), "", "a settled household said nothing at all")


func test_the_top_rung_holding_is_not_told_it_is_rising():
	panel.show_report(_home({"estate": "buerger", "estate_verdict": EstateAscension.HOLD}))
	assert_false(panel.standing_text().to_lower().contains("rising"))


func test_a_commons_has_no_standing_line_at_all():
	panel.show_report({"is_home": false, "display_name": "Sawmill", "settlement_productivity": 0.8})
	assert_eq(panel.standing_text(), "")


## The readout reads and never writes: showing it twice says the same thing
## and changes nothing about the report it was handed.
func test_the_readout_never_changes_what_it_was_handed():
	var report := _home({})
	var before := report.duplicate(true)
	panel.show_report(report)
	panel.show_report(report)
	assert_eq(report, before, "the readout wrote back into its own report")
