## Skills — the Passive Skill Web

A Path-of-Exile-style passive **web**, layered with per-player DNA-driven
uniqueness. This is **combat/magic build power**, spent from level-up skill
points — see [progression.md](progression.md) for how those points are earned.
It is deliberately separate from [labor_skills.md](labor_skills.md)'s use-based
practical mastery (Woodcutting, Smithing, Farming, ...), which levels from doing
the corresponding action, not from allocation. A character advances both at
once, independently.

## Design pillars

1. **One web, seven wedges.** There is a *single connected graph*, not seven
   disjoint trees. Each of the 7 [archetypes](classes.md) owns a wedge of it.
   Your class decides where you *start*, never where you may *go*.
2. **Pathing is the cost.** Nodes are allocated by walking outward from your
   start node: you may only take a node adjacent to one you already own. Power
   deep in another archetype's wedge is reachable, but you pay for every step of
   the journey — the PoE bargain, and the mechanical expression of
   [classes.md](classes.md)'s "class is a lens, not a cage".
3. **DNA changes the exchange rate, never the map.** Your rolled
   [DNA resonance](dna.md) makes nodes in a resonant wedge *cheaper* and their
   bonuses *bigger*, and nodes in a dissonant wedge costlier and weaker. It
   never removes an edge, never hides a node, never forbids an allocation. Soft
   and efficiency-shaped, exactly as [classes.md](classes.md) resolved.
4. **Every character's web is physically different.** On top of the shared
   graph, each character's DNA grafts a **genome net** — a small, procedurally
   generated cluster of nodes nobody else has — onto the deepest point of their
   most-resonant wedge.
5. **Every number is derived or test-pinned.** Node coordinates come from a
   layout function, not hand-placed pixels; resonance multipliers are anchored
   at neutral resonance; the genome net spends an exact rarity budget. No
   eyeballed constants (see [CLAUDE.md](../../CLAUDE.md)).

## Topology

The web is laid out in **polar coordinates** around a shared centre.

- **Wedge.** Archetype `a` (of `N = WEDGE_COUNT = 7`) owns the angular wedge
  centred on `a · 2π/N`, spanning `WEDGE_SPAN` radians (a fraction `WEDGE_FILL`
  of its full slice, so neighbouring wedges never touch). All of that
  archetype's nodes live inside it, so the web reads as seven recognisable
  neighbourhoods separated by visible gutters.
- **Rings.** Radius grows with `ring`:

  | ring | contents | base cost |
  |---|---|---|
  | 0 | the archetype's **start node** (1 per wedge) | free — granted with the class |
  | 1 | 3 **minor** nodes | 1 |
  | 2 | 3 **minor** nodes | 2 |
  | 3 | 2 **notable** nodes | 3 |
  | 4 | 2 **keystone** nodes | 4 |

  Ring prices were chosen equal to what the pre-existing flat node list already
  charged for the same nodes (a `_1` node cost 1 and sits on ring 1, a `_2` node
  cost 2 and sits on ring 2), so folding that list into the web repriced nothing.
- **Slots.** Within a ring, `k` nodes are spread evenly across the wedge span,
  so a wedge widens as it goes out. Position is a pure function of
  `(archetype_index, ring, slot)` — there is no hand-authored coordinate
  anywhere in the table.
- **Intra-wedge edges.** The start node fans out to the *whole* of ring 1 (it is
  the single node the wedge hangs off). From there, ring `r` slot `i` connects
  outward to ring `r+1` slots `i` and `i−1`, clamped into range. That lattice —
  not a strict tree — means most notables can be reached by more than one route,
  which is what makes "where do I spend my next 4 points" an actual decision.
- **Gateways.** Between every pair of adjacent wedges sits one **gateway** node
  in the gutter at start radius, belonging to no archetype. It connects to both
  neighbouring start nodes. Gateways are the *only* cross-wedge edges, so
  travelling from Warrior into Mage costs a real, countable number of points
  instead of being free.

Consequences worth stating, because they are the design:

- The graph is **fully connected** — every node is reachable from every start
  node, so no build is ever walled out of anything (pillar 1 of
  [classes.md](classes.md)).
- Reaching a *neighbouring* wedge's keystone is cheap-ish (start → gateway →
  their start → four rings). Reaching the *opposite* wedge's keystone means
  crossing three gateways. Distance around the ring is itself a balance knob
  that needs no tuning table.

