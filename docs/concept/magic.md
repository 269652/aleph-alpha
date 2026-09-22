## Magic: a spellcrafting DSL

A unique magic system based on our own in-game "magic DSL": skills, spells,
and effects are all implemented via a small language that lets players design
their own spells, Morrowind-style. There's also a normal magic skill tree the
player must progress through before they're allowed to design their own
spells (see [Skill-tree gating](#layer-1-skill-tree-gating) below).

How a parsed spell actually executes — the cast trigger, targeting, the new
mana resource, and each atom's real mechanical effect — is specified
separately in [spell_runtime.md](spell_runtime.md), scoped to a player
casting a spell they already know (enchantments and NPC instructions, this
model's other two surface forms, stay unwired).

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
instead of staying purely personal/character-bound. See the 2026-08-24
brainstorm below for the two distinct vessels (sealed gems vs. teachable
scrolls) and the gold cost of compiling a spell in the first place.

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
*recipes* — without letting buyers strip-mine the author's designs. See the
2026-08-24 brainstorm below for **scrolls**, the teachable counterpart to
this sealed vessel, and for the separate gold cost of compiling a spell at
all (distinct from this section's *sale* price).

---

## Brainstorm extensions (2026-08-24)

Answers the open request "players craft their own spells with the DSL; the
ops available depend on skill; crafting costs money, more LOCs costs
exponentially more; spells go on scrolls, get sold, and others can learn and
use them if requirements are met." Extends, not replaces, the model above —
in particular it does not touch Constraint layer 1 (mana, paid every *cast*)
or the sealed-gem decision above (unchanged); it adds a third, independent
gate on top of Layer 0, priced in gold instead of mana, plus a second
tradeable vessel alongside gems.

### The compilation gate: crafting costs gold, exponential in complexity

Everything above prices *casting* a spell you already know (mana/stamina,
paid every time — Constraint layer 1) or *authoring permission* (which
atoms/params you're even allowed to write — Layer 0). Neither prices the act
of **compiling** a finished design into a spell you permanently know. That's
a third, independent gate, paid in **gold, once** — not mana, not repeatedly:

- **LOC is the pipeline-step count.** A spell/enchantment/instruction's
  "lines of code" is the total number of atom calls across every
  `on EVENT: PIPELINE` rule in its AST (`fire_damage(...) |> ignite(...)` is
  2 lines; a three-rule enchantment with 2/3/1-step pipelines is 6 lines).
  This falls straight out of the AST the parser already produces — nothing
  new has to be authored to measure it.
- **Cost grows exponentially with LOC, not linearly or polynomially.** Each
  additional line **multiplies** the gold price by a constant growth factor
  rather than adding a flat or diminishing increment:
  `gold_cost = CRAFT_BASE * CRAFT_GROWTH ^ (weighted_loc - 1)`. This is
  deliberate: a linear or even polynomial cost still lets a patient player
  grind gold for an arbitrarily long, arbitrarily powerful spell — a genuine
  compounding exponential makes each extra line a real economic decision and
  rewards *elegant* short compositions over *long* ones, the authoring-side
  mirror of the magnitude/spam-penalty curves Constraint layer 1 already
  applies to casting.
- **Lines aren't uniform — atom tier weighs in.** `spell_atom_catalog.gd`
  already tiers every atom (see Primitive effects above); a line using a
  higher-tier atom counts as more than one "line" toward `weighted_loc` — a
  rarer, more dangerous verb should cost more to fix permanently into a
  spellbook than a common one, on top of the exponential curve itself. Exact
  tier weights and `CRAFT_BASE`/`CRAFT_GROWTH` are a first-pass numeric
  design for implementation time, pinned by a property test like every other
  cost constant here, never eyeballed.
- **Paid once per design, not once per compile.** Gold is charged the first
  time a given AST (content-addressed — same rules, same atoms, same params)
  is successfully compiled into a known spell; recompiling an *unchanged*
  draft is free, and changing even one parameter is a new design that pays
  again. A spell, once known, **stays known** even if a later respec would
  no longer let its owner *author* it from scratch — compiling fixes the
  pattern permanently, it doesn't lease it.
- **Applies uniformly across all three surface forms.** Per the unifying
  model (a self-cast spell, a weapon enchantment, and an NPC instruction are
  the same underlying object), the same gold-for-LOC gate applies whether
  the AST being compiled is a personal spell, a weapon's bound rules, or an
  NPC instruction script — it's a property of the AST, not of which context
  consumes it.
- **Where the gold is paid** is likely an arcane-forge-style crafting
  station, reusing [crafting.md](crafting.md)'s already-built tier-gated
  station pattern (`crafting_station.gd`) rather than inventing a parallel
  one. Exact tier thresholds are open (see below).

Layer 0 decides *whether you're even allowed to write this line*; this gate
decides *what fixing it into your spellbook costs*; Constraint layer 1
decides *what casting it costs every time after that*. Three independent
gates on the same AST, not one blurred cost.

### Two vessels for a finished spell: sealed gems vs. teachable scrolls

A compiled spell crystallizes into a tradeable item two ways, for two
different purposes:

- **Spell gems — sealed, use-only, no requirements** (unchanged from the
  decision above). A gem lets a buyer *cast* the author's spell, as on-item
  charges, without ever learning, inspecting, or modifying it. No
  skill/atom requirement gates *using* one — the gem holds the knowledge,
  not the wielder. The right vessel for a top-tier design nobody but the
  author should ever be able to reproduce.
- **Spell scrolls — teachable, requirement-gated, consumed only on
  success.** A scroll instead carries the *readable* AST. Reading one
  **attempts** to permanently teach the spell to the reader's known-spell
  list, gated by the exact same predicate Layer 0 already uses for
  authoring: every atom the spell uses must be unlocked on the reader's own
  skill tree, every parameter within their own caps (see
  [skills.md](skills.md)). Meet the requirements and the scroll is
  consumed, the spell is now permanently known — mana cost and casting
  behave identically to having written it yourself. Don't meet them and
  nothing happens; the scroll is **not** consumed, so an underleveled buyer
  can hold onto one and try again once they've grown into it rather than
  wasting the purchase.
- **The crafting gold cost is paid once, by the original author — never
  re-charged to learners.** A scroll's market price (informed by
  `rarity_tier.tier_from_complexity`, already pure/tested against the same
  complexity score the gold-cost formula above uses) is how the author
  recoups that cost and profits. Buying and successfully learning from a
  scroll is a purchase, not a second compile.

This is the resolution to "spells can be put on scrolls and sold and others
can then learn and use the spell if requirements are met": gems sell an
*effect* without the *recipe*; scrolls sell the *recipe* itself, gated by
the same access rules the game already uses to decide who's allowed to
write it in the first place.

### Open questions (2026-08-24)

- Exact `CRAFT_BASE`/`CRAFT_GROWTH`/per-tier weight constants — first-pass
  numeric design at implementation time, same as every other cost constant
  in this doc.
- Should guard-expression / targeting-selector complexity also count toward
  `weighted_loc`, to prevent offloading complexity into the parts of a rule
  the pipeline-step count doesn't see (a player writing one enormous `when`
  guard to dodge the per-line gold cost)?
- Does scroll-learning need a coarser raw level/skill-point floor on top of
  per-atom unlocks, or is "every atom unlocked, every param in-cap" a
  sufficient requirement on its own?
- ~~Exact station-tier thresholds for compiling (or whether compiling needs a
  station at all vs. being available from any spell-editor UI).~~ **Answered
  2026-09-19** below: it needs a station, and the station is the `mage_guild`
  a settlement may only raise at CITY tier.
- Can an NPC "study" a scroll the same way a player does, feeding
  [npc.md](npc.md)'s instruction economy — an NPC mage that learns spells
  from what it's traded, not just what it's scripted with?

---

## Brainstorm extensions (2026-08-28)

### Atom effects render as composite spritemaps, one per atom (2026-08-28)

Resolves "how are magic-item attacks rendered" from
[item_illustrations.md](item_illustrations.md), which this section belongs
to conceptually — items and atoms share the same underlying illustrated-
sprite engine (`illustrated_animal_sprite.gd`'s proven canvas/chroma-key/
divider-line/action-fallback pattern), just keyed differently.

**Per atom, not per spell.** A spell is a player-composed pipeline of atoms
(`fire_damage |> ignite`) — open-ended in combination, since the whole point
of the DSL is that players compose their own. A sheet per *compiled spell*
would need one hand-drawn asset per possible composition, which doesn't
scale. A sheet per *atom* needs exactly one per entry in
`spell_atom_catalog.gd` (~25 today, one more whenever a new atom is added),
and a cast plays back its pipeline's atoms' effect sheets in the same
sequence the mechanics already resolve them in — the visual composes exactly
the way the DSL itself composes.

**Two independent halves**, mirroring the existing split in `character_view.gd`
between the weapon sprite and its swing:

- **Caster gesture** — reuses the existing `WeaponSwing`/`ToolSlot`
  procedural rotation unchanged, no new art. Per-item swing art is a
  separate, explicitly deferred idea (see item_illustrations.md) and isn't
  needed for a spell to visibly resolve.
- **Effect sheet** — a new small spritesheet per atom, played at the target/
  impact point (or along a travel path, for a delivery method that has one —
  none exist in the engine yet for anything, magical or not; see Open
  questions). Same house convention as the Krampus ability sheets
  (`docs/art/ai_sprite_prompts.md` §6): one horizontal row, solid magenta
  `#FF00FF` chroma-key, near-white divider lines, a short wind-up/peak/
  recovery beat structure — scaled down from that doc's 8-frame/2200×900
  export target, since a hand-cast atom effect is a much smaller on-screen
  element than a boss's own body.

**Category groups the authoring, atom id keys the lookup.** The catalog's
existing `category` field (damage/heal/control/movement/defense/summon/
utility/biological/perceptual/spatial) already groups atoms that share a
family "motion language" — every `damage` atom is a single instantaneous
burst at the target, every `control` atom is a lingering status loop, every
`movement` atom is a directional force at the target — which keeps the ~25
sheets reading as one coherent set. Each atom still gets its own distinct
sheet: `fire_damage`/`frost_damage`/`shock_damage`/`poison_damage` are all
`damage`-category but cannot look alike.

**Procedural fallback first**, the same two-track pattern every other
subject in this engine already follows (`ProceduralItemSprite`,
`ProceduralAnimalAnimation`, `ProceduralCharacterSprite`): every atom must
render something correct from `category` + `tier` alone — a color per
category, a simple shape/motion per category, size/intensity scaled by tier —
before any hand-drawn sheet exists for it. Magic can ship playable the
moment a runtime executor exists; illustrated sheets are then an incremental,
atom-by-atom upgrade, never a blocker.

**Explicitly out of scope here: the runtime executor itself.** Nothing in
the engine today turns "a player pressed cast" into any effect at all,
magical or visual — `spell_parser.gd`/`spell_atom_catalog.gd`/`spell_cost.gd`
are pure, scene-tree-free math (see `docs/progress.md`'s magic entry). This
section specifies only what that executor should render once it exists, not
the executor.

Open questions:

- Delivery-method visuals (touch/projectile/area/self): no travel-time/
  flight visual exists anywhere in the engine yet, for anything — even a
  thrown rock teleports straight to its resolved landing point. A
  projectile-delivered atom's effect sheet needs a travel-phase convention
  this section doesn't yet specify.
- Do reacting atoms (fire + frost → steam, per this doc's own open question
  on elemental interactions above) need a third sheet for the reaction
  product itself, on top of each reacting atom's own sheet? Not decided.

---

## Brainstorm extensions (2026-09-19)

### The mage guild is the compile station — and a city is what holds one

Answers this doc's own standing open question from 2026-08-24: *"Exact
station-tier thresholds for compiling (or whether compiling needs a station
at all vs. being available from any spell-editor UI)."*

**It needs a station, and the station is a chartered building.**
[settlement_charter.md](settlement_charter.md) already builds the gate: a
`mage_guild` may only be raised by a settlement that has reached CITY tier,
which `settlement_tier.gd` measures as households *and* active institutions
*and* production diversity, all three crossed together. That was built as a
progression system whose currency is somebody else's prosperity. This
section is the other half of that trade — the part that says what the
player actually *gets*.

The two docs need each other to make sense. A gate with nothing behind it
is a locked door in a field; a compile station available from any menu
makes the charter ladder pointless. Putting the station behind the charter
means **the way into higher magic is through a village you helped grow**,
not through a level-up. That is the single design claim this section makes,
and everything below is its mechanism.

**Why a station at all, rather than a spell-editor UI anywhere.** The three
gates this doc already names are deliberately independent — Layer 0 decides
what you may *write*, the compilation gate what *fixing it* costs, Constraint
layer 1 what *casting* costs. A station adds a fourth axis that none of the
three can express: **where**. Skill is yours, gold is yours, mana is yours;
a guild belongs to a *place*, and a place can be helped, neglected, or lost.
That makes the magic system reach into the settlement economy rather than
sitting beside it. It is also exactly the pattern [crafting.md](crafting.md)
already proved with `crafting_station.gd` and the furnace/campfire heat-
source gate — a real structure you must be standing near, checked with the
same `has_structure_near` proximity every other station interaction uses.

### Tuition: what a guild sells before the editor exists

There is no spell-authoring UI yet — `spell_book.gd` is a fixed table of
pre-authored spells, and says so in its own header. The honest first trade
for a guild is therefore not compiling (there is nothing to compile from)
but **teaching**: gold for a spell out of the world's catalogue that you do
not yet know.

This is not a placeholder bolted on beside the compile gate. It is the
**access layer** the compile gate was always going to need and which does
not exist in code today, and it is worth stating why that layer is the real
missing piece:

- **A known-spell set has to exist before anything can grant one.**
  `SpellBook.has()` today conflates two different facts — *this spell exists
  in the world* and *you can cast it*. Every access mechanism this doc has
  brainstormed (scroll-learning, compiling, an NPC studying a traded scroll)
  is a write to a per-caster known set that nothing currently has. Splitting
  catalogue from known set is the prerequisite for all of them.
- **A gold-for-knowledge transaction has to exist.** The compile gate is
  priced in gold, paid once, per design. Nothing in the codebase yet charges
  gold for a permanent capability at all.
- **A structure gate on magic has to exist.** Named above; nothing checks it.

Tuition is those three, built for the case where the AST is already
authored. When the editor lands, compiling reuses all three unchanged and
adds only its own price curve.

**The catalogue is the world's; the known set is yours.** A caster starts
knowing exactly one spell. That starting set is a pinned constant, not a
comment, and it must contain whatever the cast key is bound to by default —
a character who cannot cast the spell the game binds to their cast button is
a bug, not a gate. Everything else in the catalogue is a purchase.

**Tuition is priced as a purchase, not as a compile.** This matters and is
not a shortcut. This doc already ruled, in the scrolls section, that *"the
crafting gold cost is paid once, by the original author — never re-charged
to learners"*: a learner buys a finished design, so charging them the
author's exponential-in-LOC compile price would bill the same design twice.
A purchase price is therefore **linear in the spell's derived power**, with
the exponential reserved for the act of fixing a *new* design into a book:

- **Power is `spell_cost.gd`'s `derived_base`** — the composition cost times
  the delivery multiplier, the same number that already prices the mana of
  every cast, and the same one the scrolls section already nominates for
  pricing a vessel. No second measure of "how big is this spell" is invented
  here.
- **Rarity multiplies it, via the vocabulary that already exists.**
  `rarity_tier.tier_from_complexity` maps that identical `derived_base` to a
  tier, and `stat_multiplier` prices the tier — both already pure and
  already test-pinned. A strictly monotonic price in power, kicked up a step
  where the power crosses into a rarer band. Nothing about a spell's price
  is typed in by hand.
- **The gold-per-power anchor is a meal, read live from the shop.** A tuned
  constant here would be an invented number. Instead the anchor is *how many
  meals a point of spell power is worth*, multiplied by whatever
  `shop.gd`'s catalogue actually charges for one. Price a spell in bread and
  it stays honest when bread moves: the anchor is a ratio between two things
  the game already prices, not a third price pulled from nowhere.

**What the anchor constant encodes is a weight class, not a price**, and
three claims asserted against the live `Shop.CATALOG` are what stop it being
a matter of taste: the cheapest lesson in the world costs more than any tool
or weapon a merchant sells; the cheapest lesson lands between the cheapest
and the dearest house blueprint; and the dearest lesson exceeds the dearest
thing on any shelf. Together they admit roughly **10..39** meals per power
unit and nothing outside — deliberately a **wide** band, because a weight
class is a wide thing and a tight one would claim a precision this design
does not have.

The resulting scale, at the shop's current 4-gold meal, spans real ground:
Farsight 123 gold (about a small-house blueprint), Minor Heal 128, Frost
Lance 236 (about a cottage), and — only from an archmage, see
[mage_guild.md](mage_guild.md) — Call Wisp at 785, more than twice the
dearest thing any merchant stocks. Real money to a new character; a genuine
expedition for the deep end. Every one of those numbers falls out of the
formula; none is typed in.

An earlier version of this section claimed the band was 10..20 and that *no*
spell should cost more than the dearest shelf item. Both were true of a
three-spell starter book and stopped being true the moment the catalogue
grew real tier-3 magic — correctly so, since a lesson from an archmage
should not be purchasable at a market stall. The claim moved rather than the
number.

### The refusal is the feature

A guild that answers "no" is useless; a guild that answers **why** is a
quest hook. Tuition refusals follow the same shape
`settlement_charter.refusal_for` established — `{}` for "nothing is wrong",
otherwise a dict naming the fact. A spell the world's catalogue does not
hold is refused first and flatly, since there is nothing there to price;
past that there are exactly three ways to be refused, each of which points
somewhere:

- **No guild within reach.** Points at the charter ladder: go find, or grow,
  a city. The refusal carries the building id so the UI can name it.
- **Already known.** Points at the rest of the catalogue.
- **Short of the price.** Carries the price *and* the shortfall, so the
  answer is "come back with 40 more gold", never a bare "you can't".

A refusal is checked in that order and **never charges**: gold moves only on
a learn that actually lands, the same conserving discipline
`village_estates.md`'s baskets and `guild_relief.gd`'s chest already hold
themselves to.

[mage_guild.md](mage_guild.md) later added two more, for the same reason
and in the same shape — `OUTSIDE` (you are not in the guild) and
`NO_MASTER` (you are, and nobody here holds that tradition, which carries
the school and depth to go looking for). The refusal order there is stated
as a contract because each step is a precondition of the next.

### Status

- ✅ The mage guild is the compile station, gated at CITY tier
  (`settlement_charter.gd`, shipped before this section).
- ✅ Known spells are a per-caster set distinct from the world catalogue;
  a caster starts with `SpellTuition.STARTING_SPELL_IDS` and casting an
  unknown spell is refused (`spell_tuition.gd`, `scenes/player.gd`).
- ✅ Tuition: price derived from `derived_base` × rarity multiplier ×
  meal-anchored gold-per-power, refusal dict naming which gate failed,
  gold charged only on success (`spell_tuition.gd`).
- ✅ Learning is gated on **being inside** a real placed `mage_guild` that
  has a master in residence who teaches the spell — see
  [mage_guild.md](mage_guild.md), which took the teaching off the building
  and put it on the people in it. An earlier version of this gate was
  proximity (`has_structure_near`); standing beside a guild is now standing
  outside it, and an apprenticeship is to a person rather than a building.
- 🚧 **Compiling itself is still unbuilt** — there is no spell-editor UI and
  so nothing to compile. `CRAFT_BASE`/`CRAFT_GROWTH`/per-tier LOC weights
  from the 2026-08-24 section remain unimplemented. Tuition builds the
  access layer they will sit on (known set, gold-for-knowledge, station
  gate), not the price curve itself.
- 🚧 **Scrolls and gems are still unbuilt.** Scroll-learning writes to the
  same known set tuition now writes to, so the vessel is what is missing,
  not the destination.
- ✅ **A spell you chose** (2026-09-21) — corrected here on 2026-09-22,
  because this entry went on claiming the opposite after it had shipped.
  The cast key no longer casts `DEFAULT_CAST_SPELL_ID`: a four-slot bar
  holds the Nth entry of `known_spell_ids()`, its keys cast *and* select,
  and the cast key repeats the selection. `DEFAULT_CAST_SPELL_ID` survives
  only as the fallback when nothing is selected.
- ✅ **The starting hand is one spell per delivery** (2026-09-22).
  `STARTING_SPELL_IDS` was `["fire_bolt"]`, and Fire Bolt is `cast(touch)`
  — `SpellTargeting.TOUCH_RANGE` is **24 px** against the sword's
  `ATTACK_RANGE` of **20**. So **nothing a normal player could cast reached
  further than a sword**, ever: the mage traded 15 `max_health` for the
  privilege of standing inside a bear's windup, and the three authored
  projectile spells were parsed, priced, tested and reachable only through
  the `/learn` dev console.

  The hand now teaches the three verbs a caster has rather than the same
  verb once — `fire_bolt` (touch, the jab), `spark` (projectile, **120 px**,
  the reason to be a caster at all) and `minor_heal` (self, the answer to
  having been hit). Three rather than four, so the fourth slot is visibly
  where the first spell a guild teaches lands.

  Pinned by rule and not by list: `test_spell_tuition.gd` asserts the hand
  *reaches further than a sword*, *teaches more than one delivery*, and is
  *castable from the pool a new mage is really born with* (the class lens
  plus the start node the web hands them free). Widening it broke fourteen
  tests in two suites that had named `minor_heal` as "a spell you do not
  know" and assumed a newly learned spell lands in slot 1 — both now derive
  what they need, so the next change to the hand cannot do it again.
- 🚧 **The guild has no interior trade UI**; `/learn` is the hand on it, the
  same honest scoping every other station interaction in `player.gd` has
  until an interaction UI exists.
