# Production Chains: Recipe Gating and the Recursive "What Do I Need" Walk

`crafting.md` and `smelting.md` already establish the base loop: gather,
craft, and — for smelting specifically — do it near the right structure.
But every gate so far has been a one-off, hardcoded special case: smelting
is the ONE recipe kind `Player.craft` knows to heat-gate, because someone
wrote `if _smelting.is_smelting_recipe(recipe_id) and not
_has_heat_source(): return false` directly into `craft()`. Reported
directly, twice, against two different concrete asks: "you also need a
given crafting skill level to build a sawmill... [and] this needs to work
for all future buildings and economics," and — for a settlement deciding
what to build — "we need a dependency chain which causes NPCs to
understand that they need a Sawmill in order to produce construction
material... also for quests and other things."

This doc is the general answer to both: two small, OPTIONAL fields on a
`CraftingRecipeBook` recipe (`required_skill`, `requires_structure`) that
`Player.craft` reads generically instead of switching on recipe id, and a
pure recursive resolver (`NeedResolver`) that walks the recipe graph
backwards from a target item to name every real reason it can't be made
right now — a missing skill, a missing structure, or a missing
sub-material, however many hops down. It does not replace `crafting.md`'s
eventual blueprint DSL; it is the dependency-and-gating layer underneath
today's simple fixed-picklist recipes, and stays equally underneath
whatever richer recipe representation crafting.md eventually ships.

## Design pillars

1. **A recipe declares its own gates; nothing else hardcodes them.**
   `required_skill`/`requires_structure` live on the recipe, in
   `CraftingRecipeBook`, next to the inputs/output they gate. `Player.craft`
   reads them generically. Adding a gate to a NEW recipe in the future means
   adding two dictionary keys, not a new `if` branch in `craft()`.
2. **Purely additive — every existing recipe keeps working.** Neither field
   is required. A recipe that doesn't declare `required_skill` has no skill
   gate; a recipe that doesn't declare `requires_structure` has no
   structure gate. This is a regression-tested guarantee, not an
   assumption — see `crafting_recipe_book.gd`'s own test coverage.
3. **One resolver, not one per caller.** The literal ask was "this needs to
   work for all future buildings and economics... also for quests and other
   things." `NeedResolver` is that one shared mechanism: the Sägewerk's own
   dependency-chain reasoning (`timber_construction.md`), a settlement
   deciding what to build next, and a quest wanting to explain WHY an item
   is missing all read the same recursive walk over the same
   `CraftingRecipeBook`, rather than each growing its own bespoke
   resolution logic that can silently disagree with the others.
4. **A resolver, not a solver.** `NeedResolver` answers "what's missing,"
   never "here's how to get it" (no pathfinding, no NPC dispatch, no
   purchase order). Turning a named need into an action is entirely the
   caller's job — quests.md's own reward/consequence machinery, or
   timber_construction.md's settlement construction ledger, or a future
   trade negotiation. Keeping the resolver a pure query keeps it reusable
   across all of them without assuming any one caller's execution model.
5. **A cheap real safety net, not defensive paranoia.** The recipe graph
   today is small and hand-authored, so a genuine cycle is unlikely — but
   "unlikely" is not "impossible" once recipes are data anyone (a modder, a
   future authoring tool, a bug) can add to. A bounded recursion depth costs
   nothing to include and turns a hypothetical infinite loop into a
   silently-truncated, still-correct-enough answer instead of a hang or a
   stack overflow.
6. **Tuned values are tested constants, not comments.** `NeedResolver.
   MAX_DEPTH` is pinned by `test_cycle_guard_terminates_on_a_cyclic_recipe_
   graph`, per this project's no-manual-tuning rule, not an eyeballed
   number with a comment next to it.

## Real-world grounding

- **Bill of materials (BOM) and multi-level BOM explosion.** Real
  manufacturing represents a finished product as a recursive tree: a car
  needs an engine, which needs pistons, which need forged steel, which
  needs raw ore and coal at a furnace. "BOM explosion" is the literal
  industry term for walking that tree from a top-level item down to its raw
  material requirements — exactly `NeedResolver`'s own recursive walk from
  a target item down to raw/gathered leaves.
