extends GutTest

## MushroomBiting (see docs/concept/mushrooms.md's fungivory section).
##
## Pure and content-driven, no engine dependencies -- the same
## constants-plus-static-functions shape TreeRooting/Pollination/
## CrushMechanic already establish for "one small, focused, tested rule".

const MushroomBiting = preload("res://src/gameplay/mushroom_biting.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")


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
