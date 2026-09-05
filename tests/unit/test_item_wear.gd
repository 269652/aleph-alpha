extends GutTest

## Pure logic for accumulated combat wear and fatigue failure -- see
## docs/concept/item_durability.md. Complements, not duplicates,
## ImpactResolver's existing shatter mechanic: shatter is a single-hit
## brittle fracture (toughness < MaterialProperties.BRITTLE_TOUGHNESS) at
## high momentum; this is the OTHER failure mode materials.md's "Physical
## honesty over time" section names -- a tough-enough material doesn't
## shatter, it wears down gradually and fails from accumulated fatigue
## instead.

const ItemWear = preload("res://src/gameplay/item_wear.gd")

var wear: ItemWear


func before_each():
	wear = ItemWear.new()


# -- max_wear: scales with toughness, the "energy absorbed before failure" --
# property materials.md already defines toughness as. ------------------------

func test_max_wear_is_toughness_times_uses_per_toughness_point():
	assert_almost_eq(wear.max_wear("iron"), 7.0 * ItemWear.USES_PER_TOUGHNESS_POINT, 0.0001)


func test_iron_survives_more_uses_than_wood_which_survives_more_than_stone():
	# Toughness (materials.md's fracture-resistance column, not hardness):
	# iron 7.0 > wood 6.0 > stone 5.0. Stone is far HARDER than either, but
	# hardness and toughness are different axes -- the entire point of the
	# two-column model -- so a knapped stone blade breaking soonest is the
	# right answer even though it's also the hardest material of the three.
	assert_gt(wear.max_wear("iron"), wear.max_wear("wood"))
	assert_gt(wear.max_wear("wood"), wear.max_wear("stone"))


func test_an_unmodeled_material_never_wears_out():
	assert_eq(wear.max_wear("unobtainium"), INF)


func test_an_empty_material_string_never_wears_out():
	# What ItemCatalog.material_of returns for any item with no material
	# modeled yet (item_catalog.gd's own "not guessed at here" convention) --
	# the same items that already report mass_kg 0.0 for the same reason.
	assert_eq(wear.max_wear(""), INF)


# -- is_broken -----------------------------------------------------------

func test_is_not_broken_below_max_wear():
	assert_false(wear.is_broken(wear.max_wear("iron") - 1.0, "iron"))


func test_is_broken_at_max_wear():
	assert_true(wear.is_broken(wear.max_wear("iron"), "iron"))


func test_is_broken_past_max_wear():
	assert_true(wear.is_broken(wear.max_wear("iron") + 1.0, "iron"))


func test_zero_wear_is_never_broken():
	assert_false(wear.is_broken(0.0, "stone"))


func test_an_unmodeled_material_is_never_broken_no_matter_how_much_wear():
	assert_false(wear.is_broken(1000000.0, "unobtainium"))


# -- condition_for: the 3-state read the composite sheet spec draws ----------

func test_condition_is_pristine_at_zero_wear():
	assert_eq(wear.condition_for(0.0, "iron"), "pristine")


func test_condition_is_pristine_just_below_the_worn_threshold():
	var cap := wear.max_wear("iron")
	assert_eq(wear.condition_for(cap * ItemWear.WORN_THRESHOLD_FRACTION - 0.01, "iron"), "pristine")


func test_condition_is_worn_at_the_worn_threshold():
	var cap := wear.max_wear("iron")
	assert_eq(wear.condition_for(cap * ItemWear.WORN_THRESHOLD_FRACTION, "iron"), "worn")


func test_condition_is_worn_just_below_the_break_point():
	var cap := wear.max_wear("iron")
	assert_eq(wear.condition_for(cap - 0.01, "iron"), "worn")


func test_condition_is_broken_at_max_wear():
	assert_eq(wear.condition_for(wear.max_wear("iron"), "iron"), "broken")


func test_condition_is_pristine_for_an_unmodeled_material_no_matter_the_wear():
	assert_eq(wear.condition_for(999.0, "unobtainium"), "pristine")


# -- the three in-scope starting weapons, named explicitly -------------------
# (wooden_club/wood, iron_sword/iron, crude_blade/stone -- ItemCatalog's own
# _WEAPON_MATERIAL_AND_VOLUME, the only items with a real material today, see
# docs/concept/item_durability.md's scope section)

func test_wooden_club_survives_a_real_number_of_uses():
	assert_almost_eq(wear.max_wear("wood"), 48.0, 0.0001)


func test_iron_sword_survives_a_real_number_of_uses():
	assert_almost_eq(wear.max_wear("iron"), 56.0, 0.0001)


func test_crude_blade_survives_the_fewest_uses_of_the_three():
	assert_almost_eq(wear.max_wear("stone"), 40.0, 0.0001)
	assert_lt(wear.max_wear("stone"), wear.max_wear("wood"))
	assert_lt(wear.max_wear("stone"), wear.max_wear("iron"))
