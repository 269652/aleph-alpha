# Milling and Baking: wheat becomes food, and a settlement learns it needs a Farm

This doc closes the two follow-ups [npc_farm_production.md](npc_farm_production.md)
named for itself and deliberately did not build: **milling and baking**
(wheat → flour → bread, "the obvious next production-chain link"), and the
**settlement-autonomous "build a farm" decision** (a settlement noticing it
is short of food and raising the buildings that fix it, on its own). It was
requested directly: *"The NPCs also need to produce food; so building a
Wheat Farm should become an emergent need pretty soon"* — and, asked which
way to close the loop, the full chain was chosen over a "wheat counts as
food" shortcut: a Mill and a Bakery first, then the need that pulls all
three buildings into existence.

Nothing here is a new kind of thing. A Mill and a Bakery are the Sägewerk's
own "a building turns one stock into another, continuously, off its own
real stock" shape ([timber_construction.md](timber_construction.md)'s
`SagewerkProduction`) applied to grain; the hauling between them is the
existing `LogisticsMarker`; the food they end in is counted by the existing
`SettlementFood`; and the decision that builds them is the existing
`SettlementBuildDecision` → `ConstructionPriority`/`NeedResolver` pipeline
([production_chains.md](production_chains.md)), which has been real, tested,
and wired at every chunk load since it shipped — and has never once fired
in live play, for reasons this doc names and removes.

## Design pillars

1. **A chain of real buildings, not a conversion constant.** Wheat is not
   silently edible. Grain is milled at a Mill into flour, flour is baked at
   a Bakery into bread, and only bread is food. Each step is a structure a
   settlement (or the player) must actually raise — that is what makes
   "the village needs a farm" an *emergent* need rather than a flag: the
   need for bread reasons backwards through flour and wheat to three real,
   missing buildings.
2. **One production model, reused.** `MillProduction` and
   `BakeryProduction` are `SagewerkProduction`'s own continuous, stock-fed
   shape — a building advances its own conversion off its own real
   `StructureStock` every step it is loaded, independent of any worker's
   phase — not a discrete per-craft `Market.produce` rewrite (the same
   "deliberate, named narrowing" [production_chains.md](production_chains.md)
   already made for the Sägewerk).
3. **The dependency chain is data the resolver already reads.** Every step
   is a real `CraftingRecipeBook` recipe with `requires_structure`, so
   `NeedResolver` walks bread → bakery → flour → mill → wheat → farm with
   zero chain-specific code. The one new general mechanism is the honest
   fix for the exploit that stopped `npc_farm_production.md` from doing
   this: an **automated** recipe (`"automated": true`) is one a structure's
   own production performs and a player can never craft by hand — so
   `grow_wheat` can exist as a resolver node without letting anyone
   hand-craft free wheat next to a Farm.
4. **Food is counted where it actually ends up.** Bread piling up in a
   Bakery and hauled to a Storage is real food the settlement owns.
   `SettlementFood`, the one existing settlement-scale "is food short"
   signal, learns to see it — no second food ledger.
5. **A settlement raises what it lacks, in the order the chain dictates,
   and stops.** The food need is a real shortfall fed into the existing
   build decision; the resolver names the deepest missing producer; the
   settlement builds one at a time across chunk loads (farm, then mill,
   then bakery); once bread flows and the settlement is no longer
   `DECLINING`, the need is gone and nothing else is queued. No cap
   constant, no "one farm per village" rule — the signal itself clears.
6. **Tuned values are tested functions, not comments.** Every ratio, rate
   and cost below is pinned by a calibration test at implementation time.

## Real-world grounding

- **Grain is not food until it is milled and baked.** Wheat kernels are
  indigestible raw; the two oldest food technologies after fire are the
  quern (grinding grain to flour) and the oven. A medieval village's mill
  and bakehouse were its two most important non-farm buildings — often the
  lord's monopoly precisely because every household depended on them.
- **Wholemeal, not white.** A village mill stone-grinds the whole kernel
  and nothing is sifted away; the extraction rate is effectively 1:1 by
  count in this game's own coarse units (`WHEAT_PER_FLOUR`), the way a
  `log` shapes into a whole `plank`. Bread likewise takes one flour per
  loaf (`FLOUR_PER_BREAD`) — the ratios are deliberately legible; the
  chain's cost is the three buildings and the time, not a hidden loss rate.
