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
  `item`/`count`, `coins`, `xp`, `level`, `severity`, `target`, `failed`,
  `reason`. An action with no row returns an empty dictionary (a real
  answer: "this verb answers with nothing", which is correct for a window
  toggle). The resolved answer it hands back is a different shape from the
  row: `action`, `sound`, `flash`, `flash_color`, `message`, `float_text`,
  `interval`, `severity`, `failed`.
- **`floating_text_for(action_id, context)`** — the number or word that
  floats, or `""`. Precedence when a context carries several
  (`FLOAT_PRECEDENCE`): damage, then the item, then coins, then XP, then
  the level — the most physical fact first. A failed action floats nothing;
  a refusal is *said*, not scored.
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

### Being hurt is a verb too — the one the player does not press

Every row above answers a key. `hurt` answers the one thing in this game
that happens **to** the character, and it was the loudest silence left:
measured on 2026-09-21, a bear could close, bite, and take a fifth of the
player's health with no sound, no flash, no number and no line. The health
bar moved. That was all.

It is an `UNBOUND_VERB`, alongside `craft` and `level_up` — a real
world-changing event that reaches the player through something other than a
key — so the two-way drift test covers it exactly as it covers those.

**Its interval is the reflex floor, and that is provably transparent.**
Pillar 5 sets an answer's gate to the rate limit the verb already has; for
being hurt, that gate is *how fast something can bite you*. Measured across
every species a biome pool can promote, the fastest real bite in the game
is the **arctic fox at 0.533 s** (`SpeciesBite.bite_cooldown_seconds_for`,
derived from body mass), and `REFLEX_INTERVAL_SECONDS` is 0.210 s — so the
limiter sits at less than half the fastest blow the world can land and can
never swallow one. That is not an assumption: a test sweeps the live spawn
pools and asserts it, so a future species that bites faster than the player
can be told about it fails the suite instead of shipping silently.

**Continuous harm is deliberately not a blow.** Venom, a mushroom toxin and
a spell debuff tick every frame through `Player.take_tick_damage`, and a
receipt per frame is a buzz, not an answer — the exact failure
`REFLEX_INTERVAL_SECONDS` exists to name. A poison is a **condition**, and
this HUD already shows conditions as chips (`HudReadouts.condition_chips`).
So `hurt` fires on the discrete blow and nothing else, and the chip carries
the rest.

**That trade is only honest if the chip is really there, and once it was
not.** Reported from play on 2026-09-22 as *"I constantly die out of
nowhere"*. There are exactly two doors into the player's health —
`take_damage`, which answers, and `take_tick_damage`, which by the rule
above answers nothing — and `Player.active_effects()` gathered venom, spell
debuffs, food buffs and the shield while never gathering
`active_mushroom_toxin_debuffs`. The state was tracked, ticked, and already
in the identical `DebuffStack` shape sitting beside it. So a Death Cap
drained a character at up to 4.5 health a second with **no receipt and no
chip**: nothing on screen named it, and the design's own justification for
the silence — *the chip carries the rest* — was not true of it.

So the rule has a guard now, stated as the invariant rather than as that
one omission (`test_nothing_kills_in_silence.gd`): **every continuous harm
the character can suffer must name itself on the row.** A future tick
source cannot be added without its chip.

Two sources deliberately outside it, each for a reason rather than an
oversight:

- **Bramble thorns** take 2% of max health over a four-second crossing
  (0.72 a second at the reference character) and have no debuff state at
  all, because the thicket is its own chip: you can *see* the brambles you
  are standing in. A poison is invisible; a thicket is not.
- **The Alp** drains stamina rather than health (`NightMare.press`), so it
  cannot kill and is not continuous harm in this sense.

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
- ✅ **Derived dwell, too** (2026-09-20). `Answerback.seconds_to_read` and
  `word_count`: how long a PROSE card stays up, from the card's own word
  count at the same measured reading rate, floored at
  `DELIBERATE_INTERVAL_SECONDS` so a very short card is still a sentence
  rather than a flash. The intervals above answer *how often*; this
  answers *how long*, from the same fact about a reader.

  It exists because a journey ring's crossing card
  ([discovery.md](discovery.md)) runs from seventeen words to thirty-four,
  and showing both for the same six seconds means one of them is wrong.
  The arrival card ([arrival.md](arrival.md)) reads the same rule.
  `MAX_CARD_SECONDS` is the ceiling real card text is held to — restated
  from `World.ANCIENT_TERMINAL_MESSAGE_DURATION`, the longest passage this
  HUD already shows anywhere, and pinned to it by test. It is deliberately
  **not** a clamp: a card cut off mid-warning is worse than a card shown a
  moment too long, so text that grows past it fails a test instead of
  being silently truncated.
