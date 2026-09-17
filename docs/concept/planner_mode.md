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
- ⬜ **Wireframe rendering.** The plans are real world state and the ledger
  answers `plans_in(chunk)` for exactly this, but nothing draws them yet —
  so a planned site is currently invisible on the map. This is the next
  slice and the biggest remaining gap.
- ⬜ **Persistence across save/load and chunk unload.** The ledger lives in
  `World` for now, so plans do not survive a reload. Pillar 3 says they
  must.
- ⬜ **Walking up to a wireframe: build-it-yourself, and hire-an-NPC.** The
  pieces it needs already exist (`ConstructionProject`'s `PLANNED` status,
  `ConstructionLabor`, `HiringGate.can_hire`); what is missing is the
  proximity check and the choice itself.
- ⬜ **A footprint that follows the cursor and colours itself** by whether
  it may be placed, the way Anno's does. `refusal_reason` already answers
  it per cell; nothing draws it yet.
