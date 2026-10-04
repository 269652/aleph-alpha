extends GutTest

## A real, homing projectile node (docs/concept/spell_runtime.md,
## "Projectile flight: a cast that truly homes"). Unlike SpellEffectMarker
## (purely cosmetic grow/hold/fade glue, untested beyond structure), this
## node drives real gameplay resolution -- WHO a projectile cast's effect
## lands on is decided here, on arrival, not at cast time -- so it gets real
## behavioural tests, the same boundary CreatureMarker's own windup/
## resolution-over-time logic already sits on.

const SpellProjectileMarker = preload("res://src/rendering/spell_projectile_marker.gd")

var projectile: SpellProjectileMarker
var target: Node2D


func before_each():
	projectile = SpellProjectileMarker.new()
	projectile.position = Vector2.ZERO
	add_child_autofree(projectile)
	target = Node2D.new()
	target.position = Vector2(100, 0)
	add_child_autofree(target)


## Drives the projectile forward one 60fps step at a time until it resolves
## (or a generous guard trips) -- the same shape test_creature_marker.gd's
## own _let_the_jaws_close already establishes for "a blow that doesn't land
## the instant it's thrown."
func _let_the_bolt_fly(bolt) -> void:
	var guard := 0
	while bolt.is_in_flight() and guard < 600:
		bolt._process(1.0 / 60.0)
		guard += 1


func test_is_in_flight_right_after_launch():
	projectile.aim_at_target(target)
	projectile.launch(func(_t, _p): pass)
	assert_true(projectile.is_in_flight())


func test_resolves_and_leaves_flight_once_it_arrives():
	projectile.aim_at_target(target)
	projectile.launch(func(_t, _p): pass)
	_let_the_bolt_fly(projectile)
	assert_false(projectile.is_in_flight())


## GDScript lambdas capture an outer local BY VALUE, not by reference --
## assigning to a captured plain variable from inside the lambda would
## mutate only the lambda's own copy. A one-element Array is captured the
## same way, but captures a REFERENCE to that array object, so mutating its
## CONTENTS (never reassigning the variable itself) is visible here too.
func test_arrival_callback_receives_the_live_target_and_the_arrival_position():
	var received := [null, null]
	projectile.aim_at_target(target)
	projectile.launch(func(t, p):
		received[0] = t
		received[1] = p
	)
	_let_the_bolt_fly(projectile)
	assert_eq(received[0], target)
	assert_eq(received[1], target.position)


## The homing claim, end to end: the target moves WHILE the bolt is still
## travelling, and the bolt still reaches it -- a straight shot fired at the
## target's ORIGINAL position would miss a target that has since moved off
## that line entirely.
func test_a_moving_target_is_still_caught():
	target.position = Vector2(200, 0)
	projectile.aim_at_target(target)
	projectile.launch(func(_t, _p): pass)
	for _i in 3:
		projectile._process(1.0 / 60.0)
	target.position = Vector2(200, 150)  # moved well off the original line
	_let_the_bolt_fly(projectile)
	assert_false(projectile.is_in_flight(), "a bolt that truly homes must still catch a target that moved")


func test_aim_at_point_resolves_at_that_fixed_point_with_a_null_target():
	var received := [null]
	var aim_point := Vector2(80, -40)
	projectile.aim_at_point(aim_point)
	projectile.launch(func(t, _p): received[0] = t)
	_let_the_bolt_fly(projectile)
	assert_eq(received[0], null)


## A target that stops existing mid-flight is a miss at its last known
## position, never a retarget (the concept doc's own rule, extended from
## Explicit target selection's "commits to it" principle) -- mirrors
## CreatureMarker._windup_target_id's own instance-id re-validation pattern.
func test_a_target_freed_mid_flight_resolves_as_a_miss_at_its_last_known_position():
	var received := [null, null]
	var last_known := Vector2(100, 0)
	projectile.aim_at_target(target)
	projectile.launch(func(t, p):
		received[0] = t
		received[1] = p
	)
	projectile._process(1.0 / 60.0)
	target.free()
	_let_the_bolt_fly(projectile)
	assert_eq(received[0], null, "a freed target must not be handed to the callback")
	assert_eq(received[1], last_known, "the bolt must still arrive where the target last really was")


func test_launch_respects_a_start_delay_before_moving():
	projectile.aim_at_target(target)
	projectile.launch(func(_t, _p): pass, 0.1)
	projectile._process(1.0 / 60.0)
	assert_eq(projectile.position, Vector2.ZERO, "a delayed bolt must not move during its own delay")


func test_the_arrival_callback_fires_exactly_once():
	var call_count := [0]
	projectile.aim_at_target(target)
	projectile.launch(func(_t, _p): call_count[0] += 1)
	_let_the_bolt_fly(projectile)
	# Extra steps after resolution must never re-fire the callback.
	for _i in 5:
		projectile._process(1.0 / 60.0)
	assert_eq(call_count[0], 1)
