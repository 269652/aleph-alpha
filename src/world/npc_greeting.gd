extends RefCounted

## Minimal talk-interaction stand-in (see docs/concept/npc.md's "Minimal talk
## interaction" section) -- turns an NpcIdentity into one deterministic
## greeting line, flavored by that villager's own personality trait and
## driving need. Explicitly NOT the real Live Dialogue System: no branching,
## no memory, no quest hooks, nothing persisted -- just enough that talking
## to a villager reads like talking to *that* individual rather than a
## generic NPC.

const NpcIdentity = preload("res://src/world/npc_identity.gd")

## One line per personality trait (see NpcIdentity.PERSONALITY_TRAITS),
## written to work for any occupation/need. `%s` is the NPC's own need,
## rendered as a short human phrase (see _need_phrase).
const _TRAIT_LINES := {
	"friendly": "smiles and waves you over: \"Good to see a new face! %s, if I'm honest.\"",
	"gruff": "grunts a greeting: \"What do you want? ...%s, if you must know.\"",
	"curious": "tilts their head, curious: \"Haven't seen you before. Say -- %s?\"",
	"stoic": "nods once, evenly: \"%s.\"",
	"greedy": "eyes your pockets before your face: \"Got any coin? Not that it'd fix -- %s.\"",
	"kind": "greets you warmly: \"Welcome, traveler. If you're able, %s.\"",
	"cautious": "keeps their distance, watchful: \"Careful now. Truth is, %s.\"",
	"bold": "grins, unbothered: \"Ha! A stranger. Well, %s -- might as well say it.\"",
}

## Human phrasing for each NpcIdentity.NEEDS entry, dropped into _TRAIT_LINES'
## %s slot.
const _NEED_PHRASES := {
	"wants_more_wood": "we could use more wood around here",
	"wants_companionship": "it gets lonely some days",
	"wants_medicine": "someone in the village could use medicine",
	"wants_protection": "we could use a bit more protection lately",
	"wants_rare_ingredients": "I'm after some rare ingredients, if you ever find any",
	"wants_news_from_afar": "I'd love to hear news from afar",
}


## One deterministic greeting for `identity`, e.g.
## "Bren the blacksmith grunts a greeting: \"What do you want? ...we could
## use more wood around here, if you must know.\""
func greeting_for(identity: NpcIdentity) -> String:
	var trait_line: String = _TRAIT_LINES.get(identity.personality_trait, _TRAIT_LINES["stoic"])
	var need_phrase: String = _NEED_PHRASES.get(identity.need, "there's always something to do")
	return "%s the %s %s" % [identity.npc_name, identity.occupation, trait_line % need_phrase]
