extends GutTest

## The sentence itself (docs/concept/dialogue.md, "The pipeline" ->
## OfflineRenderer).
##
## A five-slot plan -- OPENER, CORE, HEDGE, ASIDE, CLOSER -- with pools indexed
## by voice band. The CORE is the beat's own template with its slots
## substituted **by the core**, never by whatever produced the wording; the
## other four are tone. High bluntness with low verbosity drops three of five
## slots and you get four words.
##
## This is also where a memory's distortion is finally applied, leaving
## EventStore's ground truth uncorrupted -- the fact-versus-belief split
## docs/emergence/02 specifies.

const OfflineRenderer = preload("res://src/dialogue/offline_renderer.gd")
const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const NpcVoice = preload("res://src/dialogue/npc_voice.gd")


func _beat(overrides: Dictionary = {}) -> Dictionary:
	var beat := {
		"kind": DialogueBeat.KIND_ASK,
		"topic_id": "household_ask",
		"voice_key": "bluntness_high",
		"fact_band": "household_ask|covered_by_player:no",
		"speaker": {"name": "Bren", "occupation": "farmer", "recognition": "stranger", "allowed_names": []},
		"facts": [],
		"slots": {"count": 3, "item": "rock", "name": "Bren"},
		"required_slots": ["count", "item"],
		"required_lexemes": ["short"],
		"template": "We're short. {count} {item}, if you have it.",
		"repeat": false,
		"variant_seed": 11,
	}
	beat.merge(overrides, true)
	return beat


func _bands(overrides: Dictionary = {}) -> Dictionary:
	var bands := {}
	for axis in NpcVoice.AXES:
		bands[axis] = "mid"
	bands.merge(overrides, true)
	return bands


# -- the core is the template, substituted by the core -----------------------


## The one thing that must always be true: quantities and names reach the
## sentence by SUBSTITUTION, never by having been written into it.
func test_the_slots_are_substituted():
	var line := OfflineRenderer.render(_beat(), _bands())
	assert_string_contains(line, "3")
	assert_string_contains(line, "rock")


func test_no_placeholder_survives_into_the_sentence():
	var line := OfflineRenderer.render(_beat(), _bands())
	assert_false(line.contains("{"), "an unfilled placeholder reached the player: %s" % line)
	assert_false(line.contains("}"), "an unfilled placeholder reached the player: %s" % line)


## The words that carry the meaning survive whatever the tone does to the
## sentence -- a request for help that loses "short" has changed the game
## state as far as the player is concerned.
func test_the_required_lexemes_survive():
	for bluntness in NpcVoice.BANDS:
		for verbosity in NpcVoice.BANDS:
			var line := OfflineRenderer.render(
				_beat(), _bands({"bluntness": bluntness, "verbosity": verbosity})
			)
			assert_string_contains(
				line.to_lower(), "short", "'short' was lost at %s/%s" % [bluntness, verbosity]
			)


## Nothing to say renders as nothing, not as a sentence about the weather
## (dialogue.md pillar 2).
func test_a_deflect_with_no_template_says_something_but_claims_nothing():
	var line := OfflineRenderer.render(
		_beat({"template": "", "required_slots": [], "required_lexemes": [], "kind": DialogueBeat.KIND_DEFLECT}),
		_bands()
	)
	assert_false(line.contains("{"))


# -- the voice actually changes the sentence ---------------------------------


## The headline claim: high bluntness with low verbosity drops three of five
## slots and you get four words.
func test_a_blunt_terse_villager_says_less_than_a_warm_talkative_one():
	var terse := OfflineRenderer.render(
		_beat(), _bands({"bluntness": "high", "verbosity": "low"})
	)
	var talkative := OfflineRenderer.render(
		_beat(), _bands({"bluntness": "low", "verbosity": "high", "hedging": "high"})
	)
	assert_lt(terse.length(), talkative.length(), "the voice did not change the sentence")


func test_the_same_villager_says_the_same_thing_twice():
	assert_eq(OfflineRenderer.render(_beat(), _bands()), OfflineRenderer.render(_beat(), _bands()))


## Two villagers with different variant seeds phrase the same beat differently
## -- or a village of eight farmers is one farmer said eight times.
func test_different_villagers_phrase_the_same_beat_differently():
	var lines := {}
	for seed_value in 24:
		lines[OfflineRenderer.render(_beat({"variant_seed": seed_value}), _bands())] = true
	assert_gt(lines.size(), 1, "every villager phrases it identically")


## Someone repeating themselves says so, which is what the ledger's `repeat`
## flag is for.
func test_a_repeat_is_marked_as_one():
	var first := OfflineRenderer.render(_beat(), _bands({"verbosity": "high"}))
	var again := OfflineRenderer.render(_beat({"repeat": true}), _bands({"verbosity": "high"}))
	assert_ne(first, again, "saying it again reads exactly like saying it the first time")


# -- belief, and where distortion lands --------------------------------------


## A hedge names how the speaker knows -- firsthand, hearsay, or talk -- and it
## comes from the memory's REAL source type and confidence.
func test_the_hedge_reflects_how_they_know_it():
	var firsthand := OfflineRenderer.hedge_for("firsthand", 1.0)
	var rumor := OfflineRenderer.hedge_for("rumor", 0.2)
	assert_ne(firsthand, rumor)
	assert_ne(rumor, "", "a rumour is stated as flatly as an eyewitness account")


## A villager who saw it themselves does not hedge at all.
func test_an_eyewitness_does_not_hedge():
	assert_eq(OfflineRenderer.hedge_for("firsthand", 1.0), "")
