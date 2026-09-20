extends GutTest

## What a field sows (docs/concept/village_farms.md, "What a field sows
## follows the village's need").
##
## Reported with the village's panels open: *"they have 0 Herbs even though
## there are 3 farm houses... so deciding what to plant must be based on
## demand"*, and beside it *"The warehouse shows 205 Wheat but the Villagers
## show 50% food"*. The second explains the first: wheat is
## ItemCatalog kind "material", so a village that sows only wheat has
## grown nothing anybody can eat.

const VillageCropChoice = preload("res://src/gameplay/village_crop_choice.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

const FOOD := VillageEstates.FOOD_KIND_TOKEN


## The defect that started this, pinned where it can be seen: wheat is not
## food, so a granary full of it satisfies nothing on its own. If this ever
## flips, the whole "wheat only where it can be baked" rule below is moot
## and should go.
func test_wheat_is_not_food_but_the_other_crops_are():
	var catalog := ItemCatalog.new()
	assert_ne(catalog.kind_of("wheat"), "food", "grain is not food until it is milled")
	for crop_id in ["herb", "carrot", "potato"]:
		assert_eq(catalog.kind_of(crop_id), "food", "%s is edible as harvested" % crop_id)


func test_every_sowable_crop_is_a_real_catalog_item():
	var catalog := ItemCatalog.new()
	assert_gt(VillageCropChoice.sowable_crops().size(), 0, "the premise: something is sowable")
	for crop_id in VillageCropChoice.sowable_crops():
		assert_true(catalog.has(crop_id), "%s is sown but is not an item" % crop_id)


## A crop may only claim to answer a good some estate really asks for -- a
## crop answering an invented good would be a field sown for nothing.
func test_every_good_a_crop_answers_is_one_some_estate_really_asks_for():
	var asked := {}
	for estate in VillageEstates.ESTATE_IDS:
		for good in VillageEstates.basket_goods(estate):
			asked[good] = true
	for crop_id in VillageCropChoice.sowable_crops():
		var goods: Array = VillageCropChoice.goods_answered_by(crop_id)
		assert_gt(goods.size(), 0, "%s answers nothing" % crop_id)
		for good in goods:
			assert_true(asked.has(good), "%s claims to answer %s, which nobody asks for" % [crop_id, good])


func test_a_village_short_of_herbs_sows_herbs():
	assert_eq(
		VillageCropChoice.choose({"herb": 0.0, FOOD: 0.9}, false, "wheat"), "herb"
	)


func test_a_village_short_of_food_sows_something_it_can_eat():
	var chosen := VillageCropChoice.choose({"herb": 0.95, FOOD: 0.1}, false, "wheat")
	assert_true(
		VillageCropChoice.goods_answered_by(chosen).has(FOOD),
		"%s does not feed anybody" % chosen
	)


## The rule the reported warehouse is about: 205 wheat feeds nobody in a
## village with no mill, so wheat is not even offered there.
func test_wheat_is_never_sown_where_the_village_cannot_bake_it():
	var starving := {"bread": 0.0, FOOD: 0.0, "herb": 0.0}
	assert_ne(
		VillageCropChoice.choose(starving, false, "wheat"), "wheat",
		"a village with no mill sows something it can eat"
	)


func test_wheat_is_sown_where_the_village_really_can_bake_it():
	assert_eq(
		VillageCropChoice.choose({"bread": 0.0, FOOD: 0.9, "herb": 0.9}, true, "wheat"), "wheat"
	)


## Scored by the WORST good a crop answers, not the mean -- the same
## minimum rule EstateConsumption already applies to an estate's verdict.
## Herb answers both `herb` and food; with food desperate and herb
## comfortable, herb is still the crop that relieves the desperate one.
func test_a_crop_is_scored_by_the_worst_good_it_answers():
	var chosen := VillageCropChoice.choose({"herb": 1.0, FOOD: 0.0}, false, "wheat")
	assert_true(
		VillageCropChoice.goods_answered_by(chosen).has(FOOD),
		"the desperate good decides, not the comfortable one: got %s" % chosen
	)


## Occupation is a tie-break and nothing more: among crops the village needs
## exactly as much, the herbalist reaches for herbs.
func test_the_traditional_crop_breaks_a_tie_but_does_not_decide():
	var even := {"herb": 0.5, FOOD: 0.5}
	assert_eq(VillageCropChoice.choose(even, false, "herb"), "herb", "tied: the herbalist's own")
	var bread_is_desperate := {"bread": 0.0, FOOD: 0.8, "herb": 0.8}
	for tradition in ["herb", "carrot", "potato"]:
		assert_eq(
			VillageCropChoice.choose(bread_is_desperate, true, tradition), "wheat",
			"not tied: need decides, whoever is holding the seed (%s)" % tradition
		)


## Fail-open, like every other world hook here: a marker with no world to
## ask keeps sowing exactly what it always did.
func test_no_reading_at_all_keeps_the_traditional_crop():
	assert_eq(VillageCropChoice.choose({}, false, "wheat"), "wheat")
	assert_eq(VillageCropChoice.choose({}, true, "herb"), "herb")


## A reading that names only goods no crop can answer is the same as no
## reading: sowing a field for candles would be worse than tradition.
func test_a_need_no_crop_can_answer_keeps_the_traditional_crop():
	assert_eq(VillageCropChoice.choose({"candle": 0.0, "wood": 0.0}, false, "wheat"), "wheat")


func test_the_choice_is_deterministic():
	var reading := {"herb": 0.3, FOOD: 0.3, "bread": 0.3}
	var first := VillageCropChoice.choose(reading, true, "wheat")
	for _i in 5:
		assert_eq(VillageCropChoice.choose(reading, true, "wheat"), first)
