extends GutTest

## VillageEstates: docs/concept/village_estates.md mechanism 1 -- the four
## estates a village's households hold, the house tier each lives in, the
## one labour class each supplies, and the basket each consumes per
## household per day.
##
## Pure static table, the same shape OccupationProduction/SettlementTier
## already use. Every tuned value is pinned below by the ORDERING or the
## INVARIANT it produces (a higher estate demands strictly more; every
## basket good is a good the world really produces), never by asserting a
## number somebody liked.

const VillageEstates = preload("res://src/emergence/village_estates.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


func test_the_ladder_runs_cottager_to_burgher():
	assert_eq(VillageEstates.ESTATE_IDS, ["kossaet", "bauer", "handwerker", "buerger"])


func test_a_village_founds_its_households_at_the_bottom_rung():
	assert_eq(VillageEstates.STARTING_ESTATE, "kossaet")
	assert_eq(VillageEstates.ESTATE_IDS[0], VillageEstates.STARTING_ESTATE)


## Rank is what every ordering below is stated in, so it has to be the
## ladder's own index rather than a second list that could drift from it.
func test_rank_is_the_ladders_own_index_and_an_unknown_estate_has_none():
	for index in VillageEstates.ESTATE_IDS.size():
		assert_eq(VillageEstates.rank_of(VillageEstates.ESTATE_IDS[index]), index)
	assert_eq(VillageEstates.rank_of("emperor"), -1)


func test_the_next_estate_up_is_the_next_rung_and_the_top_has_none():
	assert_eq(VillageEstates.next_estate("kossaet"), "bauer")
	assert_eq(VillageEstates.next_estate("handwerker"), "buerger")
	assert_eq(VillageEstates.next_estate("buerger"), "")
	assert_eq(VillageEstates.next_estate("emperor"), "")


func test_the_estate_below_is_the_previous_rung_and_the_bottom_has_none():
	assert_eq(VillageEstates.previous_estate("buerger"), "handwerker")
	assert_eq(VillageEstates.previous_estate("bauer"), "kossaet")
	assert_eq(VillageEstates.previous_estate("kossaet"), "")


## The house tier is a REAL BuildingCatalog house, never an invented one --
## there are exactly three house sheets and the table may not name a fourth.
func test_every_estate_lives_in_a_real_catalog_house():
	for estate in VillageEstates.ESTATE_IDS:
		var house_id: String = VillageEstates.house_id_for(estate)
		assert_true(
			BuildingCatalog.BUILDING_IDS.has(house_id),
			"%s lives in %s, which is not a house the catalog knows" % [estate, house_id]
		)


## A higher estate never lives in a SMALLER house. Two estates sharing a
## tier is the documented, deliberate case (there are three sheets and four
## estates); going backwards is not.
func test_house_tiers_never_go_backwards_up_the_ladder():
	var previous_capacity := -1
	for estate in VillageEstates.ESTATE_IDS:
		var capacity: int = BuildingCatalog.capacity_of(VillageEstates.house_id_for(estate))
		assert_true(
			capacity >= previous_capacity,
			"%s lives smaller than the estate below it" % estate
		)
		previous_capacity = capacity


## Pillar 4: an estate supplies exactly ONE class of labour, and no two
## estates supply the same one -- that is what makes promotion cost the
## rung below rather than merely relabel it.
func test_each_estate_supplies_its_own_distinct_labour_class():
	var seen := {}
	for estate in VillageEstates.ESTATE_IDS:
		var labour_class: String = VillageEstates.labour_class_for(estate)
		assert_ne(labour_class, "", "%s supplies no labour at all" % estate)
		assert_false(seen.has(labour_class), "%s supplies %s twice over" % [estate, labour_class])
		seen[labour_class] = true
	assert_eq(seen.size(), VillageEstates.ESTATE_IDS.size())


func test_labour_classes_lists_exactly_what_the_estates_supply():
	var supplied: Array[String] = []
	for estate in VillageEstates.ESTATE_IDS:
		supplied.append(VillageEstates.labour_class_for(estate))
	assert_eq(VillageEstates.LABOUR_CLASSES, supplied)


## Pillar 5: a basket may only name goods the world really produces, or it
## is a need no village could ever meet. `kind:food` is the one exception
## and it is spelled so it cannot collide with an item id.
func test_every_basket_good_is_a_real_item_or_the_food_kind_token():
	var catalog := ItemCatalog.new()
	for estate in VillageEstates.ESTATE_IDS:
		for good in VillageEstates.basket_goods(estate):
			if good == VillageEstates.FOOD_KIND_TOKEN:
				continue
			assert_true(
				catalog.has(good),
				"%s's basket names %s, which no ItemCatalog entry produces" % [estate, good]
			)


func test_the_food_kind_token_is_not_and_cannot_be_an_item_id():
	assert_false(ItemCatalog.new().has(VillageEstates.FOOD_KIND_TOKEN))


## Every estate has to eat and every estate has to burn fuel: those are the
## two goods a household cannot do without, so both are subsistence for all
## four rungs.
func test_food_and_fuel_are_subsistence_for_every_estate():
	for estate in VillageEstates.ESTATE_IDS:
		var subsistence: Dictionary = VillageEstates.subsistence_basket(estate)
		assert_true(subsistence.has(VillageEstates.FOOD_KIND_TOKEN), "%s eats nothing" % estate)
		assert_true(subsistence.has(VillageEstates.FUEL_ITEM_ID), "%s burns nothing" % estate)


## The bottom rung is subsistence and almost nothing else; every rung above
## it claims a wider station. Pinned as an ordering, not as counts.
func test_each_rung_claims_a_strictly_wider_station_than_the_one_below():
	var previous := -1
	for estate in VillageEstates.ESTATE_IDS:
		var width: int = VillageEstates.station_basket(estate).size()
		assert_true(width > previous, "%s claims no more station than the rung below" % estate)
		previous = width


## A higher estate burns strictly more fuel: a bigger house, a workshop
## hearth, a burgher's rooms.
func test_fuel_demand_rises_strictly_up_the_ladder():
	var previous := -1.0
	for estate in VillageEstates.ESTATE_IDS:
		var fuel: float = VillageEstates.subsistence_basket(estate)[VillageEstates.FUEL_ITEM_ID]
		assert_true(fuel > previous, "%s burns no more than the rung below" % estate)
		previous = fuel


## The whole daily draw rises up the ladder too -- a burgher household is
## strictly more expensive to keep than a cottager one, which is what makes
## promoting everybody a real cost rather than a free win.
func test_the_whole_daily_basket_costs_strictly_more_at_each_rung():
	var previous := -1.0
	for estate in VillageEstates.ESTATE_IDS:
		var total: float = VillageEstates.daily_basket_total(estate)
		assert_true(total > previous, "%s costs the village no more than the rung below" % estate)
		previous = total


func test_subsistence_and_station_never_name_the_same_good_twice():
	for estate in VillageEstates.ESTATE_IDS:
		for good in VillageEstates.station_basket(estate):
			assert_false(
				VillageEstates.subsistence_basket(estate).has(good),
				"%s demands %s as both subsistence and station" % [estate, good]
			)


func test_an_unknown_estate_demands_nothing_rather_than_crashing():
	assert_eq(VillageEstates.subsistence_basket("emperor"), {})
	assert_eq(VillageEstates.station_basket("emperor"), {})
	assert_eq(VillageEstates.daily_basket_total("emperor"), 0.0)


## Mechanism 1's seasonal term, and the one line in this design Anno cannot
## have: fuel is what a village must have banked by autumn.
func test_winter_costs_a_household_strictly_more_fuel_than_summer():
	var winter: float = VillageEstates.seasonal_basket("kossaet", "winter")[VillageEstates.FUEL_ITEM_ID]
	var summer: float = VillageEstates.seasonal_basket("kossaet", "summer")[VillageEstates.FUEL_ITEM_ID]
	assert_true(winter > summer, "a winter hearth burns no more than a summer one")


## Spring and autumn are the unmodified baseline the table itself states,
## so the shoulder seasons are not a third invented number.
func test_the_shoulder_seasons_are_the_tables_own_baseline():
	for season in ["spring", "autumn"]:
		assert_eq(
			VillageEstates.seasonal_basket("bauer", season),
			VillageEstates.subsistence_basket("bauer"),
			"%s is not the plain basket" % season
		)


func test_only_fuel_moves_with_the_season():
	var winter: Dictionary = VillageEstates.seasonal_basket("buerger", "winter")
	var plain: Dictionary = VillageEstates.subsistence_basket("buerger")
	for good in plain:
		if good == VillageEstates.FUEL_ITEM_ID:
			continue
		assert_eq(winter[good], plain[good], "%s moved with the season and should not have" % good)


## The seasons named here are the real SeasonCycle's own, so a renamed
## season can never silently fall through to the baseline.
func test_every_real_season_is_one_this_table_answers_for():
	for season in SeasonCycle.SEASONS:
		assert_true(
			VillageEstates.seasonal_basket("kossaet", season).has(VillageEstates.FUEL_ITEM_ID),
			"%s is a real season this table has no answer for" % season
		)


## Mechanism 6: tax scales with provision -- a well-supplied household has
## a surplus to tax and a destitute one does not.
func test_a_destitute_household_pays_nothing_and_a_provided_one_pays_the_base():
	assert_eq(VillageEstates.tax_per_day("bauer", 0.0), 0.0)
	assert_almost_eq(
		VillageEstates.tax_per_day("bauer", 1.0), VillageEstates.BASE_TAX_PER_DAY["bauer"], 0.0001
	)


func test_tax_rises_strictly_up_the_ladder_at_equal_provision():
	var previous := -1.0
	for estate in VillageEstates.ESTATE_IDS:
		var tax: float = VillageEstates.tax_per_day(estate, 1.0)
		assert_true(tax > previous, "%s pays no more than the rung below" % estate)
		previous = tax


func test_tax_rises_with_provision_within_one_estate():
	assert_true(
		VillageEstates.tax_per_day("handwerker", 1.0) > VillageEstates.tax_per_day("handwerker", 0.5)
	)


func test_an_unknown_estate_is_untaxable_rather_than_free_money():
	assert_eq(VillageEstates.tax_per_day("emperor", 1.0), 0.0)


## A household is worth taxing: whatever the village spends keeping one
## rung, that rung must be able to pay something back, or the ledger can
## only ever run down. Pinned as the relation, not as either number.
func test_every_estate_pays_some_tax_when_fully_provided():
	for estate in VillageEstates.ESTATE_IDS:
		assert_true(VillageEstates.tax_per_day(estate, 1.0) > 0.0, "%s pays nothing ever" % estate)
