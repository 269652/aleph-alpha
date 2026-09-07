extends GutTest

## MushroomBiting (see docs/concept/mushrooms.md's fungivory section).
##
## Pure and content-driven, no engine dependencies -- the same
## constants-plus-static-functions shape TreeRooting/Pollination/
## CrushMechanic already establish for "one small, focused, tested rule".

const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")


# -- the bitten catalog identity ----------------------------------------------
#
# Mirrors the existing "meat" -> "cooked_meat" shape (ItemCatalog): a state
# change becomes its own catalog item id with its own display name/mass, not
# a mutable flag bolted onto the shared Item the way wear/captive_species
# are -- a bitten mushroom's stats are fixed the instant it's bitten, not
# something that keeps changing over that one item's lifetime.

func test_bitten_item_id_appends_the_suffix():
	assert_eq(MushroomBiting.bitten_item_id_for("parasol"), "parasol_bitten")
	assert_eq(MushroomBiting.bitten_item_id_for("champignon"), "champignon_bitten")


func test_is_bitten_item_id_recognizes_the_suffix():
	assert_true(MushroomBiting.is_bitten_item_id("parasol_bitten"))
	assert_false(MushroomBiting.is_bitten_item_id("parasol"))
	assert_false(MushroomBiting.is_bitten_item_id(""))


func test_base_item_id_strips_the_suffix():
	assert_eq(MushroomBiting.base_item_id_for("parasol_bitten"), "parasol")


## An id that was never bitten passes through unchanged -- callers can
## always ask "what's the base id" without checking is_bitten_item_id first.
func test_base_item_id_passes_through_an_unbitten_id_unchanged():
	assert_eq(MushroomBiting.base_item_id_for("parasol"), "parasol")


## Iterates MushroomSpecies.IDS directly (not a locally hardcoded copy) so
## this never silently goes stale the next time a species is added -- a
## real gap two separate concurrent sessions each hit once already.
func test_bitten_and_base_id_round_trip():
	for species_id in MushroomSpecies.IDS:
		var bitten_id := MushroomBiting.bitten_item_id_for(species_id)
		assert_true(MushroomBiting.is_bitten_item_id(bitten_id), species_id)
		assert_eq(MushroomBiting.base_item_id_for(bitten_id), species_id)


# -- what a bite actually costs -----------------------------------------------

## A single bug bite removes 17% of a mushroom's mass -- applies uniformly
## to whatever stat is asked (today just mass_kg; see ItemCatalog), so a
## bitten mushroom's stats never drift out of proportion with each other.
func test_retained_fraction_after_bite_is_pinned():
	assert_almost_eq(MushroomBiting.RETAINED_FRACTION_AFTER_BITE, 0.83, 0.0001)


func test_after_bite_applies_the_retained_fraction():
	assert_almost_eq(MushroomBiting.after_bite(1.0), 0.83, 0.0001)
	assert_almost_eq(MushroomBiting.after_bite(0.02), 0.02 * 0.83, 0.00001)


## A real single insect bite is a small loss, not most of the mushroom --
## keeps RETAINED_FRACTION_AFTER_BITE from ever being tuned into "basically
## destroyed" territory by accident.
func test_retained_fraction_is_a_small_loss_not_a_large_one():
	assert_gt(MushroomBiting.RETAINED_FRACTION_AFTER_BITE, 0.5, "a bite should not remove most of the mushroom")
	assert_lt(MushroomBiting.RETAINED_FRACTION_AFTER_BITE, 1.0, "a bite must remove something")


# -- bite count and satiation scale with the eater's own real mass ----------
#
# Reported live, directly: "the amount the bug eats should be based on mass;
# hunger and calories so a small bug probably only takes a single bite...
# and is satisfied for a few hours... a boar takes multiple successive
# bites which would visibly reduce the mushroom." See docs/concept/
# soil_fauna.md's "Progressive, mass-scaled bites, and real toxic effects"
# for the full real-world grounding (Kleiber's law for satiation duration).

## The two reference masses this whole relationship is calibrated against
## must never silently drift out of sync with CreatureMass's own real
## entries for the same two species.
func test_reference_masses_match_creature_mass():
	assert_almost_eq(MushroomBiting.BUG_REFERENCE_MASS_KG, CreatureMass.mass_kg_for("bug"), 0.0000001)
	assert_almost_eq(MushroomBiting.BOAR_REFERENCE_MASS_KG, CreatureMass.mass_kg_for("boar"), 0.0001)


