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

### Designed here but deliberately NOT built in this slice (⬜)

- ⬜ **Affordance inference.** Nothing yet turns "two opposed edges, one
  pivot, rotational motion" into an affordance tag such as SHEAR. The
  topological queries it needs exist (`permits_relative_motion`,
  `motion_between`, `separates_into`, `parts_with_geometry`); the inference
  layer on top of them does not.
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
- ⬜ **Composite stats and effect tags for a whole assembly.** materials.md's
  leverage rule (`delivered_force ∝ head_mass × lever_length × swing_speed`),
  edge-and-backing, balance/mass distribution, and the threshold-crossing that
  produces cut/pierce/crush tags are all still unbuilt at the *assembly* level.
  `ImpactResolver` already resolves a single impact from momentum and a contact
  geometry; nothing yet computes that momentum *from a part graph*.
- ⬜ **Any connection to real items.** `Item`/`ItemCatalog` still carry a flat
  `mass_kg` and `weapon_damage`. No item in the game is built from a part graph
  yet; this is a model with tests, not a live system.
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