## Allocation rules

A node may be allocated when **all** of:

1. it exists in the web and is not already allocated;
2. it is **reachable** — it is your archetype's own start node, or at least one
   of its neighbours is already allocated;
3. you can pay its **resonance-adjusted point cost**.

Nothing else gates it. There is no level requirement, no attribute requirement,
no "you must be a Mage". Keystones additionally keep
[progression.md](progression.md)'s existing `required_node_count` floor, which
the lattice mostly enforces on its own but which stays as a legible second
statement of "a keystone is the end of a real investment".

**Your own class's start node is granted free** with the class, the way Path of
Exile hands you the one you begin on: paying a level-up point for "you are a
Mage" would be a tax on existing, and without it a level-1 character owns
nothing and so can path nowhere.

**Respec is free** (see [classes.md](classes.md)) — refunding a node returns the
points it *actually cost* (recorded at purchase, not recomputed) and removes its
bonus. Two refusals: a refund may not **orphan** the web (you cannot keep a
keystone while refunding the road you walked to reach it), and the free class
start node cannot be sold back, since it was never bought.

## DNA resonance: the exchange rate

[dna.md](dna.md) rolls a `0..1` resonance per archetype. `0.5` is **neutral**,
and both multipliers are anchored so that a neutral character pays and receives
exactly the authored numbers — the tables in code mean what they say, and DNA is
visibly a *deviation* from them rather than a hidden scale factor.

| | resonance 0.0 | 0.5 (neutral) | 1.0 |
|---|---|---|---|
| **Point cost** × | `1 + COST_SPREAD/2` | `1.0` | `1 − COST_SPREAD/2` |
| **Bonus gain** × | `1 − GAIN_SPREAD/2` | `1.0` | `1 + GAIN_SPREAD/2` |

- `COST_SPREAD` is **twice** `GAIN_SPREAD`, deliberately: DNA should mostly
  change how *fast* you get there ([classes.md](classes.md)'s "faster
  leveling"), and only secondarily how much the destination is worth.
- Cost is rounded **up** and floored at **1 point** — a node can get cheaper but
  never free, and the ceiling at the other end is finite and small.
- Gateways belong to no archetype and are therefore always charged at neutral:
  the travel tax is the same for everyone, which keeps cross-archetype pathing a
  cost you can *plan*, not a second DNA lottery on top of the first.
- Because the ceiling is small, a dissonant build is measurably slower and never
  impossible. That is the whole of [classes.md](classes.md)'s "a bad roll just
  makes the road longer", made arithmetic.

### DNA-flavoured shared nodes

A minority of shared nodes (one per wedge — most stay uniform, deliberately, so
the map stays plannable) are marked **DNA-flavoured**: everyone can take the
node, in the same place on the map, for the same cost, and — pinned by test —
for the same bonus *amount*. Only *which* of 2–3 themed stats it grants is
chosen deterministically from your DNA seed. A Ranger's `marksman_2` grants raw
attack damage for one genome and throwing force for another. Equal worth is the
point: the flavour roll must never become a second power lottery stacked on the
first.

## The genome net (your unique skill net)

Every character carries one procedurally generated cluster nobody else has,
grafted onto the outermost notable of their **most-resonant** wedge — so the
unique part of your web sits at the end of the path your DNA was already pushing
you down.

- **`signature_core`** — always present. A notable-tier node with a generated
  name and one stat drawn from the anchor archetype's own stat pool.
- **Satellites** — chained outward from the core. How many depends on the roll's
  [rarity](dna.md):

  | rarity | nodes | net budget |
  |---|---|---|
  | common | 1 (core only) | `NET_BUDGET_UNITS[common]` |
  | rare | 3 | `NET_BUDGET_UNITS[rare]` |
  | legendary | 5 | `NET_BUDGET_UNITS[legendary]` |

- **The budget is the balance constraint**, the same discipline `hero_dna.gd`
  already applies to stat modifiers: a net's bonuses sum to *exactly* its
  rarity's budget, divided unevenly (so it doesn't read as a flat split) but
  never exceeding it. A legendary net is bigger and **broader**; it cannot roll a
  single absurd number, because there is no number to roll — only a fixed budget
  to divide, and a per-node cap that keeps any one node from eclipsing the best
  thing the shared web already has for that stat.
