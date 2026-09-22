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

## A level is a bigger animal

A creature's `level` rolls per individual from its own seed, in
`[1, LEVEL_RANGE]` — variety rather than a distance gradient, which the
journey rings supply by changing *which species* live where. "That one is
bigger" is meant to be a warning.

It was not one. `CreatureInfo` had `LEVEL_HEALTH_SCALE` and **no
counterpart for anything else**, and `CreatureMarker.bite_damage()` read
`info.species` and never `info.level` — so a level-5 wolf carried **twice
the health and the identical 6-damage bite**. A bigger animal was a longer
chore, never a greater danger. That is the "spongier, not deadlier" failure
the reference exchange above exists to avoid, hiding inside the level roll.

Every magnitude axis now grows with the level:

| axis | per level above 1 | note |
|---|---|---|
| `max_health` | `LEVEL_HEALTH_SCALE` 0.25 | unchanged |
| bite damage | `LEVEL_DAMAGE_SCALE` 0.18 | new; derived below |
| the telegraph | *follows the bite* | not a scale — a consequence |
| `max_stamina`, `max_mana` | 0.18 | coherence only; see below |
| speed | **does not scale** | deliberate; see below |

### Why the telegraph is not a third number

`SpeciesBite.required_windup_seconds(bite_damage, player_max_health)`
already derives the tell from **what fraction of your health the bite would
take**: the floor is one `Dodge.INVINCIBLE_DURATION` (see it, roll, the
bite passes through you) rising to a full `Dodge.COOLDOWN_DURATION` for a
bite that would kill outright.

So the moment the bite is asked of the *individual* rather than the
species, a harder-hitting animal is automatically warned about for longer.
This is what makes scaling damage safe rather than cruel, and it is why
this change also has to fix where the telegraph is read from: a level-5
wolf that hit for 10 while telegraphing like one that hits for 6 would be
the cheap shot the whole fairness model was written to forbid.

### Why 0.18, and not 0.25

`SpeciesBite.MINIMUM_TIME_TO_KILL_SECONDS` is the invariant: *however hard
it bites, an animal may not take a full-health player from alive to dead
faster than five seconds* — below that there is no "you are in trouble"
phase to read, only a death.

0.18 is the **largest hundredth** for which every biting species, at every
level it can roll, still needs at least that long. Measured, the binding
species is the **bear**: at 0.19 a level-5 bear kills a reference player in
under five seconds. Every other species has far more room (the wolf would
tolerate 0.85, the jackal 1.00), so the bear alone sets it.

The honest consequence: damage grows *slightly slower* than health (×1.72
against ×2.00 at level 5), so a very large animal is still a little
spongier than it is deadlier. That asymmetry is not a compromise between
tastes — it is exactly where the fairness floor sits, and buying more
danger would mean buying it from a player's ability to read the fight.

Measured end to end, a level-5 encounter costs about **3.4× the health** a
level-1 one does (2.00 × 1.72), where before this it cost **1.0×** — the
same bite, landed over a longer chew.

### What does not scale, and why

**Speed.** `Player.BASE_SPEED` is 40 and `CreatureMarker.HUNT_SPEED` is 36:
a player out-runs a hunting animal, but only just. Scaling pursuit with
level would flip that for large individuals and remove disengagement
entirely — you could no longer choose not to have the fight, which is the
affordance every other fairness rule here is built on top of.

**Stamina and mana** are scaled for coherence — a bigger animal is bigger
on every axis it has — but both are currently read by **nothing** in the
game (`grep` for `info.stamina` and `info.max_mana` returns no consumers).
The scale is therefore inert today. Named here rather than quietly shipped
as though it did something.

**Venom** is not scaled, because `venom_damage` is itself still a dead
column with no runtime reader; scaling it would be a second inert number
layered on the first. It should scale on the day it is wired.

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
- ✅ **Levelling grows every axis** (2026-09-22) — see *A level is a bigger
  animal* below.
- 🚧 **Block is free and invisible.** `is_blocking()` costs nothing — no
  stamina, no cooldown, no readout — and reduces damage weapon-dependently,
  so a player holding the block key experiences a materially longer fight
  than the one this rule pins. The reference exchange is stated **unblocked**
  until block has a cost; that cost wants its own doc in `dodge.md`'s shape.
- ⬜ **The five tactical layers at the top of this file are unbuilt** —
  knockback into hazards, spreadable oil/fire, elevation, vegetation
  line-of-sight, weather. Each needs its own concept doc. Nothing in the
  code reaches toward any of them today.
