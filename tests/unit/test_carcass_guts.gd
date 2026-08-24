extends GutTest

## Offal spilled from a butchered carcass -- see docs/concept/carrion.md. A
## real world entity, deliberately NOT an inventory item: a player doesn't
## carry or eat guts, but a scavenger/decomposer does. Always immediately
## edible (unlike Carcass, which has to rot first) -- exposed viscera don't
## need time to become accessible.

const CarcassGuts = preload("res://src/rendering/carcass_guts.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

var guts: CarcassGuts


func before_each():
	guts = CarcassGuts.new()
	add_child_autofree(guts)


func test_joins_the_carcass_guts_and_hoverable_groups():
	assert_true(guts.is_in_group(CarcassGuts.GROUP_NAME))
	assert_true(guts.is_in_group(HoverTargetFinder.GROUP_NAME))


func test_take_bite_always_succeeds():
	assert_true(guts.take_bite(1.0))


func test_enough_bites_fully_removes_it():
	assert_false(guts.is_queued_for_deletion())
	guts.take_bite(CarcassGuts.CONSUME_HEALTH + 1.0)
	assert_true(guts.is_queued_for_deletion())


func test_decays_on_its_own_after_rot_seconds_even_if_nothing_eats_it():
	guts._process(CarcassGuts.ROT_SECONDS + 1.0)
	assert_true(guts.is_queued_for_deletion())


func test_does_not_decay_before_rot_seconds():
	guts._process(CarcassGuts.ROT_SECONDS * 0.5)
	assert_false(guts.is_queued_for_deletion())


func test_get_display_name_is_guts():
	assert_eq(guts.get_display_name(), "Guts")


func test_offers_no_player_hover_actions():
	assert_eq(guts.get_hover_actions().size(), 0)
