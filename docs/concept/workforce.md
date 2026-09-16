# Workforce

The player unlocks a building by obtaining its **blueprint** from a settlement
merchant, then either builds it themselves (if their own Carpentry is high
enough) or hires a sufficiently-skilled NPC to build it for them. A completed
house gains a resident. A resident who isn't already working is real,
spendable **workforce** — a workplace (starting with the Sägewerk) has a
fixed number of worker slots, and assigning a resident to one occupies that
slot and reduces the settlement's free workforce by one, the same shape
Anno's population/workforce economy uses. Closing the loop, the same way
Anno's own economy closes it: the player pays a real **wage** out of their
own gold for every filled worker slot, and every resident of a player-built
house — working or not — pays the player real **rent** in return for the
roof over their head. Gold flows both ways for the first time in this
codebase; `economy.md`'s existing shop-selling faucet is no longer the
player's only real income.

This doc is the whole pipeline end to end: blueprint → unlock → build-or-hire
→ resident → workforce → wages ⇄ rent. Every piece downstream of "obtain a
blueprint" reuses a REAL, already-built or already-designed mechanism from
another doc wherever one exists — this doc's own new material is the
blueprint-as-item unlock, the build-vs-hire fork's skill comparison, a real
NPC Carpentry number to compare against, the first live Builder spawner, a
narrow directly-triggered move-in, the workforce/worker-slot layer itself,
and the wage/rent gold loop that makes that workforce actually cost and earn
something. None of the pieces below duplicate an existing system; each says
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

## Say this once, too: "wage" and "rent" already mean other things here

The same discipline the blueprint disambiguation above applies: before any
mechanism spec, name what "wage" and "rent" already mean in this codebase, so
this doc's new gold flow reads as one more real, narrow thing rather than a
collision with four adjacent, already-real-or-designed concepts:

1. **`VillageWages`/`NpcEconomy`'s "subsistence wage"** (`npc.md`'s own
   Needs section) is a REAL, live, but purely NPC-internal safety net — a
   producing household's income is levied into a shared settlement purse, a
   hungry non-producer draws exactly one meal's worth back out. `npc.md`'s
   own doc comment is explicit: *"It is not hiring: nobody negotiates,
   nobody chooses an employer."* The player is never a party to it, and this
   doc's wage does not touch that purse or that mechanism at all — it is a
   second, separate, player-funded gold flow.
2. **`HiringGate.can_hire`/`NpcTrust`** (`npc_instructions.md`) is a real,
   tested, but entirely inert PURE COMPARISON (`trust >= threshold and
   wage_offered >= minimum_wage`) for a different feature altogether — hiring
   an NPC to run scripted instructions. No live NPC carries the `trust`
   field it reads, and — per that doc's own Status section — *"nothing pays
   [a wage] out even though `hiring_gate.gd`'s check is real."* This doc's
   wage is a separate, narrower mechanism (pay for filling a real workforce
   slot) and does not attempt to also solve the instruction-hiring gate's
   still-open trust/negotiation design.