- **A bakehouse is masonry; a mill is timber and stone.** A bread oven is a
  stone/clay dome that holds heat; a post mill is a timber house on a
  stone base carrying the millstones. So the Bakery costs mostly stone and
  the Mill mostly wood, each with the other as a minority — the same
  "recipe cost reflects what the building is made of" reasoning the Farm's
  own fence-and-tilled-ground cost already follows.
- **Milling is fast, baking is a batch.** A quern-house grinds grain
  steadily as it arrives; an oven is fired and a batch baked, then the next.
  `MILL_SECONDS_PER_FLOUR` is therefore shorter than
  `BAKE_SECONDS_PER_BREAD` — illustrative pacing, pinned by test.
- **Why the whole chain, not "wheat is food".** Porridge is real, but a
  village that grows wheat and never builds a mill or an oven is not a
  village that has solved food; it is one that has solved a number. The
  buildings are the emergence.

## Mechanism

### Two new items

- `flour` — `kind = "material"`, the intermediate, exactly like `plank`/
  `beam` sit between `log` and a wall.
- `bread` — `kind = "food"`, a real meal: it joins carrot/potato/cooked meat
  in everything that already reads `ItemCatalog.kind_of(id) == "food"`
  (`SettlementFood`/`SettlementState`'s food stock, the village market's
  meals, the player's own eating) with no special-casing.

Both resolve through the item-art registry's existing procedural fallback
for now; real illustrated icons are a named follow-up (Status below), not
a blocker — every item in the first-100 list started the same way.

### Two new structures

- `mill` — a placeable (`ItemCatalog` `kind = "placeable"`, the family
  `farm`/`sagewerk`/`storage` belong to), built the same tile-based way via
  `build_at_global`. Recipe: `wood` ×10 + `stone` ×4. No skill gate.
- `bakery` — the same family. Recipe: `stone` ×8 + `wood` ×6. No skill
  gate.

**Why no skill gate, stated plainly.** `timber_construction.md` already
records the real consequence of a skill-gated recipe for autonomous
construction: `SettlementBuildDecision` passes an empty `allocated_nodes`
because no settlement-level skill/labor source exists yet, so *"'start new
work' cannot autonomously succeed in live play"* for anything skill-gated
— the Sägewerk's own Carpentry gate is why a settlement can never raise a
second Sägewerk today. A food chain whose whole point is that a settlement
raises it on its own cannot inherit that gap. So the Mill and Bakery are
gated on materials only, like `storage` and `farm` before them, with the
same reachability reasoning those two already give. Giving settlements a
real skill source, and then gating masonry, is future work for the skill
web, not something to fake here.

### Production: `MillProduction` and `BakeryProduction`

Each is `SagewerkProduction`'s shape, one per structure tile, advanced
every step the structure's chunk is loaded:

- **Mill**: while its own `StructureStock` holds ≥ `WHEAT_PER_FLOUR` wheat,
  it converts at `MILL_SECONDS_PER_FLOUR` per unit — wheat withdrawn, flour
  credited to the same stock.
- **Bakery**: while its stock holds ≥ `FLOUR_PER_BREAD` flour, it converts
  at `BAKE_SECONDS_PER_BREAD` per loaf — flour withdrawn, bread credited.

No fuel is modeled for the oven — the Sägewerk's saw consumes nothing
either; a real wood-fuel cost per batch is an Open Question below, not a
silent omission. Production is independent of any worker's own phase
(pillar 2): a Mill grinds whatever wheat has reached it whether or not a
hauler is mid-trip.

### Hauling between the links: Logistics, generalized by one field

`LogisticsMarker`/`LogisticsBehavior` today move finished goods *out of* a
producer *into* the nearest Storage (`source_structure_id`, `item_id`).
The chain needs the same walker to also feed a consumer: wheat from a Farm
(or a Storage holding wheat) into a Mill, flour from a Mill into a Bakery,
bread from a Bakery into Storage. That is one additional notion — a
**destination structure id** — on the existing walker, not a new one: a
logistics leg is (source structure, item, destination structure), where
today's behaviour is the special case "destination = storage". Legs are
reconciled the same way the Sägewerk's and Farm's Storage pairing already
is (`_sync_logistics_workers`, on build/destroy/load), one walker per real
(source, destination) pair within the same pairing radius. See the
implementation notes in Status for exactly how far the existing code
reached and what was added.

### The resolver's view: three recipes, one new flag

`CraftingRecipeBook` gains three recipes purely as chain data (the same
role `log_to_balken`/`log_to_planke` already play for the Sägewerk):

| recipe id      | inputs                     | output   | requires_structure | automated |
|----------------|----------------------------|----------|--------------------|-----------|
| `grow_wheat`   | —                          | `wheat`  | `farm`             | **yes**   |
| `mill_flour`   | `wheat` × WHEAT_PER_FLOUR   | `flour`  | `mill`             | no        |
| `bake_bread`   | `flour` × FLOUR_PER_BREAD   | `bread`  | `bakery`           | no        |

Their input counts are pinned by test to the production constants so the
two data sources can never drift, exactly as the Sägewerk's are.

`"automated": true` is the new, general recipe field: a recipe a
structure's own production performs and `Player.craft` refuses outright
(alongside its existing `requires_structure`/`required_skill` gates). It
exists for exactly the exploit `npc_farm_production.md` refused to paper
over — `grow_wheat` has no input, because `FarmPlot` consumes none, so
without this flag a player standing near any Farm could craft free wheat
forever. `mill_flour` and `bake_bread` are *not* automated: a player who
carries real wheat to a real Mill may grind it by hand, and real flour to
a real Bakery may bake it — a real input, no exploit, and a genuine
player use for the two buildings beyond watching them work.

`NeedResolver` needs no change: asked for bread with no bakery, mill or
farm nearby, it reports a structure need for each and a material need for
nothing — the whole chain's inputs are produced, not gathered.

### Food that counts: `SettlementFood` sees Storage

`SettlementFood` today sums two containers — the persisted emergence
`Market` and the live `VillageMarket` — filtered to `kind == "food"`.
Bread lives in a third: a structure's own `StructureStock` (the Bakery's,
then a Storage's once hauled). So `SettlementFood` gains the sum of
`kind == "food"` stock across the settlement chunk's own Storage
structures (and any producer's own stock — a loaf still in the Bakery is
food the village owns). Nothing about the classification itself changes:
`SettlementState.status_for` reads the same `carrying_capacity =
food_stock / FOOD_PER_HOUSEHOLD` and the same `STABLE_BAND`.

### The emergent need: a food shortfall the build decision can act on

`_apply_settlement_build_decision` runs on every real chunk load and hands
`SettlementBuildDecision.decide_and_advance` the settlement's shortfalls.
Today those come only from `production_shortfall_quests_for_settlement` —
missing *inputs* to a villager's own occupation recipe — and by design
every such recipe is ungated, so the decision has never resolved to
`BUILD_PRODUCER_FIRST` in live play. This doc adds the second, missing
source of shortfall: **food**.

`SettlementFood.food_shortfall_for(...)` (a pure function over the same
inputs `status_for` already takes) returns `{"item_id": "bread", "need":
N}` when the settlement classifies `DECLINING`, with N the loaves that
would lift it back into the stable band, and nothing otherwise. That
entry joins the shortfall list handed to `decide_and_advance` unchanged.
From there the existing pipeline does the rest:

1. `recipe_for_output("bread")` → `bake_bread`; `ConstructionPriority.
   decide` → `NeedResolver` walks it and finds, with none of the three
   built, three structure needs; `missing_structure_id` names the one to
   build first — the **deepest** (`farm`), because a Bakery with no flour
   coming is a dead building; the walk's own leaf-first order already
   yields this, pinned by test rather than assumed.
2. `SettlementConstruction.advance("farm", ...)` starts a real
   `ConstructionProject` if the settlement's own stock covers the cost
   (`ConstructionStartHysteresis`), labor catches up across chunk loads,
   `_place_completed_construction_project` places it — **fenced**: a
   settlement-raised Farm places its own `wooden_fence` on an adjacent
   buildable cell as part of completing the project (the Farm's own gate
   rule requires one before a Farmer moves in; a village raising a plot
   fences it, the same way a village house comes with its roof), the
   fence's cost drawn with the farm's.
3. The next chunk load re-evaluates: the Farm is present, wheat is not yet
   bread, the settlement is still `DECLINING` → the resolver now names the
   `mill`; then the `bakery`. Three loads, three buildings, in the only
   order that works.
4. Bread flows: Farm → (logistics) → Mill → (logistics) → Bakery →
   (logistics) → Storage. `SettlementFood` counts it; the settlement leaves
   `DECLINING`; `food_shortfall_for` returns nothing; the decision has
   nothing to act on. No cap needed (pillar 5).

Where a settlement lacks the wood and stone for the next building, the
decision reports `SHORTFALL` exactly as it would for any other project,
and the existing production-shortfall quest path is what surfaces "this
village wants to raise a farm and is short of wood" to the player — an
emergent request, not a scripted one. What a procedurally generated
village actually has in its own Market in live play is recorded honestly
in Status below.

### Placement

A settlement-raised structure goes where the existing completion path
puts it, checked against the same real terrain rule every house already
obeys (`is_buildable_terrain_at`: not water, not forest, no standing tree)
and against existing structures — see Status for the exact placement rule
the implementation reached.

## Interaction with other docs

- **[npc_farm_production.md](npc_farm_production.md)** — the Farm and its
  Farmer are reused unmodified; this doc resolves that doc's "Milling and
  baking", "Settlement-autonomous build a farm decision" and, in passing,
  its "Capacity and a second Farmer" open questions (a still-`DECLINING`
  settlement with one Farm of three plots simply raises another Farm next,
  since the deepest unmet need is still wheat volume — the same signal, no
  second-farm rule).
- **[timber_construction.md](timber_construction.md)** — the direct
  template for production (`SagewerkProduction`), stock
  (`StructureStock`), hauling (`LogisticsMarker`) and the construction
  ledger; the only generalization made is the logistics destination field.
- **[production_chains.md](production_chains.md)** — the recipe fields and
  `NeedResolver` are used as specified; `"automated"` is the one addition,
  and belongs in that doc's own field list as the third optional key.
- **[npc.md](npc.md)** — villagers' own hunger and meal-buying
  (`village_market.gd`) is untouched here; bread reaching the village
  market as a purchasable meal is a named follow-up in Open Questions, not
  assumed.
- **[quests.md](quests.md)** — a `SHORTFALL` on the chain surfaces through
  the existing shortfall-quest path; no new quest type.

## Worked example

A grassland village of five: a hunter, a nurse, a farmer (the occupation —
a forager, not a Farm), two blacksmiths. Their market holds a little meat
and fruit, never enough for five households: `DECLINING`. On the next
chunk load `food_shortfall_for` reports bread wanted; the resolver, seeing
no bakery, no mill, no farm, names the Farm. The village has wood from its
own stock; a Farm project starts, and on a later visit a fenced plot stands
at the village edge with a Farmer already tilling it. Wheat piles up in
the Farm. Still `DECLINING` — wheat is not bread — the next load names the
Mill; a hauler begins carrying wheat over the moment it stands. Flour
accumulates; the Bakery follows; bread is hauled to the Storage. The
village's carrying capacity crosses back into the stable band, and the
decision, asked again on the next load, finds nothing to build.

## Status

⬜ Everything above is specified, not yet built. Implementation notes and
the honest account of what each piece actually reached are recorded here
as the work lands, per `docs/progress.md`'s ledger convention.

## Open questions

- **Oven fuel.** A real bakehouse burns wood per batch; modeling it means
  a second input the resolver would surface as a `wood` need — correct,
  and cheap once the destination-logistics leg exists, but deliberately
  not in the first pass so the chain's first live run has three links to
  debug, not four.
- **Bread as a purchasable meal.** `village_market.gd`'s meals come from
  the producer occupations' own live yield; Storage-held bread reaching
  that market (or hungry villagers walking to the Storage) is the natural
  next step, so a village that bakes actually eats what it bakes at the
  individual level too, not only in the settlement's aggregate signal.
- **Real art.** `mill`/`bakery` structure sprites and `flour`/`bread`
  icons resolve through procedural fallbacks; the Farm/Sägewerk/Storage
  each got a real user-supplied sheet, and these should follow.
- **Skill gates once settlements have skills.** Masonry for the oven, a
  millwright's carpentry for the Mill — real gates, once the settlement-
  level skill source `timber_construction.md` names exists.
- **Offscreen catch-up** for milling/baking inherits exactly the Farm's
  and Sägewerk's own gap: production runs only while the chunk is loaded.
