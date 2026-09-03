extends GutTest

## The errand reaching the player: a villager asking, the player promising,
## and the goods actually changing hands.
##
## This is the stage docs/concept/quests.md means by "a quest actually
## reaches a player -- not a quest log, not an exclamation mark, but a
## villager saying what they are short of." QuestOffer/NpcAsk are pure and
## tested on their own; what is tested here is that they are REACHABLE, that
## a promise made in a conversation is written to the real ContractStore, and
## that the conversation itself never moves an item or a coin -- it reports
## what should change, and its owner does it.

const Conversation = preload("res://src/dialogue/conversation.gd")
const NpcAsk = preload("res://src/dialogue/npc_ask.gd")
const QuestOffer = preload("res://src/dialogue/quest_offer.gd")
const QuestReward = preload("res://src/dialogue/quest_reward.gd")
const Contract = preload("res://src/emergence/contract.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")

const PLAYER := "player:local"

var store


func before_each():
	store = ContractStore.new()


func _frame(overrides: Dictionary = {}) -> Dictionary:
	var frame := {
		"npc_id": "npc:7",
		"seed_value": 7,
		"npc_name": "Bren",
		"occupation": "blacksmith",
		"traits": {},
		"is_producer": true,
		"is_hungry": false,
		"meal_available": true,
		"wallet_gold": 200,
		"snow_depth": 0.0,
		"household_id": "household:7",
		"settlement_id": "settlement:1",
		"household_recipe_id": "stone_pickaxe",
		"shortfall_missing": [{"item_id": "rock", "need": 3}],
		"world_age_seconds": 100.0,
	}
	for key in overrides:
		frame[key] = overrides[key]
	return frame


func _asks(overrides: Dictionary = {}) -> Dictionary:
	var asks := {
		"contract_store": store,
		"player_id": PLAYER,
		"carrying": {},
		"item_kinds": {},
		"payer_gold": 200,
	}
	for key in overrides:
		asks[key] = overrides[key]
	return asks


func _open(frame_overrides: Dictionary = {}, ask_overrides: Dictionary = {}):
	return Conversation.open(
		_frame(frame_overrides), null, Conversation.RECOGNITION_STRANGER, _asks(ask_overrides)
	)


func _choice_ids(talk) -> Array:
	var out: Array = []
	for choice in talk.choices():
		out.append(choice["id"])
	return out


func _label_of(talk, choice_id: String) -> String:
	for choice in talk.choices():
		if choice["id"] == choice_id:
			return String(choice["label"])
	return ""


# -- the ask reaches the player ---------------------------------------------


func test_a_villager_short_of_something_offers_you_the_errand():
	assert_true(_choice_ids(_open()).has(NpcAsk.CHOICE_ACCEPT))


## Named from the offer's own slots, not "Accept quest".
func test_the_errand_names_what_is_actually_wanted():
	var label := _label_of(_open(), NpcAsk.CHOICE_ACCEPT)
	assert_string_contains(label, "3")
	assert_string_contains(label, "rock")


func test_a_villager_with_nothing_wrong_offers_no_errand():
	var talk = _open({"shortfall_missing": []})
	assert_false(_choice_ids(talk).has(NpcAsk.CHOICE_ACCEPT))


## Leaving is always available -- an errand must never turn a conversation
## into something you cannot walk out of.
func test_you_can_always_walk_away_from_an_ask():
	assert_true(_choice_ids(_open()).has(Conversation.CHOICE_LEAVE))


## A conversation opened with no ask context at all behaves exactly as it did
## before errands existed: same fail-open shape as every other source here.
func test_a_conversation_with_no_ask_context_is_unchanged():
	var talk = Conversation.open(_frame(), null)
	assert_ne(talk.line(), "")
	assert_false(_choice_ids(talk).has(NpcAsk.CHOICE_ACCEPT))


# -- promising ---------------------------------------------------------------


func test_accepting_writes_a_real_contract():
	var talk = _open()
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	var contracts = store.contracts_for(PLAYER)
	assert_eq(contracts.size(), 1)
	assert_eq(contracts[0].status, Contract.ACTIVE)
	assert_eq(NpcAsk.errand_of(contracts[0])["subject"], "rock")


func test_accepting_says_something_back():
	var talk = _open()
	var before: String = talk.line()
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	assert_ne(talk.line(), before)
	assert_ne(talk.line(), "")


## An ask you have already taken must not be offered again -- the offer id is
## derived from the shortage, so the same shortage is the same promise.
func test_an_errand_already_promised_is_not_offered_again():
	var talk = _open()
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	assert_false(_choice_ids(_open()).has(NpcAsk.CHOICE_ACCEPT))


func test_accepting_does_not_end_the_conversation():
	var talk = _open()
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	assert_false(talk.is_over())


## An errand with no completion path is never a promise (see NpcAsk's
## is_promisable) -- a remembered raid is directions, not a debt.
func test_an_errand_that_cannot_be_finished_is_never_offered_as_a_promise():
	var talk = _open({"shortfall_missing": []})
	assert_false(_choice_ids(talk).has(NpcAsk.CHOICE_ACCEPT))


# -- delivering --------------------------------------------------------------


func test_carrying_what_you_promised_offers_to_hand_it_over():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var back = _open({}, {"carrying": {"rock": 5}})
	assert_true(_choice_ids(back).has(NpcAsk.CHOICE_DELIVER))
	assert_string_contains(_label_of(back, NpcAsk.CHOICE_DELIVER), "rock")


