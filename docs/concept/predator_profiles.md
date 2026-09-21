# Predator profiles — the world's order, enforced by teeth

*Diagnosed 2026-09-20, from a friend's verdict on the built game: you can
stroll anywhere. There is no level wall, no locked gate, and — measured —
nothing else stopping you either, because **every animal in the world is
the same animal**.*

The numbers, read off the code rather than remembered:
`CreatureMarker.ATTACK_DAMAGE` is `6.0` for a mouse-sized fox and for a
300kg bear alike, on one `ATTACK_COOLDOWN` of `0.8`s, from one
`SENSE_RADIUS` of `80.0`px, at one `HUNT_SPEED` of `36.0`px/s — which is
**slower than the player's walk** (`Player.BASE_SPEED`, `40.0`px/s), so
every pursuit in the game today is lost by the pursuer to a player who
simply keeps walking. And `CreatureBehavior.STRONG_HEALTH_FRACTION` is
`0.5` for all of them, so whatever does connect breaks off at half health.
A bear, a wolf, a boar and a jackal are four sprites over one stat block.

[ecosystem_dynamics.md](ecosystem_dynamics.md#region-difficulty-gating-the-roster-by-player-readiness)
already decides *where* the dangerous species are allowed to exist: bear,
lion and venomous snake are gated to `RegionDifficulty.Tier.HARD`, far
from spawn. That gate is currently a **casting decision with no
consequence** — a HARD-gated bear bites for exactly what an EASY jackal
bites for. This doc gives the gate its teeth: the tier a species is gated
to must be legible in what the animal *does to you*, not only in where it
is found.

## Design pillars

1. **The world's order is enforced by teeth, not by a level wall.** Nothing
   refuses the player entry to a far region; the animals there simply hurt
   more, chase further and do not give up. Walking a long way must feel
   like walking into deeper water, and the only fence is the one made of
   what lives there.
2. **The gradient is a property of the table, not of good intentions.** A
   species gated to a harder tier is *provably* more dangerous — by a
   single derived threat score — than anything the easier tier can show
   you, with a real margin. A future species that breaks the ordering
   fails a test rather than quietly flattening the world.
3. **Lethal is allowed; cheap is not.** Fairness is structural: a bite that
   can take a larger slice of the player's health carries a proportionally
   longer **windup**, the telegraph before it lands. A bear may take a
   quarter of you in one swing precisely *because* it rears up first. The
   rule is a pure function of the damage and the player's own live max
   health, so a frail character is warned more, not less.
4. **A chase is a decision, not a formality.** An animal releases you
   further out than it sensed you (the Schmitt trigger
   `CreatureMarker.FLEE_RELEASE_RADIUS`/`SENSE_RADIUS` already uses for
   fleeing, reused for pursuit), so backing off one step never breaks a
   chase. You escape by *committing* to escape.
5. **Real mass, real speed, one derivation each.** Bite damage and bite
   rate are derived from the species' real body mass
   (`CreatureMass._REAL_MASS_KG` — already in the repo, already cited);
   pursuit speed is derived from its real top speed. Nothing in the table
   is an eyeballed per-species number: the authored columns are real
   references (kg, km/h) and four design columns (windup, sense, tenacity,
   and which species bite at all), each constrained by a test.
6. **Today's animal is the fallback, so nothing regresses.** A species with
   no row — a world boss, an easter-egg cameo — gets a profile built from
   the engine's *current* constants (6.0 damage, 0.8s cooldown, 5 tiles of
   sense, 7.5 tiles of release, 2.25 tiles/s of pursuit, 0.5 tenacity). The
   one number the fallback does not copy from today's engine is the
   windup, because today's engine has no windup at all. That absence is
   the bug this module exists to fix. An animal with no bite at all is
   owed no telegraph either: `required_windup_seconds(0, ...)` is zero,
   not the base window.

## Real-world grounding

**Bite force follows cross-section, not weight.** Muscle force scales with
the cross-sectional area of the muscle, which scales as the square of a
linear dimension, which scales as mass^(2/3). This is the same physical
reasoning `CreatureMass` already uses in the other direction
(`linear_scale_for_mass_ratio`, mass^(1/3), for footprint size). So a
300kg bear does not bite for seven and a half times a 40kg wolf; it bites
for 7.5^(2/3) ≈ 3.8 times as much. That single exponent is why a bear is
frightening without being a one-shot, and why a 3.5kg arctic fox is an
irritation rather than a threat.

