# Emergent Crafting: Parts, Joints, and the Part Graph

> This doc specifies the **data model** underneath
> [materials.md](materials.md)'s emergent-item vision: an item is a **graph of
> parts connected by typed joints**. It is the layer [crafting.md](crafting.md)'s
> open question ("does the player manipulate parts/geometry directly, or author
> intent that compiles to a part-graph?") is asking about, and the structure
> materials.md's "an item is a small graph of parts" sentence has been pointing
> at without ever making concrete.
>
> **Scope honesty up front.** This doc describes a design whose *foundation* is
> built and whose upper storeys are not. The Status list at the bottom marks
> every piece ✅ built, 🚧 partial, or ⬜ designed-but-not-built, and the ⬜ rows
> are load-bearing — read them before assuming a mechanism exists.

## Design pillars

1. **A part is a first-class thing, not a recipe ingredient.** A part is a
   `(material, geometry, role)` triple with real dimensions. It has its own
   mass, its own section, its own keenness. That is what later makes a part
   lootable, tradeable, swappable, and able to carry its own rarity: you can
   find *a good blade* rather than *a good sword*.

2. **Joints are the missing primitive.** materials.md's assembly model is
   implicitly **rigid** — it composes a haft with a head and nothing ever moves
   relative to anything else. That expresses a sword beautifully and **cannot
   express a pair of scissors at all**. Scissors are two opposed edges sharing
   a **pivot**, and they cut *by closing*. Once a joint carries a type, the
   whole articulated category opens with no new machinery: shears, bows (a limb
   held under tension), flails, doors.

3. **Affordances are inferred from topology and physics, never declared.** The
   graph never says "this is scissors". Nothing in the model may branch on what
   an assembly *is*. The system is meant to recognise that two opposed edges on
   a pivot that close afford **shear** — from the structure alone. This slice
   builds the structure and the topological queries an inference layer needs;
   it does **not** build the inference (⬜).

4. **Serviceability is a build-time choice with a real cost.** How readily a
   joint comes apart is a property of how it is *fastened*, grounded in real
   joinery, and it trades directly against how much load it carries. A smith
   picks a point on that line every time they join two parts.

5. **Determinism.** Same graph, same answers, stable ordering. Construction
   order is kept explicitly rather than read out of a dictionary's keys.

## Real-world grounding

### Geometry is solid geometry

Every part derives its volume from its own dimensions with ordinary solid
geometry, so a part can never claim a mass its shape contradicts:

| Geometry | Solid | Volume |
| --- | --- | --- |
| `edge` | triangular prism (a wedge) | `½ · length · width · thickness` |
| `point` | cone, base radius `length · tan(½ apex angle)` | `⅓ π r² length` |
| `face` | rectangular slab | `width · height · thickness` |
| `haft` | cylinder | `π (d/2)² · length` |
| `bulk` | equivalent sphere | `π d³ / 6` |

The back thickness of an edge is **its own dimension and is not derived from
the edge angle**: on a real blade the cutting bevel is ground into the last few
millimetres and says nothing about how thick the spine is. Deriving one from
the other would make every keenly-ground sword implausibly thin.

The whole geometry table is checked at once by an acceptance test: the sword
assembly below must mass **1.0–1.5 kg**, the real mass of a single-handed
arming sword. It comes out at **1.377 kg**.

### Keenness comes from real sharpening angles

materials.md commits to "edge (length, angle → keenness potential)". The angle
term runs between the two ends of actual cutlery and woodworking practice:
razors and scalpels are ground at roughly **15°** included (below that the
steel, not the angle, limits how keen the edge gets — which is why nobody
grinds thinner), and felling-axe bits at roughly **40°**, where the tool is a
wedge that parts fibres rather than a cutter that severs them. Between the two,
keenness falls off linearly, scaling the material's own `sharpness_capacity`
from the shared 8-scalar vector.

### Serviceability is derived from two observable facts

The scalar a disassembly-risk layer will consume is **not** five hand-picked
numbers. It is derived from two things a workshop can actually observe about
undoing a fastening, each on a four-step scale:

- **What it destroys** — nothing (0) / the fastener itself (1) / a joined part
  (2) / the whole assembly (3).
- **What it takes** — your hands (0) / an ordinary hand tool (1) / a workshop
  process such as drilling or heating (2) / nothing will (3).

`serviceability = 1 − (destroys + effort) / 6`

| Fastening | destroys | effort | Serviceability | Why |
| --- | --- | --- | --- | --- |
| `lashing` | 0 | 0 | **1.000** | Untie it. The cord coils back up and both members are untouched — being untied is what a lashing is *for*. |
| `pin` | 0 | 1 | **0.833** | A screwdriver or a punch. The pin itself survives. |
| `fit` | 1 | 1 | **0.667** | Mallet and drift. The wedge, or the interference set that held it, is gone. |
| `rivet` | 2 | 2 | **0.333** | Drilled out. The rivet is destroyed doing it and the hole is reamed oversize — a riveted joint genuinely costs you a part. |
| `weld` | 3 | 3 | **0.000** | A metallurgical bond. You are cutting, not disassembling. |

The three cases the design names by hand land exactly where they should.

**Adhesive is deliberately absent.** Its serviceability depends on *which*
adhesive — hide glue is prized for being reversible with heat and water, epoxy
is not — so it is a material question this joint vocabulary cannot honestly
answer yet.

### Strength is joint efficiency, the real engineering quantity

**Joint efficiency** is the fraction of the solid parent section's strength a
connection retains — exactly the quantity boiler and ship design has computed
for riveted joints for over a century (*efficiency = strength of the riveted
joint / strength of the solid plate*). Each fastening carries a real published
band and its efficiency is the **midpoint** of that band:

| Fastening | Band | Efficiency | Grounding |
| --- | --- | --- | --- |
| `lashing` | 0.25–0.35 | **0.30** | Cordage transmits load only through friction between the wraps and the members. The weakest classical connection, and why a lashed stone head works loose in use. |
| `fit` | 0.40–0.60 | **0.50** | A taper or interference fit has no fastener in tension at all; it holds by normal force. Which is why a socketed axe head tightens under every swing but pulls straight off in tension. |
| `pin` | 0.50–0.70 | **0.60** | Loses the net section its hole removes, then carries load in bearing and shear on the pin with no clamping friction to share it. |
| `rivet` | 0.60–0.80 | **0.70** | The classic double-riveted lap/butt band. A hot-driven rivet shrinks as it cools and clamps the members, so it beats a slip pin. |
| `weld` | 1.00 | **1.00** | A sound full-penetration weld is *defined* by being as strong as the parent metal; pressure-vessel codes allow 1.00 for a fully radiographed butt weld. A point, not a band — anything less is a defective weld, not a different kind. |

Read the two tables together and the trade-off falls out: **the fastening you
can always undo carries the least, the one that carries the parent metal's full
load is the one you are never undoing, and nothing is best at both.**

Load capacity itself is `efficiency × material toughness × section area`.
Toughness stands in for tensile strength — not a fudge invented here, but the
convention `MaterialProperties.ROPE_MIN_TOUGHNESS` already established, since
the 8-scalar vector has no separate tensile scalar.

## Mechanism spec

### Parts (`src/gameplay/item_part.gd`)

`ItemPart(material, geometry, role, dimensions)`.

- **Material** is a string key into the *existing* `MaterialProperties.MATERIALS`.
  An unmodeled material is **rejected**, not defaulted — falling through to
  `DEFAULT_PROPERTIES`' density 1.0 would hand back a confident, wrong mass.
- **Geometry** is `edge` / `point` / `face` / `haft` / `bulk`, exactly
  materials.md's list, each with its own required dimensions. A missing or
  non-positive dimension is rejected and named.
- **Role** is the maker's *intent*: `working` / `grip` / `structure` /
  `counterweight` / `setting` / `cover`. Six words that have to describe a
  sword, a pair of scissors and a picture frame, or the vocabulary has smuggled
  in a weapon assumption.

**Why role is a third field and not derived from geometry.** Geometry and
material carry the physics; role carries intent. Nothing may let role answer a
physical question — a part cuts because it is a keen edge of a hard material,
never because someone typed `working`. Role is read by *interface* questions
only (where does a hand go, where does a channel terminate), which genuinely
cannot be recovered from shape: a scissors bow and a frame rail are the same
slender member, one is held and one is not, and only the maker knows which.

**What lives on a part vs. on the graph.** A part answers only what it can
answer *alone*: volume, mass, span, load-bearing section, keenness. Anything
needing a second part is the graph's — leverage needs a head *and* a lever arm
*and* the path between them; "is this the weakest link" needs every other joint
to compare against; "do these two move relative to each other" is purely
topological.

### Joints (`src/gameplay/part_joint.gd`)

`PartJoint(id, part_a, part_b, type, fastening, material, axis)`.

A joint answers **two independent questions**, and the model keeps them apart:

- **Type** — what motion does it permit? `rigid` (0 DOF) / `pivot` (1
  rotational, about an axis) / `sliding` (1 translational, along a direction) /
  `sprung` (1 elastic, stores and returns energy — the bow limb) / `socket` (3
  rotational, no constrained axis).
- **Fastening** — what holds it, and what does undoing it cost? See the tables
  above.

**Two deliberate divergences from the brief's vocabulary, both to remove a
redundancy that would let two fields disagree about one fact:**

- **`LASHED` is a fastening, not a type.** "Lashed" is not a statement about
  motion — a lashing holds two parts still exactly as a rivet does. Keeping it
  as a type would permit a joint that is both `LASHED` and rivet-fastened. The
  split pays for itself in both directions: a lashed flail head really does
  swing on its lashing (`pivot` + `lashing`), and a scissors pivot really is
  sometimes a screw and sometimes a peined rivet — same kinematics, wildly
  different serviceability, which is exactly what disassembly needs and a
  single enum would have flattened away.
- **`SOCKET` means the mechanical ball-and-socket**, not a jeweller's gem
  socket. A seat that *receives* a part is a piece of material, so it is a part
  role (`setting`); the thing holding the gem in it is an ordinary rigid
  friction fit.

One cross-rule between the vocabularies, physically undeniable: **a forge weld
admits no relative motion**, so it cannot hold a pivot, slider, spring or
socket. A pivot or slider with no axis is likewise rejected — it has not said
what it turns about.

### The graph (`src/gameplay/part_graph.gd`)

Parts as nodes, joints as edges. Nothing in it knows what it is looking at;
there is no "is this a sword" branch and there deliberately cannot be one.

- **Construction/validation.** `add_part` / `add_joint` return false and record
  a reason for a duplicate id, a malformed part or joint, or a joint naming a
  part that is not in the graph. A rejection leaves no trace and never
  overwrites what is already there. `validation_errors()` carries the reason up
  from the part or joint itself.
- **Traversal.** `path_between` is breadth-first — the **shortest** route, not
  merely the first found — expanding neighbours in construction order so ties
  always break the same way. `joints_along_path` derives the joints crossed
  *from* the part path rather than keeping a second answer that could drift.
  `path_length_cm` sums the parts' spans, because channel loss is decided by
  real distance through real material, not a hop count.
- **Aggregates.** `total_mass_kg`, `parts_with_role`, `parts_with_geometry`,
  `part_load_capacity`, `joint_load_capacity` (capped by the *thinner* of the
  two members — the same net-section logic as a real riveted joint), and
  `weakest_link`, which compares every joint against every part so a joint
  being the weakest link is **computed rather than assumed**.
- **Articulation.** `is_rigid_body`, `articulating_joints`,
  `permits_relative_motion`, `motion_between`. `permits_relative_motion` tests
  whether an **all-rigid route** exists, not whether the shortest route crosses
  a hinge — if any rigid path holds two parts, they are held, which is why
  welding a strap across a hinge stops it being a hinge.
- **`separates_into(joint)`** returns what the assembly falls into if that one
  joint lets go. One query, two consumers: it is how "two opposed parts share a
  pivot" is checked structurally, and it is exactly what disassembly asks. A
  joint in a closed loop yields **one** group, because a ring stays whole when
  one link lets go — which is why a mitred frame does not drop a rail.

### The three acceptance assemblies

These are built as real tests in `tests/unit/test_part_graph.gd` and **they are
the spec**.

**A sword** — the control, and exactly what the old implicitly-rigid model
already handled. An 80cm iron blade, a 20cm crossguard, a wooden grip, an iron
pommel peined onto the tang. Rigid end to end, masses **1.377 kg**, and it
fails **at the shoulder where the blade meets the guard** — which is where real
swords break. Nobody wrote that down; it falls out of the blade's thin wedge
section being the smallest in the assembly.

**A pair of scissors** — the case the old model cannot express at all. Two 8cm
iron blades, each forge-welded to its own bow, sharing **one pivot pin**.
Masses **54 g** (household scissors are 50–90 g). Structurally, and computed
from topology alone:

- it is **not a rigid body**, where the sword is;
- it articulates at **exactly one** joint;
- the two blades **move relative to each other**, and the motion is
  **rotation** — they close about the pivot;
- each half is internally rigid (a bow forge-welded to its own blade is one
  piece of steel), but the two *bows* move relative to each other, because the
  route between them crosses the pivot;
- undo the pivot and it **falls into two halves carrying exactly one edge
  each** — two edges, on opposite sides of one articulating joint;
- and it is **weakest at the pivot**, which is where scissors really fail.

**A photo frame** — proof the grammar is not weapon-only. Four mitred wooden
rails pinned into a closed rectangle, holding a paper photograph in the rebate.
No edge, no point, nothing to swing. Masses **236 g**. It is a rigid body like
the sword; it is a **closed loop**, so the shortest route between opposite
rails goes the short way round; and letting one mitred corner go **does not
drop a rail**, which is what a frame *is* — and no rule about frames was
written to make that true.

## The compiler: an item is a small program

> Everything from here down landed 2026-08-28 and closes the Status list's
> "composite stats and effect tags" ⬜ row. Read the new ⬜/🚧 rows at the
> bottom before assuming more exists than does — in particular, **nothing in
> live gameplay calls any of it yet**, and the Status list says why.

**The thesis.** An assembly compiles to a list of `event → guard → pipeline`
**rules**, in the *same AST shape* [magic.md](magic.md)'s `spell_parser.gd`
already produces for player-written spells. Affordances — "it cuts", "it rips" —
are a **UI projection over those rules**, never the output itself.

That one choice is the whole design. Derived physics and a hand-authored
enchantment become the same kind of thing, so a Flame Brand and a blade's own
cut rule merge into **one list on one item** with no adapter between them. Had
the compiler emitted `{"cuts": true, "damage": 7}` instead, the two would have
been different kinds of thing forever. A test compares a compiled rule
key-for-key against a rule the shipped parser actually produced, so the two
shapes cannot drift.

**Guards are single comparisons, and that is a feature.** `_parse_guard` has no
`and`. So every conjunction in an affordance predicate is resolved
**statically, at compile time**: either the rule is emitted, or it is not and a
note says *which clause failed*. What remains in the guard is the one genuinely
dynamic term — the momentum of the actual blow — and its threshold is always
the shipped `ImpactResolver` symbol, never a copy of the number.

### The swing (`src/gameplay/part_mechanics.gd`)

The composition rule materials.md gestures at (`delivered_force ∝ head_mass ×
lever_length × swing_speed`) is not what got built, because it is monotonic in
mass and therefore says a 20 kg hammer is the best hammer. What got built is the
rigid-body dynamics that actually govern a swing:

| Quantity | How |
| --- | --- |
| `moment_of_inertia(graph, pivot)` | Σ (own moment + `m d²`) — the parallel-axis theorem about the grip |
| `balance_point_cm(graph, pivot)` | signed centre of mass; branches on opposite sides of the hand oppose |
| `reach_cm(graph, pivot)` | farthest point from the pivot's centre |
| `gravity_torque_nm` | `M g ·` balance point — the cost of just holding it out |
| `net_swing_torque_nm` | what is **left over** to accelerate with |
| `swing_time_s(graph, strength)` | `√(2 θ I / τ)`, constant angular acceleration through a fixed arc |
| `delivered_momentum(graph, strength)` | `I ω / r` — the angular momentum about the grip, delivered at the strike radius |

`delivered_momentum` is the textbook rigid-body impact quantity, and it is the
*right* generalisation rather than a convenient one: **for a point mass at
radius r it reduces exactly to `m v`**, so it is plain momentum wherever plain
momentum is defined, and carries the effective mass at the contact point
everywhere else.

**Why there is an optimum.** Delivered momentum **rises and then falls** with
head mass, with the maximum strictly interior. Too light and there is no mass to
carry momentum; too heavy and holding the thing out eats the entire torque
budget, `net_swing_torque` hits **zero**, and the swing stops happening at all.
That stall is a wall, not an asymptote, and it is the mechanism the optimum
exists because of. `test_there_is_an_optimum_head_mass_for_delivered_momentum`
sweeps 0.2–12 kg and asserts the turn-over; a model that ever becomes monotonic
in mass fails it.

A consequence nobody put in: **a stronger actor's optimum head is heavier**,
because strength pushes the stall wall further out.

#### The one free constant, solved for rather than picked

`SWING_TORQUE_NM_AT_UNIT_STRENGTH = 17.140 N·m` — the torque an adult delivers
*about the grip*. It is the **framing-hammer anchor inverted**: build the
reference hammer (33 cm haft, 21 oz iron head — the geometry a century of
carpentry converged on), demand its striking face arrive at the **measured
10 m/s**, and read off the torque. A test re-derives it from the fixture and the
measurement, so it cannot drift from what it encodes.

The rejected alternative was a published isometric wrist-torque figure (~10 N·m)
straight from an ergonomics table — rejected because a swing is a whole-body
kinetic chain delivering *through* the grip, not an isolated wrist action, so
that number understates it by about half and the model would have said a
carpenter cannot drive a nail.

**Two independent checks the calibration was not fitted to**, both from a
constant derived on a hammer:

- the arming sword swings in **0.295 s** (a real sword cut is about a quarter
  second);
- it arrives at **3.51 kg·m/s**, above the shipped `T_CUT` of 3.0 — so it cuts,
  and nobody said it should.

#### Why swords have pommels

Two facts about the same lump of iron, and the second is not the one you would
guess:

- At **equal total mass**, iron at the grip costs far less inertia than iron at
  the tip — `m d²`, so distance is squared.
- Take the pommel **off** and the sword gets **27% lighter (1.377 → 1.005 kg)
  and slower** (0.2953 → 0.2977 s). The inertia about the hand barely moves —
  the pommel sat close to the grip and was never much of it. What changes is the
  **balance point**, which runs away down the blade (34.1 → 49.6 cm), so the
  gravity torque *rises* (4.61 → 4.89 N·m) even though there is less sword to
  hold. That eats the torque budget, and what is left accelerates an almost
  unchanged inertia more slowly.

A lighter sword that is harder to hold out and slower to swing. That is the
pommel's job, and no rule mentions pommels.

### The compiler (`src/gameplay/item_compiler.gd`)

`compile(graph, crafter_skill) → {ok, errors, mass_kg, swing_time_s, reach_cm,
delivered_momentum, balance_point_cm, rules, affordances, notes, absences}`.

Six verbs, each a list of static clauses evaluated in order, stopping at the
first failure so the reason names the clause that actually bit:

| Verb | Static clauses | Runtime guard |
| --- | --- | --- |
| `cut` | an edge exists; its **realized keenness** ≥ the cutting line | `T_CUT` |
| `chop` | an edge exists; **`delivered_momentum` ≥ `T_CUT`** | `T_CUT` |
| `rip` | an edge with a **tooth pitch**; its **set cuts a kerf wider than the plate** | `BOUNCE_MOMENTUM_THRESHOLD` |
| `pierce` | a `point` exists | `T_PIERCE` |
| `crush` | a **working** `bulk` or `face` exists | `T_CRUSH` |
| `parry` | no working part is under `T_BRITTLE_TOUGHNESS` | `BOUNCE_MOMENTUM_THRESHOLD` |

**The cutting line.** `cut` asks about the *grind*; `chop` asks about *mass*.
Keeping them apart is what makes a scalpel and a maul different objects. The
threshold is **derived, never written down**: `cut_keenness_min()` is the
benchmark blade material (iron — the material `KEEN_SHARPNESS` was itself set
from) ground at **30° included**, the real woodworking line between a bevel that
severs fibres and one that merely splits them, sitting between the 15°/40° ends
`ItemPart` already pins. It comes out at **3.2**, and it is measured by asking a
real `ItemPart` for its `keenness()` rather than restating the formula.

**Crafter skill touches only the grind.** A novice cannot put a severing edge on
steel; what they produce is a wedge. So skill interpolates the *realized* grind
angle from `WEDGE_ANGLE_DEG` (skill 0) to the angle the part was designed with
(skill 1) — both already-shipped symbols, so this needed **no constant of its
own**. The rejected alternative was a "skill factor" multiplier with a floor
picked to feel right. At skill 0.3 the arming sword loses its `cut` rule and
**keeps its `chop` rule**, because chopping is a question about mass.

### The headline: the saw/axe reciprocal

**A saw emits `rip` and not `chop`; an axe emits `chop` and not `rip`** — and
the two absences are **two independent physical failures**, not one flag read
two ways:

- The saw **cannot chop** because its 0.9 mm plate carries only **2.18 kg·m/s**
  to the edge against the 3.0 a chop needs. A **mass** failure.
- The axe **cannot rip** because its bit is a **transverse wedge with no tooth
  pitch** — there is nothing to carry chips along a cut. A **geometry** failure.

A test asserts the saw's reason names momentum and never mentions teeth, and the
axe's names teeth and never mentions momentum. If the two ever collapse into one
shared flag, that is what notices.

**The detail worth having**: a saw's teeth are bent alternately to each side (the
**set**) so the cut they make is wider than the plate following through it. A
saw filed with every tooth it needs and **no set** still cannot rip — it binds in
its own kerf — and it fails with a third, distinct reason. That, and not
sharpness, is the deep reason an axe cannot rip a plank.

