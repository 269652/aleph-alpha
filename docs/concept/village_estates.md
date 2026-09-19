# Village Estates: consumption, station, and a ladder that can be fallen down

Asked for directly: *"overhaul and vastly improve village dynamics so it
plays more like Anno 1806. Brainstorm novel mechanics and flesh out the
economy / social interactions and gated growth."*

[village_growth.md](village_growth.md) built the first half of that: a
village that lays out a charter, draws households in, raises the next rung
it owes itself, and reads back its own wellbeing. What it built is a
**ratchet**. Households only ever arrive. Needs are a *score* nobody ever
pays for. A rung is owed on headcount alone. Every villager is the same
kind of villager.

Anno's actual loop is none of those things. A residence **consumes real
goods out of a real warehouse every tick**; it **upgrades** when what it
consumes reaches a higher standard AND the public building that entitles it
stands; and it **loses people** when the goods stop coming. Supply is a
*flow*, not a stock reading, and the population is the thing the flow moves.

This doc is that loop, built on the estate order Central Europe actually
had rather than on Anno's tier names.

## The gap, stated precisely

| Anno's loop | what this village does today |
|---|---|
| a residence consumes goods every tick | nothing consumes anything; `HouseholdWellbeing` *reads* stock and never spends it |
| unsupplied needs shrink the population | `VillageImmigration` only ever adds — there is no departure path at all |
| a house upgrades on need fulfilment + a public building | `VillageGrowth` gates every rung on raw household count |
| upgrading moves labour up a tier and starves the tier below | there is one undifferentiated villager; no labour classes exist |
| a production building demands a workforce and scales with it | a rung is a building that stands; none of them is staffed or runs a chain |
| income scales with how well-supplied a household is | `VillageWages` levies a flat share of producer income only |

Six gaps, six mechanisms below. Every one of them is built over state the
substrate already keeps — `VillageMarket.stock`, `HouseholdStore`,
`BuildingCatalog`, `SeasonCycle`, `InstitutionStore` — because a second
parallel village simulation would drift from the first within a month, the
same reasoning [npc_social_life.md](npc_social_life.md) opens with.

## Design pillars

1. **A need is a flow, not a reading.** The single change everything else
   hangs off. A household's food need is satisfied by food that *leaves the
   market*, and the same unit cannot satisfy two households. A village with
   a full granary and forty households is not well fed; it is four days
   from not being fed. Reading stock can never say that. Drawing it down
   says it on its own.
2. **The ladder goes down as well as up.** A village that stops supplying
   its people loses them — first the standard they hold, then the people
   themselves. Growth that cannot be reversed is not growth, it is a
   counter.
3. **Standing is earned and entitled, never granted.** A household rises
   only where the *charter building* for the next estate actually stands. A
   husbandman needs a farm; a craftsman needs a workshop to be apprenticed
   in; a burgher needs a civic seat to hold rights from. This is the whole
   of "gated growth": the gate is a real building on real ground, not a
   number.
4. **Ascending costs the rung below.** An estate supplies exactly one class
   of labour. Raising a cottager to a husbandman *removes a pair of hands*
   and creates a farmer. A village that promotes everyone cannot staff its
   own sawmill. This is Anno's central squeeze and it is also, precisely,
   what happened to European villages that turned their cottagers into
   burghers.
5. **Nothing is invented that the world does not already produce.** Every
   basket good below is a real `ItemCatalog` id that some real mechanism in
   this game already puts into the world — food from foraging and farming,
   `wood` from the forest, `bread` from the real mill-and-bakery chain,
   `honey` from real bee colonies, `hide` from real butchery. A basket that
   named a good nothing produces would be a need no village could ever meet.
6. **The seasons are ours and Anno does not have them.** This world runs a
   real `SeasonCycle`. Firewood is not a constant line on a basket; it is
   what a village must have banked by autumn or suffer for in winter. The
   basket is a function of the date.
7. **Tuned values are tested functions.** Every threshold, rate and weight
   below is pinned by a test against the *behaviour* it produces — an
   ordering, an invariant, a break-even — never asserted as a number
   somebody liked.

## Real-world grounding

