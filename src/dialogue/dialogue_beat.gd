extends RefCounted

## One sentence's worth of decision, as a flat Dictionary
## (docs/concept/dialogue.md, "The beat contract").
##
## The pipeline's output, and deliberately an explicit contract rather than an
## ad-hoc bundle, for the two reasons the doc gives: it is what the renderer
## consumes, and it is the ONLY surface a future AI layer would ever touch.
##
## ## Why `template` and `slots` are separate
##
## Quantities and names live in `slots` and are substituted **by the core**;
## they are never written into the sentence by whatever produced it. That one
## separation is what makes the AI seam safe: a model is handed a beat and
## returns a rephrasing of `template` with the placeholders still in it, so it
## cannot change a number, a name or a price -- only the wording around them.
## `required_slots` is what lets a returned string that dropped a placeholder
## be REJECTED rather than rendered with a hole in it.
##
## A beat is not told what to say, who to say it about, or whether to offer
## anything. All of that has already been decided by DialogueContext,
## DialogueTopic and DialogueMove before this module sees it.

const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")

## What kind of move this beat is. The roster dialogue.md names.
const KIND_GREET := "greet"
const KIND_ANSWER := "answer"
const KIND_ASK := "ask"
const KIND_ASK_DETAIL := "ask_detail"
const KIND_DEFLECT := "deflect"
const KIND_FAREWELL := "farewell"

## How well this villager knows the player. Mirrors NpcRecognition's tiers;
## carried on the beat because the renderer's opener depends on it ("Like I
## said --" is only available to someone who has said something before).
const RECOGNITION_STRANGER := "stranger"

## Topics whose facts are a REQUEST rather than a report. A villager short of
## something is asking for it, and the renderer and the choice labels both
## need to know that this beat wants an answer.
const ASKING_TOPICS := {
	DialogueTopic.TOPIC_HOUSEHOLD_ASK: true,
}

## Which fact keys become sentence slots, and under which slot name.
##
## Deliberately a small fixed set (dialogue.md's contract names item, count,
## place, name): a slot is something a sentence has a hole for, not every fact
## the topic gathered. The rest travel in `facts` for the renderer to band on
## without being interpolated anywhere.
const SLOT_SOURCES := {
	"count": ["units_short", "short_by", "missing_count", "count"],
	"item": ["item_id", "produces_item_id", "specialization", "item"],
	"place": ["place", "work_location", "settlement_id"],
}

## Fact keys holding a LIST of shortfall entries (`{item_id, need}`, as
## Quest._missing_inputs builds them). The first entry names the item a
## request is about -- "we're short three rock" is about the rock, and the
## rest of the list is what `facts` carries for anything that wants it.
const SHORTFALL_LIST_KEYS := ["missing", "shortfall_missing"]

## Fact keys whose VALUE is a continuous number, and the band edges each is
## reported at.
##
## The fact band is the situation half of the cache key, so it has to be
## coarse: a band per exact gold piece would give one cache entry per beat and
## bake nothing reusable. Thirds -- "none / some / most" -- is the coarsest
## split that still separates a village that is coping from one that is not.
const BAND_LOW := 0.34
const BAND_HIGH := 0.67


## The beat for one move.
##
## `move` may be empty -- a villager with nothing to say is a real answer, not
## an error (dialogue.md pillar 2) -- and yields a deflect with no facts.
static func build(
	move: Dictionary, frame: Dictionary, voice_key: String, recognition: String
) -> Dictionary:
	var speaker := {
		"name": String(frame.get("npc_name", "")),
		"occupation": String(frame.get("occupation", "")),
		"recognition": recognition,
		# Which names this villager may use for the player. Empty for a
		# stranger: someone who has never been told your name cannot use it,
		# and that is a rule about the world rather than about phrasing.
		"allowed_names": [],
	}
	if move.is_empty():
		return {
			"kind": KIND_DEFLECT,
			"topic_id": "",
			"voice_key": voice_key,
			"fact_band": "",
			"speaker": speaker,
			"facts": [],
			"slots": {},
			"required_slots": [],
			"required_lexemes": [],
			"template": "",
			"repeat": false,
			"variant_seed": 0,
		}

	var topic_id := String(move.get("topic_id", ""))
	var facts: Dictionary = move.get("topic", {}).get("facts", {})
	var slots := slots_for(facts, frame)
	var template := template_for(topic_id, slots)
	return {
		"kind": kind_for(topic_id),
		"topic_id": topic_id,
		"voice_key": voice_key,
		"fact_band": fact_band_for(topic_id, facts),
		"speaker": speaker,
		"facts": facts_list(facts),
		"slots": slots,
		"required_slots": required_slots_in(template),
		# Words the phrasing must keep whatever else it changes -- the ones
		# that carry the meaning rather than the tone. A rephrasing that drops
		# "short" from a request for help has changed the game state as far as
		# the player is concerned.
		"required_lexemes": required_lexemes_for(topic_id),
		"template": template,
		"repeat": bool(move.get("repeat", false)),
		"variant_seed": int(move.get("variant_seed", 0)),
	}