### Obsidian: an exception nobody wrote

Obsidian takes the **keenest edge in the game** (`sharpness_capacity` 10, above
iron's 8) **and shatters** (`toughness` 1.0, under the 3.0 the impact model
already fractures at). Both fall out of its own property vector: the obsidian
sword emits its `cut` rule and simply **does not emit a `parry` rule**, because
that guard is statically false. The tooltip's "cannot parry" is a *consequence*,
not an authored exception, and the same sword in iron parries fine.

### Absence reasons (`src/gameplay/affordance_notes.gd`)

`absence_reason(graph, verb) → String` and `affords(graph, verb) → bool`.

This is the **legibility surface**, and it is a feature rather than a debug aid.
Everything in this model is inferred rather than declared, which is the point
and is also its one real risk: a system whose failures are silent is
unlearnable. A player told only "your saw cannot chop" will guess, and will
guess wrong — they will file the teeth sharper. A player told the *plate is too
light to carry the blow* has learned something true and can act on it. It is the
same commitment materials.md's "Learning an emergent system" already makes for
descriptors over a raw scalar spreadsheet.

It has **no opinions of its own**: every string comes out of `compile`, and it
must never grow a second explanation, because a note that disagreed with the
physics would be worse than no note.

Three kinds of answer are kept distinct: the assembly is **not an item at all**
(no grip, parts not joined, malformed) — answered with *that*, because "your
offcut cannot cut" would imply it was nearly a tool; the verb is **not one the
model knows**; or the ordinary case, the compiler's own reason verbatim.

