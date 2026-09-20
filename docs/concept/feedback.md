# Feedback — every verb pays, out loud

*The friend who was shown this game "wasn't impressed at all". Ten lenses
were pointed at why, and one of the three answers that came back was the
plainest possible one: you press a key and the world says nothing.*

This doc specifies the **answerback**: the single statement of what every
world-changing action in the game replies with — a sound, a flash, a number
that floats, a line of text — and how often it is allowed to reply.

Measured on 2026-09-20, before this module existed:

- `src/audio/interaction_sfx_player.gd` has exactly **three** `play_`
  methods in the whole game: `play_footstep`, `play_mushroom_crush`,
  `play_creature_call`.
- `grep` for a hit flash, a damage number, a floating text node or a
  level-up toast anywhere under `scenes/` or `src/` returns **nothing**.
  None of the four exists.
- `Player.gain_experience` returns the number of levels gained. All three
  of its callers (`scenes/player.gd:2929`, `:3744`, `:4943`) **discard the
  return value**. The game knows you levelled up and throws the fact away.
- `Keybindings.ACTIONS` binds **36** actions. Exactly **four** of them —
  the movement quartet — produce any sound at all, through
  `play_footstep`. The other thirty-two are silent.

So the feet are the only verb in this game that answers. Everything else —
swinging an axe into a tree, placing a building, casting a spell, handing a
villager the rock they asked for — happens in total silence, with no mark
on the screen, and the player is left to infer from a number in a panel
whether anything occurred.

## Design pillars

1. **Every verb pays, out loud, within a pinned interval.** If pressing a
   key changes the world, the world answers: within
   `DELIBERATE_INTERVAL_SECONDS` at the very slowest, and for the fast
   repeated verbs within the time it takes the player to take one step.
   Not "most verbs". Every one — which is only checkable because the set of
   verbs is a real list in a real file, and this table is checked against
   it.

2. **Silence is a bug the test suite can see.** This is the whole point of
   the module. `test_answerback.gd` partitions `Keybindings.ACTIONS` into
   the verbs that change the world and the ones that only move a camera or
   open a window, and asserts **in both directions**: every world-changing
   action has a feedback row, no window-toggle has one, and no row exists
   for an action that is not in the game. Bind a new verb and the suite
   fails until it is answered. Delete a verb and the suite fails until its
   row goes. Silence stops being an oversight anybody can ship and becomes
   a red test.

3. **A refusal is feedback too.** The worst thing a game can do to a
   player is nothing, and "nothing" is exactly what today's failed action
   produces: `Player.activate_item_id` returns `false` and the bool is
   dropped on the floor. A press that *could not* do what it meant answers
   differently from one that did — its own dull sound, its own muted
   colour, no number, and a line that says why. A player who learns that a
   refusal has a voice stops wondering whether the key is broken.

4. **What floats is what changed, with its sign.** A floating number is a
   receipt. `+` is something gained (`+3 Stick`, `+6 XP`), `-` is something
   lost (`-12` over the creature that just took the hit). One float per
   press, never a stack of three, and it is drawn from the caller's own
   context — this table never invents a number, it only says *which* of
   the numbers the caller already has is the one worth showing.

5. **The interval is the verb's own gate wherever a gate exists.** A
   rapid verb must not machine-gun, but a cooldown pulled out of the air
   silences real actions. So an answer's minimum interval is set to the
   rate limit the verb *already has*: the swing answers at
   `Player.ATTACK_COOLDOWN`, the feet at their own real stride. An
   interval equal to the verb's gate is exactly transparent — it can never
   eat an action the game itself allowed.

6. **Pure, and therefore true everywhere.** `Answerback` is a
   `RefCounted` with static functions. No node, no clock, no world, no
   singleton. `should_play` takes the two timestamps rather than reading a
   clock, so the cooldown is a tested property rather than something you
   have to play the game to check.

## Real-world grounding

Two of the three intervals are read off the human body rather than picked.

