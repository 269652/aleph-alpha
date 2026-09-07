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


## -- Bite count and satiation scale with the eater's own real mass --------
##
## Reported live, directly: "the amount the bug eats should be based on
## mass; hunger and calories so a small bug probably only takes a single
## bite... and is satisfied for a few hours... a boar takes multiple
## successive bites which would visibly reduce the mushroom." See
## docs/concept/soil_fauna.md's "Progressive, mass-scaled bites, and real
## toxic effects" for the full real-world grounding this whole section
## implements.

## The two real reference masses this relationship is calibrated against --
## the user's own two concrete examples. Cross-checked by test against
## CreatureMass.mass_kg_for so the two can never silently drift apart;
## kept as separate named constants here (rather than calling CreatureMass
## at read time for every bite) so this module's own tuned thresholds read
## against fixed, known numbers.
const BUG_REFERENCE_MASS_KG := 0.0003
const BOAR_REFERENCE_MASS_KG := 90.0

## Mass thresholds gating bites_per_visit_for -- a plain tiered table, not
## a continuous formula: no real per-species "what fraction of a mouthful
## is one small mushroom" data exists to justify a precise curve, and a
## threshold table is exactly as testable/pinnable while being honest
## about that. Comfortably above insect scale (SMALL) and boar scale
## (LARGE), so both the bug and boar reference masses above land
## unambiguously in their own tier.
const SMALL_EATER_MASS_THRESHOLD_KG := 1.0
const LARGE_EATER_MASS_THRESHOLD_KG := 50.0

## How many of MAX_BITE_STAGES one committed bite EVENT consumes, by the
## eater's own real mass. A bug/ant/mouse-scale eater (under
## SMALL_EATER_MASS_THRESHOLD_KG) takes exactly 1 -- a single small nibble.
## A boar-scale eater (LARGE_EATER_MASS_THRESHOLD_KG and up) takes every
## remaining stage in one visit -- the real "successive bites... would
## visibly reduce the mushroom" the report asked for: one committed bite
## EVENT is modeled as several real bites in quick succession (a chomp, not
## a nibble), rather than restructuring GrazerForaging's whole phase
## machine to loop a single animal back onto the same target for several
## separate bouts.
static func bites_per_visit_for(mass_kg: float) -> int:
	if mass_kg < SMALL_EATER_MASS_THRESHOLD_KG:
		return 1
	if mass_kg < LARGE_EATER_MASS_THRESHOLD_KG:
		return 2
	return MAX_BITE_STAGES


## Real seconds (wall-clock -- the same unit every other timer in
## GrazerForaging/CarrionForageBehavior already runs on: GRAZE_SECONDS,
## REHUNT_SECONDS, etc.) a bug-scale eater stops re-targeting a mushroom
## for after successfully biting one. The report's own "satisfied for a
## few [in-game] hours" reads, against how casually a play session
## narrates elapsed time, as roughly 1-2 real minutes -- NOT the literal
## SeasonCycle.SECONDS_PER_DAY calendar (checked and rejected: that would
## place "a few hours" at real TENS of minutes, clearly longer than what
## "a bug is satisfied for a bit" reads as during actual play). Pinned by
## test_bug_satiation_seconds_is_pinned.
const BUG_SATIATION_SECONDS := 90.0

## Kleiber's law: BMR ~ mass^0.75, i.e. a bigger animal's metabolism runs
## at a LOWER mass-specific rate. If meal energy roughly tracks body mass
## and burn rate tracks mass^0.75, how long that meal lasts tracks
## mass / mass^0.75 = mass^0.25 -- the real, derived (not eyeballed)
## exponent satiation_seconds_for scales by.
const SATIATION_MASS_EXPONENT := 0.25

## Floor so a hypothetically-tinier-than-bug future mass can never derive a
## near-zero or negative satiation window.
const MIN_SATIATION_SECONDS := 10.0

## Real seconds a `mass_kg`-scale eater stays satiated after one successful
## mushroom bite -- see BUG_SATIATION_SECONDS/SATIATION_MASS_EXPONENT's own
## doc comments for the full grounding. A real, derived consequence of the
## formula at boar mass (~2100s / ~35 real minutes), not a separately
## eyeballed "boars wait longer" constant.
static func satiation_seconds_for(mass_kg: float) -> float:
	var seconds: float = BUG_SATIATION_SECONDS * pow(mass_kg / BUG_REFERENCE_MASS_KG, SATIATION_MASS_EXPONENT)
	return maxf(seconds, MIN_SATIATION_SECONDS)