### What the fixtures come out as

| Assembly | Mass | Momentum | Swing | Verbs |
| --- | --- | --- | --- | --- |
| Arming sword | 1.377 kg | 3.51 | 0.295 s | cut, chop, parry |
| Felling axe | 1.949 kg | 6.66 | 0.278 s | cut, chop, parry |
| Rip saw | 0.322 kg | 2.18 | 0.088 s | **rip**, parry |
| Obsidian sword | 0.891 kg | 2.24 | 0.151 s | **cut only** |

The obsidian row is the one to read twice, because two separate things went
wrong for it and nobody arranged either. Obsidian's density is 2.4 against
iron's 7.8, so the *same blade dimensions* mass a third as much — which puts its
delivered momentum at **2.24, under `T_CUT`**, so it loses `chop` on **mass**
while keeping `cut` on **grind**. And its toughness costs it `parry`
independently. An obsidian sword ends up a thing that slices and can do nothing
else, which is a fair description of a glass knife.

## Status

### Built and tested (✅)

- ✅ **`ItemPart`** — `(material, geometry, role)` with real dimensions; volume,
  mass, span, cross-section and keenness all derived from solid geometry and
  the shared material vector. Consumes `MaterialProperties.mass_kg_for`; does
  not fork it. Explicit rejection of unmodeled materials, unknown
  geometries/roles, and missing or impossible dimensions.