- **The estates (Stände).** A Central European village of this period was
  not a flat population. It was a **Kossät** (cottager: a cottage, a garden,
  no plough-land, sells labour by the day), a **Bauer** (husbandman: a hide
  of land, a plough, draught animals), a **Handwerker** (craftsman: a trade,
  a workshop, a guild), and a **Bürger** (burgher: civic rights, capital,
  a seat in the assembly). These are the four rungs below. They are not
  flavour: each held a *different legal standing*, did a *different kind of
  work*, and consumed a visibly different basket.
- **Ascent was gated on an institution, not on savings.** You did not become
  a craftsman by getting rich; you became one by being apprenticed into a
  trade that existed where you lived, and a burgher by a charter granted
  from a civic seat. Pillar 3 is that, mechanised.
- **Promotion drained the fields.** Every village that turned its cottagers into
  townsmen had to import field labour or let land go out of cultivation.
  Pillar 4 is that, mechanised.
- **Firewood was the winter budget.** A pre-industrial household's single
  largest seasonal commitment was fuel. Villages that had not laid in wood
  by autumn burned furniture, then left.
- **Guilds were insurance as much as cartel.** A Zunft held a relief chest
  (Zunftkasse) that paid a member's household through a bad season. The
  social layer is not decoration on the economy; historically it *was* the
  buffer that kept the economy from resolving to famine.

## Mechanism 1 — The estates and their baskets

`VillageEstates`, a pure static table, the same shape
`OccupationProduction`/`SettlementTier` already use.

| estate | house tier | labour class | what it is |
|---|---|---|---|
| `kossaet` | `house_small` | `hand` | cottager — a roof, a garden, day labour |
| `bauer` | `house_medium` | `field` | husbandman — plough-land and the food it grows |
| `handwerker` | `house_medium` | `craft` | craftsman — a trade and a workshop |
| `buerger` | `house_large` | `civic` | burgher — rights, capital, the assembly |

**Two estates share a house tier on purpose.** There are exactly three real
house sheets (`house_small`/`house_medium`/`house_large`), and inventing a
fourth would be art that does not exist. It is also true: a craftsman's
house *was* a husbandman's house with the workshop in the front room. What
visibly changes at that rung is not the roof, it is that the village's
sawmill finally has a sawyer.

**The basket** is `{good -> units per household per day}`, in two parts:

- **subsistence** — short for a sustained run and the household *descends*,
  then leaves. What you must have.
- **station** — short and the household simply does not *rise*. What you
  must have to be the thing you are claiming to be.

| estate | subsistence | station |
|---|---|---|
| `kossaet` | `kind:food` 1.0, `wood` 0.5 | `herb` 0.10 |
| `bauer` | `kind:food` 1.2, `wood` 0.6 | `bread` 0.40, `candle` 0.05 |
| `handwerker` | `kind:food` 1.2, `wood` 0.8 | `bread` 0.50, `candle` 0.10, `hide` 0.05 |
| `buerger` | `kind:food` 1.2, `wood` 1.0 | `bread` 0.60, `candle` 0.15, `beer` 0.30, `honey` 0.05 |

`kind:food` is not an item id and is deliberately spelled so it cannot
collide with one. It means *any* stocked item of `ItemCatalog` kind
`"food"` — the same filter `VillageMarket`/`SettlementFood` already apply
before a settlement counts as fed. A village eats what it has: venison,
fish, apples, bread. Drawing spends the **most plentiful** food first, so a
glut is eaten down before a scarcity, and a tie breaks on item id so the
draw is deterministic.

**The seasonal term** (pillar 6): `wood` demand is multiplied by
`WINTER_FUEL_MULTIPLIER` in winter and `SUMMER_FUEL_MULTIPLIER` in summer,
off the real `SeasonCycle.season_at`. Everything else is flat. A village
with a full woodpile in October and no sawmill discovers in January what
the woodpile was for. This is the one line in the whole design Anno cannot
have, and it is free here because the season is already real.

## Mechanism 2 — Consumption: the goods actually leave

`EstateConsumption`, pure:

- `demand_for(estate_counts, days, season)` → `{good -> units}`, the whole
  village's draw over an elapsed span. Carries fractions the same
  whole-units-out way `SettlementGathering`/`VillageImmigration` already do,
  so a short step loses nothing.
