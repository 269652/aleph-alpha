extends GutTest

## The beat: one Dictionary carrying everything needed to say one sentence
## (docs/concept/dialogue.md, "The beat contract").
##
## It exists as an explicit contract for two reasons the doc states: it is
## what the renderer consumes, and it is the ONLY surface a future AI layer
## would ever touch. Both of those put real constraints on its shape, and
## those constraints are what this file pins.

const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const DialogueMove = preload("res://src/dialogue/dialogue_move.gd")


func _frame() -> Dictionary:
	return {
		"npc_id": "npc:7",
		"seed_value": 7,
		"npc_name": "Bren",
		"occupation": "farmer",
		"is_hungry": true,
		"hunger": 0.8,
		"meal_price": 5,
		"wallet_gold": 2,
		"can_afford_meal": false,
		"meal_available": true,
	}


func _a_move(frame: Dictionary) -> Dictionary:
	var topics := DialogueTopic.available_for(frame)
	return DialogueMove.select_one(topics, null, String(frame["npc_id"]), 0.0, 7)


func _a_beat() -> Dictionary:
	var frame := _frame()
	return DialogueBeat.build(_a_move(frame), frame, "bluntness_high", DialogueBeat.RECOGNITION_STRANGER)


# -- the contract ------------------------------------------------------------


func test_the_test_frame_actually_produces_a_move():
	assert_false(_a_move(_frame()).is_empty(), "no topic was available to build a beat from")


func test_a_beat_carries_every_field_the_contract_names():
	var beat := _a_beat()
	for field in [
		"kind", "topic_id", "voice_key", "fact_band", "speaker", "facts",
		"slots", "required_slots", "required_lexemes", "template",
	]:
		assert_true(beat.has(field), "the beat is missing %s" % field)


func test_a_beat_knows_which_topic_it_is_about():
	assert_eq(String(_a_beat()["topic_id"]), String(_a_move(_frame())["topic_id"]))


func test_the_speaker_is_named():
	assert_eq(String(_a_beat()["speaker"]["name"]), "Bren")
	assert_eq(String(_a_beat()["speaker"]["occupation"]), "farmer")


## Nothing to say is a real answer, not an error (dialogue.md pillar 2).
func test_a_villager_with_nothing_to_say_still_produces_a_beat():
	var beat := DialogueBeat.build({}, {"npc_name": "Bren"}, "warmth_low", DialogueBeat.RECOGNITION_STRANGER)
	assert_eq(String(beat["kind"]), DialogueBeat.KIND_DEFLECT)
	assert_eq(beat["facts"], [])


# -- the property that makes the AI seam safe --------------------------------


## THE constraint. Quantities and names live in `slots` and are substituted by
## the core; they are never written into the sentence by whatever produced it.
## A template containing the literal number is a template a model could return
## with the number changed, and there would be no way to tell.
func test_the_template_never_contains_a_quantity_or_a_name():
	var beat := _a_beat()
	var template := String(beat["template"])
	assert_false(template.contains("Bren"), "the speaker's name is baked into the template")
	for slot_name in beat["slots"]:
		var value := str(beat["slots"][slot_name])
		if value.is_empty():
			continue
		assert_false(
			template.contains(value),
			"the value of slot '%s' (%s) is baked into the template" % [slot_name, value]
		)


## ...and every placeholder the template uses is declared, so a returned
## string that dropped one can be rejected rather than silently rendered with
## a hole in it.
##
## Swept over EVERY template in the roster rather than whichever one the test
## frame happened to produce: the first version of this test picked a topic
## whose sentence has no holes at all and asserted nothing.
func test_every_placeholder_in_every_template_is_declared():
	var checked := 0
	for topic_id in DialogueBeat.TEMPLATES:
		var template := String(DialogueBeat.TEMPLATES[topic_id])
		var declared := DialogueBeat.required_slots_in(template)
		for slot_name in declared:
			assert_true(template.contains("{%s}" % slot_name))
			checked += 1
	assert_gt(checked, 0, "no template in the roster has a slot at all")


## A slot only ever holds something a sentence can be filled with. The
## shortfall facts carry a LIST of {item_id, need}, and putting that in a hole
## renders an array into the middle of a sentence.
func test_a_slot_never_holds_a_list_or_a_dictionary():
	var slots := DialogueBeat.slots_for(
		{"missing": [{"item_id": "rock", "need": 3}], "units_short": 3}, {"npc_name": "Bren"}
	)
	for slot_name in slots:
		var value = slots[slot_name]
		assert_false(value is Array, "slot '%s' holds a list" % slot_name)
		assert_false(value is Dictionary, "slot '%s' holds a dictionary" % slot_name)


## ...and a request names the thing it is asking for, which lives inside that
## list rather than as a fact of its own.
func test_a_request_names_the_item_and_the_count():
	var slots := DialogueBeat.slots_for(
		{"missing": [{"item_id": "rock", "need": 3}]}, {"npc_name": "Bren"}
	)
	assert_eq(String(slots["item"]), "rock")
	assert_eq(int(slots["count"]), 3)


# -- the cache key, which is the whole precompilation thesis -----------------