## What a beat about this topic is doing.
static func kind_for(topic_id: String) -> String:
	return KIND_ASK if ASKING_TOPICS.has(topic_id) else KIND_ANSWER


## The sentence's holes, filled from the topic's own facts.
##
## Only the fixed slot roster is extracted; everything else stays in `facts`.
## A slot missing from the facts is simply absent, and `template_for` then
## picks a shape that does not need it -- rather than a sentence with an empty
## hole in it.
static func slots_for(facts: Dictionary, frame: Dictionary) -> Dictionary:
	var slots := {}
	for slot_name in SLOT_SOURCES:
		for fact_key in SLOT_SOURCES[slot_name]:
			if not facts.has(fact_key):
				continue
			var value = facts[fact_key]
			# A slot is a hole in a sentence, so only a scalar can fill one.
			# Anything structured stays in `facts`.
			if value is Array or value is Dictionary:
				continue
			slots[slot_name] = value
			break
	# A request names the item it is about, which lives in the first entry of
	# the shortfall list rather than as a fact of its own.
	for list_key in SHORTFALL_LIST_KEYS:
		var entries = facts.get(list_key, [])
		if entries is Array and not entries.is_empty() and entries[0] is Dictionary:
			if not slots.has("item"):
				slots["item"] = str(entries[0].get("item_id", ""))
			if not slots.has("count"):
				slots["count"] = int(entries[0].get("need", 0))
			break
	# `{name}` means the person being TALKED ABOUT -- the neighbour topic is the
	# one that uses it, and with the speaker's own name in the slot Joric would
	# say "You'll have met Joric, then." The facts win; the speaker is only the
	# fallback, so a template that wants a name always has one.
	if facts.has("name") and not String(facts["name"]).is_empty():
		slots["name"] = String(facts["name"])
	elif not String(frame.get("npc_name", "")).is_empty():
		slots["name"] = String(frame.get("npc_name", ""))
	return slots


## Every `{slot}` the template actually uses.
static func required_slots_in(template: String) -> Array[String]:
	var found: Array[String] = []
	var rest := template
	while true:
		var open := rest.find("{")
		if open < 0:
			break
		var close := rest.find("}", open)
		if close < 0:
			break
		var slot_name := rest.substr(open + 1, close - open - 1)
		if not slot_name.is_empty() and not found.has(slot_name):
			found.append(slot_name)
		rest = rest.substr(close + 1)
	return found


## The topic's facts as the contract's `[{key, value, unit}]`, so a renderer
## (or a model) can be shown what is true without being handed the frame and
## asked to go and find it.
static func facts_list(facts: Dictionary) -> Array:
	var out: Array = []
	for key in facts:
		out.append({"key": key, "value": facts[key], "unit": unit_of(key)})
	return out


## What a fact is measured in. Named rather than guessed from the value's type
## so "5 gold" and "5 rock" cannot render the same way.
const UNITS := {
	"meal_price": "gold",
	"wallet_gold": "gold",
	"short_by": "gold",
	"village_purse_gold": "gold",
	"missing_count": "items",
	"hunger": "fraction",
	"snow_depth": "fraction",
	"confidence": "fraction",
}


static func unit_of(fact_key: String) -> String:
	return String(UNITS.get(fact_key, ""))


## The situation half of the cache key.
##
## Coarse on purpose: this is what decides whether a baked phrasing can be
## reused, so a band per exact gold piece would give one cache entry per beat
## and bake nothing. Continuous facts are reported in thirds; booleans as
## themselves; everything else is left out, because a fact that does not change
## how a sentence should SOUND has no business in the key.
static func fact_band_for(topic_id: String, facts: Dictionary) -> String:
	var parts: Array[String] = []
	var keys := facts.keys()
	keys.sort()
	for key in keys:
		var value = facts[key]
		if value is bool:
			parts.append("%s:%s" % [key, "yes" if value else "no"])
		elif value is float:
			parts.append("%s:%s" % [key, band_of(value)])
		elif value is int:
			parts.append("%s:%s" % [key, "none" if int(value) == 0 else "some"])
	return "%s|%s" % [topic_id, "|".join(parts)]


## Where a 0..1 quantity sits, in thirds.
static func band_of(value: float) -> String:
	if value < BAND_LOW:
		return "low"
	if value < BAND_HIGH:
		return "mid"
	return "high"


## The key a baked phrasing is stored under (dialogue.md, "The AI seam").
##
## Deliberately NOT keyed on the NPC. That is the whole reason baking phrasings
## ahead of time is tractable: there are a handful of voices and a handful of
## situation bands, and thousands of villagers. Two different people in the
## same situation with the same voice say the same thing, which is also simply
## true of people.
static func cache_key_of(beat: Dictionary) -> String:
	return "%s|%s|%s|%s" % [
		String(beat.get("voice_key", "")),
		String(beat.get("topic_id", "")),
		String(beat.get("kind", "")),
		String(beat.get("fact_band", "")),
	]


