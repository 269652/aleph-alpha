# Civic Construction: One Ledger, Three Owners

Compiled from a follow-up design-brainstorm session, answering a direct
question about [timber_construction.md](timber_construction.md)'s own
still-named gap: a live Builder spawner and player-hired Builders both stay
unbuilt because every real structure the settlement decision system can
currently queue is single-tile, built in one shot — there is no real
multi-piece target for a Builder to place piece by piece. This doc is that
target, generalized to serve three real owners at once rather than one:

1. **The player's own build site** — a real "you design it, a hired
   Builder executes it" labor market.
2. **New settlement-owned civic buildings** — a Meeting Hall, a Granary,
   and a Watchtower, each a real physical home for something already real
   and abstract in this codebase.
3. **Village houses, properly** — closing the id-scheme gap
   `VillageRenderer._stamp_house`'s own retirement pass deliberately routed
   around rather than fixed.

Design only — not yet implemented. See "Status" at the end for the exact
account of what stays real today vs. what this doc specifies.

## Design pillars

1. **One ledger, many owners.** `ConstructionProject`/
   `ConstructionProjectStore` (`src/emergence/`) already generically support
   any site and any `blueprint_id` — the ONE thing that made them
   house-specific was `complete_project`'s hardcoded
   `HouseholdStore.grant_property` call, using its own fixed house-id
   scheme. Generalize that one seam and the same ledger, the same
   `BuilderMarker`, and the same offscreen labor catch-up already serve a
   player's own site, a settlement's civic building, and a village house
   without three parallel systems.
2. **A target is just a piece dict.** A player's ghost-plan, a Meeting
   Hall's own blueprint, and a village house's `HouseBlueprint` output are
   all the exact same shape (local cell → piece id) `BuilderMarker` already
   consumes for `PLACE_PIECE`. One Builder mechanism, three sources for the
   dict it's handed.
3. **Ghost-planning makes intent real before labor is real.** A player (or
   a settlement, deciding to build a civic structure) first commits to a
   real, `BuildingPlacement.can_place`-validated plan — a real `PLANNED`
   `ConstructionProject` with no material reserved yet. Only once material
   is actually committed does labor (the player's own hands, an autonomous
   settlement Builder, or a hired one) start filling it in, piece by piece.
   This mirrors real construction practice directly: a plan exists before
   the first stone is laid.
4. **Civic buildings are physical homes for systems that already exist,
   not new mechanics invented from scratch.** A Meeting Hall for
   `institution_formation.gd`'s already-real, purely-abstract institutions;
   a Granary for `VillageMarket`'s already-real settlement stock; a
   Watchtower as the real physical seed for `quests.md`'s own already-named,
   still-unstarted Diegetic Threat / Base Defense item. None of these
   invent a new abstract system — each gives an existing one a real,
   discoverable place in the world.
