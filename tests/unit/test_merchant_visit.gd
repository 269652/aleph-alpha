extends GutTest

## MerchantVisit: docs/concept/traveling_merchants.md -- the outside world
## arriving on foot, buying what a village made and paying real gold for
## it.
##
## This is the faucet that replaces NpcProduction.YIELD_TO_GOLD_RATE's
## placeholder, which conjured a coin per food unit gathered whether or not
## anyone ever bought it. Pure and static, no world, no state.

const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")

## One simulated day, in real seconds -- the module's OWN day, so these
## tests go on measuring "a day of draw" whatever that day is worth. It
## used to be a literal 3600, which is ConstructionCatchup's offscreen
## catch-up day and was never this module's to borrow. The identical
## correction test_village_immigration.gd already made for itself.
const _DAY := MerchantVisit.SECONDS_PER_SIMULATED_DAY


# -- the buy list is real goods at grounded prices -------------------------

func test_every_buyable_good_is_a_real_item_the_village_can_actually_make():
	var catalog := ItemCatalog.new()
	assert_false(MerchantVisit.buy_list().is_empty())
	for item_id in MerchantVisit.buy_list():
		assert_true(catalog.has(item_id), "%s is not a real item" % item_id)
		assert_gt(MerchantVisit.price_of(item_id), 0, "%s must be worth something" % item_id)


func test_a_good_nobody_deals_in_is_worth_nothing_rather_than_a_guess():
	assert_eq(MerchantVisit.price_of("iron_sword"), 0)
	assert_eq(MerchantVisit.price_of("moon_rock"), 0)


## Sawn timber is priced off the sawmill's OWN real conversion rate, not a
## guess: a Balken costs LOG_COST_PER_BEAM logs and a Planke
## LOG_COST_PER_PLANK, so a beam is worth exactly that ratio more.
func test_sawn_timber_is_priced_by_the_sawmills_own_conversion_rate():
	var expected_ratio := SagewerkProduction.LOG_COST_PER_BEAM / SagewerkProduction.LOG_COST_PER_PLANK
	assert_almost_eq(
		float(MerchantVisit.price_of("beam")) / float(MerchantVisit.price_of("plank")),
		expected_ratio, 0.001, "a beam is worth what its logs are worth"
	)
	assert_gt(MerchantVisit.price_of("plank"), MerchantVisit.price_of("wood"), "sawing adds value")


## The margin is the merchant's reason to exist: he pays the farm gate, not
## the town price.
func test_the_farm_gate_price_is_below_what_the_same_good_fetches_in_town():
	assert_lt(
		MerchantVisit.price_of("meat"), Shop.CATALOG["cooked_meat"],
		"raw meat at the farm gate must be under prepared meat in a shop"
	)
	for food_id in ["fish", "meat", "fruit"]:
		assert_lt(
			MerchantVisit.price_of(food_id), VillageMarket.VILLAGE_LOCAL_FOOD_PRICE,
			"%s must be under what a villager pays for a meal of it" % food_id
		)


# -- arrivals --------------------------------------------------------------

func _arrival(seconds: float, stock: Dictionary, carry: float) -> Dictionary:
	return MerchantVisit.arrivals(seconds, stock, carry)


func test_a_village_with_nothing_to_sell_is_never_visited():
	var out := _arrival(_DAY * 50.0, {}, 0.0)
	assert_false(out["arrived"], "a merchant does not walk to a village with nothing in it")


func test_a_village_holding_only_things_he_does_not_buy_is_never_visited():
	var out := _arrival(_DAY * 50.0, {"iron_sword": 40.0}, 0.0)
	assert_false(out["arrived"])


func test_a_village_with_goods_is_eventually_visited():
	var out := _arrival(_DAY * 50.0, {"fish": 30.0}, 0.0)
	assert_true(out["arrived"])


func test_no_elapsed_time_means_no_visit_and_an_untouched_carry():
	var out := _arrival(0.0, {"fish": 30.0}, 0.4)
	assert_false(out["arrived"])
	assert_almost_eq(float(out["carry"]), 0.4, 0.0001)


