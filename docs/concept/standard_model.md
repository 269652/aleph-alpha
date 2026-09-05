# The Standard Model: one physics for devices, structures, and things

> Reported directly: *"design and spec a formal standard model for our in-game
> world physics and mechanics — a DSL flexible enough that engineers can invent
> entirely new devices / structures / things."*
>
> This doc is that standard model. It sits **on top of** the physics the game
> already has and **under** every device anyone will ever build: [materials.md](materials.md)
> supplies the property vector, [emergent_crafting.md](emergent_crafting.md)
> supplies parts, joints and the part graph, [electromagnetism.md](electromagnetism.md)
> supplies the first worked circuit, and the three existing DSLs
> ([magic.md](magic.md), [capture_dsl.md](capture_dsl.md),
> [npc_instructions.md](npc_instructions.md)) supply the grammar. What none of
> them had is a **single algebra** in which a water wheel, a lever, a bellows, a
> generator, a battery and a millstone are the *same five kinds of thing*
> connected by the *same two rules* — which is what "engineers can invent
> entirely new devices" actually requires. Without that algebra every new device
> is a new special case; with it, a device is a small text the engine has never
> seen before and can still resolve.
>
> **Scope honesty up front.** The Status list at the bottom is load-bearing.
> The formal model below is complete; the shipped kernel implements its
> series-loop core (one source, a chain of transformers, gyrators, resistors and
> stores, solved in closed form), the `device` grammar that compiles to it, and
> the derivations that turn a part's real geometry and material into an
> element's parameters. Parallel junctions, inertial storage, thermal loops,
> world-placement coupling and effect atoms are designed here and marked ⬜.

## Design pillars

