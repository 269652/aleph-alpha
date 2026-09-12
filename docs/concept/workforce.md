# Workforce

The player unlocks a building by obtaining its **blueprint** from a settlement
merchant, then either builds it themselves (if their own Carpentry is high
enough) or hires a sufficiently-skilled NPC to build it for them. A completed
house gains a resident. A resident who isn't already working is real,
spendable **workforce** — a workplace (starting with the Sägewerk) has a
fixed number of worker slots, and assigning a resident to one occupies that
slot and reduces the settlement's free workforce by one, the same shape
Anno's population/workforce economy uses.

This doc is the whole pipeline end to end: blueprint → unlock → build-or-hire
→ resident → workforce. Every piece downstream of "obtain a blueprint" reuses
a REAL, already-built or already-designed mechanism from another doc
wherever one exists — this doc's own new material is the blueprint-as-item
unlock, the build-vs-hire fork's skill comparison, a real NPC Carpentry
number to compare against, the first live Builder spawner, a narrow
directly-triggered move-in, and the workforce/worker-slot layer itself. None
of the other six pieces below duplicate an existing system; each says
exactly which one it reuses.

## Say this once: "blueprint" already means three other things here

Before any mechanism spec, the naming collision has to be on the table,
because getting it wrong would make every doc and every future session
misread every other one:

1. **`ConstructionProject.blueprint_id`** is, by that class's own doc
   comment, "deliberately a real `CraftingRecipeBook` recipe id, not a
   second 'blueprint' vocabulary." It is a string key into the recipe book,
   never an item, never something a player finds or owns.
2. **`HouseBlueprint`** (`src/gameplay/house_blueprint.gd`) is a catalog of
   named house *shapes* (hut, small cottage, wide/tall/bright cottage,
   L-shaped manor) the village generator uses to decide what an NPC's
   procedurally-placed house looks like. Nothing a player acquires; nothing
   player-facing at all.
3. **`BuildingBlueprint`** (`src/gameplay/building_blueprint.gd`) is an
   older, superseded, footprint-only module `HouseBlueprint` replaced for
   real house construction.
4. **The "blueprint DSL"** (`crafting.md`) is the formula that turns a base
   item + material + modifiers into deterministic weapon/gear stats.
   Unrelated to structures entirely.

**None of the four is "an item the player can buy, hold, sell, or read to
unlock a new thing they can build" — that concept does not exist anywhere in
this codebase before this doc.** Rather than reuse an already-quadruple-
booked word for a class name, the new player-facing item this doc adds is
called a blueprint in the UI/tooltip (matches this doc's own vocabulary and
the genre it's borrowing from) but is implemented as **`ConstructionUnlock`**
in code — an `Item` of a new `ItemCatalog` kind (`"blueprint"`, a plain
string value, which collides with nothing since none of the four existing
senses above is an `Item` at all) whose only behavior is recorded by a new,
small module, `src/emergence/construction_unlocks.gd`. Every doc comment
introduced by this feature says "ConstructionUnlock (displayed as
'Blueprint')" on first mention in a file, so a future reader grep-ing for
"blueprint" lands on this disambiguation instead of guessing.

## Design pillars

1. **A blueprint is a permit, not power.** Matches `items.md`'s existing
   line for premium currency, generalized: owning a blueprint never makes
   the player stronger, it only expands what they are ALLOWED to attempt to
   build. All the real gates (skill, material, placement) are unchanged by
   owning one; it is a pure unlock, checked once, alongside those gates, not
   instead of them.
2. **A player's own building is a real `ConstructionProject`, not a second
   ledger.** `ConstructionProject.household_id` is already an untyped
   `String` — nothing stops a real player household id
   (`PlayerIdentity.PLAYER_ENTITY_ID` via `HouseholdStore.form_household`)
   from being a legitimate value today; no live caller has ever supplied
   one. This doc is the first real caller. `civic_construction.md` already
   named generalizing the ledger to "a player's own build site" as the
   next real step; this doc is that step, scoped to houses specifically
   rather than civic buildings.
