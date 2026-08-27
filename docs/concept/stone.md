# Loose stone

Boulders, cobbles and pebbles: the stone lying *on* the ground, as opposed to
the ore locked inside it (see `materials.md` for what stone is as a material,
and `crafting.md` for what it becomes).

## Design pillars

**If you can lift it, you take it. If you can't, you break it.** The divide
between picking a stone up and smashing it is a physical question about the
stone, not a tag on it. A pebble goes in your hand; a boulder has to be broken
into pieces you *can* carry. Nothing else decides it -- not the tool you hold,
not a quest flag. This is the pillar the whole system hangs from, because it
means a player can look at a rock and know what to do with it.

**Stone comes in every size, and small stone is everywhere.** A world where
every rock is one standard boulder reads as a world made of props. Real ground
is mostly small stone with the occasional large one, and that distribution is
what makes a landscape feel eroded rather than placed. This is also why a
pebble isn't always a single lone rock: real loose stone clusters as often as
it scatters, so a pebble-class cell sometimes turns out to be a FLOCK of
several pebbles sitting together rather than one.

**Size is worth something.** A bigger boulder is more work and more reward.
If size were cosmetic, the variety would be noise; a player who chooses the
big one should be making a real trade of time for material.

## Real-world grounding

Sizes follow the **Wentworth grain-size scale**, the standard geological
classification, rather than invented tiers:

| class | diameter | in hand |
|---|---|---|
| granule | 2–4mm | too small to bother with |
| **pebble** | 4–64mm | picked up in one hand |
| **cobble** | 64–256mm | picked up, two hands for a big one |
| **boulder** | above 256mm | must be broken |

The lift/smash line falls at the cobble–boulder boundary, 256mm, because that
is roughly where a rock stops being liftable -- which is exactly why geologists
put a boundary there. The game rule and the real classification agree because
they are answering the same question.

