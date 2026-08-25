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
- **Do player-placed pieces wither too?** Consistency with "one system,
  two builders" says yes, but that turns base upkeep into a real survival
  loop and needs its own player-facing warning (a creak before a collapse,
  not a silent surprise) before it ships.
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
and real timber building pieces. Everything else this doc describes
(statics, withering, the settlement construction ledger, offscreen
catch-up, autonomous NPC house-building) is still ⬜, exactly as specified
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
  output drops as `ItemStack`s via `WorldItemBus` at the Sägewerk's own
  position, the same "what you see is what's real" pattern every other
  production system here uses — no new inventory-UI concept needed.
- ✅ **Real consumers for beam/plank** — `BuildingPiece`'s new
  `timber_wall` (costs `beam`, load-bearing per pillar 1) and
  `timber_floor` (costs `plank`, non-structural), appended to `PIECE_IDS`.
  Durability sits between the wood and stone tiers. Deliberately does
  **not** add the load-bearing/support-capacity field this doc's own "Real
  statics" section describes below — that stays future work; these two
  pieces are shaped identically to every existing wood/stone piece so
  nothing implies a statics mechanic that isn't real yet.
- ⬜ **Real statics** (a support graph over the piece grid) — not built.
  Every piece placed today (wood, stone, or the new timber tier) still
  "stands because it was placed," per this doc's own pillar 2's honest
  framing of the pre-doc status quo.
- ⬜ **Withering/decay** (`condition`, the closed-form catch-up decay
  curve) — not built. No placed piece loses condition over time yet.
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
- ⬜ **Settlement construction ledger** (`ConstructionProject`,
  `ConstructionProjectStore`, `InstitutionFormation`-style hysteresis on
  whether a household starts building) — not built.
- ⬜ **Multiple lumberjacks per settlement** — out of scope for this pass;
  today's model is exactly one worker per Sägewerk instance. Two Sägewerke
  close enough together may have their Lumberjacks compete for the same
  standing tree (each independently targets its own nearest one, with no
  coordination) — a known, accepted edge case, not a crash risk.
- ⬜ All of this doc's own "Open questions" remain genuinely open (who
  becomes a builder as a real occupation vs. ad hoc, whether player-placed
  pieces wither too, collapse safety/momentum damage, tool-tier gating on
  shaping, forest depletion ceiling via `land_health`, multiplayer
  authority).

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
- `HouseholdStore.grant_property` (`src/emergence/household_store.gd`) —
  house ownership, already correct as-is.
- `InstitutionFormation` (`src/emergence/institution_formation.gd`) — the
  hysteresis-threshold *pattern* to reuse for "should this household start
  building."
- `NpcProduction`/`VillageMarket` (`src/world/`) — the producer-occupation
  → yield → shared-stock pattern a `logger` occupation and lumber stockpile
  should follow.
- `SettlementState` (`src/emergence/settlement_state.gd`) — the pure
  capacity-classifier shape a builder-count derivation should follow.

**Known anti-pattern this doc replaces**: `VillageRenderer._stamp_house`
currently stamps a complete house, instantly and for free, at settlement
generation time (see `docs/progress.md`'s NPC section). Implementing this
doc means that call site changes to seed a `ConstructionProject` at
founding time instead of stamping on the spot — a deliberate, acknowledged
behavior change, not an oversight to preserve.
