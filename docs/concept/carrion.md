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

#### Flies find it first

A carcass is rot the same way a windfall fruit is (`docs/concept/
olfaction.md`'s shared `DECAY` molecule), so it grows its own real
`FlyColony` (see `docs/concept/flies.md`) rather than a fake counter — one
founder settles a fixed, tested delay after death (real blowflies find a
body within minutes, well before a `Carcass` is rotten enough for
decomposers to actually feed on it, so the delay is a real fraction of
`ROT_SECONDS`, not equal to it), and everything after that is bred, the
same "one founder, not a swarm" rule the ground-food fly loop already
follows. That visible swarm is itself a real signal a decomposer acts on:
real scavengers cue off circling flies as a sign something is worth
investigating, so a fly-blown carcass reads as CLOSER to a hunting ant or
carrion bug than an identically-placed fresh one
(`CarrionForageBehavior.effective_distance`), and can be noticed a little
past the ordinary search radius — a fly-blown carcass is measurably more
likely to draw a decomposer than a fresh one, not merely as likely.
`CarcassGuts` is excluded from this loop, the same scope cut `disease.md`'s
carry-vector chain already makes for offal: real offal spoils too fast for
a fly colony to establish itself there before it is gone. This same fly
presence also closes a second loop, into `disease.md`'s CARRION archetype —
see that doc's own mechanism spec and Status.

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
- ✅ Flies find a carcass first, and decomposers measurably prefer a
  fly-blown carcass over a fresh one — `Carcass` grows a real `FlyColony`
  after a tested delay tied to its own age (`Carcass.fly_count`/
  `FLY_ATTRACTION_DELAY_SECONDS`), and the new
  `CarrionForageBehavior.effective_distance` discounts a fly-blown
  carcass's distance so `DecomposerMarker._nearest_food` picks it over
  a nearer, fresh one (`test_prefers_a_fly_blown_carcass_over_a_closer_
  fresh_one`). The same fly presence also closes the loop into
  `disease.md`'s CARRION archetype — a fly-blown carcass carries
  measurably higher local graze risk than an identically-rotten, fly-free
  one (`DiseaseModel.carrion_graze_transmission_chance`'s new `fly_count`
  term, read from the real carcass by `CreatureMarker._carrion_disease_
  step`) — proven end to end in one test,
  `test_corpse_age_drives_fly_count_which_measurably_raises_local_
  disease_risk` (`tests/unit/test_carcass.gd`): corpse age in, fly count
  out, disease risk out, all through the real production code, not three
  disconnected unit tests. See `disease.md`'s own Status for that half.
- ✅ Universal hover tooltip coverage (name + remaining parts' actions) for
  carcasses and guts, via the existing `get_display_name`/
  `get_hover_actions` contract.
- ✅ **Two rendering/movement bugs and one real ecosystem-gear extension**
  (reported live: "there are still gigantic ant blobs but they don't
  move... ants should eat fallen fruits, leaves and other stuff like
  seeds"):
  1. **Gigantic sprite.** `ProceduralDecomposerSprite`'s art canvas is
     authored at `ArtResolution.DETAIL_MULTIPLIER`, the same
     oversample-then-scale-down convention every other sprite generator in
     this codebase follows — but `DecomposerMarker` was the one generator
     that never actually applied `ArtResolution.SPRITE_SCALE`, so it
     rendered at its raw art-canvas size instead of its intended tiny
     insect world size. Direct precedent for the exact same failure mode:
     `ProceduralItemSprite`'s own doc comment records a fallen cherry once
     being "as wide as the tile it lay on" for the identical missing-scale
     reason. Fixed: `sprite.scale = Vector2.ONE * ArtResolution.SPRITE_
     SCALE` in `_ready()`, pinned by
     `test_sprite_is_drawn_at_its_real_tiny_world_size_not_the_raw_art_
     canvas`.
  2. **Frozen while idle.** `_step_seeking` only ever pulled a decomposer
     BACK toward home once it had drifted past `WANDER_RADIUS_PX` — nothing
     ever sent it wandering away from home in the first place, so an idle
     decomposer with nothing nearby to eat sat on exactly one frozen
     position forever (the existing `test_stays_near_home_while_nothing_
     to_eat` passed either way, since a frozen ant trivially "stays within"
     any radius — it just never proved actual wandering). Fixed by reusing
     `AmbientFlyerMovement`'s already-tested home-anchored roam algorithm
     (the same one `AmbientFlyerMarker` uses) rather than a second,
     near-duplicate wander implementation — pinned by
     `test_wanders_when_idle_instead_of_sitting_frozen`. This in turn
     exposed a THIRD, latent bug: `_step_approaching`'s unclamped
     `position += direction * speed * delta` overshot straight past a
     target now that SEEKING could hand APPROACHING a real gap to close,
     then overshot back on the very next step — forever, a decomposer that
     commits to a real, reachable target and never actually arrives.
     Latent since this marker was first built (a frozen SEEKING phase
     always started APPROACHING already within `ARRIVE_DISTANCE_PX`).
     Fixed with `position.move_toward(target, WALK_SPEED * delta)`, the
     same clamped-arrival shape `NpcMarker._process` already uses; pinned
     by `test_approaching_a_close_target_does_not_overshoot_and_orbit_
     forever`.
  3. **Opportunistic fallen-fruit/nut foraging.** An ant/carrion bug is a
     real omnivorous scavenger, not a carrion specialist — and this
     project already has an entirely separate, invisible ant simulation
     (`AntColony`, see `soil_fauna.md`) that eats fallen seeds and windfall
     fruit/nuts, just with no on-screen representation, so a player could
     never actually SEE it happening. `DecomposerMarker._nearest_food`
     (renamed from `_nearest_carrion`) now also scans
     `DroppedItem.FORAGEABLE_GROUP_NAME` — a small, pre-filtered group any
     `TreeSpecies`-identified item joins at creation rather than the whole
     "dropped_item" group filtered per scan (see `DroppedItem`'s own doc
     comment: scanning the WHOLE group — `LiftableStone`/`PickableSeed`
     very much included — for every one of a decomposer's own foraging
     checks was a real, measured fps cost, "game now has only 4-5 fps", not
     a cosmetic inefficiency); `_step_feeding` eats a found fruit/nut
     outright in one visit (`_target.queue_free()`) rather than whittling
     down a health pool the way a carcass bite does — a dropped cherry is
     not a boar carcass. Pinned by
     `test_forages_and_eats_nearby_fallen_fruit_when_theres_no_carrion`/
     `test_ignores_a_dropped_item_that_is_not_food`. **Deliberately NOT
     attempted here** (named, not silently dropped): ground-SEED foraging
     by these visible ants (`AntColony` already does this invisibly;
     making it visible would mean giving `AntColony`'s mounds a real
     rendered presence, a bigger unification project of its own). A
     "fallen leaves" mechanic did not exist anywhere in this codebase at
     the time (only cosmetic seasonal ground-tint/canopy color, no real
     leaf-litter entity) — a real prerequisite-free win here was wiring
     the visible ants into fallen fruit, which already existed, rather
     than building a whole new leaf-litter system speculatively. Leaves
     have since become a real `FORAGEABLE_GROUP_NAME` item too, needing no
     further change to this function at all — see
     [leaf_litter.md](leaf_litter.md).
- ✅ Real illustrated art for both species (2026-09-05), replacing
  `ProceduralDecomposerSprite`'s drawn silhouettes: `ant.png`/`beetle.png`,
  hand-illustrated walk cycles (`IllustratedDecomposerSprite`, same
  "sheet → `SpriteSheetSlicer` → cached frames" shape `IllustratedAnimalSprite`
  uses for grazing quadrupeds, deliberately not built on it — decomposers
  are not on the `CreatureMarker`/`AnimalAnatomy` stack at all, so this
  carries none of that stack's per-species anatomy or swim/drink/attack
  fallback chain, just the three actions a decomposer actually has). `ant.png`
  also draws a distinct carry pose (body + cargo) that `AntForagerMarker`
  now uses for its own pickup→cache leg — see `soil_fauna.md`'s own
  "Rendered presence" section. `DecomposerMarker` now actually animates: the
  walk cycle steps by elapsed time while SEEKING/APPROACHING, and switches to
  a legs-gathered idle cycle while FEEDING (a stationary decomposer with
  animated walking legs would read as sliding in place); both sheets face
  left natively, and a real horizontal step mirrors the sprite the way
  `CreatureMarker.facing_sign`'s own convention does. `has_action()`-gated
  throughout — a species with no registered sheet falls straight through to
  `ProceduralDecomposerSprite`, unchanged.
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
