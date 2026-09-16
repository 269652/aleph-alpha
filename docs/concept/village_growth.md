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

## Mechanism 3 — Arrivals: population that actually grows

`VillageImmigration.arrivals(settled_days, food_per_household,
free_capacity, attractiveness_bonus, carry)` — the same
carry-the-fraction, whole-units-out shape `SettlementGathering` and
`SettlementGranary` already use.

- **Gated on room**: `free_capacity <= 0` ⇒ no arrivals. A village with no
  spare roof takes nobody in, however rich.
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

## Mechanism 4 — Wellbeing: needs, happiness, productivity

`HouseholdWellbeing.assess(state) -> {needs, happiness, productivity}`,
pure, from real state passed in.

**Four needs**, each a satisfaction in `[0, 1]` (1 = fully met):

| need | satisfied by | real source |
|---|---|---|
| `food` | the resident's own hunger, and the settlement's food stock per household | `NpcNeeds.hunger`, `SettlementFood` / `VillageMarket.stock` |
| `shelter` | having a house at all, and its capacity vs. household size | `BuildingCatalog.capacity_of` |
| `income` | wallet balance against the local price of a meal | `Household.wallet`, `VillageMarket.VILLAGE_LOCAL_FOOD_PRICE` |
| `community` | how many civic/production rungs actually stand in the village | the ladder above, `_present_structure_ids_for_settlement_chunk` |

**Happiness** is the weighted mean of the four, food weighted heaviest and
community lightest (`NEED_WEIGHTS`, test-pinned by the ordering they
produce: an unfed household is unhappier than one merely lacking a
brewery).

**Productivity** is happiness with hunger as a hard drag: a starving
household works badly however pretty the town is. Floors at
`MIN_PRODUCTIVITY` rather than zero — a desperate household still works,
just poorly — and reaches 1.0 only for a fed, housed, paid household in a
village with its civic buildings up.

Productivity is not a decoration: it scales the settlement's own real
gathering rate (`SettlementGathering.material_delta`), so an unhappy
village visibly builds slower. That closes the loop — buildings raise
happiness, happiness raises productivity, productivity raises the material
that raises buildings — which is precisely the Anno loop this whole doc is
about.

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

## Status

- ⬜ Everything in this doc is specified here first and implemented in the
  slices below; each entry moves to ✅/🚧 as it lands, and
  [progress.md](../progress.md) carries the implementation ledger.
