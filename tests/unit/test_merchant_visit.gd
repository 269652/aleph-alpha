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

const _DAY := MerchantVisit.SECONDS_PER_DAY


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


# -- which clock a visit is paced on --------------------------------------
#
# MEASURED (tools/probe_village_famine.gd, before and after): closing the
# conjured gold faucet so the merchant is a village's only income killed 7
# of 10 villagers inside 300 seconds, where the same village had survived
# and grown to 12. The merchant is not too stingy -- he is too SLOW. His
# day was ConstructionCatchup.SECONDS_PER_DAY (3600), the deliberately
# conservative rate for integrating an UNLOADED chunk, while hunger kills
# in Starvation.seconds_to_die (200) of the day the village actually lives
# on. The soonest he could possibly call was 18x the window in which
# everyone who could not feed themselves was already dead.
#
# The same defect, and the same fix, as the raised build that "ran on the
# game's own day" (docs/concept/planner_mode.md): a thing the player is
# WATCHING is paced by the day they live in; a background integration over
# absence keeps the catch-up rate.

const Starvation = preload("res://src/emergence/starvation.gd")


func test_a_visit_is_paced_on_whatever_day_the_caller_names():
	var stock := {"fish": 100.0}
	var slow: Dictionary = MerchantVisit.arrivals(60.0, stock, 0.0, {}, 3600.0)
	var lived: Dictionary = MerchantVisit.arrivals(60.0, stock, 0.0, {}, 60.0)
	assert_false(bool(slow["arrived"]), "a minute of a 3600-second day buys no visit")
	assert_true(bool(lived["arrived"]), "a minute of a 60-second day is a whole day's draw")


## The rule that matters, stated against the two real numbers: a village
## with goods to sell must be able to see a merchant INSIDE the window in
## which its people starve, or its only income arrives after the funeral.
func test_a_merchant_can_reach_a_village_before_its_people_starve():
	var stock := {"fish": 100.0}  # plenty to sell: the best draw there is
	var carry := 0.0
	var elapsed := 0.0
	var step := 5.0
	while elapsed < Starvation.seconds_to_die():
		var result: Dictionary = MerchantVisit.arrivals(
			step, stock, carry, {}, MerchantVisit.SECONDS_PER_DAY
		)
		carry = float(result["carry"])
		elapsed += step
		if bool(result["arrived"]):
			break
	assert_lt(
		elapsed, Starvation.seconds_to_die(),
		"the merchant arrives %.0fs into a %.0fs starvation window" % [
			elapsed, Starvation.seconds_to_die()
		]
	)


## And the day he is paced on is the one the village lives in, not the
## offscreen catch-up rate.
func test_the_merchants_day_is_the_day_the_village_lives_in():
	assert_eq(
		MerchantVisit.SECONDS_PER_DAY, 60.0,
		"the same day NpcMarker's schedule, the ecosystem step and the day/night cycle run on"
	)


# -- he must buy what a village actually makes ----------------------------
#
# MEASURED (tools/probe_village_famine.gd, with the purse and wallet
# columns): purse 0.0 and wallets 0 at EVERY sample, in a village holding
# 38 sellable food in its market and 187 across its shelves. The merchant
# was being offered the stock every settlement step and refusing all of it.
#
# BUY_LIST was beam/plank/hide/wood/fish/meat/fruit. A village's fields
# grow herb/carrot/potato/wheat (VillageCropChoice.SOWABLE). The two sets
# did not intersect AT ALL, so the only faucet for gold could never open,
# so nobody could buy a meal, so they starved standing on food.

const VillageCropChoice = preload("res://src/gameplay/village_crop_choice.gd")


## The rule, generalised so the next crop cannot reintroduce the famine: a
## village must be able to SELL what its own fields are told to grow.
func test_a_merchant_buys_every_crop_a_village_can_be_told_to_grow():
	var refused: Array = []
	for crop_id in VillageCropChoice.sowable_crops():
		if not MerchantVisit.buy_list().has(crop_id):
			refused.append(crop_id)
	assert_eq(refused, [], "the fields grow what he will not buy: %s" % str(refused))


