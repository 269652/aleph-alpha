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
- **Birds**: decorative — perch on the player's shoulder or fly nearby.
- **Bears, lions**: dedicated combat pets.
- **Cows**: farmed for milk.
- **Sheep**: farmed for wool.

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

- Full species → role-category mapping, and which fitness stats map to
  which in-role performance metric (guard dog: bite damage + alertness;
  horse: speed + stamina; etc.) — needs a first-pass table.
- Bonding/loyalty mechanic — does a tamed animal's effectiveness also
  depend on an ongoing relationship (time spent, care given), similar to
  [players.md](players.md)'s child needs system, or is taming a one-time
  unlock?
- Respawn cooldown length/location — long enough that losing a pet in a
  fight still matters tactically, short enough that it doesn't feel like a
  soft permadeath in practice.
