# Dodge — the answer a player is allowed to give

[combat.md](combat.md)'s first line asks for *"twitchy dodge-and-position
combat"*. [predator_profiles.md](predator_profiles.md) builds its entire
fairness model on top of one: its two windup anchors are
`Dodge.INVINCIBLE_DURATION` and `Dodge.COOLDOWN_DURATION` by name, on the
reasoning that *"seeing the tell and dodging on the frame you see it must
be enough"* and that *"a player who has just dodged something else must
never be killed by a bite they could not answer."*

**There is no dodge.** Measured on 2026-09-21: `src/gameplay/dodge.gd` is a
complete, tested pure module with **zero consumers** outside
`SpeciesBite`'s reading of two of its constants; `grep -rn "dodge\|Dodge"
scenes/player.gd` returns nothing at all; no `dodge` action exists in
`Keybindings.ACTIONS`; and `grep -rn "invulner\|invincib\|iframe"
scenes/player.gd` returns one comment. The player has no i-frames of any
kind.

So the predator table is balanced against a verb the player cannot
perform. That is the exact failure this overhaul keeps finding — a real,
well-tested module with nobody calling it — and it is the one that matters
most, because every *other* creature's numbers were authored assuming it
works.

## Design pillars

1. **The dodge is the only unconditional answer.** Blocking reduces; armour
   soaks; a dodge *refuses*. It is the one thing a player can do about a
   blow that would otherwise simply land, and it is what makes a heavy
   predator a problem to solve rather than a number to lose to.
2. **It is movement, so it costs what movement costs.**
   [survival.md](survival.md) is explicit that stamina is traversal's
   resource and that combat stays off it. A dodge is a burst of travel, so
   it spends exactly what sprinting the same distance spends — never more,
   never less. It is not a cheaper way to cross ground.
3. **The cooldown is the real cost.** A dodge you can spam is an
   invulnerability toggle. `Dodge.COOLDOWN_DURATION` is six times the
   window it grants, so the answer is available roughly once per exchange
   and choosing *when* is the whole skill.
4. **You are untouchable exactly while you are moving out of the way.**
   The invincibility window and the dash are the same window. A dodge that
   grants i-frames while standing still is a block button wearing a
   costume, and one that moves you after the i-frames end is a lie.
5. **A blow is dodgeable; a poison is not.** The window refuses a *blow*.
   Venom already inside you, a burning debuff, a mushroom toxin — those run
   through `take_tick_damage` and are untouched. You cannot roll away from
   something that is already in your blood.
6. **A refusal is a sentence**, like every other verb in this overhaul.

## Real-world grounding, and where the numbers come from

**Nothing here is chosen.** Both of the dodge's own constants already
existed, and everything else falls out of them against numbers the game
already had.

| quantity | value | where it comes from |
|---|---|---|
| `Dodge.INVINCIBLE_DURATION` | 0.25 s | already in the module, and it is a human simple-reaction time to a visual stimulus — about a quarter second, which is also why it is the floor `SpeciesBite.BASE_WINDUP_SECONDS` is set to |
| `Dodge.COOLDOWN_DURATION` | 1.5 s | already in the module; `SpeciesBite.LETHAL_WINDUP_SECONDS` is set to it, so the heaviest bite in the game telegraphs for exactly one full cooldown |
| `DODGE_DISTANCE_PX` | 20 px | `Player.SPRINT_SPEED` × `Dodge.INVINCIBLE_DURATION`. Derived, not typed: you move at the speed you can already move, for exactly as long as you are untouchable |

Two things fall out of that 20 px, and both are load-bearing enough to be
tests rather than remarks:

- **It is 1.78 m** at this world's play scale (`GroundSlide.PX_PER_METER`
  = 11.22, itself derived from a 175 cm character). A real evasive dive or
  shoulder roll covers roughly one and a half to two metres. The number
  the game's own constants produce is the number a human body produces.
- **It clears a bite.** `CreatureMarker.ATTACK_RANGE` is 16 px, so a dodge
  begun from inside anything's reach ends outside it. If that ever stopped
  being true — a longer reach, a slower player — the dodge would become
  decoration, so it is asserted directly rather than left to arithmetic
  nobody re-does.

**Being winded stops you rolling.** The gate is `SprintCost.can_sprint`,
which is `SurvivalMeters.EXHAUSTED_THRESHOLD` itself — so *"Exhausted"* on
the survival panel and *"cannot dodge"* are one fact, the same
single-source rule the sprint already follows.

## Mechanism

### The verb

`Player.dodge()` → bool, bound to `dodge` in `Keybindings`.

- Refuses while on cooldown, while already dodging, while resting, while
  dead, while exhausted — each with its own sentence through the same
  feedback path every other verb uses ([feedback.md](feedback.md)).
- Starts through `Dodge.start_dodge()`, whose two timers `Player` owns and
  ticks with `Dodge.advance` (the module's own stated contract: *"the
  caller owns and ticks the two timers themselves"*).
- The dash reuses the displacement `apply_knockback` already implements —
  an ease-out shove converted to a velocity so `move_and_slide` still
  resolves collision, rather than a position jump that would put a player
  inside a wall — for `Dodge.INVINCIBLE_DURATION` rather than the shove's
  own shorter duration.
- Direction is where the player is *going*, or where they are *facing* when
  standing still. A dodge with no direction would be a hop in place.

### The refusal of a blow

`Player.take_damage` returns immediately while `Dodge.is_invincible`. Not
`take_tick_damage` — pillar 5.

### The key

The keyboard is full: every letter A–Z is bound, and the last verb to
arrive (`rest`) had to take `KEY_PERIOD` for exactly that reason. A combat
verb has to be reachable by the hand already holding WASD, and the three
keys in that reach are taken (`attack` = Space, `block` = Ctrl, `sprint` =
Shift). `dodge` takes **Tab**: free, under the left hand, and not a focus
key in this project, whose UI is built rather than themed.

## Interaction with other docs

- [predator_profiles.md](predator_profiles.md) — the table whose whole
  fairness model is authored against this verb, and which has been
  balanced against a dodge nobody could perform.
- [combat.md](combat.md) — the "twitchy dodge-and-position" pillar.
- [survival.md](survival.md) — stamina is traversal's resource, which is
  exactly why a dodge may spend it and a block may not.
- [feedback.md](feedback.md) — the refusal, the answer, and the fact that
  `take_damage` no longer runs at all during the window, so no `hurt` row
  is raised for a blow that was refused.

## Status

- ✅ **The verb exists, and the module has a caller** (2026-09-21).
  `Player.dodge()` / `dodge_refusal()` / `is_invincible()`, bound to
  `dodge` on Tab, with both timers ticked by their owner through
  `Dodge.advance` — the module's own stated contract. A blow inside the
  window is **refused**, not softened, and raises no receipt either
  because nothing happened to answer for; a tick of venom is untouched,
  because you cannot roll away from what is already in your blood
  (`test_player_dodge.gd`, 21).
- ✅ **Nothing new was chosen** (2026-09-21). `DODGE_DISTANCE_PX` is
  `Dodge.distance_px()` = sprint speed × the invincibility window = 20 px,
  and the two facts that fall out of it are tests rather than remarks:
  it is **1.78 m** at this world's play scale, which is what a real
  evasive dive covers, and it is **longer than `ATTACK_RANGE`** (16 px),
  so a dodge begun inside a bite's reach ends outside it. The stamina cost
  is `SprintCost.stamina_for_seconds` of the same window — exactly the
  sprint it is, never a cheaper way to cross ground — and the exhausted
  gate is `SprintCost.can_sprint`, so *"Exhausted"* on the panel and
  *"cannot dodge"* are one fact.
- ✅ **The dash and the window are one interval** (2026-09-21).
  `apply_knockback` gained a duration so the shove and the roll share a
  single displacement implementation — an ease-out converted to a velocity
  so `move_and_slide` still resolves collision, rather than a position
  jump that would put a rolling character inside a wall.
- ✅ **A refusal keeps its own clock** (2026-09-21), and this verb is what
  found it: `Player._answered_at` was keyed by action id alone, so a
  refusal and a success of the same verb shared one cooldown — and
  pressing dodge again the instant after a roll, the commonest press this
  mechanic will ever see, was muted by the roll that caused it. See
  [feedback.md](feedback.md).
- ⬜ A visual for the roll — the character simply moves.
- ⬜ **The sound.** `dodge_roll` is a commissioning-list id like every
  other sound in the feedback table; no clip exists.
- ⬜ **Nothing to dodge yet.** A bite lands on the frame a creature is in
  range, with no telegraph at all, because `SpeciesBite.windup_seconds_for`
  has no consumer — so today the dodge answers a blow a player cannot see
  coming. That is the next slice, and it is the reason this one came
  first: a telegraph with no dodge is only a delay.
- ⬜ Dodging a *spell* projectile: spells resolve on the target directly
  rather than travelling, so there is nothing yet to roll under.
- ⬜ It does not replicate. `Player._setup_replication` syncs `position`
  alone, so a remote client's roll is local-only — the same bound every
  other combat state in this game has.
