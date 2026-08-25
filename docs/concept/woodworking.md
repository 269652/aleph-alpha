## Woodworking: a felled tree is worked up in real stages, not one flat cut

A felled tree used to yield an identical mixed wood+stick drop on every one
of its 3 cuts (`FelledTree.wood_per_cut`/`ChoppableTree._cut_up`) —
mechanically real progress (the trunk visibly shrinks and eventually
clears) but no real *process*. This replaces that with the real sequence a
felled tree actually goes through: canopy off first, then the bare trunk
either broken down into raw logs by hand, or — with a saw and a trained
carpenter's eye — sawn straight into real construction lumber.

Reported: *"when chopping a felled tree, it should first remove the canopy
and spawn sticks; but leave the stem/trunk, then next chop splits the
trunk into logs which can be further split into more sticks. If you have
high enough carpenter skills you can turn the full trunk into a Balken or
Planken using a saw."*

### Design pillars

- **The stages are the real ones**, not invented game steps: limb off the
  crown (kindling), buck the bare trunk into rounds (logs), then either
  split a round by hand (more kindling) or saw a round into dimensional
  lumber. A player watching this happen should recognise actual
  woodworking, not a loot-table reskin.
- **Skill changes what a swing produces, not whether it lands.** Anyone
  can chop a bare trunk into logs. Turning that same trunk into
  construction-grade lumber needs both the right tool (a saw — an axe
  cannot rip a straight plank) and a trained eye (`Carpentry` skill) — the
  same "skill gates the OUTCOME, not the ACTION" shape `carrion.md`'s
  butchering skill already established for meat yield.
- **Nothing already reachable becomes unreachable.** Every existing
  recipe that consumes plain `wood` keeps working — logs convert to wood
  (and, separately, to more sticks) via the ordinary crafting bench,
  rather than silently cutting off the wood supply the moment this pass
  lands.

### Real-world grounding

- **Limbing before bucking.** A real felled tree is limbed (branches and
  crown removed) before the trunk itself is cut into lengths — the crown
  is the least useful part structurally and is in the way of everything
  else, exactly the same reason `carrion.md`'s butchering takes the hide
  off first.
- **A log is round; lumber is sawn.** A log split by axe/wedge along its
  grain gives rough, irregular pieces — fine for kindling, structurally
  useless for building. A **saw** is what turns a round log into a
  straight, uniform, load-bearing piece — an axe fundamentally cannot do
  this, which is why the saw is a hard tool gate here, not a yield
  multiplier the way a pickaxe is for ore.
- **Beam vs. plank is the same log, cut differently.** A *Balken* (heavy
  squared beam, structural framing) and *Planken* (thin flat boards) are
  both ordinary sawmill outputs of the same log, cut for different
  purposes. With no in-game mechanism yet for choosing a cut, sawing a
  trunk yields both — an honest, named simplification (see Status)
  rather than a hidden choice made for the player.

### Mechanism spec

#### The felled tree's real stages (`ChoppableTree`, `FelledTree`)

Extends the existing "fell first, work it up after" split
(`ChoppableTree.take_damage`/`is_felled`) with a second boolean,
`_canopy_removed`, rather than a single flat cut counter:

1. **Standing** — unchanged: a swing damages `health`; at zero it topples
   (`_fall`).
2. **Felled, canopy still on** — the FIRST swing on a freshly-felled tree
   removes the canopy and drops sticks
   (`FelledTree.sticks_from_canopy(growth_scale)`) — a real limbing pass,
   not a cut toward the trunk itself. Sets `_canopy_removed = true`; does
   NOT consume one of the trunk's `CUTS_TO_CLEAR`. **Actually swaps what's
   drawn, not just the flag** — reported live, a tree still showed its full
   canopy after this fired, since flipping the state bit alone never told
   the canopy sprite to redraw. `_remove_canopy` now swaps the sprite's
   texture to `ProceduralTreeSprite.generate_bare_trunk_texture` (the
   trunk piece drawn alone, no canopy compositing step, for both the plain
   procedural path and the illustrated-art one) the same frame the sticks
   drop.
3. **Bare trunk** — every further ordinary swing bucks off one round as a
   real `log` item (`FelledTree.logs_per_cut`), the same
   `CUTS_TO_CLEAR`-counted shape the old flat cut used, until the trunk is
   used up.
4. **Sawing the bare trunk (alternative to step 3)** — a swing while
   holding a `saw` AND having allocated enough of the `Carpentry` skill
   (`SkillTree`'s `carpentry_1`/`carpentry_2`, read live via
   `total_bonus("carpentry_level", ...)`, the same live-read-not-cached
   shape `carrion.md`'s `meat_yield` skill uses) converts the ENTIRE
   remaining trunk into `beam`+`plank` in one action
   (`FelledTree.beams_from_trunk`/`planks_from_trunk`) instead of the
   normal one-round-per-swing log split — a genuinely better outcome for
   the same trunk, gated by both tool and training. An axe (or an
   under-trained carpenter) simply cannot do this; the swing falls
   through to the ordinary log-splitting step instead.

#### Logs are further processable (`CraftingRecipeBook`)

A `log` is an ordinary inventory item, refined at the crafting bench (no
tool/skill gate — this is simple splitting, not sawing):

- `log → 3 stick` — more kindling out of a round nobody needed as lumber.
- `log → 2 wood` — keeps every existing `wood`-consuming recipe
  (`torch`, `wooden_club`, `campfire`, …) reachable through the new
  pipeline rather than silently cutting off their supply.

#### The saw itself

A new `tool`-kind item (`Item.is_saw()`, mirrors `is_axe()`/
`is_pickaxe()`'s exact `id.contains(...)` shape), craftable from wood +
rock like the existing `stone_pickaxe`.

### Status

- ✅ Staged felled-tree processing (canopy → sticks, bare trunk → logs) —
  `ChoppableTree`/`FelledTree`.
- ✅ Saw + `Carpentry` skill gate on turning a bare trunk straight into
  beam/plank — `Player._chop_step`, `SkillTree`'s `carpentry_1`/`2` nodes.
- ✅ Log refinement recipes (`log → stick`, `log → wood`) and a craftable
  `saw` — `CraftingRecipeBook`.
- ⬜ Choosing beam vs. plank output (today: sawing always yields both) —
  named simplification above, not a gap to silently paper over.
- 🚧 `beam`/`plank` consumers: partially closed —
  `timber_construction.md`'s new `timber_wall`/`timber_floor`
  `BuildingPiece`s (see that doc's Status) now spend real beam/plank on
  construction, and its Sägewerk worksite gives a second, NPC-staffed
  source for both alongside the player's own saw+Carpentry path. Still
  open: only two timber pieces exist (no door/window/roof of that tier
  yet), and `timber_construction.md`'s own statics/withering/settlement-
  ledger sections remain unbuilt, so beam/plank are spendable but not yet
  load-bearing in any mechanical sense.
- ⬜ Species/hardness variation in yield (an oak vs. a pine trunk sawing
  differently) — every tree shares one yield curve today, the same flat-
  by-role simplification `carrion.md`'s butchering already made for
  carcasses.
