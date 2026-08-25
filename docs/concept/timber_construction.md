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

### Deciding what to build, and who builds it

Compiled from a follow-up design-brainstorm session, answering this
section's own two still-named gaps: nothing decided WHICH project a
settlement should start next, and nothing decides WHO becomes a Builder.

**The first gap is closed** (2026-08-25, a further follow-up pass):
`SettlementSpareCapacity`/`SettlementBuildDecision` are real, tested, and
wired at the real chunk-load boundary — see "What's honestly still a
stand-in here" below for the exact account of what actually runs today (and
the real, honest reasons it rarely finds anything actionable yet in live
play). **The second (who becomes a Builder, a live BuilderMarker spawner,
and player-hired Builders) stays exactly as designed below and genuinely
unimplemented** — deliberately out of scope for this pass: every real
structure this decision function can currently queue is a single-tile
placeable the ALREADY-REAL offscreen labor catch-up completes in one shot
(`_place_completed_construction_project`/`build_at_global`), so there is no
real multi-piece target yet for an onscreen `BuilderMarker` to place
piece-by-piece the way `_stamp_house`'s own retirement pass explicitly kept
house construction OUT of this ledger (to avoid a real house-id-scheme
collision, see that entry's own account below) — a future pass that gives
multi-piece, ledger-tracked construction a real target to place is what
would finally need a live spawner and Builder assignment, not this one.

**What to build: shortfall names it, population gates it.** Two real
signals feed one decision, not two competing ones. `Quest.
production_shortfall_quests_for`'s own `"missing"` list already carries a
real magnitude per gap (`need := input["count"] - have`, not just an item
id) — that's the ranking a settlement needs with no new number to invent:
among several real shortfalls at once, the one with the largest `need`
wins. Population is the second, independent gate: a settlement only
*acts* on the worst shortfall once it has real spare capacity (see next
paragraph) to spend on it — a healthy, well-fed settlement with room to
grow builds; one at subsistence does not, no matter how bad its shortfall
is. This was `SettlementConstruction.advance`'s own still-missing candidate
`blueprint_id` argument — **now real** (2026-08-25):
`SettlementBuildDecision.decide_and_advance` (`src/emergence/
settlement_build_decision.gd`) is exactly this reasoning made concrete —
flattens every real shortfall quest's own `missing` list (worst `need`
first), skips any item with no real recipe producing it (a pure
raw-material issue, left to the existing shortfall/regional-trade path
unchanged, per this paragraph's own framing), and for the first item whose
recipe resolves a real `ConstructionPriority.missing_structure_id`, supplies
it as `SettlementConstruction.advance`'s own candidate `blueprint_id` —
giving `ConstructionPriority.decide`'s live caller a real settlement-decision
system to sit inside instead of only being reachable with a caller-chosen
candidate. See "What's honestly still a stand-in here" below for the exact,
honest account of how far this actually reaches in live play today.

**Spare capacity: a real derived number, the same style
`SettlementState.carrying_capacity` already uses.** Not a flat ratio.
`household_count_for_settlement(settlement_id)` (already real) minus
however many of those households are currently needed for real survival
occupations (farmer/hunter/fisher — the subset of `NpcProduction.
PRODUCER_ITEM_BY_OCCUPATION` that feeds the settlement's own food stock,
which `SettlementState.carrying_capacity` already reads) is the real spare
count. Zero or negative spare capacity means no Builder exists right now —
construction is a genuine luxury of a settlement with room to grow, never
a competing priority against the survival occupations `carrying_capacity`
itself depends on. This composes cleanly with `MAX_CATCHUP_DAYS`-style
integration for free: a `builder_count` of zero is not a special "paused"
state needing its own status or cancellation logic — `ConstructionCatchup.
advance`'s own real formula already treats zero builders as zero progress
for that call, and resumes exactly where it left off the moment spare
capacity is positive again (a famine, a raid, or a migration wave all fall
out of the SAME real number, with no new mechanism).

**Real, tested** (2026-08-25): `SettlementSpareCapacity.for_settlement`
(`src/emergence/settlement_spare_capacity.gd`) is exactly this formula —
`household_count_for_settlement` minus however many of those households
work a real survival occupation, read straight off `NpcProduction.
PRODUCER_ITEM_BY_OCCUPATION`'s own keys (not a second, hand-maintained
`["farmer", "hunter", "fisher"]` list that could drift from it), clamped at
zero. This ALSO closed a real, live bug this exact paragraph's own reasoning
named but `EarthChunkManager._apply_construction_labor_catchup` never
actually implemented: that function was passing `builder_count` as
`household_count_for_settlement` — TOTAL population, not spare capacity —
so construction labor was silently competing with the survival occupations
this paragraph says it never should. Corrected: a settlement whose entire
population works a real survival occupation now correctly accrues ZERO
construction labor even though `household_count_for_settlement` is
genuinely nonzero (real, tested — `test_earth_chunk_manager.gd`'s own
"corrected builder_count" section).

**Builder is ad hoc, not a fixed occupation.** Matches this doc's own
Open Questions section's existing lean ("shelter is a need, not a
profession"), settled here: an idle NPC not currently needed for a real
occupation picks up Builder duty only while a real project exists and
spare capacity covers it, then reverts — the same replan-interrupt shape
`npc.md`'s own migration section already names as the mechanism for a need
crossing a threshold reassigning an NPC, applied to construction instead
of migration. `Builder` is *not* added to `NpcProduction.
PRODUCER_ITEM_BY_OCCUPATION` — that table maps an occupation to the item it
produces, and a Builder doesn't produce an item, it consumes real material
and produces a placed structure; it is its own category, not a fourth
producer row.

