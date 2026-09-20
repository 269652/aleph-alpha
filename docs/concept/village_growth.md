# Village Growth: A Charter, A Ladder, And A Village That Reads Back

Compiled from a direct design request: *"flesh out the Anno-like Village
System. There should be at least a Sawmill in a near forest, a plaza and a
city hall for every village all connected with roads. Then as more NPCs
move into the town the town builds more houses, production and city
buildings. It should also be possible to click on a house and view the
needs, happiness and productivity of each house / citizen."*

Four things are asked for, and this doc specifies each as a real mechanism
over state the substrate already keeps, rather than a new parallel
simulation:

1. **A charter** — what every village lays out at founding, industry
   included: the plaza and civic plot are already real
   ([building.md](building.md), [civic_construction.md](civic_construction.md));
   this doc adds the **industry plot at the nearest forest edge** and the
   **road spur** that ties it back to the street.
2. **A ladder** — as households arrive, the village owes itself the next
   rung: houses first, then civic and production buildings at real,
   test-pinned household thresholds.
3. **Arrivals** — a village that is fed and has room attracts new
   households over time. That is what makes the ladder climb; without it,
   `SettlementGenerator.POPULATION`'s fixed 5 means every village is
   frozen at founding and a "growth ladder" is a ladder nothing ever walks
   up.
4. **A readout** — clicking a house shows its household's real needs,
   happiness and productivity, every number *derived at the moment it is
   asked for* from state that already exists.

> **Overhauled by [village_estates.md](village_estates.md) (2026-09-19).**
> What this doc built is a ratchet: households only ever arrive, needs are
> a score nobody ever pays for, and a rung is owed on headcount alone. That
> doc adds the other half — baskets that are really drawn out of the
> market, a four-estate social order, ascent gated on a charter building
> actually standing, a labour pyramid where promotion costs the rung below,
> and an estate-weighted assembly that decides what gets built. Three of
> this doc's own named gaps are closed there and are marked below. Nothing
> here was deleted: the estates are a layer over this ladder, and a village
> whose estates or whose supply nobody has read still behaves exactly as
> this doc describes.

## Design pillars

1. **A village is a charter, not a roster.** Before any villager is
   placed, the village's shape is already decided by its own seed:
   `VillageLayout.skeleton` fixes the main street, the plaza, the reserved
   civic plot, the gate, the well and the stall. This doc extends the
   skeleton with one more reservation — the **industry plot** — so a
   sawmill never has to hunt for room after the fact, and so the village's
   economy has a place from the first moment rather than as an
   afterthought. Reservations cost nothing until something is actually
   raised on them.
2. **Roads are the skeleton; nothing stands off the network.** The
   invariant `VillageLayout` already enforces for houses — *a plot's
   doorstep IS a road cell* — is what this doc extends to an outlying
   plot: the industry plot's doorstep is joined to the main street by a
   real, contiguous **road spur**. A building the village cannot walk to
   is not part of the village.
