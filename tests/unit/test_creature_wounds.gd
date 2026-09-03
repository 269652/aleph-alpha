extends GutTest

## A struck animal bleeds, slows, and leaves a trail (docs/concept/olfaction.md,
## "Blood: the trail a wounded animal leaves"; docs/concept/survival.md's
## open-wound trigger, which is the same model from the player's side).
##
## Before this there were only two states, dead and untouched: FlightDistance
## makes an animal run early and AnimalAnatomy makes a big one fast, so a hit
## that did not kill outright meant the animal was simply gone.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const WoundModel = preload("res://src/gameplay/wound_model.gd")
const BloodTrail = preload("res://src/gameplay/blood_trail.gd")

var marker: CreatureMarker


func before_each():
	marker = CreatureMarker.new()
	marker.info = CreatureInfo.new("deer")
	marker.info.health = 200.0
	marker.info.max_health = 200.0


func after_each():
	marker.free()


func test_an_untouched_animal_carries_no_wound():
	assert_eq(marker.wound_stacks(), 0)


func test_a_real_blow_opens_a_wound():
	marker.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	assert_gt(marker.wound_stacks(), 0)


## Every scratch leaving a bleeding wound would make the mechanic noise rather
## than a threat.
func test_a_scratch_does_not():
	marker.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND * 0.5)
	assert_eq(marker.wound_stacks(), 0)


func test_wounds_stack_up_to_the_cap():
	for hit in WoundModel.MAX_STACKS + 3:
		marker.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	assert_eq(marker.wound_stacks(), WoundModel.MAX_STACKS)


## A wound keeps hurting after the blow that made it -- which is the whole
## difference between a wound and damage.
func test_a_wound_bleeds_after_the_blow():
	marker.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	var after_the_hit := marker.info.health
	marker.step_wounds(5.0)
	assert_lt(marker.info.health, after_the_hit)


func test_an_unwounded_animal_does_not_bleed():
	var before := marker.info.health
	marker.step_wounds(10.0)
	assert_eq(marker.info.health, before)


## ...and it clots on its own if you let it get away, so a wounded animal is a
## thing to follow NOW rather than a permanent mark on the population.
func test_a_wound_clots_if_you_let_it_go():
	marker.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	marker.step_wounds(WoundModel.DURATION_SECONDS + 1.0)
	assert_eq(marker.wound_stacks(), 0)


## The reason tracking is worth doing: the thing at the end of the trail is
## catchable.
func test_a_wounded_animal_is_slower():
	var healthy := marker.wound_speed_multiplier()
	marker.take_damage(WoundModel.MIN_DAMAGE_TO_WOUND)
	assert_lt(marker.wound_speed_multiplier(), healthy)


## Bleeding never finishes the animal off by itself -- it is what lets you
## catch it, not what kills it for you.
func test_bleeding_alone_does_not_kill():
	marker.info.health = 1.0
	for hit in WoundModel.MAX_STACKS:
		marker.take_damage(0.0)
	marker.step_wounds(WoundModel.DURATION_SECONDS)
	assert_gt(marker.info.health, 0.0)
