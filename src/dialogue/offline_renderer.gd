extends RefCounted

## The sentence (docs/concept/dialogue.md, "The pipeline" -> OfflineRenderer).
##
## A five-slot plan -- OPENER, CORE, HEDGE, ASIDE, CLOSER -- with pools indexed
## by voice band. Only the CORE carries meaning: it is the beat's own
## `template` with its slots substituted **by the core**, never by whatever
## produced the wording. The other four are tone, and are exactly what a future
## AI layer would be allowed to replace.
##
## "Offline" because this is the guaranteed floor: it needs no model, no
## network and no cache, and it is what the player sees when nothing has been
## baked for this beat's key. dialogue.md's whole AI-seam argument rests on
## that floor existing -- "works without it" is a property of the architecture
## rather than a promise someone has to keep.
##
## This is also where a memory's DISTORTION is finally applied (see hedge_for),
## leaving EventStore's ground truth uncorrupted -- the fact-versus-belief
## split docs/emergence/02 specifies.

const NpcVoice = preload("res://src/dialogue/npc_voice.gd")

## How many of the four tone slots a voice keeps.
##
## The doc's own worked example: "High bluntness with low verbosity drops three
## of five slots and you get four words." Blunt speech cuts the softeners;
## talkative speech keeps them. Everything here is a lookup on a band the
## genome already produced -- no weight is chosen.
## Keyed by VERBOSITY, and in the direction verbosity actually runs: a
## talkative villager has more around the core, a terse one has none. The
## first version had these pools the right way round for bluntness and the
## wrong way round for the axis they were keyed on, so the tersest voice in
## the game produced the longest sentence.
const OPENERS := {
	"low": [""],
	"mid": ["", "So "],
	"high": ["Well, ", "Ah -- ", "Right, so "],
}
const CLOSERS := {
	"low": [""],
	"mid": [""],
	"high": [" That's the size of it.", " Anyway."],
}
const ASIDES := {
	"low": [""],
	"mid": [""],
	"high": [" Not that I like saying it."],
}

## What an opener becomes when the villager has said this before. The ledger's
## `repeat` flag is what makes a second telling read as one.
const REPEAT_OPENERS := ["Like I said -- ", "As I told you, ", "Again: "]

## How the opener changes with how well they know you (see NpcRecognition).
##
## Recognition that never reaches the words is bookkeeping -- and every beat in
## the game rendered at `stranger` until NpcRecognition had a caller at all.
## Only the GREETING moves: familiarity changes how you are addressed, never
## what is being said, which is why these are openers rather than templates.
const RECOGNITION_OPENERS := {
	"knows_you": ["Oh -- you again. ", "You're back. "],
	"owed": ["There you are. ", "I've been hoping you'd come by. "],
	"trusted": ["Good to see you. ", "Ah, it's you. "],
	"disappointed": ["...You. ", "Hm. You. "],
}

## How a speaker marks what they are not sure of, by how they came to know it.
##
## Straight off the memory's real `source_type` and `confidence` -- the doc's
## own worked examples. A villager who saw it does not hedge at all, which is
## the point: hedging has to MEAN something, so it cannot be everywhere.
const FIRSTHAND_SOURCES := {"firsthand": true, "witnessed": true}
const HEARSAY_HEDGES := [
	"Someone at the well said -- ",
	"I had it from a neighbour: ",
]
const RUMOUR_HEDGES := [
	"There's talk. I'd not swear to it: ",
	"Word going round, mind: ",
]
## Below this a second-hand account is stated as rumour rather than as
## testimony. The two hedge pools say genuinely different things, so the line
## between them has to be somewhere; it sits at the midpoint of the confidence
## range, which is the only non-arbitrary point on it.
const RUMOUR_CONFIDENCE := 0.5


## The finished sentence for a beat, in this villager's voice.
##
## `bands` is NpcVoice.register_for(...)["bands"] -- the five axis bands, not
## the single winning voice_key, because the slot logic needs two axes at once
## (bluntness decides how much softening survives, verbosity how much is there
## to soften).
static func render(beat: Dictionary, bands: Dictionary) -> String:
	var core := substitute(String(beat.get("template", "")), beat.get("slots", {}))
	if core.is_empty():
		return _deflection(beat)
	var bluntness := String(bands.get("bluntness", "mid"))
	var verbosity := String(bands.get("verbosity", "mid"))
	var seed_value := int(beat.get("variant_seed", 0))
	# Most specific first. Saying it AGAIN outranks knowing you -- stacking both
	# would read as a stranger who repeats themselves.
	var opener := ""
	var recognition := String(beat.get("speaker", {}).get("recognition", ""))
	if bool(beat.get("repeat", false)):
		opener = _pick(REPEAT_OPENERS, seed_value)
	elif RECOGNITION_OPENERS.has(recognition):
		opener = _pick(RECOGNITION_OPENERS[recognition], seed_value)
	else:
		opener = _pick(OPENERS[verbosity], seed_value) if OPENERS.has(verbosity) else ""
	# Bluntness cuts the softeners, whatever verbosity put there.
	var aside := ""
	var closer := ""
	if bluntness != "high":
		aside = _pick(ASIDES.get(verbosity, [""]), seed_value + 1)
		closer = _pick(CLOSERS.get(verbosity, [""]), seed_value + 2)
	return "%s%s%s%s" % [opener, core, aside, closer]


## The beat's template with its slots filled in.
##
## The one operation that must never be delegated: a rephrasing may move the
## words around the holes, and the holes are filled here, from the beat's own
## slots. A placeholder with no slot behind it is dropped rather than left on
## screen -- a sentence with a visible `{count}` in it is worse than a slightly
## vaguer one.
static func substitute(template: String, slots: Dictionary) -> String:
	var out := template
	for slot_name in slots:
		out = out.replace("{%s}" % slot_name, str(slots[slot_name]))
	while out.contains("{"):
		var open := out.find("{")
		var close := out.find("}", open)
		if close < 0:
			break
		out = out.substr(0, open) + out.substr(close + 1)
	return out.replace("  ", " ").strip_edges()


## How this speaker marks a thing they did not see themselves.
##
## Empty for firsthand knowledge: an eyewitness does not hedge, and if everyone
## hedged the hedge would carry nothing. This is where rumour distortion
## finally reaches the player -- the store still holds the truth.
static func hedge_for(source_type: String, confidence: float) -> String:
	if FIRSTHAND_SOURCES.has(source_type):
		return ""
	var pool := RUMOUR_HEDGES if confidence < RUMOUR_CONFIDENCE else HEARSAY_HEDGES
	return pool[0]


## What someone with nothing to say says. Not a topic, and it claims nothing
## about the world -- pillar 2 is that an empty topic is OMITTED, so this is a
## villager declining to talk rather than a villager remarking on the weather.
const DEFLECTIONS := [
	"They shrug, and go back to it.",
	"They've nothing to say to you today.",
	"A nod, and that's all.",
]


static func _deflection(beat: Dictionary) -> String:
	return _pick(DEFLECTIONS, int(beat.get("variant_seed", 0)))


## Deterministic pick. The same villager phrasing the same beat says the same
## thing twice; two villagers do not.
static func _pick(pool: Array, seed_value: int) -> String:
	if pool.is_empty():
		return ""
	return String(pool[absi(seed_value) % pool.size()])
