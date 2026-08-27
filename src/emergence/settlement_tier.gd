extends RefCounted

## A settlement's town/city classification, and what it specializes in --
## both derived from REAL flows already tracked in the substrate, never a
## static content tag (docs/emergence/04-settlements-cities-infrastructure.md
## "City threshold": "Use multiple dimensions rather than population alone:
## population density, economic specialization, institutional complexity,
## infrastructure density, trade connectivity, and administrative
## capacity." "Specialization": "Infer specialization from persistent
## production and trade... Do not store specialization as a static content
## tag when it can be derived from flows.")
##
## Deliberately narrow, same "don't invent what isn't grounded" discipline
## as every prior phase: of the six named dimensions, only THREE have real
## data behind them today -- population (household count, Phase 3/7),
## economic specialization (production history, Phase 5), and institutional
## complexity (active institution count, Phase 6). Infrastructure density
## (Phase 8's paths), trade connectivity (cross-SETTLEMENT trade -- Phase
## 4's automatic trigger is intra-settlement only, between two households
## of the SAME settlement), and administrative capacity (no governance/
## authority concept exists) are explicitly deferred rather than guessed at.

const HAMLET := "hamlet"
const TOWN := "town"
const CITY := "city"
const TIERS := [HAMLET, TOWN, CITY]

## Thresholds tested against the classification they produce
## (test_settlement_tier.gd), not any specific "correct" population -- there
## is no real economy data yet to derive one from, the same honesty
## InstitutionFormation.FORMATION_THRESHOLD's own doc comment states.
const TOWN_HOUSEHOLDS := 3
const TOWN_INSTITUTIONS := 1
const TOWN_PRODUCTION_DIVERSITY := 1

const CITY_HOUSEHOLDS := 6
const CITY_INSTITUTIONS := 2
const CITY_PRODUCTION_DIVERSITY := 2


## ALL THREE dimensions must cross together -- population alone is
## deliberately never sufficient by itself, the doc's own explicit point.
static func tier_for(households: int, active_institutions: int, production_diversity: int) -> String:
	if (
		households >= CITY_HOUSEHOLDS
		and active_institutions >= CITY_INSTITUTIONS
		and production_diversity >= CITY_PRODUCTION_DIVERSITY
	):
		return CITY
	if (
		households >= TOWN_HOUSEHOLDS
		and active_institutions >= TOWN_INSTITUTIONS
		and production_diversity >= TOWN_PRODUCTION_DIVERSITY
	):
		return TOWN
	return HAMLET


## Human-readable specializations for the recipes OccupationProduction
## actually grounds (see that module's own doc comment for why only these
## two exist) -- the same small, honest, documented mapping discipline, not
## a made-up archetype list with nothing real behind most of it.
const _SPECIALIZATION_BY_RECIPE := {
	"cooked_meat": "hunting center",
	"stone_pickaxe": "manufacturing town",
}


## The dominant specialization inferred from REAL production counts
## (recipe_id -> times successfully produced) -- "derived from flows," not
## a stored tag. The most-produced recipe wins; a tie breaks toward
## whichever recipe id sorts first, so the result is deterministic rather
## than depending on Dictionary iteration order. "" for a settlement with no
## successful production yet, or whose dominant recipe has no mapped
## specialization.
static func specialization_for(production_counts: Dictionary) -> String:
	var recipe_ids := production_counts.keys()
	recipe_ids.sort()
	var best_recipe := ""
	var best_count := 0
	for recipe_id in recipe_ids:
		var count: int = production_counts[recipe_id]
		if count > best_count:
			best_count = count
			best_recipe = recipe_id
	return _SPECIALIZATION_BY_RECIPE.get(best_recipe, "")
