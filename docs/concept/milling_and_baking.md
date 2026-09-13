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

### Hauling between the links: the existing hauler, a consumer as its destination

`LogisticsMarker`/`LogisticsBehavior` move goods *out of* a source
structure *into* a destination structure — and, it turned out, the marker
was already generic in both ids (`source_structure_id`, `storage_structure_
id`, `preferred_storage_position`); only its *spawner* was hard-wired to
"destination = storage". So the chain needed no change to the walker at
all, only a second pairing table: `EarthChunkManager.CHAIN_LOGISTICS_LEGS`
— farm → mill (wheat), storage → mill (wheat), mill → bakery (flour),
bakery → storage (bread) — reconciled exactly the way the Sägewerk's and
Farm's Storage pairing already is (one hauler per item per real
destination within the same pairing radius, re-decided on every relevant
tile change, on load and on unload), kept in its own
`_chain_logistics_workers` dict so a Farm's Mill legs and its Storage legs
never prune each other. The storage → mill leg is what keeps wheat from
stranding: the pre-existing farm → storage hauler keeps running, the two
haulers on one Farm simply race for a pickup and the loser aborts, and
whatever reaches the Storage is carried on to the Mill from there.

**Who works the Mill and the Bakery.** The Sägewerk's shaping runs off its
Lumberjack's *private* log stock, credited only by that Lumberjack's own
fell-and-carry loop — nothing external can ever feed it. A Mill has to be
fed by a hauler, so its worker (`StructureConversionMarker` → `MillMarker`
"Miller" / `BakeryMarker` "Baker", one per tile, spawned/despawned/
reloaded like the Lumberjack and Farmer) reads its input from the
building's *real* `StructureStock` and credits its product back to the
same stock, where the next hauler picks it up. Production is
`StockConversionProduction.advance()` every frame the marker exists; the
marker's presence itself is "staffed", the Lumberjack's own rule.

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
nothing — the whole chain's inputs are produced, not gathered. One thing
did need to change beside it: `ConstructionPriority.missing_structure_id`
returns the *first* structure need of the walk, which for a chain is the
**shallowest** link (the bakery) — this doc's own first draft assumed the
opposite. A settlement raising a chain must start from its root, so
`ConstructionPriority.deepest_missing_structure_id` (the walk's *last*
structure need — pre-order, so the deepest along the chain, pinned against
the real recipe book) exists alongside it, and `SettlementBuildDecision`
uses that one; `missing_structure_id` keeps its shallowest answer for the
double-fix cancellation re-check, where "what blocks this recipe directly"
is the right question.

### Food that counts: `SettlementFood` sees the village's own shelves