- `draw(demand, stock, food_ids)` → `{"taken": {...}, "satisfaction":
  {good -> [0,1]}, "stock": {...}}`. Removes what is there, reports the
  fraction of each good it could actually cover, and leaves the rest
  unpaid. **It does not go into debt** and it does not partially-refuse: a
  village with half the firewood burns half the firewood and is half warm.

Satisfaction is then collapsed per estate into
`subsistence_satisfaction` and `station_satisfaction` — each the *minimum*
over its own goods, not the mean. A household with all the bread in the
world and no fuel is not 80% provided for; it is cold. The minimum is what
makes a single missing good a real crisis, which is exactly how an Anno
supply chain fails.

## Mechanism 3 — Ascension and descent: the gated ladder

`EstateAscension.verdict(state)` → `ASCEND` / `HOLD` / `DESCEND`.

**ASCEND** requires all four, and the fourth is the gate:

1. subsistence satisfaction at `FULL_SATISFACTION` — you are not rising
   while you are short of what you need;
2. station satisfaction at or above `STATION_THRESHOLD`;
3. both held for `ASCENT_DWELL_DAYS` — a single good week does not make a
   burgher, and the dwell is what stops a village flapping between estates
   every step;
4. **the charter building for the next estate stands in the village.**

| ascent | charter building | why |
|---|---|---|
| `kossaet` → `bauer` | `farmhouse` | you cannot be a husbandman where there is no farm |
| `bauer` → `handwerker` | `sawmill` **or** `blacksmith` | a trade to be apprenticed into |
| `handwerker` → `buerger` | `city_hall` | civic rights are granted by a civic seat |

**DESCEND** on subsistence below `SUBSISTENCE_FLOOR` held for
`DECLINE_DWELL_DAYS`. A `kossaet` — the bottom rung — has nowhere to
descend to, so it **leaves**: `EstateAscension.verdict` returns `DESCEND`
and the caller reads `is_exodus(estate)` to know the household departs the
settlement entirely rather than changing standing.

The dwell counters are **derived from the state itself**, not persisted: a
household carries a run-length of consecutive assessments at its current
verdict, the same derived-over-persisted discipline
[village_growth.md](village_growth.md)'s pillar 5 holds.

## Mechanism 4 — The labour pyramid, and what promotion costs

`VillageLabor`, pure:

- `supply_for(estate_counts)` → `{labour_class -> heads}`, one head per
  household of the estate that supplies that class.
- `demand_for(present_building_ids)` → `{labour_class -> heads}`, from a
  per-building table:

  | building | demands |
  |---|---|
  | `farmhouse` | 2 `field` |
  | `sawmill` | 1 `hand`, 1 `craft` |
  | `warehouse` | 1 `hand` |
  | `blacksmith` | 2 `craft` |
  | `brewery` | 2 `craft` |
  | `city_hall` | 1 `civic` |

- `output_scale_for(building_id, supply, demand)` → `[0,1]`: the **minimum**
  fulfilment across the classes that building needs. A sawmill with a sawyer
  and no hand runs at half. A blacksmith with no craftsman at all does not
  run — which is why a village that has not raised a `handwerker` yet gets
  nothing out of a forge it built.

That last clause is pillar 4 in one sentence: **a building is not
production, a staffed building is.** It is also the honest answer to
[village_growth.md](village_growth.md)'s own standing gap, *"the ladder's
rungs are buildings, not yet production."*

## Mechanism 5 — The assembly: what the village votes to build

`VillageAssembly.next_building(...)` replaces a fixed ladder order with an
**estate-weighted petition**, and this is the novel mechanic the growth
system most needed.

- An unhoused household outvotes everything. Shelter first, unchanged.
- Otherwise every estate casts `count × ESTATE_VOTE_WEIGHT[estate]` votes
  for the one unbuilt building that would most directly fix **its own**
  most-unmet need — a cottager short of fuel petitions for the sawmill, a
  husbandman short of bread for the mill, a craftsman for the forge that
  employs him, a burgher for the brewery.
- Highest petition wins. Ties break on
  [village_growth.md](village_growth.md)'s own ladder order, so the result
  is deterministic and a village with no strong opinion still behaves
  exactly as it does today.
- **A building nobody could staff is never petitioned for.** The gate is
  `VillageLabor.demand_for` against the *current* supply: a village with no
  craftsmen does not vote to build a forge it would then leave cold.

