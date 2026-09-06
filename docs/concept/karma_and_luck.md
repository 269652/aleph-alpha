# Karma and Luck

Asked directly: "a Luck skill which influences dice rolls and a Karma
system which influences Luck; e.g. stepping on a worm should give -1
Karma... Abandoning a quest as well. Helping an NPC +1 Karma."

This doc resolves a real tension before specifying anything: **this
codebase has an explicit, repeatedly-stated design rule that combat,
crafting, and spellcasting have no random rolls at all** — see
`secret_d20.gd`'s own doc comment ("this project deliberately has NO
random rolls anywhere in its actual gameplay systems... isolation is the
whole point") and `docs/concept/easter_eggs.md`. Introducing "dice rolls"
wholesale would fight that design directly. Asked which way to resolve
it: **Luck biases outcomes that are already real, deterministic formulas**
— it never adds a new random roll of its own. What actually varies today
(a struggle roll against a fixed chance, a yield roll against a fixed
range) keeps its existing shape; Luck nudges the number that formula
already produces, the same way `Player.skill_bonus("taming_affinity")`
already does for `Taming.break_free_chance`.

## Design pillars

1. **Luck is a lens on existing formulas, never a new source of
   randomness.** No new `randf()`/`randi()` call exists anywhere because of
   this feature. Every place Luck reaches is a formula that already
   existed, already had a tuned min/max/chance range, and already had (or
   gets, following the identical shape) a slot for a player-stat modifier
   — see `Taming.break_free_chance`'s own `affinity` parameter for the
   pattern this copies exactly.
2. **Karma is legible, not hidden.** A karmic act names its own cause and
   effect in a code comment and a doc entry — no "mystery meter." The
   Character Sheet (see `character-sheet-portrait-shipped.md`) is the
   natural place a player would eventually see it; this pass wires the
   underlying number correctly and leaves the display as a named,
   separate follow-up rather than inventing UI under time pressure.
3. **Karma tracks the player's own DELIBERATE-enough acts, not narrated
   morality.** The starting set below is small and concrete on purpose:
   a real, checkable event (a worm died underfoot, a quest was abandoned,
   a quest was fulfilled) rather than an attempt to grade every possible
   good or bad deed. "And so on," from the request, is deliberately left
   as a small, growing, named list (see Karma events below) rather than a
   generic hook fired from everywhere — each new trigger is a real,
   reviewed decision, the same way this project has always added tuned
   constants one at a time rather than in bulk.
4. **Bounded in both directions.** Karma can go up or down without limit
   as a raw counter (it is a real, permanent record of what happened), but
   the LUCK it produces saturates — a lifetime of good deeds cannot make
   every roll a guaranteed success, the same "harder, never impossible"
   principle `Taming.AFFINITY_MAX_REDUCTION_FRACTION` already established
   for a different stat.
5. **Reuse existing seams before inventing new ones** (this project's
   standing rule, restated in `docs/concept/quests.md` pillar 4 and
   followed here too): Luck's reader is the exact shape
   `Player.skill_bonus` already established; Karma's persistence is the
   exact shape `mushrooms_eaten` already established; a crushed worm's
   Karma hook reuses the crush mechanic's own existing return value rather
   than adding a new signal system.

## Karma: what moves it, and by how much

A single persistent float on `Player` (see Persistence below), changed by
named events only:

| Event | Delta | Source |
|---|---|---|
| A worm, caterpillar, millipede, ant, or bug (`DecomposerMarker`) is crushed underfoot (player's own step OR any creature's, since `CrushMechanic` already treats all five identically — see its own doc comment). Millipedes, ants, and bugs each joined this table's first two entries the same way, once `docs/concept/soil_fauna.md`'s "Generalized to millipedes too"/"Generalized to ants too"/"Generalized to bugs too" gave them the identical crush shape a caterpillar already has | `-1.0` | `CrushMechanic`/`EarthwormPatch`/`EarthChunkManager.crush_caterpillars_near`/`crush_millipedes_near`/`crush_ants_near`/`crush_decomposers_near`, hooked from `World`'s existing per-frame crush pass |
| A quest is abandoned (see Quest lifecycle below) | `-1.0` | `QuestLog.abandon` |
| A quest is fulfilled — this is the request's "helping an NPC": every quest in this codebase's real, implemented slice is literally an NPC's own stated need (`docs/concept/quests.md` pillar 1), so completing one and helping the NPC who asked for it are the same event, not two mechanisms | `+1.0` | `QuestLog`, detected the same re-derivation way completion always works here (see below) |

