# Planner Mode: laying out a settlement before building it

A second view of the same world. **RPG mode** is the game as it is today —
a character, a hotbar, things picked up and swung. **Planner mode** lifts
the player out of their own hands for a moment and lets them *lay out*
what the place should become: pavement here, a house there, a sawmill by
the trees. Nothing is built by planning it. The plan is a set of
**wireframes** standing in the world, and the character still has to walk
over and raise them — alone, or by paying somebody who knows how.

Asked directly: *"a view toggle to the top besides the minimap which
toggles RPG Mode (hotbar) with a Planner mode, where the character can
place blueprints like pavement, houses, sawmills etc. directly on the map
similar to how it works in Anno 1800 ... then when leaving the plan mode
he can go to one of the wireframes and hire an NPC to build it or build it
himself."*

## Design pillars

1. **Planning is not building.** Placing a blueprint costs nothing, spends
   nothing, and changes no terrain. It records an intention. Every
   material, every labour hour and every real consequence still happens at
   the moment somebody builds it, through the systems that already exist
   (`ConstructionProject`, `ConstructionLabor`, `BuildingCatalog.cost_of`).
   This is what keeps planner mode from becoming a second, cheaper way to
   build.
2. **One set of placement rules, asked from two places.** The planner
   cursor and the village generator ask the *same* `BuildingPlacement`
   the player's own build cursor already asks — that file's own doc
   comment states this as its reason to exist ("anything true of a
   player's house is true of a villager's"). A blueprint that cannot be
   planned is exactly a building that could not be built.
3. **A wireframe is a real thing standing in the world, not a UI overlay.**
   It survives leaving planner mode, leaving the chunk, and quitting the
   game, because the whole point is to walk back to it later. It is world
   state, not screen state.
4. **The mode toggle changes what the player COMMANDS, never what the
   world DOES.** Time does not stop, creatures do not freeze, nothing is
   paused. Planner mode is a different set of controls over a world that
   goes on running — unlike the settings overlay, which really does pause
   (see [hud.md](hud.md)).
5. **Build-it-yourself and hire-somebody are the same construction, paid
   for differently.** Both produce one `ConstructionProject` against the
   same site and the same blueprint. What differs is who supplies the
   labour hours: the player's own time at the site, or an NPC's wage and
   `HiringGate`.

## Real-world grounding

- **Anno 1800's build menu** is the direct reference for the *feel*: a
  palette of structures, a footprint that follows the cursor and colours
  itself by whether it may be placed, and a grid that snaps. It is the
  shape of the ask, not a thing to reproduce — this game keeps its own
  character on the map the whole time, and nothing is built by placing it.
- **Planning permission before construction** is the real-world version of
  the same split, and the reason pillar 1 holds: a drawing on a plot is
  not a building, and the cost falls when somebody starts work.

## Mechanism spec

### The two modes

`ViewMode` (`src/gameplay/view_mode.gd`, pure) is the whole mode model:
two modes, a toggle, and — for each — what the HUD shows and whether the
world-space build cursor is live. Pure so the HUD's behaviour is testable
without standing up a `World`, the same "pure model, thin Node" split
`AudioSettings`, `EscapeAction` and `NatureSoundscape` already use.

- `RPG` — the hotbar is shown, the blueprint palette is not.
- `PLANNER` — the palette is shown, the hotbar is not.

Both modes keep the minimap, the meters and the message stack: they are
readouts, not controls, and pillar 4 says the world goes on running.

### The toggle

A button in the **top-right HUD column, immediately left of the minimap**
(`$UI/Minimap` owns `offset_left = -170 .. -8`; the toggle sits left of
that). The corner column already stacks this way — the karma card sits
directly under the minimap at `offset_top = 178` — so this extends an
established layout rather than inventing a place to put it. It is a themed
card, per [hud.md](hud.md)'s pillar 1: the mode you are in carries
meaning, so it may not be bare text over the world.

### What can be planned

Three kinds, all of them things the game can already build:

- **Pavement** — `TerrainRenderer.ROAD_TILE_ID`, one cell at a time. The
  same laid surface a village lays for its streets (see
  [infrastructure.md](infrastructure.md)'s Road tier).
- **Buildings** — every `BuildingCatalog.BUILDING_IDS` entry, placed by
  its own real footprint and door.
- **Works** — the recipe-backed structures `ConstructionProject` already
  speaks in terms of (its `blueprint_id` is "deliberately a real
  CraftingRecipeBook recipe id, not a second 'blueprint' vocabulary"),
  the sawmill among them.

One vocabulary, deliberately: a plan names a `blueprint_id` that some
existing system already understands, so nothing here invents a parallel
catalogue that can drift from the real one.

### The plan ledger

`BuildPlan` is one planned site: `blueprint_id`, the chunk it sits in, its
local origin cell, and when it was planned. `BuildPlanLedger` holds them,
answers what stands where, and refuses a plan that overlaps another or
fails `BuildingPlacement` — deterministic id from site + blueprint,
mirroring `ConstructionProject`/`Household`'s own "deterministic key, not
an allocated counter" idiom rather than adding a counter to protect.

### Raising a wireframe

Leaving planner mode changes nothing about the plans; they stand where
they were put. Walking within reach of one offers two ways to raise it,
and both end in the same `ConstructionProject` against the same site:

- **Build it yourself** — the player supplies the labour at the site.
- **Hire an NPC** — gated by `HiringGate.can_hire` against that NPC's own
  trust and the offered wage, exactly as every other ongoing wage
  relationship in this game is (see
  [npc_instructions.md](npc_instructions.md)).

Cancelling a plan removes the wireframe and costs nothing, because
planning cost nothing (pillar 1).

### From raised to raised: what the hours actually produce

A raised plan is a `ConstructionProject` **already under way**. Both ways
open it `IN_PROGRESS`, because `advance_project_labor` only advances an
`IN_PROGRESS` project and a project left `PLANNED` would sit at zero hours
forever with nothing ever built — a build that says it started and then
silently never happens is worse than one that refuses.

From there the project is the settlement ledger's own, and it goes the
whole way the ledger already goes for a village's own builds:

- **The site rises while it is worked.** Every labour tick syncs the same
  `_sync_construction_site` sprite a village's own project draws — the
  eight-stage construction row, at the stage the real accumulated hours
  have reached. A build with nothing standing on it and no message left on
  screen is indistinguishable from a build that never started.
- **Completing places the building.** The hours reaching the requirement
  runs the same `_place_completed_construction_project` a village's own
  project runs: the real catalog building on its plot, or the recipe's own
  placeable, and the construction site taken down. Marking a row COMPLETE
  in a ledger is bookkeeping, not construction.

### Who supplies the hours

Pillar 5's "paid for differently" is exactly this, and nothing else:

- **Hired** — the villager was paid, so the crew works whether or not the
  player is anywhere near. One builder, at the same eight hours per
  builder per in-game day a settlement's own spare hand earns.
- **Yourself** — *the player's own time at the site*. The hours accrue
  only while the player stands within `PlanRaising.REACH_TILES` of the
  plan's own footprint — the same reach that offered them the wireframe in
  the first place. Walk away and the work stops where it stands; come
  back and it goes on. This is what keeps "build it yourself" from being a
  free hire: the price of doing it yourself is standing there.

And pillar 1's "every material… still happens at the moment somebody
builds it" is paid at the same moment: raising it yourself really **takes
the materials out of the player's own inventory**, the building's own real
`BuildingCatalog.cost_of`, the same numbers a village pays. Checking that
they are carried and then not taking them would make building by hand the
cheapest path in the game. Hiring does not take them — the wage is what
the player pays, and the villager brings the material, which is the whole
reason hiring is worth gold.

### Work that is laid by hand

Pavement asks for no labour hours at all: it is not a recipe, so
`ConstructionLabor.labor_hours_required` is genuinely zero for it, and a
zero-hour project can never complete (`advance_project_labor` only
completes against a requirement above zero, deliberately — otherwise an
unknown blueprint id would complete instantly and for free).

So a blueprint whose work is zero hours is **done the moment it is
begun**: raised, it is laid at once, exactly like the earth tile the
player already places by hand. The same rule `PlanRaising.
can_build_yourself` already states for its cost ("an empty cost must read
as layable by hand") applied to its hours. It is a rule about the size of
the work, not a special case named after pavement — anything else that
ever costs no hours is laid the same way.

## Status

The spec above was written before the code, per CLAUDE.md. It lands in
slices; this list says exactly which are real rather than claiming the
whole.

- ✅ **`ViewMode`** (2026-09-17) — the two modes, the toggle, and what each
  owns. Two claims are stated as tested functions rather than left in
  comments: the hotbar and palette are never both up, and *neither mode
  pauses the world*. 9/9.
- ✅ **`BuildPlan`/`BuildPlanLedger`** — standing wireframes, deterministic
  ids from site+blueprint (the `ConstructionProject`/`Household` idiom),
  refusals with reasons for unknown blueprints, unbuildable ground and
  overlap. Buildability arrives as a `Callable`, the seam
  `BuildingPlacement` already established. 15/15.
- ✅ **The toggle, beside the minimap**, and the blueprint palette built
  from the real `BuildingCatalog` (pavement + `BUILDING_IDS` +
  `PRODUCTION_BUILDING_IDS` + `CIVIC_BUILDING_IDS`), so a building added
  to the game appears in the palette for free.
- ✅ **Click-to-plan**, gated on `ViewMode.arms_build_cursor` so a stray
  click in rpg mode can never plan a house, with the refusal reason shown
  rather than silently doing nothing. Pillar 1 is pinned by a test that
  the placement path contains no `build_at_global`, `place_building`,
  `spend` or `remove_item`.
- ✅ **Wireframe rendering** (2026-09-17) — `PlanWireframe` (pure geometry
  and colour) + `PlanWireframeLayer` (a thin Node2D that only iterates and
  draws). A child of `World` rather than `$UI`, on the ground-effects tier
  (`z_index -1`), because a plan stands on the ground rather than on the
  screen. 10/10.
- ✅ **The cursor's footprint, coloured by whether it may be placed** — one
  colour vocabulary shared with the standing wireframe, since they are the
  same thing a moment apart. The colour is derived from the ledger's own
  refusal *reason*, so what the cursor shows and what the message says
  cannot disagree. Allowed and refused differ in hue rather than
  brightness, pinned by a test.
- ✅ **Persistence** — `BuildPlanPersistence`, mirroring
  `WorldClockPersistence`'s shape. One file rather than the per-chunk
  directories chunk modifications use: a settlement's plans are tens of
  records read whole, not thousands per chunk. JSON rather than
  `store_var` because a malformed `get_var` raises an uncatchable engine
  error, where a truncated file must degrade to "no plans". Loading
  replays rows into a real ledger so its overlap refusal still knows what
  it loaded. Wiped with the rest of the world on New Game. 7/7.
- ✅ **Raising a wireframe** — `PlanRaising`: reach, the building's own
  **real catalog cost** (never a second price list), what you are short of
  so the prompt can say it, and hiring through the **same `HiringGate`**
  every other wage relationship uses. Both ways produce the same site and
  blueprint; only who supplies the hours differs. Bound to the interact
  key, which raises a wireframe you are standing at and otherwise still
  talks. 12/12.
- ✅ **Hiring a villager to build it** (2026-09-17) — and closing the gap
  that made it unreachable. `docs/concept/npc_instructions.md` named the
  blocker outright: *"nowhere on a real NpcIdentity/NpcMarker actually
  holds a live trust value for hiring_gate.gd to read"*. `NpcTrustStore`
  is that value — the "minimal, player-only trust scalar" that doc already
  specifies, keyed by `NpcIdentity.seed_value` so it survives a marker
  despawning with its chunk. **Three real conversations** earn it: the
  baseline (0.2) to `HIRE_THRESHOLD` (0.5) is a 0.3 gap and a conversation
  is worth 0.1, pinned by a test so the step and the threshold cannot
  drift apart and quietly make "three conversations" a lie. A villager
  standing close enough and willing is offered the job first, because
  hiring is the point of walking up with somebody beside you — and it does
  not ask the player to carry the materials themselves.
- ✅ **Raising opens a real `ConstructionProject`** — through the same
  `ConstructionProjectStore.start_project` every village build already
  uses, so a player-raised building is the same kind of project a
  villager-raised one is rather than a parallel one. Idempotent by site, so
  raising twice cannot reset a project already under way. The plan is
  cancelled and re-saved as it becomes a project, or a blueprint would be
  drawn over its own building.
- ✅ **The wage is really paid** (2026-09-17) — `WagePayment.pay` moves gold
  from the player's purse into the hired villager's own household wallet,
  and it is ONE function rather than a spend and an add at the call site
  for the reason that matters: a debit that succeeded next to a credit that
  did not is money destroyed, and a credit without a debit is money
  invented. Gold conservation is pinned by a test. Payment happens
  **before** the job is taken — a villager who was never paid must not end
  up working, and a player who cannot afford the wage is told so rather
  than quietly getting free labour. This is the first real wage-payment
  flow in the game; `docs/concept/npc_instructions.md` lists the general
  one as still unbuilt.
- ✅ **A hired villager works the site over time** — and does it the way
  [building.md](building.md) says hiring must come back: *"a build the
  player cannot do themselves says that hiring returns with
  construction-over-time"*. The instant-hire fork was retired on purpose,
  so nothing is spawned. A hired build opens **IN_PROGRESS** (a PLANNED one
  would silently never advance) and accrues hours through the same
  `ConstructionProjectStore.advance_project_labor` and
  `ConstructionCatchup` a settlement's own builds use — 8 hours per builder
  per in-game day, so a hired villager earns exactly what a settlement's
  spare hand does rather than on a private schedule. Stepped from
  `_step_ecology_batch` alongside every other slow world system, and
  measured against the **world clock** rather than a frame delta: one
  clock, read, never a second one kept in step — which is why a `/season`
  leap does not leave a half-built house frozen.
- ⬜ **What the hours produce.** The hours are real and the project reaches
  `COMPLETE` — and that is all it does. `advance_hired_build` calls
  `ConstructionProjectStore.advance_project_labor` directly, so it reaches
  neither `_sync_construction_site` nor
  `_place_completed_construction_project`: a hired build shows nothing
  rising and, finished, builds nothing. (An earlier version of this list
  claimed "the building completes"; measured, it does not. See "From
  raised to raised" above for what it must do.)
- ⬜ **Building it yourself supplies no hours.** The player path opens the
  project `PLANNED`, which `advance_project_labor` no-ops on, and nothing
  in `World` advances it — so "Raising it yourself" takes the wireframe
  down and then nothing ever happens. Its materials are checked and never
  taken, either (pillar 1). See "Who supplies the hours" above.
- ⬜ **Pavement can never finish.** Its work is zero hours, and
  `advance_project_labor` completes only against a requirement above zero,
  so a raised pavement plan is a project that can never complete and a
  cell that never gets paved. See "Work that is laid by hand" above.
- ⬜ **The hired villager has no visible walk to the site.** The hours are
  real and the building completes, but the NPC does not yet path there and
  animate. `BuilderMarker` exists for exactly this and is still unconsumed
  by live gameplay; wiring it belongs with
  [workforce.md](workforce.md).
