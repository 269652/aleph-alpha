extends RefCounted

## An individual villager's identity (docs/concept/npc.md "Identity": name,
## occupation, a small set of personality traits, a driving need/goal).
## Deterministic per seed, same hash-seeded philosophy as CreatureInfo/
## TreeGenome -- no RandomNumberGenerator, so a settlement regenerates the
## same villagers every time its chunk reloads.
##
## Scope note: npc.md's Identity also includes "relationships to a handful
## of other NPCs" and organic backstory growth through logged events --
## deliberately NOT modeled yet (see docs/progress.md's NPC section);
## everything here is the seed-derived starting point those would layer onto.

const OCCUPATIONS: Array[String] = ["farmer", "blacksmith", "merchant", "guard", "fisher", "herbalist"]

const PERSONALITY_TRAITS: Array[String] = [
	"friendly", "gruff", "curious", "stoic", "greedy", "kind", "cautious", "bold"
]

## A villager's driving need/goal (npc.md: "NPCs generate requests from
## their actual current needs... rather than a fixed quest-giver script") --
## flavor + a future quest-generation hook, not consumed by anything yet.
const NEEDS: Array[String] = [
	"wants_more_wood", "wants_companionship", "wants_medicine",
	"wants_protection", "wants_rare_ingredients", "wants_news_from_afar",
]

## Two-part deterministic name generator (first + second syllable), enough
## variety to avoid every villager sharing 2-3 names without needing a real
## name corpus.
const _NAME_FIRST: Array[String] = [
	"Al", "Bren", "Cal", "Dor", "El", "Fen", "Gar", "Hal", "Io", "Jor",
	"Kel", "Lira", "Mor", "Nor", "Os", "Per", "Quen", "Rho", "Sil", "Tam",
	"Ul", "Vor", "Wyn", "Yor",
]
const _NAME_SECOND: Array[String] = [
	"a", "an", "ard", "el", "en", "ic", "in", "o", "on", "ric", "ryn", "us", "yn", "wen",
]

## Kept alongside the derived fields below so a renderer can seed this
## villager's visual appearance (see VillageRenderer/HeroAppearance) from the
## same origin without re-deriving one from the name/occupation strings.
var seed_value: int
var npc_name: String
var occupation: String
var personality_trait: String
var need: String


func _init(a_seed_value: int) -> void:
	seed_value = a_seed_value
	npc_name = _NAME_FIRST[_index(seed_value, "name_first", _NAME_FIRST.size())] + \
		_NAME_SECOND[_index(seed_value, "name_second", _NAME_SECOND.size())]
	occupation = OCCUPATIONS[_index(seed_value, "occupation", OCCUPATIONS.size())]
	personality_trait = PERSONALITY_TRAITS[_index(seed_value, "trait", PERSONALITY_TRAITS.size())]
	need = NEEDS[_index(seed_value, "need", NEEDS.size())]


## Seeded pick, routed through a % 10000 reduction first -- Godot's String
## hash can freeze `% count` to one bucket for counts divisible by 3 when
## the salted strings share a suffix (see ProceduralHouseSprite._index's
## fuller note; the 24-entry name pool here is divisible by 3).
func _index(seed_value: int, salt: String, count: int) -> int:
	return (absi(hash("%d_%s" % [seed_value, salt])) % 10000) % count
