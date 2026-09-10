extends GutTest

## OfflineRenderer (src/dialogue/offline_renderer.gd) -- the pipeline's final
## stage (docs/concept/dialogue.md): a five-slot sentence plan (OPENER, CORE,
## HEDGE, ASIDE, CLOSER) with pools indexed by voice band, turning one Beat
## into the sentence a player actually reads. This is also where the
## `template` (pre-substitution) / `offline_text` (already substituted --
## "the guaranteed floor") split actually happens: DialogueBeat leaves both
## blank, and this module is the next pipeline stage that fills them in.
##
## Deliberately not exhaustive over all 22 topic ids x 5 axes x 3 bands --
## that is a combinatorial floor test this module does not attempt. What is
## pinned: every specially-worded topic produces real, non-empty, slot-
## substituted text; the five-slot plan really drops slots by voice band
## (dialogue.md's own named example: high bluntness + low verbosity -> four
## words); HEDGE wording really varies by source_type/confidence/hedging
## band; and choice labels are built from the beat's own slots, never a
## fixed menu (dialogue.md's own two named examples).

const OfflineRenderer = preload("res://src/dialogue/offline_renderer.gd")
const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const DialogueMove = preload("res://src/dialogue/dialogue_move.gd")
const NpcVoice = preload("res://src/dialogue/npc_voice.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")

## A voice register that lands mid-band on every axis -- no slot-dropping,
## no phrasing-terseness rule kicks in, so tests about ONE topic's wording
## are not also, accidentally, tests about banding.
const _NEUTRAL_TRAITS := {
	"friendly": 0.5, "kind": 0.5, "gruff": 0.5, "greedy": 0.5,
	"bold": 0.5, "cautious": 0.5, "curious": 0.5, "stoic": 0.5,
}


func _frame(overrides: Dictionary = {}) -> Dictionary:
	var frame := {"npc_name": "Bren", "occupation": "potter"}
	for key in overrides:
		frame[key] = overrides[key]
	return frame


func _beat_for(topic_id: String, facts: Dictionary, traits: Dictionary = _NEUTRAL_TRAITS) -> Dictionary:
	var topic := {"topic_id": topic_id, "salience": 0.8, "facts": facts}
	var move := DialogueMove.select_one([topic], null, "npc:1", 0.0, 7)
	return DialogueBeat.build(move, _frame(), NpcVoice.register_for(traits))


func _traits_with_band(axis: String, band: String) -> Dictionary:
	# Nudges exactly one axis to the requested band by pushing its raising
	# genes to one extreme and its lowering genes to the other -- the same
	# "raises minus lowers" contrast NpcVoice.axis_value itself computes,
	# driven from the outside rather than duplicated here. Pushing BOTH
	# sides (not just the raising genes) matters: a shared gene between two
	# axes (e.g. bluntness raises on `gruff`, verbosity lowers on it) must
	# still land this axis at its extreme regardless of what the other axis
	# already did to that gene.
	var traits := _NEUTRAL_TRAITS.duplicate()
	var raise_to := 1.0 if band == "high" else 0.0
	var lower_to := 0.0 if band == "high" else 1.0
	for gene in NpcVoice.AXIS_GENES[axis]["raises"]:
		traits[gene] = raise_to
	for gene in NpcVoice.AXIS_GENES[axis]["lowers"]:
		traits[gene] = lower_to
	assert_eq(NpcVoice.band_of(axis, NpcVoice.axis_value(axis, traits)), band, "precondition: fixture drove the axis to the wrong band")
	return traits


func test_render_never_returns_an_empty_string_for_a_real_beat():
	var beat := _beat_for(DialogueTopic.TOPIC_WEATHER, {"season": "winter", "weather": "snow", "snow_depth": 0.1})
	assert_ne(OfflineRenderer.render(beat), "")


func test_a_deflect_beat_renders_an_honest_nothing_to_say_line():
	var beat := DialogueBeat.build({}, _frame(), NpcVoice.register_for(_NEUTRAL_TRAITS))
	var text := OfflineRenderer.render(beat)
	assert_ne(text, "")
	assert_eq(beat["offline_text"], "", "DialogueBeat itself must still not have pre-filled this")


