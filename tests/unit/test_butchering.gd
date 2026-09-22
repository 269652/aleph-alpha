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


# -- species: a bear is more meat than a squirrel is, because it IS more --
# -- meat (docs/concept/carrion.md, "species-specific butcher yields") ----

const CreatureMass = preload("res://src/world/creature_mass.gd")


## The gap carrion.md carried as ⬜ from the day it was written: *"every
## carcass-eligible species shares one part order/quantity"*. A bear and a
## squirrel cut into exactly the same two steaks, which is the same
## flat-by-role shape LootTable had before it was derived from real mass.
func test_a_bear_cuts_into_more_meat_than_a_squirrel():
	assert_gt(
		Butchering.meat_count(0.0, 1.0, "bear"), Butchering.meat_count(0.0, 1.0, "squirrel")
	)


## The one animal this game had already costed keeps exactly what it had,
## so deriving the rest does not quietly rebalance it.
func test_the_reference_species_still_cuts_into_the_flat_count():
	assert_eq(
		Butchering.meat_count(0.0, 1.0, Butchering.REFERENCE_SPECIES), Butchering.BASE_MEAT_COUNT
	)


## And the mass that calibration rests on is the animal's own real one,
## read from the same table every other real-world size in this codebase
## reads, rather than a second opinion typed in here.
func test_the_reference_mass_is_that_animals_own_real_mass():
	assert_almost_eq(
		Butchering.REFERENCE_MASS_KG,
		CreatureMass.mass_kg_for(Butchering.REFERENCE_SPECIES),
		0.0001
	)


## Every caller that predates this parameter gets exactly what it always
## got.
func test_omitting_the_species_keeps_the_flat_count():
	assert_eq(Butchering.meat_count(1.0, 1.0), Butchering.meat_count(1.0, 1.0, ""))


## Fail-open on an animal the world has no mass for, the same convention
## mass_ratio already uses -- never a zero-meal kill from a typo.
func test_a_species_the_world_has_no_mass_for_keeps_the_flat_count():
	assert_eq(Butchering.meat_count(0.0, 1.0, "not_an_animal"), Butchering.BASE_MEAT_COUNT)


## Monotone across the real roster: no heavier animal is worth fewer meals
## than a lighter one. The property, swept, rather than four spot checks.
func test_the_cut_never_shrinks_as_the_animal_grows():
	var by_weight := [
		"mouse",
		"squirrel",
		"arctic_fox",
		"jackal",
		"lynx",
		"wolf",
		"goat",
		"deer",
		"boar",
		"reindeer",
		"lion",
		"bear",
		"horse",
	]
	for i in range(1, by_weight.size()):
		assert_gte(
			Butchering.base_meat_for(by_weight[i]),
			Butchering.base_meat_for(by_weight[i - 1]),
			"%s must not cut into less meat than %s" % [by_weight[i], by_weight[i - 1]]
		)


## The smallest thing a hunter can kill is still worth carrying home. A
## kill that yields nothing at all is the exact thing this derivation
## exists to prevent.
func test_even_the_smallest_animal_is_worth_one_meal():
	assert_eq(Butchering.base_meat_for("mouse"), 1)


## The skill bonus is still whole items on top of the cut, not a fraction
## of it -- a trained butcher gets the same extra steak off a bear as off
## a boar.
func test_the_skill_bonus_still_adds_whole_items_to_a_species_cut():
	assert_eq(Butchering.meat_count(1.0, 1.0, "bear"), Butchering.base_meat_for("bear") + 1)


## And mass_ratio still scales the species count, rather than the two
## rules quietly replacing one another.
func test_a_heavier_than_average_bear_still_cuts_into_more_than_an_average_one():
	assert_gt(Butchering.meat_count(0.0, 1.5, "bear"), Butchering.meat_count(0.0, 1.0, "bear"))