5. **Hiring is a real labor market, not a shortcut.**
   `timber_construction.md`'s own "pay gold to pull a settlement's spare
   Builder" design stays exactly as specified there — a genuine trade-off
   (that settlement's own construction slows while its Builder works for
   the player), not a conjured worker. This doc is what finally gives that
   hired Builder somewhere real (a player's own multi-piece site) to walk
   to and work on.
6. **Tuned values are tested functions, not comments.** Every footprint,
   piece cost, hiring-cost formula, and capacity bonus named below is
   illustrative — the real number gets pinned by a calibration test at
   implementation time, per this project's no-manual-tuning rule.

## Real-world grounding

- **Plans before labor.** Real construction is drawn and committed to
  before the first material moves — architectural plans, a buildable
  permit. A planned-but-unbuilt state is an ordinary, real phase of
  building, not a game invention this doc introduces.
- **Guild labor for hire.** Historically, a patron commissions a design and
  hires a guild of masons or carpenters to execute it — the patron does not
  need to lay every stone themselves for the result to be genuinely
  theirs. This is exactly "you design it, they build it, you pay" as a
  real, pre-industrial labor relationship, not an invented game mechanic.
- **Civic buildings are commons, not property.** A real town hall, granary,
  or watchtower belongs to the settlement, not to any one family — grounds
  this doc's own "civic buildings grant no household property" design
  directly.
- **Meeting halls and moots.** Real village and town governance
  historically happened in a dedicated physical structure (a moot hall, a
  folkmoot green, a town hall) — this doc gives `institution_formation.gd`'s
  already-real "an institution formed" event a real, discoverable physical
  seat, the same way a real settlement's own governance has one.
- **Granaries.** A real, ancient, near-universal settlement building —
  communal food storage predates almost every other civic structure, and is
  meaningfully distinct from any one household's own private stores.
- **Watchtowers.** A real, universal structure whose entire purpose is
  sightline — height genuinely extends how far real, already-present
  danger can be seen and understood, without the tower itself causing or
  scripting anything. Grounds this doc's own "a real vantage over real
  causes, never a scripted alert" Watchtower design directly.

## Mechanism

### Generalizing the ledger: an injected completion callback

`ConstructionProjectStore.complete_project` gains a `Callable` parameter
(default `Callable()`, a real no-op), replacing its own hardcoded
`household_store.grant_property(project.household_id, project.property_id())`
call:

```
func complete_project(project_id: String, on_complete: Callable = Callable()) -> bool:
    ...
    project.status = ConstructionProject.Status.COMPLETE
    if on_complete.is_valid():
        on_complete.call(project)
    return true
```

Every real caller supplies its own completion behavior instead of one
hardcoded scheme:

- **A village house** (once "Village houses, properly" below lands):
  `on_complete` grants `HouseholdStore.grant_property` — unchanged
  behavior, now explicit instead of hardcoded.
- **A settlement civic building** (Meeting Hall, Granary, Watchtower): NO
  property grant at all — a civic building's real "ownership" is simply
  its own real presence (`has_structure_near`/`nearest_structure_position`
  already answer "is one here"), the exact same ownerless shape Sägewerk
  and Storage already have. `on_complete` is the real no-op default.
- **A player's own site**: also the real no-op default — the player
  already owns whatever they build directly (the same way hand-placing a
  wall today needs no property grant); hiring a Builder to fill in a plan
  the player already committed to changes WHO places the pieces, not who
  owns the result.

`ConstructionProjectStore.abandon_project`/`active_projects_in_chunk` (real,
from `timber_construction.md`'s settlement-decision pass) are unaffected —
this change touches only the completion path.

### Ghost/planned placement mode

A new player interaction, extending `building.md`'s existing build-cursor
UI rather than inventing a second one: instead of placing a piece
immediately (consuming material, building on the spot), a "plan" toggle
marks a chosen footprint's cells as a real `PLANNED` `ConstructionProject`
— each cell validated against the real `BuildingPlacement.can_place` (a
cell that would be refused is refused here too, at plan time, not
discovered later at build time) and real statics (`BuildingStatics`), but
consuming NO material and building NOTHING yet. The project's own
`target_pieces` is this planned dict — the exact shape `BuilderMarker`
already expects.

Material reservation follows the same real shape
`SettlementConstruction._handle_ready` already established for
recipe-gated structures, mirrored here against the PLAYER's own inventory
instead of `VillageMarket`: once the player has (or accumulates) real
material for the plan, the project transitions `PLANNED` → `IN_PROGRESS`
and `reserved_material` is drawn down from their inventory — the same
"real, not eyeballed" transition point `ConstructionStartHysteresis`
already gates elsewhere, applied to a real player-scale stock instead of a
settlement-scale one.

**Labor is a real choice, not a fork in the system.** Once `IN_PROGRESS`,
the SAME project can be worked by the player themselves (walking up and
placing each planned piece by hand, the ordinary existing interaction) or
by a live `BuilderMarker` (autonomous or hired) — both credit the exact
same `labor_hours_accumulated`/piece-placement path this doc's "Live
Builder spawning" section below describes. A player can start building
their own plan by hand and later hire help to finish it; there is one real
project underneath either way, not two parallel construction paths.

### Live Builder spawning

Given any real `IN_PROGRESS` `ConstructionProject` with a real
`target_pieces` dict, a Builder is spawned to work it — generalizing
`EarthChunkManager`'s existing "spawn on real structure/modification
existing" pattern (`_sagewerk_lumberjacks`, `_resync_logistics_for_sagewerk`)
from "a tile exists" to "a real in-progress multi-piece project exists":

- **Settlement-initiated** (a Meeting Hall, Granary, or Watchtower a
  settlement decided to build): staffed from that settlement's own real
  spare capacity (`SettlementSpareCapacity.for_settlement`, already real),
  up to a real, tested cap on simultaneous Builders per project — the
  "multiple Builders may pool effort" design `timber_construction.md`
  already specs, now with a real multi-piece target to actually pool
  effort on.
- **Player-hired** (see next section): exactly one `BuilderMarker`, its
  `earth`/target references injected the same way `LogisticsMarker`'s own
  caller-assigned fields already work, walking from the hiring
  settlement to the player's own site instead of a settlement-local
  destination — `BuilderMarker`'s existing `CARRYING` leg generalizes
  directly to an arbitrary target position, not just a settlement-bounded
  one.

### Player-hired Builders

A real interaction (a dialogue-style prompt with an idle, real
spare-capacity villager, or a settlement's own market abstraction) that:

1. Confirms the target settlement has real spare capacity right now
   (`SettlementSpareCapacity.for_settlement` — the exact same real number
   gating the settlement's own autonomous construction, so hiring one away
   is a genuine, visible trade-off, not a free action).
2. Charges the player real gold, via a formula grounded in the project's
   own real scale — `ConstructionLabor.labor_hours_required_for_pieces`
   (already real) times a real, tested gold-per-labor-hour rate — not a
   flat number independent of what's actually being built.
3. Pulls one Builder from that settlement's real spare pool (reducing ITS
   OWN real `builder_count` for as long as the hire lasts — composes for
   free with the existing offscreen catch-up math the same way population
   loss already does: fewer real spare NPCs there means the settlement's
   own construction correctly slows while its Builder works elsewhere).
4. Assigns that Builder to the player's real `ConstructionProject`.

**Material**: the player's plan may already have real material reserved
(the ordinary ghost-planning path above) — hiring pays for LABOR only in
that case. A separate, explicit "hire with material included" option is
a real, larger transaction: an added gold cost covering the settlement's
own `VillageMarket` stock being drawn down and carried to the player's
site (mirroring `LogisticsMarker`'s own carry-and-deposit shape,
generalized to a cross-site delivery) before the Builder starts placing.
Both are real, both stay available — the player's own choice at hire time,
not a design fork this doc has to resolve one way.

### Meeting Hall

A new named multi-piece shape (its own footprint/piece layout — a
`CivicBlueprint` catalog entry sibling to `HouseBlueprint`'s own, or a
direct extension of it; illustrative sizing until implementation).

**Real trigger**: a settlement crosses a real threshold already meaningful
to `institution_formation.gd` — its first real formed institution (already
real: `InstitutionFormation.should_form`) queues a real `PLANNED`
`ConstructionProject` for a Meeting Hall the same way
`SettlementBuildDecision` already queues a Sägewerk/Storage, just with a
multi-piece target and the real no-op completion callback (no property
grant — a civic commons).

**Real payoff**: once built, a settlement's already-real formed
institutions gain a real, discoverable physical seat in the world — a
`has_structure_near("meeting_hall", ...)` check becomes a real, legible
signal (to quests, to dialogue, to a player just walking through) that a
settlement has real governance, not merely an internal event-store fact
nothing in the world reflects.

### Granary

Settlement-SCALE stock, reusing `VillageMarket`'s already-real
`item_id -> float` shape directly — deliberately NOT a second
`StructureStock`-style per-building container (that's Storage's own scope,
building-scale); a Granary is the settlement's own shared stock, the same
scope `VillageMarket`/`SettlementState.carrying_capacity` already operate
at.

**Real payoff, grounding why a settlement would ever want one**: a real
Granary raises a settlement's real food-capacity ceiling —
`SettlementState.carrying_capacity`'s own `FOOD_PER_HOUSEHOLD` divisor
gains a real, tested reduction (or the food-stock numerator gains a real
bonus) once a Granary is present, the same "derive a number from real
stock/presence" style `carrying_capacity` already uses elsewhere. A
settlement approaching `SettlementState.status_for`'s own `DECLINING`
classification is the real trigger for queuing one — real population
pressure, not an eyeballed threshold.

### Watchtower

**A real correction made while writing this doc**: [building.md](building.md#base-defense-diegetic-threat-not-scripted-raid-waves)'s
own diegetic-threat philosophy explicitly rejects a "threat level"
counter or anything that reads as an incoming-raid alert — a Watchtower
that "detects scripted raids" would contradict that pillar directly, since
this project has no scripted raids to detect. A Watchtower earns its real
place a different way: not as a warning siren, but as a real VANTAGE — a
place from which real, already-simulated danger (a nearby rival dynasty's
own activity, a starving predator population's real range, an evolving
world-boss candidate crossing threshold nearby, per
[quests.md](quests.md#village-endangerment-the-attractor-mechanism)'s own
real attractor mechanism) becomes more *legible* to a player or NPC
standing in it, the same way a real hilltop lookout would be — extending
sight/awareness of causes that already exist, never manufacturing a cause
that wasn't there. This doc gives it a real footprint, real placement, and
a real, tested extended-visibility radius (grounded in "a tower sees
farther," a real larger query radius than a ground-level structure uses)
— and deliberately does **NOT** build any new alert/notification system;
what a player or NPC does with better visibility of real, already-simulated
danger is exactly as unbuilt after this doc as before it, matching
`docs/progress.md`'s own Diegetic Threat / Base Defense item staying ⬜.
Named honestly as "a real building granting real extended awareness of
causes that already exist, with no new consequence system attached yet" —
the same "mechanism real, behavior/caller still pending" pattern this
codebase already applies everywhere else (`NeedResolver`,
`ConstructionPriority` before their own live callers landed).

## Interaction with other docs

- **[timber_construction.md](timber_construction.md)** — this doc
  generalizes `ConstructionProject`/`ConstructionProjectStore`/
  `BuilderMarker`/the settlement-decision system rather than replacing any
  of it; the Sägewerk/Storage/house arc and "Deciding what to build, and
  who builds it" section stay exactly as specified there. Player-hired
  Builders is the concrete continuation of that doc's own "player-hired
  Builders, on a player's own structure" paragraph.
- **[building.md](building.md)** — ghost/planned placement mode extends its
  existing build-cursor/placement-validation UI; does not replace it.
- **[npc.md](npc.md)** — hiring remains the same narrowly-scoped first
  crack at its own still-unbuilt hiring/wage section
  `timber_construction.md` already named — "pull one spare Builder for one
  project," not the fuller system that section still leaves open.
- **[governance.md](governance.md)** — the Meeting Hall is a real physical
  seat for that doc's/`institution_formation.gd`'s already-real formed
  institutions; does not change how institutions form or dissolve.
- **[building.md](building.md)** — the Watchtower is deliberately shaped to
  fit that doc's own diegetic-threat philosophy (real vantage over real,
  already-simulated causes, never a scripted alert) rather than the
  detection-mechanic framing an earlier draft of this doc used before that
  conflict was caught; does not build the still-unstarted Base Defense
  mechanic itself.
- **[quests.md](quests.md)** — the Watchtower's own real extended-visibility
  radius is grounded in the Village endangerment section's already-real
  attractor mechanism (wealth/population raising real risk); does not
  change that mechanism.
- **[persistence.md](persistence.md)** — a `PLANNED` project with no
  material reserved yet, and a settlement's own civic buildings' real
  presence, need the same real persistence consideration
  `timber_construction.md`'s own persistence entry already names for
  `ConstructionProject` generally — not solved differently here.

## Worked examples

**A. A player plans, then builds by hand.** A player marks out a four-room
extension to their own homestead in plan mode — every cell validated
against real placement/statics rules on the spot, nothing built yet. Over
the following days they gather Balken and Planke and place each planned
piece themselves; the project quietly tracks real progress underneath,
indistinguishable from building without a plan at all until the moment
they decide to hire help instead.

**B. A player hires help.** Short on time, the same player instead walks
to the nearest village, finds an idle villager with real spare capacity,
and pays gold to send them to finish the extension. The villager (a real
`BuilderMarker`) walks from the settlement to the player's own site,
withdraws its remaining planned pieces' material from wherever it was
reserved, and places them one at a time — visibly working the site the
player designed, not conjuring it. Back at the settlement, its own
`builder_count` is measurably one lower for as long as the hire lasts.

**C. A settlement earns its Meeting Hall.** A growing settlement's first
real institution forms (two households sharing enough real contracts,
`InstitutionFormation.should_form`). A `PLANNED` Meeting Hall project is
queued automatically the next time its spare capacity allows; over
following visits, the player watches (or simply returns to find) a real
multi-room hall rise at the settlement's own square — a landmark that
exists because the settlement's own social fabric earned it, not because
the chunk loaded.

**D. A vantage a future pass could use.** A Watchtower built for an
earlier, unrelated reason (population pressure, a player's own initiative)
sits at a settlement's edge, its own real query radius extending further
than any ground-level structure's. Nothing in THIS doc has it do anything
with what it can see — but the moment a future pass wants to let a
settlement's own guards notice real, already-simulated danger (a rival
dynasty's own approach, a starving predator population's real range)
sooner because of it, the real structure such a system would need already
exists, built for an entirely unrelated reason of its own.

## Open questions

- Exact Meeting Hall/Granary/Watchtower footprints, piece costs, and the
  Granary's own real capacity-bonus formula — illustrative until
  implementation, per this doc's own "tuned values are tested functions"
  pillar.
- Can a hired Builder be reassigned or recalled mid-project by a second,
  competing hire request — and what happens to material they're already
  carrying? Not resolved here.
- Do ghost-planned pieces with no material ever reserved expire if left
  indefinitely, or sit as a permanent `PLANNED` record? Leaning toward "sit
  indefinitely, harmless" (matches this project's general "nothing is
  silently deleted" discipline) but undecided.
- Multiplayer implications of a shared civic building or a hired Builder
  crossing between two players' own sites — out of scope, matches this
  project's existing single-player-simulated stance elsewhere.
- Whether "Village houses, properly" (fixing `ConstructionProject`'s own
  id-scheme mismatch with `record_settlement_founded_if_new`'s house-id
  format) is worth doing at all now that civic buildings prove the
  generalized ledger works without needing houses specifically — a real
  scope call for whoever implements this.

## Status

⬜ Everything in this doc — design only, from this brainstorm session, not
yet implemented. Builds on real, already-shipped work
(`ConstructionProject`/`ConstructionProjectStore`/`BuilderMarker`/
`SettlementSpareCapacity`/`SettlementBuildDecision`, all real per
[timber_construction.md](timber_construction.md)'s own Status section) —
nothing here needed a new foundational mechanism invented, only a generalized
completion seam and three new real callers.
