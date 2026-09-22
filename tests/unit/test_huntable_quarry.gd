extends GutTest

## HuntableQuarry: what a village hunter is allowed to put a spear into
## (docs/concept/npc.md, "Work against the real world, not against a
## number").
##
## The predicate half of the hunt. ForagerBehavior decides WHEN a villager
## commits, walks and strikes; this decides WHAT is legitimate quarry and
## WHICH one is nearest -- the direct analogue of
## LumberjackMarker._nearest_standing_tree's "live, still-standing" filter,
## pulled out into a pure module because an animal has four ways of being
## off-limits where a tree has one.
##
## Every rule here is grounded in something already live rather than
## chosen:
## - not a predator, because NpcProduction keys a hunter's whole yield to
##   herbivore_population_near -- the regional number a hunter already
##   reads counts prey, so prey is what a hunter takes.
## - not a world boss, because BossAggro exists: a villager poking a boss
##   would aggro it into the village.
## - not tamed, because a tamed animal belongs to somebody
##   (docs/concept/taming.md).
## - alive, because a carcass is a Carcass, not quarry.

const HuntableQuarry = preload("res://src/gameplay/huntable_quarry.gd")
const LumberjackMarker = preload("res://src/rendering/lumberjack_marker.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureMass = preload("res://src/world/creature_mass.gd")
const Butchering = preload("res://src/gameplay/butchering.gd")


## Duck-typed stand-in for a real CreatureMarker: the three things
## HuntableQuarry actually reads (info, is_tame, is_queued_for_deletion)
## plus a position, and nothing else. Mirrors the rest of this codebase's
## world-duck-typing convention.
class StubInfo:
	extends RefCounted
	var species := "deer"
	var health := 10.0
	var is_predator := false
	var is_world_boss := false


class StubCreature:
	extends RefCounted
	var position := Vector2.ZERO
	var info = StubInfo.new()
	var tame := false

	func is_tame() -> bool:
		return tame


## A real Node, for the one rule a RefCounted cannot stand in for:
## is_queued_for_deletion() is Object's own method, so a stub can never
## report true for it. A creature that has already been killed this frame
## is still in the "creature" group until the frame boundary (see
## LumberjackMarker._target_still_here's own note on the same hazard).
class DyingCreature:
	extends Node2D
	var info = StubInfo.new()

	func is_tame() -> bool:
		return false


## A marker that answers none of the optional questions -- the fail-open
## case (an older double, a node type that never had taming).
class BareCreature:
	extends RefCounted
	var position := Vector2.ZERO
	var info = StubInfo.new()


## A creature answering the BROADER of the two ownership questions:
## CreatureMarker.is_player_invested ("whose books is this animal on") is
## true for anything the player has fed even once or has on a rope, well
## before Taming.is_tame's trust threshold is reached.
class InvestedCreature:
	extends RefCounted
	var position := Vector2.ZERO
	var info = StubInfo.new()
	var invested := true

	func is_tame() -> bool:
		return false

	func is_player_invested() -> bool:
		return invested


func _quarry_at(at: Vector2) -> StubCreature:
	var c := StubCreature.new()
	c.position = at
	return c


# -- what counts as quarry -------------------------------------------------


func test_a_living_wild_herbivore_is_quarry():
	assert_true(HuntableQuarry.is_quarry(_quarry_at(Vector2.ZERO)))


func test_a_creature_at_zero_health_is_not_quarry():
	var dead := _quarry_at(Vector2.ZERO)
	dead.info.health = 0.0
	assert_false(HuntableQuarry.is_quarry(dead))


func test_a_predator_is_not_quarry():
	# A hunter's yield reads herbivore_population_near; wolves are not in
	# that number, so they are not in this one either.
	var wolf := _quarry_at(Vector2.ZERO)
	wolf.info.is_predator = true
	assert_false(HuntableQuarry.is_quarry(wolf))


func test_a_world_boss_is_not_quarry():
	var boss := _quarry_at(Vector2.ZERO)
	boss.info.is_world_boss = true
	assert_false(HuntableQuarry.is_quarry(boss))


func test_an_animal_the_player_has_a_stake_in_is_not_quarry():
	# A half-tamed horse the player has been feeding, or one on a rope,
	# is not yet is_tame() -- but it is already off the wild books
	# (CreatureMarker.is_player_invested's own framing), and spearing it
	# for the stew would be a bug, not emergence.
	assert_false(HuntableQuarry.is_quarry(InvestedCreature.new()))


func test_an_uninvested_animal_that_answers_the_question_is_still_quarry():
	var wild := InvestedCreature.new()
	wild.invested = false
	assert_true(HuntableQuarry.is_quarry(wild))


func test_a_tamed_animal_is_not_quarry():
	var pet := _quarry_at(Vector2.ZERO)
	pet.tame = true
	assert_false(HuntableQuarry.is_quarry(pet))


func test_a_creature_already_queued_for_deletion_is_not_quarry():
	var gone := DyingCreature.new()
	add_child_autofree(gone)
	gone.queue_free()
	assert_false(HuntableQuarry.is_quarry(gone))


func test_a_live_node_in_the_tree_is_quarry():
	# The other half of the check above: the same node type, not yet freed.
	var alive := DyingCreature.new()
	add_child_autofree(alive)
	assert_true(HuntableQuarry.is_quarry(alive))


func test_null_is_not_quarry():
	assert_false(HuntableQuarry.is_quarry(null))


func test_a_creature_with_no_info_is_not_quarry():
	var blank := _quarry_at(Vector2.ZERO)
	blank.info = null
	assert_false(HuntableQuarry.is_quarry(blank))


func test_a_creature_that_cannot_answer_is_tame_is_still_quarry():
	# Fail-open on the optional questions, same convention as every other
	# duck-typed world read here -- a node without taming is wild.
	assert_true(HuntableQuarry.is_quarry(BareCreature.new()))


# -- picking one out of a crowd --------------------------------------------


func test_nearest_returns_the_closest_quarry():
	var near := _quarry_at(Vector2(10.0, 0.0))
	var far := _quarry_at(Vector2(100.0, 0.0))
	assert_eq(HuntableQuarry.nearest([far, near], Vector2.ZERO, 200.0), near)


func test_nearest_ignores_quarry_beyond_max_distance():
	var far := _quarry_at(Vector2(300.0, 0.0))
	assert_null(HuntableQuarry.nearest([far], Vector2.ZERO, 200.0))


func test_nearest_accepts_quarry_exactly_at_max_distance():
	# Inclusive bound, matching LumberjackMarker._nearest_standing_tree's
	# own `distance <= best_distance`.
	var edge := _quarry_at(Vector2(200.0, 0.0))
	assert_eq(HuntableQuarry.nearest([edge], Vector2.ZERO, 200.0), edge)


func test_nearest_skips_a_closer_non_quarry():
	# A tamed cow standing right next to the hunter does not get speared
	# just because it is convenient.
	var pet := _quarry_at(Vector2(5.0, 0.0))
	pet.tame = true
	var deer := _quarry_at(Vector2(80.0, 0.0))
	assert_eq(HuntableQuarry.nearest([pet, deer], Vector2.ZERO, 200.0), deer)


func test_nearest_returns_null_when_nothing_qualifies():
	var wolf := _quarry_at(Vector2(5.0, 0.0))
	wolf.info.is_predator = true
	assert_null(HuntableQuarry.nearest([wolf], Vector2.ZERO, 200.0))


func test_nearest_of_an_empty_list_is_null():
	assert_null(HuntableQuarry.nearest([], Vector2.ZERO, 200.0))


func test_nearest_tolerates_a_null_in_the_candidate_list():
	var deer := _quarry_at(Vector2(30.0, 0.0))
	assert_eq(HuntableQuarry.nearest([null, deer], Vector2.ZERO, 200.0), deer)


# -- how far a villager ranges ---------------------------------------------


func test_search_radius_matches_the_lumberjacks_own_range():
	# One number for "how far a village worker ranges out from their
	# workspot looking for the thing they work on", the same reasoning
	# ForagerBehavior gives for borrowing the Lumberjack's intervals. Two
	# independently-picked radii for the same behaviour would drift.
	assert_eq(HuntableQuarry.SEARCH_RADIUS_PX, LumberjackMarker.SEARCH_RADIUS_PX)


func test_nearest_defaults_to_the_search_radius():
	var just_outside := _quarry_at(Vector2(HuntableQuarry.SEARCH_RADIUS_PX + 1.0, 0.0))
	var just_inside := _quarry_at(Vector2(HuntableQuarry.SEARCH_RADIUS_PX - 1.0, 0.0))
	assert_null(HuntableQuarry.nearest([just_outside], Vector2.ZERO))
	assert_eq(HuntableQuarry.nearest([just_inside], Vector2.ZERO), just_inside)


# -- what a kill actually gives --------------------------------------------


## Carries the one extra thing a meat yield needs beyond `info`: the
## animal's own real live mass (docs/concept/metabolism.md), the same
## reading CreatureMarker._spawn_carcass_if_eligible uses to set a
## carcass's mass_ratio.
class MassiveCreature:
	extends RefCounted
	var position := Vector2.ZERO
	var info = StubInfo.new()
	var mass_kg := 0.0

	func is_tame() -> bool:
		return false

	func current_mass_kg() -> float:
		return mass_kg


func _deer_of_mass(ratio: float) -> MassiveCreature:
	var deer := MassiveCreature.new()
	deer.info.species = "deer"
	deer.mass_kg = CreatureMass.mass_kg_for("deer") * ratio
	return deer


func test_an_average_animal_yields_exactly_what_its_carcass_would():
	# Not a second opinion about how much meat is on a deer: the SAME
	# Butchering.meat_count a player butchering that very carcass gets.
	assert_eq(HuntableQuarry.meat_yield_of(_deer_of_mass(1.0)), Butchering.meat_count(0.0, 1.0))


func test_a_well_fed_animal_yields_more_meat_than_a_starved_one():
	var fat := HuntableQuarry.meat_yield_of(_deer_of_mass(1.6))
	var thin := HuntableQuarry.meat_yield_of(_deer_of_mass(0.4))
	assert_gt(fat, thin)


func test_a_hunter_gets_no_skill_bonus_on_the_cut():
	# A villager is not a trained butcher -- SkillTree's meat_yield nodes
	# are the player's to earn (docs/concept/carrion.md), so the villager's
	# cut is the unbonused one.
	var deer := _deer_of_mass(1.3)
	assert_eq(HuntableQuarry.meat_yield_of(deer), Butchering.meat_count(0.0, 1.3))


func test_an_animal_that_cannot_report_its_mass_yields_the_flat_count():
	# Fail-open, same convention as is_tame above.
	var plain := _quarry_at(Vector2.ZERO)
	plain.info.species = "deer"
	assert_eq(HuntableQuarry.meat_yield_of(plain), Butchering.meat_count(0.0, 1.0))


func test_nothing_yields_no_meat():
	assert_eq(HuntableQuarry.meat_yield_of(null), 0)


func test_a_creature_with_no_species_record_yields_no_meat():
	var blank := _quarry_at(Vector2.ZERO)
	blank.info = null
	assert_eq(HuntableQuarry.meat_yield_of(blank), 0)


# -- the blow, and where to look -------------------------------------------


func test_strike_damage_matches_a_predators_own_bite():
	# A villager with a spear bringing down a deer is doing exactly what a
	# wolf does to the same deer, so it lands the same blow -- the same
	# reasoning LumberjackMarker.FELL_DAMAGE gives for matching
	# Player.BASE_CHOP_DAMAGE ("an axe swing is an axe swing regardless of
	# who swings it").
	assert_eq(HuntableQuarry.STRIKE_DAMAGE, CreatureMarker.ATTACK_DAMAGE)


func test_quarry_is_looked_for_in_the_creature_group():
	assert_eq(HuntableQuarry.QUARRY_GROUP_NAME, CreatureMarker.GROUP_NAME)


func test_strike_distance_matches_the_lumberjacks_own_arrival_distance():
	# "Close enough to work on it" is one rule, not two: the Lumberjack's
	# own arrival tolerance, for the same reason the search radius is
	# shared. Small relative to a tile (TILE_SIZE 16), since move_toward
	# closes asymptotically and an exact-equality arrival would never fire.
	assert_eq(HuntableQuarry.STRIKE_DISTANCE_PX, LumberjackMarker.ARRIVE_DISTANCE_PX)


# -- the other half of the animal -------------------------------------------


func test_a_kill_yields_the_same_one_hide_butchering_that_carcass_would():
	assert_eq(HuntableQuarry.hide_yield_of(_deer_of_mass(1.0)), Butchering.HIDE_COUNT)


func test_hide_does_not_scale_with_the_animals_condition():
	# Butchering's own shape: meat_count takes the mass ratio, HIDE_COUNT
	# is flat. A starved deer is a thinner deer, not a smaller one.
	assert_eq(
		HuntableQuarry.hide_yield_of(_deer_of_mass(0.4)),
		HuntableQuarry.hide_yield_of(_deer_of_mass(1.6))
	)


func test_nothing_yields_no_hide():
	assert_eq(HuntableQuarry.hide_yield_of(null), 0)


func test_a_creature_with_no_species_record_yields_no_hide():
	var blank := _quarry_at(Vector2.ZERO)
	blank.info = null
	assert_eq(HuntableQuarry.hide_yield_of(blank), 0)


func test_the_hide_is_butcherings_own_first_part():
	# Not a second opinion about what comes off a carcass first -- the
	# same id, so a rename can never leave the two disagreeing.
	assert_eq(HuntableQuarry.HIDE_ITEM_ID, Butchering.PART_ORDER[0])


## A hunter carries home what the animal really was, not a flat two
## steaks: the same species-derived cut a player butchering that very
## carcass gets (docs/concept/carrion.md).
func test_a_heavier_species_carries_more_meat_home():
	assert_gt(
		HuntableQuarry.meat_yield_of(_creature_of_species("bear")),
		HuntableQuarry.meat_yield_of(_creature_of_species("squirrel"))
	)


func test_the_hunters_cut_is_the_butchers_own_species_cut():
	var deer := _deer_of_mass(1.0)
	assert_eq(HuntableQuarry.meat_yield_of(deer), Butchering.meat_count(0.0, 1.0, "deer"))


func _creature_of_species(species: String) -> MassiveCreature:
	var animal := MassiveCreature.new()
	animal.info.species = species
	animal.mass_kg = CreatureMass.mass_kg_for(species)
	return animal
