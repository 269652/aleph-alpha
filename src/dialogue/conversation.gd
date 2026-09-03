extends RefCounted

## One conversation with one villager (docs/concept/dialogue.md).
##
## The stage that was missing entirely. The pipeline ran
## `DialogueContext -> DialogueTopic -> DialogueMove` and then stopped: nothing
## anywhere turned a villager's decision into something a player could read or
## answer, so the talk key showed a one-line greeting from a lookup table while
## ~2,700 tested lines of dialogue engine sat dark.
##
## This holds the whole exchange -- which beat is on screen, what the player
## may say back, and what saying it does -- with no engine dependency, so the
## window above it is glue that renders what this decides.
##
## ## What it is not
##
## Not a script and not a tree. There is no authored branching here: the beats
## come from whatever is really true of this villager right now, re-ranked
## after every exchange, and the choices are built from the beat's own slots.
## Two conversations with the same villager an hour apart are different
## conversations because the village is different, not because a flag was set.

const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const DialogueMove = preload("res://src/dialogue/dialogue_move.gd")
const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const OfflineRenderer = preload("res://src/dialogue/offline_renderer.gd")
const NpcVoice = preload("res://src/dialogue/npc_voice.gd")
const NpcSeenLedger = preload("res://src/dialogue/npc_seen_ledger.gd")
const NpcAsk = preload("res://src/dialogue/npc_ask.gd")
const QuestOffer = preload("res://src/dialogue/quest_offer.gd")
const Contract = preload("res://src/emergence/contract.gd")

## The player's moves. Deliberately few: this is a conversation, not a menu.
## CHOICE_MORE is "and?" -- it burns the current topic and takes the next most
## salient thing, which is the mechanism that makes the scored-topic layer
## visible at all.
const CHOICE_MORE := "more"
const CHOICE_LEAVE := "leave"

## Where the player stands with this villager (see NpcRecognition). Carried on
## the conversation because every beat is rendered AT a tier -- and until
## NpcRecognition had a caller, every beat in the game was rendered at
## stranger, so a villager you had spoken to nine times greeted you exactly
## like one you had never met.
const RECOGNITION_STRANGER := DialogueBeat.RECOGNITION_STRANGER

var _frame: Dictionary = {}
var _ledger: NpcSeenLedger = null
var _bands: Dictionary = {}
var _beat: Dictionary = {}
var _recognition: String = RECOGNITION_STRANGER
var _line: String = ""
var _over := false
## Topics already said in THIS conversation. The ledger records them too (and
## survives the conversation), but a ledger decay is measured in world seconds
## and a conversation takes none -- so within one exchange this is what stops
## the same topic coming back immediately.
var _said: Dictionary = {}

## Everything this conversation needs to know about errands, or {} for a
## conversation opened without an ask context at all -- which behaves exactly
## as it did before errands existed. Same fail-open shape as every other
## source in this layer: a missing store and an empty one are one answer.
##
## Keys: contract_store, player_id, carrying (item_id -> count), item_kinds
## (item_id -> ItemCatalog kind), payer_gold (the villager's live balance).
var _asks: Dictionary = {}
## The promises that were already overdue when this conversation opened --
## quests.md's lazy deadline check, and the one place a lapse is recorded.
## Handed out so the owner can witness each as a real event.
var _lapsed: Array = []
## What the owner must actually do to the world as a result of the last
## choice: items to take out of the player's pack and gold to put in their
## wallet. Drained by take_effect, so a window that redraws cannot pay twice.
##
## This model never touches an Inventory or a Wallet itself. That is not
## fastidiousness -- it is what keeps the whole dialogue layer testable with
## no engine, and it is the same boundary that makes the documented AI seam
## safe: there is no code path from anything holding a beat to a wallet.
var _effect: Dictionary = {}


## Opens a conversation with the villager `frame` describes.
##
## `ledger` may be null -- a villager with no history and a missing ledger are
## the same state, the same fail-open shape DialogueContext uses for every
## absent source.
## Returns `RefCounted` rather than a named type: nothing under src/dialogue/
## declares a `class_name` (see NpcSeenLedger.from_dict, which does the same),
## so the script cannot name itself.
static func open(
	frame: Dictionary, ledger: NpcSeenLedger, recognition: String = RECOGNITION_STRANGER,
	asks: Dictionary = {}
) -> RefCounted:
	var talk = new()
	talk._frame = frame
	talk._ledger = ledger
	talk._recognition = recognition
	talk._asks = asks
	talk._bands = NpcVoice.register_for(frame.get("traits", {}))["bands"]
	# quests.md: "Deadline is checked LAZILY at conversation open, not by a
	# background sweep. The only observer that matters is the conversation
	# itself, so a sweep would be pure cost." Checked before the first beat,
	# so a villager whose promise you just broke greets you having noticed.
	talk._lapse_overdue()
	talk._advance()
	return talk


