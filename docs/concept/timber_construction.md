# Timber Construction: Statics, Withering, and NPC-Built Settlements

This doc extends [building.md](building.md)'s piece/placement/room mechanism
with three things it doesn't yet have: a real **material pipeline** from
standing tree to structural component, a real **statics** model (a piece
stands because something holds it up, not because it was placed), and a
real **withering** model (an untended structure decays and can collapse).
It then spends its NPC section on the actual ask: NPCs that walk to a
forest, fell a tree, shape it, and build with it — visibly when the player
is watching, and causally (never by prefab) when they are not.

It does not replace anything in `building.md`. `BuildingPiece`,
`BuildingPlacement`, `RoomDetector`, `HouseBlueprint`, and
`stamp_structure_at_global` are the substrate this doc builds on, not
around.

## Design pillars

1. **One material pipeline, not a menu unlock.** A Balken (beam) or Planke
   (plank) is not conjured from an inventory count of generic "wood" — it
   is shaped from a specific felled trunk, and that trunk's size still
   matters, the same way `FelledTree.wood_for(growth_scale)` already scales
   a fallen tree's yield by how grown it was (`felled_tree.gd:38`). This
   doc extends the existing felling pipeline; it does not add a second one.
2. **A structure stands because something holds it up.** Real, if
   simplified, statics: every piece needs a supported path back to the
   ground. Sever that path and the piece does not just sit there —
   it eventually falls, using the `Topple / collapse` verb `materials.md`
   already declares as a general physical interaction rather than
   inventing a parallel "building health" stat.
3. **Time is a material, and it decays what nobody tends.** `materials.md`'s
   material property vector already lists a `Decay/weathering rate` scalar
   ("organics rot; metals corrode; stone endures") that nothing currently
   reads. This doc is the first real consumer of it for built structures,
   and it is bounded/legible — a decay curve that converges, not a random
   rot timer.
4. **Two fidelities, one truth** (the same pillar `ecosystem_dynamics.md`
   states for wildlife). Near the player, an NPC builder is a real agent:
   you watch it walk to a forest, swing an axe, carry logs, and raise
   walls. Far away, the exact same causal process runs as one closed-form
   catch-up integration over the elapsed unloaded time, reusing
   `chunk_ecology_catchup.gd`'s own shape. The game is not lying to the
   player about what happened off-screen; it is computing it cheaply.
5. **No city prefabs with no causal origin.** Quoting
   [docs/emergence/00-emergence-architecture.md](../emergence/00-emergence-architecture.md)'s
   own anti-pattern list verbatim. This is a deliberate correction: today
   `VillageRenderer._stamp_house` stamps a complete house, instantly and
   for free, the moment a settlement is generated (see Status below) —
   exactly the anti-pattern this doc exists to retire. A discovered
   village's houses must be traceable to accumulated builder-hours against
   a real population and a real elapsed time, never to "the chunk loaded."
6. **One system, two builders — now three.** `building.md`'s own framing:
   player and village generator build with one piece vocabulary. That doc
   already flags the gap: village stamping bypasses
   `BuildingPlacement.can_place` entirely. This doc closes it by giving the
   autonomous NPC builder a third seat at the same table — every piece
   anyone places (player, generator, or builder AI) goes through the same
   placement and statics checks.
7. **Tuned values are tested functions, not comments.** Every rate, span
   limit, and labor-hour cost named below is illustrative — grounded in the
   real-world reasoning that produced it, but the actual number gets pinned
   by a calibration test at implementation time, per this project's
   no-manual-tuning rule, the same way `materials.md`'s own open questions
   defer its threshold curves.

## Real-world grounding

- **Post-and-beam framing (Fachwerk / half-timbering).** A timber building's
  strength lives in a skeleton of squared **structural members** — sills,
  posts, plates, rafters — carrying load in compression and bending, down
  to the ground. Everything else (wattle-and-daub infill, cladding boards,
  floor decking) carries no load; it just fills the frame. Balken/Planke
  should encode exactly this division mechanically, not just cosmetically:
  a Balken is a load-bearing structural piece, a Planke is not.
- **Hewing vs. riving.** Squaring a round log into a beam (hewing, with a
  broadaxe — scoring the log then splitting/dressing the waste off) loses
  material (sapwood, offcuts) but produces a flat-faced timber that can
  seat real joints, and it is slow, skilled work. Splitting or sawing a log
  into boards (riving/ripping) is a different, faster operation that yields
  more total board footage per log but nothing structural. This grounds
  the Balken/Planke shaping split: a Balken should cost more of a felled
  trunk's wood and take longer to shape than a Planke of the same tile
  footprint.
- **Spans and support.** A post standing on a footing carries its load
  straight down; a beam spanning between two posts carries load in
  bending, and the further it spans unsupported, the less load it can
  carry before it sags and fails. This is the real principle behind
  Valheim's own "support value decays with distance" model — it is a
  simplified beam-span limit, not an invented game mechanic.
- **Why old timber buildings sit on a stone footing.** Wood in continuous
  ground contact, in a damp, low-airflow spot, rots first — "sill rot" and
  "post rot" are named failure modes, which is exactly why vernacular
  timber construction the world over keeps wood off bare earth on a stone
  or brick footing, and why a roof overhang exists at all. This grounds
  withering's exposure term: a roofed, elevated piece decays slower than
  an exposed, ground-contact one.
- **How real ruins decay.** An abandoned timber structure loses its roof
  first (thinnest cross-section, most exposed, and once its own supporting
  rafters weaken, gravity does the rest), then its walls, typically leaving
  a recognizable low ruin — a foundation, maybe a corner post — rather than
  vanishing. This grounds the collapse cascade below: a decayed support
  piece takes down what depended on it, not the whole structure at once.
- **Vernacular settlements grow one building at a time.** A real village
  gains structures at a rate bounded by available labor and material, not
  all at once — motivating the labor-hours accumulator this doc uses for
  the minimum-build-time floor, directly serving
  [npc.md](npc.md#settlement-growth-migration-toward-player-built-structures)'s
  already-specified population growth as the throttle on how fast a
  settlement can build.

## Mechanism

### Material pipeline: log → Balken / Planke

Tree felling already exists end to end and is not reinvented here:
`ChoppableTree.take_damage` fells a standing tree (`choppable_tree.gd:147`),
`_fall()` topples it (`:166`), and each further hit `_cut_up()`s a length
off the trunk (`:179`), dropping `wood`/`stick` `ItemStack`s sized by
`FelledTree.wood_per_cut(growth_scale)` (`felled_tree.gd:44`) via
`WorldItemBus.item_dropped`. A bigger tree is already a bigger haul.

This doc adds a **shaping step** between "wood in hand" and "buildable
piece," at a worksite prop (a sawpit/hewing-block — new, small, mirrors how
a campfire/furnace already exist as placeable worksite props):

- A new raw item, `log` (`kind = "material"`, following `item.gd`'s
  existing shape — no new fields needed), is what a felled trunk's cut
  yields once it's destined for construction rather than kindling; existing
  `wood`/`stick` stay as they are for the existing uses.
- **Shaping** consumes logs and time at a worksite, producing either:
  - `balken` (structural) — costs more log volume per piece, takes longer
    to shape (hewing), grounded above.
  - `planke` (non-structural) — costs less log volume per piece, shapes
    faster (riving/sawing), grounded above.
- `BuildingPiece`'s existing per-piece dict (`building_piece.gd:43`,
  `category`/`material`/`encloses`/`walkable`/`durability`/`cost`) gains one
  more field: a load-bearing flag or support-capacity number, so a
  `wood_wall` built from Balken carries real support capacity and a
  `wood_floor` built from Planke carries none. This is additive to the
  existing dict shape — every current piece keeps working, walls just
  start meaning something structurally they didn't before.

