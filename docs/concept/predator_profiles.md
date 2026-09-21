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

### The telegraph, in the engine

The windup column was authored, fairness-tested and **completely dead**:
`grep -rn windup` outside `species_bite.gd` returned two comments. A bite
landed on the frame a creature crossed `ATTACK_RANGE`, which is why the
fairness model above was arithmetic about a thing that never happened.

Five decisions, each forced by arithmetic rather than chosen.

**1. The creature freezes while it winds up.** Measured across the twelve
biting profiles: if it keeps closing at its own pursuit speed, the dodge
fails for ten of them — a lion closes 52.8 px during its 0.60 s windup, a
bear 62.2 px during its 0.90 s, against a dodge worth 20 px. The tolerance
for *any* residual closing is under about `4 / W` px per second (a wolf
under 10, a bear under 4.4), which is frozen in all but name. Frozen, the
gap at resolve is `R + 20 > 16` for every commit range including zero, so
the dodge always clears. It is also the right picture: an animal plants
itself to strike.

The guard lives at the single movement choke point (`_advance_gated`)
rather than in the `"attack"` arm, and that is a measured correction:
`_will_fight` needs half health, so a bear damaged past that mid-windup
flips its decision to *flee* — and a committed creature whose decision
flipped was free to walk away from its own bite. The jaws then closed on
ground it had left itself.

**2. The bite re-checks reach when the clock runs out.** Without it the 20
px is worth nothing and the windup is a *delayed guaranteed hit* whose only
counter is the invincibility boolean — and that window is always exactly
`[W − 0.25, W]`, so a player who reacts on the first frame of the tell is
invincible from 0.00 to 0.25 s and bitten at 0.48 s. The re-check is what
turns "wait, then press a quarter second before the jaws close" back into
"see it and go".

**3. The windup lengthens the cycle; it does not hide inside the
cooldown.** `SpeciesBite.damage_per_second` already computes
`cycle = windup + bite_cooldown`, and `test_species_bite.gd` asserts every
row clears `MINIMUM_TIME_TO_KILL_SECONDS`. Nesting the windup inside the
existing recovery would silently break that floor for the bear and the
viper. So: **commit → wind up → bite → cooldown**, and the cooldown starts
at the bite.

**4. A commitment is not interrupted — only missed.** The clock is ticked
beside the bite cooldown, above every early return, so it keeps running
through a shove, a root or a lost target. Being hit deliberately does
**not** cancel it: the player's own swing is on a 0.5 s cooldown, shorter
than eleven of the twelve windups, so an interrupt would make every heavy
predator unbiteable again — the exact unloseable fight this overhaul just
finished removing. Two consequences are stated here rather than discovered:
a creature **rooted** mid-commitment still finishes its bite (what a root
takes away is its footing, and a held animal still snaps at what is in
front of it — a behavioural change for that spell, which used to prevent
the bite outright), and a creature **killed** mid-commitment drops the
clock and the pose together, so it cannot stay reared over its own corpse.

**5. A planted animal is braced, and that is the whole reason the freeze is
safe.** Found by running the exchange rather than by reasoning about it:
the moment the windup landed, the "a player who only swings does not beat a
bear for free" test went green to red. A frozen creature cannot close again
either, so *any* shove during a windup made the bite whiff — a bear is
shoved 8 px per swing and winds up for 0.90 s, during which a 0.5 s swing
lands twice. Sixteen pixels, and the jaws close on nothing for ever. So
knockback does not move a committed creature. The asymmetry **is** the
design: moving yourself out of reach answers a bite; shoving the animal
does not. Being struck still hurts it and still makes it angry — only its
footing is unmoved.

### The tell itself

No art exists for it and none can be borrowed: the complete creature action
vocabulary is walk / idle / attack / eat / drink / swim, and for every
illustrated species `"attack"` already falls back to the **walk** row, so
an attacking boar is pixel-identical to a walking one.

So the tell is drawn in code, like the hit flash — and it is a **rear-up**,
not a colour. `BiteTell.scale_multiplier` grows the body as the strike
nears, taller than it is wider, and it is folded into
`CreatureMarker._apply_action_scale`'s own formula rather than written onto
`scale` from outside (which is reverted within one stepped frame, and would
desync the creature from its own shadow).

