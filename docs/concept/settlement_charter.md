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

Written before implementation, per CLAUDE.md; each entry corrected against
the code as it landed. See [progress.md](../progress.md) for the ledger.

- ✅ **Mechanism 1 — `SettlementCharter`.** The table, `min_tier_for`,
  `allows`, `tier_rank` and `next_tier_above`. An unknown tier ranks BELOW
  every real one, so a caller that hands in nonsense is refused everything
  chartered rather than accidentally allowed it.
- ✅ **Mechanism 2 — the refusal that teaches.** `refusal_for` names the
  tier wanted, the tier held and what is still short per dimension, never
  negative: a readout saying "-3 households" is worse than no readout.
  `shortfall_to` is the same arithmetic on its own, for a readout that is
  not refusing anything.
- ✅ **Mechanism 3 — the anti-deadlock invariant**, and it is stated
  CAUSALLY, which is the only form that is checkable. Three things feed
  `SettlementTier`, so three things must stay free at the bottom: HOUSES
  (households are a dimension, and a household needs a roof), every ESTATE
  CHARTER building (an estate that cannot be reached is labour that never
  changes class), and every building anything PRODUCES through (production
  diversity is a dimension). Plus the converse — a chartered building must
  be none of those things — so the rule cannot be satisfied by chartering
  nothing.
- ✅ **Mechanism 4 — the village obeys it too.** `VillageAssembly` reads
  the same gate before anything else, so a village can never quietly raise
  through its own construction ledger what a player standing on its square
  is refused. A settlement whose tier nobody passed is read as the LOWEST,
  so the assembly errs toward refusing rather than letting a hamlet build a
  mage guild because a caller forgot an argument.

  It also gained a **civic petition**: an estate with nothing to complain
  of and no charter left to earn asks for the institutions its place is
  finally entitled to, cheapest first. Without it a city that earned its
  charter would sit there never raising anything with it, and the player's
  own hand would be the only way a mage guild ever appeared. A shortage
  still outranks an institution — hungry people before halls.
- ✅ **Mechanism 5 — the charter on the readout.** `EarthChunkManager.
  settlement_charter_report_for` answers what a place is, what it may
  raise, what it may not, and what it is short of; it rides on every
  `household_report_at`, and `HousePanel` draws it on the COMMONS only.
  *Town — a city needs 2 more households, 1 more trade body.* A dimension
  already cleared is left out, because "0 more trades" is noise and noise
  is what stops a player reading the line at all. All three readings are
  consumers and never drivers, test-pinned.
- ✅ **`trade_hall` and `mage_guild`** are real `BuildingCatalog` entities
  with real recipes at ONE shared price, priced in the exact three
  materials a settlement gathers — a charter is one gate, and pricing them
  in anything else would be a second, hidden gate behind it. They cost
  strictly more than anything anybody may raise unchartered.

  The catalog's own invariants now read `all_building_ids()` off the
  entries themselves rather than a hand-maintained union of three lists, so
  a new entry cannot quietly escape them. That was found by adding these
  two.

### Known gaps, stated rather than papered over

- ✅ **The mage guild does something.** It teaches
  ([magic.md](magic.md)'s tuition section): a caster now carries a
  known-spell set distinct from the world's catalogue, starts with one
  spell, and buys the rest. That is the payoff this whole ladder was
  gating, so the charter is no longer a locked door in a field: the way
  into higher magic is a village a player helped grow into a city.
- ✅ **And the charter is only the first of two gates.**
  [mage_guild.md](mage_guild.md) put the teaching on the **people inside**
  rather than on the building: a guild raised today holds nobody, masters
  move in one per season up to three, each holds one of ten traditions to
  one of three depths, and a player must walk **in** and find one who
  teaches what they want. So earning the charter buys a *place where
  masters may come*, not a spell shop — and two cities with a guild each
  are not interchangeable. Compiling *new* spells still has nothing to
  compile from (there is no spell-editor UI), but the access layer it
  needs — known set, gold-for-knowledge, station gate — is now real and is
  what it will sit on.
- 🚧 **The trade hall still does nothing.** It is the natural home of
  [village_estates.md](village_estates.md)'s relief chest and does not yet
  hold it. Said plainly rather than dressed up, because a building that
  only exists to be unlocked is half a feature.
- 🚧 **Neither has art.** Both draw the procedural placeholder, which is
  what that path is for (see [building.md](building.md)'s asset contract),
  and will pick up a sheet the moment one is dropped in under its own id.
- 🚧 **The player's own build hand does not consult the gate yet.**
  `building_charter_refusal_at` is the function it will call, and the
  village's own decision already calls it — but the player's whole-building
  path today is `can_build_house_from_blueprint`, which only knows houses,
  and none of the chartered buildings is one. Wiring a player-placeable
  non-house is its own piece of work.
- ⬜ **Tiers above city.** `SettlementTier` stops at city, so `next_tier_
  above` returns "" there and the readout says so honestly.

## Interaction with other docs

- [village_estates.md](village_estates.md) — the estates, the assembly and
  the guild whose chest the trade hall houses.
- [village_growth.md](village_growth.md) — the ladder whose rungs this must
  never gate.
- [magic.md](magic.md) — the compile station the mage guild is, and the
  tuition it sells in the meantime: what a player actually gets for
  growing a city.
- [04-settlements-cities-infrastructure.md](../emergence/04-settlements-cities-infrastructure.md)
  — the city threshold `SettlementTier` implements and this hangs off.
