extends GutTest

## A killed animal's remains -- see docs/concept/carrion.md. Replaces the old
## "die and instantly drop loot" model: a carcass sits in the world with real
## parts (hide/meat/guts) a player butchers by hand, and rots on its own
## clock so decomposers (ants/bugs) can eventually finish it whether or not
## the player ever touches it.

const Carcass = preload("res://src/rendering/carcass.gd")
const Butchering = preload("res://src/gameplay/butchering.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")
const CarcassGuts = preload("res://src/rendering/carcass_guts.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

var carcass: Carcass
var _drops: Array = []


func before_each():
	carcass = Carcass.new()
	carcass.species = "boar"
	add_child_autofree(carcass)
	_drops = []
	WorldItemBus.item_dropped.connect(_record_drop)


func after_each():
	if WorldItemBus.item_dropped.is_connected(_record_drop):
		WorldItemBus.item_dropped.disconnect(_record_drop)
	# butcher()'s "guts" cut adds a CarcassGuts as a sibling (a child of
	# carcass's own parent -- the test root here), which add_child_autofree
	# only ever frees for `carcass` itself.
	for node in get_tree().get_nodes_in_group(CarcassGuts.GROUP_NAME):
		node.free()


func _record_drop(stack, _position) -> void:
	_drops.append(stack)


func test_joins_the_carcass_and_hoverable_groups():
	assert_true(carcass.is_in_group(Carcass.GROUP_NAME))
	assert_true(carcass.is_in_group(HoverTargetFinder.GROUP_NAME))


# -- butchering: real parts, in order, dropped as real items ----------------

func test_a_fresh_carcass_has_every_part_remaining():
	assert_true(carcass.has_parts_remaining())
	assert_eq(carcass.next_part(), "hide")


func test_first_butcher_yields_hide():
	var taken := carcass.butcher()
	assert_eq(taken, "hide")
	assert_eq(_drops.size(), 1)
	assert_eq(_drops[0].item.id, "hide")
	assert_eq(_drops[0].count, Butchering.HIDE_COUNT)


func test_second_butcher_yields_meat():
	carcass.butcher()
	var taken := carcass.butcher()
	assert_eq(taken, "meat")
	assert_eq(_drops[1].item.id, "meat")
	assert_eq(_drops[1].count, Butchering.meat_count(0.0))


func test_meat_yield_reads_the_skill_bonus_passed_in():
	carcass.butcher()  # hide
	carcass.butcher(3.0)  # meat, with a skill bonus
	assert_eq(_drops[1].count, Butchering.meat_count(3.0))


func test_third_butcher_yields_guts_as_a_world_entity_not_a_dropped_item():
	carcass.butcher()  # hide
	carcass.butcher()  # meat
	var before_drops := _drops.size()
	var before_guts := get_tree().get_nodes_in_group(CarcassGuts.GROUP_NAME).size()
	var taken := carcass.butcher()
	assert_eq(taken, "guts")
	assert_eq(_drops.size(), before_drops, "guts must not go through the item-drop bus")
	assert_eq(
		get_tree().get_nodes_in_group(CarcassGuts.GROUP_NAME).size(), before_guts + 1,
		"a CarcassGuts entity should have been spawned into the world"
	)


func test_a_fully_butchered_carcass_has_no_parts_left():
	carcass.butcher()
	carcass.butcher()
	carcass.butcher()
	assert_false(carcass.has_parts_remaining())
	assert_eq(carcass.next_part(), "")


func test_butchering_a_fully_stripped_carcass_does_nothing():
	carcass.butcher()
	carcass.butcher()
	carcass.butcher()
	var before := _drops.size()
	var taken := carcass.butcher()
	assert_eq(taken, "")
	assert_eq(_drops.size(), before)


# -- rot: independent of butchering -------------------------------------

func test_a_fresh_carcass_is_not_rotten():
	assert_false(carcass.is_rotten())


func test_a_carcass_becomes_rotten_after_rot_seconds():
	carcass._process(Carcass.ROT_SECONDS + 1.0)
	assert_true(carcass.is_rotten())


func test_take_bite_does_nothing_on_a_fresh_carcass():
	assert_false(carcass.take_bite(1000.0))
	assert_false(carcass.is_queued_for_deletion())


func test_take_bite_on_a_rotten_carcass_reduces_its_decompose_health():
	carcass._process(Carcass.ROT_SECONDS + 1.0)
	assert_true(carcass.take_bite(1.0))
	assert_false(carcass.is_queued_for_deletion())


func test_enough_bites_fully_removes_a_rotten_carcass():
	carcass._process(Carcass.ROT_SECONDS + 1.0)
	carcass.take_bite(Carcass.DECOMPOSE_HEALTH + 1.0)
	assert_true(carcass.is_queued_for_deletion())


# -- hover tooltip ------------------------------------------------------

func test_display_name_before_butchering():
	assert_eq(carcass.get_display_name(), "Boar Carcass")


func test_display_name_once_fully_butchered():
	carcass.butcher()
	carcass.butcher()
	carcass.butcher()
	assert_eq(carcass.get_display_name(), "Boar Remains")


func test_hover_actions_offer_butcher_while_parts_remain():
	var actions := carcass.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["verb"], "Butcher")
	assert_eq(actions[0]["action"], "attack")


func test_hover_actions_are_empty_once_fully_butchered():
	carcass.butcher()
	carcass.butcher()
	carcass.butcher()
	assert_eq(carcass.get_hover_actions().size(), 0)


# -- disease: anthrax-like contamination (see docs/concept/disease.md) --------

func test_a_fresh_carcass_is_not_contaminated():
	assert_false(carcass.contaminated)


func test_carcass_defaults_to_easy_region_tier():
	assert_eq(carcass.region_tier, RegionDifficulty.Tier.EASY)


## HARD region pressure (2.4x) on top of DiseaseModel's carcass contamination
## base rate clamps the roll to certain -- deterministic regardless of
## position/species-derived seed, the same "push the chance past 1.0" trick
## test_disease_model.gd's own tests use.
func test_a_carcass_becomes_contaminated_when_it_rots_in_a_hard_region():
	carcass.region_tier = RegionDifficulty.Tier.HARD
	assert_false(carcass.contaminated, "should not roll contamination before it's even rotten")
	carcass._process(Carcass.ROT_SECONDS + 1.0)
	assert_true(carcass.contaminated)


func test_contamination_is_only_rolled_once_per_carcass():
	carcass.region_tier = RegionDifficulty.Tier.HARD
	carcass._process(Carcass.ROT_SECONDS + 1.0)
	assert_true(carcass.contaminated)
	carcass.contaminated = false  # simulate it having been "cleared" somehow
	carcass._process(1.0)  # still rotten, but the one-time roll already happened
	assert_false(carcass.contaminated, "contamination should only be rolled once, at the rot transition")
