extends RefCounted

## "Monty Python's Bridgekeeper (three-riddle NPC)" (docs/concept/
## easter_eggs.md): RP1 name-drops this film directly. A rarely-encountered
## wandering NPC blocks a narrow crossing and asks three short ORIGINAL
## riddles -- not the film's own lines -- before letting the player pass
## EITHER WAY: "failing a riddle is harmless, just a silly non-consequence
## rather than a real penalty" (the doc's own words), the deliberate
## opposite of the film's own rather more dramatic outcome. Zero mechanical
## weight (pillar 2) -- passage never actually depends on the score.
##
## SCOPE CALL: this project has no bridge/river-crossing terrain concept and
## no free-roaming "block the player's path" NPC AI to reuse (grep turned up
## neither) -- building either from scratch would be a far bigger lift than
## an Easter egg warrants. Scoped down the same way EasterEggSightings
## scoped Mothman/the Jersey Devil down to "a log-line, not a spawned
## sprite/Node" (see that module's own doc comment): the "wandering NPC
## blocking a crossing" is a rare, location-gated encounter (mechanism #1,
## reusing GeoCoordinates + chance_per_check exactly like EasterEggSightings)
## that opens a short riddle exchange conducted through the dev console's
## existing text-input surface (mechanism #2, /answer -- see scenes/
## world.gd's _handle_bridgekeeper_answer_command), the same "secret console
## command" shape WarGames/the d20 egg already use. No new NPC node, no new
## blocking-collision AI -- the player was never actually stopped from
## walking past, matching "passes either way" by construction rather than
## needing an unblock step.
##
## Location: a real, narrow, famous foot crossing -- Trift Bridge, a long,
## precarious rope-and-plank suspension bridge over a Swiss glacial gorge --
## chosen for genuinely reading as "a narrow crossing" in real life, the
## same "quiet, factual, never named in-game" pick RushAmbientCue/
## AncientTerminal already make for their own real-world locations.
##
## Original riddles set in this game's own nature/survival vocabulary
## (rivers, trees, snow) rather than echoing the film's own three questions
## (name/quest/favourite colour) -- test_bridgekeeper_encounter.gd's own
## "does not quote the film's own questions" check pins that, the same
## discipline test_wargames_response.gd already applies to the WarGames egg.

const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

const LATITUDE := 46.707
const LONGITUDE := 8.348
const RADIUS_KM := 3.0

## First-pass placeholder, not calibrated against real playtesting data (this
## project has no Easter-egg encounter-rate data yet -- same situation as
## EasterEggSightings.SIGHTINGS' own chance_per_check values/BossAggro.
## MIN_DAMAGE_FRACTION_OF_MAX_HEALTH). Pinned as a named constant and
## exercised by test_chance_per_check_is_rare's relative bound rather than
## eyeballed inline -- "rarely-encountered" per the doc.
const CHANCE_PER_CHECK := 0.005

## index -> {question, accepted_answers[]} -- three short original riddles,
## each with one canonical answer plus the obvious no-article variant
## ("a river"/"river"), matched case-insensitively with surrounding
## whitespace trimmed (see is_correct_answer).
const RIDDLES: Array[Dictionary] = [
	{
		"question": "I run through every field and forest, yet I never take a single step. What am I?",
		"accepted_answers": ["river", "a river"],
	},
	{
		"question": "The older I grow, the taller I stand, though my feet never leave the same patch of ground. What am I?",
		"accepted_answers": ["tree", "a tree"],
	},
	{
		"question": "I fall all winter long and never make a sound, then vanish completely once the year turns round. What am I?",
		"accepted_answers": ["snow"],
	},
]

## correct_count (0..3) -> flavor line -- always ends in passage, "a silly
## non-consequence" either way per the doc, so these vary only in tone, not
## outcome.
const PASSAGE_MESSAGES := {
	0: "The Bridgekeeper winces at every answer, sighs, and waves you across anyway. \"Off you go, then.\"",
	1: "\"One out of three,\" the Bridgekeeper says, unimpressed but fair. \"Go on.\"",
	2: "The Bridgekeeper nods, mostly satisfied. \"Close enough. Mind the loose plank.\"",
	3: "The Bridgekeeper looks almost delighted. \"All three! Go in peace, and watch your footing.\"",
}

var _geo := GeoCoordinates.new()


func riddle_count() -> int:
	return RIDDLES.size()


## "" for an out-of-range index rather than an error -- an unrecognized
## riddle simply has nothing to say.
func riddle_text(index: int) -> String:
	if index < 0 or index >= RIDDLES.size():
		return ""
	return String(RIDDLES[index]["question"])


## Case-insensitive, whitespace-trimmed match against `index`'s accepted
## answers; false for an out-of-range index (never crashes on a bad index --
## same "unknown id, not an error" convention as EasterEggSightings.check_one).
func is_correct_answer(index: int, answer: String) -> bool:
	if index < 0 or index >= RIDDLES.size():
		return false
	var normalized := answer.strip_edges().to_lower()
	var accepted: Array = RIDDLES[index]["accepted_answers"]
	for candidate in accepted:
		if normalized == String(candidate):
			return true
	return false


## The flavor line for having answered `correct_count` (0-3) riddles
## correctly -- always non-empty, always ends in letting the player pass;
## clamps out-of-range counts rather than erroring.
func passage_message(correct_count: int) -> String:
	var clamped := clampi(correct_count, 0, 3)
	return String(PASSAGE_MESSAGES[clamped])


## The tile this crossing's location corresponds to on a world_width x
## world_height grid.
func tile(world_width: int, world_height: int) -> Vector2i:
	return _geo.tile_for_coordinate(LATITUDE, LONGITUDE, world_width, world_height)


## True if (tile_x, tile_y) is within RADIUS_KM of the crossing.
func is_in_range(tile_x: int, tile_y: int, world_width: int, world_height: int) -> bool:
	return _geo.tile_is_within_radius(
		tile_x, tile_y, LATITUDE, LONGITUDE, RADIUS_KM, world_width, world_height
	)


## One check against a tile+roll (see EasterEggSightings.check_one for the
## exact same shape): true only if in range AND `roll` (a caller-supplied
## [0, 1) draw -- randf() in real play, a fixed value in tests) clears
## CHANCE_PER_CHECK.
func check(tile_x: int, tile_y: int, world_width: int, world_height: int, roll: float) -> bool:
	if not is_in_range(tile_x, tile_y, world_width, world_height):
		return false
	return roll < CHANCE_PER_CHECK
