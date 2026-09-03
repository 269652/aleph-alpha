# AI sprite-generation prompts

Reference prompts for producing illustrated source art that feeds this
project's existing ingestion pipeline (`SpriteSheetSlicer`, proven on
`assets/sprites/horse.png`/`deer.png`/`boar.png` — see
`illustrated_animal_sprite.gd`). These generate PARTS/STATES that the engine
composites and recolors procedurally — not fully pre-composed final sprites.

## One kit per ARCHETYPE, not per species

Head shape (cup/layered/spike/puff) is what's structurally different
between species; color (`FlowerSpecies.color_for`) and size
(`height_tiles`) are already data-driven per species and applied at
runtime. So: 4 archetype sheets + 1 shared stem/leaf sheet covers every
current species (crocus/tulip→cup, rose→layered, lavender→spike,
clover→puff), and a new species later needs zero new art — just a data
entry. Only give a species its own head art if reusing an archetype
genuinely looks wrong in-game; don't pre-emptively split per species.

## Generating with Nano Banana (Gemini image model) specifically

- **It will not output a true crisp pixel grid from one prompt** — like
  every current image model it renders a "pixel art aesthetic" with some
  softened/anti-aliased edges even when explicitly told not to. Plan on a
  mandatory post-process: nearest-neighbor downscale to target resolution,
  then palette-quantize. The prompt wording still reduces cleanup needed,
  it just won't eliminate this step.
- **For the 4-stage bloom progression, use multi-turn editing instead of a
  single one-shot 4-panel prompt.** Nano Banana is strong at image-to-image
  identity consistency across a conversation. Generate stage 1 (bud), then
  in the next turn say "same flower, same style and palette, now show it
  opening further" and repeat for stages 3–4, rather than asking for all 4
  in one image from scratch — this keeps the SAME flower recognizable
  across the row instead of 4 different-looking blooms. Composite the 4
  results into one divided sheet as a final step (either manually or by
  asking Nano Banana to lay out the 4 already-generated images into a
  divided grid in one more turn).

## Shared style preamble

Prefix every prompt below with this block (or your generator's system/style
setting). Revised after the first "cup" bud attempt came back as a fully
open bloom, on a white (not transparent) background, with smooth gradient
shading instead of flat pixel bands:

> 8-bit top-down pixel art, in the style of a 16-bit-era top-down farming/
> adventure game (Stardew Valley-adjacent, not isometric). SHADING: strictly
> POSTERIZED/flat-banded — each surface uses ONLY 3 distinct flat color
> values (one base tone, one lighter highlight band, one darker shadow
> band), with a hard visible edge between each band. NO smooth gradients,
> NO airbrush blending, NO soft transitions anywhere. Crisp pixel edges
> throughout. BACKGROUND: flat solid magenta (#FF00FF), no scene, no
> ground, no shadow under the subject — solid magenta is a chroma-key
> placeholder to be removed afterward, do not soften or vignette it. Single
> consistent light source from the upper-left across the whole sheet.
> Orthographic top-down/near-top-down perspective, not a 3/4 isometric
> angle. No drop shadow baked into the art — the engine renders its own
> shadow separately.

(Using solid magenta instead of asking for "transparent background"
because the latter was ignored and returned plain white — a flat,
saturated, unusual color that won't otherwise appear in the art is a more
reliable target for a chroma-key removal pass afterward than hoping the
model actually outputs alpha.)

## Ingestion format (apply to every multi-cell sheet)

- Lay out multiple poses/stages/frames on ONE image, left-to-right within a
  row, multiple rows stacked for different categories.
- Separate every cell with a **thin, near-white or light-gray 1–2px divider
  line** (a straight rule, not a decorative border) — `SpriteSheetSlicer`
  auto-detects content by excluding near-white/gray low-saturation pixels
  above ~0.7 brightness as divider, so keep dividers clearly lighter/grayer
  than any real art in the frame.
- Frames do NOT need to be uniform width — the slicer detects each frame's
  own tight content bounding box. Leave generous empty space around each
  pose so nothing touches the divider lines or canvas edge.
- Export at high resolution (at least 512px per row-height) — this gets
  downsampled into the game's actual pixel grid; more source detail gives
  the downsample cleaner edges, it does not skip the pixel-art look.

---

## 1. Flower building blocks

Existing species → archetype mapping (recolored per species at runtime):
`crocus`→cup, `tulip`→cup, `rose`→layered, `lavender`→spike, `clover`→puff.

### 1a. Stem + leaves sheet (shared across all species, tinted green)

Single-turn prompt (no multi-turn needed — the 3 variants aren't a
progression, so identity drift across them doesn't matter):

> Pixel art sprite sheet of a single flower stem with two small leaves,
> shown as 3 slight variations side by side, each separated by a thin
> 1–2px near-white divider line: (1) straight stem, (2) leaning left ~15°,
> (3) leaning right ~15°. Thin green stem rising from the bottom of the
> frame in each, two small pointed leaves attached partway up on
> alternating sides. Rendered in a mid-tone green with visible darker-green
> hard-edged shading on one side for form. No flower head — stem and
> leaves only, cropped at the top where the bloom would attach. Transparent
> background, flat limited palette, hard pixel edges, no anti-aliasing
> blur, no photorealism.

### 1b. Head archetype sheet — one sheet per archetype, 4 bloom stages each

Generate **4 separate sheets**, one per archetype below (cup, layered,
spike, puff). For EACH archetype, run this as a 4-turn conversation with
Nano Banana (see multi-turn note above), then a 5th compositing turn:

**Turn 1 (bud) — revised, first attempt came back as a full open bloom:**

> Pixel art of a single flower BUD — CRITICAL: this is a bud that has NOT
> opened at all yet, not a partially or fully open flower. The petals must
> be TIGHTLY WRAPPED AROUND EACH OTHER with NO gaps, NO visible individual
> petal edges, and NO separation between petals — from the outside it
> reads as ONE SINGLE SMOOTH ENCLOSED SHAPE, like a closed almond or
> teardrop, not a cluster of separate petal shapes. Overall silhouette
> narrower and taller than it is wide — roughly 1:1.5 width:height. No
> interior detail is visible at all since nothing has opened yet. Small
> green sepal (the little leaf-like base) at the very bottom where it
> would attach to a stem. Top-down/near-top-down perspective. Petals
> rendered in a PALE, near-white/cream base tone — NOT a saturated color,
> this will be color-tinted afterward in a game engine. This is the FIRST
> of a 4-stage opening sequence, so it must look meaningfully MORE closed
> than a normal illustration of this flower — err tighter/smaller/more
> closed than feels natural. [ARCHETYPE DESCRIPTION — for the bud stage
> only, treat this as describing what shape it will grow into once open,
> not what's visible now.]

**Turn 2 (opening):** *"Same flower, same exact style and palette, now show
it just beginning to open — petal tips becoming visible as the bud starts
to unfurl. Keep it recognizably the same flower."*

**Turn 3 (full bloom):** *"Same flower, same style and palette, now fully
open at maximum size, warm pale-yellow pollen-colored center visible."*

**Turn 4 (spent):** *"Same flower, same style and palette, now spent and
drooping — petals curling and browning slightly at the tips, whole head
tilted downward as if wilting."*

**Turn 5 (composite):** *"Lay out the 4 images you just generated
(bud, opening, full bloom, spent, in that order) side by side in one row
on a single image, each cell separated by a thin 1–2px near-white divider
line, generous transparent padding around each flower so nothing touches
the dividers or edges."*

If the compositing turn doesn't lay them out cleanly, composite the 4
exported images manually instead — that's a normal fallback, not a sign
something went wrong.

Archetype descriptions to substitute for `[ARCHETYPE DESCRIPTION]`:

- **cup**: "Shape: a shallow open cup of 5–6 broad rounded petals, like a
  tulip or crocus — petals curve gently outward from a central point, no
  overlap."
- **layered**: "Shape: a dense layered rose-like bloom — many small
  overlapping petals spiraling from the center outward in 2–3 visible
  layers, fuller and rounder than the cup shape."
- **spike**: "Shape: a tall narrow spike of many tiny individual florets
  clustered tightly along a vertical axis, like lavender — read as a
  texture of small bumps, not individual large petals."
- **puff**: "Shape: a soft round puffball of many tiny thread-like petals
  radiating from the center in all directions, like a clover or dandelion
  bloom — fluffy silhouette, no single petal reads individually large."

---

## 2. Root/tuber crops — composite harvest kit (carrot, potato)

**Genuinely composite, not one artist's guess at "grown carrot"** — the
same "parts the engine assembles" philosophy section 1 uses for flowers
(archetype heads + one shared stem sheet), applied to harvest crops. Only
**3 static parts total**, and one of them isn't even per-crop:

1. **Leaves above earth** — the only thing visible while the plant is
   still planted, growth-staged, transparent background, no soil baked in.
2. **A pile of earth** — ONE shared asset, not per-crop (dirt looks the
   same regardless of what's growing in it): the soil mound the leaves
   sit in while planted, and the disturbed/broken look left behind once
   something's been pulled out of it.
3. **Root/tuber — the actual food item** — never rendered while planted;
   this is what harvesting exposes and what ends up in the player's
   inventory. This is where carrot and potato genuinely differ in
   silhouette (one long taproot vs. a loose cluster of round tubers, real
   botanical difference — a potato tuber is a swollen underground *stem*,
   not a root at all), so each gets its own prompt.

**No separate "pull" art.** An earlier draft of this section asked for a
3-turn mid-pull action sequence (soil cracking, root half-emerging,
mid-lift pose) — dropped. That's exactly the kind of motion this codebase
already handles as a runtime tween over static parts rather than baked
animation frames (the same way `Knockback.step` animates a hit, not a
drawn frame per displacement): leaves+root rise together while the soil
sprite swaps to its disturbed look, no art needed to depict the motion
itself, and it removes the single riskiest ask in the original prompt set
(a generator drawing a coherent mid-action pose with correct partial
occlusion is far less reliable than 3 independent static poses).

### 2a. Leaves above earth, 3 growth stages (shared template)

> A pixel-art sprite sheet showing [CROP] leaves at 3 growth stages, side
> by side in one row, viewed top-down/near-top-down: (1) SEEDLING — a tiny
> pale-green sprout, minimal leaf structure; (2) VEGETATIVE — [CROP LEAF
> DESCRIPTION], roughly half mature height; (3) MATURE — [CROP LEAF
> DESCRIPTION] at full height and fullest volume, ready-to-harvest size.
> Leaves and stems only — NO soil, NO ground, NO root or tuber visible at
> any stage; each stage is an isolated plant on an empty background, to be
> composited onto a separate soil sprite by the game engine. [style
> preamble] [ingestion format]

Fill-ins for `[CROP LEAF DESCRIPTION]`:
- **carrot**: "a rosette of 4–6 thin, feathery, fern-like fronds fanning
  upward and outward, fine lacy leaf texture, bright green"
- **potato**: "a cluster of upright leafy stems with broad compound leaves
  (several oval leaflets per stem, visible leaf veins), noticeably bushier
  and denser than the carrot's fronds, medium-dark green"

### 2b. Pile of earth (shared across every crop — generate once)

> A pixel-art sprite sheet of a small mound of tilled soil, viewed
> top-down/near-top-down, shown in 2 states side by side: (1) UNDISTURBED
> — a neat rounded mound of dark brown soil, smooth surface, something is
> planted in it; (2) DISTURBED — the same mound broken open, a shallow
> loose-soil crater with a few small clods and crumbs scattered just
> outside its rim, as if something was just pulled straight up out of the
> center. Same mound size/footprint in both so they can be swapped in
> place under a plant sprite. No plant, leaves, or root included — soil
> only. [style preamble] [ingestion format]

### 2c. Root/tuber — the harvested food item itself, isolated

> A single pixel-art sprite of one harvested [CROP] [ROOT/TUBER NOUN],
> viewed top-down/near-top-down, lying at a slight diagonal angle, not
> perfectly horizontal or vertical. [ROOT/TUBER DETAIL]. A few small
> clumps of dark soil clinging to it. No leaves attached — root/tuber
> only, isolated subject. [style preamble]

Fill-ins:
- **carrot** — `[ROOT/TUBER NOUN]`: "tapered root"; `[ROOT/TUBER DETAIL]`:
  "Bright orange, smooth tapered cone shape narrowing to a fine point,
  subtle horizontal texture rings along its length, a few thin pale root
  hairs branching off near the wide end, small dark leaf-scar at the top
  where it met the stem"
- **potato** — `[ROOT/TUBER NOUN]`: "tuber cluster"; `[ROOT/TUBER DETAIL]`:
  "A loose cluster of 3 oval tubers of slightly different sizes, joined by
  1–2 short pale stolon strands (thin underground stems, not roots) —
  each tuber pale tan-brown with a rough dimpled skin texture and a few
  small dark 'eyes' (dormant sprouting points), no single tuber larger
  than a third of the whole cluster's width so it reads as a cluster of
  several tubers, not one big lump"

### 2d. How the pull assembles at runtime (implementation note, not a prompt)

Planted: soil (2b, undisturbed) with leaves (2a, current growth stage)
layered on top, root/tuber (2c) hidden entirely (not drawn, or z-ordered
behind the soil). On harvest: swap soil to its disturbed state, tween the
leaves+root group upward/out over a short duration so the root becomes
visible as it clears the mound, then hand off into the pickup/inventory
flow. 3 static images, one short position tween — no additional art.

### 2e. Inventory icon

> A single pixel-art icon of one [CROP] [ROOT/TUBER NOUN], [ROOT/TUBER
> DETAIL, abbreviated if needed for a small icon], centered and upright,
> viewed from a clean 3/4 front angle suitable for a game inventory slot
> icon. Bold clean silhouette that reads clearly at small size.
> Transparent background, no cast shadow. [style preamble]

### 2f. Held/carried, 4 directions

This produces the ITEM only (not the character) — the engine layers this
over the existing player sprite per facing, matching
`character_view.gd`'s `Facing` enum (`DOWN, UP, LEFT, RIGHT`; no
diagonals). Uses the root/tuber part alone (2c), not the whole plant.

> A pixel-art sprite sheet of a single [CROP] [ROOT/TUBER NOUN] object,
> shown 4 times in one row, each oriented as if being held out by an
> unseen hand in a different facing direction: (1) DOWN — pointing toward
> the viewer/downward; (2) UP — pointing away/upward; (3) LEFT — oriented
> horizontally pointing left; (4) RIGHT — oriented horizontally pointing
> right, mirror of LEFT. Same [CROP] design in all 4, only the orientation
> changes. No hand or arm included — the [ROOT/TUBER NOUN] object only.
> [style preamble] [ingestion format]

---

## 3. Terrain ground tiles — DONE, real art registered

Base ground fill for each biome (see `ProceduralTerrainSprite`/
`TerrainRenderer`, `docs/concept/art_resolution.md`), picked per-tile-position
the same seeded-index way `IllustratedStoneSprite` already picks a
pebble/boulder variant, so a wide stretch of the same biome doesn't read as
one texture repeating. `BiomeClassifier.KNOWN_BIOMES` names seven biomes;
every LAND biome has a real registered sheet (`IllustratedTerrainSprite`) --
`assets/sprites/terrain/{grass,forest,desert,mountain,tundra,rainforest}.png`.
**Ocean stays on the procedural path** — see the note at the bottom on why.

### It's 3x3 (9 variants), not the originally-targeted 5x5 (25)

The prompt below originally asked for a strict 5x5 grid. In practice the
model reliably held a real GRID of SQUARE tiles only at 3x3 — a 5x5 attempt
came back as 7 uneven tall vertical strips instead of a grid at all (wrong
shape AND wrong aspect ratio, unusable for a full-bleed tile). 3x3 worked on
the first attempt once the prompt explicitly named a square grid rather than
just "5x5 sheet". `IllustratedTerrainSprite.frame_for`'s seeded pick still
spreads well across a 9-variant pool (see
`test_frame_for_spreads_across_variants`); if a future prompt attempt reliably
lands 5x5 or larger, `TerrainRenderer.VARIANTS_PER_BIOME` can go back up to
match — it's a plain constant, not hardcoded to 9 anywhere else.

### Ground tiles are full-bleed, not isolated objects — read before prompting

Every other sheet in this document (stems, flower heads, carrots) is an
ISOLATED subject on an empty background, cropped tightly by
`SpriteSheetSlicer`'s content-bounding-box detection. A ground tile is the
opposite: the **entire cell is opaque content, edge-to-edge, with no
padding and no background to key out inside the cell** — only the thin
divider lines between cells, and any margin around the outside of the whole
grid, use the magenta convention. Say this explicitly in the prompt or the
model will "helpfully" vignette/fade each tile's edges the way it would for
an isolated object, which breaks tiling.

One real wrinkle this surfaced: these sheets' divider lines carry a visible
soft glow/anti-aliasing that never reaches pure `#FF00FF` across most of
their own width — a strict "near pure magenta" chroma-key (the same
threshold that works fine on pebbles.png/boulders.png) missed most of a
divider's width and merged neighboring cells together. `IllustratedTerrainSprite`
uses a looser threshold for terrain specifically (`MAGENTA_SKEW_MIN`: how far
the red/blue average sits above green, rather than a strict per-channel
minimum) — expect the same if prompting more sheets with a soft-edged
divider style.

### Seamless tiling — the one hard, new requirement

A ground tile has to repeat edge-to-edge against a copy of itself with no
visible seam: **the left edge must match the right edge, and the top edge
must match the bottom edge** (this is what "tileable"/"seamless" means to
an artist, and it's worth spelling out literally rather than assuming the
model knows the term). This is a genuinely harder ask than anything else
in this doc — expect the first pass to have visible seams at some cell
edges, and plan on either re-prompting the worst offenders individually or
a manual offset-and-patch cleanup pass (the standard technique: shift the
tile 50% in both axes and paint over the seam that lands in the middle,
where it's least noticeable) rather than treating one bad seam as a sign
the whole sheet failed.

### Working prompt template (fill in `[BIOME NAME]` / `[TEXTURE DESCRIPTION]`)

> [style preamble] A pixel-art sprite sheet of top-down ground texture for a
> **[BIOME NAME]** biome in a 16-bit-era overworld game, laid out as a strict
> 3x3 grid of 9 SQUARE tiles (each tile exactly as wide as it is tall — not a
> tall rectangle), each tile separated by a thin 1-2px near-white/magenta
> divider line (the same chroma-key-friendly convention as every other
> sheet, but ONLY in the gaps between tiles and around the outer edge —
> every tile's own interior is 100% opaque ground texture, full bleed to its
> own edges, no vignette, no fade, no background showing through inside any
> tile). Each of the 9 tiles must be a genuinely DIFFERENT-looking patch of
> the same ground type — [TEXTURE DESCRIPTION] — varying in exactly where
> small details (speckles, cracks, tufts, pebbles) fall, never a
> copy-pasted repeat of another tile in the sheet. Rows progress from
> sparser/cleaner ground at the top to denser/more detailed ground at the
> bottom, so the sheet reads as a gradient of "how much is going on" as well
> as 9 individual layouts. CRITICAL: every individual tile must be
> SEAMLESSLY TILEABLE on its own — its left edge matches what its right edge
> would need to continue into, and its top edge matches what its bottom edge
> would need to continue into, so four copies of the same tile placed
> edge-to-edge show no visible seam or repeating border. [ingestion format,
> EXCEPT: no per-tile padding — tiles are full-bleed squares, not cropped
> isolated objects]

### Per-biome `[TEXTURE DESCRIPTION]` fill-ins

- **grassland**: "a vivid green grassy field, small individual grass
  blades and blade-clusters scattered across a slightly darker green
  base, a few tiny lighter-green highlight speckles"
- **forest**: "a deep-green forest floor, patchy moss blotches and fallen-
  leaf litter over a darker green-brown base, dappled light/shadow
  mottling"
- **mountain**: "grey rocky ground, fine branching cracks over a mid-grey
  stone base, small scattered darker pebbles and lighter chip highlights"
- **tundra**: "pale frost-blue-white ground, scattered small grey stones
  and patches of thin frost-crusted texture over a near-white base"
- **rainforest**: "a rich dark-green jungle floor, dense overlapping moss
  and broad-leaf litter, more saturated and busier than the forest tile"
- **desert**: "warm sandy-tan ground, fine wind-carved dune ripple lines
  over a pale gold-tan base, occasional small darker grit speckles"

### Why ocean is excluded here

`ProceduralTerrainSprite` animates water as a 4-frame scrolling loop (see
`FRAME_COUNT`), and the current illustrated-art plumbing
(`IllustratedTerrainSprite`) reuses a single static frame across all four
animation slots — there is no seam yet for an illustrated tile to carry its
own animation. Registering an illustrated ocean sheet today would trade
away the existing moving water for a flat static tile. Leave ocean
procedural until an animated-illustrated mechanism exists, or accept the
static-water tradeoff deliberately if that's ever wanted.

### Why blended/bordering tiles are still procedural

`TerrainRenderer` dithers one biome into a neighboring biome at borders
(`dominant_blend_for`/`corner_direction_for`) by generating a blend/corner
image on demand for whichever of the thousands of (biome pair x direction
mask x corner mask x variant) combinations a given border needs.
`ProceduralTerrainSprite` can synthesize any of those on the fly; hand/AI-
illustrating that same combinatorial space is not in scope. A biome with a
full illustrated sheet still shows a procedurally-generated fringe at its
borders with a differing neighbor — this is a known, deliberate scope
limit, not a gap to close in the same pass as the base tiles.

---

## 4. Character building blocks (player/NPC paperdoll)

See `docs/concept/character_art_brief.md` for the full engineering
rationale (why parts not a full-body sheet, why NEUTRAL/untinted color, the
registry shape, exact canvas/baseline). This section is just the prompts.

`IllustratedCharacterSprite` (`src/rendering/illustrated_character_sprite.gd`)
is wired and ready for **body/legs/arms** — CharacterView tints whatever art
is registered via `modulate` per class color (body, legs) or skin tone
(arms), so **draw every part in flat neutral light grey, no baked-in
color** (this is the one hard rule that differs from every other section
of this doc — a tinted part multiplies wrong). One shared leg/foot shape
and one shared arm/hand shape each cover BOTH left and right (CharacterView
already renders the same texture on both sides, just at mirrored X
positions) — don't generate separate left/right art.

**Head/hair/beard are NOT wired yet** (see the brief for why — one flat
tint can't separate skin/hair/eye color in a single drawing). Prompts 4d–4f
below are ready for whenever that layering work happens; generating them
now doesn't hurt, but don't expect them to appear in-game without the
matching engine change.

Facing convention: **right** (unlike horse/deer/boar/sheep, which all face
left) — matches `ProceduralCharacterSprite`'s existing right-facing rig.

### 4a. Torso/tunic — idle pose

> [style preamble] A single pixel-art sprite of a humanoid TORSO only — from
> the neck down to the waist/hip, no head, no arms, no legs — standing
> upright, facing RIGHT, viewed top-down/near-top-down as if seen slightly
> from above in an overworld game. A simple tunic/jerkin silhouette:
> slightly chamfered shoulders, a round collar, a belt with a small buckle
> at the waist. Rendered in a single FLAT LIGHT GREY tone throughout — no
> color, no pattern, no logos — with only posterized light/shadow banding
> (a highlight band on the upper-left-facing surfaces, a shadow band on the
> lower-right, per the shading rule above) to show its form and folds. This
> art will be tint-colored by the game engine afterward, so it must stay
> perfectly neutral grey. Isolated subject, generous empty padding on all
> sides, nothing touching the canvas edge.

### 4b. Legs — idle pose (shared shape, used for both left and right)

> [style preamble] A single pixel-art sprite of one humanoid LEG AND FOOT
> only — from the hip down, a simple trouser leg and a plain boot — standing
> upright, facing RIGHT, viewed top-down/near-top-down. Straight standing
> pose, not mid-stride. Rendered in a single FLAT LIGHT GREY tone
> throughout, posterized light/shadow banding only, no color, no pattern.
> Perfectly neutral grey for engine tinting. Isolated subject, generous
> empty padding, nothing touching the canvas edge.

### 4c. Arms — idle pose (shared shape, used for both left and right)

> [style preamble] A single pixel-art sprite of one humanoid ARM AND HAND
> only — from the shoulder down, bare skin, no sleeve — hanging naturally
> at rest, facing RIGHT, viewed top-down/near-top-down. Rendered in a
> single FLAT LIGHT GREY tone throughout, posterized light/shadow banding
> only, no skin color baked in. Perfectly neutral grey for engine tinting
> (the game applies the character's actual skin tone at runtime).
> Isolated subject, generous empty padding, nothing touching the canvas
> edge.

### 4d. Head — base (future; not yet wired, see brief)

> [style preamble] A single pixel-art sprite of a humanoid HEAD in profile,
> facing RIGHT, viewed top-down/near-top-down — neck, jaw, ears, and a bald
> scalp (no hair at all — hair is a separate overlay, see 4e), with basic
> eye sockets and a simple nose/mouth suggested but not colored (leave eyes
> as a slightly darker grey recess, not a real eye color). Rendered in a
> single FLAT LIGHT GREY tone throughout, posterized light/shadow banding
> only, no skin tone baked in — the game applies actual skin tone at
> runtime. Isolated subject, generous empty padding.

### 4e. Hair overlays — one sheet, all 5 non-bald styles

> [style preamble] A pixel-art sprite sheet of 5 different HAIR styles for
> a humanoid head, laid out side by side in one row, each separated by a
> thin 1–2px near-white divider line: (1) SHORT — a close-cropped simple
> crop; (2) SWEPT — short hair swept back off the forehead; (3) LONG —
> hair falling past the shoulder in the back; (4) PONYTAIL — hair gathered
> at the back into a single tied tail; (5) TOPKNOT — hair gathered into a
> small knot on top of the head. Each style shown as ONLY the hair shape
> itself (no head/face underneath it) sized and positioned to sit correctly
> on top of the head sprite from 4d, facing RIGHT, top-down/near-top-down
> perspective. Rendered in a single FLAT LIGHT GREY tone throughout,
> posterized light/shadow banding only — no hair color baked in, the game
> tints it per character at runtime. [ingestion format]

### 4f. Beard overlays — one sheet, all 3 non-none styles

> [style preamble] A pixel-art sprite sheet of 3 different BEARD/facial-hair
> styles, laid out side by side in one row, each separated by a thin 1–2px
> near-white divider line: (1) STUBBLE — a light shadow of short stubble
> across the jaw and chin only; (2) GOATEE — a small pointed patch of hair
> on the chin only, cheeks and jaw clean; (3) FULL — a full beard covering
> the jaw, chin, and upper cheeks, moderate length. Each style shown as
> ONLY the facial-hair shape itself (no head/face underneath it) sized and
> positioned to sit correctly on the lower half of the head sprite from 4d,
> facing RIGHT, top-down/near-top-down perspective. Rendered in a single
> FLAT LIGHT GREY tone throughout, posterized light/shadow banding only —
> no hair color baked in, tinted per character at runtime. [ingestion
> format]

### File naming, once generated

Following the `assets/sprites/animals/sheep.png` precedent, drop these into
`assets/sprites/character/`:

```
assets/sprites/character/body_idle.png
assets/sprites/character/legs_idle.png
assets/sprites/character/arms_idle.png
assets/sprites/character/head_base.png       (future)
assets/sprites/character/hair.png            (future, one sheet, 5 cells)
assets/sprites/character/beard.png           (future, one sheet, 3 cells)
```

Then register body/legs/arms in `IllustratedCharacterSprite._PARTS` (see
`character_art_brief.md`'s "How to register a finished part" for the exact
Dictionary shape) — measuring each sheet's own content band the same way
`illustrated_animal_sprite.gd`'s sheep entry documents, not by guessing.

---

## 5. Ore nodes — one sheet per ore type, boulder-scale with embedded deposits

Ore is the one stone-adjacent entity still fully procedural
(`ProceduralOreSprite`) — a flat grey ellipse with runtime-painted flecks
(`FLECK_COLOR`: iron orange-brown, copper teal-green, coal near-black), the
same "old procedural" look pebbles/boulders/cobbles have already moved past
(see `docs/concept/stone.md`). Ore nodes always draw at BOULDER scale
regardless of the underlying cell's rolled size
(`StoneRenderer._attach_body_parts`'s `diameter_cm == 0` branch), so —
unlike pebbles/cobbles/boulders, which each needed their own scale-
appropriate sheet — one sheet per ORE TYPE covers it completely; no
pebble/cobble-scale ore sheet is needed.

Follow the `boulders.png` precedent directly: that sheet is a real 4-row x
5-column (20-variant) grid that came back clean on the first attempt. Ask
for the full 5x5 (25) here — the "only 3x3 held" finding in section 3 was
specific to full-bleed *tiling* terrain textures, not isolated padded
objects like this, so there's no reason to expect the same ceiling.

### Working prompt template (fill in `[ORE NAME]` / `[DEPOSIT DESCRIPTION]`)

> [style preamble] A pixel-art sprite sheet of 25 individual **[ORE NAME]
> ORE** boulder/rock chunks, laid out as a strict 5x5 grid, each cell
> separated by a thin 1–2px near-white divider line, generous empty padding
> around each rock so nothing touches a divider or the canvas edge. Every
> rock is a craggy, faceted grey stone boulder — the same rock-formation
> style as a plain granite boulder, angular chunky facets with visible
> cracks, not a smooth pebble — with [DEPOSIT DESCRIPTION] embedded directly
> in the rock face, clearly visible as part of the stone's own surface, not
> a separate floating overlay. Each of the 25 must be a genuinely different
> rock silhouette and a different arrangement of its ore deposits — rows
> progress from smaller/simpler rocks with fewer visible deposits at the top
> to larger/more complex rocks with more deposits at the bottom. [ingestion
> format]

Fill-ins:

- **iron** — `[ORE NAME]`: "IRON"; `[DEPOSIT DESCRIPTION]`: "rusty
  orange-brown streaks and small rounded nodules of oxidized iron ore (like
  real hematite/limonite), scattered irregularly across the rock face"
- **copper** — `[ORE NAME]`: "COPPER"; `[DEPOSIT DESCRIPTION]`: "bright
  teal-green mineral veins and small crusty patches of oxidized copper ore
  (like real malachite/azurite), running through cracks and across exposed
  faces of the rock"
- **coal** — `[ORE NAME]`: "COAL"; `[DEPOSIT DESCRIPTION]`: "glossy
  near-black coal bands and chunky black seams embedded in the grey rock,
  with a subtle sheen distinguishing them from the matte grey stone around
  them"

### File naming + wiring, once generated

Following the `boulders.png`/`pebbles.png`/`cobbles.png` precedent, drop
these into `assets/sprites/`:

```
assets/sprites/iron_ore.png
assets/sprites/copper_ore.png
assets/sprites/coal_ore.png
```

Wiring these needs a small new class mirroring `IllustratedStoneSprite`'s
exact shape (sheet path + measured `row_bands`) but keyed by ORE TYPE
instead of stone CLASS — ore isn't a `StoneSize` class, so it doesn't belong
inside `IllustratedStoneSprite` itself. `StoneRenderer._ore_texture_for`
would gain a `has_variants(ore_type)`-gated preference for it, ahead of the
boulder-frame-compositing fallback that exists today
(`ProceduralOreSprite.generate_texture_from_base`, itself already a
fallback ahead of the fully-procedural ellipse) — the same
has_variants()-gated layering every other optional illustrated-art seam in
this codebase already uses, just one layer deeper.

---

## 6. World boss special-attack telegraphs — Krampus

Attack-cycle sheets for Krampus's real, tested kit (see
[worldbosses.md](../concept/worldbosses.md)'s "Krampus: a worked encounter"
section, `src/gameplay/boss_phase_kits.gd`): Chain Yank (baseline), Chain
Lash + Terrifying Roar (phase 2, 50% HP), Chain Shackle (phase 3, 20% HP).
Same one-bespoke-sheet-per-action shape as Krampus's already-generated
walk cycle (registered in `illustrated_animal_sprite.gd`'s `_SHEETS`, not
itself re-documented here — see that file's own entry for the exact walk
prompt used), not modular recolored parts. These would replace the current fallback
(`has_action`'s "attack" falls back to the walk cycle when no dedicated
`attack_bands` exists) with a real, ability-specific telegraph once
generated and wired in.

**Prefix every prompt below with the shared style preamble above**, plus
this attack-cycle addendum (parallel to the walk-cycle one, adjusted for a
wind-up→release→recovery beat instead of a locomotion loop):

> Lay out an 8-frame attack cycle in a single horizontal row — a clear
> wind-up (frames 1-3), a release/peak (frames 4-5), and a follow-through/
> recovery (frames 6-8) — each frame separated by a thin 1-2px near-white
> divider line, generous empty magenta padding around each pose so nothing
> touches a divider or the canvas edge. Frames do not need uniform width.
> Export at least 2200px wide by 900px tall for the row. SAME CHARACTER as
> the existing Krampus walk cycle, for visual continuity across his action
> set: a tall, powerfully-built bipedal creature with dark brown-black fur,
> a goat's head with large curved backswept horns, red eyes, a long lolling
> tongue, cloven hooves, a long thin tail, a leather chest harness with a
> skull ornament. Facing LEFT, matching the existing walk cycle's facing
> direction, so every action sheet reads as the same character from the
> same angle.

### 6a. Chain Yank (baseline — always available, not phase-gated)

> A pixel-art attack cycle of KRAMPUS performing a CHAIN YANK: he winds up
> by coiling the chain back in one clawed hand (frames 1-3, chain gathering
> into loose loops at his side), then whips it forward in a hard throwing
> motion so it extends nearly straight out toward the LEFT edge of the
> frame at full length (frames 4-5, the peak of the throw — chain taut, a
> few links visible along its length, small motion-blur-style speed lines
> trailing it, rendered as the same flat posterized style as everything
> else, not a soft blur), then hauls it back in a heaving retrieving
> motion, whole body leaning into the pull (frames 6-8, chain coiling back
> toward him). The chain is the star of this cycle — his body reads mostly
> as a grounded anchor/pivot for the throw and haul.

### 6b. Chain Lash (phase 2, unlocks at 50% HP)

> A pixel-art attack cycle of KRAMPUS performing a CHAIN LASH: a wide
> horizontal sweeping attack. He winds up by twisting his whole torso and
> raising the chain-wielding arm back and up (frames 1-3), then sweeps it
> in a broad horizontal arc all the way across in front of him (frames
> 4-6, the chain reading as a sweeping curved line with visible links,
> covering a wide horizontal span — this is a CROWD-CLEARING swing, the
> arc should read as wide, not a narrow jab), then follows through with
> his body twisted to the opposite side from where he started, chain now
> trailing loosely on the ground (frames 7-8).

### 6c. Terrifying Roar (phase 2, unlocks at 50% HP, alongside Chain Lash)

> A pixel-art attack cycle of KRAMPUS performing a TERRIFYING ROAR: no
> chain motion this cycle -- both his hands stay low/loose at his sides
> throughout, all the drama is in the head and posture. He draws his head
> back and inhales, chest visibly expanding (frames 1-3), then throws his
> head forward and down toward the viewer with his mouth wide open, tongue
> extended, in a full roar (frames 4-5 -- the peak: add a few short, pale,
> radiating motion-lines around his open mouth reading as a sound-wave/
> shout burst, rendered in the same flat posterized style, not a glow or
> particle effect), then straightens back up, mouth closing, breathing hard
> (frames 6-8).

### 6d. Chain Shackle (phase 3 "The Reckoning", unlocks at 20% HP)

> A pixel-art attack cycle of KRAMPUS performing a CHAIN SHACKLE: he winds
> up by gathering the chain into a tight coiled loop held ready in one hand
> (frames 1-3, distinctly a COILED LOOP shape this time, not the loose
> gathered loops of Chain Yank -- read as a lasso/snare), then hurls the
> loop forward and down toward the ground just in front of him, the loop
> opening out mid-throw (frames 4-6, the chain's loop shape clearly
> visible, aimed at a point on the ground rather than thrown straight
> ahead like Chain Yank), then plants both feet and braces, chain now taut
> and anchored to whatever it caught, leaning back against the tension
> (frames 7-8 -- this is the "something is now bound" pose, his body
> reading as actively holding something down rather than following
> through past it).

---

## 7. World bosses — Germany / Central Europe walk cycles (2026-08-24)

Bespoke, one-off illustrated sheets for the mythic-region roster in
[worldbosses.md](../concept/worldbosses.md)'s Germany entry (chronologically
these came first — before section 6's Krampus attack telegraphs — kept as
their own numbered section rather than renumbering everything above). Unlike
sections 1-2 above, these are **not** modular parts recolored/assembled at
runtime — a world boss gets its own fully-realized creature art, the same
"one bespoke sheet per species" shape `illustrated_animal_sprite.gd`
already uses for horse/deer/boar (see that file's own doc comment: no
per-seed variation, every instance shows the same illustrated frames — a
world boss is exactly that shape, just with a unique species entry of its
own instead of a common one). Each entry below is a **walk cycle**, the
minimum viable action (horse.png shipped with walk-only and still reads
fine in-game — idle can synthesize from frame 0, per `has_action`'s
fallback chain, see that file). All four of these were actually generated
and are live in the game — see `illustrated_animal_sprite.gd`'s `_SHEETS`
entries for `lindwurm`/`rubezahl`/`nyx`/`krampus`.

**Prefix every prompt below with the shared style preamble above** (flat
posterized 3-band shading, solid magenta #FF00FF background, orthographic
top-down, upper-left light source), plus this walk-cycle-specific
addendum:

> Lay out an 8-frame walking cycle in a single horizontal row, each frame
> separated by a thin 1-2px near-white divider line (not a decorative
> border), generous empty magenta padding around each pose so nothing
> touches a divider or the canvas edge. Frames do not need uniform width.
> Export at least 2200px wide by 800px tall for the row (matches this
> project's existing `horse_walk.png` precedent) so the downsample to the
> game's actual pixel grid stays clean. The creature reads at a
> consistent scale and ground-contact line across all 8 frames — it should
> not grow, shrink, or drift vertically frame to frame. Facing RIGHT
> (head/leading edge on the right side of each frame) unless the
> individual prompt says otherwise.

### 7a. Lindwurm

> A pixel-art walk cycle of a LINDWURM — a wingless, serpentine
> Central-European dragon, NOT a Western winged dragon and NOT a snake:
> a long, thick, muscular serpentine body ending in a blunt wedge-shaped
> head with small backswept horns and a forked tongue, TWO short clawed
> forelegs near the front of the body and NO hindlegs or wings at all —
> the rear two-thirds of the body drags/slithers along the ground like a
> heavy tail. Overlapping dark bronze-green scales with a lighter
> underbelly band, a single low dorsal ridge of small spines running
> down the spine's full length. Locomotion is a sinuous full-body
> slither with the two forelegs pulling/gripping the ground — NOT a
> normal quadruped walk, since it has no back legs. Roughly as long as
> 3-4 times its own body height, read as heavy and powerful rather than
> serpent-thin. [walk-cycle addendum above]

### 7b. Rübezahl (storm-boar form)

> A pixel-art walk cycle of a giant, supernatural WILD BOAR wreathed in
> a faint storm — this is Rübezahl, a Central-European mountain spirit,
> in the animal form his own folklore says he takes. A heavily-built
> wild boar, larger and more powerful-looking than a normal boar, dark
> slate-grey hide with a coarse bristled mane running along its spine
> from head to shoulders, oversized curved tusks, small crackling
> pale-blue-white lightning-like markings faintly visible along its
> flanks and mane (subtle, not a glowing special effect — read as part
> of the creature's own hide pattern, flat-shaded like everything else,
> not a light-emitting overlay). A standard quadruped walk cycle, heavy
> and deliberate rather than a light trot. [walk-cycle addendum above]

### 7c. Nix (Wasserfrau)

> A pixel-art walk cycle of a NIX (Wasserfrau) — a Central-European
> water spirit — shown in a hybrid, non-humanoid creature form suited to
> this game's animal roster: a sleek, elongated aquatic body with a
> humanoid-adjacent torso tapering smoothly into a long scaled,
> fish-finned lower body/tail (no legs at all — it moves by an
> undulating serpentine tail motion, not walking), pale
> green-grey-blue skin with a faint scale texture, webbed clawed
> forearms, long dark hair/weed-like trailing fronds streaming from the
> head. Since it has no legs, render this as a LOCOMOTION cycle of the
> tail's undulating S-curve pulling the body forward (still 8 frames in
> one row, same divider/export rules) rather than a walk gait — the
> torso stays upright and roughly level while the tail whips side to
> side beneath it. [walk-cycle addendum above, substituting "undulating
> aquatic locomotion cycle" for "walking cycle"]

### 7d. Krampus

> A pixel-art walk cycle of KRAMPUS — an Alpine/Bavarian goat-demon
> companion figure. A tall, powerfully-built bipedal creature with dark
> brown-black fur covering a humanoid-proportioned but distinctly
> non-human body, a goat's head with large curved backswept horns and a
> long lolling tongue, cloven hooves for feet, a long thin tail. One arm
> ends in a clawed hand dragging a length of heavy chain with a couple
> of visible links trailing behind it in every frame (part of the
> creature itself, not a separate prop layer). A confident, heavy
> bipedal walk cycle, chain dragging and swinging slightly with the
> gait. [walk-cycle addendum above]

---

## 8. Spell atom effects — one sheet per atom, six shared families

Effect sheets for the 25 atoms in `spell_atom_catalog.gd`, real and castable
today via the procedural fallback (`procedural_spell_effect_sprite.gd`) a
player already sees on every cast (see [spell_runtime.md](../concept/spell_runtime.md)
and [magic.md](../concept/magic.md)'s "Atom effects render as composite
spritemaps" section). Keyed by ATOM id, not spell/item id — an effect
belongs to whichever atom is resolving, not to the wand or weapon that
triggered it, so a sheet generated here replaces that ONE atom's procedural
look everywhere it's cast from, regardless of which spell used it.

Same "one kit per shared shape, not per member" efficiency this doc already
uses for flower archetypes (section 1): the procedural generator already
groups all 25 atoms into 6 shared silhouette families — **burst, ring,
cross, spiral, chevron, cloud** — matching `spell_atom_catalog.gd`'s own
category groupings (every `damage` atom is a burst, every timed/lingering
`control` atom a ring or cloud, etc. — see that file's own category field).
Generate one template per family, then a distinct color/detail pass per
atom in it — 6 base sessions instead of 25 unrelated ones, and a new atom
added later needs only a color variant of an existing family, not new art
from scratch.

**Prefix every prompt below with the shared style preamble above**, plus
this effect-cycle addendum (a small target-centered burst, not a full
character — much smaller canvas than the boss attack sheets in section 6):

> Lay out a 6-frame effect cycle in a single horizontal row — a bright
> gathering wind-up (frames 1-2), a peak burst at full size and brightness
> (frames 3-4), and a fade/dissipate (frames 5-6) — each frame separated by
> a thin 1-2px near-white divider line, generous empty magenta padding
> around each pose so nothing touches a divider or the canvas edge. This is
> a small magical effect hovering at roughly chest height on a target, NOT
> a full character — keep it compact and centered in each frame, no
> ground, no shadow, no surrounding scene. Export at least 900px wide by
> 200px tall for the row (a much smaller canvas than a full-character
> sheet). No text, no numbers, no UI elements anywhere in the image.

### 8a. Burst family — fire_damage, frost_damage, shock_damage, ignite, induce_mutation, illuminate, fear

> A pixel-art effect cycle of a radiating BURST: a bright core gathers
> inward during the wind-up (frames 1-2), then explodes outward into sharp
> radiating spikes at peak brightness (frames 3-4, 8 spikes evenly spaced
> around the core, each tapering to a point), then the spikes shrink and
> fade to nothing (frames 5-6). [COLOR/FLAVOR — see table below] Strictly
> posterized flat-banded shading throughout, no soft glow or gradient blur.

| Atom | Color/flavor variation |
|---|---|
| `fire_damage` | Vivid orange-red core, yellow-white spike tips, like a small fireball igniting. |
| `frost_damage` | Pale ice-blue core with sharp angular (not rounded) spikes, faint white frost crystals at the tips instead of a soft glow. |
| `shock_damage` | Bright yellow core, spikes drawn as jagged lightning-bolt zigzags rather than straight spikes. |
| `ignite` | Deep red-orange core, smaller and lower than fire_damage's burst (this is a lingering flame catching, not a one-shot blast) — a few small flame-lick shapes persist faintly into frame 6 instead of fully fading. |
| `induce_mutation` | Sickly violet-purple core, spikes drawn asymmetric and irregular (no two the same length) rather than evenly spaced, unsettling instead of triumphant. |
| `illuminate` | Warm bright yellow-white core, soft even spikes like sunbeams, the single brightest/whitest of this family. |
| `fear` | Very dark purple-black core with jagged spikes reading as claw-marks or cracks rather than light rays — the visual opposite of illuminate despite sharing the burst shape. |

### 8b. Ring family — freeze, root, shield, reveal, suppress_mutation, calm, teleport, portal

> A pixel-art effect cycle of an encircling RING forming around the target:
> a thin ring fades in and contracts slightly (frames 1-2), holds at full
> brightness and a settled size (frames 3-4), then fades out in place
> (frames 5-6) — this ring does not explode outward or travel, it simply
> appears around/at the target and later disappears. [COLOR/FLAVOR — see
> table below] Strictly posterized flat-banded shading, no soft glow.

| Atom | Color/flavor variation |
|---|---|
| `freeze` | Pale ice-blue ring rendered as jagged crystalline facets rather than a smooth curve, a few small icicle spikes hanging off its inner edge. |
| `root` | Earthy brown-green ring made of small thorny vine segments rather than a smooth line, a few thin roots/tendrils reaching inward from it. |
| `shield` | Soft translucent-reading blue ring, drawn as a clean smooth curve (the most "protective barrier"-looking of this family) with a faint hexagonal facet pattern along it. |
| `reveal` | Pale warm yellow ring, drawn as a soft pulse/ripple (concentric, like a radar ping) rather than a solid line. |
| `suppress_mutation` | Flat grey ring with a single diagonal bar across it (a "null/forbidden" sign read), the most graphically plain of this family on purpose. |
| `calm` | Soft pale blue-green ring, drawn as a slow gentle ripple like calm water, the softest-edged ring in the family. |
| `teleport` | Violet ring that reads as thin and fast rather than settled — draw it already at full size in frame 1 and let it be the frames 5-6 fade that does most of the visible work, a "blink" rather than a forming barrier. |
| `portal` | Deep indigo-blue ring, drawn as a genuine DOUBLE ring (two concentric rings close together, both visible) with a slightly darker "window" showing inside it, distinct from every single-ring atom in this family. |

### 8c. Cross family — minor_heal, major_heal, summon_wisp

> A pixel-art effect cycle of a small RESTORATIVE SPARKLE: a soft four-
> pointed cross/star shape gathers and brightens (frames 1-2), holds at
> peak brightness with a few small satellite sparkle particles orbiting it
> (frames 3-4), then the particles drift outward and everything fades
> (frames 5-6). [COLOR/FLAVOR — see table below] Strictly posterized
> flat-banded shading, warm and gentle rather than aggressive.

| Atom | Color/flavor variation |
|---|---|
| `minor_heal` | Soft warm gold, small and modest in scale. |
| `major_heal` | Brighter white-gold, visibly larger and with more satellite sparkles than minor_heal — the same family member, clearly the "bigger" version. |
| `summon_wisp` | Pale cyan-white, the satellite particles read as a small orbiting cluster of tiny lights rather than sparkles — this is the closest thing to a distinct "small creature" in this family, so keep it airy and alive-looking rather than a plain heal-glow. |

### 8d. Spiral family — slow, accelerate_growth, gravity_shift

> A pixel-art effect cycle of an inward SPIRAL: a line of light winds
> inward from the outer edge toward the center in a 2-turn spiral (frames
> 1-3, the spiral visibly tightening frame to frame), holds briefly at its
> most tightly-wound state (frame 4), then dissolves outward (frames 5-6).
> [COLOR/FLAVOR — see table below] Strictly posterized flat-banded shading.

| Atom | Color/flavor variation |
|---|---|
| `slow` | Muted teal-grey, drawn as a viscous, slow-moving/thick-looking line (this atom's spiral should read as the LEAST energetic of the three). |
| `accelerate_growth` | Vivid green, drawn as a sprouting vine/tendril curling inward rather than a plain line of light — the most organic-looking member of this family. |
| `gravity_shift` | Deep indigo-purple, drawn with a subtle warping/lensing distortion along the spiral's own curve (the space along the line reads slightly bent), the most "physics-bending" looking member of this family. |

### 8e. Chevron family — push, pull

> A pixel-art effect cycle of two opposed WEDGE shapes at the target: two
> triangular chevrons pointing away from center (for an outward force) or
> toward center (for an inward one) fade in small and close to the target
> (frames 1-2), snap outward/inward to their full extent at peak (frames
> 3-4, this should read as a sudden sharp motion, not a gentle drift), then
> fade out in their extended position (frames 5-6). [DIRECTION/COLOR — see
> table below] Strictly posterized flat-banded shading, sharp hard edges
> throughout (no soft chevrons).

| Atom | Direction/color variation |
|---|---|
| `push` | Chevrons point AWAY from the target's center, outward, in light cool grey — reads as a shove leaving. |
| `pull` | Chevrons point TOWARD the target's center, inward, in a darker blue-grey — reads as a force arriving/gathering in. |

### 8f. Cloud family — poison_damage, blight

> A pixel-art effect cycle of a small creeping CLOUD cluster: several
> irregular soft-edged puffs gather loosely around the target (frames 1-2),
> thicken and darken slightly at peak (frames 3-4), then thin out and
> disperse (frames 5-6) — this should read as something settling ONTO the
> target rather than exploding outward, the visual opposite energy of the
> burst family. [COLOR/FLAVOR — see table below] Strictly posterized
> flat-banded shading, no soft airbrushed fog.

| Atom | Color/flavor variation |
|---|---|
| `poison_damage` | Sickly yellow-green, a few small bubble/droplet shapes among the puffs. |
| `blight` | Dark purple-brown, drawn with small crack/wither lines radiating from the puffs into the empty space around them — the more "creeping decay" looking of the two, versus poison_damage's more "toxic gas" read. |

---

## 9. General item icons — one kit per visual archetype (2026-08-28)

The full item catalog (`item_catalog.gd`'s `_ITEMS`, the single source of
truth for every id in the game — 74 entries as of this writing) has never
had illustrated icon art at all. `docs/concept/art_resolution.md` flags
items/icons as the one art category still on its pending Phase 6; every
item today renders through `procedural_item_sprite.gd`'s color+silhouette
generator instead (see [item_illustrations.md](../concept/item_illustrations.md),
which specced the `Item.sprite_id` field this section's output would
register through — swapping an id onto real art means editing a catalog's
`sprite_id`, never touching a renderer). `carrot`/`potato` already have real
illustrated ground art (section 2) and are excluded below; every other item
is scaffolded here into 11 kits by shared silhouette, the same "one kit per
archetype, not per member" efficiency this doc uses everywhere else (see
section 1's flower archetypes or section 8's atom shape-families). The
"current look" column names `procedural_item_sprite.gd`'s existing
`_ITEM_LOOKS` color/shape for continuity — matching it isn't required, but
an item with no entry there at all (falls back to the generic grey pebble)
is called out explicitly, since those are the items with literally no
distinct look today, procedural or otherwise.

**Prefix every prompt below with the shared style preamble from the top of
this doc**, plus this icon-sheet addendum (a single still icon, not an
action cycle — much simpler than every other section here):

> Lay out each item as a single centered icon on the sheet, generously
> spaced from its neighbors and from the canvas edge, at a 3/4-from-above
> "inventory icon" angle rather than a flat side profile — the same angle
> real items already read at in this game's UI. One sheet may hold every
> member of a kit side by side (label positions loosely in your own notes,
> not baked into the image) rather than one image per item. No text, no
> numbers, no UI chrome, no ground/shadow/scene — just the object itself
> on flat solid magenta.

### 9a. Bladed & hafted weapons — wooden_club, iron_sword, crude_blade

| Item | Current look | Note |
|---|---|---|
| `wooden_club` | Brown wood, sword silhouette | A stout haft, no blade — the starting melee weapon. |
| `iron_sword` | Grey-blue steel, sword silhouette | Real modeled mass (~1.2kg, see `item_catalog.gd`'s own mass-derivation comment) — should read as a genuine one-handed blade, not oversized. |
| `crude_blade` | Grey-brown stone, sword silhouette | The knapping-chain's first weapon: a flint/stone edge lashed to a stick, visibly primitive next to iron_sword. |

> Three melee weapons on a shared vertical-blade-plus-grip silhouette, each
> reading as a clear step up in craftsmanship: `wooden_club` a plain stout
> wooden haft with no blade at all; `crude_blade` a knapped grey stone edge
> crudely lashed with fibre cord to a short wooden stick, visibly primitive;
> `iron_sword` a clean tapered steel blade with a proper crossguard and
> wrapped grip. Same posterized flat-band shading throughout, muted
> naturalistic colors (wood brown, flint grey, iron blue-grey).

### 9b. Edged/wedge tools — iron_axe, stone_pickaxe

| Item | Current look | Note |
|---|---|---|
| `iron_axe` | Grey-blue steel, axe silhouette | Felling tool — see `Item.is_axe()`. |
| `stone_pickaxe` | Grey-brown stone, axe silhouette | Mining tool — currently shares the axe silhouette procedurally; illustrated art should differentiate a pick's narrow double point from an axe's broad single wedge. |

> Two hafted mining/felling tools, deliberately NOT sharing one silhouette
> the way the procedural fallback currently does: `iron_axe` a broad
> asymmetric steel wedge-head on a wooden haft; `stone_pickaxe` a narrow
> stone head tapering to points at both ends, distinctly different from an
> axe's single broad blade. Same posterized shading, same muted materials
> as the weapons kit above.

### 9c. Handheld instruments (elongated) — torch, stick, saw, fishing_rod

| Item | Current look | Note |
|---|---|---|
| `torch` | Warm orange, sword silhouette | No lit-flame version exists — worth a lit and unlit variant if scope allows. |
| `stick` | Brown wood, sword silhouette | A stackable raw material, not a weapon, despite sharing the silhouette. |
| `saw` | **No entry — falls back to the generic grey pebble today.** | The one item in this whole kit with zero distinct look at all right now. |
| `fishing_rod` | Brown wood, sword silhouette | Held exactly like a weapon (`equip_item`), cast with the same swing animation. |

> Four straight elongated handheld objects, each with a distinct head so
> they don't collapse into "brown stick" at a glance: `torch` a bound
> bundle of resin-soaked wood topped with a small flame (posterized
> orange/yellow, flat-banded, not a glow effect); `stick` a plain bare
> branch, knobby and irregular, no head at all; `saw` a wooden handle with
> a flat toothed metal blade at a slight angle, teeth clearly visible as a
> zigzag edge; `fishing_rod` a thin tapering wooden rod with a small reel
> near the grip and a fine line running to the tip.

### 9d. Wayfinding & citizenship instruments — rough_compass, compass, map, spyglass, weather_glass, star_chart, deed, ledger, field_journal, charter

| Item | Current look | Note |
|---|---|---|
| `rough_compass` | Muted brown, round | A crude precursor to `compass` — see `docs/concept/wayfinding.md`. |
| `compass` | Gold, round | The refined instrument. |
| `map` | Pale tan, oval | Currently shares the generic paper/parchment oval read with several others below. |
| `spyglass` | Grey, sword silhouette | Reuses the elongated-object silhouette procedurally; illustrated art should read as a collapsible brass telescope, not a stick. |
| `weather_glass` | Pale blue, oval | A barometer-like instrument. |
| `star_chart` | Deep indigo, round | A star map/astrolabe read. |
| `deed` | Orange-brown, oval | A property document. |
| `ledger` | Dark green, plate silhouette | A bound book — reuses the generic flat-rectangle "armor plate" silhouette procedurally. |
| `field_journal` | Brown, plate silhouette | Another bound book — same generic silhouette as `ledger` today, needs its own read once illustrated (see below). |
| `charter` | Purple, plate silhouette | A third book/document sharing that same generic silhouette. |

> Ten wayfinding and record-keeping instruments, split into three real
> shapes rather than the generic round/oval/plate blobs the procedural
> fallback currently leans on: **round dial instruments** (`rough_compass` a
> crude carved-wood-and-needle compass, `compass` its refined brass-and-glass
> counterpart, `star_chart` a circular star-map disc with fine engraved
> constellation lines); **rolled/folded paper** (`map` a partially unrolled
> parchment map with visible drawn coastline/terrain marks, `weather_glass`
> a small glass-and-brass barometer instrument, `deed` a folded wax-sealed
> parchment document); **bound books**, each with a DIFFERENT cover color
> and a small distinguishing cover emblem so the three don't read as one
> generic book — `ledger` a dark green account-book with a ruled-lines
> emblem, `field_journal` a worn brown journal with a small leaf/pressed-
> plant emblem, `charter` a formal purple-bound charter with a wax seal on
> the cover. `spyglass` breaks from all three: a collapsible brass
> telescope, sections tapering, one end wider than the other.

### 9e. Capture, restraint & rope gear — lasso, snare, butterfly_net, trap, reinforced_rope, climbing_rope, jarred_insect, caged_songbird

| Item | Current look | Note |
|---|---|---|
| `lasso` | Pale tan, oval | Rope gone pale and dry, per `item_catalog.gd`'s own comment — not the green plant_fibre it came from. |
| `snare` | Muted brown, snare silhouette (loop + peg) | Already has a bespoke procedural shape — see `_draw_snare`. |
| `butterfly_net` | White, net silhouette (hoop + handle) | Already bespoke — see `_draw_net`. |
| `trap` | Dark grey, metal-cornered box silhouette | Already bespoke — see `_draw_trap`. |
| `reinforced_rope` | Tan with a metal-grey core, oval+core silhouette | Already bespoke — see `_draw_reinforced_rope`; "a lasso PLUS metal" read for world-boss-scale capture. |
| `climbing_rope` | **No entry yet (added after the procedural generator was last extended) — falls back to the generic grey pebble.** | A coiled traversal rope, not a capture tool — see `docs/concept/transportation.md`. |
| `jarred_insect` | Pale cyan-white, jar silhouette | Already bespoke — see `_draw_jar`. |
| `caged_songbird` | Warm orange bird blur in a cage silhouette | Already bespoke — see `_draw_cage`. |

> Eight rope/restraint/containment items — several already have a strong,
> distinct procedural silhouette worth MATCHING rather than reinventing
> (snare's staked loop, the net's hoop-on-a-handle, the trap's cornered
> box, the reinforced rope's metal-cored coil, the insect jar, the
> songbird cage — describe each of these exactly as named above, just
> rendered instead of drawn pixel-by-pixel). Two need real designs from
> scratch: `lasso` a coiled loop of pale sun-bleached rope, distinct from
> `reinforced_rope`'s visible metal core; `climbing_rope` a neatly coiled
> plain hemp rope with a small metal carabiner clipped through it, reading
> as traversal gear rather than a capture tool.

### 9f. Worn armor — leather_helm/chest/legs/boots, iron_helm/chest/legs/boots

| Item | Slot | Current look |
|---|---|---|
| `leather_helm` / `iron_helm` | head | Brown / blue-grey, dome-on-top plate |
| `leather_chest` / `iron_chest` | chest | Brown / blue-grey, broad chestplate |
| `leather_legs` / `iron_legs` | legs | Brown / blue-grey, narrower greaves |
| `leather_boots` / `iron_boots` | feet | Brown / blue-grey, short low boots |

> Two full armor sets (leather and iron), four pieces each, all eight
> sharing the SAME silhouette per slot so a player can tell material apart
> at a glance without the shapes changing: a helm reads as a rounded dome
> with a brow-line; a chestpiece a broad front torso panel with visible
> shoulder straps; leg armor a pair of narrower shin/thigh guards; boots a
> short low pair with a visible sole line. Render the LEATHER set first —
> warm brown, soft creased leather texture, simple stitched seams — then
> the IRON set as a second pass on the identical poses/silhouettes —
> cool blue-grey metal, riveted plates, a subtle specular highlight band —
> so the two sets read as a real material upgrade of the same armor rather
> than two unrelated designs.

### 9g. Placeable structures — campfire, furnace, sagewerk, storage

| Item | Current look | Note |
|---|---|---|
| `campfire` | Bespoke crossed-logs-and-flame render | Already bespoke and good — see `_draw_campfire`; a real target to match, not redesign. |
| `furnace` | Bespoke stone block with a glowing firebox | Already bespoke — see `_draw_furnace`. |
| `sagewerk` | **No entry — falls back to the generic flat "armor plate" rectangle.** | A sawmill worksite (see `docs/concept/timber_construction.md`) — needs its own building-icon read. |
| `storage` | **No entry — falls back to the generic flat "armor plate" rectangle.** | A stock-holding structure (see `docs/concept/timber_construction.md`) — needs its own building-icon read. |

> Two placeable worksite icons, currently the least-distinguished items in
> the whole catalog (both fall back to a plain flat rectangle today):
> `sagewerk` a small open-sided timber-framed sawmill shed with a visible
> saw-blade and stacked raw logs beside it; `storage` a simple wooden crate/
> shed with visible plank construction and a barred door, reading clearly
> as "a place things get kept" rather than "a place things get made" next
> to sagewerk. `campfire`/`furnace` already have strong bespoke procedural
> art (crossed burning logs; a glowing stone firebox) worth matching as
> the reference point for this kit's overall style rather than
> redesigning from scratch.

### 9h. Raw & refined materials — hide, fang, wood, rock, sharp_shard, plant_fibre, log, beam, plank, stone, iron_ore, copper_ore, coal, iron_ingot, copper_ingot

| Item | Current look |
|---|---|
| `hide` | Brown, oval (tanned pelt) |
| `fang` | Pale ivory, tapering fang |
| `wood` | **No entry — generic pebble fallback.** |
| `rock` | Grey, round |
| `sharp_shard` | Pale grey, fang silhouette (a knapped flake) |
| `plant_fibre` | Green, oval |
| `log` | **No entry — generic pebble fallback.** |
| `beam` | **No entry — generic pebble fallback.** |
| `plank` | **No entry — generic pebble fallback.** |
| `stone` | Grey, round |
| `iron_ore` | Rust-orange-brown, round |
| `copper_ore` | Teal, round |
| `coal` | Near-black, round |
| `iron_ingot` | Pale steel-grey, oval bar |
| `copper_ingot` | Warm orange-brown, oval bar |

> Fifteen raw/refined crafting materials — the biggest, most heterogeneous
> kit here, so lean on real-world reference per item rather than one shared
> silhouette: `hide` a folded tanned animal pelt; `fang` a single curved
> ivory-white tooth; `wood`/`log` a short cut length of round bark-covered
> trunk (log larger/rougher than the wood scrap); `rock`/`stone` an
> irregular grey fist-sized stone (near-identical read is fine, they are
> the same material at two points in the gather chain); `sharp_shard` a
> single knapped grey flint flake with a visible sharp edge;
> `plant_fibre` a small bundle of stripped green plant strands;
> `beam`/`plank` sawn rectangular lumber (beam thick and square-profiled,
> plank thin and flat); `iron_ore`/`copper_ore` a raw rock chunk with
> visible embedded metallic flecks (rust-orange for iron, teal-green
> patina for copper); `coal` a dull matte-black irregular chunk;
> `iron_ingot`/`copper_ingot` a smooth cast metal bar with a flat top
> face, iron in cool blue-grey steel, copper in warm orange-brown metal.

### 9i. Orchard fruit & forage — fruit, nut, cherry, apple, walnut, acorn, hazelnut, pine

| Item | Current look |
|---|---|
| `fruit` | Red, round (generic ambient-forage fruit) |
| `nut` | Brown, oval (generic ambient-forage nut) |
| `cherry` | Deep red, round |
| `apple` | Red-orange, round |
| `walnut` | Brown, oval |
| `acorn` | Brown, oval |
| `hazelnut` | Brown-red, round |
| `pine` | Dark brown, oval (pine nut) |

> Eight small round fruit/nut icons matching `TreeSpecies.fruit_color_for`'s
> own real per-species colors (see `procedural_item_sprite.gd`'s own
> comment on this — an illustrated cherry must stay the same red the tree
> canopy's own ripe-fruit dots already use). `cherry` small and glossy
> deep red with a short stem; `apple` a rounder red-orange fruit with a
> small stem dimple; `walnut`/`acorn`/`hazelnut`/`pine` four visibly
> different nuts/seeds despite sharing a brown palette — walnut a
> wrinkled round shell, acorn its familiar capped-teardrop shape,
> hazelnut a smooth small round shell, pine nut a slender elongated
> husk. `fruit`/`nut` are the unnamed ambient-forage tier (see
> `EarthChunkManager.step_forage`) — a generic round red berry and a
> generic round brown nut, deliberately plainer/less distinctive than
> their named counterparts above.

### 9j. Food & catches — meat, cooked_meat, fish, cooked_fish, rare_fish, legendary_fish

| Item | Current look |
|---|---|
| `meat` | Dark red, round |
| `cooked_meat` | Dark brown, round |
| `fish` | Blue-grey, oval |
| `cooked_fish` | Warm tan, oval |
| `rare_fish` | Cool blue-violet, oval |
| `legendary_fish` | Vivid gold, oval |

> Six food/catch icons in two pairs plus two rarity variants: `meat` a raw
> red cut of meat with visible marbling, `cooked_meat` the same cut
> browned and seared; `fish`/`cooked_fish` a small silvery-blue whole fish
> raw, then browned/crisped over a fire. `rare_fish`/`legendary_fish` (see
> `FishingMinigame.fish_rarity`) reuse `fish`'s own silhouette but in
> visibly precious materials — rare in a cool blue-violet with a faint
> iridescent sheen, legendary in a vivid gold with warm highlights — so a
> catch's rarity reads instantly in the creel, matching the same colors
> the procedural fallback already committed to.

### 9k. Curiosities — terminal_fragment, secret_room_token, wargames_punch_card, curious_keepsake

| Item | Display name | Note |
|---|---|---|
| `terminal_fragment` | Pitted Circuit Shard | One of three "Three Fragments" Easter-egg pieces (see `docs/concept/easter_eggs.md`) — no procedural look registered at all. |
| `secret_room_token` | Tarnished Token | Same hunt, second fragment — no procedural look registered. |
| `wargames_punch_card` | Scorched Punch Card | Same hunt, third fragment — no procedural look registered. |
| `curious_keepsake` | Curious Keepsake | The bonus item granted once all three fragments are held together — no procedural look registered. |

> Four small, unremarkable-looking curiosities — deliberately NOT
> flashy or magical-looking (see this Easter-egg family's own "no
> fanfare, no mechanical weight" design pillar): `terminal_fragment` a
> small pitted, corroded green-circuit-board shard; `secret_room_token`
> a dull tarnished brass coin/token, worn smooth; `wargames_punch_card`
> a scorched, edge-charred paper punch card with a few visible holes;
> `curious_keepsake` a small worn trinket that reads as "assembled from
> the other three" without literally depicting them — a simple carved
> or welded charm shape. All four should look like unremarkable found
> objects, not loot.

---

## 10. Placed structures — seeded-variant grids (2026-09-03)

The illustrated-art gap [item_illustrations.md](../concept/item_illustrations.md#placed-structures-a-second-surface-this-doc-never-named)
names: what a placed `campfire`/`furnace`/`sagewerk`/`storage` looks like
BUILT IN THE WORLD, as opposed to its inventory icon (section 9g above — a
different surface entirely, drawn by a different generator).
`ProceduralStructureSprite` (`src/rendering/procedural_structure_sprite.gd`)
already draws all four placed tiles today: two already strong bespoke
designs (`campfire`, `furnace`) and two with no distinguishing shape at all
(`sagewerk`/`storage` — both currently just a generic rounded rim outline,
the same "reads as *a* building, not *this* building" gap section 9g's icon
prompts already named for the same two items, just on the OTHER surface).
Same shape as section 5's ore sheets, not section 6/7's walk cycles: each
structure already takes a seeded `variant_seed`
(`procedural_structure_sprite.gd:97,184,267,338`), so illustrated art wants a
GRID of interchangeable variants, not an animation.

**Prefix every prompt below with the shared style preamble from the top of
this doc**, plus this variant-grid addendum (same shape as section 5's ore
template, reworded for architecture instead of ore):

> A pixel-art sprite sheet of 25 individual instances of the same structure
> (see below), laid out as a strict 5x5 grid, each cell separated by a thin
> 1–2px near-white divider line, generous empty magenta padding around each
> structure so nothing touches a divider or the canvas edge. Every instance
> is recognizably the SAME structure — same footprint, same function, same
> overall silhouette — but a genuinely different arrangement of its own
> secondary details (log placement, weathering, small clutter). Viewed
> top-down/near-top-down, matching this game's existing structure tiles.
> Rows progress from a cleaner/newer-looking instance at the top to a more
> weathered/lived-in instance at the bottom. [ingestion format]

If 5×5 doesn't hold cleanly for a boxier architectural silhouette the way it
does for an ore boulder, drop to section 3's 3×3 fallback rather than
forcing it — try 5×5 first (section 5's ore sheets held it on the first
attempt; there's no a-priori reason architecture won't).

### 10a. Campfire — match the existing bespoke procedural design

> [STRUCTURE]: a simple campfire — three or four logs arranged in a
> teepee/crossed pile over a ring of dark fire-scorched earth, a small
> licking orange-yellow flame at the center rendered in the same flat
> posterized bands as everything else (not a soft glow), a light scatter of
> ash around the ring's edge.

### 10b. Furnace — match the existing bespoke procedural design

> [STRUCTURE]: a squat stone-and-brick furnace block, roughly cubic, with a
> dark arched firebox opening in its front face glowing warm orange-red from
> within, a few soot streaks above the opening, rough mortared stone
> construction on every visible face.

### 10c. Sagewerk (sawmill) — no distinguishing shape today

> [STRUCTURE]: a small open-sided timber-framed sawmill shed — a simple
> peaked roof on four corner posts with no walls, a large flat saw-blade
> mounted vertically at working height under the roof, one or two raw felled
> logs resting on trestles beside/beneath it, a scatter of sawdust and
> offcut planks on the ground nearby. Should read unmistakably as "a place
> logs get cut," distinct from storage's "a place things get kept" below.

### 10d. Storage — no distinguishing shape today

> [STRUCTURE]: a small enclosed wooden storage shed — visible horizontal
> plank wall construction, a simple peaked roof, one barred/planked door on
> the front face (closed), no windows. Should read unmistakably as "a place
> things get kept," distinct from sagewerk's open-sided workshop above.

### File naming + wiring, once generated

A new folder — none of the existing `assets/sprites/` subfolders fit a
placed structure (`terrain/` is ground tiles, root-level flat files are
walk-cycle species):

```
assets/sprites/structures/campfire.png
assets/sprites/structures/furnace.png
assets/sprites/structures/sagewerk.png
assets/sprites/structures/storage.png
```

Wiring needs a new `IllustratedStructureSprite`
(`src/rendering/illustrated_structure_sprite.gd`), mirroring
`IllustratedStoneSprite`/`IllustratedTerrainSprite`'s exact
`has_variants()`/`frame_for()` shape, and a `has_variants()`-gated preference
for it in `TerrainRenderer` ahead of `ProceduralStructureSprite` — see
[item_illustrations.md](../concept/item_illustrations.md#sheet-spec-placed-structures-get-a-seeded-variant-grid-not-a-strip)
for the full spec. Not attempted here: per this project's TDD rule, that
class needs real source pixels to write a meaningful test against, the same
reason `IllustratedCharacterSprite._PARTS` stays unpopulated until hair/beard
art exists.

---

## Notes for whoever runs these

- Run the flower archetype sheets (1b) at pale/neutral tone as specified —
  do not let the generator "helpfully" add species-accurate color; that
  breaks the runtime tint step.
- After generating, drop files into `assets/sprites/` following the
  `horse.png`/`deer.png` naming precedent (e.g. `flower_head_cup.png`; the
  composite crop kit in section 2 is `soil_pile.png` (shared, generate
  once) plus, per crop, `carrot_leaves.png`/`carrot_root.png`/
  `carrot_icon.png`/`carrot_held.png` and the same 4-file pattern for
  `potato_*`), and expect to tune
  `SpriteSheetSlicer` call params (`alpha_threshold`, `divider_gray_min`)
  per sheet the same way `illustrated_animal_sprite.gd` already does per
  species — the doc comment there notes horse's dividers measured ~0.63
  gray, softer than the 0.7 default.
- If a generated sheet's divider lines aren't clean/consistent, it's often
  easier to re-prompt than to hand-fix — the slicer is sensitive to this.
- Terrain sheets (section 3) are DONE: all six land biomes have real art
  registered in `IllustratedTerrainSprite._SHEETS` with measured row_bands —
  `assets/sprites/terrain/{grass,forest,desert,mountain,tundra,rainforest}.png`.
  `assets/sprites/terrain/grassland_9.png` is a leftover early single-tile
  exploratory render, superseded by `grass.png` — safe to ignore/delete.
  Re-prompting a biome (more variety, a different style) means regenerating
  its sheet, dropping it in over the old file, and re-measuring row_bands
  the same way (see `IllustratedTerrainSprite._SHEETS`'s own doc comment for
  the exact Y-ranges and how they were measured).
- Krampus's attack sheets (section 6) follow the walk-cycle wiring pattern
  exactly: drop each in as `assets/sprites/krampus_<ability>.png` (e.g.
  `krampus_chain_yank.png`) and add an `<ability>_bands`/`<ability>_path`
  pair to `illustrated_animal_sprite.gd`'s existing `"krampus"` `_SHEETS`
  entry, same shape as `eat_bands`/`eat_path` on deer/boar — **measure the
  chroma-key/content Y-range from the real generated pixels, don't reuse
  the walk cycle's `Vector2i(156, 600)`**, since an attack pose's silhouette
  sits differently on the canvas (the walk cycle's own diagnostic script,
  used to catch the missing-chroma_key bug this project shipped once
  already, is the right tool to reuse here too). Registering these art
  files alone does not make the abilities fire in a real fight —
  `BossPhase`/`BossPhaseKits` (`src/gameplay/`) currently only *select*
  which ability should be active at a given health fraction; nothing yet
  reads that selection during combat and swaps `CreatureMarker`'s
  `"attack"` action away from its current walk-cycle fallback to the
  matching new sheet (see `concept/worldbosses.md`'s Krampus Status
  sub-section for that real, open gap).
- Placed-structure sheets (section 10) have **no illustrated-art ingestion
  seam built yet either** — same gap as spell atoms below, for the same
  reason (no source pixels exist yet to write a real test against). Once
  generated, wiring them in is a new `IllustratedStructureSprite` plus a
  `has_variants()`-gated preference in `TerrainRenderer`, not a change to
  `ProceduralStructureSprite` itself — see section 10's own "File naming +
  wiring" note.
- Spell atom effect sheets (section 8) have **no illustrated-art ingestion
  seam built yet** — `procedural_spell_effect_sprite.gd` only ever
  generates its own procedural image today, unlike `DroppedItem`'s
  "check `IllustratedCropSprite` first, fall back to procedural" pattern.
  Wiring one in means adding that same has-real-art-first check to
  `ProceduralSpellEffectSprite.generate_image`/`texture_for` (or the
  `SpellEffectMarker` that calls them), keyed by atom id — measure each
  generated sheet's own chroma-key/frame Y-range fresh, the same warning
  section 6's own note gives for Krampus's attack sheets, since a small
  target-centered burst sits very differently on its canvas than a full
  character does.
