extends GutTest

const Health = preload("res://src/gameplay/health.gd")

var health: Health


func before_each():
	health = Health.new()


func test_take_damage_reduces_health_by_the_amount():
	assert_eq(health.take_damage(100.0, 30.0), 70.0)


func test_take_damage_never_goes_below_zero():
	assert_eq(health.take_damage(10.0, 999.0), 0.0)


func test_heal_increases_health_by_the_amount():
	assert_eq(health.heal(50.0, 20.0, 100.0), 70.0)


func test_heal_never_exceeds_max_health():
	assert_eq(health.heal(90.0, 50.0, 100.0), 100.0)


func test_is_dead_true_at_zero_health():
	assert_true(health.is_dead(0.0))


func test_is_dead_false_above_zero_health():
	assert_false(health.is_dead(1.0))
