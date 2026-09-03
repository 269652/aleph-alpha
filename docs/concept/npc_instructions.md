# NPC instructions: a task/goal/condition DSL for hired work

This is the doc [npc.md](npc.md)'s "Hiring & instruction" section has always
pointed at and never had. That section names three things in one paragraph —
"a separate instruction DSL, not the magic DSL," a task/goal/condition
grammar, and an "instruction complexity budget, analogous to spell mana
cost" — and specifies none of them further. This doc is that specification:
the grammar, the primitive catalog, how complexity is derived instead of
authored, and where it plugs into the NPC FSM that already runs every
villager's day. It is also the floor a sibling doc on another branch is
waiting on — the Scrivener hire in `companion_server.md` (currently on
`claude/companion-webserver-concept`, not yet merged to `main`) names its own
"Instruction queue" feature as blocked outright on this DSL existing, since
remotely queuing orders to a workforce presupposes the workforce can be given
orders at all.

## Status

**Updated — a first slice is real, and a second slice has closed most of
what it left open.** This doc was written first, exactly as
[dialogue.md](dialogue.md) was before anything in its pipeline existed, and
`npc.md`'s own divergence note (still accurate about everything *outside*
this doc) is what motivated it. The first pass built the parser, the
primitive registry, cost derivation, the rule evaluator, and the `NpcMarker`
wiring, red-first, with two real, deliberate divergences from what this doc
originally specified — see Grammar, Execution / wiring, and the final
Status checklist below for exactly what shipped, under what names, and why.
A second pass then built `npc_trust.gd` (a minimal, deliberately
player-only trust scalar — not the full NPC-NPC relationship web), a real
per-NPC `npc_inventory.gd` wired into `NpcMarker`, `hiring_gate.gd`, and
`npc_instruction_effects.gd` (the impure `haul`/`gather` dispatch, real for
stone/iron/gold/berries, honestly unsupported for wood — see its own Status
entry below for why). Still unbuilt: the script book, any actual
wage-payment flow, hiring/script-editor UI, and — the reason none of the
above is reachable in a live game yet — nowhere on a real `NpcIdentity`/
`NpcMarker` actually holds a live trust value for `hiring_gate.gd` to read.

## Design pillars

1. **Small composable primitives, cost derived, never authored.** Exactly
   [magic.md](magic.md)'s defining constraint, restated for a different
   domain: there is no field anywhere in the grammar where a player writes
   down "this instruction costs X." A script's complexity is a deterministic
   function of which condition/action primitives it uses and how many rules
   it has — the DSL literally cannot express a free, unlimited routine,
   because there is nowhere in the syntax to say so.
2. **If/otherwise, not a programming language.** `npc.md`'s own worked
   example — "if inventory has >20 wood, haul to base; otherwise chop
   nearest tree" — is the whole shape of a rule. No boolean `AND`/`OR`
   nesting, no loops, no variables. This is not an arbitrary first-pass
   cut to be lifted later; it is the actual design (see Real-world
   grounding below for why staying this impoverished is the point, not a
   placeholder for something richer).
3. **A standing routine, not a one-shot cast.** A spell resolves once,
   instantly, on a keypress. An instruction is a script an NPC re-evaluates
   continuously against changing world state — an inventory count, a need
   level — for as long as it's assigned. There is no "guard checked once at
   cast time" moment here; every relevant tick or replan re-checks every
   rule from the top.
4. **Bound by the same simulation as everyone else.** An instructed NPC
   still walks at `WALK_SPEED`, still has finite inventory and real
   production yields, still can't act on a resource that isn't actually
   near it. The DSL can select *what* an NPC pursues; it cannot buy around
   how long that takes or what it's allowed to hold — the instruction-side
   mirror of magic.md's "a spell still has to land."