- ✅ **Exploration answers too** (2026-09-20). Newly-walked ground floats
  its own receipt through the same rising label every other act uses —
  *"New ground  +2 XP"*, naming what it was paid for rather than a bare
  number. An ordinary new chunk gets the float and nothing else: a chunk
  edge arrives every ~13 s of walking, and a banner at that rate teaches a
  player to stop reading banners, which is this doc's own rule about an
  unread line applied to a verb that fires on its own.
- ✅ **A craft that cannot proceed says why** (2026-09-20).
  `Player.craft_refusal` asks the same three gates `craft` itself checks,
  in the same order, so the explanation and the refusal can never
  disagree: *"Needs heat source; you are not standing at one."*,
  *"Needs smelting 2; you have 0."*, *"Short 3 wood, 1 plant fibre."*
  `World._on_craft_requested` asks BEFORE trying and answers the refusal
  through the same feedback path a success uses.

  Measured before it: `craft` returned a bare false for three different
  reasons and the caller discarded it, so clicking a recipe card that
  looked affordable did nothing at all and said nothing
  (`test_craft_refusal.gd`, 5 -- including one that a craftable recipe
  refuses nothing, so the card cannot lie in the other direction either).
- ⬜ **The sounds themselves.** Every `sound` id but the footsteps names a
  clip that does not exist yet. The table is the commissioning list; the
  clips are a separate pass.
- ✅ **Being hurt answers** (2026-09-21). The loudest silence left: a bear
  could close, bite and take a fifth of the health bar with no sound, no
  flash, no number and no line. `Player.take_damage` raises the `hurt` row
  now, and what floats is what the blow really **cost** — health actually
  lost, after block, shield and armour have each had their say — because a
  receipt that disagrees with the health bar teaches a player to distrust
  both. Raised from `take_damage` and deliberately **not** from `_suffer`,
  which the damage-over-time ticks share; a test pins that `_suffer` stays
  silent (`test_player_answerback.gd`, 15).

  The interval is `REFLEX_INTERVAL_SECONDS`, and that is provable rather
  than taste: the gate on being hurt is how fast something can bite you,
  and the fastest real bite among every species a biome pool can promote is
  the **arctic fox at 0.533 s**, against a floor of 0.210 s. A test sweeps
  the live spawn pools and asserts it, so a species that could bite faster
  than the player can be told about it fails the suite instead of shipping.

- ✅ **A row says how big the act was, not only what kind** (2026-09-21).
  `severity`, a 0–1 fraction of whatever bar the act moved, supplied by the
  caller because the table has no idea how big anybody's bar is. A flash
  that is the same red for a scratch and for a near-killing blow is a
  warning light, not a reading.

- ✅ **The flash exists** (2026-09-21) — the third thing every row said,
  which `World._on_player_answered` had been reading and throwing away. It
  is now two real things:

  **The screen** (`HurtFlash`, `World._flash_screen`) tints toward
  `UiTheme.NEGATIVE` at the instant a blow lands and fades to nothing over
  `Answerback.REFLEX_INTERVAL_SECONDS` — the same interval the hurt answer
  is gated at, so one flash is always gone before the next can start and
  two can never stack into a wall of red. How red is the row's own
  `severity`. **Only `hurt` tints the screen**: four rows carry `FLASH_HIT`
  and three of them (`attack`, `kick`, `destroy`, `cast`) are harm the
  player *dealt*, and a screen that goes red when you chop a tree teaches a
  player that red means nothing.

  **The creature** (`HitFlash`, `CreatureMarker._hit_flash_step`) leans
  toward the same red for the same interval. It **composes** rather than
  replaces, which is the whole difficulty: a `CreatureMarker` *is* the
  `Sprite2D`, and its `modulate` already had two owners — a one-shot coat
  tint written in `_ready`, and a disease tint rewritten every stepped
  frame for anything not `SUSCEPTIBLE`. So the flash steps *after*
  `_disease_step` (a flash written before it is silently swallowed on every
  sick creature), and it blends only `PEAK_BLEND` of the way, because an
  animal repainted flat red has lost its silhouette, its coat tell and its
  pallor in the same frame.

  **A real bug had to be fixed before the flash could exist at all**:
  `HEALTHY_MODULATE_COLOR` was `Color.WHITE`, so the first time a creature
  recovered from a disease its coat tell was erased for the rest of its
  life — and a flash restoring the same white would have done it on every
  blow. `CreatureMarker.base_modulate()` names the baseline nothing in this
  codebase could name before, and both the disease tint and the flash read
  it (`test_creature_hit_flash.gd`, 12).

