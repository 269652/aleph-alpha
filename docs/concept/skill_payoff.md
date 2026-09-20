# Skill payoff — what a node actually does to you

[skills.md](skills.md)'s web is finished and the payoff is not. Eighty-four
nodes, seven wedges, gateways, adjacency-gated allocation, route preview,
free respec, DNA-flavoured variants, a genome-seeded signature net — and
the first point a character ever spends buys **`+10 max_health`**, shown
in the tooltip as the words *Max Health* and the number *10*.

Measured in the 2026-09-20 diagnosis pass, against
`src/gameplay/skill_web.gd` and its two legacy tables
(`skill_tree.gd`, `keystone_passive.gd`): the web grants **26 distinct
stat keys**. Of those, **5** are read by anything in the running game —
`max_health` and `attack_damage` (`Player._apply_skill_stat`),
`meat_yield` (`Player._butcher_step` → `Butchering.meat_count`),
`carpentry_level` (`Player._meets_required_skill` and the saw gate), and
`taming_affinity` (`Player`'s restrain call → `Taming.break_free_chance`).
One more, `spell_efficiency`, has a real consumer function that takes it
(`SpellExecutor.cost_for(rule, governing_stat)`) and is **never given
it** — `Player`'s only cast site calls `cost_for(rule)` and lets the
argument default to `0.0`. The remaining **20 stat keys are inert**:
`spell_power`, `spell_atom_tier`, `pet_loyalty`, `pet_health`,
`mining_yield`, `smelting_yield`, `ore_yield`, `craft_quality`,
`wound_recovery`, `disease_resistance`, `venom_resistance`,
`knockback_resist`, `scent_range`, `throw_force`, `stamina_regen`,
`max_mana`, `max_stamina`, `hire_capacity`, `contract_throughput`,
`trade_margin`. They are summed into `Player.skill_bonus` correctly,
forever, and nothing on Earth reads them.

That is the honest state, and this module does not fix it. It makes it
**visible**, and it makes the five-and-a-half that *are* real read as
what they are.

## Design pillars

1. **The path ends in a verb or a rule, never in an unread number.** A
   node is worth showing only if something in the running game changes
   when you take it. Where that is true, the tooltip says what changes.
   Where it is not, the tooltip says *declared* — which is a truthful
   admission, not a stat name dressed up as an effect.
2. **Render a node by running the real function twice.** Once at the
   character's current bonus, once at the bonus this node would give
   them, and show both. Not a restatement of `bonus_amount` in different
   words: the actual downstream number the game itself computes, from
   the same function the game itself calls. *"Wolf escape chance 42% →
   35%"* is produced by calling `Taming.break_free_chance` twice.
3. **The delta is usually not the bonus.** `+7 attack_damage` is not
   "seven better"; it is *four swings to fell a wolf instead of six*,
   and past a threshold one more point changes nothing at all. That
   non-linearity is the build knowledge a passive tree is supposed to
   teach, and it only appears if the real function is the one asked.
4. **Never invent an effect.** A stat with no consumer gets
   `unit: "declared"` and its raw before/after totals. No plausible-
   sounding sentence is written for a number nothing reads — that would
   be a lie the player can't check, and it would remove the pressure to
   go and wire the thing up.
5. **Relevance is about this character, now.** A spell-cost node matters
   to somebody who owns spells; a taming node matters to somebody with a
   companion. The same node is worth a different amount to two
   characters, and the view is allowed to know which.
6. **Pure, like everything else that decides a number here.**
   `RefCounted`, static functions, no scene tree, no world, no file
   access — the shape `spell_cost.gd`, `errand_delivery.gd` and
   `species_bite.gd` already use. The view supplies the character's
   facts; this module supplies the sentence.

## Real-world grounding

The thing being modelled is not a physical system but a learning one.
Skill trees that teach are the ones where the player can hold a
prediction: *this node lets me kill the thing that has been killing me.*
The prediction needs a quantity the player has already watched move —
swings, bites, meat, mana, a percentage that went the wrong way at a bad
moment. The web's stat names are not that; they are the names of the
accumulator slots behind it.

This is the same move [hud.md](hud.md) makes for readouts and
[errands.md](errands.md) makes for refusals: the number the system
already computes is the only thing allowed on screen, and it is shown in
the units the player experienced it in.

## Mechanism

### `NodePayoff` — pure, and the whole rule

`src/gameplay/node_payoff.gd`. Three entry points.

**`preview_for(node_stats, current_bonuses, consumers)`** — the
centrepiece. `node_stats` is the shape `SkillWeb.node_info` already
emits, `[{stat_name, bonus_amount}, …]` (a node's own stat, plus its
DNA-flavoured `variants` if the view is showing one). `current_bonuses`
is `{stat_key: total the character already has}` — that is
`Player.skill_bonus(stat)` per key, no new accumulator. `consumers` is
`{stat_key: {label, unit, better, evaluate: Callable}}`.

For each stat the node grants, it calls `evaluate` **twice** — at
`current_bonuses[stat]` and at `current_bonuses[stat] + bonus_amount` —
and returns:

```
{
  "stat":   "taming_affinity",
  "label":  "Wolf escape chance",
  "before": 0.4278,      # evaluate(current)
  "after":  0.3597,      # evaluate(current + this node)
  "delta":  -0.0681,     # after - before, which is NOT bonus_amount
  "unit":   "chance",
  "better": "lower",     # so the view knows down is good
  "wired":  true,        # does the LIVE game feed this stat in today
}
```

A stat with no consumer returns the same shape with
`unit: UNIT_DECLARED` (`"declared"`), `before`/`after` as the raw bonus
totals, and `wired: false`. Two entries for the same stat key (a node
granting the same stat twice) are summed into one row before evaluation,
so the preview can never double-count.

**`default_consumers(facts)`** — the registry of consumers that really
exist today. Every entry wraps a function verified by reading the file
it lives in; nothing is registered that the codebase does not already
compute:

| stat | function called | the sentence | wired today |
|---|---|---|---|
| `max_health` | `SpeciesBite.bite_damage_for` | bites from *species* survived | ✅ |
| `attack_damage` | `MeleeAttack.attack_damage` + `CreatureInfo.MAX_HEALTH_BY_SPECIES` | swings to fell *species* | ✅ |
| `meat_yield` | `Butchering.meat_count` | meat from one carcass | ✅ |
| `carpentry_level` | `CraftingRecipeBook.recipe_required_skill` | recipes the gate now lets through | ✅ |
| `taming_affinity` | `Taming.break_free_chance` | escape chance of the animal on your rope | ✅ |
| `spell_efficiency` | `SpellExecutor.cost_for` | mana your spell costs | ❌ function exists, live cast site passes `0.0` |

`facts` carries the character's own live numbers (their un-bonused base
health, their held weapon, the species in front of them, the parsed
`cast` rule of the spell they have equipped). A consumer whose fact is
missing is **not registered at all** rather than evaluated against an
invented stand-in, so a character with no spell equipped sees
`spell_efficiency` as *declared* rather than as a fabricated spell's
cost. `CONSUMER_STATS` and `WIRED_STATS` are constants; the registry
cannot quietly grow past them.

