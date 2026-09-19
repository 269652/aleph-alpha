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

### The fence gate: a Farm needs a real wooden_fence before anyone works it

Reported directly: "buildings like the farm require a fence and then an NPC
can get hired." A placed `"farm"` does NOT automatically get a Farmer the
way a Sägewerk automatically gets a Lumberjack — a real `"wooden_fence"`
placeable (`ItemCatalog`, `wood` x3, no skill gate — the least
technological construction here alongside `stone_dam`) must stand within
`FARM_FENCE_GATE_RADIUS_TILES` (matches `SAGEWERK_STORAGE_PAIR_RADIUS_TILES`'s
own magnitude — "the same worksite," not a farm-specific number) before a
Farmer moves in. This is real-world grounded (a tilled plot left unfenced
invites deer/rabbits to eat the crop before it's ever harvested) and gives
the Farm a genuine two-step build order a player discovers rather than
being told: build the plot, then fence it, then it comes alive.

Reconciliation runs both directions and retroactively: building the fence
AFTER the farm still staffs it (`EarthChunkManager._reconcile_all_known_
farmers` re-checks every real farm tile in every loaded chunk whenever a
wooden_fence appears or disappears anywhere — not just already-staffed
farms, since an unfenced farm has no Farmer yet to re-pair), and destroying
the only nearby fence sends the Farmer away (despawns it) rather than
leaving an orphaned worker with no gate condition left to satisfy. A
reloaded chunk re-evaluates the gate fresh rather than trusting whatever
was staffed before the unload, so a fence destroyed while its farm's chunk
was unloaded is honored correctly on the next visit.

### The Farmer

The moment a `"farm"` tile is placed WITH a real fence already in reach (or
reloaded from a persisted modification that still satisfies the gate,
mirroring the Sägewerk's own re-staffing-on-load behavior), exactly one
`FarmerMarker` spawns there — "an NPC moves in", the same framing
[timber_construction.md](timber_construction.md) already established for
the Lumberjack. Deliberately NOT the full `NpcMarker`/`NpcIdentity`
occupation stack (no daily schedule, no hunger/wallet economy) — the same
narrow-purpose-walker shape `LumberjackMarker`/`DecomposerMarker`/
`LogisticsMarker` already use, for the same reason: a single fixed loop
over a few owned plots is the wrong shape for that machinery.

The Farmer owns a small, fixed number of real `FarmPlotMarker` instances
(reusing the exact same tilled-soil/crop-art rendering a player's own farm
plot already uses) at fixed offsets around its home tile. Every owned
plot's growth advances every frame, independent of the Farmer's own current
phase (pillar 2).

**A bed is ground, and ground does not follow a person** (2026-09-19).
"Owns" is a bookkeeping relationship, not a scene-tree one: the beds are
laid out as the Farmer's **siblings**, anchored at `home`, never as his
children. They were `add_child`ed at first, and since a child's `position`
is an offset from its parent, three tilled beds and the wheat standing in
them were carried around the field by the Farmer on every step he took —
reported live as *"there's now some weird moving char thing + soil tiles"*,
and then *"the soil tiles are also moving with the character"*.

What makes this worth writing down rather than just fixing: `APPROACHING`
had **always** walked him to `home + _plot_offset(index)`, a fixed spot in
the world, while the bed was *drawn* at `farmer + _plot_offset(index)`. The
further he wandered, the further his beds drifted from the ground he was
standing on to tend them — the loop below already believed the beds were
where they are now, and only the drawing disagreed. Both are the same
expression today, and a test holds them there.

The one thing the old parenting bought for free was cleanup: a freed Farmer
took his beds with him because they were his children. Siblings do not
follow, so he frees them deliberately when he leaves the tree — otherwise a
demolished Farm leaves three tilled beds and their wheat standing in an
empty field forever.

The Farmer's own loop:

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

### Real art

Farm, Sägewerk, and Storage (plus the wooden_fence that gates a Farm) now
render with real illustrated art (`IllustratedStructureSprite`) instead of
the crude procedural tile look — a real user-supplied reference sheet per
subject (farmhouse/sawmill/warehouse/wooden_fence), sliced with a known
fixed grid, chroma-keyed and despilled, mirroring
`illustrated_beehive_sprite.gd`'s established precedent. Rendered as a real
overlay `Sprite2D` standing on the structure's own tile (`EarthChunkManager.
_structure_art_sprites`), scaled via a "footprint" anchor (width matches
the tile, height scales by the same factor, so a structure taller than one
tile — Sägewerk/Storage's own portrait-oriented art — stays taller, and one
wider than tall — Farm/wooden_fence's own landscape-oriented art — stays
wider) rather than squashed into a single small tile texture, per
`IllustratedArtLoader`'s own documented "footprint" anchor contract. The
underlying ground tile is unchanged (bare earth) — purely additive, and
every placeable with no real art yet (campfire/furnace/stone_dam) keeps
rendering exactly as before.

Each sheet is a genuine construction → idle → damaged → ruined progression
(farmhouse/sawmill/warehouse: 5 rows; wooden_fence: 4 rows) — real, useful
content for a future pass — but only the row that reads "freshly built,
currently in use" is wired to anything today, since nothing in this
codebase yet tracks a single-tile placeable's build progress or condition
the way `BuildingPiece` walls do. Animating through those states is a real,
deliberately out-of-scope follow-up (see "Open questions").

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

✅ Farm placeable + recipe, the wooden_fence gate (retroactive both
directions, survives reload), Farmer worker (till/water/harvest loop over a
fixed small plot cluster, real tested end-to-end wheat yield, no owned plot
ever left to wither over a long run), StructureStock crediting, Storage/
Logistics pairing (reusing `LogisticsMarker` unmodified), a direct player
collection fallback, and real illustrated art (farm/sagewerk/storage/
wooden_fence, replacing the crude procedural look) — see `docs/progress.md`'s
Farming section for the exact real/tested account.

✅ **The wheat CROP itself now has real art, too** (2026-09-13) — a real,
honestly-scoped gap this doc's own "Real art" section above never actually
closed: it covers the Farm/farmhouse structure sprite, not the crop
growing in each of the Farmer's owned plots. `FarmPlotMarker`/
`IllustratedCropSprite` (the class rendering every farm plot's crop) had
no `"wheat"` entry at all until now, so a growing wheat plot showed bare
tilled soil with nothing visible in it, whether tended by the Farmer or
(hypothetically) a player. See [long_grass.md](long_grass.md)'s "A second
atlas family: farmed wheat" for the full mechanism — wheat now renders as
several small, real bending blades reusing long grass's own path-traced
wind/walker-push shader math, using three real illustrated sheets
(spring/summer/autumn) that turn with the world's own calendar season.

✅ **The beds stand still** (2026-09-19) — reported live: *"there's now
some weird moving char thing + soil tiles??"*, then *"the soil tiles are
also moving with the character..."*. The Farmer's three beds were his
scene-tree children, so they were carried around the field with him; they
are siblings anchored at `home` now, and he frees them himself when he
leaves. See "The Farmer" above for why the walking loop had been right
about where the beds were all along, and only the drawing disagreed.

⬜ **The Farmer still reads as a placeholder next to a villager.** He is
drawn with `ProceduralLumberjackSprite` — a flat tan head, a brown body and
an axe — which is the established look shared by the Lumberjack, the porter
and the conversion workers, not a broken fallback. The VILLAGE's own
farmers (see below) use the full `CharacterView` the player does, so the two
kinds of farmer standing in neighbouring fields do not look like they belong
to the same game. A real decision, not an oversight: named here rather than
quietly restyled.

## A village counterpart, 2026-09-17

[village_farms.md](village_farms.md) gives the VILLAGE's own farmer and
herbalist occupations real farmhouses and real fields. It is a separate
mechanism for a separate actor — a full `NpcMarker` with a schedule, hunger
and a wallet, not this doc's narrow-purpose `FarmerMarker` — and it reuses
`FarmPlot`, `FarmPlotMarker` and `FarmerBehavior` unchanged.

One thing moved rather than being copied: the till/water/harvest priority
that lived in `FarmerMarker._next_action_plot_index`/`_action_kind_for` is
now `VillageFarm.action_for`/`next_action`, which this doc's own Farmer
delegates to. `WATER_BEFORE_WITHER_FRACTION` is shared the same way. Two
workers tending by two slightly different rules was the drift worth
avoiding.

## Open questions

- **Offscreen catch-up.** A Farm's plot state does not yet survive a chunk
  unload/reload, the same already-accepted gap the Sägewerk's own log stock
  has today — a real `construction_catchup.gd`-style closed-form integration
  is a genuine follow-up, not attempted here.
- **Settlement-autonomous "build a farm" decision — resolved** by
  [milling_and_baking.md](milling_and_baking.md) (2026-09-13): wheat's
  chain is resolver data now (`grow_wheat`, flagged `automated` so it can
  never be hand-crafted for free — the exact exploit this question refused
  to paper over), and a `DECLINING` settlement's own bread shortfall raises
  farm → mill → bakery through `SettlementBuildDecision` on its own. See
  that doc for the whole mechanism.
- **Capacity and a second Farmer.** Three plots is a real, if arbitrary,
  cap on how much one Farmer can tend before something occasionally
  withers — a deliberate real constraint (pillar 2), not yet paired with any
  mechanism for a settlement to notice the loss and build a second Farm.
  Still open after [milling_and_baking.md](milling_and_baking.md): the
  build decision reports *missing* producers, not insufficient throughput,
  so a village with every link standing has no construction it can take
  (see that doc's own "Scaling the chain to the need").
- **Milling and baking — resolved** by
  [milling_and_baking.md](milling_and_baking.md): a Mill (wheat → flour)
  and a Bakery (flour → bread, real food), each a Sägewerk-shaped
  continuous converter with its own worker, fed by the existing Logistics
  hauler.
- **Construction/damage/ruin art states.** Each real art sheet already
  draws a full construction → idle → damaged → ruined progression (see
  "Real art" above) — wiring it to a real build-progress/condition system
  for single-tile placeables (today none exists) is a genuine, deliberately
  deferred follow-up, not a missing asset.