3. **`Contract.TYPES` already lists `"rent"`** as a valid contract type
   (`player_citizenship.md`'s "Ledger" item can propose one), but
   `obligations`/`consideration` are deliberately free-form strings with no
   real currency wired in — that doc's own reasoning: *"inventing one just
   to give a contract a number to hold would be exactly the premature
   complexity the master brief warns against."* This doc's rent is the real
   number that reasoning was waiting for, but it is deliberately its OWN
   small, direct gold transfer, not a retrofit of `Contract`'s general
   (and much more broadly used) consideration field — generalizing rent
   into a structured `Contract` payload is a real, separate, explicitly
   out-of-scope follow-up (see Open Questions).
4. **`governance.md`'s "taxation"** is a much larger, civic-government
   vision — *"Later governments can tax property, trade, production,
   transactions, or households"* (`docs/emergence/03-contracts-property-
   economy.md`), gated there on "a real currency/wealth-flow system that
   doesn't exist yet." This doc's rent is exactly one narrow instance of
   that missing wealth-flow (a landlord collecting rent from their own
   tenants), not the general civic taxation system `governance.md` still
   leaves entirely unbuilt — a settlement's own government taxing the
   player, or taxing NPC-to-NPC trade, stays exactly as unimplemented as it
   already was.

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

**Blueprint tiers — reusing the WHOLE existing `HouseBlueprint` catalog, not
just its smallest entry.** Every one of `HouseBlueprint.BLUEPRINT_IDS`' 10
named shapes (hut_tiny through the L-shaped manors) is already a real,
tested piece list — this doc's own blueprint items are a THIN unlock layer
over that existing catalog, never a second geometry system. Each tier gets
its own `ItemCatalog` blueprint item and its own `CraftingRecipeBook` recipe
(`blueprint_id` == the recipe id, `output` symbolic, `inputs` pinned to
agree with that shape's own real piece cost — see `small_house`'s own doc
comment in `crafting_recipe_book.gd` for the exact pattern every further
tier repeats). Because that `output` is symbolic — no `ItemCatalog` entry,
nothing ever holds a house in a bag — a tier's recipe **never appears in
the crafting menu and is refused by the dev console's `/craft`**
(`CraftingRecipeBook.is_bench_recipe`, the one predicate both surfaces
gate on — see [production_chains.md](production_chains.md)'s "What the
crafting menu lists"): a card or a console craft would let `craft()`
consume the wood and hand back nothing, since the stamping half of
section 2 below lives in `_try_build_house_from_blueprint`, not in
`craft()`. The blueprint action is the only door to a house recipe.

**✅ Shipped: Small House** (`hut_tiny`, `required_skill` carpentry_level
`1.0` — one `carpentry_1` node, deliberately one full node below the
Sägewerk's own `2.0`, so a player's very first blueprint needs only a
single skill-web allocation).

**A real ceiling, corrected from this doc's own first-pass account.**
This doc originally claimed the player's own `carpentry_level` was only
ever exactly `0.0`/`1.0`/`2.0` — `carpentry_1`/`carpentry_2` being "the
WHOLE Artisan carpentry wedge, with no third node." That was a real
research gap: it checked `skill_tree.gd`'s smaller `_NODES` dict, not
`skill_web.gd`'s own larger ring structure, which is what `Player.
_meets_required_skill` actually reads (via `skill_bonus()` →
`skill_web.total_bonus`). Ring 3 of that SAME Artisan wedge already
carries a real notable, `master_joiner` (`stat: carpentry_level, bonus:
1.0`) — one full node beyond `carpentry_1`/`carpentry_2`, already shipped,
already in `skills.md`'s own ring table. A genuine `3.0` tier needed no
new skill-web node at all, just the recipe to spend it on:

- **✅ Shipped: Small House** — `hut_tiny`, level `1.0` (above).
- **✅ Shipped: Cottage** — a mid-tier reusing a real, larger, window-bearing
  shape (`cottage_bright`: 5×5, 3 windows), `required_skill` level `2.0` —
  the SAME ceiling the Sägewerk itself uses, so "as sophisticated as this
  project's own existing hardest-to-reach structure," not an invented
  harder number.
- **✅ Shipped: Manor** — `manor_wide` (7×5, 3 windows), `required_skill`
  level `3.0`, reached via `carpentry_1` + `carpentry_2` + `master_joiner`
  — a genuinely harder third tier, not a re-skin of Cottage's own `2.0`.
- The remaining cottage variants (`cottage_small`, `cottage_window_pair`,
  `cottage_wide`, `cottage_tall`, `cottage_L_small`) stay exactly what they
  already were — real shapes the PROCEDURAL village generator still picks
  from for NPC-built houses (`choose_blueprint_id`) — without a player-
  facing blueprint item of their own yet. Adding one for any of them is a
  direct repeat of the Cottage pattern above, not a new mechanism, so it is
  deliberately left as an easy, named follow-up rather than shipped
  speculatively ahead of any player ever asking for that specific shape.

**NPCs building sophisticated houses is not a gap this doc needs to
close.** The procedural village generator already builds every one of
these 10 shapes for NPC villagers today, occupation- and personality-
weighted (`HouseBlueprint.choose_blueprint_id`) — "diverse, sophisticated
NPC-built houses" is real and shipped, independent of blueprints
entirely (blueprints are what the PLAYER needs to unlock the same shapes
for their OWN construction). What genuinely doesn't exist yet is an NPC
Builder constructing one of these sophisticated shapes FOR the player (the
hire-a-carpenter path, section 3/5 above) — that inherits whichever tiers
have a real recipe, automatically, once the hire mechanism itself is
built; it needs no separate "NPC sophistication" work of its own.

### 2. Starting a real player-owned construction project

**✅ Shipped, one deliberate simplification from the original sketch.**
`Player._try_build_house_from_blueprint(recipe_id)` — bound to the same
facing-tile targeting every other placement verb already uses
(`_tile_targeting.facing_tile(current_tile(), _last_facing_direction)`) —
given a known (unlocked) house recipe:

1. Checks `EarthChunkManager.can_build_house_from_blueprint(recipe_id,
   target)` — a pure query refusing if the recipe isn't unlocked, doesn't
   map to a real `HouseBlueprint` shape, the target chunk isn't loaded, or
   any cell the shape would occupy is already `modification_at_global`-
   occupied. Terrain buildability (water/cliff) is deliberately NOT checked
   yet, the same simplification `BuilderMarker._buildable_ground` itself
   already accepts (a bare `return true`) — a named, honest gap, not a
   silent one.
2. Only once that already holds does it call `Player.craft(recipe_id)`
   UNCHANGED — the existing atomic `required_skill`/material gate (the same
   one the `sagewerk` recipe already exercises) both refuses an under-
   skilled or under-supplied attempt AND, on success, consumes the real
   material. This ordering is what guarantees material is never wasted on a
   placement that was always going to fail.
3. On a successful craft, forms the player's household
   (`HouseholdStore.form_household(PlayerIdentity.PLAYER_ENTITY_ID)`,
   idempotent — a second house never creates a second household) and calls
   `EarthChunkManager.stamp_house_and_grant_ownership(recipe_id, target,
   household.id)`, which stamps the real ground+roof pieces
   (`stamp_structure_at_global`) and creates-and-immediately-completes a
   real, owned `ConstructionProject` (`ConstructionProjectStore.
   start_project` + `complete_project`, granting the house's
   `property_id()` to the household for real).

One deliberate divergence from this section's original sketch: there is no
separate `BuildingPlacement.can_place` call — `can_build_house_from_blueprint`
checks occupancy directly against `modification_at_global` (the same
per-cell check `stamp_structure_at_global`'s own callers already rely on),
since `BuildingPlacement.can_place` today has exactly one real caller
(`BuilderMarker`) and pulls in enclosure/support concerns a house-blueprint
placement doesn't need yet. Revisit if a future tier needs real support/
enclosure validation before landing.

The build-vs-hire skill fork (section 3) and the hire-a-carpenter path are
NOT part of this slice — today `_try_build_house_from_blueprint` only
succeeds when the player's own Carpentry already clears the recipe's
`required_skill` (exactly what `craft()`'s existing gate already checks);
an under-skilled player is simply refused, with no hire offer yet.

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

### 4. A real NPC Carpentry number — now the real Skill Web, not a formula

**Superseded design, kept below only for its own record.** The first-pass
version of this section gave NPCs a single deterministic float
(`genome.traits["carpentry_aptitude"] * 2.0`) capped at `[0, 2)` — real and
deterministic, but a parallel formula, not the same system the player
actually uses, and mathematically incapable of ever reaching Manor's own
`3.0` threshold. Requested directly, and replaced outright rather than
patched: *"make it so it's not capped... there should be NPCs specializing
in Carpentry and the Skill Web should also be available for NPCs where
preference is based on personality and class."*

**NPCs now allocate on the SAME real `SkillWeb` graph the player does** —
`NpcSkillAllocation.allocate` (`src/world/npc_skill_allocation.gd`), a new,
small, pure module — via that class's own already-real, already-tested
primitives (`start_node_for`/`is_reachable`/`point_cost`/`nodes_in_ring`),
never a parallel reimplementation. `NpcIdentity` gains two new public
fields (`archetype`, `allocated_nodes`) alongside `carpentry_level`, which
is now read straight off them via `SkillWeb.total_bonus` — the identical
function the player's own `Player.skill_bonus` calls. An NPC who
specializes deeply enough reaches the EXACT same ceiling a player would,
`master_joiner` included — no separate, lower cap for NPCs.

**CLASS**, in the request's own word, is the wedge an occupation walks —
grounded directly in the wedges' own real node names, not an arbitrary
table: blacksmith → `artisan` (carpentry/masonry/smith all live there),
merchant → `overseer` (trade_margin/hire_capacity), guard → `warrior`
(attack_damage/max_health), herbalist and nurse → `herbalist`
(wound_recovery/disease_resistance), farmer/fisher/hunter → `ranger` (the
closest real fit for outdoor work — and, for hunter specifically, `ranger`
already carries its own real `butchering_1`/`butchering_2` nodes). Only
`artisan` — and so only **blacksmith** NPCs — ever invest in carpentry at
all; widening which occupations can specialize in it (a dedicated
"carpenter" occupation, say) is a real, separate follow-up, not attempted
here.

**PERSONALITY** (the request's second half) picks WHICH node within that
wedge, when a ring offers more than one real choice: each NPC rolls a
deterministic "specialty" stat once from their own archetype's real
`ARCHETYPE_STAT_POOL` (e.g. an Artisan's specialty is one of mining_yield/
smelting_yield/carpentry_level — the same seeded-pool-index shape
`HouseBlueprint.choose_blueprint_id` already uses for a house shape), and
prefers whichever reachable node matches it at every ring, falling back to
a deterministic pick among the real alternatives when none match (the
same "soft class, not a cage" shape `classes.md` already establishes for
the player — a specialty is a strong lean, never a hard gate on a wedge's
other real nodes).

**How much an NPC ever invests** is `NpcIdentity.SKILL_TRAITS`' own
existing genome trait — renamed from `carpentry_aptitude` to
`vocational_dedication` now that it drives investment into WHICHEVER
archetype an NPC's occupation walks, not carpentry specifically — scaled
into a small, explicit, bounded points budget (`NpcSkillAllocation.
MAX_POINTS := 6`, exactly enough for a maximally-dedicated NPC to reach one
real ring-3 notable, e.g. `master_joiner`, and no further). No RNG
anywhere, matching this whole codebase's own convention: every choice is a
deterministic function of seed alone.

**Performance, named rather than assumed fine.** `SkillWeb._init` builds
an 80+ node graph — real, bounded work, but not something to pay once per
`NpcIdentity` construction, which happens far more often than once per
session. `SkillWeb.shared()` (a new, small, cached static accessor, purely
additive to that already-tested file) builds the graph exactly once;
`NpcSkillAllocation.allocate` itself does only a small, bounded ring-walk
per call. Confirmed via a real GUT run (`test_npc_identity.gd`, 15/15) that
this is correct, not just fast.

**Named honestly as an MVP, not the finished design.** This is still an
innate, fixed-at-birth allocation, not a skill that grows from doing real
work — `labor_skills.md`'s own larger "NPCs accrue skill from
`occupation_production.gd`'s loop" vision stays exactly as unbuilt as it
already was.

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
resident household there and record it with a real event (a new
`player_house_settled` type, siblings of the existing `npc_settled`/
`player_settled` pair). One new resident per completed house, immediately,
silently (pillar 6) — not a probability, not a pull mechanic, not eligible
for the general migration system's own future floor/pull logic, which this
doc leaves exactly where it already was.

**Where the resident's own identity comes from.** There is no registry
anywhere mapping an id to a live `NpcIdentity` (confirmed absent) — the one
real, existing pattern for "a household's own NPC" is deterministic
reconstruction from a seed, exactly `EarthChunkManager._occupation_of_
household`'s own body: `NpcIdentity.new(int(EntityRef.key_of(founder_id)))`.
This doc's resident is seeded the SAME way `_house_site_seed` already seeds
the house's own door/window placement — a real, deterministic function of
the house's own site (`chunk_coord` + local `origin` + `recipe_id`) — so the
household is formed via `HouseholdStore.form_household(EntityRef.for_npc(
resident_seed))` (the same helper `NpcIdentity`'s own seed already keys
into), not a bare, undifferentiated id. Two calls
describing the same completed house always resolve to the same resident,
the same "deterministic from a real key, not a random roll" philosophy this
whole file already applies everywhere else. This resident's `NpcIdentity` is
reconstructed on demand (never stored as a live node) exactly the way
`_occupation_of_household` already reconstructs any OTHER household's
founder today — no new registry, no new persistence burden.

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

### 8. Wages: the player pays for a filled slot

A filled worker slot (section 7) is not free — the moment a resident is
assigned, the player owes that resident's household a real, periodic wage,
paid out of the player's own `Wallet` (`scenes/player.gd`'s existing
`wallet` field — the SAME class `NpcEconomy`'s own villagers already use, so
"gold" means one thing everywhere in this codebase, not a second currency
type invented for this doc).

**Where the gold lands.** A resident household needs somewhere real to hold
gold that survives its own house's chunk unloading — a live `NpcMarker`/
`NpcEconomy` instance is exactly the wrong place (per `village_wages.gd`'s
own doc comment, its shared village purse "is not persisted — a chunk
reload resets it to zero," and an ephemeral per-frame `NpcEconomy` step
would inherit the same problem). `Household` (`src/emergence/household.gd`)
is the right place instead: a small, new `wallet: Wallet` field alongside
its existing `members`/`property`, since `Household` already IS this
project's real, persistent-in-`HouseholdStore` unit for exactly this kind
of durable per-family state — no new store, one more field on an existing
one.

**A periodic tick, not a per-frame one.** Mirrors `step_regional_trade`'s
own `_accumulator >= INTERVAL` gating exactly (`EarthChunkManager.
step_regional_trade`), a new `EarthChunkManager.step_workforce_economy
(delta_seconds)` called from `World`'s own ecology-step batch alongside
`step_settlements`/`step_regional_trade`. On each due tick, for every real
`WorkforceAssignment`: `player_wallet.spend(WAGE_PER_TICK)` (a real, tested,
tuned constant, not an eyeballed comment, per this project's own
Development-process rule) credited into that resident's `Household.wallet`.
If the player can't afford it, the wage is simply not paid THIS tick — no
debt, no eviction, a resident whose wage went unpaid stays assigned (see
Open Questions: whether an unpaid resident should eventually walk off the
job is a real, separate, un-answered question, the same shape section 7's
own "reassignment and layoffs" open question already left open).

### 9. Rent: the player as landlord

Independent of employment — a resident owes rent for the ROOF, not the JOB
— every resident household of a player-built house (section 6) pays the
player rent on the SAME periodic tick section 8 already introduces. Reusing
one `step_workforce_economy` tick for both directions (wage out, rent in)
rather than two separate cadences, since both are the same "settle the
player's tenant/employer ledger" moment.

**Rent is capped by what the household actually has.** `resident_household.
wallet.spend(RENT_PER_TICK)` — Wallet's own existing `spend` contract is
already exactly "all-or-nothing, never goes negative" (`wallet.gd`), so an
empty-walleted resident simply pays nothing that tick rather than the
player's own wallet ever going negative or a household going into debt.
**Deliberately no eviction, no arrears tracking, no black-market/evasion
consequence this pass** — `docs/emergence/03-contracts-property-economy.md`'s
own fuller taxation vision names exactly these as real future mechanics
("tax changes can cause evasion... migration... black markets"), and this
doc leaves all of them exactly that unbuilt, the same honest-simplification
shape section 2's skipped terrain-buildability check already set.

**A resident who is also an assigned worker nets out for real** — they earn
`WAGE_PER_TICK` from the player and immediately owe `RENT_PER_TICK` back;
whether the constants make working-and-living net positive, negative, or
zero for a resident is a real, tunable, test-pinned relationship (see Open
Questions), not an accident of two unrelated numbers.

### 10. Needs, v1: reusing what's already real, not inventing a happiness stat

Anno's own genre touchstone models multi-tier citizen needs (food, then
goods, then luxuries) gating growth and satisfaction. Building that at real
depth needs a general goods-consumption system that doesn't exist anywhere
in this codebase yet — confirmed absent everywhere (no "happiness" concept
exists under any name in any file; the only per-NPC need modeled anywhere
is hunger, `npc.md`'s own Needs section, and that hunger is driven by a
live, PER-FRAME `NpcEconomy`/`Drives` instance tied to a loaded chunk's
`NpcMarker` — exactly the ephemeral, chunk-unload-losable kind of state
section 8 already named as the wrong place for a resident's own wallet).

**This pass's real, honest v1: a resident's needs are read off the
SAME real, persistent, already-tested signal `SettlementState.
carrying_capacity`/`status_for` already derive** — a settlement whose real
food stock is `DECLINING` (per that module's own existing 15%-band
classification) is a settlement that cannot feed its own residents, player-
built houses included. A `DECLINING` settlement's resident households pay
**no rent** that tick (their needs are unmet — asking rent from someone
your own settlement can't feed is the one behavior this doc refuses to
model as "fine"), while wages are unaffected (the player is not the one
failing to feed anyone). `GROWING`/`STABLE` settlements collect rent
normally. This is real, live, derived from data that already exists and is
already tested — not a new number invented to sound like "needs," and not
a stub that always reports "satisfied."

**Named honestly as a v1, matching this doc's own carpentry-MVP precedent
(section 4).** Multi-good consumption, a real happiness/satisfaction scalar,
migration or productivity effects tied to it, and hooking an INDIVIDUAL
resident's own hunger (rather than the whole settlement's food stock) into
this — all stay exactly as unbuilt as they already were, named in Open
Questions rather than silently implied solved.

## Status

Updated here and in `docs/progress.md` as slices land:

- ✅ `ItemCatalog` blueprint kind + `blueprint_small_house` entry
- ✅ `Shop.CATALOG` stocks it
- ✅ Event-sourced learn/has_unlocked (`EarthChunkManager.record_blueprint_
  learned_if_new`/`has_unlocked_blueprint` — a pair of methods there rather
  than the separate `ConstructionUnlock` module first sketched here, to
  match this file's own established home for every other `record_*_if_new`
  fact; see that doc comment for the reasoning)
- ✅ `Player._try_learn_blueprint`
- ✅ `small_house` `CraftingRecipeBook` recipe (`required_skill` carpentry
  level 1.0, reusing the `hut_tiny` `HouseBlueprint` shape — corrected from
  this doc's first-pass "hut" typo)
- ✅ `NpcIdentity.carpentry_level` from a new `"carpentry_aptitude"`
  `NpcGenome` trait (a separate skill genome, confirmed not to perturb
  `personality_trait`/`dominant_trait()`)
- ✅ Cottage tier (`cottage_bright`, level 2.0 — `blueprint_cottage` item,
  `Shop.CATALOG` entry, `cottage` recipe)
- ✅ A Manor tier (`manor_wide`, level 3.0 — `blueprint_manor` item,
  `Shop.CATALOG` entry, `manor` recipe). **Correcting this doc's own
  earlier claim**: level 3.0 was NOT blocked on a new skill-web node —
  `skill_web.gd`'s own Artisan wedge ring 3 already carries a real
  `master_joiner` notable (`stat: carpentry_level, bonus: 1.0`), one full
  node beyond `carpentry_1`/`carpentry_2`. The "0.0/1.0/2.0, no third
  node" note below was a real research gap (it checked `skill_tree.gd`'s
  smaller `_NODES` dict, not `skill_web.gd`'s own larger ring structure,
  which is what `Player._meets_required_skill` actually reads via
  `skill_bonus()`) — no new node was needed, just the recipe itself.
- ✅ Player-facing "start a house project" action
  (`Player._try_build_house_from_blueprint`: checks unlock+placement via
  `EarthChunkManager.can_build_house_from_blueprint`, then material+skill
  via the existing `craft()`) creating a real player-owned, immediately
  `COMPLETE` `ConstructionProject`
  (`EarthChunkManager.stamp_house_and_grant_ownership`). **Re-routed
  (2026-09-16, [building.md](building.md) "Player building re-route")**:
  the stamp now places ONE whole-building catalog house
  (`BUILDING_ID_BY_RECIPE_ID` → `place_building`) instead of legacy
  pieces; the ledger, property grant and move-in are unchanged. The ten
  two-story recipes have no whole-building form yet and refuse with that
  message (and left `Shop.CATALOG`). Every outcome is reported in
  `Player.house_build_message` (`/buildhouse` prints it).
- ✅ Build-it-yourself path — `craft()`'s existing `required_skill` gate
  (`SkillTree.total_bonus`) IS the fork's "is the player's own skill
  enough" half; the house lands already `COMPLETE` (instant, like every
  other player craft action) rather than accruing `ConstructionLabor`
  hours over time
- 🚧 The hire-a-carpenter half of the fork (section 3): the pure query
  `EarthChunkManager.find_spare_carpenter_household` (comparing the SAME
  `required_skill` against a spare household's
  `NpcIdentity.carpentry_level`) stays. **The instant hire itself is
  retired (2026-09-16)** — `Player._try_hire_carpenter_for_house`,
  `HIRE_A_CARPENTER_GOLD_COST`, `EarthChunkManager.hire_builder_for_house`,
  `_hired_builders`/`_is_household_on_loan` and the `BuilderMarker` spawner
  built a house piece by piece, and a whole-building house has no pieces
  to build. A build the player cannot do themselves now says so
  (`Player.HOUSE_HIRE_UNAVAILABLE_MESSAGE`) and spends nothing. Hiring
  returns as construction-over-time on the same settlement ledger villages
  raise their own buildings with (`SettlementConstruction`, a construction-
  site sprite from the sheet's row 0 — see
  [civic_construction.md](civic_construction.md)); `find_spare_carpenter_
  household` is exactly the labour-source answer that pass needs.
  `BuilderMarker` itself (its own tests) stays for legacy piece structures.
- ✅ Move-in: `player_house_settled` event + household formation
  (deterministic resident identity via `EntityRef.for_npc`, section 6),
  wired automatically into `stamp_house_and_grant_ownership` on project
  completion — a real, separate `resident_household_id` field on
  `ConstructionProject`, joining a real settlement's own household census
  only when one has real founding history at that chunk
- ✅ `SAGEWERK_WORKER_SLOTS := 1` — an inspectable number, not a behavior
  change from the existing always-exactly-one Lumberjack
- ✅ Workforce assignment record (`EarthChunkManager._workforce_assignments`
  + `assign_resident_to_workplace`/`open_worker_slots_at`/
  `is_resident_assigned`/`unassign_resident`) + `free_workforce_in_chunk`
  derivation. 🚧 **Simplified**: no daily-schedule routing to the
  workplace's position yet — these residents are bookkeeping-only
  households (see section 6), not live `NpcMarker`s with a schedule to
  route; a real `/workforce assign|slots|free` dev-console command is the
  only player-facing surface today (the same "dev console is a real,
  honest interim call site" choice `player_citizenship.md`'s own Deed/
  Ledger/Charter commands already made)
- ✅ `Household.wallet` (the field sections 8/9 both depend on), persisted
  through `HouseholdStore.to_dicts`/`from_dicts`
- ✅ Wages: `EarthChunkManager.step_workforce_economy`, wired into `World`'s
  own per-frame ecology batch (the same cadence `step_settlements`/
  `step_regional_trade` already run on) — pays every filled worker slot
  from the focus player's own real `Wallet` on a periodic tick, skipped
  (no debt) if unaffordable
- ✅ Rent: the same tick collects rent from every player-built-house
  resident, capped by `Wallet.spend`'s existing all-or-nothing contract
- ✅ Needs v1: rent suspended for residents of a `DECLINING`
  (`SettlementState.status_for`, via a new `_settlement_status_for` helper
  mirroring `legitimacy_for_settlement`'s own derivation) settlement
- ✅ Needs v2, a narrow real MVP: `EarthChunkManager.resident_happiness` —
  "unhappy" only when the settlement is genuinely `DECLINING` AND the
  resident's own house has zero real furniture (`housing.md`'s own
  `appeal_score` formula, `furniture_ids.size()`, read off just that
  house's footprint). A real consequence, not a cosmetic score: an
  unhappy, currently-assigned resident quits on the next tick, closing
  this doc's own "does a resident ever leave voluntarily" Open Question.
  Deliberately NOT Anno's full multi-tier luxury-goods system — see Open
  Questions for what "v3" would still need.
- ✅ Civic taxation (see `governance.md`'s own updated Status list, cross-
  referenced from here rather than duplicated): `EarthChunkManager.
  _levy_civic_tax`, the OTHER direction from Rent above — a settlement's
  own real government (any real `governance_form_for_settlement`, not
  `Governance.NONE`) taxes the PLAYER's own property within it, paid into
  that settlement's real shared purse.
- 🚧 Interior furniture (see `housing.md`'s own Status list, cross-
  referenced from here rather than duplicated) -- real pieces and a real
  placement rule exist; the live chunk layer/rendering/player verb do not
  yet

**(2026-09-13) The caveat below is resolved: a real GUT pass has now run.**
Everything marked ✅ above from "Move-in" onward was written directly,
WITHOUT the strict TDD red-first cycle this project's own `CLAUDE.md`
otherwise mandates, and without running the test suite at all — an
explicit, direct user instruction ("skip tests") mid-session, honored as
this project's actual maintainer's call to make. That gap is now closed:
blueprint-learn/build and the hire-a-carpenter fork's own infrastructure
were exercised directly (23 of the pre-existing tests run in
`test_earth_chunk_manager.gd`, the remainder within `test_player.gd`'s own
387/390), and wages/rent/needs-v2-happiness/civic-taxation (section 8-10,
`step_workforce_economy` and its five sub-steps) got 14 new tests written
against them for the first time, isolated so only the one mechanism under
test can move a wallet. **Net result: the shipped code was correct as
written.** The only defects this pass found were in the new TEST fixtures,
not the production code -- three tests (and a fourth silently passing for
the same wrong reason) never called `record_settlement_founded_if_new`
first, so `SettlementState.status_for(0, 0)` read `STABLE` rather than
`DECLINING` (an unfounded location genuinely can't decline -- see
`test_settle_resident_if_new_still_settles_far_from_any_real_settlement`'s
own pin), meaning "declining" was never actually reachable in those
fixtures at all. Fixed by founding a real settlement first; all 14 pass
now. The three residual `test_player.gd` failures are unrelated to this
feature: two are this worktree's own stale import cache on two
newly-added building sprites (an environment artifact, not a code bug),
and one is the already-flagged zero-Rhine-discharge issue.

Not re-verified by this pass, and still worth naming honestly: the 🚧
Interior furniture line above (never claimed ✅, so outside this caveat's
original scope) and the hire-a-Builder path's own no-roof gap (named
correctly already, unaffected by anything tested here).

## Open questions

- ~~A real `carpentry_3` node~~ — **resolved, and this doc's own earlier
  premise here was wrong**: `master_joiner` (Artisan wedge ring 3) already
  grants `carpentry_level +1.0`, so a genuine path to `3.0` already existed
  before this pass touched anything. The Manor tier ships against it
  directly (see Status). What's still genuinely open: `effective_bonus`
  scales every node's contribution by DNA resonance/archetype affinity, so
  a real player's carpentry_level at "3 nodes allocated" is not always
  EXACTLY 3.0 the way this doc's numbers assume (same is already true, to
  a lesser degree, of `carpentry_1`/`carpentry_2` and the Cottage/Sägewerk
  `2.0` threshold) — harmless for a `>=` gate in the direction that matters
  (a favorable resonance only makes a tier easier, never impossible), but
  worth naming rather than silently assuming exact arithmetic.
- **Real roof-building for a hired house.** `BuilderMarker` only places
  ground pieces (its own file header's declared scope) — a player-hired
  house therefore has no roof, unlike a self-built one. Giving it real
  roof-piece placement (a SEPARATE `Chunk.roof_modifications` write,
  mirroring `stamp_structure_at_global`'s own two-layer stamp) is a real,
  separate follow-up, deliberately not bundled into this pass to avoid
  changing that already-tested module's own explicit scope boundary.
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
- **The exact `WAGE_PER_TICK`/`RENT_PER_TICK`/tick-interval numbers**, and
  whether they should net a working resident positive, negative, or exactly
  zero (section 9's own "nets out for real" paragraph) — real, tested,
  test-pinned constants once chosen (per this project's own Development-
  process rule against eyeballed values), not chosen here.
- **An unpaid wage or an unpaid rent, repeated over time** — does either
  ever become "debt," trigger eviction, cause a resident to quit, or stay a
  purely momentary, forgiven-next-tick miss forever? This pass deliberately
  ships the second (simplest, honest) answer; the richer one is
  `docs/emergence/03-contracts-property-economy.md`'s own already-named
  "evasion... migration... black markets" territory.
- **Generalizing rent into `Contract`'s own structured `consideration`**
  (see the "wage/rent" disambiguation section above) rather than a direct
  `Wallet`-to-`Wallet` transfer — real future unification work, deliberately
  not attempted this pass to avoid touching `Contract`'s many other,
  unrelated callers.
- **Needs v3** (needs v2 shipped, see Status): an individual resident's own
  hunger read live (not just the settlement's aggregate food stock, which
  is what v2 still reads), genuine multi-GOOD consumption (clothing, tools,
  luxuries — v2's own "furniture" signal is really a proxy for "has this
  person invested in their home," not a goods-flow economy), a graded
  happiness scale rather than a binary content/unhappy read, and further
  consequences beyond quitting (productivity, migration, unrest).
- **Should civic tax rate vary by governance form** (a merchant oligarchy
  taxing harder than a cooperative administration, say) — shipped as one
  flat `CIVIC_TAX_PER_TICK` regardless of which real form a settlement has,
  deliberately not differentiated without real grounding for the specific
  numbers a form-by-form split would need.
- **Trade/production/household civic taxation** (`docs/emergence/
  03-contracts-property-economy.md`'s own fuller vision: governments
  taxing NPC-to-NPC trade or production, not just the player's own
  property) stays exactly as unbuilt as it already was — `_levy_civic_tax`
  only ever taxes the player.
