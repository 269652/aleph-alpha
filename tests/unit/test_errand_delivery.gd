extends GutTest

## docs/concept/errands.md: the give verb's whole rule, decided before
## anything mutates. Pure -- no world, no market object, no player -- in the
## spirit of test_village_living_wage.gd and test_spell_cost.gd.
##
## The shape under test is the projection's own: `missing` is exactly what
## Quest.production_shortfall_quests_for puts in a quest's "missing" field,
## [{"item_id": String, "need": int}, ...].

const ErrandDelivery = preload("res://src/gameplay/errand_delivery.gd")

## A flat price of 3 coins for everything, so a test about coins is never
## also a test about scarcity pricing.
func _flat_price(_item_id: String) -> float:
	return 3.0


func _price_of(prices: Dictionary) -> Callable:
	return func(item_id: String) -> float:
		return float(prices.get(item_id, 0.0))


# -- what can be handed over at all -------------------------------------

func test_nothing_carried_is_nothing_to_give():
	assert_eq(ErrandDelivery.deliverable_for([{"item_id": "rock", "need": 3}], {}), [])


func test_the_wrong_goods_are_nothing_to_give():
	var deliverable := ErrandDelivery.deliverable_for(
		[{"item_id": "rock", "need": 3}], {"wood": 10, "fish": 2}
	)
	assert_eq(deliverable, [], "carrying ten wood does not help a household short of rock")


func test_carrying_exactly_what_is_missing_gives_all_of_it():
	assert_eq(
		ErrandDelivery.deliverable_for([{"item_id": "rock", "need": 3}], {"rock": 3}),
		[{"item_id": "rock", "count": 3}]
	)


## Partial help is help (pillar 4).
func test_carrying_less_than_the_need_gives_what_there_is():
	assert_eq(
		ErrandDelivery.deliverable_for([{"item_id": "rock", "need": 3}], {"rock": 2}),
		[{"item_id": "rock", "count": 2}]
	)


## A household never takes more than it is short of.
func test_carrying_more_than_the_need_gives_only_the_need():
	assert_eq(
		ErrandDelivery.deliverable_for([{"item_id": "rock", "need": 3}], {"rock": 99}),
		[{"item_id": "rock", "count": 3}]
	)


func test_several_missing_inputs_are_each_covered_as_far_as_they_can_be():
	var deliverable := ErrandDelivery.deliverable_for(
		[{"item_id": "rock", "need": 3}, {"item_id": "wood", "need": 2}, {"item_id": "clay", "need": 1}],
		{"rock": 1, "clay": 5}
	)
	assert_eq(
		deliverable,
		[{"item_id": "rock", "count": 1}, {"item_id": "clay", "count": 1}],
		"an input the player carries none of is dropped, not carried as a zero"
	)


## The verb's own availability test (pillar: refusals are sentences -- an
## empty deliverable is what makes the button say why).
func test_an_empty_deliverable_is_how_the_verb_knows_it_has_nothing_to_offer():
	assert_true(ErrandDelivery.deliverable_for([{"item_id": "rock", "need": 3}], {"rock": 0}).is_empty())
	assert_false(ErrandDelivery.deliverable_for([{"item_id": "rock", "need": 3}], {"rock": 1}).is_empty())


# -- the whole transaction ----------------------------------------------

func test_settling_a_full_cover_moves_the_goods_and_clears_the_shortage():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 3}], {"rock": 3}, 100, _flat_price
	)
	assert_eq(deal["given"], [{"item_id": "rock", "count": 3}])
	assert_eq(deal["units"], 3)
	assert_true(deal["clears"], "every missing input was covered, so the shortage ends")


func test_a_partial_delivery_does_not_clear_the_shortage():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 3}], {"rock": 2}, 100, _flat_price
	)
	assert_eq(deal["units"], 2)
	assert_false(deal["clears"], "one rock short is still short")


func test_covering_one_of_two_missing_inputs_does_not_clear():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 1}, {"item_id": "wood", "need": 1}], {"rock": 1}, 100, _flat_price
	)
	assert_eq(deal["units"], 1)
	assert_false(deal["clears"])


