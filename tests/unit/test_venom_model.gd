extends GutTest

## Pure damage-over-time model for a venomous snake's bite (see
## docs/concept/ecosystem_dynamics.md's Species roster -- venomous_snake).
## Stacking state itself is tracked by the existing generic DebuffStack
## (apply/advance/stacks_of) -- this module only adds the "how much does N
## stacks hurt per second" rule DebuffStack is deliberately agnostic about.

const VenomModel = preload("res://src/gameplay/venom_model.gd")

var venom: VenomModel


func before_each():
	venom = VenomModel.new()


func test_zero_stacks_deals_no_damage():
	assert_eq(venom.damage_per_second(0), 0.0)


func test_damage_increases_with_stacks():
	var one := venom.damage_per_second(1)
	var two := venom.damage_per_second(2)
	assert_gt(two, one)


func test_damage_is_capped_at_max_stacks():
	var at_cap := venom.damage_per_second(VenomModel.MAX_STACKS)
	var beyond_cap := venom.damage_per_second(VenomModel.MAX_STACKS + 5)
	assert_eq(beyond_cap, at_cap)


func test_negative_stacks_deal_no_damage():
	assert_eq(venom.damage_per_second(-3), 0.0)
