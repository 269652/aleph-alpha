extends GutTest

## Damage over time deals what its model says, not the armour floor.
##
## Found by an audit of the combat layer, and verified by hand before this
## test was written. `Player.take_damage` ends with
##
##     amount = maxf(MIN_ARMORED_DAMAGE, amount - equipment.total_armor())
##
## which is exactly right for a HIT -- worn armour never reduces a blow to
## nothing. But all three damage-over-time steps call `take_damage` with a
## PER-FRAME FRACTION: `dps * delta`. At 60 fps, venom's 1.5 dps arrives as
## 0.025 per frame, the floor lifts every one of them to 1.0, and the real
## rate becomes 60 damage per second -- forty times its spec. A fully
## stacked venom dose kills a 100-health character in under two seconds
## instead of costing 36 health over eight.
##
## The existing venom test drove `_venom_step(1.0)` -- a one-second delta,
## where 1.5 > 1.0 and the floor never trips -- and asserted only that
## health went down. So the suite was green over the bug for as long as it
## has existed.
##
## The same tick path also calls `_wear_equipped_item()` once per frame
## while blocking, so being venomed behind a raised guard destroys a weapon
## in seconds.

const PlayerScene = preload("res://scenes/player.tscn")
const VenomModel = preload("res://src/gameplay/venom_model.gd")
const MushroomToxin = preload("res://src/gameplay/mushroom_toxin.gd")
const SpellStatusEffects = preload("res://src/gameplay/spell_status_effects.gd")

## A real frame, which is the whole point: the bug only exists below the
## floor, so a test that ticks in whole seconds cannot see it.
const FRAME := 1.0 / 60.0

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)
	player.max_health = 1000.0
	player.health = player.max_health


func after_each():
	player.queue_free()


func _damage_over(seconds: float, step: Callable) -> float:
	var before: float = player.health
	var elapsed := 0.0
	while elapsed < seconds:
		step.call(FRAME)
		elapsed += FRAME
	return before - player.health


# -- venom ---------------------------------------------------------------

func test_one_second_of_venom_deals_one_second_of_venom():
	player.apply_venom()
	var stacks := 1
	var dealt := _damage_over(1.0, func(d): player._venom_step(d))
	assert_almost_eq(
		dealt, VenomModel.new().damage_per_second(stacks), 0.2,
		"a second of venom is its own damage_per_second, not sixty armour floors"
	)


## The headline: a fully stacked dose is survivable, and the whole dose is
## what the model says it is.
func test_a_full_venom_dose_costs_what_the_model_says_and_is_survivable():
	for i in VenomModel.MAX_STACKS:
		player.apply_venom()
	var dealt := _damage_over(VenomModel.DURATION_SECONDS, func(d): player._venom_step(d))
	var expected := (
		VenomModel.new().damage_per_second(VenomModel.MAX_STACKS) * VenomModel.DURATION_SECONDS
	)
	assert_almost_eq(dealt, expected, expected * 0.15, "the dose is the model's own total")
	assert_lt(dealt, 100.0, "and a full-health character survives being bitten once")


# -- the other two tick paths --------------------------------------------

func test_mushroom_poisoning_deals_its_own_rate():
	player.apply_mushroom_toxin("fly_agaric")
	var dealt := _damage_over(1.0, func(d): player._mushroom_toxin_step(d))
	assert_lt(dealt, 10.0, "a poisonous mushroom is not sixty damage a second")
	assert_gt(dealt, 0.0, "but it is really poisonous")


func test_ignite_deals_its_own_rate():
	player.apply_spell_debuff(SpellStatusEffects.IGNITE, 5.0)
	var dealt := _damage_over(1.0, func(d): player._spell_status_step(d))
	assert_lt(dealt, 10.0, "burning is not sixty damage a second")
	assert_gt(dealt, 0.0, "but it really burns")


# -- a tick is not a blow -------------------------------------------------

## Armour, a raised guard and a spell shield all answer a BLOW. A tick is
## not a blow: it is already inside you, and letting armour soak a fraction
## of a fraction is what created the floor bug in the first place.
func test_a_tick_is_not_stopped_by_armour_or_a_guard():
	player.max_health = 1000.0
	player.health = player.max_health
	var before: float = player.health
	player.take_tick_damage(0.5)
	assert_almost_eq(before - player.health, 0.5, 0.0001, "a tick lands as itself")


func test_a_blow_still_meets_the_armour_floor():
	var before: float = player.health
	player.take_damage(0.01)
	assert_almost_eq(
		before - player.health, player.MIN_ARMORED_DAMAGE, 0.0001,
		"a real hit still always lands for at least the floor"
	)


## The durability half, which is the same bug wearing a different hat.
func test_being_venomed_behind_a_guard_does_not_destroy_the_weapon():
	var Item = load("res://src/gameplay/item.gd")
	var sword = Item.new("iron_sword", "Iron Sword", "weapon", 1)
	player.equipped_item = sword
	var wear_before: float = sword.wear
	for i in VenomModel.MAX_STACKS:
		player.apply_venom()
	_damage_over(2.0, func(d): player._venom_step(d))
	assert_almost_eq(
		sword.wear, wear_before, 0.001,
		"a tick is not a parry -- it must not wear the weapon at all, let alone 120 times"
	)


# -- the fourth caller, missed the first time round -----------------------



## `_step_bramble_thorns` is a damage-over-time step exactly like the other
## three -- it passes `thorn_damage_per_second(...) * delta` -- and it was
## still calling `take_damage`. The original pass found three callers and
## there were four, so standing in a thicket cost 60 health a second at 60
## fps whatever `BlackberryBramble` said it should.
##
## Driven through the source rather than a live bramble tile, because the
## rule is which function the thorns go through, and a chunk manager with
## real bramble in it is a world fixture this suite deliberately does not
## build.
func test_the_thorns_go_through_the_tick_path_not_the_blow_path():
	var body := _function_body("_step_bramble_thorns")
	assert_false(body.is_empty(), "precondition: the step was found")
	assert_true(body.contains("take_tick_damage("), "thorns are continuous harm")
	assert_false(
		body.contains("\ttake_damage("),
		"a per-frame fraction through the blow path is the armour-floor bug"
	)


## And therefore it raises no receipt either: a bramble crossing lasts
## seconds, and a float every fifth of a second is a buzz rather than an
## answer (docs/concept/feedback.md).
func test_every_damage_over_time_step_uses_the_tick_path():
	for step in [
		"_venom_step",
		"_mushroom_toxin_step",
		"_spell_status_step",
		"_step_bramble_thorns",
	]:
		var body := _function_body(step)
		assert_false(body.is_empty(), "precondition: %s was found" % step)
		assert_false(
			body.contains("\ttake_damage("),
			"%s is continuous harm and must not take the blow path" % step
		)


func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)
