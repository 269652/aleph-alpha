## Pets & taming

Wild animals can be tamed with the right skills, ATLAS-style, and accompany
the player. See [classes.md](classes.md)'s Beastmaster archetype for the
dedicated taming/breeding playstyle.

### Species sets category, DNA sets quality

A tamed animal's *role* is fixed by species — a cow will never be a mount,
a dog will never give wool — but its *performance within that role* is
governed by its individual DNA/fitness ([dna.md](dna.md),
[evolution.md](evolution.md)). A high-fitness dog guards and fights
meaningfully better than a common one; a high-fitness horse is faster or
hardier. This gives taming rare individuals a real functional payoff, not
just a cosmetic/trade-value one — the same fitness dimension that makes a
wild animal strong in the ecosystem sim is what makes it good to keep.

Example role categories by species:

- **Dogs**: guard the home, accompany the player, partake in combat.
- **Horses**: mounts. See [transportation.md](transportation.md) for how
  horses fit alongside boats and fast travel.
- **Birds, butterflies, bees**: decorative. These are netted rather than
  lassoed (see [taming.md](taming.md)'s "Any animal, the right tool") and
  have no order AI to learn Follow/Stay — a netted creature stays a kept
  curiosity unless the player has unlocked Beastmaster's `menagerie`
  keystone, which turns it into a real bonded companion instead. Still
  never given an order; the bond is the whole of what changed.
- **Bears, lions**: dedicated combat pets.
- **Cows**: farmed for milk.
- **Sheep**: farmed for wool.

### Fitness → in-role performance: first pass

The first real wiring between [evolution.md](evolution.md)'s
`AnimalFitness` phenotype and a player-facing role. Two mappings exist
today, both keyed off an individual's own `wander_seed` (so the same
individual always scores the same way, across reloads):

| Fitness component | In-role effect | Where |
| --- | --- | --- |
| `fitness_score` (weighted blend of strength/agility/coat_vibrancy) | Mounted speed: `Taming.mounted_speed_for` lerps between 0.8x and 1.2x the `MOUNTED_SPEED` baseline, so the population median (`fitness_score` 0.5) still rides at exactly the old flat speed, and only a genuinely fitter/less-fit individual pulls away from it. | `src/gameplay/taming.gd`, wired from `Player.current_speed` |
| `coat_vibrancy` alone (not the combined score) | A warm coat-quality tint on the creature's own sprite (`CreatureMarker.coat_tint_for`), squared so an ordinary individual reads as visually unmodified and a truly vibrant one clearly stands out — the "judge a prize animal before you buy it" tell, visible on any wild individual, tameable or not, before the player spends a carrot on it. | `src/rendering/creature_marker.gd`, applied in `_ready()` |

Both apply to every land creature with a `wander_seed` — the same
population `AnimalFitness` already covers elsewhere (mate-attractiveness
scoring, kept-animal restore-by-seed) — rather than a species/role-based
carve-out, so there is one population these can miss (creatures with no
`wander_seed`) rather than several role-based edge cases to keep in sync.

Still unmapped: `strength` and `agility` individually don't yet drive
anything beyond feeding into the combined `fitness_score` above — no
guard-dog/combat role exists yet to map, say, bite damage or alertness onto
(dogs aren't tameable at all today; only horses are). The full
species → role-category table below is still open.

### Pet death: respawns, doesn't permakill

Unlike the player's own [nine lives](death.md), a pet that "dies" respawns
after a cooldown (or immediately at home) rather than being lost forever.
Keeps taming/breeding low-stakes-to-experiment-with even though (per
below) building a great bloodline can be a real time investment —
the risk in this system lives in the breeding effort, not in permanently
losing the result of it to one bad fight.

### Captive breeding: one shared model with children and crops

Players can deliberately breed two tamed animals in dedicated breeding
pens, using the **same genetic-cross-plus-mutation model** already used
for [children](players.md) and [crops](farming.md) — one consistent
breeding mechanic across the whole game rather than three separate ones.
This gives the Beastmaster archetype ([classes.md](classes.md)) a real
optimization loop: breed deliberately toward a combat-ideal or
production-ideal bloodline, parallel to how Artisan-leaning players
optimize crop strains. Captive breeding and wild reproduction
([evolution.md](evolution.md)) draw from the same underlying DNA
population, the same relationship [flora.md](flora.md) establishes
between farming and wild plant genetics.

### Open questions

- Full species → role-category mapping beyond horses (guard dog: bite
  damage + alertness; etc.) — mounted speed and coat-quality tint above are
  the first two real entries in what this table becomes, not the whole of
  it. No combat/guard role exists yet for `strength`/`agility` alone to
  drive.
- Bonding/loyalty mechanic — does a tamed animal's effectiveness also
  depend on an ongoing relationship (time spent, care given), similar to
  [players.md](players.md)'s child needs system, or is taming a one-time
  unlock?
- Respawn cooldown length/location — long enough that losing a pet in a
  fight still matters tactically, short enough that it doesn't feel like a
  soft permadeath in practice.