1. **One algebra, not one system per device.** The whole game's physics is
   already one shared property vector and one impact equation
   ([materials.md](materials.md)'s "one damage model for the whole world"). This
   doc extends that to *machines*: every device is a graph of **elements** drawn
   from a fixed set of **five laws**, joined by **bonds** that carry an
   **effort** and a **flow** in one of a fixed set of **domains**. There is no
   "water wheel system", no "circuit system", no "pump system" — there is a
   `transform`, a `gyrate`, a `resist`, a `source` and a `store`, and a water
   wheel is what you get when you write them down in a particular order.

2. **No component knows what it is connected to.** Stated by
   [electromagnetism.md](electromagnetism.md) for circuits; made structural
   here for everything. An element exposes ports, each carrying one domain's
   effort and flow, and states one law relating them. It cannot see past its
   own ports. That is what makes a device *composable*: the generator does not
   care whether the shaft it is on comes from a river, a windmill, a treadmill
   or a hand crank, because torque is torque.

3. **Derived, never authored.** A wire's resistance comes from its material's
   conductivity and its real length and section; a wheel's transformer ratio is
   its real radius; a paddle's available force is the momentum flux of the
   water actually hitting it. An author *may* type a number, and the shipped
   examples do where no part exists to derive from (a world source has no
   geometry), but wherever a part exists the parameter is read off it, so two
   parts of the same material and shape cannot disagree about their physics.
   This is [materials.md](materials.md)'s "stats and effects are not authored
   per recipe, they emerge" rule, applied to machines.

4. **Conservation is the balance mechanism.** [synthesis.md](synthesis.md)
   names it: not nerf-lists, but *physical conservation + diminishing returns +
   emergent counterplay*. Here it is literal. Transformers and gyrators are
   lossless (power in equals power out, asserted as a property); resistors
   dissipate exactly `effort × flow`; a store's level rises by exactly the power
   flowing into it times the tick. Across a whole solved device, **source power
   equals dissipated power plus stored power**, and a test says so. An author
   cannot write a device that makes energy, because the algebra cannot express
   one.

5. **Failure is a threshold the material already has.** A wire that carries
   too much power gets hot; hot enough and it crosses
   `MaterialProperties.THERMAL_FAILURE` for its material and burns out. A
   shaft that carries too much torque crosses the same toughness line the
   impact model shatters things at. No device gets a bespoke "breaks at N"
   number; it fails where its material fails, through a rule over the solved
   state. (The *rule* mechanism ships; the derived ratings are ⬜ — see
   Status.)

6. **A device is a small program, and this is its second half.**
   [emergent_crafting.md](emergent_crafting.md)'s `ItemCompiler` turns an
   assembly into `event → guard → pipeline` rules. A device carries the same
   rules — `on step when filament.power >= 40: shine(target: filament)` — and adds the
   continuous half: the solved efforts and flows the guards are evaluated
   against. Discrete events and continuous physics live in one text, in one
   AST shape, because the rule grammar is unchanged.

7. **Determinism.** Same text, same world inputs, same answer, in the same
   order. The solver is closed-form (no iteration, no relaxation, no
   time-stepping to a fixed point), every list is construction-ordered, and
   ties never depend on a dictionary's key order.

## Real-world grounding

### Bond graphs: the domain-independent physics of engineers

Henry Paynter's **bond graphs** (MIT, 1959–61) are the standard formalism
for exactly this problem — modelling systems that cross energy domains (a
DC motor driving a pump feeding a hydraulic ram) with one vocabulary. Every
domain has an **effort** variable and a **flow** variable whose product is
**power**:

| Domain | Effort `e` | Flow `f` | `e × f` |
| --- | --- | --- | --- |
| Rotation | torque, N·m | angular velocity, rad/s | W |
| Translation | force, N | velocity, m/s | W |
| Electrical | voltage (EMF), V | current, A | W |
| Hydraulic | pressure, Pa | volumetric flow, m³/s | W |
| Thermal | temperature, K | heat flow, W | *pseudo* — the flow is already a power |

Thermal is a **pseudo-bond graph** (temperature × heat flow is not a power);
this is standard practice, the model names it honestly, and the kernel
excludes the thermal domain from power accounting rather than pretending
(`PhysicsDomains.is_power_domain`).

On those variables there are exactly **nine element types**, and this
project needs five of them plus the junctions:

| Bond-graph element | Law | Here | What it is in the game |
| --- | --- | --- | --- |
| `Se` effort source | `e = e₀` | `source` | a river's push on a paddle, the wind on a sail, a hand on a crank, a furnace's heat |
| `R` resistor | `e = R·f` | `resist` | a wire, a light-bulb filament, a millstone's grinding load, a pipe's friction, a bearing |
| `TF` transformer | `e₂ = r·e₁`, `f₂ = f₁ / r` | `transform` | a lever, a gear pair, a pulley, a wheel's radius, a piston, a pump |
| `GY` gyrator | `e₂ = k·f₁`, `f₂ = e₁ / k` | `gyrate` | a generator, a motor — anything Faraday |
| `C` capacitor | `e = q / C` | `store` | a battery, a reservoir behind a dam, a drawn bow, a thermal mass |
| `I` inertia | `f = p / I` | ⬜ `inertia` | a flywheel, a trip-hammer's falling head |
| `1` junction | common flow, efforts sum | the `loop` chain | series: one current through wire and bulb |
| `0` junction | common effort, flows sum | ⬜ `fork` | parallel: a battery across a bulb |
| `Sf` flow source | `f = f₀` | via Thévenin (below) | — |

The pay-off of borrowing this rather than inventing: **a transformer and a
gyrator are power-preserving by construction** (`e₂ f₂ = e₁ f₁` in both
tables above — check it), so lossless composition is a theorem, not a
tuning; and **every domain crossing the game will ever need is one of two
rules**. A lever crosses translation→translation with `r` = arm ratio; a
wheel crosses translation→rotation with `r` = radius (torque = force × radius,
angular velocity = velocity ÷ radius — the two lines of the TF law); a
piston crosses hydraulic→translation with `r` = area; a generator crosses
rotation→electrical with `k` = Faraday's constant for that machine. Nothing
else has to be written down, ever.

### Thévenin: every real source has an internal resistance

A real source cannot deliver unlimited power. Water pushing a paddle pushes
hardest when the paddle is stalled and not at all when the paddle is moving
as fast as the water; a generator's terminal voltage sags under load; a
person cranking pushes less the faster the crank goes. Electrical
engineering's **Thévenin equivalent** captures all of these as *an ideal
effort source in series with an internal resistance*: `e_terminal = e₀ −
R_internal · f`. The kernel's `source` law is exactly that pair, so every
source in the game has a stall effort, a free-running flow (`e₀ /
R_internal`), and a real **maximum power** it can deliver, `e₀² / (4
R_internal)` — reached only when the load matches the source.

That last fact is the **maximum power transfer theorem**, and it is this
model's version of `emergent_crafting.md`'s "there is an optimum head mass":
sweep the load a source drives and the delivered power **rises and then
falls**, with the optimum strictly interior, at `R_load = R_internal`. Too
little load and there is nothing to deliver power *into*; too much and the
source stalls. A model that ever became monotonic in load would fail
`test_there_is_an_optimum_load_for_delivered_power`, the same way a swing
model monotonic in mass fails its own anchor test.

### The paddle source: momentum flux, which the game already has

[electromagnetism.md](electromagnetism.md) pillar 1: torque from flow is
[materials.md](materials.md)'s existing momentum, caught by a paddle. The
force on a flat plate normal to a stream is the drag law `F = ½ ρ C_d A v²`
with `C_d ≈ 1.28` for a flat plate (the NASA/Hoerner flat-plate figure), and
it falls to zero as the plate reaches stream speed. The kernel's
`DevicePhysics.paddle_source` flattens that to the Thévenin pair the source
law needs: stall effort `F_stall = ½ ρ C_d A v²`, internal resistance
`F_stall / v` (the secant from stall to free-running — an honest 8-bit
linearisation of a quadratic, stated rather than hidden). Water's `ρ` is
`OpenChannelFlow.WATER_DENSITY_KG_M3` (1000); air's is 1.225 kg/m³ at sea
level. The same function is a windmill source with air's density — the
"identical mechanism, zero new world-sim dependency" sibling
electromagnetism.md promised.

### Ohm, Faraday, and the lever — each already named, now each one law

- **Ohm's law** is the `resist` law in the electrical domain, and a
  conductor's resistance is `R = L / (σ A)`. `σ` comes from the material's
  *existing* conductivity scalar run backwards through
  `MaterialProperties.conductivity_from_iacs` (the scalar is a linear map of
  published %IACS, and 100 %IACS is 5.80 × 10⁷ S/m by definition), `L` and
  `A` from the part's own haft geometry. So copper wire beats iron wire by
  the published 6.4×, and wood "simply doesn't conduct and can't complete a
  circuit at all" — electromagnetism.md's sentence — by twenty orders of
  magnitude, pinned.
- **Faraday's law** is the `gyrate` law between rotation and electrical.
  For a coil of `N` turns and area `A` turning in a field `B`, the peak EMF
  is `B A N ω`, so `k = B A N` in V·s/rad, and the *same* `k` is the torque
  per ampere the coil pushes back with (`τ = k I`) — one constant, two
  directions, which is why a generator and a motor are the same machine.
- **Leverage / Hebelwirkung** is the `transform` law: `e₂ = r e₁`, `f₂ = f₁
  / r`. The haft that multiplies a sword's cutting force
  ([materials.md](materials.md#shape-and-assembly)) and the wheel radius that
  multiplies flow into torque ([electromagnetism.md](electromagnetism.md)) are
  the one rule read in two directions.
- **A load seen through a transformer scales as `1/r²`, through a gyrator
  as `k²/R`** — the reflected-impedance rules every power engineer carries
  in their head, and the reason a stalled motor draws its maximum current
  (a huge mechanical load becomes a tiny electrical resistance). The kernel's
  solver is nothing but these two rules applied from the far end of a
  device back to its source.

### Stores are tanks, which the game already builds everywhere

A `store` is a bond-graph `C`: its effort rises with what it holds (`e = q /
C`, a battery's voltage climbing as it charges, a reservoir's pressure
`ρ g h` climbing as it fills, a bow's draw force climbing as it is drawn).
Per tick it is stepped as a tank — a level, a capacity, a rate — the exact
shape `SurvivalMeters`, `Wallet`, `ChargeMeter` and electromagnetism.md's own
"a real tank model (a capacity, a current level), not a binary has-power
flag" already use. Nothing new to learn.

## The formal model

### 1. Quantities

A fixed catalog, `PhysicsDomains.DOMAINS`, of energy domains. Each names its
effort and flow variables and their SI units, and whether `effort × flow` is
a power (`is_power_domain`). The catalog is closed: adding a sixth domain is
a deliberate decision checked by a test, not a string someone types.

### 2. Things

Every physical thing the model reasons about is one of:

- **A part** — `ItemPart` exactly as [emergent_crafting.md](emergent_crafting.md)
  ships it: `(material, geometry, role, dimensions)`, with volume, mass, span,
  section and keenness derived from solid geometry. Unchanged, reused, not
  forked. A *structure* is a part graph with no articulating joints and no
  laws; the model does not need a separate word for it.
- **A joint** — `PartJoint`, unchanged: kinematics × fastening. A `sprung`
  joint is where a later `store` in the translation domain (a bow limb)
  attaches; the joint already knows it `stores_energy()`.
- **An element** — a *law* attached to a named thing: `law wheel:
  transform(in: translation, out: rotation, part: wheel)`. An element is
  either a part with a law on it (then its parameters may be derived from the
  part) or a bare named thing with no geometry (a world source: the river,
  the wind). An element has one or two **ports**.
- **A port** — one end of an element, typed by domain. One-port elements
  (`source`, `resist`, `store`) have a single port in one domain; two-port
  elements (`transform`, `gyrate`) have an input port and an output port,
  possibly in different domains.
- **A bond** — a connection between two ports of the *same* domain. In the
  shipped grammar bonds are implied by the `loop` chain (each `|>` is a bond
  from the left element's output port to the right element's input port).
  A general `bond a.p to b.q` clause and explicit junctions are the ⬜
  generalisation.

### 3. The element algebra

Five laws. `e` and `f` are the effort and flow at a port; subscripts 1 and 2
are a two-port's input and output.

| Law | Ports | Relation | Power |
| --- | --- | --- | --- |
| `source(effort: e₀, resistance: Rₛ)` | 1 | `e = e₀ − Rₛ f` | delivers `e f`; can absorb if `f < 0` |
| `resist(resistance: R)` | 1 | `e = R f` | dissipates `R f²` |
| `transform(ratio: r)` | 2 | `e₂ = r e₁`, `f₂ = f₁ / r` | `e₂ f₂ = e₁ f₁` — lossless |
| `gyrate(ratio: k)` | 2 | `e₂ = k f₁`, `f₂ = e₁ / k` | `e₂ f₂ = e₁ f₁` — lossless |
| `store(capacity: C_J, full_effort: e_max, level: L_J, resistance: R_int)` | 1 | `e = e_max · L / C_J + R_int f` | stores `e_store f`; dissipates `R_int f²` |

`ratio` must be positive; a transformer with `r = 1` is a rigid coupling
(a shaft), which is why a shaft needs no element of its own.

**The affine-load reduction.** Everything downstream of any point in a
series chain looks, from that point, like one *affine load* `e = R f + e₀`
(a resistance in series with an opposing effort — a charging battery is the
canonical one). Two rules move an affine load upstream through a two-port,
and they are the whole solver:

- through `transform(r)`: `R' = R / r²`, `e₀' = e₀ / r`
- through `gyrate(k)`: `R' = k² / R`, `e₀' = −k e₀ / R`

A `resist` in series adds `R`; a `store` adds `(R_int, e_store)`. The
gyrator line is worth reading twice: it turns a resistance into a
conductance (a heavy mechanical load is a *small* electrical resistance),
and it turns an opposing effort into a *negative* one — a charged battery
behind a generator looks, from the shaft, like something trying to turn it.
That is physically exact (it is a motor), and it is how "the battery keeps
the millstone turning after the river drops" falls out with no rule saying so.

**Open ends.** A chain whose last element is a two-port has an open output:
`R = ∞`. Through a transformer it stays `∞` (nothing flows); through a
gyrator it becomes `0` — a generator with nothing wired to it spins at the
source's free-running speed and produces its open-circuit EMF with no
current and no torque, which is what an unloaded generator does. A chain
whose last element is a one-port closes the loop back to the source. "A
circuit with no closed loop simply does nothing — not an error state, just
what an open circuit is" (electromagnetism.md, pillar 4) is therefore an
evaluation of the algebra, not a special case.

### 4. Junctions

A **series** chain is a bond-graph `1`-junction: one flow, efforts sum. That
is what the `loop` clause expresses and what ships.

A **parallel** junction (`0`: one effort, flows sum) combines affine loads
by Millman's theorem — conductances add, `e₀ = Σ(e₀ᵢ/Rᵢ) / Σ(1/Rᵢ)` — which
is closed-form too, and is the designed ⬜ `fork(a, b)` step. Until it
exists the compiler *refuses* a device that needs it, with a reason, rather
than mis-solving it (`test_a_parallel_branch_is_refused_with_a_reason`).
Series-parallel networks cover every device this project has named; a
non-series-parallel bridge topology is a genuine ⬜ beyond that.

### 5. Resolution order

Deterministic and closed-form, per tick:

1. **Compile** (`DeviceCompiler.compile`): parts → a real `PartGraph` (its
   own validation errors bubble up verbatim); laws → elements, with every
   parameter either authored or derived from a named part; the `loop` →
   an ordered chain whose first element must be a `source` and whose
   consecutive ports must agree on domain (a domain mismatch is a compile
   error naming both ports: *"wheel's output is rotation but wire's input is
   electrical"*). Compile errors name the law, part or joint they concern;
   nothing partially solves.
2. **Reduce** (`DeviceNetwork.solve`): walk the chain from its far end to
   the source, folding every element into one affine load by the rules in
   §3.
3. **Solve** the one unknown: `f_source = (e₀ − e₀_load) / (Rₛ + R_load)`.
   An infinite total resistance yields zero flow (an open circuit); a
   negative flow is legal (the loop runs backwards — a store driving the
   source) and is reported, not clamped.
4. **Propagate** forward from the source, computing each element's port
   efforts and flows and its power in, power out, dissipated, stored-rate.
5. **Step** every store: `level += stored_rate × dt`, clamped to `[0,
   capacity]`, the clipped energy reported as `overflow_j` (a full battery
   overcharged sheds the surplus as heat, as a real one does).
6. **Fire rules** (`DeviceExecutor.resolve`): the solved state becomes a
   context dictionary keyed by element id (`{filament: {effort, flow,
   power}, …}`) and every `on EVENT when GUARD: pipeline` rule for the
   requested event is evaluated against it with the same single-comparison
   guard the other DSLs use. Effects are reported as the atoms to apply;
   dispatching them into the world is the ⬜ effects layer.
   *(2026-09-05)* The compiler also exposes every **part** as facts — its
   material, geometry, role, every dimension it was declared with, its
   derived mass and span — under its part id, so a rule can read
   `bag.aperture_mm` on a device that has no loop at all. That is what lets
   the butterfly net ([capture_dsl.md](capture_dsl.md)) be a device: parts
   and rules, no energy path.

Every step is a pure function of its inputs; steps 2–5 never touch the AST
and step 6 never touches the physics.

### 6. Derived, not authored: the derivation table

When a law names a `part:`, its parameters come from that part. The kernel
derives:

| Law | From a part with geometry | Derivation | Grounding |
| --- | --- | --- | --- |
| `resist` (electrical) | `haft` (a cylinder — a wire) | `R = L / (σ A)`, `σ` from the material's conductivity scalar inverted through `conductivity_from_iacs`, `L` = length, `A` = `cross_section_cm2` | Pouillet's law; IACS definition |
| `transform` (translation→rotation) | any (a wheel) | `r = radius_m = span_cm / 200` | `τ = F r`, `ω = v / r` |
| `source` | — (no part; a world input) | `paddle_source(ρ, A, v)` → `(½ ρ C_d A v², F_stall / v)` | flat-plate drag, Thévenin secant |
| `gyrate` | — (authored `magnet_tesla`, `turns`, `area_m2`) | `k = B A N` | Faraday, rotating coil |

Anything not in this table must be authored, and the compiler says which
parameter it was missing rather than defaulting it — a defaulted resistance
is a confident, wrong current, the same class of bug `ItemPart` refuses to
commit for a defaulted dimension.

### 7. Thresholds and events

A device's rules run over its solved state. The intended failure rules
reuse material thresholds the game already has rather than inventing
ratings:

- A conductor whose dissipated power drives its temperature past
  `MaterialProperties.thermal_failure_c(material)` burns out (`melt` for
  metals, `ignite` for a wooden shaft under a hot bearing). The temperature
  model that turns dissipated watts into degrees (a lumped thermal mass with
  convective loss — a thermal-domain `store` and `resist`) is the ⬜ thermal
  loop; today an author writes the threshold as a number in the guard.
- A shaft whose torque exceeds what its section and toughness carry fails
  at `PartGraph.weakest_link()` — the same net-section reasoning
  emergent_crafting.md already computes, unread by the kernel yet (⬜).

The rule *grammar* and *evaluation* ship in full; the derived `@rating`
references are ⬜.

### 8. Determinism and units

SI throughout the solver (N, m, s, W, V, A, Pa, K). Parts keep their
existing centimetre dimensions and the derivations convert once at the
boundary. Every list is construction-ordered; the reduction and propagation
are single passes in fixed order; no dictionary is iterated for an answer.

## The DSL

### Grammar

A structural sibling of `spell_parser.gd` and `npc_instruction_parser.gd`
(and of `capture_parser.gd`, which it has since replaced — the net is device
text now) — same tokenizer, same `on EVENT(ARG) when GUARD: pipeline` rule,
same `|>`, same guard operators and operand grammar — with four declarative
clauses in front of the rules. Purely structural, like
its siblings: an unknown law or atom parses fine and is rejected one layer
up, in the compiler.

```
device   := "device" STRING "{" clause* "}"
clause   := part | joint | law | loop | rule
part     := "part" ID ":" MATERIAL GEOMETRY ROLE [ "(" params ")" ]
joint    := "joint" ID ":" ID "to" ID TYPE FASTENING MATERIAL [ "(" params ")" ]
law      := "law" ID ":" ELEMENT [ "(" params ")" ]
loop     := "loop" ID { "|>" ID }
rule     := "on" EVENT [ "(" (ID | NUMBER) ")" ] [ "when" guard ] ":" pipeline
guard    := operand OP operand                 # OP ∈ >= <= > < == !=
pipeline := step { "|>" step }
step     := ATOM [ "(" params ")" ]
params   := ID ":" value { "," ID ":" value }
value    := NUMBER | STRING | "true" | "false" | ID
operand  := NUMBER | STRING | "@" ID | ID { "." ID }
```

`part`'s three bare words are `ItemPart`'s material, geometry and role, in
that order; its params are the geometry's required dimensions. `joint`'s
`a to b` names the two members, then the joint's type, fastening and
material; a pivot or slider names its axis as `(axis: x|y|z)`. `law` names
an element kind and its parameters, `part: ID` requesting derivation from
that part. `loop` is the energy path, first element a source, each `|>` a
bond. Rules are exactly the capture DSL's rules.

### The canonical example

Electromagnetism.md's "river-powered light in the dark", as one text:

```
device "Mill Race Light" {
  part wheel: wood face working (width_cm: 200, height_cm: 200, thickness_cm: 4)
  part axle: iron haft structure (length_cm: 60, diameter_cm: 4)
  part wire: copper haft structure (length_cm: 1000, diameter_cm: 0.3)
  part filament: carbon haft working (length_cm: 2, diameter_cm: 0.01)
  joint hub: wheel to axle rigid fit iron

  law river: source(domain: translation, fluid: water, area_m2: 0.5, velocity: 1.5)
  law wheel: transform(in: translation, out: rotation, part: wheel)
  law gears: transform(in: rotation, out: rotation, ratio: 0.1)
  law dynamo: gyrate(in: rotation, out: electrical, magnet_tesla: 0.5, turns: 200, area_m2: 0.02)
  law wire: resist(domain: electrical, part: wire)
  law filament: resist(domain: electrical, part: filament)

  loop river |> wheel |> gears |> dynamo |> wire |> filament

  on step when filament.power >= 1: shine(target: filament)
}
```

Read what is *not* in it: no wattage for the bulb, no ohms for the wire, no
torque for the wheel. The river's push is momentum flux on half a square
metre of paddle in a 1.5 m/s current; the wheel's ratio is its own metre of
radius; the wire's resistance is copper's published conductivity over ten
metres of 3 mm wire; the filament's is graphite's over two centimetres of a
tenth of a millimetre. What the filament receives is what the algebra says
it receives. The one number the author *does* write that matters is the
gear ratio — and it is the model that tells them they need it (worked
example A below).

### What an author can and cannot write

- **Cannot** write a device that makes energy: no law has a gain above one
  in power. The most a transformer can do is trade effort for flow.
- **Cannot** skip a source: a loop that does not start with one does not
  compile ("a loop needs a source to drive it").
- **Cannot** join two ports of different domains: a domain mismatch is a
  compile error naming both.
- **Cannot** bypass a part's physics by typing a nicer number next to it:
  when a law names `part:`, the derivation wins and an authored value of the
  same parameter is a compile error ("wire's resistance is derived from the
  part; do not also write it").
- **Can** invent anything the algebra spans: a treadmill (`source` rotation
  from an animal's strength) → gear (`transform`) → pump (`transform`
  rotation→hydraulic) → pipe (`resist`) → cistern (`store`) is an irrigation
  works nobody has to add to the game.
- **Can** write a device with no loop at all — a net, a cage, a frame. Its
  parts compile, their dimensions become facts, and its rules read them
  (worked example G).

## Element catalog (v1)

| Element | Ports | Required params | Derivable from a part | Notes |
| --- | --- | --- | --- | --- |
| `source` | 1 (`domain`) | `effort`, `resistance` — or `fluid`, `area_m2`, `velocity` | — | Thévenin; `fluid: water|air` selects ρ |
| `resist` | 1 (`domain`) | `resistance` | yes: `haft` geometry, electrical domain | `R = L / (σ A)` |
| `transform` | 2 (`in`, `out`) | `ratio` | yes: any geometry, translation→rotation, `r` = radius | lossless |
| `gyrate` | 2 (`in`, `out`) | `ratio` — or `magnet_tesla`, `turns`, `area_m2` | — | lossless; `k = B A N` |
| `store` | 1 (`domain`) | `capacity`, `full_effort`; optional `level` (default 0), `resistance` (default 0) | — | tank; level stepped per tick |

## Worked examples

*(Every number below is produced by the shipped tests named beside it; the
prose is a reading of them, not the other way round.)*

### A — the mill race light

`test_device_book.gd`, worked end to end: the paddle source, wheel, gear
train, dynamo, wire and filament above, solved once.

- The river's stall push on 0.5 m² at 1.5 m/s is `½ · 1000 · 1.28 · 0.5 ·
  1.5² = 720 N`, internal resistance `480 N·s/m`, so it can deliver at most
  `720² / (4 · 480) = 270 W` to a perfectly matched wheel.
- The dynamo's `k = 0.5 · 0.02 · 200 = 2.0 V·s/rad`.
- The wire's resistance is `10 m / (5.80·10⁷ S/m · 7.07·10⁻⁶ m²) = 0.0244 Ω`;
  the filament's `0.02 / (2.00·10⁵ · 7.85·10⁻⁹) = 12.73 Ω`.
- **Solved.** The loaded wheel rim runs at **1.408 m/s** in a 1.5 m/s river —
  it labours by six percent — taking **44.2 N** from the water: **62.2 W**
  into the wheel. The 1:10 gears turn its 13.4 rpm into **134.5 rpm** at
  4.42 N·m; the dynamo makes **28.2 V** and pushes **2.21 A** round the
  loop; the wire drops 0.05 V (0.12 W — negligible, as a wire should be);
  the filament takes **62.1 W** — a real light bulb's worth. `shine` fires.
  Source power, wire and filament balance to the watt.
- **Take the gears out** and the same wheel runs at 1.499 m/s — almost free
  — taking 0.47 N: the dynamo makes 3.0 V, pushes 0.24 A, and the filament
  gets **0.70 W**. It does not shine. A water wheel turns at about a radian
  and a half a second, far too slow to generate from directly; real mills
  geared up by ten or more for exactly this reason, and here it is a
  consequence the solver reports
  (`test_without_a_gear_train_the_same_wheel_lights_nothing`), not a rule
  anyone wrote.
- The river's own loss — the 952 W the water spends getting past a paddle
  it cannot stall — is reported separately (`source_internal_loss`) and is
  not counted as dissipated by the device: it is the water, not the
  machine.

### B — the windmill grain mill

`test_device_book.gd`, the post mill: the same `paddle_source` with air's
density and ten square metres of sail in an 8 m/s wind (`501.8 N` stall,
`62.7 N·s/m`), a `transform` for the four-metre sail radius, a 1:5
`transform` gear pair stepping speed up, and a millstone as a 20 N·m·s/rad
rotational `resist`. No new law, no new module — a mill is a light with the
gyrator left out and a different fluid. Solved: the sail tips run at
**5.34 m/s** (12.7 rpm), taking **166.9 N** from the wind: **891 W**, all
of it into the stone, which turns at **63.7 rpm** under **133.5 N·m** —
inside the 60–125 rpm band real millstones ran at. `grind` fires.

### C — maximum power transfer, and why a bigger wheel is not always better

`test_device_network.gd::test_there_is_an_optimum_load_for_delivered_power`.
Sweep the load on a fixed source and the power delivered to it rises and
then falls, peaking where the reflected load equals the source's internal
resistance. Below the optimum the load is too free to take power off the
wheel; above it the wheel stalls. With a 100 V / 10 Ω source through a 1:2
lever and a `k = 3` dynamo the optimum bulb sits at `9 / (4 · 10) = 0.225 Ω`
and takes the source's entire 250 W ceiling — through two domain crossings
that cost nothing. Nobody wrote that in.

### D — the battery that motors the mill (series ✅; across the bulb ⬜)

Put a `store` in the loop behind the dynamo. When the river runs, the
generator charges it; when the river stops, the store's opposing effort
reflected through the gyrator is *negative* on the shaft side — it drives
the generator as a motor and the shaft keeps turning until the level hits
zero. The series form is real and pinned
(`test_a_charged_store_behind_a_generator_motors_the_shaft_when_the_river_stops`,
`test_a_charged_store_drives_the_loop_backwards_when_the_source_dies`);
putting the store *across* a bulb, so the bulb stays lit from it, is the
parallel placement that needs the ⬜ `fork` junction.

### E — the bellows furnace (⬜ needs the thermal loop)

The most valuable device this model can build, because it would replace a
table: `MaterialProperties.STATION_TEMPERATURE_C` gates the entire tech tree
with three fixed numbers (campfire 800, bloomery 1200, crucible 1600). A
bellows is a `transform` translation→hydraulic (a piston of the bellows'
area) driving airflow into a hearth whose temperature is a thermal `store`
fed by fuel and drained by a thermal `resist` to the air. Blast rate raising
temperature is real (it is why a bloomery has a tuyere) and it would turn
"which station" into "how hard are you pumping" — derived, not authored.
Designed here; the thermal domain is catalogued and excluded from power
accounting; the loop itself is ⬜.

### F — the trip hammer (⬜ needs `inertia`)

A water wheel lifts a hammer head by a cam (`transform` rotation →
translation) and drops it; the falling head's momentum resolves through
`ImpactResolver.resolve_impact` exactly as a swung hammer's does, against the
anvil's material. Needs the `I` element to carry the head's kinetic energy
between ticks, and a discrete `release` event — both ⬜.

### G — the butterfly net: a device with no loop *(2026-09-05)*

[capture_dsl.md](capture_dsl.md)'s net, authored in this grammar: a wooden
handle, an iron hoop and a fibre bag whose `face` carries an extra
`aperture_mm: 10` dimension, the way a saw's edge carries `tooth_pitch_mm`.
No `law`, no `loop` — nothing flows through a net — so the solver never
runs; the compiler builds the part graph and exposes the bag's `aperture_mm`
and `width_cm` as facts, and the net's `on catch` pipeline reads them:
`mesh_holds(mesh: bag) |> catch_roll(base: 0.65) |> confine(in: bag)`. A bee
at 6 mm across slips a 10 mm mesh, a monarch's 25 mm body does not, a 55 cm
koi does not fit a 30 cm mouth. No species is named anywhere in the text,
which is why a 1 mm-mesh insect net or a 40 cm landing net is one number
away. Solved end to end in `tests/unit/test_capture_book.gd`.

## Interaction with existing systems

| Existing module | Role in the standard model |
| --- | --- |
| `material_properties.gd` | the property vector every derivation reads; `conductivity` inverted to σ; `THERMAL_FAILURE` the intended failure thresholds; `STATION_TEMPERATURE_C` the thermal sources |
| `item_part.gd` / `part_joint.gd` / `part_graph.gd` | parts and joints, reused unchanged; `cross_section_cm2` and `span_cm` are the two geometric inputs the derivations need |
| `part_mechanics.gd` / `item_compiler.gd` | the swung-tool half of "an item is a program"; a device's rules are the same AST shape |
| `impact_resolver.gd` | where a device's delivered momentum lands (⬜ trip hammer) |
| `spell_parser.gd` / `npc_instruction_parser.gd` | the tokenizer and rule grammar the `device` parser is a sibling of (the former `capture_parser.gd` is retired in its favour) |
| `capture_executor.gd` | the guard evaluator the device executor mirrors; since 2026-09-05 it resolves the net's own device rules over the compiler's part facts |
| `open_channel_flow.gd` / `river_discharge.gd` | the real current velocity a placed water wheel's `source` will bind to (⬜ world binding) |
| `weather_model.gd` | the real wind a placed windmill's `source` will bind to (⬜ world binding) |
| `room_detector.gd` | the adjacency flood-fill that will discover bonds between placed devices (⬜) |
| `building_statics.gd` / `tunnel_support.gd` | structures as part graphs with no laws: the statics that already exist are the translation-domain limit case of this model and are not re-implemented here |

## Status

### Built and tested (✅)

*(Reconciled against the test files after the code landed — 173 tests
across eight files, `tests/unit/test_physics_domains.gd` through
`test_device_book.gd`; see `docs/progress.md` for the dated narrative.)*

- ✅ **`physics_domains.gd`** — the closed domain catalog with effort/flow
  names and units, and the power/pseudo distinction.
- ✅ **`device_elements.gd`** — the five laws as pure functions; transformer
  and gyrator losslessness asserted as properties; the two reflection rules;
  affine series composition; parameter validation per kind.
- ✅ **`device_physics.gd`** — the derivations: wire resistance from a part's
  material and haft geometry through the inverted IACS map; wheel ratio from
  span; the paddle Thévenin source from flat-plate drag; Faraday's `k`.
- ✅ **`device_network.gd`** — the closed-form series-loop solver:
  reduction, solve, propagation, store stepping, per-element power
  accounting, energy conservation across the device asserted, open-circuit
  and backward-flow cases pinned, the maximum-power-transfer optimum
  asserted as the anchor property, parallel refused with a reason.
- ✅ **`device_parser.gd`** — the grammar above; structural only; `line N:`
  errors.
- ✅ **`device_compiler.gd`** — AST → `PartGraph` + element chain; domain
  continuity checked; derived-vs-authored conflict refused; every missing
  parameter named. *(2026-09-05)* Every part exposed as facts (material,
  geometry, role, dimensions, mass, span) for rules on loop-less devices.
- ✅ **`device_executor.gd`** — solved state → context; rules evaluated with
  the shared single-comparison guard; fired effects reported.
- ✅ **`device_book.gd`** — the fixed authored examples (mill race light,
  windmill mill), parsed once and cached, solved end to end in tests.

### Designed here, deliberately not built (⬜)

- ⬜ **Parallel junctions** (`fork`) and the general `port`/`bond` topology.
  Millman closed form specified in §4; the compiler refuses rather than
  mis-solves.
- ⬜ **Inertial storage** (`inertia`, the bond-graph `I`): flywheels, a
  falling hammer head. The tank-stepping shape is identical to `store`'s;
  what is missing is the momentum-domain bookkeeping and a discrete release
  event.
- ⬜ **The thermal loop** and the bellows furnace (§ Worked example E). The
  domain is catalogued; no thermal element is solved.
- ⬜ **Derived failure ratings** (`@rating`): dissipated watts → conductor
  temperature → `thermal_failure_c`; torque → `weakest_link`. Rules fire
  today against authored thresholds.
- ⬜ **World binding**: a placed device's `source` reading the real river
  (`RiverDischarge`/`OpenChannelFlow.velocity`) or wind
  (`WeatherModel.wind_strength_for`) at its tile; bonds between separately
  placed devices discovered by adjacency (`room_detector.gd`'s flood fill,
  gated by conductivity) per electromagnetism.md. Nothing in live gameplay
  calls the kernel yet — the same honest position `ItemCompiler` is in.
- ⬜ **Effect atoms** (`shine`, `burn_out`, `grind`, …): the executor reports
  which fire; nothing dispatches them into the world.
- ⬜ **Magnetic permeability** as a material scalar (electromagnetism.md's
  proposal): `gyrate` takes an authored `magnet_tesla` until it exists.
- ⬜ **Player-facing authoring** of device text, skill gating of laws, and
  the gold-for-complexity compile gate magic.md applies to every AST —
  applicable unchanged here (a law is a line), not wired.

### Known simplifications (🚧)

- 🚧 **The paddle source is a Thévenin secant** of a quadratic drag law:
  stall force is exact, free-running speed is exact, the line between them
  is straight. The exact optimum sits at a third of stream speed; the
  secant's at half. Stated, not hidden.
- 🚧 **Faraday's `k` is the peak of a sinusoid**; the model is DC throughout,
  as electromagnetism.md already decided.
- 🚧 **A wheel's ratio is half its span**, which is a face's larger in-plane
  dimension — right for a disc, generous for a paddle that only reaches the
  water at its rim. Orientation is emergent_crafting.md's own ⬜ row.
- 🚧 **Stores are linear capacitors.** A real battery's voltage curve is
  flatter; a real reservoir's pressure is exactly linear in depth (this one
  is not a simplification for water).
- 🚧 **A joint in a device carries no law.** A pivot's bearing friction would
  be a rotational `resist` derived from the fastening; today an author adds
  one explicitly if they want it.
- 🚧 **A source's internal loss is reported, not modelled as a thing.** The
  water a paddle cannot stall carries most of the river's power straight
  past it (952 W against the light's 62 W); the solver reports it as
  `source_internal_loss` and keeps it out of the device's own dissipation.
  Where that energy goes — downstream, as it should — is the ⬜ world
  binding's concern.

## Open questions

- Should `loop` remain the concrete syntax once `fork` exists, or should
  the general `bond` form replace it? The chain reads well and covers
  everything shipped; a bond list is what a placement-discovered network
  produces. Likely both: `loop` for authored devices, bonds for the world.
- Where does a device's part graph get *its* compile — does `ItemCompiler`
  run over a device's parts too, so a wheel with a keen rim also `cut`s?
  Nothing stops it; nothing asks it yet.
- Player-visible units: watts and newtons are honest but this game shows
  descriptors, not spreadsheets (materials.md's "learning an emergent
  system"). "The wheel labours" / "the filament glows dull red" are the
  intended surface, unwritten.
- Does a burned-out wire drop its material (electromagnetism.md's own open
  question)? Unchanged here.