**Colour was considered and rejected**, with the reason written down rather
than rediscovered: a `CreatureMarker` *is* its `Sprite2D`, and that one
24-pixel body already carries three meanings in `modulate` — warm-brighter
is a good coat (`coat_tint_for`), pale green is sick
(`SICK_MODULATE_COLOR`), and red is *just hit* (`HitFlash`). A fourth would
make the body say everything and therefore nothing, and the obvious hue for
"about to hurt you" is the one already spoken for by "you just hurt it".
The freeze is itself half the tell: an animal that has been charging you
and suddenly plants is very readable.

### What the telegraph does not fix, stated rather than discovered

- **A player cannot dodge every bite.** `Dodge.COOLDOWN_DURATION` (1.5 s)
  is longer than the full `windup + cooldown` cycle of ten of the twelve
  biters — a wolf's is 1.20 s, a lynx's 1.05 s. Against those the dodge
  answers every *other* bite and the rest is the block's job. Only the bear
  (2.02 s) and the lion (1.63 s) can be answered every time, which is the
  right way round: the heaviest blows are the ones you must be able to
  refuse.
- **A dodge is a heading, not an evasion.** `Player.dodge` rolls along
  `facing_direction()`, the last real travel heading — so a player who has
  just walked *into* a bear rolls into it and closes the gap. That is a
  skill, not a bug, but it means "the dodge always clears" is a claim about
  dodging *away*.
- **A creature rooted mid-strike holds its pose.** `is_rooted()`'s early
  return skips `_animation_step`, so the rear-up stops *building* while the
  clock keeps running. The bite still lands and the animal is still visibly
  reared; only the last part of the beat is frozen. Cosmetic, and named.
- **A distant bite is untelegraphed.** Beyond `SimulationLod`'s
  `FULL_RATE_RADIUS_PX` one step can advance nearly half a second, so a
  windup can start and resolve inside a single call with no tell drawn. A
  creature biting *you* is by definition inside 16 px and therefore at full
  rate — but `_nearest_player_position` returns the first player in the
  group rather than the nearest, so in multiplayer a creature biting the
  far player is throttled and its tell is invisible to them.

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
- ✅ **The telegraph is wired** (2026-09-21) — see "The telegraph, in the
  engine" above. `windup_seconds_for(species, the target's own live max
  health)` is read the moment a creature commits, the creature plants
  itself, and the jaws re-check reach when the clock runs out. Until then
  `windup_seconds` was a fairness-tested column with no runtime consumer at
  all, so the whole fairness model above was arithmetic about something
  that never happened.
- 🚧 **Wiring, partly.** `bite_damage`, `bite_cooldown_seconds`,
  `windup_seconds` and `pursuit_speed_tiles_per_second` all reach the live
  game now. Three columns are still dead: **`tenacity`**
  (`CreatureBehavior` reads one shared `STRONG_HEALTH_FRACTION`),
  **`release_distance_tiles`** and **`venom_damage`**. And
  `sense_radius_tiles` is read by the player and by `/arena`, never by the
  creature that owns it — a creature still senses at one flat
  `SENSE_RADIUS`, so a bear's authored ten-tile nose changes nothing about
  when the bear notices you.
- ✅ **The dodge these numbers are authored against now exists**
  (2026-09-21) — see [dodge.md](dodge.md). Until then this whole fairness
  model rested on a verb the player could not perform: `Dodge` was a
  complete, tested module with zero consumers outside this file's reading
  of two of its constants, and `grep -rn "invulner\|invincib\|iframe"
  scenes/player.gd` returned one comment.
- 🚧 The windup is *seen* as a code-drawn rear-up (`BiteTell`), not as
  animation. No rear-up frame exists to play and none can be borrowed: the
  whole creature action vocabulary is walk / idle / attack / eat / drink /
  swim, and for illustrated species `"attack"` already falls back to the
  walk row, so an attacking boar is pixel-identical to a walking one. Real
  art for a gathering strike is still owed (see [combat.md](combat.md)'s
  Hammerwatch-style read-and-react feel).
- ⬜ Venom is counted in the threat score at one stack's full duration;
  `VenomModel.MAX_STACKS` (3) stacking behaviour is the live model's, not
  re-derived here.
