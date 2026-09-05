# Capture DSL: generic animal-capture mechanics

Reported directly: an experienced crafter should be able to invent completely
new capture items — "every animal needs to be catchable with the right
device" — the same way [magic.md](magic.md) lets a crafter invent new spells,
and the physics of a specific device (e.g. "a butterfly gets caught with a
probability upon performing its catch action") should be authored as data,
not hand-coded per tool.

[taming.md](taming.md)'s "Any animal, the right tool" section already made
*which* device a species needs fully generic (read off `AnimalAnatomy`
body-plan data, not a species allow-list). What stayed hand-coded was *what
happens* when the device is actually used: the lasso's restrain-and-struggle
loop and the net's instant, always-succeeds catch are both bespoke Player/
CreatureMarker code, not data a new device could reuse or vary. This doc
specs the DSL that closes that second gap, in the same spirit
[spell_runtime.md](spell_runtime.md) closes it for magic: a small text
language, parsed into a plain AST, executed by a small set of pure modules.

> **Revised 2026-09-05 — the net is a device.** Reported: *"refactor the
> butterfly net to express that it catches small animals like butterflies,
> fish, small birds; but not e.g. bees / flies because the net is not tight
> enough — it should also encode the capture action which confines the
> subject to the net."* The net is now authored in
> [standard_model.md](standard_model.md)'s `device` grammar: a real bag part
> whose mesh has an `aperture_mm`, so what it holds is read off the subject's
> body and the bag's geometry rather than off a `tier` guard, and its catch
> pipeline names the part the subject ends up confined in. The old `capture`
> block kind and its parser are retired. Sections below marked *(2026-09-05)*
> are the revision; the rest stands.

## Design pillars

- **The tool-fit layer stays exactly as it is.** `CaptureTool.required_tool_for`
  deriving lasso/snare/net/trap/reinforced-rope from body-plan data is
  already the generic, derive-don't-enumerate mechanism this whole family of
  docs insists on. This DSL does not re-decide *which* device a species
  needs — it specs what a device *does* once it's the right one in hand.
- **Odds are derived from device tuning plus real target biology, never
  eyeballed per throw.** A device's DSL text supplies one tuned `base`
  number; everything else the odds depend on (an individual's boldness,
  say) is real data the simulation already tracks, the same "derive, don't
  author a special case" discipline `magic.md`'s cost model holds itself to.
- **A pipeline can fail partway, on purpose.** Magic's pipeline is an
  unconditional sequence — every atom happens. Capture's is not: a `catch_roll`
  atom can fail and short-circuits everything after it in the same pipeline.
  This is capture's own constraint layer, as load-bearing here as "cost is
  derived" is to magic: an author cannot write a device that always works,
  because the roll atom is what stands between "attempted" and "happened."
- **One tool holds at most one thing, and holding it is a real state, not an
  instant transaction.** Netting a monarch does not instantly decide its
  fate the way it does today — the net becomes loaded, and the player
  decides what happens to what's inside it. A loaded tool cannot catch again
  until it's empty, the same real constraint a one-net-in-hand trapper has.
- **What a net holds is geometry, not a species list** *(2026-09-05)*. A
  bag's mesh has a real aperture and a real mouth; a subject has three real
  body extents. Whether it is held is one comparison per fact: it slips
  through if it is narrower than the mesh, it does not fit if it is longer
  than the mouth. No species is named anywhere. That is what makes a finer
  net, a bigger landing net or a coarse fish trap something an engineer
  *writes* rather than something a designer adds — the derive-don't-enumerate
  rule [emergent_crafting.md](emergent_crafting.md) already holds items to.
- **The capture act is a confinement, and the text says where**
  *(2026-09-05)*. `confine(in: bag)` is the atom, and it may only follow a
  `mesh_holds` on the same part: a rule cannot confine a subject in a bag
  whose mesh has not been shown to hold it. That check is static, the same
  way `ItemCompiler` resolves an affordance's conjunctions at compile time
  — an author cannot write a net that ignores its own mesh.

## Real-world grounding

- A netting attempt against a real insect is genuinely probabilistic and
  genuinely biology-linked: a habituated or sluggish individual sits still
  long enough to be netted; a wary one is airborne before the hoop closes.
  `FlyerPersonality.boldness_of` already models exactly this axis (it exists
  specifically so netting bold individuals out of a meadow makes the meadow
  shyer over generations) — this DSL is the first thing that actually reads
  it at catch time, rather than only at flee/dance time.
- A field net (or trap, or bottle) is a real, single container: you cannot
  scoop up a second insect while the first is still inside without dealing
  with it first. "The net is full, decide what happens to what's in it
  before it can catch again" is not a game rule bolted on for balance, it's
  what a net physically is.
- **A net's mesh is a real gauge** *(2026-09-05)*. A honeybee worker is
  12–15 mm long and about 6 mm across; a housefly 6–7 mm by 3; a monarch's
  body is 25 mm and its folded wings stand nearly 50 mm tall; a house
  sparrow is 140 mm by 45; a pond goldfish 150 mm by 50. The standard net
  here is a coarse bag net with a **10 mm** mesh and a **30 cm** mouth: it
  holds everything in that list except the bee and the fly, which pass a
  10 mm opening the way they pass a garden fence. An entomologist's aerial
  net is roughly a 1 mm mesh and holds both — and in this game that is
  simply a *different net*, written with `aperture_mm: 1`. A 35 cm trout
  does not go through a 30 cm mouth before it turns, which is why anglers
  carry a landing net larger than the fish they expect; `width_cm: 40` is
  that net.

## The net is a device *(2026-09-05)*

The net is authored in the `device` grammar of
[standard_model.md](standard_model.md) — the same tokenizer and the same
`on EVENT(ARG) when GUARD: pipeline` rules the first version of this doc
used, plus the `part` / `joint` clauses that give the net a real body. The
`capture` block kind and `capture_parser.gd` are retired: the device grammar
is a strict superset, and two grammars for one rule shape is exactly the
drift this project's docs keep warning about. The executor
(`capture_executor.gd`) never knew which parser produced its AST, and still
does not.

```
device "Butterfly Net" {
  part handle: wood haft grip (length_cm: 120, diameter_cm: 2.5)
  part hoop: iron haft structure (length_cm: 94, diameter_cm: 0.4)
  part bag: fiber face cover (width_cm: 30, height_cm: 60, thickness_cm: 0.05, aperture_mm: 10)
  joint ferrule: handle to hoop rigid fit iron
  joint hem: hoop to bag rigid lashing fiber

  on catch:
    mesh_holds(mesh: bag) |> catch_roll(base: 0.65) |> confine(in: bag)
  on release:
    free(from: bag)
  on transfer(glass_bottle):
    move_captive()
}
```

Three things to read off it. The bag's `aperture_mm` is an **extra
dimension** on a `face` part — the exact precedent `emergent_crafting.md`'s
rip saw set with `tooth_pitch_mm` and `tooth_set_mm` on an edge: a dimension
the geometry does not need for volume but the physics reads. The mouth is
the bag's `width_cm`. And there is no `when target.tier == "flyer"` guard
any more: the pipeline's first atom *is* the physics that decides who can be
caught, and it says why when it refuses.

A net has no `loop` — nothing flows through it — so `DeviceCompiler` builds
its part graph (a 94 cm iron hoop, a 1.2 m wooden handle, a fibre bag; under
half a kilogram) and exposes every part's dimensions and derived figures as
**facts** the rules can read (`bag.aperture_mm`, `bag.width_cm`,
`bag.mass_kg`). That is the one thing the standard model had to grow for
this: rules over a device's *parts*, not only over its solved loop.

`on transfer(glass_bottle)` still reuses the event-argument slot to name
*which* container a rule handles, the same reuse trick `on cast(touch)`
makes of that slot for delivery method.

## Atom catalog (v2, 2026-09-05)

Still a small, fully-wired set — every atom has a real dispatcher and a real
caller; nothing is catalogued ahead of having somewhere to run.
`hold_captive` and `release_captive` are retired in favour of the two atoms
that say *where*.

| Atom | Category | What it does |
|---|---|---|
| `mesh_holds(mesh: PART)` | check | The physics gate, and the first thing that can fail. Reads the named bag's `aperture_mm` and `width_cm` off the device facts and the subject's extents off the context (`CapturePhysics.mesh_verdict`); fails, **with a reason**, if the subject slips through the mesh, does not fit the mouth, or has no measured size. Failure stops the rest of the pipeline. |
| `catch_roll(base)` | roll | Unchanged: pass/fail from `CapturePhysics.catch_chance(base, boldness)` against a caller-supplied roll; failure stops the pipeline, without a reason — a miss is a miss. |
| `confine(in: PART)` | effect | Sets the tool `Item`'s `captive_species` to the subject. **Statically** required to follow a `mesh_holds(mesh: PART)` on the same part in the same pipeline (`CaptureExecutor.validate`), so no text can confine a subject in a bag its mesh was not shown to hold. |
| `free(from: PART)` | effect | Clears `captive_species`. Names the part the subject leaves, for the same reason `confine` names the one it enters. |
| `move_captive()` | effect | Unchanged: reports the species that moved so the container can be rendered as it, and empties the tool. |

## Physics: how a chance is derived

`capture_physics.gd`, pure and property-tested like `spell_cost.gd`:

```
catch_chance(base, boldness = FlyerPersonality.MIDDLING_BOLDNESS) =
    clampf(base + (boldness - 0.5) * BOLDNESS_WEIGHT, 0.0, 1.0)
```

`BOLDNESS_WEIGHT := 0.3` (tested, not eyeballed): a middling-boldness
individual (0.5, the default for anything with no personality rolled — a
hand-placed test fixture, say) gets exactly the device's own `base`; the
boldest real individual (1.0) gets `base + 0.15`; the shyest (0.0) gets
`base - 0.15`. With `butterfly_net`'s own `base := 0.65`, real odds land in
`[0.5, 0.8]` — nudged by the individual, never turned into a coin flip or a
certainty by it alone.

## Mesh physics: what a net holds *(2026-09-05)*

`capture_physics.gd`, pure like `catch_chance`, over the three principal
body extents `body_dimensions.gd` carries per species — length, breadth and
depth in millimetres, each a published figure, with the length pinned equal
to the one `wingbeat_bounce.gd` already flies on so the two tables cannot
disagree about how long a monarch is. The extents are sorted and two
comparisons are made:

- **Slips through** if the subject's *middle* extent is under the mesh
  aperture. A body passes a square opening when its two smaller extents
  both do, and the larger of those two is the one that binds — a bee's 6 mm
  across against a 10 mm hole goes; a monarch's 25 mm body against the same
  hole does not.
- **Does not fit** if the subject's *largest* extent exceeds the mouth. It
  has to go through the mouth before it turns. (The bag's depth does not
  enter: a bag deeper than its mouth always has room for what fit the
  mouth — a stated simplification.)
- **Held** otherwise. `mesh_verdict` returns which, with a reason a player
  can act on: "slips through the 10 mm mesh" tells them to weave a finer
  bag; "too big for the 30 cm mouth" tells them to build a bigger one.

Against the standard net (10 mm mesh, 30 cm mouth):

| Subject | Extents, mm (largest · middle · smallest) | Verdict |
|---|---|---|
| fly | 7 · 3 · 3 | slips through |
| bee | 13 · 6 · 5 | slips through |
| monarch | 48 · 25 · 8 | held |
| swallowtail | 40 · 30 · 9 | held |
| blue_morpho | 65 · 35 · 10 | held |
| goldfish | 150 · 50 · 30 | held |
| sparrow, robin | 140 · 45 · 45 | held |
| kingfisher | 170 · 55 · 50 | held (not a net target today — see Open questions) |
| bluegill | 190 · 75 · 35 | held |
| trout | 350 · 80 · 45 | too big for the mouth |
| koi | 550 · 160 · 90 | too big for the mouth |

Monotone by construction, and pinned: a finer mesh never releases what a
coarser one held, a wider mouth never refuses what a narrower one took. A
3 mm mesh holds the bee; a 2 mm mesh holds the fly; a 40 cm mouth takes the
trout. A species with no measured extents refuses with its own reason
rather than guessing — a named gap, not a crash.

## Resolution order

Mirrors [spell_runtime.md](spell_runtime.md)'s own resolution-order section:

0. *(2026-09-05)* At load, `CaptureBook` parses the net's device text,
   compiles it (`DeviceCompiler` — the part graph and its facts) and
   **validates** its rules (`CaptureExecutor.validate`): every `confine(in:
   X)` must follow a `mesh_holds(mesh: X)` in its pipeline, and every part a
   `mesh_holds` / `confine` / `free` names must exist. A text that fails is
   refused loudly, not shipped as a net that ignores its own mesh.
1. `CaptureExecutor.capture_rule(ast)` finds the device's `on catch` rule.
2. Player builds the context at the throw site: `target` (species; boldness
   for a flyer with a personality, middling otherwise; `extents_mm` from
   `BodyDimensions`) merged with the net's part facts from
   `CaptureBook.facts_for`, so `bag.aperture_mm` is a dotted path away. The
   rule has no guard now; the pipeline's first atom is the gate.
3. `resolve_catch(rule, context, roll)` walks the pipeline: `mesh_holds`
   fails with a reason (slips through / too big / unmeasured), `catch_roll`
   fails silently (a miss), `confine` is collected as the effect to apply.
   The roll itself is supplied by the caller, not generated inside the
   executor — the same split `CreatureMarker._step_restraint`'s own
   `hash("%d_%d_struggle" % [wander_seed, count])` roll already keeps
   between "pure decision given a roll" and "where the roll comes from."
   Player salts its roll with an incrementing attempt counter, not the
   target's bare `wander_seed` alone — a bare-seed roll would make every
   retry against the same still-alive target land on the identical outcome
   forever, silently making one miss unwinnable.
4. On success, `confine` sets the tool's `captive_species`, and the subject
   leaves the world: a flyer via `queue_free`, a fish through the same
   `catch_nearest_fish` the rod uses, so the harvest is recorded against its
   pond's real population. On a mesh failure the reason is shown ("The bee
   slips through the net's mesh.") and nothing changes; on a missed roll,
   "Missed!" — the flyer's own existing `FlyerPersonality` flee/dance
   reaction keeps running exactly as it already does, untouched.
5. `on release`: no guard, no roll — `free(from: bag)` clears
   `captive_species`. Does **not** respawn a live creature back into the
   world (⬜, an honest, named gap — see Open questions).
6. `on transfer(CONTAINER)`: matched by `event_arg == CONTAINER`.
   `move_captive` reports the species that moved; Player consumes one
   `CONTAINER` from inventory and grants it loaded.

## Integration with input & items

- Catch/Release reuse the **existing dedicated capture-tool key**
  (`Player.perform_rope_verb` → `_throw_capture_tool` → `_throw_net`), not
  the hover-based `primary_action`/`secondary_action` verb scorer
  (`AnimalActions`) — because that scorer's target lookup
  (`Player._action_target`) only ever scans `CreatureMarker.GROUP_NAME` or an
  already-lassoed animal, and has never been able to see an ambient flyer at
  all. `_throw_capture_tool` already branches net-vs-rope-tool by tool id;
  it grows one more branch: a loaded net releases instead of throwing.
- *(2026-09-05)* **Fish are net targets.** `_throw_net` considers the
  nearest fish (`EarthChunkManager.nearest_fish_position`, the same lookup a
  hunting kingfisher uses) alongside the nearest flyer, and a netted fish
  leaves the water through `catch_nearest_fish`, the rod's own path, so the
  pond's aggregate population is depleted exactly as by angling. A fish has
  no personality, so it rolls at middling boldness. Only an ambient flyer can
  be bonded through `menagerie`; a netted fish always loads the net.
- "Put into bottle" has no hover target at all — it depends only on what's
  in the player's hand and their bag. Rather than bending `AnimalActions`
  (built entirely around a live animal's `animal_state()`), it's a small new
  sibling pure scorer, `capture_item_actions.gd`, consulted by
  `_action_slots_step()` only when the existing hover-verb path offers
  nothing for that slot — so Feed/Ride/Order/Release are provably unchanged.
- `Item.captive_species` is one instance field, added the same deliberate
  way `Item.wear` already is: state that starts blank and accumulates over
  one specific item's lifetime, a documented exception to "Item is a shared,
  immutable definition."

## Status / mechanisms

- ✅ ~~`capture_parser.gd`~~ (retired 2026-09-05 — the net is device text
  parsed by `device_parser.gd`) / `capture_atom_catalog.gd` /
  `capture_physics.gd` / `capture_executor.gd` / `capture_atom_effects.gd` /
  `capture_book.gd`
- ✅ *(2026-09-05)* **Mesh physics.** `body_dimensions.gd` (sourced extents
  for the flyer and fish rosters, length pinned to `wingbeat_bounce.gd`),
  `CapturePhysics.slips_through` / `fits_mouth` / `mesh_verdict` with
  reasons, monotone in aperture and mouth and pinned so; the net authored as
  a device with a real 10 mm-mesh, 30 cm-mouth bag; `mesh_holds`, `confine`
  and `free` atoms; `CaptureExecutor.validate`'s static confine-after-mesh
  rule; `DeviceCompiler` part facts in the catch context. In play: bees and
  flies slip through and say so, butterflies and small birds are held as
  before, goldfish and bluegill are netted from the shallows, trout and koi
  are too big for the mouth.
- ✅ `Item.captive_species`; `glass_bottle` catalog + icon entry. The
  `move_captive` effect reports the species that moved, not a generic
  curiosity item, so a container can be rendered as the specific creature
  it holds — `ItemStack.can_stack_with` was extended to also require
  matching `captive_species`, so a freshly-loaded container can never
  silently merge into a stack of empty ones. **That sentence was untrue in
  code until the 2026-09-05 merge to `main`**: `Inventory.add` merged by
  item id alone and never asked `can_stack_with`, so the moment `main`
  started every player with an empty bottle in the pack, bottling a catch
  merged the loaded bottle into the empty one and the creature vanished.
  `Inventory.add` now honours `can_stack_with`, and `has` / `count_of` /
  `remove` take an optional contents filter so "Put into bottle" only ever
  counts and spends an *empty* bottle — a loaded one is never consumed to
  make room for a second catch (pinned in `test_inventory.gd` and
  `test_player.gd`).
- ✅ `capture_item_actions.gd` (the "Put into bottle" scorer)
- ✅ Player wiring: probabilistic `_throw_net`/`_attempt_net_catch`,
  `_release_net`, `_bottle_captive`, `_perform_context_action` (the
  hover-verb-then-tool-self-action fallback). Menagerie bonding keeps its
  exact shape — the roll only gates whether the catch happens at all.
- ✅ `bottled_creature_wander.gd` (confined fly/rest state)
- ✅ `illustrated_glass_bottle_sprite.gd` (the fixed 3×2 sheet reader)
- ✅ `bottled_creature_view.gd` and its `DroppedItem` wiring — a dropped,
  loaded `glass_bottle` shows a live creature; a species
  `ProceduralButterflySprite` doesn't cover (birds) gets the bottle alone.
  `BottledCreatureView.TARGET_WORLD_WIDTH_PX` is a reasoned starting
  point, not yet visually confirmed against the real art in a live
  screenshot — the same honest gap `item_illustrations.md` names for the
  armor slots.
- ⬜ **The restrain-and-struggle tier (lasso/snare/trap/reinforced rope) is
  not expressed in this DSL.** It stays on `taming.gd`'s existing
  `break_free_chance`/`hold_chance` model, which is live, tested, and
  playable end to end — porting it into `capture` text (a `struggle_roll`
  atom delegating to those same functions) is real future work, not
  attempted here, mirroring exactly how `magic.md` itself leaves `enchant`/
  `instruct` unwired against its own executor in its first pass.

*(This section gets a pass once the corresponding code lands — see
`docs/progress.md` for the dated, narrative account of what actually
shipped.)*

## Rendering a bottled catch

A loaded `glass_bottle` is not a flat trophy — reported directly: the
bottle's own composite sheet has two rows, a background layer and a
foreground layer, and a bottled creature should render sandwiched between
them, alive: flying around, settling, flapping its wings.

`assets/sprites/items/glass_bottle.png` is a fixed 3×2 grid (measured:
1536×1024, six 512×512 cells) — three condition columns (pristine/worn/
broken, reusing [item_durability.md](item_durability.md)'s existing
`ItemWear.condition_for` vocabulary rather than inventing a second one) by
two rows: row 0 uncorked (the back layer — what sits behind whatever the
bottle holds), row 1 corked (the front layer — the near glass and its seal).
Both rows carry real, continuously-varying alpha through the glass body
(measured, not just at the silhouette edge) — this is a deliberately
painted "see-through" material, not a flat icon, which is exactly what
makes the sandwich read as looking *through* glass at something inside it
rather than a sticker glued on top of one. `composite_sheet_slicer.gd`'s
blob-detection is the wrong tool here — this grid is fixed and regular, not
irregularly laid out — so it's read the same "fixed-position, measured Y/X
bands" way `item_illustrations.md`'s wooden_club sheet already is.

**The creature layer reuses existing generators wholesale, not a new art
pipeline**: `ProceduralButterflySprite.generate_flap_textures`/
`generate_settled_textures` already produce exactly "flying" and "settled,
wings folded" frame sets, per species, and `WingbeatBounce.bounce_offset`
already derives the per-beat vertical bob from real wingbeat physics. None
of that is rebuilt. What a bottled creature needs that
`AmbientFlyerMarker`'s own animation state machine doesn't offer is far
simpler than what that machine models (no courtship, no nectaring, no
perched-bird logic — nothing in a sealed bottle forages or courts), so it
gets its own small state: `bottled_creature_wander.gd` alternates
deterministically between a short FLYING leg (drifting to a fresh point
inside the bottle's interior bounds) and a longer RESTING leg (settled at
that point), continuous across the transition, the same hash-seeded-not-RNG
discipline every other per-individual timing in this codebase already
holds to.

Only species `ProceduralButterflySprite` actually covers get a live
creature layer; a bottled bird (caught the same way, see taming.md's
"Netted" class covering both) falls back to the bottle alone rather than
inventing bird-in-a-bottle art nobody asked for — an honest, named
simplification, not an oversight.

**Where it renders**: the world-DROPPED item, not the inventory icon or
hand-held view. Every other surface in `item_illustrations.md`'s own states
table converges on one static texture per item on purpose (icon/ground/
in-hand all "reuse the icon") — animating an inventory slot would be a
first, unplanned departure from that. A dropped item is already a live
`Sprite2D`-based scene node (`dropped_item.gd`), the same kind of place this
codebase already puts a live diorama (`CharacterPreviewDiorama`), so a
loaded bottle set down in the world gets a small child view
(`bottled_creature_view.gd`: back sprite → creature sprite → front sprite)
instead of `DroppedItem`'s ordinary single flat texture.

## Open questions

- Should `release` actually respawn a live creature back into the world,
  rather than just emptying the tool? Symmetrical and arguably more honest
  physically, but not asked for and not built here.
- Does `struggle_roll` (the restrain tier) ever get ported into this same
  grammar, or do the two tiers stay permanently separate because they are
  genuinely different physical acts — an instant swing versus a multi-minute
  held contest? Left open rather than forced.
- A second instant-roll device for a different tier (a hand trap for a
  mouse-scale animal? a hook-and-line for a fish?) should already fit this
  same grammar and catalog unmodified, needing only a new `capture_book.gd`
  entry — untried in practice, since only one device exists so far. Since
  2026-09-05 the obvious next entries are *variants of the same net*: a
  1 mm-mesh insect net that holds bees, a 40 cm landing net that takes a
  trout — each one text away, but neither has a craft recipe yet, so a
  player cannot make one.
- *(2026-09-05)* **No mass or tear rule.** A koi is refused for being too
  long for the mouth, not for weighing more than a fibre bag on a wooden
  handle can carry. The honest version is the subject's mass against
  `PartGraph.part_load_capacity(bag)` — the same toughness-times-section the
  part graph already computes — but no fish species carries a mass yet, so
  it is designed and not built.
- *(2026-09-05)* The kingfisher is measured (170 mm, held by the standard
  net) but is a `PiscivoreBirdMarker`, not an ambient flyer, so `_throw_net`
  never sees it. Making it a target is a wiring question, not a physics one.