3. **Population is what builds, and population is already real.** A
   settlement's household count (`EarthChunkManager.household_count_for_
   settlement`, read out of the persisted event graph and `HouseholdStore`)
   is the ONE number the ladder consults. No second population counter is
   introduced; `SettlementSpareCapacity` remains the throttle on whether
   anything can be built at all.
4. **Every rung is a real building the art already supports.** The ladder
   names only ids with a real `assets/sprites/buildings/<id>.png` sheet
   following [building.md](building.md)'s own asset contract — `sawmill`,
   `city_hall`, `warehouse`, `farmhouse`, `blacksmith`, `brewery`. Nothing
   on this ladder is a placeholder for art that does not exist.
5. **Wellbeing is derived, never stored.** A household's needs, happiness
   and productivity are computed from real state at the moment they are
   asked for — hunger from `NpcNeeds`, food from the settlement's own
   `VillageMarket`, income from the household's own `Wallet`, shelter from
   its house's own `BuildingCatalog.capacity_of`, community from the civic
   buildings actually standing. Nothing new is persisted, so the readout
   can never drift from the simulation: it *is* the simulation, read.
6. **Reading a village must cost the village nothing.** Clicking a house
   opens a panel over already-computed state. The panel is a consumer, not
   a driver — closing it changes nothing, and never having opened it
   changes nothing either.
7. **Tuned values are tested functions, not comments.** Every threshold,
   weight and rate below is pinned by a test against the behaviour it
   produces, per this project's no-manual-tuning rule.

## Real-world grounding

- **The street village (`Straßendorf`).** Central-European villages
  overwhelmingly grew as a single street with plots fronting it and a
  widened square at the middle carrying the well, the market stall and the
  civic building. `VillageLayout` already builds exactly this; the ladder
  below is what fills it in over time.
- **Industry sites at the resource, joined by a track.** A sawmill stood
  at the timber (and, historically, at the water that drove it), not on the
  village square — and a real track was worn or laid to it, because the
  logs had to come out and the sawn timber had to go back in. The spur is
  not decoration; it is what made the outlying works part of the village.
  This is the same reasoning [infrastructure.md](infrastructure.md) already
  gives for the Road tier.
- **A village builds in order of necessity.** Vernacular settlements raise
  shelter first, then the works that feed and supply them, then the civic
  and comfort buildings that only a village with a surplus can afford. The
  ladder's order is that order: houses before halls, a sawmill before a
  brewery.
- **Migration follows food and room.** Pre-industrial population movement
  tracked, very directly, where there was food to eat and a roof to be had.
  Both are real, already-measured quantities here (`SettlementFood`,
  `BuildingCatalog.capacity_of`), so "attractiveness" needs no invented
  number.
- **Needs above subsistence are what a town is for.** Anno's own need
  ladder (food and shelter first, then goods, then civic amenity) is a game
  formalisation of a real historical progression, and it is the shape the
  wellbeing model below follows.

## Mechanism 0 — A village fells the trees it needs

The plaza is the one thing a city hall cannot exist without, and it was
being refused over trees. So was nearly half of every village's housing.

A village's siting rule is now simply **not water**
(`VillageRenderer._is_buildable_local`), for its square, its house plots
and its roads alike — [building.md](building.md)'s own *"the NPCs / Player
must first fell all trees to make space for the building"*, finally applied
to the generator. Both real placement paths already clear what they write
(`_clear_vegetation_on_cells`, `_block_ground_cover_on_cells`) and
`TreeRenderer` will not put a tree back on a modified cell, so this fells
trees for real rather than leaving them standing through walls. Water is
the rule that does not move: a village does not drain a river to hold a
market.

**Measured, not assumed** (real terrain, 25×25 chunks around 51.2°N
13.6°E, 22 real villages):

| | refusing forest | clearing it |
|---|---|---|
| lay a plaza | 12 / 22 (55%) | **22 / 22 (100%)** |
| site a sawmill | 22 / 22 | 22 / 22 |
| house all five villagers | not universal | **every village** |

Forest was the blocker in every single failing case and water in none of
them. The player's own build gate is untouched, and
`SettlementGenerator` still refuses a forest-DOMINANT chunk outright, so
this clears the wooded patches inside an otherwise open chunk rather than
carving a town out of deep forest.

An earlier attempt applied the clearing rule to the SQUARE only. It took
plaza viability to 100% and cost marginal chunks their houses — once a
plaza exists, the "never straddle the square" guard skips the street's
middle span, and where the remainder was forest nothing fit. The village
was then correctly owed a house before any civic rung and the whole ladder
stalled. It was caught by this system's own tests, reverted, and re-landed
as the rule above, which applies to plots as well as the square.

## Mechanism 1 — The charter: an industry plot at the forest

`VillageLayout.skeleton` gains nothing (it must stay a pure function of the
chunk and its seed, so an older village's plaza still re-derives on
reload). Instead a new, separately-callable pure function:

```
VillageLayout.industry_plot(building_id, chunk_size, seed_value,
                            is_buildable, is_forest, is_occupied) -> Dictionary