- ✅ **The five geometry primitives** materials.md names, with the real
  dimensional parameters each needs.
- ✅ **Keenness from the real 15°/40° sharpening range**, scaling the
  material's own `sharpness_capacity`.
- ✅ **`PartJoint`** — the typed joint. Kinematics (5 types, DOF, motion kind,
  motion axis, energy storage) kept separate from joinery (5 fastenings,
  serviceability, efficiency, load capacity).
- ✅ **Serviceability grounded in real joinery**, derived from a
  destroys/effort formula rather than tabled.
- ✅ **Joint efficiency from real published bands**, and the
  serviceability-vs-strength trade-off asserted as a property.
- ✅ **`PartGraph`** — validation, breadth-first shortest paths, joints and
  physical length along a path, aggregates, articulation queries,
  `separates_into`, and a computed weakest link.
- ✅ **Determinism** — explicit construction ordering throughout, asserted.
- ✅ **The three acceptance assemblies** (sword, scissors, photo frame) as real
  tests with real dimensions and real-world mass checks.
- ✅ **`PartMechanics`** — the swing as rigid-body dynamics: moment of inertia
  by the parallel-axis theorem, signed balance point, reach, gravity torque, net
  swing torque, swing time and delivered momentum. **Unimodal in head mass with
  an interior optimum**, asserted; one free constant, solved for from the
  measured framing-hammer anchor and re-derived by a test.