`SettlementFood` summed two containers — the persisted emergence
`Market` and the live `VillageMarket` — filtered to `kind == "food"`.
Bread lives in a third: a structure's own `StructureStock` (the Bakery's,
then a Storage's once hauled). So `SettlementFood.food_stock`/`carrying_
capacity` take an optional list of the settlement chunk's own structure
stocks (`EarthChunkManager._settlement_structure_stocks`, every stock
keyed to a tile in that chunk), and every capacity read in the world —
`step_settlements`, `_settlement_status_for`, `legitimacy_for_settlement`
— goes through one `_settlement_capacity` helper that passes them.
Nothing about the classification itself changes: `SettlementState.
status_for` reads the same `carrying_capacity = food_stock /
FOOD_PER_HOUSEHOLD` and the same `STABLE_BAND`.

**And villagers eat it — from all of the village's stores.** Individual
hunger bought meals only from the `VillageMarket` (`NpcEconomy._try_eat` →
`buy_meal`), the villagers' own day's gathering, which no Storage, Bakery
or merchant ever stocks. So a hungry villager who finds the stall bare now
"walks to the stores": `EarthChunkManager.buy_village_meal_near` sells one
whole unit of any real food first from the settlement's own persisted
`Market` (where the merchant stocks and the granary/trade fill — the food
`SettlementState` had always counted as the village's own, and that nobody
had ever eaten), then off the nearest Bakery/Storage shelf within the
villager's own village (`STRUCTURE_MEAL_RADIUS_TILES`, one chunk), at
`VillageMarket`'s own flat meal price, all-or-nothing exactly like
`buy_meal`; and the purse-funded subsistence wage counts those stores as
somewhere a wage buys a meal (`has_village_meal_near`), so nobody starves
next to a stocked stall or a full bakehouse. Food is therefore consumed as
well as counted — the stores go down as the village eats, and the need can
genuinely return. The one thing that had kept the merchant's meat
permanent, the shop refilling any sold-out item, is gone for food
([economy.md](economy.md): food is seeded once as the merchant's opening
inventory; tools and blueprints still restock).

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
   built, three structure needs; `deepest_missing_structure_id` names the
   one to build first — the **root** (`farm`), because a Bakery with no
   flour coming is a dead building (see "The resolver's view" for why the
   older picker would have said the opposite).
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

**Where the wood and stone come from.** Research before building this
found that nothing in live play ever puts wood, stone or plant fibre into
a settlement's persisted Market — the Shop stocks trade goods, the granary
food, regional trade whatever is short elsewhere — so every autonomous
construction decision could only ever have ended in `SHORTFALL`, and the
chain above would have been dead on arrival. `SettlementGathering` closes
that: a settlement's spare hands (the same `SettlementSpareCapacity` the
build decision already uses — households beyond farmer/hunter/fisher)
cut timber, pick fieldstone and pull fibre into the Market every
assessment, at pinned per-household-per-day rates (wood the most
plentiful, stone the slowest), with a sub-unit carry so short steps lose
nothing. Grounded, not invented: a village has always cut its own timber
and picked its own stone; it is the unglamorous work of whoever is not
busy surviving. A settlement short of material for the *next* link still
reports `SHORTFALL` and simply waits for its own gathering to catch up.

**Cadence.** The decision used to run only at chunk load, and labor only
caught up on a reload after an unload — a village would only ever have
built while the player was away. Now `step_settlements` (every
`SETTLEMENT_STEP_INTERVAL`, 30 s) also gathers material for every
settlement and, for a *loaded* one, re-takes the build decision and
advances its projects' labor by the interval — the same closed-form
`ConstructionCatchup` math the reload path applies, so how fast a village
builds never depends on whether anyone is watching. Illustrative pacing at
today's constants (a one-hour day, 8 builder-hours per spare household per
day, 1.5 labor-hours per unit of material): a village with three spare
households has a Farm's material on hand in ~15 minutes and the Farm
standing ~40 minutes later; the Mill and Bakery follow at the same pace.

**A quirk this pass first named, then fixed on request**: a visited
merchant's Shop stocked 20 cooked meat into the emergence Market, counted
as settlement food — five households of capacity — that no villager ever
ate and the shop refilled whenever it hit zero, so a five-villager village
with a merchant could never classify `DECLINING` and never want a farm.
Villagers now eat those stores (see "Food that counts") and the shop seeds
food only once, so a merchant village eats through its meat and comes to
need a Farm like any other — pinned end to end in `test_earth_chunk_
manager_bread_chain.gd` (the meat is eaten portion by portion, the shop
does not conjure it back, the village turns `DECLINING`, the decision
starts a Farm).

### Placement

The existing pipeline sited every autonomous project at local cell
`Vector2i.ZERO` — bookkeeping, honestly named as such, never real siting
— and `build_at_global` overwrites whatever stands at a cell, so three
chain buildings would have stamped over each other in the chunk's corner.
`EarthChunkManager._settlement_build_origin_for` gives a project a real
site when it starts: the first local cell, spiralling outward from the
chunk's own centre (where `SettlementGenerator` lays its ring of houses),
that is real buildable terrain *and unmodified, together with all eight of
its neighbours* — the same `is_buildable_terrain_at` rule every house
obeys (no water, no forest, no standing tree), plus a lane of clear ground
around every structure so a Farm's fence always has somewhere to stand and
a hauler is never boxed in (the first version required only the centre
cell to be buildable, and promptly sited a Farm in a one-cell hole in a
forest with nowhere for its fence — caught by the end-to-end test).
Deterministic, and deliberately not skipping a live project's own site: a
repeated decision lands on the same still-empty cell, finds its own earlier
project there, and never queues a second copy; a placed structure modifies
its cell, so the next link goes to the next clear site. The site is
re-checked at completion (`_place_completed_construction_project`) and
the structure moved to the next clear cell if something was built there
meanwhile. A settlement whose chunk offers nowhere decides nothing and
waits.

A completed Farm is placed **fenced**: a `wooden_fence` on its first clear
cardinal neighbour, at no further charge — the Farm recipe's own stated
cost already *is* the fence ("wood (6) for fence rails/posts and
plant_fibre (4) lashing them", [npc_farm_production.md](npc_farm_production.md)),
and the Farm's own gate rule admits no Farmer until one stands nearby.

## Interaction with other docs

- **[npc_farm_production.md](npc_farm_production.md)** — the Farm and its
  Farmer are reused unmodified; this doc resolves that doc's "Milling and
  baking" and "Settlement-autonomous build a farm decision" open questions.
  Its "Capacity and a second Farmer" question stays open: this doc's own
  first draft claimed a still-`DECLINING` village would simply raise a
  second Farm, but the resolver reports *missing* structures, not
  insufficient throughput — once all three links stand, a bread shortfall
  is no longer actionable by construction (pinned by test), and the
  village's only lever is time. Scaling the chain to the need is Open
  Questions below.
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

Built TDD red-first throughout on `feat/bread-chain` (2026-09-13), every
module with its own fast unit file; the full slow `test_earth_chunk_
manager.gd`/`test_player.gd` files were deliberately not re-run per a
"skip tests" instruction to not block on multi-minute suites — the
directly affected neighbouring suites were.

- ✅ `flour` (material) / `bread` (food), `mill` / `bakery` placeables
  (`ItemCatalog`, 90/90; procedural art fallbacks — see Open questions).
- ✅ `StockConversionProduction` + `MillProduction`/`BakeryProduction`
  (8/8, 3/3, 2/2, constants pinned).
- ✅ `mill`/`bakery` recipes; `grow_wheat`/`mill_flour`/`bake_bread` as
  resolver data; the `automated` recipe flag refused by `can_craft`/`craft`
  (`test_crafting_recipe_book.gd` 66/66; [production_chains.md](production_chains.md)
  aligned). City Hall demands surface the three links with no new code
  (`test_settlement_demand.gd` 8/8).
- ✅ `ConstructionPriority.deepest_missing_structure_id` and
  `SettlementBuildDecision` using it — farm, then mill, then bakery (23/23,
  15/15).
- ✅ `MillMarker`/`BakeryMarker` via `StructureConversionMarker`,
  `EarthChunkManager._conversion_workers` (build/destroy/load/unload; 9/9).
- ✅ `CHAIN_LOGISTICS_LEGS` haulers between the links, one real end-to-end
  Farm → Mill haul (12/12).
- ✅ `SettlementFood` counts structure-held food; `food_shortfall_for`
  (28/28). Villagers eat from the bakehouse (`test_npc_economy.gd` 43/43).
- ✅ `SettlementGathering` (6/6). Real siting, fenced Farm placement, live
  cadence — `test_earth_chunk_manager_bread_chain.gd` 9/9 end to end
  against Berlin's real terrain: a hungry village starts a Farm at a real
  clear cell, completes and fences it, a Farmer moves in, the chain climbs
  farm → mill → bakery at distinct cells and stops, material and labor
  accrue in real time while loaded, bread on a shelf lifts the village out
  of `DECLINING`.
- ✅ Three pre-existing bugs found by the research and fixed on the way:
  the Sägewerk's Lumberjack was never wired to the world (every beam/plank
  ever shaped in live play was silently discarded); `Market` had no
  `remove_stock` for `SettlementConstruction` to draw materials through (a
  crash the first time any village could afford anything); a Farm staffed
  by a newly built fence never got its Storage haulers re-paired.
- ⬜ Not exercised live in this pass: a real village visited in play
  walking the whole chain end to end on the clock (the integration test
  drives the same functions the game's own `step_settlements` calls).

## Open questions

- **Scaling the chain to the need.** One Farm of three plots feeds only so
  many; a village still `DECLINING` with every link standing has no
  construction it can take, because the resolver reports missing
  producers, not insufficient throughput. A real "throughput shortfall"
  (loaves needed per day versus what the chain can bake) would let the
  decision raise a second Farm — this is also
  [npc_farm_production.md](npc_farm_production.md)'s own "Capacity and a
  second Farmer" question.
- **Three food containers, one eater.** A villager now eats from the stall,
  the persisted Market and the shelves alike, but nothing ever moves food
  between them (baked bread never reaches the `VillageMarket` a player
  sells food into), and the player's shop still prices only the Market —
  unifying the three containers is real, separate work.
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
