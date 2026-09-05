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

**`context["local_atoms"]`** (optional, `{name: Callable(args, context)}`),
added when wiring the first live marker (§4), is how a caller registers its
own bespoke, stateful atoms without teaching the shared, reusable
`behavior_atom_catalog.gd` anything about that caller's class. A local
atom is checked first and, if present, entirely replaces a same-named
shared atom for that call rather than running both — a real, deliberate
override, not a merge. This is the seam pillar 5 always implied but §2
didn't yet need: `flee`/`seek`/`schedule`/`round_trip` are pure enough to
live in the shared catalog forever, but a specific marker's own private,
side-effecting motor program (`AmbientFlyerMarker._step_ground_forage`,
say) has no business there, and reusing it means calling it, not
reimplementing it as catalog data.

### 4. Wiring a live marker: the robin

The first proof that a parsed tree can actually replace a marker's
decision path, not just be executed in a test. `AmbientFlyerMarker`'s
robin runs a real script:

```
behavior "robin" {
    priority {
        songbird_flush()
        bird_courtship()
        ground_forage()
    }
}
```

— the exact precedence its `_process` already gave robin (flush off the
player outranks a pair interaction, which outranks foraging), now data
instead of three sequential `if`s. `songbird_flush`/`bird_courtship`/
`ground_forage` are `local_atoms` (§3): thin, marker-bound wrappers around
`_step_songbird_flight_response`/`_step_pair_interactions`/
`_step_ground_forage`, reused by calling them exactly as `_process`
already did — replicating which two calls animate the wings themselves
and which one doesn't, and the `_movement == null` guard
`_step_ground_forage`'s own internals need, precisely rather than
approximately. None of the three step functions changed at all.

Only robin. `BEHAVIOR_TREE_SPECIES` gates this per species, and every
other flyer — sparrow included, despite ground-foraging by the identical
mechanism — keeps its original, direct dispatch untouched. Wiring one
species at a time, proven correct against its own existing tests before
the next, is the same discipline [ethogram.md](ethogram.md)'s own slices
used; sparrow is a real, named next candidate, not a gap.

The tree is parsed once, into a static cache, and shared by every robin —
parsing is a species-level cost, never a per-individual one, closing the
open question §1 raised about exactly this.

## What the player can see

Nothing different for a robin, by design: §4 is a behaviour-preserving
migration, pinned by the same flush/courtship/forage tests that already
existed before it, exactly as every ethogram.md slice held itself to the
same bar. The payoff is structural rather than visible: a robin's own
top-level priority is now a few lines of text referencing existing atoms
instead of three sequential `if`s baked into a 3000-line file, and a new
species' tree is a smaller, more honest unit of work than a new species'
code. The mammal/villager reuse claim (§1's worked examples, `wander` and
the `above`-gated pattern shared verbatim by two species with no code, no
genome, and no body plan in common) remains proven only in tests, not yet
wired to either's live marker.

## Status / mechanisms

- ✅ `behavior_dsl_parser.gd` — surface syntax in §1, `parse()`'s fail-closed
  contract (`test_behavior_dsl_parser.gd`, 30 tests: every node kind,
  repeated-key list accumulation, nested composition, multiple behaviour
  blocks per file, comments, nine distinct fail-closed error cases).
- ✅ `behavior_atom_catalog.gd` — `CONDITION_ATOMS`/`ACTION_ATOMS`,
  `evaluate_condition`/`resolve_action` dispatchers failing closed on an
  unknown or wrong-slot name (`test_behavior_atom_catalog.gd`, 29 tests).
- ✅ `behavior_tree_executor.gd` — `run()` over priority/sequence/parallel/
  gate/leaf, matching Colledanchise & Ögren's semantics
  (`test_behavior_tree_executor.gd`, 20 tests).
- ✅ `wander`/`flee`/`seek`/`above`/`sensed` atoms; `flee`/`seek` reusing
  `Affinity`/`BehaviorKernel.best_stimulus` verbatim, no genome involved
  (pinned directly: `test_flee_and_seek_never_read_a_genome_or_species`).
- ✅ `schedule`/`round_trip` atoms wrapping `NpcSchedule`/`AntForageBehavior`
  unmodified, proving a lookup and a stateful phase machine both compose
  in the same tree as the vector-scored atoms.
- ✅ A real mammal tree and a real villager tree, parsed from the exact text
  in §1, both executed against constructed contexts, both correctly
  invoking the shared `wander`/`above` atoms — the reuse claim, tested end
  to end rather than argued
  (`test_a_hungry_villager_seeks_forage_through_the_same_gate_the_mammal_used`
  is the one worth reading by name: same gate, same tokens, two species
  that share no code, no genome, and no body plan). 79 tests total across
  the three modules.
- ✅ `context["local_atoms"]` — a caller-registered `{name: Callable}` map,
  checked before the shared catalog and entirely replacing a same-named
  shared atom when present (`test_behavior_tree_executor.gd`, 5 tests).
- ✅ **The first live marker, wired**: `AmbientFlyerMarker`'s robin runs a
  real parsed tree (`songbird_flush` → `bird_courtship` → `ground_forage`,
  §4) via three `local_atoms`, each a thin wrapper around the exact
  existing step function it replaces at the call site. Species-gated
  (`BEHAVIOR_TREE_SPECIES`) so sparrow and every butterfly keep their
  original direct dispatch, untouched. 5 new tests pin the wiring itself;
  the file's own pre-existing flush/courtship/forage tests for robin are
  the regression bar and pass unchanged (167 passing, 2 pre-existing
  butterfly spiral-flight numerical-tolerance failures confirmed unrelated
  — the diff never touches that code path).
- ⬜ Wiring `CreatureMarker`/`NpcMarker`/`AntForagerMarker`/sparrow to
  actually run a parsed tree. One species proven at a time, per
  [ethogram.md](ethogram.md)'s own slice-5 lesson about the cost of
  touching a live marker outside a dedicated, narrowly scoped pass —
  sparrow (identical mechanism to robin) is the obvious next one.
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
- **Resolved by §4: per-node state lives on the marker, reached through
  `context["marker"]`, never on the shared tree.** Every robin shares one
  parsed AST; `local_atoms` are Callables bound to `self` at the point
  they're built (`_local_atoms()`, called fresh each `_process`), so
  `_flushed_by_player`, `perched`, and every other genuinely
  per-individual field a wrapped step function reads or writes stays
  exactly where it always lived. Confirms what this question only
  speculated before: a stateful atom needing per-individual memory is not
  a gap in the design, it is a `local_atoms` entry.
- **Should the parser accept the ethogram's own wiring shape as sugar?**
  `gate(above(need: X, threshold: Y)) { seek(on: Z) }` is exactly one
  ethogram wiring `{"gate": X, "channels": [Z], "approach": "seek_food"}`
  spelled out longhand. A future terser sugar is plausible; not built
  here, so the grammar in §1 stays the one this doc's own tests check.