func test_a_village_with_nothing_to_sell_keeps_its_carry():
	var out := _arrival(_DAY, {}, 0.7)
	assert_almost_eq(float(out["carry"]), 0.7, 0.0001, "the wait is not lost, there is just nothing to buy")


func test_a_bigger_surplus_draws_a_merchant_sooner():
	var lean := 0.0
	var rich := 0.0
	var lean_visits := 0
	var rich_visits := 0
	for i in 200:
		var a := _arrival(_DAY * 0.25, {"fish": 2.0}, lean)
		lean = a["carry"]
		if a["arrived"]:
			lean_visits += 1
		var b := _arrival(_DAY * 0.25, {"fish": 500.0}, rich)
		rich = b["carry"]
		if b["arrived"]:
			rich_visits += 1
	assert_gt(rich_visits, lean_visits, "a village sitting on a surplus is worth the detour")


func test_the_carry_is_always_a_real_fraction():
	var carry := 0.0
	for i in 100:
		var out := _arrival(_DAY * 0.3, {"fish": 20.0}, carry)
		carry = out["carry"]
		assert_between(carry, 0.0, 1.0)


# -- the sale --------------------------------------------------------------

func test_a_purchase_pays_for_exactly_what_it_takes():
	var result: Dictionary = MerchantVisit.purchase({"fish": 5.0})
	assert_eq(int(result["bought"].get("fish", 0)), 5)
	assert_eq(int(result["paid"]), 5 * MerchantVisit.price_of("fish"))


func test_a_purchase_never_mutates_the_stock_it_was_shown():
	var stock := {"fish": 5.0}
	MerchantVisit.purchase(stock)
	assert_eq(stock, {"fish": 5.0}, "the caller moves the goods, not this")


func test_only_whole_units_are_bought():
	var result: Dictionary = MerchantVisit.purchase({"fish": 2.7})
	assert_eq(int(result["bought"].get("fish", 0)), 2, "half a fish is not a sale")


func test_goods_he_does_not_deal_in_are_left_alone():
	var result: Dictionary = MerchantVisit.purchase({"iron_sword": 9.0, "fish": 1.0})
	assert_false(result["bought"].has("iron_sword"))
	assert_eq(int(result["bought"].get("fish", 0)), 1)


## The cart is finite, which is what stops a hoard becoming a windfall.
func test_a_cart_only_holds_so_much():
	var result: Dictionary = MerchantVisit.purchase({"fish": 10000.0})
	assert_eq(int(result["bought"]["fish"]), MerchantVisit.CART_CAPACITY)


## And he fills it with the valuable goods first.
func test_a_full_cart_is_filled_with_the_dearest_goods_first():
	var plenty := float(MerchantVisit.CART_CAPACITY)
	var result: Dictionary = MerchantVisit.purchase({"fish": plenty, "beam": plenty})
	assert_eq(int(result["bought"].get("beam", 0)), MerchantVisit.CART_CAPACITY, "beams before fish")
	assert_eq(int(result["bought"].get("fish", 0)), 0)


func test_an_empty_village_sells_nothing_and_is_paid_nothing():
	var result: Dictionary = MerchantVisit.purchase({})
	assert_true(result["bought"].is_empty())
	assert_eq(int(result["paid"]), 0)


func test_nothing_is_created_or_destroyed_by_a_sale():
	var result: Dictionary = MerchantVisit.purchase({"fish": 3.0, "beam": 2.0, "hide": 1.0})
	var owed := 0
	for item_id in result["bought"]:
		owed += int(result["bought"][item_id]) * MerchantVisit.price_of(item_id)
	assert_eq(int(result["paid"]), owed, "the gold paid is exactly the goods taken")


# -- surplus, not stock ------------------------------------------------------
# Measured on a real loaded village (tools/probe_village_growth.gd): a
# merchant took its wood away every few minutes, so its stone climbed
# steadily to 37 while its wood never once got past 2, its house_small
# project sat PLANNED with nothing reserved for the whole run, and a village
# that grew from 10 households to 31 built not one house for any of them.
# SettlementGathering is the only thing in the game that puts wood into a
# settlement's market, and `wood` is on the buy list.

