extends RefCounted

## What the villager is about to say, packaged for OfflineRenderer alone to
## word (docs/concept/dialogue.md's pipeline, sixth stage: `Move ->
## DialogueBeat.build -> Beat`). This is the doc's own "beat contract" --
## quoted there so it is the ONE surface a future AI rephrasing layer would
## ever touch (see dialogue.md's "The AI seam, deliberately not built").
##
## Three fields ride on the beat beyond the doc's own literal list:
##   * `variant_seed` -- OfflineRenderer's deterministic index into a
##     phrasing pool, carried from the Move. DialogueMove already computes
##     this per (villager, topic) via its own pinned FNV-1a mixer
##     (variant_seed_for); a second, different seed invented here would let
##     two stages of one pipeline disagree about which phrasing is "this
##     villager's own".
##   * `repeat` -- whether the ledger has ever heard this NPC raise this
##     topic before, carried from the Move. dialogue.md's own named
##     mechanism #2 ("the ledger burns topics... with an opener that
##     acknowledges the first") needs this at the wording stage.
##   * `voice_bands` -- ALL FIVE axis bands, not just the one `voice_key`
##     names. NpcVoice.register_for's own doc comment says exactly why the
##     renderer needs this: "high bluntness with low verbosity drops three
##     of five slots, which needs two axes, not the winner alone" -- and
##     `voice_key` can only ever name ONE (the most extreme) axis. Carried
##     from `voice_register.bands` untouched.
## Same precedent as Move carrying its whole scored `topic` through
## untouched: a field the next stage genuinely needs is added explicitly
## and documented, not smuggled in silently.
##
## Pure: Dictionaries in, one Dictionary out. No Node, no store, no world
## access -- everything on the beat came from `move`, `frame`,
## `voice_register` or `recognition`, never read fresh. `template` and
## `offline_text` are deliberately left "" here (see dialogue.md's own
## distinction between the two): choosing WHAT is worth saying is this
## module's job, choosing the WORDS is OfflineRenderer's, one stage later.

const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")

const KIND_ASK := "ask"
const KIND_ANSWER := "answer"
const KIND_DEFLECT := "deflect"

## Every field a Beat carries. `template`/`offline_text` are the doc's own
## last two; `variant_seed`/`repeat` are this module's documented additions
## (see the module doc comment above).
const BEAT_FIELDS: Array[String] = [
	"kind", "topic_id", "voice_key", "fact_band", "speaker", "facts",
	"slots", "required_slots", "required_lexemes", "template", "offline_text",
	"variant_seed", "repeat", "voice_bands",
]

## The four slot keys a Beat's `slots` Dictionary always carries, filled or
## not -- a fixed shape (dialogue.md: `slots: {item, count, place, name}`)
## rather than a variable one, so OfflineRenderer's String.format substitution
## never trips over a key that happens not to exist this time.
const _SLOT_KEYS: Array[String] = ["item", "count", "place", "name"]

const _HUNGER_SEVERE := 0.67
const _HUNGER_MODERATE := 0.34
const _SHORTFALL_MAJOR_SHARE := 0.5
const _FOOD_BARREN_SHARE := 0.8
const _FOOD_TIGHT_SHARE := 0.3
const _SNOW_DEEP := 0.66
const _SNOW_LIGHT := 0.2
const _NEIGHBOUR_STRONG := 0.5
const _CONTRADICTION_SHARP_STEPS := 3