- ✅ **`ItemCompiler`** — an assembly compiles to `event → guard → pipeline`
  rules in `spell_parser.gd`'s own AST shape, pinned key-for-key against a rule
  the shipped parser actually produced. Six verbs, guards reading the shipped
  `ImpactResolver` symbols, conjunctions resolved statically with a named reason
  for every absence. Malformed input errors with a real reason rather than
  crashing.
- ✅ **The saw/axe reciprocal** as two independent physical failures (mass vs.
  edge geometry), and the tooth-set/kerf rule as a third.
- ✅ **`AffordanceNotes`** — `absence_reason` / `affords`, projecting the
  compiler's reasons with no second opinion of its own.
- ✅ **Crafter skill on the grind**, expressed entirely in already-shipped
  symbols (the 15°/40° sharpening range) rather than a tuned skill factor.

### Designed here but deliberately NOT built in this slice (⬜)

- ⬜ **Topological affordance inference — the SHEAR case specifically.**
  `ItemCompiler` infers six verbs from **geometry, material and swing
  physics**, which covers every rigid body. It does **not** read articulation:
  nothing yet turns "two opposed edges, one pivot, rotational motion" into a
  SHEAR affordance, so **the pair of scissors that motivated the whole joint
  primitive compiles as though it were a stiff pair of knives** — it gets no
  shear verb, because there is no shear verb, and every number in its result
  comes from swinging it about one bow, which is not how scissors work at all.
  Pinned by `test_the_compiler_does_not_understand_scissors_and_says_so_here`,
  which is written to start failing the day a shear verb exists. The
  topological queries the
  inference needs all exist (`permits_relative_motion`, `motion_between`,
  `separates_into`, `parts_with_geometry`) and are unread by the compiler.
  Scissors are also the case where "the pivot is the grip part's centre" stops
  being a reasonable approximation, so this row and the orientation row below
  are the same piece of work.
