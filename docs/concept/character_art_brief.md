# Illustrated character building blocks — art brief

A practical spec for the hand/AI-illustrated character parts
`IllustratedCharacterSprite` (`src/rendering/illustrated_character_sprite.gd`)
slices and `CharacterView` wears, replacing `ProceduralCharacterSprite`'s
generated primitive shapes one part at a time. Same pipeline that already
replaced the animal roster's procedural sprites with real art (horse, deer,
boar, sheep — see `IllustratedAnimalSprite` and `docs/progress.md`'s
"Illustrated Species Sprites" row); this is that same machinery pointed at
the player/NPC rig instead.

## Status

| Part | Registry key | Source | Tinted with | Status |
|---|---|---|---|---|
| Torso/tunic | `"body"` | `hero_composite.png`, per outfit row | *(pre-colored — see below)* | ✅ wired |
| Legs | `"legs"` | `hero_composite.png`, per outfit row | *(pre-colored)* | ✅ wired, animated — see "hero_composite.png" |
| Arms | `"arms"` | `hero_composite.png`, per outfit row | *(pre-colored)* | ✅ wired — two poses, one per side (most rows) |
| Head | *(own surface, not `_PARTS`)* | `head.png`, 10×10 grid | `appearance.skin`, by recolor | ✅ wired, player-choosable — 19/100 cells fall back to procedural, see "Head" below |
| Hair | — | — | ⬜ **not built — see "Hair is a known gap"** |
| Decorations | — | — | ⬜ **undefined — see "Decorations" below** |

