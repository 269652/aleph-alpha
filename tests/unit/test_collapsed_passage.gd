extends GutTest

## CollapsedPassage (see docs/concept/exploration.md's "Puzzle content stays
## emergent, not hand-authored" -- the first named obstacle type: "a
## collapsed passage that only enough momentum (a heavy enough thrown/pushed
## object) can clear"). Pure decision logic: given a real material and a
## delivered momentum, this pins that the obstacle routes the decision
## through the SAME ImpactResolver.resolve_impact call every other hittable
## thing in this world already uses -- no bespoke "puzzle HP" stat, no
## second threshold system. Reads the real ImpactResolver constants
## (T_CRUSH) rather than inventing new numbers.

const CollapsedPassage = preload("res://src/rendering/collapsed_passage.gd")
const ImpactResolver = preload("res://src/gameplay/impact_resolver.gd")

var obstacle: CollapsedPassage


func before_each():
	obstacle = CollapsedPassage.new()
	add_child_autofree(obstacle)


func test_is_in_the_collapsed_passage_group():
	assert_true(obstacle.is_in_group(CollapsedPassage.GROUP_NAME))


## Rubble is fallen rock -- MaterialProperties' "stone" entry, not a bespoke
## new material invented for this one obstacle.
func test_defaults_to_stone_material():
	assert_eq(obstacle.rubble_material, "stone")


## Below ImpactResolver's own T_CRUSH for a blunt hit, stone only dents --
## not a clearing outcome -- so the passage should stay blocked.
func test_momentum_below_crush_threshold_does_not_clear():
	assert_false(obstacle.resolves_clear(ImpactResolver.T_CRUSH - 0.1))


## At/above T_CRUSH, a blunt hit on stone (toughness 5.0, above
## T_BRITTLE_TOUGHNESS) crushes -- a clearing outcome.
func test_momentum_at_crush_threshold_clears():
	assert_true(obstacle.resolves_clear(ImpactResolver.T_CRUSH))


func test_receiving_a_sub_threshold_impact_leaves_the_obstacle_in_place():
	obstacle.receive_impact(ImpactResolver.T_CRUSH - 0.1)
	assert_false(obstacle.is_cleared())
	assert_false(obstacle.is_queued_for_deletion())


func test_receiving_a_clearing_impact_clears_the_obstacle():
	obstacle.receive_impact(ImpactResolver.T_CRUSH)
	assert_true(obstacle.is_cleared())
	assert_true(obstacle.is_queued_for_deletion())


## A brittle material (obsidian, toughness 1.0, below T_BRITTLE_TOUGHNESS)
## shatters rather than crushes under the same blunt hit -- a different
## ImpactResolver outcome, but still one of the two CLEARING_OUTCOMES, so
## the passage still opens. Pins that `material` is a real, live parameter
## (not "always stone" hardcoded into the obstacle).
func test_a_brittle_material_shatters_instead_of_crushing_and_still_clears():
	obstacle.rubble_material = "obsidian"
	assert_true(obstacle.resolves_clear(ImpactResolver.T_CRUSH))


# -- hover tooltip: name + available actions ---------------------------------

func test_display_name():
	assert_eq(obstacle.get_display_name(), "Collapsed Passage")


func test_hover_action_is_clear_bound_to_attack():
	var actions: Array = obstacle.get_hover_actions()
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["verb"], "Clear")
	assert_eq(actions[0]["action"], "attack")
