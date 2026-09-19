# Settlement Charter: what a city may build and a village may not

Asked for directly: *"I want it so, that some buildings like a mage guild
can only be built in cities; not villages; so a player has to help
villagers to grow into a city in order to get access to mage guild and
other similar buildings."*

That is a progression system whose currency is **somebody else's
prosperity**. The player does not unlock the mage guild by levelling; they
unlock it by making a place big enough, organised enough and productive
enough to hold one. Everything needed to measure that already exists —
[village_estates.md](village_estates.md) grows the households,
`InstitutionStore` forms the trade bodies, `OccupationProduction` and
`StaffedProduction` run the trades, and `SettlementTier` already reads all
three and classifies the place. This doc is the gate that hangs off it.

## Design pillars

1. **The gate is the SETTLEMENT, not the player.** A charter is a property
   of the place. The same player raises a mage guild in a city and is
   refused in the hamlet an hour's walk away, and nothing about them
   changed in between. No skill, no level, no quest flag — the answer is
   about the ground they are standing on.
2. **The tier is already real, and it is already three things at once.**
   `SettlementTier.tier_for` reads households, ACTIVE institutions and
   production diversity, and **all three must cross together** — that is
   its own long-standing rule, written before any of this. It is exactly
   what makes "help them grow" a real errand instead of a food-dumping
   exercise: a player can carry in a hundred meals and still not have a
   city, because a city is also trades that organised themselves and goods
   that are actually being made.
3. **A refusal must teach.** "You cannot build that here" is a dead end and
   a bad game. Every refusal names the tier the building wants, the tier
   the settlement holds, and **exactly how many households, institutions
   and distinct production lines it is still short**. The player leaves
   knowing what to go and do.
4. **Nothing a settlement needs in order to GROW may be gated behind
   having grown.** Test-pinned as a hard invariant, not a convention:
   every rung of the growth ladder and every estate charter building must
   be buildable at the LOWEST tier. Break it and the ladder deadlocks on
   needing the city it would have created — the same class of bug
   [village_estates.md](village_estates.md)'s saw-pit deadlock already
   was, caught the same way.
5. **A village never asks for what it may not have.** The assembly
   ([village_estates.md](village_estates.md) mechanism 5) reads the same
   gate the player does, so a hamlet does not spend years saving timber for
   a hall it would be refused.
6. **Tuned values are tested functions.** Every threshold is
   `SettlementTier`'s own, already pinned there. This doc adds no new
   numbers to the tier at all — that is the point of hanging off it.

## Real-world grounding

**The city charter** (*Stadtrecht*). Certain institutions were not things a
place could simply decide to have: a guild hall, a mint, a staple right, a
court of its own. They were **granted to chartered towns and cities**, and
a village that wanted one had to first become a town — which in practice
meant reaching a real size, holding a real body of organised trades, and
running a real economy that produced more than one thing.

The three dimensions `SettlementTier` already measures are precisely those
three things, which is why this doc introduces no new measure. A hamlet is
a hamlet because it is small, has no organised bodies, and makes one thing.

## Mechanism 1 — The charter table

`SettlementCharter`, pure and static:

- `MIN_TIER_BY_BUILDING` — `building_id -> the lowest SettlementTier tier
  that may raise it`. A building absent from the table has no charter
  requirement and may be raised anywhere, which is every building that
  exists today.
- `min_tier_for(building_id)` → that tier, or `""`.
- `allows(building_id, tier)` → whether a settlement at `tier` may raise it.
- `tier_rank(tier)` → the tier's index in `SettlementTier.TIERS`, so
  "at least" comparisons are one shared reading rather than a chain of
  string equalities.

## Mechanism 2 — The refusal that teaches

`SettlementCharter.refusal_for(building_id, households, institutions,
production_diversity)` → `{}` when the settlement may build it, otherwise:

```
{
  "building_id":  what was refused,
  "required_tier": the tier it wants,
  "tier":          the tier this settlement actually holds,
  "short": {"households": n, "institutions": n, "production_diversity": n},
}
```

`short` is what is **still missing**, per dimension, counted against the
required tier's own thresholds — zero for a dimension already cleared. A
player refused a mage guild in a town learns they need (say) two more
households and one more trade, not merely that they were refused.

`shortfall_to(tier, households, institutions, production_diversity)` is the
same arithmetic on its own, so a readout can show the distance to the next
tier without pretending to refuse anything.

## Mechanism 3 — The anti-deadlock invariant

Stated as a test rather than a promise: **every building a settlement needs
in order to climb must be buildable at the bottom.**

- every id in `VillageGrowth.LADDER_BUILDING_IDS`
- every id in `EstateAscension`'s charter table
- every house in `BuildingCatalog.BUILDING_IDS`

must have no charter requirement above the lowest tier. A hamlet with no
farmhouse cannot make husbandmen, cannot diversify production, and cannot
become a town — so gating the farmhouse at TOWN would be a village that can
never grow, discovered months later by somebody watching a save go nowhere.

## Mechanism 4 — The village obeys it too

`VillageAssembly` gains the same gate: a settlement never petitions for a
building its charter forbids. The village's own ladder and the player's own
build hand are two callers of one rule, so a hamlet cannot quietly raise
through its own construction ledger what a player standing on its square
would be refused.

## Mechanism 5 — The readout: click the hall, read the charter

Clicking a settlement's civic building opens the readout it already has,
with the charter on it: what the place IS, and what it would take to be the
next thing up. The panel already handles a commons (it says "Settlement
commons" and shows village productivity); this is the line under it.

A player who wants a mage guild can therefore stand in the village, click
the hall, and read the errand: *Town — a city needs 2 more households, 1
more trade body.*

## The chartered buildings

Two, at two different tiers, so the mechanism is demonstrated rather than
special-cased — and both grounded in systems that already exist rather than
invented to fill a table.

| building | charter | what it is |
|---|---|---|
| `trade_hall` | **town** | the trade guild's own house. `InstitutionStore` already forms real `guild` institutions out of repeated fulfilled contracts, and [village_estates.md](village_estates.md)'s relief chest is already held by one — a guild that has organised itself enough to be measured is a guild with somewhere to meet. **Not** `guild_hall`: that id is already a 7×7 piece-built *player house* blueprint, and two different things sharing one id is how a recipe book ends up with a duplicate key. |
| `mage_guild` | **city** | the user's own example, and the answer to a question [magic.md](magic.md) has carried open since it was written: *"Exact station-tier thresholds for compiling (or whether compiling needs a station at all…)"*. Compiling a designed spell into one you permanently know is the single biggest gold sink in that doc; the station it happens at is a mage guild, and a mage guild needs a city. |

## Status

Written before implementation, per CLAUDE.md. Corrected against the code as
it lands; see [progress.md](../progress.md) for the ledger.

- ⬜ Mechanism 1 — `SettlementCharter`, the table and its readings.
- ⬜ Mechanism 2 — the refusal that names what is short.
- ⬜ Mechanism 3 — the anti-deadlock invariant.
- ⬜ Mechanism 4 — the assembly reads the same gate.
- ⬜ Mechanism 5 — the charter on the readout.
- ⬜ `trade_hall` and `mage_guild` as real catalog buildings.

## Interaction with other docs

- [village_estates.md](village_estates.md) — the estates, the assembly and
  the guild whose chest the trade hall houses.
- [village_growth.md](village_growth.md) — the ladder whose rungs this must
  never gate.
- [magic.md](magic.md) — the compile station the mage guild is.
- [04-settlements-cities-infrastructure.md](../emergence/04-settlements-cities-infrastructure.md)
  — the city threshold `SettlementTier` implements and this hangs off.