## And every one of them has a real price, or he would take it for nothing.
func test_every_crop_he_buys_fetches_something():
	for crop_id in VillageCropChoice.sowable_crops():
		assert_gt(
			MerchantVisit.price_of(crop_id), 0,
			"%s sells for nothing" % crop_id
		)


## Raw produce is priced like the raw food already on the list -- not above
## it, since preparing food is what adds the value (see FARM_GATE_PRICES).
func test_raw_produce_is_priced_like_the_raw_food_already_on_the_list():
	for crop_id in VillageCropChoice.sowable_crops():
		assert_eq(
			MerchantVisit.price_of(crop_id), MerchantVisit.price_of("fruit"),
			"%s is raw produce and fetches what raw produce fetches" % crop_id
		)


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


# -- the merchant pays labour value -------------------------------------------
#
# docs/concept/village_economy_balance.md mechanism 2. Asked for in as many
# words: "the price for goods when selling to the travel merchant needs to
# be based on per capita work output... the city should generate double the
# income through export goods than it costs to pay all workers."
#
# MEASURED before this existed (tools/probe_village_economy.gd): a visit
# paid CART_CAPACITY units at LOG_PRICE -- 20 gold -- and ten hungry
# villagers drew it as subsistence wages the same tick; the purse read
# 0 -> 20 -> 1 -> 1 -> 19 -> 1, wallets 0 at every sample.

func test_the_labour_value_is_double_the_wage_bill():
	assert_almost_eq(MerchantVisit.labour_value_for(100.0), 200.0, 0.0001)
	assert_almost_eq(MerchantVisit.EXPORT_INCOME_TO_WAGE_BILL_RATIO, 2.0, 0.0001)
	assert_almost_eq(MerchantVisit.labour_value_for(-5.0), 0.0, 0.0001, "a negative bill is no bill")


## The index is the labour value over what the surplus is worth at the farm
## gate, floored at the farm gate: a village whose output is worth more
## than its bill is paid for its output, not for its bill.
func test_the_price_index_is_the_labour_value_over_the_surplus_floored_at_the_farm_gate():
	assert_almost_eq(MerchantVisit.price_index(200.0, 50.0), 4.0, 0.0001)
	assert_almost_eq(MerchantVisit.price_index(50.0, 200.0), 1.0, 0.0001)
	assert_almost_eq(MerchantVisit.price_index(0.0, 50.0), 1.0, 0.0001, "no labour to pay for: the farm gate")
	assert_almost_eq(MerchantVisit.price_index(50.0, 0.0), 1.0, 0.0001, "no surplus to price: the farm gate")


## The base prices keep every relativity: a beam is still six logs, at any
## index.
func test_the_unit_price_is_the_base_times_the_index_so_a_beam_is_still_six_logs():
	for index in [1.0, 2.5, 40.0]:
		assert_almost_eq(
			MerchantVisit.unit_price_of("beam", index) / MerchantVisit.unit_price_of("wood", index),
			float(MerchantVisit.price_of("beam")) / float(MerchantVisit.price_of("wood")), 0.0001
		)
		assert_almost_eq(MerchantVisit.unit_price_of("fish", index), float(MerchantVisit.price_of("fish")) * index, 0.0001)
	assert_almost_eq(MerchantVisit.unit_price_of("iron_sword", 40.0), 0.0, 0.0001, "he still does not deal in it")


## What the surplus is worth at the farm gate: every sellable unit above the
## reserve, at its base price.
func test_the_surplus_value_is_the_sellable_units_at_base_prices():
	assert_almost_eq(MerchantVisit.surplus_value({"fish": 10.0, "beam": 2.0}), 10.0 + 2.0 * MerchantVisit.price_of("beam"), 0.0001)
	assert_almost_eq(MerchantVisit.surplus_value({"fish": 30.0}, {"fish": 25}), 5.0, 0.0001)
	assert_almost_eq(MerchantVisit.surplus_value({"iron_sword": 9.0}), 0.0, 0.0001)