A village therefore builds what its own people are short of, in the order
their standing entitles them to ask — and two villages with the same
headcount and different estate mixes build visibly different towns. That is
the thing a headcount ladder can never do.

## Mechanism 6 — The ledger: tax that scales with provision

`VillageEstates.tax_per_day(estate, station_satisfaction)` — a household
pays `BASE_TAX[estate]` scaled by how well provided it is. Anno's exact
shape, and the real one: a well-supplied household has a surplus to tax and
a destitute one does not. Paid into the **existing** `VillageWages` purse,
which already funds the subsistence wage a non-producer eats on, so the
loop closes on machinery that is already there:

> supply the baskets → households rise → a risen household pays more tax →
> the purse funds wages and the next building → the building supplies the
> baskets.

## Novel mechanics — the three this world can have and Anno cannot

1. **The winter fuel budget** (Mechanism 1's seasonal term). Already
   specified above, already free: the season is real.
2. **The guild relief chest.** `InstitutionStore` already forms real
   `guild` institutions out of repeated contracts between households. A
   guild levies a share of its members' tax into a **relief chest**, and a
   member household whose subsistence falls short draws from the chest
   *before* `EstateAscension` is allowed to return `DESCEND`. The social
   layer becomes the buffer that stops one bad season from unmaking a
   village's craftsmen — which is what a Zunftkasse was actually for, and
   it makes "who has repeatedly traded with whom" an economically
   load-bearing fact rather than a bookkeeping one.
3. **Patronage across estates.** [npc_social_life.md](npc_social_life.md)'s
   open "goods change hands" item, given a direction: in a meeting between
   a household with a surplus and one short of subsistence, the surplus
   household covers the shortfall and gains `trust` from the recipient.
   Standing then has a *social* return as well as an economic one, and a
   burgher who lets the cottagers starve is a burgher the village does not
   trust — which is the input `rumor.gd` names as its own missing
   relationship weighting.

## Status

Written before implementation, per CLAUDE.md; each entry corrected against
the code as it landed. See [progress.md](../progress.md) for the ledger.

- ✅ **Mechanism 1 — `VillageEstates`.** The four estates, the house tier
  each lives in, the one labour class each supplies, the two-part basket
  and the seasonal fuel term. Every tuned value is pinned by the ordering
  or the invariant it produces — a higher rung demands strictly more,
  claims a strictly wider station and pays strictly more tax; every basket
  good is a real `ItemCatalog` id.

  **That last invariant caught its own first violation.** The burgher
  basket named `beer`, and there was no such thing: the brewery, the
  dearest rung on [village_growth.md](village_growth.md)'s ladder, made
  nothing at all — a gap that doc carried in as many words ("the ladder's
  rungs are buildings, not yet production"). So the brewery brews:
  `brew_beer`, 3 wheat to 1 beer, structure-gated on the brewery exactly as
  bread is on the bakery, drawn on the same crop `grow_wheat` already
  grows. Beer and bread now compete for one harvest, which is the intended
  shape rather than an accident of adding a recipe — the City Hall's own
  demand walk reports it (`test_brewing.gd`, `test_settlement_demand.gd`).
- ✅ **Mechanism 2 — `EstateConsumption`.** Demand for a whole village over
  an elapsed span, and a real draw-down that removes the units from real
  stock. The draw never refuses and never goes into debt; `kind:food` is
  spent across whatever real food is on the shelf, most plentiful first,
  ties broken on item id. An estate's verdict is the MINIMUM over its
  goods, never the mean.
- ✅ **Mechanism 3 — `EstateAscension`.** The charter gate, the dwells and
  the way down. Ascent needs a whole ration, a station at or above
  `STATION_THRESHOLD`, the charter building standing, and one whole real
  season held (`SeasonCycle`'s own year over its own four seasons — derived,
  not typed). Descent needs half a season below half a ration: a village
  unmakes itself faster than it makes itself. At the bottom rung, which has
  nowhere to fall to, the household leaves.
- ✅ **Mechanism 4 — `VillageLabor`.** The pyramid, pooled per village, and
  an output scale that is the minimum across a building's own posts. The
  squeeze is test-pinned rather than asserted: promotion moves a head
  between classes and never creates one, so a village that promotes every
  cottager can no longer work its own store.

  **A real deadlock came out of this**, found by `VillageAssembly`'s tests
  rather than by taste. With the sawmill needing a `craft` head, a village
  of cottagers could never staff the one works that supplies its own
  firewood — and craftsmen only exist downstream of a mill. A saw pit is
  two men on a saw, which is what `BuildingCatalog` already said the
  building was ("a shed, a saw pit and a log deck"), so the mill is
  hand-worked and the brewery took over as the two-class rung: a brewer
  over somebody else's back.
- ✅ **Mechanism 5 — `VillageAssembly`.** The estate-weighted petition,
  and a layer over `VillageGrowth` rather than a replacement — shelter
  first, that ladder's buildings, that ladder's order as the tie-break,
  and a village whose estates or whose supply nobody has read falls
  straight through to the behaviour it had before this existed. Weight is
  a thumb on the scale and never a veto: three burghers outvote five
  neighbours, and forty cottagers outvote the burghers.

  The charter exemption in `_is_petitionable` is load-bearing and is
  stated as such in the code: a works nobody could put a body in is never
  petitioned for, but a charter IS, because a civic seat is not staffed
  before it exists — it is what creates the estate that keeps it. Without
  it every rung of this ladder deadlocks on needing the people its own
  charter would produce.

  It also closes [village_growth.md](village_growth.md)'s own named gap
  that "a growth house is always the small one": the house raised is the
  waiting household's own estate's house.
- ✅ **Mechanism 6 — the tax ledger.** `VillageWages.estate_tax_for` pays
  into the SAME purse the subsistence wage already comes out of, which is
  what closes the loop on machinery that already exists rather than opening
  a second treasury beside it. A destitute village raises nothing however
  many live in it. What is taxed is STATION satisfaction, not subsistence:
  taxing survival is how you get a village that cannot afford to be poor.
- ✅ **Standing is persisted, on the household.** `Household` carries its
  estate and both run-lengths, so `HouseholdStorePersistence` carries them
  with no new file and no second source of truth. A save written before
  estates existed reads back as a cottager rather than as an empty string
  every lookup then quietly fails on. `HouseholdStore.estate_census` is the
  one reading of a settlement's standing.
- ✅ **It is live.** `EarthChunkManager.step_settlements` runs the estate
  layer for every settlement, loaded or not: the basket is drawn, the runs
  advance, the ladder is walked, the tax is paid, and a departing household
  is recorded as a real `npc_departed` event the roster then reads. "What
  stands here" is the union of the ground, the loaded chunk's buildings and
  the persisted construction ledger — which is what lets the charter gate
  work for a village nobody is standing in.
- ✅ **The readout.** Clicking a house names the household's estate beside
  its resident and carries one line for the thing a player actually
  watches: *Rising to Husbandman*, *Falling to Husbandman*, *Leaving the
  village*, or *Settled* — green for up, amber for down. The verdict is
  re-derived at the moment it is asked for rather than stored when the
  ladder was last walked, so it can never be stale.

### Three bugs the measurements found, not the code review

Each one was invisible in the source and obvious the moment a real number
was put next to another real number. They are recorded because the
measurement is the interesting part.

1. **The basket was drawn on the wrong day, by a factor of sixty.**
   `SettlementGathering` fills the settlement's shelf counting in
   `ConstructionCatchup`'s one-hour day; the basket was spending from that
   same shelf counting in the sixty-second simulated one. Firewood IS
   `wood` — deliberately the same id a village builds with — so every
   village on the planet stripped its own timber and could never afford a
   building again. Caught by a *pre-existing* test,
   `test_earth_chunk_manager_bread_chain.gd`'s "spare hands gather building
   material between assessments". One pool, one clock: demand, draw and tax
   run on the economy's day, and only the ladder's dwells keep the
   simulated one — which is safe because satisfaction is a ratio, so the
   number the dwells count against is dimensionless.
2. **A fractional draw took a whole unit.** The emergence `Market` counts
   in whole units and its own `remove_stock` *ceils*, so a basket asking
   for a fiftieth of a log took a whole log, every assessment. The fraction
   is carried now — the same carry-the-fraction idiom
   `SettlementGathering`, `SettlementGranary` and `VillageImmigration` all
   already run on — and a village short of the good does **not** go into
   debt for the rest, which would be a famine that never ends.
3. **A starving village emptied itself in ten minutes.** With every
   short household leaving on the same assessment, a four-household village
   went to zero inside twenty assessments. One household leaves per
   assessment now: it is what actually happens, and each family that goes
   leaves more of the larder for those who stay — which is a village's real
   chance to recover. A *descent* is deliberately not capped; losing
   standing is not leaving, and a whole village can slip a rung together.

What made all three measurable was giving the estate layer its own draw
counter: the merchant, the production step and every construction project
spend from the same shelf, so a stock level cannot tell any of them apart,
which is exactly how these hid.

### Known gaps, stated rather than papered over

- 🚧 **Food is not drawn by this layer.** `SettlementGranary.catchup`
  already eats a settlement's food on the very same step, at a rate
  (`SettlementState.FOOD_PER_HOUSEHOLD`) a whole famine chain is
  calibrated against, and a LOADED village's own villagers buy meals from
  the same shelf through `NpcEconomy`. A third draw would be the same meal
  eaten twice or three times, and would have every village on the planet
  starve the day it landed. So the estate layer draws everything ABOVE
  food — fuel, bread, physic, candles, leather, beer, honey, exactly the
  goods no village has ever had to supply before — and reads food's
  satisfaction off the larder the granary leaves behind.

  The two halves therefore agree rather than compete, but they are still
  two models. Folding the per-villager meal into the household's own draw
  is the right end state and is its own piece of work: it means
  recalibrating the famine chain, which nobody asked for here.
- 🚧 **The labour pyramid is not yet wired to production.**
  `VillageLabor.output_scale_for` is real, tested and consulted by the
  assembly's staffing gate, but no production step multiplies its output by
  it yet. A standing forge with no craftsman is currently a forge that
  produces nothing *because nothing produces from it at all*, which is the
  right answer for the wrong reason.
- 🚧 **`HouseholdWellbeing` still reads stock rather than flow.** Its four
  needs (food, shelter, income, community) are unchanged and still power
  the happiness/productivity loop. The estate layer's per-good satisfaction
  is a strictly better input for the `food` and `community` terms; wiring
  it in means moving numbers a live construction loop is calibrated
  against, so it is deliberately a separate pass.
- ✅ **The guild relief chest** — `GuildRelief`, live. A settlement's own
  guild sets goods aside while the village is supplied and releases them
  when it is not, relieving BEFORE it banks (a guild that banked first
  would take from a shelf its own members were about to be found short
  of). The chest holds at most one real season's demand — the horizon the
  fuel term itself swings over — takes only `SET_ASIDE_SHARE` of the shelf
  so it never strips the village it protects, and banks nothing while its
  own people go short. Chests live on the `Institution`, so
  `InstitutionStorePersistence` carries them with no new file; a save from
  before they existed reads back with an empty one. **A village with no
  guild is untouched end to end**, test-pinned rather than assumed.

  The emergent half is the point: paired with the seasonal fuel term, a
  guild village banks firewood through the summer, when the basket asks for
  half as much and there is a real surplus, and burns it through the
  winter, when the basket asks for double. The mechanism has no idea what a
  season is.
- ⬜ **Patronage across estates.** Specified above; waits on
  [npc_social_life.md](npc_social_life.md)'s own trust dimension.
- ⬜ **Interiors and art per estate.** A household that rises moves up a
  house tier in the model; nothing yet re-houses it on the ground.

## Interaction with other docs

- [village_growth.md](village_growth.md) — the charter, the ladder, arrivals
  and the wellbeing readout this overhauls. Its ladder stays; what changes
  is what decides the order and what gates a rung.
- [economy.md](economy.md) — local prices and the shop spread the baskets
  are bought and sold at.
- [npc_social_life.md](npc_social_life.md) — meetings, rumours and trust;
  patronage is that doc's own open "goods change hands" item.
- [workforce.md](workforce.md) — hiring and instructing NPCs, the
  player-facing side of the same labour.
- [seasons.md](seasons.md) — the real `SeasonCycle` the fuel term reads.
- [village_warehouse.md](village_warehouse.md) — the roof that caps what a
  village can bank against winter.
- [01-society-and-institutions.md](../emergence/01-society-and-institutions.md)
  — the guild the relief chest is held by.
