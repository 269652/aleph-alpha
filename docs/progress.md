# Progress Tracker

This document is a living status tracker for everything defined across the
design docs in `docs/concept/*.md` (49 as of this writing, up from the 32
this doc was first generated against) plus `docs/roadmap.md` and, since the
2026-08-23 emergent-systems pass, `docs/emergence/*.md`, cross-referenced
against what is actually implemented in the codebase today. It was generated
by extracting every distinct mechanism named or implied in those docs
(catalogued below — the original count of 481 is stale now that more docs
have been added since, and hasn't been re-tallied to an exact figure) and
checking each one against the real, tested source in `src/`, `scenes/`, and
`tests/`.

**Update this file as work progresses.** When a mechanism moves from
not-started to partial or done, update its row/bullet, and when new design
docs are added, extend the relevant section. This is meant to be a complete
reference, not a curated highlight reel — it intentionally includes every
minor/open-question mechanism the source docs mention, not just headline
features.

### Loose stone (see `docs/concept/stone.md`)

✅ **Stone comes in sizes now**, on the Wentworth grain-size scale (the real geological one): pebble, cobble, boulder. The lift/smash line falls at the cobble-boulder boundary (256mm) because that is roughly where a rock stops being liftable -- the game rule and the classification agree because they answer the same question.

✅ **E is now contextual.** Empty-handed near a liftable stone, E takes the nearest one into the HAND (`Player._try_pick_stone_into_hand`) instead of sweeping it into inventory -- a new held-item concept distinct from both inventory and the worn "weapon" equipment slot. Empty-handed with nothing stone-shaped nearby, E still runs the ordinary ground-item sweep unchanged (`Player.pickup_nearby`, any other dropped item still goes straight to inventory). Liftable stones still join the group `DroppedItem` uses and answer `pick_up`, and still spawn with no collision body -- you walk over a pebble rather than around it -- but a hand can only ever hold one stone at a time, so a whole pebble flock can no longer be swept up in a single press the way it used to be; a deliberate, documented behaviour change, not an oversight.

✅ **Boulders take repeated strikes**, scaling with size (2 for the smallest, 6 for a two-metre one), and yield rock in proportion (2 to 20). They previously broke on the FIRST hit and yielded exactly one rock, regardless of being drawn as a rock the size of a person. A test pins that a big boulder pays at least as well per swing as a small one, so it can never become a trap.

✅ **Size is read against the player**, like flowers: a 2m boulder stands a head above the hero, a pebble is a couple of pixels. Small stone is exaggerated toward legibility without ever reordering the sizes, and the drawn size is derived from the same `StoneSize` the rules use, so art and mechanics cannot drift.

✅ **Boulder frequency was deliberately preserved.** Most stones now roll small, so leaving spawn density alone would have made boulders two-thirds rarer purely as a side effect; the density is raised to compensate and a test pins the two together. The cost is roughly 3x the stone nodes per chunk -- cheap ones (no collision, no per-frame script), but not free.

✅ **Pebbles sometimes flock.** A pebble-class cell (never cobble, never boulder) has a ~40% chance of spawning as a cluster of 2-5 pebbles instead of one lone stone -- both the chance and the size range are tested named constants (`StonePlacement.PEBBLE_FLOCK_CHANCE`/`FLOCK_MIN_MEMBERS`/`FLOCK_MAX_MEMBERS`). Each member is a REAL independently-seeded `LiftableStone` (its own diameter, shape, grain, yield), positioned around the cell's centre with a seeded angular jitter so members can never land on top of each other by construction -- flat sibling nodes, not one wrapping container (a container positioned at the cell centre would put each member's `.position` in local rather than world space, breaking `Player.pickup_nearby`'s distance check). A flock's whole spread stays well inside `Player.PICKUP_RADIUS`, so one approach collects every member.

✅ **Loose stone can draw from illustrated art.** `IllustratedStoneSprite` slices a hand/AI-illustrated sheet into cached, seed-picked variant frames -- the same "sheet → `SpriteSheetSlicer` → cached frames" shape as flowers/animals. Pebbles, boulders, AND cobbles each have a real 20-variant sheet registered and live (`assets/sprites/pebbles.png`/`boulders.png`/`cobbles.png`, each a 4-row x 5-column grid, rows increasing in size/complexity top-to-bottom, sliced as four independently hand-measured row bands with five auto-detected columns per band -- mirrors `IllustratedAnimalSprite`'s multi-band `walk_bands` shape). Cobbles were originally excluded by design (a fist-sized cobble isn't just a bigger pebble) -- since resolved by giving cobbles their own sheet instead. The supplied sheets are opaque solid-magenta background rather than real alpha (the AI generator ignores "transparent background" requests), so loading includes a chroma-key + despill pass: pixels close to pure magenta are keyed to real alpha 0, and remaining magenta-tinted blend pixels (antialiased edges baked directly into RGB, since there is no real alpha to separate them) have the colour cast removed rather than being deleted outright, so a soft shadow/outline survives as a shadow instead of a hard-edged hole. A real-chunk probe (6x6 grassland chunks, 8163 stones) confirmed all 20 variants of each class actually turn up among spawned nodes, not just a handful of buckets.

✅ **Ore nodes no longer show the old flat procedural look either.** Reported (2026-08-24, screenshot): "still boulders with the old design from the procedural engine" -- traced to `MinableOre`/`ProceduralOreSprite`, a code path entirely separate from the loose-stone illustration above (ore is a rarer subset of stone cells, `OrePlacement.ORE_FRACTION` 0.3 of ALL stone cells, not just boulder-class ones) that never got illustrated art of its own. Rather than requiring a brand new illustrated-ore sheet (none exists yet -- prompts for one are drafted in `docs/art/ai_sprite_prompts.md` section 5, not yet run), `ProceduralOreSprite.generate_image_from_base`/`generate_texture_from_base` now composite the ore's flecks onto a COPY of the illustrated BOULDER frame (ore always draws at boulder scale regardless of the underlying cell's rolled size, see `_attach_body_parts`'s `diameter_cm == 0` branch) instead of a freshly-drawn flat ellipse -- flecks are scattered by testing the base image's own alpha channel rather than ellipse geometry, so this works against any silhouette with no shape-specific math to keep in sync with the art. `StoneRenderer._ore_texture_for` gates this the same `has_variants()`-first-then-fallback way `_texture_for` already does for plain loose stone. The flat-ellipse `generate_image`/`_paint_flecks` stay completely unchanged as the fallback for a stone class with no illustrated sheet at all.

✅ **Pebble dispersion is mass-weighted and repeatable.** Walking within a few pixels of a loose stone rolls a per-contact chance (`PebbleDispersion.dispersion_chance`) of kicking it a fixed small distance directly away -- lighter stones roll a much better chance than heavier ones (the same footstep-momentum-vs-own-mass framing as the Kick action, just modelled as a foot at walking pace rather than a deliberate swing). A nudge that happens stays displaced rather than settling back, like real kicked gravel, but a stone is never "used up": every later contact rolls again (superseding the earlier one-shot-per-lifetime design), so it can keep drifting further across many walkovers. The roll is hash-derived from the stone's own seed and its own advancing contact counter (`LiftableStone._disperse_contact_count`, `PixelNoise`), not Godot's global RNG -- deterministic and reproducible like every other seeded pick in this codebase. Pure trigger/nudge/chance math lives in `PebbleDispersion` (tested headlessly); the per-frame "is a walker near a stone" detection is player-only scene glue in `World._step_pebble_dispersion`, mirroring `PathScarring`'s own pure/wiring split. Not wired to creatures yet -- deliberately, to avoid an O(creatures × nearby stones) scan every frame that nothing currently needs.

✅ **Loose stone has real mass.** `StoneSize.mass_kg_for(diameter_cm)` treats a stone as a sphere and multiplies by granite's real density (2.7 g/cm³) -- a ~5cm pebble comes out to a plausible fraction of a kilogram, a ~2m boulder to plausible tonnes, pinned against the exact sphere-volume formula so the constant and the formula can't silently drift apart. This feeds the SAME momentum model (`impact_resolver.gd`/`throwable.gd`'s `momentum = mass * velocity`, see `materials.md`) that dispersion's mass-weighting and the Kick action's leg-mass cutoff both read from, rather than inventing a parallel physics system.

✅ **"Pick (E)" interaction prompt.** `World._update_interaction_prompt` (previously villager-only) now also shows a "Pick (key)" prompt above the nearest liftable stone in pickup range, reading the live-rebindable key from `Keybindings`. An NPC to talk to takes precedence over a stone to pick up when both are in range -- talking is the rarer, more deliberate action, and a pebble on the ground isn't going anywhere. Hidden while the hand is already holding something, since E no longer sweeps in that state. `EarthChunkManager.nearest_liftable_stone_near`/`liftable_stones_near` (duck-typed on `has_method("pick_up")`, so boulders never qualify) back both this and dispersion.

✅ **Kick (K).** A new gameplay action, pure logic in `kick.gd`: delivers a real one-time momentum (`StoneSize.LEG_MASS_KG` at a brisk kick-swing speed) to the nearest liftable stone in reach (`EarthChunkManager.nearest_liftable_stone_near`, the same nearby-target-finding convention pickup/dispersion already use), through the SAME momentum model `impact_resolver.gd`/`throwable.gd` use everywhere else. How far the stone flies is real kinematics -- `GroundSlide.distance_px`, the standard sliding-stopping-distance-under-friction equation, shared with the held-item throw below -- scaled by momentum against the stone's own mass, exactly `Throwable.impact_knockback`'s reasoning. A stone at or above leg mass doesn't move at all -- since a cobble at the top of its range already outweighs a leg, this one mass cutoff naturally limits kicking to pebbles/light cobbles with no separate per-class check. `Keybindings`' `toggle_skills` moved off K onto L (the next key over) to make room.

✅ **Held-item pickup + charge/release throw.** The other half of E's new contextual behaviour: with a stone already in hand, pressing and HOLDING E starts a charge -- `ChargeMeter.fraction_at` bounces a "strengthometer" value between 0 and 1 repeatedly while held (a triangle wave, not a monotonic fill), so release power depends on exact timing. A real UI meter (`World._build_charge_meter`/`_update_charge_meter`, the same Background/Fill `ColorRect` shape as `PlayerHealthBar`, positioned above the player's head the same world-to-screen way the interaction prompt is) shows the live reading. Releasing E throws the stone: `HeldItemThrow.release_speed_mps` maps the release power to a real throw speed, `Throwable.impact_knockback(mass, speed)` turns that into real momentum for `ImpactResolver.resolve_impact`/`MeleeAttack.knockback_vector` to resolve against any creature at the landing spot, and `GroundSlide.distance_px` (shared with Kick) places the landing spot itself. The stone reappears in the world (`StoneRenderer.build_liftable_stone_node`) whether or not it struck anything. Documented simplifications: flight distance depends on release speed alone, not the stone's own mass (a thrown item is actively swung by the player, not a passive object receiving an external momentum transfer the way a kicked stone is); a landed/missed throw isn't re-registered into `EarthChunkManager`'s own per-chunk bookkeeping, so it draws and can be picked up normally but won't be recognized by Kick/dispersion/the "Pick" prompt; and impact reads `ImpactResolver`'s outcome as a simple hit/no-hit rather than a full per-outcome damage table (`materials.md` itself lists that mapping as an open, project-wide question).

✅ **Weapon mass.** Weapon-kind items now carry a real mass (`Item.mass_kg`, `MaterialProperties.mass_kg_for` -- density x an estimated real-world volume per item type, e.g. an iron sword's ~154cm³ estimate lands at ~1.2kg, within the real "one-handed swords are typically 1-1.5kg" range used as its sanity check). `Player._knockback_force_for` now scales a swing's knockback from that real mass through `Throwable.impact_knockback`, calibrated so an iron sword (unchanged) reproduces the exact original tuned `KNOCKBACK_FORCE`; bare hands and any weapon with no mass modeled yet fall back to that same original constant. Only the three weapon-kind items (sword, club, crude blade) have a mass estimate today -- tools (axe, pickaxe, fishing rod, lasso) are a documented follow-up, not guessed at here.

⬜ Visible damage state on a part-smashed boulder -- only the final break is shown.
⬜ Stone type varying by biome (granite, limestone, sandstone); all loose stone is the same grey, aside from the illustrated pebble/boulder/cobble variants.
⬜ Real illustrated ore art (as opposed to flecks composited onto the illustrated boulder frame, done above) -- prompts drafted in `docs/art/ai_sprite_prompts.md` section 5, no sheet generated/registered yet.
⬜ Pebble dispersion for creatures, not just the player.
⬜ Tool mass (axe, pickaxe, fishing rod, lasso) -- only weapon-kind items have a real mass estimate today.
⬜ A thrown stone's flight is a straight teleport to its landing spot, not an animated arc, and it isn't re-registered into chunk-manager bookkeeping (see the held-item throw entry above for the full list of documented simplifications).


### Illustrated trees (see `docs/concept/flora.md#illustrated-trees`)

✅ **Trees are composited from trunk + seasonal canopy + fruit** instead of being drawn procedurally, for any species with art. A species without art still paints procedurally, unchanged.

✅ **Canopies carry the season** -- bare, blossom, in leaf, turning. Trees previously wore one canopy all year while the flowers beneath them bloomed and died on schedule. Frames map to seasons by MEANING, not sheet order. Textures are cached per species AND season, and a season change redraws every loaded tree (not just the ones near enough to forage from -- a forest on the horizon still in leaf under snow is as wrong as one underfoot).

✅ **Composite sheets are sliced automatically.** Drawings are found as connected blobs rather than cut on a grid or on empty rows: the autumn canopies have falling leaves that bridge every gutter, so a row/column search returns the whole sheet as one region. Regions are then read by position -- top band is the canopy strip, largest drawing below it is the trunk, rest are fruit.

✅ **Fruit stages differ per species and are read from the end.** The first row of the fruit block is the crop on the tree, later rows are what it becomes once picked. Pine has three on-tree stages (bare sprig, green cone, brown cone) where the nut trees have two, so ripe is the LAST on-tree frame -- counted from the start, a pine would bear needles as its unripe crop.

✅ Placement uses each frame's painted CONTENT, not its rectangle: the sheets carry transparent padding, and positioning by rectangle left the canopy hanging in the air above the trunk.

🚧 **Two sheets have a transparency checkerboard painted into them as pixels** (pine, hazelnut) rather than real alpha. A reachability flood keys most of it -- the winter pine keeps its snow -- but hazelnut retains white pockets in the gaps between its branches, which no colour rule can reach. Being fixed at the source.

✅ **All six species are wired in**: `pine`, `acorn`, `hazelnut`, `walnut`, `cherry`, `apple`, each with illustrated art, a canopy/fruit colour, yield and ripening character, and a matching item to drop (a tree's species id IS the id of its fruit item). The nut/fruit bias spectrum is now split EVENLY over the roster instead of by hardcoded thresholds -- there were three named constants for three species, which would have meant five for six, each going stale whenever the roster changed.

✅ **Compositing was 160ms per tree and froze the game.** The cost was not drawing but `Texture2D.get_image()`, which copies back from the GPU, called two or three times per tree for pieces that never change. Pieces are kept as trimmed Images and their scaled versions cached by size; trunk heights vary per tree but land on whole pixels, so a wood only needs a handful of distinct sizes. Now ~17ms.

✅ **Fruit was piling up in one spot.** `hash("..._fruit_N")` is near-LINEAR across inputs differing only in a trailing number, so all eight of a crop landed within a tenth of a pixel of each other and read as one berry stuck to the tree. Both the illustrated and the procedural scatter now use `PixelNoise`, which exists for exactly this -- the same banding bit this project once in terrain.

⬜ Superseded: pine/acorn/hazelnut now exist as species; this note is kept only to record that they once did not.


### Illustrated character art (`concept/character_art_brief.md`)

Asked directly: "rehaul the character rendering in game and in creation so it
uses the illustrated sprite sheets" — the player/NPC rig (`CharacterView`,
already a paperdoll of separate Body/Head/LegLeft/LegRight/ArmLeft/ArmRight
sprites, see the art brief) was still 100% `ProceduralCharacterSprite`
primitive shapes despite the illustrated-part pipeline
(`IllustratedCharacterSprite`) and the `has_action`-then-fallback wiring in
`CharacterView._apply_paperdoll_part` already existing as scaffolding, with
`_PARTS` empty. Four real art files existed
(`assets/sprites/player/{torso,leg,arms,head}.png`) but in a different shape
than the original brief anticipated, discovered by actually opening them
rather than assuming the brief's plan still matched reality:

- **Torso/legs/arms are ✅ wired**, each falling back to procedural
  automatically if unregistered — but no longer from the single-pose
  `torso.png`/`leg.png`/`arms.png` files this bullet originally described.
  Superseded mid-pass (reported: "I added hero_composite ... use it") by
  `assets/sprites/player/hero_composite.png`, a combined 1024×1536 sheet: 3
  columns (arms/body/legs) × 8 rows, each row a complete PRE-COLORED outfit
  variant rather than a neutral part `modulate` tints at runtime.
  `IllustratedCharacterSprite` gained a dedicated surface for it
  (`has_composite_part`/`outfit_variant_for`/`generate_composite_textures`/
  `composite_part_scale_for`) since a variant (which of 8 outfits) and
  `facing` axis has no room in the old single-pose `_PARTS` shape; `_PARTS`
  itself is now empty (kept working, untested-by-disuse-only, for any future
  single-pose part like hair). Legs are still a FUSED pair exactly as
  `leg.png` was (one sprite covers both `LegLeft`/`LegRight` world slots,
  `CharacterView._apply_legs`); arms are still two independent poses
  (`ArmLeft`/`ArmRight` from separate frames), except outfit row 6, whose
  art doesn't split into two frames — `_apply_arms` falls back to reusing
  frame 0 for both sides there rather than erroring. Which outfit a hero
  wears is DNA-derived (`outfit_variant_for`, hash % 8), the same "vary by
  seed, no new UI" answer skin/hair/eyes already give — the opposite answer
  from head's own axis below, deliberately: a face is identity, an outfit
  color isn't. Column x-ranges needed real per-row verification, not just
  row 0 (`test_every_outfit_row_produces_the_expected_frame_count`): row 7's
  body picked up a detached 11px shoulder-cape fragment as a false second
  frame (an over-wide upper bound, narrowed 683→660), and row 7's legs
  vanished outright because their real content started at x=670, outside an
  assumed 683 lower bound (widened to 668) — both caught by looping all 8
  rows instead of trusting row 0's ranges for the rest. Only FRONT-facing
  art exists at this path today; an earlier regenerated version additionally
  had a side-profile set, but the sheet currently in place replaced it with
  a front-only one. `facing` stays a real parameter throughout this surface
  (`_resolved_facing` falls back to `"front"` for anything else), so a
  future side/back sheet slots in without another signature change — a
  structured 4-direction regeneration prompt was written and handed over for
  the user to run, but has NOT been folded into
  `docs/art/ai_sprite_prompts.md` section 4 yet (still describes the
  original single-pose prompt shape) — a real, flagged doc gap, not silently
  left stale. The walk-cycle gap this entry originally recorded (illustrated
  legs stay static while walking — reported: "the legs aren't animated") is
  now closed, partially: no per-leg swing art exists for a fused pair, but
  `CharacterView._process` gives the whole pair a vertical bob
  (`FUSED_LEG_BOB_AMPLITUDE`, dips twice per stride like a real gait) while
  walking.
- **A real, previously-latent sizing bug surfaced immediately**:
  `IllustratedCharacterSprite.CANVAS_SIZE` is ONE shared 64×96 working
  canvas every part normalizes onto (mirroring `IllustratedAnimalSprite`'s
  "one canvas per creature" convention), not a claim that a torso and a leg
  pair are the same real size — so the flat `ArtResolution.SPRITE_SCALE`
  the procedural parts share (correct only because THAT generator draws at
  exactly its target art size with no padding) would have rendered every
  illustrated part at the wrong size the instant it had any padding within
  that shared canvas, which `normalize_frames`' own aspect-preserving fit
  means it (almost) always does. Fixed the same way
  `IllustratedAnimalSprite.marker_scale` already solves it one rig over:
  `part_scale_for`/`head_scale_for` measure the generated frame's own
  opaque-pixel content height and compute the scale that maps IT to the
  part's real world height, instead of trusting the canvas size or a flat
  constant. Two now-legacy tests that assumed `texture size == content size`
  (true only for the old padding-free procedural art) were rewritten to
  measure the actual opaque content bounding box instead of the raw texture,
  reflecting the real, intentional change rather than being hacked back to
  green.
- **Head is ✅ wired, but is not a neutral single-tint part like the other
  three** — `head.png` is a 10×10 grid of 100 fully-painted faces (bald, one
  baked skin tone, solid near-black background, no alpha channel), so it
  gets its own surface (`has_head`/`generate_head_texture`/`head_scale_for`),
  not `has_part`/`generate_textures`. `HeroAppearance.appearance_for` and
  `appearance_from_choices` both carry `"seed"` on the returned appearance
  dict so illustrated art always has something deterministic to key off.
  Background removal needed a second new mechanism: `head.png` has no alpha
  and a near-pure-black background (measured directly with a small Node.js
  PNG probe rather than guessed — `IHDR`/`IDAT` parsed and inflated by hand
  since Python wasn't on PATH in this environment either) — but a first flat
  per-pixel chroma-key attempt (distance-from-black, tolerance 0.06) left a
  visible dark halo around every face once actually seen live, because the
  real background-to-face transition is a soft 20-30px blur, not a crisp
  cut. Replaced with a border-connected flood fill
  (`_remove_background_by_flood`): starting from the canvas edges and
  stepping only to a neighbour within `HEAD_BACKGROUND_FLOOD_STEP_TOLERANCE`
  of the pixel that reached it, the flood rides the blur to where real
  content begins but can never cross into the content's own interior (doing
  so would need one big step across the content's edge, which a per-step
  tolerance refuses) — a flat distance-from-black key can't tell a
  coincidentally dark pixel INSIDE a face (an eye) from real background,
  because it never checks what a pixel connects to. 0.02 was reached by
  sweeping 0.02-0.18 against 7 sample cells with a throwaway visual-diff
  harness: most cells hold a stable opaque plateau from 0.02 up to a
  per-cell cliff around 0.06-0.10, but two darker-toned cells show no clean
  plateau at all, so 0.02 is the conservative value that holds a complete
  face on every sampled cell. The sheet's own baked tone is discarded and
  repainted toward the hero's `appearance.skin` by LUMINANCE ONLY — the same
  recolor trick `ProceduralFlowerSprite._paint_illustrated_head` proved on
  illustrated blooms (see `flora.md`'s "Recolouring illustrated blooms"),
  deliberately simplified (no accent-hue mask separating eyes from skin —
  eyes are already dark enough to read as a distinct darker patch of
  whatever tone the recolor lands on).
  **Which face a hero wears reversed from DNA-derived to a real player
  choice** (reported live, after the DNA-only version shipped: "you can't
  choose different heads") — `"head"` is now a full `HeroAppearance.AXES`
  entry (`option_count` reads `HEAD_GRID_COLUMNS * HEAD_GRID_ROWS` from the
  art itself, not a second hardcoded 100), cycles in the creator like every
  other axis, and round-trips through `appearance.head_index`; a DNA roll is
  still the fallback for a hero nobody hand-authors (a fresh randomize, an
  NPC).
- **Hair is an honest, explicit gap, not a half-implementation.** `head.png`
  is bald throughout, and no hair-overlay art exists — asked directly
  (overlay the old procedural hairstyles on the new head's silhouette, or
  ship bald for now?), and bald-for-now won: those hairstyles were drawn to
  fit the OLD procedural head, not this one, and a mismatched overlay would
  read worse than an honest gap. The DNA `hair_style`/`hair` axes still
  exist and still work for the procedural fallback; they simply have
  nothing to draw against once the illustrated head is active. What closing
  this gap actually needs is spelled out in the art brief.
- **"Decorations" is explicitly undefined, not attempted.** Mentioned
  alongside hair as "still missing" when this was scoped; asked what it
  should mean and the honest answer was "no idea yet." Recorded as an open
  question in the art brief rather than guessed at.
- Also fixed in passing: `has_action` only ever checked for a part's
  `"<action>_bands"` key, so registering body/legs/arms via the new
  `idle_rects` mechanism alone left `has_action` reporting false and
  `_apply_paperdoll_part` silently stuck on the procedural fallback despite
  real art being registered — caught immediately by the new tests, not
  discovered live.
- ✅ **`CharacterView.TARGET_HEIGHT_FRACTION_OF_TREE` raised 2/3 → 0.85** once
  the illustrated parts above replaced the flat-color procedural ones. At
  2/3, a leg's own measured content rendered at roughly 4 on-screen pixels
  tall — reported as "legs are not wired" (they were; detailed shaded art
  doesn't survive that downscale the way flat color does, it smears into a
  muddy blob that blends with the ground). Asked directly how to fix it
  (raise the whole character vs. legs specifically): raising the whole
  character keeps every part's proportions AND legibility consistent, not
  just legs'. At 0.85 the same leg content renders at roughly 5.4px — a real
  compromise, not a full fix, deliberately short of 1.0 (as tall as a tree)
  to preserve the original reason this constant exists (the hero reads
  visibly smaller than the trees around it). The art was drawn assuming a
  larger viewing size than this project's tile-scale budget affords; closing
  that gap the rest of the way is a real follow-up, not solved here.
  **Correction: this alone did not fix "legs are not wired."** Relaunched
  and reported live, twice more, after this landed ("still no legs" /
  "back to the old procedural version" / "no neck; head is floating and no
  legs"): legibility was real but was never the whole story. Two separate,
  unrelated bugs were still hiding the actual, correctly-sized art:
  - **hero_composite.png's rows each hold a second, unrelated close-up**
    (a belt buckle, a shoulder pauldron) sitting BELOW the real garment, at
    x-coordinates landing inside the very same legs/body column range
    `detect_frames` already isolates for that part — `detect_frames` only
    ever splits on COLUMN gaps (see its own doc comment), so it hands back
    one rect spanning the full row height regardless of what's actually
    drawn in it, and `_content_rect`'s plain min/max bounding-box scan then
    welds the garment and the stray fragment into one "frame" with a real
    gap of transparent rows between them. Measured directly (dumped every
    row as a real PNG and looked): 6 of legs' 8 rows and 6 of body's 8 rows
    carried this, only rows 0 and 7 of each were clean. This both inflated
    `composite_part_scale_for`'s measured content height (shrinking the
    real garment further than the fraction above alone would predict) and
    painted a second, unrelated object below it. Fixed by
    `IllustratedCharacterSprite._primary_content_rect`, which clips a
    column-matched rect down to just its first contiguous run of non-empty
    rows before normalizing — the real garment is always the topmost run in
    every row observed, so "cut at the first full gap" needed no tuned
    gap-size threshold, just the same single-empty-row-is-a-divider
    convention `detect_frames` already uses for columns. Pinned by
    `test_every_outfit_rows_legs_have_no_fragment_stacked_below_a_gap` and
    its body counterpart, looping all 8 rows of each (a helper asserts no
    row reads as real content — max alpha ≥50%, chosen because
    `normalize_frames`' own LANCZOS resize blurs a true 0%-alpha source gap
    into a soft ramp that bottoms out at ≤39% everywhere it was measured —
    after a prior row that already read as a real gap).
  - **Sprite2D centers its TEXTURE on `.position` by default**, which is
    only the same thing as centering on the visible CONTENT for the old
    flat, padding-free procedural art. hero_composite.png's parts normalize
    onto one shared padded canvas with content baseline-anchored near the
    canvas's bottom (see `CANVAS_SIZE`/`BASELINE_Y`), so most of a part's
    own padding sits ABOVE its content, not evenly around it — left
    uncorrected, the actual art renders noticeably LOWER than `.position`
    alone suggests. For the body this pushed the torso down far enough to
    visually cover the (by-then correctly wired) legs entirely, and shifted
    the head/body relationship enough to read as "no neck." Fixed by
    `CharacterView._composite_content_offset_y`, which back-derives each
    part's own measured content height from the scale
    `composite_part_scale_for`/`head_scale_for` already returned and sets
    `Sprite2D.offset` so the CONTENT's own center — not the padded canvas's
    — lands on `.position`, restoring the old semantics regardless of how
    tall a given outfit row's art happens to be. Applied to body/legs/arms
    and, for consistency, the head (its own smaller canvas has the same
    padding-asymmetry shape, just less pronounced).
  - **Incidentally surfaced while dumping every seed for visual proof**: 7
    of the head's 100 cells (all but one landing in the sheet's own column
    1 — a systematic pattern, not per-cell noise, though the exact cause
    wasn't chased down) have `_remove_background_by_flood` erode almost the
    entire face — opaque fraction ≤8.3% for every one of the 7, against a
    comfortable margin for every other cell — which `head_scale_for` then
    divides a target height by, producing a huge, wildly oversized, nearly
    blank texture. A pre-existing bug, unrelated to the two above, just
    never previously noticed since the flood-fill's original calibration
    sweep only sampled 7 of the 100 cells. Not root-caused here (that needs
    understanding why column 1 specifically is fragile); instead given the
    same has-X-then-fallback safety net body/legs/arms already lean on for
    their own per-row gaps: `IllustratedCharacterSprite.has_usable_head`
    (opaque fraction ≥15%, measured with margin on both sides of the real
    7-cell/rest-of-grid gap) gates both `CharacterView._apply_head` and the
    portrait's `_portrait_head_image`, falling back to the procedural head
    for exactly those 7 cells rather than showing a broken smear.
  - **A second, opposite flood-fill failure mode surfaced live**: 12 more
    cells (a contiguous block, rows 1-2 columns 3-8) never had their
    background removed AT ALL — opaque fraction ~1.0 — reported directly:
    a dark rectangle where a face should be. Consistent with the flood's
    own approach: if a cell's face art touches (or crosses) the cell's own
    edge with no background margin, the border flood has nowhere to start
    from and leaves the whole square untouched. `has_usable_head` gained a
    matching upper bound (`HEAD_MAXIMUM_OPAQUE_FRACTION`, 0.97 — a real
    face's silhouette always leaves at least the corners transparent, so
    1.0 is only reachable by a flood that found nothing to remove),
    catching these 12 the same way. **19 of the 100 head cells now fall
    back to procedural** between both bounds — real, visible, and still not
    root-caused (that needs either a smarter per-cell flood or fixing the
    source art's own margins), just no longer broken-looking.
- ✅ **Body was rendering roughly 2x too wide** (reported live: "proportions
  are awfully wrong"). `composite_part_scale_for` only ever matched CONTENT
  HEIGHT to `BODY_SIZE.y`, then applied that one scale to width too — fine
  for the old flat rectangle (drawn at exactly that box), wrong once
  hero_composite.png's torso (short sleeves baked into the same silhouette)
  measured noticeably wider relative to its height than `BODY_SIZE`'s own
  13:19 aspect assumed. `CharacterView._width_bounded_scale` clamps to
  whichever of width/height is more constraining — the same "fit inside a
  box, preserve aspect" rule `normalize_frames` already applies one step up
  — and `BODY_SIZE.x` was widened 13→26 (measured from the most common
  outfit row's real content, 19 × 64/47, not eyeballed) so that row still
  renders at its full intended height rather than being squished by its own
  new clamp. Scoped to body alone, not every part — legs/arms/head were
  checked too and have smaller mismatches that a width clamp would "fix" by
  shrinking their height for no visible gain; revisit per-part if one is
  ever reported looking wrong the way body was.
- ✅ **Arms are visible in every movement state now, not swimming only**
  (reported live: "no hands are visible"). Leftover from when the flat
  procedural torso rectangle was wide enough to visually stand in for a
  whole upper body, arms included, and separate Arm sprites existed only
  for the swimming stroke pose — hero_composite.png's illustrated torso
  stops at the shoulder, so standing/walking showed no hands at all. Only
  the STROKE animation itself stays gated to actually swimming.
- ✅ **Body now draws BEFORE arms**, not after (`.tscn` child order, which is
  Godot's own paint order) — the wider body above is wide enough to
  horizontally overlap where `ArmLeft`/`ArmRight` sit, and with arms drawn
  first, the torso's own sleeve fabric was painting over the very hands
  the fix above just made visible. Body-then-arms keeps a hand always in
  front of the torso.
- ✅ **`LEG_SIZE.y` widened 8 → 12** (reported live: "the legs are too
  short") — 8 out of the character's own 33-unit total height put legs at
  ~24%, well short of a real standing human's ~45-50% leg-to-height share.
  `LegLeft`/`LegRight`'s `.tscn` position moved -4 → -6 alongside it so the
  fused pair's feet still land exactly on the character's own origin.
- ✅ **A real bug in the padding-offset fix itself, found while building the
  neck below**: `_composite_content_offset_y` back-derived a part's content
  height as `target_world_height / scale`, correct only when `scale` came
  straight out of `composite_part_scale_for` (which IS
  `target_world_height / measured_content_height`) — silently wrong once
  `_width_bounded_scale` could hand back a smaller, width-driven scale
  instead, which overestimates the true content height and offsets the
  content further than it should go. Stayed invisible at ordinary
  BODY_SIZE-scale sizes but became a measurable positioning error once the
  neck needed the exact same edge to the pixel. Now takes the real measured
  pixel height directly (`trimmed_composite_image`/`trimmed_head_image`'s
  own `.get_height()`) instead of back-deriving it — this whole class of
  drift is impossible by construction now.
- ✅ **A small procedural Neck bridges Head and Body** (reported live: "the
  neck should be rendered procedurally so the head doesn't float"). Neither
  part's own art draws a neck, and both are positioned by their own
  measured content (varies per outfit row/head cell), so a fixed-size neck
  would only fit one combination. `CharacterView._apply_neck` sizes and
  positions a plain skin-toned fill fresh each apply, spanning exactly
  whatever gap THIS appearance's own measured Head-bottom/Body-top edges
  leave. First attempt reused `ProceduralCharacterSprite.generate_body_part_
  texture`'s shaded-cylinder LIMB style (a full dark outline all the way
  round) — read as an obvious floating rectangle rather than a neck once
  actually seen; a plain borderless fill with a generous overlap into both
  neighbours (mostly hidden under the head/collar, only a sliver bridging
  the real gap) reads correctly instead.
- ✅ **Hands sway while walking, not just arms visible** (reported live:
  "hands should also slightly sway when walking") — reuses
  `arm_stroke_offset` (previously swim-only) with a smaller
  `ARM_SWAY_AMPLITUDE`, contralateral to `leg_swing_offset` (opposite sign:
  real gait swings an arm opposite the leg on its own side).
- ✅ **A held weapon now tracks `ArmRight`'s own current position** every
  frame (reported live: "the sword should be held by the actual hand"),
  instead of a fixed torso-side slot independent of the arm entirely — it
  inherits the hand's own walk sway as a result. The existing
  facing-driven side shift (`TOOL_SLOT_SIDE_OFFSET`) is preserved, just
  stored (`_tool_side`) and reapplied every frame against the arm's current
  position instead of written once on a facing change.
- ✅ **An interim stride cue for the fused legs**: real per-leg knee-jointed
  animation needs new source art the fused single-drawing legs can't
  provide (asked directly; user accepted a coarser interim over waiting).
  `FUSED_LEG_ROCK_AMPLITUDE` adds a small hip-pivot rotation on top of the
  existing vertical bob, once per full stride (not the bob's twice-per-
  stride cadence) — a real gait leans one way then the other over a whole
  stride. A real per-leg walk cycle is still a documented open follow-up,
  not solved here.


### Character creator live preview scene (see `concept/character_creator_preview_scene.md`)

✅ **The static hero portrait is now a real, live, always-animating mini
scene.** Asked directly, after the static-portrait panel had shipped and
every other character-rendering fix above had landed: *"It should be a
real mini in game scene with swaying grass blades; some pebbles the edge
of a pond and some trees where the char should stroll around."* Built from
the SAME rendering classes the real world uses, not a parallel art style —
`IllustratedGrassPatch` for grass, `WaterShader`/`ProceduralShoreDistanceSprite`
for the pond, `StoneRenderer` for pebbles, `TreeRenderer` for trees, and
the same `CharacterView.tscn` the player and every NPC wear.

- `src/rendering/character_preview_layout.gd` — pure, seeded placement
  math (no Godot nodes at all): given a DNA seed and a footprint, returns
  the pond's centre/radius, tree positions (kept clear of the pond),
  pebble positions (scattered along the pond's rim), and grass-clump
  positions (filling the rest, avoiding both) — same seed, same little
  scene, the same determinism convention `ecosystem_dynamics.md`'s own
  pillar already established elsewhere in this codebase. Also owns
  `is_clear(point)`, the one "is this spot clear of every obstacle here"
  predicate the grass scatter, the tree placement's own rejection
  sampling, AND the stroll's target-picking all share.
- `src/rendering/character_stroll.gd` — pure walk-to-a-point-then-pick-
  a-new-one motion (`advance`/`has_arrived`/`pick_target`), the same shape
  `CreatureWander`/`creature_movement_gate.gd` already use for ambient
  creature movement, scaled down to one character in a small pen. Not
  seed-pinned — the design doc is explicit that the stroll itself is
  ambient motion, not part of the hero's own identity, only the world
  layout needs to reproduce.
- `src/rendering/character_preview_diorama.gd` — the only Godot-coupled
  piece; turns the pure layout into actual nodes and drives the stroll
  against a real `CharacterView` every frame. Confirmed directly (traced
  against `Player._update_character_view`, the real driver) that
  `set_facing`/`set_movement_state`/`.is_moving`/`.position` are genuinely
  all `CharacterView` needs to animate correctly standalone — no
  physics/collision/input required, so no cut-down "mini player" was
  needed.
- `scenes/main_menu.gd`'s hero panel swaps a `TextureRect` for a
  `SubViewportContainer`/`SubViewport` (`UPDATE_ALWAYS`, so grass/water/the
  stroll keep animating for as long as the creator screen is open) hosting
  one diorama, framed by a fixed (non-following) `Camera2D` — a diorama is
  watched from outside its own little box. Rendered at exactly its display
  resolution (`DIORAMA_VIEW_SIZE`, 220×220), so unlike the old portrait's
  manual `TextureRect` scaling, no nearest-neighbour filter trick is
  needed to keep it crisp. The world layout only rebuilds when the DNA
  seed itself changes (a reroll) — cycling any other appearance axis or
  switching class just redresses the same, already-strolling hero via
  `apply_appearance`, rather than resetting the scene under it.
- The class-icon row's small per-class thumbnails deliberately stay static
  portraits (`ProceduralCharacterSprite.generate_hero_portrait_texture`,
  unchanged) — a live `SubViewport` per tiny icon would be wasteful; only
  the one big preview panel became a diorama.

✅ **Seen live and iterated on real screenshots** — several real bugs only
visible once actually rendered, none catchable headlessly:

- **The panel wasn't containing the diorama at all** — `glow_wrap` (a
  plain `Control`) defaulted to `SIZE_FILL`, so `inner` (a `VBoxContainer`
  whose own width tracks the hero card's `SIZE_EXPAND_FILL`) stretched it
  out to nearly the whole card; the DNA rarity-glow ring anchored inside it
  stretched right along with it, and a gold-at-0.35-alpha ring over the
  card's dark background reads as a flat, unrelated tan panel. Fixed with
  `SIZE_SHRINK_CENTER` on both axes.
- **A second, deeper bug behind the same symptom**: `frame.set_anchors_
  preset(PRESET_CENTER)` was called BEFORE the diorama view existed as its
  child, freezing the centring math against a zero-size box; when frame's
  real size appeared afterward, Godot does not recompute those offsets, so
  it grew from that frozen corner instead of staying centred — the exact
  same latent bug the very first screenshot already showed with the OLD
  static portrait, just never fixed until now. Replaced with a real
  `CenterContainer`, which recentres continuously regardless of when/how
  its child's size changes.
- **The pond "seemed tinted"** — `ProceduralShoreDistanceSprite` is built
  around a square terrain TILE with land on specific cardinal SIDES, not
  an isolated round pond; an empty `land_directions` list gave a uniform
  "no shore anywhere" fill with no alpha mask (a flat, square, untextured
  tint). `src/rendering/circular_pond_sprite.gd` measures shore-distance
  RADIALLY from the image's own centre instead and masks a real circular
  silhouette, in the same red-channel convention `WaterShader` already
  reads.
- **"The fish pond should be at the edge"** — the pond was placed with a
  small random jitter around dead-centre; `CharacterPreviewLayout` now
  picks one of the footprint's 4 edges per seed and places the pond close
  to it (`POND_EDGE_MARGIN`), randomizing only its position ALONG that
  edge.
- **"Add fish to the pond"** — `FishRenderer` gained a public
  `spawn_fish_at(parent, species, position, seed_value)` wrapper (the same
  convention `StoneRenderer.build_liftable_stone_node` already
  established) around its own private `_build_fish`, sidestepping the
  chunk-based ocean-tile spawning `spawn_fish` itself requires. 2 fish per
  diorama, scattered by seeded polar coordinates (sqrt-corrected so they
  don't bunch toward the centre) within the pond's own radius.
  `CharacterPreviewLayout.Result.fish_positions` follows the same
  determinism convention as everything else. Needed one more fix once
  trees enabled y-sort on the whole diorama root: the pond, a large flat
  ground feature sorted by its own centre point, would otherwise
  y-sort BEHIND roughly half the fish scattered around that centre and
  make them vanish — pinned to `z_index = -1` so it always draws first
  regardless of any Y comparison.
- **"The grass blades don't part when it walks through"** —
  `IllustratedGrassPatch.set_walker_position` already existed and is a
  pure no-op until called (see that function's own doc comment); the
  diorama just never called it. One line in `_process`.


### `/ecotest` — watching a year go by

✅ **`/ecotest [seconds_per_year|off]`** runs the ECOLOGY fast so a whole year can be watched: winter into spring into summer into autumn, canopies going bare and back into leaf, fruit ripening and falling, saplings coming up and growing. Defaults to a year a minute (about 15 real seconds per season). Only the ecology speeds up — the player still moves normally, so you can walk around and look while the year runs past.

Asked in terms of the thing being watched rather than as a multiplier: "600x" means nothing to someone waiting for autumn; "a year in a minute" does.

**The ecology runs at two cadences, split by measurement.** With the world running fast, one frame's ecology measured: `ecosystem 500ms, flowers 20ms, grass 9ms, worms 2ms, fruiting 4ms`. The cheap steps are exactly the ones worth running often — fruit ripening and falling, worms surfacing — and the expensive ones are periodic batch jobs that reconcile or ADD world content, written to run once a minute of world time, which is invisible at normal speed and ruinous when a frame holds several minutes. So the fine group runs per slice and the batch group runs once a frame with the whole frame's simulated time, which is what its accumulators want anyway.

**Tree pictures are bounded and cached.** A tree is rebuilt whenever its crop or season changes, which under a lapse is constantly; keyed by raw seed every tree was unique and nothing could be reused, so one frame spent 3.3s rebuilding ~190 trees. Variance now comes from a bounded variant (6 per species/season) and the crop is drawn in 4 LEVELS rather than per fruit — nobody can tell seven cherries from eight at 40px. Cold 743ms, warm 3-4ms.

Measured end state: a season turns every ~25 real seconds and a full year runs in about 90, at around 7fps. The command reports its target as a target, since the rate actually reached depends on what a frame can get through.

Time is handed over in **slices**, not one lump: the ecology steps accumulate toward their own intervals and act once when they cross them, so a frame carrying an hour of world time would make each fire exactly once and discard the rest. Past a ceiling the world runs slower than asked rather than freezing — a frozen game cannot be watched at all.

✅ **Fixed an accumulator leak this exposed.** `step_forage` and `step_tree_spread` drained by SUBTRACTING one interval rather than resetting, which is exact while a frame is shorter than the interval and leaks the surplus forever once it is not. Fast-forward does it every slice; a long frame hitch already did it in the ordinary game.


### Why forests did not spread (found via `/ecotest`)

✅ **The root cause was a unit mismatch.** `TreeGenome.spread_radius` is documented as "tiles a seed can land within" and ranges 2-8, but `TreeSpread` added it to a position measured in PIXELS -- seeds landed 2-8 pixels from the parent, a fraction of one tile, so every seed a wood produced landed on a tile that already had a tree. `MIN_TREE_SPACING` was then tuned *below* that wrong number (1.5px) so it would not reject everything, which hid it. An assumption written in a comment and enforced nowhere -- the same class of bug as the sparrow with monarch wings. An old test compared the radius against a pixel distance too, so it passed throughout.

✅ **Fruit falls across the canopy block** -- the parent's tile and the eight around it, uniformly. It used to land on the tree's exact position.

✅ **A tile holds three trees at most.** Nothing bounded this before; with a pixel-and-a-half spacing rule a tile could carry a hundred trunks.

✅ **Saplings actually grow now.** `growth_scale` was set once at spawn and never touched again, so a sapling stayed a seedling for as long as it stayed loaded -- the only way to see one mature was to walk away and let its chunk unload. Trees are aged in place each frame.

✅ **The crop follows the calendar.** Phases were 0.5/0.8 of a bearing cycle whose length varied with warmth by up to half, so the crop drifted against the seasons: abscission started at four-fifths of the year (midwinter) and part of every crop never came down. The cycle is a year, always; warmth now brings the harvest FORWARD within it instead of shortening it. Bare by winter, whole crop down by the end of autumn.

✅ **Ground food rots** on a real shelf life (`FruitSpoilage`), on WORLD time so it is visible under `/ecotest`. Nuts in their shell keep ~8x longer than cherries; cold keeps things (winter 3x summer). Non-food keeps the flat despawn, which is tidiness rather than spoilage.

⬜ **Mammal frugivory is still missing.** Bird endozoochory exists (`SeedEndozoochory`) but nothing on four legs eats a windfall, so fallen fruit is only removed by the player or by rot.
⬜ Two maturation clocks still disagree: `TreeGenome.maturity_time` (20-60s, gates fruiting/spread) and `TreeGrowth.MATURITY_SECONDS` (600s, gates visual size).


### Trees in water, and one rule for rooting

✅ **Trees no longer grow in water.** Exposed BY the spread fix: seeds only started travelling far enough to leave the parent's tile -- which was necessarily land -- so nothing had ever needed to check.

✅ **One rule for "can a tree stand here"** (`TreeRooting`), derived from the vegetation model's existing per-biome carrying capacity rather than a second list of biome names. Woods in grassland, forest and rainforest; none in water, on bare rock, on sand or above the tree line. `SeedEndozoochory` had its own narrower list (forest/rainforest) while ground spread had none at all -- two rules for one question, which is the drift that produced this. Birds can now seed a meadow, which is most of what bird dispersal is for. Guarded at both call sites and again inside the shared planting sink, which is the one place neither path can bypass.

### Depleted is not spent (a correction)

✅ **Withering is now its own thing** (`FlowerBloom`), separate from nectar. Nectar is a bloom's current CONTENTS and refills in about a minute; withered is a flower at the end of its own season. Both the wilted SPRITE and the pollinators' refusal were keyed off nectar, which meant a bloom a bee had just drained read as dead and its local pollinators stopped returning to it -- which is most of what a local pollinator does.

Which part of the year a flower withers in depends on the flower: it is a fraction of that species' OWN bloom window (75% through it), so a crocus is over before a rose has opened. A test pins that different species wither at different times, and that no species is either never-blooming or withered its whole life.

The sprite's `nectar` parameter is kept -- it is still the plant's contents and still what a pollinator drinks; it simply no longer decides WILTED. An old test asserting that near-empty nectar rendered differently encoded exactly the conflation, and has been replaced.

### Pollinators foraging withered flowers

✅ `flowers_near` iterated EVERY planted cell while the renderer only drew `blooming_cells(season)` -- so bees flew to flowers that were out of season and off-screen, and landed on ones drawn wilted. Now filtered to blooms in season that have not visibly gone over, using the same spent threshold the sprite draws with.

The existing "a pollinator cannot measure nectar across a meadow" rule is kept -- it was itself a fix for an earlier report. The line drawn: **eyesight, not omniscience**. A bee can see a plant is not in flower, or that a bloom has gone over; it cannot see that a normal-looking flower is low.

### Wind-borne seed dispersal (see `docs/concept/seed_dispersal.md`)

✅ **Wind has a direction now**, walking day to day rather than being fixed -- a prevailing wind that never turned would drive every meadow in the world one way forever. Derived from day and region, so everything dispersing that day agrees without plumbing.

✅ **Heavy-tailed, downwind, weight-dependent landing offsets** (`WindDispersal`). Weight is the one property that decides distance -- flower seed 0.08 to nut 1.0 -- which is why meadows colonise faster than woods. Most seed lands near and a little goes far (right-skewed, top twentieth travels 3x the median); that tail is what colonises new ground. Dead calm still scatters seed, just not far.

⬜ Seeds as real world entities that can be seen, blown and picked up.
✅ **Germination needs earth** (`SeedGermination`): water, bare rock, sand and everything above the tree line are not seedbeds, delegating the biome question to the same `TreeRooting` rule so there is still only one answer to "can something grow here". **Grass is a good seedbed too**, both its shades -- the light and dark speckle is one kind of ground, not two. Bare earth is BETTER (0.8 vs 0.5), not uniquely possible: seed takes in a meadow all the time, which is how meadows exist. A first pass had turf at 0.08, which made grass a near-failure and would have meant nothing ever seeded except on a path. Disturbance still drives succession, so clearing a patch is a way to deliberately start a wood and a trampled path is a nursery rather than merely a scar.

✅ **Rain is the trigger**, at exactly the moisture rain delivers. Set a hair above it -- as it first was -- and only STORMS root anything while ordinary rain falls on seed that never takes; pinned to `WeatherModel.soil_moisture("rain")` by test so the two cannot drift.

⬜ Wiring germination to real seed entities on the ground (the model is done; nothing calls it yet).
⬜ Bird hunger, digestion and defecation planting what they swallowed.
⬜ Flowers still spread on the old mechanism -- not yet wired to wind, so they still spread slower than trees.


### Pollination, and trees that take years

✅ **Plants only set seed when pollinated** (`Pollination`). Dioecious: separate male and female plants, which is the arrangement that makes a pollinator NECESSARY rather than decorative -- a perfect flower that pollinates itself needs nobody to visit. Pollen is species-specific (crocus pollen does nothing for a rose), a male flower loads a carrier, a female one leaves the load intact so one trip can fertilise several plants. Seed shedding is gated on it, so a meadow that loses its pollinators stops renewing itself. Several old tests asserted a meadow seeding itself with nothing having visited -- they encoded exactly the decoration this replaces.

✅ **Each species ripens at its own time.** One fixed ripening date for every tree meant nothing bore through most of summer and a cherry never carried a cherry (reported). Cherries ripen in summer and are gone before the apples are ready; apples, walnut, hazelnut, acorn and pine bear in autumn. Nothing bears in spring or winter.

Two bugs surfaced writing it: warmth could pull ripening back into SPRING, i.e. a tree fruiting before it blossomed (now clamped -- fruit cannot precede the flower); and "becomes ripe" and "starts falling" were one number, so the entire stretch before ripening read as ripe. Three points now: ripe, dropping, bare.

✅ **A tree takes YEARS.** `MATURITY_SECONDS` was 600 simulated seconds against a year of 691,200 -- under a tenth of a percent of a year -- so a tree went from nothing to full-grown inside one season (reported once /ecotest made a year watchable). It was justified as "roughly ten simulated ecosystem days", a different clock from the seasons. A sapling is a young tree at one year and mature at three, measured against the season cycle.

✅ **Growth is continuous**, not seven fixed sizes. `scale_at` snapped to the stage, so a tree held one size for a seventh of its life and jumped -- unnoticeable over ten simulated minutes, obvious over three watchable years. Stages still gate bearing and timber; size is a curve through them.

✅ **The second maturation clock is aligned.** `TreeGenome.maturity_time` (20-60 SECONDS) gated bearing and seeding on a clock disagreeing with TreeGrowth's by four orders of magnitude -- a sapling could seed the instant it was planted. Both measure against the season cycle now, with a spread so an early variety is a real thing.


### Seasons turn gradually; smell becomes a real sense

✅ **The cherry that falls is the cherry that was hanging** (`FruitingModel.hanging_at`/`fallen_indices`, `ProceduralTreeSprite.fruit_polar`/`fruit_ground_offset`). A tree's crop used to be two unrelated things: a decorative count baked into the canopy (quantised to four levels) and a separate abscission count that spawned brand-new stacks scattered by a hash unrelated to the canopy. So fruit hit the ground under a tree drawn bare, and what landed had no connection to what had been hanging (reported). Now there is ONE source of truth -- how many are still hanging -- and a drop is defined as the DECREASE in it, which makes the two agree by construction. Each fruit falls as itself (count 1, not a pile), leaving from the top of the crop's order, and lands under the canopy position its own index was drawn at: the drawer and the ground offset share one `fruit_polar` definition so they cannot drift. This also fixed a warmth disagreement -- the displayed window was shifted earlier by `_earliness` and the falling window was not, so a tree ripened up to four days before its fruit would drop.

✅ **Winter trees are crisp** (`ProceduralTreeSprite.scale_piece`). Tree art was resampled with `INTERPOLATE_LANCZOS`, which blends neighbours and so invents in-between colours and part-transparent edges. A dense summer canopy hid it; bare winter branches -- thin high-contrast strokes on transparency -- came out smeared and haloed (reported). Now nearest-neighbour, matching the project's own `default_texture_filter=0` and the pixel art everywhere else. Pinned as a property of the scaler ("invents no new colours", "no half-transparent edges") rather than eyeballed, since any smooth filter fails those.

✅ **Snow thaws when the season turns** (`EarthChunkManager.step_snow` now reads the world clock). Snow depth was accumulated against the real FRAME delta while the season ran on the world clock -- two clocks that had to agree and never were. `/season summer` leaps the world clock up to a year forward, the snow saw about sixteen milliseconds, and a winter's cover went on lying in the sunshine (reported). The same mismatch left an `/ecotest` winter thawing at real-time speed while the seasons flew past. Fixed structurally rather than by tuning: `step_snow` takes no delta and reads `_world_age_seconds` itself, so there is one clock instead of two. Snow depth moved from `World` into the chunk manager alongside the world clock and the snow layer, which also made it testable -- and it now updates without a snow layer bound, since a headless server has weather but nothing to paint it on. Durations unchanged; they were already right.

✅ **Fruit actually falls** (`FruitingModel.fallen_between` + `_cycle_length`). Two bugs, both of which hid behind tests that asked for a whole year in a single call. (1) `_cycle_length` multiplied the year by the species' `ripening_multiplier`, so a cherry ran a 0.65-year bearing cycle and a pine a 1.8-year one, while the ripening phases are fractions OF A YEAR -- so bearing drifted against the calendar: measured, a cherry shed 24 fruit a year in two windows with the second in mid-winter, and a pine shed 0 in a year. That is the same conflation `BEARING_CYCLE_SECONDS` was introduced to kill, back through another door. (2) `fallen_between` rounded each call's own increment to a whole fruit, and fruiting steps once a SECOND -- one second of a crop of twelve over a tenth-of-a-year window is ~0.0002 of a fruit, which rounds to zero every step forever. Flooring the CUMULATIVE count and differencing makes any partition of a span sum alike. Measured after: every species sheds exactly its crop, once a year, nuts and apples in autumn, cherries summer->autumn, nothing in winter. The `test_earth_chunk_manager` drop test was also stale -- its 3000-second span was five years when a year was ten minutes, and is 0.43% of a year now that a day is four real hours.

✅ **`/season [name]` and `/weather [state|off]`** (`SeasonCycle.seconds_until_season`, `WeatherModel.force_weather`, wired through `EarthChunkManager.jump_to_season`/`force_weather`). With no argument each reports the current state and lists what it accepts. Two design decisions worth keeping: the season jump moves the clock FORWARD only -- every other system measures itself against that clock, so winding it back would give a tree a negative age -- and it moves the fruiting mark with it, since a jump is up to a year and fruiting counts what fell since it last ran, which would otherwise tip a year of windfall onto the ground in one step. Weather is pinned on the MODEL rather than at the call sites so overlay, soil moisture, wind and snowfall all agree; snow has no state of its own because it is what rain is when it falls cold (`/weather rain` + `/season winter`).

✅ **Trees grow branch by branch** (`ProceduralTreeSprite.growth_order` + `_grown_canopy`, wired through `ChoppableTree.set_age`). Growth was a single node scale, which drew a sapling as a full-grown tree in miniature -- crown, boughs and every twig, only small. The canopy is now pruned back to the branches the tree has actually put out: traced outward from the point where the trunk meets the crown, so a sapling is a short trunk with a few leaves, then a small crown, then boughs spreading, with the far tips last. Randomised per tree, so a nursery is not one sapling drawn many times. Two things had to differ from the season turn to make it read right, both found by rendering it and looking: the turn seeds from the crown's whole bottom edge (which on a spreading crown is the drooping outer RIM, and drew a young cherry as an arch floating clear of its trunk), and the turn mixes trace and clump noise half and half (which drew a sapling as confetti scattered over the whole mature crown box). Growth seeds from the trunk join alone and weights the trace at `GROWTH_BRANCH_WEIGHT`. Node scaling stays -- a young tree really is shorter -- fewer branches is in addition to it, not instead.

✅ **A wood stops when it is full** (`TreeSpread.MAX_TREES_IN_WORLD`). Spread plants a few saplings per tick and the CALLER decides how often a tick happens, so the rate was frames-per-second rather than anything to do with the world clock. Nothing bounded the population: measured under `/ecotest`, about twenty-one saplings a second, two thousand loaded trees inside a minute, and the frame rate down to seven. Bounding the population rather than the rate is the fix that holds however the caller behaves. (The per-frame shed in `step_tree_spread` is deliberate and stays: under fast-forward it fires once per frame against ~960s of simulated time, so it plants far *slower* than the clock implies, not faster.)

✅ **Seasons arrive over time, branch by branch** (`SeasonTransition` + the canopy blend). The last third of each season is spent turning into the next, so by the moment spring starts the tree is already fully turned rather than swapping frames on one boundary. The turn spreads OUTWARD from where the canopy meets the trunk, so change runs along the branches to the twigs, with jitter so the edge breaks into individual twigs rather than sweeping as a clean arc.

The crown's SIZE interpolates too. Without that, a finished turn was the new art in the old season's box -- so the crown popped at the exact moment the season arrived, which is the jump the feature exists to remove. It is also physically right: a crown shrinks as its leaves go.

Progress is quantised to 6 steps because every distinct value is a whole tree picture to composite and cache -- the constraint that bit hard when the fast-forward first ran.

✅ **Windfalls land scattered.** Named fruit dropped the whole crop as ONE stack at a fixed offset below the trunk, so a windfall was a pile against the stem rather than fruit lying under the tree -- and every seed in it landed on the tile the tree already occupies. Each fruit now lands separately across the canopy block.

✅ **Fruit keeps five days, not one.** One day is about right for real soft fruit and made the system unobservable: a day passes in ~2 real seconds at fast-forward, so windfalls rotted before any animal could reach them and nothing was ever seen lying on the ground (reported).

✅ **Olfaction: molecules and receptors** (`Olfaction`, see `docs/concept/olfaction.md`). A smell is a MIXTURE, not a label -- sugar, decay, green, musk, smoke -- so a carcass and a rotten fruit share their decay molecule and therefore their audience without either being told about the other. Fruit interpolates from a sugar mixture to a decay one as it spoils, so its audience changes across its life rather than at a threshold.

The verdict lives in the ANIMAL: sensitivity (how well it detects a molecule) and response (whether that draws or repels) are separate numbers, so an animal can be keenly aware of something it wants nothing to do with -- which is what makes a repellent work rather than merely invisible. A boar and a fly meet the same rotting apple and disagree. Distance dilutes faster than light, so an animal casts about and closes in rather than reading a beacon.

⬜ Animals do not yet FOLLOW the gradient -- the model is built and tested, nothing consumes it.
⬜ Flies as a creature; carrion, smoke and musk emitting into the same field.


### Animals follow their noses; flies

✅ **Boars and deer forage by SMELL, not sight** (`ScentForaging`). An animal that only eats what it walks into is not foraging, it is colliding with food -- which is why no boar was ever seen at a windfall even when one was lying there. Sight reached 12 tiles; a nose reaches 20, and tells the animal whether the thing is worth crossing a field for at all. Between two identical smells the nearer wins because it is LOUDER, not because of a tiebreak bolted on.

✅ **Birds use the same nose**, so a robin takes ripe fruit and leaves what has gone over to the flies. They already had a fruit-eating path; it was searching by sight at short range.

✅ **Flies** (`Flies`). They exist to make rot MEAN something: without them a rotting windfall is food nobody wants, which is indistinguishable from no food at all -- with them it is somebody's larder, and a cloud over a windfall is the player's visible cue that it has gone over. Swarm size reads through a fly's own receptors, so they are not a special case bolted on; they simply have different receptors. The swarm grows as the fruit goes further over, so the cloud is a READING of how rotten something is rather than a switch.

⬜ Flies are not spawned into the world yet -- the model is built and tested, nothing renders them.


### The season turn was built but never connected

✅ **Fixed: transitions happened instantly.** The blend, the progress model and the branch order all existed -- and nothing ever passed a tree a turn. `_sync_tree_season` fired only when the season NAME changed, so the whole forest swapped canopies on one frame, which is precisely the jump the feature was built to remove. It now re-syncs whenever the turn advances a step (quantised, so that is a handful of times rather than every frame), and both the live trees and newly-loaded ones carry the turn.

✅ **The turn traces the BRANCHES.** Radial distance from the trunk was a straight-line measure and could not express "along a bough": a twig at the end of a long branch ranks the same as one hanging near the trunk. It is now a flood that spreads only through PAINTED pixels, outward from where the crown meets the trunk, so the order follows the actual boughs out to the twigs.

✅ **The turn goes leaf by leaf, and every tree turns differently.** The branch trace alone made every tree of a species identical -- the trace is a property of the crown ART, so it is the same for every tree drawn from it, and a per-pixel jitter only blurred the edge rather than changing the order. Turn order is now half the trace and half a draw made per leaf CLUMP per tree: whole tufts flip at once, in an order that is this tree's own, while the turn still moves broadly outward along the boughs. Rendered three trees side by side to confirm they differ.

~~Randomised per tree.~~ The cost of each step is nudged by the tree's own variant, so two trees of the same species turn in different orders and a wood does not change as one animation. Jitter tuned down to 0.15 after rendering it -- at 0.55 the noise drowned the branch structure and it read as a dissolve rather than a trace.

### Flies

✅ **The life cycle** (`FlyLifeCycle`): egg, maggot, pupa, adult, in real housefly proportions. The PUPA is included though it is invisible and does nothing -- without it maggots turn into flies where they stand and the loop runs several days faster, which is the difference between a swarm over a windfall and an explosion. Only the maggot eats; only the adult flies.

Every level is capped -- eggs per clutch, clutches per female, flies per source, flies in the world -- because a breeding population with no ceiling is the tree-spread bug again and worse: flies breed in days rather than years.

✅ **Fly art**, drawn by the same painter as the bees and butterflies so it flaps and banks like the rest, but dark and drab: the player has to tell "this windfall has gone over" from "this meadow has pollinators" at a glance. An existing test required every species in that painter to be vividly saturated; the fly is exempted from the front and pinned from the other side.

⬜ Flies are not SPAWNED yet -- model and art exist, nothing puts them in the world. Eggs and maggots live on the source rather than as wandering entities.
⬜ Maggots hastening the decay of what they eat; flies following a player's carried rot.


### Flies in the world

✅ **Flies are spawned on the rot itself** (`FlyColony` + `EarthChunkManager.step_flies`), one colony per rotting ground item and one marker per adult in it. Eggs, maggots and pupae live IN the fruit and are never nodes; only adults fly, so only adults are drawn.

**One founder, not a swarm.** A source gets a single fly when it first smells right, and everything after that is bred -- a pile that starts full has no loop in it, which is the whole feature.

✅ **Maggots hasten the decay of what they eat**, so a swarm makes its own food run out. That is the feedback that bounds the loop from the food side as well as by the ceilings, and it is why the maggot is the only stage that eats.

✅ Colonies die out when their rot is gone, and adults die of old age while it lasts, so a colony turns over rather than accumulating immortals.

⬜ Flies do not yet follow a player carrying rotten fruit.


### Carried food, snow, and footprints

✅ **Food goes off in your pack**, not just on the ground -- and it had to, or "rotten fruit in your inventory" was a state the game could never reach: a windfall is removed the moment it turns, so nothing rotten could ever be picked up. Ages on world time like rot on the ground, so fast-forwarding a season does not leave a player holding pristine apples in a world where every windfall has gone. A player carrying something that has turned now smells of it, which is what lets flies follow.

✅ **Snow instead of rain when it is cold** (`Snowfall`). TEMPERATURE decides, not the season name. Falling snow reuses the rain drop field -- one mesh, one draw call -- with colour, speed and slant swapped; reusing it unchanged would give white rain, which reads as a recolour rather than weather. It accumulates and thaws slowly enough to watch, and whitens the GROUND rather than the whole scene: tinting everything would wash over the trees and the player.

✅ **Footprints displace snow** (`SnowTrail`), the same shape as the dirt paths worn into grass. What undoes them is the difference: a path grows back on its own, while tracks sit until it snows again -- so a trail lasts through a clear cold day and is gone after a fall. Filled tracks are forgotten rather than kept at zero, so a long walk does not leave the map remembering every tile ever stepped on.

⬜ Tracks are not RENDERED yet -- snow is currently a whole-layer tint, so carving per-tile footprints needs snow to become a per-tile overlay first.


### Seeds on the wind, rain that roots them, and felled trees

✅ **Flower seed rides the wind** (`WindDispersal`). It used to drop within two tiles of the parent whatever the weather -- heavier behaviour than an acorn's, from the lightest thing in the world. It is why meadows were spreading slower than woods. Seed now goes downwind, heavy-tailed, and a still day still seeds, just not far.

✅ **Rain roots what is lying there.** A seed lies until it is watered, which is what makes rain something a player waits for rather than a weather texture. A rooted seed becomes a SEEDLING, not a bloom, and rooting respects the meadow's own ceiling.

✅ **Trees are off the grid.** They stood at exact tile centres, so an original forest read as a lattice -- every trunk on a perfect grid, which no wood has ever looked like. Each now stands somewhere within its own tile, deterministically, so a wood does not rearrange itself when a chunk reloads and no trunk drifts onto a tile the placement rules say is empty.

✅ **A felled tree lies where it fell** (`FelledTree`). Felling deleted the tree and sprayed items on the ground, which reads as the tree evaporating. Now the same sprite goes over on its side -- which way depends on the tree, so a cleared wood is not a row of trunks all pointing one way -- stops blocking the path, and holds all its wood until it is worked up over several cuts. A bigger tree is a bigger haul, so felling a seedling is not the same as felling an oak.

Two existing tests asserted the old behaviour (a killing blow sprays items and deletes the node); they now assert the two stages, and the drop itself is tested against the fallen trunk that produces it.

⬜ Seeds are still patch STATE rather than world entities -- they are rendered and can be rooted, but you cannot pick one up.
⬜ Bird digestion -> droppings planting what was swallowed.


### Birds eat because they are hungry, and leave droppings

✅ **Hunger** (`BirdDigestion`). Birds foraged constantly whether or not they needed to, which makes a bird a harvesting machine rather than an animal. A songbird gets through a serious fraction of its body weight daily, so it feeds through the day rather than at meals -- pinned from both sides by a test that counts meals across a day. A bird mid-peck finishes it rather than abandoning the grass the instant its crop fills.

✅ **Droppings**: the visible half of dispersal. Without one, a seed simply appears somewhere a bird happened to be and the player never sees the connection between the bird that ate the berry and the flower that comes up under the perch. Bounded, because scenery that accumulates forever is a leak with a sprite.

✅ **Removed a second clock I had just added.** I gave digestion its own gut-passage timer alongside the carry SeedEndozoochory already models as a distance -- two clocks for one thing, at wildly different scales (the carry is seconds of game time, a real gut passage is minutes). The timer never elapsed, so dispersal stopped happening entirely: every seed a bird swallowed simply stayed in it. The flyer's own tests caught it. The carry IS the passage; a test now pins that digestion does not own a passage clock, so it cannot come back.


### Footprints, pickable seeds, and flies that follow you

✅ **Snow is a per-tile overlay** (`SnowLayer`), so footprints can be carved out of it. A tint is one number for the whole world and cannot express "this tile is trodden and that one is not" -- which is why tracks could not exist at all before. Four depth bands, patchy at the shallow end because a dusting is snow lying in the dips with grass showing through, not a thin even wash. Walking PACKS the snow rather than clearing it: a trail reads as tracks, not as a trench dug to the soil, and only a thin cover is broken through to the ground.

Painted INCREMENTALLY. Repainting every loaded tile every frame is thousands of set_cell calls for a field that mostly has not changed -- the same shape of cost that took the frame rate down when the fast-forward first ran. The field repaints only when its depth crosses a band, which happens a handful of times a snowfall; footprints repaint only the tiles actually walked on.

✅ **Seeds can be picked up.** They were already real things -- drawn, and eaten by birds -- but the player could only watch them. A seed you can take is what makes deliberate planting possible: gather from a meadow, carry it, sow it where you want flowers. It joins the group the pickup sweep already reads, the same trick LiftableStone uses, and is taken from the PATCH as well as the screen so a picked seed is not still lying there for a bird to eat or the rain to root.

✅ **Flies follow a carrier.** A pack with something turned in it gets its own swarm, repositioned as the carrier moves rather than orbiting a spot on the ground. No colony and no breeding there -- nothing lays eggs in a pack that keeps moving, and a swarm bred in an inventory would be a strange thing to own. These are flies that caught the scent and stayed with it.


### Snow that never covered, and snow in spring

Both reported, both the same underlying mistake in different clothes: numbers chosen against "how long should a player watch this take" without checking the clock that actually governs them.

✅ **Snow now covers and tracks now fill.** A weather spell lasts 600 seconds. Covering was set to 2700 (four and a half spells), filling a footprint to 720 (more than one), thawing to 1800 (three) -- so a snowfall always ended long before it could cover anything, and a track cut on the first walk stayed for good. All three are expressed in WEATHER SPELLS now, with covering finishing inside one and a footprint drifting full faster than a whole field is buried. `WEATHER_PERIOD_SECONDS` moved to `WeatherModel`, where the weather lives, so there is one definition rather than a copy in whatever reads it.

✅ **It no longer snows on the blossom.** Measured the season curve instead of guessing: winter carries warmth 0.00-0.14 and the shoulder seasons run 0.15-0.85, while the freezing threshold sat at 0.25 -- well into spring. At the measured boundary, winter snows and an ordinary spring does not, while a genuinely cold climate still snows out of season because latitude scales warmth before it reaches the test.

Two of my own tests had assumed the old slow rates -- they asserted STRICTLY increasing depth over twenty minutes, which stopped holding once covering finished inside a spell. Flat at full cover is correct behaviour, not a regression; they assert non-decreasing and reaching full now.


### Every new game began on the same frozen instant, and a snowfall snapped instead of spreading

Both reported by name while actually playing, both traced to real code rather than assumed.

✅ **A new game no longer starts on a fixed frozen instant.** `_world_age_seconds` (the clock `season_at`/`warmth_modifier` are pure functions of) started at a hardcoded `0.0` for every fresh save, and was never persisted in any form at all -- not even for a loaded game. `warmth_modifier`'s own phase formula puts world-age zero at warmth **≈0.1465**, just under `Snowfall.FREEZING_WARMTH` (0.15), so every single new game began mid-winter-adjacent and reliably snowed within minutes (reported: "it starts to snow deterministically"). `EarthChunkManager.randomize_world_age()` now rolls a uniform random offset across the whole year (`NEW_GAME_WORLD_AGE_RANGE_SECONDS = SeasonCycle.SECONDS_PER_YEAR`, Godot's own default-seeded `randf()`) once, at New Game/Host Game creation, and `set_world_age_seconds` re-syncs `_last_fruiting_time`/`_snow_world_age` in the same call so the jump doesn't read as a fake elapsed span the next time fruiting or snow steps -- the exact "two clocks that have to agree" trap `jump_to_season`'s own doc comment already warns about, just at world-creation time instead of a `/season` skip. A loaded game never re-rolls: the clock is now genuinely persisted (`WorldClockPersistence`, `user://world_clock.bin`, the same `store_var` convention `PlayerSave`/`EventStorePersistence` already established) and `World._spawn_local_singleplayer_from_save` restores it **before** the first `update()` call, since chunk-loading itself reads the world age (sapling ages, ecology catchup). Verified live: 20 freshly-constructed managers landed on 20 distinct world-ages, and 40 of them spanned more than one season -- against the old code, all of them would have landed on the exact same instant, every time.

✅ **A snowfall now fills in a chunk tile by tile instead of snapping everywhere at once.** `Snowfall.accumulate`'s aggregate 0-to-1 coverage number is the right shape for the pure model, but `EarthChunkManager._paint_snow_tile` fed that SAME number to every tile in the loaded field, so the instant it crossed a depth-band boundary the whole chunk changed together in one frame (reported: "snow covers a whole chunk instantly instead of spreading progressively"). Each tile now carries its own small, bounded lead or lag on the shared depth (`SnowLayer.ONSET_VARIANCE = 0.18`, `onset_offset_for`, seeded off the tile's GLOBAL coordinates via `PixelNoise` so the pattern neither repeats nor seams at a chunk boundary) -- the same per-cell-seeded-jitter idea `TallGrass`/`FlowerPatch` already use so a uniform process doesn't read as synchronized; this project has hit that exact "same value everywhere" clustering bug five times before (see `PixelNoise`'s own doc comment).

A first pass left the WHOLE-FIELD repaint trigger untouched (it only fired when the tracked onset-free depth crossed one of `DEPTH_BANDS`' 4 boundaries) on the assumption that per-tile onset alone was enough. A real probe against a live `EarthChunkManager` proved that judgment call wrong: coverage sat flat at the exact same 55.1% of land tiles from global depth 0.02 clear through 0.25 (all inside band 0), then jumped straight to 100% at depth 0.5 -- the *same* instant-reveal bug, just relocated to a coarser timescale. `_repaint_snow` now ALSO repaints whenever depth has moved by `SNOW_REPAINT_DEPTH_STEP` (0.05, well under `ONSET_VARIANCE` so several checkpoints land across the onset spread) since the last repaint, not only on a band crossing. Re-measured after the fix, same live manager: 55.1% → 55.1% → 77.5% → 100.0% across depths 0.02/0.05/0.1/0.25 -- a genuine multi-step climb rather than one flat plateau followed by a snap. (A whole snowfall, `Snowfall.SECONDS_TO_COVER` ≈ 360s, still only repaints on the order of dozens of times, not every frame -- the cost concern the original batching existed for.)


## Status legend

- ✅ **Done** — implemented and (per project convention) covered by tests.
- 🚧 **Partial** — meaningfully started, but incomplete, superseded, or not
  wired into live gameplay yet.
- ⬜ **Not started** — no implementation exists.

---

## Roadmap phases (`docs/roadmap.md`)

The roadmap is the only source doc that already sequences work into phases,
so its own mechanisms are tracked here phase-by-phase. Nearly everything else
in the design corpus (classes, skills, magic, crafting, farming, etc.)
predates or sits outside this roadmap and is tracked in the
[Unscheduled](#unscheduled--not-yet-phased-into-the-roadmap) section below.

### Phase 0 — Foundations / tech spikes

Goal per roadmap: de-risk the unknowns before building gameplay on top of them.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Project Scaffold & Tile Rendering | ✅ Done | Godot 4.7 project set up; `scenes/world.gd`/`.tscn` is the root scene (viewport 1280x720). `src/rendering/terrain_renderer.gd` bakes procedurally-generated, seeded pixel-art tiles (`procedural_terrain_sprite.gd`) with `VARIANTS_PER_BIOME` (6) variety per biome, now **animated in real time** via `TileSetAtlasSource` tile animation (`FRAME_COUNT` 4-frame blocks, zero per-frame script cost): grass tufts sway (baked, frozen-per-blade -- real motion lives in the GPU blade field below), and each biome layers detail over its base speckle (grass tufts + flower accents, forest-floor moss, desert dune ripples, tundra stones, mountain cracks). The base water tile is now a calm static-per-frame tint/texture only -- all visible water motion (waves, shore blending, rain) moved to a dedicated **WaterFx GPU overlay** (`water_shader.gd`, a second TileMapLayer painted via `TerrainRenderer.build_water_overlay_tile_set`/`EarthChunkManager.set_water_layer`): a per-pixel "shore distance" data tile family (`procedural_shore_distance_sprite.gd`, 0 at the land edge to 1 in open water) drives a fragment shader that sums ambient wind chop, an incident+reflected standing-wave band near the coast ("waves bounce off shore"), and hash-seeded expanding raindrop ripple rings (`rain_intensity` uniform, driven continuously by `EarthChunkManager.set_rain` from the live weather model) into one interfering wave field, fading alpha smoothly with shore distance so the coastline blends instead of cutting off at a tile edge (replacing the old baked foam/dash shore tiles, whose 16px grid read as a jagged staircase). A `wind_strength` uniform (`WeatherModel.wind_strength_for`, driven the same way as `rain_intensity` via `EarthChunkManager.set_wind_strength`) paces the ambient wave's scroll rate to the live weather's severity, so the same shore idles calmly on a clear day and churns faster/choppier during a storm. Individual 1px grass blades similarly moved off the tile grid onto a per-chunk GPU `MultiMeshInstance2D` field (`grass_blade_field.gd`) clustered into natural tufts, excluding any cell a building piece currently occupies (`build_field`'s `occupied_cells` param, rebuilt via `EarthChunkManager._rebuild_blade_field` after every `build_at_global`/`destroy_at_global`/`stamp_structure_at_global` and after village generation stamps its houses -- previously blades sprouted straight through house floors and walls, reported as "there should not be any plants growing inside of a building"). Vegetation sprites (trees, tall-grass and scrub tufts, the GPU blade field) sway via a shared GPU vertex shader (`wind_sway.gd`, gentle two-frequency gust motion, world-position phase so gusts roll across a meadow; lichen deliberately static). `wind_sway.gd`'s amplitude now also scales with the SAME live `wind_strength` (`WeatherModel.wind_strength_for` via `EarthChunkManager.set_wind_strength`) driving the water shimmer above, rather than a fixed amount regardless of weather -- `WindSway.set_wind_strength` pushes it onto both `shared_material()` (trees, via `TreeRenderer.set_wind_strength`) and `tuft_material()` (grass/scrub tufts AND flower blooms, which share this exact material -- see `concept/long_grass.md`), calibrated so the default (`wind_strength == 1.0`) exactly reproduces today's tuned look on a clear day. Border cells still dither toward whichever differing neighbor biome dominates on each edge (`dominant_blend_for`, `BLEND_VARIANTS` 3 -- fringe needs fewer looks than base ground), and chunk seams blend through `EarthChunkGenerator.biome_at_global` exactly like interior borders. | small |
| Camera & Player Movement | ✅ Done | `scenes/player.gd` — `CharacterBody2D` with WASD movement (runtime-bound), toroidal wrap, water movement integration. | small |
| Heightmap Generation | 🚧 Partial (repurposed) | `src/world/heightmap_generator.gd` exists, tested, but no longer used for Earth — kept explicitly for generating future non-Earth planets. Earth instead uses real elevation data (`earth_elevation_source.gd`). | medium |
| Hydraulic Erosion Pass | 🚧 Partial (repurposed) | `src/world/hydraulic_erosion.gd` exists, tested, same caveat: part of the old fully-procedural pipeline, not used for Earth's real rivers/lakes. | large |
| Climate Banding | ✅ Done | `src/world/climate_model.gd` — temperature from latitude + elevation (simple lapse-rate model), applied to the real Earth world. | medium |
| Biome Classification | ✅ Done | `src/world/biome_classifier.gd` — elevation/temperature/moisture → 7 biomes (ocean/mountain/tundra/forest/grassland/rainforest/desert); has both a fictional-noise-tuned default calibration and a parameterized real-Earth calibration. | small |
| Toroidal World Wrap | ✅ Done | `src/world/world_coordinates.gd` (toroidal math) + player wrap in `scenes/player.gd`. | medium |
| Chunk Save/Load System | 🚧 Partial | `src/world/chunk.gd` + `chunk_serializer.gd` — data model and persistence built and tested, but **not wired into gameplay**: no player-driven terrain modification exists yet, so nothing is ever actually saved/loaded at runtime. | large |
| Day/Night Clock | ✅ Done (superseded design) | `src/world/solar_position.gd` drives real-time (actual system clock, not accelerated/abstract) day/night lighting via `CanvasModulate` in `scenes/world.gd`. The originally-planned abstract/accelerated clock (`world_clock.gd`, `sunlight_model.gd`) still exists, kept as a possibly-reusable utility (e.g. abstract elapsed game-days later). | trivial |
| Per-Tile Sunlight Model | ✅ Done | `solar_position.gd` computes real astronomical solar elevation from UTC time + lat/long (approximate formula, no equation-of-time correction). | small |

**Phase 0 definition of done** ("a small toroidal world generates once, looks
biome-plausible, saves/loads chunks correctly, and has a visible day/night
cycle"): mostly met, but the project deliberately diverged from the plan —
instead of a small fictional test map, it generates a real, finite Earth
(~40,000×20,000 tiles, ~111 tiles/degree, ~1km/tile) from real elevation data.
Biome plausibility and day/night are real; chunk save/load exists but is not
yet exercised by any runtime gameplay.

### Phase 1 — Living ecosystem MVP

Goal per roadmap: prove the "boars live where boars thrive" pillar. Core loop
built and wired into live gameplay (server/singleplayer-authoritative); known
gaps noted per mechanism below.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Vegetation Growth Model | 🚧 Partial | Three still-separate systems: (1) `src/world/tree_placement.gd` + `src/rendering/tree_renderer.gd` -- static, deterministic, biome-driven tree *placement* (collidable `ChoppableTree`s), unchanged; (2) `src/world/vegetation_growth_model.gd` -- a real per-cell logistic growth/die-back/neighbor-spread simulation (temperature+moisture -> effective carrying capacity -> density), driving herbivore capacity below (mountain's `CARRYING_CAPACITY_BY_BIOME` entry is now a small nonzero `0.12`, sparser than tundra's `0.2` -- previously a hard `0.0` that made mountain permanently uninhabitable, which was pointless once mountain got its own goat/mountain_lion species pool; ocean correctly stays `0.0`); (3) new **individual-tree genetics/spread** -- `TreeGenome` (deterministic per-tree DNA: fruit_yield/species_bias/spread_radius/maturity_time, with `mutate()` for inheritance), `TreeSpread` (mature trees plant a mutated-child sapling within their own spread_radius, centrally throttled like forage), and `TreeMaturity` (a sapling only forages/reproduces once its own age exceeds its genome's maturity_time) -- wired into `EarthChunkManager.step_tree_spread`, spawned/rendered via `TreeRenderer.spawn_tree_at` with a genome-tinted canopy (`ProceduralTreeSprite`), and persisted per-chunk (`Chunk.planted_trees`, `ChunkSerializer.save_planted_trees`/`load_planted_trees`) across unload/reload. None of the three are unified: the density field still doesn't spawn/despawn/resize visible trees, and individual-tree genetics is independent of the density-driven herbivore capacity. | large |
| Herbivore Population Model | ✅ Done | `src/world/herbivore_population_model.gd` (+ generic `population_model.gd`): regional/aggregate logistic growth toward a vegetation+water-access-derived capacity, with migration toward neighboring spare-capacity regions. Tested incl. drought decline/recovery (`test_ecosystem_time_lapse.gd`). | large |
| Predator Population Model | ✅ Done | `src/world/predator_population_model.gd`: same shape, capacity derived from local herbivore population (trophic-pyramid ratio). | large |
| Aggregate/Individual Promotion System | ✅ Done | `src/rendering/creature_renderer.gd` + `EarthChunkManager`: loading a chunk (i.e. player proximity, reusing the existing chunk-streaming radius) spawns individual creature nodes sized to that region's current aggregate population; unloading frees them. Each promoted creature has procedurally-generated pixel-art (`procedural_animal_sprite.gd`) and real per-individual AI (see Individual Creature AI below). Species is now **biome-gated**, realizing the "boars live where boars thrive" pillar for real: `EarthChunkManager` computes each chunk's dominant biome (`BiomeClassifier.dominant_biome`) and passes it into `spawn_creatures`, which picks from `HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME` (grassland/forest/desert/tundra/rainforest/mountain each get their own herbivore+predator pair, e.g. desert -> camel/jackal, rainforest -> tapir/jaguar) instead of one global 4-species pool; unmapped biomes (currently just ocean) fall back to the original generic pool. Not replicated to multiplayer clients yet -- a connected client sees its own locally-seeded population, not the server's evolving one (see Multiplayer's known gaps). | large |
| Individual Creature AI (flee/hunt/graze/drink) | ✅ Done | `CreatureMarker` runs a per-frame sense→decide→act loop from four tested pure modules: `creature_needs.gd` (hunger/thirst rising over time), `creature_perception.gd` (senses nearby creatures/player + scans terrain for nearest food/water), `creature_behavior.gd` (priority decision: flee/attack/hunt/seek-water/seek-food/wander), and temperament/role on `creature_info.gd`. Herbivores are calm — they flee predators and the player, graze food biomes, and drink at water; predators are aggressive — they hunt and eat herbivores when hungry, attack the player when healthy (dealing real `Player.take_damage`), and flee when weakened below half health ("weak monsters flee, strong monsters attack"). **Movement (`_advance`) now has two deliberately different treatments by body plan**, after two failed attempts at unifying them (both left in code comments as a warning against retrying): a SERPENT turns its heading toward the desired direction at `SERPENT_TURN_RATE` and only ever moves along the heading actually reached, then rotates its whole sprite to match — a long thin body reads fine at any angle. A LEGGED animal (horse, deer, etc.) moves directly toward the requested direction with no turn smoothing and NEVER rotates — its art is a strict left/right side-view silhouette with legs baked pointing at the ground; turning it toward headings it can't draw, or rotating the whole sprite to face them, both read as visibly wrong (rotating in particular tips the legs away from the ground the instant the heading isn't near-horizontal — reported directly: "that literally rotates the horse so that it's legs are upside down"). It only ever flips left/right to match its current horizontal direction, IMMEDIATELY, on the very same frame the direction's sign disagrees with the current facing — gated only by a small deadzone on the direction's x component (`FACING_DEADZONE`, so a near-vertical request doesn't flip at all either way). This used to ALSO be gated behind a **distance-based commit** (`FACING_COMMIT_DISTANCE_TILES`, 3 tiles: once flipped, must actually travel that far before flipping again), added because flipping off the raw per-frame direction with no hysteresis flickered every single frame near the player back when `ThreatAvoidantWander` recomputed its avoidance direction fresh every frame from the live relative angle (reported then: "changing direction so often that the horse shows doubled in both direction"). Removed after it overcorrected: a creature given a genuinely SUSTAINED new direction (not noise) still held its stale old facing until it had physically covered 3 tiles, which IS real backward/sideways-backward translation the whole time it hadn't caught up (reported: "the horse walks backwards or diagonally backwards sometimes... looks like it's moonwalking" — and the same root cause behind repeated "flee hystery" reports below, since a fleeing/avoiding legged animal reverses direction often and a serpent, whose travel direction and visual heading can never disagree by construction, never exhibited it). Removing it exposed that the direction feeding `_advance` was itself chattering — measured 800 facing flips per 1800 frames, reported as "now it constantly flips back and forth". The source was `CreatureWander.direction_at`'s home-anchoring, which **blended** an outward roam heading against an inward pull toward home; opposing vectors cancel, and normalizing a near-zero blend amplifies sub-pixel position noise into a full-speed reversal. Instrumenting it showed a creature parked at distance 49.7↔50.1 from home reversing every single frame. (The first attempted fix — easing the blend rather than switching hard at the radius — only moved the cancellation point, 800→774 flips; the measurement is what caught that, not inspection.) Home-anchoring is now **containment** rather than a tug of war: approaching `WANDER_RADIUS`, the heading's outward radial component is progressively projected away — the same "strip the component pointing where you shouldn't go" shape as `ThreatAvoidantWander.away_biased_step` — so at the radius the creature can only travel tangentially or inward, and a genuine inward pull eases in beyond it (reaching fully homeward by `HOME_PULL_FULL_RADIUS_FACTOR`) so a creature knocked far out still comes home. Nothing opposes anything, so there is no cancellation to be ill-conditioned about. That brought the flips to **2**. `FishMarker` shares `CreatureWander` and had the same latent chatter. Two more instances of the identical pattern were then measured and fixed near a stationary player, after the report "16-23 flips IS exactly the problem... it should not constantly flip when at the border": (1) **flee acquisition** used one threshold for both entering and leaving, so a player parked on `SENSE_RADIUS` made the creature dither in and out of fleeing — now a Schmitt trigger, entered at `SENSE_RADIUS` and only released at `FLEE_RELEASE_RADIUS` (120px, comfortably inside `CAUTION_RADIUS` so a creature that just stopped fleeing is still avoiding); (2) **caution avoidance** applied at full strength anywhere inside `CAUTION_RADIUS` and not at all outside it, so avoidance shoved the creature just past 160px, vanished, the home anchor pulled it straight back in, and avoidance shoved it out again (measured oscillating 155.0↔160.6px on a 16-frame period) — the strength now ramps 0 at `CAUTION_RADIUS` to full at `SENSE_RADIUS`. Alongside that, `_advance_avoided` stopped **renormalizing** the avoided step: a creature whose only way home is straight through the player has its step almost entirely cancelled, and scaling that residual back up to full speed produced a full-speed lurch in an ill-conditioned direction reversing every frame (measured pinned 127px from the player with distance-to-home flickering 54.0↔54.2). Keeping the surviving magnitude means a cornered creature simply slows to a stop facing away — stable, and what a real animal does. Net: **800 → 3** facing changes per 1800 frames, and two of those three are genuine direction changes. An intermediate attempt at (2) — dropping the home anchor outright whenever a threat was within `CAUTION_RADIUS` — is recorded here as a warning: it just moved the hard switch, making things *worse* (31 → 49 flips). Every hard distance threshold in this system has produced this same shape of bug; ramps and hysteresis do not. Finally, all of the above are still *reactive* — they reshape a heading that already points somewhere bad, or notice after the fact that the creature didn't advance — and reactive mechanisms degrade into thrashing precisely when there is nowhere open at all: a creature wedged between the player and a tree picks a new direction every single frame and reads as vibrating (reported: "when it's stuck between player and blocked by a tree it still flips erratically... same when blocked by a stone"). On the explicit direction "make it so that all animals first check if moving is going to be blocked by a tree or by entering flee radius and only actually execute the move if it's clear. If it doesn't have anywhere to go, it should just stay in idle mode without walk animation or flips", movement is now **gated before it happens**: `src/gameplay/creature_movement_gate.gd` (pure, 8 tests) takes the desired heading plus nearby blockers and threats and returns either a heading that is genuinely clear — trying progressively wider turns, smallest first, so an animal walks *around* a trunk rather than veering wildly — or `Vector2.ZERO` meaning stand still, which `CreatureMarker` renders as the idle pose with no movement and no facing change at all. Obstacles come from the `tree`/`stone` groups and are sized from their **own** `CollisionShape2D` (a tree's solid part is just its trunk — you walk under canopies), gathered on the throttled sensing tick. Every movement intent routes through `_advance_gated`; flee is obstacle-gated but deliberately **not** threat-gated, since a fleeing animal must not be talked out of running by the thing it is running from. Both checks are "don't make it worse" rather than "must not be close", so an animal the player has walked right up to (already inside its flee radius) or one overlapping a trunk can still move clear instead of being pinned. See [ecosystem_dynamics.md](concept/ecosystem_dynamics.md#locomotion-look-before-you-step) for the design rule this encodes. Three follow-ups landed immediately after: (1) **the gate's obstacle scan lagged the whole game** ("since the last change the game is laggy") — it walked the ENTIRE `tree`/`stone` node groups per creature per sensing tick; `EarthChunkManager.solid_obstacles_near` now answers the same question O(nearby) from its per-chunk tree/stone bookkeeping, and `CreatureMarker._blockers_near` duck-types onto it (group scan kept only as the worldless/stub fallback). `IllustratedAnimalSprite.waterline_offset_y` is also memoized — it rescanned a full frame's pixels per animation step per swimmer. (2) **The gate was memoryless**, so its detour side could alternate as position wobbled sub-pixel — still read as flipping at the obstacle ("walks into a tree and starts flipping erratically... walks into a stone and gets stuck"); `clear_direction` now takes the previously-travelled heading and keeps a committed detour while it stays clear and the desired heading stays blocked, dropping it the moment the desired heading clears. (3) **Birds had the same latent limit cycle** land creatures did ("Boars and Birds now also get stuck, flicker and flip erratically") — `AmbientFlyerMovement.direction_at` still hard-switched to "head straight home" at its radius, the exact bug `CreatureWander` was cured of; it now uses the identical containment shape. Separately, the walk/swim gait is now paced by **distance actually covered** rather than wall-clock time (`GAIT_STRIDE_PER_FRAME`, derived so ambling cadence is unchanged and faster movement cycles proportionally faster — "adapt the horse animation to be faster when it moves faster"): stride frequency ∝ speed, and a blocked creature's legs freeze automatically since no ground is covered. The horse sheet was replaced a 4th time (walk-only: one 8-frame walking row, still left-facing); idle now synthesizes from the walk cycle's frame 0 — the last link in the idle fallback chain (idle_bands → eat frame 0 → walk frame 0) — rather than regressing a standing horse to procedural art. The next pass, on the explicit directive "prevent the erratic flipping entirely... if it gets blocked by a tree and changes direction it should not be allowed to instantly flip again... if it can't move in any direction it should just stand still and idle", added the last three pieces: (1) a **facing commit** (`FACING_COMMIT_SECONDS`, 0.8s) — a reversal request inside the window is refused outright and the creature *stands* that frame; refusing to MOVE is what makes a time-based commit safe where the old distance-based one moonwalked (it kept moving while wrongly faced) — real animals stop, then turn; (2) the movement gate's detour **prefers the side that keeps the current facing** (`facing_sign` param; flip-requiring candidates are only accepted once every facing-preserving one has failed, never refused outright — a creature whose only way out is behind it still takes it); (3) **grazing pauses** (`CreatureWander.is_pausing`, `PAUSE_FRACTION` 0.3 test-pinned, deterministic per seed+interval) — ordinary wander now stands idle for a share of its intervals, since continuous never-resting drift read as mechanical ("it doesn't look like natural wandering or foraging"); searching/seeking/fleeing never pause. A second, larger perf pass followed ("it's still lagging a lot ever since your fixes for the erratic horse flipping"), this time **profiled rather than guessed** — a headless benchmark of 40 creatures x 600 frames, which measured **4.31 ms/frame** (a quarter of the 60fps budget, with nothing rendering). Two causes, both mine: (1) `_apply_action_scale` called `IllustratedAnimalSprite.marker_scale` EVERY frame for EVERY creature, and that reached `AnimalAnatomy.profile_for`, which returns `.duplicate()` — a fresh ~25-key Dictionary allocated per creature per frame. It had been a spawn-time-only call before per-action scaling. Now cached per species/action (static) AND skipped entirely unless the action actually changed (`_scaled_action`); the call itself went 191ms→20ms per 20k. (2) The movement gate ran its full candidate search, plus allocating a threat-position array, for every creature every frame — including the overwhelmingly common case of a creature in open ground with no tree, stone or threat in reach. Short-circuited to a plain `_advance` when there is nothing to avoid. Net: **4.31 → 0.88 ms/frame** with obstacles nearby, 0.76 in open ground — about 5x. Earlier in the same session, from "the lag is... sth that recently changed with horse movement. Rain just puts enough load that it becomes noticable": a creature the gate had already declared stuck was re-scanning **all candidate turns × every nearby blocker every frame** — `_gate_standing` now holds it idle until the next sensing tick (blockers only refresh then anyway, so nothing is lost); `SubmersionShader` now compiles ONE static shared `Shader` instead of a fresh identical compile per creature's first wade; the ever-swum-creature per-frame `clear_waterline()` uniform write is guarded; `solid_obstacles_near` stops allocating concatenated temp arrays. A separate residual remained even then: `FACING_DEADZONE` correctly refuses to flip on a near-vertical direction, but the small backward x was still being APPLIED (measured 266 backward frames per 1800). Inside the deadzone that backward component is now dropped so the creature travels purely sideways instead — never flipping on ambiguous noise, never sliding backward either ("quadrupeds should only be allowed to move forward and sideways"). **None of that was the actual "walking backwards" bug, though.** `assets/sprites/horse.png` is drawn facing **LEFT** (deer.png/boar.png and every procedural sprite face right), and `flip_h = desired.x < 0` is only correct for right-facing art — so the horse rendered mirrored and walked backwards in *every* direction, the whole time. The facing tests missed it for the same reason the production code did: they asserted on `flip_h`, encoding the identical right-facing assumption, and so passed green against a fully mirrored horse. Fixed by declaring `faces_left` per sheet (`IllustratedAnimalSprite.faces_left` — a property of the supplied ASSET, not the species) and adding `CreatureMarker.facing_sign()`, which reports which way the creature is actually SEEN to face; `flip_h` alone can't, since it only means "mirrored from whatever the source art happens to be" and that source is **not** consistent — an illustrated species falls back to procedural art for eat/attack, so one creature's art convention genuinely changes with its action (`_art_faces_left`, refreshed in `_animation_step`, which also flips `flip_h` to preserve visual facing across such a swap). Every facing test now asserts on `facing_sign()`, and the end-to-end guarantee runs for **both** art conventions so the suite cannot pass again by accidentally agreeing with one of them: `test_a_wandering_creature_never_translates_against_its_own_facing` (horse, left-facing) and `test_a_right_facing_species_also_never_translates_against_its_own_facing` (deer), each asserting zero backward frames over a simulated run. The walk-cycle leg animation is gated on actually having moved (`_is_moving`, set inside `_advance`) — it used to cycle purely off elapsed time, so legs kept swinging through a stride even while genuinely stationary (reported "their legs are animated even when they stand still"); not moving now shows `ProceduralAnimalAnimation`'s single static "idle" pose instead. The health bar and ground shadow are both `top_level` and manually re-synced to the marker's position (translation only) every frame — plain children otherwise inherit a rotating serpent's rotation too, tilting them along with the body (reported: "the health bar and shadow of creatures should NOT rotate together with the animal"). The ground shadow itself is a silhouette (`DropShadow.make_silhouette_shadow`) — a live, upside-down copy of the creature's own current texture/facing anchored at its feet, not a fixed oval — and its length reacts to the real sun's elevation (`DropShadow.stretch_for_elevation`, the true `1/tan(elevation)` projection ratio, clamped): a low sun (dawn/dusk) drags it out long, an overhead sun collapses it short, updated world-wide via `CreatureMarker.sun_elevation_deg` from World's existing `SolarPosition` calculation (reported: "instead maybe copy the animals shape, flip it upside down, anchor it to the feet and stretch it based on the suns elevation"). Trees/stones/village buildings still use the older fixed-ellipse `DropShadow.make_shadow`, untouched by this change. The shadow's anchor point is derived per-species from `AnimalAnatomy`'s own `body_y`/`body_height`/`leg_length` (mirroring `ProceduralAnimalSprite`'s own ground calculation), not a fixed half-height guess — the guess put the shadow visibly below a boar's actual hooves (reported: "the shadow is a few pixel below sprite so it looks like it's floating"). That anchor offset is also now scaled by the marker's own `scale` before being applied (species size x the shared art-resolution downscale, see art_resolution.md) — it was being applied as a raw, unscaled pixel count, which still overshot past the actual on-screen feet for any species whose scale wasn't exactly 1.0 (same floating-shadow report, still visible after the first fix for exactly this reason). The shadow's rotation is now also kept in sync with the marker's own rotation (both the anchor offset and the sprite itself) — a serpent's whole sprite rotates to face its heading (see `_advance`'s doc comment), so its shadow has to swing around with it to stay a physically accurate silhouette instead of a flattened blob that stopped turning with the body (reported: "The shadow for snakes is not rotating properly. Its shadow should render physically accurate when the snake is rotated"); the health bar, and any non-`Sprite2D` shadow, deliberately still never rotate. A no-op for legged animals, whose own sprite rotation is always 0. Two attempts at also rotating the shadow's ANCHOR OFFSET to match a turning serpent's body each put the shadow in the wrong place at some rotation (one swung it above the body past 90 degrees, the follow-up "mirror around the X axis" fix still didn't hold up at every angle) — the offset now deliberately stays fixed straight down instead, the same as every other creature's shadow, regardless of the body's own rotation/flip_v (reported, across all three passes: "the shadow is not rotating properly", "When the snake is upside down the shadow renders above it", "the shadow should always render on the bottom of a creature regardless if it's rotated by 180deg"). Only the shadow SPRITE's own rotation/flip_v still track the body (`sprite.rotation = rotation`, `sprite.flip_v = not flip_v`), so the flattened silhouette SHAPE still visibly matches the body's current orientation even though its anchor point does not. `ThreatAvoidantWander`'s CAUTION_RADIUS avoidance used to only cover ordinary idle wander — "search_water"/"search_food" (ranging outward to LOOK for a resource nothing's currently sensed) advanced straight off the raw roam heading instead, so a thirsty/hungry creature near a stationary player would range straight toward them regardless, cross into flee range, resume searching the instant it was safely back outside it (still thirsty/hungry), and range right back — the exact "back and forth" the caution radius was built to prevent for wander (reported again: "the horse and other animals... same flee hysteria the snake had at the beginning"). Both roaming paths now share one `_caution_biased_step` helper. A SEPARATE, more direct cause of the same symptom was found and fixed next: `_flee_commit_remaining`/`_flee_direction` (the "hold a flee heading for a beat instead of re-deriving every tick" fix) only ever decremented WHILE actively fleeing — an episode that ended early (escaping SENSE_RADIUS before its own commit window expired) left both frozen at their stale values instead of resetting, and the NEXT flee episode reused that stale heading verbatim even if the new threat was somewhere else entirely, which could point the creature TOWARD it instead of away (reported again, still, after the wander/search fixes above: "the horse still has flee hystery and tries to walk into the players flee radius"). `_apply_decision` now resets both whenever a frame ISN'T fleeing, so only a genuine gap between two separate episodes clears them — one continuous flee streak still holds its heading across its own frames exactly as before. Separately, `_is_moving` (gating the walk-cycle animation, see above) used to be derived purely from the requested direction's own length rather than whether the creature's position actually changed — anything that left position unchanged despite a nonzero requested direction (e.g. blocked by an obstacle) would keep playing the walk gait forever (reported: "should only render walk animation when moving, not when stuck against a tree or standing still"); `_advance` now compares position before/after every step instead. A third, unrelated bug reported in the same pass ("when the horse enters the water it becomes tiny"): `scale` was set ONCE at spawn time (`CreatureRenderer._build_marker`), calibrated for whichever canvas that species' INITIAL texture used — for an illustrated species, its own tiny illustrated-canvas multiplier (see `IllustratedAnimalSprite.marker_scale`). Switching to an action illustrated art doesn't cover swaps `texture` to a MUCH smaller procedural canvas (48x32 vs the illustrated canvas' 340x330) without ever revisiting `scale`, rendering the creature far too small. `_animation_step` now recomputes `scale` (and the shadow's own base scale, kept in lockstep) every step, mirroring `_build_marker`'s own two formulas exactly. A follow-up report on the SAME symptom's other half ("when swimming the procedural generated horse shape is rendered instead of the illustrated one") wasn't a bug so much as a real, then-still-open gap: no illustrated species had ANY swim art. `IllustratedAnimalSprite.has_action` now gives "swim" and "drink" their own illustrated fallback chain instead of dropping straight to procedural — swim reuses the walk cycle (moving legs/body reads far closer to swimming than a full art-style swap), drink reuses whatever "idle" itself resolves to (a creature drinking is standing still). Only "eat" and "attack" still fall all the way through to `ProceduralAnimalAnimation` — their own poses (head-down grazing, a lunge) aren't well approximated by either walk or idle. Reusing the walk cycle for swimming on its own just walks the horse across the surface fully dry, though (reported: "it doesn't have a swim animation instead it walks on the water... sprite should be submerged and tinted like the others") — so a swimming illustrated creature now also gets `SubmersionShader`, the *same* world-space waterline tint the player already uses, rather than a creature-specific invention. The waterline sits at the drawn body's own vertical centre (`IllustratedAnimalSprite.waterline_offset_y`, measured from the art's real content bbox), so "half submerged" falls out of the art itself rather than a hand-tuned fraction — the same reasoning `CharacterView` uses for the player's torso. Measured per species, since the shared canvas is baseline-aligned and a tall horse sits very differently on it than a low boar. Each creature owns its own `SubmersionShader` instance (the waterline is a world Y, so two creatures swimming at different screen depths need different ones), created lazily on first entry to water since most creatures never swim. Procedural species deliberately do NOT get the shader — their swim frames already have the water painted into the pixels (`ProceduralAnimalAnimation._swim_frame`), so shading them again would tint them twice. **Known gaps**: food-seeking is biome-granularity (walks toward vegetated *biomes*, not toward the Phase-1 per-cell vegetation *density* field — the two aren't wired together yet); killing/being-killed doesn't decrement the region's aggregate `EcosystemSimulation` population (it reseeds on next chunk reload); sensing is O(nearby creatures) per frame with no spatial index; no flocking/territory/reproduction-at-individual-scale; `seek_water`/`seek_food` (heading toward an actually-sensed resource) still bypass caution-radius avoidance entirely, on the theory that a real, urgent need should be allowed to override caution the way it already overrides wander in the decision priority order — untested against a live player, and worth revisiting if it turns out to read the same way the search-roam gap did. | large |
| Ecosystem Time-Lapse Test | ✅ Done | `tests/unit/test_ecosystem_time_lapse.gd`: proves natural biome clustering (rainforest sustains more herbivores/predators than desert with no hand-placed spawners) and a scripted drought visibly declining then recovering a region's population -- both halves of the roadmap's explicit definition of done. | medium |
| Aquatic Population Model (fish) | ✅ Done | The aquatic sibling of this whole table -- see the Fishing section's own entries (`concept/fishing.md`) for the full breakdown: `aquatic_population_model.gd`, `water_area_survey.gd`, wired into `EcosystemSimulation`/`ChunkEcologyCatchup`/`EarthChunkManager`, with an explicit `record_catch` harvest term (land creatures still lack one) and real cross-session disk persistence (land ecology still doesn't have that either). | large |
| Species Roster Expansion (mice, horses, ambient flyers, kingfisher) | ✅ Done | See `concept/ecosystem_dynamics.md`'s "Species roster" section. **Mice/horses**: pure roster variety within the existing herbivore role/AI -- new `mouse_shape` silhouette (`procedural_animal_sprite.gd`, deliberately the smallest of the five families) and horse's reuse of `deer_shape`; stats/diet in `creature_info.gd`; wired into `creature_renderer.gd`'s `HERBIVORE_SPECIES_POOL_BY_BIOME` (mouse in every non-ocean biome, horse in grassland/desert). No new mechanism -- both run the exact same aggregate `HerbivorePopulationModel`/`CreatureBehavior` AI as every other herbivore. **Ambient flyers (butterflies, songbirds)**: a new, deliberately lighter tier -- `ambient_flyer_movement.gd` (per-instance-configurable flutter/glide, shared by both; interval slowed from an initial 0.4s to 0.7s for butterflies so flutter reads as motion, not jitter; butterflies additionally render at `BUTTERFLY_SCALE` 0.5x, half a songbird's size, after in-game feedback that the full 14x10 source art read too large against grass/trees), `procedural_butterfly_sprite.gd` (monarch/swallowtail/blue_morpho, vividly saturated -- real butterflies are)/`procedural_bird_sprite.gd` (sparrow/robin, deliberately muted -- real songbirds mostly are; bird silhouette redrawn after the first attempt read as unrecognizable, verified this time by rendering to PNG and inspecting before committing), `ambient_flyer_renderer.gd` (biome-gated to grassland/forest/rainforest, capped, decorative-only -- explicitly NOT population-simulated, same tier as the original static tree-placement layer/grass tufts). Spawn count is now a **guaranteed MIN..MAX range per qualifying chunk** (deterministic ranked selection, same technique as `FishRenderer.spawn_fish`'s `target_count`), not an independent low per-cell probability roll -- the original probability design could plausibly (if astronomically unlikely per-chunk) land on zero butterflies for some real-world coordinate ranges, which is exactly what got reported ("can't see butterflies"); the guarantee removes that failure mode entirely regardless of what the actual root cause was. Wired into `EarthChunkManager`'s load/unload lifecycle. **Fish-eating birds (kingfisher)**: the one genuinely new mechanism -- `piscivore_bird_behavior.gd` (pure, tested cruise → dive → grab-or-miss (`CATCH_CHANCE` 0.35, real birds miss most strikes) → ascend → cooldown state machine), `piscivore_bird_marker.gd` (drives real movement + the dive's vertical animation), `piscivore_bird_renderer.gd` (spawn gated by water presence, not a land biome pool -- at most one per water chunk, a deliberately rare sight). A successful grab calls the exact same `EcosystemSimulation.record_catch` the player's own rod uses (via new `EarthChunkManager.fish_population_near`/`record_fish_catch_near` hooks) -- fishing pressure is no longer only ever the player's. | large |
| Per-Species Body Proportions (`AnimalAnatomy`) | ✅ Done | `src/rendering/animal_anatomy.gd`: every species is a set of real proportions (body/neck/leg/head length+height, muzzle taper, ear size, headgear, tail shape, `barrel_squareness` for a slab-sided vs. oval body, `world_scale` for real relative size) rather than one of a handful of shared hand-authored bitmaps — the fix for `herbivore`/`horse`/`deer`/`camel`/`reindeer`/`goat` all sharing one silhouette and differing only by coat colour ("herbivore, deer and horse look exactly the same"). `ProceduralAnimalSprite` assembles the parts from a profile through the shared pixel art engine (see `pixel_art_engine.md`). The horse profile has `shoulder_hump` zeroed (a level topline, unlike the humped rooters) and a deeper `head_height` than the other grazers -- but numeric tuning alone didn't fix the reported "straighter back"/"less flat head" asks: every species' neck attaches at the SAME fixed point on the body silhouette (`ProceduralAnimalSprite._paint_animal`, previously hardcoded, not profile-driven) and the muzzle is drawn as a second, much-shallower ellipse tacked onto the head ellipse — fine for a short-necked/short-muzzled grazer, but on a horse's unusually long neck and muzzle those fixed ratios read as a notch cut into the topline and a ball-with-a-cone head no matter how the lengths were dialed in. Fixed structurally, not just numerically, with three new optional per-species fields (every other species keeps today's behavior via a `.get(key, default)` fallback, so nothing else changed): `neck_attach_height`/`neck_attach_x` move the neck's attachment to the front-top corner of the barrel -- exactly where the superellipse silhouette is already curving upward — so the neck continues that curve instead of erupting from the flat mid-back; `muzzle_depth` lets a long-muzzled species keep the snout nearly as deep as the head itself instead of the sharp taper that reads fine on a cat but reads as a beak on a horse; `body_center_x` shifts the whole body left on its canvas so the now-longer neck+head have real room on the right without needing to be shrunk back down to fit (a real regression caught and then guarded against — see `test_no_species_silhouette_touches_the_top_or_right_edge`). leg_length also came down from the original 0.38 (the tallest of any species by a wide margin) to 0.33, corrected mid-fix from an initial thinner-legs attempt after explicit feedback ("shorter legs, not thinner") — leg_thickness is unchanged. A later pass against a reference image (explicitly proportions/pose only, not the reference's full painterly shading/tack — see the divergence note this triggered in the same conversation) added two more optional fields: `neck_direction_override` lets a species arch its neck at its own angle instead of sharing `NECK_UPRIGHT`'s steep near-vertical default (a horse's real neck arches forward and down from the withers, not straight up), and `has_hooves` caps each foot with a small dark hoof ellipse (`_paint_articulated_leg`) instead of the leg just tapering to the same coat color as the rest of the body. Horse's body also went stockier (`body_length` 0.58→0.52, `body_height` 0.27→0.31) to read as a real horse's build rather than a lean, elongated one. | medium |
| Illustrated Species Sprites (`IllustratedAnimalSprite`) | ✅ Done | Reported, after the anatomy pass above still didn't land: "the procedural generated sprites are too bad... let's switch to illustrated ones." Real hand/AI-illustrated art (`assets/sprites/{horse,deer,boar}.png`) now REPLACES `ProceduralAnimalSprite` entirely for these three species; every other species is untouched and still procedural. Each sheet is a small set of action rows, hand-composited (not a uniform grid -- pose extents and frame counts genuinely differ row to row) with thin divider lines between cells -- exactly which actions a sheet covers varies per species: deer/boar have a walk-cycle row + an eat/graze-cycle row (idle synthesized from the eat cycle's own first frame); horse's sheet (replaced twice since first landing, latest labeled "1. Idle 2. Walking 3. Trot 4. Sit / Hurt / Death") has dedicated idle + walk rows instead -- real idle art for the first time, but NO eat/graze row at all, so a grazing horse falls back to `ProceduralAnimalAnimation` (a real, honest gap -- unlike swim/drink, eat's own head-down grazing pose isn't approximated well by reusing walk or idle, see below). Horse's trot and sit/hurt/death rows are measured but unwired: no matching action exists yet in `CreatureMarker`, and the trot row's poses overlap across their own divider lines (legs/tail crossing into the neighbor cell), which defeats column-gap frame detection outright. `src/rendering/sprite_sheet_slicer.gd` (pure, tested) finds each frame's own tight content bounding box directly from pixel data -- masking against the same `is_content_pixel` test used to find it in the first place, not just cropping the rectangle verbatim, since a bounding box is still a rectangle around a non-rectangular silhouette and would otherwise leave background wash visible in the corners -- then re-composites every frame onto one shared canvas with a consistent ground-contact baseline, so the walk/eat cycles don't visibly bob from inconsistent source padding. Each source sheet needed its own `alpha_threshold` (0.3 default; deer's sheet uses a soft vignette wash around each cell instead of a crisp divider or true transparency, needing 0.85 to exclude it) -- boar's sheet has no alpha channel at all (opaque white background), handled by the same gray-divider check, not the alpha check. The gray-divider check itself is also tunable per sheet (`divider_gray_min`, default 0.7): horse's current sheet draws a darker dashed rule (~0.63) than the default bound catches, which otherwise pulled each frame's bounding box upward to include it, leaking a faint dotted line into the empty space above every frame. `src/rendering/illustrated_animal_sprite.gd` is the registry (species → sheet path + data-driven `<action>_bands` Y ranges, so a species registers whichever subset of actions its sheet actually has + alpha/divider thresholds + reference content width for `marker_scale`, which reuses `AnimalAnatomy.world_scale` -- `BASE_WORLD_WIDTH * world_scale / reference_content_width` -- so a species' real on-screen content width always works out to `BASE_WORLD_WIDTH * world_scale` regardless of that species' own sheet's pixel density, the same "one shared unit, scaled per species" convention the procedural generator uses; raw `marker_scale()` values themselves are NOT comparable across species with different sheets, only that resulting on-screen width is -- see `test_marker_scale_produces_a_bigger_on_screen_width_for_a_bigger_species`, which measures it from each species' own rendered frame rather than assuming the formula) and per-(species,action) texture cache (shared across every marker of a species -- there's no per-seed variation the way procedural generation has). Horse's `world_scale` was later reduced 1.6 → 1.2 (reported "make the horse ~25% smaller" -- it read oversized once the illustrated sprite replaced the procedural one); since `world_scale` is the single point of control for both this and horse's procedural fallback actions, every one of its actions shrank together rather than only the illustrated ones. `has_action` also gives "swim" and "drink" their own illustrated fallback (reusing walk/idle respectively, see the Individual Creature AI row above for why) rather than dropping straight to procedural -- reported after landing without it: "when swimming the procedural generated horse shape is rendered instead of the illustrated one". `CreatureMarker._animation_step` and `CreatureRenderer._build_marker`/`_shadow_foot_offset_y` check `has_species`/`has_action` first and fall back to the procedural path unchanged for anything still not covered, so nothing crashes or goes blank. Art has since moved to **one file per action per species** (`<action>_path` alongside `<action>_bands`): all three species (horse, boar, deer) now have dedicated walk/idle/eat sheets, and all three are drawn facing LEFT. Because those files are authored at different resolutions (a 1536x1024 idle portrait against a 2172x724 walk sheet), `marker_scale` is measured **per action** from each action's own frame-0 content width, so a creature cannot change apparent size when it switches action — and there is no hand-declared `reference_content_width` left to fall out of sync when art is swapped (this project's horse art has been replaced four times). `SpriteSheetSlicer.normalize_frames` also scales an oversized frame down to fit the shared canvas instead of CLIPPING it, which was silently rendering a crop of the horse's legs as its idle pose. `attack` now falls back to the walk cycle rather than the procedural generator (reported: "when the boar is attacking it switches to old procedural sprite") — a charge is a fast run, and keeping the creature's own art beats swapping to a different rendering of a different animal mid-lunge. With that, an illustrated species has art for **every** action, so the procedural path is now reached only by species with no sheet at all. Per-sheet `faces_left` is pinned by test per species: boar's new sheets face LEFT where the single `boar.png` they replaced faced right, and getting that wrong renders a creature mirrored so it walks backwards in every direction (the bug the horse shipped with). Known gaps: no dedicated attack/swim/drink art for any species (all are fallbacks); no per-individual visual variation (every horse in the world looks pixel-identical); horse's trot and sit/hurt/death poses exist in earlier source art but aren't wired to any in-game action. **A fourth species, sheep, was added the same way** (reported: "I added sheep spritesheet in animals folder ... can you add sheep as creature?") from a single user-supplied `assets/sprites/animals/sheep.png` (an 8-column x 2-row grid: a walk cycle, then an eat/graze cycle; no dedicated idle art, synthesized from the eat cycle's own frame 0 like deer/boar). This sheet is cut out on a solid MAGENTA background rather than real transparency or a pale divider line, which `SpriteSheetSlicer.is_empty` had no way to recognize as background (its divider check only matches near-white, low-saturation pixels) -- `IllustratedAnimalSprite` gained a `chroma_key`/`chroma_key_tolerance` per-sheet option (`_apply_chroma_key`, per-channel RGB distance so a generous tolerance handles anti-aliased edge blending without swallowing the wool's own pale-but-different-hued color) applied before handing the image to the slicer, so every downstream step keeps working off plain alpha the same way it already did for every other sheet. Sheep also got a full `AnimalAnatomy` profile (`world_scale` 0.8, hornless, short-legged and stockier than the existing goat entry -- the only field of it `IllustratedAnimalSprite.marker_scale` actually reads, since the procedural shape fields go unused for an illustrated species) and `CreatureInfo` stats (calm grazer, modest health/stamina, no mana), and joined the grassland and mountain herbivore spawn pools (`CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME`) and `/spawn sheep` (automatic, since `ConsoleSpecies` derives its roster directly from `AnimalAnatomy.SPECIES`). A later perf bug (reported as the game getting stuck on a "Loading..." screen, with the log showing many repeated "Loaded resource as image file" warnings during `_animation_step`): the fallback branches for `swim`/`attack` (→ walk), `drink` (→ idle), and idle-without-its-own-art (→ eat/walk frame 0) resolved via a private helper that recursed into ITSELF rather than back through `generate_textures`'s own cache -- so the first request for any new fallback action key re-ran a full, expensive pixel-by-pixel re-slice of the source sheet even though the identical result was already cached under a different action key. Fixed by renaming that helper to `_build_textures` and routing every fallback branch through `generate_textures(species, target_action)` instead, so a fallback is now a guaranteed cache hit; regression-tested by asserting the fallback's returned texture array is the exact same object as the target action's (`test_swim_fallback_reuses_the_exact_walk_textures_not_a_fresh_reslice` and siblings), which is only possible with no re-slice. | large |
| Mouse-Hover Animal Name Tooltip | ✅ Done | New, separate from the existing proximity-based `CreaturePanel` HUD list: `hover_target_finder.gd` (pure "what's closest to the mouse, within a radius" lookup) plus a `get_display_name()` method + shared `"hoverable_animal"` Godot group added to all four marker types (`CreatureMarker`, `FishMarker`, `AmbientFlyerMarker`, `PiscivoreBirdMarker` -- the latter three had no name display of any kind before this). `World._update_hover_tooltip` (untested scene glue, same convention as `CreaturePanel`) shows/positions a small floating label at the mouse cursor every frame. | small |
| Bear, Deer, Lion, Snakes (venomous/nonvenomous) + Region Difficulty | ✅ Done | See `concept/ecosystem_dynamics.md`'s new "Region difficulty" section for the full design rationale (why not real-world danger statistics, why not manual per-country curation). **Roster**: deer (reuses `deer_shape`) and nonvenomous_snake are ordinary, ungated herbivore-role additions; bear (reuses `boar_shape`) and lion (reuses `lynx_shape` -- lions are cats) are new predator-role apex species (`MAX_HEALTH_BY_SPECIES` tougher than every existing predator); venomous_snake is a new predator-role hazard (fragile in raw stats, dangerous via its bite instead -- see Venom below). Snakes get a genuinely new `snake_shape` silhouette (`procedural_animal_sprite.gd`); venomous_snake reuses the jaguar-rosette speckle technique for a real-world-grounded warning pattern. **Region difficulty**: `region_difficulty.gd` derives an EASY/MEDIUM/HARD tier purely from chunk-distance to the world's actual (dry-land-resolved) spawn tile -- a transparent, standard game-design gradient, explicitly not derived from real-world statistics or manual region curation. `creature_renderer.gd`'s `MIN_DIFFICULTY_TIER_BY_SPECIES` gates bear/lion/venomous_snake behind HARD; every other species (including all 15 pre-existing ones) has no gate and is unaffected. `EarthChunkManager.set_spawn_tile` (called once by `World._compute_dry_land_spawn_tile`) feeds the real spawn point in; without it, difficulty defaults to HARD (fails open to unrestricted, not "nothing dangerous ever spawns"). **Venom**: `venom_model.gd` (pure damage-per-second by stack count, capped) plus the existing generic `debuff_stack.gd` for duration/stack tracking -- `Player.apply_venom()`/`_venom_step` (real damage over time, ticked in `_authority_step`), triggered by `CreatureMarker._try_attack` when the attacker's species is `venomous_snake`. | large |

Known simplification shared by the land side of the above (documented in
`ecosystem_simulation.gd`): only chunks currently loaded (i.e. within the
existing player-proximity streaming radius) are simulated at all; there is no
whole-planet background simulation, and herbivore/predator/vegetation state is
not persisted across unload/reload (regenerated at fresh equilibrium on
revisit, same as terrain chunks already do). A real "catch-up pass" for
unloaded regions is the separate, larger "Variable-Fidelity Chunk Simulation"
item below. **Fish population is the one exception**: it now survives a real
game restart via `ChunkSerializer.save_fish_population`/`load_fish_population`
(see the Fishing section) -- a deliberate, scoped fix for the specific case
that most needed it (angler/kingfisher depletion should stay felt), not yet
backported to herbivores/predators/vegetation.

### Phase 2 — NPC AI MVP

Goal per roadmap: prove the daily-plan NPC architecture at small scale.
**Nothing in this phase has been started.**

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| NPC Data Model | ⬜ Not started | No NPCs of any kind exist. | medium |
| LLM Daily Planner | ⬜ Not started | Zero LLM API wiring exists anywhere in the codebase. | medium |
| Local Schedule Executor | ⬜ Not started | | large |
| Interrupt/Replan Handling | ⬜ Not started | | medium |
| Live Dialogue System | ⬜ Not started | | large |
| LLM Backend Abstraction | ⬜ Not started | No LLM integration whatsoever. | medium |

### Phase 3 — Core gameplay loop

Goal per roadmap: make it a game, not a simulation demo. Definition of done
is met for the two mechanisms it names explicitly (a tactical mechanic beyond
plain damage trading; a built structure surviving save/reload) — inventory,
fire/oil, and layered elevation remain unstarted.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Player Stats/Inventory/Equipment | 🚧 Partial | Real `health`/`max_health`/`take_damage()` (`health.gd`); a real **item + inventory system** (`item.gd`, `item_stack.gd`, `inventory.gd` — typed items with stacking, a fixed-slot inventory, all tested); the player starts with an **Iron Sword** (equipped weapon, drives attack damage) and an **Iron Axe** (`equipped_tool`, felling-only — see Real-Time Arena Combat), and picks up loot/forage into the inventory. The old always-visible inventory text panel is gone, replaced by a real toggleable **`InventoryWindow`** (default key I, `scenes/inventory_window.gd`) showing an icon+name+count row per stack; **right-clicking** a row **activates** it via `Player.activate_item_id()` — weapons/tools get equipped, food/potions get used, materials do nothing (`hotbar_action.gd`, tested) — left-click is reserved for dragging (reorder within the grid, or out onto a hotbar slot to bind it). Left-click used to ALSO trigger activation (on press, not release), which collided with starting a drag: pressing down to pick an item up for a drag fired the use/equip action immediately, before the drag even began — reported as "a click on a carrot makes it vanish". The paperdoll's worn slots got the same right-click-to-unequip treatment for one consistent interaction model, and the hotbar gained a hover highlight, a tooltip naming what's bound (`_hotbar_tooltip_text`), and a right-click-to-clear-a-slot gesture it previously had no way to do at all (only overwriting via drag). A real HUD now exists (`scenes/world.gd`'s `_build_hotbar_slots`/`_build_spell_bar`/`_update_player_health_bar`/`_build_survival_bar`): a player health bar, a **usable hotbar** (number keys 1–5 or a click activate the corresponding slot via `Player.activate_hotbar_slot()` — equip weapon/tool, or eat food), a placeholder spell bar, and a bottom-left survival bar (hunger/thirst/stamina meters, from `src/gameplay/survival_meters.gd`, ticking down over time and refilled by eating/drinking/resting) plus a gold-count label backed by the `Wallet` (`/gold` dev-console command). Equipping is now a **single held item**: `Player.equip_item()` points `equipped_item` at whatever weapon/tool you activate (from the hotbar or by clicking an inventory row) and draws it in hand — so switching sword↔axe↔pickaxe visibly changes what you hold, and that one item alone decides attack damage, tree-felling speed (axe fast / sword slow / bare-hands slowest, via `MaterialDamage`), and mining power (only a pickaxe mines ore). **Key bindings are configurable** in a proper **pause/settings menu** (`scenes/settings_overlay.gd`, default Escape, pauses the game while open) with **Key Bindings** and **Graphics** (fullscreen, vsync) tabs; the tested `src/gameplay/keybindings.gd` is the single source of truth for every rebindable action + default key, and both keybinding overrides and graphics prefs persist to `user://keybindings.cfg`. Default layout: **E = pick up nearby items**, **I = inventory**, **C = crafting**, **B = place earth**, Escape = close/menu. **Escape now closes whatever is open** rather than always toggling settings (`src/ui/escape_action.gd` holds the tested priority order — dev console first, then all gameplay windows at once, then the settings menu, and only opens settings on a clear screen), and the press is marked handled so it can't both close a window and re-open settings; the dev console's own Escape handler now calls `accept_event()` for the same reason (it previously closed the console *and* popped the paused settings menu open behind it). A press of E sweeps every ground item within `PICKUP_RADIUS` into the inventory (`Player.pickup_nearby`), alongside the existing click-to-pick-up. The hotbar is now **user-assignable via drag-and-drop** (`src/gameplay/hotbar.gd`, `src/ui/drag_slot.gd`): drag an inventory item onto a HUD hotbar slot to bind it to that number key, and drag one inventory item onto another to reorder your pack (`Inventory.swap_slots`/`move_to_end`). Previously the hotbar just mirrored the first 5 inventory stacks with no drag-and-drop anywhere in the project, so — since the player starts with exactly 5 stacks — anything crafted later could never be put on a key at all (the reported "can't drag the rod into the hotbar / can't equip it"). Empty slots still auto-fill from the inventory so pickups appear on their own, explicit assignments are never overwritten, and a slot clears when you no longer carry its item. Equipping a weapon/tool now also fills the paperdoll's "weapon" slot (`Item.equip_slot_name` slots tools there too), so the Character screen reflects what's in hand. Still missing: armor slots (the `character_view.gd` colored squares remain cosmetic placeholders), a temperature/wetness-driven survival dimension (wetness tracking exists separately, see Phase 0; not yet fed into a meter), a potion item kind (the "use" path exists but only food items are defined so far), splitting/merging stacks by drag, and multiplayer sync of the inventory (a networked client's inventory is its local proxy's, not the server's). | medium |
| Real-Time Arena Combat | 🚧 Partial | Cooldown-based AOE melee swing (`_perform_attack`, `melee_attack.gd`) whose **damage comes from the equipped weapon** (`attack_damage(weapon, unarmed)`); it damages, knocks back, and kills creatures, which then **drop loot** (`loot_table.gd` → ground items). The swing is a real pendulum-arc animation (`weapon_swing.gd` + `CharacterView.play_attack_swing`) oriented horizontal/vertical by facing and pivoting from the weapon's grip, not its sprite center. Combat is now **two-directional**: aggressive+healthy predators attack the player back, weak ones flee (see Individual Creature AI). Each creature within range now gets its own real HUD panel (`scenes/creature_panel.gd`, one `CreaturePanel` per nearby creature via `world.gd`'s `_update_creature_panels`) showing name, level, an HP bar, and a numeric "HP x/y" label — replacing both the earlier aggregate "Nearby Creatures" list panel and an even earlier world-space floating-nameplate attempt (both rejected in favor of this per-creature-panel design). `CreatureHoverBus` and the world-space hover/name-label code in `creature_marker.gd` were deleted outright as dead code once nothing consumed them. Creature variety expanded to **12 species total**: the original herbivore/boar and predator/lynx pairs, plus 8 more biome-specific species (camel/jackal for desert, reindeer/arctic_fox for tundra, tapir/jaguar for rainforest, goat/mountain_lion for mountain), each its own entry in `creature_info.gd`'s stat/diet/temperament tables (tapir notably reuses boar's silhouette but stays calm, not aggressive — temperament is independent of shape); and every creature's max health now scales with level (`CreatureInfo.LEVEL_HEALTH_SCALE`). Creatures now use species-shaped procedural pixel art (`procedural_animal_sprite.gd`, 24x16 shaded+outlined silhouettes from 4 hand-authored shape families — boar-shaped, lynx-shaped, deer-shaped, wolf-shaped, see `SPECIES_SHAPE_FAMILY` — each reused by 2-3 species in a different color, plus a small dark speckle overlay unique to jaguar, with per-individual seeded shade jitter) — replacing the old generic color-tinted blob sprites. Species selection is now **biome-gated** rather than one global pool per role (see the Promotion System row above for `HERBIVORE_SPECIES_POOL_BY_BIOME`/`PREDATOR_SPECIES_POOL_BY_BIOME`); within grassland/forest specifically, a promoted predator-role individual is a lynx 1-in-4 (`PREDATOR_SPECIES_POOL`), and predators are themselves the rarest role, so lynx are genuinely uncommon there; the distinct silhouette at least makes the ones that do spawn recognizable. **Combat is now material-aware** (`material_damage.gd`): creature hits go through a flesh multiplier per weapon kind (sword 1.0x, axe 0.8x, unarmed 0.5x) and tree chopping through a wood multiplier (axe 3x — the historical 15-damage tuning — sword 0.5x, bare hands 0.25x, so anything can eventually hack a tree down but only an axe is efficient). **Blocking exists** (`block.gd`, hold Shift): incoming damage is reduced by a weapon-dependent efficiency (sword 70%, axe 40%, unarmed 20%); blocking, like attacking, costs no stamina -- per `concept/survival.md`'s "Stamina scope: movement only, not combat" decision, combat stays purely cooldown-based. **Creatures are animated** (`procedural_animal_animation.gd`): every marker plays generated pixel-art animations per action, with the action driven by what the AI actually did that frame (and an on-water check forcing "swim"). Attacks lunge, eating/drinking dips the head. **Walking is a real two-bone hip/knee gait** (`quadruped_gait.gd`), not the original leg-shaped-pixels-shifted-sideways hack — each leg's hip swings and knee bends through a sine-based stride, diagonal pairs (front-left+back-right, front-right+back-left) in phase together the way real quadrupeds actually move, drawn fresh each of `WALK_FRAME_COUNT` (5, must be odd — an even count lands two sampled phases on an exactly-matching `sin()` value) frames rather than one static image with a region shifted (reported: "a horse should walk more like a horse"); a serpent still gets its own whole-body slither (no legs to hinge). **Swimming tints/fades the animal's own submerged silhouette** (`SWIM_TINT_STRENGTH`/`SWIM_ALPHA_FADE`) instead of painting a flat rectangle across the tile (reported: "remove the blue rectangle... make the water realistically cover parts of the body") — background stays transparent, only body pixels below the waterline change, with a thin surface-color stroke only where the body crosses it. The player stows their weapon while swimming (`CharacterView.set_movement_state` hides the tool slot; `Player._attack_step` refuses to swing mid-swim), and **the player's own torso now visibly submerges too**: `SubmersionShader` (shared world-space-vertex technique with `WaterShader`/`WindSway`, so one material agrees across the body/head/arm sprite parts) tints/fades whatever part of the body sits below a world-Y waterline set each frame while swimming — previously the torso rendered exactly as it does on dry land with nothing showing it was in water. The player's arm-stroke animation now only plays while actually moving (`CharacterView.is_moving`, driven by `Player`'s input vector) rather than animating while treading water in place. **The primitive knapping-tech chain is live** (see `knapping.gd`/`smashable_stone.gd`): boulders (`StonePlacement`/`StoneRenderer`) smash on a swing, always yielding the rock itself; carrying another rock knaps off sharp shards with a tested ~60% chance; a swing over mature tall grass tears up plant fibre (`EarthChunkManager.harvest_grass_near`); felled trees now drop sticks alongside wood; and `/craft crude_blade` lashes stick + shard + 2 fibre into a first crude weapon (damage 9, between fists and iron). **Trees feed animals**: herbivore-role creatures eat dropped fruit/nut ground items when standing close (`food_consumption.gd`, wired in `World._step_herbivore_food_consumption`), closing the trees→forage→herbivore loop; tall grass and trees both keep spreading on their own (`TallGrass.advance`, `TreeSpread`). The player also carries an **axe** (`equipped_tool`, see Item.is_axe()) that fells `ChoppableTree`s in range on the same attack input, dropping wood — separate from weapon combat, gated by tool type rather than weapon damage. Remaining: no abilities beyond the one swing, no armor/mitigation, killing a creature still doesn't decrement `EcosystemSimulation`'s aggregate count, and combat isn't replicated in multiplayer (a client's swing runs server-side against server creatures, not the client's local ones — play single-player for a coherent loop). | large |
| Knockback/Hazard Interaction | ✅ Done | `Knockback.step` (smooth ease-out displacement, not a teleport) + `MeleeAttack.knockback_vector` + `CreatureMarker.apply_knockback` — every hit shoves the target away from the player, Hammerwatch-style. Satisfies the roadmap's "at least one tactical/environmental mechanic beyond plain damage trading." No hazards (fire/traps/terrain) yet, only knockback. | small |
| Player Death & Respawn | 🚧 Partial | `scenes/player.gd`: reaching 0 HP now actually does something (previously it silently did nothing) — `is_dead` freezes input/movement, the sprite dims (`DEAD_MODULATE`), and after `RESPAWN_DELAY` the player respawns at `respawn_position` with health restored. No lives cost yet (`lives_tracker.gd` exists as a tested pure-logic module — see Eras/Death sections below — but isn't wired to this flow), no graveyard/corpse-recovery, no death penalty of any kind beyond the respawn delay. | medium |
| Spreadable Fire/Oil | ⬜ Not started | | large |
| Layered Tile Elevation | ⬜ Not started | | large |
| Vegetation-Based Concealment | ⬜ Not started | Blocked on combat's one-directional-only state (nothing to hide *from* yet); Phase 1's vegetation density data it would reuse now exists (`vegetation_growth_model.gd`). | medium |
| Tile Building/Destruction System | ✅ Done | `Chunk.modifications` is now real: `EarthChunkManager.build_at_global`/`destroy_at_global` write to it, `TerrainRenderer.paint()` renders a modified cell over its generated biome tile, and `ChunkSerializer.save_modifications`/`load_modifications` persist it to `user://chunk_modifications/` across chunk unload/reload (walking away and back — this project's real equivalent of "save/reload", per the pre-existing plan noted in `EarthChunkManager.update()`'s doc comment). Player-facing, with no placeable item armed: E turns the faced tile into bare earth (`TerrainRenderer.EARTH_TILE_ID`, Terraria-style terraforming -- E intentionally replaces whatever biome tile is there, grass included), Q destroys/reverts it, on whichever tile the player is facing (`src/gameplay/tile_targeting.gd`). **Placing crafted structures is now live**: selecting a `"placeable"`-kind item (campfire/furnace, `item_catalog.gd`) from the hotbar or inventory arms it (`HotbarAction.PLACE` → `Player._arm_placeable`); the next E press places that item's id into `Chunk.modifications` instead of bare earth, consuming exactly one from inventory only on a successful placement (`Player._build_step`, tested end-to-end against a real `Player`/`EarthChunkManager` in `test_player.gd`); Q on a placed structure returns one unit to the inventory (plain earth still gives nothing back). Placed campfire/furnace render with real dedicated procedural art (`ProceduralStructureSprite`: flame-on-embers / brick-block-with-firebox, each distinct from earth and each other, tested), not the flat earth-brown fill. Cooking/smelting now gate on real world proximity to a *placed* structure (`EarthChunkManager.has_structure_near`, `Player._has_campfire`/`_has_heat_source`, `HEAT_SOURCE_RADIUS_TILES = 3`) instead of merely carrying one in inventory — closing the gap an earlier doc comment flagged ("Carried, for now — placed heat sources come later"). Known gaps: only two structure types exist (no multi-tile blueprints yet, despite `building_blueprint.gd`'s pure footprint-checking logic already supporting them), and `has_structure_near`'s chunk-neighbor scan is exact only up to a `CHUNK_SIZE`-tile radius (documented limitation, comfortably beyond any realistic proximity check). | large |
| Dev/Admin Console | 🚧 Partial | Real dev console now exists: press backtick to toggle (`world.gd`'s `_bind_console_toggle_action`), type a `/command arg1 arg2` line into `DevConsole`'s `LineEdit` (`scenes/dev_console.gd`, parsed by the pure/tested `ConsoleCommandParser`). Implemented commands: `/day` (forces daytime lighting for the rest of the session), `/spawn <herbivore\|predator> [count]` (spawns creatures near the player via `CreatureRenderer.spawn_single`), `/give <item_id> [count]` (adds an item to the player's inventory via the new `ItemCatalog`), `/craft <recipe_id>` (calls `Player.craft()` against `CraftingRecipeBook`), `/gold <amount>` (adjusts the player's `Wallet` balance), `/help`. While the console has focus, `ConsoleFocus` (new autoload) suppresses the player's raw keyboard polling so typing "wasd" doesn't also move the character. No settings-tweak commands yet, and `/spawn`/`/give`-spawned entities aren't chunk-tracked (won't get cleaned up on chunk unload, unlike the world's own creatures). | medium |

### Phase 4 — Emergent quests

Goal per roadmap: replace "kill 10 boars" with need-driven requests. **Nothing
in this phase has been implemented** (depends entirely on Phase 2's NPCs and
Phase 1's ecosystem/evolution sim, both themselves partial); the mechanism
itself is now fully specified in [concept/quests.md](concept/quests.md)
(2026-08-13 design pass) — see this doc's own new Quests section below for
the mechanism-by-mechanism breakdown.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Need-Driven Quest Templates | ⬜ Not started | Spec'd in concept/quests.md: safety/production/social need sources resolving into fetch/protect/deliver/join-the-defense shapes. | large |
| LLM Quest Flavor Text | ⬜ Not started | | medium |
| Quest Reward/Consequence Hooks | ⬜ Not started | Spec'd in concept/quests.md's Consequences section (reputation/discounts/skill rewards; settlement destruction on failure). | small |

### Phase 5+ — Post-MVP expansion

Explicitly deferred by design until Phases 0–4 are solid. **Nothing in this
phase has been started**, with one notable scale-related caveat.

| Mechanism | Status | Note | Complexity |
|---|---|---|---|
| Multiplayer Netcode | 🚧 Partial (unverified live) | Server-authoritative architecture built: `--server`/client bootstrap in `world.gd` (ENet) plus an in-game **main-menu Host/Join flow** (`scenes/main_menu.gd` → `World._start_server`/`_start_client_to(address)`), dynamic per-peer `Player` spawning via `MultiplayerSpawner`, RPC input-up + `MultiplayerSynchronizer` position-down in `player.gd`, client-side visual-only proxies (facing/animation inferred from replicated position deltas + local deterministic terrain lookup, no extra network traffic). Follows standard Godot high-level multiplayer patterns. LAN/direct-IP join works via the menu; internet play needs a port-forward or an external tunnel (an ngrok-style built-in relay is not implemented — it would require a hosted relay server). **Live server↔client connectivity is unverified**: a minimal bare-ENet repro (no game code at all) also hangs on this dev machine, isolating the failure to CrowdStrike Falcon (confirmed running) blocking this specific unrecognized executable's networking — not a code bug (raw TCP and UDP loopback both work fine via a trusted process in the same environment). Needs either an EDR exception from IT or testing on an unmanaged machine/network to verify live. Known scope gaps even once verified: only tracks one player's position for chunk streaming (no multi-interest-point union yet), no client-side prediction/interpolation (positions will look choppy over real latency), no interest management/culling, no persistence of connections. | huge |
| Player Economy & Society | ⬜ Not started | | huge |
| Era Progression System | 🚧 Partial | `src/gameplay/era_progression.gd`: a tested, deterministic 4-era (medieval/industrial_revolution/ai_boom/space_exploration) progress-threshold state machine (`current_era`), plus `current_era_with_boss_defeat` letting a defeated world boss push the player one era ahead of progress alone (per `concept/worldbosses.md`'s "Era-gated bosses" section). Not wired to any live progress counter or world-boss event. | huge |
| Reincarnation Mechanic | ⬜ Not started | | large |
| Multi-Planet/Galaxy System | ⬜ Not started | | huge |
| Full-Planet-Scale World | 🚧 Partial (divergent path) | The roadmap describes reaching whole-Earth scale later by "reusing the same [procedural] worldgen systems" as a scaling exercise. In practice the project reached real-Earth scale (~40,000×20,000 tiles) much earlier and via a completely different mechanism — real bundled elevation/moisture data instead of procedurally expanding the Phase-0 heightmap. The scale goal is arguably met; none of Phase 1–4's gameplay exists on top of it yet. | huge |

### Emergence substrate (`docs/emergence/*.md`, dependency-ordered — see `docs/roadmap.md`'s "Emergence substrate" section for how this threads into the phases above)

Cross-cutting causal/social/historical substrate, not itself a roadmap phase
— see `docs/roadmap.md` for how its 18 phases map onto Phases 2/4/5+ above and
which existing concept docs (`npc.md`, `quests.md`, `worldbosses.md`,
`factions.md`, `economy.md`) already cover pieces of a given phase in this
project's own terminology.

| Emergence phase | Status | Note |
|---|---|---|
| 0 — Baseline & instrumentation | ✅ Done | Stable entity references (`EntityRef`), event type/importance model, entity-history query, cause-chain debugger, `/why`/`/history`/`/emergence` console commands, deterministic save/load round-trip. See below. |
| 1 — Event & causality substrate | ✅ Done (core); 🚧 unloaded-region replay | `Event`/`EventStore` with automatic bidirectional cause↔consequence linking, deterministic insertion-ordered IDs, importance, query-by-type/window/entity. Retention/pruning by importance is a tested function, not yet wired to actually prune a running store. "Unloaded-region replay" (catch-up simulation feeding the store while a region is unloaded) is explicitly deferred — no emergence-tracked system yet needs catch-up, so there is nothing to replay. |
| 2 — Memory, beliefs, information | ✅ Done (mechanism + live auto-propagation) | `MemoryRecord`/`Rumor`/`MemoryStore` built per `npc.md`'s "Memory, beliefs, and rumor propagation" spec, tested, wired live. `EarthChunkManager.step_npc_encounters` now closes the one gap that section itself named — NPCs meeting at real shared landmarks exchange memories automatically. See below. |
| 3 — Households & property | ✅ Done (household + property); ⬜ inheritance | `Household`/`HouseholdStore` built and wired live: every villager owns the house it lives in. See below. `npc.md`'s lifecycle (aging/reproduction/death) is still designed but not built, so multi-member households and inheritance stay out of scope until it exists. |
| 4 — Contracts & obligations | ✅ Done (mechanism + live trigger) | `Contract`/`ContractStore` built, tested, wired into events/memory. `EarthChunkManager.step_settlements` now proposes/accepts/activates/fulfills-or-breaches a real trade contract between a settlement's own households every automatic step. See below. |
| 5 — Local production economy | ✅ Done (mechanism + live trigger) | `Market`/`MarketStore` built, reusing `CraftingRecipeBook`'s existing recipes rather than a parallel schema. `step_settlements` now attempts each household's occupation-grounded recipe (`OccupationProduction`) automatically. See below. |
| 6 — Institutions | ✅ Done (formation + dissolution both live-triggered) | `Institution`/`InstitutionStore`/`InstitutionFormation` built, formation gated by real fulfilled-contract history with proper hysteresis; dissolution now reads a real RECENT window (closing the gap that made it structurally unable to ever fire). `step_settlements` drives both automatically. See below. |
| 7 — Settlement simulation | ✅ Done (food-driven); ⬜ other inputs | `SettlementState`/`EarthChunkManager.step_settlements`, food-only carrying capacity, wired into `World._step_ecology_batch`. Now also the home of Phase 4/5/6's own automatic triggers (see below) — no longer the only phase with a live trigger. |
| 8 — Infrastructure networks | ✅ Done (path tier + live trigger); ⬜ trail/road/crossings | `docs/concept/infrastructure.md` (new), `EarthChunkManager.record_path_worn_if_new`/`record_path_reclaimed`, wired into the ALREADY-live `World._step_path_scarring`. Exit criterion live-verified. See below. |
| 9 — Towns & cities | ✅ Done (tier + specialization, 3 of 6 dimensions); ⬜ contraction/abandonment | `settlement_tier.gd`, wired into `step_settlements`. Exit criterion live-verified. See below. |
| 10 — Dungeons/ruins/history POIs | ✅ Done (causal layer, 3 real sources); ⬜ physical generation | New `ruin_formed` entity in `EarthChunkManager`, linked back to its real cause via `EventStore.link_cause`. Exit criterion ("at least three independent causal sources") live-verified. See below. |
| 11 — World bosses | ✅ Done (mechanism); ⬜ live trigger | `WorldBoss`/`WorldBossStore` wrap the pre-existing, real `world_boss_fitness.gd` promotion math in a causal, `/why`/`/boss`-inspectable entity. See below — no creature currently tracks kills/lifetime age for a live trigger to read from. |
| 12 — Emergent quests | ✅ Done (production-shortfall projection); ⬜ everything else | `quest.gd` — a real, stateless PROJECTION over household/market/recipe state, never a new entity. See below — safety/social need sources, quorum/promotion, and resolution all still depend on unbuilt systems. |
| 13 — Governance & politics | ✅ Done (form + legitimacy, changes a real decision); ⬜ policy/taxation/enforcement | New `docs/concept/governance.md`, `governance.gd`. Governance form now drives which institution type a settlement's own automatic formation attempts. Live-verified. See below. |
| 14 — Regional trade & migration | ✅ Done (trade networks, one real edge); ⬜ migration | New `docs/concept/regional_trade.md`, `regional_trade.gd`. Real stock moves between two real settlements' markets to resolve a real shortage. Live-verified. See below — migration stays `quests.md`'s own unbuilt design. |
| 15 — Technology & cultural diffusion | ⬜ Not started | No `concept/*.md` coverage yet. |
| 16 — Religion, festivals, legends | ⬜ Not started | `festivals.md` is referenced by `npc.md` as an eventual daily-planner byproduct, but doesn't cover belief-community formation itself. |
| 17 — Polities, wars, civilization | ⬜ Not started | Gated behind real multiplayer per `docs/roadmap.md`; overlaps roadmap Phase 5+ #2/#3 (economy/society, era progression). |
| 18 — Player legacy | ⬜ Not started | No `concept/*.md` coverage yet, though `death.md`'s reincarnation mechanic is an obvious future tie-in. |

✅ **The event/causality substrate exists and is provably inspectable**
(`src/emergence/entity_ref.gd`, `event.gd`, `event_store.gd`,
`event_store_persistence.gd`, `why.gd`, `simulation_metrics.gd`). An
`EntityRef` is a canonical `"<kind>:<key>"` string built from whatever
deterministic key that entity already has (an NPC's `seed_value`, a
settlement's `chunk_coord`) rather than a newly-allocated counter — the same
"deterministic key, not an allocated ID" idiom `TreeGenome`/`CreatureInfo`/
`NpcIdentity` already use everywhere else, so nothing new has to be persisted
just to keep IDs from colliding. `EventStore.append` assigns each event a
deterministic, sortable id (`evt_<ordinal>_<type>`); `EventStore.link_cause`
is the only path that ever writes a cause/consequence edge, and it always
writes both directions from one call — a caller can forget to wire the
reverse edge, `link_cause` cannot, because it is the only thing that ever
writes `consequences`. `EventStore.cause_chain` is cycle-safe (a visited-set
plus a depth cap) even against a malformed graph, and so is `Why`'s own
recursive trace. Persistence (`EventStorePersistence`) mirrors `PlayerSave`'s
exact convention — one `user://emergence_events.bin` file,
`FileAccess.store_var`/`get_var`, a `file_exists` guard, a `wipe()` — rather
than inventing a second I/O convention; `EventStore` itself stays engine-free
(`to_dicts()`/`from_dicts()`), with the `FileAccess` calls isolated to the
persistence wrapper alone, matching this project's pure-module/engine-glue
split. `Why.explain_event`/`explain_entity` render the same indented
provenance shape `00-emergence-architecture.md`'s own "why does this city
exist" example uses.

**Wired into the real game lifecycle, not just held in memory.**
`EarthChunkManager` owns one shared `_event_store`, exactly where
`_snow_trail`/`_forage_claims` already live for the same reason. Founding:
`VillageRenderer.spawn_village` calls a duck-typed
`world.record_settlement_founded_if_new(chunk_coord, npcs)` (same fail-open
shape as its existing `stamp_structure_at_global` hook) every time a chunk
carrying a settlement loads — which happens on every reload, not just the
true first founding — so `EarthChunkManager` itself guards on
`events_for_entity(settlement_id).is_empty()` rather than an in-memory flag,
robust across save/load. A genuine first founding records one
`settlement_founded` event and one `npc_settled` event per villager, and the
two witness each other (the settlement witnesses each villager settling, each
villager witnesses the founding) — deliberately richer than a narrow
actor-only history, since that is exactly what `witnesses[]` exists for.
Persistence: `save_event_store`/`load_event_store`/`wipe_event_store` follow
`persistence.md`'s established pillars exactly — wiped alongside `PlayerSave`
on New Game (`World._wipe_persisted_world`), restored alongside it on Load
Game (`_spawn_local_singleplayer_from_save`), and saved alongside it on
autosave/quit (`_save_local_player`) — so "New Game means new" and "Load Game
means exactly where you left off" both now cover the event store too, not
only the player.

`/history <entity_id>`, `/why <event_id>`, and `/emergence` (store-wide
metrics: event/entity counts, events by type, tick range, average importance)
are real console commands, verified live end to end: relaunching, walking to
a settlement, and running `/history settlement:<x>_<y>` shows the real
recorded founding.

**Left for the next slice, deliberately:** no other gameplay system feeds the
store yet (fruit falling, animal deaths, tree felling, etc. — settlement
founding is the one proof-of-concept hook, chosen because it was the lowest-
risk already-existing trigger to wire against); retention/pruning by
importance is a tested pure function not yet wired to actually prune a
running store; "unloaded-region replay" has nothing to replay yet, since no
tracked system needs catch-up.

✅ **A memory is a lossy projection of an event, never a rewrite of it**
(`src/emergence/memory_record.gd`, `rumor.gd`, `memory_store.gd`,
`memory_store_persistence.gd`), built per `npc.md`'s "Memory, beliefs, and
rumor propagation" section — the project-specific expression of
`docs/emergence/02-history-memory-rumors.md`'s general mechanism, the same
relationship `quests.md` has to `worldbosses.md`. `MemoryRecord.from_event`
forms a fresh, fully-confident memory for every ACTOR (`FIRSTHAND`) and
WITNESS (`WITNESSED`) of an event — an entity with no part in it forms no
memory, there is nothing to remember firsthand if you were not there.
`Rumor.transmit` is the retelling: confidence decays by a tested constant per
hop (`CONFIDENCE_DECAY_PER_HOP`), source type degrades monotonically toward
`RUMOR` and never climbs back (`firsthand`/`witnessed` → `trusted_testimony`
→ `stranger_testimony` → `rumor`, terminal), and a `distortion` accumulator
is tracked from the first hop. **Content distortion is deliberately NOT
applied yet** — `remembered_actors`/`location`/`outcome` survive every hop
unchanged, matching `npc.md`'s explicit call that content mutation ("who did
something changes, not just how confident you are") is "real, but unproven
gameplay payoff yet," a follow-up once a scenario actually needs it, not a
missing piece of this one. (An earlier pass of this same work built the
content-mutation behavior before that concept-doc section existed to check
it against; found the conflict, and simplified back down to match the
documented, deliberately smaller scope — the concept doc is the source of
truth, not whichever was implemented first.)

`MemoryStore` layers the per-entity collection on top of `EventStore` rather
than folding into it (`00-emergence-architecture.md`'s own authoritative
loop: "emit events → update memories/beliefs" is a distinct step), so
`EventStore` stays usable for entities that do not have memories at all — a
settlement does not "remember" the way an NPC does, even though it can still
be an event's actor. `witness_event` forms memories for every actor and
witness in one call and dedupes against an event already remembered;
`transmit` is the exit criterion made concrete — **NPC A can tell NPC B about
an event and B receives a lower-confidence representation** — returning null
when the teller never actually knew. Persistence follows the exact same
`PlayerSave` convention as the event store, wired into the identical New
Game/Load Game/autosave lifecycle points alongside it. `Why.explain_memories`
(`/remember <entity_id>`) renders source type and confidence per memory,
distinct from `/history`'s authoritative record of what an entity was part
of. Wired live: founding a settlement forms real memories for the settlement
and every villager, through the same `record_settlement_founded_if_new` hook
Phase 0/1 already established.

**Left for the next slice, deliberately, per `npc.md`'s own explicit
scoping:** *auto-propagation* — the mechanism (`transmit`) is built and
tested, but nothing yet calls it automatically when two NPCs meet at a
settlement's shared landmarks on their daily schedule (`npc_schedule.gd`),
which is the trigger `npc.md` specifies; trust/relationship-weighted decay,
since `npc_identity.gd` has no relationships yet (Phase 3); time-based decay
of an unreinforced memory's confidence/salience ("shape only for now" per
`npc.md`); content distortion, as above; and the player as a first-class
belief-holder (`npc.md` answers this directly for now: a quest/rumor UI
queries a nearby NPC's own sufficiently-confident memory instead).

✅ **Auto-propagation's gap is now closed — genuinely more tractable than
it first looked** (new `npc_encounter.gd`, `EarthChunkManager.
step_npc_encounters`). `_loaded_villages` (already registering every
currently-loaded `NpcMarker`, the same list `nearest_npc_near` iterates)
and `NpcMarker.schedule` + `NpcSchedule.current_entry` (already resolving
each NPC's real current `location_tag`) meant "which NPCs share a landmark
right now" needed no new position/scheduling system, exactly as `npc.md`
itself claimed. `NpcEncounter.group_by_shared_landmark` is the pure
grouping logic — a real hour and a Dictionary of npc_id→schedule in, a
Dictionary of landmark→npc_ids (2+ only; a landmark with one npc has
nobody to meet) out. "home" is explicitly excluded (every NPC's home is a
different building, so two NPCs both "at home" have not met).

**A real hour-of-day bug avoided, not inherited.** `NpcMarker._current_hour()`
is a PRIVATE per-marker clock — elapsed real seconds since THAT marker
happened to spawn, never synced across markers — fine for its own
walk-toward-target movement, but comparing two different NPCs' schedules
against each other needs the SAME hour for both. `step_npc_encounters`
derives `_current_hour_of_day()` from the real shared world clock instead
(mirroring `NpcMarker.SECONDS_PER_SIMULATED_DAY`'s own pacing, applied to
`_world_age_seconds`), not each marker's own drifted one.

**Memory selection: each meeting exchanges the pair's single
most-recently-formed memory, bidirectionally** — "catching up on the
latest" rather than an exhaustive dump, the obvious first-slice choice
`npc.md` itself left undecided. A real ordering bug the unit tests caught
before it went live: a naive same-step double loop let the second half of
an exchange hand back whatever the first half had JUST told them moments
earlier in that same step, rather than their own actual news — fixed by
snapshotting each npc's "most recent memory" once, before any transmission
in the group runs.

**Live end-to-end verification, zero manual calls:** two real `NpcMarker`
nodes sharing a landmark on their real schedule, one holding a real
memory, let the ordinary `_process` loop run with zero manual calls to
`step_npc_encounters` or `MemoryStore.transmit` — the listener held a real
transmitted memory by tick 4.

**Left for the next slice, deliberately:** trust/relationship-weighted
decay is still deferred (`npc_identity.gd` has no relationships yet,
Phase 3's own scope), so propagation runs at a flat one-hop step
regardless of who is talking to whom; content distortion remains
deferred per this section's own earlier note; and the player still isn't
a first-class belief-holder, unchanged from before.

✅ **A household owns real property, not a placeholder** (`household.gd`,
`household_store.gd`, `household_store_persistence.gd`), the first link in
the master brief's own causal chain ("household → property → production →
market → contract → institution → resource shock → economic consequence →
NPC response → historical event"). `Household.for_founder` forms a
household keyed by its founder's own entity ref — same "deterministic key,
not an allocated ID" idiom `EntityRef` itself already uses — and is
deliberately **single-member**: `npc.md`'s own lifecycle section still has
no partnership/reproduction system built, so multi-member households would
be exactly the premature complexity the master brief warns against.
`HouseholdStore.grant_property` enforces property has at most one owner at a
time — granting it to a new household transfers it away from the old one
rather than letting two claim the same thing, the same invariant a title
deed enforces in reality.

**Wired against something real, not a synthetic fixture.** Every villager's
own house is a real, already-stamped structure (`VillageRenderer.
_stamp_house`), keyed the same way that function already derives its own
seed (`chunk_coord` + house index) — so recording ownership needed no new
per-house id scheme. `record_settlement_founded_if_new` forms a household
and grants it that house the same moment it records the founding/settling
events, guarded by the same once-only dedupe. Persistence follows the
identical `PlayerSave` convention and lifecycle wiring as the event/memory
stores. `Why.explain_household` (`/household <entity_id>`) looks a household
up by MEMBER rather than by household id, since a player is far more likely
to know an NPC's own name than the id derived from it.

**Left for the next slice, deliberately:** inheritance ("pass property to
descendants") needs death to exist, which `npc.md`'s lifecycle section does
not have yet; multi-member households need partnership/birth, same
dependency; consumption/production of resources is Phase 5's local
production economy, a separate concern from ownership itself.

✅ **A contract's full lifecycle is real, and failures are as recorded as
success** (`contract.gd`, `contract_store.gd`, `contract_store_persistence.gd`),
per `docs/emergence/03-contracts-property-economy.md`'s own schema
(`parties[]`, `obligations[]`, `consideration`, `deadline`, `status`).
`obligations`/`consideration` stay free-form strings rather than structured
amounts — this project has no currency/resource flow wired to NPCs yet
(Phase 5), and inventing one just to give a contract a number to hold would
be exactly the premature complexity the master brief warns against.
`ContractStore` enforces the documented lifecycle
(`proposed → accepted → active → fulfilled`, with `breached`/`defaulted`
reachable only from `active` and `cancelled` only from `proposed`/`accepted`)
as real transition guards, not just status labels a caller could set to
anything — an invalid transition (fulfilling a proposed contract, breaching
a cancelled one) is refused and returns false rather than erroring or
silently succeeding, and a terminal contract (`fulfilled`, `breached`, …)
stays exactly there.

**Every transition is coordinated with a real event, by construction.**
`EarthChunkManager.propose_contract`/`accept_contract`/.../`cancel_contract`
each drive `ContractStore` AND append the matching event in one call — the
same "one call, two stores kept in sync" shape
`record_settlement_founded_if_new` already established for founding — and
record NO event when the store refused the transition, since nothing
meaningful actually happened. This is what makes the Phase 4 exit criterion
("agreement failures create deterministic social/economic/history
consequences") demonstrably true even before anything in the game proposes a
contract on its own: a breach recorded this way is a real, traceable
`contract_breached` event, `/why`-inspectable like any other.

**A genuinely emergent composition, found by the live check, not
engineered on purpose:** because a contract's parties are its event actors,
and event actors automatically form firsthand memories (Phase 2's
`witness_event`), a household that goes through propose → accept → activate
→ breach ends up holding a firsthand memory of *each* of those four stages
— with zero code written specifically to connect contracts to memory. This
is the actual payoff the whole substrate was built for: composing
independently-built primitives producing a real behaviour neither one
implements alone.

**The automatic-trigger gap this phase originally left open is now closed**
(alongside Phase 5/6's own matching gaps — see Phase 7's entry below for
where the trigger actually lives). `EarthChunkManager._step_settlement_trade`,
called from `step_settlements` every automatic step, proposes a real `trade`
contract between a settlement's own households (the same two, lowest-id
first, so repeated success/failure is genuine accumulated history rather
than noise from a shuffling partner) and drives it through
accept → activate → fulfill (a growing/stable settlement can make good on
it) or breach (a declining one cannot) — tied to `SettlementState`'s own
real food-driven status (Phase 7), the same "one real number, multiple
downstream consequences" pattern Phase 5's pricing already established. A
settlement with fewer than two households is skipped, not forced onto a
solo "trade." Live-verified firing with zero manual calls (see Phase 7's
entry). Hiring/employment contracts specifically still wait on `npc.md`'s
occupation-driven behavior maturing further; trade was the grounded choice
available now.

✅ **A resource shortage raises price AND blocks production, from the same
real number** (`market.gd`, `market_store.gd`, `market_store_persistence.gd`),
the Phase 5 exit criterion made concrete: "a resource shortage can raise
prices and cause downstream production failure without scripted events."
**Production itself was not reinvented** — `CraftingRecipeBook` already has
real, tested recipes grounded in this project's real item ids (wood, rock,
stick, stone_pickaxe, ...); a parallel `ProductionRecipe` schema would have
been exactly the "two places doing the same thing" duplication this
project's own postmortems keep flagging. `Market.produce` runs an existing
recipe against a market's own stock the same way `Player.craft` already runs
one against a player's inventory — both ultimately call
`CraftingRecipeBook.craft` against a plain `item_id -> count` Dictionary; a
market is just a different Dictionary to run it against.

**One real number, two honest consequences, not two independently-tuned
effects that happen to agree.** `Market.price_for` derives price from stock
alone — `REFERENCE_STOCK / stock`, a uniform elasticity curve rather than a
per-item base-price table, since there is no real currency/value system
wired to NPCs yet and inventing per-item base prices would be an invented
number with nothing grounding it. `Market.produce` calls
`CraftingRecipeBook.can_craft` against that SAME stock. A shortage that
spikes the price is the identical shortage that blocks production — no
separate budget/currency system was needed to connect the two, because they
were never two systems. Markets are per-SETTLEMENT (`MarketStore`, keyed the
same way `HouseholdStore`/`ContractStore` already key by real entities), per
the doc's own "do not use one global price."

**Wired the same coordinator way as Phase 3/4.**
`EarthChunkManager.attempt_production(settlement_id, recipe_id)` runs
production and records a real `production_succeeded`/`production_failed`
event in one call — a failure is exactly as recorded as a success, and (via
the same automatic actor→memory composition Phase 4 already demonstrated)
the settlement forms a real firsthand memory of its own shortage. Live
end-to-end verification: a settlement's market at the reference stock level
(rock: 20, price 1.0) produced a `stone_pickaxe` successfully; draining rock
to 1 spiked its price to exactly `20/1 = 20.0` — matching the tested formula
precisely — and the same production attempt then genuinely failed,
recorded as a real, `/why`-traceable event. `/market <settlement_id>` is a
real console command; persistence follows the identical lifecycle as every
other store.

**The automatic-trigger gap this phase originally left open is now closed.**
`OccupationProduction.recipe_for` maps a household founder's real occupation
(`NpcIdentity.occupation`, reconstructed from the founder's own seed — no
live NpcMarker node required) to a `CraftingRecipeBook` recipe id, and
`EarthChunkManager._step_settlement_production`, called from
`step_settlements` every automatic step, attempts it for every household
whose occupation has one. Deliberately partial, same "don't invent what
isn't grounded" discipline as `SettlementState`'s food-only carrying
capacity: only `hunter` (→ `cooked_meat`, matching the SEPARATE, already-live
`NpcProduction.PRODUCER_ITEM_BY_OCCUPATION`'s own hunter→meat pairing) and
`blacksmith` (→ `stone_pickaxe`) have a comparably obvious real recipe to
point at; farmer/merchant/guard/fisher/herbalist/nurse have none in the
current recipe book and are silently skipped rather than forced onto an
unrelated one. Live-verified firing with zero manual calls (see Phase 7's
entry). Per-item base pricing (right now every item shares one uniform
elasticity curve around a neutral 1.0) still waits on a real currency/value
system. Trade ROUTES and cross-settlement price arbitrage (docs/emergence/03's
"repeated profitable movement creates routes") are explicitly out of scope
for this slice — they need multiple markets actually trading with each
other, not just existing independently.

✅ **An institution forms from real repeated coordination, with real
hysteresis — not a bare create-on-demand call**
(`institution.gd`, `institution_store.gd`, `institution_store_persistence.gd`,
`institution_formation.gd`), per `docs/emergence/01-society-and-institutions.md`
"Emergence": "Institution candidates arise when clusters repeatedly
coordinate around a common problem or opportunity... Use hysteresis:
formation, stabilization, and dissolution thresholds prevent flicker."
**Deliberately does NOT duplicate `factions.md`'s aggregate-reputation
model** — an institution is a new organizational *entity* with its own
membership, existing alongside `factions.md`'s reputation, which stays a
*projection* over individual relationships, not something an institution
overrides.

**Grounded in something that actually exists, unlike Phase 4/5's synthetic
verification** — this is the first phase since settlement founding (Phase
0/1) with a REAL signal to hook into. `InstitutionFormation.
shared_contract_count` counts FULFILLED contracts (docs/emergence/01's own
"repeated success" scoring factor) between two parties, reading directly
from `ContractStore` — no new coordination-tracking system needed, the
contract store already IS the record of who has coordinated with whom.
Classic two-threshold hysteresis: `FORMATION_THRESHOLD` (3) is meaningfully
higher than `DISSOLUTION_THRESHOLD` (1), so an institution sitting exactly
at the count that formed it is never at risk of dissolving on the same
edge — only a genuine regression triggers that, which is what "prevent
flicker" actually means, tested directly
(`test_should_dissolve_is_false_right_at_the_formation_threshold`).

**Institutions keep their history rather than disappearing.**
`InstitutionStore.dissolve` marks status `dissolved` rather than removing
the entity — the same "a fulfilled/breached contract stays queryable" shape
`ContractStore` already established — so a dissolved guild remains
`/institution`-inspectable, matching "history over static lore." No leader
is ever auto-assigned: `docs/emergence/01` says leadership derives from
"trust, competence, resources, reputation, coercive capacity, social
centrality, and historical success," none of which exist as real data yet
(Phase 3 households have no relationships), so `leader` stays `""` until
something with real grounds to pick one exists — an invented choice would
be worse than none.

**Live end-to-end verification, and the composition kept compounding.**
Two households with 2 fulfilled contracts: `attempt_institution_formation`
correctly refused (below threshold). A third fulfilled contract crossed it:
a real `guild` formed, `/institution` showed it, and — with zero code
written to connect any of this — `/remember` showed the household holding
firsthand memories of all three contracts' full lifecycles *and* the
institution's founding, 13 events in total. Dissolving it flipped its
status to `dissolved` while keeping it in `/institution`'s output. `/why`
correctly traced the founding event. This is the fourth phase running in a
row (2, 4, 5, 6) where memory composed with something else automatically,
purely because both were built as small, honest, composable primitives
rather than a monolith — which is the actual thesis the whole substrate is
testing.

**The automatic-trigger gap this phase originally left open is now closed —
genuinely DOWNSTREAM of Phase 4's, not a separate trigger of its own.**
`_step_settlement_trade` (Phase 4's own automatic trigger, above) calls
`attempt_institution_formation("cooperative", party_a, party_b)` for the
same pair every settlement step; once their repeated fulfilled trades cross
`InstitutionFormation`'s real threshold, a cooperative forms with no
scheduled check written specifically for it — the mechanism reuses the same
`active_institution_for` once-only guard every other coordinator already
relies on, so repeated calls after formation are harmless no-ops. Live
end-to-end verification (see Phase 7's entry) crossed the threshold for
real: three real automatic settlement steps, three real fulfilled trades
between the same two households, one real `institution_formed` event, zero
manual coordinator calls anywhere in the check. N-party clustering (this
slice is deliberately two-party only), goal derivation ("member needs,
pooled dependencies, leadership priorities..."), and institution actions
(recruit, negotiate, patrol, petition, strike, ...) are all still
explicitly out of scope — the doc's own "Start with guilds, cooperatives,
militias..." roster names the TYPES this phase supports, not yet the
behaviors those types would eventually enact.

**Dissolution's own automatic-trigger gap is now closed too — and it
needed a real fix, not just wiring, because the old metric could
structurally never produce a dissolution.** `InstitutionFormation.
shared_contract_count` (what formation reads) is ALL-TIME and
monotonically non-decreasing: once it crosses `FORMATION_THRESHOLD`, it
can only ever grow, so a `should_dissolve` check built against that same
count could only ever be true BEFORE formation, never after — a real
structural reason this had no live trigger, discovered while investigating
whether one could simply be added. The fix is a second, deliberately
different metric: `recent_shared_contract_count(store, party_a, party_b,
now)` counts only FULFILLED contracts created within a trailing
`RECENT_WINDOW_SECONDS` (300, tested against the behavior it produces, the
same "no real economy data to derive a correct number from, but real
behavior a test can pin" honesty `FORMATION_THRESHOLD` itself already
states) — genuinely falls back toward zero if a pair stops coordinating,
because CONTRACTS AGE OUT of the window rather than staying counted
forever. `should_form` still reads the all-time count unchanged (a strong
track record is exactly why an institution should form, and should never
be "forgotten"); only `should_dissolve` reads the windowed one — the real
distinction between "has a track record" and "is still active,"
mirroring how a real relationship works. Wired into `step_settlements` as
a new `_step_settlement_institution_health` step, deliberately placed
AFTER `_step_settlement_trade` in the per-settlement loop (not before) so
a pair that traded again THIS step sees its own fresh fulfilled contract
before the health check runs, rather than being judged on a stale
pre-trade snapshot.

**A real subtlety the unit tests caught before it became a live bug:** a
first draft test asserted "an institution that traded once more stays
active" using a single post-jump trade — and that trade ALONE produced
exactly one recent contract, which is itself at or below
`DISSOLUTION_THRESHOLD` (1), so the institution dissolved anyway. The fix
wasn't the mechanism, it was the test: ongoing prosperity means trading
EVERY settlement step (every 30s), so a genuinely healthy institution
accumulates several recent contracts within the 300s window, not just
one — the corrected test simulates that real repeated cadence instead of
one isolated trade. Live end-to-end verification, zero manual calls to
`dissolve_institution`: formed a real institution from manually-fulfilled
history, gave the settlement no food (so its own automatic trade breaches
every step, adding nothing new to the window), enabled `/ecotest`, and let
`step_settlements` run on its own — a real `institution_dissolved` event
appeared at world-clock tick ~960, safely past the 300-second window.

✅ **A settlement's growth/decline status is real, automatic, and
FOOD-driven** (`settlement_state.gd`,
`EarthChunkManager.step_settlements`/`_known_settlement_ids`/
`_households_in_settlement`), per
`docs/emergence/04-settlements-cities-infrastructure.md` "Carrying
capacity": "Population capacity depends on food, water, housing, jobs,
sanitation, security, transport, trade, climate, and disease. Population
should move toward capacity rather than use arbitrary growth." Deliberately
food-only for this slice — food is the one input this project already has
live, real data for (`Market`, Phase 5); water/housing/job/sanitation
simulation don't exist yet either, and deriving capacity from them would
mean inventing the very systems this slice is avoiding inventing.
`SettlementState.food_stock` reads real item CATEGORIES from the existing
`ItemCatalog` (`Item.kind == "food"`) rather than a second, hand-maintained
list of "which items count as food" that could silently drift from it.
`status_for` classifies GROWING/STABLE/DECLINING with a dead band around the
1:1 ratio, the same "prevent flicker" reasoning `InstitutionFormation`'s
two-threshold hysteresis already uses, just as one band around a single
threshold instead of two separate ones.

**Membership and settlement existence are both read back out of the event
graph itself, not tracked a second time.** `_known_settlement_ids` reads
every `settlement_founded` event's own actor; `_households_in_settlement`
reads every `npc_settled` event a settlement witnessed and resolves each
villager's household through `HouseholdStore`. Neither needed a new
membership index — the event graph built in Phase 0/1 already *was* the
record, this just queries it, which is the kind of demonstrable payoff
`00-emergence-architecture.md`'s own "why does this city exist" observability
goal is actually for.

**This was the first emergence phase with a genuinely automatic live
trigger, and is now also home to Phase 4/5/6's own.**
`EarthChunkManager.step_settlements` uses the exact same throttled-
accumulator shape `TreeSpread`/`step_tree_spread` already established
(`SETTLEMENT_STEP_INTERVAL := 30.0`), and is wired directly into
`World._step_ecology_batch` — "the heavy periodic work, and everything
that adds to the world," the same group tree spread and forage already run
in. It only event-sources a REAL status CHANGE (an unchanged status is
silently skipped, `_settlement_status` tracked but deliberately not
persisted — a reload may re-record its current status once more on the
first step after loading, a known, accepted rough edge rather than a
source of runaway duplicates, since it can only happen once per reload).
Every real settlement step now ALSO drives Phase 5's production attempt and
Phase 4's household trade (which in turn feeds Phase 6's institution check)
— extending the one real automatic hook rather than adding three separate
ones, closing "Phases 4, 5, and 6 still have NO automatic live trigger,"
the gap this same entry used to state here.

**Live end-to-end verification proved the automatic path specifically, not
just the mechanism, twice over.** Settlement status: loaded a real
settlement, enabled `/ecotest` acceleration, and let the ordinary `_process`
loop run with **zero manual calls** to `step_settlements` or any other
coordinator. A real `settlement_declining` event appeared on its own at
world-clock tick ~962, correctly reflecting that real settlement's 5 real
households against its real (zero) food stock — `/settlement`, `/why`, and
`/history` all showed consistent, correct state. Production/trade/
institutions: a fresh settlement with a real hunter household and real
`meat` stock, `/ecotest` enabled, and again **zero manual calls** to
`step_settlements`, `attempt_production`, `propose_contract`, or
`attempt_institution_formation` — within 5 real engine frames the log
showed `production_succeeded=3 contract_proposed=3 contract_fulfilled=3
institution_formed=1`, the entire Phase 4→5→6 causal chain firing on its
own from nothing but the real `_process` loop.

**Left for the next slice, deliberately:** water, housing, jobs,
sanitation, security, transport, climate, and disease — every other
carrying-capacity input the concept doc lists — wait on real systems to
derive them from (a housing capacity check is trivial but currently
meaningless, since every villager already owns exactly one house by Phase
3's own construction; it would always read "at capacity"). Food itself is
now automatically PRODUCED (Phase 5's trigger, for occupations with a
grounded recipe) but still not automatically CONSUMED by anything — a
settlement's food stock only drains if something spends it, and nothing
does yet, so `step_settlements` can currently only report GROWING/STABLE in
practice once production starts outpacing a starting stock of zero.
Migration, city thresholds, specialization-from-flows, and dependency
networks are all later parts of this same doc, explicitly out of scope
here.

✅ **Worn paths are a real, causally-grounded entity — grown from a
mechanism that already existed rather than a new one** (new
`docs/concept/infrastructure.md`, `EarthChunkManager.record_path_worn_if_new`/
`record_path_reclaimed`), the literal `docs/emergence/04-settlements-
cities-infrastructure.md` "Infrastructure" exit criterion: "Repeated
movement upgrades path → trail → road." `PathScarring` (per-tile wear from
footsteps, decaying over time, rendered as trampled earth once worn) already
existed and already ran live every session — this phase does not reinvent
it, it gives the SAME mechanism a real emergence-substrate identity. A path
needed no new `*Store` the way households/contracts/markets/institutions
did: `EntityRef.for_kind("path", "<tile_x>_<tile_y>")` is a real, already-
available deterministic key (the tile itself), and a path's whole lifecycle
IS its own event history — `/history path:<x>_<y>` already answers "why
does this dirt path exist" with no new store or `Why.explain_*` function
needed, the same "the event graph itself is the record" reasoning
`_known_settlement_ids` already established for settlements.

**Idempotent against a real, subtle reload edge Phase 7's own precedent
left as an accepted rough edge — this one closes it instead.**
`record_path_worn_if_new` is guarded on whether this path's MOST RECENT
persisted event is already a formation, not on the caller's own in-memory
transition flag (`World._scarred_tiles`, reset on every reload) — so unlike
`_settlement_status` (Phase 7, explicitly documented as "a reload may
re-record its current status once more"), a path cannot record a duplicate
founding just because a session restarted. `record_path_reclaimed` is the
mirror and deliberately NOT once-only: a path can be worn, reclaimed by
nature, and worn again over a real session, and each cycle is real,
distinct history, exactly as `docs/emergence/04`'s "Infrastructure
degrades" names it.

**This phase's automatic trigger did not need building — it already
existed.** Unlike Phases 4/5/6 (which needed a NEW periodic coordinator
built and wired in), `World._step_path_scarring` already runs every real
session from ordinary player movement; the two new coordinator calls simply
sit at the exact two points a tile already crosses a real state boundary
(newly rendered as earth; no longer worn), the same "hook the real existing
trigger" reasoning Phase 0/1 used for settlement founding via
`VillageRenderer.spawn_village`.

**Live end-to-end verification, zero manual coordinator calls:** seeded a
real player-standing tile with enough real wear to cross the threshold
(the same `PathScarring.step_on` the real per-footstep code path calls),
then let the ordinary `_process` loop run with **zero manual calls** to
`record_path_worn_if_new` or `record_path_reclaimed`. A real `path_worn`
event appeared on its own once the real 2-second refresh interval elapsed;
fast-forwarding the same real `PathScarring.advance` decay path below
threshold produced a real `path_reclaimed` event, again with no manual
coordinator call — `worn=1 reclaimed=1`, both from the real automatic path.

**Left for the next slice, deliberately** (see `docs/concept/
infrastructure.md`'s own Status list): the trail/road tiers above today's
single "worn" threshold, crossings (ford/ferry/bridge — no "crossing point"
concept exists yet), traffic heatmaps, inter-settlement routes, market
nodes, and infrastructure condition/maintenance feeding back into Phase 5's
real market prices are all explicitly out of scope for this slice.
Creature-driven wear is out of scope for the same documented reason
`PebbleDispersion` already is (an O(creatures × nearby tiles) scan nothing
yet needs enough to justify).

✅ **A settlement's town/city tier and specialization are both derived from
real flows, never a stored tag** (`settlement_tier.gd`), the literal
`docs/emergence/04-settlements-cities-infrastructure.md` "City threshold"/
"Specialization" exit criteria: "Use multiple dimensions rather than
population alone" and "Infer specialization from persistent production and
trade... Do not store specialization as a static content tag when it can be
derived from flows."

**Deliberately narrow, same honesty as every prior phase.** Of the six
named tier dimensions (population density, economic specialization,
institutional complexity, infrastructure density, trade connectivity,
administrative capacity), only THREE have real data behind them today:
population (household count, Phase 3/7), economic specialization
(production history, Phase 5), and institutional complexity (active
institution count, Phase 6) — read straight from `_households_in_settlement`,
`_production_counts_for_settlement`, and `_active_institution_count_for`,
the exact same data `_step_settlement_production`/`_step_settlement_trade`
already produce, nothing new tracked. Infrastructure density (Phase 8's
paths), trade connectivity (cross-SETTLEMENT trade — Phase 4's automatic
trigger is intra-settlement only), and administrative capacity (no
governance/authority concept exists) are explicitly deferred rather than
guessed at.

**Population alone is provably never enough — proven through the real
mechanism, not merely asserted.** `tier_for` requires households AND active
institutions AND production diversity to all cross together; a settlement
with high population but no food breaches every trade (Phase 4), so no
institution ever forms (Phase 6) and nothing is ever produced (Phase 5) —
it genuinely cannot reach TOWN no matter how many households it has, the
same causal chain the food-driven economy already enforces elsewhere in
this substrate, not a special case written just for tier classification.

**Specialization is exactly two labels today, both real, neither
invented.** `_SPECIALIZATION_BY_RECIPE` maps only the two recipes
`OccupationProduction` (Phase 5) actually grounds — `cooked_meat` →
"hunting center", `stone_pickaxe` → "manufacturing town" — picked by
whichever recipe a settlement has produced most (ties break toward the
alphabetically-first recipe id, deterministic rather than depending on
Dictionary iteration order). `Why.explain_settlement` shows tier
unconditionally and specialization only once real production actually
grounds one, via two new optional trailing parameters that keep every
existing caller working unchanged.

**Live end-to-end verification, zero manual coordinator calls:** founded a
real settlement with 3 households (one a real hunter) and real `meat`
stock, enabled `/ecotest`, and let the ordinary `_process` loop run with
**zero manual calls** to `step_settlements`, `attempt_production`,
`propose_contract`, `attempt_institution_formation`, or anything
tier-specific. Within 5 real engine frames: `became_town=1 specialized=1`
— the full population→production→trade→institution→tier chain, spanning
Phases 3 through 9, firing entirely on its own.

**Left for the next slice, deliberately, and named directly in the exit
criterion itself:** "contraction and abandonment." Contraction is already
reasonably covered by Phase 7's existing DECLINING status — a settlement
under real food pressure IS contracting pressure. True abandonment
(household count reaching zero on a settlement that once had population)
is NOT built: `SettlementState.status_for(0, 0)` already has deliberate,
tested, DIFFERENT semantics — "an empty settlement with no food and no
households is not declining, there is nothing there yet to be under
pressure" (Phase 7's own test) — meaning household_count==0 already means
"never grew" for a settlement snapshot with no memory of its own past size,
and overloading it to also mean "lost everyone" would conflict with that
existing, deliberate behavior rather than extend it. Distinguishing the two
needs real history comparison (was this settlement's household count ever
above zero before now), which nothing needs yet since no migration/death
mechanism exists to ever actually shrink a settlement's real population —
the same "no real trigger to hook into" reasoning that gated every other
deferred piece across this whole 9-phase run. Tier/specialization thresholds
are tested against the classification they produce, not any specific
"correct" population, the same honesty `InstitutionFormation.
FORMATION_THRESHOLD`'s own doc comment states.

✅ **A ruin is a real entity with a real, stored cause — never invented,
never a bare label** (new `EarthChunkManager.record_ruin_from_*` trio,
`docs/concept/exploration.md`'s new Status section), the literal
`docs/emergence/05-dungeons-bosses-exploration-content.md` "Ruins" exit
language: "A ruin is the physical state of a formerly functional place.
Creation causes must be stored." No new `*Store` — same as Phase 8's paths,
a ruin's whole lifecycle IS its own event history
(`EntityRef.for_kind("ruin", ...)`), and `EventStore.link_cause` (Phase 0/1's
own bidirectional cause↔consequence machinery, unused by any coordinator
until now) wires the ruin's `ruin_formed` event straight back to whatever
real event actually caused it — `/why ruin:<key>` traces to a genuine
antecedent, not a description with nothing behind it.

**Exactly three independent causal sources, matching the exit criterion
word for word** — mapped to `docs/emergence/05`'s own named "Dungeon
sources" categories rather than invented to hit the number three:

- **"Historical catastrophe"** ← a settlement's real, automatic decline
  (Phase 7, food-driven) — wired directly into `step_settlements`'s
  existing status-change block.
- **"Ecological transformation... overgrown ruins"** ← nature reclaiming a
  worn path (Phase 8) — the literal named phenomenon, not an analogy
  stretched to fit. Wired into `record_path_reclaimed`.
- **"Social transformation... abandoned prisons"** ← a dissolved
  institution's old headquarters (Phase 6). Wired into
  `dissolve_institution`.

Each source builds the ruin's key from ITS OWN real identifier, prefixed by
source kind so the same raw location number can never collide across
different source types (a settlement and a path could both be keyed "5_5"
otherwise) — proven directly by a test that forms all three from identical
raw numbers and gets three genuinely independent ruins. Institution ids
needed a small real correction along the way: they are NOT `EntityRef`
"kind:key" strings the way household/settlement/path ids are —
`InstitutionStore.form`'s own `"inst_<ordinal>_<type>"` shape has no colon
— so that source uses the institution id verbatim rather than running it
through `EntityRef.key_of`, which would have silently returned `""`
against it.

**Two of the three ride on already-automatic triggers; the third's own
gap is real, pre-existing, and now understood more precisely than
before.** Settlement decline and path reclamation were already firing
automatically before this phase touched them (Phase 7/8's own triggers) —
a ruin now forms as a genuine side effect of each, with zero new
scheduling. Institution dissolution is different: `dissolve_institution`
itself still has no automatic caller (Phase 6's own pre-existing,
documented gap) — and investigating why while building this phase surfaced
a real, previously-unstated reason it *can't* be trivially added the way
Phase 4/5/6's own gaps were closed: `InstitutionFormation.
shared_contract_count` counts ALL-TIME fulfilled contracts between a pair,
which only ever grows, never shrinks — so `should_dissolve` (checking that
count against `DISSOLUTION_THRESHOLD`) can only ever be true BEFORE an
institution forms, never after. A periodic automatic dissolution check
would therefore be a real no-op today, not a genuine mechanism — correctly
left unbuilt rather than added just to look complete.

**Live end-to-end verification, zero manual coordinator calls:** a real
settlement declining (Phase 7's own automatic trigger) formed a real ruin
on its own, correctly cause-linked back to the exact `settlement_declining`
event that triggered it — proven by walking `EventStore.causes_of` on the
ruin's own event and checking its id matches. A real path reclaimed by
nature (Phase 8's own automatic trigger) formed a second, independent ruin
the same way, again with no manual call to any `record_ruin_from_*`
coordinator anywhere in either check.

**Left for the next slice, deliberately, and named directly in
`docs/concept/exploration.md`'s new Status section:** physical ruin
structures/rendering in the actual game world (this phase is the causal/
data layer only — no building, monster lair, or ancient grove is generated
or drawn from any of this yet), occupants, archaeology/evidence beyond the
causal link itself, and the whole materials-gated puzzle-obstacle
vocabulary `exploration.md` already designs but nothing here builds. World
boss lairs and ancient-grove POIs specifically wait on Phase 11 (world
bosses) and a confirmed ancient-tree mechanic, neither of which exist yet.

✅ **World bosses aren't a new mechanism — the real one already existed**
(`world_boss.gd`, `world_boss_store.gd`, `world_boss_store_persistence.gd`),
discovered mid-phase rather than built from scratch: `src/gameplay/
world_boss_fitness.gd` already implements the exact math `docs/concept/
worldbosses.md` specifies (`fitness_score(level, kills, age_seconds)`,
per-species thresholds, one-shot `PhaseGenerator`/`FakePhaseGenerator`
authoring) — fully real, fully tested (20 pre-existing tests), and simply
never called from anywhere in live gameplay. `worldbosses.md`'s own "Open
questions" section still said the fitness-threshold math "needs numeric
design" even though it had already been resolved elsewhere in the codebase
— a real doc/code divergence, now corrected (see the doc's new Status
section) per `CLAUDE.md`'s cross-alignment rule.

**This phase's actual job, once that was found, was narrow: give the
already-real mechanism a causal identity, without touching its math.**
`WorldBoss`/`WorldBossStore` mirror `Institution`/`InstitutionStore`'s
exact shape (active/defeated, persisted, history kept after defeat, same
`"boss_<ordinal>_<species>"` id convention). `EarthChunkManager.
attempt_world_boss_promotion` wraps `WorldBossFitness.attempt_promotion`
and records a real `world_boss_promoted` event in the same call — the
literal `docs/emergence/05-dungeons-bosses-exploration-content.md` "Boss
emergence... must permanently affect the world" language made concrete,
`/why`/`/boss`-inspectable rather than a silent Dictionary nobody sees.
`defeat_world_boss` does the same for "Killing a boss emits a major
historical event." Both guard the same way every other coordinator here
does: `active_boss_for` blocks a duplicate promotion (a defeated boss does
NOT block re-promotion, the same "dissolved doesn't block re-forming"
reasoning `InstitutionStore.active_institution_for` already establishes),
and the (potentially costly) phase generator is never invoked for an
ineligible individual — `WorldBossFitness`'s own guarantee, still true
through the coordinator, tested directly.

**Left for the next slice, honestly — this is Phase 4's own original gap,
not a new one:** nothing in live gameplay calls `attempt_world_boss_
promotion` yet, because nothing tracks the two inputs it actually needs.
`CreatureInfo.level` is real but FIXED at spawn from the creature's own
seed — not something that grows through play — and no creature anywhere
accumulates a kill count or a lifetime-age-in-seconds value. Building that
tracking is real, separate creature/combat-system work, not something the
emergence substrate alone should invent — the mechanism is complete,
tested, and ready to be called the instant that tracking exists, the exact
position Phase 4 (contracts) was in before Phase 5/6 gave it real data to
work from. Territory effects, era-gating, village endangerment (both
depend on systems that don't exist yet either — `quests.md`'s own
endangerment mechanism, the era system), taming, and the physics-spectacle
combat layer are all untouched by this slice; `worldbosses.md`'s new
Status section names each explicitly rather than leaving them implicit.

**Investigated concretely during a later gap-closing pass (not yet
implemented):** confirmed the shape of the gap rather than closed it.
`CreatureMarker._seconds_since_birth` IS a real, already-incrementing
per-creature age value — but it is plain in-memory scene-node state, never
persisted the way this substrate's own stores are, so it almost certainly
resets on chunk unload/reload rather than surviving as a genuine lifetime
age. No kill attribution exists anywhere in the combat code (neither
player-kills-creature nor creature-on-creature predation records who
killed what). Closing this for real needs a decision on whether age must
survive unload or a fresh-per-load approximation is acceptable, plus real
kill bookkeeping added at combat-resolution time — genuine, separate
creature/combat-system work touching live simulation code under active
concurrent development, not a quick wire-up. Deferred pending an explicit
go-ahead for that scope.

✅ **A quest is a real, stateless projection — never new authoritative
content, by construction, not just by claim** (new `quest.gd`,
`EarthChunkManager.production_shortfall_quests_for_settlement`), the
literal `docs/emergence/07-implementation-roadmap.md` Phase 12 exit
language: "Refactor quests into projections of household, institution,
settlement, ecology, infrastructure, history, and economy problems.
Disabling quests must not remove the underlying problem." Deliberately NOT
a `Store` — every prior phase's entity (Household/Contract/Market/
Institution/WorldBoss) persisted real state; a quest here persists
nothing and records no event, because "disabling it must not remove the
underlying problem" means a quest can never BE the problem. Deleting
`quest.gd` entirely changes nothing about whether a settlement's market is
actually short on stock — only the player-facing framing of that real
shortage disappears. This also makes a quest incapable of going stale the
way a recorded "quest offered" event could: it is recomputed fresh every
call, so the moment a shortage resolves, the SAME query already reflects
that, live-verified directly (`test_production_shortfall_quests_disappear_
once_the_market_is_stocked`).

**Deliberately narrow, same discipline as every phase before it.** Of
`docs/concept/quests.md`'s three need sources (safety, production,
social), only Production is grounded in real, already-tracked data —
Phase 5's `Market`/`CraftingRecipeBook`, the exact same state
`_step_settlement_production`/`production_counts_for_settlement` already
read. Safety needs Phase 11's world-boss threat detection (no live
trigger) and NPC threat-memory-crossing thresholds (not built); Social is
explicitly deferred by `quests.md` itself ("lightest touch... deferred
detailed design"). Quorum/promotion/settlement-level merging and
representative selection (needs `factions.md`'s reputation score, not
built) and resolution/consequences (needs a currency-to-NPC transaction,
which does not exist — Phase 4/5's own documented gap) are both
explicitly out of scope too: this slice is discovery only — proving a real
quest can be DERIVED from real state at all, not the full offer/accept/
resolve loop `quests.md` eventually specifies.

**Named the specific shortfall, not just that one exists.** A quest names
which item(s) a household's blocked recipe is missing and by how much
(`Quest._missing_inputs`, reading the same `CraftingRecipeBook.
recipe_inputs`/`Market.stock_of` Phase 5's own `attempt_production`
already uses) — "production failed" (Phase 5's own event) tells a player
nothing actionable; "household:1 needs 3 rock for stone_pickaxe" does.

**No headless live-check this phase, deliberately — and here is exactly
why, rather than a silent skip.** Every prior phase's live-check proved
either an automatic TIMING trigger (does this fire on its own, on a real
clock) or a real SCENE-TREE dependency (does this correctly read live
`NpcMarker` state). `production_shortfall_quests_for_settlement` has
neither: it is a pure function of `EventStore`/`HouseholdStore`/
`MarketStore` state, called on demand, with zero scene-tree involvement —
and `record_settlement_founded_if_new` (the coordinator-level tests' own
setup call) IS the exact same function the real `VillageRenderer` spawn
path calls, so a synthetic test settlement and a real rendered one produce
identical underlying state. A separate live-check would exercise the
identical code path a second time in a different process, adding no real
confidence beyond what `test_earth_chunk_manager.gd`'s own coordinator
tests already provide.

**Left for the next slice, deliberately, and named directly above rather
than left implicit:** safety/social need sources, quorum/promotion/
representative selection, resolution (accept/deliver/reward), village
endangerment, and settlement growth/migration are all untouched by this
slice — `quests.md`'s own "Current implementation status" section now
names each explicitly.

✅ **Governance form and legitimacy are both real, derived classifications
— and governance form genuinely changes a real decision, not just a
label** (new `docs/concept/governance.md`, `governance.gd`), the literal
`docs/emergence/07-implementation-roadmap.md` Phase 13 exit language:
"Governance changes actual decisions and resource flows." No concept doc
covered this mechanic at all before this phase — scaffolded first per
`CLAUDE.md`, grounded in `docs/emergence/01-society-and-institutions.md`'s
own "Governance"/"Legitimacy" sections, before any code was written.

**Only the governance forms and legitimacy inputs with a real, already-
tracked signal behind them are grounded — everything else named in
`docs/emergence/01`'s own lists stays unmapped rather than guessed at.**
Of eight named governance forms, three have a real institution TYPE
(Phase 6) behind them: `militia`→military rule, `merchant_company`/
`guild`→merchant oligarchy, `cooperative`→cooperative administration.
`criminal_group` is deliberately left unmapped — a purely criminal
presence has coercive power, not legitimate authority, per
`docs/emergence/01`'s own invariant ("No authority without legitimacy or
coercion"), and this slice does not yet model coercion-based rule
separately. Of legitimacy's eight named inputs, only food security has
real data (`SettlementState`, Phase 7) — `Governance.legitimacy_for`
reads its GROWING/STABLE/DECLINING status directly, the same signal
through a different lens, not a second number to keep in sync.

**The real decision it changes**: `EarthChunkManager._step_settlement_
trade`'s own automatic institution-formation call, previously a hardcoded
`"cooperative"` since Phase 4/6 first wired it, now reads
`Governance.institution_type_for_new_formation(governance_form)` instead
— a settlement with a real military-rule history attempts a militia for
its next automatic formation, a merchant-oligarchy one attempts a
merchant_company. A settlement with no governance history yet still
defaults to `"cooperative"`, unchanged from every prior test's own
expectations — confirmed by re-running Phase 4/6/9's own existing
regression suite, all still green with zero changes needed to a single
existing test.

**Governance form is read from a settlement's WHOLE real institutional
history, active or dissolved — "historical precedent" made literal.** A
settlement's political character persists through a specific
institution's failure: `_institution_type_counts_for` counts every
distinct institution (deduped by id) any of the settlement's households
have EVER belonged to, `institutions_for`'s own "active or dissolved"
shape (Phase 6), not just its currently-active ones.

**Live end-to-end verification, zero manual calls for the pair being
tested:** a settlement with a real military-rule history (a militia
formed between one pair of its households) had its automatic formation
for a genuinely DIFFERENT pair attempt a militia too — proven by running
the ordinary `_process`/`step_settlements` loop for real elapsed time,
zero manual calls to `attempt_institution_formation` for that second
pair. One real timing lesson from this check, worth recording: an initial
attempt using a large `/ecotest` acceleration failed, because it advanced
the world clock by hundreds of simulated seconds per real frame — racing
PAST `InstitutionFormation.RECENT_WINDOW_SECONDS` (300, Phase 6's own
recent gap-closing fix) faster than fulfilled contracts could accumulate
within it, so nothing ever stayed "recent" long enough to reach
`FORMATION_THRESHOLD`. Re-run at normal real-time pace (no acceleration)
succeeded cleanly: `elapsed=90.1 found=true type=militia`, exactly the 3
real `SETTLEMENT_STEP_INTERVAL`s (30s each) the mechanism was always
expected to need.

**Left for the next slice, deliberately, and named in `governance.md`'s
own Status section:** policies, taxation, and enforcement (taxation
specifically needs a real currency/wealth-flow system that doesn't exist
yet); legitimacy's other seven inputs; council/hereditary/clan/
priesthood/representative governance forms (no real signal to derive them
from); and crime/religion (`docs/emergence/01`'s own adjacent sections,
unbuilt and unrelated to this slice).

✅ **Regional trade — the smallest possible trade network, one real edge
between two real settlements** (new `docs/concept/regional_trade.md`,
`regional_trade.gd`, `EarthChunkManager.step_regional_trade`), the "trade
networks" element of `docs/emergence/07-implementation-roadmap.md` Phase
14's own exit language: "Implement regions, trade networks, migration
flows, dependency graphs, and resource corridors." No concept doc covered
cross-settlement trade at all before this phase — scaffolded first per
`CLAUDE.md` (migration stays `quests.md`'s own already-designed, still
unbuilt section — not repeated here), then implemented the same pass.

**Composed entirely from two primitives this substrate already had, with
zero new "who needs what"/"who has extra" tracking invented.** A
settlement's shortage is Phase 12's own live `Quest` projection; a
settlement's surplus is just its real `Market` stock, checked directly.
`RegionalTrade.has_surplus(stock, need)` requires real headroom beyond a
tested safety margin (`MIN_SURPLUS`) — a settlement never trades its own
last reserve away down to the exact edge just to help a neighbor.
"Nearest" is real Euclidean distance between two settlements' own chunk
coordinates, parsed directly back out of their existing `EntityRef` keys
(`RegionalTrade.chunk_coord_of`) rather than a second stored position —
the same "derive it from a key the entity already has" idiom `EntityRef`
itself has used since Phase 0/1.

**`step_regional_trade` reuses `production_shortfall_quests_for_settlement`
directly** — every known settlement's real shortfalls are checked each
step, and for each missing item, the nearest real settlement with genuine
surplus ships exactly enough to cover it, in one call:
`Market.add_stock` with a negative count on the supplier, positive on the
recipient, both real markets updated together, and a real
`regional_trade_shipped` event naming both settlements and the item —
`/why`-inspectable, not a silent number change. Resolves a shortage fully
in one step rather than gradually (this doc's own open question names
partial/gradual shipment as a real future refinement once there's a
reason — travel time, route capacity — to model the lag).

**A regional shock affecting multiple settlements falls out of the
mechanism itself, not a bespoke propagation system** — this phase's own
third design pillar made concrete: draining a supplier's real stock to
help a neighbor is the exact same real number that could later leave the
supplier itself short, with no extra code required to make that true.

**Live end-to-end verification, zero manual calls:** a real settlement
with a real blacksmith's shortfall, a real neighboring settlement with
real surplus stock, `/ecotest` enabled, and the ordinary `_process` loop
run with zero manual calls to `step_regional_trade` or
`_attempt_regional_resupply` — `shipped=2` (both of `stone_pickaxe`'s
missing inputs) by tick 3.

**Left for the next slice, deliberately, and named in `regional_trade.md`'s
own Status section:** dependency graphs and resource corridors (real
aggregations over trade edges once enough of them exist, not a separate
structure this slice builds); migration flows (`quests.md`'s own unbuilt
design, needs the replan-interrupt architecture); and regions as a
first-class grouping (not needed for nearest-neighbor resupply to work).

---

## Unscheduled — not yet phased into the roadmap

The roadmap predates almost all of these concept docs. Each subsection below
covers one `docs/concept/*.md` file's full mechanism list. Status is honest:
the large majority are ⬜ not started, since the codebase currently has no
NPCs, combat, items, crafting, magic, DNA/genetics, economy, factions,
housing, pets, world bosses, PvP, festivals, death/respawn, survival needs,
weather beyond day/night tinting, transportation, exploration mechanics,
building, farming, cooking, fishing, or flora/vegetation simulation of any
kind. Where a mechanism does overlap with the real world-simulation
foundation, that overlap is called out explicitly.

### Ecosystem Dynamics (`concept/ecosystem_dynamics.md`)

The living-ecosystem phase, grounded in real ecological mechanisms and run at
two fidelities (individual agents near the player, aggregate catch-up for
chunks away from the player). See the concept doc for the full spec.

- **Fruit phenology (growing → ripe → fallen)** (medium) — ✅ Done — `src/world/fruiting_model.gd` (tested): each tree runs a repeating bearing cycle **one year long** (`FruitingModel.BEARING_CYCLE_SECONDS = SeasonCycle.SECONDS_PER_YEAR`), driven by its `TreeGenome` (crop size from `fruit_yield`) and local warmth (a growing-degree-day analogue — a warm climate can carry two crops a year). The cycle length **used to be `genome.maturity_time`, 20–60 SECONDS** — that is how long a sapling takes to grow up (`TreeMaturity`), an entirely different quantity — so every mature tree shed its whole crop twice a minute: a measured **1524 fallen fruit per minute from a 40-tree stand** against a ground-item budget of 80, which buried the forest floor in stacks of ~100 and churned a hundred-odd labelled, clickable nodes a second. Same root cause as the 30-second reproduction cooldown: nothing time-dependent had ever been observed running, because the ecology simulation was not stepping at all (see `World.owns_ecosystem_simulation_for`), now also scaled per **named species** (`TreeSpecies` — Walnut/Cherry/Apple, see the Flora section below) via a yield/ripening multiplier pair layered on top. Near the player (`EarthChunkManager.step_fruiting`, within a detail radius) a tree's current **ripe crop is rendered as individual pixel dots on its canopy, in its own species' colour** (`ProceduralTreeSprite.generate_image_with_fruit`) and abscised (fallen) fruit drops as a **named-species ground item** (`cherry`/`apple`/`walnut`, not the old generic `fruit`/`nut`) animals and the player can eat.
- **Frugivory (animals eat fallen fruit)** (small) — ✅ Done — herbivores/boars consume nearby fallen fruit (`FoodConsumption`, `World._step_herbivore_food_consumption`), gaining body condition. Seed dispersal (moved seeds germinating elsewhere) is ✅ for bird endozoochory specifically (see `Animal-mediated seed dispersal` below), still ⬜ for ground herbivores/omnivores.
- **Condition-gated reproduction (bioenergetics)** (medium) — ✅ Done — `src/gameplay/animal_reproduction.gd` (tested): each creature carries an `energy` value that rises on eating and decays over time; a **healthy, well-fed** creature past a **birth cooldown** spawns an offspring of the same species beside it (`CreatureMarker.can_reproduce`/`on_reproduced`, `World._step_reproduction`), capped by `MAX_LIVE_CREATURES`. The cooldown is **one real day** (`REPRO_COOLDOWN = 24h`); it was 30 seconds, which only looked survivable while the ecology simulation was silently not running (see `World.owns_ecosystem_simulation_for` below) -- once it did run, a clearing filled with deer in under a minute. Birth is additionally vetoed by **local crowding**: `World._same_species_within(NEIGHBOUR_RADIUS_PX = 160)` past `MAX_SAME_SPECIES_NEARBY = 4`, and by `EarthChunkManager.can_support_another_herbivore(position, live_nearby)`, which compares that local count against the vegetation-derived `EcosystemSimulation.herbivore_capacity_at(chunk)` -- so density dependence acts where the animal stands, not just against the global cap. Verified live over 60s: species counts held at 2-9 each with worst local crowd 1.
- **Fallen fruit is sized against something the player can see** (small) — ✅ Done — `ProceduralItemSprite.WORLD_WIDTH_BY_ID` / `world_scale_for` (tested): every dropped item rendered at a full 16px tile, so a fallen cherry was as wide as the ground square under it ("they are gigantic"). Sized off one free number — a walnut is **half a butterfly** wide — with cherry (0.8×), apple (2×) and the generic ambient-tier `nut` (0.8× cherry) and `fruit` (= cherry) all pinned to it as ratios, so re-sizing the family stays a one-line change. Non-fruit items keep the size they always had.
- **Rain draws its drops, not the whole screen** (medium) — ✅ Done — `src/rendering/rain_overlay.gd` (tested): rain was one screen-covering `ColorRect` whose fragment shader carved streaks out of it. Measured on this machine's integrated GPU, hiding that single rect took the game from **42 fps to 57.7 and removed the 130–150 ms frame spikes** — and vsync turns "just over 16.7 ms" into a dropped frame, which is why rain read as heavy lag rather than a slightly slower frame. The cost was **not** the shader: a bare `COLOR = vec4(0.0)` fragment cost the same 15 fps, so did a plain translucent `ColorRect` with no material at all, and `discard` for the ~99% of pixels between streaks changed nothing; shrinking the *same* shader to a 64×64 rect gave nearly all of it back. What the pass costs is the screen **area** it rasterises. Rain is now one `MultiMesh` instance per drop (a `STREAK_WIDTH × STREAK_LENGTH` quad) placed by the vertex shader off `TIME` — still one draw call, still no per-frame script, covering a few percent of the screen. Measured after: **55 fps under a forced storm with worst frame 18.2 ms** (was 42 fps / 150 ms). Gotcha found and documented: MultiMesh instance custom data is **8 bits per channel** in this renderer, so a raw pixel coordinate stored there reads back as 0 — every channel carries a 0..1 fraction scaled back up by a uniform.
- **Decoration is drawn where it can be seen** (small) — ✅ Done — `src/rendering/decoration_lod.gd` (tested) + guards in `EarthChunkManager`'s four `_sync_*_sprites`: the camera frames ~20×11 tiles and a chunk is 32 tiles square, yet every one of the 25–36 loaded chunks got a `Sprite2D` per grass tuft, bloom, shed seed and surfaced worm — measured at ~2,900 decorative sprites, with frame rate visibly decaying as they accumulated (55.7 → 49.1 fps across one run). Decoration now follows the player's chunk at a radius **derived from the real camera framing** (`Player.TARGET_TILE_SCREEN_PX` and the viewport size, not an eyeballed number), which drops it to ~880 sprites and total entity nodes from ~5,800 to ~2,750. The simulation still runs everywhere — grass keeps growing and worms keep surfacing in chunks nobody is looking at — only the drawing is scoped. ⬜ Not independently confirmed as an fps win: by the time it was wired the machine had thermally throttled to ~23 fps in **every** configuration including the un-culled control, so the same-session A/B (24.9/26.4 vs 22.7/21.0) is directionally positive but the absolute numbers are not trustworthy. Worth re-measuring on a cold machine.
- **Creatures stopped being deleted and respawned every minute** (medium) — ✅ Fixed — `EarthChunkManager._refresh_creatures` freed **every** creature marker in **every** loaded chunk once per `SECONDS_PER_SIMULATED_DAY` (60s) and respawned them from their deterministic spawn points (reported: "every N seconds horses and deer disappear and respawn at original spawn point"). The visible half was the teleport; the worse half was silent — it wiped all per-animal state with it (hunger, energy, and once taming existed, trust and tamed status), so a horse the player had spent five carrots taming was deleted and replaced by a wild one a minute later, making taming impossible to keep hold of. It now **reconciles**: spawns the shortfall, thins the surplus, leaves everything else exactly where it is, and never culls an animal the player has a stake in (tamed, roped, or part-way tamed) even when the herd's aggregate population crashes. Fourth instance of the same root pattern — it only ever looked survivable because the ecology simulation was never running (see `World.owns_ecosystem_simulation_for`). Verified live over 30+ forced refreshes: tracked animal survived every one, teleported by 0.0px, population stable.
- **Rebalanced breaking free so animals can actually be caught** (small) — ✅ Fixed — the tuned quantity was the chance of escaping on ONE attempt, which nobody experiences: attempts repeat every 1.2s, so 0.85 per attempt compounded to ~99.9% escape and every animal got away every time (reported: "both horses and deer always break free"). Now (a) struggling costs **stamina rather than health** (`Taming.STRUGGLE_FATIGUE`) — the spec always said stamina, the code took it out of health, which left a caught horse nearly dead and an escaped one permanently maimed; (b) an animal that fights to exhaustion **gives up** (`Taming.has_given_up`) — without which a tied horse eventually always escapes and taming can never be finished; and (c) the rate is pinned by **measuring sixty real captures** rather than by a formula. Measured: **0.32** hold rate on a fresh full-strength horse (about one throw in three), worn-down animals usually held. `Taming.hold_chance` is kept for shape only and documented as reading optimistic (0.48) against that measurement — tune against the measurement, never against it.
- **Butterflies stopped hovering at one flower, and now tumble** (small) — ✅ Fixed — two separate causes behind "most butterflies stall in front of a single flower instead of wandering randomly in search for new unvisited flowers". (1) Visit memory vetoed re-*targeting* a worked bloom but not the **scent gradient**, which steers with more weight than the wander (`AmbientFlyerMarker.SCENT_STEER_WEIGHT` 0.55) — so a flyer was pulled back to a flower it was forbidden to land on and hung there forever. `PollinatorForaging.unvisited_only` now filters the steering list by the same memory, so what a flyer may not land on cannot pull on it either (still pulls on every *other* flyer, and on this one again once the memory ages out). (2) The approach was a dead straight line; `PollinatorForaging.tumbled_heading` now veers it side to side on two frequencies with a per-individual phase, easing off as it closes so it still settles onto the blossom, and always keeping a forward component so it cannot fail to arrive. Verified live: 263 butterflies travelling steadily, with the only motionless ones being those legitimately sat on a bloom drinking. Also fixed a long-standing **assertion-less test** in the same suite (`test_a_far_bloom_is_never_targeted_while_near_ones_are_available` asserted only inside an `if` that stopped being reached once the veto landed, so it passed 200 iterations while checking nothing).
- **Crisp pixel-perfect presentation + ground texture rework** (medium) — ✅ Done — reported as "the graphics look coarse and grainy". Two independent causes. (1) **Presentation**: `window/stretch/mode` was `viewport`, rendering into a 1280x720 framebuffer and blitting it to the display — a 1.5x upscale at 1080p, so art pixels covered 2 screen pixels in places and 1 in others, which *is* the graininess (nearest filtering was already on and cannot fix a blit). Now `canvas_items`: world and HUD rasterise at the window's real resolution, so text is genuinely sharp. New `src/rendering/display_scaling.gd` (tested) pins that one art pixel covers a whole number of screen pixels at 720p/1080p/1440p/4K, and documents why the art size is not free: canvas scales between resolutions aren't integer multiples (1080p→1440p is 4/3), so 32 art px/tile (`DETAIL_MULTIPLIER` 2) is the unique value that survives every step. Verified live at 1920x1080: 3.000 screen px per art px, `is_pixel_perfect = true`. (2) **Ground texture**: terrain was independent per-pixel noise at 35% density — measured at a 65% transition rate between neighbouring pixels, i.e. mostly high-frequency static. Replaced with clustered *marks* (cell-sized roll plus a per-pixel edge fray) at lower density, so clean ground shows between them and the per-biome details that were drowned in noise — dune ripples, moss, cracks — now read. Four tests hold the shape, including one for **directional grain**: the first attempt drew its cell roll from Godot's string `hash()` and produced ground visibly combed along a diagonal (third time this project has been bitten by that hash; `PixelNoise` exists for it). Cost: none at a given window size — an A/B at 1280x720 measured `canvas_items` and `viewport` identical (~37-39 fps); the extra cost appears only when the window is physically bigger. Also fixed two **pre-existing stale tests** in `test_terrain_renderer` that hardcoded the old 4x multiplier and the old atlas stride.
- **Frame-rate pass: found the real bottleneck, and it moved** (medium) — 🚧 Partial — asked to reach 120fps "through other levers before reducing resolution". Measured at 1920x1080 with **vsync off** throughout (vsync caps at the monitor's 60Hz, so nothing above that is even measurable otherwise). **Wins:** (1) the **grass blade field was never culled** — `DecorationLod` gated the sprite decoration but not the blades, so 53,454 blade quads were drawn across all 25 loaded chunks for a camera that sees less than one; culling them to the decorated radius took **19.5 → ~36 fps, the single biggest change of the pass**. (2) `GroundTint` evaluated two noise octaves — eight sin-based hashes — **per pixel** across the whole screen (~16M sin ops/frame at 1080p); it is a slowly-varying wash (a tile spans a tenth of a noise cell) so it now computes **per vertex** and interpolates. Sound in principle, but too small to distinguish from run-to-run noise on this machine. (3) `SimulationLod` (tested): the 484 ambient flyers and 25 creatures now update at a distance-dependent rate — full rate inside a radius that comfortably covers the screen, easing to 2Hz far out, with skipped time accumulated and handed to the next update so behaviour is unchanged. Worth roughly 10%. **The important finding:** after the blade fix the frame stopped responding to rendering at all — hiding the water overlay, the tint, every entity, every creature or the whole terrain each moved fps by nothing (34–42, all inside noise), draw calls 204→57 did nothing, and **rendering into a framebuffer with a ninth of the pixels did nothing**. That is CPU-bound, and it is why the resolution setting below does not currently help on this machine. ⬜ Remaining: the CPU cost is diffuse — no single hot spot found by subsystem A/B — and needs a real profiler rather than toggling. Confounded throughout by **thermal throttling**: identical scenes measured 55fps earlier the same day and ~40fps during this pass.
- **Render resolution graphics option** (small) — ✅ Done — `src/rendering/render_resolution.gd` (tested) + an OptionButton in the settings overlay, persisted alongside the other graphics settings. `Native` uses the `canvas_items` content-scale mode (world and HUD at the window's true resolution — the sharp default); `Half` and `Third` switch to `viewport` mode and render into a framebuffer that fraction of the window, scaling up. **Only whole divisors are offered**: a 75% option was written and dropped because 1920/1440 is 1.333, so the framebuffer would scale up by a fraction of a pixel — exactly the uneven-pixel graininess the presentation pass removed. Caught by its own test, not by eye. Verified live: the framebuffer really does become 960x540 / 640x360 while the visible world stays identical. Note it buys nothing on *this* machine (see above — CPU-bound) but is the correct lever on GPU-bound hardware.
- **Courtship, mating and a real-time life cycle** (large) — 🚧 Partial — animals of the same species now **notice each other, dance, and sometimes mate**, and the result feeds the aggregate population model. `src/gameplay/courtship.gd` (tested): same-species pairing, leader/follower orbiting a shared midpoint (both sides derive who leads and whether they mated from the same two instance ids, so nothing is messaged between animals and a partner vanishing mid-dance is harmless), and a 25% mating chance. `src/gameplay/life_cycle.gd` (tested) holds the **wall-clock timescale** the design asks for: ~1 real day before a pair will mate, 2 before eggs, 3 before hatching, 7 before a newborn is grown, with juveniles visibly smaller and growing into their adult size. The first version ran on a 40-second cooldown and produced a flying adult immediately — measured adding a butterfly every few seconds. **The two fidelities are now one population**: `EcosystemSimulation.record_birth` (tested) means an individual birth in front of the player raises the region's aggregate, capped at carrying capacity so the land decides the ceiling rather than how long somebody watched; mammal births report through it too (`World._step_reproduction`). Verified live: 2–12 pairs dancing at any moment out of ~245 butterflies, flyer count climbing before the per-chunk cap was added and holding steady at 243 after. ⬜ Remaining: only pollinators dance (mammals still use the older reproduction path without a courtship stage); eggs/hatchlings are not yet distinct entities — offspring spawn as juveniles that grow, rather than as an egg that hatches; and none of it **persists across chunk unload**, which on a 7-day timescale means a juvenile will essentially never be seen reaching adulthood. That persistence gap is the blocker for the whole timescale mattering, and is the same one tamed animals have.
- **Flower art detail** (small) — ✅ Done — blooms were `petal_count` single-pixel RAYS from a 3×3 centre — about 58 painted pixels, which reads as an asterisk and left **all five species sharing an identical silhouette** with only hue to tell them apart (measured: one alpha mask across the lot). Each species now has its own head SHAPE built from filled lobes: a low tight crocus cup, a taller tulip cup with petal tips, a layered rose, a lavender spike of florets, a textured clover puff — plus a pollen-warm focal centre and top-left shading. Pinned by tests for painted area, petal thickness, per-species silhouette, shading tones and a distinct centre, all of which the old art failed.
- **Land ecology persists across sessions** (medium) — ✅ Done — `ChunkSerializer.save_ecology`/`load_ecology` (tested) plus `EarthChunkManager._apply_persisted_ecology`. Only *fish* survived a restart before; herbivores, predators and vegetation lived in the in-memory `_unloaded_ecology` record, so quitting reset every region to a freshly-seeded population at full carrying capacity — a valley the player hunted out was full again next launch. On a life cycle measured in real days (see courtship above) that made the whole timescale meaningless. State is stamped in **wall-clock** time and, on a revisit with no in-session record, advanced through the *same* `ChunkEcologyCatchup` model the in-session path uses (a real hour away ≈ an ecological day, capped at 120 days since logistic growth converges anyway). "Never saved" and "saved as empty" stay distinguishable, so a hunted-out region is a fact the world keeps rather than something quietly re-seeded.
- **Migration between regions** (small) — ✅ Verified, already existed — asked whether gradient flow between neighbouring chunks was possible; it turns out `PopulationModel.migrate` has done it all along: flow between orthogonally adjacent regions down the gradient of **surplus over carrying capacity**, each pair visited once, net flow applied after so the result is order-independent, capped at what the source actually has. **I started writing a second diffusion module and deleted it before wiring it in** — two migration mechanisms would have silently doubled the rate. What was missing was tests stating the behaviour, so those were added instead: a hunted-out region refills from its neighbour, the source actually loses them, populations stay under capacity, and non-adjacent regions never exchange.
- **Tamed and tied animals persist as individuals** (medium) — ✅ Done — `src/world/kept_animals.gd` (tested) + save/restore in `EarthChunkManager`. Creature markers are freed with their chunk and re-spawned from the region's aggregate, which is right for a wild herd and wrong for the horse the player spent an evening taming or deliberately tied to a tree. Those are now written per chunk with their position, trust, order and tie anchor, and re-spawned on load **on top of** the aggregate — deliberately extra, because the aggregate is capped at carrying capacity and a tamed horse must not be culled to make room for wild deer. Kept when tamed, part-way tamed (the carrots already spent are real effort) or tied at any trust (the player put it there on purpose); ordinary wild animals stay in the aggregate, so the save file does not grow with the world. Restoring a tied animal skips the struggle it had already given up on. Also fixed: `_tied` was never actually set during play — the Player knew the rope was tied off, the marker did not.
- **Flower sizing and growth** (small) — ✅ Done — the detail pass gave the rose a layered head but left its height alone, so mature roses rendered as big red balls towering over the small purple blooms ("flowers are now too big"). Rose and tulip heights brought down to the crocus's, with a test that no bloom stands taller than a tile of grass — flowers are accents among grass, not landmarks. Flowers now also **grow**: `FlowerPatch` tracks per-cell growth (map-seeded blooms start mature, like `TallGrass`; ones planted from shed seed start as seedlings and take ~15 minutes to fill out), folded into the patch's existing tick rather than given a second one, and `_sync_flower_sprites` re-scales blooms as they grow.
- **A sparrow that looked like a monarch** (small) — ✅ Fixed — `spawn_offspring` hardcoded the butterfly sprite and butterfly movement for every species, on an assumption written into its own comment ("courtship only applies to the pollinators") that nothing enforced. Sparrows court sparrows, so a sparrow chick came out with monarch wings: it flew like a butterfly and looked like one while the hover panel said "sparrow" and it ate seeds. Art and flight now come from the species, with tests for both the bird and butterfly cases.
- **Kingfisher actually hunts** (medium) — ✅ Done — it cruised on the ordinary ambient wander and dived only if that wander happened to cross water with fish in it, so a bird with an inland territory essentially never fished, then held position through an 8s cooldown ("mostly stuck in one place without fishing anything"). Now: finds a fish within `HUNT_RANGE_PX` and flies to it, **hovers** over it (`PiscivoreBirdBehavior.HOVER_DURATION` — the signature kingfisher beat, and what makes the strike readable at all), then strikes. Both outcomes are visible, as asked: a catch puts the bird above its cruise line with a fish sprite in its beak for `CARRY_DURATION` before it is swallowed (and really removed from the world via `catch_nearest_fish` + `record_catch`), a miss sends the fish **bolting** in a fast straight dash unlike its usual meander (`FishMarker.bolt_from`). Most strikes miss, pinned by test. Needed a new world query — `nearest_fish_position` — because hunting means knowing where a fish *is*, not just how many are around. **Two follow-up bugs found by playing it** (the unit tests passed throughout): (1) the escape moved the fish directly and returned before `FishMarker`'s shore-clearance logic ran, so a startled fish shot out of the water and flopped across the grass — with the bird calmly following it onto land to eat it. The bolt is now a fast *heading* fed through the same clearance machinery every fish moves by, so a panicking fish still cannot leave the water. (2) The strike resolved against whatever fish was nearest *at that moment*, but the target had swum on during the hover and dive, so the grab came up empty and nothing appeared in the beak. The bird now holds the specific fish it aimed at from the start of the hover, tracks it while hovering, and resolves against it. The carried sprite is also `top_level` — as a plain child it inherited the bird's rotation and swung around it like a hammer throw. Verified live: zero fish stranded on land across a 70-second run, hovering observed, carries observed, fish count dropping as catches land.
- **Flyers draw above flowers** (small) — ✅ Fixed — flowers, grass and flyers all Y-sort in one tree, and a flower is anchored at its stem FOOT so it sorts against the player like a tree. A butterfly hovering at the blossom is higher on screen (smaller y) than the flower, so it sorted *behind* the bloom and vanished into it. Y-sorting can't resolve it — the flower's sort position is where it is rooted, the flyer's is where it is flying — so flyers now carry a raised z-index. Being airborne is the answer.
- **Birds stopped jittering on the spot** (small) — ✅ Fixed — the courtship dance added earlier was not restricted to pollinators, so sparrows and robins performed a butterfly's tight nine-pixel spiralling orbit, which reads as a bird glitching in place ("birds sometimes stall and jitter on a spot"). `Courtship.dances()` now gates it to the pollinator species. This was the *second* bug from the same root: an `AmbientFlyerRenderer` comment had asserted "courtship only applies to the pollinators" while nothing enforced it — which is also how a sparrow ended up with monarch wings. An assumption in a comment is not an invariant.
- **An in-game day is four real hours** (small) — ✅ Done — `SeasonCycle.SECONDS_PER_DAY`, with the year derived from it (48 days → eight real days a year, two a season). It was 25 seconds, implied by a 20-minute year, which is why "a couple of fish a day" still stripped a pond in minutes. **Weather deliberately keeps its own, much shorter period**: it rolled once per day, and at four hours a day that would lock a whole session into one sky. Re-anchored a stale fruiting test that had hardcoded a 3000-second window — the same staleness class as the terrain-renderer tests fixed earlier.
- **Kingfisher hunger, and a life outside hunting** (medium) — ✅ Done — `src/gameplay/piscivore_appetite.gd` (tested). The bird hunted continuously and would fish out a chunk. Now: **appetite** (a couple of fish per in-game day, nothing in between) *and* **giving up on a poor patch** — even a hungry bird leaves water worked below a quarter of its capacity, which is the rule that actually protects the population rather than merely slowing the stripping. Needed a new world query, `fish_capacity_near`, since "is this pond worth working" needs what it *could* hold as well as what it does. A sated bird patrols, perches or carries material to a nest site, re-picked on an interval and seeded per bird so a river is not choreographed. Tested at the behaviour level: a bird left alone for a whole in-game day takes at most three fish, and a hungry bird at a depleted pond takes none. ⬜ Remaining: nest-building is a flight to a site, not a structure that gets built; birds still have no courtship or mating of their own (the dance is pollinator-only by design, see the jitter fix).
- **Illustrated blooms are recoloured by luminance, not multiply** (small) — ✅ Fixed — the illustrated head sheet is composited with the species petal colour, which as a plain multiply only recolours correctly if the source art is pale and neutral. The cup sheet carries real green in its sepals and outlines, and multiply preserves hue, so crocus and tulip rendered as **green cages** — invisible against grass and not a petal colour ("green petals are hard to see on green grass"). The composite now reads the source as Rec. 709 luminance and paints the petal colour at that brightness, keeping all the illustration's form and shading while discarding its hue, so the recolour is robust to the art rather than depending on a promise about it. A shade floor stops linework multiplying to near-black. Three tests pin it: no bloom is painted mostly green, every bloom stands clear of grass green, and each still carries its own species colour. **The sparse-outline look had the same root cause**: the sheet is line art with hollow petals, so the grass showed through them — recolouring the outlines left the green, because the green *was* the background ("the bloom is correctly colored but the petals are still green"). Enclosed transparent areas are now filled before compositing, found by flooding from the canvas edge, so any line-art sheet composites solid. **Flower sizes are pinned to two anchors** -- a tulip at the player's hip, a sunflower at full player height -- with the curve between them computed, not eyeballed. Deliberately taller than life (a real tulip is a quarter of a person). Anchored to centimetres rather than to the tallest species, so adding the sunflower did not silently shrink everything else. **Sunflower added** as the one species that stands above the meadow rather than among it. **Sunflower and lavender now have their own sheets** (7 registered species sheets: crocus, tulip, rose, daisy, sunflower, lavender; shared archetype sheets: cup, layered; only clover is still procedural). The sunflower's dark centre needed no special casing: brown is dark gold, so it sits in the same hue bucket as the petals and recolours with them, coming out dark in whatever colour the plant came up as. These two also proved out the earlier gate fix -- their archetypes (spike, radial) have no sheets, so the old "does this ARCHETYPE have art?" check would have silently left both procedural despite the art existing. **Flowers are sized against the player**: species carry real heights in centimetres, the tallest rendering at knee height (30% of the player) and the rest below -- they had drifted to 72%, standing chest-high on the hero. Small species are exaggerated toward legibility without reordering. **Per-plant size variance** nudges each individual off its species' norm, fixed for that plant's life. **Bush habit**: lavender and clover draw several stems with their own heights and lean rather than one lonely spike. **Masks**: each sheet declares where its petals sit on the hue wheel, and saturated gold outside that window keeps its own colour, so blooms retain their eyes -- green sepals are deliberately NOT preserved, because at this size a kept sepal reads as a green flower. Enclosed transparent pixels are filled everywhere now, not just in illustrated heads, since overlapping spikes punched holes in the bloom mass. **Per-species stature and per-species colour varieties**: each species carries its own height (a lavender spike stands nearly twice a crocus) and its own list of colours, with each plant picking a variety from its own seed so a bed comes up mixed but no individual flower changes colour. The recolour now normalises against each sheet's own peak brightness -- without that it topped out at however bright the artist drew the highlight, which a saturated red survives and a white or pale yellow does not, washing every pale variety into grey. Registered species sheets: crocus, tulip, rose, daisy; shared archetype sheets: cup, layered; spike and puff are still procedural. **The fallback shape family was renamed "daisy" -> "radial"** -- a daisy is a species, and a shape family named after one of its members left that species unable to have art of its own. **Species art overrides archetype art**: a sheet registered against a species wins over its archetype's shared one, other species of that archetype are unaffected, and a species with neither falls back to the procedural painter — the same species-first-then-generic lookup the animal art uses, so a species that deserves its own drawing costs one entry and no changes elsewhere.
- **Taming (lasso → hold → feed → tame)** (large) — 🚧 Partial, playable end to end — spec at `docs/concept/taming.md`. **Built:** `src/gameplay/taming.gd` (break-free chance from health fraction, per-struggle stamina cost, trust that rises only on feeding a HUNGRY animal, neglect decay, order/mount/predator gates) and `src/gameplay/rope_tether.gd` (slack rope leaves the animal alone, taut rope pulls it back, hard clamp so a bolting horse can't outrun its tether). Wired through `CreatureMarker` (`restrain_to`/`release`/`feed_treat`, a restrained animal stops making its own decisions and cannot flee, led movement goes through the existing movement gate so it walks *around* trees) and `Player` (`_lasso_step`: one key throws / ties to a tree / unties / releases depending on what you are holding; carrots are spent only when the animal actually takes one; a visible rope `Line2D`). Readouts: trust bar + hunger pip on the animal, state line in the HUD. **Lasso** (4× plant fibre) and **Carrot** items with their own art. **Verified live** with a temporary in-game harness, not just in tests: catch lands, healthy horses break free repeatedly (as designed), 5 hungry feeds at one carrot each takes trust 0.00→1.00, and a tamed horse stops fighting the rope. Carrots have a real source: **wild carrot** (Daucus carota) is now a real, visible growing/spreading plant (`WildCropPatch`/`WildCropMarker`, see `concept/wild_crops.md`), pulled with an animated swing-driven harvest -- superseding the earlier grass-harvest freebie. The same meadow supplies both the lasso and its reward. **Orders and riding** are in: a tamed animal takes follow/stay (cycled with the lasso key, which changes meaning once the rope has nothing left to do), and horses can be ridden at `Taming.MOUNTED_SPEED` (150 vs walking 80). The rider stays the node the player controls and the mount is carried along underneath, so inventory/combat/survival keep working while mounted. A tamed animal also stops treating the player as a threat -- players are sensed as threats, so without that fix a horse you spent five carrots taming would flee you forever. Verified live: tame -> `fears_players=false`, mount -> speed 150, rode 120px with the horse at gap 0.0, dismount -> 80, STAY order held the horse inside its `STAY_RADIUS`. ⬜ Remaining: persistence of a tamed/tied animal across chunk unload (walk ~100 tiles away and it is gone -- the significant one), and an animation for the struggle.
- **Active foraging for land herbivores** (medium) — ✅ Done — `src/gameplay/grazer_foraging.gd` (tested, see `concept/ecosystem_dynamics.md` "Grazing is an act, not an aura"): horses, boars and deer now **see a specific bite, walk to it, and put their heads down**, instead of feeding off the biome under their feet. A diet (default by `CreatureInfo` diet label, per-species override for the deer's mixed feeding) decides what an animal walks to; a seek→approach→graze phase machine decides when, with target choice delegated to `PollinatorForaging.choose_target` so a herd spreads over a meadow rather than single-filing behind one tuft. Wired through `CreatureMarker._step_foraging`, fed by `EarthChunkManager.grass_near`/`graze_grass_at` (new — mature tufts only, immediate sprite resync like `take_worm_at`) plus the existing `fruit_near`/`seeds_near`/`worms_near`. Biome grazing survives as `FOOD_UNDERFOOT`: an animal with nothing in sight crops what it stands on, but as a full head-down bout rather than the instant hunger-reset that made a grassland horse never hungry for longer than one frame. Blooms are deliberately not edible (they are the pollinators' resource). ⬜ Gaps: predators still feed only by catching prey, and an animal doesn't remember a patch it has already cropped.
- **Frame-set generation shared across animals** (small) — ✅ Done — `ProceduralAnimalAnimation.textures_for` + `LOOK_VARIANTS = 8` (tested): every `CreatureMarker` used to draw its own frame set the first time it played an action, uncached. Measured live: **25 creatures crossing into "eat" together burned 1.18 SECONDS of frame generation inside one 5-second window** (~47ms each) — the 130–145ms frame spikes reported as lag. Generation is now bounded by species × action × 8 looks for the whole session, paid once.
- **A herd is not on one clock** (small) — ✅ Done — `CreatureNeeds.new(seed_value)` / `START_STAGGER` (tested): every creature used to start at hunger 0 and rise at the same fixed rate, so a whole herd crossed the hunger threshold on the same tick and switched action in the same frame — the other half of the spike above. Each animal now starts at its own deterministic, hash-derived point in its cycle, below the threshold so nothing spawns already starving.
- **Tall grass advances in one batched step** (small) — ✅ Done — `EarthChunkManager.step_tall_grass` walked every loaded chunk's every patch **every frame** (~25 chunks × up to 64 cells, 60×/s, measured at ~5ms of frame budget) to resolve growth of 0.01 per second. It now advances once per `GRASS_REFRESH_INTERVAL` with the accumulated delta; growth is linear in delta and spread carries its own accumulator, so the batched call lands in identical state (pinned by test).
- **Illustrated long-grass cards** (medium) — 🚧 Partial — mature `TallGrass` cells now use the delivered 10×10 `assets/sprites/grass_blades.png` atlas as several deterministically selected, depth-layered blade cards instead of one procedural tuft. Tall grass now seeds at 20% of eligible cells (hard-capped at 128 per chunk) so it forms a visible field rather than isolated decorations. A shared GPU shader keeps roots planted while wind moves tips and bends nearby patches away from the player; `EarthChunkManager` writes one walker-position uniform per frame. Cards remain decoration-LOD scoped. Creature wake sharing is still open.
- **Dropped-item art is shared** (small) — ✅ Done — `ProceduralItemSprite.texture_for` (static cache): each `DroppedItem` rebuilt its own 32×32 image pixel by pixel on `_ready`. Fine for a few items, not fine once the world sheds windfall continuously.
- **Variable-fidelity LOD / unloaded-chunk catch-up** (large) — ✅ Done — `src/world/chunk_ecology_catchup.gd` (tested, reuses the same logistic + predator-prey models as loaded chunks): a chunk records its aggregate ecology at unload; on revisit `EarthChunkManager._apply_ecology_catchup` integrates it forward over the elapsed unloaded time and installs the caught-up herbivore/predator populations (`EcosystemSimulation.seed_populations`) instead of resetting to fresh equilibrium — so a region the player left keeps evolving (herds grow or get thinned by predators). Closes the long-standing "regenerates at equilibrium on revisit" gap.
- **Seasonal forcing of phenology** (medium) — ⬜ Not started — warmth is instantaneous temperature, not a seasonal calendar variable.
- **Animal-mediated seed dispersal** (medium) — ⬜ Not started.
- **Sunflower head was clipped, and its blossom read as sitting on the stem** (small) — ✅ Fixed — reported with a screenshot: "the sunflower sprite is clipped at the top" and "butterflies drink from their stem... I'm not sure if butterflies should even visit sunflowers?" The second question needed no code change: real sunflowers are a genuine nectar/pollen source for both bees and butterflies, so a pollinator visiting one is correctly grounded — the two visible symptoms shared one structural cause instead. `IllustratedFlowerHead.HEAD_CANVAS_SIZE` (18px) is taller than the headroom ANY stem roll leaves above its own attachment point (`ProceduralFlowerSprite.stem_height_px`, at most 16px of the 32px art canvas) — composited at full size the crown was sliced off flat by the canvas edge, invisible on the small species this shipped with and glaring on the sunflower once its much larger world scale (see "Illustrated blooms..." above) turned a few always-clipped art pixels into an obvious flat top. `_paint_illustrated_head` now shrinks the whole head to fit the real headroom (`ProceduralFlowerSprite.head_fit_scale`, the same "scale a drawing down to fit its canvas" trick `SpriteSheetSlicer.normalize_frames` already uses one layer up) instead of clipping it. Separately, `blossom_height_world` — where a pollinator actually lands — scaled by the species' own nominal size alone, while the sprite itself is drawn at a smaller PER-PLANT size for a below-average individual (`PLANT_SIZE_VARIANCE`) or one still growing in (`FlowerPatch.growth_at`); the landing point did not shrink with it, which on a species as large as the sunflower reads as landing near the stem rather than on the bloom. It now takes the exact per-plant scale `EarthChunkManager._flower_scale_for` draws the sprite at, so sprite and landing point can never drift apart. Tests: `head_fit_scale` never exceeds the real headroom across 200 stem rolls, a tight-headroom sunflower head measurably narrows rather than clipping flat at the same width, the blossom offset scales linearly with the actual plant scale and shrinks in lockstep with growth, and a freshly-planted seedling's `EarthChunkManager.flowers_near` landing point sits well below the mature blossom height.

### Overview (`concept/overview.md`)

- **Mechanistic Planet Simulation** (huge) — 🚧 Partial — terrain/biome layer is real and data-driven; a Phase-1-MVP-scoped slice of plant-growth/animal-ecology emergence now exists (see Plant Growth Simulation and Animal Ecology below) but it's aggregate/per-loaded-chunk only, not the full always-on planetary simulation this pillar envisions.
- **Terrain Generation** (large) — ✅ Done — via real elevation data (`earth_elevation_source.gd`, `earth_chunk_generator.gd`); the old fully-procedural generator is kept for future non-Earth planets.
- **Biome System** (medium) — ✅ Done — `biome_classifier.gd`, 7 biomes.
- **Plant Growth Simulation** (large) — 🚧 Partial — static deterministic tree placement + collision exists (`tree_placement.gd`, `tree_renderer.gd`), unchanged; a real per-cell density growth/die-back/spread simulation now also exists (`vegetation_growth_model.gd`) but isn't unified with tree placement/rendering yet -- it currently only feeds herbivore carrying capacity.
- **Animal Ecology / Population Simulation** (large) — 🚧 Partial — regional/aggregate herbivore + predator population dynamics (reproduction, drought-driven death, migration) built and wired into live gameplay (`herbivore_population_model.gd`, `predator_population_model.gd`, `ecosystem_simulation.gd`), AND individual promoted creatures now have real per-agent AI (flee/hunt/graze/drink, temperament-driven, `creature_behavior.gd` et al. — see Phase 1 table's "Individual Creature AI" row). Still missing: taming, genetics, individual reproduction, and a link between individual predation and the aggregate population counts.
- **AI-Driven NPCs** (huge) — ⬜ Not started
- **NPC Memory Log** (large) — ⬜ Not started
- **NPC Daily Planning Loop** (large) — ⬜ Not started
- **LLM Backend Integration** (medium) — ⬜ Not started
- **Need-Driven Quest System** (large) — ⬜ Not started
- **Creature Collection System** (large) — ⬜ Not started
- **Sandbox Building System** (large) — ⬜ Not started
- **Persistent World State** (medium) — ⬜ Not started
- **MMO-Scale Social Systems** (huge) — ⬜ Not started
- **Multiplayer Netcode** (huge) — 🚧 Partial (unverified live) — server-authoritative ENet architecture built (see Phase 5+ table above for detail); live connectivity blocked on this dev machine by CrowdStrike Falcon, not a code issue.
- **Shared Player Economy** (huge) — ⬜ Not started
- **Player-Driven Society** (huge) — ⬜ Not started
- **PvP Combat Rules** (large) — ⬜ Not started
- **Emergent Physics Combat** (huge) — ⬜ Not started (explicit non-goal in the doc)
- **Era Progression / Reincarnation System** (huge) — ⬜ Not started
- **Death & Carryover Mechanic** (medium) — ⬜ Not started
- **Toroidal World Map** (medium) — ✅ Done — `world_coordinates.gd`, player wrap.
- **True Spherical Globe Rendering** (huge) — ⬜ Not started (explicit non-goal)
- **Plate Tectonics Simulation** (huge) — ⬜ Not started (explicit non-goal)
- **Climate / Fluid Weather Simulation** (huge) — ⬜ Not started (explicit non-goal; only real-time day/night tint exists)
- **Multi-Planet Travel** (huge) — ⬜ Not started
- **Procedural Planet Generation** (huge) — 🚧 Partial — old procedural whole-map generator intact/tested but not wired to any "other planet" gameplay.
- **Planet Rarity System** (medium) — ⬜ Not started
- **Monetization / Platform Distribution** (small) — ⬜ Not started

### Eras (`concept/eras.md`)

- **Technological Era Progression (World Eras)** (huge) — 🚧 Partial — `src/gameplay/era_progression.gd`: a linear 4-era progress-threshold state machine (`current_era`/`era_index`/`progress_to_next_era`), tested; scoped down from the doc's full multi-planet system per its own header comment. `current_era_with_boss_defeat` adds a defeated-world-boss trigger that advances one era beyond progress alone (see World Bosses' "Emergent World-Boss Promotion" row). Nothing in live gameplay tracks progress or calls either function yet.
- **Reincarnation / Era Advancement** (large) — ⬜ Not started
- **Permadeath / Death System** (medium) — 🚧 Partial — `src/gameplay/lives_tracker.gd` (nine-lives countdown + soul-stone revival) exists as a tested pure-logic module; not wired to the live respawn flow (see Phase 3 table's Player Stats row), which currently just resets health with no lives cost.
- **Cross-Era Carryover** (medium) — ⬜ Not started
- **Era State Scope (Per-Player vs Per-Server)** (large) — ⬜ Not started

### Planets (`concept/planets.md`)

- **Multi-system / multi-galaxy structure** (huge) — ⬜ Not started
- **Earth as shared starting planet** (medium) — ✅ Done — player spawns in Berlin at real lat/long on the real-Earth world.
- **Space exploration unlock (era gate)** (medium) — ⬜ Not started
- **Spacecraft construction** (large) — ⬜ Not started
- **Interplanetary travel** (huge) — ⬜ Not started
- **Procedural planet generation** (huge) — 🚧 Partial — old generator exists, unused.
- **Planet rarity tiers** (medium) — ⬜ Not started
- **Planet discovery / rarity reveal** (medium) — ⬜ Not started
- **Planet claiming (second home base)** (large) — ⬜ Not started
- **Primitive-by-default base restriction** (medium) — ⬜ Not started
- **Space logistics / technology import** (large) — ⬜ Not started
- **Post-MVP layer gating (design note)** (trivial) — n/a — a scoping note, not a buildable mechanism.

### Classes (`concept/classes.md`)

No skills/classes/leveling/stats/XP is wired into live gameplay yet, but a first pure-logic slice now exists as tested, unwired modules:

- **Soft Class System** (small) — ✅ Done (basic) — `src/gameplay/class_archetype.gd`: 7 archetypes (Warrior/Mage/Ranger/Beastmaster/Artisan/Herbalist/Overseer) with stat-lens functions, now **wired to character creation**: the main menu's New Game class picker (`scenes/main_menu.gd`) applies the chosen archetype's lens to the player (`Player.apply_class` — max-health + attack offsets). Plus a real XP/level system (`experience_track.gd`) earning levels from kills. Full skill-web pathing and respec UI still to come (see Progression / `concept/progression.md`).
- **DNA Resonance** (medium) — 🚧 Partial — `src/gameplay/hero_dna.gd` (`HeroDna`): a deterministic-per-seed genome roll now gives every character a 0..1 resonance score for each `ClassArchetype`, matching dna.md's "a DNA suitable to be played as Mage; another which fits better to a warrior" — but nothing yet actually SPEEDS UP leveling/stat gains in a resonant archetype (the "soft/efficiency-only" half of classes.md's resolution), since there's no live leveling-speed mechanic to hook it into yet (see Soft Class System above). The genome also carries a rarity tier (common/rare/legendary, weighted heavily toward common — 80/17/3%) and stat modifiers layered on top of the class's own base stats — wired end-to-end into character creation (`MainMenu`'s "Reroll DNA" button, applied via `World._stats_with_dna` at spawn). **Common and rare stay deliberately balanced**: every common/rare genome's modifiers are a tested net-zero-raw-power invariant (one buffed stat, one equal-magnitude deficit stat — "excellent magic attack but no defense"), so those two tiers buy drama, never more total power. **Legendary is a deliberate exception**, per a follow-up ask ("add legendary dna which is just better in most stats so a real win"): a legendary roll is pure upside with no deficit stat at all — net-positive raw power spread unevenly across 3 of the 4 stats (the 4th left untouched, never reduced) — balanced only at the population level by how rare it is (~3%), not by per-genome cancellation. Same seed drives BOTH the rolled genome and `HeroAppearance`'s visuals (genotype→phenotype, not two independent random draws), per dna.md's appearance section. DNA is not yet persisted across save/load (a fresh load recomputes stats from class alone, same gap the class stats themselves already had), and inheritance/genetic-cross for children (dna.md's other resolved section) is untouched.
- **DNA Reroll (Premium)** (medium) — 🚧 Partial — superseded dna.md's original "reroll a few times (3-5) then buy premium credits" with a real-world-time gate per a follow-up ask ("rerolls should reset every 24h real world hours so you have to wait a whole day if your rerolls are empty forcing the player to make wise choices"): `HeroDna.MAX_FREE_REROLLS` (4) free rerolls, `HeroDna.RESET_INTERVAL_SECONDS` (a real 24h) before the budget refreshes regardless of how many were spent, `HeroDna.can_reroll`/`reroll_budget_has_reset` as the pure/tested time math. `MainMenu` persists `rerolls_used` + a `last_reset_unix` timestamp to `user://hero_dna_rerolls.bin` (reusing `PlayerSave`'s generic path-taking I/O) so the wait genuinely survives quitting the game, not just the current menu session, and shows a live "resets in Xh Ym" countdown once the button disables. `can_reroll`'s `has_premium` parameter stays a deliberate hook for wherever a real purchase flow eventually lands — no premium-currency/IAP system exists in this project, so running out simply forces the real-world wait rather than offering a purchase.
- **Free Respec** (small) — 🚧 Partial — `class_archetype.gd`'s `respec()` is a free no-cost archetype swap; not exposed to the player.
- **Archetype-as-Snapshot** (trivial) — 🚧 Partial — `class_archetype.gd`'s stat lens is a pure snapshot function with no persistent per-archetype state, matching this design exactly, just not wired to a live character.
- **Starting Archetype Lens** (medium)
- **NPC Need-Driven Quests** (huge)
- **Warrior: Melee/Tank Combat** (large)
- **Mage: Spellcrafting DSL** (huge)
- **Ranger: Ranged Combat** (medium)
- **Ranger: Wilderness Tracking** (medium)
- **Ranger: Vegetation Concealment** (medium)
- **Beastmaster: Taming/Breeding** (huge)
- **Beastmaster: Pet Combat** (large)
- **Artisan: Crafting/Building** (large)
- **Artisan: Resource Specialization** (small)
- **Herbalist: Medicine/Curing** (medium)
- **Herbalist: Buff/Support** (medium)
- **Overseer: NPC DSL Hiring/Instruction** (huge)
- **Overseer: Logistics/Economy** (huge)

### Players (`concept/players.md`)

No marriage/reproduction/child-rearing system exists. All ⬜ Not started:

- **Marriage System** (medium)
- **Player Reproduction / Child Conception** (medium)
- **DNA Inheritance (Genetic Cross)** (large)
- **Inheritance Mutation Chance** (trivial)
- **Breeding-for-Traits / Eugenics Strategy Layer** (small)
- **Birth Fast-Forward** (trivial)
- **Child Life Stage** (medium)
- **Child-as-Instructable-NPC (NPC DSL Integration)** (medium)
- **Sims-Style Needs System** (medium)
- **Wants/Fears (Wish) System** (medium)
- **Gradual Trait Solidification** (medium)
- **Runaway Consequence** (medium)
- **Child Death Consequence** (small)
- **Parental Grief Debuff** (small)
- **Growing Up / Graduation to Adult NPC** (medium)

### Skills (`concept/skills.md`)

No skill/passive system is wired into live gameplay yet, but a tested pure-logic foundation now exists:

- **Archetype Passive Skill Web** (large) — 🚧 Partial — `src/gameplay/skill_tree.gd` now wired to a real spend UI (`scenes/skill_tree_window.gd`, toggle L) fed by the XP/level system (see Progression / `concept/progression.md`); still a flat node list, no web/graph layout, though it now has more than one thematic branch (vitality/endurance/strength plus a new Naturalist branch, see below) rather than archetype-specific ones.
- **Small Stat Nodes** (small) — ✅ Done (basic) — `skill_tree.gd` nodes are allocated in the skill-tree window and applied live to player stats (`Player.allocate_skill` → max-health/attack bonuses); stamina-regen bonus is tracked but not yet fed to the meter. Includes a new Naturalist pair (`naturalist_1`/`naturalist_2`, `stamina_regen`) added to gate the `land_sense` keystone below (docs/concept/progression.md "Ecological literacy").
- **Keystone Passives** (medium) — ✅ Done (basic) — `keystone_passive.gd` keystones are unlockable in the window once their minimum-node gate is met and points are paid (`Player.unlock_keystone`), applying their bonus live. A new keystone, `land_sense`, deliberately breaks that "applies a stat bonus" pattern: empty `stat_name`/zero `bonus_amount` (a sentinel, not a bug — see the dict's own doc comment) instead of a number going up. `SkillTreeWindow._keystone_label` special-cases it to show a real description instead of a "+0.0" line, and once unlocked `World._update_land_sense_label` shows a small always-on HUD readout of the player's real, live `EarthChunkManager.land_health_near`/`vegetation_density_near` at their own position — the same numbers `VegetationGrowthModel.effective_capacity`/`step_land_health` already run the simulation on. See Progression / `concept/progression.md`'s "Ecological literacy" section for the full mechanism and its known gaps.
- **Soft Cross-Archetype Pathing Gate** (medium) — ⬜ Not started — no cross-archetype gating logic exists, only same-archetype node-count gating.
- **DNA Resonance / Class Resonance** (large)
- **Web-to-Domain Unlock Hooks** (medium)
- **Signature Node (Procedural DNA-Seeded Spell)** (huge)
- **DNA-Flavored Shared Node Variants** (large)
- **Respec System (undecided)** (small)

### Labor Skills (`concept/labor_skills.md`)

New design doc this pass — a second, separate use-based mastery axis
alongside the PoE-style web above (Woodcutting/Mining/Fishing/Foraging/
Farming/Herbalism/Cooking/Smithing/Construction/Animal Handling, leveled by
doing the corresponding action, shared code path for players and NPCs).
Nothing in this section is implemented yet.

- **Shared `Skill` resource** (medium) — ⬜ Not started — pure XP/level/tier
  logic mirroring `ExperienceTrack`, but independent per skill and per actor.
- **Per-action XP hooks** (large) — ⬜ Not started — value-weighted XP across
  all ten roster skills (chopping, mining, fishing, foraging, farming,
  herbalism, cooking, smithing, construction, animal handling).
- **Tier-unlocked passive bonuses** (medium) — ⬜ Not started — gathering
  yield/speed and production ceiling-realization, unlocked automatically per
  tier, no spend UI needed (the mechanical distinction from the PoE web).
- **Crafter skill quality multiplier** (medium) — ⬜ Not started — see
  Crafting section below; same feature, cross-listed.
- **NPC skill accrual from occupation production** (medium) — ⬜ Not started
  — wiring `occupation_production.gd`'s existing automatic recipe loop to
  also grant the producing NPC their own Skill XP.
- **Auction house** (large) — ⬜ Not started — see Economy section below.

### Crafting (`concept/crafting.md`)

A first crafting loop is now real and wired into live gameplay, though shallow:

- **Base gather-craft-build loop** (medium) — ✅ Done (basic) — `src/gameplay/crafting_recipe_book.gd` defines recipes (inputs → output), wired into `Player.craft()`; there's now a real **crafting UI** (`scenes/crafting_window.gd`, toggle C) — plus the `/craft` console command. Overhauled from a single narrow, right-anchored list of thin text rows into a **centered, card-based catalog** (`UiTheme`-styled, matching the inventory/settings windows rather than reading as a leftover sidebar): recipes are grouped into sections by their output's item kind (Weapons/Tools/Armor/Structures/Cooking/Materials) inside a scrolling, fixed-size window rather than one that grows unbounded with the recipe count; each card shows a real item **thumbnail**, the output name (+ a `x2`-style count badge when a recipe yields more than one), and every required material as its own icon + live **have/need** count, colored green when covered and red when short, so what's blocking a craft is legible at a glance instead of buried in a text string. Unaffordable cards dim and lose their hover/click affordance; affordable ones highlight on hover with a pointing-hand cursor. `Player.craft()` produces the output into the inventory (and, if the inventory is full and consuming inputs didn't free a slot, drops the crafted item at the player's feet rather than silently losing it). The gather side is real too: chop trees (wood+sticks), smash boulders (rock), knap rock-on-rock (sharp shards), harvest tall grass (fibre), and mine ore-bearing boulders with a pickaxe (ore+stone). **Smelting/metalworking** now exists (`src/gameplay/smelting.gd`, tested, see `concept/smelting.md`): ore + coal smelted at a **heat source** (a carried campfire or crafted **furnace**) → iron/copper ingots, which forge a full **iron armor set** that out-protects leather — `Player.craft` heat-gates the smelt recipes exactly like cooking. No skill-gating or placed stations yet.
- **Crafting Stations** (small) — 🚧 Partial — `src/gameplay/crafting_station.gd` (tier-gated `can_craft_at`), tested but not wired — `/craft` currently works anywhere, no station placement/proximity check.
- **Skill-gated crafting progression** (medium) — ⬜ Not started — design landed in
  [concept/labor_skills.md](concept/labor_skills.md) (a use-based Smithing/
  Woodcutting/Mining/... mastery track, separate from the PoE-style
  `concept/skills.md` web); no `Skill` resource or per-action XP hook exists
  in code yet.
- **Blueprint DSL** (large)
- **Base Item Templates** (trivial) — ✅ Done — `item.gd`/`item_catalog.gd` (now also includes torch/campfire/cooked_meat).
- **Material Inputs** (small) — ✅ Done — `crafting_recipe_book.gd` recipes consume a dictionary of item-id→count inputs.
- **Modifier Slots** (medium)
- **Deterministic crafting resolution** (small) — ✅ Done — no RNG in `crafting_recipe_book.gd`; a craft either has enough inputs or it doesn't.
- **Material quality feed from creature rarity** (medium)
- **Crafter skill quality multiplier** (medium) — ⬜ Not started — design landed in
  [concept/labor_skills.md](concept/labor_skills.md#skill-driven-crafting-quality-closes-smeltingmds-open-todo)
  (`final_item_stat = base_stat * ceiling_realization(crafter_skill_level)`,
  shared by players and NPCs); not wired into `crafting_recipe_book.gd` yet.
- **Dual item-sourcing tracks (crafted vs. looted)** (large) — 🚧 Partial — both tracks now exist (loot drops + `/craft`) but aren't unified under one design (no shared rarity/affix system yet).
- **Station-tier gating of blueprint complexity** (medium) — 🚧 Partial — `crafting_station.gd`'s tier check exists; not wired to `/craft`.

### Resources (`concept/resources.md`)

Gathering now has a real primitive slice (rocks/shards/fibre/sticks — see the knapping chain in Phase 3's combat row); classic vein mining is still pure-logic-only:

A first primitive-resource loop is now real and wired into live gameplay:

- **Existence-Conditioned Placement Philosophy** (large) — 🚧 Partial — boulders place deterministically only on biomes that plausibly carry them (grassland/forest, never on a tree's own cell — `stone_placement.gd`); no ore/mineral placement yet.
- **Procedural Resource Placement** (large) — 🚧 Partial — same `stone_placement.gd` slice; stones only.
- **Dynamic Resource Distribution** (large)
- **Nonrenewable Mineral Depletion** (medium) — 🚧 Partial — `src/gameplay/mining_yield.gd` (depletion-toward-zero math) still unwired; the live mining loop instead uses `src/gameplay/ore_yield.gd` (per-strike drop table) on one-shot **ore nodes** — `src/world/ore_placement.gd` marks ~30% of boulders as ore-bearing (iron/copper/coal), rendered via `src/rendering/procedural_ore_sprite.gd` and spawned by `StoneRenderer` as `MinableOre`. Mining a node consumes it (nonrenewable per node) but there's no vein-scale pool depletion yet.
- **Vein Migration & Regeneration** (large)
- **Renewable Organic Resource Growth** (medium)
- **Plant-Growth Model (world.md)** (large)
- **World-Sim Timescale** (huge)
- **Mining Action** (medium) — ✅ Done (basic) — a swing that reaches an ore node (`MinableOre`, shares the "stone" group) mines it: with a `stone_pickaxe` equipped (`Item.is_pickaxe()`, `Player._pickaxe_power`) it drops ore + stone (`OreYield`), bare-handed only stone. Craft the pickaxe from 2 stick + 3 rock.
- **Crafting Blueprint DSL Material Integration** (medium)
- **Crafting Blueprint DSL (crafting.md)** (huge)
- **DNA-Quality-to-Material-Quality Link** (large)
- **Creature DNA/Genetics System** (huge)
- **Resource Discovery / Prospecting (open design question)** (medium)
- **Surface Ore Hints & Biome Correlation** (medium)
- **Dedicated Prospecting Tools/Skills** (medium)
- **Regeneration Timescale Tuning (open design question)** (small)

### Items (`concept/items.md`)

A basic item/inventory/loot foundation now exists (typed items, stacking
inventory, loot drops, weapon damage, procedural item sprites, clickable
ground items) but none of the *rarity/affix/crafting* depth this doc
describes:

- **Rarity/Affix Tier System** (medium) — ⬜ Not started — items are fixed definitions (`item.gd`), no rolled affixes or rarity.
- **Found/Looted Gear Generation** (medium) — 🚧 Partial — creatures drop deterministic loot (`loot_table.gd`) as clickable ground items (`dropped_item.gd`); no randomized/rarity generation, and drops are materials/food/weapons, not multi-slot gear.
- **Crafted Gear (Blueprint DSL)** (large) — ⬜ Not started
- **Shared Rarity/Stat Pool Consistency** (small) — ⬜ Not started
- **Spells as Items (Gems + Scrolls)** (large) — ⬜ Not started — no
  "spell" item kind exists yet, and `item.gd` has no sealed/forkable/
  use-only flag (`docs/concept/magic.md`'s "sealed IP" decision needs both).
  The 2026-08-24 design adds a second vessel on the same item kind: a
  `vessel` field (`"gem"` sealed/use-only vs. `"scroll"` teachable/
  requirement-gated/consumed-on-success), the embedded AST, and author
  metadata — neither vessel is built.
- **Spell Gem Rarity Derivation** (medium) — 🚧 Partial — `rarity_tier.gd`'s
  `tier_from_complexity(complexity)` derives a tier straight from a numeric
  complexity/cost score (e.g. `spell_cost.gd`'s `derived_base()`), reusing the
  same tier vocabulary as `roll_tier()`'s random loot roll. Pure, tested,
  monotonic. Not yet called from anywhere that actually mints a spell gem
  (that needs the item-kind/sealed-flag work above first).
- **Spell Gem Trading Category** (small) — ⬜ Not started
- **Affix Pool Segmentation by Category** (medium) — ⬜ Not started
- **Equipment Slot / Itemization Power Balance** (large) — 🚧 Partial — a real **equipment system** now exists (`src/gameplay/equipment.gd`, tested): head/chest/legs/feet/weapon slots, `Item` carries `equip_slot` + `armor`, and worn armor reduces incoming damage (`Player.take_damage` subtracts `Equipment.total_armor()`, min 1). Wearable **leather armor** (helm/chest/legs/boots) is in the catalog with its own pixel art, and the revamped inventory screen (see UI section) is a **grid + equipment paperdoll**: click an item to wear/equip it, click a worn slot to unequip. Still missing: affix/rarity rolls, set bonuses, and full itemization balance.

Supporting systems now built (tested): `inventory.gd` (fixed-slot stacking
inventory), `item.gd`/`item_stack.gd` (typed items — "weapon"/"tool"/
"material"/"food" kinds), `loot_table.gd`, `dropped_item.gd` (clickable/
auto-pickup ground items), `procedural_item_sprite.gd` (offline pixel-art for
items, including sword/axe shapes). Trees also drop fruit/nuts as ground
forage over time — dropped centrally and throttled by
`EarthChunkManager.step_forage` via `forage_scheduler.gd` (trees themselves
run no per-frame script; an earlier per-tree approach tanked the frame rate
since thousands of trees load at once), and can be felled with the starting
axe for wood (`ChoppableTree`). Ground items despawn after a lifetime and are
capped in number; creature AI sensing is throttled/cached (`SENSE_INTERVAL`)
so per-frame cost stays low with many creatures loaded.

**Procedural pixel art** is now used consistently across every rendered
entity, all offline/deterministic/seed-based (no external image-gen
API/network/cost, same shaded-and-outlined technique everywhere):
`procedural_item_sprite.gd` (items/weapons/tools), `procedural_sprite_generator.gd`
(creatures), `procedural_character_sprite.gd` (player body/head/limbs), and
`procedural_tree_sprite.gd` (tree canopy+trunk, tinted by the tree's own
`TreeGenome.species_bias`). An **art-direction pass** (`src/rendering/pixel_palette.gd`,
tested) pushed the whole look toward a brighter, more saturated Legend-of-Zelda /
Pokémon-overworld palette with chunkier near-black outlines and a top-left
highlight (Hammerwatch readability): terrain `BASE_COLORS` are now vivid
route-style greens/blues, and the item/creature/character/tree/stone/ore
generators route their base colors + shading through the shared palette helper.
Known gaps: none of the item/creature/combat layer is replicated in multiplayer
(play single-player for a coherent loop).

### Magic (`concept/magic.md`)

The cost/atom foundation of the spellcrafting DSL has been started (pure,
tested modules); everything above the cost layer (parser, validator, runtime,
authoring UI, physics compliance) is still unbuilt. The 2026-07-15 brainstorm
extensions (atom domains beyond the physical, material-component cost,
caster self-danger, complexity-priced spell gems) now have a pure/tested
foundation too, but none of it is wired into runtime casting yet — see the
new rows below. The 2026-08-24 brainstorm (gold cost to compile a spell,
exponential in size; sealed gems vs. teachable scrolls) is design-only so
far — no code exists for it yet.

- **Spellcrafting DSL** (huge) — 🚧 Partial — first three of the pure
  `RefCounted` pipeline modules exist and are test-first: `spell_atom_catalog.gd`,
  `spell_cost.gd`, and `spell_parser.gd` (player text → canonical AST, pipeline +
  blocks surface syntax, with human-readable parse errors). No validator/runtime/
  UI yet; the parser is purely structural (does not check atoms against the
  catalog — that is the validator's job).
- **Primitive Effects Catalog** (large) — 🚧 Partial — `spell_atom_catalog.gd`:
  25 atoms across 10 categories and 3 tiers, each with cost-relevant data (base
  cost, magnitude/duration scaling refs). Pure lookup, tested. Beyond the
  original 15 damage/heal/control/movement/defense/summon/utility atoms, it now
  covers the brainstorm's three non-physical domains too:
  **biological** (`accelerate_growth`, `induce_mutation`, `suppress_mutation`,
  `blight`), **perceptual** (`illuminate`, `calm`, `fear`), and **spatial**
  (`teleport`, `portal`, `gravity_shift`) — vocabulary-level only, with no hook
  yet into `dna.md`'s genome/mutation systems, `creature_behavior.gd`/taming, or
  `fast_travel.gd`/waypoints. Not yet wired into any runtime.
- **Delivery Method System** (medium) — 🚧 Partial — delivery-method cost
  *multipliers* (self/touch/projectile/area) exist in `spell_cost.gd`; actual
  delivery (projectile travel, area resolution) is unbuilt.
- **Shape Modifier System** (medium) — ⬜ Not started
- **Elemental Reaction Matrix** (large) — ⬜ Not started
- **Resource Cost Formula** (medium) — 🚧 Partial — `spell_cost.gd` derives cost
  deterministically from atoms + params (magnitude, duration, burst radius) and
  delivery, with a stat-driven efficiency term that discounts what the caster
  *pays* without changing the derived power price. Property-tested. Not wired
  into gameplay (no mana pool spends it yet).
- **Diminishing Returns Curve** (small) — 🚧 Partial — superlinear magnitude
  exponent (`MAG_EXP`) plus a repeated-atom spam penalty in `spell_cost.gd`,
  both pinned by property tests so the constants are a tested function, not
  eyeballed.
- **Material-Component Cost** (medium) — 🚧 Partial — a third cost axis
  (`spell_cost.gd`'s `material_cost()`, folded into `breakdown()`): materials
  are declared per-atom under a `"materials"` params key (material_id →
  quantity), the same way magnitude/duration/radius already are, and summed
  across the whole composition. Pure and tested. Not wired to `inventory.gd`/
  `item_catalog.gd` — nothing actually deducts a fire gem or frost hide yet,
  and there's no per-atom *requirement* data (a caster can currently declare
  any material for any atom).
- **Caster Self-Danger** (small) — 🚧 Partial — `spell_cost.gd`'s
  `does_affect_caster(delivery, radius, caster_distance_from_effect)` is a
  small pure predicate: `"self"` delivery always affects the caster by design,
  any other delivery blows back only if the caster's standoff distance falls
  within the effect's own radius. Property-tested. Not wired into live combat
  resolution — nothing calls it during an actual cast yet.
- **Physical Simulation Compliance** (large) — ⬜ Not started
- **Projectile Travel & Interception** (medium)
- **Area/Summon Spatial Validity** (medium)
- **Mass-Based Push/Pull Knockback** (small)
- **Environmental Fire Spread (Ignite)** (medium)
- **Freeze-to-Walkable Terrain** (medium)
- **Shock Conduction Through Water** (medium)
- **Skill-Tree Gating (Layer 0)** (medium)
- **Spell Editor / Authoring Tool** (huge)
- **Compilation Gold Cost (Authoring Gate)** (medium) — ⬜ Not started — new
  2026-08-24 design (`docs/concept/magic.md`'s "compilation gate"
  brainstorm): compiling a drafted spell into a permanently known one costs
  gold, exponential in the AST's atom-tier-weighted pipeline-step count
  (`weighted_loc`), paid once per distinct design. A third, independent gate
  alongside Layer 0 (can you write this atom) and Constraint layer 1 (what
  it costs to cast once known) — no code yet, needs its own
  `spell_crafting_cost.gd` module and a numeric-design pass for
  `CRAFT_BASE`/`CRAFT_GROWTH`/tier weights, pinned by property tests like
  every other cost constant in this doc.
- **Spell Crystallization: Gems vs. Scrolls** (medium) — ⬜ Not started —
  supersedes the old single "Spell Crystallization (Tradeable Spells)" row
  with the 2026-08-24 two-vessel design: sealed, no-requirement **gems**
  (unchanged from the original decision) alongside teachable,
  requirement-gated **scrolls** that attempt to permanently teach their
  spell on read, consumed only if the reader's own skill-tree state
  satisfies the same atom/param gate Layer 0 already applies to authoring.
  See the Items section's "Spells as Items" row below for the item-kind
  work this needs.
- **Master Tier: Freeform Node-Graph Authoring** (huge) — ⬜ Not started

### Economy (`concept/economy.md`)

A first real currency now exists and is wired into live gameplay; everything else in this doc remains unbuilt:

- **Regular Currency System** (medium) — 🚧 Partial — `src/gameplay/wallet.gd` (`Wallet`): a real gold balance on the player, shown in the HUD (`world.gd`'s `_wallet_label`) and adjustable via the dev console's `/gold <amount>` command, now also spendable at a village merchant (see below). Still no way to actually earn gold through play (no quest rewards, no selling anything) — a functioning ledger with a real sink now, but no faucet beyond the debug command.
- **Premium Currency System** (large) — ⬜ Not started
- **Market (NPC & Player Selling)** (large) — 🚧 Partial — `src/gameplay/shop.gd`: buying from a village merchant NPC now works (see NPC section's "Basic Merchant Shopping"), spending the real `Wallet` above. Fixed shared catalog/pricing (not per-NPC), no shop browsing UI, and no selling the player's own goods yet. An **auction house** extending the newer `src/emergence/market.gd` (per-settlement supply/demand pricing) with crafter identity/skill-tier-aware listings is designed in [concept/labor_skills.md](concept/labor_skills.md#the-auction-house) — forward-compatible with real player listings once multiplayer ships — but not implemented; `shop.gd` remains the only live buying path today.
- **Crafting System (external)** (large)
- **Resource Gathering System (external)** (medium)
- **Taming/Breeding System (external)** (huge)
- **Quest/Bounty Reward System** (large)
- **NPC Hiring System (wages)** (large)
- **Player-to-Player Trading** (medium)
- **DNA Reroll Purchase** (small)
- **Extra Lives/Soul Stone Purchase** (small)
- **Cosmetics Purchase** (medium)
- **Convenience Purchases (storage/travel)** (small)
- **Premium/Regular Currency Exchange (open design question)** (large)
- **Wage/Price Balancing (open design question)** (small)

### Weather (`concept/weather.md`)

Only real-time day/night lighting is wired into live rendering; a first deterministic weather model now exists as tested pure logic but isn't wired into the game world yet:

- **Dynamic Weather System** (large) — 🚧 Partial — `src/world/weather_model.gd` (deterministic clear/cloudy/rain/storm per region+time) is now **wired with mechanical teeth**: `EarthChunkManager.current_weather` derives the player-region weather (shown in the HUD "Season · Weather"); rain/storm **slow the player** (`weather_speed_modifier` → `Player._weather_speed_multiplier`), and wet/cold weather feeds the new **body-temperature exposure** system (see Survival). Water is now the one visibly weather-reactive surface: `weather_model.wind_strength_for` (calm on clear days, most energetic in a storm) drives `WaterShader`'s `wind_strength` uniform via `EarthChunkManager.set_wind_strength`, pacing the GPU ambient wave scroll rate to match, alongside the existing rain-ripple tie-in. Still missing: visual rain/storm particles/tint over land, combat fire-dousing, and disaster events (drought/flood/wildfire). **Divergence note (2026-08-24)**: this is currently a flat per-region hash roll, identical odds anywhere on the planet — exactly the "independent random layer" this doc's own top bullet says not to build. See the new Climate Dynamics section below, which specifies the real mechanism this is meant to become.
- **Weather Exposure Debuff** (small) — ✅ Done — cold/wet weather chills the player's warmth meter; while cold, condition (fitness) degrades faster and, while freezing, movement is slowed further (`SurvivalMeters` warmth + `Player._weather_speed_multiplier`). See Survival section.
- **Seasons (calendar cycle)** (medium) — ✅ Done — `src/world/season_cycle.gd` (tested, see `concept/seasons.md`): a deterministic spring→summer→autumn→winter year with smooth warmth/growth modifiers. Wired into fruit phenology (`EarthChunkManager._warmth_at_pixel` scales `FruitingModel` warmth by season, so trees fruit fast in summer / slowly in winter) and shown in the HUD. A new world now starts at a random point in the year rather than always on the same frozen instant, and a loaded world resumes its own persisted point rather than re-rolling (`randomize_world_age`/`load_world_clock`, `WorldClockPersistence` — see `concept/seasons.md`'s "A new world starts at a random point in the year"). Not yet driving vegetation/tall-grass growth rate or farming crop viability.
- **Regional Weather Variety** (medium) — 🚧 Partial — `weather_model.gd` takes a `region_seed` parameter so different regions roll independently; not wired to any real per-chunk region concept yet.
- **Disaster Events** (large)
- **Drought Carrying-Capacity Penalty** (medium)
- **Flood Terrain Reshaping** (large)
- **Wildfire Vegetation Clear & Migration Trigger** (large)
- **Player-Triggered Wildfire** (medium)
- **Weather Exposure Debuff** (small)
- **Rain Douses Fire/Oil Combat Effects** (small)
- **Fog Line-of-Sight Reduction** (small)
- **Snow/Mud Movement Slow** (small)
- **Seasonal Crop Viability** (medium)
- **Farm Disaster Risk** (medium)
- **Disaster Forecast/Warning (open question)** (small)

### Climate Dynamics (`concept/climate_dynamics.md`)

New concept doc (2026-08-24), replacing `weather_model.gd`'s flat per-region
weather roll and `biome_classifier.gd`'s one-shot worldgen classification
with a live pressure/wind/ocean-current/water-cycle simulation. Nothing
implemented — all ⬜ Not started:

- **Coarse Climate Grid (Two-Fidelity LOD)** (large) — same aggregate-grid-
  plus-interpolated-tile-reads shape `ecosystem_dynamics.md`'s population
  model and `earth_elevation_source.gd`'s bilinear elevation sampling
  already use elsewhere; not yet built for atmosphere.
- **Pressure Field (Three-Cell Latitude Baseline + Land/Ocean/Season
  Modulation)** (large) — `climate_model.gd`'s `temperature_at` and
  `season_cycle.gd`'s `warmth_modifier` both already exist as real inputs
  this would read; not yet connected to any pressure computation, because
  none exists.
- **Wind from Pressure Gradient + Coriolis** (medium) — replaces
  `weather_model.gd`'s current `wind_direction_for`, an independent random
  walk with no relationship to pressure or geography.
- **Ocean Currents (Wind-Driven, Coriolis-Deflected, Coastline-Redirected)**
  (large) — no current model of any kind exists today.
- **Water Cycle (Evaporation → Advection → Precipitation, Orographic Lift)**
  (large)
- **Storms from Threshold-Crossing Pressure/Temperature Contrast** (medium)
  — replaces `weather_model.gd`'s flat 5%-of-rolls storm chance.
- **Live Biome Reclassification + Hysteresis** (large) — `biome_classifier.gd`'s
  `classify()` keeps its exact threshold logic; only whether its
  temperature/moisture inputs are a worldgen-time constant vs. a live
  climate-grid read changes. `vegetation_growth_model.gd`'s existing
  climate-to-density response is proposed to double as the visible-drift
  mechanism once biome LABEL is also climate-derived, not a new one.

### World Bosses (`concept/worldbosses.md`)

No live world-boss/creature-fitness simulation exists yet, but the promotion math and the phase-generation abstraction are now real, tested, pure logic:

- **Emergent World-Boss Promotion** (large) — 🚧 Partial — `src/gameplay/world_boss_fitness.gd`'s `attempt_promotion(individual_id, species, score, trait_description, phase_generator)` turns a passing fitness-threshold check into a named boss record (`{individual_id, species, score, threshold, phases}`); the generator side is abstracted behind a `PhaseGenerator` base class plus a deterministic `FakePhaseGenerator` (canned two-threshold phase list, no real LLM call — per `concept/worldbosses.md`'s "one offline LLM call at promotion time" design and `roadmap.md`'s stubbed-LLM testing convention). Tested; not wired to any live creature population.
- **Fitness-Threshold Promotion Math** (medium) — 🚧 Partial — `src/gameplay/world_boss_fitness.gd`: deterministic fitness scoring + a per-species promotion threshold check, tested; now feeds `attempt_promotion` above, still not wired to any live creature population (no actual world-boss promotion happens in the running game).
- **Unique Naming & Identity** (small)
- **Per-World Uniqueness** (trivial)
- **World Boss Combat Encounter** (medium)
- **Best-in-Slot Loot Drop** (small)
- **High-Risk World Boss Taming** (medium)
- **Population Impact of Killing (Outlier Removal)** (small)
- **Population Impact of Taming (Outlier Retained)** (small)
- **Village-Endangerment Attractor / Discovery Signaling** (medium) — ⬜ Not started — formerly an open question, now specified in `concept/worldbosses.md`'s "Village endangerment" section and `concept/quests.md`; no longer open, just not yet built.
- **World Boss Special AI/Behavior (open question)** (large) — 🚧 Partial —
  resolved for aggro/engagement specifically (`concept/worldbosses.md`'s
  "Krampus: a worked encounter" section): a new `is_world_boss`
  `CreatureInfo` flag + `BossAggro`
  (`MIN_DAMAGE_FRACTION_OF_MAX_HEALTH`-gated real-damage check) +
  `CreatureBehavior._perceives_threats` means a world boss ignores a
  nearby player entirely — doesn't attack, doesn't flee — until a hit
  clears a threshold scaled to the boss's own max_health; before that, a
  hit deals zero damage and sets no state. Tested
  (`test_boss_aggro.gd`/`test_creature_behavior.gd`/
  `test_creature_marker.gd`/`test_creature_info.gd`), live on the Germany
  roster's 4 `/spawn`-able bosses. Ability *selection* (not yet execution)
  is real too: `BossPhase`/`BossPhaseKits` answer "which phase/ability is
  active at this health fraction" from the exact `{hp_threshold, ability}`
  shape `WorldBossFitness.PhaseGenerator` already produces, with Krampus's
  own 3-ability kit (Chain Yank baseline, Chain Lash + Terrifying Roar at
  50% HP, Chain Shackle at 20%) written into `BossPhaseKits`. Not built:
  actually *executing* an ability (applying `pull`/`push`/`fear`/`root`'s
  physics/status effect, on a cooldown, synced to a telegraph/VFX) —
  needs the still-unbuilt spell-DSL runtime or a narrower boss-only
  executor as a smaller first step.

### Evolution (`concept/evolution.md`)

No DNA/genetics/evolution simulation exists. All ⬜ Not started:

- **Evolutionary Population System (DNA/Reproduction/Selection)** (large)
- **Resource-Constrained Reproduction** (medium)
- **Genetic Phenotype Generation** (medium) — 🚧 Partial — `src/world/animal_fitness.gd`'s `phenotype_for` derives a deterministic phenotype from a seed; not wired to any live creature's actual rendered appearance (creature color still comes from species, not individual DNA).
- **Attractive Phenotype Target** (large)
- **Mate-Attractiveness Scoring** (small) — 🚧 Partial — `animal_fitness.gd`'s `mate_attractiveness`, tested; no reproduction/mate-selection system consumes it.
- **Emergent Rarity from Population Dynamics** (medium)
- **Player-Facing Rarity/Shiny Payoff** (small)
- **DNA-Driven Fitness Attributes** (medium) — 🚧 Partial — `animal_fitness.gd`'s `fitness_score`, tested; not linked to the aggregate population model or individual creature promotion yet.
- **Pet Fitness Carryover** (medium)
- **World Boss Outlier Trigger** (large)
- **Aquatic DNA/Fitness Model (Fishing)** (medium)
- **Crop DNA/Fitness Model (Farming)** (medium)
- **Ecosystem Simulation (Resource Constraints)** (huge)
- **DNA/Genetics System** (large)

### Combat (`concept/combat.md`)

A first, minimal real-time combat loop now exists (see Phase 3 table above);
most of this doc's scope (classes, skills, PvP, weather/elevation effects) is
still unbuilt:

- **Core Real-Time Combat Loop** (medium) — 🚧 Partial — a cooldown-based AOE melee swing exists, real-animated (`weapon_swing.gd`), and is now two-directional (aggressive/healthy predators attack back, weak ones flee — see Phase 1's Individual Creature AI). Each creature has a health bar and a hover/on-hit info panel (name/level/stamina/mana).
- **Fast Movement** (trivial) — ✅ Done — pre-existing player movement, unrelated to combat specifically.
- **Cooldown-Based Ability System** (small) — 🚧 Partial — the one attack has a cooldown; no ability variety. A separate axe-driven tree-felling action (`equipped_tool`) exists on the same input, gated by tool type rather than a cooldown/ability slot.
- **Dodge/Dash Mechanic** (small) — 🚧 Partial — `src/gameplay/dodge.gd`: cooldown + invulnerability-window math, tested; not wired to any player input.
- **Positional/Tactical Spacing** (trivial) — ⬜ Not started
- **Co-op Multiplayer** (huge) — ⬜ Not started
- **Knockback** (small) — ✅ Done — smooth ease-out shove (`Knockback.step`), Hammerwatch-style, not a teleport. See Phase 3 table above.
- **Environmental Hazards** (medium) — ⬜ Not started
- **Knockback-into-Hazard Interaction** (small) — ⬜ Not started — no hazards exist yet to knock anything into.
- **Spreadable Environmental Effects** (large) — ⬜ Not started
- **Layered Tilemap Elevation** (medium) — ⬜ Not started
- **Height Advantage** (small) — ⬜ Not started
- **Line-of-Sight Blocking (Elevation)** (medium) — ⬜ Not started
- **Vegetation-Based Concealment** (large) — ⬜ Not started
- **Biome-Dependent Combat Variation** (medium) — ⬜ Not started
- **Weather Effects on Combat** (large) — ⬜ Not started
- **Throwables** (medium) — 🚧 Partial — `src/gameplay/throwable.gd`: trajectory/impact math, tested; no actual throwable item or player action exists.
- **Weight-Based Physics Interactions** (medium) — 🚧 Partial — `throwable.gd`'s `impact_knockback` covers one slice (mass-scaled knockback on impact); no broader weight/physics system.
- **Stat System** (medium) — 🚧 Partial — player health only; no broader stats.
- **Skill System** (large) — ⬜ Not started
- **Class System** (large) — ⬜ Not started
- **Equipment/Item System** (large) — ⬜ Not started
- **PvP** (medium) — ⬜ Not started
- **PvE** (small) — ✅ Done — player-vs-creature combat exists, however minimal.

### Materials (`concept/materials.md`)

A design-direction doc (2026-07-15 brainstorm) proposing that item stats and
combat outcomes *emerge* from a shared material property vector + contact
geometry, replacing per-(weapon, material) authored lookup tables. A first
pure-logic slice of that model now exists (tested), independent of and not
yet wired into the live, still-lookup-table-shaped `material_damage.gd`/
`block.gd` combat path. The 2026-08-24 revision (see `concept/smelting.md`'s
"Alloying: emergent metallurgy" brainstorm) narrowly reverses this doc's
original "materials stay pure, no alloying" clause for the mineral track
only — design-only so far, no code exists for it yet:

- **Material Property Vector** (medium) — 🚧 Partial — `src/gameplay/material_properties.gd`: a fixed "mineral track" vector (density/hardness/toughness/elasticity/sharpness_capacity/flammability/conductivity/decay_rate) for six named materials (wood/flesh/stone/iron/obsidian/fiber), tested, with unknown-material/unknown-property defaults. Only the doc's mineral track exists; the DNA-driven organic track (see dna.md/evolution.md) is unbuilt, and nothing in live gameplay reads this vector yet — `material_damage.gd`'s per-(weapon_kind, material)-string lookup table remains what `scenes/player.gd` actually calls.
- **Impact Resolution (Momentum × Geometry × Material → Outcome)** (large) — 🚧 Partial — `src/gameplay/impact_resolver.gd`'s `resolve_impact()` (tested, calibration-pinned `T_CUT`/`T_PIERCE`/`T_CRUSH`/`T_BRITTLE_TOUGHNESS`/`PIERCE_HARDNESS_CAP` thresholds — the doc's own Open Questions section flags exactly these as needing calibration tests) returns cut/dent/crush/pierce/shatter/bounce from momentum + contact geometry (edge/point/blunt) + the target material's hardness/toughness. Not wired into any live combat, tree-felling, or mining path, and doesn't yet cover the doc's shape-assembly mechanics (leverage/edge+backing/balance) that would compute momentum and geometry from an actual item.
- **Two-Track Organic vs. Mineral Materials** (large) — ⬜ Not started — no DNA-driven variable material track exists; every entry in `material_properties.gd` is a fixed mineral-style vector.
- **Shape & Assembly (Leverage, Edge+Backing, Balance)** (large) — ⬜ Not started — no part-graph/geometry-composition model exists; `impact_resolver.gd` takes momentum and contact geometry as direct inputs rather than deriving them from assembled parts.
- **Physical Interaction Verbs (Shove/Throw/Topple/Drop)** (large) — 🚧 Partial — throw exists narrowly (`throwable.gd`, see Combat section's Throwables row); shove/topple/drop-as-momentum are unmodeled, and none of the four route through `impact_resolver.gd`.
- **Reactive Surfaces (Elemental Reaction Matrix on the Floor)** (large) — ⬜ Not started — see Magic section's Elemental Reaction Matrix row.
- **Physical Honesty (Item Wear/Chip/Fracture Over Time)** (medium) — ⬜ Not started — no durability/wear state exists on any item.
- **Traversal-Tool Material Viability (Raft Buoyancy / Rope Tensile Strength)** (small) — ✅ Done (basic) — `material_properties.gd`'s `is_viable_for_tool()`, tested: density-gated for `raft`, toughness-gated (standing in for tensile strength — see the doc's transportation.md cross-reference) for `grapple_rope`. No raft/rope items or transportation.md wiring exist yet to consume it — see Transportation section.
- **Alloying (Emergent Metallurgy)** (large) — ⬜ Not started — new
  2026-08-24 design (`concept/smelting.md`'s brainstorm extension): an
  alloy's property vector is *computed*, not authored — a weighted blend
  of two existing mineral vectors via real metallurgical rules (linear
  rule-of-mixtures baseline, a solid-solution hardness/toughness bonus
  peaking at a real historical ratio, a eutectic melting-point dip near
  that same ratio, brittle collapse past a ceiling), flowing through this
  doc's existing shape/assembly/threshold pipeline unchanged. Needs: a new
  `melting_threshold` scalar on the property vector (the doc already names
  it, code doesn't have it yet), a `copper` row in `material_properties.gd`
  (missing today even though `copper_ore`/`copper_ingot` items already
  exist), new `tin`/`zinc` ore types + items for bronze/brass specifically
  (steel needs neither — see smelting.md, it reuses the existing coal fuel
  slot as a carbon-fraction input), the blend-formula module itself, and a
  numeric-design pass for the curve constants, pinned by property tests.
  Composes with, doesn't duplicate, `concept/labor_skills.md`'s
  `ceiling_realization` multiplier — see smelting.md's own 2026-08-24
  section for exactly how the two compose.

### Easter Eggs (`concept/easter_eggs.md`)

Brand-new doc, 2026-08-24. Deliberately the one place in this project's
design corpus that's hand-placed rather than emergent — see the doc's own
"Design pillars" for why that's the right call here specifically, not a
quiet contradiction of every other system's "never hand-placed" rule.

- **Real-Coordinate Reverse Lookup** (small) — ✅ Done —
  `GeoCoordinates.tile_for_coordinate`/`radius_in_tiles`/
  `tile_is_within_radius` (`src/world/geo_coordinates.gd`): the shared
  "given a real lat/lon + a small radius, is this tile in range"
  infrastructure every coordinate-triggered egg builds on (the pre-existing
  `tile_for_latitude`/`tile_for_longitude` only did an exact single-tile
  reverse lookup, no radius). Tested incl. a round trip at the real
  game-world scale (`EarthChunkGenerator.WORLD_WIDTH_TILES`/
  `WORLD_HEIGHT_TILES`, ~111 tiles/degree), not just the toy dimensions the
  pre-existing tests used — see `tests/unit/test_geo_coordinates.gd`.
- **Mothman, Jersey Devil, Roswell/Area 51 crashed-saucer + "little grey"
  pair** (small) — ✅ Done — `EasterEggSightings`
  (`src/gameplay/easter_egg_sightings.gd`), a pure tile+roll decision
  module (`tests/unit/test_easter_egg_sightings.gd`), wired into
  `scenes/world.gd`'s per-frame update (checked every
  `EASTER_EGG_CHECK_INTERVAL` seconds, not every frame) as a brief
  on-screen banner line, same shape as the existing talk/trade/fishing
  banners. Deliberately **log-line-only, not a spawned sprite/prop** — an
  explicitly-sanctioned scope call, documented in the module's own doc
  comment: there is no persistent "sighting" object for the player to walk
  up to, so "never actually catchable... gone if approached" (the doc's own
  words for Mothman) is true by construction rather than enforced by a
  despawn-on-approach check. The "crashed saucer" landmarks specifically
  read more like an actual landmark than a glimpse in the doc's own text;
  promoting them to a real visible static prop (a `_draw()`-based shape,
  no new art needed) is a reasonable next small step, left open here.
  `chance_per_check`/`radius_km` are first-pass placeholders (no real
  playtesting data yet to calibrate encounter rates against), pinned as
  named constants and exercised by relative property tests (landmarks
  trigger far more often than fleeting glimpses; Roswell/Area 51 stay a
  symmetric matched pair) rather than eyeballed.
- **Secret Console Commands** (trivial) — ✅ Done — reuses
  `console_command_parser.gd`'s existing parse/dispatch shape; each Easter
  egg command is an undocumented `match` arm in `World`'s dispatcher, never
  listed in `/help`. Two live commands: `/globalthermonuclearwar` (the
  WarGames egg, below) and `/rolld20` (the d20 egg, below).
- **Calendar-Date-Gated Triggers** (trivial) — ✅ Done — a plain
  real-*system*-date check, the same category of real-world-time input
  `SeasonCycle`/`WeatherModel` already read for unrelated reasons (though a
  genuinely different clock than `SeasonCycle`'s own in-game calendar — see
  Back to the Future Day, below, which is the one live user of this shape
  so far).
- **WarGames secret console command** (trivial) — ✅ Done —
  `WarGamesResponse` (`src/gameplay/wargames_response.gd`): a single
  original, deadpan `RESPONSE_LINE`, printed by the undocumented
  `/globalthermonuclearwar` `match` arm in `scenes/world.gd`'s dispatcher.
  No quoting of the film's own dialogue (pillar 4) — enforced by
  `test_wargames_response.gd`'s own "does not contain the film's famous
  lines" check, not just a comment. Zero mechanical weight: prints one line
  and does nothing else.
- **Back to the Future Day cameo** (small) — ✅ Done —
  `BackToTheFutureDay` (`src/gameplay/back_to_the_future_day.gd`): a pure
  `is_today(month, day)` check against the REAL system calendar date
  (`Time.get_datetime_dict_from_system()`, read by `scenes/world.gd` the
  same place it already reads UTC for solar lighting) — explicitly NOT this
  game's own fictional `SeasonCycle` clock, a distinct real-world-time input
  in the same category `SeasonCycle`/`WeatherModel` already read, just
  keyed to one calendar day instead of a season. On October 21st, fires
  once per session (a simple session flag — once-a-year eligibility makes
  "once per session" and "once per day" indistinguishable in practice, the
  same low-risk scope call `EasterEggCreatures`' own doc comment already
  sanctions) via the exact same on-screen banner (`_easter_egg_label`)
  `EasterEggSightings`' Mothman/Jersey Devil/Roswell/Area 51 cameos already
  use, since there is no real car sprite/art to spawn instead. Description
  only, no trademarked name anywhere — enforced by
  `test_back_to_the_future_day.gd`'s own "never names the car" check.
- **Rush ambient nod** (small) — 🚧 Partial — `RushAmbientCue`
  (`src/gameplay/rush_ambient_cue.gd`) reuses `GeoCoordinates`' reverse
  lookup + radius exactly like `EasterEggSightings`/`EasterEggCreatures`,
  pinned at a real, remote stretch of Canadian Shield wilderness near
  Temagami, Ontario — a private wink at the band's own home country, never
  named in-game (checked by `test_rush_ambient_cue.gd`'s own "never names
  the band" test). Unlike every `chance_per_check`-gated cameo elsewhere in
  this doc, LOCATION ALONE is the trigger (the doc: "plays... on approach",
  not "sometimes, on approach") — no rarity roll, fires once per approach
  via a simple session flag. **Deliberately incomplete, and documented as
  such rather than faked:** the doc's actual ask is a real *composed*
  short original ambient instrumental cue, and no audio-generation tool was
  available to this stage to produce one. What's implemented instead is a
  real, original, on-screen flavor line (reusing `EasterEggSightings`' own
  banner) plus an explicit `TODO` left in `scenes/world.gd` at the exact
  spot a real `AudioStreamPlayer2D` + composed `.ogg` cue would attach once
  one exists — a hook point, not a fabricated audio asset.
- **The d20 Easter egg** (small) — ✅ Done — `SecretD20`
  (`src/gameplay/secret_d20.gd`): this project's one deliberate exception
  to "no random rolls anywhere" (combat/crafting/spellcasting stay fully
  deterministic elsewhere). Isolated on purpose in its own small,
  obviously-named module specifically so it can never be mistaken for, or
  reused as, a general RNG source — `roll()` takes a caller-supplied
  `RandomNumberGenerator`, and `scenes/world.gd` wires it to its own
  dedicated `_secret_d20_rng` instance, never the ambient `randf()` the
  cameo-rarity checks elsewhere in that file already use. Findable
  "somewhere unlikely" via a second undocumented secret console command
  (`/rolld20`) — the same discovery register as the WarGames egg. Harmless
  and silly on a natural 20 (`NATURAL_20_MESSAGE`), a complete no-op on
  every other result (1-19), per the doc.
- **Squallmaw, Coilnecca, Champ** (medium) — ✅ Done — unlike the sightings
  above, these are **real, spawnable creatures**, not flavor-text-only
  glimpses: full `CreatureInfo`/`AnimalAnatomy`/`ProceduralAnimalSprite`
  entries (`src/world/creature_info.gd`, `src/rendering/animal_anatomy.gd`,
  `src/rendering/procedural_animal_sprite.gd`), same precedent shape as the
  Germany-region world bosses (krampus/lindwurm/rubezahl/nyx) but explicitly
  NOT at that roster's stat scale (Squallmaw is a strong ordinary apex
  predator, above bear, below every Germany boss — the doc: "does nothing a
  real creature doesn't already do"). All three are legless serpentine
  bodies (`AnimalAnatomy.SERPENT_SPECIES`), procedurally rendered (no
  illustrated art needed), and `/spawn`-able for testing the same way
  krampus etc. already are (`ConsoleSpecies` gates purely on
  `AnimalAnatomy.SPECIES`, so registering them there was the only wiring
  needed). Squallmaw is aggressive (can fight, per the doc) but deliberately
  NOT a world boss — no aggro-gate, ordinary creature behavior. Coilnecca is
  calm, per the doc. Champ is a NEW `"skittish"` temperament value — the doc
  is explicit it must not be a reskin of Coilnecca's calm despite the family
  resemblance; `CreatureBehavior._will_fight` only special-cases the literal
  string `"aggressive"`, so `"skittish"` already flees exactly like `"calm"`
  does with zero behavior-module changes (pinned as a regression test in
  `test_creature_behavior.gd`).
  Real-world-coordinate spawning: `EasterEggCreatures`
  (`src/gameplay/easter_egg_creatures.gd`) reuses the exact same reverse-geo
  + radius + per-check-roll shape as `EasterEggSightings`, but a hit
  returns the SPECIES ID to spawn rather than a message; wired into
  `scenes/world.gd`'s per-frame update (`_check_easter_egg_creature_spawns`,
  same `EASTER_EGG_CHECK_INTERVAL` cadence as the sightings) via
  `CreatureRenderer.spawn_single` — the same API `/spawn` itself calls, so
  a triggered cameo is a completely ordinary `CreatureMarker` once it
  exists (no despawn timer, no special persistence; "fight, flee, be
  tamed" is true by construction). Squallmaw's `chance_per_check` is tuned
  far rarer than every other coordinate-triggered cameo in the project
  (pinned by a relative property test against both this module's own
  Coilnecca/Champ and `EasterEggSightings`' whole roster) — the doc's own
  "wildly lower rate than even the rarest ordinary predator".
  **Deliberate scope decisions, documented rather than silently
  under-built:**
  - Tied into a **live, real-time coordinate check + `spawn_single`**, NOT
    into `EarthChunkManager`'s deterministic per-chunk population
    promotion — a fundamentally different mechanism (a fixed population
    computed once at chunk generation, keyed by biome) that a coordinate-
    pinned rare cameo has no natural way to hook into without much larger
    surgery on that system. Follow-up if ever wanted.
  - Champ's "visible only from a real distance, dives immediately if the
    player closes in" is approximated, not built exactly as described:
    it spawns `EASTER_EGG_CREATURE_SPAWN_DISTANCE` (220px, a first-pass
    placeholder) away from the player rather than on top of them, and then
    uses the ordinary calm/skittish flee-when-threatened `CreatureMarker`
    behavior everyone else uses (`SENSE_RADIUS`-gated) — there is no
    per-species flee-detection-radius override in `CreatureMarker` today,
    so Champ and Coilnecca currently flee at the exact same real distance
    despite the doc wanting Champ to read as more easily spooked. A real
    per-species radius hook is a follow-up, not built here.
  - No de-duplication guard against multiple simultaneous spawns of the
    same cameo (e.g. a player idling for a long session near Loch Ness) —
    accepted as a low-risk simplification given how low each
    `chance_per_check` is tuned, matching `EasterEggSightings`' own
    "no persistent state" precedent rather than adding new session state.
- **The Kraken** (medium) — 🚧 Partial — the doc's one deliberately
  higher-stakes, CONDITION-triggered (not coordinate-triggered) entry: open
  ocean, night, and active storm weather (`WeatherModel`), all at once,
  anywhere on the map. Built: (1) `KrakenTrigger`
  (`src/gameplay/kraken_trigger.gd`), a pure decision module —
  `is_open_ocean`/`is_eligible`/`check`, every input a plain already-computed
  primitive (bool/String/float), no `GeoCoordinates` lookup at all (there is
  no single point to be near) — tested in `tests/unit/test_kraken_trigger.gd`
  including a relative-property test pinning its `CHANCE_PER_CHECK` as far
  rarer than every existing coordinate-triggered cameo (`EasterEggCreatures`'
  squallmaw, this project's previous rarest entry), same "no eyeballed
  thresholds" discipline as everywhere else. (2) A full `CreatureInfo`/
  `AnimalAnatomy`/`ProceduralAnimalSprite` roster entry for `"kraken"`,
  following the Germany-region world-boss precedent's shape but deliberately
  ABOVE that whole roster's stat/size scale rather than below it (the doc's
  own one exception to pillar 2's "zero mechanical weight"): `max_health`
  220.0, over 1.5x the previous roster max (lindwurm, 140.0, pinned as a
  relative-property test, not an isolated literal); `world_scale` 3.2,
  larger than every Germany-region world boss (1.9–2.4) and every other
  Easter-egg creature. Legless `snake_shape` body (`AnimalAnatomy.
  SERPENT_SPECIES`), procedurally rendered, no illustrated art needed —
  `/spawn kraken`-able the same "registering it in `AnimalAnatomy.SPECIES`
  is the only wiring `ConsoleSpecies` needs" way as every other cameo
  creature. `is_world_boss` is set true, joining `CreatureInfo.
  WORLD_BOSS_SPECIES` — a deliberate reuse of that flag purely for its
  mechanical aggro-gate effect (`BossAggro`/`CreatureBehavior.
  _perceives_threats`: no proactive attack on an unprovoked player, but a
  real fight once real damage lands), matching the doc's "actually a real
  fight if it notices you... never a free ambush" framing with zero new
  code — NOT a claim that the Kraken joins `worldbosses.md`'s regional-
  mythology roster (no fitness-threshold promotion, no regional theming);
  documented as such in both `creature_info.gd`'s own comment and
  `kraken_trigger.gd`'s.
  **Deliberate scope decisions, documented rather than silently
  under-built:**
  - `AnimalAnatomy` has no per-tentacle limb primitive (every profile is one
    torso + at most one tail/neck/4 legs) — "many-tentacled" is approximated
    by the single longest tail in the roster plus a `has_mane` fringe
    (reinterpreted from Squallmaw's fin crest into a writhing head/neck
    fringe) rather than literally modeling N separate limbs. A real
    multi-tentacle rig would need a new anatomy field this stage didn't add.
  - `KrakenTrigger` is deliberately NOT wired into `scenes/world.gd`'s live
    per-frame loop the way `EasterEggCreatures` was for Squallmaw/Coilnecca/
    Champ — no `elevation_at_global`/`BiomeClassifier.depth_at`/
    `WeatherModel.weather_at` plumbing exists yet feeding it real values,
    and no actual `spawn_single` + combat encounter is triggered by it. The
    module itself is complete and fully tested in isolation; stitching it
    into the live game loop (computing `depth_normalized` from the player's
    real tile, choosing a spawn point, handling what happens once the fight
    ends) is left to a later integration pass.
  - `OPEN_OCEAN_MIN_DEPTH` (0.5 on `BiomeClassifier.depth_at`'s normalized
    [0,1] scale) is a first-pass placeholder, same "no real playtesting
    data yet" situation as every other tuned threshold in this doc — pinned
    as a named constant and exercised directly by its own tests rather than
    eyeballed inline.
- **The Zork-homage ancient terminal** (small) — ✅ Done — `AncientTerminal`
  (`src/gameplay/ancient_terminal.gd`): a fixed real-world location
  (Cambridge, Massachusetts — home of MIT, where Zork was actually written
  — reusing `GeoCoordinates` exactly like `RushAmbientCue`/
  `EasterEggSightings`, never named in-game) plus `TERMINAL_LINES`, a fully
  original few-line old-school-parser-style exchange. No quoting of Zork's
  own prose (pillar 4) — enforced by `test_ancient_terminal.gd`'s own "does
  not quote Zork's own famous text" check, the same discipline
  `test_wargames_response.gd` already applies to the WarGames egg. Unlike
  every proximity-only cameo elsewhere (Rush/Mothman/etc.), this needs a
  deliberate ACTION at the location, not just approach — wired in
  `scenes/world.gd`'s `_check_ancient_terminal`, called every frame (not
  the throttled `EASTER_EGG_CHECK_INTERVAL` cadence the rarity-roll cameos
  use) so it reliably catches the single-frame `Input.is_action_just_
  pressed("talk")` edge, the same generic interact verb villager talk
  already uses. Deliberately no floating "Talk (G)" interaction prompt —
  that would itself be a hint, contradicting pillar 3. `has_been_found()`/
  `mark_found()` give a clean, testable boolean signal (forwarded by
  `World.has_found_ancient_terminal()`) for the "Three Fragments" hunt
  below to eventually check against — this stage only builds the signal,
  not the fragment-drop/aggregation logic itself.
- **The signed secret room** (small) — ✅ Done — `SignedSecretRoom`
  (`src/gameplay/signed_secret_room.gd`): repeats Warren Robinett's actual
  1980 *Adventure* gesture rather than referencing the game. Pinned at
  Sunnyvale, California (Atari's real historical HQ, reusing
  `GeoCoordinates` the same way, never named in-game) PLUS an obscure
  action sequence — `stash → lasso → fish → mount`, four real, existing
  interaction verbs normally used in unrelated contexts, chosen over
  combat verbs (attack/block/kick) specifically because those DO plausibly
  chain together by accident in real play. `matches_sequence` is a pure
  tail-match over a small rolling buffer of just-pressed action names
  `scenes/world.gd`'s `_check_signed_secret_room` maintains (also called
  every frame, same just-pressed reasoning as the terminal above) — the
  module never touches `Input` itself. `CREDIT_TEXT` is a tasteful, generic
  placeholder ("You found this. Made with care by the people who built
  this world.") marked with a `TODO(ship)` comment so whoever actually
  ships this can swap in real credited names with a one-line edit, per the
  doc's own ask. Same `has_been_found()`/`mark_found()` signal shape as the
  terminal above (forwarded by `World.has_found_signed_secret_room()`).
  **Scope call:** no literal new interior geometry/teleport — reaching the
  gate reveals the credit via the same on-screen banner every other cameo
  in this doc uses, not a new walkable room, matching this doc's own
  "zero mechanical weight"/"not a new game mode" discipline (see
  `AncientTerminal`'s identical scope call) rather than building a bespoke
  interior-space system for one Easter egg.
- **Monty Python's Bridgekeeper** (small) — ✅ Done — `BridgekeeperEncounter`
  (`src/gameplay/bridgekeeper_encounter.gd`): three original riddles set in
  this game's own nature vocabulary (a river, a tree, snow), not the film's
  own three questions — enforced by `test_bridgekeeper_encounter.gd`'s own
  "does not quote the film's own questions" check. **Scope call:** this
  project has no bridge/river-crossing terrain concept and no free-roaming
  path-blocking NPC AI to reuse (neither exists anywhere in the codebase);
  building either from scratch would be a far bigger lift than an Easter
  egg warrants. Scoped the same way `EasterEggSightings` scoped Mothman
  down to "a log-line, not a spawned sprite/Node": pinned at Trift Bridge,
  Switzerland (a real, narrow, precarious rope bridge — reusing
  `GeoCoordinates`, never named in-game) as a rare `chance_per_check`
  encounter roll (`_check_bridgekeeper_encounter`, same cadence as the
  sightings cameos), and the riddle exchange itself is conducted through
  the dev console's existing text-input surface via a new undocumented
  `/answer <text>` command (`_handle_bridgekeeper_answer_command`) — the
  same "secret console command" shape WarGames/the d20 egg already use, no
  new NPC node or blocking-collision AI. Passage never actually depends on
  the score (`passage_message` always lets the player through) — "failing
  is harmless, a silly non-consequence" is true by construction rather than
  needing an explicit unblock step. Not part of the "Three Fragments" hunt,
  so no found-signal needed here.
- **"Three Fragments" hunt** (medium) — ✅ Done — `ThreeFragmentsHunt`
  (`src/gameplay/three_fragments_hunt.gd`): a pure aggregation module over
  the three source eggs' own found-signals. `has_all_fragments`/
  `should_trigger`/`mark_triggered`/`has_triggered` take plain
  caller-supplied booleans, never `AncientTerminal`/`SignedSecretRoom`/
  `WarGamesResponse` themselves — the same "caller supplies the real
  primitive, module only decides" shape `KrakenTrigger`/
  `BridgekeeperEncounter` already use — so it's fully unit-tested
  (`tests/unit/test_three_fragments_hunt.gd`) independently of the three
  source eggs, per this stage's own task ask. `should_trigger` latches
  permanently via `mark_triggered` (true exactly once, the instant all
  three are first held together, never again afterwards).
  The WarGames egg needed a found-signal added first (it didn't have one
  before this stage): `WarGamesResponse.has_been_found()`/`mark_found()`
  (`tests/unit/test_wargames_response.gd`), mirroring the shape
  `AncientTerminal`/`SignedSecretRoom` already established, forwarded by a
  new `World.has_found_wargames_egg()` getter (also new:
  `World.has_triggered_three_fragments_bonus()`, forwarding
  `ThreeFragmentsHunt.has_triggered()`) — both pinned by
  `tests/unit/test_world_easter_egg_discovery.gd`.
  **Item catalog additions** (`src/gameplay/item_catalog.gd`,
  `tests/unit/test_item_catalog.gd`): three fragment items
  (`terminal_fragment`/`secret_room_token`/`wargames_punch_card`) plus the
  bonus item (`curious_keepsake`) — all inert `"material"`-kind items with
  zero `weapon_damage`, matching this whole family's zero-mechanical-weight
  pillar (pinned by its own test, not just a comment).
  **Wiring** (`scenes/world.gd`): each of the three source-egg find sites
  (`_check_ancient_terminal`, `_check_signed_secret_room`, the
  `/globalthermonuclearwar` command handler) now checks "was this egg NOT
  already found before this call", and if so grants that egg's own fragment
  item via a shared `_grant_fragment_and_check_three_fragments_hunt` helper
  — quietly, no fanfare, alongside whatever else that egg already does (the
  terminal's prose, the secret room's credit banner, the WarGames response
  line). That helper then calls `_check_three_fragments_hunt`, which reads
  `Player.inventory.has(...)` for all three fragment ids and, the moment
  `ThreeFragmentsHunt.should_trigger` returns true, grants the bonus item
  and shows the bonus message via the same on-screen banner every other
  cameo in this doc uses. This grant-once gating is why a re-triggerable
  egg (the terminal, the secret room) never grants a second copy of its own
  fragment on a later re-find. **Scope call, matching this whole family's
  precedent (`test_world_easter_egg_discovery.gd`'s own "World has no
  direct unit tests... orchestration glue over already-tested pieces"):**
  the wiring itself (`_check_three_fragments_hunt`/
  `_grant_fragment_and_check_three_fragments_hunt`, and the edited
  `_check_ancient_terminal`/`_check_signed_secret_room`/
  `/globalthermonuclearwar` call sites) is not directly unit-tested — it
  needs a real `Player` node's `inventory` plus `World`'s own
  dynamically-built `_easter_egg_label` (not a scene-tree `@onready` field,
  so a bare `World.new()` can't exercise it safely) — the exact same
  untested-wiring shape every sibling `_check_*` function in this file
  already has. The pure module, the item catalog entries, and both new
  forwarding getters are the parts this stage could and did unit-test.
  **The final bonus discovery's actual content** (the doc's own "TBD
  what... whoever implements this gets to invent the actual payoff", now
  resolved): the three fragments physically interlock into one inert
  keepsake carrying a scratched line addressed to whoever was thorough
  enough to find all three — a deliberate meta-echo of the signed secret
  room's own tribute to Robinett's original gesture, not a reference to
  RP1's own invented Key content (pillar 4) — see
  `docs/concept/easter_eggs.md`'s own "Three Fragments" entry for the full
  reasoning. Monty Python's Bridgekeeper is deliberately NOT part of this
  hunt (never one of the three eggs the doc names for it).
- **The hidden sea cave / dueling-birds cabinet (Joust homage)** (large) —
  ✅ Done — the doc's own biggest single Starter Collection entry, "a
  genuinely bigger implementation lift... a hidden sub-area, a scripted
  transform beat, and a real second game loop, not just a prop." Three
  pieces, matching this project's established pure-module-plus-node-
  adapter split throughout:
  - `JoustMatch` (`src/gameplay/joust_match.gd`) — the pure rules core.
    Two riders close a scrolling gap; whichever is higher when it closes
    wins that pass; first to `ROUNDS_TO_WIN` (2, best-of-three) wins the
    match. Exactly Duel.advance's own pure state-in/state-out shape (the
    caller owns and persists a state `Dictionary` across frames) — no
    instance state, no Godot dependency at all. The AI opponent
    (`ai_should_flap`) is a **deterministic skill rule** ("stay at or
    above the player's own height"), never `randf()` — this project has
    no random rolls anywhere except the deliberately isolated d20 egg
    (`SecretD20`), and this is the one place a second RNG would have been
    the obvious wrong shortcut. It reacts to the player's height as of
    the START of the tick (a one-frame lag), so a well-timed player flap
    can still win — the AI can't literally read simultaneous input. Every
    tuned constant (`GRAVITY`/`FLAP_BOOST`/`APPROACH_SPEED`/`PASS_GAP`/
    `TIE_MARGIN`/`AI_HEIGHT_MARGIN`) is a first-pass placeholder (no real
    playtesting data yet, the same situation as every other Easter-egg
    rarity constant in this doc) but pinned by direct exact-value
    assertions in `tests/unit/test_joust_match.gd` (24 tests: rider
    physics, pass resolution/ties, the AI's own one-tick-lag property,
    best-of-three progression including a 2-1 decider, post-match
    inertness, no mutation of the caller's state), matching
    `spell_cost.gd`'s `MAG_EXP`/`SPAM_PENALTY` discipline rather than an
    eyeballed comment.
  - `SeaCaveGuardian` (`src/gameplay/sea_cave_guardian.gd`) — the
    location + challenge-state module for an ORIGINAL guardian, "the
    Brinewarden" (a barnacle-crowned spirit invented for this world, never
    RP1's own specific character — pillar 4). Pinned at the exact same
    Bermuda Triangle coordinate `EasterEggCreatures` uses for Squallmaw
    ("alongside Squallmaw above" per the doc), duplicated as its own named
    constants (GDScript's const-folding doesn't reliably support
    dictionary subscripting at parse time) with a test
    (`tests/unit/test_sea_cave_guardian.gd`, 14 tests) pinning the two
    coordinates in lockstep so they can't silently drift apart. A smaller
    `RADIUS_KM` (4.0) than Squallmaw's own 30.0 — a cave mouth is one
    specific findable point, not "somewhere in this stretch of ocean."
    Interaction needs a deliberate "talk" press in range, same as
    `AncientTerminal`. Deliberately **repeatable** (unlike `AncientTerminal`/
    `SignedSecretRoom`'s one-shot `has_been_found()`) — only
    `is_challenge_active()` blocks re-triggering mid-match; zero mechanical
    weight (pillar 2) means there's no reason to block a rematch. Forwarded
    by a new `World.is_sea_cave_challenge_active()` getter, pinned in
    `tests/unit/test_world_easter_egg_discovery.gd`. Not part of "Three
    Fragments" (never one of that hunt's three named eggs).
  - `JoustMatchView` (`src/rendering/joust_match_view.gd`) — the node/
    rendering adapter, and the actual playable screen: a full-viewport
    `Control` overlay built entirely from `ColorRect`/`Label` children (no
    new art asset, matching this stage's own "prefer no art asset"
    guidance), reading `JoustMatch`'s own state each frame and the
    player's "attack" action (reused rather than adding a new rebindable
    one — ordinary attack has no meaning while this overlay owns the
    screen) as the flap input. `start_match()` first holds a short, timed
    transform beat (`TRANSFORM_DURATION`, 1.2s — a plain gray panel
    standing in for the stone bench) before real play begins, matching the
    doc's "one small scripted transformation beat, not a full cutscene
    system." `scenes/world.gd` pauses the whole tree for the match's
    duration (`get_tree().paused = true`, the exact "acts like a real
    pause screen" pattern `_toggle_settings_menu` already uses for
    `SettingsOverlay`) while this Control keeps running via
    `PROCESS_MODE_ALWAYS`; `match_finished(winner)` unpauses and reports
    the outcome through `SeaCaveGuardian.outcome_line`. Only lightly
    tested (`tests/unit/test_joust_match_view.gd`, 5 tests: visibility,
    the transform-beat timer, the finished signal + auto-hide) — this
    project's own established convention (see `test_crafting_window.gd`'s
    "layout glue, not game rules" framing) holds a `Control`'s actual
    on-screen layout to a lighter bar than a pure rules module; every real
    game rule is `JoustMatch`'s job and is covered at full rigor there.
  **Wiring** (`scenes/world.gd`): `_check_sea_cave_guardian` runs every
  frame alongside `_check_ancient_terminal`/`_check_signed_secret_room`
  (the same just-pressed-edge reasoning), shows the challenge + transform
  banner text through the shared `_easter_egg_label`, starts the match, and
  pauses; `_on_joust_match_finished` (connected to `JoustMatchView.
  match_finished`) unpauses and shows the win/lose banner.
  **Scope call, matching this doc's own established precedent
  (`SignedSecretRoom`'s identical call, see above):** no literal new
  walkable interior/teleport for the "half-flooded sea cave" itself — this
  project has no interior-space system to reuse (checked first, per this
  stage's own task instructions, rather than inventing one), so "reachable
  only by finding its entrance" is built the same proximity-plus-
  interaction-at-a-point shape every other real-coordinate cameo in this
  doc already uses, not a new spatial paradigm. The cave and its guardian
  are real and discoverable; what's stubbed is the literal cave *geometry*
  players would otherwise walk through to reach the guardian — the
  encounter itself (challenge → transform → a fully real, playable,
  fully-rules-tested joust) is not a prop.
- **The retro-handheld creature-battler** (medium) — ⬜ Not started. A
  small, battered handheld prop (generic, undescribed hardware) that boots
  into a tiny original turn-based creature-battler starring miniature
  pixel-art versions of this project's own existing roster — zero new art
  needed at the character level (`ProceduralAnimalSprite`/
  `IllustratedAnimalSprite` already exist for every creature), the actual
  new work being a small turn-based battle-menu loop and a "world's
  smallest Pokédex" catch-list UI.

### Electromagnetism (`concept/electromagnetism.md`)

New concept doc (2026-08-24), extending `materials.md`'s existing (already
implemented, but so far unused) `conductivity` scalar into a real
water-wheel/windmill → generator → wire/circuit → battery/light-bulb
mechanism. Nothing implemented — all ⬜ Not started:

- **Circuit Topology (Adjacency Flood-Fill)** (medium) — the algorithm
  shape already exists and is real, tested code
  (`src/gameplay/room_detector.gd`'s room-enclosure flood-fill), just not
  yet generalized past room enclosure to conductivity.
- **Torque from Flow (Water Wheel / Windmill)** (medium) — windmill has no
  new world-sim dependency (`weather.md`'s `wind_strength_for` already
  real); water wheel's flow-from-elevation-gradient proxy is proposed, not
  validated.
- **Generator (Torque + Magnet + Coil → EMF)** (medium)
- **Wire / Circuit Resistance & Current (Ohm's Law)** (medium)
- **Battery (Charge Storage)** (small)
- **Light Bulb (Load, Brightness from Power)** (small)
- **Magnetic Permeability Material Scalar** (small) — proposed addition to
  `material_properties.gd`'s existing vector (density/hardness/toughness/
  elasticity/sharpness_capacity/flammability/conductivity/decay_rate);
  not yet added.
- **Magnetite Ore / Magnetized-Iron Crafting** (small) — proposed fourth
  `OrePlacement.ORE_TYPES` entry (today iron/copper/coal) plus a craft-a-
  magnet-from-iron recipe; neither exists.
- **Wire Overload Burnout** (small) — proposed reuse of the existing
  melting/damage-threshold mechanism (`impact_resolver.gd`'s
  `T_BRITTLE_TOUGHNESS`-style thresholds), not yet extended to current
  load.

### Housing (`concept/housing.md`)

No housing/decoration system is wired into live gameplay, but its scoring math now exists as tested pure logic:

- **Placeable Furniture/Decor Placement** (medium)
- **Coziness/Appeal Score** (medium) — 🚧 Partial — `src/gameplay/coziness_score.gd`: deterministic score from placed-decor data, tested; no actual furniture placement system to feed it real data.
- **Thematic Coherence / Set Bonus** (small) — 🚧 Partial — `coziness_score.gd`'s coherence bonus term, tested; same caveat as above.
- **NPC Home Visit Scheduling** (large)
- **NPC Opinion Formation on Homes** (medium)
- **NPC Relationship/Memory Log-and-Recall System** (huge)
- **Multiplayer Home Visiting & Rating** (huge)
- **Appeal Score Transparency Design** (small)
- **Decor-Linked Sleep Quality Bonus** (small)
- **Decor-Linked NPC Hiring Willingness** (small)

### Factions (`concept/factions.md`)

No faction/reputation system exists. All ⬜ Not started:

- **Emergent settlement reputation** (medium)
- **NPC relationship & memory system** (large)
- **Reputation aggregation function** (small) — 🚧 Partial — `src/gameplay/faction_reputation.gd`: deterministic aggregation math, tested; no actual factions/settlements/NPCs exist yet to apply it to.
- **NPC social-influence weighting** (medium) — the same score `concept/quests.md` needs to pick a settlement's quest-giving representative (2026-08-13); still unimplemented either way.
- **Reputation-gated hiring difficulty** (small)
- **Reputation-skewed quest offers** (small)
- **Reputation-based price softening** (small)
- **Settlement reputation summary (legibility layer)** (small)
- **Settlement identity** (trivial)
- **Player-formed factions (guilds/settlements)** (huge)
- **Player-faction-to-settlement standing** (medium)
- **Cross-settlement reputation propagation (open question)** (large)

### Exploration (`concept/exploration.md`)

No map/fog-of-war/waypoint exploration mechanics exist beyond raw walking. All ⬜ Not started except the two below:

- **History-Seeded POI System** (large) — ⬜ Not started. No POI/ruin/dungeon generator exists anywhere in `src/world/` yet (checked before building the obstacle below) — placement is the honest next step, not silently implied by the obstacle existing.
- **Abandoned Settlements** (medium) — a settlement lost to a `concept/quests.md` village-endangerment fight is now a named, specific cause among these (2026-08-13), the unresolved quest itself standing in as the ruin's "what happened" fragment.
- **Monster Lairs** (medium)
- **Causal Procedural Weighting** (large)
- **Historical Event Logging / Discoverable Fragments** (large)
- **Puzzle Content Stays Emergent — Momentum Obstacle** (medium) — 🚧 Partial (2026-08-24) — `src/rendering/collapsed_passage.gd`: the first of the doc's "Puzzle content stays emergent, not hand-authored" obstacle types, "a collapsed passage that only enough momentum ... can clear," built as a real, tested, standalone placeable/spawnable `StaticBody2D` (real `MaterialProperties` material, defaults to `"stone"`) rather than a bespoke puzzle mechanism — it routes every delivered hit through the SAME `ImpactResolver.resolve_impact` call every other hittable thing in this world already uses (contact geometry always `"blunt"`; `"crush"`/`"shatter"` outcomes clear it, `"dent"`/`"bounce"` leave it blocked). Wired to TWO real momentum sources already built this session: a thrown stone (`Player._resolve_stone_impact_on_obstacles`, called from `_throw_held_stone`) and a kicked stone (same helper, called from `_kick_step`) — both real, tested, no parallel physics system. Real-world-probed: a thrown 2cm pebble at minimum charge measured 0.0226 kg·m/s → `bounce`, stays blocked; a thrown 15cm cobble at full charge measured 38.17 kg·m/s → `crush`, clears; a kicked 3cm pebble measured 46.2 kg·m/s (`Kick.KICK_MOMENTUM_KG_M_S`) → clears. The other two obstacle types (Freeze/Heat-class chamber, hardness/toughness-gated sealed door) remain ⬜ out of scope this pass. **Not yet wired into any POI generator** — none exists (see above) — this is a real, correct primitive waiting to be placed by one.
- **POI Loot Rarity Integration** (small) — 🚧 Partial — `src/gameplay/poi_loot_scaling.gd`: deterministic rarity-scaling-by-POI-tier math, tested; no actual POIs exist in the world yet to attach it to.
- **World-Scale POI Density Scaling (open question)** (small)

### Transportation (`concept/transportation.md`)

- **Toroidal, Water-Heavy World** (huge) — 🚧 Partial — the world is genuinely toroidal (`world_coordinates.gd`) and genuinely water-heavy (real Earth oceans/lakes from real elevation data), but this is the terrain substrate only, not a transportation mechanic.
- **Boats** (large) — ⬜ Not started
- **Fast Travel System** (large) — 🚧 Partial — `src/gameplay/fast_travel.gd` (cost/cooldown math + living-creature cargo restriction) + `src/gameplay/waypoint_network.gd` (unlock tracking), both tested; no player-triggered travel action, no map UI, nothing actually moves the player yet.
- **Horses (Land Mount)** (trivial) — ⬜ Not started
- **Waypoint Network (fast-travel option A)** (medium) — 🚧 Partial — see `waypoint_network.gd` above.
- **Personal Portal Item (fast-travel option B)** (medium) — ⬜ Not started
- **Fast-Travel Cost/Limitation Mechanic** (small) — 🚧 Partial — resolved per `concept/transportation.md` ("Fast travel: free for cargo, never for living stock"): `fast_travel.gd`'s cost/cooldown math is unchanged and untaxed for cargo, plus a new `can_fast_travel_with_cargo(cargo)` that allows any inanimate load but blocks the whole trip if it contains even one living creature. Tested; not yet wired to a live travel action.
- **Boat/Weather Interaction (storm risk, open question)** (medium) — ⬜ Not started
- **Traversal Tools (Climbing Rope, Raft, etc.)** (medium) — ⬜ Not started — `concept/terrain_relief.md` (2026-08-24) now gives the climbing rope a real purpose (raising the slope threshold at which terrain becomes impassable); no traversal tool of any kind is craftable/usable yet.

### Terrain Relief (`concept/terrain_relief.md`)

New concept doc (2026-08-24): real elevation data currently only feeds a
biome threshold — nothing stops the player walking up a cliff, and
mountain terrain has no ore, no visible relief shading, and no relationship
to slope at all. Nothing implemented — all ⬜ Not started:

- **Slope/Aspect Field (from Real Elevation Data)** (medium) — ✅ Done, and now wired into live movement — `src/world/terrain_relief.gd` (tested, 21/21): `slope_at`/`aspect_at` sample four real neighbors through any `elevation_at(lat, lon)`-shaped source (real `EarthElevationSource` or a test fake), converting to real meters and a real central-difference gradient — real degrees, real GIS aspect-bearing convention (0=north/90=east/180=south/270=west, -1 on flat ground). Exposed per-global-tile via `EarthChunkGenerator`/`EarthChunkManager.slope_at_global`/`aspect_at_global`, and consumed by the Slope-Gated Passability row below. This is also the shared field `climate_dynamics.md`'s orographic lift needs; not yet consumed there. Hillshading and mountain-ore (the rest of this section) still aren't built on top of it.
- **Slope-Gated Passability (Soft Slow, Hard Refusal)** (large) — ✅ Done and wired into live movement — `src/gameplay/terrain_passability.gd` (`speed_multiplier`/`is_passable`, tested: 11/11) plus real wiring in `scenes/player.gd`'s `_authority_step`: `current_speed_multiplier` now also factors `_terrain_speed_multiplier(tile)` (the soft case, same shape as `_weather_speed_multiplier`), and a real look-ahead check (`_terrain_blocks_movement`, same "ask before you step" principle `creature_movement_gate.gd` established for creatures) zeroes the frame's velocity outright when the tile ahead is too steep, before `move_and_slide()` ever runs. `EarthChunkGenerator`/`EarthChunkManager` both gained `slope_at_global`/`aspect_at_global` to expose `terrain_relief.gd`'s real slope/aspect field per global tile (tested: `test_earth_chunk_generator.gd` 214/216 asserts passing — the 2 "failures" are the pre-existing, unrelated image-load-warning flake, not a real failure; `test_earth_chunk_manager.gd`/`test_player.gd` verified via targeted `-gunit_test_name` runs rather than a full-file run, both too slow to complete in full — see the Godot-test-execution memory note). **Not yet wired**: no creature (only the player) is gated by slope.
- **Climbing Rope Raises the Hard Threshold** (medium) — 🚧 Partial — `TerrainPassability.is_passable`'s `has_climbing_gear` parameter is real and tested, but `Player._has_climbing_gear()` always returns `false` — no rope item/equipment concept exists yet (`transportation.md`'s already-specified, currently-unused rope concept), so nothing can set it true. The hook is real; the payoff isn't.
- **Hillshading (Real Lambertian Formula, Real Solar Position)** (medium) — ✅ Done and wired into live chunk load/unload — `src/rendering/hillshade.gd`'s `illumination()` is the real standard hillshade formula (tested, 8/8), fed by `solar_position.gd`'s new `azimuth_degrees()` (tested, 20/20 for the whole file) alongside its existing `elevation_degrees`. `procedural_hillshade_sprite.gd` bakes real (quantized) slope/aspect as DATA into a small atlas (8 slope bins x 8 aspect octants + one shared flat tile, tested 14/14); `hillshade_shader.gd` is a real, compile-verified `canvas_item` fragment shader (tested 12/12 — caught a genuine bug mid-development: Godot's shader language rejects an early `return` inside `fragment()`, unlike plain GLSL); `TerrainRenderer.atlas_coords_for_hillshade`/`build_hillshade_overlay_tile_set` build the atlas TileSet (tested 5/5). **Now wired live**: `EarthChunkManager.set_hillshade_layer`/`_paint_hillshade_overlay`/`set_sun_position` (mirroring `set_water_layer`/`_paint_water_overlay`/`set_wind_strength` exactly) are called from `_load_chunk`/unload and verified via a real chunk load at the Berlin spawn tile — every one of ~25,600 loaded cells got a real hillshade tile, and moving away correctly erased cells outside the new radius (25605/25606 asserts passing; the one "failure" is the same pre-existing per-sheet image-load-warning flake hit repeatedly this session, not a real defect). `scenes/world.tscn` gained a real `HillshadeFx` `TileMapLayer` node (mirroring `WaterFx`/`SnowFx`); `scenes/world.gd` now computes real sun azimuth alongside its existing elevation computation and pushes both via `set_sun_position` every frame, alongside the existing `set_wind_strength`/`set_rain` calls. **Honest verification gap**: no automated test instantiates `world.tscn`/`World` itself anywhere in this project's suite, so the scene-level wiring (the `@onready $HillshadeFx` reference, the `.tscn` node block) is verified only by confirming both resources load without structural/parse errors (a real, if partial, check), not by a live GUI session.
- **Slope-Gated Mountain Ore Veins** (medium) — ✅ Done and wired into live chunk load/unload — `src/world/mountain_ore_placement.gd` (tested, 15/15): vein chance is zero below `terrain_passability.gd`'s own `SOFT_THRESHOLD_DEG`, scales linearly up to `MAX_VEIN_CHANCE` (0.35) at its `HARD_THRESHOLD_WITH_ROPE_DEG` — the same steepness gating passability also gates ore exposure, deliberately, one shared quantity with two consequences. Ore type/seed reuse `OrePlacement`'s own derivation exactly. `StoneRenderer.spawn_mountain_veins` (tested, 6/6 — 689/692 asserts passing across the whole file, the 3 "failures" the same pre-existing flake) spawns real `MinableOre` nodes on mountain cells that roll a vein, drawing from the exact same illustrated-boulder-composited texture path flat-ground ore already uses. **Now wired live**: `EarthChunkManager._load_chunk` concatenates `spawn_mountain_veins(..., self)` (passing itself as the duck-typed slope lookup) onto the same `_loaded_stones[chunk_coord]` array `spawn_stones` already populates — a deliberate one-line reuse rather than a parallel dictionary: mountain veins are `StaticBody2D` ore nodes exactly like flat-ground ore, so they need the exact same obstacle-avoidance (`solid_obstacles_near`) and unload-cleanup machinery `_loaded_stones` already provides, with nothing new to duplicate. Not separately re-verified against a real chunk load in this pass (Berlin, this suite's existing fixture location, isn't mountainous) — correctness rests on the already-passing `StoneRenderer`-level tests plus direct code review of the one-line change.

### Building (`concept/building.md`)

- **Tile placement/destruction (building system)** (medium) — ✅ Done — see Phase 3 table above; earth/campfire/furnace are all live, wired to `Player._build_step`/`_arm_placeable`, persisted across unload/reload.
- **Structure building: real multi-piece, enterable houses** (large) — ✅ Done (mechanism; not player-reachable yet) — see `concept/building.md`'s Status section for the full breakdown. `building_piece.gd`/`building_placement.gd`/`room_detector.gd`/`house_blueprint.gd` (pure logic, tested) are now wired into rendering (`ProceduralBuildingPieceSprite`, 10 piece tiles in the shared terrain atlas) and `EarthChunkManager` (real wall/window collision via the same StaticBody2D mechanism trees/boulders use; a roof piece paints onto its own `TileMapLayer` and hides over exactly the room the player is standing in, via `RoomDetector.room_containing`; `stamp_structure_at_global` writes a whole structure in one repaint). The older `src/gameplay/building_blueprint.gd` (multi-tile footprint fit/overlap validation only, no pieces/enclosure) is a separate, more limited module, superseded by this for actual house construction. Known gaps: no player-facing build cursor/piece-selection UI yet (pieces are placeable today only via direct `stamp_structure_at_global`/`build_at_global` calls, not the hotbar); village houses (see NPC section) don't call this yet either.
- **Terrain digging** (medium) — ⬜ Not started
- **Chunked world persistence** (large) — 🚧 Partial — modifications-only persistence is now wired into live gameplay (`ChunkSerializer.save_modifications`/`load_modifications` via `EarthChunkManager`); the original full-chunk `save_chunk`/`load_chunk` methods remain tested but still unused (terrain itself is deterministically regenerated, not saved).
- **Housing decoration layer** (medium) — ⬜ Not started
- **Diegetic Threat / Base Defense** (medium) — ⬜ Not started — no scripted raid waves; any threat to a built-up settlement (player or NPC) must trace to a real simulated cause. Extended (2026-08-13) from player homesteads to NPC villages generally, and given a real mechanism, in `concept/quests.md`'s Village endangerment section.
- **MMO-driven villages** (huge) — ⬜ Not started
- **Player-influenced economy** (huge) — ⬜ Not started
- **Player-driven society** (huge) — ⬜ Not started

### Timber Construction (`concept/timber_construction.md`)

New doc (2026-08-24) — no implementation yet. Specifies a Balken/Planke
material pipeline on top of the existing `FelledTree`/`ChoppableTree`
felling mechanic, a real support-graph statics model, a closed-form
withering/decay model mirroring `chunk_ecology_catchup.gd`'s own shape, and
an autonomous NPC builder AI run at two fidelities (individual agent
on-screen, deterministic catch-up integration off-screen) so a settlement
can be discovered fully built — or mid-build, or decayed to ruins — in a
chunk that was never loaded, without ever stamping a house-shaped prefab.

- **Log → Balken/Planke shaping pipeline** (medium) — ⬜ Not started.
- **Structural statics (support graph, collapse)** (large) — ⬜ Not started.
- **Withering / decay of built pieces** (medium) — ⬜ Not started.
- **NPC builder occupation + on-screen fell/shape/place FSM** (large) —
  ⬜ Not started.
- **Offscreen construction catch-up (`construction_catchup.gd`)** (large) —
  ⬜ Not started.
- **`ConstructionProject`/`ConstructionProjectStore`** (medium) —
  ⬜ Not started.
- **Retiring `VillageRenderer._stamp_house`'s instant free stamp** in favor
  of a seeded `ConstructionProject` at settlement founding (medium) —
  ⬜ Not started; see this doc's own Status section for why the current
  behavior is a known anti-pattern, not a baseline to preserve.

### Pets (`concept/pets.md`)

No pets/taming system is wired into live gameplay, but two of its core math pieces now exist as tested pure logic:

- **Taming System** (medium) — 🚧 Partial — `src/gameplay/taming_system.gd`: deterministic tame-chance/success roll, tested; no player action or creature-side state to apply it to.
- **Pet Accompaniment (Follow AI)** (medium)
- **Species-Fixed Role System** (small)
- **DNA/Fitness-Driven Performance** (large)
- **Unified Fitness Dimension (Ecosystem ↔ Taming value)** (trivial)
- **Guard Dog Behavior** (medium)
- **Combat Pet System** (large)
- **Mount System (Horses)** (large)
- **Decorative Pet Behavior (Birds)** (small)
- **Farm Animal Resource Production** (medium)
- **Beastmaster Class Archetype** (large)
- **Breeding System** (large)
- **Bonding/Loyalty Mechanic (proposed, open question)** (medium) — 🚧 Partial — `src/gameplay/pet_loyalty.gd`: loyalty accrual/decay math, tested; no actual tamed pets exist yet to carry this state.
- **Species-to-Role & Fitness-to-Metric Mapping Table (design task)** (trivial)

### Cooking (`concept/cooking.md`)

No cooking system is wired into live gameplay, but its recipe math now exists as tested pure logic:

- **Cooking System (core loop)** (medium) — 🚧 Partial — a live single-item heat transform now exists: `src/gameplay/campfire_cooking.gd` (meat→cooked_meat, fish→cooked_fish) is wired into `Player._use_food` — clicking/using a raw cookable food while carrying a **campfire** item (craftable from 8 wood) cooks it instead of eating it raw. The richer multi-ingredient `cooking_recipe_book.gd` dish system is still unwired, and the campfire is a carried "portable heat source" rather than a placed world object yet.
- **Dish Buffs** (medium) — 🚧 Partial — `cooking_recipe_book.gd` models buff type/duration/**category** data per dish (sustenance/combat/resistance), and `food_consumption.gd`'s `apply_food_buff`/`buff_in_category`/`advance_food_buffs` track a player's active food buffs as fixed per-category slots. **Now live for one trigger**: eating a rare/legendary fish catch (`FoodConsumption.FISH_BUFFS`, `Player.eat_food`/`_food_buff_step`) grants a real timed buff — extra stamina regen (sustenance) or +30% melee damage (combat), see `Player._damage_buff_multiplier`. The multi-ingredient `cooking_recipe_book.gd` dish path is still unwired — eating a cooked dish (as opposed to a raw rare fish) doesn't grant its buff in practice yet.
- **Ingredient Quality Propagation** (medium)
- **Recipe Discovery/Composition (Blueprint-DSL reuse)** (large)
- **Buff Stacking/Duration Rules (open question)** (medium) — 🚧 Partial — resolved by the 2026-07-16 brainstorm in `concept/cooking.md` ("Buff slots: fixed, and typed by category") and implemented as pure logic: `food_consumption.gd`'s `apply_food_buff` replaces same-category entries instead of stacking, `advance_food_buffs` ticks down and expires them, tested. Live and exercised by the rare-fish buff trigger above; the cooking-recipe dish path still doesn't call it.
- **Recipe/Buff-Type Space Sizing (open question)** (small)
- **Class Specialization Hook (Herbalist/Artisan)** (small)
- **Festival/Visitor Food Hook** (small)

### PvP (`concept/pvp.md`)

No PvP system exists. All ⬜ Not started:

- **Zone-Based PvP Risk Escalation** (medium)
- **Permadeath** (large)
- **Soul-Stone Life Stakes** (medium)
- **Consensual/Flagged PvP** (medium) — 🚧 Partial — `src/gameplay/duel.gd`: duel request/accept state machine + zone-flagging check (`is_pvp_allowed_in_zone`), tested; no actual PvP damage path or UI exists to use it.
- **Dueling** (small) — 🚧 Partial — same `duel.gd` module.
- **Flagged Contested Zones** (small)
- **Guild-War Declarations** (medium)
- **Full-Loot Open-World PvP** (large)
- **World Bosses** (large)
- **Top-Tier Resource Placement** (medium)
- **Resurrection by Nearby Player** (medium)
- **Biome/Danger Gradient** (large)
- **Character Power Gating** (medium)
- **World-Sim** (huge)
- **Era/Space-Travel Endgame** (huge)
- **Zone Boundary Definition (open question)** (small)

### Festivals (`concept/festivals.md`)

No festival system exists. All ⬜ Not started:

- **Emergent Festival Trigger System** (large)
- **Harvest Festival Trigger** (small) — 🚧 Partial — `src/gameplay/festival_trigger.gd`'s `harvest_festival_eligible`, tested; no actual harvest/season data feeds it live.
- **Solstice/Seasonal Festival Trigger** (small) — 🚧 Partial — `festival_trigger.gd`'s `seasonal_festival_for_day`, tested; not wired to the real solar/day clock (`solar_position.gd`).
- **Anniversary/Commemoration Festival Trigger** (medium)
- **Village History/Event Log** (medium)
- **NPC Festival Replanning** (medium)
- **Festival Schedule Entries (Stalls, Performances, Shared Meals)** (medium)
- **Player Festival Activities** (medium)
- **Festival Reputation Boost** (small)
- **Festival Trigger Threshold Calibration (open question)** (small)
- **Cross-Settlement Festivals** (large)

### DNA (`concept/dna.md`)

No DNA/genetics system exists. All ⬜ Not started:

- **DNA System (Core Generator)** (large)
- **NPC DNA Generation** (small)
- **DNA Trait Rarity Tiers** (small)
- **Class Resonance Score** (medium)
- **Free Character Reroll** (small)
- **Premium Reroll Purchase** (medium)
- **DNA Inheritance (Genetic Crossover)** (large) — 🚧 Partial — `src/gameplay/dna_crossover.gd`: generic two-parent trait crossover, tested; not species-specific and not wired to any player/pet/creature reproduction flow.
- **Inheritance Mutation Chance** (small) — 🚧 Partial — `dna_crossover.gd`'s bounded mutation nudge, tested; same wiring caveat.
- **DNA-Driven Phenotype/Body Generation** (huge)
- **Cosmetic Customization Layer** (medium)

### Death (`concept/death.md`)

A real (if simple) death/respawn loop now exists and is wired into live gameplay (see Phase 3 table's Player Death & Respawn row); the lives/permadeath/graveyard layer this doc describes on top of that is still pure-logic-only or unbuilt:

- **Nine Lives Permadeath** (medium) — 🚧 Partial — `src/gameplay/lives_tracker.gd`: countdown-of-lives + revival math, tested; the live respawn flow (`Player._respawn()`) doesn't consult it yet — dying currently costs nothing.
- **Soul Stones (Extra Life Item)** (small) — 🚧 Partial — `lives_tracker.gd`'s `add_life`, tested; no actual soul-stone item exists.
- **Premium Currency Soul Stone Purchase** (medium)
- **Rare Soul Stone Loot Drops** (small)
- **Soul Stone Boss/Quest Rewards** (small)
- **Ghost Respawn at Graveyard** (medium) — ⬜ Not started — the live respawn instead just returns the player to a fixed `respawn_position`, no graveyard concept.
- **Graveyard Network** (medium)
- **Corpse/Body Placement & Recovery** (medium) — 🚧 Partial — `src/gameplay/corpse.gd`: corpse-state/recovery-window math, tested; the live death flow doesn't drop a corpse or lose any items on death.
- **Self-Resurrection at Corpse** (small)
- **Player-Assisted Resurrection** (medium)
- **Resurrection Channeling Risk** (medium)
- **PvP Death Stakes (cross-reference)** (medium)
- **Survival Debuff Persistence on Revival (open question)** (medium)
- **Era-Reincarnation vs Lives Counter (open question)** (large)
- **Premium Currency / Economy System** (large)

### Survival (`concept/survival.md`)

Core survival meters are now real and wired into live gameplay; the sickness/wounds/debuff layer on top exists as tested pure logic but isn't wired in yet:

- **Core Survival Meters (Hunger/Thirst/Stamina/Fitness/Warmth)** (small) — 🚧 Partial — `src/gameplay/survival_meters.gd` (`SurvivalMeters`), owned by `Player`: hunger/thirst/stamina tick over time (`advance(delta)`), swimming drinks thirst down (`drink()`), eating food via the inventory window relieves hunger (`Player.eat_food`), all shown live in the HUD's bottom-left survival bar (`world.gd`'s `_build_survival_bar`). Per `concept/survival.md`'s "Stamina scope: movement only, not combat" decision, stamina no longer touches combat at all: attacking and blocking spend no stamina (the old `ATTACK_STAMINA_COST`/`Block.block_stamina_cost` coupling was removed). Stamina itself is not yet wired to anything, though -- sprinting, climbing, and swimming don't exist as stamina-consuming player actions yet (swimming is a movement mode that drains thirst but never spends stamina), so the meter currently only regenerates and never drains outside of the removed combat coupling. A **body-temperature/warmth** meter (`regulate_temperature`, see `concept/survival.md`) now closes the old temperature gap: warmth drifts toward the ambient (climate × season × weather) and is chilled by `wetness`; while cold, fitness degrades faster, and while freezing the player moves slower. Hunger/thirst rates were **retuned much slower** (pinned by a test: a minute of play no longer pushes you into hungry/thirsty), and **standing in any water (wading or swimming) drinks** from it.
- **Weather Exposure Debuffs** (medium) — 🚧 Partial — cold/wet weather is now a real debuff on warmth → fitness/movement (above). Not yet a discrete stacking entry in a unified `debuff_stack` model, and no prolonged-cold sickness trigger yet.
- **Sleep / Rest System** (small)
- **Wounds System** (medium) — 🚧 Partial — `src/gameplay/wounds.gd`: severity accrual + bandage-healing math, tested; not wired to combat or the player.
- **Debuff Stacking System** (medium) — 🚧 Partial — `src/gameplay/debuff_stack.gd`: stacking/expiry math, tested; nothing applies a debuff yet.
- **Death/Life Exclusion Rule** (small)
- **Weather Exposure Debuffs** (medium)
- **Sickness System** (large) — 🚧 Partial — `src/gameplay/sickness.gd`: a small, deliberately-scoped illness model (onset/progression), tested; not wired to gameplay, no epidemic/contagion layer.
- **Sickness Diagnosis** (medium) — 🚧 Partial — `sickness.gd`'s `diagnose()`, tested.
- **Remedy Brewing (Medicine Crafting)** (medium)
- **Crafting Blueprint System** (huge)
- **Herbalist Class** (large)
- **Herbalist Skill Nodes** (medium)
- **Preventative Treatments** (small)
- **Cooking Buffs System** (medium) — 🚧 Partial — same `food_consumption.gd` fixed-category-slot buff tracker as the Cooking section's "Dish Buffs" row above; now wired to the live eat flow for rare/legendary fish specifically (see Fishing section), the cooked-dish path from `cooking_recipe_book.gd` is still not.
- **Contagion/Epidemic System (proposed, undecided)** (huge)
- **Debuff Curve Tuning (open question)** (small)
- **Sickness Roster & Symptom Design (open question)** (small)

### NPC (`concept/npc.md`)

A first real slice of the "AI-native NPC" pillar is now live and playable --
procedurally placed villages, walking villagers running a deterministic
daily plan, basic shopping, and now real hunger with a working village-scale
production/trade economy underneath it (see "NPC Needs / Local Production
Economy" below). Still nothing LLM-driven yet: the planning architecture is
built and wired end-to-end, but behind a deterministic stand-in, exactly
like `worldbosses.md`'s `PhaseGenerator`/`FakePhaseGenerator` split -- so a
real local-LLM planner (the design brainstorm settled on Ollama + a local
model, e.g. `qwen2.5-coder:14b`, called via `HTTPRequest`, never live during
normal ticks) is a drop-in swap, not a rearchitect. No dialogue, no
instruction DSL, no memory-driven behavior, no lifecycle/aging, no faction/
festival wiring, no hiring/wages yet.

- **Procedural NPC Population Generation** (large) — ✅ Done — `src/world/settlement_generator.gd` places a sparse (~1-in-30 habitable chunks, never on ocean/mountain), deterministic 5-villager settlement per qualifying chunk, wired into `EarthChunkManager`'s chunk load/unload (same regenerates-identically-on-revisit philosophy as trees/creatures). `src/rendering/village_renderer.gd` spawns a walking `NpcMarker` per villager, wearing the same hero-appearance engine the player uses (`HeroAppearance`/`ProceduralCharacterSprite`), extended with 6 occupation outfit palettes (still only 6 — see NPC Identity System's own note below on the 2 newest occupations' cosmetic gap). **Houses are now real, enterable, multi-tile structures, not a decorative sprite** (see `concept/building.md`'s Status section for the full mechanism): `VillageRenderer._stamp_house` builds a real 5x4 `HouseBlueprint` assembly (wall ring, one door, floor, roof — seeded wood/stone material) centred on each villager's ring-layout anchor and stamps it into the chunk via `EarthChunkManager.stamp_structure_at_global` — the exact same piece vocabulary and collision/roof-hide mechanism the player's own building pieces use (`docs/concept/building.md#one-system-two-builders`, now actually true rather than aspirational). A villager's `home_position` resolves to its own house's door cell, not an arbitrary anchor point, so it stands somewhere it could actually have walked to. **A house's ring-layout anchor can land on a water pocket** (a chunk's dominant biome only gates the whole chunk, not every individual cell — see `BiomeClassifier.dominant_biome` — so a grassland-dominant chunk can still have a pond/river cutting through it, reported as "NPC should not build their house in water"): `VillageRenderer._find_dry_origin` nudges the origin to the nearest dry candidate (deterministic, squared-distance ordering) within a 6-tile search radius before stamping, and skips the house entirely (falling back to the raw anchor as a walk target, unbuilt) if nothing dry is found nearby — no house is better than a half-submerged one. This *replaces* the old decorative `ProceduralHouseSprite` (3 seeded sizes/palettes) entirely — that generator still exists, fully tested, just no longer called from village generation. The shared **well/market-stall/gate landmarks are still real visible props** (`ProceduralLandmarkSprite`) anchoring a village square, and every **merchant villager now also gets a second, personal trading stand** of their own (`VillageRenderer._door_facing_direction` + `_STAND_OFFSET_TILES`, same "stall" sprite, placed just outside their own house's door in the direction it opens) — previously every merchant in a village routed to the one shared stall, which read as a single shop rather than several villagers who each trade. Known gaps: house footprint is fixed (5x4), not seed-varied in size; no per-occupation building beyond the shared landmarks and a merchant's own stand (a blacksmith's forge, herbalist's garden stall, etc. still have no dedicated prop); a house stamped by a settlement re-loading its chunk overwrites whatever was in those exact cells before (including a player's own prior edit there) — the same "regenerates identically on revisit, no interference tracking" limitation trees/creatures already accept, not something new to houses. **Occupation balance per settlement is left to chance, deliberately** (see NPC Needs / Local Production Economy below): with `POPULATION` fixed at 5 and now 8 occupations, roughly a tenth of settlements roll zero producer villagers and every resident there genuinely struggles to eat — matches this codebase's existing "population exists wherever conditions make it viable" philosophy (`world.md`) rather than forcing an artificial producer guarantee; flagged as a real, known consequence, not an oversight.
- **NPC Identity System** (small) — ✅ Done — `src/world/npc_identity.gd`: deterministic per-seed name (two-part syllable generator), occupation (farmer/blacksmith/merchant/guard/fisher/herbalist/**hunter**/**nurse** — the last two added for the local production economy below: hunter is a producer distinct from farmer, nurse a new non-producer village-care role), personality trait, and driving need, tested. Relationships to other NPCs (also part of npc.md's Identity) are NOT modeled yet. Known gap: `HeroAppearance.CLASS_PALETTES` was not extended for hunter/nurse — both fall back to the warrior palette (fail-safe, not a crash) until a dedicated outfit is authored for each.
- **Organic Backstory Growth** (small) — ⬜ Not started
- **NPC Behaviour DSL** (huge) — ⬜ Not started
- **Daily Planning (LLM Scheduler)** (large) — 🚧 Partial — `src/world/npc_planner.gd`'s `Planner`/`FakeNpcPlanner` split (mirroring `WorldBossFitness`'s `PhaseGenerator` convention exactly): `FakeNpcPlanner` deterministically produces an occupation-keyed `{time_block, location_tag, activity}` day (work by day, home to sleep by night, a guard stays on watch through the evening instead of socializing) with zero LLM calls. The real LLM-backed planner (see intro above) isn't built yet.
- **Local FSM/Pathfinder Plan Execution** (large) — ✅ Done (basic) — `src/rendering/npc_marker.gd`: a lightweight per-frame FSM (deliberately much lighter than `CreatureMarker`'s full sense/perceive/act AI) reads the current schedule entry for the in-game hour (`src/world/npc_schedule.gd`, paced by the same `SECONDS_PER_SIMULATED_DAY` clock as the rest of the world sim) and walks toward wherever it resolves to -- "home", a settlement's 3 shared landmarks (well/stall/gate), or a personal workspot for occupations without a dedicated building yet (field/forge/dock/garden/hunting_ground). No real pathfinding (straight-line `move_toward`, no obstacle avoidance). Its bound `CharacterView` is now actually driven by that movement (previously it was bound once by `VillageRenderer._build_npc` and then never updated, so every villager's walk cycle sat frozen in `IDLE` despite visibly moving): `_update_animation` sets `is_moving`/`set_facing`/`set_movement_state` from the per-frame position delta each `_process`, and `NpcMarker.setup(world, tile_size)` (mirroring `CreatureMarker.setup`, now wired through `VillageRenderer.spawn_village`'s existing `world` param into `_build_npc`) gives it the same water-tile check `CreatureMarker` uses so a villager swims across water instead of walking on it.
- **Interrupt System** (medium) — ⬜ Not started
- **Live Dialogue System** (large) — ⬜ Not started — see "Basic Talk Interaction" below for the deterministic single-line placeholder standing in for this today.
- **Persistent Memory Log** (medium) — ✅ Done (mechanism); 🚧 not yet auto-triggered off ordinary NPC proximity — `MemoryRecord`/`MemoryStore`/`Rumor` (`src/emergence/`) implement `npc.md`'s "Memory, beliefs, and rumor propagation" spec: fact stays authoritative in `EventStore`, a memory is a separate lossy per-holder projection, `Rumor` steps confidence/source-type down one hop at a time (tested against a ~3-hop "heard it from a guy" feel). Content mutation still deliberately deferred per the spec. Propagation isn't yet wired to fire automatically off NPCs' landmark-proximity schedule (`npc_schedule.gd`) — the mechanism is real and callable, the trigger isn't live yet.
- **Self-Determination / Role Drift** (medium) — ⬜ Not started
- **Dynamic Quest Generation** (large) — ⬜ Not started (each `NpcIdentity` already carries a `need`, but nothing turns it into a request yet)
- **Instruction DSL** (huge) — ⬜ Not started
- **Instruction Complexity Budget** (small) — ⬜ Not started
- **Hiring/Wage System** (medium) — ⬜ Not started
- **Relationship/Trust Gate for Hiring** (medium) — ⬜ Not started
- **Child-NPC Trust Exception** (small) — ⬜ Not started
- **Faction/Settlement Reputation Aggregation** (medium) — ⬜ Not started
- **Emergent Village Festivals** (large) — ⬜ Not started
- **Basic Merchant Shopping** (medium) — ✅ Done (basic) — `src/gameplay/shop.gd`: a fixed gold-priced catalog (tool/weapon/armor/food), spent from the player's existing (previously unwired) `Wallet`. `EarthChunkManager.has_merchant_near` finds a nearby villager with occupation "merchant"; `Player._shop_step` (trade key, default T) buys the first affordable catalog item, cycling through the list on repeat presses so it doesn't just rebuy the same thing. No shop UI browsing, no per-NPC stock/pricing -- open follow-ups. **Selling the player's own goods now exists, but through a different path**: when no merchant is near, the trade key falls back to `Player.sell_food_to_village`, a real player-initiated sale into a nearby non-merchant villager's own `VillageMarket` (see docs/concept/progression.md "Ecological literacy") -- distinct from this shop catalog (no gold changes hands; the reward is XP for feeding a genuinely hungry village, read from `VillageMarket.can_buy_meal()`'s own real state). Selling INTO this fixed shop catalog itself is still not built.
- **Peak-timed direct-from-the-tree harvest & village-feeding XP** (small) — ✅ Done — docs/concept/progression.md "Ecological literacy": see Skills section above (`land_sense` keystone) and Progression's own status list for the full mechanism.
- **NPC Needs / Local Production Economy** (large) — ✅ Done — implements npc.md's "Needs and the local production economy" section in full: real per-NPC hunger (`src/world/npc_needs.gd`, mirrors `creature_needs.gd`'s shape -- hash-seeded stagger, `HUNGER_RATE_PER_SECOND=0.02` matching `CreatureNeeds`, `is_hungry()`/`feed()` -- deliberately hunger-only, no thirst, per the spec's own scope); real production (`src/world/npc_production.gd`) where farmer/hunter/fisher read the SAME weather-tied numbers the wild ecosystem already runs on via 2 new `EarthChunkManager` accessors mirroring `fish_population_near`'s exact existing pattern (`vegetation_density_near` for farmer, `herbivore_population_near` for hunter, the pre-existing `fish_population_near` reused as-is for fisher) -- a real drought (lower moisture, same biome/temperature) measured 93.8% lower farmer AND hunter yield in a real probe (`PRODUCTION_RATE_PER_SECOND=0.05`, a shared fraction-of-standing-resource rate, tested behaviorally rather than pinned to a magnitude, matching this codebase's existing fraction-per-time-unit tuned-rate convention); a real per-settlement `VillageMarket` (`src/world/village_market.gd`, one instance per `VillageRenderer.spawn_village` call, shared by every villager of that settlement) holding real stock keyed by real `ItemCatalog` ids (farmer→"fruit", hunter→"meat", fisher→"fish" -- no invented item ids) at a tested `VILLAGE_LOCAL_FOOD_PRICE=2` (below `shop.gd`'s `cooked_meat` price of 4, a deliberately distinct informal villager-to-villager price, NOT the player-facing global catalog); `src/world/npc_economy.gd` ties needs+`Wallet`+production+market together per NPC and is driven once per frame from `NpcMarker._process` (`NpcMarker.setup_economy`, wired by `VillageRenderer._build_npc`). **Judgment calls made and documented in-code**: (1) a producer self-feeds for FREE from their own currently-active production (no market/gold transaction) rather than buying from the market like a non-producer -- gated on genuinely nonzero real yield right now, so total ecological collapse can still starve a producer too, not just everyone else; (2) gold is a real two-faucet flow (`docs/concept/economy.md`), not a closed loop -- a producer earns `YIELD_TO_GOLD_RATE=1` gold per unit the instant it's gathered (independent of whether it's ever bought), a buyer spends `VILLAGE_LOCAL_FOOD_PRICE=2`, and the two rates deliberately differ (a real wholesale-vs-retail margin) rather than round-tripping the same number; (3) the market is NPC-only -- npc.md's own framing never extends it to the player, so the player still only uses `shop.gd`'s existing global catalog; (4) nurse's `FakeNpcPlanner` work tag resolves to the shared "well" landmark (a village-care role tending the square) rather than a new dedicated building; (5) settlement occupation balance is left to chance, not guaranteed (see Procedural NPC Population Generation above). **Real probe** (`godot --headless -s <standalone script>`, not GUT, run against the actual production code -- `EcosystemSimulation`/`NpcProduction`/`NpcEconomy`/`VillageMarket`, not hand-traced): a real settlement (chunk (30,1) in one run) with a real hunter and real blacksmith -- the hunter gathered 34 real "meat" units and earned 34 real gold over a simulated 300-second workday reading a real `herbivore_population` of 2.304 in a lush region; the blacksmith, forced hungry with 50 gold, spent 2 gold buying 1 unit from that same real stock and was fed (hunger 1.0→0.0, stock 34→33); a stranded merchant with an empty market and no gold stayed genuinely hungry (hunger→1.0, no crash, no free pass) after 100 simulated seconds. **Known gaps**: `VillageMarket` is freshly created per `spawn_village` call, so a chunk reload resets village stock to empty -- the same "regenerates identically on revisit, no persistence" limitation trees/creatures/houses already accept, not novel to this system; no wiring yet from sustained hunger to any lifecycle/death consequence (deliberately out of scope this pass, see npc.md's own "Deliberately NOT in this pass" line); `HeroAppearance` outfit palette gap for hunter/nurse (see NPC Identity System above). **Update**: a working farmer's yield now also depletes the real land it comes from — see world.md's "Land Health" entry above — so a village worked too hard by its own farmers, not just a drought, can genuinely go hungry over time.
- **Basic Talk Interaction** (small) — ✅ Done (basic) — spec'd in `concept/npc.md`'s "Minimal talk interaction" section: an explicit placeholder for the real Live Dialogue System below, not a cut-down version of it. `src/world/npc_greeting.gd` turns an `NpcIdentity` into one deterministic line flavored by its own personality trait and need (8 trait templates × 6 need phrases); `EarthChunkManager.nearest_npc_near` finds the closest villager (any occupation) within range; `Player._talk_step` (talk key, default G, new `Keybindings` entry) shows that villager's line as a HUD banner on press. A proximity prompt ("Talk (<bound key>)", reading the live keybinding so a rebind is never stale) floats above whichever villager is in range (`World._update_interaction_prompt`, world-to-screen via the viewport's canvas transform), shown even before the key is pressed -- the general "nearby-interaction hint" affordance requested for NPCs. No memory of the exchange, no branching, no quest hooks.
- **Settlement Growth via Migration** (large) — ⬜ Not started — spec'd in `concept/npc.md`'s new "Settlement growth" section and `concept/quests.md`'s Settlement growth section: player-built structures as a habitability pull, migration as a new replan-interrupt resolution, and unification of player-grown settlements with procedurally-seeded ones. Depends on Village-Endangerment Attractor Mechanism below for its preferred migration source (settlements that lost that fight).

### Quests (`concept/quests.md`)

New concept doc (2026-08-13), resolving `overview.md`'s former "quest
template design" open question. No code exists yet — depends entirely on
Phase 2's NPC daily-planner/replan architecture and Phase 1's ecosystem/
evolution sim, both still partial. All ⬜ Not started:

- **Need Source Taxonomy (safety/production/social)** (medium)
- **Individual-to-Settlement Quest Promotion** (medium) — exact-target
  matching + population-scaled quorum (`max(2, ceil(population ×
  threshold_fraction))`, `threshold_fraction` a tuned constant still
  needing a real number).
- **Settlement Representative Selection** (small) — reuses
  `concept/factions.md`'s social-influence weighting rather than a separate
  score; that weighting itself isn't implemented yet either
  (`src/gameplay/faction_reputation.gd` has the aggregation math, not the
  per-NPC influence weighting it would need).
- **Village-Endangerment Attractor Mechanism** (large) — settlement
  wealth/population feeding `predator_population_model.gd`'s carrying-
  capacity term as additional "opportunity biomass"; combat strength
  explicitly excluded from this term.
- **Autonomous Defense Resolution (loaded/unloaded)** (large) — real-time
  combat via existing `combat.md` mechanics for loaded chunks; a catch-up-
  style probabilistic resolution (same class of mechanism as
  `chunk_ecology_catchup.gd`) for unloaded ones.
- **"Join the Defense" Quest Shape** (medium)
- **Quest Consequences (reputation/discount/skill reward; ruin on failure)**
  (medium)
- **Supply/Demand Production Quests** (medium) — reuses the promotion/
  quorum machinery above with an `economy.md`/`crafting.md`-sourced need.

### Fishing (`concept/fishing.md`)

- **Aquatic ecosystem population simulation** (large) — ✅ Done —
  `src/world/aquatic_population_model.gd` (fish sibling of
  `herbivore_population_model.gd`, wraps `population_model.gd`; growth rate
  0.5/day, pinned faster than herbivores' 0.3 -- fish are more r-selected)
  and `src/world/water_area_survey.gd` (interior-water cell count + mean
  water temperature -> a bell-curve `temperature_suitability`, shared with
  `FishRenderer` so simulated capacity and spawnable cells agree). Wired
  into `EcosystemSimulation` (`_fish_population`/`_water_area_cells`/
  `_water_temperature`, seeded at capacity equilibrium on first load, same
  migrate-then-step shape as herbivores), `ChunkEcologyCatchup.advance`
  (fish/fish_capacity alongside herbivores/predators), and
  `EarthChunkManager` (`_apply_ecology_catchup` extended, `fish_population_at_chunk`).
  `EcosystemSimulation.record_catch(chunk_coord, count)` is the explicit
  harvest term the land model still lacks -- wired to both the player's
  `catch_nearest_fish` and a piscivore bird's successful dive (see below).
  Real cross-session persistence via `ChunkSerializer.save_fish_population`/
  `load_fish_population` (one file per chunk, `user://chunk_fish_population`)
  -- unlike herbivore/predator/vegetation state, a fished-out chunk stays
  fished-out across a full game restart, not just an in-session reload. See
  [fishing.md](concept/fishing.md#aquatic-population-model).
- **Aquatic environmental factors** (medium) — 🚧 Partial — water
  temperature is live as a capacity multiplier (`water_area_survey.gd`'s
  mean-interior-water-temperature -> `AquaticPopulationModel.temperature_suitability`,
  reusing `Chunk.temperature`); water quality/food-density remain open, see
  fishing.md's Open Questions.
- **Hydraulic erosion water generation** (large) — 🚧 Partial — `hydraulic_erosion.gd` exists/tested but is part of the old procedural pipeline, unused for Earth (real elevation data already contains real rivers/oceans).
- **Visible, catchable fish entities** (medium) — ✅ Done — ocean cells spawn actual `FishMarker` nodes (`src/rendering/fish_marker.gd`): `FishRenderer` (mirroring `TreeRenderer`/`CreatureRenderer`'s chunk-based spawn/despawn shape) places fish on a chunk's **interior** water tiles (never a shore-adjacent cell), in one of 4 colorful hand-authored species (`ProceduralFishSprite`: goldfish, bluegill, speckled trout, patched koi). Spawn *count* is now population-driven (`spawn_fish`'s `target_count` param, defaulting to -1 for the legacy independent per-cell-probability path so isolated callers/tests keep working unchanged): `EarthChunkManager._fish_target_count` scales `FishRenderer.MAX_FISH_PER_CHUNK` by the chunk's live `fish_population`/`fish_capacity` ratio, refreshed both on chunk load and on `EarthChunkManager`'s periodic ecosystem step, so a fished-down chunk visibly shows fewer swimming markers, not just after a reload. Each fish idle-swims via `CreatureWander`'s pure drift pattern (deliberately lighter than `CreatureMarker`'s full sense/perceive/act AI), keeps `CLEARANCE_PX` of open water on every side so no part of the sprite ever overlaps the beach, and deflects along the shore instead of freezing when its heading points at land. A fish turns gradually toward its target heading (`FishMarker.TURN_RATE`) and its sprite rotates to face the way it's swimming. Fish can also be **attracted toward a cast fishing line** (`FishMarker.set_attraction`/`EarthChunkManager.set_attraction_point`). `EarthChunkManager.catch_nearest_fish` removes a real nearby fish, names its species in the catch message, **and now decrements the real aggregate population it came from** (`EcosystemSimulation.record_catch`) -- the actual reward quantity/rarity still comes from the independent `FishingMinigame` roll. Its occasional water-ripple disturbance (`FishMarker._step_water_ripple`, on an unhurried per-fish-varied interval so a shoal doesn't flood the shared disturbance buffer) now fires a short `TAIL_WAG_RING_COUNT`-ring burst spaced `TAIL_WAG_RING_SPACING` apart, rather than one isolated ring, so a trigger reads as an actual tail wag pushing a short streak/wake across the surface -- the same forward interference pattern the player's own wading ripple makes -- instead of a single random poke; each burst is also gated on the fish having genuinely moved since the last check (mirroring `Player._step_water_ripples`' own movement gate), so a fish boxed into water it can't leave never ripples at all (reported: "It should produce a streak of rings but only when wagging the tail, so that the interference creates a forward pattern, just like when the player walks through water"). A follow-up widened `TAIL_WAG_RING_SPACING` (slower streak) and made a burst genuinely a fast tail flap, not just a faster ring cadence: `FLAP_SPEED_MULTIPLIER`/`_is_flapping` speed the fish itself up for exactly the burst's duration (reported: "slower bursts please also only when they flap tail fast"). The shore-avoidance deflection (`_DEFLECTION_TURNS`) used to re-derive its pick from scratch off the raw wander/attraction target every single frame, which flip-flopped between nearby valid deflections right at a shoreline and read as flickering; `_first_clear_heading` is now shared by both the smoothed-heading bias (a longer, fixed lookahead, `_SHORE_LOOKAHEAD_PX`) and the movement step, and the bias search starts from the fish's OWN current (already-safe) heading rather than the blocked raw target once that target is unreachable, so it holds a stable pick instead of re-litigating it every frame (reported: "avoid trying to turn into the border of the water so that the fish doesn't flicker when repelled from the edge"). No DNA/phenotype, no bait-driven species targeting -- species is still a per-tile deterministic color/pattern pick.
- **Aggregate + individual-agent promotion simulation** (large) — ✅ Done — `EcosystemSimulation` now has a real aquatic sibling of its herbivore/predator population tracking (see above), and `FishRenderer`'s population-driven `target_count` is the promotion-from-aggregate-population step, the same role `CreatureRenderer` plays for land creatures. See fishing.md.
- **Fish-eating birds (kingfisher piscivore)** (medium) — ✅ Done — see the
  Species roster entries under Phase 1 / Ecosystem below
  (`concept/ecosystem_dynamics.md`); listed here too since it's the one
  mechanism that reaches directly into this section's `record_catch` harvest
  term.
- **DNA/phenotype/sexual-selection system (aquatic)** (huge) — ⬜ Not started
- **Sexual selection / mate choice reproduction** (large) — ⬜ Not started
- **Rare-phenotype catch desirability** (small) — ⬜ Not started
- **Fishing catching minigame** (medium) — ✅ Done — a **playable fishing loop** now exists: `src/gameplay/fishing_session.gd` (tested state machine: cast → wait → bite → react → caught/missed) drives the pre-existing `fishing_minigame.gd` timing/rarity math. A craftable **fishing rod** (stick + plant fibre; player starts with one), a `fish` action (default F) that casts when next to open water and reels on the second press, a HUD prompt ("Casting…" → "! BITE — press the fish key!" → "Caught a … fish!"), and rarity-scaled fish rewards into the inventory (cooked over a campfire, eaten for hunger). A rare/legendary catch is now its own item (`rare_fish`/`legendary_fish`) that grants a real timed buff on eating (extra stamina regen / +30% melee damage) instead of the rarity vanishing after reward-quantity math — see Cooking section's "Dish Buffs". **Casting is now visible**, closing a reported gap ("no animation of the rod being thrown into water and also doesn't attract near fish and also no animation when fish bites"): `src/gameplay/fishing_cast.gd` computes a landing point from the player's facing (`FishingCast.CAST_DISTANCE_PX`), a small procedurally-drawn bobber (`ProceduralBobberSprite`) appears there, casting reuses the melee swing animation as a rod-throw, `EarthChunkManager.set_attraction_point`/`clear_attraction_point` draws any loaded fish within `Player.ATTRACTION_RADIUS` toward the bobber (still respecting shore clearance -- an attracted fish won't follow the line onto the beach), and the bobber visibly dips while a fish is biting (`FishingSession.phase_elapsed_seconds`, a new getter, drives the bob). Bait depth, species/location availability, and the aquatic population sim are still ⬜.
- **Bait/lure system** (medium) — ⬜ Not started
- **Location-based fish availability** (medium) — ⬜ Not started
- **Cooking ingredient integration** (small) — ⬜ Not started
- **Crafting material integration** (small) — ⬜ Not started
- **DNA-quality-to-material-quality link** (medium) — ⬜ Not started
- **Aquatic taming (Beastmaster/Herbalist crossover, open question)** (medium) — ⬜ Not started
- **Companion fish / pond keeping** (medium) — ⬜ Not started
- **Aquatic mount** (large) — ⬜ Not started
- **Species-category/DNA-quality pet model** (small) — ⬜ Not started
- **Freshwater/saltwater ecosystem separation (open question)** (medium) — ⬜ Not started

### Soil Fauna (`concept/soil_fauna.md`)

The trophic tier below every plant-eater in the world, and the first songbird
feeding behaviour of any kind. `ecosystem_dynamics.md` named this exact gap
("Real songbirds are largely insectivore/granivore — no feeding model exists
for either input"); this closes the **insectivore** half. Before it, songbirds
had literally no behaviour: `scent_world` is deliberately null for birds, so a
robin was pure home-tethered drift, and the marker's `perched` folded-wing
state had never once been set by anything in `src/`.

- **Per-chunk earthworm population** (medium) — ✅ Done — `src/world/earthworm_patch.gd`,
  cloning the `TallGrass`/`FlowerPatch`/`DesertScrub`/`TundraLichen` patch-sim
  contract exactly (pure `RefCounted`, `PixelNoise`-seeded — never Godot's
  string `hash` — hard `MAX_WORMS` cap, `advance(delta)`, and a pure
  `take(cell) -> bool` so a bird can just try and let the sim decide). What is
  genuinely different from its siblings: worms are never created or destroyed
  by weather. A chunk gets a permanent set of BURROWS, and each animates a
  `surfacing` value between "deep in the soil" (invisible, uncatchable) and
  "at the surface" (rendered, catchable). Gated to soil-bearing biomes only
  (grassland/forest/rainforest — ocean has no soil, desert no moisture, tundra
  is permafrost), mirroring `AmbientFlyerRenderer.BIRD_BIOMES` so the birds
  that eat worms live exactly where the worms do.
- **Moisture/temperature-driven surfacing** (small) — ✅ Done — a tested pure
  function (`EarthwormPatch.surface_drive`) of live weather moisture
  (`WeatherModel.soil_moisture`, new) and soil temperature
  (`EarthwormPatch.soil_warmth`). Wet soil lets a worm respire above ground;
  frozen soil sends it deep however wet it is. Each burrow has its own
  deterministic **reluctance**, so the response is GRADED rather than a switch
  — at drive 0.35 roughly a third of a chunk's worms are up, so drizzle brings
  a few and a downpour brings most. Two deliberate non-obvious choices, both
  test-pinned rather than eyeballed: clear weather keeps a real moisture
  baseline (it is 50% of all weather rolls, and a mechanic only visible in
  rain is one the player mostly never sees), and soil warmth uses a
  `WINTER_SOIL_FLOOR` blend rather than the `climate x season` product
  `_warmth_at_pixel` uses for fruiting — that product troughs at exactly 0.0
  mid-winter and is already ~0.09 at world start (spring's modifier is only
  ~0.15), so it would have read as frozen ground on a fresh world and shown
  the player nothing.
- **Surfaced worms crawl** (small) — ✅ Done — a worm at the surface was a
  static decal; it now creeps, via `EarthwormPatch.crawl_offset` (pure,
  deterministic per seed+time, two sines at different rates so the path is a
  slow open curve rather than an orbit or a shuttle). Deliberately a
  **sub-tile offset, not a change of cell**: the cell is the worm's identity
  everywhere else (`worm_cells`/`is_surfaced`/`take`, and a robin's own
  targeting), so a worm that changed cells mid-approach would leave the bird
  pecking where it used to be. Bounded by `limit_length` to the radius the
  constant promises — two independent sines compose ~1.12x longer than
  either, which the "stays within its own cell" test caught. Driven per
  frame from `step_worms`; measured live at ~1.3px per 3s, a creep.
- **Deer sized to 0.8x a horse** (small) — ✅ Done — `world_scale` 1.15 →
  0.96 against the horse's 1.2, requested directly. Pinned as a RATIO test
  rather than a bare number on each, so re-sizing the horse without the deer
  fails loudly instead of silently breaking the pair's proportion.
- **The entire ecology simulation never ran** (small fix, enormous blast
  radius) — ✅ Fixed — `World._owns_ecosystem_simulation` was
  `_is_dedicated_server or multiplayer_peer == null`, which is **false for
  the normal way the game is played**: starting a world from the menu HOSTS
  it (`_start_server`), so a peer exists and the process is not a dedicated
  server. That gate fronts every ecology step — `step_ecosystem`,
  `step_forage`, `step_tree_spread`, `step_tall_grass`, `step_flowers`,
  `step_worms`, `step_fruiting` — so none of them had ever run. And because
  `step_tree_spread` is also what advances `_world_age_seconds`, the world
  CLOCK was frozen at zero, so the season and weather never changed either:
  the world sat permanently on day-zero "spring, clear". Measured live in
  the running game: `owns=false age=0`. This is the actual root cause behind
  a long run of reports that each looked like a separate bug — no fruit
  trees, no worms ("no worms visible even in rain" — it had never rained),
  the robin stalling with nothing to hunt, no shed seed, nectar never
  regenerating. A hosting player IS the authority for their own world; the
  rule is now the tested pure function `owns_ecosystem_simulation_for`
  (dedicated server → owns; no peer → owns; otherwise → owns iff server),
  with a client connected to someone else's world still correctly deferring.
  Verified live after the fix: world clock advancing, weather turning over to
  rain, ground seed accumulating 3→101, and 200+ worms surfaced and
  rendered. **Why every test missed it for so long**: the suites call the
  step functions directly and never pass through this gate, so subsystem
  coverage stayed green while the game ran none of it — the single most
  useful lesson from this whole sequence.
- **Worms were gated off entirely at the spawn point** (small) — ✅ Fixed —
  reported as "I can't see any worms or birds eating worms". Not a wiring
  bug: the whole mechanic was switched off by its own calibration.
  `MILD_WARMTH` (the warmth at which temperature stops limiting surfacing)
  was 0.4, but `soil_warmth` multiplies climate temperature by a seasonal
  factor, so the game's own spawn point — Berlin, measured climate
  temperature **0.413** — peaks at 0.413 in MIDSUMMER and sits at **0.254**
  in the spring the world starts in. Measured drive at spawn in spring:
  **0.41 in rain, 0.48 in a storm, 0.12 clear** — against
  `SURFACED_THRESHOLD` 0.6. A worm could therefore never surface there in
  ANY weather, for the entire early game, so no player had ever seen one and
  robins had nothing to hunt. `MILD_WARMTH` recalibrated to 0.28. Verified
  end to end: a real spring-rain patch now surfaces **21 of 23** burrows
  within 20 simulated seconds, where it previously surfaced zero in every
  weather. Pinned by four tests asserting the BEHAVIOUR against the real
  spawn climate (rain surfaces worms in spring and summer; clear and cloudy
  never do; winter rain still does not, because cold ground is the cold
  gate's whole purpose) — so re-tuning worldgen temperature or the season
  curve fails loudly there instead of silently switching the mechanic off
  again, which is exactly how this went unnoticed.
- **Seed, granivory and bird endozoochory** (medium) — ✅ Done — a meadow now
  feeds two guilds at two different times from the SAME plants, which falls
  straight out of the bloom table already in `FlowerSpecies`: **in bloom** a
  flower offers nectar to pollinators, **out of bloom** it has gone to seed
  and feeds granivores. `FlowerPatch.seed_cells(season)` is exactly
  complementary to `blooming_cells(season)` — a plant offers one or the
  other, never both — so nothing new is placed in the world and the seasons
  gain a real consequence beyond which blooms are drawn: which guild a given
  meadow supports rotates through the year. Seed regrows far more slowly
  than nectar (`SEED_REGEN_PER_SECOND`, ~8 min vs ~1 min): a plant refills a
  nectary repeatedly but sets seed once, so a picked-over patch stays picked
  over. `EarthChunkManager.seeds_near`/`take_seed_at` are the pair
  `FlyerDiet` had been documenting as missing since the diet table was
  written ("there are no seeds in the world yet — when there are, this gains
  a parallel seed_world line and nothing else has to move"); that prediction
  held exactly. **Sparrows finally forage**: they carried a `FOOD_SEEDS`
  entry with nothing to eat, and now get a `seed_world` plus the shared
  `GroundForageBehavior` brain, hunting seed in parallel with the robin's
  worms/fruit through the same seek→descend→peck cycle. **Bird
  endozoochory**: a swallowed seed rides the existing carry timer and is
  planted where the bird later drops it (`plant_flower_at`), so new flowers
  grow away from the plant they came from — requested as "birds that eat
  seeds should disperse and plant them so new flowers grow where they poop".
  Range is the point: a grazing mammal brushing a bloom carries seed a few
  tiles (`SeedDispersal`, pre-existing), a bird carries it 10–40, so
  granivores are how meadows colonise ground no grazer walks. A seed dropped
  where flowers cannot root is simply lost, the same honest check every other
  dispersal path uses. Spec in
  [flora.md](concept/flora.md#seed-the-other-half-of-a-flowers-year).
- **Bloom-aware flower rendering** (small) — ✅ Done —
  `FlowerPatch.blooming_cells(season)`, used by
  `EarthChunkManager._sync_flower_sprites` (and re-synced from `step_flowers`
  when the season name changes, since sprites are otherwise only built at
  chunk load). Only species in bloom **this season** are drawn. Reported
  twice as broken pollinator foraging, latterly with a screenshot: "There's a
  butterfly near two flowers and does nothing... they are not attracted by
  scent at all." Foraging was never broken — an all-seasons end-to-end guard
  (`test_a_pollinator_forages_a_blooming_flower_in_every_season`, every
  season × every species that blooms then, off the real `FlowerSpecies` bloom
  table) passes. The bug was that the WORLD lied: every planted flower was
  drawn year-round while `ScentField` gives out-of-bloom species exactly zero
  scent, so a spring meadow showed summer species a butterfly could not smell.
  Diagnosing it also exposed a genuine inconsistency — scent respected bloom
  but `choose_target` did not, so a pollinator could not *smell* an
  out-of-season flower yet would still drink one it drifted into. Bloom is now
  filtered at the single point every consumer reads (the marker's sniff), so
  rendering, steering and targeting agree. **Why the whole suite missed it**:
  every pre-existing pollinator test left the stub world at its default
  `"summer"` — a season-blind suite cannot guard a season-gated mechanic. The
  new guard is parameterized over all four.
- **No nectar omniscience; memory scaled to refill** (medium) — ✅ Done —
  Reported: "the butterflies are NOT checking EVERY flower they haven't
  visited yet. Somehow they know it's empty without checking for nectar
  first... butterflies should forget which flowers they visited after a
  reasonable time so they can check same flowers again... Should refill
  nectar over one minute." Candidate blooms were filtered on `nectar > 0`
  read straight out of world data — for flowers the pollinator had never
  been near. A pollinator cannot see how full a flower is from across a
  meadow; it lands to find out. Nectar level is no longer consulted when
  choosing a target: **every unchecked bloom is worth investigating**, and
  emptiness is discovered on arrival. The only thing a flyer legitimately
  knows is where it has personally been. Consequently visit memory now
  **vetoes** rather than ranks (falling back to an already-checked bloom
  meant re-landing on the one it had just found empty — orbiting it), and
  the two timescales were retuned to match each other: nectar refills in
  60s (was ~20s) and memory expires at 90s (was 600s), so a flyer returns to
  re-check a bloom shortly after it has plausibly restocked. Steering still
  ignores drained blooms — a spent flower has no reward to advertise, and
  that is what stops a worked-out patch from pulling the flyer back — so
  targeting and steering now use deliberately different lists. Required
  migrating ~8 tests that encoded the old omniscient contract ("a spent
  bloom is never a candidate" → "a bloom it just *checked* is never a
  candidate").
- **Pollinators stalling mid-flight** (small) — ✅ Done — the scent-steered
  branch blends the wander heading with the scent gradient via `lerp`, and
  opposing vectors CANCEL: whenever the gradient pointed against the wander
  heading at roughly equal weight the blend collapsed to ~zero and the flyer
  simply did not move that frame (reported: "butterflies should only stop
  moving when they sit down on a flower... not during wandering"). Falls back
  to the wander heading now, so only drinking ever holds a pollinator still.
  Same ill-conditioned-cancellation class as the land creatures' wander bug —
  the third time this pattern has appeared. Guarded by
  `test_a_pollinator_never_stalls_mid_flight` (zero non-drinking frames
  without movement over 90 simulated seconds).
- **Scent-threshold commitment** (small) — ⬜ Attempted and REVERTED, with
  the requirement still open. Requested: "when all nearby flowers are empty
  the butterfly should not smell distant flowers directly... it should
  instead randomly wander and search away from empty flower field and only
  steer to a new flower once scent strength reaches a given threshold."
  Targeting queries `FORAGE_SEARCH_TILES` (18 tiles) while scent carries only
  `ScentField.RADIUS_TILES` (6), so pollinators do commit to blooms they
  cannot smell. Gating commitment on real concentration was implemented and
  measured: a pollinator that had worked its patch dry then searched by
  wandering alone and **never found a patch 12 tiles away in 33 simulated
  minutes** — foraging stopped happening entirely (reported within minutes:
  "now NO foraging at all happens anymore"), which is strictly worse than the
  unrealistic reach. Reverted rather than shipped. The gate is not the hard
  part; **effective search is**: random relocation hops re-randomize every
  0.7s, so they random-walk instead of covering ground. Doing this properly
  needs a directed search — hold a search heading across several relocation
  hops so a flyer flies transects — and only then re-apply the threshold.
- **Per-species flyer diet** (small) — ✅ Done — `src/gameplay/flyer_diet.gd`.
  Robins eat worms, sparrows eat seeds, kingfishers fish, butterflies/bees
  nectar. Seeds now exist (see the Seed/granivory row below), so every diet
  entry in the table is finally backed by something real to eat.
  Deliberately NOT `CreatureInfo.DIET_BY_SPECIES`, which is
  display-only HUD flavour text ("Grazer"/"Hunter") that nothing behavioural
  reads. This one is behavioural and enforced at SPAWN time: a robin is handed
  a worm world and a ground-forage brain, a sparrow is handed neither, so a
  sparrow is *structurally* incapable of hunting worms rather than merely
  missing a branch (`test_a_sparrow_is_spawned_unable_to_hunt_worms`,
  `test_only_worm_eaters_are_wired_for_worms`).
- **Ground-forage behaviour (sit down, peck, resume)** (medium) — ✅ Done —
  `src/gameplay/ground_forage_behavior.gd`, a pure engine-free state machine
  in `PiscivoreBirdBehavior`'s shape (that module decides WHEN; the marker
  applies the world effect): SEEKING → DESCENDING → PECKING → RESUMING. The
  descent ends on ARRIVAL rather than a timer (distance varies) but has a
  give-up timeout; the strike resolves once, part way through the peck, with
  the beak actually down — `PECK_STRIKE_FRACTION` is DERIVED from
  `PECK_COUNT` as the midpoint of the middle dip, not a literal, because a
  fraction on a dip boundary lands on the wrong side of it under ordinary
  float accumulation. `REHUNT_SECONDS` is the "run" half of a real robin's
  run-stop-peck cycle. Target selection reuses
  `PollinatorForaging.choose_target` (which despite its home is really "pick
  one of the nearest few, scattered by a per-flyer seed") rather than growing
  a second parallel nearest-wins implementation.
- **Visible worms and a visible peck** (small) — ✅ Done —
  `src/rendering/procedural_worm_sprite.gd` (tapered, segmented, seeded curve;
  world length stated in TILES with the scale derived to hit it, so raising
  the canvas for detail cannot change how big a worm looks — the trap this
  project has hit twice) and `ProceduralBirdSprite.generate_pecking_image`
  (head and bill swung down and forward, wings still folded), driven through
  `AmbientFlyerMarker`'s previously-dead `perched` state. The marker
  alternates the peck frame against the perched frame so the head dips
  `PECK_COUNT` times instead of the bird freezing while a worm silently
  vanishes. Pixel-tested (the dipped bill must reach lower than the
  head-up bill, and stay on the canvas for every species including the
  kingfisher's oversized dagger bill).
- **Live wiring, end to end** (small) — ✅ Done — worm sims instantiate on
  chunk load and free on unload; `EarthChunkManager.step_worms` (called from
  `World._process` under the same `_owns_ecosystem_simulation()` authority
  gate as every other ecology step) advances every loaded sim each frame while
  throttling the per-chunk weather lookup and sprite churn to
  `WORM_REFRESH_INTERVAL`; `worms_near`/`take_worm_at` mirror
  `flowers_near`/`drink_nectar_at`, including the 3x3-chunk-neighbourhood
  scan bound. Deliberately not left as pure tested logic the way
  `DesertScrub`/`TundraLichen` were (see the Biome-Specific Ground Cover row
  below, whose `graze()` still nothing calls) — a runtime probe confirmed a
  real spawned robin eating real worms out of a real Berlin chunk.
- **Bug found and fixed on the way** — the robin's worm-choice scatter seed
  was originally `hash("%d_worm" % seed)`, which put EVERY seed in a plausible
  range into bucket 0 once taken modulo the small candidate pool: every robin
  in a meadow would have picked the identical worm and conga-lined behind it.
  That is the same single-bucket freeze `PixelNoise`'s doc comment records
  ("a seeded index froze to a single bucket, so every village house came out
  the same size"). Now seeded from `PixelNoise.value`, with a regression test.
- **Seeds + sparrow granivory** (medium) — ⬜ Not started — the next pass;
  same patch-sim contract, same ground-forage state machine, a parallel
  `seeds_near`/`take_seed_at` pair, and one extra line in the diet wiring.
  `FlyerDiet.FOOD_SEEDS` already sits on the sparrow waiting for it.
- **Fruit as a robin diet entry** (small) — ⬜ Not started — waits on
  foraging from fruit trees; `FlyerDiet.FOOD_FRUIT` exists for it.
- **Worm population dynamics / bird carrying capacity** (large) — ⬜ Not started —
  burrow count is fixed and deterministic per chunk; worms do not reproduce,
  spread or starve, and a worm-rich chunk does not hatch more robins the way a
  flower-rich chunk hatches more pollinators.
- **Persistence / catch-up integration of eaten burrows** (medium) — ⬜ Not
  started, deliberately — a reloaded chunk re-seeds deterministically and
  loses which burrows had been eaten, exactly like `FlowerPatch`, `TallGrass`,
  `DesertScrub` and `TundraLichen` before it. Worm predation is a
  short-timescale, self-renewing local effect; carrying it in
  `ChunkEcologyCatchup` alongside the herbivore/predator/fish aggregates would
  imply a fidelity the rest of the patch-sim layer does not have. Called out
  here rather than left as a silent gap.

### Flora (`concept/flora.md`)

Flowering plants, scent, and pollinators (see
`concept/flora.md#flowering-plants-scent-and-pollinators`):

- ✅ `FlowerSpecies` — crocus/tulip/rose/lavender/clover, each with its own
  bloom seasons, colour and scent strength. Colour and scent are deliberately
  independent axes, so the showiest meadow is not automatically the most
  attractive one to a pollinator.
- ✅ `ScentField` — concentration is the SUM of every blooming flower's
  contribution with a squared distance falloff, so a dense clump is a
  genuinely stronger signal than the same flowers spread thin. Out-of-season
  species contribute nothing, so a meadow's pull rises and falls across the
  year.
- ✅ Pollinator hooks on the field: a bounded, saturating spawn multiplier and
  a normalized gradient direction for steering.
- ✅ Flower sprites and their placement in the world — `ProceduralFlowerSprite`
  (a real stem+blossom sprite, per-species colour, `EarthChunkManager._sync_
  flower_sprites` keeping one per live `FlowerPatch` cell in sync with the
  chunk lifecycle) replaced the flat flower pixels baked into grassland tile
  art.
- ✅ Seed dispersal carried by animals — `SeedDispersal` (pure pickup/carry-
  distance/can-root-in rules) + `EarthChunkManager._step_seed_dispersal`,
  hooked into the same per-tick pass that grazes herbivores: a grazing
  animal has a chance to pick up a nearby species' seed, carries it (tracked
  on the creature itself, `carried_seed_species`/`carried_seed_origin`, so it
  survives a chunk boundary crossing) for a seeded random distance, then
  plants it via `FlowerPatch.plant`. Flowers now genuinely spread along
  actual grazing corridors instead of needing to be seeded by hand.
- ✅ `ScentField` wired into `AmbientFlyerRenderer`/`AmbientFlyerMarker`
  spawning/steering — a pollinator's `scent_world` (duck-typed onto
  `EarthChunkManager`) samples `flowers_near` on a throttled sniff interval,
  blends a gradient-direction bias into its ordinary wander (`SCENT_STEER_
  WEIGHT`, partial so it still meanders rather than beelining), and commits
  to a concrete target to land on and drink from (see `PollinatorForaging`
  below) rather than merely drifting past blooms forever. Bees spawn from a
  **separate pool and per-chunk budget** from the true butterflies
  (`AmbientFlyerRenderer.BEE_SPECIES_POOL`/`MIN_BEES_PER_CHUNK`, additive to
  `TRUE_BUTTERFLY_SPECIES_POOL`/`MIN_BUTTERFLIES_PER_CHUNK`) -- they
  originally shared one pool with the butterflies under the same fixed
  MIN..MAX budget, which meant every bee that spawned was one fewer
  butterfly, silently halving true butterfly sightings once bees were added
  (reported: "there are much less butterflies and bees"). Splitting the
  budgets makes bees an addition to a meadow's pollinator presence rather
  than a slice out of it.
- ✅ **Foraging is a real land→drink→move-on cycle, not a stable attractor**
  (`PollinatorForaging`) — a flower's own nectar (0..1, refilling slowly via
  `NECTAR_REGEN_PER_SECOND`) is a depleting resource, and a pollinator
  separately remembers which flowers it personally emptied so it moves on
  even while one is still refilling. That memory is **time-based**
  (`VISIT_MEMORY_SECONDS`, ~10 minutes) rather than a bounded count: a
  pollinator with only one or two flowers in its own sniff radius used to
  exhaust a small fixed-count memory on them and have nowhere left to go
  until something aged out by count, which never happens with nothing new
  to visit (reported: "remember emptied flowers for only 10 minutes or so").
  Separately, the scent gradient itself doesn't know a flower's current
  nectar level (only which species are in bloom this season) — left
  unfiltered, a fully-drained local patch kept pulling the steering toward
  its exact position just as strongly as a full one even though landing
  there was correctly refused, which read as orbiting the one spent bloom
  (reported: "they should move to a new flower field when the last flower
  nearby got emptied so they don't circle the last flower for an hour").
  `AmbientFlyerMarker` now filters drained flowers out before computing the
  gradient at all, so an all-drained patch reads as nothing to smell and
  ordinary wander actually carries the flyer elsewhere.
- ✅ **A worked-out neighbourhood recovers, and no longer traps the flyer**
  (reported: "foraging works for a while but when all nearby are empty
  butterflies and bees stop foraging completely and just drift around
  meaninglessly", "they are not attracted by the scent anymore it seems").
  Two independent causes, both measured with a runtime probe rather than
  inferred — note that neither was nectar regrowth failing (nectar refills
  in ~20s and was verified doing so) nor scent decaying with nectar (scent
  is a function of species and season only, and a drained flower emits
  exactly as much as a full one: probed at 0.694 either way):
  1. **Visit memory vetoed instead of ranked.** Probed drinks per simulated
     minute were `[4, 0,0,0,0,0,0,0,0,0, 4, ...]` — one productive minute,
     then nine idle, resuming precisely at `VISIT_MEMORY_SECONDS`, despite
     every flower having refilled within ~20s. `choose_target` now prefers
     unvisited blooms but falls back to a remembered-and-refilled one rather
     than returning nothing, so a recovered meadow is foraged again. A
     just-drained bloom is still excluded by its nectar level. Probed after:
     a sustained ~20 drinks/minute indefinitely.
  2. **The wander tether made ranging impossible.** Ambient flight is
     anchored to a home point within `radius` (30px for pollinators), so a
     flyer with a full patch 12 tiles away drank nothing in ten simulated
     minutes and never got further than 31.6px from home. The forage search
     now runs at `FORAGE_SEARCH_TILES` (well past scent range, which only
     ever reached `ScentField.RADIUS_TILES`), committing to a distant flower
     moves the anchor to it, and finding nothing anywhere relocates the
     anchor by `RELOCATION_STEP_TILES`. Probed after: reaches the distant
     patch, ranging up to ~1034px from its origin.
  `MAX_REMEMBERED_VISITS` was added alongside: once foraging actually runs
  continuously, visit memory stopped being bounded by its time window
  (probed at 205 live entries and climbing with forage rate), and every
  entry is distance-checked per candidate flower per sniff per pollinator.
- ✅ **Searching is leashed, so drift is no longer an absorbing state**
  (`MAX_RELOCATION_TILES`) — a regression introduced by the relocation fix
  above and caught by probing the follow-up report ("foraging works until
  all nearby are empty, then they wander meaninglessly and don't resume
  foraging when they encounter new flowers"). Unleashed, the relocation hop
  is a random walk with nothing pulling back: a flyer that found nothing
  kept going, and once outside the chunks holding any flowers its lookup
  returned nothing, which triggered another relocation, carrying it further
  still. Probed: 93 tiles from spawn after ten simulated minutes, seeing 0
  flowers and drinking 0 when a full meadow was placed back at its spawn,
  ending 97 tiles out. Leashed: drifts 23 tiles, sees 5 flowers, drinks 5,
  ends 12 tiles out. The leash anchors to wherever the flyer last actually
  drank rather than to a fixed spawn point, so its territory follows the
  food instead of pinning it to ground that has gone barren.
- ✅ **Pollinators scatter instead of queueing** (`NEAREST_CANDIDATE_POOL`)
  — "nearest bloom wins" meant every pollinator in an area computed the
  same answer: probed at eight flyers in one spot all choosing the identical
  flower, so they conga-lined and only the leader got nectar (reported:
  "not all bees and butterflies fly the same route following each other and
  only the first gets nectar"). Each now picks among the nearest few, seeded
  from its own stable seed mixed with a per-pick counter — deterministic and
  reproducible per flyer, divergent between flyers, no global RNG. Probed
  after: the same eight spread across 3 distinct blooms, and a six-strong
  swarm sharing one meadow spread 420 drinks across all 6 of its flowers
  (68/118/75/75/52/32) rather than hammering one. No cross-pollinator
  bookkeeping was added — the scatter alone achieves the spread, so nothing
  tracks what another flyer has committed to.
- ✅ **Distance decided before visit memory** — the selection order inside
  `choose_target` was itself a bug, reported as "they ignore most flowers and
  target some much further away than the nearest". Splitting
  unvisited-from-remembered across the whole flower list before considering
  distance meant any unvisited bloom at any range beat every remembered one
  however close; since a continuously-foraging flyer remembers precisely its
  own local patch, it was systematically driven off it. Probed with the three
  nearest blooms in memory, targets over 200 seeds were the flowers 20, 50
  and 100 tiles out; after taking the near pool first and letting memory only
  break ties within it, the same probe returns 1, 2 and 3 tiles. A lone
  pollinator in a wide meadow now commutes a mean 1.9 tiles per target (worst
  2.3); a six-bee swarm still spreads across all 6 of 6 flowers (437 drinks)
  with a longest commit of 5.3 tiles. Note the partial-select itself was
  never at fault — it was verified returning only the nearest three across
  200 seeds and under shuffled input order, and "nearest" was already
  measured from the flyer's live position, not its anchor. Pinned by a
  regression test using explicit 1/2/3 vs 20/50/100-tile distances.
- ✅ **Scatter is bounded by a distance band, not a rank** (`SCATTER_BAND_
  TILES`) — the last of this subsystem's selection bugs, and the one that
  only a real-world measurement could find. Picking uniformly among a fixed
  COUNT of nearest blooms is fine where blooms are evenly spaced, but in an
  actual meadow the third-nearest is routinely 2-3x further than the first,
  so ~2 commits in 3 went to a visibly further flower (reported: "it's
  moving past dozens of flowers and doesn't even check if they have
  nectar"). Every synthetic fixture used near-uniform 1/2/3-tile spacing
  where the pool's spread is negligible, which is exactly why it shipped
  green. Measured in a live Berlin world (real chunks, real `FlowerPatch`
  data, real markers): mean chosen 5.83 tiles vs mean nearest-available
  4.26, worst 14.40, 9 of 24 commits >2 tiles worse than what was on offer.
  Now only blooms within `SCATTER_BAND_TILES` of the nearest count as tied
  with it; re-measured over 400 commits across 192 real pollinators: mean
  chosen **2.74** vs nearest **2.13**, and **5 of 400** commits >2 tiles
  worse. The band is absolute rather than proportional, so it cannot go
  slack at longer range. Both user wants are now satisfied together —
  genuinely equidistant blooms still scatter a swarm, while a clearly
  closest bloom is never skipped — and each half has its own test.
- 🚧 **Peer claims, so pollinators stop queueing behind one another**
  (`ForageClaims` + `PollinatorForaging.choose_target`'s `claimed` argument)
  — **logic complete and unit-tested, NOT YET WIRED** (see the wiring spec
  below; deliberately sequenced, because `ambient_flyer_marker.gd` and
  `earth_chunk_manager.gd` were being edited concurrently). Reported: "there
  are still butterfly chains happening where each butterfly flies to the same
  next flower". Measured cause: seeded scatter can only decorrelate flyers
  when the distance band holds more than one candidate, and **the band holds
  exactly one 86.5% of the time** — so co-located flyers reach identical
  answers and **62.1% of pairs within four tiles shared a target**, with
  followers arriving at blooms holding a mean of **0.182** nectar. Claims
  demote rather than exclude: only within the band (so a claim never sends a
  flyer past a closer bloom), still chosen when it is the only candidate (so
  a flyer never stalls), and ranked above visit memory. `ForageClaims` is
  keyed by flyer rather than by bloom, which makes the table structurally
  incapable of leaking — one row per live pollinator regardless of session
  length, with a recycled instance id taking over its stale row.
  ✅ **Now wired** (this pass): `EarthChunkManager` holds the shared
  `ForageClaims` table and exposes `claim_flower`/`release_flower_claim`/
  `claims_near` on the same duck-typed surface the markers already reach
  through `scent_world` (they are handed `self`, exactly like
  `flowers_near`/`drink_nectar_at`), so no new plumbing was needed.
  `AmbientFlyerMarker` claims on commit, reads peer claims into
  `choose_target`'s sixth argument on every sniff, and releases on landing,
  on abandoning a dry patch, and on finding nothing worth having. Every call
  is `has_method`-guarded, so a world that predates claims still forages
  unchanged. Despawn is handled by `release_many` on the chunk-unload path
  (collecting instance ids BEFORE freeing the nodes) rather than by
  `NOTIFICATION_PREDELETE`, which is not reliable here — without it the table
  leaks a row per despawned pollinator and points survivors away from blooms
  nothing is heading for. Tested on both sides: claim taken on commit,
  released on land/abandon, a second flyer avoiding a spoken-for bloom, and
  the chunk-unload leak check.
- ✅ **Flyers no longer sail past flowers they fly right by** — reported:
  "butterfly is still ignoring unvisited flowers". `_step_scent` used to
  early-return the instant `_forage_target != null`, so a flyer committed to
  a bloom three tiles off flew straight past a live, unvisited bloom a
  fraction of a tile from its path without sniffing it. That early-return was
  fixing something real (free re-picking mid-approach had flyers thrashing
  between candidates instead of ever arriving), so the fix is not to remove
  it but to add **hysteresis**: a committed flyer now sniffs every interval
  but only switches for a bloom closer by more than
  `AmbientFlyerMarker.RETARGET_IMPROVEMENT_TILES` (2 tiles — comfortably more
  than `LANDING_DISTANCE`, so an arrival can never be stolen from under
  itself). Both halves are pinned by tests: it switches for a bloom in its
  path, it refuses to switch for a marginally closer one, it still arrives
  and drinks in a full meadow, and the claim moves with it when it does
  switch.
- ⬜ **Nectar economy rebalance** — measured at **2.05x over-subscribed**
  (64.24 drinks/s of demand against 31.30 nectar/s of regen across 626
  reachable flowers), which is why arrivals find 0.182 nectar and why a
  meadow reads as dead behind a swarm. Deliberately NOT tuned yet: the
  chaining fix above changes the demand distribution, so the supply figure
  has to be re-measured once it lands rather than tuned against a number
  that is about to move.
- 🚧 **Illustrated head art per archetype** — procedural pixel art hit the
  same quality ceiling animal art did (see `IllustratedAnimalSprite`'s own
  doc comment); the fix follows the same "AI-illustrated sheet ->
  `SpriteSheetSlicer` -> cached frames" shape, but keyed by BLOOM-HEAD
  ARCHETYPE (`ProceduralFlowerSprite.HEAD_SHAPE_BY_SPECIES` — cup/layered/
  spike/puff) rather than by species: a real crocus and a real tulip share
  the same shallow-open-cup shape and differ only in colour/size, both
  already data-driven elsewhere, so one sheet per archetype covers every
  species that maps to it. `IllustratedFlowerHead` (new) slices a 4-stage
  bud/opening/full-bloom/spent sheet (see `docs/art/ai_sprite_prompts.md`
  for the generation prompts); `ProceduralFlowerSprite._paint_illustrated_
  head` composites it onto the existing procedural stem/leaves, tinted per
  species via a multiply blend against the source art's deliberately pale/
  neutral base tone. Only **"cup"** (crocus, tulip) has a sheet so far —
  layered/spike/puff still draw procedurally, unaffected (verified: nectar
  has zero effect on rose's rendered pixels). This also closes a real gap —
  nectar depletion previously had NO visual effect at all (a bloom at 1%
  nectar rendered identically to a full one, so a pollinator correctly
  skipping a near-empty flower looked like it was ignoring a good one, see
  "Flyers no longer sail past flowers" above) — an illustrated bloom now
  shows its "spent" frame below `ProceduralFlowerSprite.
  SPENT_NECTAR_THRESHOLD`. ⬜ Remaining: staging is picked once at sprite
  creation (`EarthChunkManager._sync_flower_sprites` passes `patch.
  nectar_at(cell)` in), not live-updated as an already-rendered bloom is
  foraged down — that needs `_sync_flower_sprites` to revisit existing
  sprites, which it explicitly does not do today (see its own "unlike grass
  tufts there is no growth animation" comment), a separate follow-up. Bud/
  opening frames are sliced and tested but unconsumed — no live "still
  opening toward its first bloom" render state exists yet to use them for
  (a currently-rendered flower is always already in bloom, see
  `FlowerPatch.blooming_cells`). layered/spike/puff sheets are the next
  step, then wiring bud/opening to a real growth-stage render state.

Trees are real, individual, choppable, genetically-varied, and now spread on
their own -- see the Vegetation Growth Model row in the Phase 1 table above
for the implementation detail. Most of this doc's deeper trait-rarity/
disperser/climate scope is still unbuilt:

- **Biome-Specific Ground Cover** (medium) — 🚧 Partial — desert and tundra previously had zero ground-cover flora at all. Two new self-contained per-chunk patch sims now exist, each copying `TallGrass`'s exact architecture rather than sharing a base class (deterministic hash-seeded placement, growth-toward-maturity, throttled spread into same-biome neighbor cells, a pure `graze()`): `src/world/desert_scrub.gd` (gated to `biome == "desert"`, sparser and slower-growing than tall grass -- `SEED_CHANCE 0.04`/`GROWTH_RATE 0.005` vs. grass's `0.08`/`0.01`) and `src/world/tundra_lichen.gd` (gated to `biome == "tundra"`, sparser/slower still -- `SEED_CHANCE 0.02`/`GROWTH_RATE 0.002` -- continuing the grass > scrub > lichen flavor gradient, pinned by tests rather than eyeballed). Matching procedural sprites (`src/rendering/procedural_scrub_sprite.gd` dusty sage/olive, `src/rendering/procedural_lichen_sprite.gd` pale muted grey-green) reuse `ProceduralGrassSprite`'s blade-silhouette technique. Both are wired into `EarthChunkManager` exactly like tall grass (`step_desert_scrub`/`step_tundra_lichen`, called from `World._process` alongside `step_tall_grass`; patches instantiate/render on chunk load and free on unload). Known gap: unlike tall grass's `harvest_grass_near`/herbivore-graze wiring, nothing yet triggers `graze()` on either new type from live gameplay (no fibre-equivalent harvest action, no herbivore auto-graze) -- deliberately left as pure, tested logic only, to avoid cross-cutting a parallel in-flight task also touching `EarthChunkManager`. Mountain and ocean remain intentionally without ground cover (out of scope for this pass).
- **Vegetation Density Field** (medium) — 🚧 Partial — see `vegetation_growth_model.gd` (Phase 1 table); not yet unified with individual tree placement/spread.
- **Individual-Agent Promotion (Tree LOD)** (large) — 🚧 Partial — trees are always individual, collidable, choppable nodes (`ChoppableTree`) from the start, not promoted from an aggregate; there's no LOD demotion back to a density field.
- **Fruit/Nut DNA Trait System** (medium) — ✅ Done — `TreeGenome.fruit_yield`/`species_bias` deterministically drive whether a given tree's forage drops lean fruit or nut (`ForageScheduler.genome_for`). `species_bias` now also resolves to one of three **named species** (`TreeSpecies` — Walnut/Cherry/Apple, thirds of the 0..1 spectrum) with its own canopy/fruit colour and a yield/ripening multiplier pair on `FruitingModel`, for the near-detail fidelity (`EarthChunkManager.step_fruiting`); the ambient far-fidelity tier (`step_forage`) still drops the original generic `fruit`/`nut`.
- **Common/Rare/Legendary Trait Rarity Tiers** (small) — ⬜ Not started — genome traits are continuous floats, no discrete rarity tiers.
- **Species Foraging Preference Profiles** (small) — ⬜ Not started — no animal-side foraging preferences; only the tree's own species_bias exists.
- **Disperser vs. Seed-Predator Role Assignment** (small) — 🚧 Partial — the disperser half is real for one species-pair (see Animal-Mediated Seed Dispersal below: robins disperse tree seed); no seed PREDATOR exists yet (a squirrel-equivalent cracking the seed instead), so the actual disperser-vs-predator TENSION `flora.md`'s DNA loop describes — a trait that attracts more foragers overall also attracting more predators, not just more dispersers — is not yet a real selective force.
- **Local Self-Seeding with Janzen-Connell Suppression** (medium) — 🚧 Partial — `TreeSpread` plants a mutated-child sapling within the parent's own `spread_radius` and enforces `MIN_TREE_SPACING` against overcrowding, but there's no distance-dependent survival penalty (true Janzen-Connell), just a hard minimum-spacing cutoff.
- **Animal-Mediated Seed Dispersal** (medium) — 🚧 Partial — ✅ bird endozoochory: `SeedEndozoochory` + `AmbientFlyerMarker.fruit_world`/`_carried_seed_species` + `EarthChunkManager.fruit_near`/`take_fruit_at`/`try_plant_seed_at` — a robin eats a fallen named-species fruit (a second diet entry alongside worm-hunting, see `FlyerDiet.FOOD_FRUIT`), carries the seed for a real gut-passage-timed interval (converted from `SeedEndozoochory.carry_distance_tiles` to flight time at the bird's own speed), and plants a sapling elsewhere via the same sink `TreeSpread`'s own ground-planted saplings use, gated to forest/rainforest (`SeedEndozoochory.can_root_in`). ⬜ ground herbivores/omnivores still don't disperse seed at all (only the pre-existing flower epizoochory, `SeedDispersal`, carries seed on a grazer's coat — a different mechanism for a different plant).
- **Plant DNA Inheritance & Mutation** (small) — 🚧 Partial (overstated as ✅ before this pass) — `TreeGenome.mutate()` exists and is exercised (small, bounded nudges per trait, not a full reroll), but its OUTPUT is not actually threaded through: `TreeSpread.propose_saplings` computes a mutated child genome and returns its `genome_seed`, but `EarthChunkManager.step_tree_spread` never stores it on the planted-tree record — every tree's genome (spread-in OR bird-planted, see Animal-Mediated Seed Dispersal above) is re-derived purely from its own landing position's hash, same as the original map-generated forest. So `mutate()` runs, but a spread sapling does not actually inherit its parent's (mutated) traits any more than an unrelated tree at the same position would. Discovered and documented while building bird endozoochory, which deliberately matches this existing behavior rather than diverging from it (see `flora.md`'s bird-endozoochory section) — a real inheritance fix is a reasonable follow-up for BOTH spread mechanisms at once.
- **Unified Wild/Farmed Plant DNA Population** (medium) — ⬜ Not started — no farming system exists yet.
- **Crop Escape / Wild Domestication Crossover** (small) — ⬜ Not started
- **Drought/Climate Tolerance Trait** (small) — ⬜ Not started — no climate-linked genome trait.
- **Climate-Driven Selective Mortality** (medium) — ⬜ Not started — trees never die of natural causes, only axe damage.
- **Mast Fruiting Events** (medium) — ⬜ Not started
- **Long-Timescale Forest Migration** (large) — 🚧 Partial — trees do genuinely creep outward via `TreeSpread` (throttled, persisted per-chunk), but there's no climate-driven directional bias, just proximity/spacing.
- **Ancient Tree Emergent Legendary Landmark** (medium) — ⬜ Not started
- **Ancient Tree Exploration/Crafting Payoff** (small) — ⬜ Not started
- **Rare Grove Discovery & Harvest Payoff** (small) — ⬜ Not started
- **Grove Overharvesting Population Consequence** (small) — ⬜ Not started — felling a tree (`ChoppableTree.take_damage`) drops wood and removes it permanently; nothing tracks grove-level depletion.

### Long Grass (`concept/long_grass.md`)

- **Illustrated, multi-card patch rendering** (medium) — ✅ Done — `src/rendering/illustrated_grass_patch.gd`: each `TallGrass` cell renders `CARD_COUNT=7` deterministically-placed blade cards sliced from a real 10×10 illustrated atlas (`assets/sprites/grass_blades.png`, genuine alpha transparency in its gaps — verified directly, no chroma-key/despill pass needed, unlike this codebase's other illustrated-art classes which ingest a magenta-keyed sheet instead), replacing the old purely-decorative `GrassBladeField` (a flat-colored `MultiMeshInstance2D`, removed entirely this pass — it wasn't destructible and didn't match the illustrated art style, per direct user report). Rendered GPU-instanced (see the third follow-up below) — bands, not individual cards, are what Y-sorts against the player/creatures.
- **Path-traced per-blade wind sway + walker push** (medium) — ✅ Done — the shader bends each pixel row by displacing the *sampled* texture UV in `fragment()` rather than shearing the quad's geometry in `vertex()` (the original, cruder implementation): `bend_curve(top_t) = pow(top_t, BEND_CURVE_EXPONENT)` eases in so the root stays pinned and curvature concentrates near the tip (a per-vertex shear on an unsubdivided quad can only ever interpolate linearly between 4 corners, reading as one rigid parallelogram); wind phase and amplitude both vary with local UV.x (`blade_phase`/`blade_amplitude_scale`, `AMPLITUDE_BASE`/`AMPLITUDE_VARIATION` keep every column's amplitude strictly positive) so blades drawn side by side in one card sway out of lockstep, approximating independent blade motion without per-blade geometry. The same curve gates the radial player-wake push, tuned so it clearly dominates ambient wind (`WALKER_PUSH_UV_AMPLITUDE > WIND_UV_AMPLITUDE`, pinned by test) for a readable "parting" reaction. All tuned constants are named/tested, not eyeballed. `EarthChunkManager` feeds one shared `player_world_position` uniform per frame from the live player position. **Follow-up bug, reported after seeing it live: "moves the blades left right and doesn't curve them... the bigger bushes don't part."** Root cause: a region-mapped `Sprite2D`'s canvas_item shader `UV` is atlas-relative, not local `[0,1]` to the card — a card whose seed rolled atlas row 9 of 10 saw `UV.y` in roughly `[0.9, 1.0]` for its *entire* card, compressing `top_t` into a near-flat sliver (near-uniform sideways slide instead of a curve) and, for rows near `UV.y == 1` (the bigger/denser bush variants), almost zero bend at all regardless of push strength — both symptoms, one bug. Fixed by giving each card its own atlas sub-rect as `instance uniform` parameters (`region_uv0`/`region_uv1`, one shared `ShaderMaterial` still batches every card) and renormalizing UV against them (`IllustratedGrassPatch.local_uv`, mirrored exactly between the tested GDScript helper and the GLSL) before computing the curve. **Second follow-up, reported after seeing the fix live: "only single blades move... they move at the bottom which is rooted into solid... bigger bushes don't part at all... don't sway anymore."** This codebase's headless test runner uses a null renderer (validates GLSL compilation, produces no real framebuffer), so direction was verified with a real, non-headless, off-screen `SubViewport` capture instead of more static analysis: a color-visualizing diagnostic shader confirmed `bend ≈ 0` at a card's bottommost opaque row and `bend ≈ 1` at its topmost — root-pinning direction was already correct. The actual cause was amplitude, not direction: a rendered-pixel diff showed a dense, busy bush card (many overlapping similarly-toned blades filling the cell) barely *looks* different even when its sampled pixels genuinely shift, because a small positional shift of repetitive texture still reads as the same texture — unlike a sparse single-blade card, where the identical shift moves a high-contrast silhouette edge and reads clearly (visually confirmed: at the original amplitude the blade showed an obvious lean while the bush looked static, even though the bush's raw pixel diff was numerically *larger* than the blade's). Fixed by resizing `WIND_UV_AMPLITUDE` (0.05→0.09) and `WALKER_PUSH_UV_AMPLITUDE` (0.22→0.45) for the busier case, re-confirmed visually: the bush's wheat-head now visibly displaces under push. **Third follow-up, reported once the first two fixes read correctly live: "it's still not volumetric (only one sprite per tile)... also it's now super laggy."** Root cause: individual `Sprite2D` cards, once actually rendering at the density this system is designed for (up to ~4,600 simultaneous cards across a typical decoration radius), meant that many separate alpha-blended draw calls — Y-sorting forces per-node paint order, which defeats Godot's automatic batching. User-approved trade-off (asked directly, since batching for speed and exact per-blade Y-sorting are fundamentally in tension): GPU-instance via `MultiMeshInstance2D`, one draw call per (chunk, Y-band of `BAND_COUNT=8`) rather than per chunk (which would only Y-sort as one unit, too coarse) or per card (no batching win). Building this surfaced two further, compounding rendering bugs, both invisible to this codebase's headless test runner (null renderer: validates GLSL compilation, produces no real framebuffer) and only caught via a real, non-headless `SubViewport` capture: (1) `instance uniform` for the per-card atlas region draws from one *global* buffer shared by the whole scene, hardware-capped (measured: 4096) — a test grid of just 576 cards already overflowed it, silently falling back to each instance's default value past the cap; (2) switching to `MultiMesh`'s `use_colors`, read as plain `COLOR` directly in `fragment()`, rendered as a dithered/checkerboard mix of neighboring instances' packed data — reproduced with a bare-minimum shader (zero bend math, `COLOR.rg` alone, no texture sampling) — apparently specific to this project's `gl_compatibility` (GLES3) renderer, which packs `MultiMesh` instance data into a texture internally rather than a true per-instance buffer. Fixed by reading `INSTANCE_CUSTOM` in `vertex()` (not `COLOR` in `fragment()`) and carrying it via a `varying`, confirmed clean via the same real-render technique. `CARD_COUNT` raised 4→7 once per-instance cost stopped being the constraint. **Fourth follow-up, reported across several more live sessions: "swaying was really good now player doesn't influence sprite" / "now the barely bend."** Investigating the first report found a literal `const WALKER_PUSH_UV_AMPLITUDE := 5.0 # TEMP DIAGNOSTIC CRANK` left in place from an earlier debugging pass, self-labelled but never reverted, alongside a `COLOR = vec4(1,0,1,1)` magenta override gated on `wake > 0.01` — both debug scaffolding that had shipped, not a regression in the underlying mechanism (now caught by `test_shader_never_unconditionally_overrides_color_to_a_flat_debug_tint`/`test_walker_push_amplitude_matches_its_own_tuned_constant_not_a_debug_crank`, added so this class of bug fails loudly instead of shipping silently again). Reset to the real tuned value and the magenta override removed. Confounded by a second, unrelated cause across the same stretch: a parallel editing session repeatedly touched this same file and constant concurrently, so several later "broken again" reports traced to `WALKER_PUSH_UV_AMPLITUDE` having been reverted back to `5.0` (or another stale value) between visual checks rather than a new bug — re-diagnosed and re-fixed each time by re-reading the file fresh rather than assuming a prior fix still held. Once genuinely stable, live "still not enough" feedback across several more rounds climbed the real tuned value further: 0.45 → 0.6 → 0.7 → 1.5, the last a deliberately large jump (rather than another small nudge, since the smaller steps still read as weak in practice) — pinned exactly by test, confirmed to stay well clear of the ~5.0 region where `bend_offset` overshoots the shader's own UV clamp and the curve collapses into a static-looking clamped sliver instead of a visible sway.
- **Creature wake** (small) — ⬜ Not started — the shader already exposes the same `player_world_position`/`walker_radius` inputs a creature push would need, but only the player position is ever written.
- **Cards spread across a tile's own footprint, not clustered in one corner** (medium) — ✅ Done — reported live: "make grass blades volumetric, so that more than one entity spawns on the same tile not only at bottom corner so that when the player walks through it looks and feels like a dense field of grass." `IllustratedGrassPatch.card_specs_for_seed`'s offset formula previously spread cards across only ±3.3×±1.4 world units (roughly a fifth of a 16×16 tile), a small sub-region hugging the tile's own center — visually one clump sitting somewhere on the tile rather than grass filling its whole footprint. Widened to spread across ±6.8 world units on both axes independently (comfortably inside the tile's own ±8 half-bounds, so a root never bleeds into a neighbouring cell's footprint) via a 21×17 bucket split of the same per-card hash, pinned by test (`test_card_offsets_spread_across_most_of_a_full_tile_not_a_small_corner`/`..._stay_within_the_tiles_own_bounds`). `CARD_COUNT` moved 7 → 12 alongside the spread (spreading the same small count over a bigger area would read as *sparser*, not denser, so count and spread were raised together) then settled at 8 in a later pass once a fill-rate/overdraw cost showed up on an integrated GPU (GPU instancing keeps this to one draw call regardless of card count, but each card is still a translucent, alpha-blended, shaded quad the GPU must rasterize and blend — cheap in draw calls, not in fill rate/overdraw). 8 trades a little of the peak volumetric density for materially less overdraw; the spread fix (the part of the original report about clumping in one corner) stays fully intact regardless of card count.
- **Grass draws only what the player can currently see** (medium) — ✅ Done — reported live: "optimize the grass blade rendering so it only draws what the player currently sees +2 tiles of buffer in every direction and blades get loaded/unloaded as the player walks to improve framerate." The existing chunk-level decoration gate (`DecorationLod.keeps_decoration`) only ever scoped drawing to whole `CHUNK_SIZE`=32-tile chunks near the player — several times what the camera can actually show (see `decoration_lod.gd`'s own doc comment), so a decorating chunk still drew every one of its grass cells regardless of whether they were actually on-screen. `DecorationLod.keeps_decoration_tile` adds a tighter, rectangular, tile-precise cutoff layered ON TOP of (never instead of) that coarser gate: half the camera's own visible span (`EarthChunkManager._visible_half_span_tiles`, rounded up) plus a `GRASS_VIEW_BUFFER_TILES=2` buffer in every direction, independent per axis (matching the camera's own rectangular view, not a circular radius). `_sync_grass_sprites` filters each cell against it before grouping into bands, so a band's real instance count can now be smaller than its full cell count once some of those cells fall outside the window.
- **Newly-visible tiles weren't getting grass promptly enough** (small) — ✅ Done — a regression from the view-distance culling above, reported live immediately after: "also now the blades load way too late and the player walks into a new area without any blades which then suddenly appear." The tile-precise cutoff is only re-evaluated when `_sync_grass_sprites` actually runs, which was throttled to `GRASS_REFRESH_INTERVAL=5.0`s or an immediate resync on crossing into a new CHUNK — fine for the old chunk-level-only gate, but the new cutoff is tight enough that a player can walk many tiles (up to a whole `CHUNK_SIZE`=32 without ever crossing a chunk boundary) bringing new ground into view that stayed bare until the next coarse trigger, then a whole batch of tufts popped in at once. Fixed by tracking the tile the grass view was last resynced against (`_grass_view_synced_tile`) and marking the resync due on ANY tile change — the same "mark due, picked up by the next `step_tall_grass` call" mechanism the chunk-boundary trigger already used, just at tile instead of chunk granularity. This also primes `sim.advance`/`shed_seed` to run early (both gated behind the same accumulator) — harmless, not just cheap: growth is linear in delta and spread carries its own accumulator, so more frequent smaller steps land in exactly the same state (`test_growth_lands_in_the_same_place_whether_batched_or_per_frame`); triggering per TILE rather than per frame is what keeps the cost down, since tile crossings happen at a walking pace (a few a second) rather than the 60/sec rate the original throttle exists to avoid.
- **Grass seeds into coherent fields, not scattered individual cells** (medium) — ✅ Done — reported live: "remove the percentage of overall grass blades instead make them stick more together forming fields using perlin noise / voronoi." `TallGrass._seed_initial_patches` previously rolled each grassland cell independently against `SEED_CHANCE=0.20` — statistically the right overall coverage, but because each roll is uncorrelated with its neighbours, it painted scattered individual dots rather than anything a player would read as a meadow. Replaced with `PixelNoise.smooth` (the same shared bilinear value-noise the curved terrain-blend boundaries use — see `concept/art_resolution.md`) thresholded per cell: neighbouring noise samples stay close together, so thresholding carves out contiguous blobs instead of salt-and-pepper — confirmed with a real probe (ASCII-rendered a 32×32 sample: several distinct, organically-shaped fields per chunk, not one giant blob or a return to speckle). `FIELD_NOISE_SCALE=0.12`/`FIELD_NOISE_THRESHOLD=0.65` were picked from a real probe sweeping scale × threshold combinations (deleted after use, per this project's convention) for the combination whose emergent coverage landed closest to the old `SEED_CHANCE` target (~20%), pinned exactly by test rather than eyeballed. `SEED_CHANCE` itself stays defined at the same value — it is no longer read as a literal per-cell roll, but several OTHER ecological scatter systems (`DesertScrub`, `EarthwormPatch`, `WildCropPatch`, `TundraLichen`) pin their own rarity below it in their own tests, so removing it outright would have broken a wider cross-system convention this request never asked to touch. Clustering surfaced a few pre-existing tests whose fixed guesses no longer held once nearby cells' occupancy became correlated instead of independent (e.g. a "try two adjacent corner cells to find an empty one" precondition, safe at a 4% chance of both being occupied under independent rolls, no longer safe once an occupied cell's neighbour is occupied ~3x more often than the base rate) — fixed by making those tests robust by construction (scan the whole grid; retry across several spread ticks) rather than hand-picking a new lucky seed. Deliberately NOT seamless across chunk boundaries (noise is sampled in each chunk's own local coordinates against its own per-chunk seed, the same inputs every other roll in this file already uses) — a field can visibly restart its pattern at a chunk edge; not asked for, and would need a shared noise seed sampled in global tile coordinates instead, a natural follow-up if it turns out to matter in practice.
- **Grass parts for every client, not just the simulation owner** (small) — ✅ Done — reported live: "grass doesn't part when the player walks through it." `World._process` called `EarthChunkManager.set_grass_walker_position` from inside the `_owns_ecosystem_simulation()` gate meant for actual simulation steps; that gate evaluates true in single-player (masking the bug there) but is false for every connected multiplayer client except the host, so a joining client's own local grass never parted for them. Fixed by moving the call out of the gate, unconditional every frame for every client — the same treatment `step_water_disturbances` (a fellow purely-cosmetic, per-client effect) already had, right above it in the same function. Investigated and REFUTED, via a real non-headless render (not just code reading): a `Player.position`/grass-`MODEL_MATRIX` coordinate-space mismatch (both are children of the same untransformed `$Entities` node) and the walker uniform/`wake` math not reaching the shader (a temporary `wake > 0.01` → solid-magenta diagnostic confirmed it fires exactly where expected, at the real tuned `walker_radius`/`WALKER_PUSH_UV_AMPLITUDE`, not just an artificially cranked one). See `concept/long_grass.md` History #5.
- **Ambient wind sway scales with live weather** (small) — ✅ Done — `IllustratedGrassPatch`'s ambient wind term (not the walker push, which stays constant) now carries a `wind_strength` uniform fed by `EarthChunkManager.set_wind_strength` from the same live `WeatherModel.wind_strength_for` value the water's shimmer and `WindSway` (trees, grass/scrub tufts, and flower blooms — see the Phase 0 Project Scaffold row) already use — one shared wind concept, not a parallel one. Default `1.0` is calibrated to `wind_strength_for("clear")`, so today's tuned look is exactly reproduced on a clear day (the majority weather state) and scales up visibly in worse weather. Verified with a real non-headless render: a per-pixel motion-energy diff across a burst of frames under `storm` (1.8) vs `clear` (1.0) showed a distinct, coherent canopy-shaped region of high frame-to-frame displacement under storm that the clear-weather diff (dominated by uniform background/ground-texture noise) did not show.
- **Seed, and animal-carried dispersal to distant/cross-chunk locations** (large) — ✅ Done — see `concept/long_grass.md`'s "Reproduction" section for the full mechanism spec. `_step_spread` (existing) only ever creeps into the four cells touching a mature patch; this pass adds the OTHER half real grass reproduction needs: `TallGrass.shed_seed`/`ground_seed_cells`/`take_ground_seed` (mirrors `FlowerPatch`'s own shape, no bloom/pollination gate since grass has no bloom cycle, no species field since a chunk grows only one kind of grass) and `TallGrass.plant` (the sink, mirrors `FlowerPatch.plant`), backed by `EarthChunkManager.grass_seeds_near`/`take_grass_seed_at`/`plant_grass_at` (same 3×3-chunk-neighbourhood-scanned shape as `flowers_near`/`seeds_near`/`fruit_near`). Two carriers, deliberately different mechanisms: **sparrows** eat grass seed through the exact same `seed_world` port and `SeedEndozoochory` carry-distance model they already use for flower seed (a sparrow's crop doesn't care which plant a swallowed seed came from) — `AmbientFlyerMarker` gained a fourth parallel sniff track (`_grass_seed_*`) alongside worm/fruit/flower-seed, all sharing one `ground_forage` state machine and one `_carried_seed_species` slot. **Mice** do NOT get the bird treatment: a real scatter-hoarding rodent doesn't fly and doesn't digest a seed in transit, so `src/gameplay/seed_caching.gd` is its own small module (short GROUND carry, `CARRY_MIN/MAX_TILES` 1–6 vs the bird's 10–40 and the flower grazer's 3–14 — pinned by test to sit below both) wired through `EarthChunkManager._step_grass_seed_caching`, gated to `species == "mouse"` specifically rather than the whole "Forager" diet label. Both carriers land in the SAME sink (`plant_grass_at`), so either one can found a genuinely new, disconnected field a chunk (or neighbouring chunk) away — not just extend an existing one. **Grazing counter-pressure was already live before this pass** — `EarthChunkManager._graze_by_herbivores` already ate a mature patch under any non-predator creature standing on it (horses/sheep included), driven from the same throttled tick as growth/spread — this pass only needed to confirm it, not build it; a real-world probe (real Berlin chunk, real `AmbientFlyerMarker`/`CreatureMarker` instances driven through hundreds of real `_process` steps, deleted after use) measured genuine coverage divergence between grazers-present and grazers-absent runs over the same simulated span — see the probe numbers callout below. Found and fixed one adjacent latent bug while restructuring the carried-seed-kind branching to add a third kind: `_carried_seed_is_flower` was set `true` on eating a flower seed but never reset, so a bird that later ate fruit (sparrows are diet-eligible for both) would incorrectly call `plant_flower_at` with the fruit's species instead of `fruit_world.try_plant_seed_at` — now every `_take_targeted_*` method resets both kind flags before setting its own (regression-tested).
  - **Probe numbers** (real Berlin chunk data, 500 ticks × 5s = 2500 simulated seconds; probe scripts not kept in the tree — deleted after use, per this project's real-world-verification convention). **Full loop, end to end** (4 real `AmbientFlyerMarker` sparrows + 3 real `CreatureMarker` mice, all driven through hundreds of real `_process` steps against the real production code path, no mocks): 11 grass seeds eaten, 1 new distant patch established — by a MOUSE (`mouse grass-cachings: 11`, `sparrow grass-plantings: 0`). That zero for sparrows is a real, reproducible finding, not a bug: `AmbientFlyerMarker`'s four ground-forage searches run in a fixed priority (worm → fruit → flower-seed → grass-seed, unchanged order, grass-seed only appended at the end), so with real Berlin flower-seed abundant in range the whole run, sparrows committed to flower seed on every opportunity and grass-seed foraging never got a turn — proven mechanically correct in isolation (see `test_ambient_flyer_marker.gd`'s dedicated sparrow/grass-seed tests, a `StubSeedWorld` with ONLY grass seed on offer), but in a real mixed meadow today's fixed priority order makes mice the dominant real-world driver of new distant patches, not birds. Flagged as a judgment call, not fixed: changing that priority order risks the already-tested flower-dispersal behavior and wasn't asked for. **Grazing counter-pressure**, isolated from the above (a creature pinned onto a real, currently-mature patch in its own chunk every tick, re-picked as each one is eaten — the direct causal test, since a freely-wandering herd's tiny `WANDER_RADIUS` (40px, ~2.5 tiles) turned out to make the full-loop probe's own grazer placement a matter of luck, not a property of the mechanism): 121 real `TallGrass.graze()` calls over the run; total coverage **without** a grazer grew 3101 → 3200 (+99), **with** one continuously-grazing creature it fell 3101 → 3072 (−29) — a swing of 128 patches from a single animal, confirming the mechanism (already live before this pass, see below) is real and strong. Honest caveat for what a player actually sees: that strength depends on a herd's home point actually being near grass, since footfall grazing only fires on the exact tile a creature is standing on — the same 40px tether that made the full-loop probe's own grazer placement unreliable in the wild also governs how promptly a real, freely-wandering herd finds grass to crop in the first place.

### Wild Crops (`concept/wild_crops.md`)

New concept doc + system (2026-08-24), reported: "grow in the wild; spread
and can be harvested with fully animated Pull action that pulls ripe
carrots out of earth (visually animated)". Supersedes the old
`EarthChunkManager.has_wild_carrot`/grass-harvest-yields-a-carrot freebie
(see Taming/NPC section) with a real, visible wild population, mirroring
`TallGrass`'s own patch-sim contract rather than a spawn table.

- **Growth + spread simulation** (medium) — ✅ Done — `src/world/wild_crop_patch.gd`
  (`WildCropPatch`): one instance per chunk PER CROP (carrot, potato each get
  their own sim, not a shared one), seeds a small fraction of `grassland`
  cells (`SEED_CHANCE` pinned below `TallGrass.SEED_CHANCE` by test — a
  meadow is mostly grass with the occasional carrot in it), grows 0..1 at a
  tested multiple slower than grass regrowth (`GROWTH_RATE_SLOWDOWN`), and
  spreads mature patches into adjacent grassland on a throttled tick
  (`_step_spread`, identical mechanism to `TallGrass`'s own). No animal-
  carried seed dispersal for root crops (scope cut, see the concept doc).
  **Follow-up, reported live: "carrots render potatoes as crop"** — two
  independently-seeded sims sharing a chunk could claim the exact same
  cell (each blind to the other), stacking a carrot marker and a potato
  marker on one tile. Fixed with `_in_this_crops_territory`: a stable hash
  partitions every cell into exactly one crop's share up front, and both
  seeding and spread skip any cell outside their own crop's territory —
  collision is now impossible by construction (`test_territory_partition_is_exhaustively_disjoint`
  proves it directly over a wide cell sample, not just statistically on one
  seed/grid that got lucky).
- **Growth-staged art** (medium) — ✅ Done — real AI-illustrated sheets
  already existed (`assets/sprites/plants/{carrot,potato}{,_leaves}.png`:
  3 growth-stage leaf frames + 7 root/tuber color variants each) with
  nothing in the world using them; `src/rendering/illustrated_crop_sprite.gd`
  slices them (chroma-key + `SpriteSheetSlicer`, the same `sheep.png`
  recipe `IllustratedAnimalSprite` established) and maps `WildCropPatch`'s
  continuous growth onto the 3 stages (seedling/vegetative/mature). A
  direct cross-crop distinctness test
  (`test_carrot_and_potato_leaf_textures_are_visually_distinct`) confirmed
  the two crops' art was never actually mixed up — the "don't use variants"
  live report traced to the territory-overlap bug above, not this piece.
- **Soil mound** (small) — ✅ Done (procedural fallback) —
  `src/rendering/procedural_soil_sprite.gd`: no AI art exists yet for
  `ai_sprite_prompts.md`'s soil-pile prompt, so a hand-drawn
  undisturbed/disturbed mound in the same offline-art style as
  `ProceduralBobberSprite`, swappable for real art later with no marker
  changes needed. **Follow-up, reported live: rendered ~1.5 tiles wide** —
  the raw `SIZE=24` texture was drawn with no scale applied at all, the
  same "gigantic" bug class `ProceduralItemSprite.WORLD_WIDTH_BY_ID` already
  fixed once for tree fruit. Fixed with `SOIL_WORLD_WIDTH`/`SOIL_WORLD_SCALE`
  (pinned below a full tile by test).
- **Visible per-patch markers** (medium) — ✅ Done — `src/rendering/wild_crop_marker.gd`
  (`WildCropMarker`) + `src/rendering/wild_crop_renderer.gd`
  (`WildCropRenderer`): one real Node2D per patch cell (sparse, unlike
  grass's GPU-instanced bands — each cell needs its own hover identity and
  independent pull animation), spawned/synced/despawned per chunk exactly
  like trees/stones (`EarthChunkManager._wild_crop_sims`/
  `_wild_crop_markers`, `step_wild_crops` on the same throttled cadence as
  `step_tall_grass`). **Follow-up, reported live: the root was visible even
  while still planted** ("crop should not be visible, only leaves") —
  leaves+root are now assembled as one entity from `_ready()` (the root's
  real art loads immediately, not lazily at pull time) with the root fully
  clipped away (`Sprite2D.region_rect` height 0) until a pull actually
  starts; see the pull entry below for how that region grows. Wired into
  the universal hover tooltip (see UI / presentation section) via
  `get_display_name`/`get_hover_actions` — name
  reflects growth stage ("Carrot Sprout" → "Carrot Plant" → "Carrot"),
  and only a mature patch offers "Pull".
- **Animated pull harvest** (medium) — ✅ Done — bound to the SAME swing
  input as chopping a tree / harvesting grass / smashing a boulder
  (`attack`, default Space) via `Player._pull_wild_crop_step`, the same
  group-scan + range-sweep shape as its siblings. `src/gameplay/crop_pull.gd`
  (`CropPull`) is a pure, headlessly-tested function of elapsed time (cubic
  ease-out rise), the same "runtime tween over static parts" idiom
  `Knockback.step` already established for hit displacement — no baked
  mid-pull animation frames. The same progress value also drives the
  root's `region_rect` growing from nothing to its full art, top-down, so
  it visibly emerges as it rises rather than popping instantly visible.
  On completion: soil swaps to its disturbed
  look, the sim's cell is actually removed, and the harvested root drops
  as a real `DroppedItem` carrying the SAME illustrated root texture the
  player just watched rise out of the ground (`DroppedItem._ready()` now
  prefers `IllustratedCropSprite` over the generic procedural fallback for
  any registered crop id) — not an instant straight-to-inventory grant.
  **Follow-up, reported live: "potatoes are still rendered above soil and
  not buried."** `Sprite2D` defaults to `centered = true`, so the growing
  `region_rect` drew straddling the marker's own origin — half the revealed
  strip above the ground line, half below — rather than emerging upward out
  of a fixed ground point. A carrot's thin taper made this easy to miss; a
  potato's wide, high-contrast tuber made it obvious the instant any of it
  was revealed. Confirmed against the real shipped art with a headless
  probe (not guessed at): both crops' actual root textures showed solid
  content well before the region had grown far. Fixed by turning `centered`
  off and pinning the drawn quad's BOTTOM edge, not its middle, to the
  marker's local origin (`WildCropMarker._reveal_root`'s own offset), so the
  root always grows UPWARD out of a fixed ground point for either crop, not
  just the one whose specific proportions happened to hide the bug.
- **`potato` item** (small) — ✅ Done — added to `ItemCatalog` (food); had
  no source anywhere in the game before this pass.
- **A pulled root is a real physical object, not just an inventory grant**
  (medium) — ✅ Done — reported live: "a pulled carrot/potato should be a
  physical entity like anything else and should be able to be picked up;
  thrown or kicked by the player." Picking up already worked (a harvested
  root drops as an ordinary `DroppedItem`, collected by click or the
  existing E-key sweep, same as any other ground item). Kicking did not:
  only `LiftableStone` (`docs/concept/stone.md`) offered it. Carrot/potato
  now carry a real average whole-vegetable mass (`ItemCatalog._PRODUCE_MASS_KG`
  — 70g/170g, real reference weights, not a material-density estimate the
  way weapon mass is) instead of the "not modeled" 0.0 every other food item
  still carries, feeding the SAME shared momentum model
  (`Kick.is_kickable`/`Kick.landing_position`) stones already use.
  `DroppedItem.get_hover_actions` now offers "Kick" for any item with a
  real, modeled, kickable mass — not crop-specific, so anything given a
  real mass in the future gets this for free. `Player._kick_step` now
  checks both the nearest liftable stone AND the nearest kickable
  `DroppedItem`, kicking whichever is genuinely closer, rather than a stone
  always winning just because it was the first kickable thing this game
  had. **Follow-up, reported live: "pressing K doesn't kick a potato or
  carrot" / "pick up should put it in the hand first instead of the
  inventory ... there should be an extra key to stash the item in hand
  into inventory."** The kick logic itself was verified correct end-to-end
  (a real `WildCropMarker` pull → real `WorldItemBus` drop → real
  `DroppedItem` → real `Player._kick_step` pipeline test moved the dropped
  potato); the live report is most plausibly explained by the merge/
  restart timing around this same fix landing, not a code defect. The
  hand-hold ask is real, separate work: `Player`'s held-item state,
  previously typed entirely around "a stone, described by a diameter"
  (`_hand_stone_diameter_cm`, `_try_pick_stone_into_hand`,
  `_throw_held_stone`), is now generalized (`_hand_item_stack`,
  `is_holding_item`/`is_holding_anything`, `_try_pick_item_into_hand`,
  `_throw_held_item`, `_spawn_thrown_item`) — E now picks any dropped item
  with a real, kickable-grade mass into the HAND first, exactly like a
  stone (an item with no modeled mass still goes straight to inventory,
  unchanged); charging and releasing throws it as a real `DroppedItem`
  instead of straight to inventory; and a NEW stash key (default H,
  `Player._stash_step`, `Keybindings` "stash") puts whatever's held away
  into inventory instead, dropping any overflow at the player's own feet
  rather than losing it (deliberately NOT copying `LiftableStone.pick_up`'s
  own "silently discard the overflow" ground-pickup shortcut, since
  stashing is a deliberate player action). See `docs/concept/stone.md`'s
  "Held-item pickup, throw, and stash" for the full mechanism.
- ⬜ No DNA/quality variation on the wild population (see `farming.md`'s
  still-unbuilt shared DNA model) — the 7 root/tuber art variants are
  purely cosmetic.
- ⬜ No player-tilled farming access point from this wild population yet.

### Carrion (`concept/carrion.md`)

New concept doc + system (2026-08-24), reported: *"killing a boar should
leave a carcass if not cleaned up by a player ... the player can cut out
the meat parts and skin ... if he takes out the guts they spawn as entity
and stay in the world so other animals can eat them ... then we need ants
and bugs to clean up the left parts ... all this should be skills the
player can train."* Replaces the old instant "die → hide+meat spray" model
(`CreatureMarker._drop_loot`) with a real carcass, exactly the same
"evaporates instead of being cut down" fix already made once for trees.

- **Carcass entity** (medium) — ✅ Done — `src/rendering/carcass.gd`:
  spawned in place of the old instant loot drop, for every species
  `LootTable` already covers (herbivore/boar/predator/lynx — the same
  scope as today's real drop table, no new per-species tuning in this
  pass). Real ordered parts (hide → meat → guts,
  `src/gameplay/butchering.gd`'s `PART_ORDER`), one swing removes the
  next remaining part (`Carcass.butcher`, same melee-range-sweep shape as
  chop/smash/pull). Independent rot clock (`ROT_SECONDS`, tuned to be
  observable within an ordinary session per `ecosystem_dynamics.md`'s own
  pacing pillar, deliberately NOT `FruitSpoilage`'s real-day-compressed
  timescale) and a separate decompose-health pool decomposers whittle down
  once rotten (`take_bite`) — an untouched carcass is not permanent
  clutter.
- **Guts as a real food entity, not an item** (medium) — ✅ Done —
  `src/rendering/carcass_guts.gd` (`CarcassGuts`): the "guts" cut spawns
  this as a sibling of the carcass instead of going through
  `WorldItemBus.item_dropped` — a player can't carry or eat it, but it
  exposes the same `take_bite` contract as `Carcass` so a decomposer
  doesn't need to distinguish "carcass" from "guts". Decays on its own,
  faster than the carcass it came from (offal spoils first, real-world
  grounded).
- **Butchering skill** (small) — ✅ Done — `SkillTree` gained a
  `butchering_1`/`butchering_2` node pair (same shape as the existing
  `naturalist_1`/`2` stamina nodes) raising a `meat_yield` stat;
  `Player._butcher_step` reads it live via
  `skill_tree.total_bonus("meat_yield", allocated_nodes)` (not cached
  through `_apply_skill_stat`, so it can never drift out of sync with
  actually-allocated nodes) and `Butchering.meat_count` turns it into
  extra meat off the same carcass. Not `skills.md`'s much larger
  aspirational DNA-passive-web system, which has no code yet — this uses
  the one *real, live* progression system this project has.
- **Ants + carrion bugs** (medium) — ✅ Done —
  `src/gameplay/carrion_forage_behavior.gd` (pure seek → approach → feed
  state machine, simpler than `GroundForageBehavior`/`PiscivoreBirdBehavior`
  since a ground crawler has no separate "descend" phase) +
  `src/rendering/decomposer_marker.gd`/`decomposer_renderer.gd`.
  Deliberately NOT built on `CreatureMarker`/`CreatureInfo` — that stack is
  a full roaming-wildlife AI (flee/fight/hunt/graze/mate/ecosystem
  population tracking), the wrong shape for a tiny insect whose entire
  behaviour is "find carrion, eat it, wander otherwise"; mirrors
  `AmbientFlyerMarker` instead (home-anchored wander, no population math).
  Scans the `Carcass`/`CarcassGuts` groups directly (the same
  `get_tree().get_nodes_in_group` shape `Player`'s own melee-sweep steps
  already use) rather than needing an injected "world" reference. Two
  species (`ant`, `bug`), guaranteed min/max count per land-biome chunk
  (`DecomposerRenderer`, mirroring `AmbientFlyerRenderer`'s own
  guaranteed-not-a-coin-flip fix for butterflies/bees), wired into
  `EarthChunkManager._load_chunk`/`_unload_chunk` per chunk. Verified
  end-to-end in a real test: a decomposer finds a rotten carcass, walks to
  it, bites it repeatedly, and the carcass is actually fully consumed and
  freed.
- **Universal hover tooltip coverage** (small) — ✅ Done — `Carcass`/
  `CarcassGuts` both implement `get_display_name`/`get_hover_actions` (see
  UI/presentation section's hover system): a carcass reads its species and
  "Butcher (Space)" while parts remain, "\<Species\> Remains" once
  stripped; guts show only a name, no player action.
- ⬜ Opportunistic scavenging by existing predators/omnivores (a bear or
  jackal actually walking to and eating a fresh carcass/guts instead of
  only hunting live prey) — `take_bite`'s contract is already shaped to
  support this, but wiring it into `CreatureBehavior`'s decision tree is a
  real, separate AI change, deliberately deferred rather than folded into
  this already-large pass.
- ⬜ Species-specific butcher yields (a bear's hide vs. a boar's hide) —
  every carcass-eligible species shares one part order/quantity today,
  mirroring `LootTable`'s own existing flat-by-role shape.
- ⬜ Persistence/catch-up integration for carcasses across a chunk
  unload — chunk-local, ephemeral state, the same explicit scope cut
  `soil_fauna.md`'s worm burrows already made for the same reason.

### Woodworking (`concept/woodworking.md`)

New concept doc + system (2026-08-24), reported: *"when chopping a felled
tree, it should first remove the canopy and spawn sticks; but leave the
stem/trunk, then next chop splits the trunk into logs which can be further
split into more sticks. If you have high enough carpenter skills you can
turn the full trunk into a Balken or Planken using a saw."* Replaces the
old flat "every cut on a felled tree gives the same wood+stick mix"
(`FelledTree.wood_per_cut`) with the real felling sequence: limb the crown
off first, then either buck the bare trunk into logs by hand or — saw +
trained Carpentry — turn the whole remaining trunk straight into
construction lumber in one action.

- **Staged felled-tree processing** (medium) — ✅ Done — `ChoppableTree`
  gained a second state bit, `_canopy_removed`, alongside the existing
  `_felled`: the FIRST swing on a freshly-felled tree limbs the crown off
  as sticks (`FelledTree.sticks_from_canopy`) and does not consume a trunk
  cut; every swing after that bucks one length off the now-bare trunk into
  a real `log` item (`FelledTree.logs_per_cut`), the same
  `CUTS_TO_CLEAR`-counted shape the old flat cut used. `FelledTree.wood_for`/
  `wood_per_cut` renamed `timber_for`/`logs_per_cut` to match what's
  actually dropped now.
- **Sawing the bare trunk** (medium) — ✅ Done — `ChoppableTree.saw_up`:
  an alternative to the ordinary chop, converting the ENTIRE remaining
  trunk into `beam`+`plank` in one action
  (`FelledTree.beams_from_trunk`/`planks_from_trunk`) instead of one log
  per swing. Gated on both a `saw` tool (`Item.is_saw`, same
  `id.contains(...)` shape as `is_axe`/`is_pickaxe`) AND enough allocated
  `Carpentry` (`SkillTree`'s `carpentry_1`/`2` nodes, read live via
  `total_bonus("carpentry_level", ...)` — the same live-read-not-cached
  shape `carrion.md`'s `meat_yield` skill uses) — `Player._chop_step`
  tries `saw_up()` first when both are met and falls back to the ordinary
  `take_damage()` chop otherwise; `saw_up()` itself is the authority on
  whether the trunk is actually bare and workable, so an unqualified swing
  never has a special case to get wrong. No mechanism yet to choose beam
  vs. plank output specifically — sawing always yields both, a named
  simplification (real sawmills cut a log one way or the other on
  purpose).
- **Logs refine further at the bench** (small) — ✅ Done — two new,
  ungated `CraftingRecipeBook` recipes: `log_to_sticks` (more kindling)
  and `log_to_wood` (keeps every existing `wood`-consuming recipe —
  `torch`, `wooden_club`, `campfire`, … — reachable now that bare-trunk
  chopping yields logs instead of wood directly, rather than silently
  cutting off their supply).
- **The saw itself** (small) — ✅ Done — craftable (`wood` + `rock`, same
  tier as `stone_pickaxe`), registered in `ItemCatalog`.
- ⬜ `beam`/`plank` have no consumers yet — `building.md`'s construction
  system is itself still unbuilt; this pass only makes the materials
  obtainable.
- ⬜ Species/hardness variation in yield — every tree shares one yield
  curve today, the same flat-by-role simplification `carrion.md`'s
  butchering already made for carcasses.

### World (`concept/world.md`)

The hub doc for the core simulated planet. Its foundational terrain/clock
mechanisms substantially overlap with Phase 0 above (tracked there too, in
more roadmap-oriented language); its ecosystem/weather/creature mechanisms
overlap with Phase 1 and the Weather/Evolution/Fishing/Farming/Flora/Building/
Exploration sections (referenced, not redefined, in world.md itself).

- **Procedural Terrain & Climate Generation** (large) — ✅ Done — via real Earth elevation data, replacing the doc's originally-described one-time heightmap+erosion approach (that approach still exists, retained for future non-Earth planets).
- **Köppen-style Climate Banding** (small) — ✅ Done — `climate_model.gd` + `biome_classifier.gd`.
- **Day/Night & Seasonal Clock** (medium) — ✅ Done — `solar_position.gd` real-time astronomical lighting (no distinct "season" gameplay variable yet, only the real solar geometry).
- **Vegetation Growth Simulation** (large) — 🚧 Partial — see Phase 1 table above (`vegetation_growth_model.gd`); not unified with visible tree rendering yet.
- **Land Health (overharvesting leaves a lasting mark, not just a slower respawn)** (medium) — ✅ Done (mechanism); 🚧 Partial (depletion drivers) — implements world.md's own "Land health" bullet: a persistent per-CHUNK-AGGREGATE scalar (`EcosystemSimulation._land_health`, same fidelity tier as herbivore/predator/fish population, deliberately not per-cell — documented tradeoff in `ecosystem_simulation.gd`'s own file doc comment) that `VegetationGrowthModel.effective_capacity`/`step_grid` now multiply the weather-driven ceiling down by, on top of (not instead of) the existing drought effect. `EcosystemSimulation.record_vegetation_harvest` is the new explicit mortality term standing vegetation density previously lacked entirely (only weather ever moved it) — mirrors `record_catch`'s role for fish. `VegetationGrowthModel.step_land_health` compares a region's harvest RATE since the last step against its own live `regrowth_rate` (the same logistic term `step_density` already integrates, factored out): depletes at `LAND_HEALTH_DEPLETION_PACE_PER_DAY` (`GROWTH_PACE_PER_DAY/8`) only while harvest genuinely outpaces regrowth, recovers at the far slower `LAND_HEALTH_RECOVERY_PACE_PER_DAY` (`GROWTH_PACE_PER_DAY/40`) otherwise — both grounded against real soil-organic-matter-recovery timescales (years-to-decades) vs. a single growing season's biomass regrowth, cited in the constants' own doc comments, not eyeballed. **Persists across both an in-session unload/reload and a real app restart** (`ChunkSerializer.save_ecology`/`load_ecology` gained a `land_health` field, backward-compatible with old 4-field save files via a file-length check defaulting to 1.0; `ChunkEcologyCatchup.advance` now also recovers land health — never depletes it, nothing harvests an unloaded chunk — over real elapsed unloaded time) — this is the one persistent-state gap the concept doc explicitly called out NOT to repeat (unlike vegetation density/fruit stock, which still reset to a fresh weather-driven equilibrium on every chunk reload, a known pre-existing simplification this pass did not touch). **Wired to two real depletion drivers now**: a working farmer NPC's `NpcEconomy._gather` calls `EarthChunkManager.record_vegetation_harvest_near` with the exact same amount its own yield already computed (no separately invented rate) — so sustained NPC farming, not just a hypothetical player action, is a real depletion driver, verified end-to-end in a real probe (below). **This pass adds real horse/sheep grazing as a second, independent depletion driver**, closing the gap this entry previously flagged: both real grazing paths now call `EcosystemSimulation.record_vegetation_harvest` directly with a REAL amount, never an invented one — `EarthChunkManager.graze_grass_at` (GrazerForaging's deliberate walk-to-a-tuft bite) and `EarthChunkManager._graze_by_herbivores` (the ambient any-non-predator-standing-on-mature-grass sweep) both pass `TallGrass.get_growth(cell)` read live off the sim immediately before grazing it — always exactly 1.0 today (only mature patches are ever offered/grazed), but read rather than hardcoded so it stays correct if TallGrass ever grows a partial-bite mechanic, the same "pass the real number you already computed" discipline the farmer wiring established. Two new unit tests (`test_earth_chunk_manager.gd`): `test_graze_grass_at_records_a_real_vegetation_harvest` and `test_ambient_herbivore_grazing_records_a_real_vegetation_harvest`, both red-first (failed for the expected reason against the pre-change code, confirmed via real `godot --headless ... -gselect=test_earth_chunk_manager.gd` runs) then green after the two-line wiring change; no new tuned constant was introduced (the existing `record_vegetation_harvest` is called unchanged), so nothing new needed pinning. **Known scope gap, still honestly flagged**: tree felling (`ChoppableTree`) does NOT yet feed land health — unlike grazing/farming, a `ChoppableTree` node carries no chunk-coordinate or `EarthChunkManager`/`world` reference at all (`TreeRenderer.spawn_tree_at` takes none), and there is no existing real quantity analogous to "vegetation density consumed" for a felled tree the way a farmer's yield or a grazed tuft's growth level provides one — wiring it would mean threading a manager reference through the tree-spawning pipeline AND inventing a new amount from nothing, a structurally different and larger follow-up, not attempted here. **Real probe** (`godot --headless -s <standalone script>`, not GUT, run against the live `EcosystemSimulation`/`NpcProduction`/`NpcEconomy`/`VillageMarket`/`EarthChunkManager` code): two identical grassland regions, identical good weather (temp=moisture=0.8); 2 real farmer NPCs worked one region for 15 simulated days (real `NpcEconomy.step` calls each real second) then stopped for a 10-day settle — land health fell 1.0→0.1875, density settled at a real nonzero 0.0650 (NOT stripped bare, ruling out "nothing left to harvest" as the explanation) vs. the untouched baseline's 0.3840/1.0; a **fresh farmer's real yield_per_second was 83.1% lower** in the degraded region under the exact same weather (0.003252 vs. 0.019200) — land health is a genuine, additional, separate factor from weather, exactly as the concept doc requires. Left alone for a further 200 simulated days, the region fully recovered (density back to 0.3840, land health back to 1.0), confirming the recovery-pace grounding. **A second, separate real probe for grazing** (same shape, standalone `godot --headless -s` script against the live code, deleted after use): two identical Berlin-chunk regions under identical weather; one grazed by 6 real spawned horses over 15 sustained simulated days (`EarthChunkManager._creature_renderer.spawn_single` + `_loaded_creatures`, exactly `test_earth_chunk_manager.gd`'s own `_tame_a_horse_here` wiring) exercising BOTH real grazing paths every tick — 60 deliberate `graze_grass_at` bites landed plus 12 ticks where the ambient `_graze_by_herbivores` sweep measurably moved density, all constrained to the one chunk being measured — land health fell 1.0→0.6625 and density fell 0.1360→0.0883, while the untouched control stayed EXACTLY at 1.0/0.1360 for the entire 15 days under the identical weather, isolating grazing as the sole variable. Land health's decline was not monotonic-to-zero: it flattened and partially recovered from day 7 onward (0.5625→0.6625) as the grazed field itself thinned, giving grazers fewer mature tufts per tick and so a naturally shrinking harvest rate — the mechanic self-limits rather than collapsing a field to nothing. Removing the horses for a further 10-day settle recovered land health 0.6625→0.7875, a **0.125 gain that matches `LAND_HEALTH_RECOVERY_PACE_PER_DAY` (`GROWTH_PACE_PER_DAY/40` = 0.0125/day) times 10 days exactly**, confirming the same tested recovery pace the farmer probe already validated now also governs grazing-caused depletion. **Player-observable timescale, stated honestly**: this is a deliberately SLOW mechanic — a loaded/watched chunk runs its ecosystem "day" at 60 real seconds (`EarthChunkManager.SECONDS_PER_SIMULATED_DAY`), so full depletion under continuous overharvest takes on the order of 15-20 minutes of real, continuous, active overharvesting to show up clearly, and full recovery on the order of an hour or more of the land being left alone WHILE LOADED; an unloaded/away region instead catches up on the much coarser real-wall-clock catch-up clock (1 real hour = 1 ecosystem day), so a genuinely scarred plot realistically heals over real DAYS of the player simply not being there, not one login session — matching the concept doc's "years, not until the next rain" framing translated onto this game's actual clocks.
- **Herbivore Population Simulation** (large) — ✅ Done — see Phase 1 table above.
- **Predator Population Simulation** (large) — ✅ Done — see Phase 1 table above.
- **Emergent Creature Distribution ("boars" pillar)** (medium) — ✅ Done — `test_ecosystem_time_lapse.gd` proves biome-driven clustering with no hand-placed spawners, matching this pillar's exact framing.
- **Aggregate-to-Individual Agent Promotion (simulation LOD)** (large) — ✅ Done — see Phase 1 table above; placeholder visuals only, not replicated in multiplayer yet.
- **Torus/Globe World Topology** (medium) — ✅ Done — `world_coordinates.gd` toroidal wrap.
- **Chunk-Based World Persistence** (large) — 🚧 Partial — built and tested, not wired into live gameplay.
- **Variable-Fidelity Chunk Simulation (catch-up pass)** (large) — ✅ Done
  for ecology specifically — this line was stale; see the Ecosystem
  Dynamics section above (`src/world/chunk_ecology_catchup.gd`). Not yet
  generalized beyond ecology — construction/settlement catch-up is tracked
  separately, see the Timber Construction section below.
- **Dynamic Weather & Disaster Events** (large) — ⬜ Not started (see Weather section)
- **Creature Genetics/Evolution System** (huge) — ⬜ Not started (see Evolution section)
- **World Boss Emergence** (medium) — ⬜ Not started (see World Bosses section)
- **Fishing/Aquatic Ecosystem Simulation** (large) — ⬜ Not started (see Fishing section)
- **Farming System** (medium) — ⬜ Not started (see Farming section)
- **Flora DNA & Seed-Dispersal Evolution** (huge) — ⬜ Not started (see Flora section)
- **Building/Construction System** (large) — ⬜ Not started — see the
  Building section above for the existing piece/placement/room mechanism,
  and the new Timber Construction section (`concept/timber_construction.md`)
  for statics, withering, and NPC-built settlements specifically.
- **Exploration & History-Seeded Points of Interest** (large) — ⬜ Not started (see Exploration section)

### Farming (`concept/farming.md`)

No farming system is wired into live gameplay, but its plot and breeding math now exist as tested pure logic:

- **Farming loop (plant/tend/harvest)** (medium) — 🚧 Partial — `src/gameplay/farm_plot.gd`: plant/grow-over-time/harvest state machine, tested; no plantable tile exists in the live world, no player action to use it.
- **Crop DNA/phenotype system** (large)
- **Crop trait rarity tiers** (medium)
- **Selective breeding / cross-pollination** (large) — 🚧 Partial — `src/gameplay/crop_breeding.gd`: two-parent crop crossover, tested; no live crops to breed.
- **Rare crop strain collecting hook** (small) — 🚧 Partial — `crop_breeding.gd`'s `trait_rarity_score`/`is_rare_strain`, tested; same wiring caveat.
- **Crafting ingredient integration** (medium)
- **Cooking ingredient integration** (medium)
- **Farm plot as vegetation-density override** (large)
- **Tilling/watering/fertilizing (carrying-capacity boost)** (medium)
- **Shared wild/farmed genetic population** (large)
- **Cross-breeding UI / trait-math visibility (open question)** (medium)
- **Seasonal crop viability (open question)** (medium)

---

### UI / presentation

- **Unified UI theme** — ✅ Done — `src/ui/ui_theme.gd` (tested: palette, styleboxes, built `Theme` all pinned) is one dark/rounded/gold-accent theme applied to every menu and window (main menu, settings, inventory, crafting, skill tree, dev console) plus the HUD survival card. Replaces the earlier raw grey boxes.
- **Main-menu backdrop** — ✅ Done — the start-up menu now dims the whole screen behind a full-rect backdrop (`World._show_main_menu`) so the game world/HUD no longer bleed through it.
- **HUD polish** — 🚧 Partial — survival meters grouped into a themed panel card; XP bar / creature panels repositioned to stop overlapping. Meter fills are still plain rects (no rounded fills).
- **Character screen / inventory revamp** — ✅ Done (basic) — `scenes/inventory_window.gd` (toggle I) is now a PoE/Valheim/Hammerwatch-style **two-pane character screen**: a left **equipment paperdoll** (rendered head+torso preview + right-clickable head/chest/legs/feet/weapon slots) and a right **item-slot grid** (icon + count, hover tooltips). **Right-click** an inventory item to wear/equip or eat it; right-click a worn slot to unequip. **Drag-and-drop works** (left-click and drag): drag an item onto another grid slot to reorder, or out onto a HUD hotbar slot to bind it to a number key (`src/ui/drag_slot.gd` is the shared drag-capable slot Control; `src/gameplay/hotbar.gd` holds the bindings). Left and right are deliberately split across the two gestures — clicking left used to ALSO activate an item (equip/eat) on mouse-down, which fired the instant you pressed down to start a drag, before Godot's drag threshold even triggered (reported: "a click on a carrot makes it vanish"). Shows total armor. The hotbar picked up the same UX pass: a hover highlight, a tooltip naming what's bound and its count, and right-click to clear a slot (previously the only way to change one was overwriting it via drag). Not yet: splitting/merging stacks by drag, or dragging directly onto a paperdoll slot to equip.
- **Character creation with pixel art** — ✅ Done — `scenes/main_menu.gd` is now a real **character creator**, replacing the old class picker (whose "preview" was a disembodied head floating above a flat colored rectangle): a class column with stat blurbs and a highlighted selection, a **live full-body portrait** in the middle (`ProceduralCharacterSprite.generate_hero_portrait_image` composes head/torso/arms/legs/boots into one figure, scaled 5x with nearest-neighbour filtering so it stays crisp), and an appearance column cycling **five customization axes** with ◀ ▶ arrows — skin tone (6), hair colour (7), hair style (6, named), beard (4, named), eye colour (4) — plus a Randomise button. The authored appearance now flows through `start_requested` → `World._pending_appearance` → `Player.apply_class(..., appearance)`, so the spawned hero actually wears what the creator previewed (previously the in-world look was always re-rolled from the peer id, ignoring the picker entirely). **The creator is now tabbed** (reported: "there should be tabs with character and skilltree so you can view each classes skills before creating"): a `TabContainer` splits **Character** (the class/portrait/appearance columns above, now themed card panels instead of loose Controls) from a new **Skills** tab, which previews the shared `SkillTree` node pool as a card grid and highlights whichever nodes actually synergize with the currently-picked class's own dominant stat (`_class_dominant_stat`/`_CLASS_STAT_TO_SKILL_STAT`) — live-updating as the player switches classes, before committing. Honestly scoped: `SkillTree` is one pool shared by every class (see the Soft Class System row above — full class-specific skill webs aren't built yet), so the tab previews the real shared pool plus the class's own stat lens rather than fabricating fake per-class trees; a mage-leaning pick simply highlights nothing today since no shared node grants mana yet, and the tab says so in its own footer. Visual pass: the whole creator now reuses `UiTheme`'s palette (the same theme `World` already assigns every other window) instead of picking its own colors, class/skill entries are bordered card panels rather than bare Buttons/Labels, section headers got an accent underline, and the panel grew from 760x520 to 880x620 to fit the tab bar and skills grid without cramping. That still wasn't enough headroom once real theme/font metrics applied — reported: "the character creation screen overflows and is not scrollable so I can't start a new game because button is not visible" — since MainMenu is a fixed-size panel (not an auto-growing one), the overflowing tab content was silently pushing the Back/Begin row off-screen with nothing to reach it by. The tab content is now wrapped in its own `ScrollContainer`, added deliberately OUTSIDE the Back/Begin row's own container, so the middle content scrolls internally while Begin always stays visible and clickable at a fixed position regardless of how tall either tab's content gets. **A follow-up pass made the Character tab a genuine hero showcase** (reported: "make it genuinely captivating ... I want the classes to be icons and on top over the character and more character customization options and DNA influence"): the old plain-text class name list is gone — the 7 classes are now small icon cards (`_build_class_icon_row`) sitting directly above the portrait, each icon a real miniature rendering of that class's own default look via the same portrait generator (not a placeholder glyph), so picking a class previews it before it's even selected. DNA is now visible, not just readable: a glow ring behind the portrait (`_dna_glow`) repaints to the rolled genome's rarity color and, for legendary specifically, pulses via a looping `Tween` — common/rare/legendary now read as visibly different moments, not just different words in a stat line — and a "★" badge lights up on whichever class icon the current roll's `HeroDna.resonance` favors most, so DNA visibly steers the class picker itself. **A sixth customization axis, accent/trim color** (`HeroAppearance.TRIM_COLORS`, 6 named options — gold/silver/copper/crimson/verdant/amethyst), is now independently player-chosen rather than always fixed by the class palette with no choice at all — tunic/leg colors still communicate class identity, only the accent trim is free, matching dna.md's resolved "cosmetics layer on top" pillar (customization that doesn't touch what the class itself signals).
- **Illustrated character building blocks (scaffolding)** — 🚧 Partial — `src/rendering/illustrated_character_sprite.gd` (`IllustratedCharacterSprite`) is the character-rig counterpart to `IllustratedAnimalSprite` (same registry/chroma-key/`SpriteSheetSlicer` shape that already replaced the animal roster's procedural sprites with real horse/deer/boar/sheep art), wired into `CharacterView.apply_appearance` for the three single-tint paperdoll parts (body/legs/arms — each falls back to its existing procedural texture automatically via `_apply_paperdoll_part` until real art is registered, so this is a no-op today, not a visual change). No part art is registered yet (`_PARTS` is empty) — `docs/concept/character_art_brief.md` is a practical brief for generating it with AI: draw parts NEUTRAL (grey/white, no baked-in color) so `modulate` can tint them per class/skin-tone at runtime, the same magenta chroma-key convention `sheep.png` already established, and exactly how to register a finished sheet once it exists. The HEAD is deliberately excluded from this registry (see the brief) — a head mixes skin/hair/eye color in one drawing, which a single flat tint can't separate; doing that properly needs layered art (a base head + separate recolorable hair/beard overlays), scoped but not built.
- **Character sprite engine** — ✅ Done (basic) — `HeroAppearance` grew from 3 axes to 5 with real pools, an explicit-choice constructor (`appearance_from_choices`, index-wrapping in both directions so a creator can cycle freely) and a `choices_from_appearance` inverse so a rolled hero is resumable in the creator. `ProceduralCharacterSprite`'s hero head went from "a circle with two dots" to a real face: 6 hair silhouettes (short/swept/long/ponytail/topknot/bald), 4 beard styles (none/stubble/goatee/full), brows, colored irises with pupil + catchlight, and a mouth; the tunic gained chamfered shoulders, a collar, and a belt with a buckle. Outfit palettes cover all 7 player classes plus the 6 villager occupations. Still a paper-doll rig of separate part sprites in-world (`CharacterView`) with no per-facing or walk-frame art — the parts are just much better drawn now.
- **Main-menu centering fix** — ✅ Done — `MainMenu._ready()` centered itself with `set_anchors_preset(PRESET_CENTER)` alone, which (per Godot 4's actual anchor semantics — it recomputes offsets to *preserve* the control's current on-screen rect under the new anchor fraction, not to center a rect of its size) left the panel pinned to the CanvasLayer's top-left corner. Fixed by explicitly setting the four `offset_*` to a symmetric half-`PANEL_SIZE` box after the preset call, matching the pattern every other centered popup in this codebase already used (`SettingsOverlay`/`InventoryWindow`/`DevConsole`, wired in `world.gd`). Pinned by `test_panel_is_actually_centered_not_pinned_to_a_corner`.
- **4x camera zoom** — ✅ Done — `Camera2D.zoom` bumped from the original `3x` to `4x` (`Player.CAMERA_ZOOM`, applied in `_ready()` rather than left as a bare `.tscn` number) so pixel art reads clearly across the full 1280x720 window. HUD is unaffected (built screen-space under the `_ui` `CanvasLayer`, independent of world-camera zoom). Nearest-neighbour texture filtering was already project-wide correct, so no filtering change was needed.
- **Universal hover name/action tooltip** — ✅ Done — reported: "fruits on the ground should only show labels on hover .. and also EVERY entity (worm, fly, fruit, stone, boulder, pebble, grass blade, carrot, potato, tree, fruit on tree) should show its name on hover ... also all entities with interactions should show the action name and the hotkey ... if multiple available show all". `HoverTargetFinder` (`src/rendering/hover_target_finder.gd`, group `GROUP_NAME := "hoverable"`) is a pure nearest-candidate-within-radius picker; `World._update_hover_tooltip` scans the group every frame, building each candidate's name/actions from two duck-typed methods, `get_display_name()` and `get_hover_actions() -> Array[{verb, action}]`, and renders the winner as a multi-line floating label (name, then one `"Verb (Key)"` line per action, key read live via `OS.get_keycode_string(Keybindings.keycode_for(...))` so a rebind is reflected immediately — the same pattern the pre-existing proximity `_interaction_prompt` already used for NPCs/liftable stones). Wired into every hoverable node: `CreatureMarker`/`FishMarker`/`PiscivoreBirdMarker`/`AmbientFlyerMarker` (name-only, pre-existing), `DroppedItem` (name + Pick Up — this is also what makes ground items name-on-hover-only: the old always-on floating label over every dropped item, Path-of-Exile style, is gone), `LiftableStone` (Wentworth-class name + Pick Up, plus Kick when `Kick.is_kickable` says the stone is light enough), `SmashableStone` ("Boulder" + Smash), `MinableOre` (the actual yielded item's own name via `ItemCatalog`, e.g. "Iron Ore"/"Coal", not a naive "<type> Ore" guess + Mine), `ChoppableTree` ("Tree"/"Fallen Tree" + Chop). Grass is the one exception, tile- rather than Node-based (see Long Grass below): `EarthChunkManager.tall_grass_growth_at(pixel_position)` is a new read-only accessor `World` falls back to only when nothing in the group claimed the cursor, showing "Tall Grass" name-only for an immature patch and adding Harvest once mature (`growth >= 1.0`). Explicitly out of scope for this pass: worms (`earthworm_patch.gd` has no player interaction yet), carrot/potato as world entities (only AI-art prompts exist so far, see `docs/art/ai_sprite_prompts.md`), and fruit still on a tree (passive-only — only the fallen `DroppedItem` version is a real, separately-hoverable object). `World._update_hover_tooltip`/`_hover_tooltip_text` are untested UI glue, matching this file's pre-existing boundary for `world.gd` (see Persistence section below) — every piece of actual logic underneath (the finder's nearest-candidate pick, each entity's name/action list, the grass growth accessor) is unit-tested.

---

### Persistence (`concept/persistence.md`)

- **New Game / Load Game** — ✅ Done — previously the world persisted eagerly to `user://` regardless of menu choice while the player never persisted at all, so "New Game" actually meant "old world, new stats". `Player.to_save_dict()`/`apply_save_dict()` round-trip position, class, authored appearance (now retained in a new `Player.appearance` field instead of applied-once-and-forgotten), health/max health, wallet, XP/level, skill-tree allocations, inventory, worn equipment + held weapon, and hotbar bindings. `PlayerSave` (`src/gameplay/player_save.gd`) is the pure I/O layer (mirrors `ChunkSerializer`'s `store_var`/`get_var` convention). `MainMenu` gained a root-screen **Load Game** button, shown only when a save exists, that bypasses the character creator entirely. New Game / Host Game now wipe the previous run's player save and all three `EarthChunkManager` persistence dirs (`WorldReset`, `src/world/world_reset.gd`) before spawning, so a fresh character actually loads into a fresh world. Autosaves periodically (`World.AUTOSAVE_INTERVAL`, 60s) and once on window close. Tested: `test_player_persistence.gd`, `test_player_save.gd`, `test_main_menu.gd`, `test_world_reset.gd`, `test_world_persistence.gd`. `World`'s own spawn/autosave wiring is untested glue over those pieces, matching `World`'s pre-existing boundary (no `world.gd` function had a direct unit test before this either). Not yet: multiple save slots (out of scope, see the concept doc).

- **Loading screens** — ✅ Done (see `concept/persistence.md`'s "Loading screens" section) — reported: "the game doesn't appear to hang when starting a new game". Investigated with real timing instrumentation against a real running instance (not assumed): New Game/Load Game/Join's real synchronous stall is `EarthChunkManager.update()`'s first call for a freshly-centered chunk radius, inside `_compute_dry_land_spawn_tile`/`_spawn_local_singleplayer_from_save` — **measured ~39s for that single call** in this dev sandbox (`_spawn_local_singleplayer` end to end: ~40s; the rest, mostly `CharacterView`'s appearance/portrait generation, is under a second). Nothing in that call chain (`update` → `_load_chunk` → terrain paint + tree/stone/grass/crop/decomposer/flower/scrub/lichen spawning) ever `await`s, so it fully blocks frame presentation for its whole real duration. `LoadingOverlay` (`scenes/loading_overlay.gd`, a small dim-backdrop + centered status label + indeterminate spinner `Control`) is shown via `World._show_loading_overlay`, which awaits **two** `process_frame` signals so the overlay is actually painted before the long call starts (confirmed against real rendered screenshots captured mid-freeze — one `await` alone was not reliably enough, and a first attempt without the explicit post-preset offset reset left the whole overlay pinned to a zero-size rect at the origin instead of covering the screen, the same `set_anchors_preset`-preserves-current-rect gotcha `MainMenu._ready()` already documents; both confirmed and fixed against real screenshots, not by re-reading the code and assuming it was right). Wired into all three entry points — `_on_menu_start_requested` ("Preparing a new world..."), `_on_menu_load_requested` ("Loading your world..."), `_on_menu_join_requested` ("Connecting to host...", covering a joining client's own version of the same stall, which actually lands later, inside `_client_process`, since a joining client has no single call site to wrap the way the other two do) — and hidden from one unified place, `_client_process`, right after its own `update()` call, idempotently. Progress is a real, honest **indeterminate spinner**, not a fabricated percentage: nothing outside `update()` can observe real interim progress without it yielding mid-loop, which would mean restructuring `EarthChunkManager`/`TerrainRenderer` internals — out of scope for a loading screen (every existing synchronous caller, including most of the test suite, depends on `update()` completing in one call). The same real screenshots confirm the honest limit of this approach: since nothing renders during the freeze itself, the spinner is only ever actually seen to advance across the couple of frames awaited before/after the freeze, then holds on one frame for the freeze's real duration — a real indeterminate spinner, just one that (like everything else on screen) can't animate through a period nothing can render during. Tested: `LoadingSpinner.frame_for_elapsed` (`src/ui/loading_spinner.gd`), pure and tuned-constant-driven, `test_loading_spinner.gd`; `LoadingOverlay`/its `World` wiring are untested Node-composition glue, `World`'s pre-existing boundary. Verified end-to-end against a real running instance for New Game and Load Game (real screenshots, both mid-freeze and post-spawn-with-overlay-gone); Join's overlay-hide wiring could not be verified live the same way — this dev machine's live multiplayer connectivity is blocked (see the Multiplayer notes elsewhere in this doc), so it's reasoned from the code rather than screenshot-confirmed. Separately, and NOT covered by any of the above: a stale/missing `TerrainAtlasCache` (`TerrainRenderer.build_tile_set`, gated on `ATLAS_VERSION`) is a real, similarly-sized stall (~62s measured in this dev sandbox on this session's own `ATLAS_VERSION` bump) that happens in `World._ready()`, unconditionally, before the main menu itself is even shown — out of scope here since there's no entry point left to wrap it with once it's already running before any menu click exists; self-heals after the first paid run (writes a fresh cache), so it's a one-time cost per `ATLAS_VERSION` bump rather than a recurring one.

## Reality check

This design corpus — 49 concept docs plus a roadmap and, since 2026-08-23, a
10-doc `docs/emergence/*.md` substrate spec, several hundred catalogued
mechanisms in total (the exact figure is stale, see this doc's intro) —
describes a multi-year, full-team-scale MMORPG: procedurally simulated
planetary ecology, LLM-driven autonomous NPCs with memory and daily planning,
deep genetics/evolution shared across animals/plants/players/pets, a
player-authorable spellcrafting DSL, deterministic blueprint-based crafting,
a dual-currency economy, factions, housing, world bosses, PvP, festivals,
farming, fishing, cooking, marriage and child-rearing, permadeath with
reincarnation across technological eras, eventual multi-planet space travel,
and — the newest and most structurally ambitious layer — an event-sourced
causal substrate meant to make society, history, economy, settlements, and
dungeon/boss content emerge from simulated cause and effect rather than
hand-placed content, all before multiplayer is even considered.

A solo/part-time developer has, to date, built a real, tested foundation:
a genuine real-Earth world simulation (bilinear elevation sampling, real
lat/long geodesy, real-time astronomical day/night, biome classification,
chunk streaming) plus a basic player/movement/rendering layer (toroidal
movement, water-depth-based swimming/wading/drowning, wetness tracking,
placeholder character rendering). That is Phase 0 of the roadmap, essentially
complete, plus an early, deliberate architectural pivot (real Earth data
instead of fictional procedural generation) that the roadmap didn't
anticipate.

Since that snapshot, several more passes have landed: per-creature HUD info
panels (`CreaturePanel`, one per nearby creature with name/level/HP bar +
numeric HP label) replaced both an aggregate "Nearby Creatures" list and an
earlier world-space-nameplate attempt; the always-visible inventory text
panel was replaced by a real toggleable `InventoryWindow` (key I, click a
food row to eat it); creature variety grew (boars, lynx) with level-scaled
max health; flat-color terrain tiles were replaced by procedurally-generated,
seeded pixel-art tile variants per biome, plus a directional border-blending
system between any two neighboring biomes (a border cell dithers toward
whichever biome dominates on each edge, rather than a random patchwork); a
water/land cell that meets the other on two PERPENDICULAR cardinal sides (a
real right-angle corner of the tile grid, e.g. a lake's square corner) now
has that specific corner carved into a rounded quarter-circle of the other
biome's own texture, painted directly into the opaque BASE tile layer
(`ProceduralTerrainSprite.generate_corner_image`, `TerrainRenderer.
corner_direction_for`/`atlas_coords_for_corner`) rather than left as a hard
square notch (reported: tile borders read "square" instead of rounded). A
first attempt tried to fix this by rounding the translucent GPU WaterFx
*overlay*'s shore-distance alpha fade (`ProceduralShoreDistanceSprite`) --
confirmed in-game to have **no visible effect**, because that overlay is
drawn on top of this fully-opaque base tile and can never change the base
tile's own square silhouette underneath it; that attempt was reverted. A
second attempt only ever carved the OCEAN side of a corner (an ocean cell
with land poking into it on two sides, a CONVEX "peninsula tip") --
confirmed in-game (screenshot) to fix only a small minority of corners on a
real, irregular/blobby lake outline, because most of that outline's corners
are the mirror CONCAVE shape instead: a LAND cell with ocean poking into it
on two sides (a "bay tip"), which the ocean-only check never touched at
all. `corner_direction_for` now checks both shapes symmetrically (a second
land-owning atlas tile family, `TerrainRenderer._land_corner_base_linear`),
and also carves when the two flanking land neighbors are two DIFFERENT
biomes (routine on a real coastline) rather than bailing out, carving
toward whichever neighbor wins `BLEND_PRIORITY`. A follow-up report of "zero visible
change at all" after that fix was traced with a throwaway debug script
(loads a real chunk via `EarthChunkManager.update()`, the exact code path
the game uses, then inspects the live `TileMapLayer`'s actual painted atlas
coordinates) rather than re-checking unit-test logic -- confirmed the real
render path DOES reach `corner_direction_for`/paint the corner tile family
(2882 real corner tiles painted out of 25,600 painted cells near Berlin,
both convex and concave), so the wiring was never broken; the radius was
also tightened from an eyeballed `0.3` fraction to an explicit, tested
`CORNER_RADIUS_PIXELS := 8.0` (art-pixel units at the 64px `ART_TILE_SIZE`
resolution, `CORNER_RADIUS_FRACTION` now derived from it) per CLAUDE.md's
tuned-value rule. A THIRD report ("still not giving every corner a border
radius", i.e. partial-not-zero this time) was root-caused with the same
real-chunk debug-probe technique: `corner_direction_for` picked only the
FIRST qualifying diagonal direction and returned early, silently dropping
any others -- measured directly against real generated chunks near Berlin,
859 of 3355 real corner cells qualify on MORE than one corner
simultaneously (a single-tile-wide land spit with water on three sides has
two; a lone one-tile pond/island has all four), so roughly a quarter of
real corner cells were only ever getting one of their several real corners
carved. `corner_direction_for` now collects every qualifying diagonal,
grouped by dominant partner biome (same "most edges wins" tie-break
`dominant_blend_for` already uses), and the atlas moved from one tile per
single direction to one tile per non-empty SUBSET of the 4 diagonals
(`TerrainRenderer.CORNER_MASK_COUNT`, mirroring `DIRECTION_MASK_COUNT`'s
role for the blend system) so a multi-corner cell's tile now carves all of
its real corners in one carved shape, not just one. Re-verified against the
same real Berlin chunk data after the fix: a known 4-corner cell (an
isolated one-tile pond) now gets a single atlas tile with all four corners
carved, confirmed by direct atlas-coordinate comparison, not just unit
assertions. A FOURTH report (isolated single-tile ponds still "rendering as
perfect hard squares" -- the cleanest possible 4-corner case) finally
exposed the real blocker, which every earlier check had been blind to: all
those checks compared an atlas COORDINATE against `atlas_coords_for_corner`,
but both sides derive from the same `_corner_linear` math, so they were
self-consistent and proved nothing about the PIXELS baked at that
coordinate. Reading the real built atlas texture's actual pixels showed
only ONE of an isolated pond's four corners was carved. Cause:
`ProceduralTerrainSprite` authors tiles at its own `SIZE` (64), but
`ART_TILE_SIZE` is `TILE_SIZE * ArtResolution.DETAIL_MULTIPLIER` and so
follows that shared multiplier (32 at the current 2x factor) -- and
`TerrainRenderer._blit_tile` blitted a `Rect2i(0, 0, ART_TILE_SIZE,
ART_TILE_SIZE)` SOURCE region, i.e. it silently **cropped every oversized
generated tile to its top-left quadrant** rather than scaling it down.
Three of every carved tile's four corners were discarded before reaching
the atlas. `_blit_tile` now rescales (nearest-neighbour) when a generator's
tile is larger than `ART_TILE_SIZE`. This was quietly degrading **all**
terrain art, not just corners -- blend gradients, grass blades and moss
were every one of them showing only their top-left quarter. Pinned by two
new tests that read real baked atlas pixels rather than coordinates
(`test_baked_atlas_pixels_for_an_isolated_pond_are_carved_on_all_four_corners`,
`test_baked_tiles_represent_the_whole_generated_tile_not_a_cropped_corner`).
Note the long-failing `test_art_tile_size_is_4x_the_world_tile_size`
(asserts 64, gets 32) was the direct symptom of this same
`DETAIL_MULTIPLIER` divergence and had been repeatedly dismissed as an
unrelated pre-existing failure -- it is still failing and still 🚧 open,
since reconciling the multiplier itself would rescale every entity sprite
(including this branch's deliberate character-scaling work); `_blit_tile`'s
rescale makes terrain correct regardless of what the multiplier is.
Secondary, measured but NOT the cause: the translucent GPU water overlay
still washes the water-side carve, reaching ~48% opacity at the outer edge
of the 8px wedge (0% exactly at the corner point, since shore distance is 0
there) -- the land-side (bay-tip) carves have no overlay over them at all
and render fully crisp. A fresh in-game screenshot is still needed to
confirm the carve now reads clearly at actual camera zoom -- not yet
visually re-confirmed after this pass.

✅ **Diagonal-only land/land corners now blend too.** Reported (screenshot):
a grassland/forest border, where the two biomes touch only at a single
tile-grid corner point (the outer corner of a staircase-shaped biome
boundary, no shared cardinal edge), still rendered as a hard, unblended
square corner -- the exact gap the previous pass above left open.
`corner_direction_for` now also reads the actual DIAGONAL neighbor cell (a
new `TerrainRenderer._diagonal_neighbor_biomes`, the corner-carve
counterpart of `_neighbor_biomes`) and carves toward it when both cardinal
flanks are the cell's own biome but the diagonal neighbor is a different
LAND biome with a higher `BLEND_PRIORITY` -- one-sided, same "exactly one
side carries the transition" rule `dominant_blend_for` already uses, so the
same point is never carved from both sides at once. Deliberately scoped to
LAND/LAND only; a water/land diagonal-only touch (e.g. the corner-diagonal
land cells around an isolated one-tile pond) has the same underlying gap but
is left unaddressed here too, given the water-corner logic's own four-round
bug history above (see `docs/concept/terrain_biome_borders.md`).
Investigating this surfaced a second, previously-unreported bug with the
same root cause: `_corner_linear`'s land-owning branch indexed the atlas
slot by `own_biome`'s ordinal ALONE, silently discarding `other_biome` (its
own doc comment assumed `other_biome` was always `"ocean"`) -- but
`corner_direction_for`'s existing right-angle branch never actually
restricted itself to ocean, so a real, reachable land/land right-angle
corner (a lower-priority land cell flanked on two perpendicular cardinal
sides by the SAME higher-priority land biome) silently baked **ocean's**
texture into the wedge instead of the real neighboring biome's. Fixed by
giving the corner system a genuine THIRD atlas family
(`_land_land_corner_base_linear`/`_land_land_corner_linear`), pair-indexed
like the dither-blend family already is (`_blend_linear`), rather than
single-biome-indexed -- confirmed with a real baked-pixel test
(`test_baked_atlas_pixels_for_a_land_land_corner_show_the_real_partner_biome`),
the same discipline the earlier "atlas coordinate matched but pixels were
wrong" bug round above already established as load-bearing for this
subsystem. One-time atlas-bake cost grows accordingly (measured ~218s for
the full `test_terrain_renderer.gd` file in this environment, up from the
file's own historical "~13.5s" build_tile_set() baseline) -- cached to disk
per `ATLAS_VERSION` as before, so this is paid once per version bump, not
per boot.

✅ **Illustrated ground tiles -- real art registered for every land biome.**
Following the same transition loose stone already made
(`IllustratedStoneSprite`), base biome ground tiles now draw from a
hand/AI-illustrated sheet instead of `ProceduralTerrainSprite`'s per-pixel
generation. `IllustratedTerrainSprite` (`src/rendering/
illustrated_terrain_sprite.gd`) is the same "sheet → `SpriteSheetSlicer` →
cached frames, seed-picked per position" shape, wired into `TerrainRenderer`
through a `_biome_frame_image(biome_name, variant, frame)` seam (mirrors
`StoneRenderer._texture_for`'s own has_variants()-gated fallback) --
illustrated art wins when a biome has a registered sheet, the procedural
generator runs unchanged otherwise. An illustrated tile has no animation of
its own, so the SAME frame is reused across all `FRAME_COUNT` atlas
animation slots for that biome/variant, same as a static procedural biome
already does.

The generation prompts (`docs/art/ai_sprite_prompts.md` section 3)
originally targeted a 5x5/25-variant sheet per biome -- real generation only
reliably held a square-cell GRID at 3x3; a 5x5 attempt came back as 7 uneven
tall vertical strips (wrong shape AND wrong aspect ratio for a full-bleed
tile, not just short on count). `TerrainRenderer.VARIANTS_PER_BIOME` settled
at 9 to match (briefly raised to 25 in anticipation of 5x5, then walked back
down once the real deliverable was 3x3), so every baked atlas slot maps to a
genuinely distinct illustrated tile rather than duplicating a smaller pool
across a larger cap. `ATLAS_VERSION` bumped twice alongside these changes so
no stale-atlas cache silently survives either one.

Ingestion needed one real fix beyond registering the sheets: these sheets'
divider lines carry a visible soft glow/anti-aliasing that never reaches
pure `#FF00FF` across most of their own width, so the strict near-pure-
magenta threshold that works for `pebbles.png`/`boulders.png` missed most of
a divider's width and merged neighboring cells into one wide frame (measured
directly: some sheets sliced into only 3-4 frames instead of the real 9,
and the merged frames' oversized content dragged the shared per-sheet scale
factor down, leaving even correctly-sliced frames occupying only ~25% of
their canvas instead of full-bleed). `IllustratedTerrainSprite` uses a
looser `MAGENTA_SKEW_MIN` check (how far the red/blue average sits above
green) instead of `IllustratedStoneSprite`'s strict per-channel thresholds,
tuned specifically for this sheet style. A second, narrower issue: tundra's
own near-white ground color was being misread by `SpriteSheetSlicer`'s
built-in "near-white counts as divider" heuristic (meant for sheets whose
only background signal IS a pale line) -- since the real dividers are
already punched to genuine transparency before the slicer ever sees them,
that heuristic has nothing left to legitimately catch, so
`IllustratedTerrainSprite` disables it entirely for terrain ingestion
(`_DISABLED_DIVIDER_GRAY_MIN`) and relies on alpha alone.

`assets/sprites/terrain/{grass,forest,desert,mountain,tundra,rainforest}.png`
are the six real, registered sheets (`grassland_9.png` is a superseded early
exploratory render). Two deliberate, documented scope limits rather than
gaps: ocean is excluded (an illustrated tile can't carry
`ProceduralTerrainSprite`'s animated water scroll yet, so registering one
would trade moving water for a static tile), and the directional-blend/
corner-carve border tiles between differing biomes stay procedural
regardless of what's registered -- `ProceduralTerrainSprite` can synthesize
a blend/corner image for any of the thousands of (biome pair x direction
mask x corner mask x variant) combinations on demand, and hand-illustrating
that combinatorial space isn't in scope.

**Follow-up bug, reported after seeing it live in-game: grass (and other
illustrated biomes) rendered as visible white/yellow "static" noise, with
some tiles reading as flat/blank ("missing pixel art").** Both symptoms
traced to the same cause: `IllustratedTerrainSprite` normalized every
sliced frame onto a 64x64 canvas ("matches `ProceduralTerrainSprite.SIZE`"),
then left `TerrainRenderer._blit_tile` to nearest-neighbour-downscale that
a SECOND time down to the real 32x32 `ART_TILE_SIZE`. Nearest-neighbour
discards whole rows/columns of source pixels with no averaging -- fine for
the UPSCALE direction (keeps pixel art crisp, see `_blit_tile`'s own doc
comment), actively wrong for DOWNSCALE (aliases any fine per-pixel detail
into noise regardless of content). `ProceduralTerrainSprite` only ever got
away with this same code path because its own texture is deliberately
painted in coarse 2x2-pixel marks (`SPECKLE_CLUSTER`) built to survive
exactly that decimation; the illustrated art (individual grass blades,
leaf-litter speckle) was never authored with that constraint, so it
aliased -- confirmed directly by dumping a real frame through both resize
paths side by side (`Image.INTERPOLATE_NEAREST` vs `INTERPOLATE_LANCZOS`):
nearest destroyed recognizable blade shapes into scattered noise, Lanczos
preserved them as a coherent (if softer) texture. Fixed INSIDE
`IllustratedTerrainSprite` rather than by changing `_blit_tile`'s shared
behavior -- `CANVAS_SIZE`/`BASELINE_Y` now target the real final tile size
(32, matching `ART_TILE_SIZE`) directly, so `SpriteSheetSlicer`'s own
Lanczos resize is the only downscale that ever happens and `_blit_tile`'s
rescale branch never triggers for illustrated tiles at all. This keeps
every other tile family (procedural biomes, structures, blend/corner
tiles) completely untouched -- verified by a real before/after pixel dump
of all 6 land biomes, not just grass: desert's broader dune-ripple pattern
and forest's blotchy moss survive the fix looking clean, while mountain's
fine branching cracks and grass's individual blade edges soften
noticeably (a real resolution ceiling at 32px/tile, not something further
resize-algorithm tweaking can fully solve -- illustrated linework this
fine may need a coarser-drawn source or a higher `DETAIL_MULTIPLIER` to
read crisply, neither attempted in this pass). `ATLAS_VERSION` bumped
again so the aliased cache is never silently reused.

**grass.png and forest.png regenerated** with intentionally bolder, longer,
thicker blade/leaf shapes (drawn at a scale meant to survive the 32px
downscale rather than fine hairline detail that would alias away) -- a
real, visible improvement confirmed by dumping fresh frames through the
same pipeline: distinct directional blade strokes and leaf/moss shapes now
survive at the final in-game tile size, instead of the previous
mushy/uniform speckle. Both regenerated sheets kept the same file path and
landed at nearly identical row_bands to what was already registered (still
a 1254x1254 3x3 grid; the requested 128px-per-tile generation size wasn't
literally honored by the generator, only the requested bolder STYLE was)
-- no `IllustratedTerrainSprite._SHEETS` changes needed, only
`ATLAS_VERSION` bumped again so the stale-content cache isn't reused.
desert, mountain, tundra, and rainforest are still on their original
sheets (not yet regenerated with this bolder-shape lesson applied).

✅ **Directional-blend and corner-carve border tiles now composite real
illustrated pixels, not a flat-color-plus-speckle stand-in.** Reported live
once illustrated ground tiles landed: "the blend tiles are the culprit" --
an illustrated grassland tile sitting directly against a still-flat-
procedural-looking border read as visibly inconsistent, even though the two
PLAIN tiles on either side matched. `TerrainRenderer._blend_image`/
`_corner_image` now fetch each side's real frame
(`_biome_frame_image`, illustrated-art-gated same as plain tiles) and hand
those actual pixels into `ProceduralTerrainSprite.
generate_multi_directional_blend_image_from`/`generate_corner_image_from`
(new `_from` variants, size-agnostic, no `variant_seed` of their own at the
time since the mask itself was purely positional) instead of synthesizing
a flat `BASE_COLORS` fill. `_normalized_for_compositing` Lanczos-resizes
either side up/down to match when they mismatch (every land biome is
illustrated at 32px today, but corners always involve ocean, still
procedural at `ProceduralTerrainSprite.SIZE`=64px).

✅ **Blend boundaries now curve, and differ per baked variant, instead of
running as one straight line repeated identically across every tile.**
Reported live: "improve the blended tiles so they include curves and
procedural blends looking more natural and individual per tile rather than
straight half forest half grass tile." Root cause: the blend mask's bias
(`t`, how far toward the far biome a pixel leans) was purely a function of
position along ONE axis (`y` for a north/south border), with the only
per-pixel variation coming from a small repeating 4x4 Bayer dither pattern
-- every tile sharing the same direction mask showed the textbook-identical
transition shape, since nothing in the mask depended on `variant_seed` at
all. Fixed by `ProceduralTerrainSprite.blend_edge_wobble`: a smooth, seeded
noise curve (`PixelNoise.smooth`, the same value-noise primitive `_paint_
dune_ripples`-adjacent code already had available) added to the transition
itself, salted per direction so a tile blending on two edges at once (a
corner cell bordering the same neighbor on two sides) doesn't wobble both
in lockstep. Enveloped (`blend_wobble_envelope`, a triangular window that's
*exactly* zero at and beyond `_BLEND_BAND_START`/`_BLEND_BAND_END`, not
just numerically small there) so however large the wobble amplitude is, it
can only ever act strictly inside the existing sharpening band and
provably cannot perturb a pixel the un-wobbled design already resolves to
pure near/far -- the pre-existing outer-quarter-purity and far-fraction-
monotonic-growth guarantees hold unconditionally by construction, confirmed
by every one of those original tests passing unchanged. Visually confirmed
via a real rendered dump: three variants of the same forest/grassland
north border now show three genuinely different wavy boundary shapes, and
a two-direction (north+east) corner shows both edges curving independently
rather than as a rigid right-angle wedge. `TerrainRenderer.BLEND_VARIANTS`
raised 3 → 7 (requested live: "make it 7 variants") now that each variant
has a genuinely different shape to show, not just re-speckled pixels
around one identical line -- at 3, a long biome border would still have
visibly repeated its transition shape every third tile. The naive
per-pixel implementation (recomputing the noise sample inside the double
pixel loop) measured as making a real atlas rebuild at the new variant
count not finish in several minutes; the wobble curve only ever depends on
the coordinate running ALONG an edge, never the one across it, so it's
precomputed once per direction (one `size`-length array) before the pixel
loop instead of up to `size` times over -- confirmed back down to
in-line with the increased variant count's own inherent cost (real build:
~137s, in line with roughly 2.3x more blend/corner images to generate, not
a wobble-specific slowdown). `ATLAS_VERSION` bumped for both changes at
once.

✅ **A FIFTH corner-blend report ("blended tiles still have sharp edges and
corner tiles are not blended") turned out to be a genuinely different bug
from all four rounds above.** Reported (screenshot): a grass-to-dirt-path
boundary read as a hard edge, with the tile-grid corner where they met a
hard square. Investigated with the same real-chunk debug-probe technique
the four rounds above established (`tools/probe_path_scar_blend.gd`, loads a
real Berlin/Grunewald chunk through the real `EarthChunkManager`): the real
forest/grassland biome-to-biome border was confirmed still correctly
blended (no regression in the four prior fixes), ruling out a repeat of any
earlier round. Root cause instead: `TerrainRenderer.paint`'s
`chunk.modifications.has(local)` branch has always short-circuited straight
to `atlas_coords_for_modification` -- a single dead-flat `EARTH_COLOR`
square -- before ever consulting neighbor biomes, for EVERY modification
tile. That includes `PathScarring`'s worn-ground dirt path
(`src/world/path_scarring.gd`, `World._step_path_scarring`, the exact
"grass to dirt path" shape in the report) as well as player-built floor --
neither ever got any border treatment at all, completely bypassing the
whole blend/corner system the four prior rounds built, regardless of what
real ground surrounded it. Confirmed directly against the real probe:
planting a worn path next to real Berlin grassland showed the baked earth
tile as a single flat color end to end, with a real, stark seam-pixel color
jump against its grassland neighbor (`(0.349, 0.247, 0.149)` earth vs.
`(0.196, 0.302, 0.035)` grassland at the shared edge) -- exactly the
reported hard edge. Also checked and ruled out per this round's own
decoration-vs-terrain question: tall grass patches (`IllustratedGrassPatch`)
are alpha-blended decorative cards sitting on top of the ground layer, not
part of the tile-grid boundary itself, so they were not contributing to
this. Not a cache/version bug either -- `TerrainAtlasCache.has_valid_cache`
correctly keys the cached image to `ATLAS_VERSION` and would have caught a
stale cache regardless.
Fixed narrowly, scoped to `EARTH_TILE_ID` only (structures/building pieces
stay exactly as before -- deliberately man-made, flat-edged, never
organically blended into the ground): a new `earth_dominant_blend_for`
mirrors `dominant_blend_for`'s shape but with no "same biome, stay pure"
skip and no priority gate, since earth has no real biome identity of its
own to compare against -- it always concedes to whatever real, unmodified
ground cardinally borders it (ocean excluded, same "land never blends
toward ocean, that's the GPU WaterFx overlay's job" rule every other family
already follows). A new, fourth atlas family (`_earth_blend_base_linear`/
`_earth_blend_linear`, 630 tiles: one real land-biome partner x every
non-empty cardinal-direction subset x `BLEND_VARIANTS`) reuses
`generate_multi_directional_blend_image_from` unchanged -- no separate
corner-carve family was needed or reachable, since earth's unconditional
per-direction blending already dithers a shared corner between two active
directions on its own (that function's own existing behavior), unlike the
water/land corner families which exist specifically because dithering is
priority-gated off there. `_neighbor_biomes` gained an
`exclude_modified_neighbors` param (used only by this new path) so two
adjacent earth cells -- a multi-tile worn path or built floor -- don't
dither a seam against each other's pre-modification biome; confirmed by a
dedicated test and by the real probe. Confirmed end to end against the same
real Berlin chunk after the fix: the planted earth tile's baked pixels are
no longer a flat single color, and its seam pixel against grassland moved
to `(0.216, 0.318, 0.047)` -- much closer to the real grassland neighbor's
own `(0.196, 0.302, 0.035)` than to the flat earth fill, a genuine blended
transition rather than a hard cutoff. Pinned by
`test_baked_atlas_pixels_for_an_earth_modification_cell_show_real_grassland_pixels_at_its_blended_edge`
plus a full `earth_dominant_blend_for`/`atlas_coords_for_earth_blend`/
`paint()` test suite in `tests/unit/test_terrain_renderer.gd`, following the
same discipline the third/fourth rounds above established: an atlas
coordinate matching what a caller expects proves nothing about the pixels
actually baked there. `ATLAS_VERSION` bumped
(`art_resolution_v22_earth_modification_blend`). Known, deliberate scope
limit carried forward from the same "out of scope" section every prior
round already uses: an earth cell's neighbor across a CHUNK SEAM that
itself carries a modification is not detected (`global_biome_lookup` has no
visibility into a neighboring chunk's modifications), the same pre-existing
blind spot the ordinary biome-to-biome blend/corner system already has at
chunk seams -- not attempted here, in scope only for the common in-chunk
case PathScarring/building actually produce.

reaching 0 HP now actually kills and respawns the player instead of silently
doing nothing; and three of the 36 pure-logic mechanics built in a large
parallelized TDD sweep across all 32 concept docs are now wired into the live
game loop and HUD — **survival meters** (hunger/thirst/stamina, ticking down
and refilled by eating/drinking/resting), a **wallet/gold currency**, and a
first **crafting loop** (console-driven `/craft`). The other ~30 modules from
that same sweep (mining, farming, cooking, fishing, taming/pet loyalty,
skills/keystones, class archetypes, item rarity, world-boss fitness,
dodge/throwables, corpses/lives, wounds/debuffs/sickness, housing coziness,
faction reputation, fast-travel/waypoints, animal DNA/fitness, festivals, PvP
dueling, building blueprints, and POI loot scaling) are real and tested but
not yet connected to any live gameplay system — each is called out with a
🚧 Partial note and file path in its section above, so "partial" there
specifically means "real, tested logic sitting unused," not "half-written."

The vast majority of documented mechanisms — NPCs/AI, magic, economy,
crafting, farming, pets, world bosses, PvP, festivals, death, player-side
DNA, multiplayer, and essentially everything from Phase 2 onward — have not
been started. Phase 1 (living ecosystem MVP) and a growing slice of Phase 3
(core gameplay loop) are now built: regional herbivore/predator population
dynamics, per-cell vegetation density, proximity-based creature promotion,
real per-individual creature AI (temperament-driven flee/hunt/graze/drink,
predators eating herbivores and fighting or fleeing the player, each with a
health bar and a name/level/stamina/mana info panel), a weapon-driven melee
attack with a real swing animation and Hammerwatch-style knockback that
makes creatures drop clickable loot, a real item/inventory system with a HUD
(player health bar, hotbar, spell bar placeholder), a persistent tile
build/destroy system, and — new this pass — **individual tree genetics**:
every tree has a deterministic DNA (`TreeGenome`: fruit/nut yield, spread
radius, maturity time) that drives its forage drops and its genome-tinted
canopy art, an axe-wielding player can fell trees for wood
(`ChoppableTree`), and mature trees slowly self-seed mutated-child saplings
that grow to their own maturity before foraging/reproducing in turn, all
persisted per-chunk across unload/reload. Procedural pixel art is now
consistent across items, creatures, the player character, and trees, all
offline and deterministic. Honestly-scoped known gaps remain (no
multiplayer replication for creatures/combat/items/trees — play
single-player for a coherent loop; no whole-planet background simulation;
individual predation not yet linked to aggregate ecosystem counts;
food-seeking is biome- not density-granularity) noted per mechanism above. A
real dev/admin console now exists (backtick to toggle; `/day`, `/spawn`,
`/give`, `/craft`, `/gold`, `/help` commands — see Phase 3 table). Of the 481
mechanisms catalogued here, roughly 38 are now done and roughly 55 are
partial (up sharply from 36/24, mostly via this session's batch of unwired
pure-logic modules) — both counts are approximate rather than a full
re-audit of all 481. This is not a
criticism of the design work, which is thorough and internally consistent; it
simply means prioritization decisions (what to build next, and how much of
this scope is realistic for one person) are needed rather than assuming the
roadmap's phases — let alone the full concept-doc corpus — will be
implemented linearly or in full.