func test_a_merchant_never_buys_what_the_village_is_saving_for():
	var stock := {"wood": 12.0}
	var sale: Dictionary = MerchantVisit.purchase(stock, {"wood": 12})
	assert_eq(int(sale["bought"].get("wood", 0)), 0, "the timber for its own next house is not surplus")
	assert_eq(int(sale["paid"]), 0, "and nothing is paid for it")


func test_a_merchant_buys_only_what_is_over_the_reserve():
	var sale: Dictionary = MerchantVisit.purchase({"wood": 20.0}, {"wood": 12})
	assert_eq(int(sale["bought"].get("wood", 0)), 8, "eight over the twelve it is saving")


func test_a_village_saving_for_nothing_sells_as_it_always_did():
	var sale: Dictionary = MerchantVisit.purchase({"wood": 20.0}, {})
	assert_eq(int(sale["bought"].get("wood", 0)), 20)
	assert_eq(sale, MerchantVisit.purchase({"wood": 20.0}), "an omitted reserve reserves nothing")


## A reserve on one good never holds back another: a village saving timber
## still sells its fish.
func test_a_reserve_on_one_good_does_not_hold_back_another():
	var sale: Dictionary = MerchantVisit.purchase({"wood": 5.0, "fish": 5.0}, {"wood": 12})
	assert_eq(int(sale["bought"].get("wood", 0)), 0)
	assert_eq(int(sale["bought"].get("fish", 0)), 5)


## And the VISIT is gated on the same reading: a merchant does not walk to a
## village whose every plank is already spoken for.
func test_a_merchant_does_not_walk_to_a_village_with_nothing_spare():
	var result: Dictionary = MerchantVisit.arrivals(
		1.0e6, {"wood": 12.0}, 0.0, {"wood": 12}
	)
	assert_false(result["arrived"], "nothing to buy is nothing to buy")


func test_a_merchant_still_walks_to_a_village_with_a_real_surplus():
	var result: Dictionary = MerchantVisit.arrivals(
		1.0e6, {"wood": 40.0}, 0.0, {"wood": 12}
	)
	assert_true(result["arrived"])


# -- nothing the village makes is unsellable -------------------------------
#
# This file's own doc states it as design pillar 3: *"They buy what a
# village actually produces... nothing the village makes is unsellable."*
# It was not true. The buy list was hand-written and the village kept growing
# past it -- a herbalist's crop, a farmer's wheat, a felled log, gathered
# stone and plant fibre all arrived after it was written and none was ever
# added.
#
# Measured (tools/probe_village_purse.gd) on a real village after 1200
# simulated seconds, standing where _step_merchant_visits stands:
#
#     herb               117  kind=food       merchant refuses
#     log                 24  kind=material   merchant refuses
#     wheat                5  kind=material   merchant refuses
#     stone                5  kind=material   merchant refuses
#     plant_fibre          1  kind=material   merchant refuses
#     wood                10  kind=material   merchant BUYS @1
#     sellable after reserve : 0     (reserve {"wood": 12})
#     villagers' purse 0.0 gold | merchant's purse 0.0 gold
#
# One of nine ids was sellable, and all ten of those units were spoken for
# by the village's own next house. A merchant is the ONLY faucet gold has,
# so a village that makes nothing he buys has no income at all, forever --
# which is exactly what "all villagers have 0 gold" was reported as.

