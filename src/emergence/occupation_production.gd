extends RefCounted

## Which CraftingRecipeBook recipe a settlement periodically attempts on
## behalf of a household whose founder holds a given occupation (see
## src/world/npc_identity.gd's OCCUPATIONS and
## src/gameplay/crafting_recipe_book.gd's fixed recipe list) --
## EarthChunkManager.step_settlements' automatic trigger for Emergence
## Phase 5 (see docs/emergence/07-implementation-roadmap.md), closing the
## "nothing calls attempt_production automatically" gap Phase 5 itself
## originally left open.
##
## ALL EIGHT occupations are mapped now, and that widening is the point: an
## occupation with no recipe can never fall short of an input, so its
## household can never produce a shortfall for
## Quest.production_shortfall_quests_for to name. The previous
## hunter/blacksmith-only pair left three quarters of every village with
## nothing real to want and therefore nothing to ever ask a player for.
## "Don't invent what isn't grounded" is still the bar; what changed is that
## it is met by reading each occupation's OWN already-live anchors
## (NpcProduction's producer items, NpcIdentity's work locations,
## docs/concept/taming.md's capture classes) instead of hunting for a recipe
## whose NAME happens to echo an occupation's name.
##
## Three rules bound every entry, each test-pinned rather than asserted in a
## comment (test_occupation_production.gd):
## 1. The recipe id really resolves in a real CraftingRecipeBook.
## 2. The recipe is UNGATED. Market.produce -- the only path this map is ever
##    read through -- calls CraftingRecipeBook.craft directly, which checks
##    inputs ONLY; unlike Player.craft it never consults
##    recipe_required_skill/recipe_requires_structure. A gated recipe here
##    would be a settlement walking straight through a gate a player has to
##    earn, so the heat-gated smelts and the Sägewerk's own Balken/Planke
##    shaping are out on principle, not on taste.
## 3. Every INPUT is reachable without a gate too -- raw (nothing in the book
##    produces it, so the world does) or made by an ungated recipe. The
##    shortfall this map generates is player-facing, and "bring me a plank"
##    is only actionable if a plank isn't itself behind a Sägewerk the
##    market can never raise. This, not preference, is what rules out the
##    otherwise obvious merchant -> "ledger" (plank) and guard -> iron kit
##    (heat-gated ingots).
## Plus one systemic constraint: the eight recipes are DISTINCT, because
## production diversity is a real number a settlement is measured on --
## EarthChunkManager feeds production_counts.size() into
## SettlementTier.tier_for, whose CITY_PRODUCTION_DIVERSITY is 2 -- so two
## occupations sharing a recipe would quietly cost a settlement a tier its
## villagers had genuinely earned.
##
## Per-occupation grounding, in NpcIdentity.OCCUPATIONS order:
## - "farmer" -> "lasso": NpcProduction keys a farmer's real yield to
##   vegetation density -- the same standing grass that plant fibre, the
##   lasso's ONLY input, is harvested from (the lasso recipe's own comment
##   says exactly this) -- and taming.md's capture-class table makes the
##   lasso the Roped tool for "every current herbivore", i.e. the livestock
##   half of farm work. Same single-input shape as hunter -> cooked_meat.
## - "blacksmith" -> "stone_pickaxe": unchanged. A blacksmith crafting tools
##   is the obvious real-world reading of the occupation name, and it is the
##   one tool recipe whose inputs (stick, rock) are entirely gate-free --
##   the iron kit a smith would rather make is not, per rule 3.
## - "merchant" -> "map": NpcIdentity puts a merchant at the "stall", and the
##   only real movement of goods BETWEEN settlements the substrate has is
##   EarthChunkManager's own haul trip from a surplus market to a shortage
##   one -- a route, which is what wayfinding.md's Map is for. "ledger", the
##   closer name match and a merchant's own instrument in
##   player_citizenship.md, needs a plank; see rule 3.
## - "guard" -> "wooden_club": a gate watch -- NpcPlanner keeps a guard, alone
##   among the eight, working the gate through the evening -- needs a weapon,
##   and the club is the only ItemCatalog "weapon" whose whole input list is
##   one raw material. Armour belongs downstream of a smith's smelting
##   anyway, which rule 2 keeps out of a market's reach.
## - "fisher" -> "fishing_rod": NpcProduction already ties a fisher to "fish"
##   and NpcIdentity to the "dock"; the rod is the tackle that catches them
##   (FishingCast/FishingSession). The tool rather than the catch, because
##   fish enters the world through fishing, not through any recipe.
## - "herbalist" -> "butterfly_net": an herbalist works the "garden", and the
##   pollinators a garden runs on -- Pollination/PollinatorForaging model
##   real bees visiting real flowers -- are exactly taming.md's Netted class
##   ("butterflies, bee, small birds"). The net is the only tool in the book
##   pointed at anything that lives in a garden.
## - "hunter" -> "cooked_meat": unchanged, and still the template for the
##   rest: NpcProduction.PRODUCER_ITEM_BY_OCCUPATION (the SEPARATE, already-
##   live gameplay economy) ties hunter to gathering "meat", and
##   cooked_meat's only input IS meat.
## - "nurse" -> "campfire": the one placeable here, and an honest second
##   choice. The obvious recipe for a village-care role is CookingRecipeBook's
##   health_regen dish, and it is unreachable twice over: that book is keyed
##   by sorted INGREDIENT sets and yields dish_ids, not CraftingRecipeBook
##   recipe ids Market.produce can run at all, and ItemCatalog has no "herb"
##   item to cook with in the first place. What is left with real care
##   mechanics under it is the hearth: cold is a genuinely modelled harm
##   (SurvivalMeters.is_cold drains fitness) and the campfire is the heat
##   source both Player._has_heat_source and CampfireCooking recognise --
##   warmth and cooked food, which is what village care amounts to here.
##
## Two honest limits. Nothing here claims a settlement will SUCCEED at these:
## an emergence Market only ever gains stock from its own production output
## or an inbound haul trip, so most attempts fail on empty stock -- which is
## the feature, since attempt_production records that as a real
## production_failed event and Quest turns it into a named, fetchable ask.
## And SettlementTier._SPECIALIZATION_BY_RECIPE still names only cooked_meat
## and stone_pickaxe, so the six recipes added here infer no specialization
## yet; that map is not this file's to widen.
const _RECIPE_BY_OCCUPATION := {
	"farmer": "lasso",
	"blacksmith": "stone_pickaxe",
	"merchant": "map",
	"guard": "wooden_club",
	"fisher": "fishing_rod",
	"herbalist": "butterfly_net",
	"hunter": "cooked_meat",
	"nurse": "campfire",
}


## The recipe_id this occupation's household attempts, or "" if this
## occupation (known or not) has no grounded recipe to attempt.
static func recipe_for(occupation: String) -> String:
	return _RECIPE_BY_OCCUPATION.get(occupation, "")