- A budget **unit** is deliberately not a raw stat amount but *the biggest single
  bonus the shared web already grants for that same stat*. That makes 40 max
  health and 4 taming affinity the same investment automatically, with no
  per-stat table of its own to drift out of step. The common budget is pinned
  from both sides against the real notable tier, so the unique node can become
  neither a trinket nor a trap.
- This is the original "constrained by the same rules as any player-authored
  spell, so a signature skill can be flavourful without being able to roll
  overpowered", expressed as a **budget** rather than a cost formula — skill
  nodes are passive stat grants, so they have no atoms to price. Generating an
  actual *spell* through [magic.md](magic.md)'s DSL remains the unbuilt half.
- Net nodes obey every ordinary rule: they must be pathed to (only through their
  anchor), they cost points, they are refundable. Only the DNA **seed** is
  persisted; the net is regenerated from it.

## Per-archetype web content

Each wedge's stats deliberately reach into the system that archetype is *about*,
per "webs connect outward into their domain's system". Where a stat is already
read live by real code, that is noted.

| Wedge | Ring 1–2 minors | Ring 3 notables | Ring 4 keystones |
|---|---|---|---|
| **Warrior** | `vitality_1/2` (max health), `strength_1/2` (attack), `bulwark_1/2` (knockback resist; `_2` DNA-flavoured) | `juggernaut`, `executioner` | `iron_skin`, `berserkers_fury` |
| **Ranger** | `endurance_1/2` (stamina regen), `marksman_1/2` (attack; `_2` DNA-flavoured → throw force), `butchering_1/2` (meat yield — **live** in `Player.butcher`) | `tracker` (scent range), `windrunner` | `swift_current`, `apex_predator` |
| **Mage** | `attunement_1/2` (max mana), `focus_1/2` (spell efficiency), `evocation_1/2` (spell power; `_2` DNA-flavoured) | `arcane_reservoir`, `spell_weaver` (atom tier) | `archmage`, `deep_lore` |
| **Beastmaster** | `bonding_1/2` (pet loyalty), `handler_1/2` (taming affinity), `kennel_1/2` (pet health; `_2` DNA-flavoured) | `pack_leader`, `beast_whisperer` | `alpha_bond`, `menagerie` |
| **Artisan** | `carpentry_1/2` (carpentry level — **live** gate on the `sagewerk` recipe), `masonry_1/2` (mining yield), `smith_1/2` (smelting yield; `_2` DNA-flavoured → ore yield) | `master_joiner`, `forgewright` | `grand_workshop`, `deep_delver` |
| **Herbalist** | `naturalist_1/2` (stamina regen), `remedy_1/2` (wound recovery), `soothe_1/2` (disease resist; `_2` DNA-flavoured → venom resist) | `field_surgeon`, `antivenin` | `land_sense` (reveal), `lifebloom` |
| **Overseer** | `logistics_1/2` (hire capacity), `command_1/2` (contract throughput), `ledger_1/2` (trade margin; `_2` DNA-flavoured) | `quartermaster`, `magistrate` | `guildmaster`, `grand_charter` |

`land_sense` keeps its existing shape: a **reveal** keystone with an empty
`stat_name` and zero bonus, whose payoff is real land-health/vegetation numbers
becoming visible (see [progression.md](progression.md)). The web treats an empty
`stat_name` as "grants no stat" and scaling zero by anything is still zero, so
reveal-style nodes need no special case in the allocation maths.

## Reading the map