**`stats_without_consumers(node_stats)`** — the inert keys among the
ones asked about, defaulting to `CONSUMER_STATS` as the yardstick. Run
over every stat the whole web grants, it returns the 20 listed at the
top of this doc, and `test_node_payoff.gd` asserts exactly that count
against the live `SkillWeb` — so the number in this doc cannot go stale,
and wiring a stat up is a test that *fails until the doc is corrected
downward*.

**`relevance_for(node_stats, build_facts)`** — how much this node
matters to *this* character, in `[0, 1]`, summed per stat and clamped:

- a stat nothing reads scores `INERT_STAT_SCORE` — **0.0**, by pillar 1:
  a number no code reads cannot matter to anybody, and any other value
  here would be a polite fiction;
- a stat a real consumer function computes scores `LIVE_STAT_SCORE`
  (`CONSUMER_STATS`, so `spell_efficiency` counts — the function is real
  and is one argument away from being fed);
- plus `EVIDENCE_SCORE` when the character owns the thing that reads it
  — a spell in the book for `spell_efficiency`, a companion for
  `taming_affinity`, a weapon for `attack_damage`, a carcass butchered
  for `meat_yield`, a recipe currently locked behind the gate for
  `carpentry_level`, damage actually taken for `max_health`.

`LIVE_STAT_SCORE + EVIDENCE_SCORE == 1.0` exactly, so one live,
evidenced stat is a full-relevance node and the ceiling needs no second
constant to define it (test-pinned, not eyeballed). The evidence facts
are counts the view can read off real live state — `SpellBook`'s known
spells, the companion list, the equipped item, the recipe gate — never
anything this module invents.