- ✅ **And a tick is not a blow on the creature's side either**
  (2026-09-21). Found by reading this change adversarially rather than by
  reading the old code: `CreatureMarker._spell_status_step` calls
  `take_damage` with a per-frame fraction every stepped frame, so the
  moment the flash existed an ignited animal would relight it sixty times a
  second and sit pinned at peak red for the whole burn — a creature
  permanently the colour of *just hit*, which tells a player nothing about
  when it was hit. `CreatureMarker.take_tick_damage` now mirrors the
  player's own split: no flash, no flinch row, nobody to be angry at, and
  the world-boss threshold still filtering, so a burn cannot whittle a
  sleeping boss down without ever waking it.

- ✅ **How hard reads too, on both sides** (2026-09-21). The creature flash
  scales with the fraction of *its own* bar the blow took, the mirror of
  the `severity` the player's screen reads, so a scratch and a
  near-killing blow no longer light an animal identically. And the killing
  blow is lit **before** the death branch: it would otherwise be the one
  blow in a fight that never reads.

  A measurement worth keeping: a coat tint can boost a channel above 1.0,
  so leaning such a coat toward `UiTheme.NEGATIVE` (whose own red is 0.85)
  *lowers* the red channel while plainly reddening the animal. The first
  draft of the test asserted `.r` and was wrong for exactly that reason;
  it measures distance toward the flash colour now.

- ✅ **A receipt nobody could see** (2026-09-21). `flash_color` doubles as
  the floating text's own colour, and `flash_color_for(FLASH_NONE)` is
  fully transparent — so the `fish` row, which floated an item while
  declaring no flash kind, drew *"+1 Trout"* in invisible ink for as long
  as it had existed. A landed fish is a gain like any other. The invariant
  is a test now: no row may float a receipt in a colour nobody can see.

- 🚧 **A distant creature's flash stretches.** `take_damage` writes the
  tint immediately, but `_hit_flash_step` only runs when the marker's LOD
  gate lets a step through — up to `SimulationLod.MAX_INTERVAL_SECONDS`
  (2.0 s) away from the player. The flash is not lost, it is *held*: it
  fades on the next coarse step. Named rather than discovered later; at
  that distance nobody is reading it anyway.

- ✅ **The fourth damage-over-time caller** (2026-09-21). The pass that
  split blows from ticks found three and there were four:
  `_step_bramble_thorns` still went through `take_damage`, so a thicket
  crossing cost **60 health a second** at 60 fps whatever
  `BlackberryBramble`'s own derived rate said — and once `hurt` existed it
  would have floated a receipt every fifth of a second for the whole
  crossing. A test now walks all four steps by name rather than trusting
  the next reader to find them.

- ✅ **A refusal keeps its own clock** (2026-09-21). `Player._answered_at`
  was keyed by action id alone, so a refusal and a success of the same verb
  shared one cooldown. Giving the dodge a key found it: pressing dodge
  again the instant after a roll — the commonest press that mechanic will
  ever see — was muted by the roll that caused it, and a press that says
  nothing teaches a player the key is broken, which is exactly what pillar
  3 exists to prevent. Each half still rate-limits itself, so holding a key
  against a wall hears one *"no"* rather than forty.

- ✅ **A mote granted in silence** (2026-09-21). `Player.witness` had
  called `answer("mote_found", …)` since the witness layer shipped, and
  `Answerback.has_feedback` returned false for it — so every atom a
  character earned by living through something (their first frost, their
  first storm) was granted with no sound, no flash, no number and no line.
  The call was there; the **row** was not, which is the one failure mode
  this table's two-way drift test cannot catch on its own: it checks that
  every row is a real verb and that every bound verb has a row, and
  `mote_found` was neither until now. It is an `UNBOUND_VERB` beside
  `craft`, `level_up` and `hurt`.

- ⬜ **The sounds themselves**, still. Every `sound` id but the footsteps
  names a clip that does not exist, `hurt` included. The table is the
  commissioning list.
- ⬜ **A creature's call at the moment it commits to a bite.** Real clips
  exist (`assets/audio/creatures/`, twelve of them) and
  `InteractionSfxPlayer.play_creature_call` already drives a positional
  pool — but this is not the three-line change it looks like, and the
  reasons are written down rather than discovered later:
  [creature_and_footstep_audio.md](creature_and_footstep_audio.md)'s
  pillar 4 forbids world-simulation code calling into audio at all (the
  simulation states facts; `World` decides the sound); the clips are
  full-length field recordings, so a wolf howl fired at a bite is still
  sounding many seconds later and needs the footstep path's own playback
  cap; and the call pool is four round-robin voices with no
  still-playing check, so bite calls would cut ambient ones off. It needs
  that doc extended first.
