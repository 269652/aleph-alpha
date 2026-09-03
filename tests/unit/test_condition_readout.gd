extends GutTest

## What the HUD tells the player is currently wrong with them.
##
## The survival bars have always shown RESERVES -- food, water, stamina,
## warmth -- which say how much of something is left, not what it is doing to
## you. Nothing on screen said you were bleeding, ill, or chilled through, and
## after the wound and cold-exposure passes a player could be walking toward
## sepsis or hypothermia with no indication at all. A live session recorded the
## same shape of complaint about the movement penalties: "the HUD does not say
## so".
##
## Pure, so the priority order is testable without standing up World -- the
## same split EscapeAction and HotkeyRouting already use.

const ConditionReadout = preload("res://src/ui/condition_readout.gd")
const WoundModel = preload("res://src/gameplay/wound_model.gd")
const ColdExposure = preload("res://src/gameplay/cold_exposure.gd")


## Nothing wrong reads as nothing at all -- an empty status line, not a line
## saying "fine". The HUD is for what needs attention.
func test_a_healthy_player_is_told_nothing():
	assert_eq(ConditionReadout.text({}), "")


func test_bleeding_is_named():
	assert_string_contains(ConditionReadout.text({"wound_stacks": 1}).to_lower(), "bleed")


func test_being_chilled_through_is_named():
	var chilled := ConditionReadout.text({"cold_exposure": ColdExposure.RISK_THRESHOLD})
	assert_ne(chilled, "")


## A chill that is still in the harmless stage is NOT worth a warning -- the
## line has to mean something, and one that is always on means nothing.
func test_an_ordinary_chill_is_not_worth_saying():
	assert_eq(ConditionReadout.text({"cold_exposure": ColdExposure.RISK_THRESHOLD * 0.5}), "")


# -- illness, and what the player is allowed to know about it ----------------


## `Sickness`'s own contract: an UNDIAGNOSED sickness must expose only its
## vague severity, never which sickness it is. The readout has to respect that
## or the HUD becomes the diagnosis, and the Herbalist loop this game is
## building has nothing left to do.
func test_an_undiagnosed_illness_does_not_name_itself():
	var text := ConditionReadout.text({"sickness_id": "hypothermia", "sickness_diagnosed": false})
	assert_ne(text, "")
	assert_false(text.to_lower().contains("hypothermia"), "the HUD diagnosed it for free")


func test_a_diagnosed_illness_is_named():
	var text := ConditionReadout.text({"sickness_id": "hypothermia", "sickness_diagnosed": true})
	assert_string_contains(text.to_lower(), "hypothermia")


# -- priority ----------------------------------------------------------------


## Several things at once are all worth saying, or the worst one hides the
## thing the player could actually act on.
func test_everything_wrong_is_reported():
	var text := ConditionReadout.text({
		"wound_stacks": 2,
		"sickness_id": "wound_infection",
		"sickness_diagnosed": true,
		"starving": true,
	})
	assert_string_contains(text.to_lower(), "bleed")
	assert_string_contains(text.to_lower(), "infection")
	assert_string_contains(text.to_lower(), "starv")


## ...but in a fixed order, worst first, so the line does not reshuffle itself
## frame to frame as conditions come and go.
func test_the_order_is_stable_and_worst_first():
	var both := ConditionReadout.text({"wound_stacks": 1, "starving": true})
	assert_lt(both.find("Bleeding"), both.find("Starving"), "a scratch outranked starvation")


## And it stays a HUD line rather than a paragraph.
func test_the_line_stays_short():
	var everything := ConditionReadout.text({
		"wound_stacks": 3,
		"sickness_id": "wound_infection",
		"sickness_diagnosed": true,
		"cold_exposure": 1.0,
		"starving": true,
		"dehydrated": true,
		"exhausted": true,
	})
	assert_lt(everything.length(), 90, "the status line became a paragraph")
