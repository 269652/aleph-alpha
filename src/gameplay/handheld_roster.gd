extends RefCounted

## Pure data for docs/concept/easter_eggs.md's "hidden retro handheld" entry:
## which of this project's OWN, ALREADY-BUILT wildlife species (see
## src/world/creature_info.gd, AnimalAnatomy.SPECIES) the handheld's
## mini-game can field, at which tier, with what in-battle stats -- and the
## deterministic (roll-in, species-out) encounter picker HandheldBattleView
## uses to decide which wild creature a fresh encounter starts with.
##
## Deliberately NOT the Easter-egg cameo creatures from other stages in this
## doc (squallmaw/coilnecca/champ, or the Germany-region bosses' non-krampus
## members) -- the doc is explicit this stars "miniature... versions of this
## project's own already-built roster", i.e. the real wildlife roster:
## "deer, wolf, boar, bear, lynx at common tiers; krampus/lindwurm/rubezahl
## at rare/legendary tiers". This module only decides WHICH species/tier/
## stats exist -- it never touches rendering (HandheldBattleView draws each
## species with the existing ProceduralAnimalSprite/IllustratedAnimalSprite,
## the exact reuse the doc calls for) or battle rules (HandheldBattle).
##
## A completely SEPARATE, self-contained stat table from CreatureInfo's own
## MAX_HEALTH_BY_SPECIES/etc, deliberately not read from it: this mini-game
## needs its own small, internally-balanced numbers (a "legendary" here is
## simply the stronger of two tiers within a 4-move turn-based battle, not a
## claim about the open world's own combat balance), and "wolf" specifically
## has no entry at all in CreatureInfo today (a pre-existing gap in the open
## world's own wolf wiring, not previously documented anywhere in this
## project -- see docs/progress.md's Easter Eggs section for the full scope
## note) so reaching into that table here would either crash or silently
## fall back to a meaningless default. Zero mechanical weight either way
## (pillar 2): nothing computed here ever touches the real open-world game.

const TIER_COMMON := "common"
const TIER_LEGENDARY := "legendary"

## species -> tier. Exactly the doc's own roster split.
const TIER_BY_SPECIES := {
	"deer": TIER_COMMON,
	"wolf": TIER_COMMON,
	"boar": TIER_COMMON,
	"bear": TIER_COMMON,
	"lynx": TIER_COMMON,
	"krampus": TIER_LEGENDARY,
	"lindwurm": TIER_LEGENDARY,
	"rubezahl": TIER_LEGENDARY,
}

## species -> {hp, attack, defense, speed}. First-pass placeholders (no real
## playtesting data for this project's Easter eggs yet -- same situation
## JoustMatch's own doc comment documents for its own tuned constants), each
## hand-authored with a light real-world grounding matching the same style
## CreatureInfo's own per-species tables use (a bear is tanky and slow; a
## deer is fast and fragile; a lynx is a quick, sharp striker), and pinned by
## the relative-property tests in test_handheld_roster.gd (every legendary
## outclasses every common on hp/attack) rather than left as isolated
## eyeballed literals -- the same "pin the relationship, not just the
## number" discipline test_creature_info.gd's own Kraken/Squallmaw tests use.
const STATS_BY_SPECIES := {
	"deer": {"hp": 26.0, "attack": 7.0, "defense": 5.0, "speed": 13.0},
	"wolf": {"hp": 30.0, "attack": 10.0, "defense": 6.0, "speed": 11.0},
	"boar": {"hp": 34.0, "attack": 9.0, "defense": 8.0, "speed": 7.0},
	"bear": {"hp": 40.0, "attack": 11.0, "defense": 9.0, "speed": 5.0},
	"lynx": {"hp": 24.0, "attack": 9.0, "defense": 5.0, "speed": 14.0},
	"krampus": {"hp": 60.0, "attack": 16.0, "defense": 11.0, "speed": 10.0},
	"lindwurm": {"hp": 70.0, "attack": 14.0, "defense": 13.0, "speed": 8.0},
	"rubezahl": {"hp": 66.0, "attack": 15.0, "defense": 12.0, "speed": 9.0},
}

## Chance (of a roll in [0,1)) that a fresh encounter is drawn from the
## legendary pool rather than the common pool -- "rarer, at higher 'levels'"
## per the doc. A first-pass placeholder, same discipline as every other
## rarity constant in this doc's other entries (see EasterEggCreatures'
## chance_per_check comments).
const LEGENDARY_ENCOUNTER_CHANCE := 0.15


func common_species() -> Array:
	return _species_with_tier(TIER_COMMON)


func legendary_species() -> Array:
	return _species_with_tier(TIER_LEGENDARY)


func all_species() -> Array:
	return TIER_BY_SPECIES.keys()


func _species_with_tier(tier: String) -> Array:
	var out: Array = []
	for species in TIER_BY_SPECIES:
		if TIER_BY_SPECIES[species] == tier:
			out.append(species)
	return out


func tier_for(species: String) -> String:
	return TIER_BY_SPECIES.get(species, "")


func is_legendary(species: String) -> bool:
	return tier_for(species) == TIER_LEGENDARY


## A copy of species' stat block (never the shared const Dictionary, so a
## caller building a battle state off it can freely mutate its own copy) --
## {} for an unregistered species.
func stats_for(species: String) -> Dictionary:
	if not STATS_BY_SPECIES.has(species):
		return {}
	return STATS_BY_SPECIES[species].duplicate()


## Deterministic (roll-in, species-out) encounter pick: `roll` under
## LEGENDARY_ENCOUNTER_CHANCE draws from the legendary pool, otherwise from
## the common pool -- never randf() itself (mirrors EasterEggCreatures'
## check_one, which takes the real roll as a plain caller-supplied float so
## this stays fully unit-testable without a live RandomNumberGenerator).
## Sub-selects WITHIN whichever pool by re-normalizing `roll` to that pool's
## own [0,1) slice of the full range, so every species in a pool is equally
## reachable rather than only ever landing on the pool's first entry.
func encounter_species(roll: float) -> String:
	var clamped := clampf(roll, 0.0, 0.999999)
	if clamped < LEGENDARY_ENCOUNTER_CHANCE:
		var pool := legendary_species()
		var pool_roll := clamped / LEGENDARY_ENCOUNTER_CHANCE
		return pool[clampi(int(pool_roll * pool.size()), 0, pool.size() - 1)]
	var pool := common_species()
	var pool_roll := (clamped - LEGENDARY_ENCOUNTER_CHANCE) / (1.0 - LEGENDARY_ENCOUNTER_CHANCE)
	return pool[clampi(int(pool_roll * pool.size()), 0, pool.size() - 1)]