- ⬜ **Part orientation.** Parts have no placement or facing, so "opposed" can
  only be checked as far as unoriented topology allows — two edges on either
  side of one articulating joint. *Which way* each edge faces needs a
  placement layer that does not exist.
- ⬜ **Positional affixes / enchantments on parts.** A part carries no affix,
  rarity or enchantment yet. The data model makes room for it (a part is a
  first-class object with an identity); nothing populates it.
- ⬜ **Magic channel routing.** `path_between` and `path_length_cm` exist
  precisely so routing from a `grip` along a material path to a `setting` is
  possible, and the material vector's `conductivity` is reachable through
  `ItemPart.property_value`. The loss/backfire formula itself is not written.
- ⬜ **Disassembly risk.** `serviceability`, `costs_a_part` and
  `separates_into` are the three inputs a disassembly layer needs, and all
  three are real. The layer that consumes them — rolling a risk, destroying the
  right part, returning the rest — does not exist.
- ⬜ **Any connection to real items — and this is the load-bearing one.**
  `Item`/`ItemCatalog` still carry a flat `mass_kg` and `weapon_damage`, and
  `Item.is_saw()` / `is_axe()` / `is_pickaxe()` (`scenes/player.gd`:1594, 1691,
  1773) are still `id.contains(...)` string hacks, so a **player-built saw
  cannot saw**. `AffordanceNotes.affords(graph, "rip")` is exactly the call that
  would retire them, and nothing makes it.

  The blocker is concrete and worth writing down rather than restating as "not
  wired yet": **no conversion exists between a `PartGraph` and the assembly
  dictionaries `CraftedItemRegistry` stores, in either direction.** `part_graph.gd`
  is referenced only by tests. The registry's canonical form carries a
  *quantized volume* and a material per part (that is all `_mass_kg_for` needs)
  — not geometry, not dimensions, not joint kinematics — so an assembly read
  back off a save **cannot be rehydrated into a graph** to compile. The next
  slice is that serializer, not the `player.gd` edit; doing the edit first would
  produce an `Item.affords()` with nothing behind it.

  **One half of that bridge now exists, from an unexpected direction (2026-09-05):**
  [standard_model.md](standard_model.md)'s `device` DSL declares parts and
  joints as text (`part blade: iron edge working (length_cm: 80, …)`,
  `joint pivot: a to b pivot pin iron (axis: z)`) and `DeviceCompiler`
  compiles them into *this* `PartGraph`, validated by its own rules. That is
  text → graph. Graph → text, and the `CraftedItemRegistry` round-trip, are
  still the missing halves.