### What the view does with it

`scenes/skill_web_view.gd`'s hover tooltip prints one line per row:
`label`, `before → after`, in the row's `unit`, tinted by whether
`delta` moved in the `better` direction. A `declared` row prints the
stat's name and *"declared — nothing reads this yet"*, which is the
truth and is also the most useful possible bug report. `relevance_for`
sorts or highlights when several nodes are in reach.

Wiring that view, and wiring the six inert-but-cheap stats into the
systems that should already be reading them, are separate changes and
are named as such below.

## Interaction with other docs

- [skills.md](skills.md) — the web itself, and its own ⬜ "most of the
  new stat keys are still declared and summed" entry, which this doc
  now quantifies exactly (26 granted, 5 read).
- [taming.md](taming.md) — `taming_affinity`, the one stat that has
  already made the journey from declared to read; its break-free curve
  is the model consumer.
- [predator_profiles.md](predator_profiles.md) — `SpeciesBite`'s real
  per-species bite, which is what makes `max_health` expressible as
  *bites survived* instead of as a bar getting longer.
- [magic.md](magic.md) / [spell_runtime.md](spell_runtime.md) —
  `SpellExecutor.cost_for`'s `governing_stat`, the argument the live
  cast site does not pass.
- [combat.md](combat.md) — swings-to-fell, the unit `attack_damage`
  is actually felt in.
- [hud.md](hud.md) — the single-source rule this obeys: a readout may
  only show a number the game itself computed.

## Status

- ✅ **`NodePayoff`, pure and whole** (2026-09-20).
  `preview_for` / `default_consumers` / `stats_without_consumers` /
  `relevance_for`, pinned by `tests/unit/test_node_payoff.gd` (28 tests,
  81 asserts; the two mutations that matter — re-stating `bonus_amount`
  instead of re-evaluating, and claiming an unwired stat is wired — kill
  7 and 2 of them respectively): the
  consumer is called exactly twice and at exactly the two bonus levels;
  the rendered delta is not the node's `bonus_amount` for a real
  consumer; a stat with no consumer is marked `declared` rather than
  given an invented effect; every registered consumer's number really
  moves when the stat moves; a lower-is-better consumer is marked as
  such; relevance is higher for the character who owns the thing the
  stat feeds; the module's own purity is asserted against its source, and
  the two numbers it restates from elsewhere (`PLAYER_UNARMED_DAMAGE` from
  `Player.UNARMED_DAMAGE`, `FRESH_ANIMAL_CONDITION` from
  `Taming.effective_condition(1.0, 0.0)`) are pinned against their real
  sources rather than eyeballed.
- ✅ **The inert count is a test, not a claim** (2026-09-20). The
  26-granted / 20-inert figures above are recomputed from the live
  `SkillWeb` by `test_node_payoff.gd` and asserted against the module's
  own constants.
- ✅ **`WIRED_STATS` is checked against the live game** (2026-09-20).
  The test reads `scenes/player.gd` and requires each claimed-wired stat
  to really appear as a `skill_bonus("…")` read or an
  `_apply_skill_stat` branch, and requires `spell_efficiency` *not* to
  — so unwiring a stat, or wiring `spell_efficiency` up without
  correcting this doc, fails the suite.
- ⬜ **Not wired into the view.** `SkillWebView`'s tooltip still prints
  the stat name and the raw bonus; the lead wires `preview_for` into it.
- ⬜ **20 stats still inert.** This module reports them; it does not
  read them. Each is a separate change in its own system, and
  `spell_efficiency` is the cheapest of them by a distance — the
  function already takes the argument.