const NpcProduction = preload("res://src/world/npc_production.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const SettlementGathering = preload("res://src/emergence/settlement_gathering.gd")


## The invariant itself, made structural rather than aspirational.
func test_everything_a_villages_own_producers_make_is_sellable():
	var produce: Array = MerchantVisit.village_produce()
	assert_false(produce.is_empty(), "the premise: a village makes something")
	for item_id in produce:
		assert_true(
			MerchantVisit.buy_list().has(item_id),
			"a village makes %s and no merchant will buy it" % item_id
		)
		assert_gt(MerchantVisit.price_of(item_id), 0, "%s must be worth something" % item_id)


## ...and the produce list is read off the producers' OWN maps, never a
## second hand-written list, because a second list is precisely what drifted.
func test_the_produce_list_is_the_producers_own_maps():
	var produce: Array = MerchantVisit.village_produce()
	for occupation in NpcProduction.PRODUCER_ITEM_BY_OCCUPATION:
		assert_true(
			produce.has(String(NpcProduction.PRODUCER_ITEM_BY_OCCUPATION[occupation])),
			"a %s's take is village produce" % occupation
		)
	for occupation in VillageFarm.CROP_BY_OCCUPATION:
		assert_true(
			produce.has(String(VillageFarm.CROP_BY_OCCUPATION[occupation])),
			"a %s's crop is village produce" % occupation
		)
	for item_id in SettlementGathering.gathered_item_ids():
		assert_true(produce.has(String(item_id)), "gathered %s is village produce" % item_id)


## The five ids the drift actually cost that village, named so the
## regression has a shape a later reader can check against.
func test_the_goods_a_real_village_was_sitting_on_are_sellable():
	for item_id in ["herb", "wheat", "log", "stone", "plant_fibre"]:
		assert_gt(
			MerchantVisit.price_of(item_id), 0,
			"a real village held %s and could not turn it into a coin" % item_id
		)


## Raw produce is all worth the same base unit -- the rule already latent
## in the old table, where wood, fish, meat and fruit were every one of them
## LOG_PRICE. Stated once here so a new crop needs no new number.
func test_raw_produce_is_all_worth_the_base_unit():
	for item_id in MerchantVisit.village_produce():
		if MerchantVisit.KEEPING_GOOD_PRICES.has(item_id):
			continue
		assert_eq(
			MerchantVisit.price_of(item_id), MerchantVisit.LOG_PRICE,
			"%s is raw produce and prices at the base unit" % item_id
		)


## And the goods that KEEP are still dearer than the produce that spoils --
## the doc's own grounding ("He buys what travels") and the reason a
## merchant walks the circuit at all.
func test_goods_that_keep_are_worth_more_than_raw_produce():
	for item_id in MerchantVisit.KEEPING_GOOD_PRICES:
		assert_gt(
			MerchantVisit.price_of(String(item_id)), MerchantVisit.LOG_PRICE,
			"%s keeps and travels, so it beats the farm gate" % item_id
		)


# -- the cart runs on the day the village lives on ------------------------
#
# Identical to the fault test_village_immigration.gd already names in its
# own words: *"It used to be ConstructionCatchup.SECONDS_PER_DAY (3600),
# which is the offscreen catch-up's day and was never this module's to
# borrow."* MerchantVisit is the unfixed twin.
#
# construction_catchup.gd says plainly what that day is for -- "the
# offscreen catch-up integrates an absence at the ecology LOD rate (one
# in-game hour away is one day of progress, deliberately conservative),
# while a build the PLAYER raised and is standing at runs on the game's own
# day (EarthChunkManager.SECONDS_PER_SIMULATED_DAY, 60 seconds -- what the
# ecosystem step, THE SETTLEMENT STEP, the day/night cycle and every colony
# already run on)". _step_merchant_visits runs from the settlement step,
# for a village the player is standing in.
#
# Measured (tools/probe_village_purse.gd) with the buy list fixed, on a
# real village the player is at, after 1200 simulated seconds:
#
#     sellable after reserve    : 226
#     a visit right now would pay: 20 gold
#     visit accrued (0..1)      : 0.323
#     settlement purse 0.0 gold | 8 of 8 villagers broke
#
# One visit every ~3700 seconds is one visit every 62 player-felt days,
# against a starvation window (Starvation.seconds_to_die) of 200 seconds.
# The village is dead eighteen times over before the first coin arrives.

func test_the_cart_runs_on_the_games_own_day_not_the_catchup_day():
	assert_eq(
		MerchantVisit.SECONDS_PER_SIMULATED_DAY, 60.0,
		"the day the ecosystem step, the settlement step and every colony already run on"
	)
	assert_ne(
		MerchantVisit.SECONDS_PER_SIMULATED_DAY, ConstructionCatchup.SECONDS_PER_DAY,
		"the premise: the offscreen catch-up day really is a different, longer thing"
	)


## What that means where it is felt: a village sitting on a full surplus
## gets a visit within a day, not within an hour of real play.
func test_a_village_with_a_full_surplus_is_visited_within_its_own_day():
	var stock := {"fish": MerchantVisit.SURPLUS_FOR_FULL_DRAW * 2.0}
	var out: Dictionary = MerchantVisit.arrivals(
		MerchantVisit.SECONDS_PER_SIMULATED_DAY, stock, 0.0
	)
	assert_true(out["arrived"], "a full surplus draws him inside one day")


# -- a village does not sell the food its own people need -----------------
#
# The reserve only ever protected BUILDING materials (VillageGrowth's next
# building), and until the buy list was derived that was harmless, because
# the only food he bought was fish/meat/fruit a village rarely stockpiles.
# With `herb` and `wheat` sellable -- which they must be, or a herbalist
# earns the village nothing -- a cart on the village's own clock would hold
# its food at the level its own draw settles at, and that level is BELOW
# VillageImmigration.FED_THRESHOLD.
#
# The same rule the construction reserve already states, pointed at the
# other thing a village cannot do without: a peasant sells what is left
# once the household is fed until the next market day.

const SettlementState = preload("res://src/emergence/settlement_state.gd")
const VillageImmigration = preload("res://src/emergence/village_immigration.gd")


func test_a_village_keeps_back_what_its_own_households_eat():
	var reserve := MerchantVisit.food_reserve(10)
	assert_almost_eq(
		reserve, 10.0 * SettlementState.FOOD_PER_HOUSEHOLD / MerchantVisit.VISITS_PER_DAY, 0.0001,
		"what ten households eat between one cart and the next"
	)


## Derived from the cart's OWN cadence, so retuning how often he comes
## retunes how much a village has to keep -- never two numbers to keep in
## step by hand.
func test_the_reserve_is_the_gap_between_visits_not_a_number():
	assert_gt(
		MerchantVisit.food_reserve(1), SettlementState.FOOD_PER_HOUSEHOLD,
		"one household keeps more than one day's food, because he is not daily"
	)
	assert_gt(
		MerchantVisit.food_reserve(1), VillageImmigration.FED_THRESHOLD,
		"and what it keeps leaves it FED, not merely alive"
	)


func test_a_village_with_nobody_in_it_keeps_no_food_back():
	assert_eq(MerchantVisit.food_reserve(0), 0.0)


func test_the_food_a_village_needs_is_not_for_sale():
	var stock := {"herb": 40.0, "wood": 10.0}
	var reserved: Dictionary = MerchantVisit.with_food_reserve({}, stock, ["herb"], 5)
	assert_almost_eq(
		float(reserved.get("herb", 0.0)), MerchantVisit.food_reserve(5), 0.0001,
		"the village's own meals are held back"
	)
	assert_false(reserved.has("wood"), "timber is not food and this rule is not about timber")


## Held back ACROSS the food it really has, never more of an id than it
## holds -- a village with two crops keeps some of each rather than being
## told to keep grain it has none of.
func test_the_reserve_never_claims_food_a_village_does_not_have():
	var stock := {"herb": 2.0, "wheat": 100.0}
	var reserved: Dictionary = MerchantVisit.with_food_reserve({}, stock, ["herb", "wheat"], 10)
	assert_lte(float(reserved.get("herb", 0.0)), 2.0, "it cannot keep back herb it never grew")
	var total := float(reserved.get("herb", 0.0)) + float(reserved.get("wheat", 0.0))
	assert_almost_eq(total, MerchantVisit.food_reserve(10), 0.0001, "and the whole reserve is still kept")


## The building reserve is untouched: a village saves for its next house
## AND feeds itself, it does not choose.
func test_the_building_reserve_survives_beside_it():
	var stock := {"herb": 40.0, "wood": 20.0}
	var reserved: Dictionary = MerchantVisit.with_food_reserve({"wood": 12}, stock, ["herb"], 5)
	assert_eq(int(reserved["wood"]), 12, "the next house is still spoken for")
	assert_gt(float(reserved["herb"]), 0.0)


## And a village with a real glut still sells: this holds back what people
## eat, it does not close the market.
func test_a_village_with_a_real_glut_still_sells_it():
	var stock := {"herb": 500.0}
	var reserved: Dictionary = MerchantVisit.with_food_reserve({}, stock, ["herb"], 10)
	assert_gt(
		MerchantVisit.sellable_units(stock, reserved), MerchantVisit.CART_CAPACITY,
		"a glut is still a glut"
	)
