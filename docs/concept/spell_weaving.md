# Spell weaving — motes you find, an order you choose

The magic DSL is finished and nobody can write in it.

[magic.md](magic.md) promises a language players design spells in,
Morrowind-style, and the pipeline behind that promise is real and
complete: `spell_parser.gd` parses a genuine surface syntax,
`spell_atom_catalog.gd` holds 25 atoms across 10 categories,
`spell_cost.gd` derives a price no author can undercut, and
`spell_executor.gd` decides a cast. What sits on top of all of it is
`spell_book.gd` — a **fixed authored table of twenty-four source
strings**. The player casts what the table says and can never add a line
to it. There is no way to acquire a part of a spell, and no way to put
two parts together.

This doc specifies the acquisition and composition layer: an atom as a
**mote** you can own, and a **draft** that sockets motes in an order and
compiles to the DSL the rest of the stack already speaks. It is the
answer to the friend's eighth requirement — *Magicraft-style composable
spellcrafting* — and it deliberately adds no second interpreter, no
second cost model and no second rarity scale.

## Design pillars

1. **The composition becomes a real spell, through the real pipeline.**
   `SpellDraft.source_for(draft)` emits text in exactly
   `spell_book.gd`'s format, and the proof is a round trip:
   `SpellParser.parse(SpellDraft.source_for(draft))` returns `ok` with a
   cast rule whose atoms, order and delivery are the draft's. A
   composed spell is not *like* a book spell; it is one. Delete this
   module and the DSL is untouched — the house rule
   [errands.md](errands.md) states for itself, kept.