## The words a rephrasing must keep. What carries the meaning rather than the
## tone: a rephrasing that drops "short" from a request for help has changed
## the game state as far as the player is concerned.
const LEXEMES := {
	DialogueTopic.TOPIC_HOUSEHOLD_ASK: ["short"],
	DialogueTopic.TOPIC_HUNGER: ["hungry"],
	DialogueTopic.TOPIC_WALLET: ["afford"],
}


static func required_lexemes_for(topic_id: String) -> Array:
	return LEXEMES.get(topic_id, [])


## The sentence shape for a topic, with its holes still in it.
##
## One template per topic, chosen by which slots the facts actually filled --
## so a topic that could name an item does, and one whose facts did not carry
## an item falls back to a shape that never needed it, rather than rendering a
## sentence with an empty hole.
## One per topic in the roster, and that is a hard requirement rather than a
## nicety: a topic with no template falls back, and a fallback shared by
## fifteen topics means fifteen different pieces of news reading as one remark
## -- the mad-libs mill pillar 2 exists to prevent, only worse. Seen in the
## running game, where a villager met the fallback on the first sentence.
## Pinned by test_every_topic_has_a_sentence_of_its_own.
const TEMPLATES := {
	# What this villager's own day is like.
	DialogueTopic.TOPIC_HUNGER: "I've not eaten today.",
	DialogueTopic.TOPIC_WALLET: "There's food on the stall and I can't afford it.",
	DialogueTopic.TOPIC_WAGE: "The village purse won't cover a wage this week.",
	DialogueTopic.TOPIC_WORK: "I work the {place}.",
	DialogueTopic.TOPIC_HOUSEHOLD_ASK: "We're short. {count} {item}, if you have it.",
	# What their village is.
	DialogueTopic.TOPIC_VILLAGE_STATUS: "The place is going the way it's going.",
	DialogueTopic.TOPIC_VILLAGE_TIER: "We're bigger than we were. You can feel it.",
	DialogueTopic.TOPIC_VILLAGE_SPECIALIZATION: "It's {item} that keeps this place standing.",
	DialogueTopic.TOPIC_VILLAGE_FOOD: "The stores won't see us through.",
	DialogueTopic.TOPIC_WEATHER: "The snow's deep enough to matter.",
	# News they hold, from the memory banks. Each names WHAT KIND of thing
	# happened; the hedge says how well they know it and the facts carry the
	# rest, because a villager retelling a raid does not recite coordinates.
	DialogueTopic.TOPIC_ARRIVAL: "Someone new came to stay. That still happens.",
	DialogueTopic.TOPIC_VILLAGE_HISTORY: "This place wasn't always here, you know.",
	DialogueTopic.TOPIC_PRODUCTION_NEWS: "The work's not going as it should.",
	DialogueTopic.TOPIC_INSTITUTION: "There's an arrangement now. Rules, of a sort.",
	DialogueTopic.TOPIC_CARAVAN: "A caravan came through.",
	DialogueTopic.TOPIC_RAID: "They were hit on the road. Goods still out there, most like.",
	DialogueTopic.TOPIC_RUIN: "There's a ruin out that way. Nobody's stripped it yet.",
	DialogueTopic.TOPIC_DEAL: "A bargain was struck. Not everyone was pleased.",
	DialogueTopic.TOPIC_BOSS: "Something big is out there. I'd not go looking.",
	DialogueTopic.TOPIC_PATH: "There's a track worn in now, where there wasn't one.",
	DialogueTopic.TOPIC_PLAYER_DEED: "Word is you've made your mark hereabouts.",
	# Who else is standing here.
	DialogueTopic.TOPIC_NEIGHBOUR: "You'll have met {name}, then.",
	DialogueTopic.TOPIC_CONTRADICTION: "That's not how I heard it. Not how I heard it at all.",
}
const _FALLBACK_TEMPLATE := "There's that, at least."
## Shapes for a topic whose facts did not fill the slots its full template
## wants. Keyed the same way, used only when a required slot is missing.
const SLOTLESS_TEMPLATES := {
	DialogueTopic.TOPIC_HOUSEHOLD_ASK: "We're short of what we need.",
	DialogueTopic.TOPIC_WORK: "I've my work, such as it is.",
}


static func template_for(topic_id: String, slots: Dictionary) -> String:
	var template := String(TEMPLATES.get(topic_id, _FALLBACK_TEMPLATE))
	for slot_name in required_slots_in(template):
		if not slots.has(slot_name):
			return String(SLOTLESS_TEMPLATES.get(topic_id, _FALLBACK_TEMPLATE))
	return template
