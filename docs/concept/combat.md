## Combat

Real-time, top-down, arcade-tactical — **Hammerwatch** as the base feel
(fast movement, cooldown-based abilities, twitchy dodge-and-position combat,
co-op friendly), with a few **Baldur's Gate 3**-flavored tactical layers that
are achievable in 2D:

- Knockback into environmental hazards (fire, water, cliffs/ledges).
- Spreadable environmental effects (oil + fire, grass fires).
- Elevation via layered tilemaps (height advantage, line-of-sight blocking).
- Concealment tied directly into the ecosystem sim — tall/dense vegetation
  breaks line of sight, so a lush biome plays differently than a barren one
  (see [world.md](world.md)).
- Weather as another environmental lever — rain douses fire/oil, fog
  blocks line of sight independent of vegetation (see
  [weather.md](weather.md)).
- Throwables and simple physics-driven interactions (weight/knockback), in
  the spirit of "kill it by dropping/throwing something heavy on it," without
  committing to a full 3D physics-driven combat system at MVP.

Stat/skill/class/equipment systems and PvP/PvE are standard RPG scaffolding
on top of this — not novel on their own, but see [skills.md](skills.md),
[classes.md](classes.md), and [items.md](items.md) for this project's twist
on each.

## The reference exchange

The section above is the *feel* this game is aiming at. It had no numeric
half at all, and for as long as it had none the numbers drifted where
nothing was watching. This is that half: one rule, derived from constants
the game already owns, that says how long a fight must last.

> **An animal that stands and trades must live long enough to land two
> bites.**

Counted the way the animal's own clock runs: it telegraphs, it bites, it
recovers, it telegraphs again — so two windups and one recovery, not two
whole cycles. The recovery after the last bite is time the fight does not
need, and charging for it would demand about a fifth more health than the
rule actually asks.

Two bites, because **a telegraph you see once is a surprise and a telegraph
you see twice is a pattern.** A fight that ends before the second tell
cannot teach the animal that is in it.

The rule binds against the **reference character**: the one the game
actually builds for a new player — `ClassArchetype`'s warrior lens plus
`StarterKit.DEFAULT_CHOICES`. Measured, not assumed: an iron axe is a
*tool*, so `_held_weapon()` returns null and the swing is
`UNARMED_DAMAGE 5 + class 12 = 17`, times the axe-into-flesh multiplier
`0.8` — **13.6 damage on a 0.5 s cooldown, 27.2 dps.**

### What it was before

Every number below was driven out of the real code, not estimated.

| | HP | you kill it | it kills you | ratio |
|---|---|---|---|---|
| wolf | 29 | **1.5 s** | 19.3 s | 11.3× |
| boar | 28 | 1.5 s | 12.9 s | 7.8× |
| jaguar | 34 | 1.5 s | 12.9 s | 6.4× |
| bear | 50 | 2.0 s | 7.1 s | 2.4× |

`Dodge.COOLDOWN_DURATION` is 1.5 s and a bear's rear-up is 0.90 s. So the
telegraph, the windup freeze, the i-frames, the reach asymmetry and the
braced-knockback rule — every mechanic built for this fight — were real,
tested, and **never got a turn**. The fight was over before it started.

### Why health, and why uniformly

The lever is creature health, applied as one uniform scale inside
`CreatureInfo._init`, and both halves of that are deliberate.

**Health rather than player damage**, because `MaterialDamage` makes the
swing load-bearing for chopping trees and breaking stone: tuning combat
through it would retune woodworking.

**Uniform, and at the instance rather than in the table**, because
everything else that reads `max_health` reads it as a *ratio* —
`health_fraction` for fight-or-flight, the health bar, `BossAggro`'s
real-damage threshold, the hit-flash severity — and a uniform scale leaves
every one of them exactly where it was. `Taming`'s
`PREDATOR_BREAK_FREE_MULTIPLIER` is derived from `MAX_HEALTH_BY_SPECIES`
itself, so leaving the *table* untouched leaves that constant untouched
too. A predators-only scale would have moved it, making wild animals harder
to tame for a reason that has nothing to do with taming.

**A longer fight sharpens the species gradient rather than flattening it**,
which is the part worth being explicit about, because "more health" sounds
like "spongier". The creature's dps is unchanged, so doubling the fight's
length doubles the bites that land: the wolf stays a warm-up (22 damage
taken, 15% of the reference character) while the bear becomes a real fight
(103 damage, 71%). The animals the journey rings gate you toward are
exactly the ones that get more dangerous.

### Who it does not bind

Two species are exempt, each by a property the code already owns rather
than by name on a list:

- **The Alp** (`NightMare.presses_instead_of_striking`) never strikes at
  all. Its `windup_seconds` column is fiction, so two of its bite cycles is
  a requirement about something that does not happen.
- **The venomous snake** (`SpeciesBite.VENOMOUS_SPECIES`) is a glass cannon
  whose threat is what it leaves behind, not what it survives. Binding it
  would demand 41 HP of a snake — tougher than a jackal — to protect a
  telegraph nobody is meant to trade blows through.

## Status

- ✅ **The reference exchange is pinned** (2026-09-22) — the rule above,
  `CombatPacing`, and `test_combat_pacing.gd`, which drives the real
  default character against the real roster and asserts every bound species
  satisfies it. `EXCHANGE_HEALTH_SCALE` is **2.5**, the smallest tenth that
  does, and the test pins it from *both* sides: one tenth lower and a bound
  species fails, so the constant is a measurement rather than a preference.
  Measured, the binding species is the **boar** — 2.02 s to land two bites
  on only 28 base health. Every other bound species is satisfied between 1.3
  (curupira) and 1.9 (wolf).
- 🚧 **Levelling still only grows one axis.** `CreatureInfo` has
  `LEVEL_HEALTH_SCALE` and no counterpart for damage, so a level-5 wolf has
  **twice the health and the identical 6-damage bite**. Levels roll per
  individual from a seed (`LEVEL_RANGE` 5), so this is about variety rather
  than the ring gradient — "that one is bigger" should be a warning and is
  currently only a longer chore. Named here rather than silently left.
- 🚧 **Block is free and invisible.** `is_blocking()` costs nothing — no
  stamina, no cooldown, no readout — and reduces damage weapon-dependently,
  so a player holding the block key experiences a materially longer fight
  than the one this rule pins. The reference exchange is stated **unblocked**
  until block has a cost; that cost wants its own doc in `dodge.md`'s shape.
- ⬜ **The five tactical layers at the top of this file are unbuilt** —
  knockback into hazards, spreadable oil/fire, elevation, vegetation
  line-of-sight, weather. Each needs its own concept doc. Nothing in the
  code reaches toward any of them today.
