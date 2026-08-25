extends RefCounted

## A press that HAPPENED AT ALL since the last poll, rather than a press that
## happens to still be held AT the poll.
##
## Every momentary action in Player (attack, build, destroy, kick, stash,
## talk, trade) is read by polling `Input.is_action_pressed` inside
## `_physics_process`, and Godot delivers accumulated input once per rendered
## frame. At 6-8 FPS the gap between two flushes is 125-165ms, so a tap
## shorter than that has its press AND its release delivered in the SAME
## flush: `is_action_pressed` is never true on any physics tick that observes
## it, and the input is not delayed, it is erased. Reported live during a
## playtest: a 140ms tap silently swallowed.
##
## The EVENTS are not lost, though -- only the level is. `_input` /
## `_unhandled_input` still receive both the press and the release, whatever
## the frame rate. So Player latches the rising edge there and consumes it
## from the physics step, which makes the poll rate irrelevant: a press is
## remembered until something takes it.
##
## Deliberately pure -- no `Input`, no `Node`, no engine singleton -- so the
## rule ("a tap between two polls still fires exactly once") is testable on
## its own, the same "pure logic here, wiring in the Node" split ChargeMeter
## and Kick already use. The wiring lives in Player._unhandled_input.
##
## One press per action is remembered, not a queue: two taps that both land
## between the same pair of polls fire once. That matches what the polled
## rising-edge detector this replaces could ever have done (it can only see
## one edge per poll), so nothing that used to fire twice now fires once.

var _latched: Dictionary = {}


## Record that `action` was pressed. Called from the input event, once per
## real rising edge -- not per frame, and not while the key is merely held.
func press(action: String) -> void:
	_latched[action] = true


## True if `action` was pressed since the last consume, and clears it, so one
## press fires exactly one thing. This is the physics step's replacement for
## "pressed now and not pressed last tick".
func consume(action: String) -> bool:
	if not _latched.has(action):
		return false
	_latched.erase(action)
	return true


## Whether a press is pending, WITHOUT taking it -- for a caller that has to
## look before it knows whether it is allowed to act on it.
func is_latched(action: String) -> bool:
	return _latched.has(action)


## Drops every pending press. For a state change that should not replay
## whatever was pressed during it (e.g. coming back from death, where the
## simulation step that would have consumed the press never ran).
func clear() -> void:
	_latched.clear()
