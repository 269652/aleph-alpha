extends GutTest

const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const Market = preload("res://src/emergence/market.gd")


func _region(vegetation: float, herbivores: float, fish: float):
	var region = SettlementGranary.SeededRegion.new()
	region.vegetation_density = vegetation
	region.herbivore_population = herbivores
	region.fish_population = fish
	return region


# -- what a settlement eats --


## The consumption side is not a new number: SettlementState.FOOD_PER_
## HOUSEHOLD already calls itself "how much food one household draws down
## per assessment", and a settlement step IS one assessment. Until now
## nothing ever drew it -- it was only ever a divisor for capacity.
func test_subsistence_is_settlement_states_own_per_household_draw():
	assert_eq(SettlementGranary.subsistence_draw(1), SettlementState.FOOD_PER_HOUSEHOLD)
	assert_eq(SettlementGranary.subsistence_draw(8), 8 * SettlementState.FOOD_PER_HOUSEHOLD)


func test_a_settlement_with_no_households_eats_nothing():
	assert_eq(SettlementGranary.subsistence_draw(0), 0)
	assert_eq(SettlementGranary.subsistence_draw(-3), 0, "and a nonsense census is empty, not negative")


# -- what a settlement gathers --


## The production side is not a new rate either: gathered_over is
## NpcProduction.yield_per_second, integrated over the elapsed interval, so
## an offscreen villager gathers at exactly the rate an onscreen one does.
func test_gathering_is_npc_productions_own_rate_over_the_elapsed_time():
	var gathered: Dictionary = SettlementGranary.gathered_over(["hunter"], _region(0.0, 10.0, 0.0), 30.0)
	assert_almost_eq(
		float(gathered["meat"]), NpcProduction.PRODUCTION_RATE_PER_SECOND * 10.0 * 30.0, 0.0001
	)


## Each producer occupation gathers its OWN real item off its OWN real
## regional number -- the three separate resource pools NpcProduction
## already keys them to, not one pooled "food".
func test_each_producer_gathers_its_own_item_from_its_own_resource():
	var gathered: Dictionary = SettlementGranary.gathered_over(
		["farmer", "hunter", "fisher"], _region(1.0, 10.0, 4.0), 30.0
	)
	assert_eq(gathered.keys().size(), 3)
	assert_gt(float(gathered["meat"]), float(gathered["fish"]), "more game than fish in this region")
	assert_gt(float(gathered["fish"]), float(gathered["fruit"]), "and more fish than a 0-1 density")


func test_a_settlement_of_non_producers_gathers_nothing():
	var gathered: Dictionary = SettlementGranary.gathered_over(
		["blacksmith", "merchant", "guard", "nurse", ""], _region(1.0, 50.0, 50.0), 30.0
	)
	assert_eq(gathered, {})


func test_two_households_of_the_same_occupation_gather_twice_as_much():
	var one: Dictionary = SettlementGranary.gathered_over(["hunter"], _region(0.0, 10.0, 0.0), 30.0)
	var two: Dictionary = SettlementGranary.gathered_over(["hunter", "hunter"], _region(0.0, 10.0, 0.0), 30.0)
	assert_almost_eq(float(two["meat"]), 2.0 * float(one["meat"]), 0.0001)


func test_a_dead_region_yields_nothing_to_gather():
	assert_eq(SettlementGranary.gathered_over(["farmer", "hunter", "fisher"], _region(0.0, 0.0, 0.0), 30.0), {})


# -- the split: what is eaten now vs. what is stored --


## The keystone. A settlement that gathers more than it eats banks the
## difference, in whole units, and that stored difference IS what
## SettlementState.carrying_capacity has always been dividing.
func test_the_surplus_over_subsistence_is_what_gets_banked():
	var result: Dictionary = SettlementGranary.catchup({"meat": 10.0}, {}, {}, 1)
	assert_eq(result["stock_delta"], {"meat": 10 - SettlementState.FOOD_PER_HOUSEHOLD})


func test_a_village_that_eats_everything_it_gathers_banks_nothing():
	var gathered := {"meat": float(SettlementState.FOOD_PER_HOUSEHOLD)}
	var result: Dictionary = SettlementGranary.catchup(gathered, {}, {}, 1)
	assert_eq(result["stock_delta"], {})


## The same rule run backwards, which is the whole reason a settlement can
## DECLINE offscreen rather than merely fail to grow: a shortfall is eaten
## out of what was stored earlier.
func test_a_shortfall_is_eaten_out_of_the_granary():
	var result: Dictionary = SettlementGranary.catchup({}, {}, {"meat": 20}, 2)
	assert_eq(result["stock_delta"], {"meat": -2 * SettlementState.FOOD_PER_HOUSEHOLD})


func test_a_granary_can_be_eaten_empty_but_never_past_empty():
	var result: Dictionary = SettlementGranary.catchup({}, {}, {"meat": 3}, 8)
	assert_eq(result["stock_delta"], {"meat": -3}, "the village eats what there is, and no more")


