# Sleep — putting the night behind you, and what finds you while you do

[survival.md](survival.md)'s first paragraph has always said a character
must *"eat, drink, and sleep"*. Eating and drinking are real:
`SurvivalMeters` carries hunger, thirst and nutrition, and `eat`/`drink`
relieve them. **Sleep has never existed.** `SurvivalMeters.rest(amount)` is
an arithmetic helper that adds to the stamina bar; there is no resting
state, nothing that can interrupt one, and no way for a character to put a
night behind them.

That gap blocks a specific piece of design. [monsters.md](monsters.md)'s
entry 3, the Alp, is a creature whose entire behaviour is *"it is only
dangerous while you are not… it approaches only while you rest, and drains
stamina rather than health. Waking is the counterplay, and the cost of
waking is the rest you lose."* There is nothing for that to attach to.

## Design pillars

1. **Sleep is not a fatigue meter.** This game already has four needs and a
   sickness model; a fifth bar that fills while you play and empties while
   you stand still would be a chore, not a mechanic. Resting is a **verb**
   you choose, with a cost and a payoff, not a debt the clock collects.
2. **What it buys is the night.** Night in this world is real and hostile:
   `SurvivalMeters`' cold, no light to forage by, and predators that sense
   as well in the dark as you do not. Resting is the honest answer to *"it
   is four in the morning and there is nothing to do but freeze"* — the
   same complaint the dawn clause answered for the first ten seconds
   ([arrival.md](arrival.md)), answered for every night after.
3. **It ends at first light, and that is one constant.** A rest runs to
   `DawnClause.FIRST_LIGHT_HOUR` — civil dawn, the sun's centre 6° below
   the horizon, already derived from this repo's own astronomy for the
   arrival clause. The hour a character wakes and the hour a new character
   opens their eyes are the same fact, stated once.
4. **A commitment, not a button.** The payoff is banked **only when the
   rest completes**. Waking early — by choice, or because something reached
   you — keeps the hours that really passed and loses the rest. That is
   what makes the Alp a decision rather than damage.
5. **While you rest you are not watching.** The whole cost. No refusal
   keeps a player safe while asleep, because a safe sleep is a loading
   screen.
6. **Refusals are sentences.** *"Something is hunting you."* — the same
   rule every other verb in this overhaul follows.

## Real-world grounding, and where the numbers come from

**The wake hour is civil dawn**, exactly as [arrival.md](arrival.md)
derives it: sunrise on an equinox is 06:00 local solar time at every
latitude, the sun climbs at Earth's own 15°/hour, and 6° of that is 24
minutes — so `FIRST_LIGHT_HOUR` = 5.6. Read from `DawnClause`, never
retyped.

**The rate is derived from two constants that already exist.** A rest must
not itself cost the player real time — the point of skipping a night is to
skip it:

```
MAX_NIGHT_HOURS       = DawnClause.MAX_OFFSET_HOURS          (12)
LONGEST_WATCHABLE     = Answerback.MAX_CARD_SECONDS          (12 s)
HOURS_PER_REAL_SECOND = MAX_NIGHT_HOURS / LONGEST_WATCHABLE  (1.0)
```

Half a clock face is the worst case any rest can face, and
`MAX_CARD_SECONDS` is this HUD's own statement of the longest thing it will
ask a player to sit and read. So **the longest possible night passes in no
more real time than the longest card**, and the rate falls out at a
memorable one in-game hour per real second. Both bounds are pinned by test.

**The clock it advances is the world's own.** `SeasonCycle.SECONDS_PER_DAY`
is four real hours per in-game day, so one in-game hour is
`SECONDS_PER_DAY / 24` of world age, and the advance per real second of
rest is that times the rate above. `World` pushes it through
`EarthChunkManager.advance_world_age` — the same door `/ecotest`'s
`TimeLapse` already uses — so the season, the sun, the fruit and the
ecology all move together and nothing runs on a second clock.

## Mechanism

