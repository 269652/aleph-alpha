# Building Storage — goods sit somewhere before they are anywhere

Asked for directly: *"Farmhouses, Sawmills, Houses should have their own
small storage where e.g. a villager keeps his acquired goods; the farmhouse
stockpiles wheat until the storage is full and workers then move stock from
farmhouse to city storage regularily... it should be visible as inventory tab
in the popover when you click a building"*.

## What this is not

Not a new container. `StructureStock` (item_id → int) already exists and its
own doc comment says outright that it serves **two** roles — a Storage
building's inventory and a production building's accumulated-output queue —
and that "there is exactly one stock shape in this codebase". A whole
building is the **third** role of that same shape, not a fourth container
design.

Not a new store either. `StructureStockStore` is keyed by *a position string
built from a global tile coordinate*, explicitly "regardless of which
structure id sits there". A whole building has a global origin tile. It fits
with nothing changed.

Not a new hauler. `LogisticsBehavior` is already the pure state machine for
"move a production building's accumulated output into a Storage building" —
`SEEKING → APPROACHING → COLLECTING → CARRYING → DEPOSITING` — written for
exactly this job.

## The gap, stated precisely

Every one of those pieces serves the **placeable tile** economy (`farm`,
`sagewerk`, `storage` — single-tile structures the player builds). The
village's **whole-building** economy has none of it.

`NpcEconomy.record_real_harvest` is the whole of it today:

```gdscript
market.add_stock(item_id, float(count))
_earn(float(count) * float(NpcProduction.YIELD_TO_GOLD_RATE))
```

A farmer cuts wheat in a field and it is *instantly, teleportingly* a number
in a settlement-wide market. It never sits in the farmhouse. Nobody ever
carries it anywhere. There is no such thing as a full building, and so no
such thing as a village whose granary is the bottleneck.

## Design pillars

1. **Goods exist somewhere.** A harvest sits in the farmhouse that produced
   it until a person carries it out. A settlement-wide number that appears
   the instant a scythe swings is a convenience, not an economy.
2. **One stock shape, at a third scale.** `StructureStock` for a tile,
   `Market` for a settlement, and now the same `StructureStock` for a
   building — the same instruction `timber_construction.md` already gave when
   building-scale stock was introduced in the first place.
3. **Full means full.** A building holds a real, finite amount. A full
   farmhouse is what makes hauling matter; without a cap, a stockpile is just
   a slower number.
4. **Carrying is work somebody does, and you can watch them do it.** The same
   pillar the social layer runs on: a stock that moves by bookkeeping is not
   logistics, it is a transfer.
5. **Pay is for the work, not for the delivery.** A villager is paid when
   they harvest, exactly as they are now. Decoupling *payment* from *where
   the goods are* is what lets stock become real without touching the famine
   chain that hangs off a villager being able to buy a meal.

## Real-world grounding

A farm has a barn. Grain sits in it after harvest and goes to the village
granary by cart, in loads, when someone has time and the barn is filling.
That lag is not friction to be designed away — it is where hoarding, spoilage,
shortage, theft and trade all come from. A village where every ear of wheat is
instantly communal property has no logistics and therefore no economy.

## Mechanism

### Every building has a stock and a capacity

`BuildingCatalog.storage_capacity_of(building_id)` — how many units a
building holds in total, across all item ids.

| building | holds | why |
|---|---|---|
| house (all tiers) | small | a household's own goods, not a business's |
| farmhouse, sawmill, blacksmith, brewery, mill, bakery | medium | a few harvests' worth: enough to work between collections |
| warehouse | large | the village's granary — the point of the building |
| city hall and the rest | none | not a place goods are kept |

`EarthChunkManager.building_stock_at(global_x, global_y)` returns the
`StructureStock` for whichever building's footprint covers that tile, from the
existing `StructureStockStore`, keyed by the building's own **origin** tile so
every cell of a 3×2 farmhouse answers with the same stock.

### Production stockpiles where it was produced

`record_real_harvest` keeps paying the villager and stops teleporting the
goods. The crop goes into the workplace's own stock. When that stock is full
the building takes no more — which is the pressure pillar 3 exists to create,
and the reason the next section exists.

A villager's own acquired goods go into their **house** the same way, which is
what makes a house a home with things in it rather than a sleeping box.

### Hauling: workers move stock to the city storage

A villager with nothing more pressing, whose workplace stock is filling,
takes a load to the settlement's warehouse and deposits it there — where it
becomes the settlement market stock everyone buys from. Built on
`LogisticsBehavior`, which is that state machine already.

This is the step that keeps the market fed. It is deliberately the *same*
shape as the social layer's meetings: a real walk, taking real time, that you
can watch happen.

### The popover shows it

`household_report_at` gains the building's stock, and `HousePanel` draws an
**Inventory** tab beside what it already shows. `HousePanel` is a pure
consumer of that dictionary by design — it "renders what it is handed and
reaches for nothing else" — so the tab is drawn from the report, never from a
second lookup of its own.

## Status

Written before implementation, per CLAUDE.md. Corrected against the code as
each slice lands.

- ⬜ **Every building has a stock and a capacity** — `storage_capacity_of`,
  `building_stock_at`, persisted through the existing store.
- ⬜ **An Inventory tab on the building popover.**
- ⬜ **Production stockpiles into its own building** rather than teleporting
  into the settlement market.
- ⬜ **Workers haul loads to the warehouse**, and that is what feeds the
  market.
- ⬜ **A villager's own goods live in their house.**

## Interaction with other docs

- [timber_construction.md](timber_construction.md) — "Storage, logistics, and
  the autonomous dependency chain": the tile-scale original of every piece
  reused here, including the explicit instruction not to invent a second
  container.
- [economy.md](economy.md), [production_chains.md](production_chains.md) — the
  settlement-scale market this feeds, instead of being fed directly.
- [village_farms.md](village_farms.md) — the farmhouse whose harvest is the
  first thing to stockpile.
- [village_growth.md](village_growth.md) — mechanism 5 is the click-a-building
  readout the Inventory tab joins.
- [npc_social_life.md](npc_social_life.md) — hauling is a villager behaviour
  and obeys the same "real work outranks a need" ordering.
