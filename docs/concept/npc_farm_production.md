# NPC Farm Production: an Autonomous Wheat Farm

This doc gives [farming.md](farming.md)'s player-tilled loop an NPC-built,
NPC-staffed counterpart: a real placeable **Farm** structure that a settler
(or the player) builds, which an autonomous **Farmer** then works forever,
turning empty plots into a steady stream of real, storable **wheat** — the
same "a building produces a good automatically, hauled to storage by a
dedicated worker" loop [timber_construction.md](timber_construction.md)'s
Sägewerk already proved, applied to a second commodity.

It does not replace anything. `FarmPlot`/`FarmPlotMarker` (the pure
plant/water/harvest state machine and its rendering, both already real and
tested) are the substrate this doc builds on — a Farm is a small cluster of
those same plots with an NPC tending them instead of the player's own
key-presses. `StructureStock`, `LogisticsMarker`/`LogisticsBehavior`, and
`build_at_global` are reused unmodified, exactly as
[timber_construction.md](timber_construction.md) intended when it built
them generic rather than Sägewerk-specific.

## Design pillars

1. **One growth model, not a second one.** Wheat is not a new crop
   simulation — it is `FarmPlot`'s existing deterministic plant/water/
   harvest lifecycle (`farm_plot.gd`), the same one a player's own hand-run
   plot already uses, staffed by an NPC instead of a key-press. No second
   growth formula to keep in sync with the first.
