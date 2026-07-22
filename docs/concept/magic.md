## Magic: a spellcrafting DSL

A unique magic system based on our own in-game "magic DSL": skills, spells,
and effects are all implemented via a small language that lets players design
their own spells, Morrowind-style. There's also a normal magic skill tree the
player must progress through before they're allowed to design their own
spells (see [Skill-tree gating](#layer-1-skill-tree-gating) below).

### Primitive effects: fine-grained atoms

Rather than a handful of coarse verbs, magic is built from **dozens of
narrow, atomic effects** (à la *Magicka*): `FireDamage`, `FrostDamage`,
`ShockDamage`, `PoisonDamage`, `MinorHeal`, `MajorHeal`, `Push`, `Pull`,
`Slow`, `Root`, `Shield`, `Reveal`, `Summon:Wisp`, `Ignite`, `Freeze`,
`Levitate`, etc. A spell is a small composition of these atoms plus a
delivery method (touch / projectile / area / self) and a shape modifier
(point / cone / line / burst radius).

This is more combinatorial and more fun to discover than a coarse-verb
system (`Fire` + `Frost` atoms colliding to make steam that obscures vision,
`Shock` + standing water conducting to a wider area — Magicka's whole
appeal) — at the cost of needing real balance discipline, which the two
constraint layers below exist to provide.

### Constraint layer 1: resource cost scales with power

Mana/stamina/cast-time cost is a **deterministic function of the atoms and
parameters chosen** — magnitude, radius, duration, and atom rarity all feed
a cost formula. There is no way to express "large effect for free"; the DSL
literally cannot represent it, because cost is derived, not authored.
Diminishing-returns curves on magnitude keep min-maxed single-atom spam from
being strictly better than varied compositions.

### Constraint layer 2: physical simulation checks

On top of cost, effects must obey the world simulation, same physics/rules
combat and the ecosystem already respect (see [combat.md](combat.md),
[world.md](world.md)):

- Projectile-delivered effects **travel** at a real speed and can be dodged,
  blocked by terrain, or intercepted — no instant-hit spells regardless of
  how much mana you spend.
- Area/summon effects need physical space to resolve in — you can't summon
  something inside solid rock, or drop a burst radius that clips through a
  wall it should be blocked by.
- Push/Pull/knockback obey mass — a `Push` atom moves a rat much further
  than it moves a bear, and moves nothing at all through a wall.
- Environmental interactions are real: `Ignite` on oil-slicked or grassy
  terrain spreads exactly like the non-magical fire in
  [combat.md](combat.md); `Freeze` on water makes it walkable; `Shock` on
  standing water conducts to everything touching it.

Together, layers 1 and 2 mean a spell can never be "free," and even a
spell whose cost you can afford still has to actually land — giving every
overpowered-looking composition a real tactical counterplay window.

### Layer 0 (prerequisite): skill-tree gating

Before any of the above is available, a player has to progress a
conventional magic skill tree (see [skills.md](skills.md)) that
incrementally unlocks: which atoms you know, the parameter ranges you're
allowed to push them to (e.g. max radius, max magnitude), and eventually the
spell-editor/DSL tool itself. This is the *access* gate; layers 1-2 are the
*power* gate. A max-level player with every atom unlocked still can't
express something the cost formula and physics won't allow.

### Open questions

- Exact atom list and cost-formula shape — needs a first-pass numeric
  design once we're implementing rather than conceptualizing.
- Do atoms have elemental interactions beyond the fire/frost/shock examples
  above (a fuller reaction matrix, Magicka-style), and if so, how many
  reaction pairs are worth the complexity for a solo/part-time project?

**Resolved**: spells are tradeable — see
[items.md](items.md#spells-as-items). A designed spell can be crystallized
into a scroll/gem item, so spellcrafting feeds the wider item economy
instead of staying purely personal/character-bound.

---

## Brainstorm extensions (2026-07-15)

Decisions from the design pass captured in [synthesis.md](synthesis.md);
these extend, not replace, the model above.

### Spells inject *forces*; the shared sim resolves them

The deepest framing (parallel to [materials.md](materials.md)'s one physics
model): a high-tier spell doesn't script an outcome, it **injects a force into
the same simulation the whole game runs on**, and the world does the rest —
`Ignite` adds *heat*, and oil catching, spreading, flashing water to steam, and
melting ice are all the *general* physics, not spell-specific code. Low-tier
spells stay discrete authored effects (accessible); the DSL is the master's
tool for authoring raw forces. Magic is thus another way to feed the
`mass × velocity` / heat / charge model in [materials.md](materials.md) — a
conjured boulder and a thrown one resolve identically.

### The primitive domains go beyond the physical

The atom catalog spans four domains, not just elements:

- **Physical** — heat, cold (heat-removal), kinetic force/momentum, charge.
  The elemental substrate the physics sim already respects.
- **Biological / genetic** — accelerate growth, heal tissue, induce/suppress
  **mutation**, blight/wither. Magic that acts on the *life-system* itself,
  making the mage a **genetic engineer with spells** and tying magic directly
  to the [dna.md](dna.md)/[evolution.md](evolution.md) north star. (This is the
  "inducible via breeder/mage skills" mutation path referenced in
  [synthesis.md](synthesis.md).)
- **Perceptual / mental** — light/dark, fear, calm — hooks into creature
  temperament (a *calm* atom aids taming, [pets.md](pets.md)) and NPC minds.
- **Spatial** — teleport, portal, gravity-shift — mobility/logistics, ties to
  [transportation.md](transportation.md).

### A third power axis: material components

Beyond mana/cost (Layer 1) and physics (Layer 2), spells can **consume
material components** — genetic or mined mats (a fire gem, a frost hide) — so
casting draws on the same economy crafting does. Big effects cost energy *and*
scarce matter.

### Master tier: freeform node-graph authoring

Above the atom-composition DSL sits a **freeform node-graph editor** — wire
primitives, deliveries, shapes, and modifiers together like a visual program.
This is deliberately the *same authoring shape* as crafting's part-graph and
the NPC instruction graph: **compose primitives into a graph, let the
deterministic sim resolve the emergent result.** One creative grammar, pointed
at forces instead of parts.

### Balance = three self-policing pressures (not nerf-lists)

Anti-degeneracy comes from the systems, not a patch list: **energy
conservation** (a game-breaking effect costs game-breaking energy), **diminishing
returns** on stacking, and **emergent counterplay** (every force has a physical
answer — fire↔water, force↔immovable mass, shock↔insulation). Access/parameter
gating stays [dna.md](dna.md)-resonance-flavored on top.

### Physical honesty cuts both ways — caster self-danger is real

Because spells are forces the sim resolves, they **backfire on the caster**:
inject heat next to yourself and *you* burn; the sim does not spare the one who
cast it. Positioning and standoff distance are genuine tactical decisions
(BG3-style fireball-in-melee risk). **Decided**: caster self-danger is canon.
**Still open (lighter/undecided)**: how far to extend blowback to *allies and
your own camp* (friendly-fire on spreading surfaces) and whether a badly
composed master spell can *catastrophically mis-fire* (wild-magic-style
authoring risk) — both are plausible but not committed.

### Spell gems are sealed IP, priced by complexity

Refining the tradeable-spell note above: a crystallized spell gem is
**use-only, not forkable** — a buyer can *cast* the author's spell but cannot
open, learn, or modify it. The authoring *knowledge* stays with the mage who
composed it; the gem is a sealed good. A gem's **rarity/value derives from the
spell's complexity and material cost** (a costly-to-author spell is a rare
gem), slotting into the shared item rarity vocabulary
([items.md](items.md)/[dna.md](dna.md)). This makes a mage's authored library a
real piece of personal IP and a market of *effects* — distinct from a market of
*recipes* — without letting buyers strip-mine the author's designs.