Every part falls back to the existing procedural texture automatically if
its own art isn't registered/isn't returning frames (`has_part`/
`has_action`/`has_head`/`has_composite_part` checked first, and
`CharacterView`'s callers additionally check the actual returned array isn't
empty — see `_apply_body`'s own comment), so any one part can regress to
procedural without breaking the others.

## Why building *blocks*, not one full-body sheet per class

CharacterView is a paperdoll: separate `Body`/`Head`/`LegLeft`/`LegRight`/
`ArmLeft`/`ArmRight` sprites, composited together. The illustrated pipeline
follows that same seam rather than fighting it — one small set of part
sheets instead of a full hand-illustrated character × 7 classes × 6 skin
tones × 7 hair colors. Two different recoloring conventions coexist here,
though, and it matters which part uses which (see each part's own section
below for why):

- **Neutral, tint-at-runtime** (the original plan): draw a part in flat
  light grey/white with real shading (folds, highlights, an outline) but no
  baked-in hue, and `CharacterView` multiplies it by a class/skin-tone color
  via `modulate`. This is how the FIRST `torso.png`/`leg.png`/`arms.png` were
  drawn, and how any future single-pose part (hair, beard) should still be
  drawn.
- **Pre-colored, `modulate` stays WHITE**: `hero_composite.png` (below) and
  the recolored head texture are already the color they should be by the
  time `CharacterView` receives them — one bakes 8 whole class-colored
  outfits at the source, the other recolors per-pixel by luminance at
  runtime. Applying `modulate` on top of either would double-tint them.

## hero_composite.png: what body/legs/arms actually source from

Body, legs, and arms no longer come from the three separate single-pose
`torso.png`/`leg.png`/`arms.png` files this doc originally specified.
`_PARTS` (the registry those files fed through `has_part`/`generate_textures`)
is now empty; asked directly to use the newly-delivered art ("I added
hero_composite ... use it"), those three parts moved onto a dedicated
surface: `HERO_COMPOSITE_PATH`, `has_composite_part`, `outfit_variant_for`,
`generate_composite_textures`, `composite_part_scale_for`,
`trimmed_composite_image`. The old three files are untouched on disk, just
no longer referenced — `_PARTS`' mechanism is kept working (see "Sheet
format" below) for any future part that only ever needs one neutral pose.

- **8 pre-colored outfits, one sheet.** `hero_composite.png` is
  1024×1536 px: 3 columns (arms, body, legs, left to right) × 8 rows, each
  row a complete, already-colored outfit variant (`HERO_COMPOSITE_ROW_HEIGHT`
  = 192px × `HERO_COMPOSITE_ROWS` = 8). Column boundaries
  (`HERO_COMPOSITE_COLUMN_X`) were measured directly against the real file
  rather than assumed from an even three-way pixel split (1024 doesn't
  divide evenly by 3, and arms' own content sits toward the left of its
  third) — deliberately generous ranges, since `normalize_frames`' own
  crop-to-content step finds the real boundary inside whatever range it's
  given; a range only has to fully contain one column's content without
  touching its neighbour's.
- **Which outfit a hero wears is DNA-derived** (`outfit_variant_for(seed)`,
  `hash % 8`) — asked directly, and answered the same way skin/hair/eyes
  already are: vary by DNA, no new player-choosable axis. This is the
  opposite answer from the HEAD axis below (a real per-player choice) —
  worth remembering as a real asymmetry in this rig, not an inconsistency to
  "fix": a face is a personal identity choice, a class outfit's color isn't.
- **Legs are still a fused pair**, exactly as the original `leg.png` was:
  both legs drawn together as one connected pose, worn as ONE sprite
  covering both `LegLeft`/`LegRight` world slots (`LegLeft` repositioned to
  the midpoint, `LegRight` hidden — `CharacterView._apply_legs`,
  `legs_are_fused()`).
- **Arms are still two independent drawings** side by side with real
  transparent space between them (unlike the fused legs) — found the same
  way `detect_frames`' column-emptiness scan already splits any other
  divided sheet, no exact-rects workaround needed this time (the first
  `arms.png` needed one because its divider was an opaque line; this sheet's
  gap is real transparency). `ArmLeft` gets frame 0, `ArmRight` gets frame 1,
  each measured and scaled independently. **Not every row splits cleanly**:
  row 6 does not produce two frames — `CharacterView._apply_arms` falls back
  to reusing frame 0 for BOTH slots in that case (accepted as a graceful
  degradation rather than fixed at the source; that outfit's arms read
  symmetric instead of independently posed).
- **Column ranges needed real per-row verification, not just row 0.**
  `test_every_outfit_row_produces_the_expected_frame_count` loops all 8 rows
  and checks frame counts — added after this exact class of bug reached the
  live game twice: body row 7's shoulder-cape art cast a detached 11px
  fragment that an over-wide upper bound wrongly counted as a second body
  frame (narrowed 683→660), and legs row 7's real content started at x=670,
  outside an assumed 683 lower bound, so the whole frame silently vanished
  (widened 668). Column bounds are deliberately not a clean three-way split
  of the sheet width for exactly this reason.
- **Only front-facing art exists.** An earlier regenerated version of this
  sheet additionally had a side-profile set; the version currently at
  `assets/sprites/player/hero_composite.png` replaced it with a cleaner
  front-only sheet. `facing` is a real parameter throughout this whole
  surface (`generate_composite_textures`, `composite_part_scale_for`,
  `trimmed_composite_image`), and `_resolved_facing` falls back to `"front"`
  for anything else so a caller asking for "side" today gets a facing hero
  instead of nothing — but no actual side/back art is wired in yet. A
  structured 4-direction (front/back/left/right-profile), 8-outfit-row
  regeneration prompt was written and handed over directly for the user to
  run through their AI art generator, but **has not yet been folded into
  `docs/art/ai_sprite_prompts.md` section 4** (which still describes the
  original single-pose torso/leg/arms/head prompt shape, predating
  `hero_composite.png` entirely) — a real doc gap, flagged here rather than
  quietly left stale. Whoever generates back/side art next should write that
  prompt into section 4 properly rather than relying on it having survived
  in chat history.
- **The walk-cycle gap this doc used to flag is closed, partially.** The
  original `leg.png` version of this doc recorded "illustrated legs stay
  static while walking" as an honest, explicit gap. There is still no real
  per-leg swing art for the fused pair (splitting `leg_swing_offset`'s
  opposite-direction motion across a single sprite would visibly tear it
  into two offset copies of itself), but `CharacterView._process` now gives
  the fused pair a whole-pair vertical bob instead
  (`FUSED_LEG_BOB_AMPLITUDE`, `absf(sin(_cycle_time))` so it dips at every
  footfall rather than once per stride) while `MovementState.WALKING`,
  reported gap: "the legs aren't animated." Reads as "this pair is walking"
  without needing per-leg frames — a real animation, just a coarser one than
  true per-leg swing art would give.

## Four bugs that made correctly-wired art still look broken

Getting a part registered and correctly SIZED (the sections above) turned
out not to be sufficient — reported live, repeatedly, after all of the
above had already landed: "still no legs," then "back to the old procedural
version," then "no neck; head is floating and no legs." The actual causes
were two independent bugs neither of which was about size or wiring at all:

1. **A stray fragment stacked below the real garment, inside the same
   column range.** `detect_frames` only ever splits on COLUMN gaps (see its
   own doc comment) — it hands back one rect spanning the FULL row height
   regardless of what's actually drawn in it, on the assumption that one
   column-separated blob is one frame's whole vertical extent.
   `hero_composite.png`'s rows break that assumption: several hold a
   second, unrelated close-up (a belt buckle, a shoulder pauldron) below
   the real garment at x-coordinates landing inside that same column range,
   with a real gap of empty rows between the two. `_content_rect`'s plain
   min/max bounding-box scan then welds them into one contaminated frame —
   inflating the measured content height `composite_part_scale_for` scales
   against (shrinking the real garment further than intended) and painting
   a second object below it. Measured directly by dumping every row as a
   real PNG: 6 of legs' 8 rows and 6 of body's 8 rows carried this, only
   rows 0 and 7 of each were clean. Fixed by
   `IllustratedCharacterSprite._primary_content_rect`, clipping a
   column-matched rect to just its first contiguous run of non-empty rows
   before normalizing — the real garment was always the topmost run in
   every row observed, so no tuned gap-size threshold was needed, just the
   same single-empty-row-is-a-divider convention `detect_frames` already
   applies to columns. Pinned per-row, both parts, by
   `test_every_outfit_rows_legs_have_no_fragment_stacked_below_a_gap` and
   its body counterpart (`test_illustrated_character_sprite.gd`).
2. **Sprite2D centers the padded CANVAS on `.position`, not the visible
   CONTENT.** True content-center-at-position semantics for the old flat,
   padding-free procedural art, but every hero_composite/head part
   normalizes onto a canvas taller than its own content, with that content
   baseline-anchored near the canvas's BOTTOM (see "Every part gets its own
   measured scale" below) — so most of a part's padding sits above its
   content, not evenly around it. Left uncorrected, a part's art renders
   noticeably LOWER than `.position` alone suggests. For body specifically
   this pushed the torso down far enough to fully cover the (by-then
   correctly-sized) legs, and shifted the head/body relationship enough to
   read as a floating, disconnected head. Fixed by
   `CharacterView._composite_content_offset_y`, which back-derives a part's
   own measured content height from the scale already computed for it
   (`target_world_height / scale`, avoiding a second image scan) and sets
   `Sprite2D.offset` so the content's own center — not the canvas's — lands
   on `.position`. Applied to body/legs/arms and the head alike (the head's
   own smaller canvas has the same padding-asymmetry shape, just less
   pronounced).

Neither bug was caught by the existing "every outfit row produces the
expected FRAME COUNT" test — a contaminated frame is still exactly one
frame, and a mispositioned one still renders, just in the wrong place.
Both needed actually looking at rendered pixels (dumped composites,
per-row crops) to catch, not just checking that a texture existed. A third,
unrelated, pre-existing bug (see "Head" below) surfaced the same way.

Fixing the occlusion surfaced two more, both reported live once legs and
head were actually visible for the first time:

3. **Body rendered roughly 2x too wide** ("proportions are awfully wrong").
   `composite_part_scale_for` matches CONTENT HEIGHT to `BODY_SIZE.y` alone,
   then `CharacterView` applies that one scale to width too — correct only
   when the source art's aspect already matches `BODY_SIZE`'s own 13:19,
   which the old flat rectangle satisfied by construction but
   hero_composite.png's torso (short sleeves baked into the same
   silhouette) does not: measured at 64×47 for the most common outfit row,
   noticeably wider relative to its height. Fixed two ways together:
   `CharacterView._width_bounded_scale` clamps to whichever of width/height
   is more constraining (the same "fit inside a box, preserve aspect" rule
   `normalize_frames` already applies one step up), and `BODY_SIZE.x` was
   widened 13→26 (measured from that same row's real content, `19 * 64/47`,
   not eyeballed) so the common case still renders at its full intended
   height instead of being squished by its own new clamp. Scoped to body
   alone — legs/arms/head have smaller aspect mismatches that the same
   clamp would "fix" by shrinking their height for no visible gain.
4. **Arms were invisible outside swimming** ("no hands are visible") — a
   leftover from when the flat procedural torso was wide enough to visually
   stand in for a whole upper body, arms included; hero_composite.png's
   torso stops at the shoulder, so that assumption silently cost every
   standing/walking hero their hands. Arms now stay visible in every
   movement state (only the STROKE animation itself stays gated to actually
   swimming) — which combined with fix 3 above (a body wide enough to
   horizontally overlap where `ArmLeft`/`ArmRight` sit) meant the torso's
   own sleeve fabric started painting over the hands the moment they became
   visible, since Arms drew after Body in the `.tscn`'s child order. Fixed
   by reordering Body before Arms so a hand is always painted in front of
   the torso, not by narrowing the body back down.

## Head

Unlike body/legs/arms, head art is **not** a neutral sheet and is **not**
exposed through `has_part`/`generate_textures` at all — it has its own
surface, `has_head()`/`generate_head_texture(cell_index, skin_tone)`/
`head_scale_for`. The delivered `head.png` is a 10×10 grid
(`HEAD_GRID_COLUMNS`/`HEAD_GRID_ROWS`) of 100 fully-painted faces (bald, one
baked skin tone, solid near-black background, no alpha channel).

- **Which face is a real player choice, not derived from DNA.** This
  reversed once already: the first version picked one of the 100 cells
  deterministically from the hero's seed with no browsing UI, on the theory
  that a face is "just" cosmetic variation like skin/hair/eyes. Reported
  directly after seeing it live ("you can't choose different heads") — faces
  are personal identity, unlike a class's outfit color, and a face someone
  actively picked and liked shouldn't reroll out from under them on a DNA
  change. `"head"` is now a real entry in `HeroAppearance.AXES`, with its
  own `option_count` (`HEAD_GRID_COLUMNS * HEAD_GRID_ROWS`, read from the
  art rather than a second hardcoded 100 so the two can't drift), cycles
  like every other creator axis, and round-trips through
  `appearance.head_index`. `appearance_for`'s DNA-rolled path still rolls a
  head index for a hero nobody hand-authors (an NPC, a freshly-randomized
  creator preview) — only the creator's own cycling is a genuine player
  choice; a roll is still the right default absent one.
- **Recoloring** is unchanged from the original plan: `head.png`'s baked-in
  skin tone is discarded and repainted toward the hero's own
  `appearance.skin`, by LUMINANCE ONLY (`_recolor_by_luminance`) — the same
  trick `ProceduralFlowerSprite._paint_illustrated_head` proved on
  illustrated blooms (`flora.md`'s "Recolouring illustrated blooms"): read
  the source as light/shade only, discard its hue, repaint the target tint
  at that same brightness. No accent-hue mask separates eyes from skin —
  eyes are dark/low-luminance enough to still read as a visibly darker patch
  of whatever tone the recolor lands on, just not independently colored. A
  real eye-color mask is a legitimate follow-up, not attempted.
  `HEAD_SHADE_FLOOR`/`HEAD_MINIMUM_PEAK_LUMINANCE` (both 0.35) keep the
  darkest linework from multiplying to a black hole and a shadow-only source
  region from blowing out white, mirroring the flower sprite's own
  `ILLUSTRATED_SHADE_FLOOR`/`MINIMUM_PEAK_LUMINANCE`.
- **Background removal is a border-connected flood fill, not a flat
  chroma-key.** The sheet has no alpha channel and a near-pure-black
  background, but the transition into a face is a wide, gradual 20–30px
  blur, not a crisp cut. A flat per-pixel distance-from-black chroma-key was
  tried first and either left a visible dark halo around every face (tight
  tolerance — reported: the recolored head rendering as a dark block) or
  risked punching a hole through a genuinely dark part of a face — an eye —
  wherever it happened to also fall within tolerance of black (loose
  tolerance). `_remove_background_by_flood` floods inward from the four
  canvas edges instead, stepping only to a 4-connected neighbour within
  `HEAD_BACKGROUND_FLOOD_STEP_TOLERANCE` (0.02, mean per-channel RGB
  difference) of the pixel that reached it — it rides the gradual blur all
  the way to where real content begins but can never cross INTO the
  content's interior, since doing so would require one big step across the
  content's own edge, which the per-step tolerance refuses. A flat
  distance-from-a-fixed-color key can't make that distinction: it treats a
  coincidentally dark pixel in the middle of a face exactly like real
  background, because it never looks at what a pixel is connected to. 0.02
  was reached by sweeping 0.02–0.18 against 7 sample cells with a throwaway
  visual-diff harness — most cells hold a stable ~33–42% opaque from 0.02 up
  to a per-cell cliff between 0.06–0.10 where retention collapses, but two
  darker-toned cells (rows 8–9) show no clean plateau at all, so 0.02 is the
  conservative value that holds a complete face on every sampled cell,
  including those two.
- **Scale**: the head is normalized onto its own `HEAD_CANVAS_SIZE`/
  `HEAD_BASELINE_Y` (24×24), separate from body/legs/arms' shared 64×96
  `CANVAS_SIZE`/`BASELINE_Y` — a head isn't a ground-contact-anchored
  standing limb, it's anchored where the neck meets the torso.
  `CharacterView._apply_head` scales it via `head_scale_for`, the same
  measure-the-actual-drawn-content approach `part_scale_for`/
  `composite_part_scale_for` use for every other part (see "Every part gets
  its own measured scale" below).
- **19 of the 100 cells' flood fill fails, two opposite ways.** A
  pre-existing bug, unrelated to the four under "Four bugs that made
  correctly-wired art still look broken" above — surfaced incidentally
  while dumping test seeds for visual proof of THOSE fixes. The original
  0.02 tolerance sweep (above) only sampled 7 of the 100 cells; two full
  100-cell surveys done alongside this pass found:
  - **7 cells erode almost the entire face** (all but one landing in the
    sheet's own column 1 — a systematic pattern, not per-cell noise, though
    the exact cause wasn't chased down here): flood retains ≤8.3% opaque
    content, against a comfortable margin for every other cell. Left alone
    this reaches the live game as a huge, nearly blank, wildly oversized
    texture — `head_scale_for` dividing a target height by a near-zero
    measured content height — reported live as "a floating translucent
    smear where a face should be."
  - **12 more cells never have their background removed at all** (a
    contiguous block, rows 1-2 columns 3-8): opaque fraction ~1.0.
    Consistent with the flood's own border-walk approach — if a cell's face
    art touches or crosses the cell's own edge with no background margin,
    the flood has nowhere to start from and leaves the whole square
    untouched. Reported live as a dark rectangle where a face should be.
  Neither root-caused here (that needs either a smarter per-cell flood or
  fixing the source art's own margins); instead given the same
  has-X-then-fallback safety net body/legs/arms already lean on for their
  own per-row gaps: `IllustratedCharacterSprite.has_usable_head(cell_index,
  skin_tone)` now checks BOTH bounds (opaque fraction ≥15% and ≤97%) and
  gates both `CharacterView._apply_head` and the portrait's
  `_portrait_head_image`, so all 19 cells fall back to the procedural head
  instead of showing a broken one. A hero who rolls or picks one of the 19
  sees a plainer procedural face, not their chosen illustrated one — a
  real, visible gap, affecting close to 1 in 5 possible faces, just a far
  smaller defect than a smear or a solid block.

## Hair is a known gap

`head.png`'s 100 faces are all bald. There is no hair overlay art, so an
illustrated hero currently reads bald **regardless of the DNA-picked
`hair_style`/`hair` color** — those axes still exist and still work for the
procedural head, they simply have nothing to draw against once the
illustrated head is active. This was a deliberate choice (asked directly:
overlay the old procedural hairstyles on the new head shape, or ship bald-
for-now?) — bald-for-now won, because the existing procedural hairstyles
were drawn to fit the OLD procedural head's silhouette, not this one, and a
mismatched overlay would look worse than an honest gap.

**To close this gap**: a hair sheet needs to be drawn to align with THIS
head art's actual silhouette (not reused from `ProceduralCharacterSprite`),
per `HeroAppearance.HAIR_STYLES` (short, swept, long, ponytail, topknot —
bald needs no overlay), neutral grey/white so it can be tinted by
`appearance.hair` the same way the original neutral-part convention works —
i.e. a genuine SECOND illustrated layer composited on top of (or in place
of) the recolored head, not a change to `head.png` itself. A beard overlay
per `HeroAppearance.BEARD_STYLES` (stubble, goatee, full — none needs no
overlay) is the same shape, lower priority.

## Decorations

Mentioned alongside hair as "still missing" when this pass was scoped, but
**what it should actually cover is not yet defined** — asked directly and
the answer was "no idea yet." Not attempted here. Whoever picks this up next
should pin down the concept first (small illustrated head/face accents like
face paint or jewelry? equippable cosmetic items beyond the existing
`HeadSlot`/`ToolSlot`? something else?) before generating art or registering
anything.

## Every part gets its own measured scale, not one flat constant

`IllustratedCharacterSprite.CANVAS_SIZE` (64×96, shared by body/legs/arms) is
one working RESOLUTION every part is normalized onto — not a claim that a
torso and a leg pair are the same real size. `part_scale_for`/
`composite_part_scale_for(part_name, variant, target_world_height,
frame_index, facing)` both measure the ACTUAL opaque-pixel content height of
the generated frame and return the scale that maps it to the part's real
world height (`CharacterView.BODY_SIZE`/`LEG_SIZE`/`ARM_SIZE`).
`head_scale_for` is the same idea for the head's own canvas.
`CharacterView._apply_paperdoll_part`/`_apply_head`/`_apply_body`/
`_apply_legs`/`_apply_arms` apply this per part instead of the flat
`ArtResolution.SPRITE_SCALE` the procedural fallback still uses (that
constant only ever worked because the procedural generator draws AT EXACTLY
its target art size with no padding — illustrated art, normalized onto a
shared padded canvas, essentially never does).

## Sizing against the world: the legibility compromise

`CharacterView.TARGET_HEIGHT_FRACTION_OF_TREE` (how tall the whole hero
reads against a full-grown tree) was raised from the original 2/3 to 0.85
once this illustrated art replaced the old flat-color procedural parts.
2/3 was fine for flat single-color shapes, but at that scale a leg's own
measured content rendered at roughly **4 on-screen pixels tall** — reported
as "legs are not wired" (they were; detailed shaded art just doesn't survive
that downscale the way a single flat color does, it smears into a muddy
blob that blends with the ground). Asked directly how to fix it (raise the
whole character's size vs. legs specifically): raising the whole character
keeps every part's proportions, and every part's own legibility, consistent
— not just legs'. At 0.85 the same leg content renders at roughly **5.4px**.
This is a real compromise, not a full fix: it deliberately stays short of
1.0 (as tall as a tree) to preserve the ORIGINAL reason this constant exists
(the character reads visibly smaller than the trees around it), which caps
how far this lever alone can go. The art itself was drawn assuming a larger
viewing size than this project's tile-scale budget affords; closing that gap
the rest of the way (bigger source canvases, or a coarser/bolder art style
that survives downscaling better) is a real follow-up, not solved here.

## Sheet format (for any NEW single-pose part — hair, beard overlays, etc.)

The `_PARTS`/`has_part`/`generate_textures` mechanism above is still real
and tested, just currently unpopulated — it's the right shape for any part
that only ever needs ONE neutral pose (no outfit-variant or facing axis),
the way a hair or beard overlay would.

The original `torso.png`/`leg.png`/`arms.png` had real, usable alpha
channels (measured directly, not assumed from the animal pipeline's
magenta-chroma-key convention) — real transparency where the AI generator
actually produced it. If future single-pose art comes back the same way, no
`chroma_key` entry is needed; if it comes back solid-background instead (as
`head.png` did), key it out explicitly — `_apply_chroma_key` for a uniform
background, or the border-flood-fill approach (see "Head" above) for a
background with a soft/gradual edge into the content. Don't assume either
convention, measure the actual file (see `docs/progress.md`'s entry on this
pass for the Node.js probing approach used, since Python isn't on PATH in
this environment).

- **Frame dividers, if a sheet holds several poses**: a real transparent gap
  lets `detect_frames` find the boundary automatically (`"<action>_bands"`).
  An OPAQUE divider (a drawn line) defeats that scan — give exact pixel
  rects instead (`"<action>_rects"`, see `_load_frames`).
- **Canvas**: no fixed pixel size required from the generator — whatever
  resolution reads clearly. `SpriteSheetSlicer.normalize_frames` crops to
  the actual drawn content and rescales onto `IllustratedCharacterSprite
  .CANVAS_SIZE`/`BASELINE_Y` (body/legs/arms) or `HEAD_CANVAS_SIZE`/
  `HEAD_BASELINE_Y` (head) automatically.
- **Orientation**: draw facing the VIEWER (front-on) to match every part
  currently registered — not facing right, which this doc previously
  specified before any art existed to check against. There is still no
  per-part facing override in the `_PARTS` mechanism (unlike
  `hero_composite.png`'s own `facing` parameter, or some animal sheets,
  which declare `faces_left` per species) — a future single-pose sheet drawn
  in profile would need that option added.

`hero_composite.png` (body/legs/arms' real current source) is a different,
richer format than the above — see its own section further up for the
row-per-outfit, real-alpha-gap-per-frame, `facing`-parameterized shape it
actually uses, and how its column ranges were calibrated.

## File locations

The current art lives at `assets/sprites/player/hero_composite.png` (body,
legs, arms — 8 outfit rows) and `assets/sprites/player/head.png` (100
faces). The original `assets/sprites/player/{torso,leg,arms}.png` files
this doc first specified are still present on disk but no longer referenced
by any code path — kept only because `_PARTS` (see "Sheet format" above)
could still point at them if ever needed again. This is NOT the
`assets/sprites/character/{body,legs,arms}_idle.png` layout this doc
originally proposed before any art existed. Follow the
`assets/sprites/player/` location for any new part (hair, beard,
decorations, back/side-facing hero_composite regeneration).

## How to register a finished single-pose part (`_PARTS`)

Add an entry to `IllustratedCharacterSprite._PARTS`, mirroring
`IllustratedAnimalSprite._SHEETS`:

```gdscript
const _PARTS := {
	"hair": {
		"path": "res://assets/sprites/player/hair.png",
		"idle_rects": [Rect2i(0, 0, 1254, 1254)],  # measured from the real file, not guessed
	},
}
```

`has_part`/`has_action` (and `_apply_paperdoll_part` in `character_view.gd`)
pick this up automatically — no other code changes needed for a part that
fits the neutral-single-tint shape. A part that needs its own recolor
mechanism (multi-color source art with its own baked shading) needs a
dedicated surface instead, the same way head does — see "Head" above for the
shape to copy. A part that needs a variant axis (like hero_composite's 8
outfit rows) or a `facing` axis needs a dedicated surface too — see
"hero_composite.png" above.
