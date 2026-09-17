extends GutTest

## VillagerBehavior: what a villager does next, decided from what they NEED
## and what is around them rather than from a fixed schedule (see
## docs/concept/npc_social_life.md).
##
## The sibling of CreatureBehavior, over the same BehaviorKernel and the same
## Ethogram wiring table -- so a villager's inner life runs on the same code
## every other creature's does. These tests pin the villager-side contract:
## which intent comes out for which drives and which surroundings.

const VillagerBehavior = preload("res://src/gameplay/villager_behavior.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")
const BehaviorKernel = preload("res://src/gameplay/behavior_kernel.gd")

var behavior: VillagerBehavior


func before_each():
	behavior = VillagerBehavior.new()


## Everything a villager can sense, all at once, with no drive pressing.
func _context(drives: Dictionary, extras: Dictionary = {}) -> Dictionary:
	var context := {
		"position": Vector2.ZERO,
		"drives": drives,
		"company": [Vector2(40, 0)],
		"market": Vector2(0, 40),
		"home": Vector2(-40, 0),
		"water": Vector2(0, -40),
	}
	for key in extras:
		context[key] = extras[key]
	return context


func _quiet_drives() -> Dictionary:
	return {"hunger": 0.0, "thirst": 0.0, "rest": 0.0, "company": 0.0}


func _only(drive: String, level: float = 1.0) -> Dictionary:
	var drives := _quiet_drives()
	drives[drive] = level
	return drives


# -- one need at a time ----------------------------------------------------


func test_a_hungry_villager_goes_to_market():
	var decision := behavior.decide(_context(_only("hunger")))
	assert_eq(decision["intent"], VillagerBehavior.EAT)
	assert_eq(decision["target"], Vector2(0, 40))


func test_a_thirsty_villager_goes_to_the_water():
	var decision := behavior.decide(_context(_only("thirst")))
	assert_eq(decision["intent"], VillagerBehavior.DRINK)
	assert_eq(decision["target"], Vector2(0, -40))


func test_a_tired_villager_goes_home():
	var decision := behavior.decide(_context(_only("rest")))
	assert_eq(decision["intent"], VillagerBehavior.REST)
	assert_eq(decision["target"], Vector2(-40, 0))


func test_a_lonely_villager_goes_to_somebody():
	var decision := behavior.decide(_context(_only("company")))
	assert_eq(decision["intent"], VillagerBehavior.SOCIALIZE)
	assert_eq(decision["target"], Vector2(40, 0))


# -- nothing pressing ------------------------------------------------------


## The whole point of pillar 2: with no need pressing, the villager is NOT
## steered at all, and the caller's own schedule stands. A behaviour layer
## that always had an opinion would have replaced the schedule rather than
## interrupting it.
func test_a_contented_villager_is_left_to_their_own_schedule():
	var decision := behavior.decide(_context(_quiet_drives()))
	assert_eq(decision["intent"], VillagerBehavior.NOTHING)
	assert_null(decision["target"])


func test_a_villager_with_nothing_around_them_is_left_alone_too():
	var decision := behavior.decide({
		"position": Vector2.ZERO, "drives": _only("company"),
	})
	assert_eq(decision["intent"], VillagerBehavior.NOTHING, "nobody to talk to is not an intent")
	assert_null(decision["target"])


# -- priority --------------------------------------------------------------


## Hunger outranks everything, and deliberately so: a whole famine chain
## hangs off a villager going to buy food the moment they are hungry.
func test_hunger_beats_every_other_need_at_once():
	var all_urgent := {"hunger": 1.0, "thirst": 1.0, "rest": 1.0, "company": 1.0}
	assert_eq(behavior.decide(_context(all_urgent))["intent"], VillagerBehavior.EAT)


func test_company_is_the_need_a_villager_puts_off():
	var drives := _only("company")
	drives["rest"] = 1.0
	assert_eq(behavior.decide(_context(drives))["intent"], VillagerBehavior.REST)


