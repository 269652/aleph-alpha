# Design Synthesis — the unified vision

This doc captures a design pass that connected the existing concept docs into
a single coherent whole. It's a **direction, not a spec** — it records the
decisions made in a brainstorm and how the previously-separate pillars
(genetics, crafting, survival/combat, NPCs, eras, death) turn out to be one
system viewed from different angles. Where it resolves an
[overview.md open question](overview.md#open-questions-to-resolve-during-mvp-work-not-blocking-day-1),
that's called out inline. Sequencing is still [roadmap.md](../roadmap.md)'s
problem; this folder is the vision bible.

## North star

> **One evolutionary system governs all life — beasts, crops, and people.
> Evolution is the universal grammar of the game; the player is an organism
> inside it, not above it. You don't beat the game — you outlive yourself
> through what you propagate.**

Nearly every system below feeds this core. Pillars that weren't the starting
focus — NPCs, eras, society — got pulled in *by necessity*, not bolted on.

### The deeper pattern — one authoring grammar for all creation

The north star has a structural twin. Every creative system in the game is the
**same verb**: *compose primitives into a graph, and let a deterministic
simulation resolve the emergent result.*

- **Crafting** — a graph of *parts* (material × geometry), resolved by the
  physics model. See [materials.md](materials.md).
- **Magic** — a graph of *forces* (physical / biological / mental / spatial),
  resolved by the same physics — and, for bio-forces, the genetic sim. See
  [magic.md](magic.md).
- **NPC command** — a graph of *intent*, compiled to checkable policy and
  resolved by the FSM executor.
- **Breeding** — a graph of *genes*, resolved by the evolution sim across
  generations.

So the smith, the mage, the breeder, and the overseer are the *same act*
pointed at different substrates (matter, energy, life, society). Nothing is a
scripted content list; everything is emergent from composed primitives. This is
why the design coheres despite its size — and it is balanced the same way
everywhere: not nerf-lists, but **physical conservation + diminishing returns +
emergent counterplay**, so the systems police themselves.

## The genetic core — one system, three kingdoms

Animals, plants ([flora.md](flora.md), [farming.md](farming.md)), and players
([dna.md](dna.md), [players.md](players.md)) all share one DNA system driving
**stats, appearance, and crafting-material quality**
([resources.md](resources.md), [crafting.md](crafting.md)). Behaviour is
layered: a species baseline + a heritable slice + learned conditioning (how
you treat/raise a creature or child shapes it).

- **Rarity emerges** from population genetics ([evolution.md](evolution.md))
  plus rare, *seekable* mutation events — not a flat spawn %. Mutation is an
  active mechanic: signposted, environmentally triggered (mutation zones), and
  inducible via breeder/mage skills.
- **Crafting is deterministic** — same inputs + blueprint = same output. All
  variance lives in the living inputs you hunt/breed/mutate, so **the genetics
  system *is* the loot system.** Material quality scales stats, unlocks
  modifier slots/tiers, *and* transfers signature traits (a fire-resistant
  beast → fire-resistant armor). Blueprint authoring (a DSL over primitives,
  like [magic.md](magic.md)'s spellcrafting) unlocks with mastery on top of
  discovered base recipes. **Item stats/effects aren't authored per recipe —
  they *emerge*** from each material's intrinsic property vector and the
  geometry of the shape, via a shared "8-bit physics" model; see
  [materials.md](materials.md).
- **The butcher-vs-breed dilemma.** The best materials come only from killing
  the best specimens, which fights against keeping them alive to breed or
  fight beside. Every magnificent creature is a genuine choice. Harvesting is
  sharp (death = premium mats); only lesser renewables come from a living
  animal.
- **A shared, depletable gene pool.** Farmed crops can escape and
  cross-pollinate into the wild sim; overharvesting a region crashes that
  lineage's quality ([flora.md](flora.md) grove-overharvest,
  [worldbosses.md](worldbosses.md) outlier removal). Sustainability is a real
  strategy.

## The spatial loop — a danger gradient

Risk, material quality, mutation potential, and lethality all rise together as
you push outward:

1. **Homestead / civilization** — survival trivial, ranched mid-grade mats,
   safe. Genuinely safe from scripted escalation: no Valheim-style automatic
   raid-wave scaling. The only threats here are **diegetic** — a rival
   dynasty or poacher coming for your prize stock, or a real simulated cause
   like drought-driven wildlife desperation (see
   [building.md](building.md#base-defense-diegetic-threat-not-scripted-raid-waves)).
2. **Deep wild** — survival brutal, wild apex specimens for premium mats,
   hunting expeditions ([survival.md](survival.md) contextual intensity).
3. **Mutation frontier** — warped, dangerous wildlife; the *only* place to
   gamble your prize stock into new alleles (they may mutate better *or*
   worse). Highest risk, highest reward. The gradient up to here is
   continuous, but **first entry is boss-gated**: crossing into the frontier
   for the first time requires downing a regional emergent apex specimen
   ([worldbosses.md](worldbosses.md)) — a discrete Valheim-style wall at the
   one threshold that matters most, layered on an otherwise smooth curve.
   Signature world bosses can similarly gate
   [era transitions](eras.md#era-transitions-can-be-boss-gated).

Combat ([combat.md](combat.md)) is maximally tactical to match — a full
elemental matrix **and** environmental reactions (fire+oil, shock+water,
freeze-to-walkable) — so trait-transferred gear genuinely matters. Tamed/bred
creatures ([pets.md](pets.md)) serve as autonomous companions, mounts, and
commanded units by species/role. Wounds are granular and healed by
genetics-sourced medicine (rare herb strain → potent remedy), closing the
survival → herbalism → farming loop. Expansion outward is the meta-game: you
**build, prep, and breed** your way into new zones (cold gear for tundra, an
aquatic mount for oceans).

Under all of it is one physical substrate ([materials.md](materials.md)): a
single momentum model (`mass × velocity` vs. material hardness/toughness) where
swinging, **throwing anything you can lift, shoving into hazards, toppling
structures, falling, and mining** are the *same equation* — BG3-style emergent
physics where weight itself is a weapon. Reactive surfaces (oil, water, ice),
2.5D verticality, and items that wear and **shatter** all compose out of it,
never scripted per object.

## The generational loop — death is the engine

**Resolves [death.md](death.md) / [eras.md](eras.md) carryover open
questions.** You live a mortal, permadeath life ([death.md](death.md)'s nine
lives as the buffer), aging in accelerated time; children grow up within a
playthrough so you *feel* generations.

- What persists isn't *you* — it's your **DNA/aptitudes, bred creature & crop
  bloodlines, knowledge (recipes/blueprints/map), and stored wealth**, plus a
  **homestead/household that runs autonomously** while you're away. Skills,
  gear, reputation, and relationships are earned fresh each life. No inherited
  debt/enemies — legacy is a clean springboard, not a burden.
- **Die with an heir → you continue *as* them**, inheriting the biological and
  built capital ([players.md](players.md) inheritance). Each reincarnation can
  vault the world into the next **era** (medieval → industrial → AI boom →
  space), which shifts *everything*: which traits matter, the threat model,
  the whole tech tree, and the face of the living map.
- **Die heirless → the line ends → hard reset** to a fresh naked-and-afraid
  character. Courtship, marriage, and raising an heir
  ([players.md](players.md)) are therefore **survival-critical**, not a side
  system. Mate choice is love-vs-lineage in genuine tension: the optimal-DNA
  match may not be the one you want.

## The doors-off endgame — evolve your own dynasty

Because aptitude is heritable and eras shift the selection pressure, *playing a
certain way selectively breeds your bloodline toward it* — a century of your
family hunting produces hunter-DNA descendants. But the optimal bloodline
keeps changing underneath you (brawn in the medieval wild, intellect in the AI
boom). **You are evolving your own dynasty to fit a changing world.**
Self-directed evolution, applied to the player's own family, is the ultimate
progression system — the same [evolution.md](evolution.md) engine that governs
wildlife, turned on the protagonist's bloodline.

Classes stay soft ([classes.md](classes.md), [dna.md](dna.md)): DNA/resonance
*inclines* without gating, real specialization has teeth but is reroll-able,
and you can maintain a **stable of specialist bloodlines** rather than one
character.

## The people — your household as your first NPCs

A fully-simulated, order-taking household means AI NPCs
([npc.md](npc.md)) are load-bearing after all — and your **kin are your first,
most intimate NPC roster**, an onboarding to the wider NPC world through your
own family.

- **The LLM is a planner, not a puppeteer.** Once per in-game day it generates
  a schedule for *notable* NPCs (heir, spouse); an FSM + pathfinder executes
  it with zero further LLM calls. Lightweight relatives are pure FSM.
  (Matches [roadmap.md](../roadmap.md) Phase 2.)
- **You govern by intent.** Natural-language orders are compiled down into
  checkable, exploit-resistant structured policy (the "instruction complexity
  budget" of [npc.md](npc.md)).
- **Society is a web of lineages** ([factions.md](factions.md),
  [economy.md](economy.md)) that cooperate, compete over depleting
  resources/frontiers/era-firsts, and **intermarry — genetics as diplomacy**
  (player bloodlines literally merge). It's self-policed by reputation and
  emergent NPC law rather than a hard PvP ruleset ([pvp.md](pvp.md)): you can
  die, but the danger scales with how far past civilization you push.

## The first hour

Naked-and-afraid classic survival open — fire, shelter, first food/water
before nightfall — with the genetic depth revealed slowly, not front-loaded.
The player learns the universal grammar one organism at a time.