Every delta is a named constant in `src/gameplay/karma.gd`
(`WORM_OR_CATERPILLAR_CRUSH_PENALTY`, `QUEST_ABANDON_PENALTY`,
`QUEST_FULFILLED_REWARD`), not a bare literal at each call site — the
usual "tuned values are tested constants" rule, applied even though these
three happen to share one magnitude today; they are free to diverge later
without a signature change anywhere.

**Deliberately not scored here, named so a future pass doesn't have to
rediscover why:** combat kills (this game's combat has no morality axis
today — a wolf and a bandit are not distinguished anywhere existing), and
regular trading/crafting (both already have their own real economic
consequence; adding Karma on top would double-count an already-modeled
cost/benefit).

## Luck: how Karma becomes a number formulas can read

`src/gameplay/karma.gd`:

```gdscript
const KARMA_CEILING := 15.0  # symmetric: -15.0 is the floor
static func luck_for(karma: float) -> float:
    return clampf(karma, -KARMA_CEILING, KARMA_CEILING) / KARMA_CEILING
```

`luck_for` always returns a value in `[-1.0, 1.0]` — saturating at
`KARMA_CEILING` (15 karma, i.e. 15 net good acts) the same way
`Taming.AFFINITY_CEILING` saturates at 15 skill-node investment, a
deliberate echo, not a coincidence: both represent "the practical ceiling
of investing in this axis at all," so they share the same scale rather
than each inventing its own.

`Player.luck() -> float` is the single reader every formula below calls,
mirroring `Player.skill_bonus`'s own "one reader, many call sites"
shape: `return Karma.luck_for(karma)`.

## Where Luck actually reaches

Two real, already-existing, already-tuned formulas, chosen because both
already have a proven "player-stat nudges this number, byte-identical at
zero investment" slot to extend — no new formula shape was invented for
either:

- **`Taming.break_free_chance`** gains a `luck` parameter alongside its
  existing `affinity` one. Good luck shaves a further, SEPARATE small
  fraction off the break-free chance (bad luck adds it back), on top of
  whatever `affinity` already does — same
  `AFFINITY_MAX_REDUCTION_FRACTION`-shaped "fraction of the existing
  MIN/MAX spread" derivation, not a fresh eyeballed number, and exactly
  0 effect at `luck == 0.0` (a character who has done nothing notable
  either way sees byte-identical numbers to before this parameter
  existed — pinned the same way `test_break_free_chance_is_unchanged_
  with_no_predator_and_no_affinity` already pins the `affinity` case).
- **`OreYield.yields`** gains the same shaped `luck` parameter, nudging
  the existing extra-ore roll's own chance rather than the guaranteed
  base yield (bad luck should make bonus ore rarer, not take away ore a
  swing already earned).

**Deliberately not reached this pass, named rather than silently
skipped:** `FishingMinigame.fish_rarity`, `KnappingModel.shard_yield`,
`RarityTier.roll_tier` (this last one has zero call sites anywhere yet —
loot drops aren't wired up at all, a separate, bigger gap this doc isn't
closing). Each is a real, same-shaped follow-up once wanted; this pass
proves the pattern on two formulas rather than touching every candidate
at once.

## Quest lifecycle: accept, abandon, fulfil

`src/emergence/quest.gd`'s real, implemented slice (Production shortfall
quests) is a pure, stateless PROJECTION over live household/market state
— by its own pillar 1, it is never itself a persisted entity, and this
doc does not change that. What it has never had, because nothing
consumed it yet, is any record of the PLAYER'S OWN commitment to one.
`QuestLog` (`src/emergence/quest_log.gd`) adds exactly that, as a thin
layer that references the live projection rather than duplicating it:

- **`offer_id_for(quest: Dictionary) -> String`** — derived, never
  allocated, matching `docs/concept/quests.md`'s own stated convention
  for the (unbuilt) dialogue `QuestOffer` shape: `"production:<household_
  id>:<recipe_id>"`. The same real shortage always yields the same id.
- **`accept(offer_id)`** — the player commits. Pure set-membership; no
  new fact about the WORLD is created, only about the player's own
  intent.
- **`abandon(offer_id)`** — the player explicitly withdraws, `-1` Karma.
- **Fulfilment is DERIVED, never a separate mutator** — matching this
  whole system's "rewards are re-derived from live state, never trusted
  from the offer" rule (`quests.md`'s own "Rewards are derived, and
  re-derived" section): a periodic reconciliation (`World`'s existing
  per-tick ecosystem step, the same shape `reconcile_bird_markers`
  already uses for a different kind of periodic re-sync) re-runs
  `production_shortfall_quests_for_settlement` for every settlement with
  an accepted quest; any accepted `offer_id` that no longer appears in
  the fresh result had its underlying need genuinely resolved —
  `+1` Karma, removed from the accepted set. A quest can therefore never
  be "completed" by anything other than the real shortage actually going
  away, the same honesty the reward-derivation rule already requires.

**Deliberately out of scope, named rather than silently assumed done:**
this is NOT the full `docs/concept/quests.md` vision (settlement quorum,
safety/social need sources, village endangerment, rewards/currency
transactions) — those remain exactly as unbuilt as that doc's own status
section already says. This adds only the accept/abandon/fulfil state
machine on top of the one need source that is real today. **Also
deliberately out of scope: a player-facing UI to invoke accept/abandon.**
`QuestLog` is real, tested, engine-free logic — same as `quest.gd` itself,
which also has no UI consumer yet. Wiring a first quest-facing
interaction (dialogue, a prompt, or otherwise) is a separate, named
follow-up this doc does not claim to have solved.

## Persistence

`Player.karma` (float) and `Player.accepted_quest_ids` (Array[String], from
`QuestLog`) round-trip through `to_save_dict`/`apply_save_dict` exactly the
way `mushrooms_eaten` already does — one line added to each side, no
change to `PlayerSave`'s own schemaless-Dictionary format.

## Status

- ✅ `Karma` module: event constants, `luck_for`.
- ✅ `Player.karma` + `Player.luck()`, persisted.
- ✅ `Taming.break_free_chance` and `OreYield.yields` read `Player.luck()`.
- ✅ Worm/caterpillar crush → Karma, wired into `World`'s existing crush
  pass.
- ✅ `QuestLog`: accept/abandon/derived-fulfilment, wired to Karma.
  `reconcile` runs automatically every `EarthChunkManager.
  SETTLEMENT_STEP_INTERVAL` from `World._step_ecology_batch` whenever the
  player has an accepted quest. `accept`/`abandon` themselves are ready to
  be called by a future player-facing interaction (see the next line).
- ⬜ Character Sheet display of Karma/Luck.
- ⬜ Player-facing accept/abandon interaction (dialogue or otherwise).
- ⬜ `FishingMinigame`/`KnappingModel`/`RarityTier` Luck hooks.
- ⬜ Safety/social quest need sources, settlement quorum, and everything
  else `docs/concept/quests.md` already names as unbuilt — unaffected by
  this doc.

## Open questions

- Should Karma decay slowly toward 0 over time (a "the world forgets, but
  slowly" framing), or stay a pure permanent ledger? Left as a pure
  ledger for this pass — simpler, and reversible later without touching
  any of the event-recording call sites, only `luck_for`'s own math.
- Once a Character Sheet display exists, should raw Karma be shown as a
  number, or only its qualitative effect on Luck? Deferred to whoever
  builds that display.
