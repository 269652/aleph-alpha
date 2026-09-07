extends GutTest

## Pure part-order/yield logic for butchering a carcass (see
## docs/concept/carrion.md). No engine dependencies, like every other tuned
## logic module in this codebase.

const Butchering = preload("res://src/gameplay/butchering.gd")


func test_hits_required_matches_the_number_of_parts():
	assert_eq(Butchering.hits_required(), Butchering.PART_ORDER.size())


func test_part_order_is_hide_then_meat_then_guts():
	assert_eq(Butchering.PART_ORDER, ["hide", "meat", "guts"])


func test_part_for_hit_walks_the_order():
	assert_eq(Butchering.part_for_hit(0), "hide")
	assert_eq(Butchering.part_for_hit(1), "meat")
	assert_eq(Butchering.part_for_hit(2), "guts")


func test_part_for_hit_is_empty_past_the_last_part():
	assert_eq(Butchering.part_for_hit(3), "")


func test_part_for_hit_is_empty_for_a_negative_index():
	assert_eq(Butchering.part_for_hit(-1), "")


func test_meat_count_with_no_skill_bonus_is_the_base_amount():
	assert_eq(Butchering.meat_count(0.0), Butchering.BASE_MEAT_COUNT)


func test_meat_count_grows_with_the_skill_bonus():
	assert_gt(Butchering.meat_count(3.0), Butchering.meat_count(0.0))


func test_meat_count_rounds_the_bonus_to_a_whole_item_count():
	assert_eq(Butchering.meat_count(1.0), Butchering.BASE_MEAT_COUNT + 1)


# -- mass_ratio: a real, heavier-or-lighter-than-average kill yields more --
# -- or less meat (see docs/concept/metabolism.md) --------------------------

## Omitting mass_ratio entirely (every caller that predates this
## parameter) must behave exactly as before.
func test_omitting_mass_ratio_keeps_the_old_behavior():
	assert_eq(Butchering.meat_count(1.0), Butchering.meat_count(1.0, 1.0))


## The real, new consequence of a unified live mass: a creature killed
## while genuinely heavier than its own species' reference mass yields
## MORE meat than the flat, mass-blind count.
func test_a_heavier_than_average_kill_yields_more_meat():
	assert_gt(Butchering.meat_count(0.0, 1.5), Butchering.meat_count(0.0, 1.0))


## The mirror case: a starved kill, genuinely lighter than reference,
## yields LESS meat.
func test_a_lighter_than_average_kill_yields_less_meat():
	assert_lt(Butchering.meat_count(0.0, 0.5), Butchering.meat_count(0.0, 1.0))


## Defensive: a hypothetically negative ratio (should never actually reach
## here -- Metabolism's own starvation floor keeps a real ratio well above
## zero) never produces a negative meat count.
func test_mass_ratio_never_produces_a_negative_meat_count():
	assert_gte(Butchering.meat_count(0.0, -5.0), 0)