func test_turning_up_empty_handed_offers_nothing_to_hand_over():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	assert_false(_choice_ids(_open({}, {"carrying": {"rock": 1}})).has(NpcAsk.CHOICE_DELIVER))


func test_nothing_is_delivered_that_was_never_promised():
	assert_false(_choice_ids(_open({}, {"carrying": {"rock": 5}})).has(NpcAsk.CHOICE_DELIVER))


## The conversation is a model, not a scene: it never touches an Inventory or
## a Wallet. It reports exactly what should change hands and its owner does
## it -- the same split that keeps this whole layer testable headlessly.
func test_handing_it_over_reports_what_changes_hands_and_moves_nothing_itself():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var back = _open({}, {"carrying": {"rock": 5}, "payer_gold": 200})
	back.choose(NpcAsk.CHOICE_DELIVER)

	var effect: Dictionary = back.take_effect()
	assert_eq(effect["items"], {"rock": 3})
	assert_eq(effect["gold"], QuestReward.full_gold_for(3))
	assert_eq(effect["npc_id"], "npc:7")


func test_handing_it_over_fulfils_the_contract():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var back = _open({}, {"carrying": {"rock": 5}})
	back.choose(NpcAsk.CHOICE_DELIVER)
	assert_eq(store.contracts_for(PLAYER)[0].status, Contract.FULFILLED)


## quests.md's derived-reward claim, end to end: the offer said one number
## and the villager pays what they actually have when you come back.
func test_a_villager_who_went_broke_pays_what_they_have_when_you_return():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var back = _open({"wallet_gold": 1}, {"carrying": {"rock": 5}, "payer_gold": 1})
	back.choose(NpcAsk.CHOICE_DELIVER)
	assert_eq(back.take_effect()["gold"], 1)


## The effect is drained, so a window that redraws twice cannot pay twice.
func test_the_effect_is_taken_once():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var back = _open({}, {"carrying": {"rock": 5}})
	back.choose(NpcAsk.CHOICE_DELIVER)
	assert_false(back.take_effect().is_empty())
	assert_true(back.take_effect().is_empty())


# -- lapsing -----------------------------------------------------------------


## quests.md: the deadline is checked lazily AT CONVERSATION OPEN, because
## the conversation is the only observer that matters.
func test_a_promise_left_too_long_has_lapsed_by_the_time_you_speak_again():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var late := 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0
	var back = _open({"world_age_seconds": late}, {"carrying": {"rock": 5}})
	assert_eq(back.lapsed().size(), 1)
	assert_eq(store.contracts_for(PLAYER)[0].status, Contract.DEFAULTED)


func test_a_lapsed_promise_cannot_be_delivered_on():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var late := 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0
	var back = _open({"world_age_seconds": late}, {"carrying": {"rock": 5}})
	assert_false(_choice_ids(back).has(NpcAsk.CHOICE_DELIVER))


## Once it has lapsed the shortage is still real, so the villager asks again
## -- the promise broke, the need did not.
func test_the_need_outlives_the_broken_promise():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var late := 100.0 + QuestOffer.DEADLINE_SECONDS + 1.0
	assert_true(_choice_ids(_open({"world_age_seconds": late})).has(NpcAsk.CHOICE_ACCEPT))


func test_a_promise_still_in_time_has_not_lapsed():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	assert_eq(_open().lapsed().size(), 0)


# -- whose words are on screen ----------------------------------------------


## The window shows ONE speaker, and it is the villager. Found by playing:
## agreeing to fetch meat produced `Rhoel: "I'll bring you meat. Right. Thank
## you."` -- the player's own line, under the villager's name, so Rhoel read
## as agreeing to bring himself meat. The player's move is the BUTTON they
## just pressed; the line is the answer to it.
func test_the_villager_does_not_repeat_the_players_own_line_back():
	var talk = _open()
	var label := _label_of(talk, NpcAsk.CHOICE_ACCEPT)
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	assert_false(
		String(talk.line()).contains(label),
		"the villager is saying the player's line: %s" % talk.line()
	)


func test_the_villager_still_answers_when_you_agree():
	var talk = _open()
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	assert_ne(talk.line(), "")


# -- the goods have to actually arrive --------------------------------------


## Found by playing: handing over the meat fulfilled the contract, paid what
## the villager had, took the item out of the pack -- and the villager asked
## for it again immediately, because nothing put it into the settlement's
## stock. quests.md's first pillar cuts both ways: a quest is a projection of
## a real shortage, so a delivery that does not change the real shortage is
## not a delivery, it is an infinite errand.
##
## The effect has to name where the goods are going, or its owner cannot put
## them anywhere.
func test_a_delivery_names_the_settlement_the_goods_are_going_to():
	_open().choose(NpcAsk.CHOICE_ACCEPT)
	var back = _open({}, {"carrying": {"rock": 5}})
	back.choose(NpcAsk.CHOICE_DELIVER)
	assert_eq(String(back.take_effect()["settlement_id"]), "settlement:1")


## Promising and delivering in the SAME conversation, which is what happens
## when the player already has the goods on them when they are first asked.
## The choices are recomputed on every call, so the promise made a moment ago
## has to be visible to the delivery check immediately.
func test_you_can_hand_it_over_in_the_same_conversation_you_promised_it():
	var talk = _open({}, {"carrying": {"rock": 5}})
	talk.choose(NpcAsk.CHOICE_ACCEPT)
	assert_true(
		_choice_ids(talk).has(NpcAsk.CHOICE_DELIVER),
		"carrying what was just promised, and no way to hand it over"
	)