## What they just said.
func line() -> String:
	return _line


func speaker_name() -> String:
	return String(_frame.get("npc_name", ""))


func topic_id() -> String:
	return String(_beat.get("topic_id", ""))


## The beat on screen, for anything that wants the facts behind the sentence
## rather than the sentence (the AI seam, a quest offer, a debug overlay).
func beat() -> Dictionary:
	return _beat


func is_over() -> bool:
	return _over


## What the player may say back.
##
## Built from the beat's OWN slots -- "Ask about the three rock" -- never from
## a fixed global menu, which is what stops every villager in the world
## offering the same four options. Leaving is always available: a conversation
## you cannot end is a trap.
func choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _over:
		return out
	# The errand comes first when there is one: it is the only choice that
	# changes the world rather than the subject.
	var deliverable := _deliverable()
	if not deliverable.is_empty():
		out.append({
			"id": NpcAsk.CHOICE_DELIVER,
			"label": NpcAsk.deliver_label(NpcAsk.errand_of(deliverable["contract"])),
		})
	else:
		var offer := _open_offer()
		if not offer.is_empty():
			out.append({"id": NpcAsk.CHOICE_ACCEPT, "label": NpcAsk.accept_label(offer)})
	if not _beat.is_empty() and not topic_id().is_empty():
		out.append({"id": CHOICE_MORE, "label": _more_label()})
	out.append({"id": CHOICE_LEAVE, "label": "Take your leave."})
	return out


## Makes the player's move.
func choose(choice_id: String) -> void:
	if _over:
		return
	if choice_id == CHOICE_LEAVE:
		_over = true
		return
	if choice_id == CHOICE_MORE:
		_advance()
		return
	if choice_id == NpcAsk.CHOICE_ACCEPT:
		_take_on(_open_offer())
		return
	if choice_id == NpcAsk.CHOICE_DELIVER:
		_hand_over(_deliverable())


## The promises that were already overdue when this conversation opened, now
## recorded as real defaults. The owner witnesses each as an event: quests.md
## wants a lapse to change what OTHER people say to you, through the gossip
## network that already runs, rather than through a reputation number.
func lapsed() -> Array:
	return _lapsed


## What the owner must do to the world after the last choice, and then clear.
## {} when there is nothing to do, which is almost always.
func take_effect() -> Dictionary:
	var effect := _effect
	_effect = {}
	return effect


## The one errand this villager would raise, if it is one the player has not
## already promised and one that can actually be finished. {} otherwise --
## which is the common case, because most villagers want nothing from you.
func _open_offer() -> Dictionary:
	if _asks.is_empty():
		return {}
	for offer in QuestOffer.offers_for(_frame):
		if not NpcAsk.is_promisable(offer):
			continue
		if NpcAsk.already_promised(_contract_store(), offer, _player_id(), _now()):
			continue
		return offer
	return {}


## An open promise to this villager the player is carrying the goods for
## right now, as {"contract": Contract, "delivery": {...}}. {} otherwise.
func _deliverable() -> Dictionary:
	if _asks.is_empty():
		return {}
	var carrying: Dictionary = _asks.get("carrying", {})
	var kinds: Dictionary = _asks.get("item_kinds", {})
	for contract in NpcAsk.open_asks(_contract_store(), _npc_id(), _player_id(), _now()):
		var delivery := NpcAsk.delivery_for(NpcAsk.errand_of(contract), carrying, kinds)
		if delivery["complete"]:
			return {"contract": contract, "delivery": delivery}
	return {}


## The player promises. The conversation does not end -- there is usually
## more to say, and being dismissed the moment you agree to help reads as a
## menu closing rather than a person answering.
func _take_on(offer: Dictionary) -> void:
	if offer.is_empty():
		return
	if NpcAsk.accept(_contract_store(), offer, _player_id(), _now()) == null:
		return
	# The villager's ANSWER, and nothing else. The window shows one speaker and
	# it is them; prefixing the player's own line here made a villager read as
	# agreeing to fetch something for himself ("Rhoel: I'll bring you meat.
	# Right. Thank you."). The player's move is the button they just pressed.
	_line = OfflineRenderer.gratitude_for(_bands)


