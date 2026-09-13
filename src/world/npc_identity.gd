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
##
## personality_trait is DNA derived (npc.md follow-up ask), not its own
## independent flat roll: it is exactly `genome.dominant_trait()` -- see
## NpcGenome's own doc comment for why that genome's shape (a plain String
## -> float traits Dictionary) is already what a future NPC child-
## inheritance pass would need, not a placeholder.

const NpcGenome = preload("res://src/world/npc_genome.gd")
const SkillWeb = preload("res://src/gameplay/skill_web.gd")
const NpcSkillAllocation = preload("res://src/world/npc_skill_allocation.gd")

## "hunter" and "nurse" (docs/concept/npc.md "Needs and the local production
## economy") joined this pass: hunter is a producer occupation distinct from
## farmer (gathers wild game, not tended crops); nurse is a new non-producer
## village-care role. Adding to this array reshuffles which seed rolls which
## OTHER occupation too (see NpcIdentity._index's modulo pick) -- every
## existing occupation test loops the module's own const arrays rather than
## hardcoding a seed->occupation expectation, so that reshuffle is harmless.
const OCCUPATIONS: Array[String] = [
	"farmer", "blacksmith", "merchant", "guard", "fisher", "herbalist", "hunter", "nurse",
]

## Which location_tag an occupation works at during the day -- the single
## shared source both NpcPlanner.FakeNpcPlanner (which tag a villager's
## schedule sends them to) and VillageRenderer (which landmark prop, if any,
## actually stands there -- see ProceduralLandmarkSprite's field/forge/dock/
## garden props) read from, so the two can never drift apart the way two
## independently hand-maintained copies of the same mapping eventually
## would. "stall", "gate" and "well" are three of the settlement's 3
## always-present shared landmarks (see SettlementGenerator), so merchant/
## guard/nurse already have something real there without any extra
## per-villager prop; farmer/blacksmith/fisher/herbalist/hunter did not
## until VillageRenderer started rendering one at each such villager's own
## workspot (reported: the previous personal-stand-only pass left "no
## per-occupation building beyond the shared landmarks and a merchant's own
## stand" as a known gap). hunter's own "hunting_ground" tag has no
## dedicated art of its own yet -- ProceduralLandmarkSprite falls back to
## the well sprite for any unrecognized landmark id, so a hunter's workspot
## still gets a real, visible (if not yet bespoke) prop rather than nothing.
const WORK_LOCATION_BY_OCCUPATION := {
	"farmer": "field",
	"blacksmith": "forge",
	"merchant": "stall",
	"guard": "gate",
	"fisher": "dock",
	"herbalist": "garden",
	"hunter": "hunting_ground",
	"nurse": "well",
}

const PERSONALITY_TRAITS: Array[String] = [
	"friendly", "gruff", "curious", "stoic", "greedy", "kind", "cautious", "bold"
]

## Drives how many real skill-web points this NPC ever invests (see
## NpcSkillAllocation.allocate) -- deliberately a SEPARATE genome from
## `genome`/PERSONALITY_TRAITS above, never added to that list: this gene
## must never be eligible to become an NPC's own dominant PERSONALITY trait
## (dominant_trait() picks whichever gene in ITS OWN genome rolled highest,
## with no concept of "this one doesn't count"). Renamed from this field's
## own first-pass name, `carpentry_aptitude`: it now drives investment in
## WHICHEVER archetype this NPC's own occupation walks (see
## NpcSkillAllocation.ARCHETYPE_BY_OCCUPATION), not carpentry specifically
## -- a guard or merchant "specializing" reads this same trait, just into a
## different wedge. An innate, fixed-at-birth dedication, not a skill that
## grows from doing real work -- labor_skills.md's own larger "NPCs accrue
## skill from real work" vision stays exactly as unbuilt as it already was;
## this is honestly an MVP, not that finished design.
const SKILL_TRAITS: Array[String] = ["vocational_dedication"]

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
var genome: NpcGenome
var personality_trait: String
var need: String
## Which SkillWeb archetype this NPC's own occupation walks (docs/concept/
## workforce.md: "the Skill Web should also be available for NPCs...
## preference... based on personality and class") -- see
## NpcSkillAllocation.ARCHETYPE_BY_OCCUPATION for the full reasoning.
var archetype: String
## This NPC's own real allocated_nodes for that archetype, on the SAME
## SkillWeb graph the player uses (see NpcSkillAllocation.allocate) --
## exposed generally, not just for carpentry, so any other real stat this
## project already wires a skill-web node to (mining_yield, wound_
## recovery, trade_margin, ...) already has a real per-NPC number to read
## the same way carpentry_level does below.
var allocated_nodes: Dictionary
## Real, deterministic, read straight off allocated_nodes via the SAME
## SkillWeb.total_bonus the player's own Carpentry stat reads (empty
## resonance -- NPCs have no DNA-resonance system of their own, so every
## node pays/grants exactly its face-value cost/bonus). An NPC who
## specializes here (see NpcSkillAllocation) reaches the EXACT SAME numbers
## a player would, including the Artisan wedge's own real `master_joiner`
## notable -- no separate, lower ceiling for NPCs than for the player, and
## in particular no fixed [0, 2) cap: this field's own first-pass formula
## (`skill_genome.traits["carpentry_aptitude"] * 2.0`) was replaced outright
## once a real NPC skill web made that cap unnecessary, per a direct
## request ("make it so it's not capped... there should be NPCs
## specializing in Carpentry").
var carpentry_level: float


func _init(a_seed_value: int) -> void:
	seed_value = a_seed_value
	npc_name = _NAME_FIRST[_index(seed_value, "name_first", _NAME_FIRST.size())] + \
		_NAME_SECOND[_index(seed_value, "name_second", _NAME_SECOND.size())]
	occupation = OCCUPATIONS[_index(seed_value, "occupation", OCCUPATIONS.size())]
	genome = NpcGenome.new(seed_value, PERSONALITY_TRAITS)
	personality_trait = genome.dominant_trait()
	need = NEEDS[_index(seed_value, "need", NEEDS.size())]
	var skill_genome := NpcGenome.new(seed_value, SKILL_TRAITS)
	archetype = String(NpcSkillAllocation.ARCHETYPE_BY_OCCUPATION.get(occupation, "artisan"))
	var skill_web = SkillWeb.shared()
	allocated_nodes = NpcSkillAllocation.allocate(
		skill_web, archetype, seed_value, skill_genome.traits["vocational_dedication"]
	)
	carpentry_level = skill_web.total_bonus("carpentry_level", allocated_nodes, {}, seed_value)


## Seeded pick, routed through a % 10000 reduction first -- Godot's String
## hash can freeze `% count` to one bucket for counts divisible by 3 when
## the salted strings share a suffix (see ProceduralHouseSprite._index's
## fuller note; the 24-entry name pool here is divisible by 3).
func _index(seed_value: int, salt: String, count: int) -> int:
	return (absi(hash("%d_%s" % [seed_value, salt])) % 10000) % count
