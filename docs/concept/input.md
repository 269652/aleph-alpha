# Input

How a keypress becomes an action. This doc exists because the answer used to
be "the physics tick asks whether the key is down right now", and that turns
out to be a *lossy* question: at a low frame rate it silently throws away
whole presses. Reported live during a playtest, at 6-8 FPS: a 140ms tap on
the talk key did nothing at all. Not late — nothing.

Everything else the player does is specified in its own doc
([combat.md](combat.md), [stone.md](stone.md), [fishing.md](fishing.md),
[taming.md](taming.md), [trade.md](trade.md), [building.md](building.md)).
What this doc pins is the one rule they all share: whether an action is read
as an *edge* or as a *level*, and what each of those guarantees.

## Design pillars

1. **A press that happened must act, whatever the frame rate.** The frame
   rate decides how *soon* an action resolves, never *whether* it resolves. A
   dropped input is a bug in its own right, not an acceptable symptom of a
   slow frame — and it must be fixed as one, because making the game faster
   only narrows the window in which presses vanish, it never closes it.
2. **One press, one action.** No press may fire twice, and holding a tap key
   down may not auto-repeat. This is what makes the fix above safe to add on
   top of the existing read rather than as a replacement for it.
3. **An edge action and a level action are different things, and the code
   says which.** "Swing the sword" is an event. "Hold guard up" is a state.
   Reading either one the other way is a bug: a level read loses a fast tap,
   an edge read turns a hold into a single frame.

## Real-world grounding: why a poll loses presses

Godot delivers accumulated input **once per rendered frame**, not
continuously. At 6-8 FPS the gap between two flushes is 125-165ms. A tap
shorter than that has its press *and* its release delivered in the **same
flush**, so `Input.is_action_pressed` is false on every physics tick before
that flush and false again on every tick after it. The press is never
observed by anything that polls — it is erased, not delayed.

Physics ticks do not help. At 60 Hz physics and 6 FPS rendering, Godot runs
several physics ticks per frame, but they all read the *same* post-flush
input state. Eight ticks that each ask "is it down?" get eight identical
answers.

The events themselves are never lost. `_input` / `_unhandled_input` receive
both the press and the release regardless of frame rate. Only the *level*
between them is unobservable.

## Mechanism spec

### Edge actions latch; level actions poll

**Edge ("momentary") actions** — `attack`, `build`, `destroy`, `kick`,
`stash`, `talk`, `trade` — are listed once, in `Player.MOMENTARY_ACTIONS`.
`Player._unhandled_input` records each rising edge into an `InputLatch`
(`src/gameplay/input_latch.gd`), and the physics step *consumes* it. The
latch remembers "this was pressed since you last looked", which is a question
the frame rate cannot change the answer to.

**Level actions** — `block`, `pickup`, `fish`, `lasso`, `mount`, and
movement — keep polling `Input.is_action_pressed`, deliberately. `block` is
"is guard up right now"; `pickup` drives the charge meter
([stone.md](stone.md)), `fish` the cast-and-reel ([fishing.md](fishing.md)),
`lasso` and `mount` the rope and the saddle ([taming.md](taming.md)). All of
those genuinely need to know the key is *still* down, and latching them would
collapse a hold into one tap. A level action can still be *late* at a low
frame rate; it cannot be erased, because there is no edge to miss.

### The latch is added to the poll, not swapped for it

`Player._rising_edge(action, pressed_now, pressed_last_tick)` fires on either
a latched press or the polled level going false→true. Both halves stay:

- the **latch** is the only thing that sees a tap shorter than one frame;
- the **poll** still fires for a key genuinely held across a tick, still
  fires when the event was consumed by a focused `Control` before reaching
  `_unhandled_input`, and is the *only* source on the authority for a
  **remote** client, whose actions arrive as a replicated level
  (`_pending_*_pressed`) rather than as local events.