- ⬜ **Edge-and-backing.** materials.md names it and nothing implements it: an
  edge's support against its own backing material is not modelled, so an obsidian
  blade bonded to a tough spine behaves exactly like a bare one.
- ⬜ **Wear, chipping and durability, for EMERGENT/crafted items specifically.**
  `weakest_link` is computed and the compiler still ignores it — so the
  serviceability/strength trade-off the joint vocabulary exists to express
  still has no consequence in play for anything assembled through this part
  graph. [`item_durability.md`](item_durability.md) built the general
  mechanism (toughness-derived fatigue wear, real for the three base
  catalog weapons with a modeled material), but nothing connects it to
  `weakest_link` or to a crafted item's own computed vector yet — a crafted
  sword still doesn't wear any differently for being assembled from a
  weaker joint.
- ⬜ **Effect magnitudes.** The compiler emits *which* rules fire and under what
  guard; the pipelines carry the physical facts (keenness, kerf, delivered
  momentum) but no damage number. What an atom like `cut_damage` actually does
  with them is the runtime's, and is unwritten.
- ⬜ **Two-handed grips, thrusts and non-swung use.** Every verb here assumes a
  swing about one grip. A spear thrust, a two-handed haft, a drawn bow and a
  pressed chisel are all real and none is modelled.