### `Slumber` — pure, and the whole rule

`src/gameplay/slumber.gd`, a `RefCounted` of static functions with no
player, no world and no scene tree.

- **`refusal_for(facts)`** — the empty string when a character may rest,
  and a sentence when they may not. Facts are what the caller already
  knows: `hunted`, `in_water`, `already_resting`.
- **`hours_until_first_light(local_hour)`** — how long this rest has to
  run, from *now* to `DawnClause.FIRST_LIGHT_HOUR`, wrapping the clock
  face. Resting **after** first light and before dusk is allowed and
  simply runs nearly a whole day; the world does not forbid a nap.
- **`world_age_seconds_for(real_delta)`** — how much world age one frame of
  resting advances, at the derived rate.
- **`is_complete(hours_remaining)`** — whether first light has arrived.
- **`wake_report(hours_slept, completed)`** — what the character is told:
  *"You slept until first light."* or *"Woken after two hours."*

### The verb, on the player

`Player.begin_rest()` / `wake()` / `is_resting()`, with the refusal raised
through the same feedback path every other verb uses
([feedback.md](feedback.md)). Bound to `rest` in `Keybindings`.

While resting, `Player` holds still (input is ignored, not merely unused),
and `World` advances the world clock by `Slumber.world_age_seconds_for`
each frame on top of its ordinary advance.

**Anything that damages the character wakes them.** That is the single
interruption rule, and it is what the Alp's stamina drain hooks: a drain
that wakes you is a drain you can answer.

## Interaction with other docs

- [survival.md](survival.md) — the "eat, drink and sleep" this finally
  makes true, and the stamina a completed rest fills.
- [arrival.md](arrival.md) — `DawnClause.FIRST_LIGHT_HOUR`, shared.
- [monsters.md](monsters.md) — entry 3, the Alp, which this unblocks.
- [seasons.md](seasons.md) — `SeasonCycle.SECONDS_PER_DAY`, the clock the
  rate is expressed against.
- [feedback.md](feedback.md) — the refusal, and the wake line.

## Status

- ✅ **`Slumber`, the whole rule** (2026-09-21). `refusal_for` /
  `hours_until_first_light` / `world_age_seconds_for` / `is_complete` /
  `wake_report`, pure and pinned (`test_slumber.gd`, 20): the rate asserted
  against both constants it is derived from, the longest possible night
  shown to pass inside the longest card *and* to still take long enough to
  be a passage rather than a cut, the wait swept across the whole clock
  face, and every refusal a sentence with no id in it.
- ✅ **The verb, on the player** (2026-09-21). `begin_rest` / `rest_step` /
  `wake` / `is_resting` / `rest_hours_remaining`, bound to `rest`
  (`test_player_rest.gd`, 14): input is really ignored while asleep rather
  than merely unused, the rest really counts down at the shared rule's
  rate, reaching first light really ends it, **a completed rest fills the
  bar and an interrupted one does not**, and being hurt really wakes you.
- ✅ **The world clock really moves.** `World` advances
  `EarthChunkManager.advance_world_age` by what `rest_step` hands back —
  the player counts its own hours and World only pushes them, so the rate
  lives in one place. Verified live: a rest begun at midnight ran 5.60
  in-game hours in **5.62 real seconds** and advanced the world age by
  3370 s, which is 5.6 in-game hours exactly; a bite mid-sleep woke the
  character with the stamina still at zero.
- ✅ **The keyboard is full**, and `test_keybindings.gd` caught it the
  moment this verb reached for R (which `primary_action` holds). Every
  letter A–Z is bound. `rest` takes `KEY_PERIOD`: a number would read as a
  sixth hotbar slot.
- ⬜ There is no visual for sleeping — no fade, no lying-down pose. The
  character simply stops and the sky runs.
- ⬜ Nothing yet makes a night *worth* skipping beyond the cold: shelter,
  a bedroll and a safe/unsafe distinction are unbuilt.
