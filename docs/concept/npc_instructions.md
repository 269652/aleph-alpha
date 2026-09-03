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

Concept stage. Nothing here is built — no parser, no primitive catalog, no
cost derivation, no executor, no wiring into `NpcMarker`. `npc.md`'s own
divergence note already says so twice ("no instruction DSL," listed both at
the top-level and again under "Needs and the local production economy").
This doc is the spec, written first, exactly as [dialogue.md](dialogue.md)
was before anything in its pipeline existed.

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

**Parser reuse is deliberately left open.** `spell_parser.gd`'s
`_BLOCK_KINDS` already lists `"instruct"` as a structurally-parseable block
kind (per [spell_runtime.md](spell_runtime.md), which scopes wiring it as
explicitly out of scope for *that* doc, not for this one) — but that
parser's actual grammar shape, `on EVENT(ARG): when GUARD: PIPELINE`, is a
single trigger/guard/pipeline triple, not the ordered-rule-list shape above.
Whether the instruction body extends that same parser's grammar productions
or ships as a small sibling parser reusing only its tokenizer is an
implementation decision, not specified here — the AST *shape* above is the
actual contract every other module in this doc is written against, the same
role the beat contract plays in [dialogue.md](dialogue.md).

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
the spell ones under different names. **Exact weights are left unspecified
here on purpose** — per `CLAUDE.md`'s no-eyeballed-tuning rule, they become
test-pinned constants in `npc_instruction_cost.gd` once this is implemented,
not numbers asserted in a design doc.

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
step underneath it:

- `NpcMarker` gains a new nullable field, `instruction_script` — parallel to
  the already-`null`-checked `economy` field's own pattern, so a marker with
  no assigned instruction is byte-for-byte unaffected.
- At the top of `_process`, `if instruction_script != null:` calls a new
  pure function, `NpcInstructionExecutor.evaluate(instruction_script.rules,
  context) -> Dictionary`, which walks the rule list top to bottom exactly
  as specified above and returns a Dictionary in the **same
  `{location_tag, activity}` shape** an ordinary schedule entry already has
  — so `_resolve_location` and `economy.step`'s `activity == "work"` read
  both keep working completely unmodified. When `instruction_script` is
  `null`, execution falls straight through to the existing
  `NpcSchedule.current_entry` path, unchanged.
- `context` is a flat Dictionary built the same way `SpellExecutor`'s
  caster-context is built for `evaluate_guard` — inventory counts, the
  NPC's own `NpcNeeds`-shaped hunger, nothing that isn't already live state
  — so `NpcInstructionExecutor` itself never touches a node.
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
- **No hiring UI.** `hiring_gate.gd`'s pure `can_hire` check is specified;
  the screen/flow a player uses to actually offer a wage and assign a
  script is not.
- **No relationships/trust system for NPCs.** `npc_identity.gd` has no
  relationships field today — this doc specifies the DSL that will consume
  that state once it exists; it does not build the state itself. Both the
  hiring gate and the complexity ceiling above are written against a trust
  value that is not yet real anywhere outside `Taming`'s animal-only trust.
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
  live?** `Taming.trust` is real today but is animal-only; NPC
  relationships are unbuilt. This doc can't name a concrete file for it
  because that file doesn't exist yet — blocked on relationships landing
  first, not a design gap in this doc.
- **Per-NPC script instance, or a reusable named template** assignable to
  many hired NPCs at once (the `spell_book.gd` shape, vs. a personally
  bound spell)? `npc.md`'s brief doesn't say either way.
- **`haul`'s carry-phase state** — flagged under Execution / wiring above —
  needs an actual home once `npc_instruction_effects.gd` exists; likely a
  small carrying field mirroring how `economy`'s own per-frame state
  already persists on `NpcMarker`, but not designed here.
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

- ⬜ `npc_instruction_catalog.gd` — the 2-condition/2-action primitive
  table with per-primitive base weights.
- ⬜ `npc_instruction_cost.gd` — deterministic complexity derivation over a
  parsed script; test-pinned weight constants.
- ⬜ `npc_instruction_executor.gd` — pure top-to-bottom rule evaluator,
  `evaluate(rules, context) -> {location_tag, activity}`.
- ⬜ `npc_instruction_effects.gd` — the impure `haul`/`gather` dispatch
  layer against live `NpcMarker`/`World`/`EarthChunkManager` state.
- ⬜ `hiring_gate.gd` — wage + trust-threshold `can_hire` check, and the
  separate trust-threshold complexity ceiling.
- ⬜ `npc_instruction_book.gd` — a fixed table of pre-authored example
  scripts, standing in for a real authoring UI.
- ⬜ Parser support for the ordered-rule-list grammar (extending
  `spell_parser.gd` or a sibling parser — undecided, see Grammar above).
- ⬜ `NpcMarker.instruction_script` field and the `_process` override
  branch described under Execution / wiring.
- ⬜ NPC relationships/trust state itself (`npc_identity.gd`) — a hard
  prerequisite this doc depends on but does not build.
- ⬜ Hiring UI, script-editor UI, and any integration with
  `companion_server.md`'s Tier 2 Instruction queue.