- ⬜ **Non-linear alloy discovery.** Alloys arrive at a property vector by a
  separate route (see [smelting.md](smelting.md)) and then flow through this
  pipeline unchanged. Nothing here needs changing to accommodate them, and
  nothing here implements them.

### Known simplifications (🚧)

- 🚧 **Joints are massless.** A lashing's cordage and a rivet have real mass,
  but a joint has no dimension to compute it from, so `total_mass_kg` is the
  sum of the parts only. Named as a limit rather than fudged with a guess.
- 🚧 **A joint's section is capped by the thinner member**, which is right for
  a riveted or pinned connection through both members but generous for a
  lashing (whose real load-carrying section is the cord's).
- 🚧 **`motion_between` describes the shortest route.** In an assembly where
  two parts are joined by several differently-articulated routes, it reports
  the shortest one rather than the union of all of them. It returns empty
  whenever a rigid route holds the two parts, so it can never contradict
  `permits_relative_motion`.
- 🚧 **The swing has no orientation to work with**, so parts lie end-to-end
  along their own spans and `path_length_cm` — the shipped notion of distance
  along a route — is what measures them. **A 20 cm crossguard therefore reads as
  20 cm of reach it does not really have**, which is why the arming sword comes
  out with a 105.5 cm reach and a 34 cm balance point against a real one's ~86 cm
  and ~15 cm. Reusing the shipped symbol was judged worth more than a private,
  differently-wrong guess at which dimension points along the assembly; the fix
  is the ⬜ orientation row above, not a special case here.
- 🚧 **The hand is at the grip part's centre.** True enough for a sword,
  generous for an axe — you hold the end of a haft, not the middle — so
  long-hafted tools get roughly half the lever they really have (the felling axe
  swings at 5.2 m/s where a real one reaches the teens). The calibration anchor
  uses the same convention so the one free constant absorbs it and the model
  stays self-consistent; the rejected alternative, pivoting at the grip's far
  end, makes gravity torque on a two-handed axe eat most of a one-handed torque
  budget, which is worse.
- 🚧 **The actor's own limb inertia is not modelled.** A real swing must also
  accelerate your arm. Omitted because the graph's own inertia already prevents
  the light-end blow-up and an arm-inertia constant would be a second ungrounded
  number bought for nothing.
- 🚧 **Each part's own moment uses the slender-rod result** `m L² / 12` rather
  than a per-geometry inertia tensor. Not load-bearing: the parallel-axis terms
  dominate it several times over on the sword (asserted), so refining it could
  only move the answer by a fraction of a fraction.
- 🚧 **`parry` asks only whether the material survives**, not whether the shape
  is any good at blocking — which is why the rip saw affords it. A real block
  wants a face, a guard, or enough length to intercept, and none of that is
  checked.
- 🚧 **A branchy assembly gets all its branches on one side.** The signed
  balance point puts the branch holding the farthest part positive and every
  other branch negative, which is exactly right for a hand in the middle of a
  sword and a simplification for anything with three or more limbs off the grip.
- 🚧 **Fatigue, accuracy and control are not priced**, which is why the model's
  momentum optimum for a 33 cm haft lands at a head heavier than real one-handed
  practice settles on. Momentum is not the only thing a carpenter is optimising.
