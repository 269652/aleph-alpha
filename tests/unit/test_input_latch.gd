extends GutTest

## InputLatch: "this action was pressed at some point since I last looked",
## as opposed to "this action happens to still be held AT the moment I
## look".
##
## Every momentary action in Player is read by polling
## Input.is_action_pressed inside _physics_process. Godot delivers accumulated
## input once per rendered frame, so at 6-8 FPS a tap shorter than the frame
## interval has its press AND its release delivered between two polls, and
## the poll is simply never true on any tick that observes it -- the press is
## not delayed, it is erased. Reported live: a 140ms tap silently swallowed.
##
## Latching the EDGE (fed from _unhandled_input, which sees every event
## regardless of frame rate) makes the poll rate irrelevant. Pure state, no
## engine dependency, so it can be tested without an Input singleton at all
## -- the same "pure logic, wiring keeps the Node" split ChargeMeter/Kick use.

const InputLatch = preload("res://src/gameplay/input_latch.gd")


func test_a_press_and_release_between_two_polls_is_still_reported_once():
	var latch := InputLatch.new()

	# The press event arrives; the release arrives in the same input flush,
	# so nothing about "is it held right now" is ever true for the poller.
	latch.press("attack")

	assert_true(latch.consume("attack"), "a press between two polls must survive to the next poll")


func test_consuming_clears_the_latch():
	var latch := InputLatch.new()
	latch.press("attack")

	assert_true(latch.consume("attack"), "the first consume reports the press")
	assert_false(latch.consume("attack"), "the same press must not fire a second time")


func test_an_unpressed_action_is_never_reported():
	var latch := InputLatch.new()

	assert_false(latch.consume("attack"), "nothing was pressed")


func test_two_presses_before_one_consume_report_once_not_twice():
	var latch := InputLatch.new()
	latch.press("attack")
	latch.press("attack")

	assert_true(latch.consume("attack"), "the pending press is reported")
	assert_false(latch.consume("attack"), "one consume clears everything pending for that action")


func test_actions_are_latched_independently_of_each_other():
	var latch := InputLatch.new()
	latch.press("build")

	assert_false(latch.consume("destroy"), "consuming one action must not report another")
	assert_true(latch.consume("build"), "and must not clear another either")


func test_is_latched_reports_without_consuming():
	var latch := InputLatch.new()
	latch.press("talk")

	assert_true(latch.is_latched("talk"), "peeking sees the pending press")
	assert_true(latch.is_latched("talk"), "peeking does not clear it")
	assert_true(latch.consume("talk"), "so it is still there to consume")


func test_clear_drops_everything_pending():
	var latch := InputLatch.new()
	latch.press("attack")
	latch.press("build")

	latch.clear()

	assert_false(latch.consume("attack"), "attack was dropped")
	assert_false(latch.consume("build"), "build was dropped")
