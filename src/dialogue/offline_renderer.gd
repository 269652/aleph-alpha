extends RefCounted

## The pipeline's last stage (docs/concept/dialogue.md): turns one
## DialogueBeat into the sentence a player actually reads. A five-slot
## sentence plan -- OPENER, CORE, HEDGE, ASIDE, CLOSER -- with pools indexed
## by voice band, exactly as the doc describes: "High bluntness with low
## verbosity drops three of five slots and you get four words."
##
## -- Where the five slots come from --
##
##   OPENER  "Like I said," when `beat.repeat` is true (dialogue.md's own
##           named mechanism #2 -- acknowledging the first telling); a warm
##           "Well," for a high-`warmth` villager otherwise; "" for anyone
##           blunt (bluntness overrides warmth -- a blunt villager who is
##           ALSO warm still skips the pleasantry) or merely unremarkable.
##   CORE    the fact itself, dispatched by topic_id (or by event_type for
##           the eleven memory-backed topics, which all share one facts
##           shape -- see DialogueTopic._memory_facts). The one slot that
##           is never dropped: a beat with nothing in CORE has nothing to
##           say at all, which is what the deflect kind is for.
##   HEDGE   only for a beat with a real memory source (`top_memory` in its
##           facts): worded from that memory's ACTUAL source_type and
##           confidence (dialogue.md's own examples), terser or fuller by
##           `hedging` band.
##   ASIDE   a recognition-flavored aside ("You still owe me on that,
##           mind."), dropped for low `verbosity` or high `bluntness`
##           villagers, and empty anyway when there is nothing notable in
##           the relationship (pillar 2, generalized: no fact, no aside).
##   CLOSER  a self_interest-flavored sign-off, included only for a high
##           `verbosity` villager -- the one band that bothers to elaborate
##           at all.
##
## -- template vs. offline_text --
##
## DialogueBeat leaves both "" -- deciding WHAT to say is its job, not HOW.
## This module builds `template` as the slot plan joined together WITH its
## `{item}`/`{count}`/`{place}`/`{name}` placeholders still in it (Godot's
## own String.format token syntax, which the beat's `slots` Dictionary keys
## already match), then substitutes to get `offline_text`. Keeping the two
## genuinely different strings -- not the same text twice -- is what would
## let a future AI rephrasing layer touch `template` alone and have the core
## re-substitute afterward (dialogue.md's "AI seam", not built here).
##
## Pure: a Dictionary in, a String (or an enriched Dictionary) out. No Node,
## no store, no world access. The one non-pipeline dependency is ItemCatalog,
## used ONLY to turn a raw item_id into a display name at the last possible
## moment -- DialogueBeat itself never reaches for it, so choosing what to
## call something stays entirely this module's concern, same division of
## labour QuestLogWindow already draws between the quest projection and its
## own display text.