A web of 84 circles is only a map if it says what it is. Three things carry
that, all of them addressing the same reported problem ("the skills have no
hover tooltip and it's pretty unclear what paths do what"):

- **Wedge names.** Each archetype's name is painted on its own centre line, out
  past its keystones, in that wedge's own hue. Without them the map is
  unattributed circles and there is no way to tell which direction is which
  archetype.
- **Node names.** The landmarks — start nodes, notables, keystones and your
  genome net — are named on the map at every zoom. The small nodes are named too
  once you lean in past `MINOR_LABEL_ZOOM`; naming all 84 at every distance is
  an unreadable thicket, and the zoom at which they appear is also the zoom at
  which there is room for them. Gateways are never named: their ids are not
  names anyone needs, and seven of them would crowd the centre.
- **Hover tooltip.** Everything in it is resolved for *this* character — the
  DNA-chosen variant, the resonance-scaled bonus, the resonance-scaled price —
  because a tooltip quoting the table's numbers rather than the player's own
  would be worse than no tooltip. It names the node, its wedge and tier, what it
  grants, what it costs, and what state it is in; a genome-net node says it came
  from your own genome, a DNA-flavoured node says its effect was DNA-chosen.

### Route preview

The real answer to "what do these paths do" is not a prettier picture but a
concrete one: *from where I stand, what would it take to get **there***.
Hovering a node you cannot yet reach previews the **cheapest route** to it —
drawn as a lit chain through every node you would have to buy, with the total
quoted in the tooltip ("18 points to reach, 6 nodes away").

`SkillWeb.cheapest_path` is Dijkstra with the weight on the **node** rather than
the edge — you pay to own a node, not to traverse an edge — seeded from your
entire owned frontier at once, or from your class start if you own nothing yet.
Prices along the route are your own, so a resonant character is quoted a cheaper
journey than a dissonant one to the same destination, which is exactly the
efficiency-only bargain made visible.

## Status

- ✅ **Graph** — `src/gameplay/skill_web.gd`: 7 wedges × 11 nodes + 7 gateways,
  derived polar coordinates, lattice edges, gateway cross-links, connectivity
  proven by test (every node reachable from every start).
- ✅ **Adjacency-gated allocation** — `can_allocate` requires reachability; a
  node floating in another wedge simply cannot be bought.
- ✅ **Legacy nodes folded in, not duplicated** — a String entry in the wedge
  table defers stat/bonus/cost to `skill_tree.gd`/`keystone_passive.gd`, held to
  it by drift tests, so those numbers live in exactly one place.
- ✅ **Resonance cost/gain** — `point_cost` / `effective_bonus`, anchored at
  neutral, ceiling finite so dissonance never gates.
- ✅ **DNA-flavoured shared nodes** — `flavored_variant`, equal-worth variants.
- ✅ **Genome net** — `src/gameplay/genome_skill_net.gd`, rarity-sized, exact
  budget, grafted at the most-resonant wedge, seed-persisted.
- ✅ **Free respec** — `Player.refund_skill`; `SkillWeb.can_refund` refuses to
  orphan the allocated subgraph.
- ✅ **Wired to the player** — `Player.allocate_skill`/`unlock_keystone`/
  `refund_skill` run on the web with the character's real rolled resonance;
  `Player.skill_bonus` is the single reader for every stat it grants.
- ✅ **Web view** — `scenes/skill_web_view.gd`: pan/zoom graph canvas in the
  skill window (toggle L), four distinct node states, per-character labels,
  click to take, right-click to refund; the old flat list survives as a tab.
- ✅ **Reading the map** — wedge names, on-map node names (zoom-tiered), and a
  full hover tooltip resolved for the hovering character.
- ✅ **Route preview** — `SkillWeb.cheapest_path`/`route_cost`; hovering an
  out-of-reach node lights the cheapest journey to it and quotes its price.
- ✅ **The window is the screen** — sized from the project's own design viewport
  (`SkillTreeWindow.DESIGN_VIEWPORT`, pinned against ProjectSettings) less a
  margin, rather than the stale 960x540 figure it was first built against. A
  test asserts the whole web, wedge names included, fits the canvas at minimum
  zoom, and that the small nodes are already named at the zoom it opens on.
- ⬜ **Not built** — most of the new stat keys are *declared and summed* but not
  yet read by their owning system (only `max_health`, `attack_damage`,
  `meat_yield`, `carpentry_level` are live today); no atom-unlock/parameter-cap
  hook into [magic.md](magic.md)'s catalog, which is the specific integration
  this doc has always called for; no node search and no keyboard navigation in
  the view (the route preview answers "how do I get there", but you still have
  to find the node by eye first); the genome net is derived rather than stored,
  so a change to the generator would silently change an existing character's net.

## Open questions

- How many keystone-tier passives per wedge is right? Currently 2, chosen for
  symmetry rather than from play — the number to revisit once builds are
  actually played.
- Should a trainer-NPC/fee respec variant exist alongside the free one (tying
  into [economy.md](economy.md)), or is free-everywhere final?
- Should DNA-flavoured variants widen from a fixed 2–3 per node to a procedural
  range, now that the equal-worth constraint is a tested invariant?