**The floor is a footfall.** `FootstepGait.STRIDE_LENGTH_METERS` is 0.75 m,
the real heel-to-heel stride of an average adult at a walk. At this world's
scale (`GroundSlide.PX_PER_METER` = 11.22, itself derived from a 175 cm
player) that is 8.415 px, and at `Player.BASE_SPEED` (40 px/s) the player
plants a foot every **0.210 s**. That is the rate at which this game
already answers a verb, so nothing here may answer faster: below a fifth of
a second, repeated sound stops being a rhythm and becomes a buzz.

**The ceiling is a read.** Brysbaert's 2019 meta-analysis of 190 studies
puts silent reading of English non-fiction at about **238 words per
minute**. A feedback line is about four words — *"Crafted Stone Axe"*,
*"+3 Stick"*, *"Nothing to trade here"* — so reading one takes
`4 / 238 × 60 ≈ 1.01 s`. A deliberate act that answers with a sentence gets
that second before it may speak again, because two sentences inside one
read is not two answers, it is one answer lost.

Both numbers are derived in code from the constants they come from
(`Answerback.REFLEX_INTERVAL_SECONDS`, `DELIBERATE_INTERVAL_SECONDS`) and
neither is typed in.

## Mechanism

### `Answerback` — pure, and the whole table

`src/gameplay/answerback.gd`, a pure `RefCounted` of static functions in
the spirit of `sprint_cost.gd` and `errand_delivery.gd`. It holds one
constant dictionary, `FEEDBACK`, keyed by action id. Each row is:

```
{
  "sound":   "axe_bite",        # a sound id the audio layer must provide
  "flash":   FLASH_HIT,         # which of five flash kinds, or FLASH_NONE
  "floats":  FLOAT_DAMAGE,      # which context key the number comes from
  "message": "",                # a banner line template, or "" for none
  "interval": SWING_INTERVAL_SECONDS,
}
```

The colours are not this module's own. `FLASH_HIT` is `UiTheme.NEGATIVE`,
`FLASH_GAIN` and `FLASH_LEVEL` are `UiTheme.ACCENT`, `FLASH_REFUSED` is
`UiTheme.TEXT_MUTED` — the same warm-gold/red good-bad pair
[hud.md](hud.md) already pins for karma, so a gain here and a gain there
are one decision.

