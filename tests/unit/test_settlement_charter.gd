extends GutTest

## SettlementCharter: docs/concept/settlement_charter.md -- which buildings
## a settlement's own tier entitles it to raise, and what it is still short
## of when it is not.
##
## Asked for directly: a mage guild that only a CITY may build, so helping
## a village grow is how a player gets access to one. The measure is
## SettlementTier's own, unchanged: households, active institutions and
## production diversity, all three crossing together.

const SettlementCharter = preload("res://src/emergence/settlement_charter.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const EstateAscension = preload("res://src/emergence/estate_ascension.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")


func _city() -> Array:
	return [SettlementTier.CITY_HOUSEHOLDS, SettlementTier.CITY_INSTITUTIONS, SettlementTier.CITY_PRODUCTION_DIVERSITY]


func _town() -> Array:
	return [SettlementTier.TOWN_HOUSEHOLDS, SettlementTier.TOWN_INSTITUTIONS, SettlementTier.TOWN_PRODUCTION_DIVERSITY]


func _hamlet() -> Array:
	return [1, 0, 0]


func _refusal(building_id: String, place: Array) -> Dictionary:
	return SettlementCharter.refusal_for(building_id, place[0], place[1], place[2])


# -- the table ------------------------------------------------------------

func test_a_building_with_no_charter_may_be_raised_anywhere():
	assert_eq(SettlementCharter.min_tier_for("house_small"), "")
	assert_eq(_refusal("house_small", _hamlet()), {})


func test_the_mage_guild_is_a_city_building():
	assert_eq(SettlementCharter.min_tier_for("mage_guild"), SettlementTier.CITY)


func test_the_trade_hall_is_a_town_building():
	assert_eq(SettlementCharter.min_tier_for("trade_hall"), SettlementTier.TOWN)


## Every tier named in the table is a real SettlementTier tier -- a charter
## demanding a tier nothing can ever be is a building nobody can ever raise.
func test_every_charter_names_a_real_tier():
	for building_id in SettlementCharter.MIN_TIER_BY_BUILDING:
		assert_true(
			SettlementTier.TIERS.has(SettlementCharter.MIN_TIER_BY_BUILDING[building_id]),
			"%s wants a tier that does not exist" % building_id
		)


## And every chartered building is a real building. A charter on an id
## nothing can build is a rule about nothing.
func test_every_chartered_building_is_a_real_catalog_building():
	for building_id in SettlementCharter.MIN_TIER_BY_BUILDING:
		assert_true(
			BuildingCatalog.has_building(building_id),
			"%s is chartered and is not a building" % building_id
		)


func test_tier_rank_orders_the_real_tiers_and_an_unknown_one_sits_below_them_all():
	assert_eq(SettlementCharter.tier_rank(SettlementTier.HAMLET), 0)
	assert_lt(
		SettlementCharter.tier_rank(SettlementTier.TOWN),
		SettlementCharter.tier_rank(SettlementTier.CITY)
	)
	assert_lt(SettlementCharter.tier_rank(""), 0)


# -- what a place may raise ----------------------------------------------

func test_a_city_may_raise_everything_a_town_may_and_more():
	for building_id in SettlementCharter.MIN_TIER_BY_BUILDING:
		assert_true(
			SettlementCharter.allows(building_id, SettlementTier.CITY),
			"a city was refused %s" % building_id
		)


func test_a_hamlet_is_refused_both_chartered_buildings():
	assert_false(SettlementCharter.allows("trade_hall", SettlementTier.HAMLET))
	assert_false(SettlementCharter.allows("mage_guild", SettlementTier.HAMLET))


func test_a_town_may_raise_its_trade_hall_and_still_not_a_mage_guild():
	assert_true(SettlementCharter.allows("trade_hall", SettlementTier.TOWN))
	assert_false(SettlementCharter.allows("mage_guild", SettlementTier.TOWN))


# -- the refusal that teaches --------------------------------------------

func test_a_place_that_may_build_it_is_refused_nothing():
	assert_eq(_refusal("mage_guild", _city()), {})


## Pillar 3: a refusal names the tier wanted, the tier held, and exactly
## what is short. "You cannot build that here" is a dead end.
func test_a_refusal_names_the_tier_wanted_and_the_tier_held():
	var refusal: Dictionary = _refusal("mage_guild", _hamlet())
	assert_eq(String(refusal["building_id"]), "mage_guild")
	assert_eq(String(refusal["required_tier"]), SettlementTier.CITY)
	assert_eq(String(refusal["tier"]), SettlementTier.HAMLET)


func test_a_refusal_counts_what_is_still_missing_in_every_dimension():
	var refusal: Dictionary = _refusal("mage_guild", [0, 0, 0])
	var short: Dictionary = refusal["short"]
	assert_eq(int(short["households"]), SettlementTier.CITY_HOUSEHOLDS)
	assert_eq(int(short["institutions"]), SettlementTier.CITY_INSTITUTIONS)
	assert_eq(int(short["production_diversity"]), SettlementTier.CITY_PRODUCTION_DIVERSITY)


## A dimension already cleared is short by NOTHING, never by a negative --
## a readout saying "-3 households" is worse than no readout.
func test_a_dimension_already_cleared_is_short_by_nothing():
	var refusal: Dictionary = _refusal("mage_guild", [SettlementTier.CITY_HOUSEHOLDS + 5, 0, 0])
	assert_eq(int(refusal["short"]["households"]), 0)
	assert_gt(int(refusal["short"]["institutions"]), 0)


## The errand a player actually reads: a town one household and one trade
## body short of a city is told exactly that.
func test_a_town_short_of_a_city_is_told_exactly_what_it_needs():
	var refusal: Dictionary = _refusal(
		"mage_guild",
		[SettlementTier.CITY_HOUSEHOLDS - 1, SettlementTier.CITY_INSTITUTIONS - 1, SettlementTier.CITY_PRODUCTION_DIVERSITY]
	)
	assert_eq(int(refusal["short"]["households"]), 1)
	assert_eq(int(refusal["short"]["institutions"]), 1)
	assert_eq(int(refusal["short"]["production_diversity"]), 0)


func test_a_building_nothing_charters_is_never_refused_however_small_the_place():
	assert_eq(_refusal("sawmill", [0, 0, 0]), {})


# -- the distance to the next tier, asked on its own ----------------------

func test_shortfall_to_a_tier_is_the_same_arithmetic_without_a_refusal():
	var short: Dictionary = SettlementCharter.shortfall_to(SettlementTier.CITY, 0, 0, 0)
	assert_eq(int(short["households"]), SettlementTier.CITY_HOUSEHOLDS)
	assert_eq(int(short["institutions"]), SettlementTier.CITY_INSTITUTIONS)
	assert_eq(int(short["production_diversity"]), SettlementTier.CITY_PRODUCTION_DIVERSITY)


func test_a_place_already_at_the_tier_is_short_of_nothing():
	var city := _city()
	var short: Dictionary = SettlementCharter.shortfall_to(SettlementTier.CITY, city[0], city[1], city[2])
	for dimension in short:
		assert_eq(int(short[dimension]), 0, "%s short at a real city" % dimension)


func test_the_lowest_tier_asks_nothing_of_anybody():
	var short: Dictionary = SettlementCharter.shortfall_to(SettlementTier.HAMLET, 0, 0, 0)
	for dimension in short:
		assert_eq(int(short[dimension]), 0, "a hamlet demanded %s" % dimension)


func test_an_unknown_tier_asks_nothing_rather_than_crashing():
	assert_eq(SettlementCharter.shortfall_to("metropolis", 0, 0, 0), {})


## The next rung up from where a place stands, so a readout can name the
## errand without knowing the ladder.
func test_the_next_tier_up_is_named_and_the_top_has_none():
	assert_eq(SettlementCharter.next_tier_above(SettlementTier.HAMLET), SettlementTier.TOWN)
	assert_eq(SettlementCharter.next_tier_above(SettlementTier.TOWN), SettlementTier.CITY)
	assert_eq(SettlementCharter.next_tier_above(SettlementTier.CITY), "")


# -- the anti-deadlock invariant -----------------------------------------

## Pillar 4, as a hard test rather than a promise. A hamlet with no
## farmhouse cannot make husbandmen, cannot diversify its production and
## cannot become a town -- so a farmhouse chartered at TOWN would be a
## village that can never grow, found months later by somebody watching a
## save go nowhere.
func test_nothing_a_settlement_needs_in_order_to_grow_is_gated_behind_growing():
	var must_be_free: Array = []
	must_be_free.append_array(VillageGrowth.LADDER_BUILDING_IDS)
	must_be_free.append_array(BuildingCatalog.BUILDING_IDS)
	for estate in VillageEstates.ESTATE_IDS:
		must_be_free.append_array(EstateAscension.charter_building_ids_for(estate))

	for building_id in must_be_free:
		assert_true(
			SettlementCharter.allows(building_id, SettlementTier.HAMLET),
			"%s is needed to grow and is gated behind having grown" % building_id
		)


## And the warehouse every village is FOUNDED with, which is not on the
## ladder precisely because it is already standing.
func test_the_store_a_village_is_founded_with_is_never_chartered():
	assert_true(SettlementCharter.allows("warehouse", SettlementTier.HAMLET))