2. **The building's production is independent of the worker's own phase,
   within real limits.** Matches `SagewerkProduction`'s own pillar: every
   owned plot's growth advances every frame regardless of what the Farmer is
   currently doing elsewhere on the farm — a planted plot keeps growing
   while the Farmer is off tending a different one. Unlike the Sägewerk's
   stockpile-fed shaping, though, growth here has a real, already-modeled
   failure mode (`FarmPlot`'s own wither-on-neglect rule) — which is exactly
   the honest reason a Farm has real capacity limits (see "Open questions"),
   not an invented one.
3. **Generic infrastructure stays generic.** `StructureStock` and
   `LogisticsMarker`/`LogisticsBehavior` were built (per
   [timber_construction.md](timber_construction.md)'s own "Storage,
   logistics, and the autonomous dependency chain" section) to collect from
   ANY source structure with real waiting stock, not hardcoded to the
   Sägewerk. This doc is the first real proof of that claim: a Farm plugs
   into both with zero changes to either class.
4. **No carry leg a real farm wouldn't have.** A Lumberjack carries a felled
   log home because the tree stood wherever it happened to grow, possibly
   `LumberjackMarker.SEARCH_RADIUS_PX` away. A Farm's plots are the Farm's
   own fixed fixtures, a few strides apart — harvested wheat credits the
   Farm's own `StructureStock` the moment the harvest dwell completes, with
   no separate CARRYING/DEPOSIT leg. This is a real, deliberate
   simplification relative to the Lumberjack's shape, not an oversight.
5. **Tuned values are tested functions, not comments**, per this project's
   own no-manual-tuning rule — every rate/dwell/threshold below is
   illustrative pacing, pinned by a calibration test at implementation time.

## Real-world grounding

- **A kitchen-garden plot, not a mechanized field.** This models a small,
  hand-tended market-garden bed — a few rows a single farmer can walk
  between and tend directly — not a mechanized wheat field. That is why one
  Farmer suffices for a small, fixed plot count rather than needing
  machinery or a crew.
- **Wheat as a staple grain crop.** Wheat is harvested as grain (not eaten
  fresh like a carrot pulled from the ground) — it is a raw material that
  feeds a downstream product (flour, then bread), matching this codebase's
  existing "material" item convention (`log`, `wood`, `stone`) rather than
  the "food" convention wild/farmed produce like carrot/potato already use.
  Milling wheat into flour and baking bread are real, named, explicitly
  out-of-scope follow-ups (see "Open questions") — this pass ships the
  grain itself, the first link in that chain.
- **Why a farmer re-waters before a crop actually wilts, not after.** A real
  farmer checks on crops on a walking circuit and waters ahead of visible
  wilting, not only once a plant has already started to droop — this grounds
  the Farmer's own `WATER_BEFORE_WITHER_FRACTION` margin (water once a
  growing plot has used up half its real wither grace window, not only once
  it is about to cross it).

## Mechanism

### The Farm structure

A new placeable, `"farm"` (`ItemCatalog`, `kind = "placeable"` — the same
family `campfire`/`furnace`/`sagewerk`/`storage` already belong to), built
the same tile-based way via `EarthChunkManager.build_at_global`. Recipe (no
skill gate, matching `storage`'s own reachability reasoning): `wood` (6) for
fence rails/posts and `plant_fibre` (4) lashing them — a simple tilled,
fenced plot costs meaningfully less than Storage's own enclosed lumber shed
(12 wood + 4 plank), since there is no roof or walls to raise, just ground
to till and fence.

### The Farmer

The moment a `"farm"` tile is placed (or reloaded from a persisted
modification, mirroring the Sägewerk's own re-staffing-on-load behavior),
exactly one `FarmerMarker` spawns there — "an NPC moves in", the same
framing [timber_construction.md](timber_construction.md) already
established for the Lumberjack. Deliberately NOT the full
`NpcMarker`/`NpcIdentity` occupation stack (no daily schedule, no
hunger/wallet economy) — the same narrow-purpose-walker shape
`LumberjackMarker`/`DecomposerMarker`/`LogisticsMarker` already use, for the
same reason: a single fixed loop over a few owned plots is the wrong shape
for that machinery.

The Farmer owns a small, fixed number of real `FarmPlotMarker` instances
(reusing the exact same tilled-soil/crop-art rendering a player's own farm
plot already uses) at fixed offsets around its home tile. Every owned
plot's growth advances every frame, independent of the Farmer's own current
phase (pillar 2). The Farmer's own loop:

`SEEKING` (decide which owned plot needs attention: a **ready** plot to
harvest, else an **empty/withered** plot to till-and-plant wheat, else a
**growing** plot at real risk of withering to re-water — in that priority
order, so productive work always wins over routine maintenance) →
`APPROACHING` (walk to it) → `WORKING` (a timed dwell — kneeling to tend a
bed is a real, non-instant action) → performs the actual till/plant, water,
or harvest call against that `FarmPlotMarker` → back to `SEEKING`. A
completed harvest credits the Farm's own real `StructureStock` at its home
tile directly (`EarthChunkManager.deposit_to_structure_at`), pillar 4.

### Storage, Logistics, and direct collection — reused, not rebuilt

A Farm pairs with every real Storage within the same
`SAGEWERK_STORAGE_PAIR_RADIUS_TILES` radius the Sägewerk already uses,
spawning one real `LogisticsMarker` (`item_id = "wheat"`,
`source_structure_id = "farm"`) per paired Storage — the identical
reconcile-on-modification-change wiring
`_resync_logistics_for_sagewerk`/`_sync_logistics_workers` already runs for
the Sägewerk, generalized to a second producer id rather than duplicated
into a parallel mechanism. `LogisticsMarker`/`LogisticsBehavior` needed zero
changes — pillar 3's actual payoff.

A player with no Storage/Logistics built yet still has a direct way to
collect: mirroring `Player._collect_step`'s exact shape, standing near a
Farm and swinging withdraws whatever real wheat stock has piled up straight
into inventory.

### Persistence and the two fidelities

Persisted implicitly the same way the Sägewerk is: the `"farm"` tile itself
is an ordinary chunk modification, so a reloaded chunk re-staffs a fresh
Farmer for every persisted Farm found in `_load_chunk` — the Farmer's own
in-progress plot state (what's growing, how close to ready) is NOT
persisted across an unload, the same documented, already-accepted class of
gap the Sägewerk's own log stock and a player's own hand-tilled farm plot
both already carry (see `docs/progress.md`'s Farming and Timber
Construction entries). A genuine offscreen catch-up integration (mirroring
`chunk_ecology_catchup.gd`'s closed-form shape, the way
[timber_construction.md](timber_construction.md) built one for construction
labor) is a real, named, deliberately out-of-scope follow-up for this pass
— see "Open questions."

## Interaction with other docs

- **[farming.md](farming.md)** — this doc is the NPC-built counterpart to
  its player-tilled loop, reusing `FarmPlot`/`FarmPlotMarker` exactly rather
  than forking them. Wheat does not yet participate in that doc's DNA/
  breeding vision (`crop_breeding.gd`) — a real, later unification, not a
  divergence.
- **[timber_construction.md](timber_construction.md)** — the direct
  template: Farm/Farmer mirror Sägewerk/Lumberjack's structure/worker/
  production shape, and reuse (rather than duplicate) its Storage/Logistics
  infrastructure outright.
- **[production_chains.md](production_chains.md)** — deliberately NOT
  wired into `ConstructionPriority`/`NeedResolver` this pass (see "Open
  questions"): unlike `beam`/`plank`, wheat has no consumed raw-material
  input in `FarmPlot`'s own model, so a naive `requires_structure: "farm"`
  ghost recipe with no real input cost would let a player instantly "craft"
  free wheat near any Farm — a real economy exploit this pass deliberately
  avoids rather than papering over.
- **[npc.md](npc.md)** — the Farmer is, like the Lumberjack and Builder, NOT
  a fourth entry on `NpcProduction.PRODUCER_ITEM_BY_OCCUPATION` (that table
  is unrelated: personal per-NPC wallet/hunger yield for the existing
  `"farmer"` *occupation*, which forages wild vegetation-density fruit, a
  separate and pre-existing mechanic this doc does not touch). The Farm's
  Farmer is a dedicated structure-worker, the same category the Lumberjack
  already established, not a village-occupation villager.

## Worked example

A player builds a Farm at the edge of their settlement. Within moments, a
Farmer arrives, tills and plants its three plots with wheat, then walks a
tending circuit: watering a plot that's approaching its wither risk,
harvesting one that ripened while it was elsewhere, planting a freshly
harvested bed again. Wheat piles up in the Farm's own stock. A Storage
built nearby a minute later gets its own dedicated Logistics worker within
moments (the same reconcile-on-build wiring the Sägewerk already proved),
which begins hauling wheat over in hand-cart loads — no additional wiring,
no separate mechanism, exactly the generic infrastructure this doc's
pillar 3 promised.

## Status

✅ Farm placeable + recipe, Farmer worker (till/water/harvest loop over a
fixed small plot cluster), StructureStock crediting, Storage/Logistics
pairing (reusing `LogisticsMarker` unmodified), and a direct player
collection fallback — see `docs/progress.md`'s Farming section for the
exact real/tested account.

## Open questions

- **Offscreen catch-up.** A Farm's plot state does not yet survive a chunk
  unload/reload, the same already-accepted gap the Sägewerk's own log stock
  has today — a real `construction_catchup.gd`-style closed-form integration
  is a genuine follow-up, not attempted here.
- **Settlement-autonomous "build a farm" decision.** `ConstructionPriority`/
  `SettlementBuildDecision` do not yet know a Farm exists as a buildable
  target — reaching that needs a real, non-exploitable way to express
  wheat's dependency chain (see "Interaction with other docs" above), left
  open rather than solved with a shortcut.
- **Capacity and a second Farmer.** Three plots is a real, if arbitrary,
  cap on how much one Farmer can tend before something occasionally
  withers — a deliberate real constraint (pillar 2), not yet paired with any
  mechanism for a settlement to notice the loss and build a second Farm.
- **Milling and baking.** Wheat → flour → bread is the obvious next
  production-chain link (real-world grounding above) and is deliberately
  not built here — this pass ships the grain, not the chain past it.