## A need that is not urgent yet does not steer anybody: a villager who is
## slightly peckish keeps working.
##
## Driven through a REAL NpcNeeds clock rather than a hand-written level,
## because the contract that makes this true lives there: `decide` is fed
## Drives.gains(), which is 0 below a drive's own onset and 1 at its
## threshold -- not raw levels, which would have every villager permanently
## one-thousandth hungry and therefore permanently walking to market.
## Written as a hand-set 0.0 first, which passed vacuously against quiet
## drives and proved nothing.
##
## Only hunger's own gain is published here. Published whole, the run finds
## the villager DRINKING before ever going hungry, which is correct and is
## its own test below -- but it is not this one's question.
func test_a_need_below_its_own_threshold_steers_nobody():
	var NpcNeeds = load("res://src/world/npc_needs.gd")
	var needs = NpcNeeds.new()
	var step := (1.0 / float(NpcNeeds.HUNGER_RATE_PER_SECOND)) * 0.02
	var flipped_at := -1.0
	for i in 200:
		var drives := _quiet_drives()
		drives["hunger"] = needs.gains()["hunger"]
		var intent: String = behavior.decide(_context(drives))["intent"]
		if intent == VillagerBehavior.NOTHING:
			assert_false(needs.is_hungry(), "a villager past their own hunger threshold was not steered")
		else:
			assert_eq(intent, VillagerBehavior.EAT)
			assert_true(needs.is_hungry(), "a villager below their own hunger threshold was steered anyway")
			if flipped_at < 0.0:
				flipped_at = needs.hunger
		needs.advance(step)
	assert_gt(flipped_at, 0.0, "precondition: hunger really crossed its threshold during the run")
	assert_almost_eq(
		flipped_at, float(NpcNeeds.HUNGRY_THRESHOLD), 0.05,
		"the villager started for market at their own threshold, not somewhere else"
	)


## Thirst rises faster than hunger (the mammal profile: 0.03 against 0.02),
## so a villager really does get thirsty BEFORE they get hungry and the well
## is the first place a day sends them. Found by a test that assumed
## otherwise; kept because it is the behaviour, not the accident.
func test_a_villager_reaches_for_water_before_food_over_a_real_clock():
	var NpcNeeds = load("res://src/world/npc_needs.gd")
	var needs = NpcNeeds.new()
	var step := (1.0 / float(NpcNeeds.HUNGER_RATE_PER_SECOND)) * 0.02
	var first := VillagerBehavior.NOTHING
	for i in 200:
		var intent: String = behavior.decide(_context(needs.gains()))["intent"]
		if intent != VillagerBehavior.NOTHING:
			first = intent
			break
		needs.advance(step)
	assert_eq(first, VillagerBehavior.DRINK, "the first need of a villager's day is a drink")


# -- the nearest of several ------------------------------------------------


func test_a_lonely_villager_walks_to_the_nearest_neighbour():
	var context := _context(_only("company"))
	context["company"] = [Vector2(200, 0), Vector2(30, 0), Vector2(120, 0)]
	assert_eq(behavior.decide(context)["target"], Vector2(30, 0))


# -- it really is the shared engine ----------------------------------------


## Not a private copy of the wiring table: the intents this can ever return
## are exactly the approaches the ethogram names for a villager, so adding a
## wiring there is all it takes to add a behaviour here.
func test_every_intent_comes_from_the_ethograms_own_villager_wirings():
	var approaches := {}
	for wiring in Ethogram.wirings_for("villager"):
		approaches[wiring["approach"]] = true
	for intent in [
		VillagerBehavior.EAT, VillagerBehavior.DRINK,
		VillagerBehavior.REST, VillagerBehavior.SOCIALIZE,
	]:
		assert_true(approaches.has(intent), "%s is not a villager wiring's own approach" % intent)


func test_the_quiet_answer_is_not_one_of_the_wirings():
	for wiring in Ethogram.wirings_for("villager"):
		assert_ne(wiring["approach"], VillagerBehavior.NOTHING)
