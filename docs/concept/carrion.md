## Carrion: a carcass is a real object, not an instant loot spray

A killed animal used to die and dissolve into hide+meat items in the same
frame (`CreatureMarker._drop_loot`) — the exact "evaporates instead of being
cut down" pattern already fixed once for trees (see `progress.md`'s Long
Grass/Flora history). This closes the same gap for creatures: a kill leaves
a real **carcass** behind. The player butchers it by hand, in stages, for
real parts — and if nobody does, the carcass rots and a new trophic tier
(ants, carrion beetles) actually finishes it, the same way real decomposers
close every food web this project models.

Reported: *"killing a boar should leave a carcass if not cleaned up by a
player ... the player can cut out the meat parts and skin ... if he takes
out the guts they spawn as entity and stay in the world so other animals
can eat them ... then we need ants and bugs to clean up the left parts ...
all this should be skills the player can train."*

### Design pillars

- **A carcass is a physical object with parts, not a bag of loot.** Killing
  something is the start of a process (skin it, take the meat, the guts),
  not a single transaction — the same "felling is the first half of the
  job" split `ChoppableTree`/`FelledTree` already established for wood.
- **Guts are food, not inventory.** Offal isn't something a player carries
  or eats — it's what a real carcass most urgently offers a scavenger. It
  becomes its own object in the world specifically so the ecosystem can eat
  it, the same "a real object other systems can act on" idea a dropped
  fruit already is for a bird.
- **Decomposition is a real trophic tier, not a despawn timer.** An
  unbutchered (or partially butchered) carcass doesn't just vanish after a
  while — ants and carrion-feeding bugs are drawn to it and visibly consume
  it, closing the loop `soil_fauna.md` opened for plant litter but never
  extended to animal remains.
- **Cutting well is a trained skill**, not a flat, always-perfect action —
  ties into the one *real, live* progression system this project has
  (`SkillTree`'s point-allocation web, not `skills.md`'s much larger
  aspirational DNA-passive system, which has no code yet and would be a
  separate, far bigger undertaking).

### Real-world grounding

- **A field-dressed carcass really does come apart in this order**: hide
  off first (it's in the way of everything else and is worth keeping
  intact), then the muscle meat, then the viscera (gutting) — evisceration
  is in fact often done *before* skinning in real practice to stop the meat
  spoiling from the inside, but the reverse order reads more clearly as a
  game interaction (skin → meat → guts, each a visibly different cut) and
  the real urgency that ordering exists for is instead modeled directly as
  the guts' own fast decay (see below) — a deliberate, named simplification.
- **Offal spoils fastest.** Viscera are already colonized by gut bacteria
  and have the least structural protection — hunters and butchers
  universally treat them as the first thing to go off. The guts entity
  therefore decays far faster than the meat/hide would.
- **Ants and carrion beetles are real, primary carcass decomposers** —
  *Silphidae* (burying/carrion beetles) specifically locate and consume
  carrion, and ants recruit to any exposed meat source opportunistically.
  This is the literal real-world "cleanup crew" for anything larger that
  dies in the open and isn't scavenged by a vertebrate first.
- **A carcass does not last.** Left alone, decomposition (bacterial +
  insect) reduces even a large carcass to bones over days in warm weather —
  fast on a game clock the same way `FruitSpoilage`'s "a windfall rots in a
  season, compressed to real minutes" already treats plant decay.

### Mechanism spec

#### The carcass (`Carcass`)

Spawned in place of the old instant `_drop_loot()` call, for exactly the
species that currently have a real loot table (see `LootTable._DROPS`).
Mirrors `SmashableStone`'s "N hits, N states" shape rather than
`ChoppableTree`'s two-stage fell/cut split — a carcass doesn't move or fall,
it just has parts.

- **Parts remaining**, an ordered list (`Butchering.PART_ORDER`: hide,
  meat, guts) — one real swing removes the next remaining part, same
  swing-driven interaction every other harvest in this game already uses
  (chop/smash/mine/pull, all bound to `attack`). Hide and meat drop as
  ordinary ground items (`WorldItemBus.item_dropped`, same path as
  everything else); guts do NOT — they spawn a `CarcassGuts` entity
  instead (see below).
- **Freshness**, a decay timer independent of butchering progress — a
  carcass rots whether or not the player ever touches it. Once it crosses
  the ROTTEN threshold, decomposers (see below) can start actually eating
  it regardless of what parts remain.
- **Decomposition health.** Once rotten, a carcass also has a consumable
  pool decomposers whittle down (`take_bite`) — when it reaches zero the
  carcass is gone, cleaned up, whether or not the player ever butchered it
  at all. An untouched carcass a player ignores is not permanent clutter.

#### Guts (`CarcassGuts`)

A real world entity, not an item: it has a position, decays on its own
(faster) timer, and offers itself to anything that eats carrion the same
`take_bite` contract the carcass itself uses — so a decomposer (or, later,
an opportunistic predator/omnivore — see Status) doesn't need to
distinguish "carcass" from "guts", only "something here is carrion."

#### Butchering (`Butchering`, `Player._butcher_step`)