Sizes are read against the PLAYER, as everything else in this world is (see
`flora.md`, where flowers are pinned to the player's hip). A 2m boulder stands a
head above the player -- because it is two metres and a person is not, the
yardstick being applied honestly rather than rounded off; a pebble is a couple
of pixels. Small stone is exaggerated
toward legibility exactly as small flowers are -- a true-scale 1cm pebble would
be invisible -- and the exaggeration never reorders the classes.

Frequency follows the same power law real scree does: small stone vastly
outnumbers large. A field is mostly pebbles, with cobbles scattered through it
and a boulder as a landmark.

Mass follows from size the same honest way: a stone is treated as a sphere of
its own diameter, and granite's real density (2.7 g/cm³) gives it a real mass
in kilograms -- a few grams for the smallest pebble, several tonnes for the
largest boulder. That real mass is what a "kicks a pebble far, but not a
cobble" rule needs to mean something: the cutoff is a real anthropometric
reference (a human leg is roughly 16-17% of body mass), not an arbitrary
"pebbles yes, cobbles no" flag, and it happens to land almost exactly where a
cobble's own size range does -- a cobble at the very top of its range already
outweighs a leg.

**Pebbles flock; cobbles and boulders stay solitary.** Real gravel piles up in
loose clusters wherever water or slope gathers it, and reads as scree exactly
because it isn't spaced out like placed props. A boulder is explicitly a
scattered LANDMARK (see `StonePlacement`'s own doc comment: "boulders are
scattered landmarks, not ground cover") and stays one, never clustering. A
cobble is already a large enough visual event standing alone -- several
cobbles clustered at their bigger drawn size reads as clutter, where the same
clustering at pebble scale reads as a natural scatter of gravel -- so only
pebbles flock, for now.

A flock is a handful of pebbles (2 to 5) at one cell instead of the usual one,
positioned with a small jitter so they don't stack identically, each one its
OWN independently-seeded pebble -- its own size, its own shape, its own
yield -- rather than one entity with an invented "handful" yield. That keeps
the economy exactly what it already is for every other seeded pickup in this
game: you're not collecting from "a flock", you're collecting several real
pebbles that happen to sit together. Not every pebble flocks -- a lone pebble
is still the commoner sight -- but it's a regular occurrence, not a rarity.

## Mechanism

**Picking up.** E is now CONTEXTUAL. Empty-handed and near a liftable stone,
E takes the nearest one into the HAND -- a new held-item concept distinct
from both inventory and the worn "weapon" equipment slot -- rather than
sweeping it straight into inventory. Empty-handed with no stone nearby, E
still does the ordinary ground-item sweep exactly as before (any other
dropped item -- food, wood, hide -- goes straight to inventory, no swing, no
tool, no cooldown). Standing near a pebble or cobble (but not a boulder,
which can't be picked up) shows a "Pick (E)" prompt above it, the same
on-screen convention used for talking to a villager; if both an NPC and a
stone are in range at once, the talk prompt wins, since talking is the
rarer, more deliberate action and a pebble on the ground isn't going
anywhere. The prompt hides itself while the hand is already full, since E no
longer sweeps in that state (see "Held-item throw" below).

Because a hand holds only one stone at a time, this is a deliberate change
from the old behaviour where walking up to a whole pebble flock and pressing
E collected every member in one sweep: today's first press takes the
nearest single stone into the hand, and the rest wait for another visit
once the hand is free again.

**Kick.** Bound to K (`toggle_skills` moved to L to make room). Delivers a
real one-time momentum -- the "leg" (`StoneSize.LEG_MASS_KG`) swung at a
brisk, deliberate speed (`Kick.KICK_SPEED_MPS`) -- to the nearest kickable
PHYSICAL OBJECT in reach, through the SAME momentum model (`momentum = mass
* velocity`) `impact_resolver.gd`/`throwable.gd` already use for combat and
throwing (see `materials.md`'s "one damage model for the whole world"). How
far it flies scales with that momentum against its OWN mass
(`Kick.kick_distance_px`, real sliding kinematics under kinetic friction) --
a heavier object moves less for the same kick, exactly `Throwable.
impact_knockback`'s own reasoning. Something at or above leg mass simply
doesn't move at all: too heavy for a kick's delivered momentum to matter.
Since a cobble at the top of its size range already outweighs a leg, this
single mass cutoff naturally limits kicking to pebbles (and the lightest
cobbles) with no separate per-class check needed.

`Kick`'s own math was always generic (mass in, distance/landing position
out -- nothing about it named "stone"); only `Player._kick_step`'s target
search was stone-only. It now also checks the nearest `DroppedItem` with a
real, modeled mass (`Item.mass_kg > 0.0`, most items still sit at the
"not modeled" 0.0), kicking whichever candidate -- stone or dropped item --
is genuinely closer, so a pulled wild carrot/potato
(`docs/concept/wild_crops.md`) is kickable the same way a pebble is. This
extends to the held-item pickup/charge/throw mechanism below too (see that
section's own update) -- both halves of "a real physical object" now cover
the same set: a liftable stone, or a dropped item with a real, modeled
mass.

**Held-item pickup, throw, and stash.** E's pickup-into-hand is likewise no
longer stone-only (reported live: "pick up should put it in the hand first
instead of the inventory"): empty-handed near a liftable stone, E still
picks it into the hand first; failing that, empty-handed near a dropped
item with a real, kickable-grade mass, E picks THAT into the hand instead
(`Player._try_pick_item_into_hand`) -- an item with no modeled mass (most
food/material drops) is left alone, still going straight to inventory via
the ordinary sweep exactly as before. With a stone OR an item already in
hand, pressing and HOLDING E starts a charge: a "strengthometer" bar above
the player's own head bounces back and forth between empty and full
repeatedly while held (`ChargeMeter` -- a classic charge-meter minigame,
not a bar that simply fills), so release power depends on exact timing,
not just how long E was held. Releasing E throws whatever's in hand with
power set by wherever the meter was at that instant
(`HeldItemThrow.release_speed_mps`), feeding the SAME shared momentum model
as Kick: release speed x the held object's real mass is its impact momentum
against whatever it lands near (`ImpactResolver.resolve_impact`,
`MeleeAttack.knockback_vector`), and its flight distance follows the same
real sliding kinematics Kick uses. It reappears in the world at its
landing spot whether or not it struck anything on the way -- a stone as a
`LiftableStone` exactly as before, a generic item as an ordinary
`DroppedItem`.

A NEW key (default H, "Stash Held Item") is the deliberate complement:
puts whatever's in hand away into the inventory instead of throwing it --
a stone converts to rock (the same conversion `LiftableStone.pick_up`
already does on an ordinary ground pickup), a generic item goes in as
itself. Unlike the ordinary ground-pickup path (which silently discards
whatever doesn't fit), stashing never loses anything: an inventory too
full to take it all drops the remainder as a real ground item at the
player's own feet, since this is a deliberate player action, not an
incidental walk-up collect.

**Dispersion.** Walking close enough to a loose stone rolls a MASS-WEIGHTED
CHANCE, fresh on every contact, of kicking it a small distance further out of
the way -- like real kicked gravel, a nudge that happens stays wherever it
lands rather than settling back, but a stone is never "used up" after one
kick: every later contact rolls again, so it can keep drifting further
across many walkovers. Lighter stones roll a much better chance per contact
than heavier ones -- an incidental footstep reliably disturbs a light pebble
but only occasionally nudges a heavy cobble, the same momentum-vs-own-mass
logic as a deliberate Kick, just at footstep scale (see PebbleDispersion).
Applies to any liftable stone underfoot, not just flock members.

**Illustrated art.** Loose stone increasingly draws from hand/AI-illustrated
variant sheets (several differently-shaped, differently-sized stones drawn
side by side) rather than a single procedurally generated shape, the same
"sheet sliced into cached frames, picked per-instance by a seed" approach
already used for flowers and animals. Pebbles, cobbles, and boulders each
draw from their own 20-variant sheet (a 4-row x 5-column grid, rows
increasing in size/complexity top-to-bottom) -- every real stone class has
real illustrated art today. Any FUTURE class with no sheet yet falls back to
the procedural generator (see IllustratedStoneSprite's class doc comment),
so nothing is ever left undrawn while art is still being produced for it.

**Smashing.** A boulder takes repeated strikes, and how many scales with its
size: a small boulder is a couple of hits, a large one is real work. Each
strike shows progress, and the boulder breaks apart on the last one, yielding
rock in proportion to its size.

This replaces a one-hit boulder that always yielded exactly one rock,
regardless of the fact that it was drawn as a rock the size of a person.

**Knapping is unchanged.** Striking a boulder while carrying a rock can still
split off sharp shards (see `Knapping`) -- the start of the primitive tool
chain. Shards come from the striking, so they come from boulders only; a pebble
picked up off the ground was never struck.

## Status

- ✅ Wentworth size classes, with the lift/smash line at the cobble–boulder
  boundary
- ✅ Continuous per-stone diameter, power-law distributed so small stone
  dominates
- ✅ Boulder hit counts and rock yields scaling with size
- ✅ Pebbles and cobbles taken by E -- into the hand if empty-handed and a
  stone is nearby, otherwise the ordinary ground-item sweep (see the
  "Held-item pickup + charge/release throw" entry below for the full
  contextual behaviour)
- ✅ Pebble flocks: a pebble-class cell sometimes spawns 2–5 independently-
  seeded pebbles instead of one, jittered so they don't overlap. Cobbles and
  boulders never flock.
- ✅ Illustrated pebble, cobble, AND boulder art (20 hand/AI-illustrated
  variants each, sliced from a 4x5 grid sheet) -- every real stone class has
  its own art; the procedural generator remains the fallback for any future
  class with no sheet yet
- ✅ Pebble dispersion: walking onto a loose stone rolls a mass-weighted
  chance, fresh on every contact, of kicking it a small distance further out
  of the way -- lighter stones roll a much better chance than heavier ones,
  and a stone can keep drifting across many walkovers rather than being
  "used up" after one kick. Player-only for now -- not wired to creatures, to
  avoid an O(creatures × nearby stones) scan every frame nothing currently
  needs.
- ✅ Real per-stone mass (`StoneSize.mass_kg_for`, granite density x sphere
  volume), feeding the same momentum model the rest of combat/throwing uses
  (see `materials.md`) -- what pebble dispersion's mass-weighting and the
  Kick action's leg-mass cutoff both read from.
- ✅ Kick (K): a real one-time momentum sends the nearest reachable
  kickable object -- a liftable stone, or a dropped item with a real
  modeled mass, whichever is closer -- flying a mass-scaled distance;
  anything at or above leg mass doesn't move at all. `toggle_skills` moved
  from K to L to make room.
- ✅ Held-item pickup + charge/release throw + stash: E is contextual --
  empty-handed near a stone it picks into the HAND (a new concept distinct
  from inventory and the worn weapon slot); failing that, empty-handed
  near a dropped item with a real, kickable-grade mass, it picks THAT into
  the hand instead (an item with no modeled mass keeps going straight to
  inventory, unchanged). With something in hand, hold E to bounce a
  strengthometer (`ChargeMeter`) and release to throw, feeding the same
  shared momentum model -- a stone reappears as a `LiftableStone`, a
  generic item as an ordinary `DroppedItem`. A real UI meter floats above
  the player while charging. A new key (default H, "Stash Held Item")
  puts whatever's in hand into inventory instead -- a stone converts to
  rock, an item goes in as itself; anything that doesn't fit drops at the
  player's own feet rather than being lost.
- ✅ Weapon mass: weapon-kind items (sword, club, crude blade) carry a real
  mass derived from their material's real density x an estimated real-world
  volume (`MaterialProperties.mass_kg_for`), feeding a swing's knockback
  through the same momentum model instead of one flat constant for every
  weapon. Tools (axe, pickaxe, fishing rod, lasso) don't have a modeled mass
  yet -- a documented follow-up, not an oversight.
- ✅ A "Pick (E)" interaction prompt above a nearby liftable stone, mirroring
  the existing "Talk (key)" villager prompt -- hidden while the hand is
  already holding something, since E no longer sweeps in that state.
- ⬜ Visible damage state on a part-smashed boulder (currently only the final
  break is shown)
- ⬜ Stone type varying by biome (granite, limestone, sandstone) -- today all
  loose stone is the same grey granite (illustrated pebble/cobble/boulder art
  aside)
- ⬜ A thrown stone that misses/passes a creature is simply respawned as a
  loose stone at its landing spot rather than animated flying there, and
  isn't re-registered into EarthChunkManager's own per-chunk bookkeeping --
  it draws and can be picked up normally, but won't be recognized by
  Kick/dispersion/the "Pick" prompt until the world's own generation cycle
  handles it some other way. A documented simplification, not an oversight.
- ⬜ Per-outcome thrown/kicked-impact damage: ImpactResolver's outcome
  (cut/dent/crush/pierce/shatter/bounce) is read as a simple hit/no-hit for
  a thrown stone today, not mapped to a full per-outcome damage table --
  `materials.md` itself lists that mapping as an open, project-wide design
  question.
