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

### The build palette

Asked directly, with a screenshot of ten identical text buttons in a row:
*"Make the Planner / Building HUD more professional and more like Anno 1806.
Add Icons not only text"*.

Ten equal-weight words side by side is a **list**, not a build menu. It says
nothing about what a thing looks like, what it costs, how much ground it
takes or what kind of thing it even is — a player reads "Brewery" and
learns only that the word exists. Anno's menu answers all four before a
click, and that is what this section specifies.

**A card, not a strip.** The palette is one `PanelContainer` on the shared
`UiTheme` card ([hud.md](hud.md)'s pillar 1), titled, sitting where the
hotbar sits in rpg mode.

**Grouped, and the groups are the catalogue's own.** `BuildingCatalog`
already sorts its ids into meaning-carrying lists — `BUILDING_IDS` are
homes, `PRODUCTION_BUILDING_IDS` are works, `CIVIC_BUILDING_IDS` are the
commons — and each of those lists' own doc comment says what it means. The
palette's categories **are** those lists, read at runtime, plus pavement's
own Roads group. It does not keep a second grouping: a new building lands
in the right category for free, and no category can drift out of step with
what the catalogue says a building is.

One category is shown at a time, chosen by a row of tabs — Anno's own
shape, and the thing that makes ten buildings legible where one flat row
of ten does not.

**Icons are the building's own art, never a second icon set.** An icon is
cut from exactly the picture that building will have when it is finished:
`BuildingCatalog.finished_sheet_chain`'s best available sheet, the same
chain `EarthChunkManager` draws the real building from. This is pillar 2's
"one vocabulary" applied to the menu — a drawn icon set would be a second
picture of every building, free to disagree with the first, and the player
would be choosing from pictures of buildings this game does not have.

Pavement's icon is the real road tile (`TerrainRenderer.road_tile_image`),
for the same reason and by the same rule: the surface it will lay.

The cut is **fitted into a square box**, aspect preserved, centred, never
upscaled past the box — a manor is wider than a cottage and a warehouse is
wider than both, and squashing each into a square would misreport the one
thing the icon is for. `BlueprintIcon` is that fit, pure and pinned.

**Every card says what it costs before it is clicked.** A slot carries the
building's name and its footprint; hovering it gives the full reckoning —
name, footprint in tiles, the real `BuildingCatalog.cost_of` material list,
and the labour. All of it read from the catalogue, never a second price
list (the same rule `PlanRaising` already keeps), so what the menu promises
and what raising it actually charges cannot disagree.

Work that costs no hours reads as **laid by hand** rather than as "0 hours"
— the same `PlanRaising.is_laid_by_hand` rule the raising path already
applies, said in the menu instead of discovered at the site.

**The selected slot is visibly the selected one.** A toggled button in a
`ButtonGroup`, so exactly one can be armed at a time and the mode's own
"nothing selected" state is a real state rather than a stuck-looking
button.

A `ButtonGroup` alone turned out not to be enough, and both gaps were
found by *rendering* the thing (`tools/probe_build_palette.gd`) rather
than by reading it:

- Godot draws a toggled button in its `pressed` stylebox, which in this
  theme is a shade *darker* than normal — about 5% of value, invisible
  over the card's own dark background. A menu whose selection cannot be
  seen is a menu with no selection, so an armed slot and an open tab wear
  `UiTheme.selected_button_stylebox` instead: the gold `ACCENT` that
  already means "this one" everywhere else in this UI, over a background
  that *lifts* out of the card. Applied per control rather than in the
  shared `Theme`, because `pressed` there also means a momentary click on
  every ordinary button in the game.
- `set_pressed_no_signal` deliberately does not tell the `ButtonGroup`, so
  a tab opened from code — arming a blueprint that lives in another
  category, or the palette's own first build — left the previous tab
  looking open too. The siblings are put down by hand.

`BlueprintPaletteModel` is the words — categories, what each slot says,
what a hover reads — pure and tested without standing up a `World`, the
same split `ViewMode` already keeps for the mode itself.
`BlueprintPaletteView` is the menu itself, its own `Control` for the
reason every other panel in this game already is one (`CreaturePanel`,
`HousePanel`): a menu with tabs, a selection and a footer is a thing with
*behaviour*, and behaviour buried in a 19k-line `World` can only be tested
by reading its source. What stays in `World` is only what is genuinely
`World`'s — where the card sits, and the two numbers the view is not
allowed to invent, which arrive as the same calls the raising path itself
makes.

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
- ✅ **What the hours produce** (2026-09-18) — the site rises through the
  same `_sync_construction_site` sprite a village's own project draws, and
  finishing runs the same `_place_completed_construction_project`. Before
  this, `advance_hired_build` called `advance_project_labor` directly and
  reached neither: a hired build showed nothing rising and, finished, built
  nothing. (An earlier version of this list claimed "the building
  completes". Measured, it did not — marking a ledger row `COMPLETE` is
  bookkeeping, not construction.)
- ✅ **Building it yourself really supplies the hours** (2026-09-18) — both
  ways open the project `IN_PROGRESS` through one `begin_build_project`,
  and `_step_player_builds` adds the player's own hours **while they stand
  within the same `REACH_TILES` that offered them the wireframe**. Walk
  away and the work stops where it stands. Before this the player path
  opened it `PLANNED`, which `advance_project_labor` no-ops on, with
  nothing in `World` advancing it — "Raising it yourself" took the
  wireframe down and then nothing ever happened. The materials it already
  checked for are really taken now, too (pillar 1); hiring still does not
  take them, because there the wage is what the player pays.
- ✅ **Pavement is laid by hand** (2026-09-18) — `PlanRaising.
  is_laid_by_hand` on the work's own hours, and `finish_build_project` on
  the spot. Its requirement is genuinely zero (it is not a recipe) and
  `advance_project_labor` completes only against a requirement above zero,
  so a raised pavement plan used to be a project that could never finish.
- ✅ **A raised build runs on the game's own day** (2026-09-18) — measured
  with `tools/probe_raised_build.gd`. It inherited
  `ChunkEcologyCatchup.SECONDS_PER_DAY` (3600), the deliberately
  conservative LOD rate for integrating vegetation and herds over an
  **unloaded** chunk, which is 60× the day the player lives in
  (`SECONDS_PER_SIMULATED_DAY`, 60 — what the ecosystem step, the
  settlement step, the day/night cycle and every colony already run on). A
  small house is 2.25 builder-days, so the player stood at their own site
  for **8100 real seconds** before anything finished, and somebody who had
  just paid a wage watched nothing happen for two and a quarter hours —
  indistinguishable from broken, which is how it was reported. Now 135
  real seconds, measured end to end.
  **Named divergence:** a settlement's own construction and the offscreen
  catch-up keep the catch-up rate they were tuned at. A raised build is a
  thing the player is *watching*; a village's is a background process
  integrated over absence. The two rates differing is a decision, pinned by
  `test_the_settlements_own_construction_keeps_the_catchup_rate` rather
  than left to drift.
- ✅ **Two actions, two keys, and a prompt that names them** (2026-09-19) —
  reported a third time: *"Planned nodes (e.g. pavement) still can't be
  actually built by the player or hired NPCs... there should be tooltips with
  hotkeys for both actions"*.

  The mechanism was not broken: `test_world_raising_a_plan.gd` drives it end
  to end on a real ledger, chunk manager and player, and a pavement plan
  really is laid by hand and really is laid by a paid hire. What was missing
  was the **player's half** of it, and in two ways.

  Both actions hung off the **talk key**, which offered the hire first and
  fell through to your own hands when it failed. Standing in a village —
  which is where wireframes are raised — one press did one of three things
  and nothing said which. And the floating prompt over a wireframe read
  **"Talk (G)"**, for the same reason: a villager is nearly always in
  talking range, and the prompt chain asked about people before plans.

  So `_raise_plan_yourself` and `_hire_builder_for_plan` are separate, one
  **context slot** each — the two keys `Keybindings` already keeps for
  exactly this ("what they do is decided by whatever is under the cursor and
  the state it is in"), rather than two new letters on a keyboard with one
  free. Each **refuses in its own terms**: "Nobody here to hire", "does not
  know you well enough", "You cannot pay them" — and your own hands are one
  key over, always. **A reversal, deliberately:** the old fall-through from a
  failed hire to your own labour is gone, because it is precisely what made
  the outcome unpredictable.

  A wireframe in reach is prompted **before** the villager beside you — it is
  the least ambiguous thing in reach, you walked onto it — naming the plan
  and both keys, read live from the bindings like every other prompt here.
  The overloaded `_raise_plan_within_reach` is deleted rather than left dead.

  *Named:* standing at a wireframe while also within reach of a cart or a
  tame animal, the same slot can still do both — the context slots are polled
  by `Player` as well as read here. Rare, and both outcomes are harmless.
- ✅ **The palette is a build menu rather than a row of words** (2026-09-20)
  — asked directly, with a screenshot of ten identical text buttons:
  *"Make the Planner / Building HUD more professional and more like Anno
  1806. Add Icons not only text"*. See "The build palette" above for the
  spec this landed against. `BlueprintPaletteModel` 22/22,
  `BlueprintIcon` 12/12, `BlueprintPaletteView` 15/15, `UiTheme` 12/12,
  and `test_world_planner_mode_wiring` 31/31 with its palette half
  rewritten: what the menu *does* is now driven for real rather than read
  out of `World`'s source, which is the point of the view being its own
  class.

  Icons are cut from each building's own `finished_sheet_chain` — the
  very sheet `EarthChunkManager` draws the real building from — so there
  is no second picture of any building to drift from the first. Measured
  per slot by the probe: every icon is a 48px box that is 50–100% real
  art rather than transparent padding.

  *Named:* the palette still offers exactly the ids it offered before
  (pavement + `BUILDING_IDS` + `PRODUCTION_BUILDING_IDS` +
  `CIVIC_BUILDING_IDS`), pinned by a test. `CHARTERED_BUILDING_IDS` is
  still absent — a charter is a settlement-tier gate
  ([settlement_charter.md](settlement_charter.md)), and offering a
  blueprint a player could plan but never raise is a different question
  from how the menu looks.
- ⬜ **A raised build in progress does not survive a reload.** The project
  itself is persisted, but `_hired_builds`/`_player_builds` — the records
  that say *whose* hours advance it — live only in memory. A raised build
  inside a settlement chunk keeps going anyway, because the village's own
  `_advance_construction_labor` advances every `IN_PROGRESS` project in its
  chunk; one out in the wilderness stalls at the hours it had when the
  game was quit.
- ⬜ **The hired villager has no visible walk to the site.** The hours are
  real and the building completes, but the NPC does not yet path there and
  animate. `BuilderMarker` exists for exactly this and is still unconsumed
  by live gameplay; wiring it belongs with
  [workforce.md](workforce.md).