Same melee-range-sweep shape as `_chop_step`/`_smash_step`/
`_pull_wild_crop_step`: a swing connecting with a nearby `Carcass` removes
its next remaining part. The hover tooltip (`get_display_name`/
`get_hover_actions`, see the UI/presentation universal hover system) shows
the carcass's species and remaining parts, and "Butcher (Space)" while any
remain.

**Skill-gated yield**, not a gate on the action itself — anyone can
butcher, a trained player gets more out of it (real butchery: skill
changes yield/waste, not whether you're physically able to cut). A new
`butchering_1`/`butchering_2` node pair in `SkillTree` (same shape as the
existing `naturalist_1`/`2` stamina nodes) raises `bonus_meat_yield`;
`Butchering.meat_count` reads it the same way `Player._apply_skill_stat`
already reads allocated nodes for other stats.

#### Decomposers: ants and carrion bugs

Deliberately **not** built on `CreatureMarker`/`CreatureInfo` — that stack
is a full roaming-wildlife AI (flee/fight/hunt/graze/mate/ecosystem
population tracking), the wrong shape for a tiny insect whose entire
behavior is "find carrion, eat it, wander otherwise." Mirrors
`AmbientFlyerMarker` instead (home-anchored ambient wander, no ecosystem
population math), with a new ground-based forage state machine
(`CarrionForageBehavior`) shaped like `GroundForageBehavior`
(seek → approach → feed → resume) but simplified for a crawler with no
"descend" phase — it's already on the ground, so "approach" just walks
there and ends on arrival, exactly like `PollinatorForaging`'s own
landing-distance convention.

Two species, both carrion-only (no nectar/seed/worm diet — a real ant or
carrion beetle at a carcass is there for the carcass): **ant** (small,
fast, swarms) and **bug** (a carrion beetle stand-in; slower, bigger bite).
Both eat from `Carcass` OR `CarcassGuts` indiscriminately via the shared
`take_bite` contract above.

### Status

- ✅ Carcass entity, real parts (hide/meat/guts), independent decay/rot
  clock — `src/rendering/carcass.gd`.
- ✅ Guts as a real, faster-decaying world food entity, not an item —
  `src/rendering/carcass_guts.gd`.
- ✅ Butchering: swing-driven part extraction —
  `src/gameplay/butchering.gd` (pure part-order/yield logic),
  `Player._butcher_step`.
- ✅ Skill-gated meat yield — `SkillTree`'s `butchering_1`/`butchering_2`
  nodes.
- ✅ Ants + carrion bugs: ambient decomposer creatures that find and
  consume carcasses/guts — `src/gameplay/carrion_forage_behavior.gd`,
  `src/rendering/decomposer_marker.gd`/`decomposer_renderer.gd`.
  **Follow-up (readability):** `ProceduralDecomposerSprite.ANT_COLOR` was
  `Color(0.08, 0.06, 0.05)` — a hair from `PixelPalette.OUTLINE`
  `(0.08, 0.06, 0.1)`, the shared near-black ring every creature generator
  draws around its own silhouette — and this generator never actually drew
  that ring at all (it instantiated `PixelPalette` but never called it).
  With the fill and the never-drawn outline the same color, a whole ant or
  bug rendered as one undifferentiated black blob rather than a small dark
  creature (reported live, from a real screenshot: "these black blobs",
  identified from a follow-up close-up crop as a creature silhouette, not
  flora). Fixed by darkening `ANT_COLOR`/`BUG_COLOR` to warm dark-brown
  chitin tones clearly apart from `OUTLINE` (real ants/carrion beetles stay
  genuinely dark, per this doc's own Silphidae note above — this isn't a
  move toward brightness for its own sake) and by actually ringing the
  silhouette, reusing `ProceduralBirdSprite._outline_silhouette`'s exact
  technique. Both halves are pinned separately in
  `test_procedural_decomposer_sprite.gd` (a minimum RGB distance from
  `OUTLINE`, and a direct check that an outline-colored pixel exists in the
  generated image) rather than left an eyeballed color pair.
- ✅ Universal hover tooltip coverage (name + remaining parts' actions) for
  carcasses and guts, via the existing `get_display_name`/
  `get_hover_actions` contract.
- ⬜ Opportunistic scavenging by existing predators/omnivores (a bear or
  jackal actually walking to and eating a fresh carcass/guts instead of
  only hunting live prey) — the `take_bite` contract is already shaped to
  support this, but wiring it into `CreatureBehavior`'s decision tree is a
  real, separate AI change, deliberately deferred rather than folded into
  this already-large pass.
- ⬜ Species-specific butcher yields (a bear's hide vs. a boar's hide) —
  today every carcass-eligible species shares one part order/quantity,
  mirroring `LootTable`'s own existing flat-by-role shape
  (`herbivore`/`boar`/`predator`/`lynx`) rather than inventing new
  per-species tuning in the same pass.
- ⬜ Persistence/catch-up integration for carcasses across a chunk
  unload — a carcass is chunk-local, ephemeral state, same explicit scope
  cut `soil_fauna.md`'s worm burrows already made for the same reason.