func test_nothing_to_give_settles_to_nothing_rather_than_failing():
	var deal := ErrandDelivery.settle([{"item_id": "rock", "need": 3}], {}, 100, _flat_price)
	assert_eq(deal["given"], [])
	assert_eq(deal["units"], 0)
	assert_eq(deal["value"], 0)
	assert_eq(deal["paid"], 0)
	assert_eq(deal["debt"], 0)
	assert_false(deal["clears"])


# -- what it is worth, and what the village can actually pay -------------

func test_value_is_the_villages_own_price_per_unit():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 3}], {"rock": 3}, 100, _flat_price
	)
	assert_eq(deal["value"], 9, "three rock at the market's own 3 coins each")


func test_each_item_is_valued_at_its_own_price():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 2}, {"item_id": "iron", "need": 1}],
		{"rock": 2, "iron": 1},
		100,
		_price_of({"rock": 3.0, "iron": 11.0})
	)
	assert_eq(deal["value"], 17, "2 x 3 + 1 x 11")


## Scarcity pricing is the only price model (pillar 5): what a village is
## desperate for pays better, with no second model for the player.
func test_a_scarcer_good_pays_better_for_the_same_count():
	var cheap := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 2}], {"rock": 2}, 100, _price_of({"rock": 2.0})
	)
	var dear := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 2}], {"rock": 2}, 100, _price_of({"rock": 9.0})
	)
	assert_gt(int(dear["value"]), int(cheap["value"]))


func test_a_nearly_worthless_good_still_pays_the_pinned_floor():
	var deal := ErrandDelivery.settle(
		[{"item_id": "straw", "need": 4}], {"straw": 4}, 100, _price_of({"straw": 0.01})
	)
	assert_eq(
		deal["value"], 4 * ErrandDelivery.MIN_COIN_PER_UNIT,
		"a unit of help is never worth nothing"
	)


func test_a_purse_that_can_pay_pays_it_all_and_owes_nothing():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 3}], {"rock": 3}, 100, _flat_price
	)
	assert_eq(deal["paid"], 9)
	assert_eq(deal["debt"], 0)


## Pillar 3: a poor village takes the goods, pays what it holds, and
## carries the rest as a debt -- it never refuses and never conjures coins.
func test_a_poor_village_pays_what_it_has_and_owes_the_rest():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 3}], {"rock": 3}, 4, _flat_price
	)
	assert_eq(deal["given"], [{"item_id": "rock", "count": 3}], "the goods still move")
	assert_eq(deal["value"], 9)
	assert_eq(deal["paid"], 4, "it pays every coin it has")
	assert_eq(deal["debt"], 5, "and owes the rest")
	assert_true(deal["clears"], "the shortage ends whether or not it could pay")


func test_an_empty_purse_owes_the_whole_value():
	var deal := ErrandDelivery.settle(
		[{"item_id": "rock", "need": 2}], {"rock": 2}, 0, _flat_price
	)
	assert_eq(deal["paid"], 0)
	assert_eq(deal["debt"], 6)


func test_the_purse_is_never_overdrawn_and_payment_is_never_negative():
	for balance in [0, 1, 5, 9, 50]:
		var deal := ErrandDelivery.settle(
			[{"item_id": "rock", "need": 3}], {"rock": 3}, balance, _flat_price
		)
		assert_true(int(deal["paid"]) >= 0, "payment is never negative")
		assert_true(int(deal["paid"]) <= balance, "a purse is never overdrawn")
		assert_eq(int(deal["paid"]) + int(deal["debt"]), int(deal["value"]), "value is conserved")


# -- conservation, over the whole surface --------------------------------

## Whatever the inputs, the deal never invents goods or coins.
func test_the_deal_never_gives_more_than_is_carried_or_needed():
	var missing := [{"item_id": "rock", "need": 3}, {"item_id": "wood", "need": 5}]
	for rock in [0, 1, 3, 7]:
		for wood in [0, 2, 5, 9]:
			var carried := {"rock": rock, "wood": wood}
			var deal := ErrandDelivery.settle(missing, carried, 1000, _flat_price)
			for entry in deal["given"]:
				var item_id: String = entry["item_id"]
				assert_true(
					int(entry["count"]) <= int(carried[item_id]),
					"never gives more %s than carried" % item_id
				)
				assert_true(int(entry["count"]) > 0, "a zero entry is dropped, not listed")
			var expected_clear: bool = rock >= 3 and wood >= 5
			assert_eq(bool(deal["clears"]), expected_clear, "clears iff every input is covered")