**A Sägewerk itself needs a real carpenter's eye to raise, not just
materials — generalized, not hardcoded.** Reported directly: "you also
need a given crafting skill level to build a sawmill... [and] this needs
to work for all future buildings and economics." Rather than a
Sägewerk-specific check, this is [production_chains.md](production_chains.md)'s
general `required_skill` recipe field, applied to the `"sagewerk"` recipe
(Carpentry level N, read live via the exact
`SkillTree.total_bonus("carpentry_level", allocated_nodes)` pattern
`Player._chop_step`'s `CARPENTRY_LEVEL_FOR_SAWING` already uses) — the
SAME mechanism any future production building's own skill requirement
uses, not a one-off gate invented for this one structure. See that doc
for the full mechanism; this paragraph only records the Sägewerk's own
concrete instance of it.

### Real statics: a support graph over the piece grid

`RoomDetector` already treats a structure's pieces as a grid keyed by local
cell, flood-filling for enclosure (`room_detector.gd:30`). Statics reuses
the same grid, with a different traversal: every load-bearing piece needs a
path of adjacent load-bearing pieces back to a **grounded** cell (bare
terrain, or a foundation piece) within a maximum unsupported run — the game
version of a beam's span limit. A floor or roof piece needs to sit adjacent
to (or above) a load-bearing piece within its own, shorter cantilever
limit.

This is **event-driven, not per-tick**: a graph recompute over
O(structure size) cells whenever a piece is placed, removed, or decays away
— live, during a player edit, or as the last step of an offscreen catch-up
pass installing a settlement's caught-up state. It never needs to run every
frame, and it never needs to be a cellular automaton itself — only the
things that change piece state *over time* (construction progress,
withering) do.

A piece that loses its support path does not vanish: it accumulates
instability and, past a short grace threshold, **collapses** — the same
`Topple / collapse` verb `materials.md`'s damage model already names as a
general interaction, not a bespoke "building HP" system. A collapse drops
its own material back to the ground (mirroring `materials.md`'s "breaking
terrain drops its constituent materials, closing the loop straight back
into crafting supply") and re-triggers the support graph for whatever it
was holding up — a roof over a rotted-out wall comes down with it, not
independently.

### Withering: decay as a bounded, closed-form catch-up

Every placed piece carries a `condition` value (1.0 = new), decaying
toward 0 at a rate keyed to `materials.md`'s already-declared
`Decay/weathering rate` for its material, modulated by exposure — a
roofed piece (`RoomDetector` already answers "is this cell indoors")
or a piece belonging to an inhabited/maintained property
(`HouseholdStore.owner_of(piece_id) != ""`) decays slower; an abandoned,
exposed piece decays fastest, grounded in the ground-contact/post-rot
reasoning above.

The integration is the **same closed-form shape**
`chunk_ecology_catchup.gd` already uses for vegetation regrowth
(`new_vegetation := 1.0 - (1.0 - vegetation) * exp(-rate * days)`,
`chunk_ecology_catchup.gd:63`): here,
`new_condition := condition * exp(-decay_rate * exposure_multiplier *
elapsed_days)`. A large elapsed-time jump is safe and deterministic in one
call — no need to iterate day by day for a chunk that has been unloaded for
a year. `condition` crossing zero feeds the exact same collapse path a
severed support does: decay and statics are two *inputs* into one collapse
mechanism, not two parallel ones. And like the ecology catch-up's own
120-day cap ("logistic growth converges anyway"), decay converges toward 0
past a bounded elapsed time regardless of how long a structure sat
unvisited — an abandoned house read after a decade is a fixed "ruins" state,
not an ever-precise timer nobody needed.

### NPC construction: the two fidelities

**Loaded / onscreen fidelity.** A per-NPC state machine, the same shape
`npc_production.gd`/`npc_economy.gd` already use for farmer/hunter/fisher
(`NpcProduction.PRODUCER_ITEM_BY_OCCUPATION`, `npc_production.gd:27`),
driven once per frame from `NpcMarker` the way `NpcEconomy.step` already is
(`npc_economy.gd:60`):

`SEEK_FOREST` (find the nearest tile with real tree density above a
threshold — reusing `EarthChunkManager.vegetation_density_near` the same
way the farmer occupation already does, `npc_production.gd:89`) →
`WALK_TO_TREE` (the same straight-line `move_toward` every `NpcMarker`
already uses) → `FELL` (calls the *same* `ChoppableTree.take_damage` loop
the player's axe uses — an NPC swinging an axe is not a separate mechanic,
it is the same one with a different caller) → `CARRY_LOG` (walk to the
settlement's worksite) → `SHAPE` (a timed action producing Balken/Planke)
→ `CARRY_MATERIAL` → `PLACE_PIECE` — one piece at a time, each validated
against `BuildingPlacement` *and* the statics support graph as it goes, so
a player watching genuinely sees a wall rise plank by plank, and could in
principle watch an over-cantilevered piece refuse to place, or a badly
supported one placed anyway and later creak and fall.

`HouseBlueprint.build` (`house_blueprint.gd:29`) already turns a seed and
footprint into a full piece dict — a *target*, not an install order.
Construction adds an incremental installation sequence over that same
output (foundation/floor first, then load-bearing wall posts, then
infill walls, then roof last — the real historical build order), sitting
on top of `house_blueprint.gd` rather than replacing it.

**Unloaded / offscreen fidelity.** A `construction_catchup.gd` mirroring
`chunk_ecology_catchup.gd`'s exact contract:
`advance(state: Dictionary, elapsed_seconds: float, capacity: Dictionary)
-> Dictionary`, pure, deterministic, no mutation of its input.

- `state`: stockpiled `log`/`balken`/`planke` counts, and a list of
  in-progress `{blueprint_id, labor_hours_accumulated}` projects.
- `capacity`: `builder_count` (derived from settlement population, the
  same way `SettlementState.carrying_capacity` already derives a number
  from real stock, `settlement_state.gd:48`), `forest_density_nearby`
  (`vegetation_density_near`), and named per-builder felling/shaping/
  building rates.
- Stockpiles and labor-hours advance by the elapsed time in closed form,
  capped the same way the ecology precedent is capped, so integrating a
  century of unloaded time is bounded arithmetic, not an unbounded loop.
- **This *is* the minimum-build-time floor.** A project completes only
  once `labor_hours_accumulated >= blueprint.total_labor_hours`. No amount
  of elapsed wall-clock time skips that faster than `builder_count` many
  NPCs' worth of hours can accumulate — a lone, unpopulated hamlet cannot
  will a house into existence just by sitting unloaded for a thousand
  years. Population growth (already specified in npc.md's settlement
  growth section) is what raises `builder_count` and therefore how fast
  and how much a settlement can build — construction capacity is a real
  consequence of population, not an independent dial.

**On chunk load**, a settlement's founding tick plus elapsed time yields
some number of completed projects, some in-progress, and a leftover
material stockpile. Completed projects are stamped via the *existing*
`stamp_structure_at_global`/`HouseBlueprint` mechanism — no new rendering
path — after applying condition decay for the time since completion (an
old village should not look freshly built) and a statics pass (a
long-neglected structure may stamp missing its roof, a real partial ruin,
rather than pristine). An in-progress project stamps its *current* partial
piece set — walls up, no roof yet — so a half-built house is discoverable
too, not just complete-or-nothing.

**Determinism** follows `tall_grass.gd`'s own discipline exactly: no
`RandomNumberGenerator` anywhere in this pipeline. Which trees get felled,
build-order tie-breaks, which cell a project starts at — all hash-derived
from `(settlement seed, project index, tick)`, never an RNG object. A
chunk that has genuinely never been loaded, discovered for the first time
after the settlement has existed off-screen for the whole session, must
reproduce identically if the player leaves and returns — the same
guarantee terrain and ecology already give.

### Settlement construction ledger

A lightweight `ConstructionProject` (mirrors `Household`'s shape —
`household.gd:1` — id, footprint origin, blueprint id, assigned household,
a status enum, `labor_hours_accumulated`, reserved material) plus a
`ConstructionProjectStore` (mirrors `HouseholdStore`'s
`to_dicts`/`from_dicts`/idempotent-creation shape,
`household_store.gd:23`) in `src/emergence/`. A settlement's Balken/Planke
stockpile needs no new container — `VillageMarket.stock`
(`village_market.gd:35`) is already a generic `item_id -> float` dict, fed
today only by food; it holds lumber the same way.

**Deciding whether a household starts building** reuses
`InstitutionFormation`'s hysteresis *pattern*
(`institution_formation.gd:44`) — not institutions themselves — against a
real, already-tracked number: material stock crossing a blueprint's
requirement to start, dropping *well* below it (not just below) to
abandon, the same asymmetric gap that stops formation/dissolution from
flickering on a single unit of stock changing hands.

**Ownership** on completion is `HouseholdStore.grant_property(household_id,
"house_<chunk>_<origin>")` (`household_store.gd:52`) — this call already
does exactly the right thing and needs no changes.

**Sourcing** extends `NpcProduction`'s existing occupation → yield mapping
(`npc_production.gd:27`) with a new producer entry, e.g. `"logger": "log"`,
reading a new `EarthChunkManager.forest_density_near` accessor that mirrors
`vegetation_density_near` exactly. Gathering timber draws down the *same*
vegetation-density grid the ecosystem simulation already tracks — a large,
long-lived village measurably thins its surrounding forest, the same way a
real drought already measurably lowers a farmer's yield
(`docs/progress.md`'s NPC section: "a real drought... measured 93.8% lower
farmer AND hunter yield"). This closes construction into the existing
ecosystem loop rather than inventing a separate, infinite lumber source.

### Storage, logistics, and the autonomous dependency chain (mechanism spec)

Compiled from a follow-up design-brainstorm session, reported directly:
"NPCs should be able to build a storage building in their village — if
both production buildings and storage exist, new NPCs may move in which
handle logistics... and somehow we need a dependency chain which causes
NPCs to understand that they need a Sawmill in order to produce
construction material they can use to build houses." This is the
Settlement construction ledger's own "which project does a settlement
start next" reasoning made concrete — extending the Sägewerk (see
"Material pipeline" above) with two more real building/NPC roles and the
autonomous logic to sequence them correctly.

**Storage: a real place accumulated goods live, not loose ground
clutter.** A new placeable structure, `storage`, built the same tile-based
way `campfire`/`furnace`/`sagewerk` already are (`ItemCatalog`, a real
`CraftingRecipeBook` recipe — 12 wood + 4 plank, no skill gate; only the
Sägewerk's own log-shaping step is skill-gated), with its own real
per-instance stock: `item_id -> int`, the *exact same shape*
`Market`/`VillageMarket` already prove at settlement scale, reused here at
building scale (`StructureStock`/`StructureStockStore`, keyed by the
structure's own tile position — two Storage buildings never share a
stock, the same way two settlements' markets don't) rather than a third
container design. `EarthChunkManager` grew the small, generic glue this
needs: `nearest_structure_position` (WHERE the nearest structure of a
given id is, not just whether one exists — `has_structure_near`'s own
boolean answer plus a location a walker can use), and
`structure_stock_at`/`deposit_to_structure_at`/`withdraw_from_structure_at`
against that per-position stock.

**Logistics: carrying finished goods, not raw material.** A new dedicated
worker (`LogisticsMarker` + `LogisticsBehavior`), the same "small,
purpose-built walker, not the full NpcMarker AI stack" shape
`LumberjackMarker`/`DecomposerMarker`/`CaravanMarker` already established
(mirroring `DecomposerMarker`/`CarrionForageBehavior`'s pure-state-
machine-plus-engine-glue split exactly) — the mirror image of the
Lumberjack's own loop: instead of raw material INTO production, it moves
FINISHED output OUT of a source structure and INTO the nearest real
Storage. `SEEKING` (find a source structure with real waiting stock) →
`APPROACHING` → `COLLECTING` (a timed pickup, up to a real hand-cart-sized
`CARRY_CAPACITY` per trip, not "however much the source has") →
`CARRYING` (walk to the nearest real Storage — a second walk leg to a
*different* destination than the first) → `DEPOSITING` (a timed drop-off,
crediting Storage's real stock) → back to `SEEKING`. Intra-settlement
transport, distinct from `CaravanMarker`'s inter-settlement one — same
walker shape, different route and cargo. Every transition is driven by
real distance/timers, not a scripted animation.

**Who moves in, and when.** Matches `quests.md`'s own already-specified
migration pillar almost exactly: "specialty infrastructure (a forge, a
dock, a farm plot) is a specific pull for a specific occupation-need." The
full mechanism there (real push/pull, a minimum floor before eligibility,
player-invite, sourced preferentially from a declining settlement's own
push-pressured residents) stays exactly as specified there, and exactly as
unbuilt (it needs a replan-interrupt architecture that doesn't exist yet)
— this section does not attempt to build it. The intended design,
mirroring how placing a Sägewerk directly spawns its own Lumberjack with
no hiring/migration system needed, is: a settlement/area with both a real
production building AND a real Storage building present spawns one
Logistics worker directly — a simplified, directly-triggered stand-in for
the fuller migration mechanism. See "What's honestly still a stand-in
here" below for how far this is actually wired today.

**The dependency chain: recognizing what to build first.** The actual
ask's hardest piece. `ConstructionPriority.decide`
(`src/gameplay/construction_priority.gd`) is the pure function that
answers it: given a target recipe, a settlement's real local stock, and
which structures are known present nearby, it returns `READY` (build it
now), `SHORTFALL` (materials are short — the existing regional-trade/
shortfall path in `regional_trade.md`/`trade.md` applies, not a new
producer), or `BUILD_PRODUCER_FIRST` (the recipe is gated on a structure
that isn't there yet — go build that first, ahead of the project that
needed it). This is the general, reusable [production_chains.md](production_chains.md)
mechanism's real payoff: `CraftingRecipeBook`'s `requires_structure`/
`required_skill` fields and its `NeedResolver` already answer exactly this
question for ANY recipe, not a Sägewerk-specific one-hop lookup — the
Sägewerk is simply that system's first two real recipes (`"sagewerk"`
itself, and the log→beam/plank shaping recipes), not a special case with
its own bespoke resolution logic. See "What's honestly still a stand-in
here" below for `ConstructionPriority.decide`'s actual current
implementation, which does not yet call `NeedResolver`.

### What's honestly still a stand-in here

This section's implementation and this doc's own prose were, for a real
stretch, written independently by two different sessions against two
different views of this codebase, then reconciled. A follow-up pass
(2026-08-25) closed most of what that reconciliation left open — this is
what's ACTUALLY real right now:

- **Storage, `StructureStock`/`StructureStockStore`, and
  `LogisticsMarker`/`LogisticsBehavior` are real, tested, and generic** —
  designed to collect from ANY source structure with real waiting stock,
  not hardcoded to the Sägewerk specifically, so a real future producer
  (or the Sägewerk itself, see next point) plugs in with no changes to the
  worker.
- **The Sägewerk's own real production now feeds `StructureStock`.**
  `LumberjackMarker._step_production` credits `SagewerkProduction`'s real
  beam/plank output straight into `StructureStock` at the Sägewerk's own
  tile position (via `EarthChunkManager.deposit_to_structure_at`, through
  a late-bound `earth` reference set the same way `LogisticsMarker`'s own
  is) — NOT a `WorldItemBus` ground-drop any more. This closes the
  architecture mismatch the previous version of this note described: the
  Logistics worker's own `SEEKING` step looks for `StructureStock`, and
  now the Sägewerk's real output is actually there to find.
  `test_lumberjack_marker.gd` covers both the credit itself and that the
  old ground-drop is genuinely gone (no double-crediting between a
  Logistics worker's delivery and a leftover ground pickup).
- **A player with no Storage/Logistics built yet still has a real, direct
  way to collect.** Removing the ground-drop would otherwise be a
  regression for that player — `Player._collect_step` (wired into
  `_perform_attack` alongside `_chop_step`/`_butcher_step`, the same
  swing-driven-interaction convention) withdraws whatever real beam/plank
  stock a nearby Sägewerk has piled up straight into the player's own
  inventory when standing near one, mirroring `_has_heat_source`'s own
  proximity-check shape. Real, tested (`test_player.gd`): withdraws real
  present stock, no-ops with nothing stocked, no-ops with no Sägewerk
  nearby.
- **A Sägewerk pairs with EVERY real Storage within
  `SAGEWERK_STORAGE_PAIR_RADIUS_TILES`, not just the single nearest one**
  (closed 2026-08-25 — this section previously named the single-nearest
  behavior as an honest constraint; it no longer applies).
  `EarthChunkManager._sync_logistics_workers`/`_resync_logistics_for_sagewerk`
  still mirror the existing `_sagewerk_lumberjacks` sync-on-modification-
  change wiring, but now reconcile against a full set: a new
  `nearby_structure_positions` accessor (the ALL-matches counterpart to
  `nearest_structure_position`, reusing its exact chunk-scan loop) returns
  every real Storage in range, and `_resync_logistics_for_sagewerk` spawns
  one full worker-pair (one `LogisticsMarker` per `beam`/`plank`) for each
  Storage newly in range, despawns the pair for any previously-paired
  Storage that dropped out of range or was destroyed, and leaves an
  already-correctly-staffed pair alone. `_logistics_workers` grew one level
  deeper to hold this: chunk_coord → local_cell (the Sägewerk's own cell)
  → storage_key (`_storage_pairing_key`, the same position-keying pattern
  `_structure_stock_key` already uses, so two Storages never share an
  identity) → `{item_id -> LogisticsMarker}`. A new `LogisticsMarker.
  preferred_storage_position` field (unset/null by default, additive —
  every existing single-storage caller/test is unaffected) is what makes
  the pairing mean anything: without it, every worker's own dynamic
  `nearest_structure_position` lookup would independently reconverge on
  the SAME single nearest Storage regardless of which one it was nominally
  paired with. `_resync_logistics_for_sagewerk` sets each newly-spawned
  pair's `preferred_storage_position` to its own paired Storage's position;
  `_collect_from_source` uses it directly when set, falling back to the
  original dynamic lookup when unset. Real, tested
  (`test_earth_chunk_manager.gd`'s Storage/Logistics section and
  `test_logistics_marker.gd`): two real Storages in range of one Sägewerk
  each get their own full worker-pair (four workers total, not two), each
  pair's real deliveries land in its own paired Storage's stock (not
  funneled to whichever Storage `nearest_structure_position` would have
  picked), destroying one of two paired Storages despawns only that
  Storage's own pair and leaves the other's workers running, and the
  original single-Storage behavior (exactly one pair) is unchanged as a
  pure regression case.
- **`ConstructionPriority.decide` is now rebuilt on the real
  `NeedResolver`** — the old `CraftingRecipeBook` + `Smelting.can_smelt`
  composition is gone. `decide` resolves the recipe's own output item
  through `NeedResolver.resolve`, then maps ANY `"structure"` or `"skill"`
  need anywhere in the recursive walk to `BUILD_PRODUCER_FIRST` (both name
  something that must exist before the recipe can happen at all,
  regardless of material stock) and a remaining `"material"` need to
  `SHORTFALL`, preserving the exact same three-value contract. This closed
  a real behavioral gap the old Smelting-only composition could not see:
  `"sagewerk"` itself is not a smelting recipe, so the old code never
  checked its `required_skill` (Carpentry) at all — a settlement with
  enough logs and wood but no carpenter would have been reported READY.
  `decide` now takes an optional `allocated_nodes` parameter (default
  empty) so a caller with a real skill pool can clear that gate; existing
  callers/tests are unaffected by the default.
  Real, tested (`test_construction_priority.gd`), including the new
  skill-gate case and a multi-hop structure+material case. (This entry
  used to note `decide` had no live settlement caller yet -- see the next
  bullet immediately below, which closes that gap.)
- **`ConstructionPriority` now HAS a live settlement caller** (2026-08-25,
  a further follow-up pass) — closes the gap this note used to describe.
  `ConstructionPriority` also grew one small additive method,
  `missing_structure_id` (same "does not change `decide`'s own signature or
  behavior" shape `Quest.deeper_need_for` already established next to
  `production_shortfall_quests_for`): for a `BUILD_PRODUCER_FIRST` result,
  names the SPECIFIC structure id blocking it (or `""` for a skill-only
  gate, or for an abstract multi-structure category like `"heat_source"`
  that doesn't map to one concrete recipe — a named, honest limitation, see
  its own test/doc comment) by reading the same `NeedResolver` walk
  `decide` already runs. See the "Settlement construction ledger" section
  below for the real, tested caller this feeds.

## Interaction with other docs

- **[building.md](building.md)** — this doc adds sourcing, physics, decay,
  and incremental/autonomous building on top of its piece/placement/room/
  persistence mechanism; it does not replace any of it. It also closes
  that doc's own documented gap — village stamping bypassing
  `BuildingPlacement.can_place` — by routing every NPC-built piece through
  real placement *and* statics validation.
- **[materials.md](materials.md)** — reuses its already-declared
  `Decay/weathering rate` scalar and `Topple / collapse` verb rather than
  inventing parallel ones. The statics model here ships first as a
  simpler fixed span/support-count approximation; once materials.md's
  property-vector threshold curves land, span capacity can be derived from
  a piece's real hardness/toughness instead — a staged upgrade, not a
  divergence.
- **[ecosystem_dynamics.md](ecosystem_dynamics.md)** /
  **[world.md](world.md)** — the offscreen catch-up here is a direct
  sibling of `chunk_ecology_catchup.gd`, reusing its two-fidelity
  philosophy and its bounded-integration-cap precedent exactly. The new
  logger occupation draws down the same vegetation grid, so deforestation
  near a large village is visible in the ecosystem simulation itself, not
  a separate stat.
- **[npc.md](npc.md)** — builder is a new producer-shaped occupation on
  `NpcProduction`'s existing pattern. Settlement growth (population
  rising) is what raises a settlement's `builder_count` in the offscreen
  catch-up, directly tying construction speed to the population-growth
  mechanism npc.md already specifies, rather than a separate number.
- **[docs/emergence/00-emergence-architecture.md](../emergence/00-emergence-architecture.md)**
  / **[04-settlements-cities-infrastructure.md](../emergence/04-settlements-cities-infrastructure.md)**
  — this doc is the concrete implementation of Layer 0's "construction"
  line and of Layer 5's Infrastructure section, for player-visible
  buildings specifically. Roads, bridges, wells, and full city-threshold
  mechanics stay out of scope here — that is Phase 8 ("Infrastructure
  networks") and Phase 9 ("Towns & cities") in `docs/progress.md`, a
  sibling system this doc deliberately does not absorb.
- **[persistence.md](persistence.md)** — "save what can't be regenerated,
  skip what can." A `ConstructionProject`'s accumulated labor-hours,
  condition, and founding tick must persist — they cannot be re-derived.
  A *completed* house's piece layout needs no separate save slot beyond
  the chunk-modification persistence `building.md` already has, since
  `HouseBlueprint` deterministically regenerates identical pieces from
  `(seed, footprint)` exactly as it does today.

## Worked examples

**A. Player builds by hand.** A player fells an oak, works its trunk up
into logs at their own campsite, carries them to a hewing block, shapes
four Balken (slow — hewing) and six Planke (fast — riving), and raises a
one-room hut: four corner posts (Balken, load-bearing) infilled with plank
walls and a plank floor. The statics graph accepts it because every wall
segment sits within its span limit of a corner post. Nothing here differs
from how an NPC does the same thing — same pieces, same placement checks.

**B. An onscreen NPC builder.** Astrid, a villager with a live shelter
need, walks to the treeline at the chunk's edge, fells a young birch (a
smaller haul than an oak — `wood_for(growth_scale)` already scales this),
carries the logs to the village's sawpit, shapes them over several
in-game minutes, then carries a Balken to her building's northeast corner
and places it. If she (or the player, doing the same thing) tries to
cantilever a plank floor two tiles past the last supporting post, the
statics check refuses the placement outright — visible, immediate feedback
that teaches the mechanic without a tooltip.

**C. Discovering a never-loaded settlement.** A player walks into a chunk
founded 40 in-game days ago with six households, never once loaded before.
`construction_catchup.advance` integrates 40 days of `builder_count`
(derived from those six households) against the local forest density,
producing: three completed houses, one in-progress (walls up, no roof),
and a stockpile of eleven Balken sitting at the worksite. All three
completed houses are stamped via the ordinary `stamp_structure_at_global`
call, aged by their own completion time (the oldest shows a little
condition loss on its roof already). Reloading the same chunk with the
same elapsed time reproduces the identical village — nothing here is
rolled once and cached.

**D. Withering and cascading collapse.** A household dies out
(`npc.md`'s lifecycle section) and its house's ownership goes unclaimed.
With no maintenance and no roof shelter for its own walls once the roof
itself starts failing, condition decays fastest at the exposed roof edge.
Once a wall's condition crosses zero it collapses, dropping its Balken
back to the ground as loose material — and the statics recompute this
triggers finds the roof section it was holding up now unsupported, which
comes down in turn. What a returning player finds is a genuine partial
ruin: three walls standing, one gone, roof caved on that side, exactly the
shape a real abandoned timber building decays into.

## Open questions

- **Who becomes a builder?** A dedicated occupation slot competing with
  farmer/hunter/fisher for population, or an ad hoc task any idle
  non-producer NPC picks up once a household's shelter need crosses a
  threshold (mirroring the existing replan-interrupt pattern from
  `npc.md`'s settlement-growth section)? Leaning toward ad hoc — shelter
  is a need, not a profession — but undecided.
- **Do player-placed pieces wither too?** Settled by implementation
  (2026-08-25): yes — `BuildingDecay`'s catch-up runs over every real piece
  in `chunk.modifications` with no placer distinction, "one system, two
  builders" applied literally. Still genuinely open: the player-facing
  warning this turns into a real survival loop needs (a creak before a
  collapse, not a silent surprise on return from a long trip) — nothing
  reads `piece_condition_at_global` for UI/audio feedback yet.
- **Collapse safety.** Should a falling piece deal real momentum damage
  to whoever's standing under it, per `materials.md`'s one damage model —
  or is that a frustration risk worth a grace window first? Deferred to a
  combat-adjacent decision, not settled here.
- **Tool-tier gating.** Does shaping a Balken need a dedicated tool (an
  adze or saw, beyond the felling axe) per `crafting.md`'s existing
  tool-tier conventions, or does the axe double for shaping too?
- **Forest depletion ceiling.** Should the logger occupation respect
  `land_health` the way farming/grazing already do, so an overbuilt
  village can genuinely deforest its surroundings and face a real material
  shortage — closing the loop with
  [docs/emergence/04](../emergence/04-settlements-cities-infrastructure.md)'s
  Decline section? Proposed yes, not yet speced in the detail that section
  would need.
- **Multiplayer/authority.** Out of scope for this pass — the project is
  effectively single-player-simulated today — but the catch-up model's
  determinism is exactly what would make a later authoritative-server
  version safe.

## Status

🚧 A scoped MVP slice is real: the Sägewerk worksite, its Lumberjack NPC,
real timber building pieces, a real, generic, now-live end-to-end
Storage/Logistics/dependency-chain-priority layer, real statics — a support
graph over the piece grid, with real grace-period collapse and material
drop-back — real withering (a closed-form decay catch-up feeding that same
collapse path), and the settlement construction ledger with
`ConstructionPriority.decide`'s first real, live caller (all landed
2026-08-25, across three follow-up passes). Everything else this doc
describes (offscreen construction catch-up, and autonomous NPC
house-building beyond gathering — `CARRY_MATERIAL`/`PLACE_PIECE` and
retiring `VillageRenderer._stamp_house`) is still ⬜, exactly as specified
below — deliberately left alone this pass, not silently dropped.

- ✅ **The Sägewerk worksite** — the doc's own generic "sawpit/hewing-block"
  prop, named and built concretely as `sagewerk` (`item_catalog.gd`'s
  `"placeable"` kind, `ProceduralStructureSprite.STRUCTURE_IDS`,
  `CraftingRecipeBook`'s `sagewerk` recipe costing real logs). Placed the
  same way campfire/furnace are — a tile via `EarthChunkManager.
  build_at_global`, no new scene.
- ✅ **The Lumberjack NPC** — `LumberjackMarker`
  (`src/rendering/lumberjack_marker.gd`), a small purpose-built walker
  mirroring `DecomposerMarker`'s own shape (not the full `NpcMarker` daily-
  schedule stack). Its SEEKING → APPROACHING → FELLING → CARRYING →
  DEPOSIT loop is `LumberjackBehavior`
  (`src/gameplay/lumberjack_behavior.gd`), pure and unit-tested. FELLING
  calls the *same* `ChoppableTree.take_damage` loop `Player._chop_step`
  uses — an NPC swinging an axe really is the same mechanic, a different
  caller, exactly as this doc's own mechanism section frames it. It fells
  and buck-cuts into plain `log` items the ordinary way (deliberately does
  NOT use the player's saw+Carpentry `saw_up` shortcut).
- ✅ **One Lumberjack per placed Sägewerk, "an NPC moves in"** —
  `EarthChunkManager._sagewerk_lumberjacks` (chunk_coord → {local_cell →
  LumberjackMarker}) spawns one the moment a `sagewerk` tile is built,
  scans persisted modifications for any already there on `_load_chunk`
  (a revisited Sägewerk gets re-staffed, not left abandoned), and
  despawns/frees its worker on destroy, overwrite, or chunk unload. No
  hiring/wage/relationship system — `npc.md`'s own hiring section stays
  untouched and out of scope, exactly as this doc's own open question
  ("who becomes a builder?") left ad hoc.
- ✅ **Sägewerk production: log → Balken/Planke** — `SagewerkProduction`
  (`src/world/sagewerk_production.gd`), pure, mirrors `npc_production.gd`'s
  rate-formula shape. Grounded in the doc's own "hewing vs. riving"
  section: a Balken costs more log stock (`LOG_COST_PER_BEAM` >
  `LOG_COST_PER_PLANK`) and takes longer to shape
  (`SHAPE_SECONDS_PER_BEAM` > `SHAPE_SECONDS_PER_PLANK`) than a Planke,
  both pinned by tests rather than eyeballed. Runs continuously while the
  marker exists (staffed == the marker's presence, no separate flag); real
  output credits `StructureStock` at the Sägewerk's own tile position (via
  `EarthChunkManager.deposit_to_structure_at`) — migrated off the earlier
  `WorldItemBus` ground-drop so a Logistics worker's own `SEEKING` step has
  real stock to find (see the "Storage, logistics, and the autonomous
  dependency chain" section's own status below). A player without
  Storage/Logistics built yet collects it directly via
  `Player._collect_step`.
- ✅ **Real consumers for beam/plank** — `BuildingPiece`'s new
  `timber_wall` (costs `beam`, load-bearing per pillar 1) and
  `timber_floor` (costs `plank`, non-structural), appended to `PIECE_IDS`.
  Durability sits between the wood and stone tiers. Now also carries the
  real `support_capacity` field the "Real statics" section below consumes
  (see that bullet) — the load-bearing/support-capacity field this entry
  used to say was deliberately deferred is real now.
- ✅ **Real statics** (a support graph over the piece grid) — real
  (2026-08-25 follow-up pass), not the "stands because it was placed"
  status quo pillar 2 called out. `BuildingPiece` gains a `support_capacity`
  field (`is_load_bearing`/`support_capacity_of`), additive to the existing
  category/material/encloses/walkable/durability/cost shape and regression-
  tested for every existing piece id: every `CATEGORY_WALL` piece across
  all three material tiers (wood/stone/timber) is load-bearing, mirroring
  its own already-tuned durability number rather than a fresh eyeballed
  one — generalizing pillar 1 beyond just the timber tier, exactly as
  asked. `BuildingStatics`
  (`src/gameplay/building_statics.gd`, `tests/unit/test_building_statics.gd`)
  is the new pure module: reuses `RoomDetector`'s grid-over-local-cells
  shape and 4-neighbor flood-fill approach, but the traversal answers "does
  this load-bearing cell have a path of adjacent load-bearing cells back to
  a grounded cell within `MAX_UNSUPPORTED_RUN` (4, grounded in real
  half-timbered bay spacing)" instead of enclosure; a non-load-bearing
  piece (floor/roof/door/window) needs a SUPPORTED load-bearing cell within
  its own shorter `CANTILEVER_LIMIT` (3, real floor-joist-reach grounding,
  calibrated against every actual `HouseBlueprint` — see that constant's
  own doc comment for a real regression this calibration caught: a tighter
  literal reading of Worked Example B's "two tiles" language flagged
  already-shipped village houses' own dead-center floor tiles as
  permanently unsupported). Ships as one fixed span for every
  material this pass — `support_capacity` is real and regression-tested but
  not yet consumed by the span computation itself, exactly the "simpler
  fixed span/support-count approximation" this doc's own "Interaction with
  other docs" section on materials.md already named as the first-ship
  shape, staged for a later upgrade once materials.md's property-vector
  curves land.

  A piece that loses its support path does not vanish: `BuildingStatics.
  resolve` accumulates real instability (seconds continuously unsupported)
  and, past `GRACE_SECONDS` (6, a real grace window), collapses — the
  `Topple / collapse` verb, not a bespoke "building HP" system. A collapse
  drops its own constituent material back to the ground (`BuildingPiece.
  cost_of` reversed, via the exact same `WorldItemBus.item_dropped` path
  `_resolve_caravan_raid` already uses) and the SAME `resolve()` pass finds
  the whole cascade at once (a piece can only ever be a valid support
  stepping-stone by being supported itself, so an unsupported chain and
  everything cantilevered off it are already flagged together) — Worked
  Example D's "the roof section it was holding up now unsupported, comes
  down in turn" resolves within one call given enough elapsed time, no
  second manual trigger required.

  Event-driven, not per-tick: `EarthChunkManager._sync_statics` hooks
  `build_at_global`/`destroy_at_global`/`stamp_structure_at_global`
  (mirroring the existing `_sync_sagewerk_lumberjack`/
  `_sync_logistics_workers` call-site convention exactly), scoped via
  `_structure_statics_view`'s own flood-fill to just the touched
  structure's own connected piece grid — O(structure size), never the
  whole chunk. Real per-cell instability/last-checked-at tracking lives on
  `Chunk` (`structural_instability`/`structural_checked_at`), read against
  the real world-age clock (`advance_world_age`), not a fixed per-event
  tick — so a piece genuinely needs real elapsed time unsupported before it
  collapses, not just "an edit happened."

  **Named, honest limitation**: the grace clock only actually gets
  re-checked when a build/destroy/stamp event touches that structure's own
  connected piece grid again — there is no independent per-frame poll (yet)
  driving an idle, untouched at-risk structure's own clock forward on its
  own. In real play this means an unsupported piece with no further nearby
  edits sits "creaking" (correctly flagged, correctly not yet collapsed)
  until something else disturbs that structure; a lightweight periodic
  poll over just the currently-at-risk cell set (bounded, not O(chunk))
  would close this gap and is the natural next step, deliberately left out
  of this pass's scope. Also does not yet read `roof_modifications` (a
  separate per-cell dict from `modifications`, see `chunk.gd`) into the
  statics grid — roof pieces are not yet statics-checked; only
  wall/floor/door/window pieces (`modifications`) are. Withering/decay
  (2026-08-25 follow-up pass) is now real too and feeds this same collapse
  path exactly as this framing predicted — see its own entry below, which
  inherits this same roof-pieces gap for the identical reason.

  Real, tested: `tests/unit/test_building_piece.gd` (the new field, every
  piece id, regression), `tests/unit/test_building_statics.gd` (18 tests:
  supported/severed detection, the cantilever rule, grace-threshold timing
  across successive calls, cascade-in-one-call, determinism, the three
  calibration constants), `tests/unit/test_house_blueprint.gd`'s new
  `test_every_blueprint_is_fully_statically_supported` (every real
  `HouseBlueprint` shape across 30 seeds validates as fully standing — the
  actual calibration guard behind `CANTILEVER_LIMIT`'s chosen value, not
  the number alone), and `tests/unit/test_earth_chunk_manager.gd`'s new
  "real statics" section (grace delay before collapse, a real collapse
  dropping the wall's own `cost_of` material via `WorldItemBus`, the
  cascade at the engine level, and collision-body cleanup on collapse).
- ✅ **Withering/decay** (`condition`, the closed-form catch-up decay curve)
  (2026-08-25 follow-up pass). `Chunk` gains `piece_condition`/
  `piece_condition_checked_at` (local cell -> float / world-age), the exact
  same "value + last-checked-at" pairing `structural_instability`/
  `structural_checked_at` already established for statics. `BuildingDecay`
  (`src/gameplay/building_decay.gd`, `tests/unit/test_building_decay.gd`,
  21 tests) is the new pure module: the EXACT closed-form shape
  `chunk_ecology_catchup.gd` uses for vegetation regrowth, decaying toward
  zero instead of growing toward one — `new_condition := condition *
  exp(-decay_rate * exposure_multiplier * elapsed_days)`. `exp(-x)` for
  `x >= 0` is always in `(0, 1]`, so a huge `elapsed_days` jump (tested up
  to 100 years in one call) can never overshoot below zero, never produces
  NaN/Inf, and needs no clamping — exactly the "safe and deterministic in
  one call" property this section asked for.
  `MaterialProperties.MATERIALS` gains a real `"timber"` entry (previously
  absent — a lookup silently fell back to `DEFAULT_PROPERTIES`'
  stone-like `decay_rate=1.0`, an unnoticed but real bug this entry
  closes): shares every property with `"wood"` except `decay_rate` (4.0,
  two-thirds of wood's 6.0 — seasoned, worked timber resists rot better
  than raw green wood but is still organic, nowhere near stone's 1.0),
  test-pinned in `test_material_properties.gd` rather than eyeballed.
  Exposure modulation is real: `BuildingDecay.exposure_for(is_roofed,
  owner_id)` returns `SHELTERED` (0.2x the material's base rate — real
  untreated-wood service-life surveys put a roofed, elevated member at
  roughly 5x the life of the same wood in continuous ground contact/full
  exposure) if EITHER the piece is roofed (caller answers via
  `RoomDetector.find_rooms`) OR belongs to an owned property (caller
  answers via `HouseholdStore.owner_of`), else `EXPOSED` (1.0x, the
  material's own undamped rate) — both multiplier values test-pinned.
  `BuildingDecay.RUINED_CONDITION_THRESHOLD` (0.05, test-pinned) is the
  real collapse trigger in place of an unreachable literal zero (`exp(-x)`
  is asymptotic, never exactly 0 for finite `x`).

  Wired at the exact same unload/reload catch-up boundary the ecology
  precedent already uses: `EarthChunkManager._unloaded_piece_condition`
  (chunk_coord -> `{unloaded_at, condition}`) is `_unload_chunk`'s own
  snapshot, and `_apply_piece_condition_catchup` (called from `_load_chunk`,
  before the first paint/collision pass, mirroring `_apply_ecology_catchup`
  exactly) advances every real placed piece by the actual elapsed
  world-age, capped at the SAME `MAX_CATCHUP_DAYS` (120) the ecology
  catch-up already established — a decade-unloaded structure converges to
  a fixed "ruins" condition in one call, not an ever-precise unbounded
  timer. A piece whose caught-up condition crosses
  `RUINED_CONDITION_THRESHOLD` feeds the EXACT SAME `_collapse_piece`/
  `_sync_statics` path a severed support does (`_apply_piece_condition_
  catchup` calls both directly for each decayed-out cell) — decay and a
  severed support are two INPUTS into one collapse mechanism, not two
  parallel ones, per this section's own framing. `EarthChunkManager.
  piece_condition_at_global` is the new read accessor (1.0 default for an
  unrecorded/unloaded/non-piece cell, matching `structural_instability`'s
  own "absent means default" convention).

  Real, tested: `test_building_decay.gd` (the formula's monotonicity/
  boundedness/determinism, exposure modulation, the ruined threshold,
  timber-vs-wood-vs-stone material grounding), `test_material_properties.gd`
  (the timber entry's pinned `decay_rate` and that every OTHER property
  matches plain wood exactly), and `tests/unit/test_earth_chunk_manager.gd`'s
  new withering section (a freshly-placed piece starts at 1.0, a piece on a
  chunk that never unloads does not decay, a real simulated unloaded
  absence measurably lowers condition, a roofed wall retains more condition
  than a free-standing exposed one over the same absence, a piece decayed
  past the ruined threshold collapses via the real `_collapse_piece` path
  and drops its own `cost_of` material, and a collapsed piece's condition
  is no longer tracked afterward) — all run against the real chunk
  streaming path (`manager.update` to unload, `advance_world_age`, `manager.
  update` to reload), not a stubbed shortcut.

  **Named, honest limitations**: `Chunk.piece_condition`/
  `piece_condition_checked_at` are NOT persisted to disk — the exact same
  class of gap `structural_instability`'s own doc comment already names.
  `EarthChunkManager._unloaded_piece_condition` keeps an IN-SESSION record
  (mirroring `_unloaded_ecology`'s own shape) so a chunk unloaded and
  reloaded within one session still catches up correctly; only a real app
  restart loses accumulated condition. Decay only actually advances at the
  unload/reload catch-up boundary — there is no separate live per-frame
  decay tick for a chunk that stays loaded the whole time, the same
  two-fidelity split `chunk_ecology_catchup.gd` itself uses (and the same
  shape statics' own grace clock already has: it only re-checks when a
  further edit touches that structure). Only `chunk.modifications`
  (wall/floor/door/window) pieces decay — `roof_modifications` is a
  separate per-cell dict `_piece_grid_for` never reads, so roof pieces are
  not yet withering-checked either, mirroring statics' own identical named
  gap exactly. The "owned property" exposure branch is wired to the real
  `HouseholdStore.owner_of` (via a new `_piece_property_id(chunk_coord,
  local_cell)` per-CELL key, the smallest honest thing available before the
  still-⬜ settlement construction ledger's real per-house property
  grouping exists) but no real caller grants ownership under that exact key
  yet, so in real play today this branch always resolves unowned — only
  the roofed branch is actually live; a future settlement-ledger caller (or
  a player claiming a tile with a Deed) makes it live with no changes
  needed here.
- ⬜ **NPC construction beyond gathering** — the Lumberjack's own loop stops
  at DEPOSIT; `CARRY_MATERIAL`/`PLACE_PIECE` (an NPC actually building a
  house piece by piece) are not built. `HouseBlueprint`/
  `stamp_structure_at_global` are unchanged; `VillageRenderer._stamp_house`
  still stamps a complete house for free at generation time — the doc's
  own named anti-pattern this doc set out to retire is **not yet
  retired**.
- ⬜ **Offscreen catch-up** (`construction_catchup.gd`, the two-fidelity
  model) — not built. A Lumberjack's own in-progress state (log stock,
  shaping progress) is not persisted across a chunk unload/reload either —
  a real, documented gap (see `docs/progress.md`), the same class of
  limitation geology's mined-tunnel state already has.
- ✅ **Settlement construction ledger** (2026-08-25, a further follow-up
  pass) — `ConstructionProject`/`ConstructionProjectStore`
  (`src/emergence/`), mirroring `Household`/`HouseholdStore`'s own real
  shape and idempotent-creation/`to_dicts`/`from_dicts` contract exactly:
  a project is keyed deterministically off its own site (chunk_coord +
  footprint origin) and `blueprint_id` (a real `CraftingRecipeBook` recipe
  id, not a second vocabulary), carries a real `PLANNED`/`IN_PROGRESS`/
  `COMPLETE`/`ABANDONED` status, `labor_hours_accumulated`, and
  `reserved_material`. `ConstructionProjectStore.complete_project` calls
  the already-correct `HouseholdStore.grant_property(household_id,
  "house_<chunk>_<origin>")` unchanged, per this section's own "Ownership"
  paragraph. `ConstructionStartHysteresis`
  (`src/emergence/construction_start_hysteresis.gd`) is
  `InstitutionFormation`'s own asymmetric hysteresis PATTERN applied to a
  real number instead of shared FULFILLED-contract counts: local material
  stock crossing a blueprint recipe's own input requirement to start,
  dropping WELL below it (a test-pinned `ABANDON_FRACTION`, not a fixed
  unit gap, since a recipe's own requirement varies wildly by blueprint)
  to abandon — its own small, fresh module, not a reuse of
  `InstitutionFormation` itself (contract-specific).

  **The live wiring**: `SettlementConstruction.advance`
  (`src/emergence/settlement_construction.gd`) is `ConstructionPriority.
  decide`'s first real, live caller (closing this doc's own
  previously-named gap) — a static-function module, the same explicit-
  dependencies-in shape `Quest.gd`'s `production_shortfall_quests_for`/
  `deeper_need_for` already use. Given a settlement's real `VillageMarket`
  stock, its present structure ids, and a candidate blueprint to build
  next at a real site, it calls the real `ConstructionPriority.decide` and
  acts on all three real outcomes: **READY** starts (or continues) a real
  `ConstructionProject`, gated by `ConstructionStartHysteresis` rather than
  an eyeballed assumption that `decide()==READY` always implies the
  recipe's own direct inputs are covered (a real edge case this gate
  catches: `decide`'s own "already-stocked output" shortcut can report
  READY off an already-sufficient OUTPUT stock with the recipe's own INPUT
  completely absent — the gate refuses to draw down material that isn't
  really there), and on passing draws the recipe's real inputs down from
  `VillageMarket` (via a new `VillageMarket.remove_stock`, mirroring
  `StructureStock.remove_stock`'s own all-or-nothing contract exactly),
  recording them as the project's own `reserved_material`. **
  BUILD_PRODUCER_FIRST** is this section's own actual payoff, and
  `production_chains.md`'s "a resolver, not a solver" pillar's real
  consequence made concrete: `ConstructionPriority.missing_structure_id`
  names the specific blocking structure, and a real `PLANNED`
  `ConstructionProject` is queued for THAT producer, ahead of the project
  that needed it (idempotent — a repeat call while still missing returns
  the same queued project) — a missing SKILL (no structure to queue) is
  surfaced plainly instead of silently no-op'ing. **SHORTFALL** never
  mutates `VillageMarket` (the existing regional-trade/shortfall path
  already covers a pure materials gap, per this section's own framing) —
  its only real action is retiring an already-PLANNED (materials not yet
  committed) project via `ConstructionStartHysteresis.should_abandon` when
  local stock has genuinely collapsed well below the recipe's own
  requirement; a project already `IN_PROGRESS` has already reserved what
  it needs and is left alone regardless of how the SHARED stock pool reads
  afterward (a real scenario this pass tests directly: a project's own
  drawdown of the last shared units must not immediately read back as a
  shortfall crash against itself).

  **Named, honest limitations, not silently glossed over**: the queued
  producer project's own footprint `origin` is bookkeeping, not real
  siting — this pass does not build a placement/collision algorithm for
  where a producer structure should actually go (explicitly out of scope,
  same as the rest of this list's still-⬜ items below). `labor_hours_
  accumulated` and `reserved_material` are real fields nothing yet
  advances further once a project is `IN_PROGRESS` — that is `construction_
  catchup.gd`'s own job (offscreen catch-up, still ⬜ below); this pass
  builds the ledger and the live decision wiring, not the labor-accrual
  loop that would carry a project to `COMPLETE` on its own. No persistence
  wrapper (`ConstructionProjectStorePersistence`) or `EarthChunkManager`
  save/load wiring exists yet — `to_dicts`/`from_dicts` are real and
  tested in isolation (mirroring `HouseholdStore`'s own split) but nothing
  currently calls them from a save path, the same "additive capability,
  no live caller yet" honesty this doc's own `NeedResolver`/`Quest.
  deeper_need_for` entries already carry. And per this doc's own explicit
  scope for this pass: nothing here is wired into `VillageRenderer.
  _stamp_house` or any chunk-generation call site — that migration stays
  a documented future step (see "Known anti-pattern this doc replaces"
  below), not attempted this pass. Real, tested:
  `tests/unit/test_construction_project.gd`,
  `tests/unit/test_construction_project_store.gd`,
  `tests/unit/test_construction_start_hysteresis.gd`,
  `tests/unit/test_settlement_construction.gd` (15 tests covering all
  three `ConstructionPriority.Priority` outcomes end to end), plus the new
  `missing_structure_id` cases in `test_construction_priority.gd` and the
  new `remove_stock` cases in `test_village_market.gd`.
- ⬜ **Multiple lumberjacks per settlement** — out of scope for this pass;
  today's model is exactly one worker per Sägewerk instance. Two Sägewerke
  close enough together may have their Lumberjacks compete for the same
  standing tree (each independently targets its own nearest one, with no
  coordination) — a known, accepted edge case, not a crash risk.
- ⬜ Most of this doc's own "Open questions" remain genuinely open (who
  becomes a builder as a real occupation vs. ad hoc, collapse safety/
  momentum damage, tool-tier gating on shaping, forest depletion ceiling
  via `land_health`, multiplayer authority). One is now settled by
  implementation: player-placed pieces do wither too (see the Withering/
  decay entry above) — its own player-facing warning UX is what remains
  open there.
- ✅ **Storage, logistics, and the dependency-chain priority function** (see
  that section's own "What's honestly still a stand-in here" for the full
  account): Storage (a real placeable structure with a real per-instance
  stock), the Logistics worker (a real, tested SEEKING→APPROACHING→
  COLLECTING→CARRYING→DEPOSITING state machine plus engine glue), and
  `ConstructionPriority.decide` (the dependency-chain priority function)
  are all real and tested — and now live end to end: the Sägewerk's real
  output credits `StructureStock` (migrated off the old `WorldItemBus`
  ground-drop, with `Player._collect_step` as the direct-pickup fallback
  for a player with no Storage/Logistics yet), a Sägewerk+Storage pair
  auto-spawns exactly two Logistics workers
  (`EarthChunkManager._resync_logistics_for_sagewerk`, mirroring the
  Sägewerk/Lumberjack sync wiring), and `ConstructionPriority.decide` now
  calls the real, general `NeedResolver` instead of `Smelting.can_smelt`.
  `ConstructionPriority.decide` now DOES have a real, live settlement
  caller (2026-08-25, a further follow-up pass): `SettlementConstruction.
  advance` (`src/emergence/settlement_construction.gd`) — see the
  "Settlement construction ledger" section's own entry below for the full
  account of `ConstructionProject`/`ConstructionProjectStore` and this
  wiring, closing the gap this paragraph used to name.
  The previously-named constraint here (a Sägewerk pairing with only its
  single nearest Storage) is closed (2026-08-25): a Sägewerk now pairs
  with EVERY real Storage within `SAGEWERK_STORAGE_PAIR_RADIUS_TILES` (see
  this section's own account above).

Reusable primitives already in the codebase this system should build on,
not reinvent:

- `FelledTree`/`ChoppableTree` (`src/rendering/felled_tree.gd`,
  `choppable_tree.gd`) — the log source.
- `BuildingPiece`/`BuildingPlacement`/`RoomDetector`/`HouseBlueprint`/
  `EarthChunkManager.stamp_structure_at_global` (`src/gameplay/`,
  `src/world/earth_chunk_manager.gd`) — the piece vocabulary, placement
  validity, enclosure, blueprint generation, and batched-stamp rendering.
- `chunk_ecology_catchup.gd` — the exact offscreen catch-up shape
  (`advance(state, elapsed_seconds, capacity) -> Dictionary`, pure,
  closed-form, bounded) to mirror for construction.
- `BuildingDecay`/`BuildingStatics` (`src/gameplay/`) — withering's own
  real, tested closed-form decay module and the collapse mechanism it
  feeds; a settlement-decision construction catch-up should read
  `piece_condition_at_global`/collapse the same way rather than a third
  aging model.
- `HouseholdStore.grant_property` (`src/emergence/household_store.gd`) —
  house ownership, already correct as-is.
- `InstitutionFormation` (`src/emergence/institution_formation.gd`) — the
  hysteresis-threshold *pattern* `ConstructionStartHysteresis`
  (`src/emergence/construction_start_hysteresis.gd`) already reuses for
  "should this household start building" (see Status).
- `NpcProduction`/`VillageMarket` (`src/world/`) — the producer-occupation
  → yield → shared-stock pattern a `logger` occupation and lumber stockpile
  should follow. `VillageMarket.remove_stock` (real, see Status) is the
  all-or-nothing draw-down `SettlementConstruction.advance` already uses
  against it, mirroring `StructureStock.remove_stock`'s own contract.
- `SettlementState` (`src/emergence/settlement_state.gd`) — the pure
  capacity-classifier shape a builder-count derivation should follow.
- `Quest.production_shortfall_quests_for`/`Market.stock_of`
  (`src/emergence/quest.gd`, `market.gd`) — the exact shortfall-detection
  shape the dependency chain's own "is this settlement missing a real
  input" check reuses, not a second one.
- [production_chains.md](production_chains.md) (real sibling doc, merged
  to `main`) — the general recipe-requirement/dependency-resolution
  mechanism (`NeedResolver`, `CraftingRecipeBook`'s `requires_structure`/
  `required_skill` fields) this doc's Sägewerk skill-gate already uses and
  `ConstructionPriority.decide` should be rewired to use (see Status).
- `StructureStock`/`StructureStockStore` (`src/emergence/`) — Storage's real
  per-instance stock, and the shape any future production structure should
  reuse for its own accumulated-output queue rather than a third design.
- `LogisticsBehavior`/`LogisticsMarker` (`src/gameplay/`,
  `src/rendering/`) — the real, tested collect/carry/deposit worker; assign
  a `source_structure_id`/`item_id` to it once a real producer credits
  `StructureStock`. `LogisticsMarker.preferred_storage_position` pins a
  specific worker to a specific Storage when a caller has already paired
  them (see Status).
- `EarthChunkManager.nearby_structure_positions` (`src/world/`) — the
  ALL-matches counterpart to `nearest_structure_position`; use this
  whenever a caller needs every real structure of a given id in range, not
  just the closest.
- `ConstructionPriority` (`src/gameplay/construction_priority.gd`) — the
  real, tested dependency-chain priority function, rebuilt on the real
  `NeedResolver`, and (see Status) now with a real live settlement caller,
  `SettlementConstruction.advance`.
- `ConstructionProject`/`ConstructionProjectStore`
  (`src/emergence/construction_project.gd`,
  `construction_project_store.gd`) — the real settlement construction
  ledger (see Status); mirrors `Household`/`HouseholdStore`'s own shape and
  idempotent-creation contract exactly.
- `SettlementConstruction` (`src/emergence/settlement_construction.gd`) —
  the real, tested live caller of `ConstructionPriority.decide` (see
  Status); the entry point a future settlement-decision system (e.g. a
  household's own "what should my village build next" loop) should call
  rather than re-deriving this reasoning itself.

**Known anti-pattern this doc replaces**: `VillageRenderer._stamp_house`
currently stamps a complete house, instantly and for free, at settlement
generation time (see `docs/progress.md`'s NPC section). Implementing this
doc means that call site changes to seed a `ConstructionProject` at
founding time instead of stamping on the spot — a deliberate, acknowledged
behavior change, not an oversight to preserve.