**Big jaws close slowly.** Limb and jaw cycle time scales with the square
root of a linear dimension (a pendulum's period, the standard allometric
approximation for gait and chewing frequency) — mass^(1/6). A bear's bite
lands every 1.12s where a viper's strike recovers in 0.57s.

**Top speeds are real, compressed onto one playable band.** Every pursuit
speed comes from that species' commonly-cited top speed in km/h — grass
snake 9, house mouse 13, squirrel 20, wild boar 40, arctic fox and gray
wolf 50, golden jackal and brown bear 56 ("you cannot outrun a bear"),
deer 60, lynx and jaguar 64-65, horse 70, reindeer 78, cougar and lion 80.
Used literally, a lion would cross the screen at 15 tiles/s and the game
would be unplayable, so the real *order* is kept and the real *range* is
linearly compressed onto a band anchored to the player's own two speeds
(below). The ordering in the world is therefore the ordering in nature.

**Why an animal breaks off.** A solitary cat that is injured cannot hunt,
and a lost hunt is starvation — so lynx, jaguar and cougar are risk-averse
and quit at 40% health. A brown bear has almost nothing that can make it
quit (10%). A viper cannot flee anything, so the strike *is* its defence
and it stands until nearly dead (15%). A jackal is a scavenger that lives
by not fighting (45%), and the 3.5kg arctic fox quits earliest of all
(50% — exactly today's universal `STRONG_HEALTH_FRACTION`, which survives
in this table as the behaviour of the roster's *most* cowardly predator
rather than as everyone's rule).

## Mechanism

`src/gameplay/species_bite.gd` — a pure `RefCounted` with static functions,
no scene tree, no world, no singletons, in the spirit of
[errands.md](errands.md)'s `ErrandDelivery` and `spell_cost.gd`. It is a
lookup table plus the handful of pure rules that generate and constrain it.
The wiring into `CreatureMarker` is a separate change; this module decides
nothing about frames.

### One row per species

`SpeciesBite.profile_for(species)` returns:

| key | meaning |
| --- | --- |
| `bite_damage` | damage a single bite lands, derived from real mass |
| `venom_damage` | delayed damage that bite is worth (`VenomModel`), 0 for everything but the viper |
| `bite_cooldown_seconds` | recovery before the next bite, derived from real mass |
| `windup_seconds` | the telegraph before the bite lands |
| `sense_radius_tiles` | how far it notices the player |
| `pursuit_speed_tiles_per_second` | how fast it moves when it has a reason to — for a grazer, how fast it *flees*, which is also whether you can catch it |
| `release_distance_tiles` | how far you must get before it gives up |
| `tenacity` | the health fraction at or below which it breaks off |

### The derived columns

- `bite_damage_for(species)` = `REFERENCE_BITE_DAMAGE` × (mass / wolf mass)^(2/3),
  and zero for any species whose `CreatureInfo` temperament is not
  `"aggressive"` — the roster's existing single source of truth for who
  fights at all. `REFERENCE_BITE_DAMAGE` is `6.0`: today's universal
  `ATTACK_DAMAGE`, kept as the **wolf's** bite, so this table re-scales the
  roster around the number the game already shipped instead of inflating
  it. The wolf is the one animal whose bite is unchanged by this doc.
- `bite_cooldown_seconds_for(species)` = `REFERENCE_BITE_COOLDOWN` ×
  (mass / wolf mass)^(1/6), with `REFERENCE_BITE_COOLDOWN` = `0.8`, today's
  universal `ATTACK_COOLDOWN`, again at the wolf.
- `pursuit_speed_for_real_top_speed(kmh)` linearly maps the roster's real
  speed range (9-80 km/h) onto `[SLOWEST_PURSUIT, FASTEST_PURSUIT]` =
  `[walk × 0.8, sprint × 1.1]` = `[2.0, 5.5]` tiles/s. Both anchors are
  read from `Player.BASE_SPEED`/`SPRINT_SPEED` over
  `TerrainRenderer.TILE_SIZE` (40 and 80 px/s over 16 px = 2.5 and 5.0
  tiles/s) and pinned against them by test. The band states the two design
  facts directly: **the slowest animal in the world is comfortably
  outwalked, and the fastest cannot be outsprinted.**
- `release_distance_tiles_for(sense)` = `sense` × `RELEASE_DISTANCE_RATIO`
  (1.5) = `FLEE_RELEASE_RADIUS` / `SENSE_RADIUS`, the engine's own existing
  Schmitt-trigger ratio for fleeing, now also the ratio for pursuit —
  floored at `sense` + `MIN_RELEASE_HYSTERESIS_TILES` (one whole tile), so
  a close-range ambusher nobody has authored yet still opens a real gap
  rather than releasing half a tile out. The floor is a rule, not a
  property of the radii that happen to be authored today.

### Fairness is a function, and it binds at runtime

```
required_windup_seconds(bite_damage, player_max_health) =
    BASE_WINDUP_SECONDS
  + max(0, bite_damage / player_max_health - FAIR_BITE_HEALTH_FRACTION)
    × WINDUP_SECONDS_PER_HEALTH_FRACTION
```

Two anchors, both derived from the game's own dodge:

- `BASE_WINDUP_SECONDS` = `Dodge.INVINCIBLE_DURATION` (0.25s). The smallest
  telegraph in the world is exactly as long as the invulnerability window
  the player's own dodge grants: seeing the tell and dodging on the frame
  it starts covers the whole bite.
- A bite that would kill a full-health player outright requires
  `LETHAL_WINDUP_SECONDS` = `Dodge.COOLDOWN_DURATION` (1.5s) — a player who
  has *just* dodged something else must never be killed by a bite they
  could not possibly have avoided.
- `FAIR_BITE_HEALTH_FRACTION` (0.06) is the slice today's universal 6.0
  bite takes from the player's 100 max health: a bite no worse than the one
  the game already ships needs no more than the base telegraph.
- `WINDUP_SECONDS_PER_HEALTH_FRACTION` is whatever slope joins those two
  anchors — it is computed, never authored.

The per-species `windup_seconds` column is **authored independently** (a
bear rears up, a viper strikes in a blink) and every row is asserted to
clear its own requirement, so the test is a real constraint on real data
rather than a restatement of a formula. Callers ask for
`windup_seconds_for(species, player_max_health)`, which returns the larger
of the two — so a 20-HP character faces a *longer* bear windup than a
100-HP one, automatically, and fairness holds for a character build this
table has never seen.

### The threat score, and the gradient it enforces

```
sustained_damage_per_second = (bite_damage + venom_damage) / (windup + cooldown)
threat_score                = sustained_damage_per_second
                              × (1 - tenacity)      # how much of itself it will spend
                              × pursuit_speed_tiles_per_second
```

Three things make an animal dangerous and all three are in it: how fast it
takes your health, how long it keeps taking it, and whether you can leave.
It is a *ranking* device, not a damage simulation. The resulting order, with
the gated species in bold:

| species | dmg | cooldown | windup | sense | pursuit | tenacity | threat |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **bear** | 22.99 | 1.12 | 0.90 | 10 | 4.32 | 0.10 | **44.2** |
| **lion** | 16.35 | 1.03 | 0.60 | 9 | 5.50 | 0.20 | **44.2** |
| **venomous snake** | 1.50 (+12 venom) | 0.57 | 0.25 | 3 | 2.10 | 0.15 | **29.5** |
| jaguar | 10.30 | 0.92 | 0.45 | 6 | 4.76 | 0.40 | 21.5 |
| cougar | 7.86 | 0.86 | 0.45 | 6 | 5.50 | 0.40 | 19.9 |
| boar | 10.30 | 0.92 | 0.55 | 7 | 3.53 | 0.30 | 17.4 |
| wolf | 6.00 | 0.80 | 0.40 | 9 | 4.02 | 0.25 | 15.1 |
| lynx | 3.52 | 0.70 | 0.35 | 6 | 4.71 | 0.40 | 9.5 |
| jackal | 2.38 | 0.63 | 0.30 | 8 | 4.32 | 0.45 | 6.1 |
| arctic fox | 1.18 | 0.53 | 0.30 | 7 | 4.02 | 0.50 | 2.9 |
| every grazer | 0 | — | — | 3-9 | 2.0-5.4 | 1.00 | 0 |

The three HARD-gated species hold the top three places, and the gap between
the *least* dangerous gated species and the *most* dangerous ungated one is
a factor of 1.37 — above `TIER_THREAT_MARGIN` (1.25), asserted, so a harder
region is never *marginally* harder. The viper earns its place with venom
rather than pursuit: it is the one dangerous animal in the world you can
walk away from, and the one that kills you fastest if you do not.

### What this does to the eight requirements

Requirement 3 — *not being able to stroll to the final boss* — is answered
here without a single gate. Distance alone stops saving you: a lion, a
cougar, a jaguar, a horse and a reindeer are all faster than a full sprint,
so you leave a fight by *deciding* to (terrain, a door, a fight won), not
by holding a key. And the fastest thing that wants to eat you lives where
the gate put it.

Stakes (the brief's "nothing is at stake"), measured as seconds from full
health to dead while an animal stays on you: today, uniformly 13.3s. Under
this table: 6.0s for a viper, 8.8s for a bear, 10.0s for a lion, 13.3s for
a jaguar — and never below `MINIMUM_TIME_TO_KILL_SECONDS` (5.0s), asserted
over the whole table, so there is always time to be visibly in trouble
before dying.

## Status

- ✅ `SpeciesBite` pure profile table: every species in the real spawn
  pools (21) has a row, two-way drift-tested against
  `CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME`/
  `PREDATOR_SPECIES_POOL_BY_BIOME` and the generic fallback pools.
- ✅ Damage and bite rate derived from `CreatureMass`'s real masses;
  pursuit speed derived from real top speeds, compressed onto a band
  pinned against `Player.BASE_SPEED`/`SPRINT_SPEED`.
- ✅ `required_windup_seconds` / `windup_seconds_for`: fairness as a
  function of live player max health, asserted for every row.
- ✅ Monotone tier gradient asserted over the real rosters with a 1.25×
  margin; `release > sense` and a full tile of hysteresis asserted per row.
- ✅ 48 tests in `tests/unit/test_species_bite.gd`, mutation-checked:
  flattening the bear's tenacity back to 0.5, shortening its windup,
  slowing the lion to a boar's pace, dropping a species from the table,
  and collapsing bite damage back to a flat 6.0 each fail at least two
  tests.
- 🚧 **Wiring, partly.** `CreatureMarker.bite_damage()` and
  `bite_cooldown_seconds()` read this table now, and `pursuit_speed_tiles_
  per_second` reaches `hunt_speed()`. Measured 2026-09-21, four columns are
  still dead: **`windup_seconds`** (no telegraph exists — see below),
  **`tenacity`** (`CreatureBehavior` still reads one shared
  `STRONG_HEALTH_FRACTION`), **`release_distance_tiles`**, and
  **`venom_damage`**. `sense_radius_tiles` is read by the player and by
  `/arena`, never by the creature that owns it — a creature still senses at
  one flat `SENSE_RADIUS`, so a bear's authored ten-tile nose changes
  nothing about when the bear notices you.
- ✅ **The dodge these numbers are authored against now exists**
  (2026-09-21) — see [dodge.md](dodge.md). Until then this whole fairness
  model rested on a verb the player could not perform: `Dodge` was a
  complete, tested module with zero consumers outside this file's reading
  of two of its constants, and `grep -rn "invulner\|invincib\|iframe"
  scenes/player.gd` returned one comment.
- ⬜ The windup needs an animation/telegraph to be *seen* — a profile that
  says 0.9s of rear-up is only fair once the player can watch it happen
  (see [combat.md](combat.md)'s Hammerwatch-style read-and-react feel).
  With the dodge built and the telegraph not, the player has the answer
  and no question: a bite still lands on the frame a creature is in range.
- ⬜ Venom is counted in the threat score at one stack's full duration;
  `VenomModel.MAX_STACKS` (3) stacking behaviour is the live model's, not
  re-derived here.