The sound ids are a **commissioning list**, not a claim that the clips
exist. Three do (`FootstepSound`'s steps and the mushroom crush); the rest
name the sound the audio layer owes each verb, so the gap is written down
in one place rather than being invisible.

### The four entry points

- **`for_action(action_id, context)`** — the resolved feedback for this
  press. `context` carries only what the caller already knows: `damage`,
  `item_id`/`item_count`, `xp`, `levels`, `target`, `failed`, `reason`. An
  action with no row returns an empty dictionary (a real answer: "this verb
  answers with nothing", which is correct for a window toggle).
- **`floating_text_for(action_id, context)`** — the number or word that
  floats, or `""`. Precedence when a context carries several: damage, then
  the item, then XP, then levels — the most physical fact first. A failed
  action floats nothing; a refusal is *said*, not scored.
- **`should_play(action_id, last_played_seconds, now_seconds)`** — pure
  rate limiting. True when at least `interval_for(action_id)` has passed. A
  never-played action (negative `last_played_seconds`) is always true, and
  so is a clock that has gone backwards: when in doubt this module makes
  noise, because the failure it exists to prevent is silence.
- **`interval_for(action_id)`** — the minimum interval, so a caller that
  wants to schedule rather than poll can.

### Refusal

`for_action` with `{"failed": true}` returns the refusal row for that
action instead of its success row, built from three fixed parts: the
shared `SOUND_REFUSED`, `FLASH_REFUSED`, and the caller's own `reason`
string as the message (falling back to a generic line when the caller has
no reason to give). Refusals share `REFUSAL_INTERVAL_SECONDS` —
deliberately the deliberate interval, not the reflex one, because a player
holding a key against a wall should hear *one* "no", not forty.

### The three intervals

| constant | value | what it is |
|---|---|---|
| `REFLEX_INTERVAL_SECONDS` | ≈ 0.210 s | one real stride at walking pace, derived from `FootstepGait.STRIDE_LENGTH_PX / WALK_SPEED_PX_PER_SECOND` |
| `SWING_INTERVAL_SECONDS` | 0.5 s | `Player.ATTACK_COOLDOWN` itself — the swing's own gate |
| `DELIBERATE_INTERVAL_SECONDS` | ≈ 1.008 s | the time to read a four-word line at 238 wpm |

They are strictly ordered, and the test pins the order as well as each
value, so a future edit cannot quietly make a craft line flicker faster
than a footstep. The whole scale sits comfortably under
`World.EASTER_EGG_MESSAGE_DURATION` (6.0 s), the repo's own existing answer
to "long enough to read a short line, short enough to be a glimpse".

### The drift test, in both directions

The test names three constants and checks them against the live
`Keybindings.ACTIONS`:

- `WORLD_CHANGING_ACTIONS` (28) — the verbs that change something outside
  the UI. Includes the movement quartet (moving is how this game is
  played, and the feet are already its one honest answer) and
  `hotbar_1..5`, which are **not** a selection: `Player.activate_hotbar_slot`
  equips a weapon, eats food, or arms a placeable, and returns a bool
  saying whether it worked.
- `VIEW_ONLY_ACTIONS` (8) — every `toggle_*`. These open a window or a
  mode. They must have **no** row, because a window that thumps when it
  opens is noise, and because letting them in would make the forward
  direction of the test meaningless.
- `UNBOUND_VERBS` — world-changing acts that reach the player through
  something other than a key: `craft` (`CraftingWindow.craft_requested` →
  `Player.craft`) and `level_up` (the return value of
  `Player.gain_experience` that nobody reads). These get rows, and the test
  asserts they are **not** in `ACTIONS` — so the day someone binds a craft
  key, the partition has to be redone on purpose rather than by accident.

The two partitions must union to exactly the live action list, with no
overlap and no duplicates. That single assertion is what makes adding a
silent verb impossible: a new action in `ACTIONS` is in neither list, and
the suite goes red before it can ship.

## Status

- ✅ **Wired into the game** (2026-09-20). `Player.answered` carries
  `Answerback`'s own resolved dictionary and `World._on_player_answered`
  draws it: the line on the shared message stack, the number floating up
  off the hero and fading inside the table's own deliberate interval so
  two receipts never stack. Raised from the real paths rather than a
  test hook — a connecting swing (`_perform_attack`), a sweep off the
  ground (`pickup_nearby`), experience gained and a level reached.

  **`gain_experience` has always returned the levels it granted, and all
  three of its callers threw that away** — which is exactly why a
  level-up was a silent change to a corner label. It is read now.

  Rate-limited per action from the table's own interval, against a clock
  the player advances itself rather than `Time.get_ticks_msec`, so the
  limit is testable without a real clock — the same reason
  `should_play` takes its `now`. A verb with no feedback row raises
  nothing at all (`test_player_answerback.gd`, 8).


- ✅ **The table and its four entry points** (2026-09-20).
  `Answerback.for_action` / `floating_text_for` / `should_play` /
  `interval_for`, pure and static (`tests/unit/test_answerback.gd`).
- ✅ **The two-way drift test** (2026-09-20). The partition of
  `Keybindings.ACTIONS` is a named constant in the test; adding a verb
  without feedback fails, adding feedback for a verb that does not exist
  fails, and a `toggle_*` that grows a row fails.
- ✅ **Derived intervals** (2026-09-20). Reflex from the real stride,
  swing from `Player.ATTACK_COOLDOWN`, deliberate from a measured silent
  reading rate. No global magic cooldown anywhere.
- ⬜ **The sounds themselves.** Every `sound` id but the footsteps names a
  clip that does not exist yet. The table is the commissioning list; the
  clips are a separate pass.
- ⬜ **The wiring.** Nothing calls `Answerback` yet — the flash, the
  floating text node and the toast are `World`/`Player`'s to build, and
  `Player.gain_experience`'s discarded return value is the first caller
  that should change. Named follow-ups, not silent gaps.