```

- Scans for the **nearest forest cell** to the village's own street middle
  (`is_forest`, supplied by the caller — the real one is
  `EarthChunkManager`'s biome query), within `INDUSTRY_SEARCH_RADIUS_TILES`.
- Sites the building on **buildable, unoccupied, non-forest ground adjacent
  to that forest edge**, south of the street row so it never collides with
  the street's own north-side plots, and at least `INDUSTRY_MIN_DISTANCE_
  TILES` from the plaza so it reads as outlying rather than as another
  plot on the square.
- Returns `{origin, building_id, doorstep, road_spur}` where `road_spur` is
  a **contiguous L-shaped run of cells from the doorstep to the main
  street** — vertical leg then horizontal leg, every cell buildable and
  unoccupied. If the spur cannot be completed, the plot is refused
  entirely: an unreachable sawmill is not a sawmill. `{}` when no forest is
  in range, or no plot works — a village on open steppe honestly has no
  sawmill, the same way a village whose square is a lake honestly has no
  plaza.

Deterministic and pure, like everything else in that module: the same
inputs give the same plot, so a reload re-derives the site without
persisting it.

## Mechanism 2 — The ladder: what a village owes itself next

`VillageGrowth.next_building(household_ids_count, housed_count,
present_building_ids)` returns the ONE building id the village should
raise next, or `""`.

Order, highest priority first:

1. **A house for every household that has none.** `housed_count <
   household_count` ⇒ the next house id, chosen from the catalog's own
   house pool. A village shelters its people before it adorns itself.
2. **The next unbuilt rung whose household threshold is met**, in ladder
   order:

   | rung | building id | min households | what it is for |
   |---|---|---|---|
   | 1 | `sawmill` | 1 | timber — the input every later building is made of |
   | 2 | `city_hall` | 3 | the civic seat ([civic_construction.md](civic_construction.md)'s Meeting Hall; unchanged threshold) |
   | 3 | `warehouse` | 4 | a real physical home for `VillageMarket`'s already-real stock (that doc's Granary) |
   | 4 | `farmhouse` | 5 | food production — what lets population keep growing |
   | 5 | `blacksmith` | 7 | tools; the first rung needing stone in quantity |
   | 6 | `brewery` | 9 | a comfort good — the first building raised for happiness, not survival |

3. Otherwise `""` — nothing owed. A village that has everything its size
   entitles it to simply lives.

The thresholds are pinned by `test_village_growth.gd` against the ORDER
they produce (a bigger village is entitled to strictly more), not against
any one "correct" population — the same honesty
`SettlementTier.TOWN_HOUSEHOLDS`'s own doc comment already states.

Nothing here decides whether the village *can* build: that stays
`SettlementSpareCapacity` (are there hands beyond the survival
occupations?) and `SettlementConstruction.try_start` (is the material
actually in the market?), exactly as for the city hall today. The ladder
only names the target.

**The ORDER is no longer this table's** (2026-09-19). `VillageAssembly`
([village_estates.md](village_estates.md) mechanism 5) asks the village
instead: each estate petitions for the works that would supply what it is
shortest of, or for the charter that would let it rise, weighted by
standing. This table's buildings, its shelter-first rule and its order as
the tie-break all survive and are read from here rather than restated —
and a village with no estate census, or none whose supply has been
assessed, falls straight through to `next_building` exactly as before. Two
villages of the same size with different estate mixes now build visibly
different towns, which is the one thing a headcount ladder cannot do.

## Mechanism 3 — Arrivals: population that actually grows

`VillageImmigration.arrivals(settled_days, food_per_household,
free_capacity, attractiveness_bonus, carry)` — the same
carry-the-fraction, whole-units-out shape `SettlementGathering` and
`SettlementGranary` already use.

- **Gated on room**: `free_capacity <= 0` ⇒ no arrivals. A village with no
  spare roof takes nobody in, however rich. **Room means a house that
  really stands with a place free in it — never frontage to build one on**
  (corrected 2026-09-20; see "Room is made first, moved into after" below).
- **Gated on food**: `food_per_household` below `FED_THRESHOLD` ⇒ no
  arrivals. A hungry village does not attract anyone.
- **Rate**: `BASE_ARRIVALS_PER_DAY` scaled by how far above the fed
  threshold the village is, plus `attractiveness_bonus` (a real number:
  how many ladder rungs actually stand — a village with a hall and a
  brewery draws people a bare hamlet does not).
- Whole arrivals out, the fraction carried to the next step, so a short
  step loses nothing.

Each arrival is a real new household in the settlement, formed through
`HouseholdStore.form_household` and recorded with the same `npc_settled`
event `record_settlement_founded_if_new` already uses — so
`household_count_for_settlement`, `SettlementSpareCapacity`,
`SettlementTier` and the ladder all see it with no new plumbing. The
villager themself is a deterministic `NpcIdentity` at the next index, so a
reload regenerates exactly the same person.

### Room is made first, moved into after (2026-09-20)

Reported live with the town panel in shot — *"Population 21 (10 housed)"* —
*"The population is rising but no new houses are built.. NPCs should only
move in when a new unoccupied house exists for them"*.

The gate above had drifted from what this document says. `arrivals` capped
at `spare_house_capacity + 1 if the village still had FRONTAGE`, on the
reading that somewhere to build is somewhere to live. It is not: that
allowance is granted again on **every settlement step**, whether or not the
house the last one promised was ever raised. Frontage is nearly always
available, so households piled up under no roof at all — eleven of
twenty-one in the report.

Two halves, and neither works without the other:

1. **Arrivals need a real empty house.** `room = spare_house_capacity`, and
   the frontage term is gone rather than reduced, so there is no dial left
   to reopen it. Whatever the draw produced beyond the cap is lost, not
   banked, exactly as before.
2. **The ladder builds a house when no spare roof stands.** Priority 1 only
   ever fires for a household that is ALREADY here with nowhere to live, so
   with (1) alone a village whose people are all housed would owe itself
   nothing, build nothing, and never have the roof an arrival needs — it
   would stop growing for good the moment it caught up with itself. So
   `next_building` gains a lowest rung: a house for nobody in particular,
   when `spare_house_capacity <= 0`.

That rung sits **below** the civic and production rungs deliberately — a
village finishes what it already owes itself before it makes room for
strangers — and `next_building`'s new parameter defaults to 1 ("there is
already room"), so a caller that does not know its spare capacity gets
exactly the ladder it always got.

The shape this gives a growing village: build the rungs it is entitled to →
find itself with no spare roof → raise a house → somebody moves into it →
no spare roof again. Population now advances one household per house
actually built, which is the pace the report asked for.

### An arrival you can actually see (2026-09-20)

The rest of the same report: *"despite showing 20 population only 10 NPCs
are there"*.

`spawn_village` runs only from `_load_chunk`, which fixes the villager
roster at the moment the chunk loaded — while `admit_household` goes on
adding to the settlement's household count. A household that moved in while
the player stood in the village had no villager at all until they walked far
enough away to unload the chunk and came back.

`admit_household` now re-derives the village (`_respawn_village`), which is
a **whole re-derivation rather than one appended marker** on purpose: a
villager is not just a marker. They need their farmhouse's field, their
pond, their market stand, their store round, their workspot prop — all
handed out together by `spawn_village` against the roster as a whole, so a
villager bolted on afterwards would be the only one in the village without
any of it.

Re-running it is safe because everything `spawn_village` does to the WORLD
is already idempotent: every building, fence, pond and paved cell goes
through a `_if_missing` check, precisely so that a chunk reload never raises
a second village on top of the first. What gets rebuilt is the scene nodes —
exactly what a reload rebuilds.

**The cost, named rather than hidden**: a villager mid-errand restarts it.
An arrival happens once per house the village actually raises, so it is
rare, and it is the same thing the player already causes whenever they walk
far enough away for the chunk to unload.

It is a no-op unless that chunk's village is really on screen, which is what
makes it safe to call from `admit_household` at all —
`settle_up_to_founding_roster` admits households during `_load_chunk`
*before* the village is spawned.

## Mechanism 4 — Wellbeing: needs, happiness, productivity

`HouseholdWellbeing.assess(state) -> {needs, happiness, productivity}`,
pure, from real state passed in.

**Five needs**, each a satisfaction in `[0, 1]` (1 = fully met):

| need | satisfied by | real source |
|---|---|---|
| `food` | the resident's own hunger, and the settlement's food stock per household against `FOOD_STOCK_PER_HOUSEHOLD_TARGET` — the village's minimum stock per household ([village_economy_balance.md](village_economy_balance.md) mechanism 4) | `NpcNeeds.hunger`, `SettlementFood` / `VillageMarket.stock` |
| `shelter` | having a house at all, and its capacity vs. household size | `BuildingCatalog.capacity_of` |
| `income` | wallet balance against the local price of a meal — funded by the living wage every assessment ([village_economy_balance.md](village_economy_balance.md) mechanism 1) | `Household.wallet`, `VillageMarket.VILLAGE_LOCAL_FOOD_PRICE` |
| `community` | how many civic/production rungs actually stand in the village | the ladder above, `_present_structure_ids_for_settlement_chunk` |
| `work` | whether there is a post in this village for the household's own labour class | `VillageLabor.employment_for` ([village_estates.md](village_estates.md) mechanism 4) |

`work` is the fifth, added 2026-09-19 with the estate overhaul, and it
sits between shelter and income in weight: losing your trade costs a
household more than losing its savings, because the trade is what
produced the savings, and less than losing the roof. It is also the one
need whose MISSING input is not read as destitution — employment is read
off the settlement's buildings, and a caller that could not look at them
has discovered nothing rather than idleness.

**Happiness** is the weighted mean of the five, food weighted heaviest and
community lightest (`NEED_WEIGHTS`, test-pinned by the ordering they
produce: an unfed household is unhappier than one merely lacking a
brewery).

**Productivity** is happiness with hunger as a hard drag: a starving
household works badly however pretty the town is. Floors at
`MIN_PRODUCTIVITY` rather than zero — a desperate household still works,
just poorly — and reaches 1.0 only for a fed, housed, paid household in a
village with its civic buildings up.

Productivity is not a decoration: it scales the settlement's own real
construction crew (`_advance_construction_labor`'s `builder_count`), so an
unhappy village visibly builds slower. That closes the loop — buildings
raise happiness, happiness raises productivity, productivity raises the
rate at which the next building goes up — which is precisely the Anno loop
this whole doc is about.

It deliberately does **not** scale `SettlementGathering`. A hungry village
must still be able to cut the timber for the farm that would fix its
hunger; scaling the gathering is a doom loop, where the villages most in
need of building their way out are the ones least able to. It is also
simply wrong about people: hunger is what *motivates* the survival work of
cutting wood and picking fieldstone, not what slows it. What an unhappy
village does worse is RAISE what it gathered, which is where the scale
belongs. Both halves are test-pinned — an unhappy village builds slower,
and gathers exactly as fast.

## Mechanism 5 — The readout: clicking a house

A left-click on a real building cell resolves it through the already-real
`EarthChunkManager.building_at_global`, finds the household that owns it
(`HouseholdStore.owner_of` over the same `ConstructionProject.property_id`
scheme village and player houses already share), and opens a panel showing:

- the building (display name, footprint, its resident's name and
  occupation from the record's own `occupation`/`resident_seed`);
- the four needs as labelled bars;
- happiness and productivity as percentages;
- the household's real wallet balance.

Clicking empty ground, or a building no household owns, closes the panel.
The panel reads; it never writes.

## Mechanism 6 — `/village` lands you in a village that is really there

Reported in play, twice. First *"It teleports me to where no village is"*,
which earned the layout pre-check `_village_would_settle`; then, with the
console still on screen and nothing but grass and flowers around,
*"/village teleports me to an empty field..."*.

The pre-check is a **prediction**: it re-derives the roster and the layout
for a candidate chunk and asks whether every house would fit. It is careful,
it is strictly stricter than the founding itself (which settles if even one
house fits), and it is still a prediction — it never looks at what is
actually standing on the ground, because it deliberately loads nothing.

A dev command that says *"Teleported to the nearest village"* is making a
claim about the world. So it checks the world:

- **The candidate chunk is LOADED and looked at.** Only for chunks that
  already passed the settlement roll (one in
  `SETTLEMENT_CHANCE_DENOMINATOR`) *and* the layout pre-check, so the ring
  search still pays for terrain rarely rather than per chunk — and the
  player is about to go there anyway.
- **A chunk with no buildings standing in it is not a village**, whatever
  the prediction said. The search moves on to the next ring.
- **A chunk that was not loaded before is unloaded again** if its village
  turns out not to stand, so a rejected candidate leaves nothing behind.
- **The destination is a real building's doorstep**, not the planned well.
  The well comes out of `VillageLayout.skeleton`, which is a plan; a
  doorstep is a cell a building really has, so you land where you can see
  the village rather than where one was drawn.
- **"No village standing within N chunks" is an honest answer** rather than
  the absence of one: it means the search really looked and really found
  nothing standing.
- **It says what it found.** Reported a third time, with the verification
  already in — *"It still teleports me to the same empty spot"* — and a line
  that only claims success leaves a player no way to tell WHICH thing is
  wrong: the wrong chunk, no buildings recorded, or buildings recorded that
  nothing then drew. So `/village` names the chunk it landed you in and how
  many buildings are standing there (`VillageFinder.teleport_report`). Zero
  is spelled out rather than counted, because a village with nothing in it
  is the bug being hunted, not a detail.

The prediction stays in front of the load, as the cheap filter it is good
at being. What changed is that it no longer gets the last word.

## What a village is saving for

A village that owes itself a building is **saving for it**, and nothing else
in the village may spend that material first.

This is one rule with two callers, and without it the ladder cannot be
climbed at all. `SettlementGathering` is the only thing in the game that
puts wood, stone or plant fibre into a settlement's market. Two things then
take it away again before the ladder ever sees it:

- **The traveling merchant** buys `wood` (it is on his buy list), so the
  timber a village cut for its own next house left on the next cart. See
  [traveling_merchants.md](traveling_merchants.md)'s "Surplus, not stock".
- **The village's own production step** runs each household's
  occupation recipe against the market every step, and the sawyer's
  `log_to_balken` turns 3 wood into 1 beam. A village therefore sawed its
  construction timber into beams the moment it had three of them — and the
  merchant, whose cart fills with the dearest goods first, carried the
  beams off too.

Measured on a real loaded village (`tools/probe_village_growth.gd`): its
stone climbed steadily past 50 while its wood never once got past 2, its
`house_small` project sat `PLANNED` with nothing reserved for the whole
run, and a village that grew from 10 households to 31 built **not one
house** for any of them. That is the emptiness reported from play as *"the
warehouse stays empty"*, and the reason a village that grows by itself
still looked frozen.

So both callers ask the same question first: what does this village's own
next building need? That reserve is read from the same
`VillageGrowth.next_building` this ladder walks and the same
`CraftingRecipeBook` inputs the building is priced in — never a second list
of protected goods, which would drift from what a village is actually
saving for. Stock above the reserve is surplus: sell it, saw it, spend it.
Stock at or below it belongs to the building.

A village that owes itself nothing reserves nothing and behaves exactly as
it did before.

## Status

Implemented 2026-09-16, TDD red-first throughout. See
[progress.md](../progress.md) for the implementation ledger.

- ✅ **The ladder's buildings.** `sawmill`, `farmhouse`, `warehouse`,
  `blacksmith` and `brewery` are real `BuildingCatalog` whole-building
  entities beside `city_hall`, each with its real
  `assets/sprites/buildings/<id>.png` sheet already on disk, capacity 0
  (nobody lives in any of them), and ONE price shared between
  `BuildingCatalog.cost_of` and `CraftingRecipeBook` rather than two that
  could drift. Two invariants are test-pinned rather than assumed: every
  rung is priced ONLY in wood/stone/plant_fibre — the exact three materials
  `SettlementGathering` gathers, so a rung priced in anything else could
  never be raised autonomously — and costs rise strictly along ladder order
  (`sawmill` < `farmhouse` < `warehouse` < `city_hall` < `blacksmith` <
  `brewery`), each building's labour equalling its recipe-derived hours so
  a rising building's construction sprite and the ledger agree on progress.
  The three HOUSES gained recipes too: without one, a queued house finds
  nothing to wait on, derives zero labour hours, and completes instantly
  and for free on the tick it is queued. They deliberately have no
  `ItemCatalog` entry, and that absence IS the gate — `is_bench_recipe`
  only offers a recipe whose output the item catalog knows, so a house can
  never turn up at a crafting bench (`test_building_catalog.gd`,
  `test_crafting_recipe_book.gd`).
- ✅ **Mechanism 1 — the industry plot and its spur.**
  `VillageLayout.industry_plot` sites the works on buildable, unoccupied,
  non-forest ground within `INDUSTRY_FOREST_REACH_TILES` of real forest,
  at least `INDUSTRY_MIN_PLAZA_DISTANCE_TILES` from the square, nearest
  qualifying site winning. The spur is an L from the doorstep along its own
  row to a column and up that column to the main street, routed around the
  building's own footprint when the works stand south of the street; a site
  whose spur cannot be laid is refused outright. `VillageRenderer` places
  it at FOUNDING alongside the houses (a village the player discovers has
  been standing for years, and its mill is part of the fabric it was
  founded with), idempotently on both the founding and the recover path, so
  a reload never raises a second and an older village gains one on its next
  visit. Verified by a real flood fill over paved cells in both the pure
  and the renderer test: the mill must be walkable back to the street on
  road, not merely near it (`test_village_layout.gd`,
  `test_village_renderer.gd`).
  **Measured, not assumed** (`tools/probe_village_industry.gd`, 45x45
  chunks around 52.52N 13.405E): of 52 real settlement chunks, **51 (98.1%)
  qualify for a sawmill plot**. A settlement chunk is grassland-DOMINANT
  but averages 190 real forest cells, so "a sawmill in a near forest" is
  the ordinary case rather than the lucky one. The single miss did have
  forest, just none of it reachable from a legal outlying, spur-connected
  site — honestly no mill, exactly as specified.
- ✅ **Mechanism 2 — the ladder.** `VillageGrowth.next_building` names the
  one building a village owes itself; `EarthChunkManager._apply_village_
  growth_decision` queues it as a real `ConstructionProject` at a real site
  (`VillageLayout.next_street_plot` for street buildings, the industry plot
  for the mill) and pays for it out of the village market through the same
  `SettlementConstruction.try_start` the hall uses — so a growth building
  rises visibly on its plot over real labour hours. The hall keeps its own
  live decision (`CivicBuildDecision`); the growth decision returns when
  the ladder names it rather than queuing a second, differently-sited
  project. A house is credited to the first household waiting for one
  (`VillageCensus`'s sorted waiting list), everything else to the
  settlement as a commons (`test_village_growth.gd`,
  `test_village_census.gd`, `test_earth_chunk_manager_village_growth.gd`).
- ✅ **Mechanism 3 — arrivals.** `VillageImmigration.arrivals` draws
  households at a rate raised by larder surplus and by how much of the
  ladder stands; either gate alone (no room, or a larder below
  `FED_THRESHOLD`) stops it dead. Arrivals are capped at the room the
  village really has and the excess is LOST rather than banked, so a long
  offline stretch cannot dump a town onto a village — pinned by a test that
  runs ten thousand days through it and still sees exactly one arrival.
  `EarthChunkManager.admit_household` settles the next deterministic
  villager (`SettlementGenerator`'s own per-index seed continued past the
  founding roster) with the same `npc_settled` event founding uses, which
  is what makes them visible to `household_count_for_settlement`,
  `SettlementSpareCapacity`, `SettlementTier` and the ladder with no
  further plumbing. `SettlementGenerator.generate_settlement` takes the
  real population so newcomers are generated, and `VillageRenderer` matches
  a villager to their house by OWNERSHIP as well as by the founding seed —
  a newcomer's house was raised by the ladder and carries no founding seed
  at all (`test_village_immigration.gd`, `test_settlement_generator.gd`,
  `test_village_renderer.gd`).
- ✅ **Mechanism 4 — wellbeing.** `HouseholdWellbeing.assess` derives the
  four needs, happiness and productivity from live state; every weight and
  threshold is pinned by the ordering it produces (going hungry costs more
  happiness than lacking a brewery; a hungry household works below its own
  mood), never asserted as a magic number. Productivity is not decoration:
  `EarthChunkManager.settlement_productivity` scales the construction
  crew's own `builder_count`, closing the loop — buildings raise happiness,
  happiness raises productivity, productivity raises the rate at which the
  next building goes up. Applied to the crew rather than the elapsed time
  so the same scale reaches both the live step and the offline catch-up
  that shares its body. **It was first wired to the GATHERING rate
  instead, and a real pre-existing test caught it**
  (`test_earth_chunk_manager_bread_chain.gd`'s "spare hands gather building
  material between assessments"): a starving village gathering at the
  productivity floor cannot cut the timber for the farm that would fix its
  hunger, which is a doom loop, and hunger is anyway what MOTIVATES that
  survival work rather than what slows it. Gathering is now explicitly
  unscaled, pinned by its own test (`test_household_wellbeing.gd`,
  `test_earth_chunk_manager_village_growth.gd`).
- ✅ **Mechanism 5 — the readout.**
  `EarthChunkManager.household_report_at` answers for any footprint cell,
  not just the anchor, and `HousePanel` renders it: four labelled need bars
  in `NEED_IDS` order, each proportional to its need and coloured as a
  warning below half, then happiness, productivity and the household's
  purse. `World` routes a left-click in the world through it and closes it
  on a click elsewhere; the click is ignored while a modal is open and
  Escape closes the readout with the rest. Pinned as a consumer and never a
  driver: one test asserts that calling it leaves household count, market
  stock and building count untouched, another feeds the village and watches
  the reported happiness rise (`test_house_panel.gd`,
  `test_world_house_panel_wiring.gd`,
  `test_earth_chunk_manager_village_growth.gd`).

- 🚧 **Variant art for the first-tier cottage.** `BuildingCatalog.
  finished_sheet_for` prefers a per-building VARIANT sheet over the
  lifecycle sheet's idle row: a plain 5x5 grid of 25 complete cottages,
  black background, no dividers, one picked per building seed, so a street
  of cottages reads as a street of DIFFERENT cottages rather than one house
  repeated. The pipeline, the seeded pick (all 25 test-pinned as reachable)
  and the fallback chain are real and tested, and the sheet is IN
  (`assets/sprites/buildings/house_1.png`, 1402x1122, 25 cottages). All
  three house tiers share the one sheet on purpose: no house had a
  lifecycle sheet of its own at all, so declaring the art for only the
  smallest tier would leave a street half cottages and half procedural
  boxes.

  Its grid is DETECTED, not assumed (`VariantSheetGrid`): the sheet's rows
  sit ~213px apart inside a 1122px image with 45px of blank at the bottom,
  so an even fifth-of-the-height cut sliced 3% through the first boundary
  and 8.1% through the last -- shaving a chimney off one cottage and
  gluing a strip of the next one's grass along another. Cuts are found in
  the sheet's own background gutters instead; all eight now pass through
  0.0% art (`tools/probe_house_variant_sheet.gd`).
  `tools/probe_house_variants_at_game_scale.gd` renders every variant at
  the true on-screen size (32x27 as a Cottage, 48x41 as a House, 64x54 as
  a Manor) so the art can be judged at the scale it is actually played at. A rising building still draws from the
  lifecycle sheet's construction row — a variant sheet has no scaffold
  stages. See [building.md](building.md)'s "Building variant sheets" for
  the full contract.

### A household that leaves keeps its house, and that froze the village

Reported live off the settlement card: *"Population 1 (10 housed)"*,
alongside *"The villages population is declining"*. The first is
impossible on its face — you cannot have ten of one household under roofs
— and the second was its consequence.

`EarthChunkManager._record_household_departure` appends a
`npc_departed` event and **releases nothing**: no roof, no villager, no
household record. `_households_in_settlement` then stops counting that
household, while the house it built still names it as owner. So
`VillageCensus` met roofs whose owners were not on the roster it was
handed, and counted them among "ours" — against the contract
`VillageAssembly` states in its own argument list, *"housed_count — how
many of THEM have a roof"*.

The bookkeeping error froze the village solid, which is the part that
mattered:

- `housed_count >= household_count` tells `VillageGrowth.next_building`
  there is nobody left to house, so **no house is ever raised again**.
- `spare_house_capacity = capacity - housed_count` tells
  `VillageImmigration` there is no room, so **nobody ever moves in
  again**.

A village carrying ghost owners can therefore only lose people. The
census now counts only the roster it was handed, which restores both
gates and makes the card unable to contradict itself. A roof whose owner
has left is room the village may grow into again.

### Known gaps, stated rather than papered over

- 🚧 **The villagers you can see are a render-time snapshot; the card is
  live.** `VillageRenderer._population_for` reads the real roster
  (`household_count_for_settlement`) — but only when the chunk is
  rendered. Nothing spawns a villager when a household arrives mid-session
  and nothing removes one when a household departs, so the markers walking
  about and the card's Population row drift apart until the chunk reloads.
  Reported exactly that way: *"there still run around more NPCs than the
  number displays"*. Closing it means spawning and despawning villagers
  live, which is a real change to how a village is rendered rather than a
  counting fix, so it is named here rather than guessed at.
- 🚧 **A village only draws new households while its chunk is LOADED.** The
  room half of the immigration gate is read off buildings that really
  stand, and an unloaded chunk has none to read; guessing at them would be
  exactly the invented number this project's rules forbid. A village
  therefore grows while the player is near it — the same scope
  `_step_settlement_construction` already has. Construction itself keeps
  its unloaded catch-up (`_apply_construction_labor_catchup`); immigration
  has no equivalent yet.
- 🚧 **Interiors.** `sawmill`/`blacksmith`/`brewery` declare a `workshop`
  family and `farmhouse` a `farmstead` one; `InteriorTemplates` has real
  plans for `cottage`/`house`/`manor` only, so those (like the already-real
  `hall`) fall back to the cottage variants. Entering a mill shows a
  cottage interior, honestly noted here rather than dressed up.
- ✅ **A growth house is always the small one** — closed 2026-09-19 by
  [village_estates.md](village_estates.md) mechanism 5. The house a village
  raises is the waiting household's own ESTATE's house
  (`VillageEstates.house_id_for`), so a burgher who lost a roof is not
  rehoused in a cottage. `VillageGrowth.next_building` itself still names
  the first house id, which is the right answer for a caller with no
  villager in hand.
- 🚧 **The ladder's rungs are buildings, not yet production.** A standing
  `sawmill`, `farmhouse`, `blacksmith` or `brewery` is a real building the
  village raised and a real contributor to the `community` need; none of
  them yet RUNS a production chain of its own the way the legacy
  single-tile `sagewerk`/`farm` do (`_sync_sagewerk_lumberjack`,
  `_farm_farmers`).

  **Mostly closed, 2026-09-19** ([village_estates.md](village_estates.md)
  mechanisms 1 and 4). Every rung has a real WORKFORCE it must be staffed
  from and an output scale that is zero until somebody of the right estate
  stands in it (`VillageLabor`), and `StaffedProduction` spends that scale:
  a staffed brewery really brews `beer` out of the village's own grain, so
  beer and bread compete for one harvest, and a staffed sawmill really
  brings more usable timber in from the same hands.

  The two still producing nothing are out for reasons the code found. A
  `blacksmith` would run the heat-gated smelts `OccupationProduction` rules
  out on principle plus a tool recipe its own smith's household already
  runs. A `farmhouse` would run `grow_wheat`, which is `automated` —
  `can_craft` refuses one outright, because a farmhouse's grain really does
  come from its real field (`FarmPlot`/`VillageFarm`), and running it again
  through a market would be the same crop harvested twice.
- ⬜ **Civic buildings beyond the ladder.**
  [civic_construction.md](civic_construction.md)'s Watchtower, and its
  richer multi-piece `CivicBlueprint` shape, stay design-only.
