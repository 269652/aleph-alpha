# Behavior DSL: composable, reusable behavior without genetics

A second, deliberately different answer to the same original question
[ethogram.md](ethogram.md) answers. That doc gets reuse from biology: a
species' receptors and valence are genome-expressed vectors, and the same
kernel scores any stimulus against them — a fly wants rot because its decay
receptor and decay valence are both high. That is a real, working answer,
and [ethogram.md](ethogram.md)'s own slice 5 investigation found its actual
limit: several body plans (fish, villagers, ants) have no vector-scored
stimulus-approach-avoid decision to express at all — a villager's "decision"
is a schedule lookup, a fish's flee is triggered by something else's strike,
an ant's forage is a round trip. Genetics could not make those reusable,
because they were never receptor decisions to begin with.

This doc answers the reuse question a second way, without that requirement:
a real, parsed, authored language whose composable unit is the **behavior
itself** — a named, reusable node a species' tree references, not a
receptor a genome expresses. `wander()` is one line, reused verbatim by
every species that ever needs to wander, whether or not it has a genome at
all. The two systems are not rivals: [ethogram.md](ethogram.md)'s kernel
becomes one *kind* of node this DSL can compose (`seek`/`flee` reuse
`Affinity`/`BehaviorKernel` verbatim, §4), sitting beside a schedule lookup
or a round-trip state machine as equals in the same tree.

## Design pillars

1. **The composable unit is a behavior, not a receptor.** A tree is built
   from named nodes — `wander`, `flee`, `seek`, `schedule`, `round_trip` —
   each a small, reusable, independently-tested primitive. Reuse comes from
   two trees referencing the *same* node, the same way two functions calling
   the same subroutine reuse it — no genome, no expression step, no
   population statistics required for a node to fire.

2. **Composition is a small, fixed, literature-grounded vocabulary.**
   Exactly four ways to combine nodes — priority, sequence, parallel, gate —
   and nothing else. This is not an invented taxonomy: it is the standard
   behavior-tree node set from the game-AI literature (see Real-world
   grounding), chosen because a fixed, small set of combinators is what
   makes a tree *readable* by someone who didn't write it, the same reason
   [npc_instructions.md](npc_instructions.md) keeps its own grammar to a
   flat if/otherwise rather than a general-purpose language.

3. **Pure structure, deferred meaning — same split as every DSL this
   project already has.** The parser (`behavior_dsl_parser.gd`) knows the
   grammar, not the atoms: an unknown node name parses fine and is only
   rejected when the executor tries to look it up, mirroring
   `spell_parser.gd`'s own explicit "knows the grammar, not the game"
   pillar. Named arguments only (`on: predator`), never positional, so
   unlike [npc_instructions.md](npc_instructions.md)'s parser this one needs
   no per-primitive signature table to convert one shape into the other —
   simpler because the surface syntax was designed for the AST it produces,
   not layered over the AST after the fact.

4. **A condition is not an action, and the catalog says so structurally.**
   Exactly [npc_instructions.md](npc_instructions.md)'s own split: a
   `CONDITION_ATOMS` registry (used only inside `gate`, returns a bool) and
   an `ACTION_ATOMS` registry (used only as a tree leaf, returns a decision
   or null). A condition used where an action belongs, or vice versa, fails
   the same way an unknown atom does — a category error, not a silent
   coercion.

5. **An atom is a wrapper, never a reimplementation.** Every action atom
   this doc ships delegates to code that already exists and is already
   tested — `Affinity`/`BehaviorKernel` for `seek`/`flee`,
   `NpcSchedule.current_entry` for `schedule`, `AntForageBehavior`'s own
   phase machine for `round_trip`. The DSL's job is giving these a common
   calling convention so they can sit in the same tree, not re-deriving
   what they already do correctly.

6. **No cost, no balance, no player authorship.** Unlike the magic DSL or
   the NPC instruction DSL, nobody plays this — it is how the game's own
   developer expresses a species' behavior, the same relationship
   `Ethogram.SPECIES`'s Dictionary literals already have to the game today,
   just textual and composable instead of baked into `.gd` source. There is
   therefore no cost function, no complexity budget, and no validator
   guarding against an overpowered script: the only reader is whoever is
   designing the next species.

## Real-world grounding

**Behavior trees are a real, specific game-AI technique, not an invented
shape.** Selector (try each child until one succeeds), Sequence (run each
child until one fails), Parallel (run every child regardless), and Decorator
(gate or transform one child) are the four node kinds behavior trees have
used since Damian Isla's account of the Halo 2 AI system (2005) popularised
them for games, and Colledanchise & Ögren's *Behavior Trees in Robotics and
AI* (2018) gives them the formal semantics this doc's executor implements
verbatim: a Sequence returns Success only if every child does and fails at
the first failure; a Selector (`priority` here, the more legible name for a
design-facing DSL) returns Success at the first child that succeeds and
Failure only if every child does. This project's own five-tier mammal
priority ladder ([ethogram.md](ethogram.md) §6) is a Selector in this exact
sense — a hard-coded one. This doc is what a design pattern most game AI
already reaches for looks like written down as an actual authored language,
rather than as GDScript `if` statements nesting the same shape by hand every
time.

