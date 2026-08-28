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
const CaptureTool = preload("res://src/gameplay/capture_tool.gd")

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


## The RIGHT tool, not just any tool. Since "any animal, the right tool"
## landed, capture-class is read off the body plan -- a serpent needs a snare,
## a mouse a trap -- so offering a catch while holding the wrong one would
## promise something that cannot happen.
func test_the_wrong_tool_is_not_offered_as_a_catch():
	var snake := _state({"species": "venomous_snake"})
	assert_false(
		_verbs(AnimalActions.for_animal(snake, LASSO)).has("Snare"),
		"a rope is not a snare"
	)
	assert_eq(AnimalActions.for_animal(snake, LASSO).size(), 0)


func test_the_right_tool_is_offered_and_named_after_itself():
	var snake := _state({"species": "venomous_snake"})
	var actions := AnimalActions.for_animal(snake, CaptureTool.SNARE)
	assert_gt(actions.size(), 0, "the right tool should offer the catch")
	assert_eq(actions[0]["verb"], "Snare", "the prompt should name the tool in hand")


## A world boss stays refused whatever is in hand -- Taming.can_be_tamed keeps
## that exclusion on purpose, and the offer follows it rather than second-
## guessing it.
func test_a_world_boss_is_never_offered_a_catch():
	for tool in [LASSO, CaptureTool.SNARE, CaptureTool.REINFORCED_ROPE]:
		assert_eq(AnimalActions.for_animal(_state({"species": "krampus"}), tool).size(), 0)


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


# -- the ordering is SCORED, not a ladder ------------------------------------
#
# Reported: the primary/secondary slots should be filled "by a generic
# mechanism which scores priority on context / item relevance".
#
# The first version was an if/else ladder, which meant every new verb had to be
# hand-placed against every existing one and the reasoning lived in the order
# of the branches. Now each candidate scores itself from two things a player
# can actually see -- how relevant what they are HOLDING is, and how badly the
# animal NEEDS it -- and the slots are just the top two.
#
# The tests pin ORDERINGS, never the numbers: which action wins in a given
# situation is the design, the arithmetic that produces it is not.

func test_scores_are_reported_so_the_ordering_can_be_explained():
	var scored := AnimalActions.scored_for(
		_state({"restrained": true, "hungry": true}), CARROT
	)
	assert_gt(scored.size(), 0)
	for entry in scored:
		assert_true(entry.has("score"), "every candidate should carry the score that ranked it")
		assert_true(entry.has("why"), "and why it scored -- an unexplainable ordering is untunable")


## Item relevance: the same animal, the same needs, different thing in hand.
## What you are holding is the strongest signal about what you mean to do.
func test_what_you_hold_changes_what_ranks_first():
	var animal := _state({"restrained": true, "hungry": true})
	assert_eq(AnimalActions.for_animal(animal, CARROT)[0]["verb"], "Feed")
	assert_ne(AnimalActions.for_animal(animal, "")[0]["verb"], "Feed")


## Need urgency: a starving animal wants feeding more than a peckish one, so
## feeding climbs as hunger does. Pinned as the RELATIONSHIP, not a threshold.
func test_a_hungrier_animal_ranks_feeding_higher():
	var peckish := _state({"restrained": true, "hungry": true, "hunger_urgency": 0.55})
	var starving := _state({"restrained": true, "hungry": true, "hunger_urgency": 1.0})
	assert_gt(
		AnimalActions.score_of("Feed", starving, CARROT),
		AnimalActions.score_of("Feed", peckish, CARROT),
		"a starving animal should want the carrot more"
	)


## An action the player cannot carry out scores nothing at all, rather than
## scoring low -- a prompt they will press and watch fail is worse than silence.
func test_an_impossible_action_scores_nothing():
	assert_eq(AnimalActions.score_of("Feed", _state({"restrained": true, "hungry": true}), ""), 0.0)
	assert_eq(AnimalActions.score_of("Ride", _state({"tame": false}), ""), 0.0)


## The reported case, now as a consequence of the scoring rather than a branch:
## holding food for a tied hungry animal beats every other thing you could do
## to it, including riding it.
func test_feeding_outranks_riding_for_a_hungry_tame_mount():
	var mount := _state({"tame": true, "trust": 1.0, "restrained": true, "hungry": true})
	assert_gt(
		AnimalActions.score_of("Feed", mount, CARROT),
		AnimalActions.score_of("Ride", mount, CARROT)
	)


## And the other way round once it is fed: nothing is asking for anything, so
## the payoff verb takes the slot.
func test_riding_outranks_everything_once_the_animal_is_content():
	var mount := _state({"tame": true, "trust": 1.0, "restrained": true, "hungry": false})
	assert_eq(AnimalActions.for_animal(mount, CARROT)[0]["verb"], "Ride")


## Ranking must be total and stable: two runs of the same situation cannot
## disagree about which key does what.
func test_the_same_situation_always_ranks_the_same_way():
	var animal := _state({"tame": true, "trust": 1.0, "restrained": true, "hungry": true})
	var first := AnimalActions.for_animal(animal, CARROT)
	for _i in 5:
		var again := AnimalActions.for_animal(animal, CARROT)
		assert_eq(again.size(), first.size())
		for i in first.size():
			assert_eq(again[i]["verb"], first[i]["verb"], "ranking flipped between identical calls")
