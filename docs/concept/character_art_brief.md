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

| Part | Registry key | Tinted with | Status |
|---|---|---|---|
| Torso/tunic | `"body"` | `appearance.tunic` (class color) | ✅ wired |
| Legs | `"legs"` | `appearance.legs` (class color) | ✅ wired — see "Legs are a fused pair" |
| Arms | `"arms"` | `appearance.skin` (skin tone) | ✅ wired — two poses, one per side |
| Head | *(own surface, not `_PARTS`)* | `appearance.skin`, by recolor | ✅ wired — see "Head" below |
| Hair | — | — | ⬜ **not built — see "Hair is a known gap"** |
| Decorations | — | — | ⬜ **undefined — see "Decorations" below** |

Every part falls back to the existing procedural texture automatically if
its own art isn't registered (`has_part`/`has_action`/`has_head` checked
first), so any one part can regress to procedural without breaking the
others.

## Why building *blocks*, not one full-body sheet per class

CharacterView is a paperdoll: separate `Body`/`Head`/`LegLeft`/`LegRight`/
`ArmLeft`/`ArmRight` sprites, composited together and each tinted
independently (tunic color, skin tone, leg color). The illustrated pipeline
follows that same seam rather than fighting it — one small set of NEUTRAL
part sheets, tinted per class/skin-tone by the engine at runtime via
`modulate`, instead of a full hand-illustrated character × 7 classes × 6
skin tones × 7 hair colors. Draw the shape once; the engine recolors it.

**Draw every part in a light neutral grey (or white), no baked-in color.**
`modulate` multiplies the sprite's own pixels by the tint color — a part
drawn in flat color would come out wrong (a red tunic tinted "warrior red"
multiplies to a muddy dark red, not warrior red). A light neutral grey/white
base multiplies cleanly to whatever tint is applied. Keep genuine shading
(folds, highlights, an outline) — flat single-value art won't read as
clothing/skin at all — just keep the *hue* neutral. `torso.png`/`leg.png`/
`arms.png` all follow this; `head.png` does not (see below), which is why
the head needs its own recolor mechanism instead of a plain `modulate`.

## Legs are a fused pair, not a mirrored single leg

The delivered `leg.png` draws both legs together as one connected pose
(belt to boots), not one leg meant to be duplicated left/right. CharacterView
wears it as ONE sprite covering both world slots: `LegLeft` carries the whole
pair, repositioned to the midpoint between the two slots' normal positions,
and `LegRight` is hidden outright (`CharacterView._apply_legs`,
`legs_are_fused()`). The procedural fallback is unaffected — it still uses
two independent leg sprites with the opposite-direction walk-swing that shape
needs.

**Known gap this creates**: the walk cycle's leg-swing (see
`CharacterView._process`) is not applied while legs are fused — no per-leg
swing art exists for a single fused image, so illustrated legs stay static
while walking rather than bobbing. Real walk-cycle art (see "Sheet format"
below) is the natural follow-up; until then this is an honest "doesn't
animate yet," not a broken animation.

## Arms are two independent poses, not a mirrored single arm

`arms.png` holds two poses side by side, divided by an OPAQUE black line
rather than a transparent gap — `SpriteSheetSlicer.detect_frames`'s
column-emptiness scan can't find that boundary, so the `"arms"` `_PARTS`
entry gives exact pixel rects instead of a band (see `idle_rects` in
`_load_frames`). `ArmLeft` gets frame 0, `ArmRight` gets frame 1 — each
measured and scaled independently (`part_scale_for`'s `frame_index`
argument), since the two are independent AI-illustrated crops, not a
mirrored copy of one drawing.

## Head

Unlike body/legs/arms, head art is **not** a neutral sheet — the delivered
`head.png` is a 10×10 grid of 100 fully-painted faces (bald, one baked skin
tone, solid near-black background, no alpha channel), and it is **not**
exposed through `has_part`/`generate_textures` at all — it has its own
surface, `has_head()`/`generate_head_texture(seed_value, skin_tone)`/
`head_cell_index_for(seed_value)`/`head_scale_for`.

- **Which face**: `head_cell_index_for(seed_value)` picks one of the 100
  cells deterministically from the hero's own DNA seed (see
  `HeroAppearance.appearance_for`/`appearance_from_choices`, both of which
  now carry `"seed"` on the returned appearance dict specifically so a face
  choice has something stable to key off). Same seed, same face, always —
  no new character-creator UI for browsing faces individually.
