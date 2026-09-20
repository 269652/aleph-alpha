extends GutTest

## GuildRelief: docs/concept/village_estates.md's second novel mechanic --
## the guild chest (Zunftkasse), and the point where the SOCIAL layer
## becomes economically load-bearing rather than bookkeeping.
##
## A guild sets goods aside while its village is supplied, and releases
## them when it is not. One bad season then costs a village its comfort
## instead of its craftsmen, which is what a guild's relief chest was
## actually for -- and, paired with the seasonal fuel term, it produces the
## behaviour nobody wrote: a guild village banks firewood through the
## summer and burns it through the winter.

const GuildRelief = preload("res://src/emergence/guild_relief.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const EstateAscension = preload("res://src/emergence/estate_ascension.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const FUEL := VillageEstates.FUEL_ITEM_ID


# -- the cap: a chest is a season's larder, not a hoard -------------------

## Grounded rather than chosen: a guild banks at most one SEASON's demand,
## which is exactly the horizon the winter fuel term swings over.
func test_a_chest_holds_at_most_one_real_seasons_demand():
	assert_almost_eq(
		GuildRelief.CHEST_HORIZON_DAYS,
		SeasonCycle.DAYS_PER_YEAR / float(SeasonCycle.SEASONS.size()),
		0.0001
	)


func test_the_cap_is_that_horizon_times_what_the_village_uses_in_a_day():
	assert_almost_eq(GuildRelief.cap_for(2.0), 2.0 * GuildRelief.CHEST_HORIZON_DAYS, 0.0001)


func test_a_good_the_village_never_uses_has_no_cap_and_is_never_banked():
	assert_almost_eq(GuildRelief.cap_for(0.0), 0.0, 0.0001)


# -- setting aside --------------------------------------------------------

func test_a_supplied_village_banks_a_share_of_what_is_left_on_the_shelf():
	var result: Dictionary = GuildRelief.set_aside(
		{FUEL: 100.0}, {FUEL: 2.0}, {}, true
	)
	assert_true(float(result["chest"].get(FUEL, 0.0)) > 0.0, "a supplied guild banked nothing")
	assert_true(
		float(result["stock"][FUEL]) < 100.0, "the goods were banked without leaving the shelf"
	)


## Nothing is created: what the chest gains, the shelf loses, exactly.
func test_banking_moves_goods_and_never_creates_them():
	var result: Dictionary = GuildRelief.set_aside({FUEL: 60.0}, {FUEL: 1.0}, {}, true)
	assert_almost_eq(
		float(result["stock"][FUEL]) + float(result["chest"][FUEL]), 60.0, 0.0001
	)


## You do not stockpile while your own people go short.
func test_a_village_that_is_not_supplied_banks_nothing():
	var result: Dictionary = GuildRelief.set_aside({FUEL: 100.0}, {FUEL: 2.0}, {}, false)
	assert_eq(result["chest"], {})
	assert_almost_eq(float(result["stock"][FUEL]), 100.0, 0.0001)


func test_a_chest_never_fills_past_its_own_cap():
	var chest := {FUEL: GuildRelief.cap_for(1.0)}
	var result: Dictionary = GuildRelief.set_aside({FUEL: 999.0}, {FUEL: 1.0}, chest, true)
	assert_almost_eq(float(result["chest"][FUEL]), GuildRelief.cap_for(1.0), 0.0001)
	assert_almost_eq(float(result["stock"][FUEL]), 999.0, 0.0001, "a full chest still took goods")


## A chest is for what the village actually eats and burns -- never for
## whatever happens to be lying in the store.
func test_a_chest_never_banks_a_good_the_village_has_no_use_for():
	var result: Dictionary = GuildRelief.set_aside({"stone": 500.0}, {FUEL: 1.0}, {}, true)
	assert_false(result["chest"].has("stone"), "the guild banked building rubble")
	assert_almost_eq(float(result["stock"]["stone"]), 500.0, 0.0001)


func test_banking_takes_only_a_share_so_the_shelf_is_never_stripped():
	var result: Dictionary = GuildRelief.set_aside({FUEL: 10.0}, {FUEL: 100.0}, {}, true)
	assert_true(
		float(result["stock"][FUEL]) > 0.0,
		"the guild took the whole shelf and left the village with nothing"
	)


func test_the_callers_own_stock_and_chest_are_left_untouched():
	var stock := {FUEL: 50.0}
	var chest := {}
	GuildRelief.set_aside(stock, {FUEL: 1.0}, chest, true)
	assert_almost_eq(float(stock[FUEL]), 50.0, 0.0001)
	assert_eq(chest, {})


# -- releasing ------------------------------------------------------------

func test_a_full_chest_covers_a_shortfall_outright():
	var result: Dictionary = GuildRelief.relieve({FUEL: 0.0}, {FUEL: 4.0}, {FUEL: 40.0})
	assert_almost_eq(float(result["satisfaction"][FUEL]), 1.0, 0.0001)
	assert_almost_eq(float(result["released"][FUEL]), 4.0, 0.0001)
	assert_almost_eq(float(result["chest"][FUEL]), 36.0, 0.0001)


func test_a_half_full_chest_covers_half_of_it():
	var result: Dictionary = GuildRelief.relieve({FUEL: 0.0}, {FUEL: 4.0}, {FUEL: 2.0})
	assert_almost_eq(float(result["satisfaction"][FUEL]), 0.5, 0.0001)
	assert_false(result["chest"].has(FUEL), "an emptied chest still holds something")


func test_an_empty_chest_relieves_nobody():
	var result: Dictionary = GuildRelief.relieve({FUEL: 0.25}, {FUEL: 4.0}, {})
	assert_almost_eq(float(result["satisfaction"][FUEL]), 0.25, 0.0001)
	assert_eq(result["released"], {})


func test_relief_tops_a_partial_supply_up_rather_than_starting_over():
	var result: Dictionary = GuildRelief.relieve({FUEL: 0.75}, {FUEL: 4.0}, {FUEL: 40.0})
	assert_almost_eq(float(result["satisfaction"][FUEL]), 1.0, 0.0001)
	assert_almost_eq(float(result["released"][FUEL]), 1.0, 0.0001, "the chest paid for what was already supplied")


func test_a_good_already_fully_supplied_draws_nothing_from_the_chest():
	var result: Dictionary = GuildRelief.relieve({FUEL: 1.0}, {FUEL: 4.0}, {FUEL: 40.0})
	assert_eq(result["released"], {})
	assert_almost_eq(float(result["chest"][FUEL]), 40.0, 0.0001)


func test_relief_never_pushes_a_good_past_fully_supplied():
	var result: Dictionary = GuildRelief.relieve({FUEL: 0.5}, {FUEL: 2.0}, {FUEL: 900.0})
	assert_almost_eq(float(result["satisfaction"][FUEL]), 1.0, 0.0001)
	assert_almost_eq(float(result["released"][FUEL]), 1.0, 0.0001)


func test_relief_leaves_the_callers_own_chest_untouched():
	var chest := {FUEL: 40.0}
	GuildRelief.relieve({FUEL: 0.0}, {FUEL: 4.0}, chest)
	assert_almost_eq(float(chest[FUEL]), 40.0, 0.0001)


# -- the whole point ------------------------------------------------------

## A village with no guild -- no chest, nothing banked -- comes out of both
## calls exactly as it went in. The mechanic can never change a village
## that has no guild to run it.
func test_a_village_with_no_guild_is_completely_unaffected():
	var satisfaction := {FUEL: 0.3}
	var relieved: Dictionary = GuildRelief.relieve(satisfaction, {FUEL: 4.0}, {})
	assert_eq(relieved["satisfaction"], satisfaction)
	var banked: Dictionary = GuildRelief.set_aside({FUEL: 40.0}, {}, {}, true)
	assert_eq(banked["stock"], {FUEL: 40.0})
	assert_eq(banked["chest"], {})


## The claim the mechanic exists for, end to end: a village that would have
## dropped below the subsistence floor -- and started unmaking its
## craftsmen -- does not, because the guild banked for it.
func test_a_guild_carries_its_village_over_the_floor_a_bad_season_would_drop_it_under():
	var daily := {FUEL: 4.0}
	var chest := {}
	# Banked through a supplied stretch.
	for _day in 20:
		var banked: Dictionary = GuildRelief.set_aside({FUEL: 40.0}, daily, chest, true)
		chest = banked["chest"]

	var bad_season := {FUEL: 0.1}
	assert_true(
		float(bad_season[FUEL]) < EstateAscension.SUBSISTENCE_FLOOR,
		"precondition: this really is a season that would cost the village its standing"
	)
	var relieved: Dictionary = GuildRelief.relieve(bad_season, daily, chest)
	assert_true(
		float(relieved["satisfaction"][FUEL]) >= EstateAscension.SUBSISTENCE_FLOOR,
		"the guild's chest did not carry its village over the floor"
	)