## The player hands the goods over. The reward is re-derived HERE against the
## villager's live balance (quests.md: "a villager who went broke while you
## were away pays less, and says so"), and what actually moves is reported
## rather than done -- see _effect.
func _hand_over(deliverable: Dictionary) -> void:
	if deliverable.is_empty():
		return
	var contract = deliverable["contract"]
	var settled := NpcAsk.settle(
		_contract_store(), contract, int(_asks.get("payer_gold", 0)), _now()
	)
	if int(settled.get("paid", 0)) <= 0 and contract.status != Contract.FULFILLED:
		return
	_effect = {
		"npc_id": _npc_id(),
		# Where the goods are going. Without it the owner can take the items
		# out of the player's pack and has nowhere to put them, which is
		# exactly what happened: the errand completed, the village stayed
		# short, and the same villager asked again in the same breath.
		"settlement_id": String(_frame.get("settlement_id", "")),
		"contract_id": contract.id,
		"items": deliverable["delivery"]["items"],
		"gold": int(settled["paid"]),
	}
	_line = OfflineRenderer.settlement_for(_bands, settled)


## quests.md's lazy deadline check. Runs once, at open.
func _lapse_overdue() -> void:
	if _asks.is_empty():
		return
	_lapsed = NpcAsk.lapse_overdue(_contract_store(), _npc_id(), _player_id(), _now())


func _contract_store():
	return _asks.get("contract_store")


func _player_id() -> String:
	return String(_asks.get("player_id", ""))


func _npc_id() -> String:
	return String(_frame.get("npc_id", ""))


func _now() -> float:
	return float(_frame.get("world_age_seconds", 0.0))


## The next thing this villager has to say, or the end of the conversation.
##
## Re-runs the whole ranking every time rather than walking a list built at
## open: the frame is a read of the world, and between two exchanges a
## villager can genuinely have something new to say.
func _advance() -> void:
	var topics := DialogueTopic.available_for(_frame)
	var fresh: Array = []
	for topic in topics:
		if not _said.has(String(topic.get("topic_id", ""))):
			fresh.append(topic)
	var now := float(_frame.get("world_age_seconds", 0.0))
	var move := DialogueMove.select_one(
		fresh, _ledger, String(_frame.get("npc_id", "")), now, int(_frame.get("seed_value", 0))
	)
	if move.is_empty():
		# Nothing left. Said once, plainly, and then the conversation is over
		# -- running out is an ending rather than an error, and a villager who
		# looped back to their loudest need forever would make the whole
		# scored-topic layer invisible.
		if _beat.is_empty():
			_beat = DialogueBeat.build({}, _frame, _voice_key(), _recognition)
			_line = OfflineRenderer.render(_beat, _bands)
		else:
			_line = OfflineRenderer.render(
				DialogueBeat.build({}, _frame, _voice_key(), _recognition), _bands
			)
		_over = true
		return
	_beat = DialogueBeat.build(move, _frame, _voice_key(), _recognition)
	_line = OfflineRenderer.render(_beat, _bands)
	_remember(String(move.get("topic_id", "")), now)


## Records what was said, in this conversation and in the world.
##
## The ledger is what makes the NEXT conversation start where this one left off
## rather than resetting to the loudest need again -- dialogue.md's mechanism 2.
func _remember(said_topic_id: String, now: float) -> void:
	_said[said_topic_id] = true
	if _ledger != null:
		_ledger.mark_told(String(_frame.get("npc_id", "")), said_topic_id, now)


func _voice_key() -> String:
	return NpcVoice.voice_key_for(_frame.get("traits", {}))


## "And the three rock?" rather than "Continue" -- the label names what is
## actually on the table, from the beat's own slots.
func _more_label() -> String:
	var slots: Dictionary = _beat.get("slots", {})
	var item := String(slots.get("item", ""))
	if not item.is_empty():
		var count := int(slots.get("count", 0))
		if count > 0:
			return "Ask about the %d %s." % [count, item]
		return "Ask about the %s." % item
	return "Ask what else is on their mind."
