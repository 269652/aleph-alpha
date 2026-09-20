extends GutTest

## docs/concept/village_estates.md mechanism 6: the tax a village's
## households actually pay, and the loop it closes.
##
## Deliberately paid into the SAME VillageWages purse the subsistence wage
## already comes out of, rather than a second treasury. That is what closes
## the loop on machinery that already exists: supply the baskets, households
## rise, a risen household pays more tax, the purse funds the wages and the
## next building, the building supplies the baskets.

const VillageWages = preload("res://src/world/village_wages.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")


func test_a_village_with_nobody_in_it_raises_nothing():
	assert_almost_eq(VillageWages.estate_tax_for({}, {}, 1.0), 0.0, 0.0001)


func test_a_span_of_no_time_raises_nothing():
	assert_almost_eq(VillageWages.estate_tax_for({"bauer": 10}, {"bauer": 1.0}, 0.0), 0.0, 0.0001)
	assert_almost_eq(VillageWages.estate_tax_for({"bauer": 10}, {"bauer": 1.0}, -5.0), 0.0, 0.0001)


func test_one_provided_household_pays_exactly_its_own_estates_rate():
	assert_almost_eq(
		VillageWages.estate_tax_for({"bauer": 1}, {"bauer": 1.0}, 1.0),
		VillageEstates.BASE_TAX_PER_DAY["bauer"],
		0.0001
	)


func test_the_take_scales_with_households_and_with_days():
	var one: float = VillageWages.estate_tax_for({"bauer": 1}, {"bauer": 1.0}, 1.0)
	assert_almost_eq(VillageWages.estate_tax_for({"bauer": 4}, {"bauer": 1.0}, 1.0), one * 4.0, 0.0001)
	assert_almost_eq(VillageWages.estate_tax_for({"bauer": 1}, {"bauer": 1.0}, 3.0), one * 3.0, 0.0001)


## Anno's exact shape and the real one: a destitute household has no
## surplus to take, so a village that stops supplying its people also stops
## being able to pay for anything.
func test_a_destitute_village_raises_nothing_however_many_live_in_it():
	assert_almost_eq(VillageWages.estate_tax_for({"buerger": 50}, {"buerger": 0.0}, 10.0), 0.0, 0.0001)


func test_a_half_provided_village_raises_half():
	var whole: float = VillageWages.estate_tax_for({"handwerker": 6}, {"handwerker": 1.0}, 2.0)
	var half: float = VillageWages.estate_tax_for({"handwerker": 6}, {"handwerker": 0.5}, 2.0)
	assert_almost_eq(half, whole * 0.5, 0.0001)


## A household whose provision nobody reported is treated as destitute
## rather than as fully provided -- the same destitute default every other
## estate module takes, and the one that cannot invent revenue.
func test_a_household_whose_provision_is_unknown_is_taxed_as_destitute():
	assert_almost_eq(VillageWages.estate_tax_for({"bauer": 9}, {}, 1.0), 0.0, 0.0001)


## The loop's actual claim, stated as an ordering rather than a number: the
## SAME village raises strictly more once its households have risen.
func test_the_same_village_raises_more_once_its_households_have_risen():
	var provision := {"kossaet": 1.0, "buerger": 1.0}
	var before: float = VillageWages.estate_tax_for({"kossaet": 8}, provision, 1.0)
	var after: float = VillageWages.estate_tax_for({"buerger": 8}, provision, 1.0)
	assert_true(after > before, "a risen village pays no more than a cottagers' one")


## And it is the same purse: what the tax raises really does fund wages,
## which is the whole reason it is not a second treasury.
func test_a_days_tax_on_a_real_village_funds_real_subsistence_wages():
	var purse: float = VillageWages.estate_tax_for({"buerger": 10}, {"buerger": 1.0}, 3.0)
	assert_true(
		VillageWages.can_pay_subsistence(purse),
		"three days of ten provided burghers could not pay one villager one meal"
	)
	var paid: Dictionary = VillageWages.pay_subsistence(purse)
	assert_eq(int(paid["paid"]), VillageWages.subsistence_wage())
	assert_almost_eq(float(paid["purse"]), purse - float(VillageWages.subsistence_wage()), 0.0001)


func test_an_unknown_estate_in_the_census_is_untaxable_rather_than_free_money():
	assert_almost_eq(VillageWages.estate_tax_for({"emperor": 99}, {"emperor": 1.0}, 5.0), 0.0, 0.0001)
