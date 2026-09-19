extends GutTest

## docs/concept/village_estates.md: the step that makes an unmet basket
## something a village can BUILD its way out of.
##
## Without it the estate layer is a demand nothing answers. A village short
## of bread has no bakery, no mill and no farm, and nothing in the game
## ever tells it to raise one -- so no household ever meets its station and
## the whole ladder is decorative. SettlementBuildDecision already reasons
## "bread -> bakery -> flour -> mill -> wheat -> farm" from a shortfall in
## one fixed shape (SettlementFood.food_shortfall_for's own), so an unmet
## basket is reported in exactly that shape and needs no new code on the
## other side.

const EstateShortfall = preload("res://src/emergence/estate_shortfall.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const EstateConsumption = preload("res://src/emergence/estate_consumption.gd")

const FOOD := VillageEstates.FOOD_KIND_TOKEN
const FUEL := VillageEstates.FUEL_ITEM_ID


func _supplied(estate_counts: Dictionary) -> Dictionary:
	var satisfaction := {}
	for estate in estate_counts:
		for good in VillageEstates.basket_goods(estate):
			satisfaction[good] = 1.0
	return satisfaction


func test_a_fully_supplied_village_reports_no_shortfall_at_all():
	var counts := {"bauer": 4}
	assert_eq(EstateShortfall.shortfalls_for(counts, _supplied(counts), 1.0), [])


func test_a_village_with_nobody_in_it_reports_nothing():
	assert_eq(EstateShortfall.shortfalls_for({}, {}, 1.0), [])


func test_a_span_of_no_time_reports_nothing():
	var counts := {"bauer": 4}
	assert_eq(EstateShortfall.shortfalls_for(counts, {"bread": 0.0}, 0.0), [])


## The shape is SettlementFood.food_shortfall_for's own, so the build
## decision reasons about it with no new code.
func test_a_shortfall_is_reported_in_the_shape_the_build_decision_already_reads():
	var counts := {"bauer": 4}
	var satisfaction := _supplied(counts)
	satisfaction["bread"] = 0.0
	var shortfalls: Array = EstateShortfall.shortfalls_for(counts, satisfaction, 1.0)
	assert_eq(shortfalls.size(), 1)
	var entry: Dictionary = shortfalls[0]
	for key in ["kind", "household_id", "occupation", "recipe_id", "missing"]:
		assert_true(entry.has(key), "a shortfall with no %s is not the shape" % key)
	assert_eq(String(entry["kind"]), EstateShortfall.KIND)
	assert_eq(String(entry["missing"][0]["item_id"]), "bread")


## The NEED is the real unmet quantity, so the decision's worst-first
## ranking has a real number to rank rather than a flag.
func test_the_need_is_the_real_units_the_village_actually_went_short():
	var counts := {"bauer": 10}
	var satisfaction := _supplied(counts)
	satisfaction["bread"] = 0.0
	var shortfalls: Array = EstateShortfall.shortfalls_for(counts, satisfaction, 1.0)
	var owed: float = float(VillageEstates.station_basket("bauer")["bread"]) * 10.0
	assert_almost_eq(float(shortfalls[0]["missing"][0]["need"]), owed, 0.51)


func test_a_half_supplied_good_is_owed_half_as_much():
	var counts := {"bauer": 10}
	var whole := _supplied(counts)
	whole["bread"] = 0.0
	var half := _supplied(counts)
	half["bread"] = 0.5
	var whole_need: float = float(EstateShortfall.shortfalls_for(counts, whole, 1.0)[0]["missing"][0]["need"])
	var half_need: float = float(EstateShortfall.shortfalls_for(counts, half, 1.0)[0]["missing"][0]["need"])
	assert_true(half_need < whole_need)
	assert_true(half_need > 0.0, "a village half short of bread is still short of bread")


## A need is a whole unit at minimum: the build decision ranks and acts on
## integers, and "0.4 of a loaf short" must not round away to nothing.
func test_even_the_smallest_real_shortfall_is_at_least_one_unit():
	var counts := {"kossaet": 1}
	var satisfaction := _supplied(counts)
	satisfaction["herb"] = 0.0
	var shortfalls: Array = EstateShortfall.shortfalls_for(counts, satisfaction, 1.0)
	assert_eq(shortfalls.size(), 1)
	assert_true(int(shortfalls[0]["missing"][0]["need"]) >= 1)


## The food TOKEN is never reported: it is not an item id, nothing can be
## built to produce "kind:food", and SettlementFood already has its own,
## calibrated food shortfall for exactly this.
func test_the_food_token_is_never_reported_as_a_buildable_shortfall():
	var counts := {"kossaet": 5}
	var satisfaction := _supplied(counts)
	satisfaction[FOOD] = 0.0
	assert_eq(
		EstateShortfall.shortfalls_for(counts, satisfaction, 1.0),
		[],
		"a village short of nothing but food asked for something buildable"
	)


## And it is skipped rather than skipping the whole village: a village
## short of food AND firewood still asks for the firewood.
func test_a_village_short_of_food_and_fuel_still_asks_for_the_fuel():
	var counts := {"kossaet": 5}
	var satisfaction := _supplied(counts)
	satisfaction[FOOD] = 0.0
	satisfaction[FUEL] = 0.0
	var goods: Array = []
	for shortfall in EstateShortfall.shortfalls_for(counts, satisfaction, 1.0):
		for missing in shortfall["missing"]:
			goods.append(String(missing["item_id"]))
	assert_eq(goods, [FUEL], "the village asked for the food token, or forgot the firewood")


## Several estates short of the same good ask for it ONCE, with the sum --
## otherwise the worst-first ranking sees three small asks instead of one
## big one and builds the wrong thing.
func test_estates_short_of_the_same_good_ask_once_for_the_whole_village():
	var counts := {"bauer": 5, "handwerker": 5}
	var satisfaction := _supplied(counts)
	satisfaction["bread"] = 0.0
	var shortfalls: Array = EstateShortfall.shortfalls_for(counts, satisfaction, 1.0)
	var bread_entries := 0
	for shortfall in shortfalls:
		for missing in shortfall["missing"]:
			if String(missing["item_id"]) == "bread":
				bread_entries += 1
	assert_eq(bread_entries, 1, "the village asked for bread more than once")


## Every good a shortfall names is a real item, so the build decision can
## always look up a recipe for it rather than silently skipping.
func test_every_reported_good_is_a_real_item():
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var catalog = ItemCatalog.new()
	var counts := {"kossaet": 2, "bauer": 2, "handwerker": 2, "buerger": 2}
	for shortfall in EstateShortfall.shortfalls_for(counts, {}, 1.0):
		for missing in shortfall["missing"]:
			assert_true(catalog.has(String(missing["item_id"])), "%s is not a real item" % missing["item_id"])


## Deterministic: the same village reports the same shortfalls in the same
## order every time, never in Dictionary iteration order.
func test_the_same_village_reports_the_same_shortfalls_in_the_same_order():
	var counts := {"kossaet": 3, "buerger": 3}
	var first: Array = EstateShortfall.shortfalls_for(counts, {}, 1.0)
	for _i in 20:
		assert_eq(EstateShortfall.shortfalls_for(counts, {}, 1.0), first)


## And the whole point, end to end: a village short of beer is a village
## the build decision can be told to raise a brewery for, because beer has
## a real recipe with a real structure gate.
func test_a_village_short_of_beer_reports_a_good_a_real_structure_makes():
	var CraftingRecipeBook = load("res://src/gameplay/crafting_recipe_book.gd")
	var book = CraftingRecipeBook.new()
	var counts := {"buerger": 4}
	var satisfaction := _supplied(counts)
	satisfaction["beer"] = 0.0
	var reported := false
	for shortfall in EstateShortfall.shortfalls_for(counts, satisfaction, 1.0):
		for missing in shortfall["missing"]:
			if String(missing["item_id"]) != "beer":
				continue
			reported = true
			var recipe_id: String = book.recipe_for_output("beer")
			assert_ne(recipe_id, "", "beer has no recipe to build toward")
			assert_eq(book.recipe_requires_structure(recipe_id), "brewery")
	assert_true(reported, "a village with no beer never asked for any")
