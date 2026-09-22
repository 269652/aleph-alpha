extends GutTest

## The `slow` spell atom, on the things you cast it at.
##
## Measured: `grep -c SLOW src/rendering/creature_marker.gd` returned **0**.
## `SpellStatusEffects.SLOW` and `SLOW_SPEED_MULTIPLIER` exist, `Player`
## reads them at `_status_speed_multiplier`, and `SpellAtomEffects` really
## applies the debuff to a creature -- the marker carried the stacks
## faithfully in `active_spell_debuffs` and its movement never looked at
## them. So Frost Lance, whose own source is
## `frost_damage(magnitude: 6) |> slow(duration: 3)`, slowed nothing in the
## world; half of a two-atom spell was decoration.
##
## `freeze` and `root` worked, because `is_rooted()` reads them and stops
## the creature outright. `slow` is the only one that needed a speed, and a
## speed was the one thing nothing multiplied.

const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const CreatureInfo = preload("res://src/world/creature_info.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")
const DiseaseModel = preload("res://src/gameplay/disease_model.gd")

var marker


func before_each():
	marker = CreatureMarker.new()
	marker.home = Vector2(100, 100)
	marker.position = Vector2(100, 100)
	marker.wander_seed = 5
	marker.info = CreatureInfo.new("wolf")
	add_child(marker)


func after_each():
	marker.queue_free()


func _travelled(seconds: float) -> float:
	var start: Vector2 = marker.position
	var elapsed := 0.0
	while elapsed < seconds:
		marker._advance(Vector2.RIGHT, 40.0, 1.0 / 60.0)
		elapsed += 1.0 / 60.0
	return start.distance_to(marker.position)


# -- it really slows ------------------------------------------------------

func test_a_slowed_creature_really_moves_slower():
	var full := _travelled(0.5)
	marker.position = Vector2(100, 100)
	marker.apply_spell_debuff(SpellStatusEffects.SLOW, 10.0)
	var slowed := _travelled(0.5)
	assert_gt(full, 0.0, "precondition: it moves at all")
	assert_lt(slowed, full, "a spell that slows nothing is half a spell")


## By the shared rule's own figure, not a second opinion invented in the
## marker -- the same multiplier the player wears when slowed.
func test_it_is_slowed_by_the_shared_rule():
	var full := _travelled(0.5)
	marker.position = Vector2(100, 100)
	marker.apply_spell_debuff(SpellStatusEffects.SLOW, 10.0)
	var slowed := _travelled(0.5)
	assert_almost_eq(
		slowed / full, SpellStatusEffects.SLOW_SPEED_MULTIPLIER, 0.02,
		"the creature and the player must be slowed by one number"
	)


## And it wears off, because a debuff that never ended would be a kill.
func test_the_slow_wears_off():
	marker.apply_spell_debuff(SpellStatusEffects.SLOW, 0.2)
	marker._spell_status_step(1.0)
	marker.position = Vector2(100, 100)
	var after := _travelled(0.5)
	marker.position = Vector2(100, 100)
	var full := _travelled(0.5)
	assert_almost_eq(after, full, 0.001)


## Composing with the disease slowdown that already uses this choke point
## rather than replacing it: a sick, slowed wolf is slower than a sick one.
func test_it_composes_with_the_sickness_that_already_slowed_creatures():
	marker.apply_disease_bite(DiseaseModel.HERD)
	marker._disease_step(0.1)
	marker.disease_severity = 1.0
	marker.position = Vector2(100, 100)
	var sick := _travelled(0.5)
	marker.apply_spell_debuff(SpellStatusEffects.SLOW, 10.0)
	marker.position = Vector2(100, 100)
	var sick_and_slowed := _travelled(0.5)
	assert_lt(sick_and_slowed, sick, "two slowdowns are slower than one")