## A sale with no labour to pay for is the farm-gate sale it always was.
func test_a_sale_with_no_labour_value_is_the_farm_gate_sale_it_always_was():
	for stock in [{"fish": 5.0}, {"fish": 50.0, "beam": 30.0}, {}]:
		var before: Dictionary = MerchantVisit.purchase(stock)
		var after: Dictionary = MerchantVisit.purchase(stock, {}, 0.0)
		assert_eq(after["bought"], before["bought"])
		assert_almost_eq(float(after["paid"]), float(before["paid"]), 0.0001)
		assert_almost_eq(float(after["index"]), 1.0, 0.0001)


## When the surplus is worth less than the labour, the cart takes all of it
## and pays the labour value: the village earns its wage bill twice over
## from what it made, however little that was.
func test_a_surplus_worth_less_than_the_labour_is_taken_whole_and_paid_the_labour_value():
	var sale: Dictionary = MerchantVisit.purchase({"fish": 10.0}, {}, 50.0)
	assert_eq(int(sale["bought"].get("fish", 0)), 10, "every unit goes")
	assert_almost_eq(float(sale["paid"]), 50.0, 0.0001)
	assert_almost_eq(float(sale["index"]), 5.0, 0.0001)


## When the surplus is worth more, he pays the farm gate and takes what
## covers the labour value.
func test_a_surplus_worth_more_than_the_labour_is_paid_base_and_taken_to_cover_it():
	var sale: Dictionary = MerchantVisit.purchase({"fish": 100.0}, {}, 50.0)
	assert_eq(int(sale["bought"].get("fish", 0)), 50)
	assert_almost_eq(float(sale["paid"]), 50.0, 0.0001)
	assert_almost_eq(float(sale["index"]), 1.0, 0.0001)


## The fixed cart is a FLOOR on a visit, not a ceiling on a village's income.
func test_the_cart_is_a_floor_on_a_visit_not_a_ceiling_on_income():
	var small: Dictionary = MerchantVisit.purchase({"fish": 100.0}, {}, 5.0)
	assert_eq(int(small["bought"].get("fish", 0)), MerchantVisit.CART_CAPACITY, "never fewer than a cart-load")
	assert_almost_eq(float(small["paid"]), float(MerchantVisit.CART_CAPACITY), 0.0001)
	var large: Dictionary = MerchantVisit.purchase({"fish": 100.0}, {}, 300.0)
	assert_eq(int(large["bought"].get("fish", 0)), 100, "a village's whole output rides when the labour asks for it")
	assert_almost_eq(float(large["paid"]), 300.0, 0.0001)


## And a hoard still cannot become a windfall: what a hoard earns above the
## labour value is its base value, exactly as before.
func test_a_hoard_still_cannot_become_a_windfall():
	var sale: Dictionary = MerchantVisit.purchase({"fish": 1000.0}, {}, 100.0)
	assert_eq(int(sale["bought"].get("fish", 0)), 100)
	assert_almost_eq(float(sale["paid"]), 100.0, 0.0001)


func test_dearest_goods_still_ride_first_under_a_labour_value():
	var sale: Dictionary = MerchantVisit.purchase({"beam": 20.0, "fish": 100.0}, {}, 30.0)
	assert_eq(int(sale["bought"].get("beam", 0)), MerchantVisit.CART_CAPACITY, "the cart-load is beams")
	assert_eq(int(sale["bought"].get("fish", 0)), 0)


## The reserve is the reserve, whatever the price: the larder and the next
## house are not for sale at any index.
func test_the_reserve_still_holds_under_a_labour_value():
	var sale: Dictionary = MerchantVisit.purchase({"fish": 30.0}, {"fish": 25}, 100.0)
	assert_eq(int(sale["bought"].get("fish", 0)), 5)
	assert_almost_eq(float(sale["paid"]), 100.0, 0.0001)
	assert_almost_eq(float(sale["index"]), 20.0, 0.0001)


func test_nothing_is_created_or_destroyed_by_an_indexed_sale():
	var sale: Dictionary = MerchantVisit.purchase({"fish": 3.0, "beam": 2.0, "hide": 1.0}, {}, 70.0)
	var owed := 0.0
	for item_id in sale["bought"]:
		owed += float(sale["bought"][item_id]) * MerchantVisit.unit_price_of(item_id, float(sale["index"]))
	assert_almost_eq(float(sale["paid"]), owed, 0.0001, "the gold paid is exactly the goods taken at the indexed price")