They cannot double-fire: a real press latches exactly once and the consume
clears it, while the level half only fires on the tick the level itself
changes. A client forwards `latched or held` to the server
(`Player._local_momentary_input`), so the server's own edge detector sees the
tap it would otherwise never have been told about.

### Where the latch is read from, and what that buys

`_unhandled_input`, not `_input`: an event a focused `Control` has already
used — typing into the dev console, driving a menu — never reaches it. That
is the behaviour the polled path could only approximate with the
`ConsoleFocus` flag, which is still checked for the polling half.

### A press is remembered until it is looked at — never longer

The latch's whole value is that a press outlives the frame it happened in.
Its whole hazard is the same sentence with "indefinitely" on the end, which
is a failure mode the polled read could not have: a poll has no memory, so
losing focus loses the press for free.

So the rule is **the tick that looks at the latch always takes the press**,
and only *acting* on it is conditional. `Player._rising_edge` consumes
unconditionally and then gates the result on `_controlled_locally`; a press
the world was not in control for is therefore **dropped**, not banked. Without
that, pressing `T` a frame before the dev console takes focus greets an NPC
whenever the console is closed again — seconds or minutes later, out of
nowhere. Pinned by
`test_a_press_the_console_stole_focus_from_is_dropped_not_banked`.

`Player._local_momentary_input` — what a non-authority client forwards to the
server each tick — follows the same rule and additionally checks
`ConsoleFocus` itself. It reads `Input` directly, and Godot's `Control` focus
system does not suppress that, so a client typing `b` into the dev console
was otherwise telling the server to build on every keystroke. (That half is
older than the latch; the `_submit_*` calls polled `Input` with no focus check
at all.)

### Nothing pressed during a dead frame replays

`Player._authority_step` returns early while dead, so no step consumes the
latch. `_respawn` clears it, so a key mashed during the respawn wait does not
fire the instant control returns. The polled half has this property for free,
since it only ever reads the current level.

## Status

- ✅ `InputLatch` — pure, engine-free, `src/gameplay/input_latch.gd`, pinned
  by `tests/unit/test_input_latch.gd`.
- ✅ The seven edge actions latch from `Player._unhandled_input` and are
  consumed by the physics step, pinned by
  `tests/unit/test_player_input_latch.gd` — including the reported bug
  itself (a tap delivered as events with the poll never true still acts) and
  the two no-double-fire guards.
- ✅ The five level actions are pinned as *deliberately not latched* by the
  same test file, so converting one is a decision someone has to make on
  purpose.
- ✅ A latched press the world never got to act on is dropped rather than
  banked, on both the authority read (`_rising_edge`) and the client's
  forwarded read (`_local_momentary_input`), pinned by
  `test_a_press_the_console_stole_focus_from_is_dropped_not_banked` and
  `test_the_clients_forwarded_momentary_input_is_suppressed_by_console_focus`
  with green-both-ways guards beside each.
- ✅ `attack` is pinned end-to-end (a between-polls tap starts the swing
  cooldown, exactly once) — it is the action the original report was about
  and `_attack_step` had no direct test anywhere before this.
- ⬜ `pickup`'s press-and-hold charge cycle still starts from a polled level,
  so the initial grab of a very fast tap can still be lost even though the
  hold itself is correct. Converting it means splitting "the press that
  starts the charge" (edge) from "still holding" (level), which is a real
  mechanic change, not a wiring change.
- ⬜ Only `attack`, `build` and `destroy` are forwarded to the authority at
  all (`_submit_*`). `kick`, `stash`, `talk` and `trade` have
  `_pending_*_pressed` fields that nothing ever sets, so in real multiplayer
  a remote client cannot perform them. Pre-existing; the latch neither
  causes nor fixes it.
- ⬜ `Player._bind_wasd_movement` does not bind `kick` or `stash`; only
  `World._apply_keybindings` does. An isolated `Player` therefore has two
  edge actions with no key, which is why the latch guards on
  `InputMap.has_action`.