**Reuse-by-subroutine is the older, plainer half of software reuse.**
[ethogram.md](ethogram.md)'s reuse mechanism is elegant but specific to
stimulus-response behaviors with a genuine population to vary across.
Ordinary subroutine reuse — the same named, tested function called from
many call sites — needs none of that, and is the actual mechanism behind
every existing DSL this project has: `spell_atom_catalog.gd`'s atoms are
reused across every enchant a player writes, `npc_instruction_primitives.gd`'s
`haul`/`gather` are reused across every instructed villager. This doc applies
that exact, well-proven mechanism to *behavior itself* rather than to spell
effects or chore primitives.

## Mechanism spec

### 0. Files

```
src/gameplay/behavior_dsl_parser.gd    ⬜ text -> AST, purely structural
src/gameplay/behavior_atom_catalog.gd  ⬜ condition/action atom registries
src/gameplay/behavior_tree_executor.gd ⬜ walks an AST against a context
```

All three are `RefCounted`, no engine dependency, no RNG — the same
pure-core discipline [ethogram.md](ethogram.md) pillar 5 states for its own
three modules, for the same reason: a tree's composition logic and an atom's
decision logic are both facts about data, testable without a scene tree.

### 1. Surface syntax

```
behavior "mammal" {
    priority {
        flee(on: predator, on: player)
        gate(above(need: thirst, threshold: 0.5)) {
            seek(on: water)
        }
        gate(above(need: hunger, threshold: 0.5)) {
            priority {
                seek(on: flesh)
                seek(on: forage)
            }
        }
        wander()
    }
}

behavior "villager" {
    priority {
        gate(above(need: hunger, threshold: 0.5)) {
            seek(on: forage)
        }
        schedule()
    }
}

behavior "ant_forager" {
    round_trip()
}
```

A file is zero or more `behavior "name" { <node> }` blocks, each holding
exactly one top-level node. A `<node>` is one of:

- **`priority { <node>... }`** — a Selector: evaluate children in order,
  return the first non-null result, or null if every child returns null.
- **`sequence { <node>... }`** — evaluate children in order; if any child
  returns null, the whole sequence returns null immediately (a real
  Sequence's fail-fast semantics); otherwise returns the *last* child's
  result.
- **`parallel { <node>... }`** — evaluate every child regardless of the
  others' results and return the Array of all results (null entries
  included) — used for a behavior that must keep ticking a background
  process (a crop digesting) alongside whatever the tree decides to do.
- **`gate(COND) { <node> }`** — a Decorator: `COND` is exactly one
  condition-atom call (`above(need: hunger, threshold: 0.5)`,
  `sensed(on: predator)`); if it evaluates false, the gate returns null
  without evaluating its child at all; if true, returns the child's result
  verbatim.
- **`IDENT(name: value, ...)`** or **`IDENT()`** — a leaf: a call to a
  registered action atom. Repeated `on: value` pairs accumulate into one
  list argument (`{"on": ["predator", "player"]}`), which is what lets
  `flee`/`seek` take one or several channels without a separate list-literal
  syntax to parse.

A value is an `ident` (a bareword, stored as a `String` — same convention
[npc_instructions.md](npc_instructions.md) uses for `item`/`need` names),
a `string`, a `number`, or `true`/`false`.

`parse(source) -> {"ok": bool, "behaviors": {name: <node-AST>}, "errors": []}`.
Same fail-closed contract as every parser in this project: an unknown node
keyword, an unclosed brace, a `gate` with anything but exactly one condition
call, or a leaf where a block was expected all fail with `"line N: ..."`,
never a crash and never a silent partial parse.

### 2. Atom catalogs

Two registries, mirroring [npc_instructions.md](npc_instructions.md)'s own
condition/action split so that using one where the other belongs is a
structural error the same way an unrecognised name is:

```gdscript
BehaviorAtomCatalog.CONDITION_ATOMS := {
    "above":  func(args, context) -> bool: ...   # needs[args.need] > args.threshold
    "sensed": func(args, context) -> bool: ...    # any stimulus carries a feature on args.on
}
BehaviorAtomCatalog.ACTION_ATOMS := {
    "wander":     func(args, context): return {"intent": "wander"}
    "flee":       func(args, context): ...  # Affinity/BehaviorKernel, away from the nearest hit
    "seek":       func(args, context): ...  # Affinity/BehaviorKernel, toward the nearest hit
    "schedule":   func(args, context): ...  # NpcSchedule.current_entry, wrapped
    "round_trip": func(args, context): ...  # AntForageBehavior's own phase, wrapped
}
```

`wander` is the one action every tree can end on and always fires — the
same universal fallback role `wander` already plays at the bottom of the
mammal ladder, now literally the same three-token leaf in any species'
text. `flee`/`seek` read `context["position"]` and `context["stimuli"]`
(the exact `{"position", "features"}` shape `Affinity`/`BehaviorKernel`
already consume — see [ethogram.md](ethogram.md) §2) and call
`BehaviorKernel.best_stimulus` with a valence of −1 (flee) or +1 (seek) on
the named channels, `attract_only` set for `seek`. Neither reads a genome
or a species record: **this is the "not based on genetics" half made
concrete** — the same ranking math [ethogram.md](ethogram.md) built, used
here as a plain computational tool rather than gated by receptor
expression. A tree can still compose a fully genome-expressed decision by
calling into that system explicitly (a future atom, `ethogram_decide`,
named and deferred below) — the two are complementary, not exclusive.

