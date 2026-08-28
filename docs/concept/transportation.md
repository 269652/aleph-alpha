## Transportation

The planet is toroidal and water-heavy ([world.md](world.md)), and
[pets.md](pets.md) currently only offers horses as a mount. Transportation
gets its own system rather than staying an afterthought of the pet list.
This doc covers the tools a player carries; see
[infrastructure.md](infrastructure.md) for what the land itself accumulates
from repeated traffic — worn paths, trails, roads, and crossings:

- **Boats** are a craftable/buildable mode of transport (see
  [crafting.md](crafting.md)/[building.md](building.md)) for crossing the
  rivers ([rivers.md](rivers.md)) and oceans [world.md](world.md) generates —
  necessary, not optional, given how much of the map is water.
- **Fast travel is available early**, not gated behind late-game tech —
  waypoints/portals exist from early on for convenience alongside normal
  movement, horses, and boats, rather than being withheld until
  [eras.md](eras.md)'s later technological eras.
- Horses ([pets.md](pets.md)) remain the land-mount option; boats cover
  water; fast travel covers long-distance convenience on top of both.

### Traversal tools: crafted from the shared grammar, gated by material sourcing

Decided in a 2026-07-16 brainstorm against Zelda-style key-item traversal
unlocks: there are **no unique found-treasure traversal items** (no "Zora
armor" pickup). Every traversal tool — a raft, a grapple, a diving hull — is
assembled from the same [materials.md](materials.md) property/shape grammar
as everything else (a raft just needs a high-buoyancy material; a proper
climbing rope needs high tensile strength).

The Zelda-style "aha, now I can cross that" moment is preserved a different
way: the **materials that make a traversal tool actually good live further out
on the [danger gradient](synthesis.md#the-spatial-loop--a-danger-gradient)**
— light-and-strong wood only found deep in a forest biome makes a real glider
possible; waterproof hide from an aquatic apex predator makes a real diving
hull possible. Traversal capability is therefore gated by the same
material-sourcing loop as crafting power generally, not a separate unlock
track.

**The climbing rope now has something to unlock.** Until
[terrain_relief.md](terrain_relief.md), no terrain feature actually
required one — this doc named it, nothing consumed it. Terrain relief's
slope-gated passability is what a high-tensile rope, crafted the same way
as any other traversal tool above, actually raises.

### Fast travel: free for cargo, never for living stock

Resolves the cost/limitation open question below: fast travel/portals carry
**inanimate cargo with no restriction** — no Valheim-style "can't carry ore"
rule, no mass/value cost curve. The one hard restriction is on **living
creatures**: tamed/bred stock can never be fast-traveled, full stop. Moving a
prize animal home means actually walking or riding it through the world,
which is exactly where the [danger gradient](synthesis.md#the-spatial-loop--a-danger-gradient)'s
real risk to your breeding investment is meant to live — the friction is
targeted at what the design wants to matter, rather than at all cargo
generically.

### Open questions

- Fast-travel mechanic specifics — fixed waypoint network (discover/unlock
  nodes) vs. a craftable personal-portal item vs. something else?
  [wayfinding.md](wayfinding.md)'s Waystone item is a candidate answer (a
  player-placed, persistent, nameable waypoint) but deliberately doesn't
  resolve this question itself — it only registers the point; whether
  registering one grants fast travel is this open question's call to make.
- Do boats interact with the [weather](weather.md) system (storms making
  water travel genuinely risky)?
