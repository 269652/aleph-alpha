# Electromagnetism

> Extends [materials.md](materials.md): that doc already names **electrical
> conductivity** as one of the eight-to-ten scalars in every material's
> property vector — declared, never used. This doc is what finally uses it,
> the same way [flora.md](flora.md) later gave individual trees the DNA
> `world.md` had only gestured at. Nothing here is a bespoke "power system" —
> a water wheel, a generator, a wire, and a light bulb are each just an
> ordinary object exposing ordinary physical properties (mass, velocity,
> conductivity, a threshold), and electricity is what falls out of composing
> them, the same way cut/pierce/crush fall out of composing a blade with a
> haft.

## Design pillars

1. **One shared circuit model, composed from primitives that already
   exist.** Torque from flow is [materials.md](materials.md)'s existing
   momentum formula; a generator's leverage is the same
   `force × lever_length` relationship that already turns a sword's haft
   into cutting force; current-carrying capacity is the conductivity scalar
   materials already carry; overload failure is the same melting/damage
   threshold every material already has. No new physics primitive is
   invented — electromagnetism is what these primitives do when arranged
   in a loop.
2. **No component knows what it's connected to.** A water wheel doesn't
   know it's driving a generator; a generator doesn't know its magnet came
   from a mine instead of a mountain lion's territory; a battery doesn't
   know whether a windmill or a river is charging it; a light bulb doesn't
   know or care what's upstream. Each exposes one physical quantity (torque
   in, current in/out) and real circuit math resolves the rest — the same
   "general systems, not scripted per object" pillar
   [materials.md](materials.md#physical-interaction-verbs) already commits
   to, just for a new domain.
3. **A circuit is a real graph, discovered, not declared.** Whether two
   placed pieces are electrically connected is answered by adjacency over
   conductive material, the same flood-fill shape
   [building.md](building.md)'s room-enclosure detector already uses to
   answer "is this indoors" — not a separate "wire mode" UI or a hand-drawn
   connection graph.
4. **Real stakes in both directions.** A circuit with no closed loop simply
   does nothing — not an error state, just what an open circuit *is*. Too
   much current through too little conductivity burns the conductor out,
   using the exact same stress-vs-toughness/melting-threshold rule that
   already lets an obsidian blade shatter mid-fight. Nothing new to learn,
   same rule, new domain.
5. **Intermittency is a feature of the world you already have, not a flag
   you invent.** [weather.md](weather.md)'s wind already varies with real
   storms; a river's flow already varies with terrain. A battery only
   matters *because* generation is sometimes weak — that tension is free,
   inherited from systems that already exist.

## Real-world grounding

Three real equations, each already partially present in this project under
a different name:

- **Momentum → torque (already exists).** Moving water or air has real
  momentum (`mass × velocity`, exactly
  [materials.md](materials.md#one-damage-model-for-the-whole-world)'s
  existing formula). A wheel's paddle catches that momentum and converts it
  to torque through its own radius acting as a lever arm — literally the
  same `delivered_force ∝ head_mass × lever_length × swing_speed`
  relationship materials.md already uses to turn a sword's haft into
  cutting force
  ([Hebelwirkung/leverage](materials.md#shape-and-assembly)), just read in
  reverse: instead of a haft multiplying a swing into damage, a wheel's
  radius multiplies flow momentum into torque.
- **Faraday's law of induction, simplified.** A magnet moving relative to a
  coil of conductive wire induces a voltage (EMF) proportional to the
  magnet's strength, the coil's turn count, and how fast the magnet moves
  relative to the coil. Flattened to one "8-bit" multiplicative formula in
  the same spirit as every other formula in this project's physics docs:
  `EMF ∝ magnet_strength × coil_turns × rotation_speed`. Real generators
  produce alternating current and real electronics care about that
  distinction; this project doesn't need to — see Open questions.
- **Ohm's law + power, simplified.** Current through a closed loop is
  `I = EMF / total_resistance`, where total resistance sums every
  component's own resistance (a wire's resistance falls out of its
  material's existing conductivity scalar and its length; a load like a
  light bulb has its own fixed resistance). Power delivered is
  `P = I × EMF` (equivalently `I² × R`) — this is what sets a bulb's
  brightness, and what determines whether a wire is carrying more current
  than its own material can bear before crossing its existing melting/
  damage threshold and burning out.

## Mechanism

### Circuit topology: adjacency, not authorship

A circuit is any connected run of conductive placed pieces (wire, generator
coils, battery terminals, a bulb's filament) that includes at least one
active **source** (a generator producing EMF, or a discharging battery) and
at least one **load** (a light bulb, a charging battery). This is
structurally identical to
[building.md](building.md)'s existing room-enclosure problem — "is this
cell reachable from that cell without crossing a non-conducting boundary" —
so it's resolved the same way: a flood-fill over placed pieces, gated by
each piece's own material conductivity rather than
`BuildingPiece.encloses`'s wall/door check. **No wire-drawing tool, no
connection graph the player authors directly** — place conductive pieces
adjacent to each other and a circuit exists because the adjacency does, the
same way a room exists because the walls do.

A circuit with no source, no load, or no closed loop back to the source
carries no current — not a special case, just what `I = EMF / resistance`
evaluates to when there's no EMF or the loop never closes.

### Components

Every component below is placed through the existing Terraria-style tile
system ([building.md](building.md)) — nothing here is a new placement
mechanic, only new piece types with real physical properties.

- **Water wheel.** Spans a flowing-water tile; converts local flow momentum
  into torque via the leverage formula above. **Flow velocity isn't a
  simulated field today** (real river *geometry* now exists —
  [rivers.md](rivers.md)'s curated+procedural catalog, plus a real,
  animated flow DIRECTION reusing the exact gradient primitive this
  section already proposed — but no per-tile current SPEED/discharge
  figure is curated) — rather than adding a whole new hydrological
  simulation, flow speed would be derived from the water tile's own local
  elevation gradient (steeper drop → faster flow), reusing
  [world.md](world.md)'s already-real elevation data instead of a new
  field. A real river's steepest stretches become the valuable mill sites,
  the same way real historical mills sited themselves on real gradients.
- **Windmill.** Same torque formula, driven by
  [weather.md](weather.md)'s existing `wind_strength_for` instead of water
  flow — and since that field is *already real and simulated* (unlike
  river flow), a windmill is the cheaper, ship-first sibling of the water
  wheel: identical mechanism, zero new world-sim dependency. A stormy day
  is already a better wind day in the existing weather model; that's a
  windmill's whole value proposition for free.
- **Generator.** Takes torque in (from a water wheel, windmill, or any
  future rotational source — a hand-crank, an animal on a treadmill,
  nothing here is generator-specific about the SOURCE), produces EMF per
  the Faraday formula above. Requires a magnet and a coil of conductive
  material as its own internal parts — same (material × geometry) part
  composition [materials.md](materials.md#shape-and-assembly) already uses
  for crafted items, applied to a new kind of assembly.
- **Wire.** Any placed run of conductive material. Its resistance derives
  from its material's conductivity scalar and its length — copper (high
  conductivity) makes a genuinely better wire than iron (lower
  conductivity, and see Magnetism below for why you'll still want iron
  around); wood or stone simply doesn't conduct and can't complete a
  circuit at all.
- **Battery.** Stores charge from surplus current, discharges to sustain a
  circuit when generation drops or stops — a real tank model (a capacity,
  a current level), not a binary "has power" flag. Only matters *because*
  wind and river flow are variable (see Design pillars) — a battery next to
  a generator that never stops turning is just an expensive wire.
- **Light bulb** (a load). Converts delivered power into light (and heat),
  brightness scaling with power (`P = I × EMF`). A natural, if not
  immediate, tie-in: a lit bulb is a real light source, sitting alongside
  [world.md](world.md)'s existing day/night `CanvasModulate` lighting
  rather than replacing it — a player-built light overriding the dark
  exactly where it's placed.

### Magnetism: a material property, not a separate system

Real magnetism only applies to specific materials (iron, nickel, cobalt,
and their natural ore, magnetite/lodestone) — this is a genuinely new
scalar, not a reuse of conductivity (copper conducts excellently but isn't
magnetic at all; iron conducts less well but *is* magnetic — real-world
accurate, and it means a generator genuinely wants both materials for
different parts, a real sourcing decision in the same spirit as
[materials.md](materials.md#the-core-idea)'s "no material is simply
better"). Proposed addition to materials.md's existing property vector:
**magnetic permeability**, near-zero for almost everything, real only for
iron/nickel/cobalt and their ores.

- **Found, not just crafted.** Magnetite is a real, naturally magnetic
  iron ore — the existing ore system ([ore_placement.gd](../../src/world/ore_placement.gd),
  today `iron`/`copper`/`coal`) is the natural home for a fourth ore type
  rather than a bespoke "find a magnet" mechanic.
- **Craftable too.** Real iron can be magnetized by repeated stroking with
  an existing magnet, or by proximity to strong enough current (the same
  induction relationship running in reverse) — a real, simple crafting
  chain (ordinary iron + an existing magnet → a new magnet) rather than
  magnetite being the only source.

## Worked example — "a river-powered light in the dark"

Nothing below is scripted for "light bulb"; every step is a general system
composing, mirroring [materials.md](materials.md#worked-example--throw-the-oil-barrel-into-the-torch-lit-room)'s
own oil-barrel example:

1. A water wheel spans a river tile with a real elevation gradient →
   real flow momentum → real torque, via the same leverage formula a
   weapon's haft already uses.
2. That torque turns a generator's magnet past a copper coil → real EMF,
   via the Faraday formula, using copper specifically for its high
   conductivity (not iron — iron's own value here is being magnetic, not
   being wired).
3. A run of copper wire (adjacency-discovered, not hand-connected) closes
   a loop from the generator to a battery and a light bulb → real current,
   via Ohm's law over the loop's total resistance.
4. At night, the river's flow hasn't changed — the bulb stays lit exactly
   as brightly as the circuit's power delivery says it should, with no
   day/night special case anywhere in this doc.
5. A drought that runs the river shallow (an existing, already-simulated
   [weather.md](weather.md) condition) lowers the elevation gradient's
   effective flow, which lowers torque, which lowers EMF, which dims the
   bulb — the battery is what buys time until the flow recovers, exactly
   the intermittency tension Design pillar 5 promises, for free.

Momentum, leverage, conductivity, magnetism, and a threshold-gated overload
rule are each independent general systems, most already existing before
this doc. The lit bulb is emergent, not authored.

## Open questions

- **River flow DIRECTION and SPEED as elevation gradient are now both
  validated visually**, ahead of any water wheel: [rivers.md](rivers.md)'s
  `RiverFlowShader`/`_paint_river_flow_overlay` (2026-08-29, speed added
  2026-08-29 after "more natural water flow" feedback) computes both
  `TerrainRelief.aspect_degrees_from_gradient` (direction) and
  `slope_degrees_from_gradient` (speed, via `RiverFlowShader.
  speed_fraction_for_slope_deg`, anchored at `TerrainPassability.
  HARD_THRESHOLD_DEG`) per river cell and drives a real, tested, animated
  visual from both. **Still not validated: DISCHARGE-accurate speed** —
  the visual's speed is real GRADIENT-derived, not derived from actual
  water volume/channel width, since no per-river discharge data is
  curated to ground it against and no water wheel yet exists to consume a
  torque number either way. Still needs a real discharge formula and a
  test once a water wheel is actually built, the same "tuned function, not
  eyeballed constant" discipline every other threshold in this project's
  docs already commits to.
- **AC vs. DC.** Real generators produce alternating current; real
  batteries store direct current, and real electronics care about the
  difference. This doc deliberately flattens both to one scalar "current"
  value — revisit only if a real gameplay reason to model the distinction
  shows up (a resource/tech-tree gate at some future era transition,
  perhaps — see [eras.md](eras.md)'s industrial-age pillar).
- **Exact EMF/resistance/power constants** — real formulas, tuned
  coefficients deferred to implementation and pinned by tests, per this
  project's no-manual-tuning rule.
- **Magnetic permeability's exact scalar range and which existing materials
  get a nonzero value** — a small, bounded addition to
  [materials.md](materials.md#the-material-property-vector)'s existing
  vector, needs its own numeric pass alongside that doc's own open
  question on exact scalar units.
- **Multi-tile components** (a water wheel spanning more than one tile) —
  `docs/progress.md`'s Building section already tracks multi-tile
  footprints (`BuildingBlueprint`) as partial/not-wired-to-live-placement;
  this doc's components would be the first real consumer once that lands,
  not a reason to block on it — a single-tile water wheel is a reasonable
  first slice.
- **Does a burned-out wire drop its own constituent materials**, mirroring
  [materials.md](materials.md#one-damage-model-for-the-whole-world)'s
  "breaking terrain drops its constituent materials" rule? Probably yes,
  for consistency, but not decided here.

## Status

**Revised 2026-09-05.** The circuit *algebra* this doc describes is no
longer a special case waiting to be built: [standard_model.md](standard_model.md)
generalises it into one physics for every device, and its shipped kernel
implements exactly this doc's chain as its first worked example. Torque
from flow is a `transform` (the wheel's radius) fed by a paddle `source`
whose stall force is the flat-plate drag law; the generator is a `gyrate`
whose ratio is Faraday's `k = B A N`; a wire is a `resist` whose ohms come
from its material's conductivity scalar and its real length and section
(so copper beats iron by the published 6.4× and wood cannot complete a
circuit at all); a battery is a `store`; Ohm's law is the loop solve; and
"an open circuit simply does nothing" is what the algebra evaluates to.
The river-powered light of this doc's worked example is solved end to end
in `tests/unit/test_device_book.gd` — with one lesson this doc did not
anticipate: the wheel needs a 1:10 gear train to light anything, because
a water wheel turns far too slowly to generate from directly.

What remains specific to this doc, all still ⬜: circuit topology
discovered by adjacency over placed pieces (the `room_detector.gd`
flood-fill generalised to conductivity — the kernel solves an *authored*
loop, not a placed one); the magnetic-permeability scalar and magnetite
ore (a generator's field strength is an authored `magnet_tesla` until it
exists); wire burnout as a *derived* rating (the rule grammar fires today
against an authored threshold); a lit bulb as a real light source; and the
world binding that reads a real river's current or the real wind at a
placed device's tile. See `docs/progress.md`'s Electromagnetism and
Standard Model entries.