const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const DialogueMove = preload("res://src/dialogue/dialogue_move.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

const _DEFLECT_TEXT := "Nothing more to say right now."
const _FALLBACK_CORE := "There's word of it, but I couldn't tell you more."

## Confidence at or above this reads as "sounded sure enough" rather than
## "take that for what it's worth" for a stranger's secondhand account --
## named and tested rather than an inline eyeballed number (CLAUDE.md).
const _HEDGE_CONFIDENCE_THRESHOLD := 0.5

const _OPENER_REPEAT := "Like I said, "
const _OPENER_WARM := "Well, "

const _ASIDE_BY_RECOGNITION := {
	"owed": "You still owe me on that, mind.",
	"trusted": "Good to see a friendly face.",
	"disappointed": "Didn't expect you back, honestly.",
}

const _CLOSER_SELF_INTEREST_HIGH := "Anyway -- if you're of a mind to help, I wouldn't say no."
const _CLOSER_SELF_INTEREST_OTHER := "Anyway, good to talk with you."

## One honest line per real event type the substrate emits (see
## DialogueTopic.MEMORY_TOPIC_EVENT_TYPES, which this table is pinned
## against by test_offline_renderer.gd's own census test). One phrasing per
## type for this pass -- per-voice-band flavor comes from the OPENER/HEDGE/
## ASIDE/CLOSER slots wrapping it, not from CORE itself varying, a
## deliberate scope line named here rather than pretended away.
const _NEWS_LINE_BY_EVENT_TYPE := {
	"npc_settled": "Word is someone new settled here not long ago.",
	"player_settled": "They still talk about you settling here.",
	"settlement_founded": "This place got its start not so long ago, from what I hear.",
	"settlement_growing": "I hear we've been growing.",
	"settlement_stable": "Word is we're holding steady.",
	"settlement_declining": "I hear things have been slipping here.",
	"settlement_became_hamlet": "We're a proper hamlet now, they say.",
	"settlement_became_town": "We've grown into a town, or so I hear.",
	"settlement_became_city": "A city now, if you can believe it.",
	"settlement_specialized": "Word is we've made a name for ourselves at something.",
	"production_succeeded": "I hear the work's been paying off lately.",
	"production_failed": "I hear the work hasn't been going well.",
	"institution_formed": "There's a new institution here, from what I hear.",
	"institution_dissolved": "I hear an institution here fell apart.",
	"regional_trade_departed": "A caravan set out from here, I hear.",
	"regional_trade_shipped": "I hear a shipment made it through.",
	"regional_trade_raided": "There was a raid on a caravan, from what I hear.",
	"ruin_formed": "Something around here has fallen to ruin, they say.",
	"contract_fulfilled": "I hear a deal was honored recently.",
	"contract_breached": "I hear a deal fell through, and not politely.",
	"contract_defaulted": "I hear someone couldn't make good on a deal.",
	"contract_cancelled": "I hear a deal was called off before it came to anything.",
	"world_boss_promoted": "There's word of something dangerous growing stronger out there.",
	"world_boss_defeated": "I hear something fearsome was put down.",
	"path_worn": "A path's been worn through, from what I hear.",
	"path_reclaimed": "I hear a path's gone back to the wild.",
	"player_claimed_property": "I hear someone's staked a claim nearby.",
}


## The final sentence alone -- what a ConversationWindow actually shows.
static func render(beat: Dictionary) -> String:
	return str(render_beat(beat).get("offline_text", ""))


## `beat` merged with its computed `template` (placeholders intact) and
## `offline_text` (fully substituted) -- exposed separately from render() so
## the template/offline_text split itself is directly testable, the same
## reason dialogue.md calls it out as its own contract rather than an
## implementation detail.
static func render_beat(beat: Dictionary) -> Dictionary:
	var out := beat.duplicate()
	if str(beat.get("kind", "")) == DialogueBeat.KIND_DEFLECT:
		out["template"] = _DEFLECT_TEXT
		out["offline_text"] = _DEFLECT_TEXT
		return out

	var bands := _bands_for(beat)
	var slots: Dictionary = beat.get("slots", {})
	var facts: Dictionary = _facts_dict(beat)

	var parts: Array[String] = []
	var opener := _opener_for(beat, bands)
	if opener != "":
		parts.append(opener.strip_edges())
	parts.append(_core_for(beat, facts))
	var hedge := _hedge_for(facts, bands)
	if hedge != "":
		parts.append(hedge)
	var aside := _aside_for(beat, bands)
	if aside != "":
		parts.append(aside)
	var closer := _closer_for(beat, bands)
	if closer != "":
		parts.append(closer)

	var template := " ".join(parts)
	out["template"] = template
	out["offline_text"] = template.format(_display_slots(slots))
	return out


## "Ask about the three rock" / "Ask what Doran said" (dialogue.md's own two
## named examples) -- built from the beat's own slots, never a fixed menu.
static func choice_label_for(beat: Dictionary) -> String:
	var topic_id := str(beat.get("topic_id", ""))
	var slots: Dictionary = _display_slots(beat.get("slots", {}))
	match beat.get("kind", ""):
		DialogueBeat.KIND_ASK:
			if int(slots.get("count", 0)) > 1:
				return "Ask about the {count} {item}".format(slots)
			return "Ask about the {item}".format(slots)
	if topic_id == DialogueTopic.TOPIC_NEIGHBOUR or topic_id == DialogueTopic.TOPIC_CONTRADICTION:
		return "Ask what {name} said".format(slots)
	if topic_id == DialogueTopic.TOPIC_WEATHER:
		return "Ask about the weather"
	if topic_id.begins_with("village_"):
		return "Ask about the village"
	return "Ask about it"


static func _facts_dict(beat: Dictionary) -> Dictionary:
	# `facts` on the beat is the doc's own [{key, value, unit}] array shape
	# (a future consumer's grounding); the CORE/HEDGE builders below want
	# the original richer Dictionary instead, which DialogueBeat.build read
	# it from -- reconstructed here rather than carried twice on one beat.
	var out := {}
	for entry in beat.get("facts", []):
		out[entry["key"]] = entry["value"]
	return out


## `beat.voice_bands` (DialogueBeat's own documented addition, carrying
## NpcVoice.register_for's full `bands` through) -- ALL FIVE axes, which is
## what the slot logic below actually needs (see this module's own doc
## comment). Missing/unrecognised axes default to "mid" (unremarkable), the
## same fail-open shape NpcVoice itself uses for a missing gene, so a
## hand-built beat in a test that only sets `voice_key` still renders rather
## than erroring.
static func _bands_for(beat: Dictionary) -> Dictionary:
	var bands := {"warmth": "mid", "bluntness": "mid", "verbosity": "mid", "hedging": "mid", "self_interest": "mid"}
	var voice_bands: Dictionary = beat.get("voice_bands", {})
	for axis in bands:
		if voice_bands.has(axis):
			bands[axis] = str(voice_bands[axis])
	return bands


static func _display_slots(slots: Dictionary) -> Dictionary:
	var catalog := ItemCatalog.new()
	var item_id := str(slots.get("item", ""))
	var display_item := item_id.capitalize()
	if item_id != "" and catalog.has(item_id):
		display_item = catalog.make(item_id).display_name
	return {
		"item": display_item,
		"count": int(slots.get("count", 0)),
		"place": str(slots.get("place", "")),
		"name": str(slots.get("name", "")),
	}


static func _opener_for(beat: Dictionary, bands: Dictionary) -> String:
	if bool(beat.get("repeat", false)):
		return _OPENER_REPEAT
	if bands["bluntness"] == "high":
		return ""
	if bands["warmth"] == "high":
		return _OPENER_WARM
	return ""


static func _core_for(beat: Dictionary, facts: Dictionary) -> String:
	var topic_id := str(beat.get("topic_id", ""))
	if DialogueTopic.MEMORY_TOPIC_EVENT_TYPES.has(topic_id):
		return _memory_core(facts)
	match topic_id:
		DialogueTopic.TOPIC_HOUSEHOLD_ASK:
			var line := "I could use {count} more {item}, if you happen to have it."
			if facts.get("missing", []).size() > 1:
				line += " There's more than that I'm short on, if you're asking."
			return line
		DialogueTopic.TOPIC_NEIGHBOUR:
			return "{name} has been on my mind lately."
		DialogueTopic.TOPIC_CONTRADICTION:
			return "{name} tells it differently than I remember it."
		DialogueTopic.TOPIC_HUNGER:
			var line := "I could eat -- it's been a while."
			if not bool(facts.get("can_afford_meal", false)):
				line += " A meal's {count} gold, more than I've got on me right now."
			return line
		DialogueTopic.TOPIC_WALLET:
			return "A meal costs {count} gold more than I'm carrying."
		DialogueTopic.TOPIC_WAGE:
			return "The village purse is {count} gold short of what it owes me."
		DialogueTopic.TOPIC_WORK:
			return "My {item} isn't enough to fill the shelves -- we're {count} short."
		DialogueTopic.TOPIC_VILLAGE_STATUS:
			match str(facts.get("status", "")):
				"growing":
					return "This place is growing -- more mouths every season."
				"declining":
					return "This place is thinning out, and it worries me."
				"stable":
					return "This place holds steady, for now."
			return "This place is what it is."
		DialogueTopic.TOPIC_VILLAGE_TIER:
			return "We've grown into a proper {item}."
		DialogueTopic.TOPIC_VILLAGE_SPECIALIZATION:
			return "Around here, we're known for our {item}."
		DialogueTopic.TOPIC_VILLAGE_FOOD:
			return "The shelves are {count} short of what this village needs to eat."
		DialogueTopic.TOPIC_WEATHER:
			var snow := float(facts.get("snow_depth", 0.0))
			if snow >= 0.66:
				return "This snow won't quit -- it's up past the doorstep."
			if snow >= 0.2:
				return "There's a fair bit of snow settling in."
			return "Weather's been {item} lately, nothing to complain about."
	return _FALLBACK_CORE


static func _memory_core(facts: Dictionary) -> String:
	var top: Dictionary = facts.get("top_memory", {})
	var event_type := str(top.get("event_type", ""))
	return str(_NEWS_LINE_BY_EVENT_TYPE.get(event_type, _FALLBACK_CORE))


## Only for a beat whose facts actually carry a real memory source -- the
## eleven memory topics, plus neighbour and contradiction, which are the
## only shapes with a `top_memory` at all. Worded from that memory's REAL
## source_type and confidence (dialogue.md's own three examples), terser or
## fuller by `hedging` band; a high-bluntness villager gets the terse
## variant regardless of their own hedging band, the same "bluntness
## overrides" rule the opener uses.
static func _hedge_for(facts: Dictionary, bands: Dictionary) -> String:
	var memory: Dictionary = facts.get("top_memory", {})
	if memory.is_empty():
		return ""
	var source_type := str(memory.get("source_type", ""))
	var confidence := float(memory.get("confidence", 0.0))
	var terse: bool = bands["bluntness"] == "high" or bands["hedging"] == "low"

	match source_type:
		MemoryRecord.FIRSTHAND, MemoryRecord.WITNESSED:
			return "I saw it myself." if terse else "I saw it with my own eyes, so I know it's true."
		MemoryRecord.TRUSTED_TESTIMONY:
			return "Someone I trust told me." if terse else "Someone I trust told me straight, so I'd wager it's so."
		MemoryRecord.STRANGER_TESTIMONY:
			if terse:
				return "Someone at the well said so."
			if confidence >= _HEDGE_CONFIDENCE_THRESHOLD:
				return "Someone at the well said so, and it sounded sure enough."
			return "Someone at the well said so -- take that for what it's worth."
		MemoryRecord.RUMOR:
			return "There's talk, that's all." if terse else "There's talk. I'd not swear to it."
	return ""


static func _aside_for(beat: Dictionary, bands: Dictionary) -> String:
	if bands["verbosity"] == "low" or bands["bluntness"] == "high":
		return ""
	var speaker: Dictionary = beat.get("speaker", {})
	var recognition := str(speaker.get("recognition", "stranger"))
	return str(_ASIDE_BY_RECOGNITION.get(recognition, ""))


static func _closer_for(beat: Dictionary, bands: Dictionary) -> String:
	if bands["verbosity"] != "high":
		return ""
	return _CLOSER_SELF_INTEREST_HIGH if bands["self_interest"] == "high" else _CLOSER_SELF_INTEREST_OTHER