## `move`: one Move from DialogueMove.select/select_one, or {} for "nothing
## to say" -- a real, valid answer (dialogue.md pillar 2), not an error.
## `frame`: the same frame the move's topics were scored from.
## `voice_register`: NpcVoice.register_for(identity.genome.traits)'s output.
## `recognition`: NpcRecognition.tier_for(...)'s output, or {} when the
## caller has no stores to ask -- reads as "stranger", the same fail-open
## shape every other absent source in this pipeline uses.
static func build(
	move: Dictionary,
	frame: Dictionary,
	voice_register: Dictionary,
	recognition: Dictionary = {}
) -> Dictionary:
	var voice_key := str(voice_register.get("voice_key", ""))
	var voice_bands: Dictionary = voice_register.get("bands", {})

	if move.is_empty():
		return {
			"kind": KIND_DEFLECT, "topic_id": "", "voice_key": voice_key, "fact_band": "none:general",
			"speaker": _speaker_for(frame, recognition, _empty_slots()), "facts": [], "slots": _empty_slots(),
			"required_slots": [], "required_lexemes": [], "template": "", "offline_text": "",
			"variant_seed": 0, "repeat": false, "voice_bands": voice_bands,
		}

	var topic_id := str(move.get("topic_id", ""))
	var topic: Dictionary = move.get("topic", {})
	var facts_dict: Dictionary = topic.get("facts", {})
	var slots := _slots_for(topic_id, facts_dict)
	var speaker := _speaker_for(frame, recognition, slots)

	var required_slots: Array[String] = []
	for key in _SLOT_KEYS:
		var value = slots[key]
		if (value is String and value != "") or (value is int and value != 0):
			required_slots.append(key)

	return {
		"kind": KIND_ASK if topic_id == DialogueTopic.TOPIC_HOUSEHOLD_ASK else KIND_ANSWER,
		"topic_id": topic_id,
		"voice_key": voice_key,
		"fact_band": _fact_band_for(topic_id, facts_dict),
		"speaker": speaker,
		"facts": _facts_array(facts_dict),
		"slots": slots,
		"required_slots": required_slots,
		"required_lexemes": [],
		"template": "",
		"offline_text": "",
		"variant_seed": int(move.get("variant_seed", 0)),
		"repeat": bool(move.get("repeat", false)),
		"voice_bands": voice_bands,
	}


static func _empty_slots() -> Dictionary:
	return {"item": "", "count": 0, "place": "", "name": ""}


## `speaker.allowed_names` -- every proper name this beat is permitted to
## mention, the AI seam's own future validation surface (dialogue.md: a
## rephrasing must stay "in that villager's voice", never invent a person).
## Always the speaker's own name; a neighbour/contradiction topic adds the
## one real name its facts actually name.
static func _speaker_for(frame: Dictionary, recognition: Dictionary, slots: Dictionary) -> Dictionary:
	var name := str(frame.get("npc_name", ""))
	var allowed_names: Array[String] = []
	if name != "":
		allowed_names.append(name)
	var slot_name := str(slots.get("name", ""))
	if slot_name != "" and not allowed_names.has(slot_name):
		allowed_names.append(slot_name)
	return {
		"name": name,
		"occupation": str(frame.get("occupation", "")),
		"recognition": str(recognition.get("tier", "stranger")),
		"allowed_names": allowed_names,
	}


## Best-effort, generic extraction: only the four fixed slot keys exist, so a
## topic whose facts do not name an item/count/place/person leaves that slot
## at its empty default rather than inventing one (pillar 2, generalized to
## wording material rather than topic availability).
static func _slots_for(topic_id: String, facts: Dictionary) -> Dictionary:
	var slots := _empty_slots()
	match topic_id:
		DialogueTopic.TOPIC_HOUSEHOLD_ASK:
			var missing: Array = facts.get("missing", [])
			if not missing.is_empty():
				slots["item"] = str(missing[0].get("item_id", ""))
				slots["count"] = int(missing[0].get("need", 0))
		DialogueTopic.TOPIC_NEIGHBOUR:
			slots["name"] = str(facts.get("name", ""))
		DialogueTopic.TOPIC_CONTRADICTION:
			slots["name"] = str(facts.get("neighbour_name", ""))
			slots["count"] = int(facts.get("steps", 0))
		DialogueTopic.TOPIC_HUNGER:
			slots["count"] = int(facts.get("meal_price", 0))
		DialogueTopic.TOPIC_WALLET:
			slots["count"] = int(facts.get("short_by", 0))
		DialogueTopic.TOPIC_WAGE:
			slots["count"] = int(facts.get("short_by", 0.0))
		DialogueTopic.TOPIC_WORK:
			slots["item"] = str(facts.get("produces_item_id", ""))
			slots["place"] = str(facts.get("work_location", ""))
			slots["count"] = maxi(int(facts.get("food_needed", 0)) - int(facts.get("food_stock", 0)), 0)
		DialogueTopic.TOPIC_VILLAGE_STATUS:
			slots["count"] = int(facts.get("household_count", 0))
		DialogueTopic.TOPIC_VILLAGE_TIER:
			slots["item"] = str(facts.get("tier", ""))
			slots["count"] = int(facts.get("household_count", 0))
		DialogueTopic.TOPIC_VILLAGE_SPECIALIZATION:
			slots["item"] = str(facts.get("specialization", ""))
			slots["count"] = int(facts.get("production_diversity", 0))
		DialogueTopic.TOPIC_VILLAGE_FOOD:
			slots["count"] = maxi(int(facts.get("food_needed", 0)) - int(facts.get("food_stock", 0)), 0)
		DialogueTopic.TOPIC_WEATHER:
			var weather := str(facts.get("weather", ""))
			slots["item"] = weather if weather != "" else str(facts.get("season", ""))
	return slots


