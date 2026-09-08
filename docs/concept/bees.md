# Bees: Honeybee Hives and Solitary Wild Bees

Requested live: *"can you add a real beehive system similar to the ant hive
for honeybees which build hives which can be harvested for honey ... there
should also be wild bees which lay eggs in little holes (twigs with holes)
the distinction should be visible in tooltip hover and bees should relocate
their hive if destroyed/harvested or if there is no food anymore near ...
hives should produce more bees and if the hive gets to maximum population,
half the hive builds and moves into a new hive."*

This closes a real, explicitly-named gap: the "bee" that already exists
(`FlyerDiet.DIET_BY_SPECIES["bee"]`, `ambient_flyer_renderer.gd`'s
`BEE_SPECIES_POOL`) is pure decorative wander with a nectar sip — no hive,
no home, no population, no predation pressure on it whatsoever
([ecosystem_dynamics.md](ecosystem_dynamics.md) names this directly:
*"Butterflies/bees remain purely decorative: there is still no predation
pressure on pollinators to make an aggregate number mean anything real
yet"*). [flora.md](flora.md) already owns nectar/pollen/flower mechanics in
full; this doc is what finally puts a real animal economy on the *consuming*
end of it, the same way [soil_fauna.md](soil_fauna.md) did for the robin/
worm relationship it's modeled on.

**This doc is deliberately the ant colony system's own direct sibling, not
a fresh design.** `AntColony`/`AntForagerMarker`/`AntMoundMarker` are read
in full below and mirrored wherever the mechanic is genuinely the same
shape (a queen-driven population bounded by what foragers bring home, a
forager round trip, a hover/panel contract, a chunk-scoped spawn/step/
teardown lifecycle) — see "What's reused verbatim, what's a deliberate
new duplicate, and why" below for the exact boundary. Two real differences
drive everything that ISN'T a mirror: **a beehive is a harvestable
resource** (no ant precedent exists for a player extracting a resource
from a colony structure), and **a real colony's response to losing its
home is to relocate, not to quietly respawn in place** (also no ant
precedent — a starved ant mound refounds at the identical cell).

## Design pillars

1. **Real mechanisms, not scripted spawns** — the same pillar
   [soil_fauna.md](soil_fauna.md) opened with. A hive grows because its
   foragers are actually finding nectar, not because a timer fired; honey
   you harvest is honey the colony actually stored; a colony that can no
   longer feed itself actually leaves.
2. **Two real, biologically distinct bees, not one mechanic reskinned
   twice.** A honeybee colony and a solitary wild bee are genuinely
   different animals with different social structures, different
   dwellings, and — critically — only one of them produces anything a
   player could harvest. The distinction is not cosmetic and must read as
   real in both the tooltip and the mechanism, not just the sprite.
3. **Harvesting is a real trade-off, not a free resource tap.** Honey is
   the colony's own winter food store, not a separate currency that
   happens to sit in the hive. Taking it costs the colony something real
   (see "Harvesting honey" below) — a player who strips a hive bare is
   making the same choice a real over-harvesting beekeeper makes.
4. **Legible on screen.** A player should be able to tell a young hive
   from a thriving one, and a honeybee hive from a wild bee's nest hole,
   by looking — and by hovering, get the exact numbers behind what they're
   seeing, the same contract `AntMoundMarker` already established.
5. **Determinism**, the same standing rule every patch-sim and colony in
   this project already follows.

## Real-world grounding

**Honeybees (*Apis mellifera*) are a true superorganism**, not a large
group of independent animals: one queen, whose egg-laying rate — itself
bounded by how much nectar and pollen her workers actually bring home —
is what drives colony growth, exactly the mechanism `soil_fauna.md`
already specified for an ant queen and gave a name to
("A queen, and where a colony's size comes from"). This is the single
biggest reason this system mirrors `AntColony` as closely as it does: the
underlying population mechanism (a forage-bounded logistic growth curve)
is genuinely the same *kind* of animal economy, just around a different
resource.

**A wild colony's nest is a real, gradually-built structure**, not a
container the bees move into — comb is wax the colony itself secretes and
shapes, cell by cell, as it grows. Real wild honeybee colonies most
commonly nest in an enclosed cavity (a hollow tree, a rock crevice), but
open-air, exposed-comb nesting — a single comb built hanging in the open,
usually from a branch — is also real and well-documented, both regionally
(some populations nest exposed as their norm) and as a colony's own early
stage before it has grown enough to fully invest in a protective outer
wax envelope. This is exactly what the supplied art
(`assets/sprites/beehive.png`) draws: rows 1-2 are a 16-frame growth
sequence from a tiny exposed cluster of cells, through a small
part-enclosed comb, to a large, fully wax-sealed hive with a real
entrance hole — a young, still-vulnerable colony investing more
structure as it grows, not sprite-sheet padding.

**Either way, a real hive is physically anchored to something — never
free-standing over open ground or water.** A wild colony hangs its comb
from a real tree branch or nests inside a real cavity; a manmade hive (a
beekeeper's own box or skep) sits on a stand, typically near a
structure for shelter and access, never planted in bare open ground and
never over standing water. Requested live, after the honeybee hive
system above had already shipped: *"Beehives should only be able to
build on trees or structures like houses .. not free floating over a
river or ground."* `EarthChunkManager._has_real_hive_anchor` (see
"Absconding" below for where it is actually enforced) is the fix: a
real tree or a real building piece within a small radius, and never a
river/lake tile regardless. **A known, named gap, not silently
extended: wild bee nests (`WildBeePatch`) have the identical
"needs real deadwood/an old stem nearby" real-world claim below and no
enforcement of it either — this pass fixes honeybee hives only, since
that is what was asked for.**

**Honey is the colony's own winter survival store, not a spare
resource.** Bees convert nectar to honey and cap it in comb specifically
to have something to live on through winter, when cold shuts down both
foraging and, below a hard cutoff, flight itself — a real colony clusters
and lives entirely off its own stored reserve until conditions improve.
A colony a beekeeper (or, here, a player) strips of too much honey can
genuinely starve over winter. This is the direct real-world grounding for
treating "honey stored" as the same number that both feeds the colony's
own growth *and* is what a player harvests — there is deliberately no
separate, free-standing "loot pool" a hive carries alongside its real
economy.

**Swarming is the real biological mechanism for how a honeybee colony
reproduces itself** — described almost exactly in the live request: when
a colony becomes crowded and resource-rich, the *old* queen leaves with
roughly half the workforce to found a brand new colony elsewhere, while
the hive left behind raises a new queen from the brood already there and
carries on. This is precisely the same shape `AntColony.bud_new_mound`
already implements for ants (an even population/reserve split, gated on
`is_overpopulated_at`, a real site-search for the destination) — the one
piece of this whole system that is close to a straight port, not a new
mechanism, because the real biology genuinely converges here.

**Absconding is the real, separate mechanism for the rest of the
request** — "relocate if destroyed/harvested or if there is no food
anymore near." A real honeybee colony that loses its nest to destruction,
to a predator (or, historically, to a human raiding it for honey — see
"Harvesting honey" below, which is modeled on exactly this real
practice), or that finds itself somewhere the forage has genuinely dried
up, does not sit and die in place: the *whole* colony (not half, unlike
swarming) leaves together and re-establishes elsewhere. This is a real,
named, distinct behavior from swarming, and it is the mechanism this doc
uses for every "hive is gone" trigger — never a same-site respawn the way
a starved ant mound's `_maybe_refound` is.

**The vast majority of real bee species are solitary, not social — and
none of them produce harvestable honey.** Only a handful of the world's
roughly 20,000 bee species are eusocial honey-producers at all (honeybees
foremost among them); the overwhelming majority — mason bees, leafcutter
bees, mining bees, and hundreds of others — have no queen, no worker
caste, and no shared nest at all. A single female does everything herself:
she finds or excavates a cavity, provisions a short series of small brood
cells each with just enough pollen and nectar for one egg, seals it, and
moves on. There is no surplus, no comb, nothing to store — which is
exactly why the live request only ever mentions harvesting for the
honeybee hive, never for wild bees; that omission is itself correct
biology, not an oversight this doc needs to correct. "Little holes...
twigs with holes" describes the real cavity-nesting guild specifically
(as opposed to the equally real ground-nesting guild, which tunnels into
bare soil instead) — this doc models exactly the guild the request names.

## What's reused verbatim, what's a deliberate new duplicate, and why

- **`PopulationModel`** (`src/world/population_model.gd`) — reused
  verbatim. It is already the fully generic logistic-growth engine every
  domain-specific population in this game wraps; nothing about it is
  ant-specific.
- **`AntForageBehavior`/`AntScoutWander`** — **not** reused, deliberately
  duplicated as `BeeForageBehavior`/`BeeScoutWander`. Both are small
  (71/76 lines), pure, and already genuinely generically named/shaped —
  reusing them directly would work today, but would silently couple two
  unrelated colony systems' tuning together the moment either needs its
  own timing (a bee's round trip is a very different real timescale from
  an ant's), and this project has an explicit standing preference for
  exactly this trade-off: *"three similar things beats a premature
  abstraction"* (`DesertScrub`'s own doc comment, referenced directly by
  `soil_fauna.md`).
- **The hover contract (`HoverTargetFinder.GROUP_NAME`,
  `get_display_name()`, `get_hover_actions()`) and the HUD panel contract
  (`panel_state()`, `CreaturePanel.set_state`)** — reused verbatim; these
  are the established, general interfaces every hoverable/panel-worthy
  entity in the game already implements, not ant-specific code.
- **`AntColony`/`AntPopulationModel` themselves** — not reused (a
  `BeeColony` is a new class), but every mechanism that carries over
  unchanged in spirit is named explicitly below rather than silently
  re-derived, so the two systems stay legibly parallel.
- **Pheromone-trail recruitment (`PheromoneField`,
  `AntColony`'s cluster/scout/resolver wave dispatch) — deliberately NOT
  built for bees in this pass.** Real honeybee recruitment (the waggle
  dance) is a genuinely different signal — a symbolic dance encoding
  direction and distance, not a laid scent trail — and modeling it
  faithfully is its own separate piece of work, not a reskin of ant
  pheromones. Named here as a real, reasonable follow-up, not silently
  dropped. Concurrent foragers still scale with colony health
  (mirroring `active_forager_cap_at`'s shape), just without wave-spread
  dispatch or trail-following.

## Mechanism spec

### Honeybee colony economy — `BeeColony`

One `BeeColony` per chunk (mirrors `AntColony` exactly), addressing
multiple hive cells the same way. Per hive cell:

- **Population** (`_population`, an abstract colony-strength number, the
  same abstraction level `AntColony._population` already sits at) grows
  via a new `BeePopulationModel` (thin wrapper around `PopulationModel`,
  mirroring `AntPopulationModel`'s shape): `STARTING_POPULATION`,
  `BASE_CAPACITY`, `GROWTH_RATE_PER_DAY`. A real honeybee colony can grow
  considerably faster through a season than a mature ant colony matures
  across years, so this rate is pinned **faster** than
  `AntPopulationModel.GROWTH_RATE_PER_DAY` — an ordering, not an
  eyeballed number, the same "ordering over magic constant" convention
  `AntColony.MOUND_CHANCE` already established relative to
  `EarthwormPatch.SEED_CHANCE`.
- **Capacity is bounded by forage success alone** — no separate
  moisture/water input the way `AntColony` has one. A real colony's
  growth ceiling is nectar/pollen availability; there is no comparably
  central "does this site have water nearby" driver for bees the way
  there genuinely is for digging, larvae-humidity-dependent ants. Winter
  throttling (below) covers the seasonal half of what water/warmth
  jointly covered for ants.
  ```
  capacity(recent_forage_success) = BASE_CAPACITY * (1 + FOOD_CAPACITY_BONUS * recent_forage_success)
  ```
- **Honey storage IS the colony's real food reserve — one number, two
  roles.** `_honey_stored` mirrors `AntColony._food_stored` exactly
  (deposited by `record_forage_result` on a successful trip, depleted
  per day per population via `HONEY_PER_BEE_PER_DAY`, gates capacity
  through `honey_availability_fraction` exactly like
  `food_availability_fraction`) — **and is also, unmodified, the exact
  quantity a player harvest reduces.** There is no second "loot" number;
  harvesting honey and starving the colony's own growth are the same
  lever, which is the entire point (see Design Pillar 3).
- **Winter dormancy** mirrors `dormancy_multiplier_at` — reuses
  `EarthwormPatch.COLD_CUTOFF`/`MILD_WARMTH` for the same real cold-gate
  signal (a colony doesn't need its own separate temperature model; cold
  soil and cold air move together at a chunk's scale), floored so a
  clustering colony still burns *some* stored honey, never zero.
- **Swarming** — `is_overpopulated_at`/`should_bud`/`bud_new_mound` are
  near-direct ports of the ant versions: population reaching
  `MAX_REFERENCE_POPULATION` makes a swarm roll possible each `advance`;
  a successful roll **halves both population and honey** between the
  original hive and a brand new one, sited by the same
  "nearest-real-`is_valid_hive_site`-with-real-forage-nearby" search
  `EarthChunkManager._find_bud_site` already does for ants (reused as
  the identical *shape* of query, against bee-appropriate site/forage
  checks).

### The queen — a real, minimal presence, added live

Requested live: *"Also added honeybee_queen sprite add a honeybee
queen and wire it... give her a real place in the ecosystem."* This
section was added alongside `honeybee_queen.png` (a real, delivered
1536x1024 sheet sharing the exact same real row layout as the worker
sheets — see "Bee body poses" below) in a later pass than the rest of
this doc.

**Was "queen-driven population" already a real mechanic?** No — checked
directly before writing a line of code, per this doc's own header
promise never to force a match that isn't real. `BeeColony`/
`BeePopulationModel` have no queen entity, no queen state, nothing an
individual could point to as "her" — "queen-driven" is real-world-
grounding *language* (see "Real-world grounding" above and `soil_fauna.
md`'s identical phrase for `AntColony`) explaining *why* the logistic
growth curve looks the way it does, not a mechanic with a queen behind
it. Ants have the same gap, deliberately: `AntMoundMarker`/`soil_fauna.
md` are explicit that a real ant queen is sessile and essentially never
seen, so no queen sprite exists there at all and population alone
stands in for her. Bees now **depart from that ant precedent on
purpose** — the user supplied real queen art and asked for a real
place in the ecosystem, not a purely decorative reskin, so this is a
new, minimal, tracked queen-presence mechanic ants still deliberately
lack.

**The real mechanism, scoped honestly.** A real queen does not forage —
she stays in the hive her whole life, and her loss is existentially
important to a real colony (a queenless hive cannot requeen itself
forever; eventually it collapses without a replacement). No requeening/
succession precedent exists anywhere in this codebase to mirror (ants
have none either), so this ships the honest, minimal first pass named
as acceptable up front rather than a full requeening simulation:

- `BeeColony.has_queen_at(cell)` — real per-hive state, defaulting to
  `true` (mirrors `population_at`'s own "unset reads as the healthy
  default" fallback: a hive predates this mechanic, so it starts
  assumed healthy).
- **Swarming is the one real, already-named trigger for losing her** —
  this doc's own "Real-world grounding" already stated the biology
  ("the *old* queen leaves with roughly half the workforce... while the
  hive left behind raises a new queen from the brood already there and
  carries on") without any mechanic behind it. `bud_new_hive` now makes
  this real: the new hive gets `has_queen_at = true` (she left with the
  swarm), the parent hive left behind gets `has_queen_at = false` and
  starts a real requeening clock. Absconding is deliberately NOT a
  trigger — the whole colony relocates together, queen included, so
  `abscond_to` carries her presence (or absence/requeening progress)
  over unchanged.
- **A queenless hive cannot grow at all** (no queen laying means no new
  brood — there is no partial-capacity version of this the way merely
  being under-fed still has one) **and gradually declines**
  (`QUEENLESS_DECLINE_RATE_PER_DAY`, grounded in a worker honeybee's own
  real ~5-week active-season lifespan: with nothing replacing them,
  existing workers simply age out) — the real, observable "hive
  strength degrades without a live queen" consequence, readable through
  the hive's own existing population number and everything that already
  derives from it (growth-stage art, `active_forager_cap_at`).
- **A real path back**: once `REQUEENING_DAYS` (28 — grounded in a real
  queen's ~16-day egg-to-emergence time plus roughly another 5-10 days
  to mature and complete her mating flights, commonly cited in aggregate
  as about four weeks) of real simulated time passes, the hive raises a
  real replacement and resumes ordinary logistic growth from whatever
  population actually survived.
- `BeeHiveMarker.get_display_name` reports queenless/requeening state
  through the hive's own existing tooltip (`"... -- queenless,
  requeening (NN%)"`) rather than growing a second hoverable entity for
  one real boolean plus a progress number.

**Visual representation.** `BeeQueenMarker` (`src/rendering/
bee_queen_marker.gd`) is a new, deliberately simple, visual-only child
of `BeeHiveMarker` — never `BeeForagerMarker`'s scout/forage state
machine, since a real queen does not make that trip at all. She shows
one real static pose (`IllustratedBeeSprite.generate_queen_texture`,
frame 0 of the real "walk" band — she has no flight cycle to play
either) and is hidden entirely whenever `has_queen_at` is false, rather
than playing a "dying" pose that would have to sit there, misleadingly,
for the real multi-week `REQUEENING_DAYS` window. She reads as visibly
distinct from a worker — confirmed via a real render
(`tools/probe_bee_queen_verify.gd`), not assumed from real queen
biology alone: a gold crown with a red jewel (an unambiguous "this is
the queen" marker with no real-world equivalent, a deliberate legibility
choice), and a notably longer, more elongated, golden-amber abdomen
against a worker's shorter black-striped one, at
`WORLD_LENGTH_TILES_QUEEN` (0.27, real queen honeybees running ~18-22mm
against a worker's ~12-15mm) — roughly 1.6x a worker's on-screen width
at a shared zoom.

### Bee body poses — real row semantics, corrected

`bee.png`/`honeybee.png`/`honeybee_queen.png` are all 1536x1024 sheets.
Live user correction: *"Rows are: walking, flying, foraging, building
hive / nest, dying"* — five named concepts. The row originally shipped
as "fly" assumed an 8-column x 4-EQUAL-row x 192x256 grid (ported,
unverified, from `worm.png`/`caterpillar.png`/`millipede.png`'s own
sheets, which really do divide into 4 equal rows) — these three bee
sheets were never independently probed for their own real grid the way
every other illustrated sheet in this codebase was before shipping.
That guess happened to land exactly on this sheet's real walk/fly
boundary by coincidence, so row 0 ("assumed fly") was actually
**walking** — every bee had been animating through its walk cycle for
its entire always-airborne on-screen lifecycle (`BeeForagerMarker` has
no landed phase at all, see that class's own doc comment) until this
was corrected.

Measured directly (`tools/probe_bee_row_semantics.gd`: a per-row pixel-
density profile plus stitched, despilled visual crops of every band,
cross-checked against both worker sheets agreeing pixel-for-pixel, and
against the queen's own sheet): the real layout is **five bands of
non-uniform height**, packed edge to edge with zero blank divider row
anywhere in the whole 1024px height (confirmed: a blank-row scan found
exactly one band spanning all 1024 rows on every sheet — boundaries
were only found by locating where a pose needing the full 256px stops
and a pose fitting a compact 128px starts):

| Band | y range | Height | Real content |
| --- | --- | --- | --- |
| `walk` | [0, 256) | 256 | Ground contact: legs planted, a real drop shadow beneath every frame. |
| `fly` | [256, 384) | 128 | Level flight: legs tucked, no ground shadow, minimal frame-to-frame variation — the one band actually wired. |
| `forage_a` | [384, 640) | 256 | A taller, more dynamic reaching pose with a visible orange/red mark at the mouthparts on several frames (active nectar/pollen engagement). |
| `forage_b` | [640, 768) | 128 | A compact variant of `forage_a`, same mark. |
| `dying` | [768, 1024) | 256 | A progressive collapse across 8 frames: upright, then leaning, then legs curling inward, ending lying on its side — confirmed on all three sheets, including the queen's own (her crown stays visible through her own collapse). |

`IllustratedBeeSprite._ROW_BAND` now encodes this real layout.
`BeeForagerMarker` wires only `fly` — it is airborne its entire
lifecycle (SCOUTING → APPROACHING → RETURNING, see that class's own doc
comment on why it deliberately has no landed phase), and `forage_a`/
`forage_b` both carry a visible feeding mark that would read as wrong
during SCOUTING/RETURNING, when nothing has been (or is still being)
fed on. `walk`/`forage_a`/`forage_b`/`dying` remain real, delivered, and
correctly unwired for the identical reason they always were —
`BeeForagerMarker` has no landed/feeding/death phase to trigger them
from yet, named explicitly rather than silently dropped.

**"Building hive/nest" has no matching row on any of the three
sheets.** Checked directly rather than forced: a hive's own
construction/growth is already fully represented by the separate
`beehive.png` sheet (`IllustratedBeehiveSprite.growth_stage_index`,
see "Growth-stage and destruction art" below), and neither
`BeeForagerMarker` nor `BeeColony`/`WildBeePatch` has any "under
construction" phase a bee's own body pose would need to play for. A
real, honest "doesn't map, and doesn't need to" finding, not a gap.

### Absconding — relocation on destruction, harvest-collapse, or lost forage

The one mechanism with no ant precedent at all (a starved ant mound
`_maybe_refound`s at the same cell; it never moves). A hive cell
relocates — freeing its current marker and re-establishing a brand new
one at a freshly-searched site, carrying its population and remaining
honey across the move (mirroring `bud_new_mound`'s carry-the-numbers-over
shape, not a `STARTING_POPULATION` reset) — under any of three real
triggers, matching the live request's own three clauses:

1. **Destroyed / harvested to collapse.** A hive struck past its
   `HARVEST_HITS_TO_DESTROY` threshold (see "Harvesting honey" below) is
   gone as a structure; the colony absconds rather than the population
   being wiped out with it — a real, resilient colony surviving a raided
   nest is the whole reason this differs from a same-site refound.
2. **Sustained lack of nearby forage.** A decaying EMA of recent forage
   success (mirroring `_forage_success` exactly) sitting below a real
   floor for a sustained window — not a single unlucky trip, the same
   "sustained conditions, not one data point" reasoning
   `record_forage_result`'s own EMA already embodies for ants.
3. **Population collapse.** Population reaching 0 (the same hard-floor
   `PopulationModel.step` already produces once capacity hits 0) is
   folded into the SAME absconding path rather than getting `AntColony`'s
   own same-site-refound treatment — for bees, a colony that has
   genuinely run its home into the ground moves on rather than
   respawning where it just starved, which is the more real outcome for
   a mobile superorganism.

A relocated hive is a **real cost**, not a free reset: the new site search
can fail (no valid site with real forage in range), in which case the
colony is lost outright — the honest, real consequence of "no food
anywhere nearby," not something this doc papers over with a guaranteed
success.

**A site must also be a real, physical anchor — a tree or a structure,
never free-floating** (2026-09-08, see "Real-world grounding" above).
`BeeColony.is_valid_hive_site` only ever sees a biome grid — it cannot
know whether a real tree or building actually stands nearby, so this
lives one layer up, in `EarthChunkManager._find_bee_hive_site` itself,
alongside the existing real-nearby-forage check:
`_has_real_hive_anchor(pixel, global_tile)` rejects a river/lake tile
outright, then requires a real tree (`trees_near`) or a real building
piece (`chunk.modifications` + `BuildingPiece.has_piece`, the identical
idiom `TreeRenderer.spawn_trees` already uses to keep a tree from
rooting in a house) within a small, tight `HIVE_ANCHOR_RADIUS_TILES` —
a hive hangs from a *specific* branch or sits beside a *specific* wall,
not merely somewhere in the same general area as one. This covers
swarming, absconding, and harvest-relocation uniformly (all three route
through `_find_bee_hive_site`), but **not** initial world-generation
seeding — `BeeColony._seed_initial_hives` is a separate path with no
`_find_bee_hive_site` filter afterwards to catch a free-floating hive
it already placed, so `EarthChunkManager._load_chunk` now injects the
identical check as an optional `extra_site_check` Callable at
construction instead (`BeeColony._init`'s new 5th parameter, unbound —
and so a strict no-op — for every other/existing caller). Without this
second wiring point, every hive placed by ordinary world generation
(the most common way a hive appears at all) would have stayed
unconstrained even after site-search relocation was fixed.

### Harvesting honey — the one genuinely new player-interaction mechanic

No existing harvest mechanic fits a "take a partial resource from a
living, still-growing structure" interaction — trees/stone are
progressively destroyed to their drop, mushrooms are one-shot picked up.
A wild honeybee hive being broken into for its honey is real,
long-practiced human behaviour (traditional honey-hunting predates
beekeeping by millennia), and — confirmed directly against the supplied
art — row 3 of `beehive.png` draws exactly this: 8 frames of a mature
hive being progressively broken open, honeycomb spilling out, ending in
scattered debris. This doc follows the art rather than inventing a
separate mechanic: harvesting is multi-hit and destructive, reusing the
established `_attack_step` → per-mechanic-step → group-scan → duck-typed
verb pattern `_chop_step`/`_smash_step` already use (a new
`_harvest_beehive_step` in `player.gd`, scanning `BeeHiveMarker.
GROUP_NAME`, calling a `harvest_honey()`-shaped method — the same
family, not a new input verb).

- `HARVEST_HITS_TO_DESTROY := 8` — pinned to row 3's own frame count, not
  an arbitrary tuning number: the destruction sequence and the hit-count
  budget are the same 8 by construction.
- Each hit yields honey (capped by what the colony actually has stored —
  striking an already-empty hive still costs the swing, same as swinging
  at anything, but yields nothing) and advances the destruction-frame
  index; the sprite shows the matching row-3 frame once harvesting has
  begun, and reverts to nothing further once the marker is gone.
- The final hit frees the marker and triggers absconding (see above) —
  the colony's own population and any honey left un-harvested carry over
  to wherever it re-establishes, exactly like a swarm's own carried-over
  numbers, just at 100% rather than a 50% split.

### Foraging — `BeeForagerMarker`

A flying sibling of `AntForagerMarker`, reusing `AmbientFlyerMovement`
for real flight physics (the same way an ant's own SCOUT phase already
does for its ground wander) rather than the walking gait a forager ant
uses. Same three-phase shape as `AntForageBehavior`
(SCOUTING → APPROACHING → RETURNING), via the new `BeeForageBehavior`
duplicate named above. Targets a real nearby flower with real nectar —
reusing whatever query `EarthChunkManager`/`PollinatorForaging` already
expose for "flowers with nectar near here," never a second, parallel
flower-finding mechanism — drinks (reducing that bloom's real nectar,
same as the existing decorative pollinator already does), flies home,
and deposits into the hive's `_honey_stored` via `record_forage_result`/
a bee-appropriate deposit call. Concurrent foragers scale with the
hive's own population/capacity fraction (mirroring
`active_forager_cap_at`'s shape) without pheromone-trail dispatch (see
above).

**The existing decorative "bee" (`FlyerDiet`'s `"bee": [FOOD_NECTAR]`,
`AmbientFlyerRenderer.BEE_SPECIES_POOL`) is retired by this pass, not
kept alongside the new one.** It has no home, no population, and nothing
behind it but wander+nectar-sip — precisely the "presence without
population dynamics" gap `ecosystem_dynamics.md` already names as
unclosed. Every visible bee going forward is a real forager tied to a
real nest (a honeybee hive or a wild bee's hole) rather than two
unrelated "bee" concepts coexisting on screen — the same call this
project already made for caterpillars, ants, and millipedes: a shallow
decorative stand-in gets replaced by the real mechanism once one exists,
not run in parallel with it.

**A scout also detects distant scent, not just what it can already sense
locally** (2026-09-07, see `flora.md`#tree-blossoms-emit-real-scent-too
for the full mechanism spec, including why this is detection-and-commit
rather than a gradient blend: `ScentField`'s own real plume range is
*smaller* than a bee's close-sense radius already, unlike for a
butterfly). Local sensing (`_sense_food_nearby`,
`BeeColony.SENSE_RADIUS_TILES`) is unchanged and always preferred when it
finds something; only when it finds NOTHING does a scout also check
`_sense_distant_food` across its whole `BeeColony.FORAGE_RADIUS_TILES`
home range and commit straight to whichever real flower or blossom
scores highest by `ScentField.concentration_at` (real superposition: a
cluster or a stronger-scented species wins over a lone or fainter one).
This is what makes a real orchard or meadow pull a bee from beyond
guaranteed sensing range, rather than the scout only ever finding one by
wandering into it by chance — the missing half of "blossom scent should
attract bees."

### Growth-stage and destruction art — `IllustratedBeehiveSprite`

Rows 1-2 of `beehive.png` (16 frames, tiny exposed cluster → full sealed
hive) are a genuine size/growth progression, not cosmetic variants the
way `ant_mound.png`'s 3x3 grid is — so this follows `IllustratedCropSprite.
growth_stage_index`'s established "map a continuous growth fraction onto
a discrete frame index" convention instead of `IllustratedAntMoundSprite`'s
continuous-rescale-one-fixed-frame convention; the art itself, not an
arbitrary technique choice, decides which precedent applies here. Each
row is hand-measured as its own `_ROW_BAND` and sliced via the existing
`SpriteSheetSlicer.detect_frames`/`normalize_frames`, mirroring
`IllustratedAntMoundSprite` exactly (safe against the sheet not being
pixel-perfectly divided, the same "measure, don't assume" convention
`tools/probe_intro_sheet.gd`/`tools/probe_worm_sheet.gd` already
established) — measured with a dedicated probe script before any frame
boundary is pinned as a constant. Row 3 (8 frames) is the harvest/
destruction sequence described above, selected by harvest-hit count, not
growth fraction. Texture only actually reassigns when the computed index
changes, the same `stage == _drawn_stage` guard
`wild_crop_marker.gd` already uses.

### Wild bee nests — `WildBeePatch` / `WildBeeNestMarker`

Deliberately a MUCH lighter system than the honeybee hive economy above,
because the real biology is genuinely lighter: no queen, no worker caste,
no shared colony, no honey, no swarming. A per-chunk `WildBeePatch`
(mirrors `EarthwormPatch`'s own much simpler per-chunk fixed-site shape,
not `AntColony`'s full economy) deterministically places a handful of
real nest-hole sites in soil-bearing, tree-bearing biomes (a nest needs
real deadwood/an old stem nearby, the cavity-nesting guild's own real
requirement); each site tracks a small local population that grows
slowly as resident females forage nearby flowers and lay eggs (a
simplified stand-in for "more brood cells provisioned," at the same
abstraction level as `AntColony`'s own "abstract colony-strength number,
not a literal headcount"), gated by real nearby forage exactly like the
honeybee hive's own capacity, but with **no honey, no harvestable
resource, and no player interaction at all** — biologically correct, not
an arbitrary omission (see "Real-world grounding" above). It DOES
relocate on lost nearby forage (the one absconding trigger that still
applies — a real, if less dramatic, thing a lone female would do by
simply choosing a different hole next season), but is not
player-destructible in this pass — a real scope cut, named rather than
silently dropped, since there is nothing for a player to gain by
destroying one and "can be destroyed for no reason" is not itself a
mechanic worth building. No dedicated art was supplied for this (unlike
the honeybee hive); `ProceduralWildBeeNestSprite` — a small twig stub
with a dark entrance hole, the same "posterized circle + darker entrance
dot" technique `ProceduralAntMoundSprite` already established for a
structurally similar "small ground/branch feature with a hole" shape —
is the only art this pass ships, a real, named gap for future
illustrated art rather than a blocker.

### Tooltip distinction

`BeeHiveMarker.get_display_name()` and `WildBeeNestMarker.
get_display_name()` report genuinely different information, mirroring
`AntMoundMarker.get_display_name()`'s "population X, food Y" shape:
- Honeybee hive: `"Honeybee Hive (population %d, honey %d)"` — the
  colony's real population and real harvestable honey.
- Wild bee nest: `"Wild Bee Nest (%d resident%s)"` — no honey figure at
  all, because there genuinely is none to report; the absence itself is
  part of what makes the distinction read as real rather than reskinned.

Both join `HoverTargetFinder.GROUP_NAME`. Only `BeeHiveMarker` implements
`get_hover_actions()` (a `"Harvest"` verb) and `panel_state()` for the
HUD side-panel stack (`bar_label = "Honey"`, `health_fraction =
honey_availability_fraction`) — `WildBeeNestMarker` is hoverable (a name
and nothing else) but not panel-worthy or interactive, matching its
lighter mechanism above.

## Status

✅ **Honeybee colony economy** (`src/world/bee_colony.gd`,
`src/world/bee_population_model.gd`) — per-chunk placement (tree-bearing
biomes, sparser than `AntColony`'s own mound density), queen-driven
logistic growth bounded by real forage success, a real honey reserve
that is both the colony's own food AND the exact quantity a harvest
withdraws, winter dormancy (warmth only, no water/moisture input),
swarming (`bud_new_hive`, an even population/honey split, real
site-search), and absconding (`abscond_to`, a full-colony move, no
same-site refounding the way a starved ant mound gets).

✅ **A real queen** (`has_queen_at`/`_advance_queenless` in
`src/world/bee_colony.gd`, `src/rendering/bee_queen_marker.gd`) — added
live, in a later pass than the rest of this doc: "queen-driven
population" was flavor text with no queen entity behind it until this
(see "The queen" above); `bud_new_hive` now makes her departure with a
swarm real, a queenless hive cannot grow and gradually declines
(`QUEENLESS_DECLINE_RATE_PER_DAY`), and a real `REQUEENING_DAYS` clock
restores her. `BeeQueenMarker` shows her one real static pose at the
hive, visibly distinct from a worker (crown, longer abdomen, larger
`WORLD_LENGTH_TILES_QUEEN`), hidden entirely while queenless. A
deliberate departure from the ant precedent (`AntColony` has no queen
entity at all, by design).

✅ **Real illustrated growth/harvest art** (`src/rendering/
illustrated_beehive_sprite.gd`, `src/rendering/
procedural_beehive_sprite.gd`) — the user-supplied `beehive.png` sheet
sliced on its own known-regular grid; 16 real growth-stage frames
selected by a discrete `growth_stage_index` (the art itself dictated
this technique over `IllustratedAntMoundSprite`'s own continuous-
rescale one), 8 real destruction frames selected by harvest-hit count.

✅ **`BeeHiveMarker`** (`src/rendering/bee_hive_marker.gd`) — hover
tooltip (population + honey), HUD honey bar
(`scenes/world.gd._update_creature_panels`), and the one genuinely new
player interaction this whole feature adds: `harvest()`, multi-hit and
destructive (`HARVEST_HITS_TO_DESTROY` pinned to the real 8-frame
destruction sheet), wired into `scenes/player.gd._harvest_beehive_step`
alongside `_chop_step`/`_smash_step`. The final hit frees the marker and
hands off to `EarthChunkManager.relocate_bee_hive_after_harvest` — the
colony survives, it just needs a new site.

✅ **Real round-trip foraging** (`src/gameplay/bee_forage_behavior.gd`,
`src/rendering/bee_forager_marker.gd`) — flies (not walks) via
`AmbientFlyerMovement`, scouts with no known target, senses real
in-bloom nectar through the SAME `EarthChunkManager.flowers_near/
drink_nectar_at` query the old decorative pollinator used, re-checks on
genuine arrival, deposits only once actually home. No pheromone-trail
recruitment this pass (see "What's reused verbatim..." above).

✅ **Real illustrated forager art, at a real scale, real row semantics**
(`src/rendering/illustrated_bee_sprite.gd`) — `honeybee.png`/`bee.png`
sliced and animated at a measured `world_scale` (~0.18 tiles, a real
honeybee's own ~12-15mm), replacing the old unscaled procedural "bee"
silhouette. The row wired for flight was corrected in a later pass —
see "Bee body poses" above for the real, non-uniform 5-band layout and
why the originally-shipped row was actually walking, not flying.

✅ **`BeeQueenMarker`** (`src/rendering/bee_queen_marker.gd`) — see "The
queen" above.

✅ **Scent-drawn foraging and a real pollination gate** (2026-09-07, see
`flora.md`#tree-blossoms-emit-real-scent-too and #where-a-forest-comes-
from) — an uncommitted scout now also detects (and commits straight to)
the strongest flower/blossom by `ScentField.concentration_at` across its
whole home range (`BeeForagerMarker._sense_distant_food`), not just what
close-range sensing already finds; `FruitingModel.pollination_factor`'s
floor is a genuine 0.0 (was a 0.2 soft discount), so an insect-pollinated
tree with zero real visits this cycle bears nothing at all, and
`EarthChunkManager.step_tree_spread` withholds an unvisited one from
seeding new trees too. Closes the full loop the feature exists for:
blossom → scent → bee attraction → visit → fruit set and new growth.

✅ **A hive must be a real physical anchor — a tree or a structure,
never free-floating** (2026-09-08, see "Absconding" above) —
`EarthChunkManager._has_real_hive_anchor` gates swarming, absconding,
and harvest-relocation (via `_find_bee_hive_site`) AND initial
world-generation seeding (via `BeeColony._init`'s new optional
`extra_site_check` Callable, injected only by real chunk loading —
every other/existing caller is completely unaffected). Never a
river/lake tile; otherwise a real tree or a real building piece within
a small, tight radius. **Wild bee nests have the identical claim
("needs real deadwood/an old stem nearby") and no equivalent
enforcement — a known, named, not-yet-fixed parallel gap**, since this
pass was specifically asked about honeybee hives.

✅ **Wild bee nests** (`src/world/wild_bee_patch.gd`, `src/rendering/
wild_bee_nest_marker.gd`, `src/rendering/
procedural_wild_bee_nest_sprite.gd`) — the much lighter solitary/
cavity-nesting system: no honey, no harvest, no swarming, a fixed-size
procedural hole (no illustrated art supplied for this one — a real,
named gap for future art), relocates on sustained lost forage (the one
absconding trigger it keeps). `BeeForagerMarker` serves it too (a lone
resident's own real forage trip), not a separate near-duplicate marker.

✅ **`EarthChunkManager` wiring** — `step_bees` (chunk load/unload,
advancing, swarming, absconding, forage dispatch for both hives and
wild nests), called from `scenes/world.gd._step_ecology_batch` on the
same batched cadence `step_ants` already uses.

✅ **The decorative ambient "bee" pollinator is retired** —
`FlyerDiet.DIET_BY_SPECIES`/`AmbientFlyerRenderer.BEE_SPECIES_POOL` (and
its own per-chunk budget/spawn call) are gone; `TRUE_BUTTERFLY_SPECIES_POOL`
(monarch/swallowtail/blue_morpho) is the only remaining ambient
pollinator roster. `ProceduralButterflySprite`'s own "bee" art tables
are deliberately UNTOUCHED (`BeeForagerMarker` still reuses that exact
generator directly — only the old spawn/lifecycle is retired, never the
art). Closing this also surfaced and fixed a real regression risk: the
old decorative bee's `TREE_POLLINATING_SPECIES` was the ONLY code path
pollinating blossoming fruit trees at all — `BeeForagerMarker` now
covers that too (see "Foraging" above), so tree pollination did not
silently disappear along with the decorative species.

⬜ **Pheromone-trail recruitment for honeybees** (the real waggle dance)
— named explicitly as out of scope this pass, not silently dropped (see
"What's reused verbatim, what's a deliberate new duplicate, and why").

⬜ **Illustrated art for the wild bee nest hole** — ships procedural-only
this pass, the same "real mechanism first, real art later" order ants
themselves went through.
