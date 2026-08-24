extends GutTest

## World's forwarding getters for the "was this found" signals two of this
## stage's Easter eggs expose (docs/concept/easter_eggs.md's Zork-homage
## terminal and signed secret room -- see AncientTerminal/SignedSecretRoom's
## own doc comments) -- the clean, testable hook point a later "Three
## Fragments" system can check "has the player found X" against, without
## reaching into World's private fields directly.
##
## World itself has no direct unit tests (see test_world_persistence.gd's
## own doc comment: "World's role is orchestration glue over already-tested
## pieces"), but these two getters are genuinely pure/dependency-free --
## they only read a plain (non-@onready) field, so, like test_world_
## persistence.gd's own tests, they don't need add_child() or the real
## scene tree.

const World = preload("res://scenes/world.gd")

var world: World


func before_each():
	world = World.new()


func after_each():
	world.free()


func test_has_found_ancient_terminal_false_until_the_module_marks_it():
	assert_false(world.has_found_ancient_terminal())
	world._ancient_terminal.mark_found()
	assert_true(world.has_found_ancient_terminal())


func test_has_found_signed_secret_room_false_until_the_module_marks_it():
	assert_false(world.has_found_signed_secret_room())
	world._signed_secret_room.mark_found()
	assert_true(world.has_found_signed_secret_room())