`above`/`sensed` read `context["needs"]`/`context["stimuli"]` generically
by name, which is what makes `gate(above(need: hunger, threshold: 0.5))`
identical text for a mammal and a villager: both already publish a `needs`
Dictionary shaped `{name: level}` (`CreatureNeeds.gains()`/`NpcNeeds.gains()`,
both facades over the same `Drives` clock since
[ethogram.md](ethogram.md)'s slice 3) — the condition atom does not know or
care which species it is gating.

### 3. The executor

```gdscript
BehaviorTreeExecutor.run(node: Dictionary, context: Dictionary) -> Variant
```

One recursive function, matched on `node["kind"]`, implementing exactly the
five semantics in §1 with no state of its own between calls — the tree and
the atoms are what may carry state (a leaf's own atom function can read and
write whatever it needs on `context`, the same way an ethogram wiring's
caller owns commitment). Given the same node and context, `run` always
returns the same result: a real, pinned property
(`test_running_the_same_tree_twice_gives_the_same_answer`), not merely
assumed of a function with no internal RNG.

## What the player can see

Nothing, by design, in this slice: no marker is wired to this executor yet.
The payoff is that a new species' *tree* — a few lines of text referencing
existing atoms — is now a smaller, more honest unit of work than a new
species' *code*, and that two structurally unrelated body plans (a land
mammal and a villager) already share two real nodes (`wander`, and the
`above`-gated pattern) verbatim, which the tests below prove rather than
merely claim.

## Status / mechanisms

- ⬜ `behavior_dsl_parser.gd` — surface syntax in §1, `parse()`'s fail-closed
  contract.
- ⬜ `behavior_atom_catalog.gd` — `CONDITION_ATOMS`/`ACTION_ATOMS`,
  `evaluate_condition`/`resolve_action` dispatchers failing closed on an
  unknown or wrong-slot name.
- ⬜ `behavior_tree_executor.gd` — `run()` over priority/sequence/parallel/
  gate/leaf, matching Colledanchise & Ögren's semantics.
- ⬜ `wander`/`flee`/`seek`/`above`/`sensed` atoms; `flee`/`seek` reusing
  `Affinity`/`BehaviorKernel.best_stimulus` verbatim, no genome involved.
- ⬜ `schedule`/`round_trip` atoms wrapping `NpcSchedule`/`AntForageBehavior`
  unmodified, proving a lookup and a stateful phase machine both compose
  in the same tree as the vector-scored atoms.
- ⬜ A real mammal tree and a real villager tree, parsed from the exact text
  in §1, both executed against constructed contexts, both correctly
  invoking the shared `wander`/`above` atoms — the reuse claim, tested end
  to end rather than argued.
- ⬜ Wiring any live marker (`CreatureMarker`, `NpcMarker`, `AntForagerMarker`)
  to actually run a parsed tree instead of its current hard-coded decision
  path. Deliberately not attempted here: [ethogram.md](ethogram.md)'s own
  slice 5 found that touching a live marker without a dedicated, narrowly
  scoped pass is exactly the mistake to avoid, and the same caution applies
  to a brand-new executor with zero hours of runtime behind it yet.
- ⬜ An `ethogram_decide` action atom that runs a full
  `Ethogram.wirings_for(body_plan)` list through `BehaviorKernel.decide` as
  a single tree leaf — the explicit bridge letting a species mix a fully
  genome-expressed sub-decision into an otherwise DSL-composed tree, named
  here so it is a planned seam and not a forgotten one.

## Open questions

- **Does `sequence`/`parallel` earn their place in v1, or are they
  speculative?** Every worked example above only uses `priority` and
  `gate`. Real value for `sequence` (a strict multi-step ritual) and
  `parallel` (a background process ticking alongside a decision) is
  plausible but unproven by a concrete species yet — kept because the
  literature's four-node set is what makes the vocabulary recognisable,
  not because a caller needs the other two today.
- **Where does per-node state live once a tree is shared across many
  individuals?** Every mammal *shares one parsed tree* (parsing is a
  one-time cost per species, not per individual), but `flee`/`seek`'s
  underlying `BehaviorKernel` calls are already stateless per pillar 4 of
  [ethogram.md](ethogram.md) — the open question is only for a future
  stateful atom (a cooldown, a commitment) needing genuinely
  per-individual memory the shared AST cannot hold.
- **Should the parser accept the ethogram's own wiring shape as sugar?**
  `gate(above(need: X, threshold: Y)) { seek(on: Z) }` is exactly one
  ethogram wiring `{"gate": X, "channels": [Z], "approach": "seek_food"}`
  spelled out longhand. A future terser sugar is plausible; not built
  here, so the grammar in §1 stays the one this doc's own tests check.
