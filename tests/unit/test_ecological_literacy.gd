extends GutTest

## Ecological literacy: XP for skillfully engaging real simulation systems,
## not flat per-action grinding (docs/concept/progression.md "Ecological
## literacy"). Pure XP-award arithmetic only -- the real triggers (was the
## fruit at genuine peak ripeness, was the village genuinely hungry) are read
## from FruitingModel/VillageMarket's own real state elsewhere
## (EarthChunkManager.harvest_peak_fruit_near, Player.sell_food_to_village);
## this file covers only the XP numbers, test-pinned named constants per
## CLAUDE.md rather than eyeballed.

const EcologicalLiteracy = preload("res://src/gameplay/ecological_literacy.gd")

var literacy: EcologicalLiteracy


func before_each():
	literacy = EcologicalLiteracy.new()


func test_harvest_xp_pinned_constants():
	assert_eq(EcologicalLiteracy.HARVEST_XP_BASE, 2)
	assert_eq(EcologicalLiteracy.HARVEST_XP_PEAK_BONUS, 4)


func test_harvest_xp_off_peak_awards_the_base_amount():
	assert_eq(literacy.harvest_xp(false), EcologicalLiteracy.HARVEST_XP_BASE)


func test_harvest_xp_at_peak_awards_strictly_more_than_off_peak():
	assert_gt(literacy.harvest_xp(true), literacy.harvest_xp(false))
	assert_eq(
		literacy.harvest_xp(true),
		EcologicalLiteracy.HARVEST_XP_BASE + EcologicalLiteracy.HARVEST_XP_PEAK_BONUS
	)


func test_village_sale_xp_pinned_constants():
	assert_eq(EcologicalLiteracy.VILLAGE_SALE_XP_BASE, 2)
	assert_eq(EcologicalLiteracy.VILLAGE_FEEDING_XP_BONUS, 4)


func test_village_sale_xp_to_a_well_stocked_village_awards_the_base_amount():
	assert_eq(literacy.village_sale_xp(false), EcologicalLiteracy.VILLAGE_SALE_XP_BASE)


func test_village_sale_xp_to_a_hungry_village_awards_strictly_more():
	assert_gt(literacy.village_sale_xp(true), literacy.village_sale_xp(false))
	assert_eq(
		literacy.village_sale_xp(true),
		EcologicalLiteracy.VILLAGE_SALE_XP_BASE + EcologicalLiteracy.VILLAGE_FEEDING_XP_BONUS
	)


## Both "skillfully engaged" totals match Player.XP_PER_KILL (6, a level-1
## creature) -- reading the world correctly is worth about as much as one
## real kill, not a throwaway fraction of it. Named locally (not preloading
## Player, a heavy scene script) but pinned against the real constant's
## known value -- see test_player.gd for Player's own XP_PER_KILL coverage.
func test_skillful_totals_match_the_existing_kill_xp_scale():
	var kill_xp_scale := 6  # Player.XP_PER_KILL
	assert_eq(literacy.harvest_xp(true), kill_xp_scale)
	assert_eq(literacy.village_sale_xp(true), kill_xp_scale)