## The availability test and the transaction agree with each other.
func test_settle_gives_exactly_what_deliverable_for_offered():
	var missing := [{"item_id": "rock", "need": 4}, {"item_id": "clay", "need": 2}]
	var carried := {"rock": 2, "clay": 9}
	assert_eq(
		ErrandDelivery.settle(missing, carried, 100, _flat_price)["given"],
		ErrandDelivery.deliverable_for(missing, carried)
	)


# -- the offer the give button shows -------------------------------------
#
# docs/concept/errands.md, "The verb, at the villager's door" and
# "Refusals are sentences": the button is built from the dialogue frame
# DialogueContext already produces (shortfall_missing, household_id,
# settlement_id, and the carrying facts), so the villager who says "I could
# use three more rock" and the button that hands them over read the same
# state. A refusal names its reason instead of standing dead.

func _frame(missing: Array, carried: Dictionary) -> Dictionary:
	return {
		"npc_name": "Mira",
		"household_id": "household:7",
		"settlement_id": "settlement:676_120",
		"shortfall_missing": missing,
		"player_carrying": carried,
	}


func test_a_villager_with_no_shortfall_is_offered_no_give_at_all():
	var offer := ErrandDelivery.offer_from_frame(_frame([], {"rock": 9}))
	assert_false(offer["available"], "nobody here needs anything")


func test_a_shortfall_the_player_cannot_help_with_says_why():
	var offer := ErrandDelivery.offer_from_frame(
		_frame([{"item_id": "rock", "need": 3}], {"wood": 10})
	)
	assert_false(offer["available"])
	assert_true(offer["reason"].contains("rock"), "the reason names what is needed: %s" % offer["reason"])
	assert_true(offer["reason"].contains("Mira"), "and who needs it: %s" % offer["reason"])


func test_carrying_the_goods_offers_the_give_and_names_the_count():
	var offer := ErrandDelivery.offer_from_frame(
		_frame([{"item_id": "rock", "need": 3}], {"rock": 5})
	)
	assert_true(offer["available"])
	assert_eq(offer["given"], [{"item_id": "rock", "count": 3}])
	assert_true(offer["label"].contains("3"), "the label names the count: %s" % offer["label"])
	assert_true(offer["label"].contains("Rock") or offer["label"].contains("rock"), offer["label"])


func test_carrying_part_of_it_is_still_offered():
	var offer := ErrandDelivery.offer_from_frame(
		_frame([{"item_id": "rock", "need": 3}], {"rock": 1})
	)
	assert_true(offer["available"], "partial help is help")
	assert_eq(offer["given"], [{"item_id": "rock", "count": 1}])


func test_the_offer_carries_the_household_and_settlement_the_transfer_needs():
	var offer := ErrandDelivery.offer_from_frame(
		_frame([{"item_id": "rock", "need": 3}], {"rock": 3})
	)
	assert_eq(offer["household_id"], "household:7")
	assert_eq(offer["settlement_id"], "settlement:676_120")


func test_an_offer_without_a_settlement_is_refused_rather_than_half_performed():
	var frame := _frame([{"item_id": "rock", "need": 3}], {"rock": 3})
	frame["settlement_id"] = ""
	var offer := ErrandDelivery.offer_from_frame(frame)
	assert_false(offer["available"], "there is no market to add the stock to")


func test_several_missing_inputs_read_as_one_labelled_offer():
	var offer := ErrandDelivery.offer_from_frame(
		_frame([{"item_id": "rock", "need": 2}, {"item_id": "wood", "need": 1}], {"rock": 2, "wood": 1})
	)
	assert_true(offer["available"])
	assert_eq(offer["given"].size(), 2)
	assert_true(offer["label"].contains("2"), offer["label"])