5. **Hiring gates on relationship, graded — not a boolean, not gold alone.**
   `npc.md` is explicit that "a stranger won't work for you at any price."
   Both being hirable at all and how much instruction complexity an NPC
   will tolerate read the *same* trust value at two different thresholds,
   the way [taming.md](taming.md#5-trust-as-a-relationship-not-a-meter)'s
   single `trust` float already gates both following and guarding at two
   named constants rather than needing two separate meters.
6. **Pure core, thin glue.** Parsing, the primitive catalog, cost
   derivation, and the top-to-bottom rule evaluator are all
   `RefCounted` modules taking and returning plain Dictionaries, unit-tested
   with no engine dependency — the same boundary
   [dialogue.md](dialogue.md)'s pillar 5 and the magic DSL's
   parser/catalog/cost/executor split both already establish as house
   style. Only turning a resolved action into an actual NPC-location/
   inventory change touches a live node.

## Real-world grounding

**Standing orders to a hired hand.** Before radios or phones, a farmer who
could not personally supervise a hired hand for a full working day still
needed the work done correctly while unattended — the historical answer was
a short list of standing conditional orders, given once, checked by the hand
against whatever they found: *if the trough is low, fill it before anything
else; otherwise muck the stalls; if it rains before noon, bring the tools in
first.* Nobody wrote a general-purpose instruction manual for this — a hand
capable of executing a genuinely complex, deeply-branching program was not
what was being hired, and a routine that tried to anticipate every
contingency was worse than a hand exercising ordinary judgment on anything
the list didn't cover. The list stayed short and conditional-shaped because
that's the actual expressive range a standing order needs: a handful of
checkable facts, a handful of jobs, "otherwise" for the rest.

**If-this-then-that home automation.** The modern version of the same
constraint shows up in every consumer smart-home rule system (Nest, Hue,
IFTTT): the player-facing tier is deliberately a flat trigger → action pair,
not a scripting language, even though the underlying platform could support
one. This isn't a UI limitation — usability research on trigger-action
programming consistently finds that once a homeowner's rules start chaining
multiple triggers or nesting conditions, the automations produce interactions
the author didn't predict and can no longer reason about by reading the rule
list. The single condition → single action shape isn't the beginner tier of
a richer language; it's the tier that stays legible to the person who wrote
it, which is exactly [magic.md](magic.md)'s "keeps players from scripting an
NPC into an absurdly optimal, game-breaking routine" concern restated as a
*comprehension* problem rather than only a balance one — an instruction
script the player themselves can't predict the behavior of is a design
failure independent of whether it's also overpowered.

Both analogies land on the identical shape `npc.md`'s own example already
uses: a short, flat list of *condition → action*, evaluated in order, with
an explicit fallback. That is not a coincidence this doc is reverse-engineering
— it's why that shape is specified below as the actual grammar, not loosened
into something more expressive.

## Grammar & first-pass primitives

**This is a first slice, not the final language.** Two conditions, two
actions, no nesting. What's explicitly *not* here is listed under Non-goals
below, not silently dropped.

**Script shape.** A script is an ordered list of rules, each
`{condition, action}`, evaluated top to bottom every planning tick; the
first rule whose condition holds wins. A rule with `condition: null` is the
"otherwise" catch-all and, if present, must be last.

**Conditions (exactly 2, v1):**

- `inventory_at_least(item, count)` — true if the NPC's/household's
  inventory count of `item` is `>= count`.
- `need_above(need, threshold)` — true if a named need (e.g. `hunger`, the
  same `NpcNeeds`-shaped signal `npc.md`'s "Needs and the local production
  economy" section specs) is above `threshold`.

**Actions (exactly 2, v1):**

- `haul(item, destination_tag)` — go to the nearest source of `item` and
  carry it to `destination_tag`.
- `gather(resource_tag)` — go to the nearest instance of `resource_tag` and
  perform its default gather action.

**Built as `src/world/npc_instruction_primitives.gd`** — a pure static
module (no instance state, `creature_behavior.gd`/`dialogue_context.gd`'s
static-module convention rather than the parser's instance-based one, since
there's nothing to carry between calls) holding both condition functions
(`inventory_at_least`/`need_above`, each `(args, frame) -> bool`) and both
action functions (`haul`/`gather`, each `(args) -> Dictionary`, an
unexecuted action descriptor), plus `evaluate_condition`/`resolve_action`
dispatchers that fail closed to `false`/`{}` on an unrecognised `fn`. This
is the module the doc's original "primitive table" language was pointing at
before the weights split out into `npc_instruction_cost.gd` below — there is
no separate `npc_instruction_catalog.gd`.

**Worked example**, the same routine `npc.md`'s own paragraph describes:

```
instruct "haul_and_forage" {
    if inventory_at_least(wood, 20): haul(wood, base)
    if need_above(hunger, 0.7): gather(berries)
    otherwise: gather(wood)
}
```

which parses to the flat Dictionary/Array shape every pure module below
actually consumes — no object references, matching `spell_parser.gd`'s own
`{kind, name, rules}` AST convention:

```gdscript
{
  "kind": "instruct",
  "name": "haul_and_forage",
  "rules": [
    {"condition": {"fn": "inventory_at_least", "args": {"item": "wood", "count": 20}},
     "action":    {"fn": "haul", "args": {"item": "wood", "destination_tag": "base"}}},
    {"condition": {"fn": "need_above", "args": {"need": "hunger", "threshold": 0.7}},
     "action":    {"fn": "gather", "args": {"resource_tag": "berries"}}},
    {"condition": null,
     "action":    {"fn": "gather", "args": {"resource_tag": "wood"}}},
  ],
}
```

**Parser reuse — resolved.** `spell_parser.gd`'s `_BLOCK_KINDS` lists
`"instruct"` as a structurally-parseable block kind, but its actual grammar
shape (`on EVENT(ARG): when GUARD: PIPELINE`, a single trigger/guard/pipeline
triple) never matched the ordered-rule-list shape above, so it was not
extended. `src/world/npc_instruction_parser.gd` ships as a small sibling
parser instead, tokenizer/cursor/`_expect`/`_fail` conventions borrowed from
`spell_parser.gd`'s house style but with its own grammar productions. One
detail worth recording here rather than only in the code: the surface syntax
above takes *positional* arguments (`inventory_at_least(wood, 20)`) but the
AST needs *named* ones (`{"item": "wood", "count": 20}`), so the parser owns
a private per-primitive signature table (name → ordered `{name, type}`
params) to do that conversion — currently living inside
`npc_instruction_parser.gd` itself, not in `npc_instruction_catalog.gd`
(see Complexity budget below for why that module didn't end up existing as
such). The AST *shape* above remains the actual contract every other module
in this doc is written against, the same role the beat contract plays in
[dialogue.md](dialogue.md); `NpcInstructionParser.parse(source) -> {ok, ast,
errors}` fails closed (never a crash) on an unknown primitive name, a
primitive used in the wrong slot, wrong arg count, or wrong arg type.

## Complexity budget

Same constraint as magic's mana cost, restated for a domain with no
magnitude/duration axis to derive from. `npc_instruction_cost.gd` computes
one number from the parsed AST alone — nothing in the grammar can set it
directly:

- **A per-rule weight.** Every rule in the list adds to the total,
  independent of what it does — a five-rule script costs more than a
  two-rule one purely for having more branches, which is what keeps a
  script from creeping toward an exhaustively-optimal decision tree one
  "just one more case" at a time.
- **A per-primitive weight**, read from `npc_instruction_catalog.gd`'s own
  `{condition|action -> base_weight}` table. Action primitives weigh more
  than condition primitives — a routine that *does* more distinct kinds of
  work is a materially smarter (and more valuable) hire than one that
  merely checks more facts before doing the one thing it always does.
- **A rarity multiplier** on the primitive's own resource/item/tag argument
  — hauling a common item costs less than hauling a scarce one, the same
  "rarer atoms cost more" lever `spell_atom_catalog.gd`'s tiering already
  applies to spells.

There is no `mag_ref`/`dur_ref` pair to borrow from the spell side, because
an instruction has no single-cast magnitude or duration — rule-count and
primitive-rarity are this domain's own reference dimensions, not a reuse of
the spell ones under different names.

**Built as `src/world/npc_instruction_cost.gd`**, with the weights this
section originally left open now real, test-pinned constants (not asserted
here — `test_npc_instruction_cost.gd` pins two full worked-example totals,
e.g. this doc's own `haul_and_forage` script costs exactly `8.5`, and fails
if any constant drifts): `RULE_WEIGHT = 1.0`, `CONDITION_WEIGHT = 0.5`,
`ACTION_WEIGHT = 1.5` (three times a condition's weight, per "actions weigh
more than conditions" above), and a `_RESOURCE_RARITY` table
(`wood`/`berries` = `1.0`, `stone` = `1.2`, `iron` = `1.5`, `gold` = `2.0`,
anything unlisted defaulting to `1.0` — common, not free, not an error).
There is no separate `npc_instruction_catalog.gd`: this rarity/weight table
lives inline in `npc_instruction_cost.gd` with a doc comment naming it as
that future module's stand-in, so if `npc_instruction_catalog.gd` is ever
actually split out, this is the table that moves there.

**What the number gates against is not a per-cast resource.** Mana recharges
and is spent per cast; an instruction doesn't "cast," it runs continuously,
so there's no natural recharging pool to spend it from. Instead, the
complexity total is checked once, at assignment/reassignment time, against a
**ceiling read from the same trust/relationship scalar that gates hiring in
the first place** (see Execution / wiring below) — a stranger you can barely
persuade to work for you tolerates only a trivial one-or-two-rule script; an
NPC whose quest you completed, or whose child you helped, tolerates
something closer to the worked example above. This is the graded-threshold
shape [taming.md](taming.md#5-trust-as-a-relationship-not-a-meter) already
established for a single trust float gating two different behaviors at two
different named constants, applied here as the *actual* mechanism behind
`npc.md`'s "instruction complexity budget," rather than the mana-like
resource the phrase alone might suggest.

## Execution / wiring

**The real seam, not a hypothetical one.** Every villager's day already runs
through one function: `NpcMarker._process(delta)` in
`src/rendering/npc_marker.gd`. Each frame it lazily (re)generates the day's
schedule (`_planner.plan_day`, defaulting to the deterministic
`NpcPlanner.FakeNpcPlanner`), reads the entry that applies right now
(`NpcSchedule.current_entry(schedule, _current_hour())`), resolves that
entry's `location_tag` to a world position (`_resolve_location`), and walks
toward it (`position.move_toward(target, WALK_SPEED * delta)`) before
stepping `economy` with `entry.get("activity", "") == "work"` as the working
flag.

An instruction script overrides that lookup, not the walking or the economy
step underneath it. **Built, with one deliberate contract change from what
this section originally specified** — recorded here rather than left as a
silent mismatch between doc and code:

- `NpcMarker` gains a new nullable field, `instruction_script` — parallel to
  the already-`null`-checked `economy` field's own pattern, so a marker with
  no assigned instruction is byte-for-byte unaffected. Holds the parsed AST
  `NpcInstructionParser.parse(source)["ast"]` produces directly.
- At the top of `_process`, `if instruction_script != null:` calls
  **`NpcInstructionEvaluator.evaluate(instruction_script, frame) ->
  action_or_null`** (`src/world/npc_instruction_evaluator.gd`) — **not**
  the `NpcInstructionExecutor.evaluate(rules, context) -> {location_tag,
  activity}` this section originally named. The evaluator walks the rule
  list top to bottom exactly as specified above, but returns the matched
  rule's *raw primitive action descriptor* (`npc_instruction_primitives.gd`'s
  own `{"fn": "haul"/"gather", ...}` shape) rather than an already-adapted
  schedule entry, or `null` if nothing matched (including the
  no-`otherwise` case). Renamed deliberately, not accidentally: the shape
  genuinely differs, and reusing this doc's planned `executor` name for a
  different contract would have left doc and code silently disagreeing.
  `NpcMarker` itself does the `{location_tag, activity}` adaptation, in a
  new private helper, `_entry_for_instructed_action(action) -> Dictionary`,
  right next to `_resolve_location` — reusing its existing tag lookup, no
  new spatial-query layer — so `_resolve_location` and `economy.step`'s
  `activity == "work"` read both keep working completely unmodified either
  way. A `null` `instruction_script`, or a `null` `evaluate()` result, falls
  straight through to the existing `NpcSchedule.current_entry` path,
  unchanged — the fallback contract this section promised is intact even
  though the module boundary moved.
- The `frame` passed in (named `context` in this section's first draft) is
  built by a new `NpcMarker._instruction_frame()` helper: `{"inventory": {},
  "needs": {"hunger": economy.needs.hunger}}` — `inventory` is honestly left
  empty rather than stubbed, since no per-NPC/household inventory system
  exists anywhere in the codebase yet (the primitives already fail-open on a
  missing key, so an always-empty `inventory` is truthful, not a workaround).
  Building that inventory system is real, separate, unbuilt scope.
- This is exactly the shape `NpcMarker.set_planner` already establishes as
  this codebase's own convention for "swap in a different behavior source,
  default preserves old behavior for anyone who doesn't opt in" — a
  planner swaps the whole day at day-rollover grain; an instruction script
  overrides specific decisions at tick grain, on top of (not instead of) an
  NPC that still has its own autonomous daily life. The closer structural
  analog for the evaluator itself is `CreatureBehavior.decide(context: Dictionary)
  -> Dictionary` in `src/gameplay/creature_behavior.gd` — a pure per-tick
  decision function over a context Dictionary — not `spell_targeting.gd`'s
  single-shot resolve-and-done query.

**Turning a resolved action into a real effect is the impure edge**, mirroring
`spell_atom_effects.gd`'s role exactly: `npc_instruction_effects.gd` takes
`{fn, args}` plus the live `NpcMarker`/`World`/`EarthChunkManager` and
actually moves inventory or performs a gather, using whatever
"nearest-X-near" spatial query the world already exposes for that resource
(the same convention `EarthChunkManager.nearest_liftable_stone_near`/
`fruit_near` already establish — no new spatial-query shape needed). One
detail worth being honest about here rather than glossing over: `haul` is
not a single-tick action — going to fetch an item and then carrying it to a
destination are two different phases, and a pure `evaluate()` call re-run
fresh every tick has nowhere obvious to keep "am I currently carrying it"
across ticks unless that phase is read from real state (most naturally
whatever inventory-carrying field `npc_instruction_effects.gd`'s own
mutation already left behind, mirroring how `economy`'s own state persists
across frames today). This is flagged, not resolved — see Open questions.

**Hiring is a separate gate from the DSL itself.** `hiring_gate.gd` is a new
module answering only "may this instruction even be assigned to this NPC" —
an ongoing wage (a genuinely new, negotiated payment, **not**
`VillageWages`'s existing flat subsistence draw, which `npc.md` is explicit
is "not hiring: nobody negotiates, nobody chooses an employer") plus the
trust/relationship threshold from Design pillar 5. It gates *whether*
`instruction_script` may be set on a given `NpcMarker` at all; the
complexity ceiling above gates *how elaborate* a script may be once hiring
already succeeded — two checks against the same underlying trust value, at
two different named thresholds, not one check reused for two purposes.
Child-NPCs (`players.md`) bypass only the relationship half of this gate,
per `npc.md`'s own stated exception — the wage still applies.

## Non-goals / explicitly deferred

Stated plainly, matching this project's own honest-scope-cut convention:

- **No boolean composition beyond one condition per rule.** No `AND`/`OR`,
  no nested conditions — see Real-world grounding above for why this is the
  design, not a first-pass gap.
- **No loops, no variables, no more than these 4 primitives.** The
  catalog grows later; this is deliberately the smallest slice that
  reproduces `npc.md`'s own worked example exactly.
- **No player-facing script-editor UI.** Scripts are authored as raw DSL
  text for now, the same "fixed book before an editor" bootstrap
  `spell_book.gd` already used for magic —
  `npc_instruction_book.gd` would hold a small table of pre-authored
  example scripts, assignable before any real authoring tool exists.
- **No hiring UI.** `hiring_gate.gd`'s pure `can_hire`/`can_assign_script`
  checks are now built and tested (see Status below); the screen/flow a
  player uses to actually offer a wage and assign a script is not.
- **No full relationships system for NPCs, and no LIVE trust value yet.**
  `npc_trust.gd` now exists (see Status below) as the smallest real thing
  that can unblock hiring — a single player-trust scalar both gates read —
  but it is a pure model taking `trust` as a plain float parameter, not a
  field anywhere on a real NPC: `npc_identity.gd` still has no
  `trust`/relationships field today, and nothing yet raises or lowers
  trust through quests or dialogue. `npc.md`'s full "relationships to
  other NPCs" web remains entirely unbuilt and out of this doc's scope, as
  originally noted — this doc's own trust scalar is deliberately narrower
  (player-only, single-player game, no relationship graph).
- **No integration with `companion_server.md`'s Tier 2 Instruction queue.**
  That doc's own feature is explicit that it has "no floor to stand on"
  until this DSL exists — this doc is that floor, not the consumer built
  on top of it.
- **No LLM involvement anywhere in this mechanism.** `npc.md` elsewhere
  imagines LLM-authored personalities and daily plans, but an instruction
  script itself is player-authored text evaluated by the same deterministic
  pure functions every other module in this doc already uses — the
  "entirely offline system" framing [dialogue.md](dialogue.md) opens with
  applies here too.
- **No new physical-simulation mechanics.** Real travel time, real
  inventory capacity, real production yields are reused exactly as they
  already exist; nothing here adds a new constraint layer on top of them.
- **No AST-derived gold cost to *assign* a script.** magic.md's 2026-08-24
  brainstorm already generalizes a gold-priced-to-compile gate across all
  three DSL surface forms (spell/enchant/instruct) as "a property of the
  AST, not of which context consumes it" — whether that gate also applies
  here, on top of the ongoing wage, is left to Open questions rather than
  specified as part of this first pass.

## Open questions

- **Exact `npc_instruction_cost.gd` weights** — per-rule overhead,
  per-primitive base weights, the rarity multiplier's shape — need a
  first-pass numeric design once this is actually being implemented, the
  same deferral magic.md's own Open questions section already made for its
  atom cost formula.
- **Does assigning a script also cost gold via the shared AST-compile gate**
  (magic.md 2026-08-24), on top of the ongoing wage, or is the wage the
  only cost an instruction ever carries? Left open above.
- **Where does the trust scalar this doc's two gates both read actually
  live, on a real NPC?** `npc_trust.gd` (see Status below) is now the real
  pure model both gates read, resolving *what* the scalar means and how
  it's thresholded — but it still doesn't answer *where a live value is
  stored*: `NpcIdentity`/`NpcMarker` carry no `trust` field, so every
  caller today has to supply `trust` as a plain float from nowhere in
  particular. `Taming.trust` remains real but animal-only. Narrowed from
  "blocked on relationships landing first" to a smaller, more concrete
  remaining gap: a `trust: float` field on `NpcIdentity` (or `NpcMarker`)
  plus whatever raises/lowers it through quests/dialogue — not a design
  gap in this doc, just genuinely unbuilt.
- **Per-NPC script instance, or a reusable named template** assignable to
  many hired NPCs at once (the `spell_book.gd` shape, vs. a personally
  bound spell)? `npc.md`'s brief doesn't say either way.
- **`haul`'s carry-phase state** — flagged under Execution / wiring above.
  `npc_instruction_effects.gd` now exists (see Status below) but
  deliberately only implements the FETCH half (find a real source, collect
  it into inventory); actually carrying the result on to `destination_tag`
  across multiple ticks still needs an actual home, likely a small
  carrying field mirroring how `economy`'s own per-frame state already
  persists on `NpcMarker` — still not designed, let alone built.
- **What happens when no rule matches** (no authored `otherwise`)? Falling
  back to the ordinary planner-produced schedule entry for that tick (the
  same graceful-degrade shape a `null` `instruction_script` already gets)
  seems like the natural default, but isn't pinned here.
- **Does the complexity ceiling replenish as trust grows**, letting an
  already-assigned script that was authored right at the current ceiling
  become "affordable" for a larger one later without player action, or
  does a bigger script always require deliberate reassignment? Open.
- **One active script per NPC, or one per time-block** (mirroring the
  planner's own 4-entry day) eventually? v1 as specified assumes exactly
  one script, evaluated every tick, for the whole day.

## Status

- ✅ `npc_instruction_parser.gd` — the ordered-rule-list grammar, shipped
  as a small sibling parser (not an extension of `spell_parser.gd`, see
  Grammar above); positional surface syntax → named-arg AST, fails closed
  on any malformed input. `test_npc_instruction_parser.gd`, 28 tests.
- ✅ `npc_instruction_primitives.gd` — the 2-condition/2-action registry
  (`inventory_at_least`, `need_above`, `haul`, `gather`) plus dispatchers.
  **There is no separate `npc_instruction_catalog.gd`** — this module holds
  the primitive functions; their weights live in `npc_instruction_cost.gd`
  instead (see below). `test_npc_instruction_primitives.gd`, 20 tests.
- ✅ `npc_instruction_cost.gd` — deterministic complexity derivation over a
  parsed script; test-pinned weight constants (`RULE_WEIGHT`,
  `CONDITION_WEIGHT`, `ACTION_WEIGHT`, a resource-rarity table) — see
  Complexity budget above for the actual values. No cap/reject enforcement
  yet — this file only derives the number; a ceiling check is still
  `hiring_gate.gd`, below. `test_npc_instruction_cost.gd`, 11 tests.
- ✅ `npc_instruction_evaluator.gd` — pure top-to-bottom rule evaluator.
  **Not `npc_instruction_executor.gd`, and not this section's originally
  planned `evaluate(rules, context) -> {location_tag, activity}` contract**
  — the real, shipped contract is `evaluate(parsed_script, frame) ->
  action_or_null`, returning a raw primitive action descriptor; the
  `{location_tag, activity}` adaptation happens in `NpcMarker` itself (see
  Execution / wiring above for the full reasoning).
  `test_npc_instruction_evaluator.gd`, 6 tests, including this doc's own
  worked example end to end.
- ✅ `NpcMarker.instruction_script` field and the `_process` override
  branch — built exactly as described (with the evaluator-contract change
  above), plus `_instruction_frame()` and `_entry_for_instructed_action()`
  helpers. Regression-gated against `test_npc_planner.gd` (12/12) and
  `test_npc_economy.gd` (39/39) — an NPC with no instruction script is
  unaffected. `test_npc_marker.gd`, 17/17 (4 new, 13 pre-existing).
- ✅ `npc_trust.gd` — a minimal player-NPC trust scalar (docs/concept/
  npc_instructions.md's own Design pillar 5), built as the smallest real
  thing that can unblock hiring: a single `[0,1]` scalar for how much ONE
  NPC trusts THE PLAYER, not `npc.md`'s full "relationships to other NPCs"
  web (this is a single-player game — no NPC-NPC relationship graph is
  needed or built). Mirrors `pet_loyalty.gd`'s shape (a baseline const,
  named thresholds, pure functions) but deliberately not its numbers:
  `BASELINE_TRUST := 0.2` sits BELOW `HIRE_THRESHOLD := 0.5` (the opposite
  relationship `pet_loyalty.gd`'s `BASELINE_LOYALTY`/`FOLLOW_THRESHOLD`
  have), because `npc.md` is explicit "a stranger won't work for you at any
  price" — a freshly-met NPC must never itself clear the hire gate.
  `complexity_ceiling_for(trust)` implements the Complexity budget section's
  ceiling as an actual CONTINUOUS function of trust (linear from
  `MIN_COMPLEXITY_CEILING := 3.0`, grounded in
  `npc_instruction_cost.gd`'s own `RULE_WEIGHT+CONDITION_WEIGHT+ACTION_WEIGHT`
  for one trivial rule, at `HIRE_THRESHOLD`, up to
  `MAX_COMPLEXITY_CEILING := 10.0`, comfortably above this doc's own
  8.5-cost worked example, at full trust) rather than a second boolean
  gate, per this section's own "a stranger... tolerates only a trivial
  one-or-two-rule script... tolerates something closer to the worked
  example" language. `test_npc_trust.gd`, 9 tests, pinning
  baseline-is-not-hireable and 3+ points on the ceiling curve.
- ✅ `npc_inventory.gd` — the smallest real per-NPC/household inventory:
  a plain `item_id -> int` Dictionary plus pure static `add`/`remove`/
  `count_of` helpers (mirroring `npc_instruction_primitives.gd`'s own
  pattern), NOT a general-purpose inventory system (no capacity, stacking,
  UI, or shop/crafting integration). `add`/`remove` are pure (return a new
  Dictionary) and `remove` fails closed — clamped at 0, never negative,
  never crashes on removing more than held. `test_npc_inventory.gd`, 12
  tests. **Wired into `NpcMarker`**: a new `inventory := {}` field —
  deliberately NOT null-checked like `economy`/`instruction_script`, since
  an empty inventory is a valid real state, not an absence — that
  `_instruction_frame()` now reads directly instead of always reporting
  `{}`. `inventory_at_least` can finally be truthfully exercised against
  real held items in a live `NpcMarker`. `test_npc_marker.gd`, 20/20 (3 new
  tests plus a stale-comment fix on the pre-existing no-rule-matches test);
  regression-checked against `test_npc_planner.gd` (12/12) and
  `test_npc_economy.gd` (39/39).
- ✅ `hiring_gate.gd` — the wage + trust-threshold `can_hire` check, and
  the separate trust-threshold `can_assign_script` complexity-ceiling
  check, both pure and reading the same underlying `npc_trust.gd` scalar
  at two independent thresholds. `can_hire(trust, wage_offered,
  minimum_wage)` is true only if trust clears `NpcTrust.HIRE_THRESHOLD` AND
  `wage_offered` clears `minimum_wage` — a stranger cannot be bought at any
  wage, and a hireable NPC still won't work for nothing.
  `can_assign_script(trust, script_cost)` is true only if the caller's own
  `npc_instruction_cost.gd`-derived `script_cost` fits under
  `NpcTrust.complexity_ceiling_for(trust)` — this module never re-derives
  cost, only checks it. `default_minimum_wage()` is a documented fallback
  floor anchored to `VillageWages.subsistence_wage() * 2`, so a negotiated
  hire wage always clears mere subsistence (`npc.md`: hiring is "a
  genuinely new, negotiated payment, not `VillageWages`'s existing flat
  subsistence draw"). `test_hiring_gate.gd`, 9 tests, including
  below-threshold trust unable to hire at any wage and an over-budget
  script rejected even at full trust. **Not wired to a live NPC yet** — see
  the honest gap list below.
- 🚧 `npc_instruction_effects.gd` — the impure `haul`/`gather` dispatch
  layer against live `world`/`EarthChunkManager` state, for the resource
  ids that DO have a real backing spatial query: stone/iron/gold via
  `EarthChunkManager.nearest_liftable_stone_near` (consumed via
  `stone.queue_free()` directly — the SAME convention `scenes/player.gd`'s
  own `_try_pick_stone_into_hand` already uses, not `LiftableStone.pick_up`,
  which expects an Item/Inventory-class picker `NpcMarker.inventory`'s
  plain Dictionary doesn't satisfy), and berries via
  `EarthChunkManager.harvest_peak_fruit_near` (no separate consume step
  needed at all — that query is read-only by design, since `hanging_at` is
  a pure function of elapsed time, not a depletable stock). **Wood is
  deliberately UNSUPPORTED**: no real nearest-tree/wood query exists
  anywhere in this codebase (`ChoppableTree`/`TreeRenderer` carry no
  chunk-coordinate or `EarthChunkManager` reference at all — the same gap
  `docs/progress.md`'s "Land Health" entry already documents for a
  different feature), so `dispatch()` returns a clear
  `{"ok": false, "reason": "unsupported_resource"}` for wood rather than
  crashing or silently no-op'ing — meaning this doc's own canonical worked
  example (`haul(wood, base)`) still cannot execute against live world
  state through this module. `dispatch()` also only implements `haul`'s
  FETCH half (find a real source, collect it into inventory) — carrying
  the result on to `destination_tag` is still the flagged, unresolved
  multi-tick carry-phase question below, not attempted.
  `test_npc_instruction_effects.gd`, 10 tests, covering the stone and
  berries paths against a duck-typed stub world, wood failing closed via
  both `gather` and `haul`, a null-world crash guard, and a purity check.
  **Not yet wired into `NpcMarker._process` or anywhere else live** —
  `_entry_for_instructed_action`'s tag-lookup stand-in is still what
  actually runs; this module exists and is tested but nothing calls it yet.
- ⬜ `npc_instruction_book.gd` — a fixed table of pre-authored example
  scripts, standing in for a real authoring UI.
- 🚧 NPC relationships/trust state itself (`npc_identity.gd`) — `npc_trust.gd`
  above is real and tested, but nothing actually HOLDS a live trust value
  anywhere: `NpcIdentity`/`NpcMarker` carry no `trust` field, both
  `npc_trust.gd` and `hiring_gate.gd` take `trust` as a plain float
  parameter today, not read from any real NPC, and nothing yet raises or
  lowers it through quests/dialogue (`npc.md`: "an NPC whose quest you
  completed... will [work for you]"). Full NPC-NPC relationships (the
  "relationships to other NPCs" web `npc.md`'s Identity section wants)
  remain entirely unbuilt and out of this doc's scope, as originally noted.
- ⬜ Hiring UI, script-editor UI, an actual wage-PAYMENT flow (an ongoing
  negotiated draw distinct from `VillageWages`'s subsistence levy — nothing
  pays it out even though `hiring_gate.gd`'s check is real), and any
  integration with `companion_server.md`'s Tier 2 Instruction queue.
