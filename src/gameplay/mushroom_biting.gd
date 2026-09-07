extends RefCounted

## What changes when a decomposer bug takes a single bite out of a fruiting
## wild mushroom (see docs/concept/mushrooms.md's fungivory section). Real
## fungivory removes a small bite, not the whole body, so the mushroom stays
## present and pickable, just diminished -- lighter, and visibly marked --
## rather than destroyed outright the way a crushed one is (see
## CrushMechanic / WildMushroomPatch.crush).
##
## Pure and content-driven, no engine dependencies -- the same
## constants-plus-static-functions shape TreeRooting/Pollination/
## CrushMechanic already establish for "one small, focused, tested rule".

## Suffix a bitten mushroom's catalog item id carries, e.g. "parasol" ->
## "parasol_bitten" -- mirrors the existing "meat" -> "cooked_meat" shape of
## a state change becoming its own catalog identity (see ItemCatalog), not a
## mutable flag bolted onto the shared Item: a bitten mushroom's stats are
## fixed the instant it's bitten, unlike wear/captive_species, which keep
## changing over one item's own lifetime.
const BITTEN_SUFFIX := "_bitten"

## How much of a mushroom's original mass survives one bug bite -- a real
## insect bite removes a small fraction of even a small mushroom's body, not
## most of it. Applies uniformly to whatever stat is asked (today just
## mass_kg; see ItemCatalog._mass_kg_for) so a bitten mushroom's stats never
## drift out of proportion with each other. Pinned by
## test_retained_fraction_after_bite_is_pinned.
const RETAINED_FRACTION_AFTER_BITE := 0.83

## How many discrete bite STEPS a fruiting body can take before it is
## genuinely consumed (see docs/concept/soil_fauna.md's "Progressive,
## mass-scaled bites, and real toxic effects"). Not an arbitrary cap: this
## is exactly how many independently-delivered bitten sheets exist per
## species today (most species' own `*_bitten_1/2/3.png` -- see
## IllustratedMushroomSprite), so every stage this whole mechanic can ever
## reach has a real, distinct piece of art to show. death_cap is the one
## exception with only one delivered bitten sheet -- it still has 3 real
## bite STAGES (WildMushroomPatch tracks them the same as any other
## species), it just re-shows that one sheet for stages 2/3 (the same
## has-art-or-doesn't fallback convention every optional illustrated-art
## seam in this codebase already uses).
const MAX_BITE_STAGES := 3


## The catalog item id a bite turns `species_id` into.
static func bitten_item_id_for(species_id: String) -> String:
	return species_id + BITTEN_SUFFIX


## Whether `item_id` already names a bitten variant.
static func is_bitten_item_id(item_id: String) -> bool:
	return item_id.ends_with(BITTEN_SUFFIX)


## The un-bitten species/item id a bitten item id came from, or `item_id`
## unchanged if it wasn't a bitten id at all -- so a caller can always ask
## "what's the base id" without checking is_bitten_item_id first.
static func base_item_id_for(item_id: String) -> String:
	if not is_bitten_item_id(item_id):
		return item_id
	return item_id.substr(0, item_id.length() - BITTEN_SUFFIX.length())


## What a bitten mushroom's mass (or any other stat) becomes, given the
## unbitten baseline.
static func after_bite(base_value: float) -> float:
	return base_value * RETAINED_FRACTION_AFTER_BITE