**Multiple Builders may pool effort on one project.** Unlike one-
Lumberjack-per-Sägewerk, a large project may be worth more than one pair
of hands. This needs less new mechanism than it sounds: each Builder's own
`PLACING` step already operates on one piece at a time from a shared
target dict, and `ConstructionProjectStore.advance_project_labor_for_piece`
already clamps `labor_hours_accumulated` at the real required total
regardless of how many separate calls credit it — several Builders
crediting the same project concurrently is already safe under today's real
code, not a new completion-math problem. The new work is purely on the
assignment side: allowing N idle-and-spare NPCs to be assigned to the same
`ConstructionProject`, not just one.

**Two real needs resolving each other: the settlement's own project gets
cancelled, not left redundant.** If a settlement is already building its
own missing producer (say, a second Sägewerk) and the player independently
brings/builds the same real fix first, `ConstructionPriority.decide`
re-evaluated against the now-current structure list simply stops reporting
`BUILD_PRODUCER_FIRST` for it — the settlement's own redundant `PLANNED`/
`IN_PROGRESS` project for that structure is abandoned (the real `ABANDONED`
status `ConstructionProject.Status` already has) the next time this
decision loop runs, the same way `SettlementConstruction._handle_shortfall`
already abandons a project whose material has genuinely crashed. No second
Sägewerk silently appears because the player got there first.

**Real, tested** (2026-08-25): composed into `SettlementBuildDecision.
decide_and_advance`'s own same call, running unconditionally (independent of
spare capacity — retiring wasted work needs no population headroom). Every
real `PLANNED`/`IN_PROGRESS` project at a site whose `blueprint_id` names a
real structure-producing recipe AND is a genuine producer-fix target (some
real recipe in the book actually `requires_structure` it) is re-checked
against `ConstructionPriority.missing_structure_id` for that dependent
recipe with the CURRENT `present_structure_ids`; once the structure is no
longer missing, `ConstructionProjectStore.abandon_project` (a new small,
tested method, lifted out of `_handle_shortfall`'s own inline
`project.status = ABANDONED` mutation so both real triggers — a material
crash, or a double-fix — share one real action) retires it. Deliberately
scoped to structures SOME real recipe actually gates on — a structure
nothing gates on (e.g. `"storage"`, which has no skill/structure
prerequisite of its own) is never swept, since a settlement may legitimately
want a SECOND one (`EarthChunkManager.nearby_structure_positions` already
supports multiple real Storages per settlement — a real feature, not a
redundancy).

**Silent by design.** No quest, no popup — a settlement deciding to build
is discovered the same way village growth already is: you notice the new
or half-finished structure next time you visit. Matches this doc's own
"the game is not lying to the player about what happened off-screen; it is
computing it cheaply" pillar exactly.

**Player-hired Builders, on a player's own structure.** A real, later
extension of the same mechanism, not a separate system: the player pays
gold to a settlement (via its own `VillageMarket`) to pull one of ITS real
spare-capacity Builders to work at the player's own build site instead of
the settlement's own queue — a genuine trade-off (that settlement's own
construction slows while its Builder works for the player), not a free or
conjured worker. This is the first real, deliberately-scoped crack at the
hiring/wage system `npc.md`'s own hiring section and this doc's earlier
passes both flagged as unbuilt — scoped narrowly to "hire one spare
Builder for one project," not the fuller hiring system those sections
still leave open.

