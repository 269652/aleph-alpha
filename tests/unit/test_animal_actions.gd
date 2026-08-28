extends GutTest

## What the PRIMARY and SECONDARY action on an animal are, right now.
##
## Reported: "we should implement a primary action and secondary action feature
## ... so when the lasso is tied and player has carrot in hand the horses
## primary action should be feed (when it's tied up and hungry)".
##
## The rule underneath it: the primary action is whatever the animal's own
## state says it most needs, not a fixed verb per species. A tied, hungry horse
## wants feeding; a tame one wants riding or ordering; a loose one wants
## catching. Pure logic here so the ordering can be tested without a scene --
## the marker, the hover tooltip and the input handler all read the same list.
##
## Ordering IS the feature: index 0 is the primary, index 1 the secondary.

const AnimalActions = preload("res://src/gameplay/animal_actions.gd")
const Taming = preload("res://src/gameplay/taming.gd")

const CARROT := "carrot"
const LASSO := "lasso"


func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"species": "horse",
		"hungry": false,
		"thirsty": false,
		"cold": false,
		"trust": 0.0,
		"tame": false,
		"restrained": false,
		"tied": false,
	}
	for key in overrides:
		state[key] = overrides[key]
	return state


func _verbs(actions: Array) -> Array:
	var out := []
	for action in actions:
		out.append(action["verb"])
	return out


# -- the reported case --------------------------------------------------------

func test_a_tied_hungry_animal_offers_feed_first_when_you_are_holding_food():
	var actions := AnimalActions.for_animal(
		_state({"restrained": true, "tied": true, "hungry": true}), CARROT
	)
	assert_gt(actions.size(), 0, "a tied hungry animal should offer something")
	assert_eq(actions[0]["verb"], "Feed")


## The food has to be IN HAND. Offering "Feed" to someone holding a rope is a
## prompt they cannot act on, which is worse than no prompt.
func test_feed_is_not_offered_without_food_in_hand():
	var actions := AnimalActions.for_animal(
		_state({"restrained": true, "tied": true, "hungry": true}), LASSO
	)
	assert_false(_verbs(actions).has("Feed"))


## The rule the whole taming loop rests on: only a HUNGRY feed earns trust
## (Taming.trust_after_feeding). Offering to feed a full animal would be
## offering a no-op, and the player would rightly read the lack of progress as
## the mechanic being broken.
func test_feed_is_not_offered_to_an_animal_that_is_not_hungry():
	var actions := AnimalActions.for_animal(
		_state({"restrained": true, "tied": true, "hungry": false}), CARROT
	)
	assert_false(_verbs(actions).has("Feed"))


## Held, not yet tied, still counts -- an animal on the end of the rope is
## close enough to eat from your hand.
func test_a_led_hungry_animal_can_also_be_fed():
	var actions := AnimalActions.for_animal(
		_state({"restrained": true, "tied": false, "hungry": true}), CARROT
	)
	assert_eq(actions[0]["verb"], "Feed")


## A loose animal is not standing still to be fed; it has to be caught first.
func test_a_free_animal_is_not_offered_feeding():
	var actions := AnimalActions.for_animal(_state({"hungry": true}), CARROT)
	assert_false(_verbs(actions).has("Feed"))


# -- what else the ordering has to get right ---------------------------------

func test_a_free_animal_offers_the_lasso_when_you_are_holding_one():
	var actions := AnimalActions.for_animal(_state(), LASSO)
	assert_eq(actions[0]["verb"], "Lasso")


func test_a_free_animal_offers_nothing_you_cannot_do_empty_handed():
	assert_eq(AnimalActions.for_animal(_state(), "").size(), 0)


## A tame horse is for riding; that is the payoff the whole loop was for.
func test_a_tame_ridable_animal_offers_riding_first():
	var actions := AnimalActions.for_animal(
		_state({"tame": true, "trust": 1.0, "species": "horse"}), ""
	)
	assert_eq(actions[0]["verb"], "Ride")


## A tame animal that cannot be ridden still takes orders -- that is what being
## tame BUYS for a species that will never carry anyone.
func test_a_tame_unridable_animal_offers_orders_instead():
	var actions := AnimalActions.for_animal(
		_state({"tame": true, "trust": 1.0, "species": "sheep"}), ""
	)
	assert_gt(actions.size(), 0)
	assert_ne(actions[0]["verb"], "Ride")
	assert_true(_verbs(actions).has("Order"))


## Feeding outranks riding: a hungry animal you are holding food for is asking
## for something, and the ride will still be there afterwards.
func test_feeding_a_hungry_tame_animal_outranks_riding_it():
	var actions := AnimalActions.for_animal(
		_state({"tame": true, "trust": 1.0, "restrained": true, "hungry": true}), CARROT
	)
	assert_eq(actions[0]["verb"], "Feed")
	assert_true(_verbs(actions).has("Ride"), "riding is still offered, just second")


func test_a_held_animal_can_always_be_let_go():
	var actions := AnimalActions.for_animal(_state({"restrained": true}), "")
	assert_true(_verbs(actions).has("Release"))


## Predators are not tameable at all (Taming.can_be_tamed), so a rope is not an
## answer to one and must not be offered as though it were.
func test_a_predator_is_not_offered_the_lasso():
	var actions := AnimalActions.for_animal(_state({"species": "wolf"}), LASSO)
	assert_false(_verbs(actions).has("Lasso"))


# -- the contract the tooltip and the input handler both rely on -------------

## Every action names a real, rebindable input, or the prompt cannot show a key
## and the press cannot be routed.
func test_every_offered_action_names_a_real_rebindable_input():
	var bindings := Keybindings.new()
	var names := bindings.action_names()
	var cases := [
		[_state({"restrained": true, "tied": true, "hungry": true}), CARROT],
		[_state({"tame": true, "trust": 1.0}), ""],
		[_state(), LASSO],
		[_state({"restrained": true}), ""],
	]
	for case in cases:
		for action in AnimalActions.for_animal(case[0], case[1]):
			assert_true(
				names.has(action["action"]),
				"%s maps to '%s', which is not a rebindable action"
					% [action["verb"], action["action"]]
			)


const Keybindings = preload("res://src/gameplay/keybindings.gd")


## Two slots, and no more offered than there are keys to press them with.
func test_no_more_actions_are_offered_than_there_are_slots_to_press():
	var busiest := AnimalActions.for_animal(
		_state({"tame": true, "trust": 1.0, "restrained": true, "tied": true, "hungry": true}),
		CARROT
	)
	assert_lte(
		busiest.size(), AnimalActions.MAX_SLOTS,
		"more actions offered than the player has slots for"
	)


## The slots ARE the feature: whatever is offered first is what the primary key
## does, whatever is second is the secondary. The verbs still have their own
## dedicated keys (mount, lasso) and those keep working -- but a player should
## not have to remember which verb is on which key to do the obvious thing to
## the animal in front of them.
func test_the_first_action_is_on_the_primary_key_and_the_second_on_the_secondary():
	var actions := AnimalActions.for_animal(
		_state({"tame": true, "trust": 1.0, "restrained": true, "hungry": true}), CARROT
	)
	assert_eq(actions.size(), 2, "this case should fill both slots")
	assert_eq(actions[0]["action"], "primary_action")
	assert_eq(actions[1]["action"], "secondary_action")


func test_a_single_offered_action_sits_on_the_primary_key():
	var actions := AnimalActions.for_animal(_state(), LASSO)
	assert_eq(actions[0]["action"], "primary_action")
