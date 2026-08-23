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