## The user's own two concrete examples, exactly: a bug takes a single
## bite, a boar (the user's own example of "bigger") takes several,
## visibly reducing the mushroom faster.
func test_a_bug_takes_a_single_bite():
	assert_eq(MushroomBiting.bites_per_visit_for(CreatureMass.mass_kg_for("bug")), 1)


func test_a_boar_takes_every_remaining_stage_in_one_visit():
	assert_eq(MushroomBiting.bites_per_visit_for(CreatureMass.mass_kg_for("boar")), MushroomBiting.MAX_BITE_STAGES)


## Never below 1 (there is no such thing as less than one bite) and never
## above the real stage cap (there is nothing more to consume once fully
## eaten) -- across a wide real span of masses, not just the two named
## examples.
func test_bites_per_visit_is_always_within_real_bounds():
	for mass_kg in [0.000001, CreatureMass.mass_kg_for("ant"), CreatureMass.mass_kg_for("mouse"), CreatureMass.mass_kg_for("horse"), 10000.0]:
		var bites := MushroomBiting.bites_per_visit_for(mass_kg)
		assert_gte(bites, 1, "mass_kg=%f" % mass_kg)
		assert_lte(bites, MushroomBiting.MAX_BITE_STAGES, "mass_kg=%f" % mass_kg)


## Monotonic: a heavier eater never takes FEWER bites than a lighter one --
## bigger mass, more bites needed per visit, matching the report's own
## framing exactly.
func test_bites_per_visit_is_monotonic_with_mass():
	var ant_bites := MushroomBiting.bites_per_visit_for(CreatureMass.mass_kg_for("ant"))
	var bug_bites := MushroomBiting.bites_per_visit_for(CreatureMass.mass_kg_for("bug"))
	var mouse_bites := MushroomBiting.bites_per_visit_for(CreatureMass.mass_kg_for("mouse"))
	var boar_bites := MushroomBiting.bites_per_visit_for(CreatureMass.mass_kg_for("boar"))
	assert_lte(ant_bites, bug_bites)
	assert_lte(bug_bites, mouse_bites)
	assert_lte(mouse_bites, boar_bites)


## The report's own explicit real-time target for a bug: "satisfied for a
## few [in-game] hours" -- read against how casually a play session narrates
## elapsed time (not the literal SeasonCycle.SECONDS_PER_DAY calendar,
## which would place "a few hours" at real tens of minutes) -- lands at a
## real, testable, pinned 90 real seconds (1.5 real minutes).
func test_bug_satiation_seconds_is_pinned():
	assert_almost_eq(MushroomBiting.satiation_seconds_for(CreatureMass.mass_kg_for("bug")), MushroomBiting.BUG_SATIATION_SECONDS, 0.001)
	assert_almost_eq(MushroomBiting.BUG_SATIATION_SECONDS, 90.0, 0.001)


## Kleiber's law (BMR ~ mass^0.75): a bigger animal's lower mass-specific
## metabolic rate means a meal relative to its own body size lasts
## proportionally longer -- satiation duration ~ mass / mass^0.75 =
## mass^0.25. A real, derived consequence, not a separately eyeballed
## "boars wait longer" number: several real minutes, comfortably longer
## than the bug's 90 seconds, pinned as a range rather than the exact
## transcendental value.
func test_boar_satiation_is_several_real_minutes_and_longer_than_a_bugs():
	var boar_seconds := MushroomBiting.satiation_seconds_for(CreatureMass.mass_kg_for("boar"))
	assert_gt(boar_seconds, MushroomBiting.BUG_SATIATION_SECONDS * 10.0, "a 90kg boar should be satisfied far longer than a 0.3g bug")
	assert_gt(boar_seconds, 60.0 * 20.0, "comfortably more than 20 real minutes")
	assert_lt(boar_seconds, 60.0 * 60.0, "comfortably under a full real hour")


func test_satiation_seconds_is_monotonic_with_mass():
	var bug_seconds := MushroomBiting.satiation_seconds_for(CreatureMass.mass_kg_for("bug"))
	var mouse_seconds := MushroomBiting.satiation_seconds_for(CreatureMass.mass_kg_for("mouse"))
	var boar_seconds := MushroomBiting.satiation_seconds_for(CreatureMass.mass_kg_for("boar"))
	assert_lt(bug_seconds, mouse_seconds)
	assert_lt(mouse_seconds, boar_seconds)


## Floored so a hypothetically-tinier-than-bug future mass can never derive
## a near-zero or negative satiation window.
func test_satiation_seconds_never_drops_below_the_floor():
	assert_gte(MushroomBiting.satiation_seconds_for(0.0000001), MushroomBiting.MIN_SATIATION_SECONDS)