func test_household_ask_names_the_real_missing_item_and_count():
	var beat := _beat_for(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var text := OfflineRenderer.render(beat)
	assert_string_contains(text, "3")
	assert_string_contains(text.to_lower(), "rock")


func test_neighbour_names_the_real_neighbour():
	var beat := _beat_for(DialogueTopic.TOPIC_NEIGHBOUR, {
		"npc_id": "npc:9", "name": "Lira", "occupation": "farmer",
		"memories": [], "top_memory": {}, "strength": 0.6,
	})
	assert_string_contains(OfflineRenderer.render(beat), "Lira")


func test_village_status_wording_actually_differs_by_the_real_status():
	var growing := _beat_for(DialogueTopic.TOPIC_VILLAGE_STATUS, {
		"status": "growing", "household_count": 5, "capacity": 10, "food_stock": 20,
	})
	var declining := _beat_for(DialogueTopic.TOPIC_VILLAGE_STATUS, {
		"status": "declining", "household_count": 9, "capacity": 3, "food_stock": 0,
	})
	assert_ne(OfflineRenderer.render(growing), OfflineRenderer.render(declining))


func test_template_and_offline_text_differ_exactly_by_slot_substitution():
	var beat := _beat_for(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var rendered := OfflineRenderer.render_beat(beat)
	assert_string_contains(rendered["template"], "{item}")
	assert_string_contains(rendered["template"], "{count}")
	assert_false(rendered["offline_text"].contains("{item}"), "offline_text must be fully substituted")
	assert_string_contains(rendered["offline_text"].to_lower(), "rock")
	assert_string_contains(rendered["offline_text"], "3")


func test_every_declared_memory_event_type_renders_real_non_empty_text():
	for topic_id in DialogueTopic.MEMORY_TOPIC_EVENT_TYPES:
		for event_type in DialogueTopic.MEMORY_TOPIC_EVENT_TYPES[topic_id]:
			var memory := {"event_type": event_type, "confidence": 0.9, "distortion": 0.0, "source_type": MemoryRecord.FIRSTHAND, "actors": []}
			var beat := _beat_for(topic_id, {
				"event_types": [event_type], "memories": [memory], "top_memory": memory, "strength": 0.9,
			})
			var text := OfflineRenderer.render(beat)
			assert_ne(text, "", "event type '%s' rendered no text at all" % event_type)
			# Non-empty alone would also pass silently on the generic
			# _FALLBACK_CORE filler -- _NEWS_LINE_BY_EVENT_TYPE.get() falls
			# back to it for any key it doesn't recognize. "Real" text (this
			# test's own name, and this file's header: "every specially-
			# worded topic produces real ... text") means a bespoke entry, so
			# a declared event type that only reaches the fallback is exactly
			# the gap this asserts against.
			assert_false(
				text.contains(OfflineRenderer._FALLBACK_CORE),
				(
					"event type '%s' has no bespoke line in _NEWS_LINE_BY_EVENT_TYPE -- "
					+ "it fell through to the generic fallback"
				) % event_type
			)


func test_high_bluntness_with_low_verbosity_drops_the_opener_and_the_aside():
	var terse_traits := _traits_with_band("bluntness", "high")
	for gene in NpcVoice.genes_of("verbosity"):
		if _axis_raises("verbosity", gene):
			terse_traits[gene] = 0.0
	var register := NpcVoice.register_for(terse_traits)
	assert_eq(register["bands"]["bluntness"], "high", "precondition")
	assert_eq(register["bands"]["verbosity"], "low", "precondition")

	var topic := {"topic_id": DialogueTopic.TOPIC_WEATHER, "salience": 0.8, "facts": {"season": "winter", "weather": "snow", "snow_depth": 0.1}}
	var move := DialogueMove.select_one([topic], null, "npc:1", 0.0, 7)
	var beat := DialogueBeat.build(move, _frame(), register, {"tier": "owed"})
	var rendered := OfflineRenderer.render_beat(beat)

	assert_false(rendered["template"].begins_with("Well"), "a blunt villager does not open with pleasantries")
	assert_false(rendered["template"].to_lower().contains("owe"), "a low-verbosity, blunt villager drops the aside entirely")


func test_high_verbosity_villagers_get_a_closer_low_verbosity_villagers_do_not():
	var chatty := _traits_with_band("verbosity", "high")
	var terse := _traits_with_band("verbosity", "low")
	var facts := {"season": "winter", "weather": "snow", "snow_depth": 0.1}

	var chatty_beat := _beat_for(DialogueTopic.TOPIC_WEATHER, facts, chatty)
	var terse_beat := _beat_for(DialogueTopic.TOPIC_WEATHER, facts, terse)

	var chatty_len := OfflineRenderer.render(chatty_beat).length()
	var terse_len := OfflineRenderer.render(terse_beat).length()
	assert_true(chatty_len > terse_len, "a chatty villager's line should be strictly longer than a terse one's")


func test_a_repeat_beat_opens_by_acknowledging_the_first_telling():
	var topic := {"topic_id": DialogueTopic.TOPIC_WEATHER, "salience": 0.8, "facts": {"season": "winter", "weather": "snow", "snow_depth": 0.1}}
	var ledger = load("res://src/dialogue/npc_seen_ledger.gd").new()
	ledger.mark_told("npc:1", DialogueTopic.TOPIC_WEATHER, 0.0)
	var move := DialogueMove.select_one([topic], ledger, "npc:1", 500.0, 7)
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for(_NEUTRAL_TRAITS))
	assert_string_contains(OfflineRenderer.render(beat).to_lower(), "like i said")


func test_hedge_wording_differs_by_source_type():
	var firsthand := _beat_for(DialogueTopic.TOPIC_ARRIVAL, {
		"event_types": ["npc_settled"],
		"memories": [], "top_memory": {"event_type": "npc_settled", "confidence": 1.0, "distortion": 0.0, "source_type": MemoryRecord.FIRSTHAND, "actors": []},
		"strength": 1.0,
	})
	var rumor := _beat_for(DialogueTopic.TOPIC_ARRIVAL, {
		"event_types": ["npc_settled"],
		"memories": [], "top_memory": {"event_type": "npc_settled", "confidence": 0.3, "distortion": 0.5, "source_type": MemoryRecord.RUMOR, "actors": []},
		"strength": 0.15,
	})
	var firsthand_text := OfflineRenderer.render(firsthand)
	var rumor_text := OfflineRenderer.render(rumor)
	assert_ne(firsthand_text, rumor_text)
	assert_string_contains(rumor_text.to_lower(), "talk")


func test_hedging_band_picks_a_terser_or_fuller_hedge_phrase():
	var memory := {"event_type": "npc_settled", "confidence": 0.9, "distortion": 0.0, "source_type": MemoryRecord.FIRSTHAND, "actors": []}
	var facts := {"event_types": ["npc_settled"], "memories": [], "top_memory": memory, "strength": 0.9}

	var low_hedging := _beat_for(DialogueTopic.TOPIC_ARRIVAL, facts, _traits_with_band("hedging", "low"))
	var high_hedging := _beat_for(DialogueTopic.TOPIC_ARRIVAL, facts, _traits_with_band("hedging", "high"))
	assert_ne(OfflineRenderer.render(low_hedging), OfflineRenderer.render(high_hedging))


func test_choice_label_for_household_ask_names_the_real_item_and_count():
	var beat := _beat_for(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var label := OfflineRenderer.choice_label_for(beat)
	assert_string_contains(label, "3")
	assert_string_contains(label.to_lower(), "rock")


func test_choice_label_for_neighbour_asks_what_they_said():
	var beat := _beat_for(DialogueTopic.TOPIC_NEIGHBOUR, {
		"npc_id": "npc:9", "name": "Lira", "occupation": "farmer",
		"memories": [], "top_memory": {}, "strength": 0.6,
	})
	var label := OfflineRenderer.choice_label_for(beat)
	assert_string_contains(label, "Lira")


func test_two_different_topics_never_share_a_choice_label():
	var ask := _beat_for(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var weather := _beat_for(DialogueTopic.TOPIC_WEATHER, {"season": "winter", "weather": "snow", "snow_depth": 0.1})
	assert_ne(OfflineRenderer.choice_label_for(ask), OfflineRenderer.choice_label_for(weather))


## Whether `gene` is one of the genes that RAISES `axis` (vs. lowers it) --
## a tiny local helper, not a NpcVoice API, kept private to this fixture.
func _axis_raises(axis: String, gene: String) -> bool:
	return NpcVoice.AXIS_GENES[axis]["raises"].has(gene)