**Deliberately still unbuilt (2026-08-25 pass), and why**: a live
`BuilderMarker` spawner for the projects this decision function queues, and
player-hired Builders. Every real structure this decision function can
currently queue (`storage`; `sagewerk` is skill-blocked, see the "Spare
capacity" entry's own real limitation above) is a SINGLE-TILE placeable,
built in one shot by the ALREADY-REAL offscreen labor catch-up
(`_place_completed_construction_project` calling `build_at_global` once
`labor_hours_accumulated` clears the requirement) — there is no real
multi-piece target for an onscreen `BuilderMarker` to place piece-by-piece
here, unlike `_stamp_house`'s own house-construction case (deliberately kept
OUT of `ConstructionProject`/`ConstructionProjectStore` during its own
retirement, to avoid a real house-id-scheme collision, see that entry's own
account below). Both stay genuinely blocked on a future pass that gives
multi-piece, ledger-tracked construction a real target to place, not
something to fabricate a use case for here.

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
- **"Deciding what to build, and who builds it" now HAS its first two real
  pieces** (2026-08-25, a further follow-up pass) — closes that section's
  own "nothing decides WHICH project a settlement should start next" gap,
  and its own real, honest account of how far this ACTUALLY reaches today:
  - `SettlementSpareCapacity.for_settlement` (`src/emergence/
    settlement_spare_capacity.gd`) is real and tested: `household_count`
    minus however many households work a real survival occupation (read off
    `NpcProduction.PRODUCER_ITEM_BY_OCCUPATION`'s own keys), clamped at
    zero. `EarthChunkManager._apply_construction_labor_catchup`'s own
    `builder_count` — previously TOTAL population, a real bug relative to
    this doc's own design — now reads this instead (real, tested:
    `test_earth_chunk_manager.gd`'s "corrected builder_count" section).
  - `SettlementBuildDecision.decide_and_advance` (`src/emergence/
    settlement_build_decision.gd`) is real and tested: ranks a settlement's
    real shortfalls worst-`need`-first, skips any with no real recipe
    producing the missing item (a pure material issue, left to the existing
    shortfall path), and for the first with a real
    `ConstructionPriority.missing_structure_id`, supplies it as
    `SettlementConstruction.advance`'s own candidate `blueprint_id` if real
    spare capacity is positive (`{"action": "no_spare_capacity"}`,
    distinctly named, otherwise). Composes "double-fix cancellation" into
    the same call (see that paragraph's own "Real, tested" note above).
    Wired at the real chunk-load boundary: `EarthChunkManager.
    _apply_settlement_build_decision`, called from `_load_chunk` on every
    real load of a chunk with real households (not gated on there already
    being `IN_PROGRESS` work, unlike its `_apply_construction_labor_catchup`
    sibling — a settlement with zero in-progress projects still needs a
    real chance to decide whether to start one), using real
    chunk-scanned `present_structure_ids`
    (`_present_structure_ids_for_settlement_chunk`, generalized over every
    real `ItemCatalog` "placeable" id via the same `has_structure_near`
    chunk-scan style, not hardcoded to `"sagewerk"`/`"storage"`).
  - **Named, honest limitation, not glossed over**: `production_shortfall_
    quests_for_settlement`'s own real wiring today
    (`OccupationProduction._RECIPE_BY_OCCUPATION`) only ever grounds
    `"hunter"` → `cooked_meat` and `"blacksmith"` → `stone_pickaxe` — and
    NEITHER recipe's own inputs (`meat`; `stick`/`rock`) are produced by any
    real recipe in the book, so `recipe_book.recipe_for_output` always
    returns `""` for them and this function's "start new work from a real
    shortfall" branch never actually finds an actionable one in live play
    yet. Double-fix cancellation IS real and reachable today regardless (it
    does not depend on the shortfalls feed at all — see that paragraph's own
    "Real, tested" account); "start new work" is real, tested (via directly
    -supplied shortfalls, the same explicit-dependencies-in shape this whole
    module already uses) and will fire the moment a real shortfall-producing
    recipe requiring a SKILL-UNGATED structure exists — it is simply not the
    lived case today, the same honesty this doc's `_stamp_house`
    partial-completion entry below already carries for its own
    rarely-reached branch.
  - **A sharper version of the skill-gate limitation than first written,
    found and fixed while merging this pass (2026-08-25)**: it recurses.
    `SettlementBuildDecision` correctly resolves e.g. `"beam"`'s own missing
    structure as `"sagewerk"` and hands it to `SettlementConstruction.
    advance` as the candidate `blueprint_id` — but `advance` then asks
    `ConstructionPriority.decide("sagewerk", ...)` whether building a
    Sägewerk ITSELF is ready, and that recipe's OWN Carpentry-2.0 gate
    blocks it too (with an empty `allocated_nodes`, exactly the same gate
    the "Spare capacity" entry above already names) — so no project ever
    actually gets queued for `"sagewerk"` specifically, not even `PLANNED`,
    unless a real skill pool clears BOTH the direct recipe AND whatever
    structure it resolves to. Two of this pass's own tests initially failed
    for exactly this reason (expecting a real queued Sägewerk project with
    no skill pool supplied) and were corrected to pass a real
    `allocated_nodes` (`{"carpentry_1": true, "carpentry_2": true}`, the
    same fixture `test_construction_priority.gd`'s own skill-gate test
    already uses) — demonstrating the pipeline genuinely works end-to-end
    once a skill pool exists, while a separate, dedicated test
    (`test_a_carpentry_gated_recipe_is_never_queued_even_as_the_only_
    shortfall`) keeps the honest without-skill-pool case real and covered.
    Practical upshot: with today's real recipe book, `"sagewerk"` is the
    ONLY concrete `requires_structure` target this pipeline could ever
    resolve to, and it is unconditionally skill-gated — so "start new work"
    cannot autonomously succeed in live play until a real settlement-level
    skill/labor source exists, not merely "rarely," full stop. Storage is
    real and skill-ungated but is never anyone's `requires_structure`
    target, so it is never something this pipeline is asked to fix.
  - Also real, tested: the exact "Carpentry-gated recipe is never
    autonomously queued" limitation named in the "Spare capacity" entry
    above (`test_settlement_build_decision.gd`'s own dedicated case, not
    left as a comment alone).
  - Real, tested: `test_settlement_spare_capacity.gd`,
    `test_settlement_build_decision.gd`, `test_construction_project_store.
    gd`'s new `abandon_project`/`active_projects_in_chunk` sections, and
    `test_earth_chunk_manager.gd`'s new "corrected builder_count" and
    "double-fix cancellation" sections (the latter proven against the REAL
    chunk-scanned `present_structure_ids`, not a literal Array a test hands
    the pure decision function directly).
  - Still genuinely unimplemented, deliberately: WHO becomes a Builder (the
    ad hoc replan-interrupt NPC assignment), a live `BuilderMarker` spawner,
    and player-hired Builders — see this section's own "Deliberately still
    unbuilt" paragraph above for the real reason (no multi-piece target for
    a live spawner yet).

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
- **[npc.md](npc.md)** — corrected: Builder is deliberately NOT a fourth
  row on `NpcProduction.PRODUCER_ITEM_BY_OCCUPATION` (see "Deciding what to
  build, and who builds it" above) — it's ad hoc, not a producer occupation,
  assigned via the same replan-interrupt shape npc.md's own migration
  section already names. Settlement growth (population rising) is still
  what raises a settlement's real spare capacity and therefore its
  `builder_count`, directly tying construction speed to the
  population-growth mechanism npc.md already specifies, rather than a
  separate number.
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

- **Who becomes a builder?** Settled by design (2026-08-25, a follow-up
  brainstorm — see "Deciding what to build, and who builds it" above): ad
  hoc, not a dedicated occupation — an idle non-producer NPC picks up
  Builder duty only while a real project exists and real spare capacity
  (population beyond what farmer/hunter/fisher require) covers it, the
  same replan-interrupt pattern `npc.md`'s settlement-growth section
  already names. Design only, not yet implemented.
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
collapse path), the settlement construction ledger with
`ConstructionPriority.decide`'s first real, live caller (all landed
2026-08-25, across three follow-up passes), the offscreen construction labor
catch-up itself — `construction_catchup.gd` plus its real
`ConstructionProjectStore.advance_project_labor` caller (landed 2026-08-25,
a fourth follow-up pass) — which actually carries an `IN_PROGRESS`
`ConstructionProject` to `COMPLETE` over elapsed time, and now (2026-08-25, a
fifth follow-up pass, run in two parallel tracks) two more real pieces: that
catch-up's own real, live `EarthChunkManager` chunk-unload/reload caller
(`_apply_construction_labor_catchup`, wired at the EXACT SAME unload/reload
boundary withering's own `_unloaded_piece_condition`/
`_apply_piece_condition_catchup` pair already uses, with a `COMPLETE`
project whose recipe output is a real placeable now actually getting built
via `build_at_global` — closing the previously-silent gap where completing
a project only marked status and granted household property without ever
placing anything in the world), and a real Builder worker —
`BuilderBehavior`/`BuilderMarker` — that actually carries
`CARRY_MATERIAL`/`PLACE_PIECE`, placing one real piece at a time and
crediting the SAME real `labor_hours_accumulated` field the offscreen
catch-up writes to ("two fidelities, one truth"). A sixth follow-up pass
(2026-08-25) closed this doc's own named anti-pattern —
`VillageRenderer._stamp_house` — for real: see that entry below for the
exact mechanism (a real, computed completion fraction, reusing this
section's own labor math as a bare, un-persisted calculation, deliberately
NOT wired through the `ConstructionProject`/`ConstructionProjectStore`
ledger — see that entry's own honest account of why), and a seventh
follow-up pass (2026-08-25) closed the remaining "which project should a
settlement start next" gap this paragraph used to name: `SettlementSpareCapacity`/
`SettlementBuildDecision` are real, tested, and wired at the real chunk-load
boundary (see "Deciding what to build, and who builds it" above for the full
account, including the corrected `builder_count` bug fix and the honest
account of how rarely "start new work" actually fires in live play today,
given `production_shortfall_quests_for_settlement`'s own narrow real
wiring). What's still ⬜, honestly, is the OTHER gap that section names: no
live spawner yet decides a Builder should exist for a given
`ConstructionProject` and injects its real `target_pieces` — see that
entry's own "Named, honest limitations" below, and "Deciding what to build,
and who builds it" above's own "Deliberately still unbuilt" paragraph for
the real reason (no multi-piece target for a live spawner yet).

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
- ✅ **NPC construction beyond gathering: a real Builder worker**
  (2026-08-25, a fifth follow-up pass) — the Lumberjack's own loop stopped
  at DEPOSIT; `CARRY_MATERIAL`/`PLACE_PIECE` (an NPC actually building a
  structure piece by piece) is now real. A deliberately SIMPLER slice than
  this section's own full
  `SEEK_FOREST->WALK_TO_TREE->FELL->CARRY_LOG->SHAPE` chain — raw-material
  sourcing is already covered by the real
  Sägewerk/Storage/Logistics chain above, so a Builder does not re-fell
  trees itself.

  `BuilderBehavior` (`src/gameplay/builder_behavior.gd`, pure FSM) mirrors
  `LumberjackBehavior`/`LogisticsBehavior`'s own split exactly:
  `SEEKING -> WITHDRAWING -> CARRYING -> PLACING -> SEEKING`.
  `WITHDRAWING`/`PLACING`
  each cover BOTH a walk leg and their own timed action (a deliberately
  simpler 4-phase shape than `LogisticsBehavior`'s separate
  `APPROACHING`/`COLLECTING` split) — the caller only ticks each one's timed
  method once real arrival is confirmed, mirroring `LumberjackBehavior`'s
  own two-separate-timed-methods precedent (`advance()` for `FELLING`,
  `advance_deposit()` for `DEPOSIT`) rather than `LogisticsBehavior`'s
  single always-ticking `advance()`.

  `BuilderMarker` (`src/rendering/builder_marker.gd`, engine glue) mirrors
  `LogisticsMarker`/`LumberjackMarker`'s own "small, purpose-built walker,
  not the full `NpcMarker` stack" shape. It withdraws the SPECIFIC target
  piece's own real `BuildingPiece.cost_of` material from the nearest real
  Storage (`EarthChunkManager.nearest_structure_position`/
  `withdraw_from_structure_at` — the SAME real accessor
  `Player._collect_step`/`LogisticsMarker` already use), carries it to the
  build site, and attempts a real placement validated against
  `BuildingPlacement.can_place` BEFORE ever calling the real
  `EarthChunkManager.build_at_global`: a refused piece (no floor beneath it
  yet, the cell already occupied) is never force-placed —
  `build_at_global` is never even called on that branch — its withdrawn
  material is returned to Storage, and the same cell is retried on a later
  round-robin pass rather than blocking every other piece's own turn. Going
  through the real `build_at_global` for every ACCEPTED placement also means
  the real statics graph (`_sync_statics`) gets re-synced exactly the way
  every other real placement (player, village generator) already triggers
  it — nothing here bypasses that mechanism.

  `target_project`/`target_pieces`/`project_store`/`household_store`/`earth`
  are all injected by whatever spawns this worker — the SAME "caller
  assigns what to do" pattern `LogisticsMarker`'s own
  `source_structure_id`/`item_id` already establishes. `target_pieces` is a
  real piece layout (`Vector2i` local cell -> piece_id, the same
  cell-keyed shape `RoomDetector`/`BuildingStatics` already use),
  footprint-relative to `target_project`'s own site (`chunk_coord` +
  `origin`) via the SAME `origin_tile + local_cell` convention
  `stamp_structure_at_global`'s own doc comment already establishes for
  turning a footprint-relative piece dict into real global tile
  coordinates. `SEEKING` round-robins through `target_pieces`' own still-
  unplaced cells (sorted deterministically, the same y-then-x convention
  `BuildingStatics._cell_before` already uses) rather than always retrying
  whichever cell sorts first, so a refused piece does not starve every OTHER
  piece's own turn; each cell's real placed state is verified live via
  `EarthChunkManager.modification_at_global` — "each real placed cell
  verified, not just a count."

  Placing a real piece credits its own real labor-hours onto the real
  `ConstructionProject`: `ConstructionLabor.labor_hours_for_piece` (a new,
  small, test-pinned sibling to `labor_hours_required` in
  `src/emergence/construction_labor.gd`, reusing the EXACT SAME
  `HOURS_PER_UNIT_MATERIAL` rate — "two fidelities, one truth" — applied
  per-piece via `BuildingPiece.cost_of` instead of a whole recipe's summed
  inputs, since a Builder's own target is a real piece layout, not
  necessarily a `CraftingRecipeBook` recipe the way a whole project's
  `blueprint_id` is; `labor_hours_required_for_pieces` sums it across a
  whole target layout for the real total) onto the SAME
  `labor_hours_accumulated` field the offscreen catch-up above also writes
  to — not a second parallel completion signal — via a new
  `ConstructionProjectStore.advance_project_labor_for_piece`, mirroring
  `advance_project_labor`'s own no-op/clamp/completion shape exactly and
  calling the SAME already-correct `complete_project` once every real
  piece's own labor-hours have accumulated.

  Real, tested: `test_builder_behavior.gd` (24 tests: the full
  `SEEKING->WITHDRAWING->CARRYING->PLACING` cycle advancing one piece at a
  time, abort/refusal-retry semantics, timing constants pinned),
  `test_construction_labor.gd`'s new `labor_hours_for_piece`/
  `labor_hours_required_for_pieces` section,
  `test_construction_project_store.gd`'s new per-piece-labor section, and
  `test_builder_marker.gd`
  (engine-level, against a real `EarthChunkManager`/real Storage stock/a
  real `ConstructionProject`/`HouseholdStore`, 7 tests): a real withdrawal
  pulls EXACTLY the target piece's own `cost_of` material (not more, not
  less) from real Storage stock; a placement `BuildingPlacement` would
  refuse (a wall with no floor anywhere near it) is genuinely skipped —
  never force-placed, its withdrawn material restored to Storage; and
  completing every real piece in a 2-piece target layout (a floor, then a
  wall that is refused once and succeeds once the floor exists, exercising
  the real round-robin retry) drives the real `ConstructionProject` to
  `COMPLETE` and the household genuinely receives its property via
  `HouseholdStore.grant_property`.

  **Named, honest limitations**: no live spawner exists yet that decides a
  Builder should exist for a given `ConstructionProject` and injects its
  `target_pieces` — `EarthChunkManager` does not auto-spawn a Builder the
  way it does a Lumberjack/Logistics worker, because there is no real
  trigger yet that decides which project a settlement should be actively
  building piece-by-piece, and no real caller yet produces a real
  footprint-relative piece layout for a house-shaped `ConstructionProject`.
  See "Deciding what to build, and who builds it" above for the real,
  agreed design ("ad hoc, replan-interrupt, spare-capacity-gated"),
  design-only and not yet implemented.
  `VillageRenderer._stamp_house`'s own retirement — this doc's own named
  anti-pattern — was a separate, later task (closed 2026-08-25, a sixth
  follow-up pass, see that entry below), and it does NOT use this real
  Builder worker: a village house's physical piece placement is resolved by
  a bare completion-fraction calculation at stamp time, not by spawning a
  live `BuilderMarker` per house — the same "reuse the math, not the
  machinery built for a different ledger" reasoning that entry's own doc
  comment names explicitly. Roof pieces are out of scope: `CATEGORY_ROOF` lives in a
  SEPARATE `roof_modifications` layer only `stamp_structure_at_global`
  writes to; `build_at_global` (what `BuilderMarker` calls) never touches
  it, mirroring withering/statics' own already-named "roof pieces not yet
  handled" gap. `buildable_ground` is a permissive stand-in always
  answering true — no live caller anywhere in this codebase checks real
  water/cliff buildability for a piece yet, so this pass does not invent
  one. A Builder's own in-progress state (which piece it is mid-carrying,
  round-robin cursor) is not persisted across a chunk unload/reload, the
  same class of gap the Lumberjack's own shaping progress already has.