## dialogue.md: "the natural cache key is (voice_key, topic_id, kind,
## fact_band) and NOT the NPC". That is what makes baking phrasings ahead of
## time tractable at all -- you bake per voice x topic x situation, not per
## villager, and there are a handful of the first and thousands of the second.
func test_two_different_villagers_in_the_same_situation_share_a_cache_key():
	var one := _frame()
	var other := _frame()
	other["npc_id"] = "npc:99"
	other["seed_value"] = 99
	other["npc_name"] = "Doran"
	var beat_one := DialogueBeat.build(_a_move(one), one, "bluntness_high", DialogueBeat.RECOGNITION_STRANGER)
	var beat_two := DialogueBeat.build(_a_move(other), other, "bluntness_high", DialogueBeat.RECOGNITION_STRANGER)
	assert_eq(DialogueBeat.cache_key_of(beat_one), DialogueBeat.cache_key_of(beat_two))


func test_a_different_voice_is_a_different_cache_key():
	var frame := _frame()
	var blunt := DialogueBeat.build(_a_move(frame), frame, "bluntness_high", DialogueBeat.RECOGNITION_STRANGER)
	var warm := DialogueBeat.build(_a_move(frame), frame, "warmth_high", DialogueBeat.RECOGNITION_STRANGER)
	assert_ne(DialogueBeat.cache_key_of(blunt), DialogueBeat.cache_key_of(warm))


## ...and a different SITUATION is too, or one baked line would be reused for
## a village that is thriving and one that is starving.
func test_a_different_situation_is_a_different_cache_key():
	var poor := _frame()
	var poorer := _frame()
	poorer["wallet_gold"] = 0
	poorer["hunger"] = 1.0
	var a := DialogueBeat.build(_a_move(poor), poor, "bluntness_high", DialogueBeat.RECOGNITION_STRANGER)
	var b := DialogueBeat.build(_a_move(poorer), poorer, "bluntness_high", DialogueBeat.RECOGNITION_STRANGER)
	assert_ne(String(a["fact_band"]), String(b["fact_band"]))


## A cache key has to be stable: the same beat asked twice is the same key, or
## nothing baked is ever found again.
func test_the_same_beat_gives_the_same_key_twice():
	assert_eq(DialogueBeat.cache_key_of(_a_beat()), DialogueBeat.cache_key_of(_a_beat()))


# -- facts ------------------------------------------------------------------


## The facts travel with the beat as {key, value, unit} so a renderer (or a
## model) can be shown WHAT is true without being handed the frame and asked
## to find it.
func test_the_facts_travel_with_the_beat():
	var beat := _a_beat()
	assert_gt(beat["facts"].size(), 0)
	for fact in beat["facts"]:
		assert_true(fact.has("key"))
		assert_true(fact.has("value"))
		assert_true(fact.has("unit"))


## And they are the topic's own facts, not a re-derivation.
func test_the_facts_are_the_topics_own():
	var frame := _frame()
	var move := _a_move(frame)
	var beat := DialogueBeat.build(move, frame, "bluntness_high", DialogueBeat.RECOGNITION_STRANGER)
	var topic_facts: Dictionary = move["topic"]["facts"]
	assert_eq(beat["facts"].size(), topic_facts.size())


# -- every topic has a sentence ----------------------------------------------


## Seen in the running game: a villager said "There's that, at least." -- the
## fallback -- because the topic that won had no sentence of its own. Eight of
## the roster's twenty-three had templates and the rest all rendered the same
## line, which is exactly the mad-libs mill pillar 2 exists to prevent, only
## worse: one line for fifteen different things a villager might be telling
## you about.
##
## A topic that can be SAID has to have something to say.
func test_every_topic_has_a_sentence_of_its_own():
	for topic_id in DialogueTopic.TOPIC_IDS:
		assert_true(
			DialogueBeat.TEMPLATES.has(topic_id),
			"topic '%s' has no template and would fall back" % topic_id
		)


## ...and no two topics share one, or two different pieces of news read as the
## same remark.
func test_no_two_topics_say_the_same_thing():
	var seen := {}
	for topic_id in DialogueBeat.TEMPLATES:
		var template := String(DialogueBeat.TEMPLATES[topic_id])
		assert_false(seen.has(template), "'%s' reuses another topic's sentence" % topic_id)
		seen[template] = true


## Every template's slots have to be ones the beat can actually fill, or the
## sentence renders with its hole cut out.
func test_no_template_asks_for_a_slot_that_does_not_exist():
	var known := ["count", "item", "place", "name"]
	for topic_id in DialogueBeat.TEMPLATES:
		for slot_name in DialogueBeat.required_slots_in(String(DialogueBeat.TEMPLATES[topic_id])):
			assert_true(known.has(slot_name), "'%s' wants unknown slot '%s'" % [topic_id, slot_name])


## `{name}` in a template means the person being TALKED ABOUT, not the person
## talking. The neighbour topic is the one that uses it, and with the speaker's
## own name filling the slot Joric would say "You'll have met Joric, then."
func test_a_name_slot_names_the_other_person_not_the_speaker():
	var slots := DialogueBeat.slots_for({"name": "Doran", "npc_id": "npc:3"}, {"npc_name": "Joric"})
	assert_eq(String(slots["name"]), "Doran")


## ...and with nobody else in the facts it is still the speaker, so a template
## that wants a name always has one.
func test_a_name_slot_falls_back_to_the_speaker():
	assert_eq(String(DialogueBeat.slots_for({}, {"npc_name": "Joric"})["name"]), "Joric")