- **A blocked production line names its actual blocker.** A real factory
  floor that runs out of a sub-part doesn't just report "line stopped" — a
  real MRP (material requirements planning) system names the specific part,
  and often the specific missing UPSTREAM part, not just the symptom at the
  final assembly step. This is the difference this doc's "deeper
  resolution" makes over the existing shortfall quest's flat "missing:
  rock" — for a raw material that's the same answer, but for `iron_helm`
  it's the difference between "missing iron_ingot" and "missing a heat
  source AND raw ore/coal," the real actionable chain.
- **Tool/facility gating is universal in real crafts, not a game
  invention.** A blacksmith cannot forge without a forge; a sawmill needs a
  real building, not just logs, to turn timber into lumber; a licensed
  tradesperson's own certification (a real skill threshold) gates which
  jobs they're allowed to take on. `requires_structure`/`required_skill`
  model exactly these two real gate types — a place, and a trained
  capability — as the two general categories, rather than inventing a
  third for every new recipe.
- **Dependency graphs, not dependency lists.** Real supply chains and real
  tech trees (Factorio's own recipe graph is the game-design analogue
  most directly comparable here) are graphs, not flat lists — an item can
  depend on another item that itself has its own dependencies, and the
  same intermediate can feed multiple higher-level products. `NeedResolver`
  reasons over the same shape `CraftingRecipeBook` already is (recipe_id ->
  inputs, several recipes able to consume the same intermediate item), not
  a simplified flat table.

## Mechanism

### The two recipe fields

`CraftingRecipeBook`'s recipe dict shape gains two OPTIONAL keys:

```
recipe_id -> {
  "inputs": [{"item_id": String, "count": int}, ...],
  "output": {"item_id": String, "count": int},
  "required_skill": {"stat_name": String, "level": float},  # OPTIONAL
  "requires_structure": String,                             # OPTIONAL
}
```

- `required_skill` names a `SkillTree` stat and the threshold total_bonus
  must reach — read live via `SkillTree.total_bonus(stat_name,
  allocated_nodes)`, the exact pattern `Player._chop_step`'s own
  `CARPENTRY_LEVEL_FOR_SAWING` check already established. The `sagewerk`
  recipe is the first real consumer: `{"stat_name": "carpentry_level",
  "level": 2.0}`, pinned to the SAME real threshold
  `CARPENTRY_LEVEL_FOR_SAWING` already uses for the same real skill — not a
  second invented number for Carpentry.
- `requires_structure` names a structure id that must be built/nearby (see
  `EarthChunkManager.has_structure_near`). One value is an abstract
  CATEGORY rather than one specific structure id: `"heat_source"`, which
  `Player._has_heat_source` already resolves as "a campfire OR a furnace,
  either counts" — `smelting.md`'s own existing vocabulary ("a heat source
  present: a campfire, or the sturdier crafted furnace"), not a new
  concept. Every other value (`"sagewerk"`, and any future structure id)
  names one real, specific structure directly.

### Player.craft's generalized gate

The old `craft()` had exactly one hardcoded special case: `if _smelting.
is_smelting_recipe(recipe_id) and not _has_heat_source(): return false`.
That branch is now gone, replaced by two small generic checks, each
consulting the recipe's own declared fields:

- `_meets_requires_structure(recipe_id)`: no gate declared → true. Gate ==
  `"heat_source"` → defers to the existing `_has_heat_source()` (still
  campfire-OR-furnace, unchanged). Any other gate value → a direct
  `_has_structure_near_player(structure_id)` check.
- `_meets_required_skill(recipe_id)`: no gate declared → true. Otherwise
  reads `skill_tree.total_bonus(stat_name, allocated_nodes)` live and
  compares against the recipe's threshold.

`craft()` calls both before doing anything else. This is a regression-
tested, behavior-preserving refactor for smelting (iron_ingot/copper_ingot
now declare `requires_structure: "heat_source"` and behave identically to
before) AND the mechanism that makes the Sägewerk's new `required_skill`
gate — and any future recipe's gates — actually refuse a craft in
practice, not just exist as unread data.

### NeedResolver: the recursive "what do I actually need" walk