3. **Build it yourself, or pay someone who genuinely can — one real
   number, two comparisons.** The existing `required_skill: {"stat_name",
   "level"}` recipe field is read against the PLAYER via
   `SkillTree.total_bonus` today (the `sagewerk` recipe already does this).
   This doc reads the exact same recipe field against an NPC's own real
   Carpentry number for the hire path — one threshold, checked against
   whichever of the two parties is actually swinging the hammer, never two
   different numbers pretending to be the same gate.
4. **A house is population, not scenery.** The moment a player-owned house
   construction project reaches `COMPLETE`, it is exactly as real a
   dwelling as an NPC-village house — same `BuildingPiece`/room-enclosure
   rules, same eligibility for a resident.
5. **Workforce is derived, never stored.** `SettlementSpareCapacity.
   for_settlement` already computes "spare labor" as `household_count -
   households_on_survival_duty`, recomputed fresh every time it's asked,
   never synced. Free workforce here is the same idiom one layer up:
   `residents_of_player_built_houses - residents_currently_assigned_to_a_
   worker_slot`. There is deliberately no `free_workforce` field anywhere to
   go stale.
6. **Silent and observable, not a popup.** Matches `timber_construction.md`'s
   own pillar exactly: no quest, no toast when an NPC moves in or takes a
   job — the player notices the same way they notice village growth, by
   looking.

## Genre grounding, honestly labelled

Unlike this project's ecology docs, the workforce/worker-slot shape here is
a **game-design borrow, not a real-world model** — worth saying plainly
rather than dressing it up as research. Anno's population tiers provide
inhabitants; production buildings declare a worker requirement; an
under-staffed building runs at reduced or zero output; the player's whole
mid-game loop is matching housing growth to production headcount. This doc
takes exactly that shape — houses provide residents, workplaces declare
worker slots, an unfilled slot is a real, felt shortfall — grounded in this
codebase's own existing "population vs. survival-occupation" arithmetic
(`SettlementSpareCapacity`) rather than inventing a parallel number.

## Mechanism spec

### 1. Blueprints: obtaining one, and what it unlocks

**The item.** A new `ItemCatalog` entry per building, e.g. `blueprint_small_
house` — kind `"blueprint"`, non-stackable, no weight/material line (per
`items.md`'s own "a stat not modelled is omitted" rule, since a blueprint
has neither). Tooltip kind line reads "Blueprint" (see disambiguation
above); its one line of extra tooltip text names what it unlocks: "Teaches:
Small House".

