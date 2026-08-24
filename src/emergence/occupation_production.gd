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
## Deliberately partial -- same "don't invent what isn't grounded"
## discipline as SettlementState's food-only carrying capacity:
## - "hunter" -> "cooked_meat": NpcProduction.PRODUCER_ITEM_BY_OCCUPATION
##   (the SEPARATE, already-live gameplay economy) already ties hunter to
##   gathering "meat"; cooked_meat's only input IS meat, so this is the same
##   real pairing carried into the emergence substrate, not an invented one.
## - "blacksmith" -> "stone_pickaxe": a blacksmith crafting tools is the
##   obvious real-world reading of the occupation name, and no other recipe
##   in the book is metalworking/tool-adjacent enough to prefer instead.
## The rest (farmer, merchant, guard, fisher, herbalist, nurse) have no
## recipe with a comparably obvious real match -- CraftingRecipeBook has no
## herb, fish, produce, or service-shaped recipe to point them at -- so they
## intentionally produce nothing here rather than being forced onto an
## unrelated recipe.
const _RECIPE_BY_OCCUPATION := {
	"hunter": "cooked_meat",
	"blacksmith": "stone_pickaxe",
}


## The recipe_id this occupation's household attempts, or "" if this
## occupation (known or not) has no grounded recipe to attempt.
static func recipe_for(occupation: String) -> String:
	return _RECIPE_BY_OCCUPATION.get(occupation, "")
