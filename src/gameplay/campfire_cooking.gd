extends RefCounted

## Pure cooking-over-fire logic: a raw food id -> its cooked output, gated on
## the presence of a heat source. Deterministic fixed lookup, no RNG. Item ids
## (fish/cooked_fish/cooked_meat) are registered in item_catalog.gd by the
## orchestrator; this table only decides which raw food a campfire transforms.

## raw_item_id -> cooked_item_id. Anything absent cannot be cooked (stays raw).
const _RECIPES := {
	"meat": "cooked_meat",
	"fish": "cooked_fish",
}


## Cooked result for a raw food id, or "" when the item can't be cooked.
func cooked_output(raw_item_id: String) -> String:
	return _RECIPES.get(raw_item_id, "")


## True only when a heat source is present AND the item is actually cookable.
func can_cook(raw_item_id: String, near_campfire: bool) -> bool:
	return near_campfire and _RECIPES.has(raw_item_id)