**Selling it.** `Shop.CATALOG` today is one flat catalog every merchant
sells from (`shop.gd`'s own documented "Phase 1 simplification"). This
doc adds `blueprint_small_house` to that same catalog rather than inventing
a second merchant type or a second stocking mechanism — every settlement
merchant can sell the first blueprint, exactly as bluntly simple as the
existing catalog already is, and exactly as easy to narrow later (a
dedicated "carpenter's supply" merchant subtype) without anything here
depending on the narrowing happening.

**Learning it.** Using a blueprint from the inventory (a new player verb,
`_try_learn_blueprint`, matching this codebase's existing `_try_<verb>`
naming for an item-triggered action that can fail — see `_try_eat`,
`_try_plant_seed_at`) mirrors `items.md`'s own already-specified spell-
scroll pattern exactly: *"Reading one attempts to permanently learn the
spell ... consumed only on a successful learn."* A blueprint that resolves
to a real, not-yet-known recipe is consumed and a `blueprint_learned` event
is appended (actor: the player's own entity id, tags: `[recipe_id]`) —
event-sourced, not a transient flag, the same "the fact is the event
history" discipline `_recorded_settlement_status` and every sibling
`_recorded_*` reader in `earth_chunk_manager.gd` already use. A blueprint
for an already-known recipe fails to consume (nothing to learn) rather than
silently vanishing — same "an invalid transition does nothing" rule this
codebase applies everywhere else.

`ConstructionUnlock.has_unlocked(event_store, actor_id, recipe_id) -> bool`
reads that history back (scans for a `blueprint_learned` event naming
`recipe_id`) — no new store, `EventStore` already is the store.

**First blueprint: Small House.** Reuses an EXISTING `HouseBlueprint` shape
as its geometry — the smallest current entry (`"hut"`) — rather than adding
a new footprint/piece system. Its `ConstructionProject.blueprint_id` is a
new `CraftingRecipeBook` recipe, `small_house`, whose inputs are the same
piece materials `HouseBlueprint.build()` already itemizes for that shape
(wood walls/floor/roof, per `building.md`'s existing piece-cost table) and
whose `required_skill` is `{"stat_name": "carpentry_level", "level": 1.0}`
— deliberately ONE full `carpentry_1` node below the Sägewerk's `2.0`, so a
player's very first blueprint is buildable with a single skill-web
allocation, not the same two-node bar as a production building. (The exact
number is a design placeholder pinned by a test at implementation time, not
asserted as final here — same convention `civic_construction.md`'s own
"illustrative until implementation" numbers already use.)

### 2. Starting a real player-owned construction project

A new player action (e.g. bound alongside the existing build cursor) that,
given a placement footprint and a known (unlocked) house recipe:

1. Checks `ConstructionUnlock.has_unlocked` for that recipe — refuses with
   "you don't know how to build this yet" if not.
2. Checks `BuildingPlacement.can_place` — the exact same call the village
   generator and every existing player placeable already use, per
   `building_placement.gd`'s own doc comment ("the player's build cursor
   and the village generator ask the same question of the same code").
3. Checks the recipe's material cost is affordable (same `CraftingRecipeBook`
   input-count check `Player.craft` already runs for every other recipe).
4. Calls `ConstructionProjectStore.start_project` with the player's own
   household id — a real `PLANNED` project, indistinguishable in the store
   from a settlement's own, because pillar 2 says it should be.

### 3. The fork: build it yourself, or hire someone who can

Read once the project exists, from the SAME recipe's `required_skill`:

- **Player builds it themselves** if `SkillTree.total_bonus("carpentry_
  level", player_allocated_nodes) >= required_level`. Mechanically nothing
  new: the player's own hand-placement already accrues
  `labor_hours_accumulated` via `ConstructionLabor`'s existing "two
  fidelities, one truth" formula, the same path an NPC Builder's placements
  already share.
- **Player hires an NPC Builder** if their own skill falls short. This is
  where a REAL, per-NPC Carpentry number is required (see section 4) — not
  a labor-hours-only "pay and it's done" shortcut, because a settlement
  with nobody skilled enough yet is meant to be a real, feelable
  limitation, the same way a settlement with no real skill/labor source is
  already explicitly named as a blocker in `civic_construction.md`.
  Mechanically, this is `timber_construction.md`'s own already-specified
  "pay gold to pull a settlement's spare Builder to the player's own site"
  design (quoted there in full), with one added filter: only a spare
  household whose own NPC's `carpentry_level` (section 4) clears the same
  `required_level` is offered. A settlement with real spare capacity but
  nobody skilled enough correctly offers no hire — the player either waits,
  looks elsewhere, or raises their own skill instead.

Both paths converge on the same `ConstructionProject`; `COMPLETE` doesn't
care which one got it there.

### 4. A real NPC Carpentry number

NPCs have no numeric skill of any kind today — confirmed absent everywhere
in the codebase, and `labor_skills.md`'s own fuller vision for "NPCs grow
skill from real repeated work" is entirely `⬜`. Building that whole
system is explicitly out of scope here (it is `labor_skills.md`'s own,
much larger, cross-cutting backlog item, spanning ten skills). What this
doc needs is much narrower and, per the codebase's own existing tools, is
close to free:

**`NpcGenome` already IS "a real, continuous, deterministic-from-seed
number per named trait," generalized on purpose.** Its own doc comment:
*"the same 'continuous 0..1 gene per trait, deterministic from a seed'
shape ... generalized to an arbitrary trait-name list passed in by the
caller ... nothing here is personality-specific."* Adding `"carpentry_
aptitude"` to whatever trait-name list an NPC's genome is built from costs
nothing new in `npc_genome.gd` itself — it is exactly the extension point
that doc comment describes. `NpcIdentity.carpentry_level` (a new, small,
public float) is then `genome.traits["carpentry_aptitude"] * 2.0`, scaled
into the SAME `[0, 2]` range `carpentry_1`/`carpentry_2` already put the
player's own stat in, so the exact same recipe threshold (`level: 1.0`,
`level: 2.0`, ...) means the same thing whichever side is being checked.

**Named honestly as an MVP, not the finished design.** This is an innate,
fixed-at-birth aptitude, not a skill that grows from doing carpentry work —
the "grows from `occupation_production.gd`'s existing automatic recipe
loop" vision `labor_skills.md` describes for NPC skills generally stays
exactly as unbuilt as it already was; wiring real growth into this one
number later is a named, separate follow-up (see Open Questions), not
something this pass pretends to have solved.

### 5. Hiring: the first live Builder spawner

`timber_construction.md`'s own Status section names this exact gap twice
over: *"no live spawner exists yet that decides a Builder should exist for
a given `ConstructionProject` and injects its `target_pieces`"* — true for
both a settlement's own queue and a player's hired case. This doc builds
that spawner, but scoped ONLY to the player-hired path (a settlement
deciding to spawn a Builder for its OWN queued work stays exactly as
unimplemented as it already is — a strictly separate, larger gap this
feature does not need to close to work).

On a successful hire (section 3's filter already found a qualifying spare
household): spawn a real `BuilderMarker` for that household's NPC, hand it
the player's `ConstructionProject`'s remaining `target_pieces`, and reduce
that settlement's own effective spare capacity for the hire's duration —
`SettlementSpareCapacity`'s own formula already recomputes fresh every
call, so "one Builder is currently on loan" is tracked the same lightweight
way an NPC's `Household` already tracks any other momentary assignment,
not a new ledger.

### 6. Move-in: a narrow, directly-triggered shortcut

**This is explicitly NOT** `quests.md`'s "Settlement growth: migration
toward player-built structures" section — that full mechanism (habitability
pull, replan-interrupt, a floor before eligibility, active player-invite)
stays exactly as specified there and exactly as unbuilt, because it
extends `npc.md`'s lifecycle section, and lifecycle (aging/reproduction/
death) doesn't exist yet. Building the general mechanism is out of scope
for this doc.

