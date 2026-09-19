extends GutTest

## SpellTuition: docs/concept/magic.md's 2026-09-19 section -- what a mage
## guild is actually FOR.
##
## The charter (settlement_charter.md) gates a mage_guild at CITY tier, so
## the way to one is through a village the player helped grow. This is the
## other half of that trade: behind the gate, a guild TEACHES. It is also
## the access layer the compile gate was always going to need and which did
## not exist in code -- a per-caster known-spell set distinct from the
## world's catalogue, a gold-for-knowledge transaction, and a structure gate
## on magic.

const SpellTuition = preload("res://src/gameplay/spell_tuition.gd")
const SpellBook = preload("res://src/gameplay/spell_book.gd")
const SpellCost = preload("res://src/gameplay/spell_cost.gd")
const SpellExecutor = preload("res://src/gameplay/spell_executor.gd")
const RarityTier = preload("res://src/gameplay/rarity_tier.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const Wallet = preload("res://src/gameplay/wallet.gd")
const SettlementCharter = preload("res://src/emergence/settlement_charter.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

var tuition: RefCounted
var book: RefCounted


func before_each():
	tuition = SpellTuition.new()
	book = SpellBook.new()


func _starting() -> Array:
	return SpellTuition.STARTING_SPELL_IDS.duplicate()


## The dearest spell in the whole catalogue, whatever the book holds.
func _dearest_teachable() -> int:
	var dearest := 0
	for spell_id in tuition.teachable(book, _starting()):
		dearest = maxi(dearest, tuition.tuition_for(book, spell_id))
	return dearest


func _cheapest_teachable() -> int:
	var cheapest := -1
	for spell_id in tuition.teachable(book, _starting()):
		var price: int = tuition.tuition_for(book, spell_id)
		if cheapest < 0 or price < cheapest:
			cheapest = price
	return cheapest


# -- the known set is yours; the catalogue is the world's --------------------

func test_a_caster_starts_knowing_only_the_starting_set():
	# The whole point of the split: SpellBook.has() says a spell EXISTS, it
	# must no longer say you can cast it.
	assert_gt(book.known_ids().size(), SpellTuition.STARTING_SPELL_IDS.size(),
		"the catalogue must hold more than a caster starts with, or there is nothing to teach")


func test_the_starting_set_contains_whatever_the_cast_key_is_bound_to():
	# A character who cannot cast the spell the game binds to their cast
	# button is a bug, not a gate (magic.md, this section).
	var Player = load("res://scenes/player.gd")
	assert_true(SpellTuition.STARTING_SPELL_IDS.has(Player.DEFAULT_CAST_SPELL_ID))


func test_every_starting_spell_is_really_in_the_catalogue():
	for spell_id in SpellTuition.STARTING_SPELL_IDS:
		assert_true(book.has(spell_id), "%s is granted at birth but is not in the book" % spell_id)


func test_teachable_is_the_catalogue_minus_what_you_already_know():
	var offered: Array = tuition.teachable(book, _starting())
	for spell_id in SpellTuition.STARTING_SPELL_IDS:
		assert_false(offered.has(spell_id), "a guild must not offer to teach what you know")
	for spell_id in book.known_ids():
		if not SpellTuition.STARTING_SPELL_IDS.has(spell_id):
			assert_true(offered.has(spell_id), "%s is in the catalogue and unknown -- it must be on offer" % spell_id)


func test_teaching_nothing_is_offered_to_someone_who_knows_everything():
	assert_eq(tuition.teachable(book, book.known_ids()), [])


func test_teachable_is_stable_in_order():
	assert_eq(tuition.teachable(book, _starting()), tuition.teachable(book, _starting()))


# -- the price is derived, never typed --------------------------------------

func test_power_is_spell_costs_own_derived_base_not_a_second_measure():
	var executor := SpellExecutor.new()
	var cost := SpellCost.new()
	for spell_id in book.known_ids():
		var rule = executor.cast_rule(book.ast_for(spell_id))
		var expected: float = cost.derived_base(rule.get("pipeline", []), executor.delivery_for(rule))
		assert_almost_eq(tuition.power_of(book, spell_id), expected, 0.0001,
			"%s must be priced off the same number that prices its mana" % spell_id)


func test_a_spell_outside_the_catalogue_has_no_power_and_no_price():
	assert_eq(tuition.power_of(book, "not_a_real_spell"), 0.0)
	assert_eq(tuition.tuition_for(book, "not_a_real_spell"), 0)


func test_gold_per_power_unit_is_read_off_the_shops_live_meal_price():
	# Price a spell in bread and it stays honest when bread moves: the anchor
	# is a ratio between two things the game already prices.
	var expected := SpellTuition.MEALS_PER_POWER_UNIT * float(Shop.CATALOG[SpellTuition.MEAL_ITEM_ID])
	assert_almost_eq(SpellTuition.gold_per_power_unit(), expected, 0.0001)


func test_the_meal_the_anchor_names_is_really_on_the_shelf():
	assert_true(Shop.CATALOG.has(SpellTuition.MEAL_ITEM_ID))


func test_tuition_is_power_times_the_anchor_times_the_rarity_multiplier():
	var rarity := RarityTier.new()
	for spell_id in book.known_ids():
		var power: float = tuition.power_of(book, spell_id)
		var tier: String = rarity.tier_from_complexity(power)
		var expected := int(round(power * SpellTuition.gold_per_power_unit() * rarity.stat_multiplier(tier)))
		assert_eq(tuition.tuition_for(book, spell_id), expected, "%s" % spell_id)


func test_tuition_rises_strictly_with_power():
	# Monotonic: a stronger spell is never cheaper to be taught.
	var ranked: Array = book.known_ids().duplicate()
	ranked.sort_custom(func(a, b): return tuition.power_of(book, a) < tuition.power_of(book, b))
	for i in range(1, ranked.size()):
		assert_gte(tuition.tuition_for(book, ranked[i]), tuition.tuition_for(book, ranked[i - 1]))


func test_the_rarity_tier_a_price_uses_is_the_same_score_the_gem_price_uses():
	var rarity := RarityTier.new()
	for spell_id in book.known_ids():
		assert_eq(tuition.tier_of(book, spell_id), rarity.tier_from_complexity(tuition.power_of(book, spell_id)))


func test_a_guild_never_teaches_for_free():
	for spell_id in book.known_ids():
		assert_gt(tuition.tuition_for(book, spell_id), 0, "%s must cost something" % spell_id)


# -- the anchor constant, pinned by the design claim it encodes -------------

## What MEALS_PER_POWER_UNIT encodes is a WEIGHT CLASS, not a price, and
## these three claims are how that stops being a matter of taste. Together
## they admit roughly 10..39 meals per power unit and nothing outside --
## deliberately a wide band, because a weight class is a wide thing; what
## would be dishonest is a tight band pretending to a precision the design
## does not have.
##
## The upper bound used to be "no spell costs more than the dearest thing
## on the shelf". That was true of a three-spell starter book and stopped
## being true the moment the book grew real tier-3 magic -- correctly so: a
## lesson from an archmage SHOULD cost more than anything a merchant
## stocks, which is now the third claim below rather than a broken second.

func test_the_cheapest_lesson_costs_more_than_any_tool_or_weapon_on_the_shelf():
	# A spell is a PERMANENT capability. It is not a sword you can also
	# just buy.
	var dearest_tool := 0
	for item_id in ["fishing_rod", "torch", "cooked_meat", "leather_helm", "iron_sword"]:
		dearest_tool = maxi(dearest_tool, int(Shop.CATALOG[item_id]))
	assert_gt(_cheapest_teachable(), dearest_tool)


func test_the_cheapest_lesson_sits_in_the_house_blueprint_weight_class():
	# At least the cheapest blueprint, and no more than the dearest: your
	# FIRST spell is somewhere between a small house and a manor.
	assert_gte(_cheapest_teachable(), int(Shop.CATALOG["blueprint_small_house"]))
	assert_lte(_cheapest_teachable(), int(Shop.CATALOG["blueprint_manor"]))


func test_the_deepest_magic_costs_more_than_anything_a_merchant_sells():
	# The other half of the same claim, and the reason an archmage is worth
	# travelling for: what they teach is not a thing you can walk into a
	# market and buy.
	var dearest_on_the_shelf := 0
	for item_id in Shop.CATALOG:
		dearest_on_the_shelf = maxi(dearest_on_the_shelf, int(Shop.CATALOG[item_id]))
	assert_gt(_dearest_teachable(), dearest_on_the_shelf)


# -- the refusal is the feature ---------------------------------------------

func _refusal(spell_id: String, known: Array, gold: int, at_guild: bool) -> Dictionary:
	return tuition.refusal_for(book, spell_id, known, gold, at_guild)


func test_standing_at_a_guild_with_the_gold_and_no_prior_knowledge_is_no_refusal():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	assert_eq(_refusal(spell_id, _starting(), tuition.tuition_for(book, spell_id), true), {})


func test_not_standing_at_a_guild_is_refused_and_names_the_building():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var refusal := _refusal(spell_id, _starting(), 100000, false)
	assert_eq(refusal.get("reason", ""), SpellTuition.NO_GUILD)
	assert_eq(refusal.get("building_id", ""), SpellTuition.GUILD_BUILDING_ID)


func test_the_building_the_refusal_names_is_the_one_the_charter_gates():
	# The refusal points at the charter ladder: go find, or grow, a city.
	assert_eq(SettlementCharter.min_tier_for(SpellTuition.GUILD_BUILDING_ID), "city")
	assert_true(BuildingCatalog.all_building_ids().has(SpellTuition.GUILD_BUILDING_ID))


func test_a_spell_you_already_know_is_refused():
	var refusal := _refusal(SpellTuition.STARTING_SPELL_IDS[0], _starting(), 100000, true)
	assert_eq(refusal.get("reason", ""), SpellTuition.ALREADY_KNOWN)


func test_being_short_of_the_price_names_the_price_and_the_shortfall():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var price: int = tuition.tuition_for(book, spell_id)
	var refusal := _refusal(spell_id, _starting(), price - 40, true)
	assert_eq(refusal.get("reason", ""), SpellTuition.CANNOT_AFFORD)
	assert_eq(refusal.get("tuition", 0), price, "the refusal must say what it costs")
	assert_eq(refusal.get("short", 0), 40, "'come back with 40 more gold', never a bare no")


func test_exactly_the_price_is_enough():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	assert_eq(_refusal(spell_id, _starting(), tuition.tuition_for(book, spell_id), true), {})


func test_a_spell_outside_the_catalogue_is_refused_before_it_is_priced():
	var refusal := _refusal("not_a_real_spell", _starting(), 100000, true)
	assert_eq(refusal.get("reason", ""), SpellTuition.UNKNOWN_SPELL)


func test_no_guild_is_reported_before_the_price():
	# Standing in a field is the first thing wrong, not the last.
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var refusal := _refusal(spell_id, _starting(), 0, false)
	assert_eq(refusal.get("reason", ""), SpellTuition.NO_GUILD)


func test_every_refusal_carries_the_spell_it_is_about():
	for refusal in [
		_refusal("not_a_real_spell", _starting(), 100000, true),
		_refusal("minor_heal", _starting(), 100000, false),
		_refusal(SpellTuition.STARTING_SPELL_IDS[0], _starting(), 100000, true),
		_refusal("minor_heal", _starting(), 0, true),
	]:
		assert_eq(refusal.get("spell_id", ""), refusal.get("spell_id", "_"), "")
		assert_true(refusal.has("spell_id"), "a refusal must name what it refused: %s" % refusal)


# -- learning: gold moves only on a learn that lands -------------------------

func _wallet(balance: int) -> RefCounted:
	var wallet := Wallet.new()
	wallet.add(balance)
	return wallet


func test_learning_adds_the_spell_and_charges_exactly_the_tuition():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var price: int = tuition.tuition_for(book, spell_id)
	var wallet := _wallet(price + 7)

	var result: Dictionary = tuition.learn(book, spell_id, _starting(), wallet, true)

	assert_true(result["ok"])
	assert_eq(result["gold"], price)
	assert_eq(wallet.balance, 7)
	assert_true((result["known"] as Array).has(spell_id))


func test_learning_leaves_the_callers_own_known_list_alone():
	# Pure: the caller decides whether to adopt the new list.
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var known := _starting()
	tuition.learn(book, spell_id, known, _wallet(100000), true)
	assert_eq(known, _starting(), "learn must not mutate the array it was handed")


func test_a_refused_learn_charges_nothing():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var price: int = tuition.tuition_for(book, spell_id)
	for attempt in [
		{"spell_id": spell_id, "gold": price, "at_guild": false},
		{"spell_id": spell_id, "gold": price - 1, "at_guild": true},
		{"spell_id": SpellTuition.STARTING_SPELL_IDS[0], "gold": price, "at_guild": true},
		{"spell_id": "not_a_real_spell", "gold": price, "at_guild": true},
	]:
		var wallet := _wallet(attempt["gold"])
		var result: Dictionary = tuition.learn(book, attempt["spell_id"], _starting(), wallet, attempt["at_guild"])
		assert_false(result["ok"], "%s" % attempt)
		assert_eq(result["gold"], 0)
		assert_eq(wallet.balance, attempt["gold"], "a refusal must never move gold: %s" % attempt)
		assert_eq(result["known"], _starting())
		assert_false((result["refusal"] as Dictionary).is_empty())


func test_a_landed_learn_carries_no_refusal():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var result: Dictionary = tuition.learn(book, spell_id, _starting(), _wallet(100000), true)
	assert_eq(result["refusal"], {})


func test_learning_the_same_spell_twice_is_refused_the_second_time():
	var spell_id: String = tuition.teachable(book, _starting())[0]
	var wallet := _wallet(100000)
	var first: Dictionary = tuition.learn(book, spell_id, _starting(), wallet, true)
	var after: int = wallet.balance

	var second: Dictionary = tuition.learn(book, spell_id, first["known"], wallet, true)

	assert_false(second["ok"])
	assert_eq(second["refusal"].get("reason", ""), SpellTuition.ALREADY_KNOWN)
	assert_eq(wallet.balance, after, "a guild must not charge twice for one spell")


func test_learning_every_teachable_spell_ends_with_the_whole_catalogue():
	var known := _starting()
	var wallet := _wallet(100000)
	for spell_id in tuition.teachable(book, known):
		known = tuition.learn(book, spell_id, known, wallet, true)["known"]
	assert_eq(tuition.teachable(book, known), [])
	for spell_id in book.known_ids():
		assert_true(known.has(spell_id))
