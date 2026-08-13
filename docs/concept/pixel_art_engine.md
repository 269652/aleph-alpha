# Pixel Art Engine

The shared toolkit every `src/rendering/procedural_*.gd` generator draws
with. This doc specifies the techniques; the individual generators specify
*what* they draw, not *how* shading, randomness, and form work.

## Why this exists

The 4x resolution pass (see [art_resolution.md](art_resolution.md)) gave
every sprite 16x the pixels. That exposed a separate problem: the
generators' *drawing technique* was the limiting factor, not the canvas.
Each one independently did `image.set_pixel()` loops with ad-hoc rules, and
they shared almost nothing, so every sprite was:

- **Flat.** Shading meant `Color.darkened()` / `lightened()` -- the same hue
  at two or three brightnesses, which no real surface looks like.
- **Banded.** Volume was faked with hard cutoffs ("if dy < -0.3 use the
  highlight color"), which read as stripes painted across a shape rather
  than light falling on it.
- **Clumpy.** Randomness came from Godot's string `hash()`, which
  correlates badly across near-identical inputs.

Fixing that per-generator would mean re-deriving the same techniques
fifteen-plus times, inconsistently. Raising the shared engine lifts every
generator at once, and makes each generator's own file shorter and about
its subject rather than about shading maths.

## Design pillars

1. **Techniques live once.** A generator says "this is a leaf, this is
   fur, this is a rounded body"; it does not restate how light works.
2. **Real pixel-art technique, not just maths.** The rules below are the
   ones human pixel artists actually use (hue-shifted ramps, bounce light,
   readable silhouettes) -- chosen because they look right, then pinned by
   tests so they can't silently erode.
3. **Deterministic, always.** Same inputs, same pixels, forever: sprites
   are generated at load and must not shimmer between sessions. No
   `RandomNumberGenerator` anywhere.
4. **Pixel art, not rendering.** Every technique here serves a limited
   palette with hard edges. Smooth gradients, soft noise texture, and
   anything that reads as photographic are explicitly out of scope no
   matter how physically correct the maths behind them is -- this is a
   16-bit-styled game, and correct lighting rendered continuously still
   looks wrong in it.
5. **Tested by property, not by pixel.** Tests assert *qualities* -- "the
   lit side is brighter than the shadowed side", "consecutive samples
   scatter", "the ramp spans a wide value range" -- so art can be improved
   without rewriting a snapshot every time.

## Modules

### `pixel_ramp.gd` -- hue-shifted shading ramps

The single biggest quality lever. A `STOPS`-step ramp built from one base
color, where along the ramp:

- **Shadows shift cooler** (toward blue/purple). A shadow is not the surface
  with less light on it; it is the surface lit by the blue sky instead of by
  the sun.
- **Highlights shift warmer** (toward yellow) -- the color of the direct
  light doing the lighting.
- **Saturation peaks in the midtones** and eases off at both ends. Saturated
  shadows look like black paint; saturated highlights look like glare.
- **Near-grey bases are given a hue** (cool shadows, warm highlights) rather
  than staying grey, which is what stops stone and metal reading as
  lifeless.

Callers shade by a 0..1 fraction (`sample`), never by stop index, so their
maths doesn't need to know how many stops exist.

**`sample` SNAPS to a discrete stop and never interpolates between them.**
This is the property that makes output read as 16-bit pixel art rather than
a soft 3D render: real sprite work uses a handful of hard-edged colors per
material with visible banding between them, not a continuous gradient. The
first version of this module returned the continuous value, and the art
came out looking airbrushed -- correct lighting maths, wrong medium.

### `pixel_noise.gd` -- deterministic randomness

An integer avalanche mix (xorshift-multiply) replacing string `hash()`.
Allocation-free (no string built per sample) and well-distributed for the
sequential and grid-shaped inputs pixel art actually uses. Provides
per-pixel scatter (`unit`, `range_value`, `range_index`), smooth value noise
(`smooth`) for organic gradients, and multi-octave `fractal` for texture
with both broad shape and fine grain.

This exists because the string-hash approach bit this project twice: a
seeded index froze to one bucket (every village house came out the same
size), and whole rows of tree leaves came out at the same angle.

### `pixel_form.gd` -- volumetric shading

Treats an ellipse as the silhouette of a spheroid: reconstructs the surface
normal at each point and takes the standard diffuse dot product against a
top-left light (`LIGHT_DIRECTION`, matching the convention the codebase's
art already assumed). Adds:

- an **ambient floor**, so shadow is never a hole;
- a **bounce-light rim** on the shadowed edge -- light reflected off the
  ground -- without which a shaded sphere dissolves into a flat dark blob at
  its far edge instead of reading as round.

Feed the result to `PixelRamp.sample()` and any shape becomes a lit volume.

## Status / mechanisms

- ✅ `pixel_ramp.gd` -- hue-shifted ramps, tested (`test_pixel_ramp.gd`).
- ✅ `pixel_noise.gd` -- integer-mix randomness + smooth/fractal noise,
  tested (`test_pixel_noise.gd`), including regressions for both real
  string-hash clustering failures.
- ✅ `pixel_form.gd` -- spheroid normal/diffuse shading with ambient and
  bounce rim, tested (`test_pixel_form.gd`).
- 🚧 Adoption across generators. The engine only pays off where generators
  actually call it; each one converts as its art-resolution phase lands
  (see [art_resolution.md](art_resolution.md)'s phase list).
- ⬜ `pixel_texture.gd` -- reusable material overlays (fur, bark, cloth
  weave, stone grain, metal sheen) so surface character isn't re-derived
  per generator.
- ⬜ Retiring `pixel_palette.gd`'s flat `shade`/`highlight` pair in favour
  of ramps everywhere. It is still used by generators that haven't
  converted yet.