What this doc does instead is the same shape `timber_construction.md`'s own
Logistics-worker auto-spawn already is for occupation-pull — *"a directly-
triggered shortcut for one specific case, not an implementation of the full
mechanism"*: the moment a player-owned house `ConstructionProject` reaches
`COMPLETE` and its house has no resident household, directly form one new
resident household there (`HouseholdStore.form_household`, the same call
`record_settlement_founded_if_new` already uses) and record it with a real
event (a new `player_house_settled` type, siblings of the existing
`npc_settled`/`player_settled` pair). One new resident per completed house,
immediately, silently (pillar 6) — not a probability, not a pull mechanic,
not eligible for the general migration system's own future floor/pull
logic, which this doc leaves exactly where it already was.

### 7. Workforce: a real, spendable resource

**Population.** A resident of ANY player-built house (section 6) who is not
currently assigned to a worker slot is available workforce. Read fresh,
never stored (pillar 5) — the same "recompute, don't sync" idiom
`SettlementSpareCapacity.for_settlement` already established one layer
down, generalized from "spare capacity for construction" to "spare capacity
for any worker slot."

**Worker slots.** A workplace declares a real `worker_slots: int` — the
Sägewerk is the first (today it auto-spawns exactly one `LumberjackMarker`
per placement with no slot concept at all; this doc turns that fixed "one"
into `worker_slots := 1`, a real, inspectable, and — for a future,
separately-scoped pass — potentially upgradeable number, not a change of
behavior for the existing single-worker case).