- **Recoloring**: `head.png`'s baked-in skin tone is discarded and repainted
  toward the hero's own DNA-picked `appearance.skin`, by LUMINANCE ONLY —
  the exact trick `ProceduralFlowerSprite._paint_illustrated_head` already
  proved on illustrated blooms (see `flora.md`'s "Recolouring illustrated
  blooms"): read the source as light/shade, discard its hue, repaint the
  target tint at that same brightness. This is deliberately simpler than the
  flower version — there is no accent-hue mask separating eyes from skin, so
  an eye recolors along with the rest of the face rather than keeping its
  own distinct color. Eyes in this art are already fairly dark/low-luminance,
  so they still read as a visibly darker patch of whatever tone the recolor
  lands on; a real eye-color mask (see the flower's `ACCENT_HUE_MIN/MAX`
  approach) is a legitimate follow-up, not attempted here.
- **Background removal**: `head.png` has no alpha channel and a solid,
  near-pure-black background (measured: RGB 0–3, no gradient) — each cropped
  cell is chroma-keyed against black (`HEAD_BACKGROUND_KEY`/
  `_TOLERANCE = 0.06`, generous enough for the measured background noise,
  conservative enough to leave the art's own dark-grey linework alone —
  this project's convention is dark-grey outlines, not literal `(0,0,0)`,
  the same risk `flora.md`'s "shade floor" note already covers for the same
  reason) before it goes through the normal
  `detect_frames`/`normalize_frames` pipeline.
- **Scale**: the head is normalized onto its own `HEAD_CANVAS_SIZE`/
  `HEAD_BASELINE_Y` (24×24), separate from `CANVAS_SIZE`/`BASELINE_Y` (the
  shared 64×96 canvas every body/legs/arms part uses) — a head isn't a
  ground-contact-anchored standing limb, it's anchored where the neck meets
  the torso. `CharacterView._apply_head` scales it via `head_scale_for`, the
  same measure-the-actual-drawn-content approach `part_scale_for` uses for
  the other parts (see "Every part gets its own measured scale" below).

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
`appearance.hair` the same way body/legs/arms are — i.e. a genuine SECOND
illustrated layer composited on top of (or in place of) the recolored head,
not a change to `head.png` itself. A beard overlay per
`HeroAppearance.BEARD_STYLES` (stubble, goatee, full — none needs no
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
one working RESOLUTION every part is normalized onto — mirroring
`IllustratedAnimalSprite`'s "one canvas per creature, regardless of species
size" convention — not a claim that a torso and a leg pair are the same real
size. `part_scale_for(part_name, target_world_height, frame_index)` measures
the ACTUAL opaque-pixel content height of the generated frame (the Y-axis
counterpart to `IllustratedAnimalSprite._reference_width`'s X-axis scan) and
returns the scale that maps it to the part's real world height
(`CharacterView.BODY_SIZE`/`LEG_SIZE`/`ARM_SIZE`). `head_scale_for` is the
same idea for the head's own canvas. `CharacterView._apply_paperdoll_part`/
`_apply_head`/`_apply_legs` apply this per part instead of the flat
`ArtResolution.SPRITE_SCALE` the procedural fallback still uses (that
constant only ever worked because the procedural generator draws AT EXACTLY
its target art size with no padding — illustrated art, normalized onto a
shared padded canvas, essentially never does).

## Sheet format (for any NEW part sheet — hair, walk cycles, etc.)

The delivered `body.png`/`leg.png`/`arms.png` already have real, usable alpha
channels (measured directly, not the magenta-chroma-key convention this doc
previously assumed from the animal pipeline's `sheep.png`) — real
transparency where the AI generator actually produced it, rather than a flat
color to key out. If future art comes back the same way, no `chroma_key`
entry is needed (see `torso`/`legs`/`arms` in `_PARTS`); if it comes back
solid-background instead (as `head.png` did), key it out explicitly the way
`IllustratedCharacterSprite._apply_chroma_key`/`HEAD_BACKGROUND_KEY` do
before handing it to `SpriteSheetSlicer` — don't assume either convention,
measure the actual file (see `docs/progress.md`'s entry on this pass for the
Node.js probing approach used to check).

- **Frame dividers, if a sheet holds several poses**: a real transparent gap
  lets `detect_frames` find the boundary automatically (`"<action>_bands"`).
  An OPAQUE divider (a drawn line, like `arms.png`'s) defeats that scan —
  give exact pixel rects instead (`"<action>_rects"`, see `_load_frames`).
- **One pose per part is enough** to replace the procedural texture. A walk
  cycle (several frames, one row) can follow later and will need
  CharacterView's walk animation switched from its current transform-wiggle
  (rotating/offsetting the same static texture) to real frame-cycling for
  body/arms, and (for legs specifically) real per-leg swing art before the
  fused-pair gap above can close — that wiring doesn't exist yet either, so
  keep starting with idle-only art.
- **Canvas**: no fixed pixel size required from the generator — whatever
  resolution reads clearly. `SpriteSheetSlicer.normalize_frames` crops to the
  actual drawn content and rescales onto `IllustratedCharacterSprite
  .CANVAS_SIZE`/`BASELINE_Y` (body/legs/arms) or `HEAD_CANVAS_SIZE`/
  `HEAD_BASELINE_Y` (head) automatically.
- **Orientation**: draw facing the VIEWER (front-on), matching what
  `torso.png`/`leg.png`/`arms.png`/`head.png` all actually are — not facing
  right, which this doc previously specified before any art existed to check
  against. There is still no per-part facing override in
  `IllustratedCharacterSprite` (unlike some animal sheets, which declare
  `faces_left` per species) — a future sheet drawn in profile would need
  that option added, not just a different source image.

## File locations

The delivered art lives at `assets/sprites/player/{torso,leg,arms,head}.png`
— note this is NOT the `assets/sprites/character/{body,legs,arms}_idle.png`
layout this doc originally proposed before any art existed; `_PARTS`/
`HEAD_PATH` point at the real paths. Follow the same `assets/sprites/player/`
location for any new part (hair, beard, decorations, walk-cycle art).

## How to register a finished body/legs/arms-style part

Add an entry to `IllustratedCharacterSprite._PARTS`, mirroring
`IllustratedAnimalSprite._SHEETS`:

```gdscript
const _PARTS := {
	"body": {
		"path": "res://assets/sprites/player/torso.png",
		"idle_rects": [Rect2i(0, 0, 1254, 1254)],  # measured from the real file, not guessed
	},
}
```

`has_part`/`has_action` (and `_apply_paperdoll_part` in `character_view.gd`)
pick this up automatically — no other code changes needed for a part that
fits the neutral-single-tint shape body/legs/arms already use. A part that
needs its own recolor mechanism (multi-color source art, like a hypothetical
hair sheet with its own baked shading) needs a dedicated surface instead,
the same way head does — see "Head" above for the shape to copy.
