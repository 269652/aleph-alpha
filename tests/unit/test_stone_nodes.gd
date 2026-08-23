extends GutTest

## Taking a stone off the ground (see docs/concept/stone.md).
##
## The pillar again, at the node level: a liftable stone is swept up by the
## ordinary pickup action, and a boulder takes repeated strikes.

const StoneSize = preload("res://src/world/stone_size.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const PebbleDispersion = preload("res://src/rendering/pebble_dispersion.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

var _drops: Array = []


func before_each():
	_drops = []
	WorldItemBus.item_dropped.connect(_record_drop)


func after_each():
	if WorldItemBus.item_dropped.is_connected(_record_drop):
		WorldItemBus.item_dropped.disconnect(_record_drop)


func _record_drop(stack, _position) -> void:
	_drops.append(stack)


func _rock_count() -> int:
	var total := 0
	for stack in _drops:
		if stack.item.id == "rock":
			total += stack.count
	return total


# -- boulders take real work -------------------------------------------------

## A boulder used to break in ONE hit and yield exactly one rock, no matter
## that it was drawn as a rock the size of a person.
func test_a_boulder_does_not_break_on_the_first_hit():
	var stone := SmashableStone.new()
	stone.stone_seed = 1
	stone.diameter_cm = 150.0
	add_child_autofree(stone)
	stone.smash(false)
	assert_false(stone.is_queued_for_deletion(), "a big boulder broke in one hit")
	assert_eq(_rock_count(), 0, "a boulder should not yield until it breaks")


func test_a_boulder_breaks_once_it_has_taken_its_hits():
	var stone := SmashableStone.new()
	stone.stone_seed = 1
	stone.diameter_cm = 150.0
	add_child_autofree(stone)
	for _i in StoneSize.hits_to_smash(150.0):
		stone.smash(false)
	assert_true(stone.is_queued_for_deletion(), "the boulder should have broken by now")
	assert_gt(_rock_count(), 0, "breaking a boulder should yield rock")


## Striking a broken boulder again must not yield a second haul.
func test_a_broken_boulder_cannot_be_smashed_again():
	var stone := SmashableStone.new()
	stone.stone_seed = 1
	stone.diameter_cm = 30.0
	add_child_autofree(stone)
	for _i in StoneSize.hits_to_smash(30.0) + 4:
		stone.smash(false)
	assert_eq(
		_rock_count(), StoneSize.rock_yield(30.0),
		"a broken boulder yielded more than once"
	)


func test_a_bigger_boulder_yields_more_rock():
	var small := SmashableStone.new()
	small.stone_seed = 1
	small.diameter_cm = 30.0
	add_child_autofree(small)
	for _i in StoneSize.hits_to_smash(30.0):
		small.smash(false)
	var small_yield := _rock_count()

	_drops = []
	var large := SmashableStone.new()
	large.stone_seed = 2
	large.diameter_cm = 190.0
	add_child_autofree(large)
	for _i in StoneSize.hits_to_smash(190.0):
		large.smash(false)
	assert_gt(_rock_count(), small_yield, "the big boulder should be the better haul")


## Knapping is unchanged: striking a boulder while carrying a rock can still
## split off shards. They come from the striking, so a picked-up pebble never
## produces them.
func test_knapping_still_works_on_a_boulder():
	var stone := SmashableStone.new()
	stone.stone_seed = 7
	stone.diameter_cm = 40.0
	add_child_autofree(stone)
	for _i in StoneSize.hits_to_smash(40.0):
		stone.smash(true)
	var ids := {}
	for stack in _drops:
		ids[stack.item.id] = true
	assert_true(ids.has("rock"), "smashing should still yield rock")


# -- liftable stone goes straight in your hands ------------------------------

## A pebble is collected by the ordinary pickup sweep -- it joins the same
## group DroppedItem uses, so Player.pickup_nearby finds it with no special
## case of its own.
func test_a_pebble_answers_to_the_ordinary_pickup_sweep():
	var pebble := LiftableStone.new()
	add_child_autofree(pebble)
	assert_true(pebble.is_in_group(DroppedItem.GROUP_NAME))
	assert_true(pebble.has_method("pick_up"))


func test_picking_up_a_pebble_puts_rock_in_the_inventory():
	var pebble := LiftableStone.new()
	pebble.diameter_cm = 4.0
	add_child_autofree(pebble)
	var picker := _Picker.new()
	assert_true(pebble.pick_up(picker))
	assert_eq(picker.inventory.count_of("rock"), StoneSize.rock_yield(4.0))
	assert_true(pebble.is_queued_for_deletion(), "a picked-up pebble should be gone")


## A cobble is more rock than a pebble, because it is more rock.
func test_a_cobble_is_worth_more_than_a_pebble():
	var pebble := LiftableStone.new()
	pebble.diameter_cm = 3.0
	add_child_autofree(pebble)
	var cobble := LiftableStone.new()
	cobble.diameter_cm = 24.0
	add_child_autofree(cobble)
	var picker := _Picker.new()
	pebble.pick_up(picker)
	var after_pebble := picker.inventory.count_of("rock")
	cobble.pick_up(picker)
	assert_gt(picker.inventory.count_of("rock") - after_pebble, after_pebble)


## A full inventory leaves the stone on the ground rather than deleting it.
func test_a_pebble_that_does_not_fit_stays_put():
	var pebble := LiftableStone.new()
	pebble.diameter_cm = 4.0
	add_child_autofree(pebble)
	var picker := _Picker.new()
	picker.inventory = _FullInventory.new()
	assert_false(pebble.pick_up(picker))
	assert_false(pebble.is_queued_for_deletion(), "the stone should still be there")


# -- dispersion: mass-weighted, rolled fresh on every contact ---------------
#
# See PebbleDispersion for the pure trigger/nudge/chance math this wraps.
# Superseded design: dispersion used to be a one-shot lifetime flag (kicks
# once, never again). The user explicitly corrected this: every contact
# should roll again, so a stone can keep drifting further across many
# walkovers, not just once ever (see PebbleDispersion's own doc comment).
# The roll itself is hash-derived from (stone_seed, contact index), not
# Godot's global RNG -- deterministic and reproducible like every other
# seeded pick in this codebase, while still varying contact to contact.

func test_try_disperse_does_nothing_when_the_walker_is_far_away():
	var pebble := LiftableStone.new()
	pebble.position = Vector2(100, 100)
	add_child_autofree(pebble)
	var moved := pebble.try_disperse(Vector2(500, 500))
	assert_false(moved)
	assert_eq(pebble.position, Vector2(100, 100))


## Pins the wiring exactly: try_disperse's outcome on a walker within range
## must match the SAME roll-vs-chance comparison PebbleDispersion.
## dispersion_chance and the deterministic per-contact roll would produce
## computed independently -- true whichever way that particular seed's first
## roll happens to land, so this is not a flaky "probably passes" test.
func test_try_disperse_matches_the_deterministic_roll_against_chance():
	var pebble := LiftableStone.new()
	pebble.stone_seed = 9
	pebble.diameter_cm = 3.0
	pebble.position = Vector2(100, 100)
	add_child_autofree(pebble)

	var walker_position := Vector2(102, 100)  # within PebbleDispersion.TRIGGER_RADIUS_PX
	var mass := StoneSize.mass_kg_for(pebble.diameter_cm)
	var chance := PebbleDispersion.dispersion_chance(mass)
	var roll := PixelNoise.unit(pebble.stone_seed, 0, LiftableStone.DISPERSE_ROLL_CHANNEL)
	var expect_nudge: bool = roll < chance

	var moved := pebble.try_disperse(walker_position)
	assert_eq(moved, expect_nudge)
	if expect_nudge:
		assert_ne(pebble.position, Vector2(100, 100))
		assert_almost_eq(
			pebble.position.distance_to(Vector2(100, 100)), PebbleDispersion.NUDGE_DISTANCE_PX, 0.01
		)
	else:
		assert_eq(pebble.position, Vector2(100, 100))


## The new, corrected design: a stone is never "used up" after one nudge --
## repeated contacts each roll again, and a light-enough stone (high
## per-contact chance) should end up nudged more than once across many
## contacts. Deterministic: PixelNoise.unit's sequence for a fixed
## (stone_seed, channel) never changes, so this always resolves the same way.
func test_try_disperse_can_nudge_the_same_stone_more_than_once():
	var pebble := LiftableStone.new()
	pebble.stone_seed = 3
	pebble.diameter_cm = 2.0  # very light: near the max per-contact chance
	pebble.position = Vector2(100, 100)
	add_child_autofree(pebble)

	var successful_nudges := 0
	for _i in 30:
		# Re-approach from wherever the stone currently sits, so every call
		# is genuinely "within trigger range" regardless of earlier nudges.
		var walker_position: Vector2 = pebble.position + Vector2(2, 0)
		if pebble.try_disperse(walker_position):
			successful_nudges += 1
	assert_gt(successful_nudges, 1, "a light stone should be nudgeable more than once across repeated contacts")


## The contact counter (and therefore the roll) must actually advance between
## calls -- otherwise every contact would deterministically repeat the exact
## same first roll forever, which would make the "more than once" behaviour
## above pure luck rather than a real advancing sequence.
func test_try_disperse_contact_count_advances_between_calls():
	var pebble := LiftableStone.new()
	pebble.stone_seed = 5
	pebble.diameter_cm = 3.0
	pebble.position = Vector2(100, 100)
	add_child_autofree(pebble)
	assert_eq(pebble._disperse_contact_count, 0)
	pebble.try_disperse(Vector2(102, 100))
	assert_eq(pebble._disperse_contact_count, 1)
	pebble.try_disperse(pebble.position + Vector2(1, 0))
	assert_eq(pebble._disperse_contact_count, 2)


class _Picker:
	var inventory = Inventory.new(20)


class _FullInventory:
	func add(_item, count: int) -> int:
		return count  # nothing fits

	func count_of(_id: String) -> int:
		return 0