**Assignment is real and mutable — the one genuine architectural
extension.** Today `NpcIdentity.occupation` is fixed forever at spawn
(deterministic from seed, never reassigned). A resident taking a workforce
job is the first case of an NPC's work assignment changing after creation.
Scoped deliberately narrowly: this applies ONLY to residents of player-built
houses filling a REAL workplace slot, not a retrofit of every existing
procedurally-generated village NPC's fixed occupation — the existing
`OCCUPATIONS`/`WORK_LOCATION_BY_OCCUPATION` system for village-generated
NPCs is untouched, so no already-tested existing behavior is at risk.
Assigning a resident to a slot: records the assignment (a new small
`WorkforceAssignment`-shaped record, resident household id -> workplace
position + occupation-equivalent label), reduces that workplace's open
slot count by one and the settlement's free workforce by one (both derived
reads, not stored counters), and routes that resident's daily schedule to
the workplace's position — reusing `WORK_LOCATION_BY_OCCUPATION`'s existing
"a location tag to walk to during work hours" shape rather than inventing a
second scheduling system.

**An unfilled slot is a real shortfall, not a display state.** A Sägewerk
with an open slot and nobody assigned produces at whatever reduced rate
zero/partial staffing already implies for its production formula (today:
none, since one Lumberjack always exists per Sägewerk; a future pass that
lets `worker_slots` exceed 1 is what makes partial staffing a real,
distinct state worth its own production-scaling rule — out of scope here,
named for later).

## Status

Nothing in this doc is built yet — this is the spec, written before any
implementation line, per this project's own doc-before-code discipline.
Updated here and in `docs/progress.md` as slices land:

- ⬜ `ItemCatalog` blueprint kind + `blueprint_small_house` entry
- ⬜ `Shop.CATALOG` stocks it
- ⬜ `ConstructionUnlock` module (event-sourced learn/has_unlocked)
- ⬜ `Player._try_learn_blueprint`
- ⬜ `small_house` `CraftingRecipeBook` recipe (`required_skill` carpentry
  level 1.0, reusing the `"hut"` `HouseBlueprint` shape)
- ⬜ Player-facing "start a house project" action (checks: unlock,
  placement, material) creating a real player-owned `ConstructionProject`
- ⬜ Build-it-yourself path wired to the player's own `SkillTree.
  total_bonus` check (reuses existing hand-placement/`ConstructionLabor`)
- ⬜ `NpcIdentity.carpentry_level` from a new `"carpentry_aptitude"`
  `NpcGenome` trait
- ⬜ Hire-a-Builder path: spare-capacity filter by `carpentry_level`, gold
  cost, settlement-side capacity reduction for the hire's duration
- ⬜ The first live `BuilderMarker` spawner (player-hired projects only)
- ⬜ Move-in: `player_house_settled` event + household formation on project
  completion
- ⬜ `worker_slots` on the Sägewerk (starts at the existing implicit 1)
- ⬜ Workforce assignment record + free-workforce derivation + daily-
  schedule routing to the workplace

## Open questions

- **Growing NPC Carpentry from real work**, closing the gap this doc
  deliberately leaves open (section 4) — waits on `labor_skills.md`'s own
  larger "NPCs accrue skill from `occupation_production.gd`'s loop" item,
  which this doc does not attempt to build.
- **Reassignment and layoffs.** Can a resident already working one
  workplace be reassigned to another, or fired outright if a workplace is
  destroyed? Today's spec only covers first assignment into an open slot.
- **What happens to a resident if their house is destroyed or decays away**
  (`BuildingDecay` already models withering) — does the workforce
  assignment survive, end, or migrate the resident elsewhere?
- **Does a resident ever leave voluntarily** (dissatisfaction, a better
  offer elsewhere), or is an assignment permanent once made?
- **Hiring cost formula** — flat, distance-scaled, or reputation-scaled?
  Left exactly as open as `timber_construction.md`'s own hiring design
  already leaves it.
- **More than one blueprint-gated building at once** — does a second
  blueprint (a workshop, a warehouse) reuse every mechanism above verbatim,
  or does a production building's worker-slot concept need something a
  pure house doesn't (e.g. an input/output rate tied to staffing
  fraction)? The Sägewerk's `worker_slots := 1` starting point is
  deliberately the smallest possible instance of the general case, not
  proof the general case needs nothing more.
- **Should `worker_slots` ever exceed 1 for the Sägewerk itself**, and if
  so what does partial staffing do to `SagewerkProduction`'s own rate —
  named in section 7 as future work, not answered here.