- ✅ **Retiring `VillageRenderer._stamp_house`'s "stamps for free" anti-pattern**
  (2026-08-25, a sixth follow-up pass) — closes this doc's own explicitly
  named anti-pattern (see pillar 5 and "Known anti-pattern this doc
  replaces" below) with a real, computed, causal resolution, deliberately
  behavior-preserving for the common case rather than turning every
  already-shipped village into rubble.

  `_stamp_house` now derives a real completion fraction BEFORE stamping,
  reusing the exact same offscreen labor-catch-up math this doc's own
  "Unloaded / offscreen fidelity" section already established, as a bare,
  un-persisted CALCULATION rather than a real `ConstructionProject`:
  `ConstructionLabor.labor_hours_required_for_pieces(pieces)` for the
  requirement, `ConstructionCatchup.advance` for how much of it a
  settlement's own real villager count (`settlement.npcs.size()`, now
  threaded into `_stamp_house` as a new `npc_count` parameter) could
  plausibly have accumulated over `ConstructionCatchup.MAX_CATCHUP_DAYS`
  worth of assumed elapsed time — the SAME "logistic growth converges
  anyway" cap `EarthChunkManager.MAX_CATCHUP_DAYS` already establishes
  elsewhere: by the time a player discovers a settlement, assume it has had
  at least that long to build.

  **Deliberately NOT wired through the real
  `ConstructionProject`/`ConstructionProjectStore` ledger** — a real,
  already-discovered hazard this pass explicitly avoided:
  `EarthChunkManager.record_settlement_founded_if_new` already forms a real
  `Household` per villager and already grants that household its house
  property, under its OWN house-id scheme (`EntityRef.for_kind("house",
  "%d_%d_%d" % [chunk_coord.x, chunk_coord.y, i])`, keyed by chunk +
  villager INDEX) — a DIFFERENT scheme than `ConstructionProject.
  property_id()`'s own (keyed by chunk + footprint ORIGIN, see
  `construction_project.gd`). Creating a real `ConstructionProject` here
  would produce two divergent ownership records for the same real house.
  This pass's scope is the physical PIECE PLACEMENT only.

  At fraction >= 1.0 — real, tested, and true for every real
  `HouseBlueprint.BLUEPRINT_IDS` entry (both material tiers) at
  `SettlementGenerator.POPULATION`'s real villager count
  (`test_every_real_blueprint_reaches_full_completion_at_the_real_
  settlement_population`, the actual regression-safety proof, not an
  assumption) — a house stamps exactly as it always has: full pieces, full
  roof, `stamp_structure_at_global` called the same way, unchanged visible
  behavior for every settlement in the game today.

  Fraction < 1.0 is a real, reachable, tested code path, exercised honestly
  (not left as untested theater) against a deliberately oversized synthetic
  piece set (500 non-roof cells, an order of magnitude past the biggest
  real blueprint) and a single builder in `test_village_renderer.gd` — it
  stamps a real, deterministic PARTIAL prefix following this doc's own real
  historical build order: floor first, then load-bearing walls
  (`BuildingPiece.is_load_bearing`), then infill door/window cells, a
  proportional prefix sized by the completion fraction (no
  `RandomNumberGenerator`, per this doc's determinism pillar), with the
  roof included only once every non-roof piece is placed — Worked Example
  C's own "walls up, no roof yet" partial-project flavor, made real.
  **Named, honestly**: this essentially never fires at today's typical
  settlement sizes — even a single real villager's own
  `MAX_CATCHUP_DAYS`-capped labor budget (960 hours) comfortably dwarfs
  every real blueprint's own requirement (roughly a few dozen to ~150
  hours), so this is a real, tested, reachable safety valve for a
  hypothetically much larger future blueprint or a much smaller settlement
  population, not a constant lived experience today.

  The door position (`_stamp_house`'s own `home_position` output) stays
  real and sensible even in the partial case: it is derived from the FULL
  blueprint's own door cell regardless of completion state, using the exact
  same `_door_cell`/`_door_facing_direction` helpers, unchanged signatures
  — a villager needs somewhere real to walk home to while their own house
  is still being built.

  Real, tested: the new "retiring the 'houses stamp instantly, for free'
  anti-pattern" section of `tests/unit/test_village_renderer.gd` (8 new
  tests: the completion-fraction formula cross-checked against the real
  `ConstructionLabor`/`ConstructionCatchup` functions directly rather than
  reimplemented math, the empty/zero-cost guard, the full regression proof
  across every real blueprint/material at the real settlement population,
  the oversized-piece-set partial fraction, the deterministic
  floor->wall->infill install order, a real `_stamp_house` call stamping
  only the partial prefix with no roof, the door position staying correct
  in the partial case, and the fraction >= 1.0 boundary stamping the full
  set unchanged) plus the FULL pre-existing 26-test regression suite in
  that same file — 34/34 passing.