2. **One cost model, and it is not this one.** `cost_of` calls
   `SpellCost.paid_mana` on the same atom list the parser would emit.
   A second price for the same spell is how a world stops being one
   world ([village_ponds.md](village_ponds.md)'s rule).
3. **The first mote of anything is paid for with experience, not
   loot.** You learn `frost_damage` by nearly freezing to death, not by
   opening a box. Every phenomenon in the witness table is a system
   that already exists and can already hurt you: `SurvivalMeters`'
   `is_freezing`, `VenomModel`'s stacking bite, `WeatherModel`'s
   `storm`, a campfire, starving after dark, ground too steep to climb,
   a predator that chose you. Magic in this world is not studied first;
   it is survived first.
4. **Depth is paced by distance, and the pacing is somebody else's
   constant.** Which atom tiers may *drop* at a given
   [journey ring](journey_rings.md) is the ring's own
   `RegionDifficulty.Tier` plus one — EASY ground drops tier 1, MEDIUM
   drops up to tier 2, HARD up to tier 3. Nothing new is invented and
   nothing can disagree: a `summon_wisp` mote cannot exist in the
   hearth because the hearth is EASY, the same fact that keeps bears
   out of it. The friend's third requirement — *you should not be able
   to stroll to the final boss* — gets its magical half here, again as
   a gradient rather than a fence.
5. **Order is the craft.** Adjacent motes react, and the reactions are
   **ordered pairs**: fire then ignite is a conflagration; frost then
   fire is steam; fire then frost is *quenched* and costs you effect.
   Swapping two motes visibly changes the result, which is the whole
   reason a socket row is more interesting than a checklist.
6. **Order buys effect, never a discount.** Reordering a draft changes
   its reaction set and never changes its price — `SpellCost`'s
   composition cost reads a multiset, and reactions scale magnitude at
   resolution. A clever order that also paid less would make the cost
   model advisory.
7. **A refusal is a sentence.** `validate` returns named refusals with
   text a UI can print verbatim. A bare `false` in a spellcrafting
   screen is a player staring at a socket row wondering which of five
   things is wrong.

## Real-world grounding

A mote is the alchemical *principle*: the thing an alchemist believed a
substance carried and could be extracted from it — sulphur from what
burns, salt from what remains, mercury from what moves. Extraction came
from working with the substance and being harmed by it. Every
practitioner who wrote down what antimony does learned it the hard way,
and several of them died of the lesson. Pillar 3 is that literally: the
witness table is a list of ways the world hurts you and the principle
each injury teaches.

Composition by adjacency is the *recipe order* of every real craft that
works with reactions. A smith's quench after a heat is not the same
operation as a heat after a quench; a dyer's mordant before the dye is
not the mordant after it. The order of two steps is a different result,
not a different arrangement of the same result — which is why the
reaction table is keyed on ordered pairs and why `quenched` is a
penalty rather than a missing entry. Doing it backwards is not nothing.
It is worse than nothing.

## Mechanism

### `SpellMote` — an atom as a thing you can own

`src/gameplay/spell_mote.gd`, a `RefCounted` of static functions in the
spirit of `journey_ring.gd` and `spell_schools.gd`: no scene tree, no
world access, no file access, no singleton. It preloads
`SpellAtomCatalog` (the atom's real tier and category), `SpellSchools`
(the tradition it belongs to), `RarityTier` (the rarity vocabulary the
rest of the game already uses) and `JourneyRing` (the ring ladder drops
are paced against), and nothing else.

`mote_for(atom_id)` is the whole record:

```
{"atom": "frost_damage", "name": "Frost Damage",
 "school": "cryomancy", "category": "damage",
 "tier": 1, "rarity": "common"}
```

`{}` for anything that is not an atom — the same "unrecognized
contributes nothing" convention `spell_cost.gd`'s `atom_cost` uses.

**Rarity is `RarityTier`'s, indexed by the atom's own tier.** Tier 1 is
`common`, tier 2 `uncommon`, tier 3 `rare`. The fourth band,
`legendary`, is deliberately unreachable by any single mote: it is what
a *composition* can reach through `RarityTier.tier_from_complexity`, and
that is the point — legendary is something you make, not something you
pick up. Both halves are test-pinned (`test_no_single_mote_is_ever_
legendary`, `test_a_full_draft_of_the_deepest_motes_reaches_legendary`).

**The witness table**, phenomenon → the atom that phenomenon teaches:

| phenomenon | the system that does it to you | mote |
|---|---|---|
| `froze` | `SurvivalMeters.is_freezing` | `frost_damage` |
| `envenomated` | `VenomModel`'s stacking bite | `poison_damage` |
| `warmed_at_a_fire` | the `campfire` placeable | `fire_damage` |
| `caught_in_a_storm` | `WeatherModel`'s `storm` state | `shock_damage` |
| `hungry_in_the_dark` | `is_starving` after `is_night` | `illuminate` |
| `climbed_ground_that_fought_back` | `TerrainPassability.speed_multiplier` | `slow` |
| `hunted` | a predator's chase | `fear` |

Seven phenomena, seven distinct atoms — the mapping is injective
(`test_no_two_phenomena_teach_the_same_mote`), so no experience in the
world is redundant. Every witness atom is **tier 1**, pinned not against
the literal `1` but against `drop_tier_cap_for_ring(0)`: witnessing can
never teach something deeper than the ground you are standing on would
have dropped. Suffering is a head start, not a shortcut.

The table is not exhaustive and is not meant to be. Eighteen of the
twenty-five atoms have no witness at all; those are found, and found
further out.

### Where a mote may drop

`drop_tier_cap_for_ring(ring_index)` is `MIN_ATOM_TIER` plus the ring's
own `RegionDifficulty.Tier` ordinal, read off `JourneyRing.RINGS`:

| ring | tier | atom tiers that may drop |
|---|---|---|
| The Hearth | EASY | 1 |
| The Commons | EASY | 1 |
| The Marches | MEDIUM | 1–2 |
| The Wilds | MEDIUM | 1–2 |
| The Far Country | HARD | 1–3 |

This is a derivation, not a table: change `JourneyRing`'s bands and the
caps follow. Two facts hold it honest —
`test_the_outermost_rings_cap_is_the_catalogs_deepest_tier` (every atom
is obtainable *somewhere*, so no mote is dead content) and
`test_the_catalogs_tier_range_matches_the_difficulty_bands` (a catalog
that grew a tier 4 fails loudly here rather than quietly becoming
undroppable). `droppable_atoms_at_ring(i)` returns the sorted list, and
it grows outward.

### `SpellDraft` — sockets, order, and the compile

`src/gameplay/spell_draft.gd`, pure in the same sense. A draft is a
plain dictionary:

```
{"atoms": ["frost_damage", "freeze"], "delivery": "projectile"}
```

`MAX_SOCKETS` is **4**, and the number is `SpellCost.SPAM_PENALTY`'s,
not this module's opinion. That penalty charges `1.35^k` for the k-th
repeat of a mote, and the fourth socket is the first one where
repeating has cost **more than double** face price — `1.35^3 = 2.46`,
`1.35^2 = 1.82`. A row shorter than that never makes spam hurt; a row
longer just sells more of it (and widens the reaction bound below for
nothing). Both sides of the inequality are asserted, so retuning
`SPAM_PENALTY` fails here rather than drifting
(`test_the_socket_count_is_where_repetition_has_doubled_in_price`).

Four sockets is also exactly enough room to reach the top rarity band
no single mote can: four `summon_wisp` motes at `touch` clear
`RarityTier.COMPLEXITY_RARE_MAX`, three do not
(`test_a_full_draft_of_the_deepest_motes_reaches_legendary`).

`DELIVERIES` is the executor's own four — `self`, `touch`, `projectile`,
`area` — and an unlisted string is refused rather than passed through,
because `SpellCost.delivery_multiplier` silently prices an unknown
delivery as `touch`. A refusal is better than a spell that costs the
wrong thing forever.

- `source_for(draft)` — DSL text in `spell_book.gd`'s exact shape:
  `spell "NAME" { on cast(DELIVERY) when wielder.mana >= @cost: atom(...)
  |> atom(...) }`. Each atom is emitted at its catalog reference
  magnitude/duration (`mag_ref`/`dur_ref`), which is also the value
  `spell_cost.gd` assumes when a parameter is absent — a mote casts at
  its own reference strength, and per-atom tuning is a later surface.
- `cost_of(draft, governing_stat)` / `complexity_of(draft)` /
  `cast_time_of(draft, haste_stat)` — all `SpellCost`, called on the
  parsed pipeline shape.
- `rarity_of(draft)` — `RarityTier.tier_from_complexity(complexity_of(
  draft))`, the same derivation `rarity_tier.gd` already documents for
  spell gems.
- `validate(draft)` — `{"ok": bool, "refusals": [{"code", "reason"}]}`,
  every reason a printable sentence. Five codes: `empty_draft`,
  `unknown_atom`, `too_many_sockets`, `unknown_delivery`,
  `delivery_rejects_atom`.
- `name_for(draft)` — `"<epithet> <noun>"`, the epithet from the
  strongest reaction if the order produced one and otherwise from the
  first mote's school, the noun from the last mote's category. Every
  school and every category has a word, swept exhaustively so a new
  catalog category fails here rather than producing a nameless spell.
- `reactions_of(draft)` / `reaction_multiplier(draft)` — see below.

**`delivery_rejects_atom`** has exactly one rule today:
summon-category atoms require `self` or `touch`, because
[magic.md](magic.md)'s constraint layer 2 says a summon needs physical
space to resolve in and you cannot throw one. The rule is held against
the authored book rather than asserted in the abstract —
`test_every_authored_book_spell_validates_as_a_draft` rebuilds all
twenty-four entries as drafts and requires every one to pass. A
composition rule that refuses content the world already ships is a bug
in the rule.

### The reaction table

Adjacent pairs only, keyed on the **ordered** pair, so `[a, b]` and
`[b, a]` are different lookups:

| order | reaction | effect ×|
|---|---|---|
| `fire_damage` → `ignite` | conflagration | 1.50 |
| `frost_damage` → `shock_damage` | conduction | 1.40 |
| `frost_damage` → `freeze` | flash freeze | 1.35 |
| `frost_damage` → `fire_damage` | steam | 1.25 |
| `fire_damage` → `frost_damage` | quenched | 0.70 |

`MAX_PAIR_MULTIPLIER` (1.5) and `MIN_PAIR_MULTIPLIER` (0.7) bound every
entry, pinned by a sweep of the table. The whole-draft bound is a
product of per-pair caps and nothing else:
`max_reaction_multiplier() == pow(MAX_PAIR_MULTIPLIER, MAX_SOCKETS - 1)`
— three adjacencies in a four-socket draft, so 3.375. It is asserted by
construction, never by searching the space of drafts for the worst one.

The multiplier scales the spell's **effect** at resolution, not its
cost. `test_reordering_changes_the_reaction_set_but_never_the_price`
holds both halves of pillar 6 at once.

## What this is deliberately not

- Not an inventory. Which motes a given player actually holds is a
  caller's state; this module answers "what is this mote" and "may one
  drop here", and stops.
- Not a drop roller. `RarityTier.roll_tier` and the loot layer own
  chance; `drop_tier_cap_for_ring` only says what is *eligible*.
- Not a second executor. `source_for` hands the composition to
  `SpellParser` and the existing stack does the rest.
- Not a parameter editor. Motes cast at their reference magnitudes;
  per-atom magnitude/duration tuning is a later surface and will ride
  the same `source_for`.

## Status

- ✅ **A character owns parts, weaves them, and casts the result**
  (2026-09-20). `Player.motes` / `witness` / `grant_mote` / `weave` /
  `woven_draft` / `cast_woven` (`test_player_spell_weaving.gd`, 12).

  The acquisition story is real: `witness(phenomenon)` grants the atom
  that phenomenon teaches the **first time only** — you learn frost
  because the cold really took you there — and after that the same atom is
  a supply, found rather than re-learned. An experience that teaches
  nothing grants nothing.

  The hinge holds: `cast_woven` compiles the draft through
  `SpellDraft.source_for`, parses it with the **real** `SpellParser`, runs
  it through the **real** `SpellExecutor` and resolves each step through
  the same `_apply_cast_step` an authored spell uses. There is no second
  interpreter and no second cost model — the mana spent is
  `SpellDraft.cost_of`'s own figure, asserted against it.

  Two gates before a weave is accepted, in order: you must own every mote
  you socket (refused by name — *"You hold no Frost mote."*), and the
  arrangement must pass the shared validator, whose refusals are
  sentences. The pouch, what has been witnessed and the weave itself all
  persist, because a spell you designed is yours.
- ⬜ **No authoring surface yet.** A player can own and cast a weave, but
  nothing on screen lets them arrange one: the socket row, the pouch and
  the live name/cost/reaction header are the next slice. Until then the
  loop is reachable only through code.
- ⬜ **Nothing calls `witness` from the world yet**, so the phenomena
  (standing at a fire, freezing, being envenomated, caught in a storm)
  grant nothing in play. Each is a one-line call at a site that already
  detects the condition.


- ✅ `SpellMote`: `mote_for`, `display_name_for`, `rarity_of`,
  `school_of`, `tier_of`, witness table + `first_witness_atom_for`,
  `drop_tier_cap_for_ring`, `can_drop_at_ring`,
  `droppable_atoms_at_ring`.
- ✅ `SpellDraft`: `make`, `atoms_of`, `delivery_of`, `pipeline_of`,
  `source_for`, `cost_of`, `complexity_of`, `cast_time_of`, `rarity_of`,
  `validate`, `name_for`, `reactions_of`, `reaction_pairs`,
  `dominant_reaction`, `reaction_multiplier`, `max_reaction_multiplier`.
- ✅ Round trip through the real parser and executor, for all four
  deliveries, plus the contract that anything `validate` accepts
  compiles to source the parser accepts.
- ✅ Every authored `SpellBook` entry re-validated as a draft (24 of
  24).
- ✅ Drop caps derived from `JourneyRing`/`RegionDifficulty`, swept over
  the whole ring ladder and — independently — over real chunk distances
  through `RegionDifficulty.tier_at`, the same call that decides whether
  a bear may spawn there.
- ✅ Reaction bound pinned by construction as a product of per-pair
  caps.
- ✅ 53 tests: `tests/unit/test_spell_mote.gd` (21),
  `tests/unit/test_spell_draft.gd` (32).
- ⬜ Wiring: nothing grants a mote yet. The witness hooks
  (`SurvivalMeters.is_freezing`, `VenomModel`'s apply, the campfire,
  `WeatherModel`'s storm) are callers that do not exist.
- ⬜ No socket UI. A draft can be built and compiled in code; there is
  no screen that lets a player drag a mote into a socket.
- ⬜ The reaction multiplier is computed and not yet applied — the
  resolution layer that multiplies an atom's magnitude by it is the
  wiring half.
- ⬜ Motes do not drop. `drop_tier_cap_for_ring` says what is eligible;
  no loot table reads it.
