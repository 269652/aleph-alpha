extends GutTest

## The nearby-creature card. Reported live: "it's neither visible from the
## horses panel nor in hover or extra panel what the horses states are
## (hunger / cold / trust / thirst)" -- the card showed a name, a level and an
## HP bar, and nothing else, for an animal whose hunger was the one fact that
## decided whether the player's next action would do anything.
##
## Condition shows for animals the player has a STAKE in, not for every sheep
## in the meadow: five wild animals wander into range at once (observed live --
## a column of near-identical cards), and giving each of them four extra bars
## would bury the one card that matters under the ones that do not. The
## predicate is CreatureMarker.is_player_invested, the same line already used
## to decide what the aggregate model may cull.

const CreaturePanel = preload("res://scenes/creature_panel.gd")

var panel: CreaturePanel


func before_each():
	panel = CreaturePanel.new()
	add_child_autofree(panel)


func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"name": "Horse",
		"species": "horse",
		"level": 3,
		"health_fraction": 1.0,
		"fullness": 1.0,
		"hydration": 1.0,
		"warmth": 1.0,
		"hungry": false,
		"thirsty": false,
		"cold": false,
		"trust": 0.0,
		"tame": false,
		"restrained": false,
		"tied": false,
		"sick": false,
		"invested": false,
	}
	for key in overrides:
		state[key] = overrides[key]
	return state


func test_a_wild_animal_still_shows_its_name_and_level():
	panel.set_state(_state())
	assert_string_contains(panel.headline(), "Horse")
	assert_string_contains(panel.headline(), "3")


## The HUD stays readable with a meadow's worth of wildlife in range.
func test_a_wild_animal_shows_no_condition_rows():
	panel.set_state(_state())
	assert_false(panel.shows_condition())


func test_an_animal_you_have_a_stake_in_shows_its_condition():
	panel.set_state(_state({"invested": true, "restrained": true}))
	assert_true(panel.shows_condition())


## The four things the report asked for, by name.
func test_the_condition_covers_trust_food_water_and_warmth():
	panel.set_state(_state({"invested": true, "trust": 0.4, "fullness": 0.3,
		"hydration": 0.2, "warmth": 0.1}))
	var text := panel.condition_text()
	for label in ["Trust", "Food", "Water", "Warmth"]:
		assert_string_contains(text, label)


## A number, not just a bar: "how hungry exactly" is what decides whether the
## player waits or feeds, and a short bar is not readable to a percentage.
func test_condition_reads_as_percentages():
	panel.set_state(_state({"invested": true, "trust": 0.4}))
	assert_string_contains(panel.condition_text(), "40%")


## The verdicts that change what the player should DO are called out, because
## a bar at 45% and a bar at 55% look identical and mean opposite things --
## only a hungry animal can be fed toward trust at all.
func test_a_hungry_animal_says_so_in_words():
	panel.set_state(_state({"invested": true, "hungry": true, "fullness": 0.1}))
	assert_string_contains(panel.condition_text().to_lower(), "hungry")


func test_a_cold_animal_says_so_in_words():
	panel.set_state(_state({"invested": true, "cold": true, "warmth": 0.1}))
	assert_string_contains(panel.condition_text().to_lower(), "cold")


func test_a_healthy_kept_animal_is_not_nagging_about_anything():
	panel.set_state(_state({"invested": true}))
	var text := panel.condition_text().to_lower()
	for complaint in ["hungry", "thirsty", "cold", "sick"]:
		assert_false(text.contains(complaint), "a comfortable animal should not report '%s'" % complaint)
