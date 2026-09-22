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


## Whether wheat answers anything here at all: a mill AND a bakery, because
## the chain is grain -> flour -> bread and a village with only half of it
## still cannot eat (docs/concept/milling_and_baking.md).
func test_wheat_needs_both_halves_of_the_chain_before_it_is_worth_sowing():
	assert_true(VillageCropChoice.can_bake(["mill", "bakery", "farmhouse"]))
	assert_false(VillageCropChoice.can_bake(["mill"]), "flour nobody can bake")
	assert_false(VillageCropChoice.can_bake(["bakery"]), "an oven with no flour")
	assert_false(VillageCropChoice.can_bake([]), "the reported village")


## Both links are real placeables rather than names invented here -- a
## chain named after buildings the world cannot raise would gate wheat
## for ever.
func test_both_links_of_the_chain_are_real_buildable_things():
	var catalog := ItemCatalog.new()
	assert_gt(VillageCropChoice.BAKING_CHAIN.size(), 0, "the premise: there is a chain")
	for structure_id in VillageCropChoice.BAKING_CHAIN:
		assert_true(catalog.has(structure_id), "%s is not a real thing" % structure_id)


## The end-to-end shape of the report: a village with three farmhouses, no
## mill, wheat in the store and everybody hungry stops sowing wheat.
func test_the_reported_village_stops_sowing_what_it_cannot_eat():
	var reported := {FOOD: 0.5, "herb": 0.0, "bread": 0.5}
	var chosen := VillageCropChoice.choose(
		reported, VillageCropChoice.can_bake(["farmhouse", "warehouse"]), "wheat"
	)
	assert_ne(chosen, "wheat", "205 wheat and half rations is what this fixes")
	assert_eq(chosen, "herb", "and the good actually at zero is the one it sows")


# -- a starving village plants what actually feeds it -----------------------
#
# Reported live with the panels open: *"The farmers produce mostly herbs
# even though it says it can feed 0 / 10 ... the supply chain needs to be
# stable, so that happiness can saturate at 100% and unlock second tier
# buildings"*.
#
# Measured on three real villages, with the settlement step really running
# (tools/probe_village_cropping.gd -- a first pass that only LOADED chunks
# read an empty satisfaction and would have reported the wrong defect):
#
#     satisfaction: { "wood": 1.0, "herb": 0.0, "kind:food": 0.0 }
#     scores:       { "herb": 0.0, "carrot": 0.0, "potato": 0.0, "wheat": inf }
#     a wheat-farmer sows: herb
#     a herb-farmer  sows: herb
#
# A hungry village has BOTH goods at 0.0, so the scores tie -- and a tie is
# the normal state of a village that needs feeding, not an edge case. The
# tie was broken by declaration order, and `herb` is declared first, so
# every field in a starving village sowed the crop that feeds it least: a
# 20g bunch of herbs against a 170g potato, eight and a half times the food
# per harvest. Hence "mostly herbs" and "feeds 0 of 10" in the same panel.
#
# The score itself is right and is not touched: a good sitting at 0.0 is
# worth more than one at 0.9. What is added is what happens when two crops
# are equally needed -- the one that really feeds more wins, on the
# catalog's own real produce masses.


func test_a_starving_village_sows_the_crop_that_feeds_it_most():
	var starving := {"herb": 0.0, VillageEstates.FOOD_KIND_TOKEN: 0.0}
	for default_crop in ["wheat", "herb", "carrot", ""]:
		assert_eq(
			VillageCropChoice.choose(starving, false, default_crop), "potato",
			"a %s-farmer in a starving village should sow the heaviest food crop" % default_crop
		)


## ...and the rule it must not break: a FED village that lacks herbs still
## sows herbs, because then the scores do not tie and the worst-supplied
## good really is the herb.
func test_a_fed_village_still_sows_the_good_it_lacks():
	var fed := {"herb": 0.0, VillageEstates.FOOD_KIND_TOKEN: 0.9}
	assert_eq(VillageCropChoice.choose(fed, false, "wheat"), "herb")


## And the reverse: a village with herbs and no food sows food, as it always
## did -- the score, not the weight, decides that.
func test_a_village_with_herbs_and_no_food_sows_food():
	var hungry := {"herb": 0.9, VillageEstates.FOOD_KIND_TOKEN: 0.0}
	var sown := VillageCropChoice.choose(hungry, false, "wheat")
	assert_true(
		sown == "potato" or sown == "carrot", "expected a food crop, got %s" % sown
	)


## The weights are the ItemCatalog's own real produce masses, not numbers
## invented here -- so "which crop feeds more" cannot drift from what the
## world says a carrot weighs.
func test_the_crop_food_weights_are_the_catalogs_own_real_masses():
	var catalog := ItemCatalog.new()
	for crop_id in VillageCropChoice.FOOD_WEIGHT_KG:
		assert_almost_eq(
			float(VillageCropChoice.FOOD_WEIGHT_KG[crop_id]),
			catalog.make(crop_id).mass_kg, 0.0001,
			"%s's weight must be the catalog's own" % crop_id
		)
	# Every crop that answers food has to have one, or the tie-break is
	# silently deciding on a zero.
	for crop_id in VillageCropChoice.SOWABLE:
		if VillageCropChoice.SOWABLE[crop_id].has(VillageEstates.FOOD_KIND_TOKEN):
			assert_true(
				VillageCropChoice.FOOD_WEIGHT_KG.has(crop_id),
				"%s answers food and has no weight" % crop_id
			)


## Deterministic: the same reading always sows the same crop.
func test_the_same_reading_always_sows_the_same_crop():
	var reading := {"herb": 0.0, VillageEstates.FOOD_KIND_TOKEN: 0.0}
	var first := VillageCropChoice.choose(reading, false, "wheat")
	for _i in 8:
		assert_eq(VillageCropChoice.choose(reading, false, "wheat"), first)


## The floor is bounded by the two readings that define it, never eyeballed:
## strictly above the starving villages measured, and no higher than the
## half-fed case the occupation tie-break was written for.
func test_the_hunger_floor_sits_between_the_two_readings_that_define_it():
	assert_gt(VillageCropChoice.HUNGRY_BELOW, 0.0, "a starving village must fall below it")
	assert_lte(
		VillageCropChoice.HUNGRY_BELOW, 0.5,
		"a half-fed village must not, or the occupation tie-break never runs"
	)