## A settlement short of food eats every food it has, not just the first
## one -- the shortfall is a shortfall of FOOD, not of one item id.
func test_a_shortfall_draws_across_every_food_in_the_granary():
	var result: Dictionary = SettlementGranary.catchup({}, {}, {"fish": 2, "meat": 2}, 1)
	var delta: Dictionary = result["stock_delta"]
	assert_eq(int(delta.get("fish", 0)) + int(delta.get("meat", 0)), -SettlementState.FOOD_PER_HOUSEHOLD)


## A granary also holds what a settlement PRODUCED (Market.produce crafts
## into its own stock), and a village cannot eat a stone pickaxe.
func test_a_village_cannot_eat_what_is_not_food():
	var result: Dictionary = SettlementGranary.catchup({}, {}, {"stone_pickaxe": 40}, 4)
	assert_eq(result["stock_delta"], {})


## Whole units only: an emergence Market's stock is integer, and
## NpcProduction.FOOD_UNIT is one whole gathered unit. A sub-unit trickle is
## carried rather than truncated away, the same carry-until-it-crosses-a-
## whole-unit idiom NpcEconomy._accumulated_yield already runs on.
func test_a_sub_unit_trickle_is_carried_rather_than_lost():
	var carry := {}
	var banked := 0
	for step in 10:
		var result: Dictionary = SettlementGranary.catchup({"meat": 0.5}, carry, {}, 0)
		carry = result["carry"]
		banked += int(result["stock_delta"].get("meat", 0))
	assert_eq(banked, 5, "ten half-units really is five whole ones")


func test_the_carry_never_holds_a_whole_unit_back():
	var result: Dictionary = SettlementGranary.catchup({"meat": 2.75}, {}, {}, 0)
	assert_eq(result["stock_delta"], {"meat": 2})
	assert_almost_eq(float(result["carry"]["meat"]), 0.75, 0.0001)


## Gathering and eating resolve against ONE pool: food gathered this
## assessment is available to eat this assessment, so a settlement that
## gathers exactly what it needs does not have to have banked it first.
func test_this_assessments_catch_feeds_this_assessment():
	var result: Dictionary = SettlementGranary.catchup(
		{"meat": float(SettlementState.FOOD_PER_HOUSEHOLD) + 1.0}, {}, {}, 1
	)
	assert_eq(result["stock_delta"], {"meat": 1})


## Determinism, because this drives a persisted ledger: the same state must
## always produce the same delta, whatever order the Dictionaries iterate in.
func test_the_drawdown_is_deterministic_across_iteration_order():
	var a: Dictionary = SettlementGranary.catchup({}, {}, {"meat": 2, "fish": 2, "fruit": 2}, 1)
	var b: Dictionary = SettlementGranary.catchup({}, {}, {"fruit": 2, "fish": 2, "meat": 2}, 1)
	assert_eq(a["stock_delta"], b["stock_delta"])


# -- the whole loop, against the real constants --


## The break-even census, stated as a number rather than a feeling: how many
## households one producer's real catch can carry before the settlement
## starts eating its granary instead of filling it. Nothing is tuned here --
## it falls straight out of NpcProduction's rate and SettlementState's draw,
## which is the whole point of anchoring both sides to constants that
## already existed.
func test_break_even_is_the_catch_divided_by_the_subsistence_draw():
	var region = _region(0.0, 10.0, 0.0)
	var per_hunter: float = float(
		SettlementGranary.gathered_over(["hunter"], region, 30.0)["meat"]
	)
	var break_even := int(per_hunter / float(SettlementState.FOOD_PER_HOUSEHOLD))
	assert_gt(break_even, 1, "precondition: this region really can feed more than the hunter")

	var occupations: Array = ["hunter"]
	for i in break_even - 1:
		occupations.append("guard")
	var fed: Dictionary = SettlementGranary.catchup(
		SettlementGranary.gathered_over(occupations, region, 30.0), {}, {}, occupations.size()
	)
	assert_gt(
		int(fed["stock_delta"].get("meat", 0)), 0,
		"at break-even the whole census eats and there is still something to store"
	)

	occupations.append("guard")
	var over: Dictionary = SettlementGranary.catchup(
		SettlementGranary.gathered_over(occupations, region, 30.0), {}, {}, occupations.size()
	)
	assert_eq(
		over["stock_delta"], {},
		"one mouth past break-even banks nothing at all -- and with an empty granary, goes short"
	)


## One gathered food unit is one emergence-Market unit is one meal: the
## three constants that make this model's arithmetic legal in the first
## place, pinned so a change to any of them breaks here rather than silently
## rescaling every settlement in the world.
func test_the_gathered_unit_the_market_unit_and_the_meal_are_the_same_unit():
	assert_eq(NpcProduction.FOOD_UNIT, VillageMarket.FOOD_UNITS_PER_MEAL)
	var market := Market.new()
	market.add_stock("meat", int(NpcProduction.FOOD_UNIT))
	assert_eq(market.stock_of("meat"), 1)


func test_has_producer_answers_without_needing_a_region():
	assert_true(SettlementGranary.has_producer(["guard", "fisher", "nurse"]))
	assert_false(SettlementGranary.has_producer(["guard", "nurse", "merchant", ""]))
	assert_false(SettlementGranary.has_producer([]))