- ✅ **Offscreen catch-up** (2026-08-25, a fourth follow-up pass) —
  `construction_catchup.gd` (`src/world/`), mirroring
  `chunk_ecology_catchup.gd`'s EXACT contract shape:
  `advance(state, elapsed_seconds, capacity) -> Dictionary`, pure, no
  mutation of `state`. `state` carries `labor_hours_accumulated`/
  `labor_hours_required`; `capacity` carries `builder_count` (the doc's own
  "derived from settlement population" framing — supplying a real number is
  the CALLER's job, this module only consumes it). `labor_hours_accumulated`
  advances LINEARLY with elapsed time (construction labor is a
  straightforward hours-worked accumulator, not a capacity-bounded logistic
  growth process like ecology's own curves) scaled by `builder_count` and a
  new, test-pinned `HOURS_PER_BUILDER_PER_DAY` (8.0 — the conventional
  8-hour workday a labor-hour budget is denominated in), reusing
  `chunk_ecology_catchup.gd`'s own `SECONDS_PER_DAY` exchange rate directly
  rather than a second one, and capped at `labor_hours_required` so a
  project can never overshoot done. A huge elapsed-time jump is bounded in
  one call by a new `MAX_CATCHUP_DAYS` (120.0, reusing
  `EarthChunkManager.MAX_CATCHUP_DAYS`'s own exact value and "logistic
  growth/an unpopulated settlement converges anyway" justification) — the
  doc's own "no amount of elapsed wall-clock time skips [the minimum-build-
  time floor] faster than `builder_count` many NPCs' worth of hours can
  accumulate" framing, now real: `builder_count == 0` makes zero progress
  regardless of elapsed time, tested directly.

  A real labor-hours REQUIREMENT for a project (previously nonexistent —
  there is no `HouseBlueprint.total_labor_hours` field anywhere real, since
  `blueprint_id` is a `CraftingRecipeBook` recipe id, not a `HouseBlueprint`
  id) is `ConstructionLabor.labor_hours_required` (`src/emergence/
  construction_labor.gd`), a small, pure, static-function module: sums the
  recipe's own real input material counts (`recipe_book.recipe_inputs`) and
  scales by a new, test-pinned `HOURS_PER_UNIT_MATERIAL` (1.5), grounded in
  "a structure needing more raw material to assemble genuinely takes more
  labor to put together" — the same proportional-to-real-quantity reasoning
  `SagewerkProduction`'s own `LOG_COST_PER_BEAM`/`SHAPE_SECONDS_PER_BEAM`
  asymmetry already uses, not an arbitrary flat number per project.

  The real, tested CALLER carrying a project from `IN_PROGRESS` to
  `COMPLETE`: `ConstructionProjectStore.advance_project_labor(project_id,
  elapsed_seconds, capacity, recipe_book, household_store)`. No-ops
  (`{"action": "no_op"}`, no mutation) for an unknown `project_id` or any
  project not `IN_PROGRESS` — `PLANNED`/`COMPLETE`/`ABANDONED` all mean
  either nothing has actually started being built yet or there is nothing
  left to advance. For a real `IN_PROGRESS` project it derives the real
  requirement via `ConstructionLabor`, calls `construction_catchup.advance`
  with the project's own current `labor_hours_accumulated`, writes the
  (possibly still-partial) result back onto the real project, and — once
  accumulated reaches required — calls the ALREADY-CORRECT
  `complete_project` (see that entry above) rather than reimplementing
  what it already does: marking `COMPLETE` and granting `household_store`
  the property via `HouseholdStore.grant_property`.

  Real, tested: `test_construction_labor.gd` (6 tests: the per-unit-material
  scaling, a larger recipe requiring more labor than a smaller one, linear
  scaling, unknown-blueprint zero, purity/determinism),
  `test_construction_catchup.gd` (12 tests: purity/determinism/zero-elapsed,
  proportional-to-elapsed-time and proportional-to-builder-count scaling,
  zero builders making zero progress, the pinned per-builder-per-day rate,
  never exceeding the requirement, a huge elapsed-time jump staying
  bounded/finite in one call, negative elapsed treated as zero, missing
  state keys defaulting to zero), and `test_construction_project_store.gd`'s
  new "offscreen labor catch-up" section (7 tests: an `IN_PROGRESS` project
  with enough elapsed time and builders reaches `COMPLETE` and the household
  genuinely receives the property, accumulated caps exactly at the real
  requirement on completion, partial elapsed time accumulates real partial
  progress without completing, and `PLANNED`/`COMPLETE`/`ABANDONED`/unknown
  projects are all left untouched no-ops).

  **`EarthChunkManager` now HAS a live chunk-unload/reload caller**
  (2026-08-25, a fifth follow-up pass — closes the gap this note used to
  describe). `_apply_construction_labor_catchup`, wired at the EXACT SAME
  unload/reload boundary `_apply_ecology_catchup`/
  `_apply_piece_condition_catchup` already use: `_unload_chunk` snapshots
  `{unloaded_at: world_age}` into a new `_unloaded_construction_labor`
  Dictionary (chunk_coord -> record) whenever real `IN_PROGRESS`
  `ConstructionProject`s are sited in that chunk (via the new
  `ConstructionProjectStore.in_progress_projects_in_chunk` lookup, an
  additive "find every match at a site's own chunk_coord" counterpart to
  `find_project`'s single-exact-key lookup); `_load_chunk` calls
  `_apply_construction_labor_catchup` last (after every other per-chunk
  system is already wired back up, so a completed project's own placement
  below reuses every existing sync path rather than needing an earlier-in-
  load-order variant), which computes the real elapsed unloaded time and,
  for each real `IN_PROGRESS` project sited there, supplies `builder_count`
  from the EXISTING `household_count_for_settlement` (keyed by the SAME
  `EntityRef.for_settlement(chunk_coord)` id `record_settlement_founded_if_new`
  already derives a chunk's settlement under — not reinvented) before
  calling `advance_project_labor`. Simpler than its ecology/withering
  siblings in one real way: `ConstructionProjectStore` itself (like
  `_household_store`/`_market_store`) lives at `EarthChunkManager`'s own
  manager-lifetime scope and is never discarded on unload the way a
  `Chunk`/`EcosystemSimulation` region is, so a project's own
  `labor_hours_accumulated` is already safe across an unload — only the
  elapsed unloaded TIME needs recording, not a state snapshot.

  **A `COMPLETE` project's real placeable output is now actually placed.**
  `advance_project_labor`'s own return value (`{"action": "completed", ...}`)
  is what `_apply_construction_labor_catchup` reads to trigger the new
  `_place_completed_construction_project`: if the project's `blueprint_id`
  names a real `CraftingRecipeBook` recipe whose OUTPUT item is a real
  placeable (`ItemCatalog.kind_of(output_item_id) == "placeable"` --
  sagewerk/storage/campfire/furnace), it calls `build_at_global` at the
  project's own `(chunk_coord, origin)` — the SAME call `Player`'s own
  placeable-handling build step makes, no new placement path. Closes a real,
  previously silent gap: completing a project used to only mark status and
  grant household property, never actually build anything. A recipe whose
  output is NOT a placeable (e.g. `log_to_balken` -> `beam`, a plain
  material) still reaches real `COMPLETE` status and still grants its
  household real property — there is simply nothing to place in the world
  for a raw-material output, a deliberate no-op, not a crash or a garbage
  tile.

  Real, tested: `test_construction_project_store.gd`'s new
  `in_progress_projects_in_chunk` cases, and `test_earth_chunk_manager.gd`'s
  new "construction labor catch-up" section (mirroring the withering
  section's own test style exactly): a real `IN_PROGRESS` project's
  `labor_hours_accumulated` measurably advances after a real simulated
  chunk-unload absence, a chunk that never unloads does not advance
  construction labor at all (regression, mirroring withering's own identical
  "never unloads" test), a completed project's real placeable output
  (`sagewerk`) is actually placed in the world (verified via
  `modification_at_global`), and a completed project whose recipe output is
  NOT a placeable (`log_to_balken`) reaches `COMPLETE` while placing nothing
  and not crashing.

  **Named, honest limitation — deliberately still out of scope**: this pass
  does NOT decide which project a settlement should START next. Only
  projects that are ALREADY `IN_PROGRESS` get their labor advanced by this
  new wiring; `SettlementConstruction.advance` (the function that actually
  starts a `PLANNED` project via `ConstructionPriority.decide`) is not
  called from anywhere in this chunk-load path. "Which structure should this
  settlement build next" — e.g. when a settlement wants a second Sägewerk —
  is now a real, agreed design (see "Deciding what to build, and who builds
  it" above: the worst real shortfall, gated by real spare population
  capacity) but remains unimplemented; this pass only ever advances real,
  already-reserved-material work that some
  other caller (today: only tests, and `SettlementConstruction.advance`
  itself in isolation) already put into `IN_PROGRESS`. A Lumberjack's own
  in-progress state (log stock, shaping progress) is also still not
  persisted across a chunk unload/reload — a separate, still-real,
  still-documented gap (see `docs/progress.md`), the same class of
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
  same as the rest of this list's still-⬜ items below). `reserved_material`
  is a real field nothing reads back once reserved (a project's material is
  drawn down and recorded, but nothing currently returns it to `market` on
  abandonment, say). `labor_hours_accumulated` NO LONGER sits idle once a
  project is `IN_PROGRESS` — `ConstructionProjectStore.advance_project_labor`
  (see the "Offscreen catch-up" entry above, closed 2026-08-25, a fourth
  follow-up pass) is the real labor-accrual loop that carries a project the
  rest of the way to `COMPLETE`, closing the gap this paragraph used to
  name. No persistence
  wrapper (`ConstructionProjectStorePersistence`) or `EarthChunkManager`
  save/load wiring exists yet — `to_dicts`/`from_dicts` are real and
  tested in isolation (mirroring `HouseholdStore`'s own split) but nothing
  currently calls them from a save path, the same "additive capability,
  no live caller yet" honesty this doc's own `NeedResolver`/`Quest.
  deeper_need_for` entries already carry. And per this doc's own explicit
  scope for this pass: this real `ConstructionProject`/`ConstructionProjectStore`
  ledger itself is still never wired into `VillageRenderer._stamp_house` or
  any chunk-generation call site — a village house never seeds a real
  ledger entry (deliberately: see "Known anti-pattern this doc replaces"
  below for why a later pass closed the actual anti-pattern by a narrower,
  different mechanism instead of this one). Real, tested:
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
  closed-form, bounded) `construction_catchup.gd` (`src/world/`, see
  Status) now mirrors for construction, reusing its own `SECONDS_PER_DAY`
  exchange rate directly.
- `ConstructionLabor`/`ConstructionProjectStore.advance_project_labor`
  (`src/emergence/construction_labor.gd`,
  `construction_project_store.gd`, see Status) — the real labor-hours-
  required derivation (from a project's own recipe, since there is no
  `HouseBlueprint.total_labor_hours`) and the real, tested caller that
  carries an `IN_PROGRESS` `ConstructionProject` to `COMPLETE` via
  `construction_catchup.gd`, calling the already-correct `complete_project`
  rather than reimplementing it. `EarthChunkManager.
  _apply_construction_labor_catchup` (see Status) is its real, live
  chunk-unload/reload caller; `EarthChunkManager.construction_project_store()`
  exposes the manager's own `ConstructionProjectStore` instance the same way
  `household_store()`/`market_store()` already expose theirs.
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
- `BuilderBehavior`/`BuilderMarker` (`src/gameplay/builder_behavior.gd`,
  `src/rendering/builder_marker.gd`) — the real, tested worker that actually
  places pieces (see Status): inject `target_project`/`target_pieces`/
  `project_store`/`household_store`/`earth` to point it at a real
  `ConstructionProject` and a real footprint-relative piece layout; a future
  spawner (the natural next step, mirroring how `LogisticsMarker` itself
  shipped before `EarthChunkManager` auto-spawned it) should call this
  rather than re-deriving the withdraw/carry/place loop itself.
  `ConstructionLabor.labor_hours_for_piece`/`labor_hours_required_for_pieces`
  (`src/emergence/construction_labor.gd`) is the per-piece labor-hours
  derivation it credits onto a project's real `labor_hours_accumulated` via
  `ConstructionProjectStore.advance_project_labor_for_piece`.
- `SettlementSpareCapacity` (`src/emergence/settlement_spare_capacity.gd`) —
  the real, tested "population minus real survival-occupation households,
  clamped at zero" derivation (see Status); the real `builder_count`
  `EarthChunkManager._apply_construction_labor_catchup` now uses instead of
  total population.
- `SettlementBuildDecision` (`src/emergence/settlement_build_decision.gd`) —
  the real, tested "what should this settlement build next" decision (see
  Status): ranks real shortfalls, supplies `SettlementConstruction.advance`'s
  own candidate `blueprint_id`, and composes double-fix cancellation into
  the same call. `EarthChunkManager._apply_settlement_build_decision` is its
  real, live chunk-load caller.

**Known anti-pattern this doc replaces**: `VillageRenderer._stamp_house`
used to stamp a complete house, instantly and for free, at settlement
generation time (see `docs/progress.md`'s NPC section). **Closed
(2026-08-25, a sixth follow-up pass)** — see the "NPC construction beyond
gathering" section's own "Retiring `VillageRenderer._stamp_house`'s 'stamps
for free' anti-pattern" entry above for the full account — but by a real,
computed, causal resolution genuinely narrower than this paragraph
originally proposed: rather than seeding a real `ConstructionProject` at
founding time, `_stamp_house` now gates its stamp behind a real completion
fraction computed from the exact same labor-catch-up math this doc's
offscreen fidelity already uses, applied as a bare, un-persisted
calculation. Seeding a real `ConstructionProject` here turned out to be a
real hazard, not a viable path: `EarthChunkManager.
record_settlement_founded_if_new` already forms a real `Household` per
villager and grants it house property under its own chunk+villager-index
house-id scheme, a different scheme than `ConstructionProject.
property_id()`'s own chunk+footprint-origin one — wiring the ledger in here
would have produced two divergent ownership records for the same real
house. The house is no longer stamped UNCONDITIONALLY for free — it is
gated by a real, tested, computed check — even though that check resolves
to "fully complete" for essentially every real settlement in the game
today (see that entry's own regression proof); a deliberate, acknowledged
behavior change was avoided for the common case on purpose, not by
oversight.