`src/gameplay/need_resolver.gd`, pure `RefCounted`, no engine dependency.
Given a target `item_id`, a real stock `Dictionary` (item_id -> count from
whatever the caller's own stock source is — player inventory, `Market.
stock`, a Storage building's own stock), an `allocated_nodes` Dictionary
(the same shape `Player.allocated_nodes`/`SkillTree` already use), and a
`nearby_structures` Dictionary (structure_id -> true, mirroring
`allocated_nodes`'s own id -> bool shape), `resolve()` walks
`CraftingRecipeBook` recursively and returns the ordered `Array` of real
unmet needs — or an empty `Array` once the target is already satisfied.

The walk, per item, at each recursion depth:

1. Already in stock (>= the amount this call needs)? Nothing to report —
   the base case that stops recursion down a satisfied branch.
2. Not in stock: does anything produce it? `CraftingRecipeBook.
   recipe_for_output(item_id)` (new reverse lookup: output item_id ->
   recipe_id, "" if nothing produces it) answers this. Nothing produces
   it → this item is raw/gathered, and the walk bottoms out here: a
   `{"kind": "material", "item_id": ..., "need": ...}` need, "go get it
   from the world," matching `Quest.production_shortfall_quests_for`'s own
   `{"item_id", "need"}` shape for consistency.
3. Something DOES produce it: check that recipe's own `requires_structure`
   (missing and not in `nearby_structures` → a `{"kind": "structure", ...}`
   need) and `required_skill` (short of the threshold → a `{"kind":
   "skill", ...}` need, naming `stat_name`/`level`/current `have`). Both
   checks are independent of the recursion below — a structure/skill gap
   is real regardless of whether the sub-materials also happen to be
   short.
4. Recurse into every one of that recipe's OWN inputs, at THEIR own
   required count, appending whatever each sub-walk reports. A multi-hop
   chain (e.g. `iron_helm` -> `iron_ingot` -> `iron_ore`/`coal`) surfaces
   every real blocker at every level, not just the first one hit.

A `MAX_DEPTH` recursion cap (see Design pillar 5/6) is the cheap safety
net: past it, the walk simply stops reporting further down that branch
rather than recursing forever on a cyclic recipe graph. Real chains in
this game today are 1-2 hops deep — `MAX_DEPTH` is a generous, tested
bound, not a realistic limit any real recipe should ever approach.

### Quest's new additive capability

`Quest.production_shortfall_quests_for` (Phase 5/12, the existing
settlement-shortfall quest generator) is untouched — same signature, same
behavior, same one real call site
(`EarthChunkManager.production_shortfall_quests_for_settlement`). A NEW,
separate, purely additive function, `Quest.deeper_need_for(item_id, stock,
allocated_nodes, nearby_structures, recipe_book)`, exists alongside it: for
one specific item named in an existing shortfall quest's own `"missing"`
list (or any other item id a caller wants the deeper picture on), it
delegates straight to `NeedResolver.resolve`. A caller that wants MORE than
"how many of item_id are missing" — explaining to a player WHY, or a
settlement's own construction-ledger reasoning per `timber_construction.md`
— reaches for this; nothing about the existing shortfall-quest path
changes underneath it.

### Sägewerk production: a deliberate, named narrowing

`timber_construction.md`'s own framing describes the Sägewerk's log ->
Balken/Planke shaping eventually running through "a real recipe +
Market.produce." This pass deliberately does NOT do that rewrite.
`SagewerkProduction.advance` (the Sägewerk's own already-tested, carefully-
tuned continuous production formula — real dual-lane concurrent beam/plank
shaping off a shared log stockpile, staffed by its Lumberjack) keeps
running exactly as it already does, untouched.

Instead, two new `CraftingRecipeBook` entries — `log_to_balken` and
`log_to_planke`, each `requires_structure: "sagewerk"` — exist PURELY so
`NeedResolver` has real recipe nodes to walk through when reasoning about
beam/plank's dependency chain (e.g. "a house needs Balken; Balken need a
Sägewerk and logs"). Their input counts are pinned by test to agree with
`SagewerkProduction.LOG_COST_PER_BEAM`/`LOG_COST_PER_PLANK` so the two data
sources can never silently disagree. A player does not craft a Balken by
hand at a bench through these entries in practice — the Sägewerk's real
production is the Lumberjack-staffed mill, not `Player.craft`. This is an
honest, acknowledged scope decision, not an oversight: rewriting an
already-working, carefully-tuned continuous-production module into a
discrete per-craft recipe call is a real, risky change for no functional
gain in this pass, and is explicitly deferred rather than attempted here.

## Interaction with other docs

- **[crafting.md](crafting.md)** — this doc's two recipe fields sit
  underneath today's simple fixed-picklist `CraftingRecipeBook` and will
  sit underneath crafting.md's eventual blueprint DSL exactly the same
  way; it does not compete with or anticipate that DSL's own modifier-slot
  design.
- **[smelting.md](smelting.md)** — the heat-source gate itself is
  unchanged in behavior; only its mechanism generalized, from one
  hardcoded `is_smelting_recipe` branch to `requires_structure:
  "heat_source"` read generically. `Smelting.is_smelting_recipe`/
  `smelted_output` remain real and unchanged for their own purpose (naming
  which recipes are smelts, and which ore smelts into which ingot);
  `Player.craft` simply no longer needs to ask `Smelting` that question to
  decide whether to gate a craft.
- **[timber_construction.md](timber_construction.md)** — this doc's own
  "generalized, not hardcoded" section names `required_skill` as the real
  mechanism behind the Sägewerk's Carpentry gate, and its own "dependency
  chain" section names `NeedResolver` as the real mechanism behind "how do
  NPCs understand they need a Sawmill." Both are implemented here; that
  doc's own Status section records the Sägewerk-specific application, not
  a duplicate of this doc's general one.
- **[quests.md](quests.md)** — `Quest.deeper_need_for` is the concrete,
  additive answer to a quest wanting to explain WHY an item is missing,
  not just that it is; it does not change the existing production-
  shortfall quest mechanism quests.md already documents.
- **[regional_trade.md](regional_trade.md)** / **[trade.md](trade.md)** —
  per `timber_construction.md`'s own framing: when `NeedResolver` finds NO
  missing producer for a shortfall (the settlement already has one, or the
  item is raw/gathered with no real producer at all), the existing
  regional-trade shortfall path applies completely unchanged. `NeedResolver`
  only changes what happens when a missing PRODUCER (a building) is the
  actual blocker — that case routes to construction, not trade.
- **[skills.md](skills.md)** / **[labor_skills.md](labor_skills.md)** —
  `required_skill` reads `SkillTree` (the PoE-style stat-node web), not
  `labor_skills.md`'s separate use-based mastery track — matching which of
  the two systems `CARPENTRY_LEVEL_FOR_SAWING` (the precedent this doc's
  first real consumer matches) already reads.

## Worked examples

**A. A player without Carpentry tries to build a Sägewerk.** They gather 8
logs and 4 wood and open the crafting menu. `can_craft` reports the
materials are sufficient, but `craft("sagewerk")` still returns false:
`_meets_required_skill` reads `total_bonus("carpentry_level",
allocated_nodes)` as 0.0, short of the recipe's 2.0 threshold. Nothing is
consumed. Once they allocate both `carpentry_1` and `carpentry_2`, the
exact same call succeeds — no materials were wasted on the failed attempt
either time.

**B. A settlement's construction ledger asks what it needs for a house.**
(Per `timber_construction.md`'s own still-unbuilt settlement ledger — this
worked example describes how that FUTURE caller would use `NeedResolver`
once it exists, not a currently-wired call site.) The blueprint needs 4
Balken. `NeedResolver.resolve("beam", settlement_stock, {}, settlement_
structures)` walks: not enough beam in stock → `log_to_balken`'s recipe →
no Sägewerk nearby → a `{"kind": "structure", "structure_id": "sagewerk"}`
need. The settlement's own decision logic (not this doc) reads that and
prioritizes building a Sägewerk before the house project that needs it —
the concrete answer to "how do NPCs understand they need a Sawmill,"
without a scripted tech-tree unlock.

**C. A player asks a shortfall quest "what do I actually need to fix
this."** A production-shortfall quest already names `iron_ingot` as
missing for a blacksmith household. `Quest.deeper_need_for("iron_ingot",
market_stock, {}, settlement_structures, recipe_book)` reports the real
answer is a missing heat source (a campfire or furnace, not yet present
near that household) — not a phantom ore/coal shortage if the settlement
already has both banked. The player brings a campfire, not more ore.

## Open questions

- **Quantity scaling through the recursive walk.** `NeedResolver` reasons
  in recipe-hops, not batch-multiplied quantities: asking for 2 iron_helm
  (each needing 2 iron_ingot) does not currently ask `NeedResolver` to
  resolve 4 iron_ingot's worth of ore/coal — each recursive step uses the
  RECIPE's own stated per-craft input count, not the parent's requested
  multiple. Correct for "is this producible at all right now" (today's only
  real caller shape), but a future caller wanting an exact bulk material
  count would need this doc's own scaling extended, not assumed.
  Deliberately left unresolved this pass — no real caller needs it yet.
- **Diamond dependencies and shared sub-material double-counting.** Two
  different inputs of the same recipe that both bottom out needing the
  same raw material (rare in the current recipe table, but structurally
  possible) are reported as two separate needs today, not merged/summed
  into one. Harmless for "what's blocking me" framing (a player reads
  "need more X" fine even if named twice); would need real deduplication
  for a caller that wants exact aggregate totals.
- **Structure/skill needs for an item ALREADY in the recursion path.**
  `MAX_DEPTH` guards against unbounded recursion but does not deduplicate
  repeated needs for the same item reached via two different branches —
  acceptable today (no diamond-shaped chains exist in the real recipe
  table yet), revisit if one gets added.
- **Should `NeedResolver` read a live `EarthChunkManager.has_structure_near`
  directly instead of taking a `nearby_structures` Dictionary?** Kept as an
  injected Dictionary deliberately — `NeedResolver` stays engine-free and
  callable for settlement-scale reasoning (a settlement's OWN built
  structures, not "near the player") without threading a live
  `EarthChunkManager` reference through a pure module. Each caller builds
  its own `nearby_structures` Dictionary the way that fits its own
  context.

## Status

✅ **Recipe gating fields** — `CraftingRecipeBook.recipe_required_skill`/
`recipe_requires_structure`, purely additive (regression-tested), plus
`recipe_for_output`'s reverse lookup. `sagewerk` carries a real
`required_skill` (Carpentry, matching `CARPENTRY_LEVEL_FOR_SAWING`);
`iron_ingot`/`copper_ingot` carry `requires_structure: "heat_source"`
(behavior-preserving refactor of the old hardcoded smelting gate);
`log_to_balken`/`log_to_planke` carry `requires_structure: "sagewerk"`.

✅ **Player.craft's generalized gate** — the old hardcoded
`is_smelting_recipe`/`_has_heat_source` special case is gone, replaced by
`_meets_requires_structure`/`_meets_required_skill`, each reading the
recipe's own declared fields generically. Regression-tested (smelting
still heat-gates exactly as before, campfire-or-furnace) AND
newly-real (the Sägewerk's Carpentry gate and its `requires_structure:
"sagewerk"` gate both now actually refuse a craft, not just exist as
unread data).

✅ **NeedResolver** — `src/gameplay/need_resolver.gd`, pure, recursive,
cycle-guarded (`MAX_DEPTH`, pinned by test). Covers direct stock
satisfaction, one-hop missing structure, one-hop missing skill, multi-hop
missing sub-material, a raw/gatherable item with no recipe, and the
cycle-guard itself against a fabricated cyclic recipe graph.

✅ **Quest.deeper_need_for** — additive, does not change
`production_shortfall_quests_for`'s own signature/behavior/call site.

🚧 **Sägewerk production stays bespoke (deliberate narrowing)** —
`SagewerkProduction.advance` is NOT rerouted through `CraftingRecipeBook`/
`Player.craft` this pass; `log_to_balken`/`log_to_planke` exist only as
data for `NeedResolver` to reason over. See this doc's own "Sägewerk
production: a deliberate, named narrowing" section above for the full
reasoning. Revisit only if a real functional need (not just architectural
tidiness) emerges for routing the Sägewerk's own production through the
recipe book.

⬜ **No live caller yet reads `NeedResolver`/`Quest.deeper_need_for` from
gameplay.** Both are real, tested, callable capabilities — but
`timber_construction.md`'s own settlement construction ledger (the
intended real consumer for the Sägewerk dependency-chain case) is itself
still unbuilt (see that doc's own Status section), so nothing in live
gameplay currently calls either function yet. This mirrors that doc's own
honest framing: the mechanism is real, its first live caller is not.

⬜ **Quantity scaling and diamond-dependency deduplication** — see Open
questions above; not needed by any real caller yet, deliberately left
unresolved.
