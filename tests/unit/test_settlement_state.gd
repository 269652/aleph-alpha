extends GutTest

## SettlementState: carrying capacity and growth/decline status (see
## docs/emergence/04-settlements-cities-infrastructure.md "Carrying
## capacity": "Population capacity depends on food, water, housing, jobs,
## sanitation, security, transport, trade, climate, and disease. Population
## should move toward capacity rather than use arbitrary growth").
##
## Deliberately FOOD-only for this first slice (avoid premature complexity):
## food is the one input this project already has live, real data for (via
## Market, Phase 5) -- water/housing/job/sanitation simulation do not exist
## yet either, so deriving capacity from them would mean inventing the very
## systems this slice is trying to avoid inventing.

const Market = preload("res://src/emergence/market.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")


# -- food_stock reads real market stock, not a synthetic total --------------

func test_food_stock_sums_only_food_typed_items():
	var market := Market.new()
	market.add_stock("meat", 5)
	market.add_stock("apple", 3)
	market.add_stock("wood", 100)  # a material, not food -- must not count
	assert_eq(SettlementState.food_stock(market), 8)


func test_food_stock_of_an_empty_market_is_zero():
	assert_eq(SettlementState.food_stock(Market.new()), 0)


func test_food_stock_ignores_an_unknown_item_id():
	var market := Market.new()
	market.add_stock("not_a_real_item", 5)
	assert_eq(SettlementState.food_stock(market), 0)


# -- carrying_capacity is derived from food, not a flat constant -------------

func test_carrying_capacity_of_an_empty_market_is_zero():
	assert_eq(SettlementState.carrying_capacity(Market.new()), 0)


func test_carrying_capacity_rises_with_more_food():
	var market := Market.new()
	# Whole units, because a Market's stock is whole units -- the per-house-
	# hold draw is a measured 1.2 now, not a whole number (see "what a
	# household really eats" below), so three households' worth has to be
	# rounded to something a market can actually hold.
	market.add_stock("meat", int(round(SettlementState.FOOD_PER_HOUSEHOLD * 3.0)))
	assert_eq(SettlementState.carrying_capacity(market), 3)


# -- status_for classifies growth/decline, with a dead band to avoid flicker -

func test_status_is_growing_well_below_capacity():
	assert_eq(SettlementState.status_for(1, 10), SettlementState.GROWING)


func test_status_is_declining_well_above_capacity():
	assert_eq(SettlementState.status_for(10, 1), SettlementState.DECLINING)


func test_status_is_stable_right_at_capacity():
	assert_eq(SettlementState.status_for(5, 5), SettlementState.STABLE)


## An empty settlement with no food and no households is not "declining" --
## there is nothing there yet to be under pressure.
func test_status_with_no_food_and_no_households_is_stable_not_declining():
	assert_eq(SettlementState.status_for(0, 0), SettlementState.STABLE)


## Households with genuinely zero food IS real pressure -- a village that
## exists but has nothing to eat is declining, not merely "at capacity."
func test_status_with_households_but_zero_food_is_declining():
	assert_eq(SettlementState.status_for(3, 0), SettlementState.DECLINING)


func test_every_documented_status_exists():
	var expected := ["growing", "stable", "declining"]
	for status in expected:
		assert_true(SettlementState.STATUSES.has(status), "missing status: %s" % status)


# -- what a household really eats -----------------------------------------
#
# FOOD_PER_HOUSEHOLD used to be 4, with its own comment admitting "there is
# no real economy data yet to derive one from" -- and by the time there was,
# nobody went back. It is MEASURED now, off the villagers' own hunger clock,
# and these are the tests that hold it there.

const NpcNeeds = preload("res://src/world/npc_needs.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")

## Fine enough that a meal is never missed by a coarse step, coarse enough
## that 200 assessments run in a test.
const _SLICE := 0.05
## Long enough that discrete meals average out: a villager eats once per 25
## world-seconds and an assessment is 30, so any single assessment sees one
## meal or two and only a long run sees 1.2.
const _ASSESSMENTS := 200


## The derivation, run rather than asserted: a villager fed the moment they
## read as hungry, for 200 real assessments of the real clock.
func test_a_households_draw_is_what_its_own_hunger_clock_really_eats():
	var needs := NpcNeeds.new()
	var meals := 0
	var elapsed := 0.0
	var total := SettlementState.ASSESSMENT_SECONDS * float(_ASSESSMENTS)
	while elapsed < total:
		needs.advance(_SLICE)
		elapsed += _SLICE
		if needs.is_hungry():
			needs.feed()
			meals += 1
	var measured := float(meals) * VillageMarket.FOOD_UNITS_PER_MEAL / float(_ASSESSMENTS)
	assert_almost_eq(
		SettlementState.FOOD_PER_HOUSEHOLD, measured, 0.02,
		"the per-household draw must be what a villager's own hunger really takes"
	)


## ...and the clock it is derived from is the one the ethogram really gives a
## villager, so retuning hunger fails here rather than quietly leaving the
## whole settlement economy priced against the old pace.
func test_the_draw_follows_the_villagers_own_hunger_profile():
	var hunger: Dictionary = Ethogram.drive_profile("", "villager")[Ethogram.DRIVE_HUNGER]
	var seconds_between_meals: float = float(hunger["rise_seconds"]) * float(hunger["threshold"])
	assert_almost_eq(
		SettlementState.FOOD_PER_HOUSEHOLD,
		SettlementState.ASSESSMENT_SECONDS / seconds_between_meals * VillageMarket.FOOD_UNITS_PER_MEAL,
		0.02,
		"an assessment's worth of meals, at the pace the ethogram sets"
	)


## The old number was not a little out: a village of five was charged 20
## units an assessment for food its villagers could only eat 6 of.
func test_the_old_draw_overstated_what_a_village_eats():
	assert_lt(
		SettlementState.FOOD_PER_HOUSEHOLD, 4.0,
		"4 was the unmeasured number this replaced -- if it comes back, so does a 3.3x error"
	)