## `[{key, value, unit}]` (dialogue.md's own `facts` shape) -- every raw fact
## the topic was scored from, for a future consumer that wants more than the
## four named slots (an AI rephrasing layer's grounding, or a debug view).
## `unit` is "" throughout: nothing upstream carries a unit system (hunger is
## a bare 0-1 float, a shortfall is bare item counts), so inventing one here
## would be exactly the fabricated-fact pillar 2 forbids.
static func _facts_array(facts: Dictionary) -> Array:
	var out: Array = []
	for key in facts:
		out.append({"key": str(key), "value": facts[key], "unit": ""})
	return out


## A coarse, cache-friendly "<dimension>:<qualitative-state>" string
## (dialogue.md's own examples: "market:empty", "status:declining") --
## deliberately NOT keyed by NPC (that is the whole point of the AI seam's
## cache key, `(voice_key, topic_id, kind, fact_band)`: a phrasing baked
## ahead of time and one fetched live are the same artifact only if two
## different villagers in the same real situation share one band). The
## bucket thresholds are named, tested constants (CLAUDE.md's own
## no-eyeballed-tuning rule), not inline numbers.
static func _fact_band_for(topic_id: String, facts: Dictionary) -> String:
	if DialogueTopic.MEMORY_TOPIC_EVENT_TYPES.has(topic_id):
		var top: Dictionary = facts.get("top_memory", {})
		return "news:%s" % str(top.get("event_type", "unknown"))
	match topic_id:
		DialogueTopic.TOPIC_HUNGER:
			var hunger := float(facts.get("hunger", 0.0))
			if hunger >= _HUNGER_SEVERE:
				return "hunger:severe"
			if hunger >= _HUNGER_MODERATE:
				return "hunger:moderate"
			return "hunger:low"
		DialogueTopic.TOPIC_WALLET:
			return "wallet:short"
		DialogueTopic.TOPIC_WAGE:
			return "wage:short"
		DialogueTopic.TOPIC_WORK, DialogueTopic.TOPIC_VILLAGE_FOOD:
			return "food:%s" % _food_band(facts)
		DialogueTopic.TOPIC_HOUSEHOLD_ASK:
			var recipe_units := int(facts.get("recipe_units", 0))
			if recipe_units <= 0:
				return "shortfall:major"
			var share := float(facts.get("units_short", 0)) / float(recipe_units)
			return "shortfall:major" if share >= _SHORTFALL_MAJOR_SHARE else "shortfall:minor"
		DialogueTopic.TOPIC_VILLAGE_STATUS:
			return "status:%s" % str(facts.get("status", "unknown"))
		DialogueTopic.TOPIC_VILLAGE_TIER:
			return "tier:%s" % str(facts.get("tier", "unknown"))
		DialogueTopic.TOPIC_VILLAGE_SPECIALIZATION:
			return "specialization:%s" % str(facts.get("specialization", "unknown"))
		DialogueTopic.TOPIC_WEATHER:
			var snow := float(facts.get("snow_depth", 0.0))
			if snow >= _SNOW_DEEP:
				return "snow:deep"
			if snow >= _SNOW_LIGHT:
				return "snow:light"
			return "snow:bare"
		DialogueTopic.TOPIC_NEIGHBOUR:
			return "neighbour:strong" if float(facts.get("strength", 0.0)) >= _NEIGHBOUR_STRONG else "neighbour:weak"
		DialogueTopic.TOPIC_CONTRADICTION:
			return "contradiction:sharp" if int(facts.get("steps", 0)) >= _CONTRADICTION_SHARP_STEPS else "contradiction:mild"
	return "%s:general" % (topic_id if topic_id != "" else "none")


static func _food_band(facts: Dictionary) -> String:
	var needed := int(facts.get("food_needed", 0))
	if needed <= 0:
		return "ample"
	var share := clampf(1.0 - float(facts.get("food_stock", 0)) / float(needed), 0.0, 1.0)
	if share >= _FOOD_BARREN_SHARE:
		return "barren"
	if share >= _FOOD_TIGHT_SHARE:
		return "tight"
	return "ample"
